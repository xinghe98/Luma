import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_router.dart';
import '../../../core/theme.dart';
import '../../../data/models/api_catalog.dart';
import '../../../data/repositories/catalog_repository.dart';
import '../../../shared/states/empty_state.dart';
import '../../../shared/states/error_state.dart';
import '../../../shared/states/skeleton.dart';

class OrganizationPage extends StatefulWidget {
  const OrganizationPage({super.key, required this.repository});

  final CatalogRepository repository;

  @override
  State<OrganizationPage> createState() => _OrganizationPageState();
}

class _OrganizationPageState extends State<OrganizationPage> {
  List<CatalogIssue>? _issues;
  Object? _error;
  bool _loading = false;

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
      if (mounted) setState(() => _issues = issues);
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('待整理文件'),
      actions: [
        IconButton(
          tooltip: '刷新待整理文件',
          onPressed: _loading ? null : _load,
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
    ),
    body: _buildBody(),
  );

  Widget _buildBody() {
    final issues = _issues;
    if (issues == null) {
      if (_error != null) {
        return ErrorState(
          title: '无法读取待整理文件',
          message: '请检查服务器连接后重试。',
          onRetry: _load,
        );
      }
      return const SettingsListSkeleton(items: 5);
    }
    final content = issues.isEmpty
        ? const EmptyState(
            icon: Icons.task_alt_rounded,
            title: '媒体库已整理',
            message: '没有需要人工确认的电影或剧集文件。',
          )
        : ListView.separated(
            padding: LumaLayout.pagePadding(top: LumaSpacing.xs),
            itemCount: issues.length,
            separatorBuilder: (_, _) => const Divider(),
            itemBuilder: (context, index) {
              final issue = issues[index];
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
                    extra: issue,
                  );
                  if (changed == true) _load();
                },
              );
            },
          );
    return Column(
      children: [
        if (_loading) const LinearProgressIndicator(minHeight: 2),
        if (_error != null)
          ErrorState(
            compact: true,
            title: '待整理文件刷新失败',
            message: '当前仍显示上次成功加载的内容。',
            retryLabel: '重试刷新',
            onRetry: _load,
          ),
        Expanded(child: content),
      ],
    );
  }
}
