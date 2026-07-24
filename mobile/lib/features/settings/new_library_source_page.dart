import 'package:flutter/material.dart';

import '../../core/extensions.dart';
import '../../core/theme.dart';
import '../../data/models/api_access.dart';
import '../../data/repositories/access_repository.dart';
import '../../data/repositories/source_repository.dart';
import '../../shared/layout/constrained_page_list.dart';
import '../../shared/layout/section_header.dart';
import '../../shared/library/library_kind_presentation.dart';

// Collects the administrator-only data needed to create a server-local source.
class NewLibrarySourcePage extends StatefulWidget {
  const NewLibrarySourcePage({
    super.key,
    required this.sources,
    required this.access,
  });

  final MutableSourceRepository sources;
  final AccessRepository access;

  @override
  State<NewLibrarySourcePage> createState() => _NewLibrarySourcePageState();
}

class _NewLibrarySourcePageState extends State<NewLibrarySourcePage> {
  final _name = TextEditingController();
  final _selectedUsers = <String>{};
  List<AccessUser>? _users;
  List<String>? _roots;
  Object? _loadError;
  Object? _rootsLoadError;
  bool _submitting = false;
  String _libraryKind = 'personal';
  String? _selectedRoot;

  @override
  void initState() {
    super.initState();
    _loadUsers();
    _loadRoots();
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  /// Loads the server-configured paths that an administrator may select.
  /// A failure keeps the form visible and offers a local retry for this field.
  Future<void> _loadRoots() async {
    setState(() => _rootsLoadError = null);
    try {
      final roots = await widget.sources.listAvailableRoots();
      if (!mounted) return;
      setState(() => _roots = roots);
    } on Object catch (error) {
      if (mounted) setState(() => _rootsLoadError = error);
    }
  }

  Future<void> _loadUsers() async {
    setState(() => _loadError = null);
    try {
      final users = await widget.access.listUsers();
      if (!mounted) return;
      setState(() {
        _users = users
            .where((user) => !user.isAdmin && user.enabled)
            .toList(growable: false);
      });
    } on Object catch (error) {
      if (mounted) setState(() => _loadError = error);
    }
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final name = _name.text.trim();
    final rootPath = _selectedRoot;
    if (name.isEmpty) {
      context.showLumaSnack('请输入媒体源名称');
      return;
    }
    if (rootPath == null) {
      context.showLumaSnack('请选择媒体目录');
      return;
    }
    setState(() => _submitting = true);
    try {
      final created = await widget.sources.createManagedSource(
        name: name,
        rootPath: rootPath,
        libraryKind: _libraryKind,
        userIds: _selectedUsers.toList(growable: false),
      );
      if (mounted) Navigator.of(context).pop(created);
    } on Object catch (error) {
      if (mounted) context.showLumaSnack('新增失败：$error');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('新增媒体源')),
    body: ConstrainedPageList(
      padding: LumaLayout.pagePadding(top: LumaSpacing.sm),
      children: [
        Text(
          '选择已由服务端配置的媒体目录。保存后会立即开始首次扫描。',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: LumaSpacing.lg),
        TextField(
          controller: _name,
          enabled: !_submitting,
          maxLength: 200,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(
            labelText: '媒体源名称',
            hintText: '例如：家庭影片',
            prefixIcon: Icon(Icons.drive_file_rename_outline),
          ),
        ),
        const SizedBox(height: LumaSpacing.md),
        if (_rootsLoadError != null)
          TextButton.icon(
            onPressed: _submitting ? null : _loadRoots,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('无法读取可用媒体目录，点击重试'),
          )
        else if (_roots == null)
          const _RootSelectorSkeleton()
        else if (_roots!.isEmpty)
          Text(
            '服务端尚未配置可用媒体目录。请在服务端的 security.allowed_roots 中添加目录后重试。',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          )
        else
          DropdownButtonFormField<String>(
            initialValue: _selectedRoot,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: '媒体目录',
              prefixIcon: Icon(Icons.folder_outlined),
            ),
            hint: const Text('选择已配置的媒体目录'),
            items: _roots!
                .map((root) => DropdownMenuItem(value: root, child: Text(root)))
                .toList(growable: false),
            onChanged: _submitting
                ? null
                : (root) => setState(() => _selectedRoot = root),
          ),
        const SizedBox(height: LumaSpacing.lg),
        const SectionHeader(title: '视频用途'),
        const SizedBox(height: LumaSpacing.xs),
        DropdownButtonFormField<String>(
          initialValue: _libraryKind,
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.category_outlined),
          ),
          items: const ['personal', 'movies', 'tv']
              .map(
                (kind) => DropdownMenuItem(
                  value: kind,
                  child: Text(LibraryKindPresentation.label(kind)),
                ),
              )
              .toList(growable: false),
          onChanged: _submitting
              ? null
              : (kind) => setState(() => _libraryKind = kind!),
        ),
        const SizedBox(height: LumaSpacing.lg),
        const SectionHeader(title: '可访问成员'),
        const SizedBox(height: LumaSpacing.xs),
        if (_loadError != null)
          TextButton.icon(
            onPressed: _submitting ? null : _loadUsers,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('无法读取成员，点击重试'),
          )
        else if (_users == null)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: LumaSpacing.md),
            child: LinearProgressIndicator(),
          )
        else if (_users!.isEmpty)
          Text(
            '没有可授权的成员。新媒体源暂时仅管理员可见。',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          )
        else
          ..._users!.map(
            (user) => CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _selectedUsers.contains(user.id),
              onChanged: _submitting
                  ? null
                  : (selected) => setState(() {
                      if (selected == true) {
                        _selectedUsers.add(user.id);
                      } else {
                        _selectedUsers.remove(user.id);
                      }
                    }),
              title: Text(user.name),
              controlAffinity: ListTileControlAffinity.leading,
            ),
          ),
        const SizedBox(height: LumaSpacing.lg),
        FilledButton.icon(
          onPressed: _submitting || _roots?.isEmpty != false ? null : _submit,
          icon: _submitting
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.create_new_folder_outlined),
          label: Text(_submitting ? '正在新增' : '新增并开始扫描'),
        ),
      ],
    ),
  );
}

class _RootSelectorSkeleton extends StatelessWidget {
  const _RootSelectorSkeleton();

  @override
  Widget build(BuildContext context) => const InputDecorator(
    decoration: InputDecoration(
      labelText: '媒体目录',
      prefixIcon: Icon(Icons.folder_outlined),
    ),
    child: LinearProgressIndicator(),
  );
}
