import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:ai_gallery_native/ai_gallery_native.dart';
import 'package:flutter/material.dart';
import 'gallery_controller.dart';
import 'ota/ota_controller.dart';
import 'ota/update_sheet.dart';
import 'settings/app_theme.dart';
import 'settings/settings_page.dart';
import 'ui/brand.dart';
import 'ui/glass.dart';

const _transitionDuration = Duration(milliseconds: 180);
const _revealDuration = Duration(milliseconds: 240);

// Example phrasings shown while the empty search field is focused.
const _suggestions = ['海边的日落', '猫咪', '生日蛋糕', '雪山', '夜晚的城市', '穿红衣服的人'];

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
  final dockKey = GlobalKey();
  double dockExtent = 0;
  bool dockMeasurementQueued = false;
  late final OtaController ota;
  late final Listenable changes;
  int? dismissedRelease;
  bool dialogOpen = false;
  String? lastNotice;
  String? searchedQuery;
  bool queryEmpty = true;

  @override
  void initState() {
    super.initState();
    searchFocus.addListener(onSearchFocusChanged);
    query.addListener(onQueryChanged);
    controller = widget.controller ?? GalleryController();
    controller.addListener(onUpdate);
    controller.start();
    ota = widget.otaController ?? OtaController();
    changes = Listenable.merge([controller, ota]);
    if (ota.automaticChecksAllowed) unawaited(ota.check());
  }

  void onSearchFocusChanged() {
    if (mounted) setState(() {});
  }

  // Suggestions only depend on whether the field is empty.
  void onQueryChanged() {
    final empty = query.text.isEmpty;
    if (mounted && empty != queryEmpty) setState(() => queryEmpty = empty);
  }

  void dismissKeyboard() => searchFocus.unfocus();

  // The floating dock can grow for keyboard/selection/progress/large text.
  // Measure it after layout so the last photo and expansion action stay usable.
  void measureDock() {
    if (dockMeasurementQueued) return;
    dockMeasurementQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      dockMeasurementQueued = false;
      if (!mounted) return;
      final box = dockKey.currentContext?.findRenderObject();
      if (box is RenderBox &&
          box.hasSize &&
          (box.size.height - dockExtent).abs() > .5) {
        setState(() => dockExtent = box.size.height);
      }
    });
  }

  void onUpdate() {
    if (!mounted) return;
    if (controller.promptRequested && !dialogOpen) {
      dialogOpen = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        // Both platforms index locally; keep shared copy free of cloud-provider names.
        final description =
            '将在本地为 ${controller.photos.length} 张照片建立搜索索引，已分析的照片会跳过。图片不会上传。';
        final accept = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            icon: const BrandBadge(icon: Icons.auto_awesome, size: 56),
            title: const Text('分析你的照片？'),
            content: Text(description),
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
    // Unfocus the field itself: unfocusing the scope while the field is focused
    // (chip or arrow button) makes the route restore it after a detail pop.
    dismissKeyboard();
    final trimmed = query.text.trim();
    setState(() => searchedQuery = trimmed.isEmpty ? null : trimmed);
    await controller.search(query.text);
    if (scroll.hasClients) scroll.jumpTo(0);
  }

  Future<void> clearSearch() async {
    dismissKeyboard();
    query.clear();
    setState(() => searchedQuery = null);
    await controller.search('');
    if (scroll.hasClients) scroll.jumpTo(0);
  }

  bool get showingResults =>
      controller.hits.isNotEmpty && controller.hits.first.score != null;

  @override
  void dispose() {
    controller.removeListener(onUpdate);
    if (widget.controller == null) controller.dispose();
    if (widget.otaController == null) ota.dispose();
    searchFocus.removeListener(onSearchFocusChanged);
    searchFocus.dispose();
    query.removeListener(onQueryChanged);
    query.dispose();
    scroll.dispose();
    super.dispose();
  }

  void openSettings() {
    dismissKeyboard();
    Navigator.push(
        context,
        MaterialPageRoute<void>(
            builder: (_) => SettingsPage(ota: ota, gallery: controller)));
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: changes,
        builder: (context, _) => Scaffold(
          resizeToAvoidBottomInset: true,
          extendBodyBehindAppBar: true,
          appBar: GlassNavigationBar(
            title: 'AI Gallery',
            actions: [
              AppTextAction(label: '设置', onPressed: openSettings),
              // Long press is the only entry into selection. Keep an explicit
              // exit so users can return to normal photo browsing afterwards.
              if (controller.selectionMode)
                AppTextAction(
                    label: '完成', onPressed: controller.toggleSelectionMode),
            ],
          ),
          // Photos scroll under the translucent bar and the floating dock.
          body: Column(children: [
            if (showBaseUpdateBanner)
              Padding(
                  padding: EdgeInsets.only(
                      top: MediaQuery.paddingOf(context).top +
                          GlassNavigationBar.height),
                  child: buildUpdateBanner()),
            Expanded(
                child: buildGalleryContent(
                    topPadding: showBaseUpdateBanner
                        ? 8
                        : MediaQuery.paddingOf(context).top +
                            GlassNavigationBar.height +
                            8,
                    bottomPadding: dockExtent + 24)),
          ]),
          // Scaffold positions this overlay above the keyboard. The photos can
          // scroll underneath its bounded blur without a second viewInset.
          bottomSheet: buildFloatingDock(),
        ),
      );

  bool get showBaseUpdateBanner =>
      ota.fullRelease != null &&
      ota.fullRelease!.buildNumber != dismissedRelease;

  Widget buildUpdateBanner() => Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: AppCard(
          child: ListTile(
        leading: const BrandBadge(icon: Icons.system_update_alt, size: 40),
        title: Text('发现新版本 ${ota.fullRelease!.version}'),
        subtitle: const Text('需要安装新版应用，已有照片索引会保留'),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          AppTextAction(
              label: '更新',
              onPressed: () {
                dismissKeyboard();
                showUpdateDialog(context, controller: ota);
              }),
          IconButton(
              tooltip: '稍后更新',
              icon: const Icon(Icons.close),
              onPressed: () => setState(
                  () => dismissedRelease = ota.fullRelease!.buildNumber)),
        ]),
      )));

  Widget buildFloatingDock() {
    measureDock();
    return NotificationListener<SizeChangedLayoutNotification>(
      onNotification: (_) {
        measureDock();
        return true;
      },
      child: SizeChangedLayoutNotifier(
          child: KeyedSubtree(key: dockKey, child: buildSearchBar())),
    );
  }

  Widget buildGalleryContent(
      {double topPadding = 8, double bottomPadding = 24}) {
    if (controller.loading) return ModelLoadingView(controller: controller);
    if (controller.needsModelDownload) {
      return ModelDownloadView(controller: controller);
    }
    if (!controller.ready) {
      return StateMessage(
          icon: Icons.photo_library_outlined,
          title: '照片库或模型未准备好',
          body: '允许访问照片后，AI Gallery 会在本机为它们建立搜索索引。',
          children: [
            SizedBox(
                width: double.infinity,
                child: FilledButton(
                    onPressed: controller.start, child: const Text('重试'))),
            const SizedBox(height: 8),
            TextButton(
                onPressed: controller.service.native.openSettings,
                child: const Text('打开权限设置')),
          ]);
    }
    if (controller.hits.isEmpty) {
      return const StateMessage(
          icon: Icons.image_search_rounded,
          title: '没有可显示的图片',
          body: '相册里的照片会显示在这里，用一句话就能找到它们。');
    }
    final results = showingResults;
    final gridCount =
        results ? controller.visibleCount - 1 : controller.visibleCount;
    final gap = results ? 8.0 : 3.0;
    return CustomScrollView(
      controller: scroll,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      slivers: [
        SliverToBoxAdapter(
            child: Padding(
                padding: EdgeInsets.fromLTRB(20, topPadding + 4, 12, 14),
                child: results ? buildResultsHeader() : buildLibraryHeader())),
        if (results)
          SliverToBoxAdapter(
              child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: LayoutBuilder(
                      builder: (context, constraints) => SizedBox(
                          height: math.min(constraints.maxWidth * .62, 220),
                          child: buildPhotoTile(controller.hits.first,
                              hero: true))))),
        SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: results ? 16 : 12),
          sliver: SliverGrid(
            gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: results ? 150 : 100,
                crossAxisSpacing: gap,
                mainAxisSpacing: gap),
            delegate: SliverChildBuilderDelegate(
                (context, index) => buildPhotoTile(
                    controller.hits[results ? index + 1 : index]),
                childCount: math.max(gridCount, 0)),
          ),
        ),
        SliverToBoxAdapter(
            child: Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, bottomPadding),
          child: controller.hasMore
              ? FilledButton.tonalIcon(
                  onPressed: () {
                    dismissKeyboard();
                    controller.expand();
                  },
                  icon: const Icon(Icons.expand_more),
                  label: const Text('扩大搜索范围 · 再看 15 张'))
              : results
                  ? Center(
                      child: Text('已展示全部候选',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant)))
                  : const SizedBox.shrink(),
        )),
      ],
    );
  }

  Widget buildLibraryHeader() {
    final theme = Theme.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('全部照片', style: theme.textTheme.titleLarge),
      const SizedBox(height: 4),
      Row(children: [
        Icon(Icons.lock_outline_rounded,
            size: 13, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 4),
        Flexible(
            child: Text('${controller.photos.length} 张 · 搜索在本机完成，图片不会上传',
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant))),
      ]),
    ]);
  }

  Widget buildResultsHeader() {
    final theme = Theme.of(context);
    // Two lines keep the best match and first result row above the dock.
    return Row(children: [
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const GradientIcon(Icons.auto_awesome, size: 14),
            const SizedBox(width: 6),
            Flexible(
                child: Text(
                    '语义搜索 · 按相似度排序 · ${controller.visibleCount}/${controller.hits.length}',
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w600))),
          ]),
          const SizedBox(height: 2),
          Text(searchedQuery == null ? '搜索结果' : '“$searchedQuery”',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleLarge),
        ]),
      ),
      AppTextAction(label: '清除', onPressed: clearSearch),
    ]);
  }

  Widget buildPhotoTile(SearchHit hit, {bool hero = false}) {
    final selected = controller.selected.contains(hit.photo.id);
    final motion = _motionDuration(context);
    final scheme = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(hero ? 20 : (showingResults ? 14 : 6));
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
          scale: selected ? .94 : 1,
          duration: motion,
          curve: Curves.easeOutCubic,
          child: ClipRRect(
            borderRadius: radius,
            child: Stack(fit: StackFit.expand, children: [
              NativePhotoImage(
                  photo: hit.photo, native: controller.service.native),
              if (hero)
                const IgnorePointer(
                    child: DecoratedBox(
                        decoration: BoxDecoration(
                            gradient: LinearGradient(
                                begin: Alignment(0, .1),
                                end: Alignment.bottomCenter,
                                colors: [
                      Colors.transparent,
                      Colors.black54
                    ])))),
              IgnorePointer(
                child: AnimatedContainer(
                  duration: motion,
                  decoration: BoxDecoration(
                      color: selected
                          ? Colors.black.withValues(alpha: .18)
                          : Colors.transparent,
                      borderRadius: radius,
                      border: Border.all(
                          width: 3,
                          color:
                              selected ? scheme.primary : Colors.transparent)),
                ),
              ),
              if (hit.score != null)
                Positioned(
                    left: hero ? 14 : 6,
                    bottom: hero ? 14 : 6,
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      if (hero) ...[
                        const BestMatchLabel(),
                        const SizedBox(width: 8),
                      ],
                      ScoreBadge(score: hit.score!),
                    ])),
              Positioned(
                top: 8,
                right: 8,
                child: AnimatedSwitcher(
                    duration: motion,
                    child: controller.selectionMode
                        ? SelectionMark(
                            key: ValueKey(selected), selected: selected)
                        : const SizedBox.shrink()),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget buildAnalysisProgress() {
    final theme = Theme.of(context);
    final progress = controller.progress;
    final fraction = progress == null || progress.total == 0
        ? null
        : progress.completed / progress.total;
    return Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            const GradientIcon(Icons.auto_awesome, size: 16),
            const SizedBox(width: 8),
            Expanded(
                child: Text(
                    progress == null
                        ? '正在检查新增照片…'
                        : '正在分析照片 ${progress.completed}/${progress.total}',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w500))),
            if (fraction != null)
              Text('${(fraction * 100).round()}%',
                  style: theme.textTheme.labelMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ]),
          const SizedBox(height: 8),
          ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(value: fraction)),
        ]));
  }

  Widget buildSuggestionRow() {
    final scheme = Theme.of(context).colorScheme;
    final canSearch = controller.ready && !controller.busy;
    // Count taps here as inside the field so onTapOutside keeps focus until
    // the chip's own tap submits the search.
    return TextFieldTapRegion(
      child: SizedBox(
        height: 44,
        child: Row(children: [
          Expanded(
              child: queryEmpty
                  // Fade the trailing edge so overflowing chips read as
                  // scrollable instead of clipped by the dismiss action.
                  ? ShaderMask(
                      blendMode: BlendMode.dstIn,
                      shaderCallback: (bounds) => const LinearGradient(
                            stops: [.82, 1],
                            colors: [Colors.white, Colors.transparent],
                          ).createShader(bounds),
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.only(left: 6),
                        itemCount: _suggestions.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 6),
                        itemBuilder: (context, index) => Center(
                          child: Material(
                            color: scheme.primary.withValues(alpha: .1),
                            shape: const StadiumBorder(),
                            child: InkWell(
                              customBorder: const StadiumBorder(),
                              onTap: canSearch
                                  ? () {
                                      query.text = _suggestions[index];
                                      submit();
                                    }
                                  : null,
                              child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 7),
                                  child: Text(_suggestions[index],
                                      style: TextStyle(
                                          fontSize: 13,
                                          color: scheme.primary,
                                          fontWeight: FontWeight.w500))),
                            ),
                          ),
                        ),
                      ))
                  : const SizedBox.shrink()),
          AppTextAction(label: '收起键盘', onPressed: dismissKeyboard),
        ]),
      ),
    );
  }

  Widget buildSearchBar() {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final canSearch = controller.ready && !controller.busy;
    final controls = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (controller.analyzing) buildAnalysisProgress(),
          if (controller.selectionMode && controller.selected.isNotEmpty)
            Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 4, 8),
                child: Row(children: [
                  Text('已选择 ${controller.selected.length} 张',
                      style: theme.textTheme.titleSmall
                          ?.copyWith(color: scheme.onSurface)),
                  const Spacer(),
                  FilledButton.icon(
                      style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 40),
                          padding: const EdgeInsets.symmetric(horizontal: 18)),
                      onPressed:
                          controller.sharing ? null : () => controller.share(),
                      icon: const Icon(Icons.ios_share, size: 17),
                      label: const Text('分享')),
                ])),
          if (searchFocus.hasFocus) buildSuggestionRow(),
          TextField(
            style: const TextStyle(fontSize: 16),
            controller: query,
            focusNode: searchFocus,
            enabled: canSearch,
            textInputAction: TextInputAction.search,
            // iOS does not dismiss on outside touch by default; explicitly
            // release focus while preserving the unfinished search text.
            onTapOutside: (_) => dismissKeyboard(),
            onSubmitted: (_) => submit(),
            decoration: InputDecoration(
              hintText: '用一句话描述你要找的照片…',
              hintStyle: TextStyle(color: scheme.onSurfaceVariant),
              prefixIcon: const GradientIcon(Icons.auto_awesome, size: 20),
              suffixIcon: Padding(
                  padding: const EdgeInsets.all(6),
                  child: controller.searching
                      ? const Padding(
                          padding: EdgeInsets.all(8),
                          child: SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(strokeWidth: 2)))
                      : GradientCircleButton(
                          icon: Icons.arrow_upward_rounded,
                          tooltip: '搜索',
                          onPressed: canSearch ? submit : null)),
              filled: false,
              contentPadding: const EdgeInsets.symmetric(vertical: 14),
              border: InputBorder.none,
            ),
          ),
        ]);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        // Skip the size controller entirely for reduced motion. A zero-duration
        // AnimatedSize can notify layout listeners while it is laying out.
        child: GlassSurface(
            radius: 28,
            child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: animatedControls(controls))),
      ),
    );
  }

  Widget animatedControls(Widget controls) =>
      MediaQuery.disableAnimationsOf(context)
          ? controls
          : AnimatedSize(
              duration: _transitionDuration,
              curve: Curves.easeOutCubic,
              alignment: Alignment.bottomCenter,
              child: controls);
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
          final scheme = Theme.of(context).colorScheme;
          // A quiet placeholder: no per-tile spinner flickering across the grid.
          return ColoredBox(
              color: widget.fullSize
                  ? Colors.transparent
                  : scheme.surfaceContainerHighest,
              child: Center(
                  child: snapshot.connectionState == ConnectionState.waiting
                      ? (widget.fullSize
                          ? const SizedBox.square(
                              dimension: 24,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const SizedBox.shrink())
                      : Icon(Icons.broken_image_outlined,
                          color: scheme.onSurfaceVariant)));
        },
      );
}

