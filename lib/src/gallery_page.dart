import 'dart:async';
import 'dart:typed_data';
import 'package:ai_gallery_native/ai_gallery_native.dart';
import 'package:flutter/material.dart';
import 'gallery_controller.dart';
import 'ota/ota_controller.dart';
import 'settings/settings_page.dart';

const _transitionDuration = Duration(milliseconds: 180);
const _revealDuration = Duration(milliseconds: 240);

// Respect iOS/Android accessibility preferences for reduced motion.
Duration _motionDuration(BuildContext context, {bool reveal = false}) =>
    MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : reveal
            ? _revealDuration
            : _transitionDuration;

class GalleryPage extends StatefulWidget {
  const GalleryPage({super.key, this.controller, this.otaController});
  final GalleryController? controller;
  final OtaController? otaController;
  @override
  State<GalleryPage> createState() => _GalleryPageState();
}

class _GalleryPageState extends State<GalleryPage> {
  late final GalleryController controller;
  final query = TextEditingController();
  final searchFocus = FocusNode();
  final scroll = ScrollController();
  late final OtaController ota;
  bool dialogOpen = false;
  String? lastNotice;

  @override
  void initState() {
    super.initState();
    searchFocus.addListener(onSearchFocusChanged);
    controller = widget.controller ?? GalleryController();
    controller.addListener(onUpdate);
    controller.start();
    ota = widget.otaController ?? OtaController();
    unawaited(ota.check());
  }

  void onSearchFocusChanged() {
    if (mounted) setState(() {});
  }

  void dismissKeyboard() => searchFocus.unfocus();

