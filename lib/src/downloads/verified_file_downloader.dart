import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'download_artifact.dart';

class VerifiedFileDownloader {
  VerifiedFileDownloader(
      {this.onProgress,
      HttpClient Function()? clientFactory,
      this.probeTimeout = const Duration(seconds: 5)})
      : _clientFactory = clientFactory ?? HttpClient.new;
  final void Function(FileDownloadProgress)? onProgress;
  final HttpClient Function() _clientFactory;
  final Duration probeTimeout;
  static const probeBytes = 256 * 1024;
  static const _connectionTimeout = Duration(seconds: 25);
  static const _requestTimeout = Duration(seconds: 30);
  static const _idleTimeout = Duration(seconds: 40);
  static const _progressInterval = Duration(milliseconds: 150);
  final _clients = <HttpClient>{};
  bool _cancelled = false;
  bool _running = false;

  File fileFor(Directory directory, DownloadArtifact model) =>
      File('${directory.path}/${model.sha256}${model.extension}');
  File _marker(Directory directory, DownloadArtifact model) =>
      File('${directory.path}/${model.sha256}.verified');

  Future<bool> isAvailable(Directory directory, DownloadArtifact model) async {
    final file = fileFor(directory, model);
    final marker = _marker(directory, model);
    return await file.exists() &&
        await file.length() == model.size &&
        await marker.exists() &&
        (await marker.readAsString()).trim() == model.sha256;
  }

  void cancel() {
    _cancelled = true;
    for (final client in _clients.toList()) {
      client.close(force: true);
    }
  }

  void _checkCancelled() {
    if (_cancelled) throw FileDownloadCancelled();
  }

  void _progress(String stage, int received, int total) =>
      onProgress?.call(FileDownloadProgress(stage, received, total));

  HttpClient _openClient(Duration timeout) {
    _checkCancelled();
    final client = _clientFactory()
      ..connectionTimeout = timeout
      ..autoUncompress = false;
    _clients.add(client);
    return client;
  }

  void _closeClient(HttpClient client) {
    client.close(force: true);
    _clients.remove(client);
  }

  /// Measure equal real transfers, including DNS/TLS/redirect latency. Always
  /// terminate at the sample limit, even if a source ignores the Range header.
  Future<int?> _probe(Uri uri, DownloadArtifact model) async {
    final client = _openClient(probeTimeout);
    final timer = Stopwatch()..start();
    final sampleSize = min(probeBytes, model.size);
    try {
      return await (() async {
        final request = await client.getUrl(uri);
        request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
        request.headers
            .set(HttpHeaders.rangeHeader, 'bytes=0-${sampleSize - 1}');
        final response = await request.close();
        if (response.statusCode == HttpStatus.partialContent) {
          if (_range(response, model, 0).$2 != sampleSize - 1) return null;
        } else if (response.statusCode != HttpStatus.ok ||
            (response.contentLength >= 0 &&
                response.contentLength != model.size)) {
          return null;
        }
        var received = 0;
        await for (final chunk in response) {
          _checkCancelled();
          received += min(chunk.length, sampleSize - received);
          if (received == sampleSize) {
            // Cancelling HttpClientResponse alone may drain its body for reuse.
            // Tear down the socket before leaving the loop to bound probe traffic.
            final elapsed = timer.elapsedMicroseconds;
            _closeClient(client);
            return elapsed;
          }
        }
        return received == sampleSize ? timer.elapsedMicroseconds : null;
      })()
          .timeout(probeTimeout);
    } on Exception {
      return null;
    } finally {
      _closeClient(client);
    }
  }

  Future<List<Uri>> _rankSources(DownloadArtifact model, int offset) async {
    final urls = model.downloadUrls;
    if (urls.length < 2) return urls;
    _progress('probing', offset, model.size);
    _checkCancelled();
    final samples = await Future.wait(
        urls.map((uri) async => (uri: uri, elapsed: await _probe(uri, model))));
    _checkCancelled();
    final reachable = samples.where((sample) => sample.elapsed != null).toList()
      ..sort((a, b) => a.elapsed!.compareTo(b.elapsed!));
    // A short probe timeout is not conclusive. Keep those sources as last-resort
    // fallbacks with the longer download request timeout.
    return [
      ...reachable.map((sample) => sample.uri),
      ...samples
          .where((sample) => sample.elapsed == null)
          .map((sample) => sample.uri)
    ];
  }

  (int, int) _range(
      HttpClientResponse response, DownloadArtifact model, int offset) {
    final value = response.headers.value(HttpHeaders.contentRangeHeader) ?? '';
    final match = RegExp(r'^bytes (\d+)-(\d+)/(\d+)$').firstMatch(value);
    if (match == null ||
        int.parse(match[1]!) != offset ||
        int.parse(match[3]!) != model.size ||
        int.parse(match[2]!) < offset ||
        int.parse(match[2]!) >= model.size) {
      throw const HttpException('下载服务返回了不正确的续传范围，请重试。');
    }
    return (int.parse(match[1]!), int.parse(match[2]!));
  }

