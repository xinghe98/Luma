import 'package:flutter/material.dart';

import '../../core/extensions.dart';
import '../../core/theme.dart';
import '../../data/models/api_access.dart';
import '../../data/repositories/access_repository.dart';
import '../../data/repositories/source_repository.dart';
import '../../shared/layout/constrained_page_list.dart';
import '../../shared/layout/section_header.dart';
import '../../shared/library/library_kind_presentation.dart';
import '../../shared/widgets/single_choice_sheet.dart';

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
  static const _libraryKindChoices = [
    BottomSheetChoice(
      value: 'personal',
      label: '个人视频',
      icon: Icons.video_library_outlined,
      description: '按文件夹和日期浏览',
    ),
    BottomSheetChoice(
      value: 'movies',
      label: '电影',
      icon: Icons.movie_outlined,
      description: '按影片信息整理',
    ),
    BottomSheetChoice(
      value: 'tv',
      label: '电视剧',
      icon: Icons.tv_outlined,
      description: '按剧、季和集整理',
    ),
  ];

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

  /// Lets the administrator choose a local video-organization rule for this
  /// form. The returned value stays local until [_submit] creates the source.
  Future<void> _selectLibraryKind() async {
    if (_submitting) return;
    final kind = await showSingleChoiceSheet<String>(
      context,
      title: '选择视频用途',
      supportingText: '决定扫描后视频的整理方式。',
      selectedValue: _libraryKind,
      choices: _libraryKindChoices,
    );
    if (!mounted || kind == null || kind == _libraryKind) return;
    setState(() => _libraryKind = kind);
  }

  /// Lets the administrator choose one server-approved root for this form.
  /// The returned path is submitted only from [_submit], never edited locally.
  Future<void> _selectRoot() async {
    final roots = _roots;
    if (_submitting || roots == null || roots.isEmpty) return;
    final root = await showSingleChoiceSheet<String>(
      context,
      title: '选择媒体目录',
      supportingText: '仅显示服务器已配置的目录。',
      selectedValue: _selectedRoot,
      choices: [
        for (final root in roots)
          BottomSheetChoice(
            value: root,
            label: root,
            icon: Icons.folder_outlined,
          ),
      ],
    );
    if (!mounted || root == null || root == _selectedRoot) return;
    setState(() => _selectedRoot = root);
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
          _SelectionField(
            label: '媒体目录',
            selectedValue: _selectedRoot,
            placeholder: '选择已配置的媒体目录',
            supportingText: '仅可选择服务器已配置的目录',
            icon: Icons.folder_outlined,
            enabled: !_submitting,
            onTap: _selectRoot,
          ),
        const SizedBox(height: LumaSpacing.lg),
        _SelectionField(
          label: '视频用途',
          selectedValue: LibraryKindPresentation.label(_libraryKind),
          placeholder: '选择视频用途',
          supportingText: '决定扫描后视频的整理方式',
          icon: Icons.category_outlined,
          enabled: !_submitting,
          onTap: _selectLibraryKind,
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

class _SelectionField extends StatelessWidget {
  const _SelectionField({
    required this.label,
    required this.selectedValue,
    required this.placeholder,
    required this.supportingText,
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final String? selectedValue;
  final String placeholder;
  final String supportingText;
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(LumaRadii.medium),
      side: BorderSide(color: scheme.outlineVariant.withAlpha(100)),
    );
    return Semantics(
      button: enabled,
      label: '$label，${selectedValue ?? placeholder}',
      child: Material(
        color: scheme.surfaceContainer,
        shape: shape,
        child: InkWell(
          borderRadius: BorderRadius.circular(LumaRadii.medium),
          onTap: enabled ? onTap : null,
          child: ListTile(
            enabled: enabled,
            leading: Icon(icon),
            title: Text(
              selectedValue ?? placeholder,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text('$label · $supportingText'),
            trailing: const Icon(Icons.expand_more_rounded),
          ),
        ),
      ),
    );
  }
}
