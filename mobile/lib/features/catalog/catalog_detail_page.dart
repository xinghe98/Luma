// 作品详情页只负责路由首帧、资料刷新和收藏状态。
// 具体首屏与内容区由 widgets/ 下的组件承载，避免页面状态与展示结构互相耦合。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/route_transition.dart';
import '../../data/models/api_catalog.dart';
import '../../data/repositories/catalog_repository.dart';
import '../../shared/states/error_state.dart';
import '../../shared/states/skeleton.dart';
import 'catalog_store.dart';
import 'widgets/catalog_detail_content.dart';
import 'widgets/catalog_detail_theme.dart';

/// 展示电影或电视剧详情，并在可选的路由过渡结束后刷新完整资料。
class CatalogDetailPage extends StatefulWidget {
  /// 展示作品详情，优先保留路由首帧并在真实入场动画结束后刷新。
  const CatalogDetailPage({
    super.key,
    required this.catalogId,
    this.initialItem,
    this.heroTag,
    required this.repository,
    required this.onOpenMedia,
    required this.onOpenMediaFromStart,
  });

  final String catalogId;
  final CatalogItem? initialItem;
  final String? heroTag;

  final CatalogRepository repository;
  final ValueChanged<String> onOpenMedia;
  final ValueChanged<String> onOpenMediaFromStart;

  @override
  State<CatalogDetailPage> createState() => _CatalogDetailPageState();
}

class _CatalogDetailPageState extends State<CatalogDetailPage> {
  CatalogItem? _item;
  Object? _error;
  var _loading = false;
  var _savingFavorite = false;
  var _favorite = false;
  var _favoriteRevision = 0;
  var _loadDetailArtwork = false;
  var _loadGeneration = 0;
  var _favoriteGeneration = 0;
  var _initialLoadStarted = false;
  CatalogStore? _store;

  @override
  void initState() {
    super.initState();
    _store = widget.repository is CatalogStore
        ? widget.repository as CatalogStore
        : null;
    if (widget.initialItem case final initialItem?) {
      _store?.rememberAll([initialItem], notify: false);
    }
    _item = _store?.findById(widget.catalogId) ?? widget.initialItem;
    _syncFavorite(_item);
    _loading = widget.initialItem == null;
    _store?.addListener(_handleStoreChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialLoadStarted) return;
    _initialLoadStarted = true;
    _loadInitialDetail();
  }

  /// 等待真实路由动画后分别启动背景图与资料刷新，网络请求不会阻塞背景图。
  Future<void> _loadInitialDetail() async {
    await waitForRouteTransition(context);
    if (!mounted) return;
    if (!_loadDetailArtwork && _item != null) {
      setState(() => _loadDetailArtwork = true);
    }
    unawaited(_load());
  }

  /// 刷新资料时保留首帧内容，避免网络波动造成详情页闪白。
  Future<void> _load() async {
    final generation = ++_loadGeneration;
    if (mounted && (_error != null || !_loading)) {
      setState(() {
        _error = null;
        _loading = true;
      });
    } else {
      _error = null;
      _loading = true;
    }
    try {
      final item = await widget.repository.detail(widget.catalogId);
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _item = item;
        _loadDetailArtwork = true;
        if (!_savingFavorite && item.favoriteRevision >= _favoriteRevision) {
          _syncFavorite(item);
        }
        _loading = false;
      });
    } on Object catch (error) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  void _syncFavorite(CatalogItem? item) {
    if (item == null) return;
    final favorite = _store?.favoriteFor(item);
    _favorite = favorite?.favorite ?? item.favorite;
    _favoriteRevision = favorite?.revision ?? item.favoriteRevision;
  }

  void _handleStoreChanged() {
    if (!mounted) return;
    final store = _store!;
    final latest = store.findById(widget.catalogId);
    final favorite = latest == null ? null : store.favoriteFor(latest);
    final itemChanged = latest != null && !identical(latest, _item);
    final favoriteChanged =
        !_savingFavorite &&
        favorite != null &&
        favorite.revision >= _favoriteRevision &&
        (favorite.favorite != _favorite ||
            favorite.revision != _favoriteRevision);
    if (itemChanged || favoriteChanged) {
      setState(() {
        if (latest != null) _item = latest;
        if (favoriteChanged) {
          _favorite = favorite.favorite;
          _favoriteRevision = favorite.revision;
        }
      });
    }
    if (store.isItemInvalidated(widget.catalogId) && !_loading) {
      unawaited(_load());
    }
  }

  /// 乐观保存作品级收藏，保存失败后恢复原值并告知用户。
  Future<void> _toggleFavorite() async {
    final item = _item;
    if (item == null || _savingFavorite) return;
    final wasFavorite = _favorite;
    final revision = _favoriteRevision;
    final generation = ++_favoriteGeneration;
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
      if (!mounted || generation != _favoriteGeneration) return;
      setState(() {
        _favorite = saved.favorite;
        _favoriteRevision = saved.revision;
        _savingFavorite = false;
      });
    } on Object {
      if (!mounted || generation != _favoriteGeneration) return;
      setState(() {
        final refreshed = _item;
        if (refreshed != null && refreshed.favoriteRevision > revision) {
          _syncFavorite(refreshed);
        } else {
          _favorite = wasFavorite;
        }
        _savingFavorite = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('收藏暂未保存，请稍后重试')));
    }
  }

  @override
  void dispose() {
    _loadGeneration++;
    _favoriteGeneration++;
    _store?.removeListener(_handleStoreChanged);
    super.dispose();
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
                  heroTag: widget.heroTag,
                  loadDetailArtwork: _loadDetailArtwork,
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
                if (_error != null)
                  Positioned(
                    top: MediaQuery.paddingOf(context).top + kToolbarHeight,
                    left: 0,
                    right: 0,
                    child: MaterialBanner(
                      content: const Text('作品资料刷新失败，当前仍显示上次内容。'),
                      actions: [
                        TextButton(onPressed: _load, child: const Text('重试')),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}
