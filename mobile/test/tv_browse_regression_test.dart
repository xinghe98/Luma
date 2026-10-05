// TV 浏览回归：真实网格局部约束、搜索提交与补页、图片坐标和嵌套分支返回。
// 使用内存仓库与隔离依赖，焦点和滚动状态由真实组件持有，测试结束统一释放。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/app/app_dependencies.dart';
import 'package:luma/app/app_device_profile.dart';
import 'package:luma/app/app_scope.dart';
import 'package:luma/core/theme.dart';
import 'package:luma/core/theme/tv_theme.dart';
import 'package:luma/data/mock/mock_connection_service.dart';
import 'package:luma/data/mock/mock_media_repository.dart';
import 'package:luma/data/models/media_filter.dart';
import 'package:luma/data/models/media_item.dart';
import 'package:luma/data/models/media_types.dart';
import 'package:luma/data/models/server_profile.dart';
import 'package:luma/features/details/dialogs/image_preview_dialog.dart';
import 'package:luma/features/search/search_page.dart';
import 'package:luma/main.dart';
import 'package:luma/shared/interaction/tv_focus_collection.dart';
import 'package:luma/shared/interaction/tv_key_bindings.dart';
import 'package:luma/shared/media/media_card.dart';
import 'package:luma/shared/media/tv_media_grid.dart';

MediaItem _item(int index) => MediaItem(
  id: 'regression-$index',
  title: '长标题混排 Media Title 第 $index 集继续测试文字换行',
  type: MediaType.image,
  duration: Duration.zero,
  resolution: '1080p',
  format: 'jpg',
  fileSize: '1 MB',
  directory: '/',
  tags: const [],
  addedAt: DateTime(2026),
  artSeed: index,
  aspectRatio: 0.5,
);

AppDependencies _dependencies({MockMediaRepository? repository}) =>
    AppDependencies(
      mediaRepository: repository ?? MockMediaRepository(),
      connectionService: MockConnectionService(),
      deviceProfile: AppDeviceProfile.television,
    );

