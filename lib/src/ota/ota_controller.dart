import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import '../downloads/download_artifact.dart';
import '../downloads/verified_file_downloader.dart';
import 'app_release.dart';
import 'app_distribution.dart';
import 'release_gateway.dart';
import 'package:flutter/foundation.dart';
import 'package:shorebird_code_push/shorebird_code_push.dart';

/// The adapter keeps network/FFI calls separate from UI state and regression tests.
abstract interface class OtaGateway {
  bool get isAvailable;
  Future<int?> currentPatch();
  Future<int?> nextPatch();
  Future<UpdateStatus> check();
  Future<void> download();
}

class ShorebirdGateway implements OtaGateway {
  ShorebirdGateway({ShorebirdUpdater? updater})
      : _updater = updater ?? ShorebirdUpdater();
  final ShorebirdUpdater _updater;
  static const track =
      UpdateTrack(String.fromEnvironment('OTA_TRACK', defaultValue: 'stable'));
  @override
  bool get isAvailable => _updater.isAvailable;
  @override
  Future<int?> currentPatch() async =>
      (await _updater.readCurrentPatch())?.number;
  @override
  Future<int?> nextPatch() async => (await _updater.readNextPatch())?.number;
  @override
  Future<UpdateStatus> check() => _updater.checkForUpdate(track: track);
  @override
  Future<void> download() => _updater.update(track: track);
}

/// No FFI updater is created for builds distributed through an app store.
class StoreOtaGateway implements OtaGateway {
  const StoreOtaGateway();
  @override
  bool get isAvailable => false;
  @override
  Future<int?> currentPatch() async => null;
  @override
  Future<int?> nextPatch() async => null;
  @override
  Future<UpdateStatus> check() async => UpdateStatus.unavailable;
  @override
  Future<void> download() async {}
}

enum OtaPhase {
  idle,
  unavailable,
  checking,
  current,
  available,
  downloading,
  ready,
  failed,
  packageAvailable,
  packageDownloading,
  packageReady,
  packageOpening,
  storeManaged,
  storeOpening
}

class OtaController extends ChangeNotifier {
  OtaController(
      {OtaGateway? gateway,
      ReleaseGateway? releases,
      VerifiedFileDownloader? packageDownloader,
      this.distribution = const AppDistribution(),
      this.checkTimeout = const Duration(seconds: 20)})
      : _gateway = gateway ??
            (distribution.managedByStore
                ? const StoreOtaGateway()
                : ShorebirdGateway()),
        _releases = releases ?? NativeReleaseGateway() {
    _packages = packageDownloader ??
        VerifiedFileDownloader(onProgress: (value) {
          packageProgress = value;
          _emit();
        });
    if (distribution.managedByStore) phase = OtaPhase.storeManaged;
  }
  final AppDistribution distribution;
  bool get automaticChecksAllowed => !distribution.managedByStore;
  final OtaGateway _gateway;
  final ReleaseGateway _releases;
  late final VerifiedFileDownloader _packages;
  InstalledApp? installed;
  AppRelease? fullRelease;
  FileDownloadProgress? packageProgress;
  File? packageFile;
  bool packageCheckConfirmed = false;
  bool installPermissionRequired = false;
  String? packageNotice;
  final Duration checkTimeout;
  OtaPhase phase = OtaPhase.idle;
  int? currentPatch;
  int? nextPatch;
  String? error;
  bool _disposed = false;
  bool get busy =>
      phase == OtaPhase.checking ||
      phase == OtaPhase.downloading ||
      phase == OtaPhase.packageDownloading ||
      phase == OtaPhase.packageOpening ||
      phase == OtaPhase.storeOpening;
  bool get hasFullRelease => fullRelease != null;

