import 'dart:io';
import 'package:ai_gallery/src/ota/app_distribution.dart';
import 'package:ai_gallery/src/ota/app_release.dart';
import 'package:ai_gallery/src/ota/ota_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'ota_test.dart' show FakeOtaGateway, FakeReleaseGateway;

void main() {
  for (final channel in ['fdroid', 'play']) {
    test(
        '$channel never checks or downloads direct updates, even with a working updater',
        () async {
      final patches = FakeOtaGateway();
      final releases = FakeReleaseGateway();
      final controller = OtaController(
          distribution: AppDistribution(channel: channel),
          gateway: patches,
          releases: releases);
      addTearDown(controller.dispose);
      expect(controller.automaticChecksAllowed, false);
      expect(controller.phase, OtaPhase.storeManaged);
      await controller.check();
      expect(releases.infoReads, 0);
      expect(releases.checks, 0);
      expect(patches.checks, 0);
      // Store restrictions apply to actions as well as the visible UI.
      controller.fullRelease = AppRelease(
          platform: 'android',
          channel: 'direct',
          version: '99',
          buildNumber: 99,
          kind: 'apk',
          url: Uri.parse('https://example.com/app.apk'));
      controller.phase = OtaPhase.available;
      await controller.download();
      controller.phase = OtaPhase.packageAvailable;
      await controller.downloadPackage();
      controller.packageFile = File('/unused.apk');
      controller.phase = OtaPhase.packageReady;
      await controller.installPackage();
      expect(patches.downloads, 0);
      expect(releases.installs, 0);
      expect(releases.validations, 0);
    });

    test('$channel only opens an explicit HTTPS store link after user action',
        () async {
      final releases = FakeReleaseGateway();
      final controller = OtaController(
          distribution: AppDistribution(
              channel: channel, listingUrl: 'https://example.com/store'),
          releases: releases);
      addTearDown(controller.dispose);
      expect(releases.opens, 0);
      await controller.openStore();
      expect(releases.opens, 1);
      expect(releases.lastOpened!.kind, 'store');
      expect(releases.lastOpened!.channel, channel);
      expect(releases.checks, 0);
      expect(controller.phase, OtaPhase.storeManaged);
    });
  }

  test(
      'store links reject unsafe or missing URLs; direct builds keep automatic checks',
      () async {
    expect(const AppDistribution().managedByStore, false);
    for (final url in ['', 'http://example.com', 'javascript:alert(1)']) {
      final releases = FakeReleaseGateway();
      final controller = OtaController(
          distribution: AppDistribution(channel: 'fdroid', listingUrl: url),
          releases: releases);
      addTearDown(controller.dispose);
      await controller.openStore();
      expect(releases.opens, 0);
    }
  });
}