void _viewport(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  for (final size in [
    const Size(960, 540),
    const Size(1280, 720),
    const Size(1920, 1080),
  ]) {
    for (final scale in [1.0, 1.25, 1.5]) {
      for (final dark in [false, true]) {
        testWidgets('TV 实际网格尺寸 $size 字号 $scale 深色 $dark', (tester) async {
          _viewport(tester, size);
          final dependencies = _dependencies();
          final scroll = ScrollController();
          final reveal = TvGridReveal(controller: scroll);
          final first = FocusNode();
          addTearDown(() {
            dependencies.dispose();
            scroll.dispose();
            first.dispose();
          });
          final items = List.generate(60, _item);
          String? activated;
          final width = (size.width - 169 - size.width * 0.1 - 40).clamp(
            0.0,
            1240.0,
          );
          final columns = const TvMediaGridGeometry().columnsFor(width);
          await tester.pumpWidget(
            AppScope(
              dependencies: dependencies,
              child: MaterialApp(
                theme: applyTvTheme(
                  dark ? LumaTheme.dark() : LumaTheme.light(),
                ),
                home: MediaQuery(
                  data: MediaQueryData(
                    size: size,
                    textScaler: TextScaler.linear(scale),
                  ),
                  child: TvKeyBindings(
                    child: Scaffold(
                      body: Center(
                        child: SizedBox(
                          width: width,
                          child: TvFocusCollection(
                            itemIds: [for (final item in items) item.id],
                            axis: Axis.vertical,
                            columns: columns,
                            revealIndex: reveal.revealIndex,
                            child: CustomScrollView(
                              controller: scroll,
                              slivers: [
                                TvMediaSliverGrid(
                                  items: items,
                                  reveal: reveal,
                                  firstItemFocusNode: first,
                                  onTap: (item, {heroTag}) =>
                                      activated = item.id,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final card0 = tester.getRect(find.byType(MediaCard).at(0));
          final card1 = tester.getRect(find.byType(MediaCard).at(1));
          expect(card0.top, card1.top);
          expect(
            card0.width,
            closeTo((width - (columns - 1) * 24) / columns, 0.01),
          );
          first.requestFocus();
          await tester.pump();
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
          await tester.pumpAndSettle();
          await tester.sendKeyEvent(LogicalKeyboardKey.select);
          await tester.pump();
          expect(activated, items[columns].id);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        });
      }
    }
  }

  testWidgets('已返回结果的搜索提交立即移交焦点，新输入不被旧提交抢焦点', (tester) async {
    _viewport(tester, const Size(960, 540));
    final dependencies = _dependencies(repository: _SearchRepository());
    addTearDown(dependencies.dispose);
    await tester.pumpWidget(
      AppScope(
        dependencies: dependencies,
        child: MaterialApp(
          theme: applyTvTheme(LumaTheme.dark()),
          home: SearchPage(onOpenMedia: (_, {heroTag}) {}),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), 'first');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'search-input');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'tv-first-result');
    tester
        .widget<CustomScrollView>(find.byType(CustomScrollView))
        .controller!
        .jumpTo(0);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'second');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'search-input');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('搜索首屏不足时结果返回后继续补页，无需滚动或再次提交', (tester) async {
    _viewport(tester, const Size(1280, 720));
    final repository = _SearchRepository(paged: true);
    final dependencies = _dependencies(repository: repository);
    addTearDown(dependencies.dispose);
    await tester.pumpWidget(
      AppScope(
        dependencies: dependencies,
        child: MaterialApp(
          theme: applyTvTheme(LumaTheme.dark()),
          home: SearchPage(onOpenMedia: (_, {heroTag}) {}),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), 'first');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(repository.cursors, [null, '1', '2']);
    expect(find.byType(MediaCard), findsNWidgets(3));
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'search-input');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('竖图缩放后左右平移保持居中，Back 先还原再关闭', (tester) async {
    _viewport(tester, const Size(960, 540));
    final dependencies = _dependencies();
    addTearDown(dependencies.dispose);
    await tester.pumpWidget(
      AppScope(
        dependencies: dependencies,
        child: MaterialApp(
          theme: applyTvTheme(LumaTheme.dark()),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showImagePreviewDialog(context, _item(0)),
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.select);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'tv-preview-image');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    final transform = tester
        .widget<InteractiveViewer>(find.byType(InteractiveViewer))
        .transformationController!;
    final center = MatrixUtils.transformPoint(
      transform.value,
      const Offset(480, 270),
    );
    expect(center.dx, closeTo(480, 0.01));
    expect(transform.value.getMaxScaleOnAxis(), closeTo(1.25, 0.01));
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(transform.value.getMaxScaleOnAxis(), 1);
    expect(find.byType(ImagePreviewDialog), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(ImagePreviewDialog), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final size in [const Size(960, 540), const Size(1280, 720)]) {
    for (final ratio in [16 / 9, 0.5]) {
      testWidgets('TV 图片平移后缩回原尺寸保持完整居中 $size 比例 $ratio', (tester) async {
        _viewport(tester, size);
        final dependencies = _dependencies();
        addTearDown(dependencies.dispose);
        await tester.pumpWidget(
          AppScope(
            dependencies: dependencies,
            child: MaterialApp(
              theme: applyTvTheme(LumaTheme.dark()),
              home: Builder(
                builder: (context) => Scaffold(
                  body: TextButton(
                    onPressed: () => showImagePreviewDialog(
                      context,
                      _item(0).copyWith(aspectRatio: ratio),
                    ),
                    child: const Text('打开'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('打开'));
        await tester.pumpAndSettle();
        for (final key in [
          LogicalKeyboardKey.select,
          LogicalKeyboardKey.arrowUp,
          LogicalKeyboardKey.arrowLeft,
          LogicalKeyboardKey.arrowDown,
          LogicalKeyboardKey.select,
          LogicalKeyboardKey.arrowRight,
          LogicalKeyboardKey.select,
        ]) {
          await tester.sendKeyEvent(key);
          await tester.pumpAndSettle();
        }
        final transform = tester
            .widget<InteractiveViewer>(find.byType(InteractiveViewer))
            .transformationController!;
        expect(transform.value.getMaxScaleOnAxis(), closeTo(1, 0.001));
        final center = MatrixUtils.transformPoint(
          transform.value,
          Offset(size.width / 2, size.height / 2),
        );
        expect(center.dx, closeTo(size.width / 2, 0.01));
        expect(center.dy, closeTo(size.height / 2, 0.01));
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(find.byType(ImagePreviewDialog), findsNothing);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }

  testWidgets('壳层搜索编辑中系统 Back 先回字段，再回左导航', (tester) async {
    _viewport(tester, const Size(1280, 720));
    final dependencies = _dependencies();
    addTearDown(dependencies.dispose);
    dependencies.session.connect(
      const ServerProfile(
        name: 'test',
        address: 'http://test.local',
        token: 'test',
        hostName: 'test',
      ),
    );
    await tester.pumpWidget(LumaApp(dependencies: dependencies));
    await tester.pump(const Duration(milliseconds: 1100));
    await tester.pumpAndSettle();
    for (var i = 0; i < 3; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    tester.widget<TextField>(find.byType(TextField)).focusNode!.requestFocus();
    await tester.pump();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'tv-field-gate');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'tv-nav-search');
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

class _SearchRepository extends MockMediaRepository {
  _SearchRepository({this.paged = false});
  final bool paged;
  final cursors = <String?>[];

  @override
  Future<MediaListPage> searchPage(
    MediaFilter filter, {
    String? cursor,
    int? limit,
  }) async {
    cursors.add(cursor);
    final index = int.parse(cursor ?? '0');
    return MediaListPage(
      items: [_item(index)],
      nextCursor: paged && index < 2 ? '${index + 1}' : null,
    );
  }
}
