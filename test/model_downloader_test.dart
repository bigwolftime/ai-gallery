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

  ModelManifest withMirrors({List<int>? content}) => ModelManifest(
      name: model.name,
      modelVersion: model.modelVersion,
      url: model.url,
      mirrors: [model.url.replace(path: '/mirror')],
      sha256:
          content == null ? model.sha256 : sha256.convert(content).toString(),
      size: content?.length ?? model.size);

  bool isProbe(HttpRequest request) {
    final range = request.headers.value(HttpHeaders.rangeHeader);
    return range != null && !range.endsWith('-');
  }

  void respond(HttpRequest request, List<int> content, {int? truncateAt}) {
    final range = request.headers.value(HttpHeaders.rangeHeader);
    var start = 0;
    var end = content.length - 1;
    if (range != null) {
      final match = RegExp(r'^bytes=(\d+)-(\d*)$').firstMatch(range)!;
      start = int.parse(match[1]!);
      if (match[2]!.isNotEmpty) end = int.parse(match[2]!);
      request.response.statusCode = 206;
      request.response.headers.set(HttpHeaders.contentRangeHeader,
          'bytes $start-$end/${content.length}');
    }
    final payload = content.sublist(start, end + 1);
    request.response
        .add(truncateAt == null ? payload : payload.take(truncateAt).toList());
    unawaited(request.response.close());
  }

  // Real HTTP endpoints make selection, cancellation and cross-origin resume
  // observable, rather than reproducing the downloader's sorting algorithm.
  test('probes concurrently and downloads the faster actual source', () async {
    final probesStarted = Completer<void>();
    var probes = 0;
    final downloads = <String>[];
    handler = (request) {
      unawaited(() async {
        if (isProbe(request)) {
          if (++probes == 2) probesStarted.complete();
          await probesStarted.future;
          if (request.uri.path == '/model') {
            await Future<void>.delayed(const Duration(milliseconds: 120));
          }
        } else {
          downloads.add(request.uri.path);
        }
        respond(request, bytes);
      }());
    };
    final stages = <String>[];
    final file = await ModelDownloader(onProgress: (p) => stages.add(p.stage))
        .ensure(directory, withMirrors());
    expect(probes, 2);
    expect(downloads, ['/mirror']);
    expect(stages,
        containsAllInOrder(['probing', 'downloading', 'verifying', 'ready']));
    expect(await file.readAsBytes(), bytes);
  });

  test('failed winning download falls back and resumes the written prefix',
      () async {
    await File('${directory.path}/${model.sha256}.partial')
        .writeAsBytes(bytes.sublist(0, 4096));
    final downloads = <String>[];
    handler = (request) {
      unawaited(() async {
        if (isProbe(request)) {
          if (request.uri.path == '/model') {
            await Future<void>.delayed(const Duration(milliseconds: 80));
          }
          respond(request, bytes);
        } else if (request.uri.path == '/mirror') {
          downloads.add(request.uri.path);
          respond(request, bytes, truncateAt: 4096);
        } else {
          downloads.add(request.uri.path);
          expect(request.headers.value(HttpHeaders.rangeHeader), 'bytes=8192-');
          respond(request, bytes);
        }
      }());
    };
    final file = await ModelDownloader().ensure(directory, withMirrors());
    expect(downloads, ['/mirror', '/model']);
    expect(await file.readAsBytes(), bytes);
  });

  test('bad mirror checksum is discarded before fallback activation', () async {
    handler = (request) {
      unawaited(() async {
        if (isProbe(request) && request.uri.path == '/model') {
          await Future<void>.delayed(const Duration(milliseconds: 80));
        }
        respond(
            request,
            request.uri.path == '/mirror'
                ? List.filled(bytes.length, 0)
                : bytes);
      }());
    };
    final file = await ModelDownloader().ensure(directory, withMirrors());
    expect(await file.readAsBytes(), bytes);
  });

  test('corrupt resumed prefix gets one clean retry on the healthy source',
      () async {
    await File('${directory.path}/${model.sha256}.partial')
        .writeAsBytes(List.filled(4096, 0));
    final ranges = <String?>[];
    handler = (request) {
      ranges.add(request.headers.value(HttpHeaders.rangeHeader));
      respond(request, bytes);
    };
    final file = await ModelDownloader().ensure(directory, model);
    expect(ranges, ['bytes=4096-', null]);
    expect(await file.readAsBytes(), bytes);
  });

  test('unresponsive probe is bounded and the available source still downloads',
      () async {
    handler = (request) {
      if (isProbe(request) && request.uri.path == '/mirror') return;
      respond(request, bytes);
    };
    final file =
        await ModelDownloader(probeTimeout: const Duration(milliseconds: 250))
            .ensure(directory, withMirrors())
            .timeout(const Duration(seconds: 3));
    expect(await file.readAsBytes(), bytes);
  });

  test('failed probes do not prevent a successful full download', () async {
    handler = (request) {
      if (isProbe(request)) {
        request.response.statusCode = 503;
        unawaited(request.response.close());
      } else {
        respond(request, bytes);
      }
    };
    final file = await ModelDownloader().ensure(directory, withMirrors());
    expect(await file.readAsBytes(), bytes);
  });

  test('pause closes every probe without starting the full transfer', () async {
    final started = Completer<void>();
    handler = (request) {
      expect(isProbe(request), true);
      if (!started.isCompleted) started.complete();
    };
    final downloader = ModelDownloader();
    final future = downloader.ensure(directory, withMirrors());
    await started.future;
    downloader.cancel();
    await expectLater(future.timeout(const Duration(seconds: 2)),
        throwsA(isA<ModelDownloadCancelled>()));
    expect(await downloader.isAvailable(directory, model), false);
  });

  test('ignoring Range during a probe never consumes the entire model',
      () async {
    final content = List<int>.generate(2 * 1024 * 1024, (i) => i % 251);
    final rawServer = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final sockets = <Socket>[];
    addTearDown(() async {
      for (final socket in sockets) {
        socket.destroy();
      }
      await rawServer.close();
    });
    final stopped = Completer<void>();
    var probeSent = 0;
    // HttpResponse intentionally ignores socket-write errors. A raw socket lets
    // this test observe the peer closing, rather than count discarded writes.
    rawServer.listen((socket) {
      sockets.add(socket);
      var closed = false;
      var started = false;
      var headers = '';
      socket.listen(
          (chunk) {
            headers += utf8.decode(chunk);
            if (started || !headers.contains('\r\n\r\n')) return;
            started = true;
            unawaited(() async {
              try {
                socket.write(
                    'HTTP/1.1 200 OK\r\nContent-Length: ${content.length}\r\n\r\n');
                await socket.flush();
                for (var start = 0;
                    start < content.length && !closed;
                    start += 65536) {
                  socket.add(content.sublist(start, start + 65536));
                  await socket.flush();
                  probeSent += 65536;
                  await Future<void>.delayed(const Duration(milliseconds: 5));
                }
              } catch (_) {
                /* The sampled connection is deliberately terminated. */
              } finally {
                socket.destroy();
                stopped.complete();
              }
            }());
          },
          onDone: () => closed = true,
          onError: (_) {
            closed = true;
            socket.destroy();
          });
    });
    handler = (request) => respond(request, content);
    final largeModel = ModelManifest(
        name: model.name,
        modelVersion: model.modelVersion,
        url: Uri.parse('http://127.0.0.1:${rawServer.port}/model'),
        mirrors: [model.url],
        sha256: sha256.convert(content).toString(),
        size: content.length);
    final file = await ModelDownloader().ensure(directory, largeModel);
    await stopped.future;
    expect(probeSent, lessThan(content.length));
    expect(await file.length(), content.length);
  });

  test('legacy Hugging Face manifest includes the verified Qiniu mirror', () {
    final data =
        jsonDecode(File('assets/models/model-manifest.json').readAsStringSync())
            as Map<String, dynamic>;
    final configured = ModelManifest.decode(jsonEncode(data));
    expect(configured.downloadUrls.map((u) => u.host),
        ['huggingface.co', 'img.zonheng.net']);
    expect(configured.indexVersion, 'embeddinggemma-2-256-v1');
    data['mirrors'] = [
      ModelManifest.qiniuMirrorUrl,
      ModelManifest.qiniuMirrorUrl
    ];
    expect(ModelManifest.decode(jsonEncode(data)).downloadUrls.length, 2);
    data['mirrors'] = ['http://example.com/model'];
    expect(() => ModelManifest.decode(jsonEncode(data)), throwsFormatException);
    data.remove('mirrors');
    data['sha256'] = model.sha256;
    expect(ModelManifest.decode(jsonEncode(data)).downloadUrls.length, 1);
  });
}
