// 覆盖播放器选择入口的手机/桌面布局，以及面板的焦点、重试和关闭生命周期。
// 使用内存选择状态和无解码器播放器；真实媒体切换由原生冒烟用例验证。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/app/controllers/media_controller.dart';
import 'package:luma/core/theme.dart';
import 'package:luma/data/fixtures/media_fixtures.dart';
import 'package:luma/data/mock/mock_media_repository.dart';
import 'package:luma/features/player/player_controller.dart';
import 'package:luma/features/player/player_device_controls.dart';
import 'package:luma/features/player/player_interaction_controller.dart';
import 'package:luma/features/player/player_selection_controller.dart';
import 'package:luma/features/player/widgets/player_scene.dart';
import 'package:luma/features/player/widgets/player_selection_sheet.dart';
import 'package:media_kit/media_kit.dart';

void main() {
  for (final size in [
    const Size(320, 640),
    const Size(390, 844),
    const Size(768, 1024),
    const Size(1024, 768),
    const Size(960, 640),
    const Size(1280, 800),
  ]) {
    for (final dark in [false, true]) {
      testWidgets('选择入口完整显示且面板随空间适配 $size dark=$dark', (tester) async {
        final harness = _Harness();
        final selection = _SelectionState();
        final dpi = size.width == 960
            ? 1.25
            : size.width == 1280
            ? 1.5
            : 1.0;
        _setViewport(tester, size, dpi);
        await _pumpScene(
          tester,
          harness,
          selection,
          dark: dark,
          textScale: 1.5,
        );
        for (final tooltip in ['选集', '清晰度', '字幕', '音轨', '播放速度']) {
          final target = find.byTooltip(tooltip);
          final rect = tester.getRect(target);
          expect(rect.left, greaterThanOrEqualTo(0));
          expect(rect.right, lessThanOrEqualTo(size.width));
          expect(rect.bottom, lessThanOrEqualTo(size.height));
          expect(rect.height, greaterThanOrEqualTo(48));
          expect(target.hitTestable(), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
        await tester.tap(find.byKey(const ValueKey('player-episodes-button')));
        await tester.pumpAndSettle();
        if (size.width >= LumaLayout.navigationRailBreakpoint) {
          expect(find.byType(Dialog), findsOneWidget);
          expect(
            tester.getSize(find.byType(PlayerSelectionPanel)).width,
            lessThanOrEqualTo(520),
          );
        } else {
          expect(find.byType(BottomSheet), findsOneWidget);
          expect(find.byType(Dialog), findsNothing);
        }
        final second = find.byKey(const ValueKey('player-choice-e-2'));
        expect(second.hitTestable(), findsOneWidget);
        expect(tester.getRect(second).right, lessThanOrEqualTo(size.width));
        await tester.tap(second);
        await tester.pumpAndSettle();
        expect(find.byType(Dialog), findsNothing);
        expect(find.byType(BottomSheet), findsNothing);
        expect(find.byType(ModalBarrier).hitTestable(), findsNothing);
        expect(tester.takeException(), isNull);
        await _dispose(tester, harness, selection);
      });
    }
  }

  testWidgets('电影只显示清晰度，键盘可选版本并在重新打开后突出当前项', (tester) async {
    final harness = _Harness();
    final selection = _SelectionState()..showEpisodes = false;
    _setViewport(tester, const Size(1280, 800), 1);
    await _pumpScene(tester, harness, selection);
    expect(find.byKey(const ValueKey('player-episodes-button')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('player-quality-button')));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
    await tester.tap(find.byKey(const ValueKey('player-quality-button')));
    await tester.pumpAndSettle();
    final second = find.descendant(
      of: find.byKey(const ValueKey('player-choice-q-2')),
      matching: find.byType(ListTile),
    );
    expect(tester.widget<ListTile>(second).selected, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(ModalBarrier).hitTestable(), findsNothing);
    await _dispose(tester, harness, selection);
  });

  testWidgets('加载失败保留旧选项并允许重试，失败选择保留面板', (tester) async {
    final harness = _Harness();
    final selection = _SelectionState()..error = '无法读取最新剧集';
    _setViewport(tester, const Size(390, 844), 1);
    await _pumpScene(tester, harness, selection);
    await tester.tap(find.byKey(const ValueKey('player-episodes-button')));
    await tester.pumpAndSettle();
    expect(find.text('无法读取最新剧集'), findsOneWidget);
    expect(find.byKey(const ValueKey('player-choice-e-2')), findsOneWidget);
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.text('无法读取最新剧集'), findsNothing);
    selection.rejectSelection = true;
    await tester.tap(find.byKey(const ValueKey('player-choice-e-2')));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.text('所选媒体不可用'), findsOneWidget);
    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();
    expect(find.byType(ModalBarrier).hitTestable(), findsNothing);
    expect(
      find.byKey(const ValueKey('player-episodes-button')).hitTestable(),
      findsOneWidget,
    );
    await _dispose(tester, harness, selection);
  });

  testWidgets('系统返回关闭手机选择面板后没有残留遮罩', (tester) async {
    final harness = _Harness();
    final selection = _SelectionState();
    _setViewport(tester, const Size(390, 844), 1);
    await _pumpScene(tester, harness, selection);
    await tester.tap(find.byKey(const ValueKey('player-quality-button')));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.byType(ModalBarrier).hitTestable(), findsNothing);
    await _dispose(tester, harness, selection);
  });
  for (final width in [320.0, 1280.0]) {
    testWidgets('TV 多轨与选集入口在 $width 宽度完整可见且可打开', (tester) async {
      final harness = _Harness();
      final selection = _SelectionState();
      _setViewport(tester, Size(width, 844), 1);
      await _pumpScene(tester, harness, selection, television: true);
      await tester.pump();
      for (final key in [
        'player-episodes-button',
        'player-quality-button',
        'tv-player-subtitle',
        'tv-player-audio',
        'tv-player-speed',
        'tv-player-close',
      ]) {
        final target = find.byKey(ValueKey(key));
        expect(target.hitTestable(), findsOneWidget);
        final rect = tester.getRect(target);
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(width));
        expect(rect.height, greaterThanOrEqualTo(48));
      }
      if (width > 1000) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.select);
      } else {
        await tester.tap(find.byKey(const ValueKey('player-episodes-button')));
      }
      await tester.pumpAndSettle();
      expect(find.byType(PlayerSelectionPanel), findsOneWidget);
      await tester.tap(find.byTooltip('关闭'));
      await tester.pumpAndSettle();
      expect(find.byType(ModalBarrier).hitTestable(), findsNothing);
      expect(tester.takeException(), isNull);
      await _dispose(tester, harness, selection);
    });
  }
}

