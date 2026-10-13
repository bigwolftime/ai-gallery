import 'dart:convert';

/// Deployment metadata is shared by both platforms. Paths use the content hash,
/// so an interrupted download can never replace a different verified model.
class ModelManifest {
  const ModelManifest(
      {required this.name,
      required this.modelVersion,
      required this.url,
      required this.sha256,
      required this.size,
      this.dimensions = 256,
      this.visionTokens = 70});
  final String name;
  final String modelVersion;
  final Uri url;
  final String sha256;
  final int size;
  final int dimensions;
  final int visionTokens;
  static const legacyHash =
      'e7a8a2204b91e0f96e92960e84a09a89212e1633dcb7575a9bf3378b4df77f4c';

  // Keep old iOS/Android vectors reusable for the identical model/settings.
  String get indexVersion =>
      sha256 == legacyHash && dimensions == 256 && visionTokens == 70
          ? 'embeddinggemma-2-256-v1'
          : '$sha256-d$dimensions-v$visionTokens';

  factory ModelManifest.decode(String source) {
    final map = jsonDecode(source) as Map<String, dynamic>;
    final uri = Uri.parse(map['url'] as String);
    final hash = map['sha256'] as String;
    final size = map['size'] as int;
    final dimensions = map['dimensions'] as int;
    final visionTokens = map['visionTokens'] as int;
    if (map['schemaVersion'] != 1 ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(hash) ||
        size <= 0 ||
        dimensions != 256 ||
        visionTokens != 70) {
      throw const FormatException('模型清单不兼容，请检查下载配置。');
    }
    return ModelManifest(
        name: map['name'] as String,
        modelVersion: map['modelVersion'] as String,
        url: uri,
        sha256: hash,
        size: size,
        dimensions: dimensions,
        visionTokens: visionTokens);
  }
}

class ModelDownloadProgress {
  const ModelDownloadProgress(this.stage, this.received, this.total);
  final String stage;
  final int received;
  final int total;
  double? get fraction => total > 0 ? (received / total).clamp(0.0, 1.0) : null;
}

class ModelDownloadCancelled implements Exception {
  @override
  String toString() => '模型下载已暂停，可稍后继续。';
}
