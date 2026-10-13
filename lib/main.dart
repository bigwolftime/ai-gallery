import 'dart:async';
import 'package:flutter/material.dart';
import 'src/gallery_controller.dart';
import 'src/gallery_page.dart';
import 'src/ota/ota_controller.dart';
import 'src/settings/app_settings.dart';
import 'src/settings/app_theme.dart';

void main() => runApp(const AIGalleryApp());

class AIGalleryApp extends StatefulWidget {
  const AIGalleryApp({super.key, this.settings, this.gallery, this.ota});
  final AppSettingsController? settings;
  final GalleryController? gallery;
  final OtaController? ota;
  @override
  State<AIGalleryApp> createState() => _AIGalleryAppState();
}

class _AIGalleryAppState extends State<AIGalleryApp> {
  late final AppSettingsController settings;
  @override
  void initState() {
    super.initState();
    settings = widget.settings ?? AppSettingsController();
    unawaited(settings.load());
  }

  @override
  void dispose() {
    if (widget.settings == null) settings.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AppSettingsScope(
        controller: settings,
        child: AnimatedBuilder(
            animation: settings,
            builder: (context, _) => MaterialApp(
                  title: 'AI Gallery',
                  debugShowCheckedModeBanner: false,
                  theme: AppTheme.build(Brightness.light),
                  darkTheme: AppTheme.build(Brightness.dark),
                  themeMode: settings.themeMode,
                  themeAnimationDuration:
                      MediaQuery.maybeOf(context)?.disableAnimations == true
                          ? Duration.zero
                          : const Duration(milliseconds: 180),
                  home: GalleryPage(
                      controller: widget.gallery, otaController: widget.ota),
                )),
      );
}
