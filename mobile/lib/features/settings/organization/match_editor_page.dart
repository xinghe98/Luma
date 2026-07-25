import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../data/models/api_catalog.dart';
import '../../../data/repositories/catalog_repository.dart';

class OrganizationMatchEditorPage extends StatefulWidget {
  const OrganizationMatchEditorPage({
    super.key,
    required this.issue,
    required this.repository,
  });

  final CatalogIssue issue;
  final CatalogRepository repository;

  @override
  State<OrganizationMatchEditorPage> createState() =>
      _OrganizationMatchEditorPageState();
}

class _OrganizationMatchEditorPageState
    extends State<OrganizationMatchEditorPage> {
  late final TextEditingController _title;
  late final TextEditingController _year;
  late final TextEditingController _season;
  late final TextEditingController _episode;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.issue.suggestedTitle);
    _year = TextEditingController();
    _season = TextEditingController(
      text: widget.issue.seasonNumber?.toString() ?? '1',
    );
    _episode = TextEditingController(
      text: widget.issue.episodeNumber?.toString() ?? '1',
    );
  }

  @override
  void dispose() {
    _title.dispose();
    _year.dispose();
    _season.dispose();
    _episode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isSeries = widget.issue.libraryKind == 'tv';
    return Scaffold(
      appBar: AppBar(title: const Text('确认归属')),
      body: ListView(
        padding: LumaLayout.pagePadding(top: LumaSpacing.sm),
        children: [
          Text(
            widget.issue.filename,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: LumaSpacing.lg),
          TextField(
            controller: _title,
            decoration: InputDecoration(labelText: isSeries ? '剧名' : '电影名'),
          ),
          const SizedBox(height: LumaSpacing.md),
          TextField(
            controller: _year,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: '年份（可选）'),
          ),
          if (isSeries) ...[
            const SizedBox(height: LumaSpacing.md),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _season,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: '季'),
                  ),
                ),
                const SizedBox(width: LumaSpacing.md),
                Expanded(
                  child: TextField(
                    controller: _episode,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: '集'),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: LumaSpacing.lg),
          FilledButton(
            onPressed: _saving ? null : () => _save(isSeries),
            child: Text(_saving ? '正在保存' : '保存匹配'),
          ),
          TextButton(
            onPressed: _saving ? null : _ignore,
            child: const Text('忽略这个文件'),
          ),
        ],
      ),
    );
  }

  Future<void> _save(bool isSeries) async {
    if (_title.text.trim().isEmpty) return;
    setState(() => _saving = true);
    try {
      await widget.repository.updateMatch(
        mediaId: widget.issue.mediaId,
        kind: isSeries ? CatalogKind.series : CatalogKind.movie,
        title: _title.text.trim(),
        year: int.tryParse(_year.text),
        seasonNumber: isSeries ? int.tryParse(_season.text) : null,
        episodeNumber: isSeries ? int.tryParse(_episode.text) : null,
      );
      if (mounted) Navigator.of(context).pop(true);
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('保存失败：$error')));
      setState(() => _saving = false);
    }
  }

  Future<void> _ignore() async {
    setState(() => _saving = true);
    try {
      await widget.repository.ignore(widget.issue.mediaId);
      if (mounted) Navigator.of(context).pop(true);
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('操作失败：$error')));
      setState(() => _saving = false);
    }
  }
}

