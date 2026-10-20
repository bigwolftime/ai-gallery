import 'dart:convert';
import '../downloads/download_artifact.dart';

class InstalledApp {
  const InstalledApp(
      {required this.platform,
      required this.channel,
      required this.version,
      required this.buildNumber,
      this.appId = 'com.aigallery.app'});
  final String platform;
  final String channel;
  final String version;
  final int buildNumber;
  final String appId;
  factory InstalledApp.fromMap(Map<Object?, Object?> map) {
    final platform = map['platform'] as String;
    final channel = const String.fromEnvironment('APP_DISTRIBUTION_CHANNEL',
                defaultValue: '')
            .isNotEmpty
        ? const String.fromEnvironment('APP_DISTRIBUTION_CHANNEL')
        : map['channel'] as String;
    final version = map['version'] as String;
    final build = (map['buildNumber'] as num).toInt();
    if (!['android', 'ios'].contains(platform) ||
        channel.isEmpty ||
        version.isEmpty ||
        build <= 0) {
      throw const FormatException('无法读取当前应用版本。');
    }
    return InstalledApp(
        platform: platform,
        channel: channel,
        version: version,
        buildNumber: build,
        // The stable source identity is unaffected by iOS re-signing suffixes.
        appId: const String.fromEnvironment('APP_APPLICATION_ID',
            defaultValue: 'com.aigallery.app'));
  }
}

class AppRelease {
  const AppRelease(
      {required this.platform,
      required this.channel,
      required this.version,
      required this.buildNumber,
      required this.kind,
      required this.url,
      this.notes = '',
      this.sha256,
      this.size});
  final String platform;
  final String channel;
  final String version;
  final int buildNumber;
  final String kind;
  final Uri url;
  final String notes;
  final String? sha256;
  final int? size;
  bool get isApk => kind == 'apk';
  DownloadArtifact get artifact => DownloadArtifact(
      urls: [url], sha256: sha256!, size: size!, extension: '.apk');

  factory AppRelease.fromMap(Map<String, dynamic> map) {
    final url = Uri.parse(map['url'] as String);
    final platform = map['platform'] as String;
    final channel = map['channel'] as String;
    final kind = map['kind'] as String;
    final version = map['version'] as String;
    final build = map['buildNumber'] as int;
    final hash = map['sha256'] as String?;
    final size = map['size'] as int?;
    final validKind =
        (platform == 'android' && channel == 'direct' && kind == 'apk') ||
            (platform == 'ios' && channel == 'sideload' && kind == 'ipa') ||
            (platform == 'android' &&
                ['play', 'store'].contains(channel) &&
                kind == 'store') ||
            (platform == 'ios' &&
                ['appstore', 'testflight'].contains(channel) &&
                kind == 'store');
    if (!validKind ||
        version.isEmpty ||
        build <= 0 ||
        url.scheme != 'https' ||
        url.host.isEmpty ||
        (kind == 'apk' &&
            (hash == null ||
                !RegExp(r'^[a-f0-9]{64}$').hasMatch(hash) ||
                size == null ||
                size <= 0))) {
      throw const FormatException('应用版本清单不兼容。');
    }
    return AppRelease(
        platform: platform,
        channel: channel,
        kind: kind,
        version: version,
        buildNumber: build,
        url: url,
        notes: map['notes'] as String? ?? '',
        sha256: hash,
        size: size);
  }
}

/// Match only the running platform/channel; a store build never selects an APK.
class AppReleaseManifest {
  const AppReleaseManifest(this.releases, {this.appId = 'com.aigallery.app'});
  final List<AppRelease> releases;
  final String appId;
  factory AppReleaseManifest.decode(String source,
      {String expectedAppId = 'com.aigallery.app'}) {
    final map = jsonDecode(source) as Map<String, dynamic>;
    if (map['schemaVersion'] != 1 || map['appId'] != expectedAppId) {
      throw const FormatException('应用版本清单不兼容。');
    }
    final releases = (map['releases'] as List)
        .map((value) =>
            AppRelease.fromMap(Map<String, dynamic>.from(value as Map)))
        .toList();
    final seen = <String>{};
    for (final release in releases) {
      if (!seen.add(
          '${release.platform}/${release.channel}/${release.buildNumber}')) {
        throw const FormatException('应用版本清单有重复版本。');
      }
    }
    return AppReleaseManifest(List.unmodifiable(releases),
        appId: expectedAppId);
  }
  AppRelease? newerThan(InstalledApp installed) {
    final latest = latestFor(installed);
    return latest != null && latest.buildNumber > installed.buildNumber
        ? latest
        : null;
  }

  AppRelease? latestFor(InstalledApp installed) {
    if (installed.appId != appId) return null;
    final candidates = releases
        .where((release) =>
            release.platform == installed.platform &&
            release.channel == installed.channel)
        .toList()
      ..sort((a, b) => b.buildNumber.compareTo(a.buildNumber));
    return candidates.isEmpty ? null : candidates.first;
  }
}