  /// Called without awaiting from initState: OTA cannot block photos/model startup.
  Future<void> check() async {
    if (busy || _disposed) return;
    if (distribution.managedByStore) {
      phase = OtaPhase.storeManaged;
      _emit();
      return;
    }
    error = null;
    phase = OtaPhase.checking;
    packageNotice = null;
    packageCheckConfirmed = false;
    _emit();
    try {
      installed = await _releases.installedApp().timeout(checkTimeout);
      final release = await _releases.check(installed!).timeout(checkTimeout);
      packageCheckConfirmed = true;
      fullRelease = release;
      if (_disposed) return;
      if (release != null) {
        // A native base upgrade takes priority over patches for the old base.
        phase = OtaPhase.packageAvailable;
        _emit();
        return;
      }
    } catch (_) {
      fullRelease = null;
      packageNotice = '整包版本暂未确认，可稍后重新检查。';
    }
    if (_disposed) return;
    if (!_gateway.isAvailable) {
      phase = OtaPhase.unavailable;
      _emit();
      return;
    }
    try {
      final status = await _gateway.check().timeout(checkTimeout);
      currentPatch = await _gateway.currentPatch().timeout(checkTimeout);
      nextPatch = await _gateway.nextPatch().timeout(checkTimeout);
      phase = switch (status) {
        UpdateStatus.outdated => OtaPhase.available,
        UpdateStatus.restartRequired => OtaPhase.ready,
        UpdateStatus.unavailable => OtaPhase.unavailable,
        UpdateStatus.upToDate => OtaPhase.current,
      };
    } catch (_) {
      error = '暂时无法检查更新，请稍后重试。';
      phase = OtaPhase.failed;
    }
    _emit();
  }

  Future<void> download() async {
    if (busy || _disposed || distribution.managedByStore) return;
    if (phase != OtaPhase.available) return;
    if (!_gateway.isAvailable) {
      phase = OtaPhase.unavailable;
      _emit();
      return;
    }
    phase = OtaPhase.downloading;
    error = null;
    _emit();
    try {
      await _gateway.download();
      // Completion confirms the patch is staged. A patch-number read is optional.
      try {
        nextPatch = await _gateway.nextPatch().timeout(checkTimeout);
      } catch (_) {}
      phase = OtaPhase.ready;
    } on UpdateException catch (failure) {
      if (failure.reason == UpdateFailureReason.noUpdate) {
        phase = OtaPhase.current;
      } else {
        error = '更新下载失败，请检查网络后重试。';
        phase = OtaPhase.failed;
      }
    } catch (_) {
      error = '更新下载失败，请稍后重试。';
      phase = OtaPhase.failed;
    }
    _emit();
  }

  Future<void> downloadPackage() async {
    final release = fullRelease;
    if (distribution.managedByStore ||
        busy ||
        _disposed ||
        phase != OtaPhase.packageAvailable ||
        release == null ||
        !release.isApk) {
      return;
    }
    phase = OtaPhase.packageDownloading;
    packageProgress = null;
    error = null;
    packageNotice = null;
    _emit();
    try {
      final directory = await _releases.downloadDirectory();
      await directory.create(recursive: true);
      // This directory is dedicated to update packages. Keep the current hash's
      // prefix for resume, and remove only obsolete generated update artifacts.
      await for (final entry in directory.list()) {
        final name = entry.uri.pathSegments.last;
        if (entry is File &&
            RegExp(r'^[a-f0-9]{64}\.(apk|partial|verified)$').hasMatch(name) &&
            !name.startsWith('${release.sha256}.')) {
          await entry.delete();
        }
      }
      final file = await _packages.ensure(directory, release.artifact);
      try {
        await _releases.validatePackage(file, release);
      } catch (_) {
        // A file for the wrong package or signing identity is never installable.
        try {
          if (await file.exists()) await file.delete();
          final marker = File('${directory.path}/${release.sha256}.verified');
          if (await marker.exists()) await marker.delete();
        } on FileSystemException {
          /* Preserve the original validation failure. */
        }
        rethrow;
      }
      if (_disposed) return;
      packageFile = file;
      phase = OtaPhase.packageReady;
    } on FileDownloadCancelled {
      phase = OtaPhase.packageAvailable;
      packageNotice = '下载已暂停，点击继续下载可恢复进度。';
    } catch (failure) {
      phase = OtaPhase.packageAvailable;
      error = _describe(failure, '安装包下载或校验失败，请重试。');
    }
    _emit();
  }