class ScoreBadge extends StatelessWidget {
  const ScoreBadge({super.key, required this.score});
  final double score;
  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: .55),
            borderRadius: BorderRadius.circular(12)),
        child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                      gradient: AppTheme.accent, shape: BoxShape.circle)),
              const SizedBox(width: 5),
              Text(score.toStringAsFixed(2),
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      fontFeatures: [FontFeature.tabularFigures()])),
            ])),
      );
}

class BestMatchLabel extends StatelessWidget {
  const BestMatchLabel({super.key});
  @override
  Widget build(BuildContext context) => const DecoratedBox(
        decoration: BoxDecoration(
            gradient: AppTheme.accent,
            borderRadius: BorderRadius.all(Radius.circular(12))),
        child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.auto_awesome, size: 13, color: Colors.white),
              SizedBox(width: 4),
              Text('最佳匹配',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
            ])),
      );
}

class SelectionMark extends StatelessWidget {
  const SelectionMark({super.key, required this.selected});
  final bool selected;
  @override
  Widget build(BuildContext context) => Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: selected ? AppTheme.accent : null,
            color: selected ? null : Colors.black.withValues(alpha: .2),
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: const [
              BoxShadow(color: Colors.black26, blurRadius: 4),
            ]),
        child: selected
            ? const Icon(Icons.check_rounded, size: 15, color: Colors.white)
            : null,
      );
}

