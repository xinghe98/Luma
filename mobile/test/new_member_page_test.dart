// 新成员页面测试覆盖幂等创建和部分授权失败后的恢复重试。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/data/models/api_access.dart';
import 'package:luma/data/models/api_source.dart';
import 'package:luma/data/repositories/access_repository.dart';
import 'package:luma/data/repositories/source_repository.dart';
import 'package:luma/features/settings/access/new_member_page.dart';

void main() {
  testWidgets('partial grants retry without recreating the member', (
    tester,
  ) async {
    final access = _RecoverableAccessRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: NewMemberPage(
          access: access,
          sources: const _MemberSourceRepository(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, '成员名称'), 'Alice');
    await tester.enterText(find.widgetWithText(TextField, '用户名'), 'alice');
    await tester.enterText(
      find.widgetWithText(TextField, '初始密码'),
      'password-123',
    );
    await tester.enterText(
      find.widgetWithText(TextField, '确认密码'),
      'password-123',
    );
    await tester.tap(find.text('家庭影片'));
    await tester.tap(find.text('共享照片'));
    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pump();
    await tester.tap(find.text('创建成员'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(access.createCalls, 1);
    expect(access.requestIds.single, isNotEmpty);
    expect(access.grants, ['source-1', 'source-2']);
    expect(find.text('继续授权'), findsOneWidget);
    expect(find.textContaining('仍有 1 个媒体源未授权'), findsOneWidget);

    await tester.tap(find.text('继续授权'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(access.createCalls, 1);
    expect(access.requestIds, hasLength(1));
    expect(access.grants, ['source-1', 'source-2', 'source-2']);
  });
}

final class _RecoverableAccessRepository implements AccessRepository {
  int createCalls = 0;
  int sourceTwoAttempts = 0;
  final List<String> requestIds = [];
  final List<String> grants = [];

  @override
  Future<AccessUser> createUser(
    String name, {
    required String username,
    required String password,
    String? requestId,
  }) async {
    createCalls++;
    requestIds.add(requestId!);
    return AccessUser(
      id: 'member-1',
      name: name,
      username: username,
      role: 'member',
      enabled: true,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );
  }

  @override
  Future<void> grantSource(String userId, String sourceId) async {
    grants.add(sourceId);
    if (sourceId == 'source-2' && sourceTwoAttempts++ == 0) {
      throw StateError('temporary failure');
    }
  }

  @override
  Future<List<String>> listGrants(String userId) async => const [];

  @override
  Future<List<LoginSession>> listSessions(String userId) async => const [];

  @override
  Future<List<AccessUser>> listUsers() async => const [];

  @override
  Future<void> resetPassword(String userId, String password) async {}

  @override
  Future<void> revokeSession(String sessionId) async {}

  @override
  Future<void> revokeSource(String userId, String sourceId) async {}

  @override
  Future<AccessUser> updateUser(String id, {String? name, bool? enabled}) =>
      throw UnimplementedError();
}

final class _MemberSourceRepository implements SourceRepository {
  const _MemberSourceRepository();

  @override
  Future<Source?> find(String id) async => null;

  @override
  Future<List<Source>> list({bool refresh = false}) async => [
    _source('source-1', '家庭影片'),
    _source('source-2', '共享照片'),
  ];

  static Source _source(String id, String name) => Source(
    id: id,
    name: name,
    type: 'local',
    libraryKind: 'personal',
    enabled: true,
    status: 'online',
    lastScanId: null,
    lastSeenAt: null,
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
  );
}
