import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_gallery/main.dart';

void main() {
  testWidgets('permission denial leaves settings and retry reachable',
      (tester) async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const methods = MethodChannel('ai_gallery/native');
    const progress = MethodChannel('ai_gallery/progress');
    messenger.setMockMethodCallHandler(progress, (_) async => null);
    messenger.setMockMethodCallHandler(methods, (_) async {
      throw PlatformException(code: 'PHOTO_PERMISSION', message: '请允许访问照片');
    });
    await tester.pumpWidget(const AIGalleryApp());
    await tester.pumpAndSettle();
    expect(find.text('AI Gallery'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
    expect(find.text('打开权限设置'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    messenger.setMockMethodCallHandler(methods, null);
    messenger.setMockMethodCallHandler(progress, null);
  });
}
