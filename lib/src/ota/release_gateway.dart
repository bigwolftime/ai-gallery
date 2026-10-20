import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:ai_gallery_native/ai_gallery_native.dart';
import 'app_release.dart';

enum InstallAction { opened, permissionRequired }

abstract interface class ReleaseGateway {
  Future<InstalledApp> installedApp();
  Future<AppRelease?> check(InstalledApp installed);
  Future<Directory> downloadDirectory();
  Future<void> validatePackage(File file, AppRelease release);
  Future<InstallAction> installPackage(File file, AppRelease release);
  Future<void> openRelease(AppRelease release);
}

class NativeReleaseGateway implements ReleaseGateway {
  NativeReleaseGateway(
      {AIGalleryNative? native,
      Uri? manifestUrl,
      HttpClient Function()? clientFactory})
      : _native = native ?? AIGalleryNative(),
        _url = manifestUrl ??
            Uri.parse(const String.fromEnvironment('APP_RELEASE_MANIFEST_URL',
                defaultValue:
                    'https://img.zonheng.net/apps/ai-gallery/releases.json')),
        _clientFactory = clientFactory ?? HttpClient.new;
  final AIGalleryNative _native;
  final Uri _url;
  final HttpClient Function() _clientFactory;
  static const _timeout = Duration(seconds: 12);
  static const _maxManifestBytes = 65536;

  @override
  Future<InstalledApp> installedApp() async =>
      InstalledApp.fromMap(await _native.appUpdateInfo());
  @override
  Future<AppRelease?> check(InstalledApp installed) async {
    if (_url.scheme != 'https' || _url.host.isEmpty) {
      throw const FormatException('版本清单必须使用 HTTPS。');
    }
    final client = _clientFactory()
      ..connectionTimeout = _timeout
      ..autoUncompress = false;
    try {
      // This domain also hosts long-lived images. A unique cache key prevents a
      // previously cached manifest from hiding newly published base versions.
      final url = _url.replace(queryParameters: {
        ..._url.queryParameters,
        'check': DateTime.now().microsecondsSinceEpoch.toString()
      });
      return await (() async {
        final request = await client.getUrl(url);
        request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
        request.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
        final response = await request.close();
        if (response.statusCode != 200) {
          throw HttpException('整包版本检查失败（HTTP ${response.statusCode}）。');
        }
        final bytes = <int>[];
        await for (final chunk in response) {
          if (bytes.length + chunk.length > _maxManifestBytes) {
            client.close(force: true);
            throw const FormatException('应用版本清单过大。');
          }
          bytes.addAll(chunk);
        }
        final latest = AppReleaseManifest.decode(utf8.decode(bytes),
                expectedAppId: installed.appId)
            .latestFor(installed);
        if (latest == null) throw const FormatException('版本清单暂未包含当前安装渠道。');
        return latest.buildNumber > installed.buildNumber ? latest : null;
      })()
          .timeout(_timeout);
    } finally {
      client.close(force: true);
    }
  }

  @override
  Future<Directory> downloadDirectory() async =>
      Directory(await _native.appUpdateDirectory());
  @override
  Future<void> validatePackage(File file, AppRelease release) => _native
      .validateAppPackage(file.path, release.version, release.buildNumber);
  @override
  Future<InstallAction> installPackage(File file, AppRelease release) async =>
      await _native.installAppPackage(
                  file.path, release.version, release.buildNumber) ==
              'permissionRequired'
          ? InstallAction.permissionRequired
          : InstallAction.opened;
  @override
  Future<void> openRelease(AppRelease release) =>
      _native.openUpdateUrl(release.url.toString());
}
