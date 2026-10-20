import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:ai_gallery/src/ota/app_release.dart';
import 'package:ai_gallery/src/ota/ota_controller.dart';
import 'package:ai_gallery/src/ota/release_gateway.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'ota_test.dart' show FakeOtaGateway, FakeReleaseGateway;

const installed = InstalledApp(
    platform: 'android', channel: 'direct', version: '0.4.3', buildNumber: 7);
final content = List<int>.generate(65536, (i) => i % 251);
Map<String, Object> apkMap({int build = 8, String channel = 'direct'}) => {
      'platform': 'android',
      'channel': channel,
      'kind': channel == 'direct' ? 'apk' : 'store',
      'version': '0.4.4',
      'buildNumber': build,
      'url': 'https://example.com/app.apk',
      'sha256': sha256.convert(content).toString(),
      'size': content.length,
      'notes': '修复问题，保留模型和索引。',
    };
String manifest(List<Map<String, Object>> entries) => jsonEncode({
      'schemaVersion': 1,
      'appId': 'com.aigallery.app',
      'releases': entries,
    });

void main() {
  test(
      'public identity and old test identity cannot select each other manifests',
      () async {
    final publicMap = jsonDecode(manifest([apkMap()])) as Map<String, dynamic>;
    publicMap['appId'] = 'net.zonheng.aigallery';
    final source = jsonEncode(publicMap);
    expect(() => AppReleaseManifest.decode(source), throwsFormatException);
    final metadata = AppReleaseManifest.decode(source,
        expectedAppId: 'net.zonheng.aigallery');
    expect(metadata.latestFor(installed), isNull);
    const publicInstalled = InstalledApp(
        platform: 'android',
        channel: 'direct',
        version: '0.4.4',
        buildNumber: 7,
        appId: 'net.zonheng.aigallery');
    expect(metadata.latestFor(publicInstalled)!.buildNumber, 8);
    expect(
        () => AppReleaseManifest.decode(manifest([apkMap()]),
            expectedAppId: 'net.zonheng.aigallery'),
        throwsFormatException);
    final client = ManifestHttpClient(source);
    final gateway = NativeReleaseGateway(
        manifestUrl: Uri.parse('https://example.com/public/releases.json'),
        clientFactory: () => client);
    final release = await gateway.check(publicInstalled);
    expect(release!.buildNumber, 8);
  });

  test('selects by platform/channel and numeric build, never version string',
      () {
    final source = manifest([
      apkMap(build: 6),
      apkMap(build: 8),
      apkMap(build: 10)..['version'] = '0.4.4',
      apkMap(build: 99, channel: 'play'),
      {
        'platform': 'ios',
        'channel': 'sideload',
        'kind': 'ipa',
        'version': '2.0',
        'buildNumber': 100,
        'url': 'https://example.com/app.ipa'
      },
    ]);
    final metadata = AppReleaseManifest.decode(source);
    expect(metadata.newerThan(installed)!.buildNumber, 10);
    expect(
        metadata.newerThan(const InstalledApp(
            platform: 'android',
            channel: 'direct',
            version: '0.4.4',
            buildNumber: 10)),
        isNull);
    expect(
        metadata.latestFor(const InstalledApp(
            platform: 'ios',
            channel: 'appstore',
            version: '1',
            buildNumber: 1)),
        isNull);
    expect(
        metadata
            .newerThan(const InstalledApp(
                platform: 'android',
                channel: 'play',
                version: '1',
                buildNumber: 1))!
            .isApk,
        false);
  });

  test(
      'rejects wrong app, schema, unsafe URL, incomplete APK identity and duplicates',
      () {
    for (final invalid in [
      apkMap()..['url'] = 'http://example.com/app.apk',
      apkMap()..remove('sha256'),
      apkMap()..['sha256'] = 'bad',
      apkMap()..['size'] = 0,
      apkMap()..['buildNumber'] = 0,
      apkMap()..['platform'] = 'ios',
      apkMap(channel: 'appstore'),
    ]) {
      expect(() => AppReleaseManifest.decode(manifest([invalid])),
          throwsFormatException);
    }
    final wrongApp = jsonDecode(manifest([apkMap()])) as Map<String, dynamic>;
    wrongApp['appId'] = 'another.app';
    expect(() => AppReleaseManifest.decode(jsonEncode(wrongApp)),
        throwsFormatException);
    wrongApp['appId'] = 'com.aigallery.app';
    wrongApp['schemaVersion'] = 2;
    expect(() => AppReleaseManifest.decode(jsonEncode(wrongApp)),
        throwsFormatException);
    expect(() => AppReleaseManifest.decode(manifest([apkMap(), apkMap()])),
        throwsFormatException);
  });

  test('base upgrade takes priority and works even without Shorebird',
      () async {
    final patches = FakeOtaGateway()..available = false;
    final releases = FakeReleaseGateway()
      ..release = AppRelease.fromMap(apkMap());
    final controller = OtaController(gateway: patches, releases: releases);
    addTearDown(controller.dispose);
    await controller.check();
    expect(controller.phase, OtaPhase.packageAvailable);
    expect(patches.checks, 0);
    expect(controller.installed!.buildNumber, 7);
    // A stale patch action cannot replace the pending full-package upgrade.
    await controller.download();
    expect(controller.phase, OtaPhase.packageAvailable);
  });

  test(
      'manifest failure still checks patches but never claims full version is latest',
      () async {
    final patches = FakeOtaGateway();
    final releases = FakeReleaseGateway()
      ..failure = const SocketException('offline');
    final controller = OtaController(gateway: patches, releases: releases);
    addTearDown(controller.dispose);
    await controller.check();
    expect(patches.checks, 1);
    expect(controller.packageCheckConfirmed, false);
    expect(controller.title, '当前基础包暂无新补丁');
    expect(controller.packageNotice, contains('暂未确认'));
  });

  test(
      'APK downloads into its own directory and requires native validation before install',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('gallery-apk-test-');
    addTearDown(() => directory.delete(recursive: true));
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) {
      request.response.add(content);
      unawaited(request.response.close());
    });
    final releases = FakeReleaseGateway()
      ..directory = directory
      ..release = AppRelease(
          platform: 'android',
          channel: 'direct',
          version: '0.4.4',
          buildNumber: 8,
          kind: 'apk',
          url: Uri.parse('http://127.0.0.1:${server.port}/app.apk'),
          sha256: sha256.convert(content).toString(),
          size: content.length);
    final controller =
        OtaController(gateway: FakeOtaGateway(), releases: releases);
    addTearDown(controller.dispose);
    await controller.check();
    await controller.downloadPackage();
    expect(controller.phase, OtaPhase.packageReady);
    expect(controller.packageFile!.path, endsWith('.apk'));
    expect(await controller.packageFile!.readAsBytes(), content);
    expect(releases.validations, 1);
    expect(releases.installs, 0);
    releases.action = InstallAction.permissionRequired;
    await controller.installPackage();
    expect(controller.installPermissionRequired, true);
    expect(controller.phase, OtaPhase.packageReady);
    expect(controller.packageNotice, contains('允许安装此来源'));
    releases.action = InstallAction.opened;
    await controller.installPackage();
    expect(releases.installs, 2);
    expect(
        controller.phase,
        OtaPhase
            .packageReady); // Launching an installer is not installation success.
    expect(controller.packageNotice, contains('系统安装界面'));
  });

  test(
      'native package rejection deletes the cached package and never enables install',
      () async {
    final directory = await Directory.systemTemp.createTemp('gallery-bad-apk-');
    addTearDown(() => directory.delete(recursive: true));
    final releases = FakeReleaseGateway()
      ..directory = directory
      ..release = AppRelease.fromMap(apkMap())
      ..validationFailure =
          PlatformException(code: 'INVALID_APK', message: '安装包签名不一致。');
    // A verified byte stream is still insufficient: native package identity must match.
    final hash = sha256.convert(content).toString();
    await File('${directory.path}/$hash.apk').writeAsBytes(content);
    await File('${directory.path}/$hash.verified').writeAsString(hash);
    final controller =
        OtaController(gateway: FakeOtaGateway(), releases: releases);
    addTearDown(controller.dispose);
    await controller.check();
    await controller.downloadPackage();
    expect(controller.phase, OtaPhase.packageAvailable);
    expect(controller.error, '安装包签名不一致。');
    expect(await File('${directory.path}/$hash.apk').exists(), false);
    expect(await File('${directory.path}/$hash.verified').exists(), false);
    await controller.installPackage();
    expect(releases.installs, 0);
  });

  test('APK pause preserves progress and resumes without claiming installation',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('gallery-apk-resume-');
    addTearDown(() => directory.delete(recursive: true));
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) {
      unawaited(() async {
        try {
          final range = request.headers.value(HttpHeaders.rangeHeader);
          if (range == null) {
            request.response.add(content.sublist(0, 4096));
            await request.response.flush();
            await Future<void>.delayed(const Duration(milliseconds: 100));
            request.response.add(content.sublist(4096));
          } else {
            expect(range, 'bytes=4096-');
            request.response.statusCode = 206;
            request.response.headers.set(HttpHeaders.contentRangeHeader,
                'bytes 4096-${content.length - 1}/${content.length}');
            request.response.add(content.sublist(4096));
          }
          await request.response.close();
        } catch (_) {/* Deliberately interrupted transfer. */}
      }());
    });
    final releases = FakeReleaseGateway()
      ..directory = directory
      ..release = AppRelease(
          platform: 'android',
          channel: 'direct',
          version: '0.4.4',
          buildNumber: 8,
          kind: 'apk',
          url: Uri.parse('http://127.0.0.1:${server.port}/app.apk'),
          sha256: sha256.convert(content).toString(),
          size: content.length);
    final controller =
        OtaController(gateway: FakeOtaGateway(), releases: releases);
    addTearDown(controller.dispose);
    var pause = true;
    controller.addListener(() {
      if (pause &&
          controller.phase == OtaPhase.packageDownloading &&
          (controller.packageProgress?.received ?? 0) > 0) {
        pause = false;
        controller.pausePackageDownload();
      }
    });
    await controller.check();
    await controller.downloadPackage();
    expect(controller.phase, OtaPhase.packageAvailable);
    expect(controller.packageNotice, contains('暂停'));
    expect(releases.validations, 0);
    expect(releases.installs, 0);
    await controller.downloadPackage();
    expect(controller.phase, OtaPhase.packageReady);
    expect(await controller.packageFile!.readAsBytes(), content);
  });

  test(
      'sideload iOS and store releases open their channel URL without APK download',
      () async {
    for (final kind in ['ipa', 'store']) {
      final releases = FakeReleaseGateway()
        ..current = const InstalledApp(
            platform: 'ios',
            channel: 'sideload',
            version: '0.4.1',
            buildNumber: 5)
        ..release = AppRelease(
            platform: 'ios',
            channel: kind == 'ipa' ? 'sideload' : 'appstore',
            version: '0.4.4',
            buildNumber: 8,
            kind: kind,
            url: Uri.parse('https://example.com/update'));
      final controller =
          OtaController(gateway: FakeOtaGateway(), releases: releases);
      await controller.check();
      await controller.downloadPackage();
      await controller.openFullRelease();
      expect(releases.opens, 1);
      expect(releases.installs, 0);
      expect(controller.phase, OtaPhase.packageAvailable);
      controller.dispose();
    }
  });

  test('metadata fetch bypasses stale CDN keys and always closes the client',
      () async {
    final client = ManifestHttpClient(manifest([apkMap()]));
    final gateway = NativeReleaseGateway(
        manifestUrl: Uri.parse('https://example.com/releases.json?existing=1'),
        clientFactory: () => client);
    final release = await gateway.check(installed);
    expect(release!.buildNumber, 8);
    expect(client.requested!.queryParameters['existing'], '1');
    expect(client.requested!.queryParameters['check'], isNotEmpty);
    expect(client.headers.values['cache-control'], 'no-cache');
    expect(client.closed, true);
    final missing = ManifestHttpClient(manifest([]));
    final missingGateway = NativeReleaseGateway(
        manifestUrl: Uri.parse('https://example.com/releases.json'),
        clientFactory: () => missing);
    await expectLater(missingGateway.check(installed), throwsFormatException);
    expect(missing.closed, true);
    final failed = ManifestHttpClient('error', status: 503);
    await expectLater(
        NativeReleaseGateway(
            manifestUrl: Uri.parse('https://example.com/releases.json'),
            clientFactory: () => failed).check(installed),
        throwsA(isA<HttpException>()));
    final oversized = ManifestHttpClient('x' * 65537);
    await expectLater(
        NativeReleaseGateway(
            manifestUrl: Uri.parse('https://example.com/releases.json'),
            clientFactory: () => oversized).check(installed),
        throwsFormatException);
    expect(oversized.closed, true);
  });
}

