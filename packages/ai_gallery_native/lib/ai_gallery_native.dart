import 'dart:async';

import 'package:flutter/services.dart';

class GalleryPhoto {
  const GalleryPhoto({
    required this.id,
    required this.uri,
    this.createdAt,
    this.width = 0,
    this.height = 0,
  });

  final String id;
  final String uri;
  final DateTime? createdAt;
  final int width;
  final int height;

  factory GalleryPhoto.fromMap(Map<Object?, Object?> map) {
    final rawDate = map['createdAt'];
    return GalleryPhoto(
      id: map['id'] as String,
      uri: map['uri'] as String,
      createdAt: rawDate is String ? DateTime.tryParse(rawDate) : null,
      width: (map['width'] as num?)?.toInt() ?? 0,
      height: (map['height'] as num?)?.toInt() ?? 0,
    );
  }
}

class SearchHit {
  const SearchHit({required this.photo, this.score});

  final GalleryPhoto photo;
  final double? score;

  factory SearchHit.fromMap(Map<Object?, Object?> map) {
    final photo = GalleryPhoto.fromMap(
      Map<Object?, Object?>.from(map['photo'] as Map),
    );
    return SearchHit(
      photo: photo,
      score: (map['score'] as num?)?.toDouble(),
    );
  }
}

class AnalysisProgress {
  const AnalysisProgress({required this.completed, required this.total});

  final int completed;
  final int total;

  factory AnalysisProgress.fromMap(Map<Object?, Object?> map) {
    return AnalysisProgress(
      completed: (map['completed'] as num?)?.toInt() ?? 0,
      total: (map['total'] as num?)?.toInt() ?? 0,
    );
  }
}

class AIGalleryNative {
  AIGalleryNative({MethodChannel? methods, EventChannel? progress})
      : _methods = methods ?? const MethodChannel('ai_gallery/native'),
        _progress = progress ?? const EventChannel('ai_gallery/progress');

  final MethodChannel _methods;
  final EventChannel _progress;

  Stream<AnalysisProgress> get analysisProgress =>
      _progress.receiveBroadcastStream().map((event) =>
          AnalysisProgress.fromMap(Map<Object?, Object?>.from(event as Map)));

  Future<String> getModelDirectory() async {
    final directory = await _methods.invokeMethod<String>('getModelDirectory');
    if (directory == null || directory.isEmpty) throw StateError('无法获取模型存储目录。');
    return directory;
  }

  Future<void> initializeModel(
      {String? modelPath, String? indexVersion}) async {
    await _methods.invokeMethod<void>('initializeModel', {
      'modelPath': modelPath,
      'indexVersion': indexVersion,
    });
  }

  Future<Uint8List?> loadThumbnail(String id) async {
    return await _methods.invokeMethod<Uint8List>('loadThumbnail', {'id': id});
  }

  Future<Uint8List?> loadImage(String id) =>
      _methods.invokeMethod<Uint8List>('loadImage', {'id': id});

  Future<bool> shouldOfferAnalysis() async =>
      await _methods.invokeMethod<bool>('shouldOfferAnalysis') ?? false;

  Future<void> dismissAnalysisPrompt() =>
      _methods.invokeMethod<void>('dismissAnalysisPrompt');

  Future<void> openSettings() => _methods.invokeMethod<void>('openSettings');

  Future<List<GalleryPhoto>> loadPhotos() async {
    final raw =
        await _methods.invokeListMethod<Object?>('loadPhotos') ?? const [];
    return raw
        .map((item) =>
            GalleryPhoto.fromMap(Map<Object?, Object?>.from(item as Map)))
        .toList();
  }

  Future<bool> hasIndexedPhotos(List<String> photoIds) async {
    return await _methods.invokeMethod<bool>(
          'hasIndexedPhotos',
          {'photoIds': photoIds},
        ) ??
        false;
  }

  Future<AnalysisSummary> analyzePhotos(List<String> photoIds) async {
    final raw = await _methods.invokeMapMethod<Object?, Object?>(
      'analyzePhotos',
      {'photoIds': photoIds},
    );
    return AnalysisSummary.fromMap(raw ?? {});
  }

  Future<List<SearchHit>> search(String query, {int limit = 0}) async {
    final raw = await _methods.invokeListMethod<Object?>(
          'search',
          {'query': query, 'limit': limit},
        ) ??
        const [];
    return raw
        .map((item) =>
            SearchHit.fromMap(Map<Object?, Object?>.from(item as Map)))
        .toList();
  }

  Future<void> sharePhotos(List<String> photoIds) async {
    await _methods.invokeMethod<void>(
      'sharePhotos',
      {'photoIds': photoIds},
    );
  }
}

class AnalysisSummary {
  const AnalysisSummary(
      {this.processed = 0, this.succeeded = 0, this.failed = 0});
  final int processed;
  final int succeeded;
  final int failed;
  factory AnalysisSummary.fromMap(Map<Object?, Object?> map) => AnalysisSummary(
        processed: (map['processed'] as num?)?.toInt() ?? 0,
        succeeded: (map['succeeded'] as num?)?.toInt() ?? 0,
        failed: (map['failed'] as num?)?.toInt() ?? 0,
      );
}
