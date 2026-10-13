import 'dart:async';
import 'package:ai_gallery/src/gallery_controller.dart';
import 'package:ai_gallery/src/gallery_page.dart';
import 'package:ai_gallery/src/native_service.dart';
import 'package:ai_gallery/src/search_window.dart';
import 'package:ai_gallery_native/ai_gallery_native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeNative extends AIGalleryNative {
  List<GalleryPhoto> photos =
      List.generate(40, (i) => GalleryPhoto(id: '$i', uri: 'ph://$i'));
  final indexed = <String>{};
  bool offered = true;
  bool fail = false;
  int analyzed = 0;
  int searchCalls = 0;
  List<String> shared = [];
  @override
  Stream<AnalysisProgress> get analysisProgress => const Stream.empty();
  @override
  Future<void> initializeModel(
      {String? modelPath, String? indexVersion}) async {}
  @override
  Future<List<GalleryPhoto>> loadPhotos() async => photos;
  @override
  Future<bool> shouldOfferAnalysis() async => offered;
  @override
  Future<void> dismissAnalysisPrompt() async {
    offered = false;
  }

  @override
  Future<bool> hasIndexedPhotos(List<String> ids) async =>
      ids.any(indexed.contains);
  @override
  Future<AnalysisSummary> analyzePhotos(List<String> ids) async {
    final pending = ids.where((id) => !indexed.contains(id)).toList();
    indexed.addAll(pending);
    analyzed += pending.length;
    return AnalysisSummary(
        processed: pending.length, succeeded: pending.length);
  }

  @override
  Future<List<SearchHit>> search(String query, {int limit = 0}) async {
    searchCalls++;
    if (fail) throw PlatformException(code: 'INFERENCE', message: 'failed');
    return [
      SearchHit(photo: photos.first, score: .82),
      for (var i = 1; i < photos.length; i++)
        SearchHit(photo: photos[i], score: .77 - i * .001)
    ];
  }

  @override
  Future<Uint8List?> loadThumbnail(String id) async => null;
  @override
  Future<Uint8List?> loadImage(String id) async => null;
  @override
  Future<void> sharePhotos(List<String> ids) async {
    shared = ids;
  }
}

class FakeService extends GalleryNativeService {
  FakeService({required super.native});
  @override
  Future<bool> modelIsAvailable() async => true;
  @override
  Future<void> initializeModel() => native.initializeModel();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('missing model requires explicit download before analysis or search',
      () async {
    final native = FakeNative();
    final service = DownloadRequiredService(native: native);
    final controller = GalleryController(service: service);
    addTearDown(controller.dispose);
    await controller.start();
    expect(controller.needsModelDownload, true);
    expect(controller.ready, false);
    expect(controller.promptRequested, false);
    await controller.downloadModel();
    expect(controller.ready, true);
    expect(controller.needsModelDownload, false);
    expect(controller.promptRequested, true);
  });
  group('score windows', () {
    test('mooncake isolated top result does not fill to fifteen', () {
      expect(SearchWindow.initialCount([.82, .77, .765, .76, .754]), 1);
    });
    test('twenty strong candidates are retained before the gap', () {
      expect(
          SearchWindow.initialCount(
              [...List.filled(20, .82), ...List.filled(40, .7)]),
          20);
    });
    test('uniform/equal and small sets have no fabricated boundary', () {
      expect(SearchWindow.initialCount([]), 0);
      expect(SearchWindow.initialCount([.82]), 1);
      expect(SearchWindow.initialCount(List.filled(40, .7)), 40);
      expect(SearchWindow.initialCount([.8, .79, .78, .77]), 4);
    });
    test('each expansion appends fifteen and clamps to the end', () {
      expect(SearchWindow.expand(1, 40), 16);
      expect(SearchWindow.expand(16, 40), 31);
      expect(SearchWindow.expand(31, 40), 40);
      expect(SearchWindow.expand(40, 40), 40);
    });
  });
  test('declining startup never blocks a later search prompt', () async {
    final native = FakeNative();
    final controller = GalleryController(service: FakeService(native: native));
    addTearDown(controller.dispose);
    await controller.start();
    expect(controller.promptRequested, isTrue);
    await controller.answerPrompt(false);
    expect(controller.promptRequested, isFalse);
    await controller.search('月饼');
    expect(controller.promptRequested, isTrue);
    expect(native.searchCalls, 0);
    await controller.answerPrompt(true);
    expect(native.searchCalls, 1);
    expect(controller.visibleCount, 1);
    expect(controller.hits.length, 40);
    controller.expand();
    expect(controller.visibleCount, 16);
    controller.expand();
    expect(controller.visibleCount, 31);
    controller.expand();
    expect(controller.visibleCount, 40);
    expect(controller.hasMore, isFalse);
  });
  test(
      'manual analysis refreshes the library and empty search restores browsing',
      () async {
    final native = FakeNative()..offered = false;
    final controller = GalleryController(service: FakeService(native: native));
    addTearDown(controller.dispose);
    await controller.start();
    await controller.analyze();
    native.photos = [
      ...native.photos,
      const GalleryPhoto(id: 'new', uri: 'ph://new')
    ];
    await controller.analyze();
    expect(native.analyzed, 41);
    expect(controller.photos.length, 41);
    await controller.search('月饼');
    controller.select('0');
    await controller.share();
    expect(native.shared, ['0']);
    await controller.search('   ');
    expect(controller.visibleCount, 41);
    expect(controller.selected, isEmpty);
  });
  test(
      'inference failure clears loading without replacing the last successful search',
      () async {
    final native = FakeNative()..offered = false;
    native.indexed.add('0');
    final controller = GalleryController(service: FakeService(native: native));
    addTearDown(controller.dispose);
    await controller.start();
    await controller.search('月饼');
    native.fail = true;
    await controller.search('猫');
    expect(controller.searching, isFalse);
    expect(controller.error, contains('failed'));
    expect(controller.visibleCount, 1);
  });
  testWidgets('search, expand, detail and multiselect sharing are reachable',
      (tester) async {
    final native = FakeNative()..offered = false;
    native.indexed.add('0');
    final controller = GalleryController(service: FakeService(native: native));
    addTearDown(controller.dispose);
    await tester
        .pumpWidget(MaterialApp(home: GalleryPage(controller: controller)));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '月饼');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(find.text('0.82'), findsOneWidget);
    expect(controller.visibleCount, 1);
    await tester.tap(find.text('扩大搜索范围 · 再看 15 张'));
    await tester.pumpAndSettle();
    expect(controller.visibleCount, 16);
    await tester.tap(find.byKey(const ValueKey('0')));
    await tester.pumpAndSettle();
    expect(find.text('图片详情'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('选择'), findsNothing);
    expect(find.byTooltip('分析照片'), findsNothing);
    await tester.longPress(find.byKey(const ValueKey('0')));
    // Wait for the selection action panel to finish its entrance animation.
    await tester.pumpAndSettle();
    await tester.tap(find.text('分享'));
    await tester.pumpAndSettle();
    expect(native.shared, ['0']);
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    expect(controller.selectionMode, isFalse);
    expect(controller.selected, isEmpty);
  });
  test('native channel decodes typed thumbnails, scores and analysis summaries',
      () async {
    const channel = MethodChannel('ai_gallery/native');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'loadThumbnail') return Uint8List.fromList([1, 2, 3]);
      if (call.method == 'analyzePhotos') {
        return {'processed': 2, 'succeeded': 1, 'failed': 1};
      }
      if (call.method == 'search') {
        return [
          {
            'photo': {'id': 'p', 'uri': 'ph://p'},
            'score': .82
          }
        ];
      }
      return null;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
    final native = AIGalleryNative();
    expect(await native.loadThumbnail('p'), [1, 2, 3]);
    expect((await native.analyzePhotos(['p'])).failed, 1);
    expect((await native.search('月饼')).single.score, .82);
  });
}

class DownloadRequiredService extends FakeService {
  DownloadRequiredService({required super.native});
  bool downloaded = false;
  @override
  Future<bool> modelIsAvailable() async => downloaded;
  @override
  int get modelBytes => 484622336;
  @override
  Future<void> initializeModel() async {
    downloaded = true;
    await native.initializeModel();
  }
}
