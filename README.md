# AI Gallery

Flutter UI with native iOS and Android photo search. Version 0.2.0 migrates the working SwiftUI flow; the previous project remains in `../ai-gallery` for reference.

## Android Beta

Early Android builds are published as prereleases on [GitHub Releases](https://github.com/bigwolftime/ai-gallery/releases). The public Beta uses application ID `net.zonheng.aigallery` and a production signing key. It installs separately from the older `com.aigallery.app` test build; their models and photo indexes are stored separately.

Android 8.0 or newer with a 64-bit ARM or x86 processor is required. First setup downloads approximately 485 MB of model data. The interface is Simplified Chinese and search accepts Chinese and English descriptions. Analysis currently requires keeping the app open. This is an early Beta tested on an Android emulator; physical-device performance and sharing behavior still need broader testing.

[Privacy policy](docs/privacy-policy.md) · [Report a problem](https://github.com/bigwolftime/ai-gallery/issues) · [Distribution and build instructions](docs/store-publishing.md)

Source code is licensed under Apache-2.0. Third-party runtimes and model data retain their respective notices; see [NOTICE](NOTICE).

## Responsibilities

- `lib/src/gallery_page.dart`: gallery, detail preview, multi-select, sharing, fixed bottom search field, analysis confirmation and progress.
- `lib/src/gallery_controller.dart`: initialization, search-before-index prompt, manual incremental analysis, error handling and selection.
- `lib/src/search_window.dart`: same initial score-gap rule as SwiftUI (median/MAD, 0.02 minimum gap); each expansion adds 15 ordered candidates without rerunning inference.
- `packages/ai_gallery_native/lib`: typed MethodChannel/EventChannel contract. Dart receives identifiers, scores, image bytes and progress, not model weights or vectors.
- `packages/ai_gallery_native/ios/Classes`: PhotoKit, LiteRT-LM Swift actors, JSON index and iOS share sheet.
- `packages/ai_gallery_native/android/src/main/kotlin`: MediaStore permissions, bounded image decoding, LiteRT-LM worker, SQLite vector index and Android share intent.

Inference and image decoding do not execute on Flutter's UI isolate. Android model calls are serialized on a worker and thumbnails use a separate bounded pool. iOS inference uses the SDK's embedding actor. Analysis currently runs while the app is active; background scheduling is a separate future feature.

## Behavior retained

- Load accessible system photos; support selected-photo permission scopes.
- Download and verify the model on first use, then initialize it and offer analysis.
- Choosing "暂不" dismisses the startup prompt. Searching without an index offers analysis again.
- Manual analysis is the first action in Settings. It uses the shared gallery controller, reloads the current library and skips successful records for the current model version.
- Long press a photo to enter selection, then tap other photos to select them; Done exits selection. The homepage no longer has a Select or Analyze action.
- Query/image embeddings use 256 dimensions, L2 normalization and 70 vision tokens.
- Search returns scores; Flutter cuts the initial list at a significant score gap. Without a gap all candidates remain visible, as in the previous implementation.
- View details, zoom, select one or several photos, share through the system sheet. iOS supplies individual JPEG-backed image items and image previews instead of file URLs; Android uses image MIME types and SEND_MULTIPLE. Missing/unreadable selections fail explicitly instead of silently sharing fewer photos.
- Clear the query to return to the photo library.
- iOS uses real Gaussian backdrop blur in the floating search dock and update dialogs, plus translucent Cupertino navigation. Thin tints reveal the photos scrolling underneath, without drop shadows or decorative borders. Settings cards share the same material; high contrast uses opaque surfaces. The dock stays above the keyboard and reserves measured scroll padding for the last photo.
- Settings offers a persisted system/dark/light theme choice. Gallery chrome, placeholders and dialogs adapt to both themes. Checking updates from settings only opens a wide dialog for available or pending updates.
- Keep the search bar above the keyboard. Use "收起键盘", outside touch or a gallery drag to dismiss it without losing the query.
- Fade in newly mounted photo tiles, animate selection feedback and resize the action panel; respect the system reduced-motion setting.

Score gaps are a relative presentation heuristic, not a probability of correctness. Existing deleted-photo index records are not automatically purged by this migration; searches only return accessible current assets.

## Model and data compatibility

Both platforms use LiteRT-LM 0.18.0. Model weights are no longer bundled: `assets/models/model-manifest.json` identifies the Hugging Face artifact, with a verified Qiniu CDN mirror for the current model added in Dart. Before a needed download, the shared downloader concurrently samples 256 KiB per source, selects the faster transfer, and falls back with Range resume on failure. It supports pause/retry, verifies exact byte length and SHA-256 on a separate isolate, then atomically activates the file in persistent native-managed storage. Future launches reuse it offline without probing. Detailed hosting requirements and remote-manifest setup are in [docs/model-delivery.md](docs/model-delivery.md).

iOS retains Bundle ID `com.aigallery.app`, model index version `embeddinggemma-2-256-v1`, and `Application Support/AIGallery/photo-embeddings.json`. Cover-installing with the same signing identity and effective Bundle ID preserves old vectors. Removing the app or changing the signing tool's effective Bundle ID does not preserve the sandbox.

Independent model downloads and full-package version checks are implemented. The new Android/iOS baseline is `0.4.4+8`, including APK update validation and iOS SideStore download guidance. Deployment instructions are in [docs/ota-updates.md](docs/ota-updates.md) and [docs/app-updates.md](docs/app-updates.md). Native SDK, permission or plugin changes require a new IPA/APK. Native runtimes only load a downloaded file after the downloader has verified it.

## Build

Use the existing Flutter 3.41.9 SDK. Do not duplicate it. On this Mac, Gradle runs with the installed JDK 21 and complete NDK 27:

```sh
flutter pub get
flutter analyze
flutter test
flutter build ios --no-codesign
JAVA_HOME=/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home flutter build apk --release
```

Android Kotlin 2.4.0 is required by LiteRT-LM 0.18.0 metadata. Android supports arm64/x86_64 and minimum API 26; iOS minimum is 15. Native plugin declarations are in the plugin pubspec and podspec. The iOS project opens via `ios/Runner.xcworkspace`.

`dist/AI-Gallery-Flutter-unsigned.ipa` is for re-signing with SideStore/iloader. `dist/AI-Gallery-Flutter.apk` uses the local Android debug signing key for internal testing, not store publishing.

For OTA/full-package update testing install `dist/AI-Gallery-OTA-0.4.4-unsigned.ipa` (iOS) or `dist/AI-Gallery-OTA-0.4.4.apk` (Android). These preserved baseline packages contain the Shorebird updater and no model weights. Android 0.4.1 crashes on embedding calls and needs the new APK, rather than a Dart patch. The old ordinary Flutter packages cannot receive patches. Cover-install using the same signing identity and effective app ID; OTA does not renew SideStore signing. Current artifact hashes and download URLs are generated in `dist/app-updates/releases.json`; older baseline receipts remain in `dist/`.

## Validation

Flutter analysis and automated tests cover permission-denied recovery, analysis prompts after skipping, incremental workflow, failure recovery, score-gap selection, repeated expansion, detail navigation, sharing and platform-codec decoding. Native iOS and Android builds additionally validate SDK linking and plugin compilation. Download tests cover fresh transfers, Range resume, servers ignoring Range, incorrect ranges, hash failures, interrupted transfers, pause/resume and offline reuse. Actual model speed/accuracy, photo permissions and system share targets still require physical-device testing.

After each Android release build, run `python3 scripts/test_android_runtime.py <apk-path>`. It inspects the final optimized DEX for the input classes, constructors and accessors used by LiteRT-LM's JNI, plus the embedding response constructor/accessor. The native plugin exports consumer rules to preserve these SDK names; R8 remains enabled for the rest of the app.

## Image sharing validation

Version 0.4.1+5 changes native sharing and requires covering installation of the new base IPA/APK; Dart OTA patches cannot replace the old native file-URL sharing implementation. Keep the same effective app ID and signing identity to retain the downloaded model, settings and photo index.

`python3 scripts/test_ios_share.py` uses real UIKit via Mac Catalyst to verify three separate image items, JPEG type information, decodable previews and invalid-image rejection. Flutter regressions additionally verify multiple identifiers across the native channel and selection/error recovery. WeChat's actual received-image count and rendering still need physical-device testing; receiving extensions may impose their own limits.
