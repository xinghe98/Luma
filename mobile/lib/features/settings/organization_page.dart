import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_router.dart';
import '../../core/theme.dart';
import '../../data/models/api_catalog.dart';
import '../../data/repositories/catalog_repository.dart';
import '../../shared/states/empty_state.dart';
import '../../shared/states/error_state.dart';

class OrganizationPage extends StatefulWidget {
  const OrganizationPage({super.key, required this.repository});

  final CatalogRepository repository;

  @override
  State<OrganizationPage> createState() => _OrganizationPageState();
}

class _OrganizationPageState extends State<OrganizationPage> {
  List<CatalogIssue>? _issues;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final issues = await widget.repository.issues();
      if (mounted) setState(() => _issues = issues);
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('待整理文件')),
    body: _error != null
        ? ErrorState(onRetry: _load)
        : _issues == null
        ? const Center(child: CircularProgressIndicator())
        : _issues!.isEmpty
        ? const EmptyState(
            icon: Icons.task_alt_rounded,
            title: '媒体库已整理',
            message: '没有需要人工确认的电影或剧集文件。',
          )
        : ListView.separated(
            padding: LumaLayout.pagePadding(top: LumaSpacing.xs),
            itemCount: _issues!.length,
            separatorBuilder: (_, _) => const Divider(),
            itemBuilder: (context, index) {
              final issue = _issues![index];
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.rule_folder_outlined),
                title: Text(issue.filename),
                subtitle: Text(
                  issue.libraryKind == 'tv' ? '未识别到季号或集号' : '需要确认电影名称',
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () async {
                  final changed = await context.pushNamed<bool>(
                    AppRoute.organizationEditor,
                    pathParameters: {'mediaId': issue.mediaId},
                  );
                  if (changed == true) _load();
                },
              );
            },
          ),
  );
}

class OrganizationMatchRoutePage extends StatefulWidget {
  const OrganizationMatchRoutePage({
    super.key,
    required this.repository,
    required this.mediaId,
  });

  final CatalogRepository repository;
  final String mediaId;

  @override
  State<OrganizationMatchRoutePage> createState() =>
      _OrganizationMatchRoutePageState();
}

class _OrganizationMatchRoutePageState
    extends State<OrganizationMatchRoutePage> {
  CatalogIssue? _issue;
  Object? _error;
  var _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _error = null;
      _loading = true;
    });
    try {
      final issues = await widget.repository.issues();
      CatalogIssue? match;
      for (final issue in issues) {
        if (issue.mediaId == widget.mediaId) {
          match = issue;
          break;
        }
      }
      if (mounted) {
        setState(() {
          _issue = match;
          _loading = false;
        });
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _error = error;
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final issue = _issue;
    if (issue != null) {
      return OrganizationMatchEditorPage(
        issue: issue,
        repository: widget.repository,
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('确认归属')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? ErrorState(onRetry: _load)
          : const EmptyState(
              icon: Icons.task_alt_rounded,
              title: '文件已处理',
              message: '该文件不再需要人工确认。',
            ),
    );
  }
}

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
