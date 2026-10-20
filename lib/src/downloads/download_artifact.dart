import 'dart:io';

/// Immutable identity for an independently verified, resumable download.
class DownloadArtifact {
  DownloadArtifact(
      {required List<Uri> urls,
      required this.sha256,
      required this.size,
      required this.extension})
      : downloadUrls = List.unmodifiable(urls.toSet()) {
    if (downloadUrls.isEmpty ||
        size <= 0 ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(sha256) ||
        !RegExp(r'^\.[a-z0-9]+$').hasMatch(extension)) {
      throw const FormatException('下载文件配置不正确。');
    }
  }
  final List<Uri> downloadUrls;
  final String sha256;
  final int size;
  final String extension;
}

class FileDownloadProgress {
  const FileDownloadProgress(this.stage, this.received, this.total);
  final String stage;
  final int received;
  final int total;
  double? get fraction => total > 0 ? (received / total).clamp(0.0, 1.0) : null;
}

// Reuse the existing cancellation contract for both kinds of transfer.
class FileDownloadCancelled implements IOException {
  @override
  String toString() => '下载已暂停，可稍后继续。';
}