  void onUpdate() {
    if (!mounted) return;
    if (controller.promptRequested && !dialogOpen) {
      dialogOpen = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        final accept = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: const Text('分析你的照片？'),
            content: Text(
                '将在本地为 ${controller.photos.length} 张照片建立搜索索引，已分析的照片会跳过。图片不会上传；仅在 iCloud 中的图片可能需要下载。'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('暂不')),
              FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('开始分析')),
            ],
          ),
        );
        if (!mounted) return;
        dialogOpen = false;
        await controller.answerPrompt(accept == true);
      });
    }
    final notice = controller.error ?? controller.message;
    if (notice == null) lastNotice = null;
    if (notice != null && notice != lastNotice) {
      lastNotice = notice;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(notice)));
        }
      });
    }
  }

  Future<void> submit() async {
    FocusScope.of(context).unfocus();
    await controller.search(query.text);
    if (scroll.hasClients) scroll.jumpTo(0);
  }

  @override
  void dispose() {
    controller.removeListener(onUpdate);
    if (widget.controller == null) controller.dispose();
    if (widget.otaController == null) ota.dispose();
    searchFocus.removeListener(onSearchFocusChanged);
    searchFocus.dispose();
    query.dispose();
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: controller,
        builder: (context, _) => Scaffold(
          resizeToAvoidBottomInset: true,
          appBar: AppBar(
            title: const Text('AI Gallery'),
            actions: [
              TextButton(
                onPressed: () {
                  dismissKeyboard();
                  Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                          builder: (_) =>
                              SettingsPage(ota: ota, gallery: controller)));
                },
                child: const Text('设置'),
              ),
              // Long press is the only entry into selection. Keep an explicit
              // exit so users can return to normal photo browsing afterwards.
              if (controller.selectionMode)
                TextButton(
                    onPressed: controller.toggleSelectionMode,
                    child: const Text('完成')),
            ],
          ),
          // Keep the search bar inside the resized body. A bottomNavigationBar
          // stays behind the keyboard; adding viewInsets here would lift twice.
          body: Column(children: [
            Expanded(child: buildGalleryContent()),
            buildSearchBar(),
          ]),
        ),
      );

  Widget buildGalleryContent() {
    if (controller.loading) return ModelLoadingView(controller: controller);
    if (controller.needsModelDownload) {
      return ModelDownloadView(controller: controller);
    }
    if (!controller.ready) {
      return Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('照片库或模型未准备好'),
        const SizedBox(height: 12),
        FilledButton(onPressed: controller.start, child: const Text('重试')),
        TextButton(
            onPressed: controller.service.native.openSettings,
            child: const Text('打开权限设置')),
      ]));
    }
    if (controller.hits.isEmpty) {
      return const Center(child: Text('没有可显示的图片'));
    }
    return CustomScrollView(
      controller: scroll,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3, crossAxisSpacing: 10, mainAxisSpacing: 10),
            delegate: SliverChildBuilderDelegate(
                (context, index) => buildPhotoTile(controller.hits[index]),
                childCount: controller.visibleCount),
          ),
        ),
        SliverToBoxAdapter(
            child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          child: controller.hasMore
              ? OutlinedButton.icon(
                  onPressed: () {
                    dismissKeyboard();
                    controller.expand();
                  },
                  icon: const Icon(Icons.expand_more),
                  label: const Text('扩大搜索范围 · 再看 15 张'))
              : controller.hits.any((hit) => hit.score != null)
                  ? Center(
                      child: Text('已展示全部候选',
                          style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant)))
                  : const SizedBox.shrink(),
        )),
      ],
    );
  }

  Widget buildPhotoTile(SearchHit hit) {
    final selected = controller.selected.contains(hit.photo.id);
    final motion = _motionDuration(context);
    return GestureDetector(
      key: ValueKey(hit.photo.id),
      onTap: () {
        dismissKeyboard();
        if (controller.selectionMode) {
          controller.select(hit.photo.id);
        } else {
          Navigator.push(
              context,
              MaterialPageRoute<void>(
                  builder: (_) =>
                      PhotoDetailPage(hit: hit, controller: controller)));
        }
      },
      onLongPress: () {
        dismissKeyboard();
        controller.select(hit.photo.id);
      },
      // Animate only newly mounted tiles, including appended candidates.
      // Progress and selection rebuilds keep the existing animation state.
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: _motionDuration(context, reveal: true),
        curve: Curves.easeOutCubic,
        builder: (_, value, child) => Opacity(
            opacity: value,
            child: Transform.translate(
                offset: Offset(0, (1 - value) * 8), child: child)),
        child: AnimatedScale(
          scale: selected ? .96 : 1,
          duration: motion,
          curve: Curves.easeOutCubic,
          child: Stack(fit: StackFit.expand, children: [
            ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: NativePhotoImage(
                    photo: hit.photo, native: controller.service.native)),
            IgnorePointer(
              child: AnimatedContainer(
                duration: motion,
                decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                        width: 2,
                        color: selected
                            ? Theme.of(context).colorScheme.primary
                            : Colors.transparent)),
              ),
            ),
            if (hit.score != null)
              Positioned(top: 7, left: 7, child: ScoreBadge(score: hit.score!)),
            Positioned(
              top: 7,
              right: 7,
              child: AnimatedSwitcher(
                  duration: motion,
                  child: controller.selectionMode
                      ? Icon(
                          selected ? Icons.check_circle : Icons.circle_outlined,
                          key: ValueKey(selected),
                          color: selected
                              ? Theme.of(context).colorScheme.primary
                              : Colors.white)
                      : const SizedBox.shrink()),
            ),
          ]),
        ),
      ),
    );
  }

  Widget buildSearchBar() {
    final controls = Column(mainAxisSize: MainAxisSize.min, children: [
      if (controller.analyzing)
        Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(children: [
              Text(controller.progress == null
                  ? '正在检查新增照片…'
                  : '正在分析照片 ${controller.progress!.completed}/${controller.progress!.total}'),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                  value: controller.progress == null ||
                          controller.progress!.total == 0
                      ? null
                      : controller.progress!.completed /
                          controller.progress!.total),
            ])),
      if (controller.selectionMode && controller.selected.isNotEmpty)
        Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(children: [
              Text('已选择 ${controller.selected.length} 张'),
              const Spacer(),
              FilledButton.icon(
                  onPressed:
                      controller.sharing ? null : () => controller.share(),
                  icon: const Icon(Icons.ios_share),
                  label: const Text('分享')),
            ])),
      if (searchFocus.hasFocus)
        Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
                onPressed: dismissKeyboard,
                // Reuse the existing chevron in the baseline's icon font.
                icon: const Icon(Icons.expand_more, size: 18),
                label: const Text('收起键盘'))),
      TextField(
        controller: query,
        focusNode: searchFocus,
        enabled: controller.ready && !controller.busy,
        textInputAction: TextInputAction.search,
        // iOS does not dismiss on outside touch by default; explicitly
        // release focus while preserving the unfinished search text.
        onTapOutside: (_) => dismissKeyboard(),
        onSubmitted: (_) => submit(),
        decoration: InputDecoration(
          hintText: '描述你要找的图片…',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: controller.searching
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2)))
              : IconButton(
                  tooltip: '搜索',
                  onPressed:
                      controller.ready && !controller.busy ? submit : null,
                  icon: const Icon(Icons.arrow_upward)),
          filled: true,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(22),
              borderSide: BorderSide.none),
        ),
      ),
    ]);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        // Skip the size controller entirely for reduced motion. A zero-duration
        // AnimatedSize can notify layout listeners while it is laying out.
        child: MediaQuery.disableAnimationsOf(context)
            ? controls
            : AnimatedSize(
                duration: _transitionDuration,
                curve: Curves.easeOutCubic,
                alignment: Alignment.bottomCenter,
                child: controls),
      ),
    );
  }
}

