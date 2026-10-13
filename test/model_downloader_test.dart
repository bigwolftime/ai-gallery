import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_gallery/src/models/model_downloader.dart';
import 'package:ai_gallery/src/models/model_manifest.dart';

void main() {
  late Directory directory;
  late HttpServer server;
  final bytes = List<int>.generate(65536, (i) => i % 251);
  late ModelManifest model;
  late void Function(HttpRequest) handler;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('ai-gallery-download-');
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) => handler(request));
    model = ModelManifest(
        name: 'test',
        modelVersion: 'test-v1',
        url: Uri.parse('http://127.0.0.1:${server.port}/model'),
        sha256: sha256.convert(bytes).toString(),
        size: bytes.length);
    handler = (request) {
      request.response.add(bytes);
      request.response.close();
    };
  });
  tearDown(() async {
    await server.close(force: true);
    await directory.delete(recursive: true);
  });

  test(
      'downloads, verifies and atomically activates without fetching again offline',
      () async {
    var requests = 0;
    handler = (request) {
      requests++;
      request.response.add(bytes);
      request.response.close();
    };
    final stages = <String>[];
    final downloader =
        ModelDownloader(onProgress: (progress) => stages.add(progress.stage));
    final file = await downloader.ensure(directory, model);
    expect(await file.readAsBytes(), bytes);
    expect(await downloader.isAvailable(directory, model), true);
    await downloader.ensure(directory, model);
    expect(requests, 1);
    expect(stages, containsAllInOrder(['downloading', 'verifying', 'ready']));
  });
  test('resumes persisted prefix with correct byte range', () async {
    final partial = File('${directory.path}/${model.sha256}.partial');
    await partial.writeAsBytes(bytes.take(4096).toList());
    handler = (request) {
      expect(request.headers.value(HttpHeaders.rangeHeader), 'bytes=4096-');
      request.response.statusCode = 206;
      request.response.headers.set(HttpHeaders.contentRangeHeader,
          'bytes 4096-${bytes.length - 1}/${bytes.length}');
      request.response.add(bytes.skip(4096).toList());
      request.response.close();
    };
    final file = await ModelDownloader().ensure(directory, model);
    expect(await file.readAsBytes(), bytes);
    expect(await partial.exists(), false);
  });
  test('server ignoring Range restarts rather than appending duplicate bytes',
      () async {
    await File('${directory.path}/${model.sha256}.partial')
        .writeAsBytes(bytes.take(8192).toList());
    final file = await ModelDownloader().ensure(directory, model);
    expect(await file.length(), bytes.length);
    expect(await ModelDownloader.hashFile(file.path), model.sha256);
  });
  test('wrong range never modifies the persisted prefix', () async {
    final partial = File('${directory.path}/${model.sha256}.partial');
    await partial.writeAsBytes(bytes.take(4096).toList());
    handler = (request) {
      request.response.statusCode = 206;
      request.response.headers.set(HttpHeaders.contentRangeHeader,
          'bytes 0-${bytes.length - 1}/${bytes.length}');
      request.response.add(bytes);
      request.response.close();
    };
    await expectLater(ModelDownloader().ensure(directory, model),
        throwsA(isA<HttpException>()));
    expect(await partial.length(), 4096);
  });
  test('bad checksum is never activated and removes the unusable partial',
      () async {
    handler = (request) {
      request.response.add(List.filled(bytes.length, 0));
      request.response.close();
    };
    final downloader = ModelDownloader();
    await expectLater(
        downloader.ensure(directory, model), throwsA(isA<FormatException>()));
    expect(await downloader.isAvailable(directory, model), false);
    expect(await File('${directory.path}/${model.sha256}.partial').exists(),
        false);
  });
  test('incomplete response preserves bytes for a later retry', () async {
    handler = (request) {
      request.response.add(bytes.take(4096).toList());
      request.response.close();
    };
    await expectLater(ModelDownloader().ensure(directory, model),
        throwsA(isA<HttpException>()));
    expect(
        await File('${directory.path}/${model.sha256}.partial').length(), 4096);
  });
  test('pause preserves progress and the next attempt resumes', () async {
    var pause = true;
    late ModelDownloader downloader;
    downloader = ModelDownloader(onProgress: (progress) {
      if (pause && progress.stage == 'downloading' && progress.received > 0) {
        pause = false;
        downloader.cancel();
      }
    });
    handler = (request) {
      final range = request.headers.value(HttpHeaders.rangeHeader);
      if (range != null) {
        final offset = int.parse(range.substring(6, range.length - 1));
        request.response.statusCode = 206;
        request.response.headers.set(HttpHeaders.contentRangeHeader,
            'bytes $offset-${bytes.length - 1}/${bytes.length}');
        request.response.add(bytes.skip(offset).toList());
        request.response.close();
      } else {
        unawaited(() async {
          try {
            request.response.add(bytes.take(4096).toList());
            await request.response.flush();
            await Future<void>.delayed(const Duration(milliseconds: 100));
            request.response.add(bytes.skip(4096).toList());
            await request.response.close();
          } catch (_) {
            /* The paused client deliberately closes the connection. */
          }
        }());
      }
    };
    await expectLater(downloader.ensure(directory, model),
        throwsA(isA<ModelDownloadCancelled>()));
    final partial = File('${directory.path}/${model.sha256}.partial');
    expect(await partial.length(), greaterThan(0));
    final file = await downloader.ensure(directory, model);
    expect(await file.readAsBytes(), bytes);
  });
  test('adopts a complete unverified existing file only after hashing',
      () async {
    final downloader = ModelDownloader();
    await downloader.modelFile(directory, model).writeAsBytes(bytes);
    handler =
        (_) => fail('Existing verified bytes must not be downloaded again');
    await downloader.ensure(directory, model);
    expect(await downloader.isAvailable(directory, model), true);
  });
  test(
      'manifest rejects unsupported settings and preserves legacy index identity',
      () {
    Map<String, Object> valid() => {
          'schemaVersion': 1,
          'name': 'embeddinggemma-2',
          'modelVersion': 'v1',
          'url': 'https://example.com/model.litertlm',
          'sha256': ModelManifest.legacyHash,
          'size': 484622336,
          'dimensions': 256,
          'visionTokens': 70
        };
    expect(ModelManifest.decode(jsonEncode(valid())).indexVersion,
        'embeddinggemma-2-256-v1');
    expect(
        () => ModelManifest.decode(
            jsonEncode(valid()..['url'] = 'http://example.com/model')),
        throwsFormatException);
    expect(
        () => ModelManifest.decode(jsonEncode(valid()..['dimensions'] = 512)),
        throwsFormatException);
    final other = valid()..['sha256'] = model.sha256;
    expect(ModelManifest.decode(jsonEncode(other)).indexVersion,
        contains(model.sha256));
  });
}
