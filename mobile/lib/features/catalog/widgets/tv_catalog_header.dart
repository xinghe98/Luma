// TV 影视库页头：承接页面导航回调，按局部宽度重排操作；不持有控制器或焦点生命周期。
import 'package:flutter/material.dart';

import '../../../core/theme.dart';

/// 影视库总览标题与分类入口，分类回调由页面携带已加载数据。
class TvCatalogHeader extends StatelessWidget {
  const TvCatalogHeader({
    super.key,
    required this.onSearch,
    required this.onRefresh,
    required this.onMovies,
    required this.onSeries,
    required this.onPersonalVideos,
  });

  final VoidCallback onSearch;
  final VoidCallback onRefresh;
  final VoidCallback onMovies;
  final VoidCallback onSeries;
  final VoidCallback onPersonalVideos;

  @override
  Widget build(BuildContext context) {
    final categories = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        OutlinedButton(
          key: const ValueKey('tv-category-movies'),
          onPressed: onMovies,
          child: const Text('电影'),
        ),
        const SizedBox(width: 12),
        OutlinedButton(
          key: const ValueKey('tv-category-series'),
          onPressed: onSeries,
          child: const Text('电视剧'),
        ),
        const SizedBox(width: 12),
        OutlinedButton(
          key: const ValueKey('tv-category-personal'),
          onPressed: onPersonalVideos,
          child: const Text('个人视频'),
        ),
      ],
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        LumaLayout.pagePaddingH,
        8,
        LumaLayout.pagePaddingH,
        4,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final masthead = _CatalogMasthead(
            title: '影视库',
            onSearch: onSearch,
            onRefresh: onRefresh,
            refreshLabel: '刷新影视库',
          );
          if (constraints.maxWidth < 860) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                masthead,
                const SizedBox(height: 12),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: categories,
                ),
              ],
            );
          }
          return Row(
            children: [
              Text('影视库', style: Theme.of(context).textTheme.headlineLarge),
              const SizedBox(width: 24),
              categories,
              const Spacer(),
              Tooltip(
                message: '搜索',
                child: TextButton.icon(
                  onPressed: onSearch,
                  icon: const Icon(Icons.search_rounded),
                  label: const Text('搜索'),
                ),
              ),
              Tooltip(
                message: '刷新影视库',
                child: TextButton.icon(
                  onPressed: onRefresh,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('刷新影视库'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// 完整分类页的返回、标题和显式搜索/刷新操作。
class TvCatalogCollectionHeader extends StatelessWidget {
  const TvCatalogCollectionHeader({
    super.key,
    required this.title,
    required this.onSearch,
    required this.onRefresh,
  });

  final String title;
  final VoidCallback onSearch;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      LumaLayout.pagePaddingH,
      16,
      LumaLayout.pagePaddingH,
      24,
    ),
    child: _CatalogMasthead(
      title: title,
      onSearch: onSearch,
      onRefresh: onRefresh,
      showBack: true,
    ),
  );
}

class _CatalogMasthead extends StatelessWidget {
  const _CatalogMasthead({
    required this.title,
    required this.onSearch,
    required this.onRefresh,
    this.showBack = false,
    this.refreshLabel = '刷新',
  });

  final String title;
  final VoidCallback onSearch;
  final VoidCallback onRefresh;
  final bool showBack;
  final String refreshLabel;

  @override
  Widget build(BuildContext context) {
    final heading = Row(
      children: [
        if (showBack) ...[const BackButton(), const SizedBox(width: 12)],
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.headlineLarge),
        ),
      ],
    );
    final actions = Wrap(
      spacing: 12,
      runSpacing: 8,
      children: [
        Tooltip(
          message: '搜索',
          child: TextButton.icon(
            onPressed: onSearch,
            icon: const Icon(Icons.search_rounded),
            label: const Text('搜索'),
          ),
        ),
        Tooltip(
          message: refreshLabel,
          child: TextButton.icon(
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh_rounded),
            label: Text(refreshLabel),
          ),
        ),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact =
            constraints.maxWidth <
            640 * MediaQuery.textScalerOf(context).scale(18) / 18;
        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [heading, const SizedBox(height: 12), actions],
          );
        }
        return Row(
          children: [
            Expanded(child: heading),
            const SizedBox(width: 16),
            actions,
          ],
        );
      },
    );
  }
}
