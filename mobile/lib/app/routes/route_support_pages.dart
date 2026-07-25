import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/api_access.dart';
import '../../data/repositories/access_repository.dart';
import '../../data/repositories/source_repository.dart';
import '../../features/shell/app_destination.dart';
import '../../shared/states/empty_state.dart';
import '../../shared/states/skeleton.dart';

class UnavailableRoutePage extends StatelessWidget {
  const UnavailableRoutePage({
    super.key,
    required this.title,
    required this.message,
  });

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: EmptyState(
      icon: Icons.link_off_rounded,
      title: title,
      message: message,
      action: FilledButton(
        onPressed: () => context.go(AppDestination.settings.path),
        child: const Text('返回设置'),
      ),
    ),
  );
}

class AccessUserRoutePage extends StatefulWidget {
  const AccessUserRoutePage({
    super.key,
    required this.access,
    required this.sources,
    required this.userId,
    this.initialUser,
    required this.builder,
  });

  final AccessRepository access;
  final SourceRepository? sources;
  final String userId;
  final AccessUser? initialUser;
  final Widget Function(AccessUser user, SourceRepository sources) builder;

  @override
  State<AccessUserRoutePage> createState() => AccessUserRoutePageState();
}

class AccessUserRoutePageState extends State<AccessUserRoutePage> {
  Future<AccessUser?>? _request;

  @override
  void initState() {
    super.initState();
    _request = widget.initialUser == null ? _load() : null;
  }

  Future<AccessUser?> _load() async {
    final users = await widget.access.listUsers();
    for (final user in users) {
      if (user.id == widget.userId) return user;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final sources = widget.sources;
    if (sources == null) {
      return const UnavailableRoutePage(
        title: '成员与访问管理',
        message: '当前服务器不支持成员与访问管理。',
      );
    }
    final initialUser = widget.initialUser;
    if (initialUser != null) return widget.builder(initialUser, sources);
    return FutureBuilder<AccessUser?>(
      future: _request,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: SettingsListSkeleton(items: 3),
          );
        }
        if (snapshot.hasError) {
          return UnavailableRoutePage(
            title: '无法读取成员资料',
            message: '请检查服务器连接后重试。',
          );
        }
        final user = snapshot.data;
        if (user == null) {
          return const UnavailableRoutePage(
            title: '找不到成员',
            message: '该成员可能已被删除，或当前账号没有访问权限。',
          );
        }
        return widget.builder(user, sources);
      },
    );
  }
}
