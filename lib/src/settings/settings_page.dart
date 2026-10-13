import 'dart:async';
import 'package:flutter/material.dart';
import '../gallery_controller.dart';
import '../ota/ota_controller.dart';
import '../ota/update_sheet.dart';
import 'app_settings.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.ota, required this.gallery});
  final OtaController ota;
  final GalleryController gallery;
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  String get analysisStatus {
    final gallery = widget.gallery;
    if (gallery.analyzing) {
      final progress = gallery.progress;
      return progress == null
          ? '正在检查新增照片…'
          : '已处理 ${progress.completed}/${progress.total} 张';
    }
    if (!gallery.ready) return '请先在首页准备模型并允许访问照片';
    return '只处理新增或未分析的照片，已分析的照片会跳过';
  }

  Future<void> checkUpdates() async {
    final ota = widget.ota;
    if (ota.phase != OtaPhase.downloading && ota.phase != OtaPhase.ready) {
      await ota.check();
    }
    if (!mounted) return;
    // Only an available/pending update opens a dialog. Other outcomes stay on
    // the settings page, so an up-to-date check does not interrupt browsing.
    if (ota.phase == OtaPhase.available ||
        ota.phase == OtaPhase.ready ||
        ota.phase == OtaPhase.downloading) {
      await showUpdateDialog(context, controller: ota);
    } else {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(ota.title)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = AppSettingsScope.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        Text('照片', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 12),
        AnimatedBuilder(
          animation: widget.gallery,
          builder: (context, _) => Card(
            margin: EdgeInsets.zero,
            child: ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              leading: Icon(Icons.auto_awesome, color: scheme.primary),
              title: Text(widget.gallery.analyzing ? '正在分析照片…' : '分析照片'),
              subtitle: Text(analysisStatus),
              trailing: widget.gallery.analyzing
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : null,
              // Share the homepage controller, index and completion feedback.
              // Popping settings does not stop or create a second analysis job.
              onTap: widget.gallery.ready && !widget.gallery.busy
                  ? () => unawaited(widget.gallery.analyze())
                  : null,
            ),
          ),
        ),
        const SizedBox(height: 28),
        Text('主题', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 12),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: RadioGroup<ThemeMode>(
              groupValue: settings.themeMode,
              onChanged: (mode) {
                if (mode != null) unawaited(settings.setTheme(mode));
              },
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                RadioListTile<ThemeMode>(
                    value: ThemeMode.system,
                    title: const Text('跟随系统'),
                    subtitle: const Text('自动使用手机的深色或浅色主题')),
                RadioListTile<ThemeMode>(
                    value: ThemeMode.dark, title: const Text('深色')),
                RadioListTile<ThemeMode>(
                    value: ThemeMode.light, title: const Text('浅色')),
              ]),
            ),
          ),
        ),
        if (settings.error != null)
          Padding(
              padding: const EdgeInsets.only(top: 10),
              child:
                  Text(settings.error!, style: TextStyle(color: scheme.error))),
        const SizedBox(height: 28),
        Text('应用', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 12),
        AnimatedBuilder(
          animation: widget.ota,
          builder: (context, _) => Card(
            margin: EdgeInsets.zero,
            child: ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              leading: Icon(Icons.system_update_alt, color: scheme.primary),
              title: const Text('检查更新'),
              subtitle: Text(widget.ota.phase == OtaPhase.idle
                  ? '查看是否有可用的应用更新'
                  : widget.ota.title),
              trailing: widget.ota.busy
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : null,
              onTap:
                  widget.ota.phase == OtaPhase.checking ? null : checkUpdates,
            ),
          ),
        ),
      ]),
    );
  }
}
