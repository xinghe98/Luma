// TV 列表焦点测试：验证方向键移动、离屏目标滚动交接、删除/清空后的焦点恢复
// 以及快速重复按键只保留最新目标；不使用文字存在性代替焦点与布局断言。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/shared/interaction/luma_focusable_surface.dart';
import 'package:luma/shared/interaction/tv_focus_collection.dart';
import 'package:luma/shared/interaction/tv_key_bindings.dart';
import 'package:luma/shared/media/tv_media_grid.dart';

void main() {
  Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyEvent(key);
    await tester.pump();
    await tester.pump();
    await tester.pump();
  }

  testWidgets('grid d-pad reveals unmounted target and activates it', (
    tester,
  ) async {
    _setViewport(tester, const Size(800, 600));
    final key = GlobalKey<_GridHarnessState>();
    await tester.pumpWidget(_GridHarness(key: key, itemCount: 60));
    await tester.pumpAndSettle();
    final harness = key.currentState!;

    // 首卡获得初始焦点，确认键激活当前卡。
    await press(tester, LogicalKeyboardKey.select);
    expect(harness.activatedId, 'item-0');

    // 下移 13 行到第 39 项（行 13 未挂载），右移到第 40 项并激活。
    for (var i = 0; i < 13; i++) {
      await press(tester, LogicalKeyboardKey.arrowDown);
    }
    await press(tester, LogicalKeyboardKey.arrowRight);
    await press(tester, LogicalKeyboardKey.select);
    expect(harness.activatedId, 'item-40');
    expect(find.text('item-40'), findsOneWidget);
  });

  testWidgets('back returns focus to the same card inside viewport', (
    tester,
  ) async {
    _setViewport(tester, const Size(800, 600));
    final key = GlobalKey<_GridHarnessState>();
    await tester.pumpWidget(
      _GridHarness(key: key, itemCount: 60, pushDetailsOnActivate: true),
    );
    await tester.pumpAndSettle();
    final harness = key.currentState!;

    for (var i = 0; i < 13; i++) {
      await press(tester, LogicalKeyboardKey.arrowDown);
    }
    await press(tester, LogicalKeyboardKey.arrowRight);
    await press(tester, LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(find.text('detail-page'), findsOneWidget);
    // 系统返回键出栈详情；详情页没有 AppBar 返回按钮，不能用 tester.pageBack。
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    // 返回后焦点仍在第 40 项：按确认键再次打开同一详情。
    await press(tester, LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(harness.activatedId, 'item-40');
    expect(find.text('detail-page'), findsOneWidget);
  });

  testWidgets('deleting the focused id restores the nearest valid item', (
    tester,
  ) async {
    _setViewport(tester, const Size(800, 600));
    final key = GlobalKey<_GridHarnessState>();
    await tester.pumpWidget(_GridHarness(key: key, itemCount: 60));
    await tester.pumpAndSettle();
    final harness = key.currentState!;

    // 聚焦第 10 项（行 3 列 1），随后从列表中删除它。
    for (var i = 0; i < 3; i++) {
      await press(tester, LogicalKeyboardKey.arrowDown);
    }
    await press(tester, LogicalKeyboardKey.arrowRight);
    harness.removeId('item-10');
    await tester.pump();
    await tester.pump();
    await tester.pump();

    await press(tester, LogicalKeyboardKey.select);
    // 原索引位置现在由旧第 11 项占据，焦点保留在该位置。
    expect(harness.activatedId, 'item-11');
  });

  testWidgets('empty list releases focus to the filter action', (tester) async {
    _setViewport(tester, const Size(800, 600));
    final key = GlobalKey<_GridHarnessState>();
    await tester.pumpWidget(_GridHarness(key: key, itemCount: 60));
    await tester.pumpAndSettle();
    final harness = key.currentState!;

    harness.clearItems();
    await tester.pumpAndSettle();

    await press(tester, LogicalKeyboardKey.arrowUp);
    expect(harness.filterFocusNode.hasFocus, isTrue);
  });

  testWidgets('rapid repeated arrows keep only the latest target', (
    tester,
  ) async {
    _setViewport(tester, const Size(800, 600));
    final key = GlobalKey<_GridHarnessState>();
    await tester.pumpWidget(_GridHarness(key: key, itemCount: 60));
    await tester.pumpAndSettle();
    final harness = key.currentState!;

    // 不插帧连续发送 5 次下移，旧交接必须全部作废。
    for (var i = 0; i < 5; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    }
    for (var i = 0; i < 8; i++) {
      await tester.pump();
    }
    await press(tester, LogicalKeyboardKey.select);
    expect(harness.activatedId, 'item-15');

    // 额外帧之后不允许出现延迟跳焦。
    for (var i = 0; i < 10; i++) {
      await tester.pump();
    }
    harness.resetActivated();
    await press(tester, LogicalKeyboardKey.select);
    expect(harness.activatedId, 'item-15');
  });

  testWidgets(
    'replacing a card focus node keeps directional activation valid',
    (tester) async {
      final original = FocusNode();
      final replacement = FocusNode();
      final second = FocusNode();
      final selectedNode = ValueNotifier(original);
      addTearDown(() {
        selectedNode.dispose();
        original.dispose();
        replacement.dispose();
        second.dispose();
      });
      String? activated;
      await tester.pumpWidget(
        MaterialApp(
          home: TvKeyBindings(
            child: Scaffold(
              body: ValueListenableBuilder<FocusNode>(
                valueListenable: selectedNode,
                builder: (context, first, _) => TvFocusCollection(
                  itemIds: const ['first', 'second'],
                  axis: Axis.horizontal,
                  columns: 1,
                  revealIndex: (_) async {},
                  child: Row(
                    children: [
                      for (final (id, node) in [
                        ('first', first),
                        ('second', second),
                      ])
                        LumaFocusableSurface(
                          label: id,
                          focusId: id,
                          focusNode: node,
                          borderRadius: BorderRadius.zero,
                          onActivate: () => activated = id,
                          child: SizedBox(
                            width: 100,
                            height: 60,
                            child: Text(id),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      selectedNode.value = replacement;
      await tester.pump();
      second.requestFocus();
      await tester.pump();
      await press(tester, LogicalKeyboardKey.arrowLeft);
      expect(replacement.hasPrimaryFocus, isTrue);
      await press(tester, LogicalKeyboardKey.select);
      expect(activated, 'first');
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('离开卡片后筛选按钮方向键不被历史卡片索引接管', (tester) async {
    final first = FocusNode();
    final filter = FocusNode();
    final nextFilter = FocusNode();
    addTearDown(() {
      first.dispose();
      filter.dispose();
      nextFilter.dispose();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TvFocusCollection(
            itemIds: const ['a', 'b'],
            axis: Axis.horizontal,
            columns: 1,
            revealIndex: (_) async {},
            child: Column(
              children: [
                Row(
                  children: [
                    FilledButton(
                      focusNode: filter,
                      onPressed: () {},
                      child: const Text('筛选'),
                    ),
                    FilledButton(
                      focusNode: nextFilter,
                      onPressed: () {},
                      child: const Text('排序'),
                    ),
                  ],
                ),
                Row(
                  children: [
                    for (final id in ['a', 'b'])
                      LumaFocusableSurface(
                        label: id,
                        focusId: id,
                        focusNode: id == 'a' ? first : null,
                        borderRadius: BorderRadius.zero,
                        onActivate: () {},
                        child: SizedBox(
                          width: 100,
                          height: 60,
                          child: Text(id),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    first.requestFocus();
    await tester.pump();
    filter.requestFocus();
    await tester.pump();
    await press(tester, LogicalKeyboardKey.arrowRight);
    expect(nextFilter.hasPrimaryFocus, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('重复 reveal 同一目标不累计滚动距离', (tester) async {
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: ListView.builder(
          controller: scroll,
          itemExtent: 100,
          itemCount: 100,
          itemBuilder: (_, index) => Text('$index'),
        ),
      ),
    );
    final grid = TvGridReveal(controller: scroll);
    grid.track(0, 600);
    await grid.revealIndex(30);
    final target = scroll.offset;
    await grid.revealIndex(30);
    expect(scroll.offset, target);
    scroll.jumpTo(0);
    final list = TvListReveal.linear(controller: scroll, stepExtent: 100);
    list.track(0);
    await list.revealIndex(20);
    await list.revealIndex(21);
    await list.revealIndex(21);
    expect(scroll.offset, 2100);
  });

  testWidgets('horizontal shelf moves adjacent and boundary bubbles out', (
    tester,
  ) async {
    _setViewport(tester, const Size(800, 300));
    final key = GlobalKey<_ShelfHarnessState>();
    await tester.pumpWidget(_ShelfHarness(key: key, itemCount: 20));
    await tester.pumpAndSettle();
    final harness = key.currentState!;

    await press(tester, LogicalKeyboardKey.arrowRight);
    await press(tester, LogicalKeyboardKey.select);
    expect(harness.activatedId, 'item-1');

    // 回到第一张卡后向左越界：焦点离开列表落到左侧导航按钮。
    await press(tester, LogicalKeyboardKey.arrowLeft);
    await press(tester, LogicalKeyboardKey.arrowLeft);
    expect(harness.navFocusNode.hasFocus, isTrue);
  });
}

void _setViewport(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// 规则网格：行高固定 50，列数 3，小视口下仅部分行挂载。
/// autofocus 只用于进入列表的初始焦点，测试不滚动回看第 0 项。
class _GridHarness extends StatefulWidget {
  const _GridHarness({
    super.key,
    required this.itemCount,
    this.pushDetailsOnActivate = false,
  });

  final int itemCount;
  final bool pushDetailsOnActivate;

  @override
  State<_GridHarness> createState() => _GridHarnessState();
}

class _GridHarnessState extends State<_GridHarness> {
  static const _columns = 3;
  static const _rowExtent = 50.0;

  final ScrollController scrollController = ScrollController();
  final FocusNode filterFocusNode = FocusNode();
  late List<String> ids = List.generate(widget.itemCount, (i) => 'item-$i');
  String? activatedId;

  void removeId(String id) => setState(() => ids.remove(id));

  void clearItems() => setState(() => ids = <String>[]);

  void resetActivated() => activatedId = null;

  Future<void> _revealIndex(int index) async {
    final row = index ~/ _columns;
    final target = (row * _rowExtent - _rowExtent).clamp(
      0.0,
      scrollController.position.maxScrollExtent,
    );
    scrollController.jumpTo(target);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: TvKeyBindings(
        child: Scaffold(
          body: Column(
            children: [
              FilledButton(
                focusNode: filterFocusNode,
                onPressed: () {},
                child: const Text('筛选'),
              ),
              Expanded(
                child: TvFocusCollection(
                  itemIds: ids,
                  axis: Axis.vertical,
                  columns: _columns,
                  revealIndex: _revealIndex,
                  child: GridView.builder(
                    controller: scrollController,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: _columns,
                          mainAxisExtent: _rowExtent,
                        ),
                    itemCount: ids.length,
                    itemBuilder: (context, index) => LumaFocusableSurface(
                      label: ids[index],
                      focusId: ids[index],
                      autofocus: index == 0,
                      borderRadius: BorderRadius.zero,
                      onActivate: () {
                        activatedId = ids[index];
                        if (widget.pushDetailsOnActivate) {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) =>
                                  const Scaffold(body: Text('detail-page')),
                            ),
                          );
                        }
                      },
                      child: Center(child: Text(ids[index])),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 横向货架：卡宽固定 120，左侧放一个导航按钮验证越界冒泡。
class _ShelfHarness extends StatefulWidget {
  const _ShelfHarness({super.key, required this.itemCount});

  final int itemCount;

  @override
  State<_ShelfHarness> createState() => _ShelfHarnessState();
}

class _ShelfHarnessState extends State<_ShelfHarness> {
  static const _cardWidth = 120.0;

  final ScrollController scrollController = ScrollController();
  final FocusNode navFocusNode = FocusNode();
  late List<String> ids = List.generate(widget.itemCount, (i) => 'item-$i');
  String? activatedId;

  Future<void> _revealIndex(int index) async {
    final target = (index * _cardWidth - _cardWidth).clamp(
      0.0,
      scrollController.position.maxScrollExtent,
    );
    scrollController.jumpTo(target);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: TvKeyBindings(
        child: Scaffold(
          body: Row(
            children: [
              FilledButton(
                focusNode: navFocusNode,
                onPressed: () {},
                child: const Text('导航'),
              ),
              Expanded(
                child: TvFocusCollection(
                  itemIds: ids,
                  axis: Axis.horizontal,
                  columns: 1,
                  revealIndex: _revealIndex,
                  child: ListView.builder(
                    controller: scrollController,
                    scrollDirection: Axis.horizontal,
                    itemExtent: _cardWidth,
                    itemCount: ids.length,
                    itemBuilder: (context, index) => LumaFocusableSurface(
                      label: ids[index],
                      focusId: ids[index],
                      autofocus: index == 0,
                      borderRadius: BorderRadius.zero,
                      onActivate: () => activatedId = ids[index],
                      child: Center(child: Text(ids[index])),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