class PhotoDetailPage extends StatefulWidget {
  const PhotoDetailPage(
      {super.key, required this.hit, required this.controller});
  final SearchHit hit;
  final GalleryController controller;
  @override
  State<PhotoDetailPage> createState() => _PhotoDetailPageState();
}

/// Shows the cached thumbnail at once, then swaps in the original. Fetching an
/// iCloud original can take seconds, so the wait is explained instead of an
/// unexplained spinner.
class _PhotoDetailPageState extends State<PhotoDetailPage> {
  static const _slowAfter = Duration(milliseconds: 700);
  Uint8List? thumbnail;
  Uint8List? original;
  bool originalFailed = false;
  bool slow = false;
  double? cloudProgress;
  Timer? slowTimer;
  StreamSubscription<ImageLoadProgress>? progressSubscription;

  AIGalleryNative get native => widget.controller.service.native;
  String get id => widget.hit.photo.id;

  @override
  void initState() {
    super.initState();
    native.loadThumbnail(id).then((bytes) {
      if (mounted && original == null) setState(() => thumbnail = bytes);
    }, onError: (Object _) {});
    native.loadImage(id).then((bytes) {
      if (!mounted) return;
      setState(() {
        original = bytes;
        originalFailed = bytes == null;
      });
    }, onError: (Object _) {
      if (mounted) setState(() => originalFailed = true);
    });
    progressSubscription = native.imageLoadProgress
        .where((event) => event.id == id)
        .listen((event) => setState(() => cloudProgress = event.fraction));
    slowTimer = Timer(_slowAfter, () {
      if (mounted) setState(() => slow = true);
    });
  }