  void pausePackageDownload() => _packages.cancel();

  Future<void> installPackage() async {
    final file = packageFile;
    final release = fullRelease;
    if (distribution.managedByStore ||
        busy ||
        _disposed ||
        phase != OtaPhase.packageReady ||
        file == null ||
        release == null) {
      return;
    }
    phase = OtaPhase.packageOpening;
    error = null;
    _emit();
    try {
      final action = await _releases.installPackage(file, release);
      installPermissionRequired = action == InstallAction.permissionRequired;
      packageNotice = installPermissionRequired
          ? '请在系统设置中允许安装此来源的应用，返回后点击“继续安装”。'
          : '已打开系统安装界面，请确认覆盖安装。模型和照片索引会保留。';
    } catch (failure) {
      error = _describe(failure, '无法打开安装界面，请重试。');
    }
    // Launching the installer does not prove that an upgrade was installed.
    phase = OtaPhase.packageReady;
    _emit();
  }

  Future<void> openFullRelease() async {
    final release = fullRelease;
    if (distribution.managedByStore ||
        busy ||
        _disposed ||
        release == null ||
        release.isApk) {
      return;
    }
    phase = OtaPhase.packageOpening;
    error = null;
    _emit();
    try {
      await _releases.openRelease(release);
    } catch (failure) {
      error = _describe(failure, '无法打开更新地址，请重试。');
    }
    phase = OtaPhase.packageAvailable;
    _emit();
  }

  Future<void> openStore() async {
    if (!distribution.managedByStore || busy || _disposed) return;
    final uri = distribution.storeUri;
    if (uri == null) return;
    phase = OtaPhase.storeOpening;
    packageNotice = null;
    _emit();
    try {
      // Read local version information only; stores perform version checks.
      final current = await _releases.installedApp().timeout(checkTimeout);
      await _releases.openRelease(AppRelease(
          platform: current.platform,
          channel: distribution.channel,
          version: current.version,
          buildNumber: current.buildNumber,
          kind: 'store',
          url: uri));
    } catch (failure) {
      packageNotice = _describe(failure, '无法打开应用商店，请在商店客户端中检查更新。');
    }
    phase = OtaPhase.storeManaged;
    _emit();
  }

  String _describe(Object failure, String fallback) =>
      failure is PlatformException
          ? failure.message ?? fallback
          : failure is HttpException
              ? failure.message
              : failure is FormatException
                  ? failure.message.toString()
                  : failure is FileSystemException
                      ? '无法保存安装包，请检查可用存储空间后重试。'
                      : fallback;

  String get title => switch (phase) {
        OtaPhase.idle => '应用更新',
        OtaPhase.unavailable =>
          packageCheckConfirmed ? '整包版本已检查，在线补丁不可用' : '暂时无法确认应用更新',
        OtaPhase.checking => '正在检查更新…',
        OtaPhase.current => packageCheckConfirmed ? '当前应用已是最新版本' : '当前基础包暂无新补丁',
        OtaPhase.available => '有可用更新',
        OtaPhase.downloading => '正在下载更新…',
        OtaPhase.ready => '更新已下载，下次打开时生效',
        OtaPhase.failed => error ?? '更新失败，请重试。',
        OtaPhase.packageAvailable => '发现新版本 ${fullRelease!.version}',
        OtaPhase.packageDownloading =>
          ['verifying', 'ready'].contains(packageProgress?.stage)
              ? '正在校验安装包…'
              : '正在下载安装包…',
        OtaPhase.packageReady => '安装包已就绪',
        OtaPhase.packageOpening =>
          fullRelease?.isApk == true ? '正在打开安装界面…' : '正在打开更新地址…',
        OtaPhase.storeManaged => '由 ${distribution.storeName} 管理更新',
        OtaPhase.storeOpening => '正在打开 ${distribution.storeName}…',
      };
  void _emit() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _packages.cancel();
    super.dispose();
  }
}
