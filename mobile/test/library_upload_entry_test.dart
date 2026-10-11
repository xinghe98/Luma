// 验证图片上传返回后保留库页内容并合并刷新结果；用受控仓储隔离网络和真实凭据。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/app/app_dependencies.dart';
import 'package:luma/app/app_scope.dart';
import 'package:luma/core/theme.dart';
import 'package:luma/data/mock/mock_connection_service.dart';
import 'package:luma/data/mock/mock_media_repository.dart';
import 'package:luma/data/models/media_filter.dart';
import 'package:luma/data/models/media_item.dart';
import 'package:luma/data/models/media_types.dart';
import 'package:luma/features/library/library_page.dart';
import 'package:luma/shared/states/skeleton.dart';

void main() {
  for (final size in [const Size(320, 700), const Size(1280, 800)]) {
    for (final brightness in Brightness.values) {
      testWidgets('上传返回刷新保留图片 ${size.width} ${brightness.name}', (
        tester,
      ) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final repository = _UploadRefreshRepository();
        final dependencies = AppDependencies(
          mediaRepository: repository,
          connectionService: MockConnectionService(),
        );
        addTearDown(dependencies.dispose);
        final returned = Completer<bool>();
        await tester.pumpWidget(
          AppScope(
            dependencies: dependencies,
            child: MaterialApp(
              theme: brightness == Brightness.light
                  ? LumaTheme.light()
                  : LumaTheme.dark(),
              home: LibraryPage(
                type: MediaType.image,
                onOpenMedia: (_, {heroTag}) {},
                onOpenSearch: () {},
                onUploadImages: () => returned.future,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('existing')), findsOneWidget);
        final upload = find.byTooltip('上传图片');
        final target = tester.getRect(upload);
        expect(target.width, greaterThanOrEqualTo(48));
        expect(target.height, greaterThanOrEqualTo(48));
        expect(target.right, lessThanOrEqualTo(size.width));
        if (size.width < 600) {
          await tester.tap(upload);
        } else {
          var focused = false;
          for (var step = 0; step < 12 && !focused; step++) {
            await tester.sendKeyEvent(LogicalKeyboardKey.tab);
            await tester.pump();
            FocusManager.instance.primaryFocus?.context?.visitAncestorElements((
              element,
            ) {
              if (element.widget case Tooltip(message: '上传图片')) focused = true;
              return !focused;
            });
          }
          expect(focused, isTrue, reason: '上传操作必须可通过 Tab 到达');
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        }
        returned.complete(true);
        await tester.pump();
        expect(find.byKey(const ValueKey('existing')), findsOneWidget);
        expect(find.byType(PhotoMasonrySkeleton), findsNothing);
        repository.next.complete(
          MediaListPage(
            items: [_image('uploaded'), _image('existing')],
            nextCursor: null,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('uploaded')), findsOneWidget);
        expect(find.byKey(const ValueKey('existing')), findsOneWidget);
        expect(find.byType(ModalBarrier).hitTestable(), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
}

class _UploadRefreshRepository extends MockMediaRepository {
  final next = Completer<MediaListPage>();
  var loaded = false;

  @override
  Future<MediaListPage> searchPage(
    MediaFilter filter, {
    String? cursor,
    int? limit,
  }) async {
    if (loaded) return next.future;
    loaded = true;
    return MediaListPage(items: [_image('existing')], nextCursor: null);
  }
}

MediaItem _image(String id) => MediaItem(
  id: id,
  title: id,
  type: MediaType.image,
  duration: Duration.zero,
  resolution: '400 × 300',
  format: 'PNG',
  fileSize: '1 KB',
  directory: '照片',
  tags: const [],
  addedAt: DateTime.utc(2026),
  artSeed: 1,
);
