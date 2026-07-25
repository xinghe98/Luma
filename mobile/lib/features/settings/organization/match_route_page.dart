// Organization match routing resolves deep links that arrive without an issue extra.
// It preserves a stable loading and error page until it can build the editor.
import 'package:flutter/material.dart';

import '../../../data/models/api_catalog.dart';
import '../../../data/repositories/catalog_repository.dart';
import '../../../shared/states/empty_state.dart';
import '../../../shared/states/error_state.dart';
import '../../../shared/states/skeleton.dart';
import 'match_editor_page.dart';

class OrganizationMatchRoutePage extends StatefulWidget {
  const OrganizationMatchRoutePage({
    super.key,
    required this.repository,
    required this.mediaId,
    this.initialIssue,
  });

  final CatalogRepository repository;
  final String mediaId;
  final CatalogIssue? initialIssue;

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
    _issue = widget.initialIssue;
    _loading = _issue == null;
    if (_issue == null) _load();
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
          ? const SettingsListSkeleton(items: 3)
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


