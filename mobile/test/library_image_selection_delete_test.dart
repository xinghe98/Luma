// 图片库批量选择删除的控件测试：覆盖触控与键盘路径、部分失败保留、
// 取消/Back/Escape 退出选择、删除中停止剩余批次；布局在多个尺寸/文本
// 缩放/浅深主题与含上传入口的最窄工具栏下无溢出；另附 TV 分支选择回归。
import 'dart:async';

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
import 'package:luma/data/models/media_types.dart';
import 'package:luma/features/library/library_page.dart';
import 'package:luma/shared/interaction/tv_key_bindings.dart';
import 'package:luma/shared/media/media_selection_marker.dart';

const _sizes = [
  Size(320, 700), // 最窄约束
  Size(390, 844), // 常见手机
  Size(768, 1024), // 竖屏平板
  Size(1024, 768), // 横屏平板
  Size(960, 640), // 横屏桌面窗口
  Size(1280, 800), // 宽屏
];
const _scales = [1.0, 1.25, 1.5];

Widget _app(
  AppDependencies dependencies, {
  Brightness brightness = Brightness.light,
  bool television = false,
  Future<bool> Function()? onUploadImages,
}) => AppScope(
  dependencies: dependencies,
  child: MaterialApp(
    theme: television
        ? applyTvTheme(
            brightness == Brightness.light
                ? LumaTheme.light()
                : LumaTheme.dark(),
          )
        : brightness == Brightness.light
        ? LumaTheme.light()
        : LumaTheme.dark(),
    home: television
        ? TvKeyBindings(
            child: LibraryPage(
              type: MediaType.image,
              onOpenMedia: (_, {heroTag}) {},
              onOpenSearch: () {},
              onUploadImages: onUploadImages,
            ),
          )
        : LibraryPage(
            type: MediaType.image,
            onOpenMedia: (_, {heroTag}) {},
            onOpenSearch: () {},
            onUploadImages: onUploadImages,
          ),
  ),
);

AppDependencies _deps(_DeleteMediaRepository repository, {bool tv = false}) =>
    AppDependencies(
      mediaRepository: repository,
      connectionService: MockConnectionService(),
      deviceProfile: tv
          ? AppDeviceProfile.television
          : AppDeviceProfile.standard,
    );

