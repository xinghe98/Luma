import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../data/models/media_item.dart';
import '../../data/models/api_catalog.dart';
import '../../data/models/media_types.dart';
import '../details/dialogs/image_preview_dialog.dart';
import '../details/media_detail_page.dart';
import '../catalog/catalog_detail_page.dart';
import '../catalog/catalog_page.dart';
import '../home/home_page.dart';
import '../library/library_page.dart';
import '../player/player_page.dart';
import '../search/search_page.dart';
import '../settings/settings_page.dart';
import 'app_destination.dart';
import 'shell_controller.dart';
import 'widgets/adaptive_app_navigation.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  final _controller = ShellController();

  /// 按需创建 Tab 页，避免 IndexedStack 首帧同时构建全部库网格。
  final Map<AppDestination, Widget> _pages = {};
  var _didWarmSearch = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final selected = _controller.selected;
        _pages.putIfAbsent(selected, () => _buildPage(selected));
        _scheduleSearchWarmup();
        return AdaptiveAppNavigation(
          destination: selected,
          onSelect: _controller.select,
          content: IndexedStack(
            index: selected.index,
            children: AppDestination.values
                .map(
                  (destination) => TickerMode(
                    enabled: destination == selected,
                    child: _pages[destination] ?? const SizedBox.shrink(),
                  ),
                )
                .toList(growable: false),
          ),
        );
      },
    );
  }

  /// 首页首帧后再预创建搜索页，把构建成本挪出首次点击。
  void _scheduleSearchWarmup() {
    if (_didWarmSearch || _pages.containsKey(AppDestination.search)) return;
    _didWarmSearch = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _pages.containsKey(AppDestination.search)) return;
      setState(() {
        _pages[AppDestination.search] = _buildPage(AppDestination.search);
      });
    });
  }

  Widget _buildPage(AppDestination destination) => switch (destination) {
    AppDestination.home => HomePage(
      onOpenMedia: _openDetails,
      onOpenSearch: () => _controller.select(AppDestination.search),
    ),
    AppDestination.photos => LibraryPage(
      type: MediaType.image,
      onOpenMedia: _openImageViewer,
      onLongPressMedia: _openDetails,
      onOpenSearch: () => _controller.select(AppDestination.search),
    ),
    AppDestination.videos => CatalogPage(
      onOpenCatalog: _openCatalog,
      onOpenPersonalMedia: _openDetails,
      onOpenSearch: () => _controller.select(AppDestination.search),
    ),
    AppDestination.search => SearchPage(onOpenMedia: _openDetails),
    AppDestination.settings => const SettingsPage(),
  };

  void _openDetails(MediaItem item, {String? heroTag}) {
    // 库/搜索结果可能不在首页 media.items 中，先写入缓存再进详情。
    AppScope.of(context).media.remember(item);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MediaDetailPage(mediaId: item.id, heroTag: heroTag),
      ),
    );
  }

  void _openImageViewer(MediaItem item, {String? heroTag}) {
    AppScope.of(context).media.remember(item);
    showImagePreviewDialog(
      context,
      item,
      heroTag: heroTag,
      onOpenDetails: () => _openDetails(item, heroTag: heroTag),
    );
  }

  void _openCatalog(CatalogItem item) {
    final dependencies = AppScope.of(context);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CatalogDetailPage(
          catalogId: item.id,
          repository: dependencies.catalog,
          onOpenMedia: _openPlayerById,
        ),
      ),
    );
  }

  Future<void> _openPlayerById(String mediaId) async {
    final media = AppScope.of(context).media;
    await media.loadDetail(mediaId);
    if (!mounted) return;
    if (media.findById(mediaId) == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => PlayerPage(mediaId: mediaId)),
    );
  }
}