  @override
  void dispose() {
    slowTimer?.cancel();
    progressSubscription?.cancel();
    super.dispose();
  }

  bool get loading => original == null && !originalFailed;

  @override
  Widget build(BuildContext context) {
    // Photos read best on black regardless of the app theme.
    final dark = AppTheme.build(Brightness.dark);
    final bytes = original ?? thumbnail;
    return Theme(
      data: dark.copyWith(
          platform: Theme.of(context).platform,
          // A black surface keeps the translucent bar from reading as a band.
          colorScheme: dark.colorScheme.copyWith(surface: Colors.black),
          scaffoldBackgroundColor: Colors.black),
      child: Builder(
        builder: (context) => Scaffold(
          extendBodyBehindAppBar: true,
          appBar: GlassNavigationBar(title: '图片详情', actions: [
            IconButton(
                tooltip: '分享',
                onPressed: () => widget.controller.share([id]),
                color: Colors.white,
                icon: const Icon(Icons.ios_share))
          ]),
          body: Stack(children: [
            Center(
                child: bytes != null
                    ? InteractiveViewer(
                        minScale: .5,
                        maxScale: 5,
                        child: Image.memory(bytes,
                            fit: BoxFit.contain, gaplessPlayback: true))
                    : loading
                        ? const SizedBox.square(
                            dimension: 24,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.broken_image_outlined,
                            color: Colors.white54, size: 40)),
            Positioned(
                left: 24,
                right: 24,
                bottom: MediaQuery.paddingOf(context).bottom + 20,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  if (loadingNotice(context) case final notice?) ...[
                    notice,
                    const SizedBox(height: 10),
                  ],
                  if (widget.hit.score != null)
                    _DetailPill(children: [
                      const GradientIcon(Icons.auto_awesome, size: 15),
                      const SizedBox(width: 6),
                      Text('相似度 ${widget.hit.score!.toStringAsFixed(2)}',
                          style: _DetailPill.text),
                    ]),
                ])),
          ]),
        ),
      ),
    );
  }

  Widget? loadingNotice(BuildContext context) {
    final apple = isApplePlatform(context);
    if (originalFailed && thumbnail != null) {
      return _DetailPill(children: [
        const Icon(Icons.cloud_off_rounded, size: 16, color: Colors.white70),
        const SizedBox(width: 8),
        Flexible(
            child: Text(apple ? '原图暂时无法获取，请检查网络或 iCloud 设置' : '原图暂时无法读取',
                style: _DetailPill.text)),
      ]);
    }
    if (!loading) return null;
    final progress = cloudProgress;
    if (progress != null) {
      return _DetailPill(children: [
        const Icon(Icons.cloud_download_outlined,
            size: 16, color: Colors.white),
        const SizedBox(width: 8),
        Flexible(
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('正在从 iCloud 下载原图 · ${(progress * 100).round()}%',
                    style: _DetailPill.text),
                const SizedBox(height: 6),
                SizedBox(
                    width: 180,
                    child: ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                            value: progress,
                            minHeight: 3,
                            backgroundColor: Colors.white24))),
              ]),
        ),
      ]);
    }
    if (!slow) return null;
    return _DetailPill(children: [
      const SizedBox.square(
          dimension: 14,
          child:
              CircularProgressIndicator(strokeWidth: 1.8, color: Colors.white)),
      const SizedBox(width: 10),
      Flexible(
          child: Text(apple ? '正在获取原图，照片在 iCloud 中时需要先下载…' : '正在加载原图…',
              style: _DetailPill.text)),
    ]);
  }
}

