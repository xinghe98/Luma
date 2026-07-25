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
        ? const SettingsListSkeleton(items: 5)
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
                    extra: issue,
                  );
                  if (changed == true) _load();
                },
              );
            },
          ),
  );
}

