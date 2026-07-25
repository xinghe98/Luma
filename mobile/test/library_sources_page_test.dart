// Verifies media-source settings use an in-page empty-state action and only
// reveal the app-bar action after at least one source has loaded.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/data/models/api_managed_source.dart';
import 'package:luma/data/models/api_source.dart';
import 'package:luma/data/repositories/access_repository.dart';
import 'package:luma/data/repositories/source_repository.dart';
import 'package:luma/features/settings/library_sources_page.dart';

void main() {
  testWidgets('empty media sources use the page action instead of app bar', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: LibrarySourcesPage(
          repository: _FakeSourceRepository(const []),
          access: const UnavailableAccessRepository(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('还没有媒体源'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '新增媒体源'), findsOneWidget);
    expect(find.byTooltip('新增媒体源'), findsNothing);
  });

  testWidgets('existing media sources keep the app-bar create action', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: LibrarySourcesPage(
          repository: _FakeSourceRepository([_source()]),
          access: const UnavailableAccessRepository(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('家庭影片'), findsOneWidget);
    expect(find.byTooltip('新增媒体源'), findsOneWidget);
  });
}

class _FakeSourceRepository implements MutableSourceRepository {
  const _FakeSourceRepository(this._sources);

  final List<Source> _sources;

  @override
  Future<ManagedSourceCreation> createManagedSource({
    required String name,
    required String rootPath,
    required String libraryKind,
    required List<String> userIds,
  }) => throw UnimplementedError();

  @override
  Future<Source?> find(String id) async {
    for (final source in _sources) {
      if (source.id == id) return source;
    }
    return null;
  }

  @override
  Future<List<String>> listAvailableRoots() async => const [];

  @override
  Future<List<Source>> list({bool refresh = false}) async => _sources;

  @override
  Future<Source> updateLibraryKind(String id, String libraryKind) =>
      throw UnimplementedError();
}

Source _source() => Source(
  id: 'source_test',
  name: '家庭影片',
  type: 'local',
  libraryKind: 'personal',
  enabled: true,
  status: 'online',
  lastScanId: null,
  lastSeenAt: null,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);
