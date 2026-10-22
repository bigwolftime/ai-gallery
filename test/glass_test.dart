import 'package:ai_gallery/main.dart';
import 'package:ai_gallery/src/gallery_controller.dart';
import 'package:ai_gallery/src/ota/ota_controller.dart';
import 'package:ai_gallery/src/settings/app_settings.dart';
import 'package:ai_gallery/src/ui/glass.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

// The search dock is the glass surface that hosts the text field.
Finder get dock => find.ancestor(
    of: find.byType(TextField), matching: find.byType(GlassSurface));

void main() {
  // iOS and Android share one visual language; run the same checks on both.
  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets(
        '${platform.name}: shared glass chrome and theme control keep state',
        (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      await mountGlassApp(tester);
      expect(find.byType(GlassNavigationBar), findsOneWidget);
      expect(dock, findsOneWidget);
      expect(find.byType(CupertinoNavigationBar), findsNothing);
      expect(find.byType(AppBar), findsNothing);
      await tester.enterText(find.byType(TextField), '月饼');
      await tester.tap(find.text('设置'));
      await tester.pumpAndSettle();
      expect(find.byType(CupertinoSlidingSegmentedControl<ThemeMode>),
          findsOneWidget);
      expect(find.byType(RadioListTile<ThemeMode>), findsNothing);
      await tester.tap(find.text('深色'));
      await tester.pumpAndSettle();
      expect(
          Theme.of(tester.element(find.byType(GlassNavigationBar))).brightness,
          Brightness.dark);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
          '月饼');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets(
        '${platform.name}: last photo remains reachable above the floating dock',
        (tester) async {
      debugDefaultTargetPlatformOverride = platform;
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
      expect(photoBottom, lessThanOrEqualTo(tester.getTopLeft(dock).dy));
      await tester.longPress(find.byKey(const ValueKey('39')));
      await tester.pumpAndSettle();
      expect(find.text('已选择 1 张'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    });
  }

  testWidgets('high contrast removes blur from the glass surface',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
            data: const MediaQueryData(highContrast: true),
            child: const GlassSurface(child: Text('可读的文字')))));
    expect(find.byType(BackdropFilter), findsNothing);
    expect(find.text('可读的文字'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('navigation bar keeps status bar icons readable', (tester) async {
    for (final (brightness, expected) in [
      (Brightness.dark, Brightness.light),
      (Brightness.light, Brightness.dark),
    ]) {
      await tester.pumpWidget(MaterialApp(
          theme: ThemeData(brightness: brightness),
          home: const Scaffold(appBar: GlassNavigationBar(title: '图片详情'))));
      await tester.pumpAndSettle(); // let the theme animation finish
      final region = tester.widget<AnnotatedRegion<SystemUiOverlayStyle>>(
          find.descendant(
              of: find.byType(GlassNavigationBar),
              matching: find.byType(AnnotatedRegion<SystemUiOverlayStyle>)));
      expect(region.value.statusBarIconBrightness, expected);
    }
  });
}
