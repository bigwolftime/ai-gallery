# AI Gallery — request for packaging draft

Status: draft, not submitted. Public tagged source, device testing and project-maturity evidence must be completed before requesting inclusion.

- Name: AI Gallery
- Application ID: net.zonheng.aigallery
- Source: https://github.com/bigwolftime/ai-gallery
- License: Apache-2.0 (third-party licenses preserved separately)
- Issue tracker: https://github.com/bigwolftime/ai-gallery/issues
- Intended source release: v0.4.5 / versionCode 9 (publish and pin the actual commit before submission)
- Suggested category: Graphics

## Purpose

Search a device's photo library with natural-language queries using a local multimodal embedding model. No account or remote photo-analysis server is required. Users can preview photos, long-press for multi-selection and share chosen images through the Android system share sheet. Query/image embeddings and the index stay on the device. Chinese and English search queries are supported; the current UI is Simplified Chinese.

The app's focus is local semantic search of an existing system photo library, without needing a self-hosted photo backend.

## Build

Ordinary Flutter 3.41.9, pinned framework commit 00b0c91f06209d9e4a41f71b7a512d6eb3b9c694; JDK 17+; Android SDK 36; NDK 27.0.12077973; arm64-v8a and x86_64; minSdk 26.

```sh
python3 scripts/build_android_store.py --channel fdroid --unsigned --flutter /path/to/flutter/bin/flutter
```

The script and build flags are part of the source release. Output: build/app/outputs/flutter-apk/app-release.apk. Android runtime dependencies are pinned through Gradle dependency versions and the Pub lockfile and use Google Maven / Maven Central. LiteRT-LM 0.18.0 declares Apache-2.0. The iOS framework directory is unrelated to this Android build and may be removed in the F-Droid build checkout during scanning.

## Network and model

The F-Droid build disables automatic update checks, Shorebird and APK self-installation. It uses the official Flutter engine; the install permission and update FileProvider are removed. Application updates are handled by F-Droid.

The model download is explicitly initiated by the user. URLs are the official Hugging Face conversion repository and the developer's Qiniu mirror; byte size and SHA-256 are checked before use. The model and its conversion are Apache-2.0. Model weights are data, not a downloaded native runtime. The app does not require an account and works offline after model setup.

- Model: embeddinggemma-2-740m.litertlm
- Source: https://huggingface.co/litert-community/embeddinggemma-2-740m-litert-lm
- Bytes: 484622336
- SHA-256: e7a8a2204b91e0f96e92960e84a09a89212e1633dcb7575a9bf3378b4df77f4c
- Mirror: https://img.zonheng.net/embeddinggemma-2-740m.litertlm

Photos, queries and vectors are never uploaded by the app. A privacy policy is bundled and accessible in Settings; native runtime notices and model attribution are included. There are no advertising or analytics SDKs in the store build. Download providers can see ordinary network request metadata.

## Review status

Flutter regression tests, final package manifest/ELF checks and an emulator smoke test are recorded in the release receipt. Android GPU inference still needs physical-device validation. The project is new: first source commit is 2026-10-13. Real user feedback or the normal maintenance period must be documented for the inclusion-policy maturity requirement; no exception is asserted by this draft.

The sideload test edition has a different application ID (com.aigallery.app) and retains its own update system. It is not the APK requested for F-Droid.
