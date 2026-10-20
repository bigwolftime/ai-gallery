import 'package:ai_gallery/main.dart';
import 'package:ai_gallery/src/gallery_controller.dart';
import 'package:ai_gallery/src/ota/ota_controller.dart';
import 'package:ai_gallery/src/settings/app_settings.dart';
import 'package:ai_gallery/src/ui/ios_glass.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'gallery_test.dart' show FakeNative, FakeService;
import 'ota_test.dart' show FakeOtaGateway, FakeReleaseGateway;
import 'settings_test.dart' show MemorySettingsStore;

Future<GalleryController> mountGlassApp(WidgetTester tester) async {
  final gallery = GalleryController(
      service: FakeService(native: FakeNative()..offered = false));
  final settings = AppSettingsController(store: MemorySettingsStore());
  final ota =
      OtaController(releases: FakeReleaseGateway(), gateway: FakeOtaGateway());
  addTearDown(gallery.dispose);
  addTearDown(settings.dispose);
  addTearDown(ota.dispose);
  await tester
      .pumpWidget(AIGalleryApp(settings: settings, gallery: gallery, ota: ota));
  await tester.pumpAndSettle();
  return gallery;
}

void main() {
  testWidgets(
      'iOS navigation and theme control retain navigation/state behavior',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    await mountGlassApp(tester);
    expect(find.byType(CupertinoNavigationBar), findsOneWidget);
    expect(find.byType(IosGlassSurface), findsOneWidget);
    await tester.enterText(find.byType(TextField), '月饼');
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    expect(find.byType(CupertinoSlidingSegmentedControl<ThemeMode>),
        findsOneWidget);
    await tester.tap(find.text('深色'));
    await tester.pumpAndSettle();
    expect(
        Theme.of(tester.element(find.byType(CupertinoNavigationBar)))
            .brightness,
        Brightness.dark);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '月饼');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('high contrast removes blur from the glass surface',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
            data: const MediaQueryData(highContrast: true),
            child: const IosGlassSurface(child: Text('可读的文字')))));
    expect(find.byType(BackdropFilter), findsNothing);
    expect(find.text('可读的文字'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'last iOS photo remains reachable above the measured floating dock',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await mountGlassApp(tester);
    await tester.fling(
        find.byType(CustomScrollView), const Offset(0, -3000), 8000);
    await tester.pumpAndSettle();
    final photoBottom =
        tester.getBottomRight(find.byKey(const ValueKey('39'))).dy;
    final dockTop = tester.getTopLeft(find.byType(IosGlassSurface)).dy;
    expect(photoBottom, lessThanOrEqualTo(dockTop));
    await tester.longPress(find.byKey(const ValueKey('39')));
    await tester.pumpAndSettle();
    expect(find.text('已选择 1 张'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('Android keeps its material surfaces without glass filters',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    await mountGlassApp(tester);
    expect(find.byType(IosGlassSurface), findsNothing);
    expect(find.byType(CupertinoNavigationBar), findsNothing);
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    expect(find.byType(RadioListTile<ThemeMode>), findsNWidgets(3));
    expect(find.byType(BackdropFilter), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    debugDefaultTargetPlatformOverride = null;
  });
}