/// Keep each image request stable across score/selection/progress rebuilds.
class NativePhotoImage extends StatefulWidget {
  const NativePhotoImage(
      {super.key,
      required this.photo,
      required this.native,
      this.fullSize = false});
  final GalleryPhoto photo;
  final AIGalleryNative native;
  final bool fullSize;
  @override
  State<NativePhotoImage> createState() => _NativePhotoImageState();
}

class _NativePhotoImageState extends State<NativePhotoImage> {
  late Future<Uint8List?> image;
  @override
  void initState() {
    super.initState();
    load();
  }

  void load() {
    image = widget.fullSize
        ? widget.native.loadImage(widget.photo.id)
        : widget.native.loadThumbnail(widget.photo.id);
  }

  @override
  void didUpdateWidget(NativePhotoImage old) {
    super.didUpdateWidget(old);
    if (old.photo.id != widget.photo.id || old.fullSize != widget.fullSize) {
      load();
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List?>(
        future: image,
        builder: (context, snapshot) {
          final bytes = snapshot.data;
          if (bytes != null) {
            return Image.memory(bytes,
                fit: widget.fullSize ? BoxFit.contain : BoxFit.cover,
                gaplessPlayback: true);
          }
          return ColoredBox(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Center(
                  child: snapshot.connectionState == ConnectionState.waiting
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.broken_image_outlined)));
        },
      );
}

class ScoreBadge extends StatelessWidget {
  const ScoreBadge({super.key, required this.score});
  final double score;
  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: .72),
            borderRadius: BorderRadius.circular(12)),
        child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
            child: Text(score.toStringAsFixed(2),
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold))),
      );
}

class PhotoDetailPage extends StatelessWidget {
  const PhotoDetailPage(
      {super.key, required this.hit, required this.controller});
  final SearchHit hit;
  final GalleryController controller;
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('图片详情'), actions: [
          IconButton(
              tooltip: '分享',
              onPressed: () => controller.share([hit.photo.id]),
              icon: const Icon(Icons.ios_share))
        ]),
        body: Center(
            child: InteractiveViewer(
                minScale: .5,
                maxScale: 5,
                child: NativePhotoImage(
                    photo: hit.photo,
                    native: controller.service.native,
                    fullSize: true))),
      );
}

class ModelLoadingView extends StatelessWidget {
  const ModelLoadingView({super.key, required this.controller});
  final GalleryController controller;
  @override
  Widget build(BuildContext context) {
    final progress = controller.modelProgress;
    final isTransfer =
        controller.downloadingModel && progress?.stage == 'downloading';
    final verifying =
        controller.downloadingModel && progress?.stage == 'verifying';
    return Center(
        child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (isTransfer)
                LinearProgressIndicator(value: progress?.fraction)
              else
                const CircularProgressIndicator(),
              const SizedBox(height: 18),
              Text(isTransfer
                  ? '正在下载搜索模型'
                  : verifying
                      ? '正在校验模型…'
                      : '正在准备 AI Gallery…'),
              if (isTransfer && progress != null)
                Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(
                        '${(progress.received / 1000000).toStringAsFixed(1)} / ${(progress.total / 1000000).toStringAsFixed(1)} MB')),
              if (controller.downloadingModel && progress?.stage != 'ready')
                TextButton(
                    onPressed: controller.pauseModelDownload,
                    child: const Text('暂停下载')),
            ])));
  }
}

class ModelDownloadView extends StatelessWidget {
  const ModelDownloadView({super.key, required this.controller});
  final GalleryController controller;
  @override
  Widget build(BuildContext context) => Center(
      child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.download_for_offline_outlined, size: 48),
            const SizedBox(height: 18),
            const Text('下载本地搜索模型',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Text(
                '首次使用需要下载约 ${(controller.service.modelBytes / 1000000).toStringAsFixed(0)} MB 的模型。建议连接 Wi-Fi，完成后可离线搜索，图片不会上传。',
                textAlign: TextAlign.center),
            const SizedBox(height: 22),
            FilledButton.icon(
                onPressed: controller.downloadModel,
                icon: const Icon(Icons.download),
                label: const Text('下载 / 继续下载')),
          ])));
}