void _setViewport(WidgetTester tester, Size size, double dpi) {
  tester.view.devicePixelRatio = dpi;
  tester.view.physicalSize = size * dpi;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _pumpScene(
  WidgetTester tester,
  _Harness harness,
  _SelectionState selection, {
  bool dark = true,
  double textScale = 1,
  bool television = false,
}) => tester.pumpWidget(
  MaterialApp(
    theme: dark ? LumaTheme.dark() : LumaTheme.light(),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: Scaffold(
      body: PlayerScene(
        controller: harness.player,
        interaction: harness.interaction,
        selection: selection,
        isTelevision: television,
        onBack: () {},
        onRotate: () {},
        isDesktop:
            tester.view.physicalSize.width / tester.view.devicePixelRatio >=
            840,
      ),
    ),
  ),
);

Future<void> _dispose(
  WidgetTester tester,
  _Harness harness,
  _SelectionState selection,
) async {
  await tester.pumpWidget(const SizedBox.shrink());
  selection.dispose();
  harness.interaction.dispose();
  harness.player.dispose();
  harness.media.dispose();
}

class _Harness {
  final media = MediaController(MockMediaRepository());
  late final player = _TrackPlayer(media);
  late final interaction = PlayerInteractionController(
    player: player,
    deviceControls: _DeviceControls(),
  );
}

class _TrackPlayer extends PlayerController {
  _TrackPlayer(MediaController media)
    : super(item: buildMediaFixtures().first, media: media);
  @override
  bool get initialized => true;
  @override
  List<AudioTrack> get audioTracks => const [
    AudioTrack('1', '中文', 'zh'),
    AudioTrack('2', '英语', 'en'),
  ];
  @override
  List<SubtitleTrack> get subtitleTracks => const [
    SubtitleTrack('1', '中文', 'zh'),
  ];
}

class _SelectionState extends ChangeNotifier
    implements PlayerSelectionController {
  @override
  bool showEpisodes = true;
  @override
  bool get loading => false;
  @override
  bool get switching => false;
  @override
  String? error;
  @override
  String? selectedEpisodeMediaId = 'e-1';
  @override
  String selectedQualityMediaId = 'q-1';
  bool rejectSelection = false;
  @override
  List<PlayerMediaChoice> get episodes => const [
    PlayerMediaChoice(mediaId: 'e-1', label: '第 1 季 第 1 集'),
    PlayerMediaChoice(mediaId: 'e-2', label: '第 1 季 第 2 集'),
  ];
  @override
  List<PlayerMediaChoice> get qualities => const [
    PlayerMediaChoice(mediaId: 'q-1', label: '1080p'),
    PlayerMediaChoice(mediaId: 'q-2', label: '720p'),
  ];
  @override
  Future<void> refresh() async {
    error = null;
    notifyListeners();
  }

  @override
  Future<bool> selectEpisode(String id) async {
    if (rejectSelection) {
      error = '所选媒体不可用';
      notifyListeners();
      return false;
    }
    selectedEpisodeMediaId = id;
    notifyListeners();
    return true;
  }

  @override
  Future<bool> selectQuality(String id) async {
    selectedQualityMediaId = id;
    notifyListeners();
    return true;
  }
}

class _DeviceControls implements PlayerDeviceControls {
  @override
  Future<PlayerDeviceState> readState() async => const PlayerDeviceState(
    volume: 0.5,
    brightness: 0.5,
    volumeAvailable: false,
    brightnessAvailable: false,
  );
  @override
  Future<void> restoreBrightness() async {}
  @override
  Future<bool> setBrightness(double value) async => false;
  @override
  Future<bool> setVolume(double value) async => false;
}
