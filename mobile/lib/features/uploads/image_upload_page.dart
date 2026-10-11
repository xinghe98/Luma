// 图片上传页：持有会话级 ImageUploadController，负责路由返回、
// 生命周期清理与状态呈现；选择/上传/重试的具体逻辑在 controller。
// 返回 bool：true 表示至少一张成功，供库页决定是否刷新。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/route_transition.dart';
import '../../core/theme.dart';
import '../../data/models/api_source.dart';
import '../../shared/states/empty_state.dart';
import '../../shared/states/error_state.dart';
import 'image_upload_controller.dart';
import 'widgets/pick_error_banner.dart';
import 'widgets/upload_action_bar.dart';
import 'widgets/upload_queue_list.dart';
import 'widgets/upload_queue_summary.dart';
import 'widgets/upload_source_selector.dart';

/// 本页返回 true 表示至少成功上传一张；false/null 表示无成功或被取消。
class ImageUploadPage extends StatefulWidget {
  const ImageUploadPage({super.key, required this.controller, this.onPop});

  /// 由父级按当前会话身份构建；页面负责 dispose。
  final ImageUploadController controller;

  /// 可选的路由返回处理；默认 `Navigator.maybePop(result)`。
  /// 测试或父路由需要拦截时注入。
  final void Function(bool result)? onPop;

  @override
  State<ImageUploadPage> createState() => _ImageUploadPageState();
}

class _ImageUploadPageState extends State<ImageUploadPage> {
  /// 确认框点了“放弃”后置 true，PopScope 放行一次真实出栈。
  bool _allowPop = false;
  bool _leaving = false;

  /// 离开确认对话框已在展示时置 true，防止连续 Back/Escape 叠多框。
  bool _confirming = false;

  /// 首次进入已自动拉起系统选图后置 true；取消/失败后不再重复自动弹。
  bool _autoPickAttempted = false;