  Future<void> _download(Uri uri, File partial, DownloadArtifact model) async {
    var offset = await partial.exists() ? await partial.length() : 0;
    if (offset == model.size) return;
    _progress('downloading', offset, model.size);
    _checkCancelled();
    final client = _openClient(_connectionTimeout);
    RandomAccessFile? writer;
    try {
      final request = await client.getUrl(uri).timeout(_requestTimeout);
      request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
      if (offset > 0) {
        request.headers.set(HttpHeaders.rangeHeader, 'bytes=$offset-');
      }
      final response = await request.close().timeout(_requestTimeout);
      _checkCancelled();
      if (response.statusCode == HttpStatus.partialContent) {
        _range(response, model, offset);
      } else if (response.statusCode == HttpStatus.ok) {
        // A source that ignores Range must replace the prefix, never append.
        offset = 0;
      } else {
        throw HttpException('文件下载失败（HTTP ${response.statusCode}），请重试。');
      }
      final output = await partial.open(
          mode: offset == 0 ? FileMode.write : FileMode.append);
      writer = output;
      var received = offset;
      var lastProgress = DateTime.fromMillisecondsSinceEpoch(0);
      await for (final chunk
          in response.timeout(_idleTimeout, onTimeout: (sink) {
        client.close(force: true);
        sink.addError(TimeoutException('文件下载响应超时，请重试。'));
        sink.close();
      })) {
        _checkCancelled();
        if (received + chunk.length > model.size) {
          _closeClient(client);
          await output.close();
          writer = null;
          await partial.delete();
          throw const HttpException('文件文件大小不符，请检查下载地址。');
        }
        // Backpressure keeps the file out of the UI isolate's heap.
        await output.writeFrom(chunk);
        received += chunk.length;
        final now = DateTime.now();
        if (now.difference(lastProgress) >= _progressInterval ||
            received == model.size) {
          _progress('downloading', received, model.size);
          lastProgress = now;
        }
      }
      await output.flush();
      _checkCancelled();
      if (received != model.size) {
        throw const HttpException('下载尚未完成，请点击继续下载。');
      }
    } finally {
      try {
        if (writer != null) {
          try {
            await writer.flush();
          } finally {
            await writer.close();
          }
        }
      } finally {
        _closeClient(client);
      }
    }
  }

  Future<File> ensure(Directory directory, DownloadArtifact model) async {
    if (_running) throw StateError('文件下载正在进行。');
    _running = true;
    _cancelled = false;
    final file = fileFor(directory, model);
    final partial = File('${directory.path}/${model.sha256}.partial');
    final marker = _marker(directory, model);
    try {
      await directory.create(recursive: true);
      if (await isAvailable(directory, model)) return file;
      // Existing verified files never probe, so launches remain offline-capable.
      if (await file.exists()) {
        if (await file.length() == model.size && await _verify(file, model)) {
          await marker.writeAsString(model.sha256, flush: true);
          return file;
        }
        await file.delete();
      }
      if (await partial.exists() && await partial.length() > model.size) {
        await partial.delete();
      }
      var complete =
          await partial.exists() && await partial.length() == model.size;
      if (complete && !await _verify(partial, model)) {
        await partial.delete();
        complete = false;
      }
      if (!complete) {
        final offset = await partial.exists() ? await partial.length() : 0;
        final sources = await _rankSources(model, offset);
        for (var index = 0; index < sources.length; index++) {
          _checkCancelled();
          if (index > 0) {
            _progress(
                'switching',
                await partial.exists() ? await partial.length() : 0,
                model.size);
          }
          try {
            final resumed =
                await partial.exists() && await partial.length() > 0;
            await _download(sources[index], partial, model);
            var valid = await _verify(partial, model);
            if (!valid) {
              await partial.delete();
              if (resumed) {
                // Do not let a corrupt prefix from a failed source poison a good
                // fallback. Retry once from zero after a resumed hash failure.
                await _download(sources[index], partial, model);
                valid = await _verify(partial, model);
                if (!valid) await partial.delete();
              }
            }
            if (!valid) throw const FormatException('文件校验失败，请重新下载。');
            break;
          } on Exception catch (failure) {
            _checkCancelled();
            // Another network source cannot resolve a local disk failure.
            if (failure is FileSystemException ||
                (failure is! IOException &&
                    failure is! TimeoutException &&
                    failure is! FormatException) ||
                index == sources.length - 1) {
              rethrow;
            }
          }
        }
      }
      _checkCancelled();
      await partial.rename(file.path);
      await marker.writeAsString(model.sha256, flush: true);
      _progress('ready', model.size, model.size);
      return file;
    } catch (_) {
      if (_cancelled) throw FileDownloadCancelled();
      rethrow;
    } finally {
      for (final client in _clients.toList()) {
        client.close(force: true);
      }
      _clients.clear();
      _running = false;
    }
  }

  Future<bool> _verify(File file, DownloadArtifact model) async {
    _checkCancelled();
    _progress('verifying', model.size, model.size);
    _checkCancelled();
    final path = file.path;
    final checksum = await Isolate.run(() => hashFile(path));
    _checkCancelled();
    return checksum == model.sha256;
  }

  static Future<String> hashFile(String path) async =>
      (await sha256.bind(File(path).openRead()).first).toString();
}
