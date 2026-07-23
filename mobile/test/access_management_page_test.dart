import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/app/app_dependencies.dart';
import 'package:luma/app/app_scope.dart';
import 'package:luma/data/mock/mock_media_repository.dart';
import 'package:luma/data/models/api_access.dart';
import 'package:luma/data/models/api_source.dart';
import 'package:luma/data/models/server_profile.dart';
import 'package:luma/data/repositories/access_repository.dart';
import 'package:luma/data/repositories/source_repository.dart';
import 'package:luma/data/services/connection_service.dart';
import 'package:luma/features/settings/access/member_detail_page.dart';
import 'package:luma/features/settings/access/access_management_page.dart';
import 'package:luma/features/settings/access/new_member_page.dart';
import 'package:luma/features/settings/settings_page.dart';

void main() {
  testWidgets('settings hides access management from a member', (tester) async {
    final dependencies = _dependencies(
      profile: _profile(role: 'member', capabilities: const ['media.read']),
    );
    addTearDown(dependencies.dispose);

    await tester.pumpWidget(
      AppScope(
        dependencies: dependencies,
        child: const MaterialApp(home: SettingsPage()),
      ),
    );

    expect(find.text('成员与访问管理'), findsNothing);
  });

  testWidgets('settings exposes access management to an authorized admin', (
    tester,
  ) async {
    final dependencies = _dependencies(
      profile: _profile(
        role: 'admin',
        capabilities: const ['users.manage', 'sources.manage'],
      ),
    );
    addTearDown(dependencies.dispose);

    await tester.pumpWidget(
      AppScope(
        dependencies: dependencies,
        child: const MaterialApp(home: SettingsPage()),
      ),
    );

    expect(find.text('成员与访问管理'), findsOneWidget);
  });

  testWidgets(
    'access management identifies recently active members as online',
    (tester) async {
      final access = _FakeAccessRepository()
        ..users = [_user(name: 'Alice', online: true)];
      await tester.pumpWidget(
        MaterialApp(
          home: AccessManagementPage(
            access: access,
            sources: _FakeSourceRepository(),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('成员 · 已启用 · 在线'), findsOneWidget);
    },
  );

  testWidgets('new member workflow grants sources before issuing its token', (
    tester,
  ) async {
    _useTallViewport(tester);
    final access = _FakeAccessRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: NewMemberPage(access: access, sources: _FakeSourceRepository()),
      ),
    );
    await tester.pump();

    await tester.enterText(find.byType(TextField).at(0), 'Alice');
    await tester.tap(find.byType(CheckboxListTile).at(0));
    await tester.enterText(find.byType(TextField).at(1), 'Alice 的手机');
    await tester.ensureVisible(find.text('创建成员并签发令牌'));
    await tester.tap(find.text('创建成员并签发令牌'));
    await tester.pumpAndSettle();

    expect(access.operations, [
      'create:Alice',
      'grant:source-1',
      'issue:Alice 的手机',
    ]);
    expect(find.text('请立即保存访问令牌'), findsOneWidget);
    expect(find.text('one-time-token'), findsOneWidget);
  });

  testWidgets('new member workflow resumes after a grant failure', (
    tester,
  ) async {
    _useTallViewport(tester);
    final access = _FakeAccessRepository()..failedGrantIds.add('source-2');
    await tester.pumpWidget(
      MaterialApp(
        home: NewMemberPage(access: access, sources: _FakeSourceRepository()),
      ),
    );
    await tester.pump();

    await tester.enterText(find.byType(TextField).at(0), 'Alice');
    await tester.tap(find.byType(CheckboxListTile).at(0));
    await tester.tap(find.byType(CheckboxListTile).at(1));
    await tester.enterText(find.byType(TextField).at(1), 'Alice 的手机');
    await tester.ensureVisible(find.text('创建成员并签发令牌'));
    await tester.tap(find.text('创建成员并签发令牌'));
    await tester.pumpAndSettle();

    expect(access.createCalls, 1);
    expect(access.issueCalls, 0);
    expect(find.textContaining('成员 Alice 已创建'), findsOneWidget);

    access.failedGrantIds.clear();
    await tester.ensureVisible(find.text('继续完成授权'));
    await tester.tap(find.text('继续完成授权'));
    await tester.pumpAndSettle();

    expect(access.createCalls, 1);
    expect(access.issueCalls, 1);
    expect(access.operations, [
      'create:Alice',
      'grant:source-1',
      'grant:source-2',
      'grant:source-2',
      'issue:Alice 的手机',
    ]);
  });

  testWidgets('discarding an unsaved token revokes it before leaving', (
    tester,
  ) async {
    _useTallViewport(tester);
    final access = _FakeAccessRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: NewMemberPage(access: access, sources: _FakeSourceRepository()),
      ),
    );
    await tester.pump();

    await tester.enterText(find.byType(TextField).at(0), 'Alice');
    await tester.enterText(find.byType(TextField).at(1), 'Alice 的手机');
    await tester.ensureVisible(find.text('创建成员并签发令牌'));
    await tester.tap(find.text('创建成员并签发令牌'));
    await tester.pumpAndSettle();
    expect(find.text('请立即保存访问令牌'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(access.operations.last, 'revoke:token-1');
  });

  testWidgets('member detail serializes source grant mutations', (
    tester,
  ) async {
    _useTallViewport(tester);
    final access = _FakeAccessRepository()..grantGate = Completer<void>();
    await tester.pumpWidget(
      MaterialApp(
        home: MemberDetailPage(
          access: access,
          sources: _FakeSourceRepository(),
          user: _user(name: 'Alice'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final firstGrant = find.byType(CheckboxListTile).at(0);
    await tester.tap(firstGrant);
    await tester.pump();

    expect(access.operations, ['grant:source-1']);
    expect(tester.widget<CheckboxListTile>(firstGrant).onChanged, isNull);

    access.grantGate!.complete();
    await tester.pumpAndSettle();

    expect(tester.widget<CheckboxListTile>(firstGrant).value, isTrue);
  });
}

void _useTallViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

AppDependencies _dependencies({required ServerProfile profile}) {
  final dependencies = AppDependencies(
    mediaRepository: MockMediaRepository(),
    connectionService: _FakeConnectionService(),
    sourceRepository: _FakeSourceRepository(),
    accessRepository: _FakeAccessRepository(),
  );
  dependencies.session.connect(profile);
  return dependencies;
}

ServerProfile _profile({
  required String role,
  required List<String> capabilities,
}) => ServerProfile(
  name: 'server.local',
  address: 'http://server.local:8080',
  token: 'admin-token',
  hostName: 'server.local',
  userRole: role,
  capabilities: capabilities,
);

class _FakeConnectionService implements ConnectionService {
  @override
  ServerProfile? connectedProfile;

  @override
  Future<void> disconnect() async {}

  @override
  Future<ConnectionResult> test(String address, String token) async =>
      ConnectionResult.success;
}

class _FakeSourceRepository implements SourceRepository {
  final sources = [
    _source('source-1', '家庭视频'),
    _source('source-2', '电影收藏', libraryKind: 'movies'),
  ];

  @override
  Future<Source?> find(String id) async {
    for (final source in sources) {
      if (source.id == id) return source;
    }
    return null;
  }

  @override
  Future<List<Source>> list({bool refresh = false}) async => sources;
}

class _FakeAccessRepository implements AccessRepository {
  final operations = <String>[];
  final failedGrantIds = <String>{};
  List<AccessUser> users = [_user()];
  Completer<void>? grantGate;
  var createCalls = 0;
  var issueCalls = 0;

  @override
  Future<AccessUser> createUser(String name, {String? requestId}) async {
    createCalls++;
    operations.add('create:$name');
    return _user(name: name);
  }

  @override
  Future<void> grantSource(String userId, String sourceId) async {
    operations.add('grant:$sourceId');
    final gate = grantGate;
    if (gate != null) await gate.future;
    if (failedGrantIds.contains(sourceId)) {
      throw StateError('grant unavailable');
    }
  }

  @override
  Future<IssuedAccessToken> issueToken(
    String userId, {
    required String name,
    DateTime? expiresAt,
    String? requestId,
  }) async {
    issueCalls++;
    operations.add('issue:$name');
    return IssuedAccessToken(
      id: 'token-1',
      userId: userId,
      name: name,
      tokenPrefix: 'luma_one',
      expiresAt: expiresAt,
      revokedAt: null,
      createdAt: DateTime.utc(2026),
      token: 'one-time-token',
    );
  }

  @override
  Future<List<String>> listGrants(String userId) async => const [];

  @override
  Future<List<AccessToken>> listTokens(String userId) async => const [];

  @override
  Future<List<AccessUser>> listUsers() async => users;

  @override
  Future<void> revokeSource(String userId, String sourceId) async {}

  @override
  Future<void> revokeToken(String tokenId) async {
    operations.add('revoke:$tokenId');
  }

  @override
  Future<AccessUser> updateUser(
    String id, {
    String? name,
    bool? enabled,
  }) async => _user(name: name ?? 'Alice', enabled: enabled ?? true);
}

AccessUser _user({
  String name = 'Administrator',
  bool enabled = true,
  bool online = false,
}) => AccessUser(
  id: 'user-1',
  name: name,
  role: 'member',
  enabled: enabled,
  online: online,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

Source _source(String id, String name, {String libraryKind = 'personal'}) =>
    Source(
      id: id,
      name: name,
      type: 'local',
      libraryKind: libraryKind,
      enabled: true,
      status: 'online',
      lastScanId: null,
      lastSeenAt: null,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );
