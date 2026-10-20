import 'package:ai_gallery/main.dart';
import 'package:ai_gallery/src/gallery_controller.dart';
import 'package:ai_gallery/src/ota/app_distribution.dart';
import 'package:ai_gallery/src/ota/ota_controller.dart';
import 'package:ai_gallery/src/settings/app_settings.dart';
import 'package:ai_gallery/src/settings/legal_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'gallery_test.dart' show FakeNative, FakeService;
import 'ota_test.dart' show FakeOtaGateway, FakeReleaseGateway;
import 'settings_test.dart' show MemorySettingsStore;

void main() {
  for (final channel in ['fdroid', 'play']) {
    testWidgets(
        '$channel startup stays offline and settings opens only its store',
        (tester) async {
      final releases = FakeReleaseGateway();
      // Asset reads use real I/O; finish them outside the widget fake clock.
      await tester.runAsync(() async {
        for (final file in [
          'privacy.txt',
          'NOTICE.txt',
          'Apache-2.0.txt',
          'LiteRT-LM-LICENSE.txt'
        ]) {
          await rootBundle.loadString('assets/legal/$file');
        }
      });
      final patches = FakeOtaGateway();
      final ota = OtaController(
          distribution: AppDistribution(
              channel: channel, listingUrl: 'https://example.com/store'),
          gateway: patches,
          releases: releases);
      final settings = AppSettingsController(store: MemorySettingsStore());
      final gallery = GalleryController(
          service: FakeService(native: FakeNative()..offered = false));
      addTearDown(ota.dispose);
      addTearDown(settings.dispose);
      addTearDown(gallery.dispose);
      await tester.pumpWidget(
          AIGalleryApp(settings: settings, gallery: gallery, ota: ota));
      await tester.pumpAndSettle();
      expect(releases.infoReads, 0);
      expect(releases.checks, 0);
      expect(patches.checks, 0);
      await tester.tap(find.text('设置'));
      await tester.pumpAndSettle();
      final link = find.text('前往 ${ota.distribution.storeName} 更新');
      await tester.ensureVisible(link);
      await tester.tap(link);
      await tester.pumpAndSettle();
      expect(releases.opens, 1);
      expect(releases.checks, 0);
      expect(patches.checks, 0);
      expect(find.byType(Dialog), findsNothing);
      final privacy = find.text('隐私政策');
      await tester.ensureVisible(privacy);
      await tester.tap(privacy);
      await tester.pump();
      await tester
          .runAsync(() => rootBundle.loadString('assets/legal/privacy.txt'));
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(LegalPage), findsOneWidget);
      expect(find.textContaining('不会将照片、搜索词或向量索引上传'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      final licenses = find.text('开源许可');
      await tester.ensureVisible(licenses);
      await tester.tap(licenses);
      await tester.pump();
      final entries =
          await tester.runAsync(() => LicenseRegistry.licenses.toList());
      expect(
          entries!.any((entry) => entry.packages.contains('EmbeddingGemma 2')),
          true);
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(LicensePage), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