/// Minimal transport fixture: exercise the production metadata parser and limit
/// handling without relying on an external release server in unit tests.
class ManifestHttpClient implements HttpClient {
  ManifestHttpClient(this.body, {this.status = 200});
  final String body;
  final int status;
  final headers = RecordingHeaders();
  bool closed = false;
  Uri? requested;
  @override
  set connectionTimeout(Duration? value) {}
  @override
  set autoUncompress(bool value) {}
  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    requested = url;
    return ManifestRequest(this);
  }

  @override
  void close({bool force = false}) {
    closed = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class RecordingHeaders implements HttpHeaders {
  final values = <String, Object>{};
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    values[name] = value;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class ManifestRequest implements HttpClientRequest {
  ManifestRequest(this.client);
  final ManifestHttpClient client;
  @override
  HttpHeaders get headers => client.headers;
  @override
  Future<HttpClientResponse> close() async => ManifestResponse(client);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class ManifestResponse extends Stream<List<int>> implements HttpClientResponse {
  ManifestResponse(this.client);
  final ManifestHttpClient client;
  @override
  int get statusCode => client.status;
  @override
  StreamSubscription<List<int>> listen(void Function(List<int>)? onData,
          {Function? onError, void Function()? onDone, bool? cancelOnError}) =>
      Stream.value(utf8.encode(client.body)).listen(onData,
          onError: onError, onDone: onDone, cancelOnError: cancelOnError);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
