import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:ai_gallery_native/ai_gallery_native.dart';
import 'package:flutter/services.dart';
import 'models/model_downloader.dart';
import 'models/model_manifest.dart';

class GalleryNativeService {
  GalleryNativeService({AIGalleryNative? native})
      : native = native ?? AIGalleryNative() {
    _downloader = ModelDownloader(onProgress: (progress) {
      if (!_modelEvents.isClosed) _modelEvents.add(progress);
    });
  }
  final AIGalleryNative native;
  final _modelEvents = StreamController<ModelDownloadProgress>.broadcast();
  late final ModelDownloader _downloader;
  ModelManifest? _manifest;
  Directory? _directory;

  Stream<AnalysisProgress> get analysisProgress => native.analysisProgress;
  Stream<ModelDownloadProgress> get modelProgress => _modelEvents.stream;
  int get modelBytes => _manifest?.size ?? 0;
  String get modelName => _manifest?.name ?? 'EmbeddingGemma 2';

  Future<void> _prepareManifest() async {
    if (_manifest != null) return;
    final directory = Directory(await native.getModelDirectory());
    final cached = File('${directory.path}/active-manifest.json');
    final embedded =
        await rootBundle.loadString('assets/models/model-manifest.json');
    var source = embedded;
    const remote = String.fromEnvironment('MODEL_MANIFEST_URL');
    if (remote.isNotEmpty) {
      final uri = Uri.parse(remote);
      if (uri.scheme != 'https' || uri.host.isEmpty) {
        throw const FormatException('模型清单地址必须使用 HTTPS。');
      }
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 10);
      try {
        final request =
            await client.getUrl(uri).timeout(const Duration(seconds: 12));
        final response =
            await request.close().timeout(const Duration(seconds: 12));
        if (response.statusCode != 200) throw HttpException('模型清单暂不可用。');
        final bytes = <int>[];
        await for (final chunk
            in response.timeout(const Duration(seconds: 12))) {
          bytes.addAll(chunk);
          if (bytes.length > 65536) throw const FormatException('模型清单过大。');
        }
        source = utf8.decode(bytes);
        ModelManifest.decode(source);
      } catch (_) {
        // Cached metadata lets previously downloaded models work offline.
        if (await cached.exists()) {
          try {
            final fallback = await cached.readAsString();
            ModelManifest.decode(fallback);
            source = fallback;
          } catch (_) {
            source = embedded;
          }
        }
      } finally {
        client.close(force: true);
      }
    }
    _manifest = ModelManifest.decode(source);
    _directory = directory;
    _manifestSource = source;
  }

  String _manifestSource = '';

  Future<bool> modelIsAvailable() async {
    await _prepareManifest();
    return _downloader.isAvailable(_directory!, _manifest!);
  }

  Future<void> initializeModel() async {
    await _prepareManifest();
    final file = await _downloader.ensure(_directory!, _manifest!);
    await native.initializeModel(
        modelPath: file.path, indexVersion: _manifest!.indexVersion);
    // Persist the active version atomically, only after the runtime accepts it.
    final metadata = File('${_directory!.path}/active-manifest.json.partial');
    await metadata.writeAsString(_manifestSource, flush: true);
    await metadata.rename('${_directory!.path}/active-manifest.json');
  }

  void cancelModelDownload() => _downloader.cancel();
  void dispose() {
    _downloader.cancel();
    _modelEvents.close();
  }

  Future<List<GalleryPhoto>> loadPhotos() => native.loadPhotos();
  Future<bool> hasIndexedPhotos(List<String> ids) =>
      native.hasIndexedPhotos(ids);
  Future<AnalysisSummary> analyzePhotos(List<String> ids) =>
      native.analyzePhotos(ids);
  Future<List<SearchHit>> search(String query) => native.search(query);
  Future<void> sharePhotos(List<String> ids) => native.sharePhotos(ids);
}
