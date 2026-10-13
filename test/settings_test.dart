import 'dart:async';
import 'dart:io';
import 'package:ai_gallery/main.dart';
import 'package:ai_gallery/src/gallery_controller.dart';
import 'package:ai_gallery/src/gallery_page.dart';
import 'package:ai_gallery/src/ota/ota_controller.dart';
import 'package:ai_gallery/src/ota/update_sheet.dart';
import 'package:ai_gallery/src/settings/app_settings.dart';
import 'package:ai_gallery/src/settings/settings_page.dart';
import 'package:ai_gallery_native/ai_gallery_native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shorebird_code_push/shorebird_code_push.dart';
import 'gallery_test.dart' show FakeNative, FakeService;
import 'ota_test.dart' show FakeOtaGateway;

class MemorySettingsStore implements SettingsStore {
  ThemeMode saved = ThemeMode.system;
  final writes = <ThemeMode>[];
  Completer<ThemeMode>? pendingRead;
  bool failWrite = false;
  @override
  Future<ThemeMode> readTheme() async => pendingRead?.future ?? saved;
  @override
  Future<void> writeTheme(ThemeMode mode) async {
    if (failWrite) throw const FileSystemException('not writable');
    saved = mode;
    writes.add(mode);
  }
}

Future<void> mountApp(WidgetTester tester,
    {required AppSettingsController settings,
    required OtaController ota}) async {
  final native = FakeNative()..offered = false;
  final gallery = GalleryController(service: FakeService(native: native));
  addTearDown(gallery.dispose);
  await tester
      .pumpWidget(AIGalleryApp(settings: settings, gallery: gallery, ota: ota));
  await tester.pumpAndSettle();
}

