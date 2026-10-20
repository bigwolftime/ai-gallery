import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import '../gallery_controller.dart';
import '../ota/ota_controller.dart';
import '../ota/update_sheet.dart';
import '../ui/ios_glass.dart';
import 'app_settings.dart';
import 'legal_page.dart';

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
    if (ota.distribution.managedByStore) {
      if (ota.distribution.storeUri != null) {
        await ota.openStore();
      } else if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(ota.title)));
      }
      return;
    }
    if (ota.phase != OtaPhase.downloading &&
        ota.phase != OtaPhase.ready &&
        ota.phase != OtaPhase.packageDownloading &&
        ota.phase != OtaPhase.packageReady &&
        ota.phase != OtaPhase.packageOpening) {
      await ota.check();
    }
    if (!mounted) return;
    // Only an available/pending update opens a dialog. Other outcomes stay on
    // the settings page, so an up-to-date check does not interrupt browsing.
    if (ota.phase == OtaPhase.available ||
        ota.phase == OtaPhase.ready ||
        ota.phase == OtaPhase.downloading ||
        ota.hasFullRelease) {
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
      extendBodyBehindAppBar: usesIosStyle(context),
      appBar: AdaptiveNavigationBar(
          platform: Theme.of(context).platform, title: '设置'),
      body: ListView(
          padding: EdgeInsets.fromLTRB(
              20,
              usesIosStyle(context)
                  ? MediaQuery.paddingOf(context).top +
                      AdaptiveNavigationBar.iosHeight +
                      20
                  : 20,
              20,
              MediaQuery.paddingOf(context).bottom + 20),
          children: [
            Text('照片', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 12),
            AnimatedBuilder(
              animation: widget.gallery,
              builder: (context, _) => AdaptiveGlassCard(
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
            AdaptiveGlassCard(
              child: usesIosStyle(context)
                  ? Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            CupertinoSlidingSegmentedControl<ThemeMode>(
                                groupValue: settings.themeMode,
                                children: const {
                                  ThemeMode.system: Padding(
                                      padding:
                                          EdgeInsets.symmetric(horizontal: 4),
                                      child: Text('跟随系统')),
                                  ThemeMode.dark: Text('深色'),
                                  ThemeMode.light: Text('浅色'),
                                },
                                onValueChanged: (mode) {
                                  if (mode != null) {
                                    unawaited(settings.setTheme(mode));
                                  }
                                }),
                            const SizedBox(height: 12),
                            Text('跟随系统会自动匹配手机的外观设置',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(color: scheme.onSurfaceVariant)),
                          ]))
                  : Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: RadioGroup<ThemeMode>(
                        groupValue: settings.themeMode,
                        onChanged: (mode) {
                          if (mode != null) unawaited(settings.setTheme(mode));
                        },
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
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
                  child: Text(settings.error!,
                      style: TextStyle(color: scheme.error))),
            const SizedBox(height: 28),
            Text('应用', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 12),
            AnimatedBuilder(
              animation: widget.ota,
              builder: (context, _) => AdaptiveGlassCard(
                child: ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  leading: Icon(Icons.system_update_alt, color: scheme.primary),
                  title: Text(widget.ota.distribution.managedByStore
                      ? '前往 ${widget.ota.distribution.storeName} 更新'
                      : '检查更新'),
                  subtitle: Text(widget.ota.phase == OtaPhase.idle
                      ? '查看是否有可用的应用更新'
                      : [
                          widget.ota.title,
                          if (widget.ota.packageNotice != null)
                            widget.ota.packageNotice!
                        ].join('\n')),
                  trailing: widget.ota.busy
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : null,
                  onTap: widget.ota.phase == OtaPhase.checking ||
                          widget.ota.phase == OtaPhase.storeOpening
                      ? null
                      : checkUpdates,
                ),
              ),
            ),
            const SizedBox(height: 12),
            AdaptiveGlassCard(
                child: Column(children: [
              ListTile(
                leading:
                    Icon(Icons.privacy_tip_outlined, color: scheme.primary),
                title: const Text('隐私政策'),
                onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                        builder: (_) => const LegalPage(
                            title: '隐私政策', asset: 'assets/legal/privacy.txt'))),
              ),
              ListTile(
                leading:
                    Icon(Icons.description_outlined, color: scheme.primary),
                title: const Text('开源许可'),
                onTap: () => showLicensePage(
                    context: context,
                    applicationName: 'AI Gallery',
                    applicationLegalese:
                        'Copyright 2026 AI Gallery contributors.'),
              ),
            ])),
          ]),
    );
  }
}
