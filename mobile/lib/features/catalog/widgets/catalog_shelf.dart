part of '../catalog_page.dart';

class _CatalogShelfSection extends StatelessWidget {
  const _CatalogShelfSection({
    required this.title,
    required this.controller,
    required this.onOpenCatalog,
    required this.onOpenAll,
  });

  final String title;
  final CatalogController controller;
  final CatalogOpenCallback onOpenCatalog;
  final ValueChanged<List<CatalogItem>> onOpenAll;

  @override
  Widget build(BuildContext context) {
    void openAll() =>
        onOpenAll(controller.items.take(12).toList(growable: false));
    if (controller.items.isEmpty &&
        controller.state == CatalogLoadState.error) {
      return _CatalogSectionIssue(
        title: title,
        onRetry: controller.load,
        onOpenAll: openAll,
      );
    }
    if (controller.items.isEmpty &&
        controller.state != CatalogLoadState.ready) {
      return _CatalogShelfPlaceholder(title: title, onOpenAll: openAll);
    }
    if (controller.items.isEmpty) {
      return _CatalogSectionEmpty(title: title, onOpenAll: openAll);
    }
    return _CatalogShelf(
      title: title,
      items: controller.items,
      onOpenCatalog: onOpenCatalog,
      onOpenAll: openAll,
      loading: controller.state == CatalogLoadState.loading,
      hasError: controller.state == CatalogLoadState.error,
      onRetry: controller.load,
    );
  }
}

class _CatalogShelfPlaceholder extends StatelessWidget {
  const _CatalogShelfPlaceholder({
    required this.title,
    required this.onOpenAll,
  });

  final String title;
  final VoidCallback onOpenAll;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: LumaSpacing.lg),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeading(title: title, onOpenAll: onOpenAll),
        const SizedBox(height: LumaSpacing.md),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: LumaLayout.pagePaddingH),
          child: SizedBox(
            height: 262,
            child: Row(
              children: [
                Expanded(
                  child: SkeletonBox(
                    height: double.infinity,
                    radius: LumaRadii.large,
                  ),
                ),
                SizedBox(width: LumaSpacing.md),
                Expanded(
                  child: SkeletonBox(
                    height: double.infinity,
                    radius: LumaRadii.large,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

class _CatalogSectionIssue extends StatelessWidget {
  const _CatalogSectionIssue({
    required this.title,
    required this.onRetry,
    required this.onOpenAll,
  });

  final String title;
  final VoidCallback onRetry;
  final VoidCallback onOpenAll;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: LumaSpacing.lg),
    child: Column(
      children: [
        _SectionHeading(title: title, onOpenAll: onOpenAll),
        SizedBox(
          height: 262,
          child: Center(
            child: TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('加载失败，轻触重试'),
            ),
          ),
        ),
      ],
    ),
  );
}

class _CatalogSectionEmpty extends StatelessWidget {
  const _CatalogSectionEmpty({required this.title, required this.onOpenAll});

  final String title;
  final VoidCallback onOpenAll;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: LumaSpacing.lg),
    child: Column(
      children: [
        _SectionHeading(title: title, onOpenAll: onOpenAll),
        SizedBox(
          height: 108,
          child: Center(
            child: Text(
              '暂时没有$title',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

class _CatalogShelf extends StatelessWidget {
  const _CatalogShelf({
    required this.title,
    required this.items,
    required this.onOpenCatalog,
    required this.onOpenAll,
    required this.loading,
    required this.hasError,
    required this.onRetry,
  });

  final String title;
  final List<CatalogItem> items;
  final CatalogOpenCallback onOpenCatalog;
  final VoidCallback onOpenAll;
  final bool loading;
  final bool hasError;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: LumaSpacing.lg),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeading(title: title, onOpenAll: onOpenAll),
        if (loading)
          const Padding(
            padding: EdgeInsets.only(top: LumaSpacing.xs),
            child: LinearProgressIndicator(minHeight: 2),
          )
        else if (hasError)
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: LumaLayout.pagePaddingH,
              ),
              child: TextButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('刷新失败，当前保留上次内容'),
              ),
            ),
          ),
        const SizedBox(height: LumaSpacing.md),
        SizedBox(
          height: 262,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(
              horizontal: LumaLayout.pagePaddingH,
            ),
            scrollDirection: Axis.horizontal,
            itemCount: items.length.clamp(0, 12),
            separatorBuilder: (_, _) => const SizedBox(width: LumaSpacing.md),
            itemBuilder: (context, index) {
              final item = items[index];
              final heroTag = CatalogCard.heroTagFor(item);
              return SizedBox(
                width: 138,
                child: CatalogCard(
                  item: item,
                  heroTag: heroTag,
                  onTap: () => onOpenCatalog(item, heroTag: heroTag),
                ),
              );
            },
          ),
        ),
      ],
    ),
  );
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.title, required this.onOpenAll});

  final String title;
  final VoidCallback onOpenAll;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: LumaLayout.pagePaddingH),
    child: SectionHeader(
      title: title,
      action: TextButton(
        onPressed: onOpenAll,
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [Text('查看全部'), Icon(Icons.chevron_right_rounded)],
        ),
      ),
    ),
  );
}
