// Verifies NewLibrarySourcePage uses configured server roots with lightweight
// repository fakes; no shared app state survives between widget-test cases.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/data/models/api_access.dart';
import 'package:luma/data/models/api_managed_source.dart';
import 'package:luma/data/models/api_source.dart';
import 'package:luma/data/repositories/access_repository.dart';
import 'package:luma/data/repositories/source_repository.dart';
import 'package:luma/features/settings/new_library_source_page.dart';

void main() {
  testWidgets(
    'new source selects a configured media root instead of typing it',
    (tester) async {
      final sources = _FakeSourceRepository();
      await tester.pumpWidget(
        MaterialApp(
          home: NewLibrarySourcePage(
            sources: sources,
            access: _FakeAccessRepository(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('服务端文件夹路径'), findsNothing);
      expect(find.textContaining('媒体目录'), findsOneWidget);
      expect(find.byType(DropdownButtonFormField<String>), findsNothing);

      await tester.tap(find.text('选择已配置的媒体目录'));
      await tester.pumpAndSettle();

      expect(find.text('选择媒体目录'), findsOneWidget);
      expect(find.text('仅显示服务器已配置的目录。'), findsOneWidget);
      await tester.tap(find.text('/media/family').last);
      await tester.enterText(find.byType(TextField), '家庭影片');
      await tester.tap(find.text('新增并开始扫描'));
      await tester.pumpAndSettle();

      expect(sources.createdRoot, '/media/family');
    },
  );

  testWidgets('new source chooses its video purpose from a bottom sheet', (
    tester,
  ) async {
    final sources = _FakeSourceRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: NewLibrarySourcePage(
          sources: sources,
          access: _FakeAccessRepository(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('个人视频'));
    await tester.pumpAndSettle();

    expect(find.text('选择视频用途'), findsOneWidget);
    expect(find.text('按文件夹和日期浏览'), findsOneWidget);
    expect(find.text('按影片信息整理'), findsOneWidget);
    expect(find.text('按剧、季和集整理'), findsOneWidget);
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);

    await tester.tap(find.text('电影').last);
    await tester.pumpAndSettle();

    expect(find.text('选择视频用途'), findsNothing);
    expect(find.text('电影'), findsOneWidget);

    await tester.tap(find.text('选择已配置的媒体目录'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('/media/family').last);
    await tester.enterText(find.byType(TextField), '家庭影片');
    await tester.tap(find.text('新增并开始扫描'));
    await tester.pumpAndSettle();

    expect(sources.createdLibraryKind, 'movies');
  });

  testWidgets('dismissing the video-purpose sheet preserves the selection', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: NewLibrarySourcePage(
          sources: _FakeSourceRepository(),
          access: _FakeAccessRepository(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('个人视频'));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('选择视频用途'), findsNothing);
    expect(find.text('个人视频'), findsOneWidget);
  });
}

class _FakeSourceRepository implements MutableSourceRepository {
  String? createdRoot;
  String? createdLibraryKind;

  @override
  Future<ManagedSourceCreation> createManagedSource({
    required String name,
    required String rootPath,
    required String libraryKind,
    required List<String> userIds,
  }) async {
    createdRoot = rootPath;
    createdLibraryKind = libraryKind;
    throw StateError('not persisted in widget test');
  }

  @override
  Future<Source?> find(String id) async => null;

  @override
  Future<List<String>> listAvailableRoots() async => const [
    '/media/family',
    '/media/movies',
  ];

  @override
  Future<List<Source>> list({bool refresh = false}) async => const [];

  @override
  Future<Source> updateLibraryKind(String id, String libraryKind) =>
      throw UnimplementedError();
}

class _FakeAccessRepository implements AccessRepository {
  @override
  Future<AccessUser> createUser(String name, {String? requestId}) =>
      throw UnimplementedError();

  @override
  Future<void> grantSource(String userId, String sourceId) async {}

  @override
  Future<IssuedAccessToken> issueToken(
    String userId, {
    required String name,
    DateTime? expiresAt,
    String? requestId,
  }) => throw UnimplementedError();

  @override
  Future<List<String>> listGrants(String userId) async => const [];

  @override
  Future<List<AccessToken>> listTokens(String userId) async => const [];

  @override
  Future<List<AccessUser>> listUsers() async => const [];

  @override
  Future<void> revokeSource(String userId, String sourceId) async {}

  @override
  Future<void> revokeToken(String tokenId) async {}

  @override
  Future<AccessUser> updateUser(String id, {String? name, bool? enabled}) =>
      throw UnimplementedError();
}
