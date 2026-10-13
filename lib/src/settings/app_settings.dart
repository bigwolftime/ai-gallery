import 'dart:convert';
import 'dart:io';
import 'package:ai_gallery_native/ai_gallery_native.dart';
import 'package:flutter/material.dart';

abstract interface class SettingsStore {
  Future<ThemeMode> readTheme();
  Future<void> writeTheme(ThemeMode mode);
}

/// Reuse the native persistent directory API; adding a preferences plugin would
/// require a new base IPA/APK. Settings live beside models, not inside them.
class FileSettingsStore implements SettingsStore {
  FileSettingsStore({Future<Directory> Function()? directory})
      : _directory = directory ?? _appDirectory;
  final Future<Directory> Function() _directory;
  static const _fileName = 'settings.json';

  static Future<Directory> _appDirectory() async =>
      Directory(await AIGalleryNative().getModelDirectory()).parent;

  @override
  Future<ThemeMode> readTheme() async {
    try {
      final file = File('${(await _directory()).path}/$_fileName');
      if (!await file.exists()) return ThemeMode.system;
      final data =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      if (data['schemaVersion'] != 1) return ThemeMode.system;
      return ThemeMode.values.firstWhere((mode) => mode.name == data['theme'],
          orElse: () => ThemeMode.system);
    } catch (_) {
      // A missing/corrupt preference must never block the first app frame.
      return ThemeMode.system;
    }
  }

  @override
  Future<void> writeTheme(ThemeMode mode) async {
    final directory = await _directory();
    await directory.create(recursive: true);
    final file = File('${directory.path}/$_fileName.partial');
    await file.writeAsString(
        jsonEncode({'schemaVersion': 1, 'theme': mode.name}),
        flush: true);
    await file.rename('${directory.path}/$_fileName');
  }
}

class AppSettingsController extends ChangeNotifier {
  AppSettingsController({SettingsStore? store})
      : _store = store ?? FileSettingsStore();
  final SettingsStore _store;
  ThemeMode themeMode = ThemeMode.system;
  String? error;
  Future<void> _writes = Future.value();
  int _generation = 0;
  bool _disposed = false;

  Future<void> load() async {
    final generation = _generation;
    final restored = await _store.readTheme();
    // Do not overwrite a choice made while the initial disk read was pending.
    if (_disposed || generation != _generation) return;
    themeMode = restored;
    notifyListeners();
  }

  Future<void> setTheme(ThemeMode mode) async {
    if (_disposed) return;
    final generation = ++_generation;
    themeMode = mode;
    error = null;
    notifyListeners();
    // Serialize rapid changes so the last visible choice is the last saved one.
    final write = _writes.then((_) => _store.writeTheme(mode));
    _writes = write.catchError((Object _) {});
    try {
      await write;
    } catch (_) {
      if (!_disposed && generation == _generation) {
        error = '主题已切换，但未能保存，请重新选择一次。';
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

class AppSettingsScope extends InheritedNotifier<AppSettingsController> {
  const AppSettingsScope(
      {super.key,
      required AppSettingsController controller,
      required super.child})
      : super(notifier: controller);

  static AppSettingsController of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppSettingsScope>()!.notifier!;
}
