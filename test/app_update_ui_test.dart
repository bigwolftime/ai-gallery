import 'package:ai_gallery/main.dart';
import 'package:ai_gallery/src/gallery_controller.dart';
import 'package:ai_gallery/src/ota/app_release.dart';
import 'package:ai_gallery/src/ota/ota_controller.dart';
import 'package:ai_gallery/src/ota/update_sheet.dart';
import 'package:ai_gallery/src/settings/app_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'gallery_test.dart' show FakeNative, FakeService;
import 'ota_test.dart' show FakeOtaGateway, FakeReleaseGateway;
import 'settings_test.dart' show MemorySettingsStore;
import 'app_release_test.dart' show apkMap;

void main() {
  testWidgets(
      'homepage exposes a dismissible base update and opens the update dialog',
      (tester) async {
    final releases = FakeReleaseGateway()
      ..release = AppRelease.fromMap(apkMap());
    final ota = OtaController(gateway: FakeOtaGateway(), releases: releases);
    final gallery = GalleryController(
        service: FakeService(native: FakeNative()..offered = false));
    final settings = AppSettingsController(store: MemorySettingsStore());
    addTearDown(ota.dispose);
    addTearDown(gallery.dispose);
    addTearDown(settings.dispose);
    await tester.pumpWidget(
        AIGalleryApp(ota: ota, gallery: gallery, settings: settings));
    await tester.pumpAndSettle();
    expect(find.text('发现新版本 0.4.4'), findsOneWidget);
    await tester.tap(find.text('更新'));
    await tester.pumpAndSettle();
    expect(find.byType(UpdateSheet), findsOneWidget);
    expect(find.text('下载 / 继续下载'), findsOneWidget);
    expect(find.textContaining('不要卸载'), findsOneWidget);
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('稍后更新'));
    await tester.pumpAndSettle();
    expect(find.text('发现新版本 0.4.4'), findsNothing);
  });
  for (final brightness in Brightness.values) {
    testWidgets('full update dialog fits a compact screen in $brightness',
        (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final releases = FakeReleaseGateway()
        ..release = AppRelease.fromMap(apkMap());
      final ota = OtaController(gateway: FakeOtaGateway(), releases: releases);
      addTearDown(ota.dispose);
      await ota.check();
      await tester.pumpWidget(MaterialApp(
          theme: ThemeData(brightness: brightness),
          home: Builder(
              builder: (context) => Scaffold(
                  body: TextButton(
                      onPressed: () =>
                          showUpdateDialog(context, controller: ota),
                      child: const Text('open'))))));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(
          tester.getSize(find.byType(Dialog)).width, greaterThanOrEqualTo(280));
      await tester.ensureVisible(find.text('下载 / 继续下载'));
      expect(tester.takeException(), isNull);
    });
  }
}