class _DetailPill extends StatelessWidget {
  const _DetailPill({required this.children});
  final List<Widget> children;
  static const text =
      TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500);
  @override
  Widget build(BuildContext context) => DecoratedBox(
      decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: .55),
          border: Border.all(color: Colors.white.withValues(alpha: .12)),
          borderRadius: BorderRadius.circular(20)),
      child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Row(mainAxisSize: MainAxisSize.min, children: children)));
}

class ModelLoadingView extends StatelessWidget {
  const ModelLoadingView({super.key, required this.controller});
  final GalleryController controller;
  @override
  Widget build(BuildContext context) {
    final progress = controller.modelProgress;
    final isTransfer =
        controller.downloadingModel && progress?.stage == 'downloading';
    final label = controller.downloadingModel
        ? switch (progress?.stage) {
            'probing' => '正在选择下载线路…',
            'switching' => '正在切换下载线路…',
            'downloading' => '正在下载搜索模型',
            'verifying' => '正在校验模型…',
            _ => '正在准备 AI Gallery…',
          }
        : '正在准备 AI Gallery…';
    return StateMessage(
        icon: isTransfer ? Icons.downloading_rounded : Icons.auto_awesome,
        title: label,
        body: isTransfer && progress != null
            ? '${(progress.received / 1000000).toStringAsFixed(1)} / ${(progress.total / 1000000).toStringAsFixed(1)} MB'
            : null,
        children: [
          if (isTransfer)
            ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                    value: progress?.fraction, minHeight: 6))
          else
            const SizedBox.square(
                dimension: 28,
                child: CircularProgressIndicator(strokeWidth: 2.5)),
          if (controller.downloadingModel && progress?.stage != 'ready')
            Padding(
                padding: const EdgeInsets.only(top: 12),
                child: TextButton(
                    onPressed: controller.pauseModelDownload,
                    child: const Text('暂停下载'))),
        ]);
  }
}