void _setSurface(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// 判断当前焦点是否落在含 [tooltip] 的组件上。
bool _focusedOnTooltip(String tooltip) {
  var hit = false;
  FocusManager.instance.primaryFocus?.context?.visitAncestorElements((element) {
    if (element.widget case Tooltip(
      message: final message,
    ) when message == tooltip) {
      hit = true;
    }
    return !hit;
  });
  return hit;
}

/// Tab 迁移到首个 ValueKey 为 [id] 的卡片；返回是否到达。
Future<bool> _focusCard(
  WidgetTester tester,
  String id, {
  int maxSteps = 32,
}) async {
  for (var step = 0; step < maxSteps; step++) {
    var hit = false;
    FocusManager.instance.primaryFocus?.context?.visitAncestorElements((
      element,
    ) {
      if (element.widget.key case ValueKey<String>(
        value: final key,
      ) when key == id) {
        hit = true;
      }
      return !hit;
    });
    if (hit) return true;
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
  }
  return false;
}

void main() {
  // 全部尺寸 × 缩放 × 浅深主题的结构检查：选择入口可见、卡片正常构建、
  // 进入选择后操作栏无溢出；业务断言集中在下方代表尺寸。
  for (final size in _sizes) {
    for (final scale in _scales) {
      for (final brightness in Brightness.values) {
        testWidgets(
          '选择界面结构无溢出 ${size.width}x${size.height}@${scale}x ${brightness.name}',
          (tester) async {
            _setSurface(tester, size);
            tester.platformDispatcher.textScaleFactorTestValue = scale;
            addTearDown(
              tester.platformDispatcher.clearTextScaleFactorTestValue,
            );
            final repository = _DeleteMediaRepository();
            final dependencies = _deps(repository);
            addTearDown(dependencies.dispose);
            await tester.pumpWidget(_app(dependencies, brightness: brightness));
            await tester.pumpAndSettle();
            final select = find.byTooltip('选择图片');
            expect(select, findsOneWidget);
            expect(tester.getRect(select).right, lessThanOrEqualTo(size.width));
            await tester.tap(select);
            await tester.pump();
            expect(find.text('已选 0 项'), findsOneWidget);
            await tester.tap(find.byKey(const ValueKey('image-0')));
            await tester.pump();
            expect(find.text('已选 1 项'), findsOneWidget);
            expect(find.text('删除(1)'), findsOneWidget);
            await tester.tap(find.byTooltip('退出选择'));
            await tester.pump();
            expect(find.byTooltip('选择图片'), findsOneWidget);
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }

  // 含上传入口的最窄工具栏：上传+选择+搜索+收藏+排序 5 个操作在 320px 下不溢出。
  for (final scale in _scales) {
    for (final brightness in Brightness.values) {
      testWidgets('含上传的工具栏 320px @${scale}x ${brightness.name}', (
        tester,
      ) async {
        _setSurface(tester, const Size(320, 700));
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final repository = _DeleteMediaRepository();
        final dependencies = _deps(repository);
        addTearDown(dependencies.dispose);
        await tester.pumpWidget(
          _app(
            dependencies,
            brightness: brightness,
            onUploadImages: () async => false,
          ),
        );
        await tester.pumpAndSettle();
        for (final tooltip in ['上传图片', '选择图片', '搜索', '更多操作']) {
          final finder = find.byTooltip(tooltip);
          expect(finder, findsOneWidget, reason: '$tooltip 应存在');
          final rect = tester.getRect(finder);
          expect(
            rect.right,
            lessThanOrEqualTo(320),
            reason: '$tooltip 不应溢出',
          );
          expect(rect.left, greaterThanOrEqualTo(0));
        }
        // 次要操作收进溢出菜单后，320px + 任意缩放都不允许布局异常。
        expect(tester.takeException(), isNull);
      });
    }
  }

  for (final size in [const Size(320, 700), const Size(1280, 800)]) {
    testWidgets('多选删除成功移除已选图片 ${size.width}x${size.height}', (tester) async {
      _setSurface(tester, size);
      final repository = _DeleteMediaRepository();
      final dependencies = _deps(repository);
      addTearDown(dependencies.dispose);
      await tester.pumpWidget(_app(dependencies));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('image-0')), findsOneWidget);

      await tester.tap(find.byTooltip('选择图片'));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('image-0')));
      await tester.tap(find.byKey(const ValueKey('image-2')));
      await tester.pump();
      expect(find.text('已选 2 项'), findsOneWidget);
      expect(
        tester
            .widgetList<MediaSelectionMarker>(find.byType(MediaSelectionMarker))
            .where((marker) => marker.selected)
            .length,
        2,
      );

      await tester.tap(find.text('删除(2)'));
      await tester.pumpAndSettle();
      expect(find.text('删除 2 张图片？'), findsOneWidget);
      await tester.tap(find.text('永久删除'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('image-0')), findsNothing);
      expect(find.byKey(const ValueKey('image-2')), findsNothing);
      expect(find.byKey(const ValueKey('image-1')), findsOneWidget);
      expect(find.byTooltip('选择图片'), findsOneWidget);
      expect(repository.deletedIds, ['image-0', 'image-2']);
      expect(find.byType(ModalBarrier).hitTestable(), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('取消确认不发起删除请求', (tester) async {
    _setSurface(tester, const Size(390, 844));
    final repository = _DeleteMediaRepository();
    final dependencies = _deps(repository);
    addTearDown(dependencies.dispose);
    await tester.pumpWidget(_app(dependencies));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('选择图片'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('image-1')));
    await tester.pump();
    await tester.tap(find.text('删除(1)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(repository.deletedIds, isEmpty);
    expect(find.text('已选 1 项'), findsOneWidget);
    expect(find.byKey(const ValueKey('image-1')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('部分失败保留失败项并显示可重试提示', (tester) async {
    _setSurface(tester, const Size(390, 844));
    final repository = _DeleteMediaRepository(failOn: {'image-1'});
    final dependencies = _deps(repository);
    addTearDown(dependencies.dispose);
    await tester.pumpWidget(_app(dependencies));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('选择图片'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('image-0')));
    await tester.tap(find.byKey(const ValueKey('image-1')));
    await tester.pump();
    await tester.tap(find.text('删除(2)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('永久删除'));
    await tester.pumpAndSettle();
    // 成功项被移除，失败项仍选中并可重试。
    expect(find.byKey(const ValueKey('image-0')), findsNothing);
    expect(find.byKey(const ValueKey('image-1')), findsOneWidget);
    expect(find.text('已选 1 项'), findsOneWidget);
    expect(find.text('有 1 项删除失败，仍在选择列表中，可重试'), findsOneWidget);
    expect(repository.deletedIds, ['image-0']);
    expect(repository.attempts['image-1'], 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('删除中显示进度且停止剩余批次保留未删项', (tester) async {
    _setSurface(tester, const Size(390, 844));
    // image-0 的删除挂起：批次在第一项上等待，停止后不再发后续请求。
    final repository = _DeleteMediaRepository(holdOn: {'image-0'});
    final dependencies = _deps(repository);
    addTearDown(dependencies.dispose);
    await tester.pumpWidget(_app(dependencies));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('选择图片'));
    await tester.pump();
    // 用「全选已加载」一次选 12 项：避免依赖瀑布流懒构建的逐项点击。
    await tester.tap(find.text('全选已加载'));
    await tester.pump();
    expect(find.text('已选 12 项'), findsOneWidget);
    await tester.tap(find.text('删除(12)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('永久删除'));
    await tester.pump();
    expect(find.text('删除中 0/12'), findsOneWidget);
    // 删除中 Back/Escape/退出都被解释为停止：先按「停止剩余」验证同一语义。
    await tester.tap(find.text('停止剩余'));
    await tester.pump();
    repository.release('image-0');
    await tester.pumpAndSettle();
    // 只完成已发出的第一项，其余 11 项被取消且仍选中。
    expect(repository.deletedIds, ['image-0']);
    expect(find.text('已停止剩余删除'), findsOneWidget);
    expect(find.text('已选 11 项'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('删除中退出按钮与卡片操作均被锁定', (tester) async {
    _setSurface(tester, const Size(390, 844));
    final repository = _DeleteMediaRepository(holdOn: {'image-0'});
    final dependencies = _deps(repository);
    addTearDown(dependencies.dispose);
    await tester.pumpWidget(_app(dependencies));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('选择图片'));
    await tester.pump();
    // 用「全选已加载」一次选 12 项。
    await tester.tap(find.text('全选已加载'));
    await tester.pump();
    expect(find.text('已选 12 项'), findsOneWidget);
    await tester.tap(find.text('删除(12)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('永久删除'));
    await tester.pump();
    expect(find.text('删除中 0/12'), findsOneWidget);
    // AppBar 退出按钮删除中解释为停止剩余批次，不清空也不退出。
    await tester.tap(find.byTooltip('退出选择'));
    await tester.pump();
    expect(find.text('删除中 0/12'), findsOneWidget);
    // 删除中点击卡片不改勾选：进度与选中集合都不应变化。
    await tester.tap(find.byKey(const ValueKey('image-1')));
    await tester.pump();
    repository.release('image-0');
    await tester.pumpAndSettle();
    expect(find.text('已停止剩余删除'), findsOneWidget);
    expect(find.text('已选 11 项'), findsOneWidget);
  });

  testWidgets('全选已加载只选当前已加载项且退出可清空', (tester) async {
    _setSurface(tester, const Size(390, 844));
    final repository = _DeleteMediaRepository();
    final dependencies = _deps(repository);
    addTearDown(dependencies.dispose);
    await tester.pumpWidget(_app(dependencies));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('选择图片'));
    await tester.pump();
    await tester.tap(find.text('全选已加载'));
    await tester.pump();
    // fixtures 共 12 张图片，全部已加载时应一次选中 12 项。
    expect(find.text('已选 12 项'), findsOneWidget);
    await tester.tap(find.byTooltip('退出选择'));
    await tester.pump();
    expect(find.byTooltip('选择图片'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('键盘可到达选择按钮并用 Enter/Space 切换选中、删除与 Escape 退出', (tester) async {
    _setSurface(tester, const Size(1280, 800));
    final repository = _DeleteMediaRepository();
    final dependencies = _deps(repository);
    addTearDown(dependencies.dispose);
    await tester.pumpWidget(_app(dependencies));
    await tester.pumpAndSettle();

    // Tab 找到「选择图片」入口后按 Enter 进入选择态。
    var focused = false;
    for (var step = 0; step < 12 && !focused; step++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      focused = _focusedOnTooltip('选择图片');
    }
    expect(focused, isTrue, reason: '选择操作必须可通过 Tab 到达');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(find.text('已选 0 项'), findsOneWidget);

    // 逐 Tab 直到焦点落在网格首卡，Space/Enter 切换勾选。
    expect(
      await _focusCard(tester, 'image-0'),
      isTrue,
      reason: '网格首卡必须可通过 Tab 到达',
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(find.text('已选 1 项'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(find.text('已选 0 项'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(find.text('已选 1 项'), findsOneWidget);

    // 删除按钮在操作栏中：从卡片用焦点顺序向前迁移，直到落在
    // 包含「删除(1)」文案的按钮上，按 Enter 弹出确认框。
    var deleteFocused = false;
    for (var step = 0; step < 32 && !deleteFocused; step++) {
      FocusManager.instance.primaryFocus?.nextFocus();
      await tester.pump();
      final focusCtx = FocusManager.instance.primaryFocus?.context;
      // 焦点节点的 context 即 Focus widget 的元素；子树中应包含按钮文案。
      void scanForDeleteText(Element element) {
        if (element.widget case Text(data: '删除(1)')) deleteFocused = true;
        element.visitChildElements(scanForDeleteText);
      }

      if (focusCtx is Element) scanForDeleteText(focusCtx);
    }
    expect(deleteFocused, isTrue, reason: '删除按钮必须可通过焦点遍历到达');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('删除这张图片？'), findsOneWidget);
    // 确认框取消后仍在选择态；Escape 退出选择态本身。
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('已选 1 项'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.byTooltip('选择图片'), findsOneWidget);
    expect(repository.deletedIds, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('TV 分支选择态渲染与 Back 退出选择', (tester) async {
    _setSurface(tester, const Size(1280, 720));
    final repository = _DeleteMediaRepository();
    final dependencies = _deps(repository, tv: true);
    addTearDown(dependencies.dispose);
    await tester.pumpWidget(_app(dependencies, television: true));
    await tester.pumpAndSettle();
    // TV 头部提供独立「选择」入口。
    final select = find.text('选择');
    expect(select, findsOneWidget);
    await tester.tap(select);
    await tester.pump();
    expect(find.text('已选 0 项'), findsOneWidget);
    expect(find.text('全选已加载'), findsOneWidget);
    expect(find.text('删除(0)'), findsOneWidget);
    // 点击卡片切换勾选标记。
    await tester.tap(find.byKey(const ValueKey('image-0')));
    await tester.pump();
    expect(find.text('已选 1 项'), findsOneWidget);
    expect(
      tester
          .widgetList<MediaSelectionMarker>(find.byType(MediaSelectionMarker))
          .where((marker) => marker.selected)
          .length,
      1,
    );
    // TV 的 Back/Escape 同样先退出选择而不是离开页面。
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.text('已选 1 项'), findsNothing);
    expect(find.text('选择'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('TV 分支键盘可到达头部选择与网格卡片并切换勾选', (tester) async {
    _setSurface(tester, const Size(1280, 720));
    final repository = _DeleteMediaRepository();
    final dependencies = _deps(repository, tv: true);
    addTearDown(dependencies.dispose);
    await tester.pumpWidget(_app(dependencies, television: true));
    await tester.pumpAndSettle();
    // 点击「选择」进入选择态，验证头部按钮组与网格卡片均可操作。
    await tester.tap(find.text('选择'));
    await tester.pump();
    expect(find.text('已选 0 项'), findsOneWidget);
    // 焦点必须能落在首个网格卡上（TV FocusCollection 注册 focusId）。
    expect(await _focusCard(tester, 'image-0'), isTrue, reason: 'TV 网格首卡必须可聚焦');
    // select 键激活卡片即切换勾选。
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect(find.text('已选 1 项'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect(find.text('已选 0 项'), findsOneWidget);
    // Escape 退出选择态回到普通头部。
    await tester.tap(find.byKey(const ValueKey('image-0')));
    await tester.pump();
    expect(find.text('已选 1 项'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.text('选择'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('删除中会话切换清空旧勾选并退出选择', (tester) async {
    _setSurface(tester, const Size(390, 844));
    final repository = _DeleteMediaRepository(holdOn: {'image-0'});
    final dependencies = _deps(repository);
    addTearDown(dependencies.dispose);
    await tester.pumpWidget(_app(dependencies));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('选择图片'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('image-0')));
    await tester.tap(find.byKey(const ValueKey('image-1')));
    await tester.pump();
    expect(find.text('已选 2 项'), findsOneWidget);
    await tester.pump();
    await tester.tap(find.text('删除(2)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('永久删除'));
    await tester.pump();
    expect(find.text('删除中 0/2'), findsOneWidget);
    // 会话切换：已发出的删除完成但不再触碰新服务器，选择被清空退出。
    repository.release('image-0');
    dependencies.media.clear();
    await tester.pumpAndSettle();
    expect(find.text('连接已更改，已清空选择'), findsOneWidget);
    expect(find.text('已选 0 项'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

/// 可逐 id 控制删除结果的仓储；[failOn] 抛出错误，[holdOn] 挂起直到 [release]。
class _DeleteMediaRepository extends MockMediaRepository {
  _DeleteMediaRepository({this.failOn = const {}, this.holdOn = const {}});

  final Set<String> failOn;
  final Set<String> holdOn;
  final List<String> deletedIds = [];
  final Map<String, int> attempts = {};
  final Map<String, Completer<void>> _holds = {};

  void release(String id) {
    _holds.remove(id)?.complete();
  }

  @override
  Future<void> deleteImage(String id) async {
    attempts[id] = (attempts[id] ?? 0) + 1;
    final hold = _holds[id] ??= Completer<void>();
    if (holdOn.contains(id)) await hold.future;
    if (failOn.contains(id)) throw StateError('模拟删除失败: $id');
    deletedIds.add(id);
    return super.deleteImage(id);
  }
}
