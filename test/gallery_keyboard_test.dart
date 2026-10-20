import 'ota_test.dart' show testOtaController;
import 'package:ai_gallery/src/gallery_controller.dart';
import 'package:ai_gallery/src/gallery_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'gallery_test.dart' show FakeNative, FakeService;

void main() {
  for (final size in [const Size(390, 844), const Size(320, 568)]) {
    testWidgets(
        'keyboard keeps search accessible at $size; dismissal retains text',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetViewInsets);
      final native = FakeNative()..offered = false;
      final controller =
          GalleryController(service: FakeService(native: native));
      addTearDown(controller.dispose);
      await tester.pumpWidget(MaterialApp(
          theme: ThemeData(platform: TargetPlatform.iOS),
          home: GalleryPage(
              controller: controller, otaController: testOtaController())));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '还没写完的搜索词');
      final keyboardHeight = size.height > 600 ? 300.0 : 216.0;
      tester.view.viewInsets = FakeViewPadding(bottom: keyboardHeight);
      await tester.pumpAndSettle();

      // The input must sit just above the keyboard, without applying its
      // height twice. Test both a modern iPhone and a compact screen.
      final inputBottom = tester.getBottomRight(find.byType(TextField)).dy;
      expect(inputBottom, lessThanOrEqualTo(size.height - keyboardHeight));
      expect(inputBottom, greaterThan(size.height - keyboardHeight - 32));
      expect(tester.getBottomRight(find.text('收起键盘')).dy,
          lessThan(size.height - keyboardHeight));
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('收起键盘'));
      tester.view.resetViewInsets();
      await tester.pumpAndSettle();
      final input = tester.widget<TextField>(find.byType(TextField));
      expect(input.focusNode!.hasFocus, isFalse);
      expect(input.controller!.text, '还没写完的搜索词');
      expect(tester.testTextInput.isVisible, isFalse);
      expect(native.searchCalls, 0);
      expect(find.text('收起键盘'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('iOS outside touch and gallery drag release search focus',
      (tester) async {
    final native = FakeNative()..offered = false;
    final controller = GalleryController(service: FakeService(native: native));
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
        theme: ThemeData(platform: TargetPlatform.iOS),
        home: GalleryPage(
            controller: controller, otaController: testOtaController())));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '月饼');
    await tester.pumpAndSettle();
    await tester.tap(find.text('AI Gallery'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byType(TextField)).focusNode!.hasFocus,
        isFalse);
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -120));
    await tester.pumpAndSettle();
    final input = tester.widget<TextField>(find.byType(TextField));
    expect(input.focusNode!.hasFocus, isFalse);
    expect(input.controller!.text, '月饼');
    expect(find.text('图片详情'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('reduced motion removes tile and selection animation delays',
      (tester) async {
    final native = FakeNative()..offered = false;
    final controller = GalleryController(service: FakeService(native: native));
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: GalleryPage(
                controller: controller, otaController: testOtaController()))));
    await tester.pumpAndSettle();
    await tester.longPress(find.byKey(const ValueKey('0')));
    await tester.pump();
    expect(controller.selected, contains('0'));
    expect(
        tester.widget<AnimatedScale>(find.byType(AnimatedScale).first).duration,
        Duration.zero);
    expect(find.text('已选择 1 张'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