void main() {
  test('theme file survives controller recreation; malformed data uses system',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('gallery-settings-');
    addTearDown(() => directory.delete(recursive: true));
    final store = FileSettingsStore(directory: () async => directory);
    expect(await store.readTheme(), ThemeMode.system);
    final settings = AppSettingsController(store: store);
    await settings.setTheme(ThemeMode.dark);
    settings.dispose();
    final restored = AppSettingsController(store: store);
    addTearDown(restored.dispose);
    await restored.load();
    expect(restored.themeMode, ThemeMode.dark);
    await File('${directory.path}/settings.json').writeAsString('broken json');
    expect(await store.readTheme(), ThemeMode.system);
  });

  test('late initial load does not override a new choice; writes keep order',
      () async {
    final store = MemorySettingsStore()..pendingRead = Completer<ThemeMode>();
    final settings = AppSettingsController(store: store);
    addTearDown(settings.dispose);
    final loading = settings.load();
    final first = settings.setTheme(ThemeMode.dark);
    final second = settings.setTheme(ThemeMode.light);
    store.pendingRead!.complete(ThemeMode.system);
    await Future.wait([loading, first, second]);
    expect(settings.themeMode, ThemeMode.light);
    expect(store.saved, ThemeMode.light);
    expect(store.writes, [ThemeMode.dark, ThemeMode.light]);
  });

  test('failed preference save can retry the same visible theme', () async {
    final store = MemorySettingsStore()..failWrite = true;
    final settings = AppSettingsController(store: store);
    addTearDown(settings.dispose);
    await settings.setTheme(ThemeMode.dark);
    expect(settings.themeMode, ThemeMode.dark);
    expect(settings.error, isNotNull);
    store.failWrite = false;
    await settings.setTheme(ThemeMode.dark);
    expect(store.saved, ThemeMode.dark);
    expect(settings.error, isNull);
  });

  testWidgets('system brightness and explicit theme choices update both routes',
      (tester) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    final store = MemorySettingsStore();
    final settings = AppSettingsController(store: store);
    final ota = OtaController(gateway: FakeOtaGateway());
    addTearDown(settings.dispose);
    addTearDown(ota.dispose);
    await mountApp(tester, settings: settings, ota: ota);
    Brightness galleryBrightness() =>
        Theme.of(tester.element(find.byType(GalleryPage))).brightness;
    expect(settings.themeMode, ThemeMode.system);
    expect(galleryBrightness(), Brightness.light);
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    await tester.pumpAndSettle();
    expect(galleryBrightness(), Brightness.dark);
    await tester.enterText(find.byType(TextField), '月饼');
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsPage), findsOneWidget);
    await tester.tap(find.text('浅色'));
    await tester.pumpAndSettle();
    expect(store.saved, ThemeMode.light);
    expect(Theme.of(tester.element(find.byType(SettingsPage))).brightness,
        Brightness.light);
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    await tester.pumpAndSettle();
    await tester.tap(find.text('深色'));
    await tester.pumpAndSettle();
    expect(Theme.of(tester.element(find.byType(SettingsPage))).brightness,
        Brightness.dark);
    await tester.tap(find.text('跟随系统'));
    await tester.pumpAndSettle();
    expect(Theme.of(tester.element(find.byType(SettingsPage))).brightness,
        Brightness.light);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(galleryBrightness(), Brightness.light);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '月饼');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('saved manual theme is restored before using settings',
      (tester) async {
    final store = MemorySettingsStore()..saved = ThemeMode.dark;
    final settings = AppSettingsController(store: store);
    final ota = OtaController(gateway: FakeOtaGateway());
    addTearDown(settings.dispose);
    addTearDown(ota.dispose);
    await mountApp(tester, settings: settings, ota: ota);
    expect(Theme.of(tester.element(find.byType(GalleryPage))).brightness,
        Brightness.dark);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'first settings action analyzes incrementally through shared gallery',
      (tester) async {
    final native = FakeNative()..offered = false;
    native.indexed.addAll(native.photos.take(20).map((photo) => photo.id));
    final gallery = GalleryController(service: FakeService(native: native));
    final settings = AppSettingsController(store: MemorySettingsStore());
    final ota = OtaController(gateway: FakeOtaGateway());
    addTearDown(gallery.dispose);
    addTearDown(settings.dispose);
    addTearDown(ota.dispose);
    await tester.pumpWidget(
        AIGalleryApp(settings: settings, gallery: gallery, ota: ota));
    await tester.pumpAndSettle();
    expect(find.text('选择'), findsNothing);
    expect(find.byTooltip('分析照片'), findsNothing);
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    expect(
        (tester.widget<ListTile>(find.byType(ListTile).first).title as Text)
            .data,
        '分析照片');
    await tester.tap(find.text('分析照片'));
    await tester.pumpAndSettle();
    expect(native.analyzed, 20);
    native.photos = [
      ...native.photos,
      const GalleryPhoto(id: 'new', uri: 'ph://new')
    ];
    await tester.tap(find.text('分析照片'));
    await tester.pumpAndSettle();
    expect(native.analyzed, 21);
    expect(gallery.photos.length, 41);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(gallery.visibleCount, 41);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('up-to-date check stays in settings without opening a dialog',
      (tester) async {
    final gateway = FakeOtaGateway();
    final ota = OtaController(gateway: gateway);
    final settings = AppSettingsController(store: MemorySettingsStore());
    addTearDown(settings.dispose);
    addTearDown(ota.dispose);
    await mountApp(tester, settings: settings, ota: ota);
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('检查更新'));
    await tester.pumpAndSettle();
    expect(
        gateway.checks, 2); // Startup check plus the explicit settings check.
    expect(find.byType(Dialog), findsNothing);
    expect(find.text('当前应用已是最新版本'), findsWidgets);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets('available update dialog fits compact screen in ${mode.name}',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 568);
      tester.platformDispatcher.textScaleFactorTestValue = 1.4;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final gateway = FakeOtaGateway()..status = UpdateStatus.outdated;
      final ota = OtaController(gateway: gateway);
      final store = MemorySettingsStore()..saved = mode;
      final settings = AppSettingsController(store: store);
      addTearDown(settings.dispose);
      addTearDown(ota.dispose);
      await mountApp(tester, settings: settings, ota: ota);
      await tester.tap(find.text('设置'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('检查更新'), 150,
          scrollable: find.descendant(
              of: find.byType(SettingsPage),
              matching: find.byType(Scrollable)));
      await tester.tap(find.text('检查更新'));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsOneWidget);
      // Dialog includes the full-screen alignment and its insets. Measure the
      // visible content surface rather than that outer layout box.
      expect(tester.getSize(find.byType(UpdateSheet)).width, 280);
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('下载更新'));
      await tester.tap(find.text('下载更新'));
      await tester.pumpAndSettle();
      expect(gateway.downloads, 1);
      expect(find.text('待生效补丁：2'), findsOneWidget);
      expect(find.textContaining('完全关闭'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