  ImageUploadController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    unawaited(_enterThenLoad());
  }

  /// 入场转场落定后再拉来源；成功且非空时自动打开一次系统选图。
  Future<void> _enterThenLoad() async {
    await waitForRouteTransition(context);
    if (!mounted) return;
    await _controller.load();
    if (!mounted) return;
    _maybeAutoPick();
  }

  /// 来源就绪且非空时自动拉起一次选图；用户取消或失败都不再重复。
  void _maybeAutoPick() {
    if (_autoPickAttempted ||
        _controller.sourcesState != UploadSourcesState.ready ||
        (_controller.sources?.isEmpty ?? true)) {
      return;
    }
    _autoPickAttempted = true;
    unawaited(_controller.pickImages());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 确认离开：放行后先出栈再取消上传，已成功项不会因取消丢失。
  Future<void> _leave() async {
    if (_leaving || _confirming) return;
    final confirmed = await _confirmLeave();
    if (!confirmed || !mounted) return;
    _leaving = true;
    final result = _controller.hasSuccessfulUpload;
    final onPop = widget.onPop;
    if (onPop != null) {
      onPop(result);
      return;
    }
    // setState 只标记 PopScope 放行；真正出栈等下一帧新 widget 生效，
    // 避免旧 canPop=false 拦截后 _leaving 卡死。
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(
        Navigator.of(context).maybePop(result).whenComplete(() {
          if (mounted) setState(() => _allowPop = false);
        }),
      );
    });
  }

  /// 返回/离开前确认：仅仍有未完结上传且存在未成功项时提示。
  /// 已成功上传的项不会因取消而丢失，这里防止“误触丢弃在途/待传”。
  /// 返回 true 才允许继续离开；对话框重入由 [_confirming] 拦截。
  Future<bool> _confirmLeave() async {
    if (_leaving || _allowPop) return true;
    final hasUnfinished = _controller.uploading || _controller.hasPendingItems;
    if (!hasUnfinished) return true;
    _confirming = true;
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('放弃上传？'),
          content: Text(
            _controller.uploading ? '还有图片正在上传，确定要取消并离开吗？' : '还有未上传的图片，确定要离开吗？',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('继续上传'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('放弃'),
            ),
          ],
        ),
      );
      if (confirmed != true) return false;
      await _controller.cancel();
      return true;
    } finally {
      _confirming = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    // 普通路由页没有默认 Escape；显式注册让键盘与系统 Back 等价。
    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.escape): _LeaveUploadIntent(),
      },
      child: Actions(
        actions: {
          _LeaveUploadIntent: CallbackAction<_LeaveUploadIntent>(
            onInvoke: (_) {
              unawaited(_leave());
              return null;
            },
          ),
        },
        child: PopScope(
          canPop: _allowPop,
          onPopInvokedWithResult: (didPop, _) {
            if (didPop) return;
            unawaited(_leave());
          },
          child: Scaffold(
            appBar: AppBar(
              title: const Text('上传图片'),
              leading: IconButton(
                tooltip: '返回',
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () => unawaited(_leave()),
              ),
            ),
            body: SafeArea(
              child: ListenableBuilder(
                listenable: _controller,
                builder: (context, _) => _buildBody(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    final controller = _controller;
    final queue = controller.queue;
    final sourcesState = controller.sourcesState;
    final sources = controller.sources;

    // 会话已作废：显示冻结提示，队列只读展示，选图/上传均拒绝。
    if (controller.sessionInvalidated) {
      return Column(
        children: [
          ErrorState(
            compact: true,
            title: '会话已切换',
            message: '请返回媒体库重新进入上传。',
            retryLabel: '返回',
            onRetry: () => unawaited(_leave()),
          ),
          Expanded(
            child: queue.isEmpty
                ? const SizedBox.shrink()
                : Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: LumaLayout.contentMaxWidth,
                      ),
                      child: CustomScrollView(
                        slivers: [
                          SliverPadding(
                            padding: LumaLayout.pagePadding(
                              top: LumaSpacing.sm,
                            ),
                            sliver: SliverList.list(
                              children: [
                                UploadQueueSummary(
                                  count: controller.selectedCount,
                                  bytes: controller.totalBytes,
                                ),
                                const SizedBox(height: LumaSpacing.xs),
                              ],
                            ),
                          ),
                          SliverPadding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: LumaLayout.pagePaddingH,
                            ),
                            sliver: SliverList.builder(
                              itemCount: queue.length,
                              itemBuilder: (context, i) => UploadQueueTile(
                                key: ValueKey(queue[i].image.path),
                                entry: queue[i],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
        ],
      );
    }

    // 来源加载中或失败：已有队列时仍在列表上方提示，不隐藏已选文件；
    // 来源未就绪时不渲染选择器/选图按钮，防止空选。
    Widget? banner;
    List<Source>? pickerSources;
    var canPick = false;
    if (sourcesState == UploadSourcesState.loading && queue.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(LumaSpacing.lg),
        child: UploadSourcesSkeleton(),
      );
    }
    if (sourcesState == UploadSourcesState.loading) {
      banner = const LinearProgressIndicator(minHeight: 2);
    } else if (sourcesState == UploadSourcesState.error) {
      banner = ErrorState(
        compact: true,
        title: '媒体源刷新失败',
        message: controller.sourcesError?.toString() ?? '请稍后重试。',
        retryLabel: '重试',
        onRetry: controller.load,
      );
    } else {
      pickerSources = sources ?? const [];
      if (pickerSources.isEmpty) {
        banner = ErrorState(
          compact: true,
          title: '没有可用媒体源',
          message: '当前账号没有可上传的媒体源。',
          retryLabel: '重试',
          onRetry: controller.load,
        );
      } else {
        canPick = true;
      }
    }

    return Column(
      children: [
        ?banner,
        if (controller.pickError case final message?)
          PickErrorBanner(
            message: message,
            onDismiss: controller.clearPickError,
          ),
        Expanded(
          // 队列缩略图须惰性构建：for+children 会让所有本地图片同时活跃解码。
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: LumaLayout.contentMaxWidth,
              ),
              child: CustomScrollView(
                slivers: [
                  SliverPadding(
                    padding: LumaLayout.pagePadding(top: LumaSpacing.sm),
                    sliver: SliverList.list(
                      children: [
                        if (pickerSources != null &&
                            pickerSources.isNotEmpty) ...[
                          UploadSourceSelector(
                            sources: pickerSources,
                            selectedSourceId: controller.selectedSourceId,
                            enabled: !controller.uploading,
                            onSelected: controller.selectSource,
                          ),
                          const SizedBox(height: LumaSpacing.lg),
                        ],
                        if (queue.isEmpty)
                          EmptyState(
                            icon: Icons.add_photo_alternate_outlined,
                            title: '还没有选择图片',
                            message: canPick
                                ? '支持 JPG / PNG / GIF / WebP / BMP，单张不超过 64 MB。'
                                : '媒体源就绪后可选择图片上传。',
                          )
                        else
                          UploadQueueSummary(
                            count: controller.selectedCount,
                            bytes: controller.totalBytes,
                          ),
                        const SizedBox(height: LumaSpacing.xs),
                      ],
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: LumaLayout.pagePaddingH,
                    ),
                    sliver: SliverList.builder(
                      itemCount: queue.length,
                      itemBuilder: (context, i) {
                        final entry = queue[i];
                        return UploadQueueTile(
                          key: ValueKey(entry.image.path),
                          entry: entry,
                          onRemove:
                              controller.uploading ||
                                  entry.status != ImageUploadStatus.pending
                              ? null
                              : () => controller.removeAt(i),
                        );
                      },
                    ),
                  ),
                  const SliverToBoxAdapter(
                    child: SizedBox(height: LumaSpacing.lg),
                  ),
                ],
              ),
            ),
          ),
        ),
        UploadActionBar(
          canPick: canPick,
          controller: controller,
          onPick: () => unawaited(controller.pickImages()),
          onStart: () => unawaited(controller.start()),
          onRetry: () => unawaited(controller.retryFailed()),
          onDone: () => unawaited(_leave()),
        ),
      ],
    );
  }
}

/// Escape/Back 共用意图：路由页自身把它转成离开确认流程。
class _LeaveUploadIntent extends Intent {
  const _LeaveUploadIntent();
}
