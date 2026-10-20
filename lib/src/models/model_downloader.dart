import 'dart:io';
import '../downloads/download_artifact.dart';
import '../downloads/verified_file_downloader.dart';
import 'model_manifest.dart';

/// Models and application packages share transfer/verification mechanics, while
/// retaining separate paths, metadata and activation rules.
class ModelDownloader {
  ModelDownloader(
      {void Function(ModelDownloadProgress)? onProgress,
      HttpClient Function()? clientFactory,
      Duration probeTimeout = const Duration(seconds: 5)})
      : _files = VerifiedFileDownloader(
            clientFactory: clientFactory,
            probeTimeout: probeTimeout,
            onProgress: onProgress == null
                ? null
                : (progress) => onProgress(ModelDownloadProgress(
                    progress.stage, progress.received, progress.total)));
  final VerifiedFileDownloader _files;
  static const probeBytes = VerifiedFileDownloader.probeBytes;
  DownloadArtifact _artifact(ModelManifest model) => DownloadArtifact(
      urls: model.downloadUrls,
      sha256: model.sha256,
      size: model.size,
      extension: '.litertlm');
  File modelFile(Directory directory, ModelManifest model) =>
      _files.fileFor(directory, _artifact(model));
  Future<bool> isAvailable(Directory directory, ModelManifest model) =>
      _files.isAvailable(directory, _artifact(model));
  Future<File> ensure(Directory directory, ModelManifest model) async {
    try {
      return await _files.ensure(directory, _artifact(model));
    } on FileDownloadCancelled {
      throw ModelDownloadCancelled();
    }
  }

  void cancel() => _files.cancel();
  static Future<String> hashFile(String path) =>
      VerifiedFileDownloader.hashFile(path);
}
