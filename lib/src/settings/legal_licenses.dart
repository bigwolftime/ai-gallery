import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

bool _registered = false;

/// Flutter collects Dart package licenses; add the separately downloaded model
/// and the native runtime's notices without initializing any native service.
void registerLegalLicenses() {
  if (_registered) return;
  _registered = true;
  LicenseRegistry.addLicense(() async* {
    final notice = await rootBundle.loadString('assets/legal/NOTICE.txt');
    final license = await rootBundle.loadString('assets/legal/Apache-2.0.txt');
    yield LicenseEntryWithLineBreaks(
        ['AI Gallery', 'EmbeddingGemma 2'], '$notice\n\n$license');
    final native =
        await rootBundle.loadString('assets/legal/LiteRT-LM-LICENSE.txt');
    yield LicenseEntryWithLineBreaks(['LiteRT-LM native runtime'], native);
  });
}
