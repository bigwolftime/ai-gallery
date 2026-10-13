import 'dart:async';
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

enum OtaPhase {
  idle,
  unavailable,
  checking,
  current,
  available,
  downloading,
  ready,
  failed
}

class OtaController extends ChangeNotifier {
  OtaController(
      {OtaGateway? gateway, this.checkTimeout = const Duration(seconds: 20)})
      : _gateway = gateway ?? ShorebirdGateway();
  final OtaGateway _gateway;
  final Duration checkTimeout;
  OtaPhase phase = OtaPhase.idle;
  int? currentPatch;
  int? nextPatch;
  String? error;
  bool _disposed = false;
  bool get busy => phase == OtaPhase.checking || phase == OtaPhase.downloading;

  /// Called without awaiting from initState: OTA cannot block photos/model startup.
  Future<void> check() async {
    if (busy || _disposed) return;
    error = null;
    if (!_gateway.isAvailable) {
      phase = OtaPhase.unavailable;
      _emit();
      return;
    }
    phase = OtaPhase.checking;
    _emit();
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
    if (busy || _disposed) return;
    if (!_gateway.isAvailable) {
      phase = OtaPhase.unavailable;
      _emit();
      return;
    }
    if (phase != OtaPhase.available) return;
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

  String get title => switch (phase) {
        OtaPhase.idle => '应用更新',
        OtaPhase.unavailable => '此安装包暂不支持在线更新',
        OtaPhase.checking => '正在检查更新…',
        OtaPhase.current => '当前应用已是最新版本',
        OtaPhase.available => '有可用更新',
        OtaPhase.downloading => '正在下载更新…',
        OtaPhase.ready => '更新已下载，下次打开时生效',
        OtaPhase.failed => error ?? '更新失败，请重试。',
      };
  void _emit() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
