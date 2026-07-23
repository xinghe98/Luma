import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../data/models/api_source.dart';
import '../../data/repositories/source_repository.dart';
import '../../shared/states/error_state.dart';
import '../../shared/library/library_kind_presentation.dart';

class LibrarySourcesPage extends StatefulWidget {
  const LibrarySourcesPage({super.key, required this.repository});

  final MutableSourceRepository repository;

  @override
  State<LibrarySourcesPage> createState() => _LibrarySourcesPageState();
}

class _LibrarySourcesPageState extends State<LibrarySourcesPage> {
  List<Source>? _sources;
  Object? _error;
  final Set<String> _saving = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final sources = await widget.repository.list(refresh: true);
      if (mounted) setState(() => _sources = sources);
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  Future<void> _change(Source source, String kind) async {
    setState(() => _saving.add(source.id));
    try {
      final updated = await widget.repository.updateLibraryKind(
        source.id,
        kind,
      );
      if (!mounted) return;
      setState(() {
        _sources = [
          for (final item in _sources!) item.id == source.id ? updated : item,
        ];
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('视频用途已更新，重新扫描后作品库会自动整理')));
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('更新失败：$error')));
    } finally {
      if (mounted) setState(() => _saving.remove(source.id));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('媒体源类型')),
    body: _error != null
        ? ErrorState(onRetry: _load)
        : _sources == null
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: LumaLayout.pagePadding(top: LumaSpacing.sm),
            children: [
              Text(
                '请选择目录中视频的用途。目录及子目录中的图片会自动进入图片库；电影和电视剧会按作品、季和集自动整理。',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: LumaSpacing.lg),
              for (final source in _sources!)
                Padding(
                  padding: const EdgeInsets.only(bottom: LumaSpacing.sm),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                    leading: Icon(LibraryKindPresentation.icon(source.libraryKind)),
                    title: Text(source.name),
                    subtitle: Text('${LibraryKindPresentation.label(source.libraryKind)}库'),
                    trailing: _saving.contains(source.id)
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : PopupMenuButton<String>(
                            tooltip: '修改视频用途',
                            initialValue: source.libraryKind,
                            onSelected: (value) => _change(source, value),
                            itemBuilder: (_) => const [
                              PopupMenuItem(
                                value: 'personal',
                                child: Text('个人视频'),
                              ),
                              PopupMenuItem(value: 'movies', child: Text('电影')),
                              PopupMenuItem(value: 'tv', child: Text('电视剧')),
                            ],
                          ),
                  ),
                ),
            ],
          ),
  );
}
