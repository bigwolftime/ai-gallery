import 'package:flutter/material.dart';
import 'ota_controller.dart';

/// Fill the phone's available width, with a comfortable cap on larger screens.
Future<void> showUpdateDialog(BuildContext context,
        {required OtaController controller}) =>
    showDialog<void>(
        context: context,
        builder: (_) => Dialog(
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
        OtaPhase.current => '无需更新，可以继续使用 AI Gallery。',
        OtaPhase.unavailable => '需要先安装支持在线更新的新版基础包。',
        OtaPhase.failed => '请检查网络后重试。',
        OtaPhase.idle => '检查是否有可用的应用更新。',
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
                    if (controller.currentPatch != null)
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
                      const Padding(
                          padding: EdgeInsets.only(top: 20),
                          child: LinearProgressIndicator()),
                    const SizedBox(height: 24),
                    if (controller.phase == OtaPhase.available)
                      FilledButton(
                          onPressed: controller.download,
                          child: const Text('下载更新')),
                    if (!controller.busy &&
                        controller.phase != OtaPhase.unavailable &&
                        controller.phase != OtaPhase.ready &&
                        controller.phase != OtaPhase.available)
                      FilledButton(
                          onPressed: controller.check,
                          child: const Text('检查更新')),
                    TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('关闭')),
                  ]),
            ),
          );
        },
      );
}