class ModelDownloadView extends StatelessWidget {
  const ModelDownloadView({super.key, required this.controller});
  final GalleryController controller;
  @override
  Widget build(BuildContext context) => StateMessage(
          icon: Icons.auto_awesome,
          title: '下载本地搜索模型',
          body:
              '首次使用需要下载约 ${(controller.service.modelBytes / 1000000).toStringAsFixed(0)} MB 的模型，建议连接 Wi-Fi。',
          children: [
            const _Feature(
                icon: Icons.chat_bubble_outline_rounded,
                text: '用自然语言描述画面，直接找到照片'),
            const _Feature(icon: Icons.wifi_off_rounded, text: '下载完成后可离线搜索'),
            const _Feature(
                icon: Icons.lock_outline_rounded, text: '照片只在本机分析，不会上传'),
            const SizedBox(height: 20),
            SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                    onPressed: controller.downloadModel,
                    icon: const Icon(Icons.download_rounded),
                    label: const Text('下载 / 继续下载'))),
          ]);
}

class _Feature extends StatelessWidget {
  const _Feature({required this.icon, required this.text});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: .1),
                borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, size: 17, color: scheme.primary)),
        const SizedBox(width: 12),
        Expanded(
            child: Text(text, style: Theme.of(context).textTheme.bodyMedium)),
      ]),
    );
  }
}
