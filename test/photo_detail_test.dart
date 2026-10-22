import 'dart:async';
import 'dart:typed_data';
import 'package:ai_gallery/src/gallery_controller.dart';
import 'package:ai_gallery/src/gallery_page.dart';
import 'package:ai_gallery_native/ai_gallery_native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'gallery_test.dart' show FakeNative, FakeService;

// A valid 1x1 PNG so Image.memory can decode the thumbnail/original.
final _png = Uint8List.fromList([
  0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00, 0x00, 0x0d, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1f, 0x15, 0xc4, 0x89, 0x00, 0x00, 0x00,
  0x0d, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9c, 0x63, 0xf8, 0xcf, 0xc0, 0xf0,
  0x1f, 0x00, 0x05, 0x00, 0x01, 0xff, 0x89, 0x99, 0x3d, 0x1d, 0x00, 0x00,
  0x00, 0x00, 0x49, 0x45, 0x4e, 0x44, 0xae, 0x42, 0x60, 0x82,
]);

class SlowOriginalNative extends FakeNative {
  final original = Completer<Uint8List?>();
  final progress = StreamController<ImageLoadProgress>.broadcast();
  @override
  Future<Uint8List?> loadThumbnail(String id) async => _png;
  @override
  Future<Uint8List?> loadImage(String id) => original.future;
  @override
  Stream<ImageLoadProgress> get imageLoadProgress => progress.stream;
}

Future<SlowOriginalNative> openDetail(
    WidgetTester tester, TargetPlatform platform) async {
  final native = SlowOriginalNative()..offered = false;
  final controller = GalleryController(service: FakeService(native: native));
  addTearDown(controller.dispose);
  addTearDown(native.progress.close);
  await tester.pumpWidget(MaterialApp(
      theme: ThemeData(platform: platform),
      home: PhotoDetailPage(
          hit: SearchHit(photo: native.photos.first, score: .82),
          controller: controller)));
  await tester.pump();
  return native;
}

void main() {
  testWidgets('thumbnail shows at once; slow iOS originals explain the wait',
      (tester) async {
    final native = await openDetail(tester, TargetPlatform.iOS);
    expect(find.byType(Image), findsOneWidget);
    expect(find.textContaining('iCloud'), findsNothing);
    await tester.pump(const Duration(milliseconds: 800));
    expect(find.text('正在获取原图，照片在 iCloud 中时需要先下载…'), findsOneWidget);
    native.progress.add(ImageLoadProgress(id: '0', fraction: .45));
    native.progress.add(ImageLoadProgress(id: 'other', fraction: .9));
    await tester.pump();
    expect(find.text('正在从 iCloud 下载原图 · 45%'), findsOneWidget);
    native.original.complete(_png);
    await tester.pump();
    expect(find.textContaining('iCloud'), findsNothing);
    expect(find.text('相似度 0.82'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Android wording never mentions iCloud', (tester) async {
    final native = await openDetail(tester, TargetPlatform.android);
    await tester.pump(const Duration(milliseconds: 800));
    expect(find.text('正在加载原图…'), findsOneWidget);
    native.original.complete(null);
    await tester.pump();
    expect(find.text('原图暂时无法读取'), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('failed iCloud original keeps the thumbnail and says why',
      (tester) async {
    final native = await openDetail(tester, TargetPlatform.iOS);
    native.original.completeError(Exception('offline'));
    await tester.pump();
    expect(find.text('原图暂时无法获取，请检查网络或 iCloud 设置'), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
