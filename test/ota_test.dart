import 'dart:async';
import 'package:ai_gallery/src/ota/ota_controller.dart';
import 'package:ai_gallery/src/ota/update_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shorebird_code_push/shorebird_code_push.dart';

class FakeOtaGateway implements OtaGateway {
  bool available = true;
  int checks = 0;
  int downloads = 0;
  int? current = 1;
  int? next = 1;
  UpdateStatus status = UpdateStatus.upToDate;
  Completer<UpdateStatus>? waitForCheck;
  UpdateException? downloadFailure;
  @override
  bool get isAvailable => available;
  @override
  Future<int?> currentPatch() async => current;
  @override
  Future<int?> nextPatch() async => next;
  @override
  Future<UpdateStatus> check() async {
    checks++;
    return waitForCheck?.future ?? status;
  }

  @override
  Future<void> download() async {
    downloads++;
    if (downloadFailure != null) throw downloadFailure!;
    next = (current ?? 0) + 1;
  }
}

void main() {
  test(
      'ordinary Flutter build reports OTA unavailable without a network request',
      () async {
    final gateway = FakeOtaGateway()..available = false;
    final ota = OtaController(gateway: gateway);
    addTearDown(ota.dispose);
    await ota.check();
    await ota.download();
    expect(ota.phase, OtaPhase.unavailable);
    expect(gateway.checks, 0);
    expect(gateway.downloads, 0);
  });
  test('check exposes available patch; download stages it for next launch only',
      () async {
    final gateway = FakeOtaGateway()..status = UpdateStatus.outdated;
    final ota = OtaController(gateway: gateway);
    addTearDown(ota.dispose);
    await ota.check();
    expect(ota.phase, OtaPhase.available);
    await ota.download();
    expect(ota.phase, OtaPhase.ready);
    expect(ota.currentPatch, 1);
    expect(ota.nextPatch, 2);
    expect(gateway.downloads, 1);
    await ota.download();
    expect(gateway.downloads, 1);
  });
  test('pending downloaded patch remains restart-required', () async {
    final gateway = FakeOtaGateway()
      ..status = UpdateStatus.restartRequired
      ..next = 2;
    final ota = OtaController(gateway: gateway);
    addTearDown(ota.dispose);
    await ota.check();
    expect(ota.phase, OtaPhase.ready);
  });
  test('slow check times out, while duplicate checks do not overlap', () async {
    final gateway = FakeOtaGateway()..waitForCheck = Completer<UpdateStatus>();
    final ota = OtaController(
        gateway: gateway, checkTimeout: const Duration(milliseconds: 20));
    addTearDown(ota.dispose);
    final first = ota.check();
    await ota.check();
    expect(gateway.checks, 1);
    await first;
    expect(ota.phase, OtaPhase.failed);
    gateway.waitForCheck!.complete(UpdateStatus.upToDate);
    await Future<void>.delayed(Duration.zero);
    expect(ota.phase, OtaPhase.failed);
  });
  test('withdrawn patch does not show a successful installation', () async {
    final gateway = FakeOtaGateway()
      ..status = UpdateStatus.outdated
      ..downloadFailure = const UpdateException(
          message: 'withdrawn', reason: UpdateFailureReason.noUpdate);
    final ota = OtaController(gateway: gateway);
    addTearDown(ota.dispose);
    await ota.check();
    await ota.download();
    expect(ota.phase, OtaPhase.current);
  });
  test('failed download supports checking and retrying', () async {
    final gateway = FakeOtaGateway()
      ..status = UpdateStatus.outdated
      ..downloadFailure = const UpdateException(
          message: 'offline', reason: UpdateFailureReason.downloadFailed);
    final ota = OtaController(gateway: gateway);
    addTearDown(ota.dispose);
    await ota.check();
    await ota.download();
    expect(ota.phase, OtaPhase.failed);
    gateway.downloadFailure = null;
    await ota.check();
    await ota.download();
    expect(ota.phase, OtaPhase.ready);
  });
  testWidgets('update sheet offers download then explains full-app restart',
      (tester) async {
    final gateway = FakeOtaGateway()..status = UpdateStatus.outdated;
    final ota = OtaController(gateway: gateway);
    addTearDown(ota.dispose);
    await ota.check();
    await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: UpdateSheet(controller: ota))));
    expect(find.text('下载更新'), findsOneWidget);
    await tester.tap(find.text('下载更新'));
    await tester.pumpAndSettle();
    expect(find.text('更新已下载，下次打开时生效'), findsOneWidget);
    expect(find.textContaining('完全关闭'), findsOneWidget);
    expect(find.text('下载更新'), findsNothing);
  });
}
