import 'package:flutter/material.dart';
import 'ota_controller.dart';
import '../ui/glass.dart';

/// Fill the phone's available width, with a comfortable cap on larger screens.
Future<void> showUpdateDialog(BuildContext context,
        {required OtaController controller}) =>
    showDialog<void>(
        context: context,
        barrierColor: Colors.black.withValues(alpha: .4),
        builder: (context) => Dialog(
              insetPadding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              constraints: const BoxConstraints(maxWidth: 440),
              child: UpdateSheet(controller: controller),
            ));

class UpdateSheet extends StatelessWidget {
  const UpdateSheet({super.key, required this.controller});
  final OtaController controller;

  String get description => switch (controller.phase) {
        OtaPhase.ready => '请完全关闭并重新打开 App。已下载模型和照片索引会保留。',
        OtaPhase.available => '下载后重新打开 App 即可使用更新。模型和照片索引会保留。',
        OtaPhase.downloading => '正在下载应用更新，请保持网络连接。',
        OtaPhase.checking => '正在获取最新版本信息…',
        OtaPhase.current => controller.packageCheckConfirmed
            ? '无需更新，可以继续使用 AI Gallery。'
            : '在线补丁已检查，整包版本暂未确认。',
        OtaPhase.unavailable => controller.packageCheckConfirmed
            ? '当前没有新版安装包，此安装包暂不支持在线补丁。'
            : '请检查网络，或安装支持更新的新版基础包后重试。',
        OtaPhase.failed => '请检查网络后重试。',
        OtaPhase.idle => '检查是否有可用的应用更新。',
        OtaPhase.packageAvailable => controller.fullRelease!.isApk
            ? '此版本需要下载安装包。请确认覆盖安装，不要卸载当前应用；模型和照片索引会保留。'
            : controller.fullRelease!.kind == 'ipa'
                ? '此版本需要更新 IPA。下载后通过 SideStore 导入并覆盖安装，沿用原账号和应用标识。'
                : '此版本需要通过应用商店更新，点击下方按钮前往。',
        OtaPhase.packageDownloading => '正在准备安装包，请保持 App 在前台。可暂停后继续下载。',
        OtaPhase.packageReady => '安装包已完成校验，点击安装并在系统界面确认。',
        OtaPhase.packageOpening => '正在打开系统更新界面…',
        OtaPhase.storeManaged =>
          '请在 ${controller.distribution.storeName} 客户端中检查和安装更新。',
        OtaPhase.storeOpening => '正在打开应用商店…',
      };

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final theme = Theme.of(context);
          final scheme = theme.colorScheme;
          return SizedBox(
            width: double.infinity,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                            color: scheme.primaryContainer,
                            borderRadius: BorderRadius.circular(16)),
                        child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Icon(Icons.system_update_alt,
                                size: 30, color: scheme.onPrimaryContainer)),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(controller.title,
                        style: theme.textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 12),
                    Text(description,
                        style: theme.textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant, height: 1.5)),
                    if (controller.installed != null)
                      Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(
                              '当前版本：${controller.installed!.version} (${controller.installed!.buildNumber})',
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(color: scheme.onSurfaceVariant))),
                    if (controller.fullRelease case final release?) ...[
                      if (release.notes.isNotEmpty)
                        Padding(
                            padding: const EdgeInsets.only(top: 16),
                            child: Text(release.notes)),
                      if (release.size != null)
                        Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                                '安装包约 ${(release.size! / 1000000).toStringAsFixed(1)} MB',
                                style: theme.textTheme.bodySmall)),
                    ],
                    if (controller.packageNotice != null)
                      Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(controller.packageNotice!)),
                    if (controller.error != null && controller.hasFullRelease)
                      Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(controller.error!,
                              style: TextStyle(color: scheme.error))),
                    if (controller.currentPatch != null &&
                        !controller.hasFullRelease)
                      Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: Text('当前补丁：${controller.currentPatch}',
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(color: scheme.onSurfaceVariant))),
                    if (controller.phase == OtaPhase.ready &&
                        controller.nextPatch != null)
                      Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text('待生效补丁：${controller.nextPatch}',
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(color: scheme.onSurfaceVariant))),
                    if (controller.busy)
                      Padding(
                          padding: EdgeInsets.only(top: 20),
                          child: LinearProgressIndicator(
                              value: controller.phase ==
                                          OtaPhase.packageDownloading &&
                                      controller.packageProgress?.stage ==
                                          'downloading'
                                  ? controller.packageProgress?.fraction
                                  : null)),
                    if (controller.phase == OtaPhase.packageDownloading &&
                        controller.packageProgress != null)
                      Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                              '${(controller.packageProgress!.received / 1000000).toStringAsFixed(1)} / ${(controller.packageProgress!.total / 1000000).toStringAsFixed(1)} MB')),
                    const SizedBox(height: 24),
                    if (controller.phase == OtaPhase.packageAvailable)
                      FilledButton(
                          onPressed: controller.fullRelease!.isApk
                              ? controller.downloadPackage
                              : controller.openFullRelease,
                          child: Text(controller.fullRelease!.isApk
                              ? '下载 / 继续下载'
                              : controller.fullRelease!.kind == 'ipa'
                                  ? '下载新版 IPA'
                                  : '前往应用商店')),
                    if (controller.phase == OtaPhase.packageReady)
                      FilledButton(
                          onPressed: controller.installPackage,
                          child: Text(controller.installPermissionRequired
                              ? '继续安装'
                              : '安装新版')),
                    if (controller.phase == OtaPhase.packageDownloading)
                      AppTextAction(
                          label: '暂停下载',
                          onPressed: controller.pausePackageDownload),
                    if (controller.phase == OtaPhase.available)
                      FilledButton(
                          onPressed: controller.download,
                          child: const Text('下载更新')),
                    if (!controller.busy &&
                        controller.phase != OtaPhase.unavailable &&
                        controller.phase != OtaPhase.ready &&
                        controller.phase != OtaPhase.available &&
                        !controller.hasFullRelease)
                      FilledButton(
                          onPressed: controller.check,
                          child: const Text('检查更新')),
                    AppTextAction(
                      label: '关闭',
                      onPressed: () => Navigator.pop(context),
                    ),
                  ]),
            ),
          );
        },
      );
}
