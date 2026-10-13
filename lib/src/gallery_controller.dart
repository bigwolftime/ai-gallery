import 'dart:async';
import 'package:ai_gallery_native/ai_gallery_native.dart';
import 'package:flutter/foundation.dart';
import 'native_service.dart';
import 'models/model_manifest.dart';
import 'search_window.dart';

/// Coordinates UI workflows; native services own assets, inference and persistence.
class GalleryController extends ChangeNotifier {
  GalleryController({GalleryNativeService? service})
      : service = service ?? GalleryNativeService() {
    _subscription = this.service.analysisProgress.listen((value) {
      progress = value;
      _emit();
    }, onError: (Object failure) {
      error = failure.toString();
      _emit();
    });
    _modelSubscription = this.service.modelProgress.listen((value) {
      modelProgress = value;
      _emit();
    });
  }

  final GalleryNativeService service;
  late final StreamSubscription<AnalysisProgress> _subscription;
  late final StreamSubscription<ModelDownloadProgress> _modelSubscription;
  ModelDownloadProgress? modelProgress;
  bool needsModelDownload = false;
  bool downloadingModel = false;
  List<GalleryPhoto> photos = [];
  List<SearchHit> hits = [];
  int visibleCount = 0;
  bool loading = true;
  bool ready = false;
  bool searching = false;
  bool analyzing = false;
  bool sharing = false;
  bool promptRequested = false;
  bool selectionMode = false;
  String? error;
  String? message;
  AnalysisProgress? progress;
  final selected = <String>{};
  String? _pendingQuery;
  int _generation = 0;
  bool _disposed = false;

  bool get hasMore => visibleCount < hits.length;
  bool get busy => loading || searching || analyzing || sharing;
  List<SearchHit> get visibleHits => hits.take(visibleCount).toList();

  Future<void> start() async {
    loading = true;
    error = null;
    message = null;
    _emit();
    try {
      photos = await service.loadPhotos();
      _showLibrary();
      needsModelDownload = !await service.modelIsAvailable();
      if (!needsModelDownload) {
        await service.initializeModel();
        ready = true;
        promptRequested =
            photos.isNotEmpty && await service.native.shouldOfferAnalysis();
      }
    } catch (failure) {
      error = _describe(failure);
    } finally {
      loading = false;
      _emit();
    }
  }

  Future<void> downloadModel() async {
    if (loading || downloadingModel) return;
    loading = true;
    downloadingModel = true;
    error = null;
    message = null;
    _emit();
    try {
      await service.initializeModel();
      needsModelDownload = false;
      ready = true;
      promptRequested =
          photos.isNotEmpty && await service.native.shouldOfferAnalysis();
    } on ModelDownloadCancelled {
      message = '下载已暂停，点击继续下载即可恢复进度。';
    } catch (failure) {
      error = _describe(failure);
    } finally {
      loading = false;
      downloadingModel = false;
      _emit();
    }
  }

  void pauseModelDownload() => service.cancelModelDownload();

  Future<void> search(String query) async {
    if (busy || !ready) return;
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      _generation++;
      _showLibrary();
      _emit();
      return;
    }
    searching = true;
    error = null;
    message = null;
    final generation = ++_generation;
    _emit();
    try {
      if (!await service
          .hasIndexedPhotos(photos.map((photo) => photo.id).toList())) {
        _pendingQuery = trimmed;
        promptRequested = true;
        return;
      }
      final ranked = await service.search(trimmed);
      if (_disposed || generation != _generation) return;
      hits = ranked;
      visibleCount =
          SearchWindow.initialCount(ranked.map((hit) => hit.score!).toList());
      selected.clear();
      selectionMode = false;
    } catch (failure) {
      error = _describe(failure);
    } finally {
      searching = false;
      _emit();
    }
  }

  Future<void> answerPrompt(bool accept) async {
    promptRequested = false;
    final query = _pendingQuery;
    _pendingQuery = null;
    _emit();
    try {
      await service.native.dismissAnalysisPrompt();
    } catch (failure) {
      error = _describe(failure);
      _emit();
    }
    if (accept) {
      final hasIndex = await analyze();
      if (query != null && hasIndex && error == null) await search(query);
    }
  }

  Future<bool> analyze() async {
    if (busy || !ready) return false;
    analyzing = true;
    error = null;
    message = null;
    progress = null;
    _emit();
    try {
      // Refresh the library on manual analysis so newly added photos are included.
      photos = await service.loadPhotos();
      final summary =
          await service.analyzePhotos(photos.map((photo) => photo.id).toList());
      message = summary.processed == 0
          ? '所有可访问照片都已分析，无需重复处理。'
          : '分析完成：成功 ${summary.succeeded} 张，未完成 ${summary.failed} 张。';
      if (hits.every((hit) => hit.score == null)) _showLibrary();
      return await service
          .hasIndexedPhotos(photos.map((photo) => photo.id).toList());
    } catch (failure) {
      error = _describe(failure);
      return false;
    } finally {
      analyzing = false;
      progress = null;
      _emit();
    }
  }

  void expand() {
    visibleCount = SearchWindow.expand(visibleCount, hits.length);
    _emit();
  }

  void toggleSelectionMode() {
    selectionMode = !selectionMode;
    if (!selectionMode) selected.clear();
    _emit();
  }

  void select(String id) {
    selectionMode = true;
    if (!selected.add(id)) selected.remove(id);
    _emit();
  }

  Future<void> share([List<String>? ids]) async {
    if (sharing) return;
    final ordered = ids ??
        hits
            .where((hit) => selected.contains(hit.photo.id))
            .map((hit) => hit.photo.id)
            .toList();
    if (ordered.isEmpty) return;
    sharing = true;
    _emit();
    try {
      await service.sharePhotos(ordered);
    } catch (failure) {
      error = _describe(failure);
    } finally {
      sharing = false;
      _emit();
    }
  }

  void clearNotice() {
    error = null;
    message = null;
    message = null;
  }

  void _showLibrary() {
    hits = photos.map((photo) => SearchHit(photo: photo)).toList();
    visibleCount = hits.length;
    selected.clear();
    selectionMode = false;
  }

  String _describe(Object failure) => failure.toString();
  void _emit() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _subscription.cancel();
    _modelSubscription.cancel();
    service.dispose();
    super.dispose();
  }
}
