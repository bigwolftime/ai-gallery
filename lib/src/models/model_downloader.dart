import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'package:crypto/crypto.dart';
import 'model_manifest.dart';

class ModelDownloader {
  ModelDownloader({this.onProgress, HttpClient Function()? clientFactory})
      : _clientFactory = clientFactory ?? HttpClient.new;
  final void Function(ModelDownloadProgress)? onProgress;
  final HttpClient Function() _clientFactory;
  HttpClient? _client;
  bool _cancelled = false;
  bool _running = false;

  File modelFile(Directory directory, ModelManifest model) =>
      File('${directory.path}/${model.sha256}.litertlm');
  File _marker(Directory directory, ModelManifest model) =>
      File('${directory.path}/${model.sha256}.verified');

  Future<bool> isAvailable(Directory directory, ModelManifest model) async {
    final file = modelFile(directory, model);
    final marker = _marker(directory, model);
    return await file.exists() &&
        await file.length() == model.size &&
        await marker.exists() &&
        (await marker.readAsString()).trim() == model.sha256;
  }

  void cancel() {
    _cancelled = true;
    _client?.close(force: true);
  }

  void _checkCancelled() {
    if (_cancelled) throw ModelDownloadCancelled();
  }

  void _progress(String stage, int received, int total) =>
      onProgress?.call(ModelDownloadProgress(stage, received, total));

  Future<File> ensure(Directory directory, ModelManifest model) async {
    if (_running) throw StateError('模型下载正在进行。');
    _running = true;
    _cancelled = false;
    RandomAccessFile? writer;
    final file = modelFile(directory, model);
    final partial = File('${directory.path}/${model.sha256}.partial');
    final marker = _marker(directory, model);
    try {
      await directory.create(recursive: true);
      if (await isAvailable(directory, model)) return file;
      // Adopt an existing full file only after verifying it (e.g. a pre-migration copy).
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
      var offset = await partial.exists() ? await partial.length() : 0;
      if (offset < model.size) {
        _progress('downloading', offset, model.size);
        final client = _clientFactory();
        _client = client;
        client.connectionTimeout = const Duration(seconds: 25);
        client.autoUncompress = false;
        final request =
            await client.getUrl(model.url).timeout(const Duration(seconds: 30));
        request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
        if (offset > 0) {
          request.headers.set(HttpHeaders.rangeHeader, 'bytes=$offset-');
        }
        final response =
            await request.close().timeout(const Duration(seconds: 30));
        _checkCancelled();
        if (response.statusCode == HttpStatus.partialContent) {
          final range =
              response.headers.value(HttpHeaders.contentRangeHeader) ?? '';
          final match = RegExp(r'^bytes (\d+)-(\d+)/(\d+)$').firstMatch(range);
          if (match == null ||
              int.parse(match[1]!) != offset ||
              int.parse(match[3]!) != model.size ||
              int.parse(match[2]!) < offset ||
              int.parse(match[2]!) >= model.size) {
            throw const HttpException('下载服务返回了不正确的续传范围，请重试。');
          }
        } else if (response.statusCode == HttpStatus.ok) {
          // A server can ignore Range. Restart instead of appending a full response.
          offset = 0;
        } else {
          throw HttpException('模型下载失败（HTTP ${response.statusCode}），请重试。');
        }
        final output = await partial.open(
            mode: offset == 0 ? FileMode.write : FileMode.append);
        writer = output;
        var received = offset;
        var lastProgress = DateTime.fromMillisecondsSinceEpoch(0);
        await for (final chunk
            in response.timeout(const Duration(seconds: 40))) {
          _checkCancelled();
          if (received + chunk.length > model.size) {
            await output.close();
            writer = null;
            await partial.delete();
            throw const HttpException('模型文件大小不符，请检查下载地址。');
          }
          // Backpressure keeps the 485 MB download out of the UI isolate's heap.
          await output.writeFrom(chunk);
          received += chunk.length;
          final now = DateTime.now();
          if (now.difference(lastProgress).inMilliseconds >= 150 ||
              received == model.size) {
            _progress('downloading', received, model.size);
            lastProgress = now;
          }
        }
        await output.flush();
        await output.close();
        writer = null;
        _checkCancelled();
        if (received != model.size) {
          throw const HttpException('下载尚未完成，请点击继续下载。');
        }
      }
      if (!await _verify(partial, model)) {
        await partial.delete();
        throw const FormatException('模型校验失败，请重新下载。');
      }
      _checkCancelled();
      // Same-filesystem rename activates only a complete, verified model.
      await partial.rename(file.path);
      await marker.writeAsString(model.sha256, flush: true);
      _progress('ready', model.size, model.size);
      return file;
    } catch (_) {
      if (_cancelled) throw ModelDownloadCancelled();
      rethrow;
    } finally {
      if (writer != null) {
        try {
          await writer.flush();
        } finally {
          await writer.close();
        }
      }
      _client?.close(force: true);
      _client = null;
      _running = false;
    }
  }

  Future<bool> _verify(File file, ModelManifest model) async {
    _checkCancelled();
    _progress('verifying', model.size, model.size);
    final path = file.path;
    // Hash streaming runs on a separate isolate; it never loads the full file.
    final checksum = await Isolate.run(() => hashFile(path));
    _checkCancelled();
    return checksum == model.sha256;
  }

  static Future<String> hashFile(String path) async =>
      (await sha256.bind(File(path).openRead()).first).toString();
}
