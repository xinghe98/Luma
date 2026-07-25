// 作品详情页只负责路由首帧、资料刷新和收藏状态。
// 具体首屏与内容区由 widgets/ 下的组件承载，避免页面状态与展示结构互相耦合。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/models/api_catalog.dart';
import '../../data/repositories/catalog_repository.dart';
import '../../shared/states/error_state.dart';
import '../../shared/states/skeleton.dart';
import 'widgets/catalog_detail_content.dart';
import 'widgets/catalog_detail_theme.dart';

class CatalogDetailPage extends StatefulWidget {
  const CatalogDetailPage({
    super.key,
    required this.catalogId,
    this.initialItem,
    required this.repository,
    required this.onOpenMedia,
    required this.onOpenMediaFromStart,
  });

  final String catalogId;
  final CatalogItem? initialItem;
  final CatalogRepository repository;
  final ValueChanged<String> onOpenMedia;
  final ValueChanged<String> onOpenMediaFromStart;

  @override
  State<CatalogDetailPage> createState() => _CatalogDetailPageState();
}

class _CatalogDetailPageState extends State<CatalogDetailPage> {
  CatalogItem? _item;
  Object? _error;
  var _loading = true;
  var _savingFavorite = false;
  var _favorite = false;
  var _favoriteRevision = 0;

  @override
  void initState() {
    super.initState();
    _item = widget.initialItem;
    _syncFavorite(widget.initialItem);
    _load();
  }

  /// 刷新资料时保留首帧内容，避免网络波动造成详情页闪白。
  Future<void> _load() async {
    setState(() {
      _error = null;
      _loading = true;
    });
    try {
      final item = await widget.repository.detail(widget.catalogId);
      if (!mounted) return;
      setState(() {
        _item = item;
        _syncFavorite(item);
        _loading = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  void _syncFavorite(CatalogItem? item) {
    if (item == null) return;
    _favorite = item.favorite;
    _favoriteRevision = item.favoriteRevision;
  }

  /// 乐观保存作品级收藏，保存失败后恢复原值并告知用户。
  Future<void> _toggleFavorite() async {
    final item = _item;
    if (item == null || _savingFavorite) return;
    final wasFavorite = _favorite;
    final revision = _favoriteRevision;
    setState(() {
      _favorite = !wasFavorite;
      _savingFavorite = true;
    });
    try {
      final saved = await widget.repository.setFavorite(
        catalogId: item.id,
        favorite: !wasFavorite,
        revision: revision,
      );
      if (!mounted) return;
      setState(() {
        _favorite = saved.favorite;
        _favoriteRevision = saved.revision;
        _savingFavorite = false;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _favorite = wasFavorite;
        _savingFavorite = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('收藏暂未保存，请稍后重试')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = _item;
    return Scaffold(
      backgroundColor: item == null ? null : CatalogDetailPalette.background,
      extendBodyBehindAppBar: item != null,
      appBar: AppBar(
        title: item == null ? const Text('作品详情') : null,
        backgroundColor: item == null ? null : Colors.transparent,
        surfaceTintColor: Colors.transparent,
        foregroundColor: item == null ? null : CatalogDetailPalette.text,
        systemOverlayStyle: item == null ? null : SystemUiOverlayStyle.light,
        actions: [
          if (item != null)
            IconButton(
              onPressed: _savingFavorite ? null : _toggleFavorite,
              tooltip: _favorite ? '取消收藏' : '收藏',
              icon: Icon(
                _favorite
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
              ),
            ),
        ],
      ),
      body: item == null
          ? _error == null
                ? const DetailPageSkeleton(artworkAspectRatio: 16 / 9)
                : ErrorState(onRetry: _load)
          : Stack(
              children: [
                CatalogDetailContent(
                  item: item,
                  favorite: _favorite,
                  savingFavorite: _savingFavorite,
                  onPlay: widget.onOpenMedia,
                  onPlayFromStart: widget.onOpenMediaFromStart,
                  onToggleFavorite: _toggleFavorite,
                ),
                if (_loading)
                  const Align(
                    alignment: Alignment.topCenter,
                    child: LinearProgressIndicator(minHeight: 2),
                  ),
              ],
            ),
    );
  }
}
