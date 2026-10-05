// 播放竞态回归：真实 PlayerController/PlayerScene 消费串行假平台的状态事件，
// 覆盖延迟播放、初始化暂停、定位续播与速度弹窗焦点；仓库记录真实进度提交。
// 每例独立会话，门闩控制原生命令落地，卸载时释放控制器、计时器和依赖。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/app/app_dependencies.dart';
import 'package:luma/app/app_device_profile.dart';
import 'package:luma/app/app_scope.dart';
import 'package:luma/core/theme.dart';
import 'package:luma/data/fixtures/media_fixtures.dart';
import 'package:luma/data/mock/mock_connection_service.dart';
import 'package:luma/data/mock/mock_media_repository.dart';
import 'package:luma/data/models/media_item.dart';
import 'package:luma/data/models/media_types.dart';
import 'package:luma/features/player/player_controller.dart';
import 'package:luma/features/player/player_device_controls.dart';
import 'package:luma/features/player/player_interaction_controller.dart';
import 'package:luma/features/player/widgets/player_scene.dart';
import 'package:media_kit/media_kit.dart';

void main() {
  group('排队播放与最新暂停意图', () {
    test('已初始化暂停后排队播放，后台暂停必须使原生最终保持暂停', () async {
      final harness = _PlaybackHarness();
      addTearDown(harness.dispose);
      await harness.start();
      harness.fake.emitPosition(const Duration(seconds: 12));
      await pumpEventQueue();
      await harness.player.pause(revealControls: false);
      await pumpEventQueue();
      expect(harness.fake.state.playing, isFalse);
      final savedBefore = harness.repository.positions.length;

      final playGate = harness.fake.holdNextPlay();
      harness.player.togglePlay();
      await pumpEventQueue();
      expect(harness.fake.pendingPlays, 1);
      expect(harness.fake.state.playing, isFalse);
      await harness.player.pause(revealControls: false);
      await harness.player.pause(revealControls: false);
      playGate.complete();
      await pumpEventQueue();

      expect(
        harness.fake.state.playing,
        isFalse,
        reason: '后台暂停必须排在已请求但尚未落地的播放之后生效',
      );
      expect(harness.player.playing, isFalse);
      expect(
        harness.repository.positions.length,
        savedBefore,
        reason: '已暂停位置不因重复后台事件再次保存',
      );
      harness.player.togglePlay();
      await pumpEventQueue();
      expect(harness.fake.state.playing, isTrue, reason: '之后的明确播放仍能恢复播放');
      expect(harness.player.playing, isTrue);
    });

    testWidgets('mediaPlay 排队期间连按 mediaPause，放行后原生与按钮均暂停', (tester) async {
      final harness = _PlaybackHarness();
      addTearDown(harness.dispose);
      await harness.pumpScene(tester);
      harness.fake.emitPosition(const Duration(seconds: 12));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.mediaPause);
      await tester.pump();
      expect(harness.fake.state.playing, isFalse);
      final savedBefore = harness.repository.positions.length;
      final playGate = harness.fake.holdNextPlay();

      await tester.sendKeyEvent(LogicalKeyboardKey.mediaPlay);
      await tester.pump();
      expect(harness.fake.pendingPlays, 1);
      await tester.sendKeyEvent(LogicalKeyboardKey.mediaPause);
      await tester.sendKeyEvent(LogicalKeyboardKey.mediaPause);
      await tester.pump();
      playGate.complete();
      await tester.pump();
      await tester.pump();

      expect(harness.fake.state.playing, isFalse);
      expect(harness.player.playing, isFalse);
      expect(harness.repository.positions.length, savedBefore);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('tv-player-play')),
          matching: find.byIcon(Icons.play_arrow_rounded),
        ),
        findsOneWidget,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.mediaPlay);
      await tester.pump();
      expect(harness.fake.state.playing, isTrue);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('tv-player-play')),
          matching: find.byIcon(Icons.pause_rounded),
        ),
        findsOneWidget,
      );
    });

    test('初始化的原生 pause 等待期间明确播放，完成后原生实际起播', () async {
      final openGate = Completer<void>();
      final harness = _PlaybackHarness(openGate: openGate);
      addTearDown(harness.dispose);
      harness.player.start();
      await pumpEventQueue();
      await harness.player.pause(revealControls: false);
      final pauseGate = harness.fake.holdNextPause();
      openGate.complete();
      await pumpEventQueue();
      expect(harness.fake.pendingPauses, 1);
      expect(harness.player.initialized, isFalse);

      harness.player.togglePlay();
      pauseGate.complete();
      await pumpEventQueue();

      expect(harness.player.initialized, isTrue);
      expect(
        harness.fake.state.playing,
        isTrue,
        reason: '界面显示播放前必须把最新播放意图下发原生',
      );
      expect(harness.player.playing, isTrue);
      expect(harness.repository.positions, isEmpty);
    });
  });

  group('定位与拖动播放意图保持', () {
    for (final pauseDuringScrub in [false, true]) {
      test('拖动提交后${pauseDuringScrub ? '遵守后台暂停' : '恢复原播放'}并保留最终位置', () async {
        final harness = _PlaybackHarness();
        addTearDown(harness.dispose);
        await harness.start();
        harness.fake.emitPosition(const Duration(seconds: 12));
        await pumpEventQueue();
        harness.player.beginScrub();
        await pumpEventQueue();
        expect(harness.fake.state.playing, isFalse);
        harness.player.updateScrub(const Duration(seconds: 48));
        if (pauseDuringScrub) {
          await harness.player.pause(revealControls: false);
        }
        final seekGate = harness.fake.holdNextSeek();
        harness.player.commitScrub();
        await pumpEventQueue();
        expect(harness.player.position, const Duration(seconds: 48));
        expect(harness.player.buffering, isTrue);
        seekGate.complete();
        await pumpEventQueue();

        expect(harness.player.position, const Duration(seconds: 48));
        expect(harness.fake.state.position, const Duration(seconds: 48));
        expect(harness.player.buffering, isFalse);
        expect(harness.fake.state.playing, !pauseDuringScrub);
        expect(harness.player.playing, !pauseDuringScrub);
        if (pauseDuringScrub) {
          expect(harness.repository.positions, [48000]);
          await harness.player.pause(revealControls: false);
          expect(harness.repository.positions, [48000]);
        }
      });
    }

    test('拖动取消恢复原位置和播放，随后重复暂停仅保存一次', () async {
      final harness = _PlaybackHarness();
      addTearDown(harness.dispose);
      await harness.start();
      harness.fake.emitPosition(const Duration(seconds: 12));
      await pumpEventQueue();
      harness.player.beginScrub();
      await pumpEventQueue();
      harness.player.updateScrub(const Duration(seconds: 48));
      harness.player.cancelScrub();
      await pumpEventQueue();
      expect(harness.player.position, const Duration(seconds: 12));
      expect(harness.fake.state.playing, isTrue);
      expect(harness.repository.positions, isEmpty);
      await harness.player.pause();
      await harness.player.pause();
      await pumpEventQueue();
      expect(harness.fake.state.playing, isFalse);
      expect(harness.repository.positions, [12000]);
    });
  });

  for (final selectSpeed in [false, true]) {
    testWidgets('初始化期间打开速度弹窗，起播并超时后${selectSpeed ? '选择' : '取消'}仍恢复速度焦点', (
      tester,
    ) async {
      final openGate = Completer<void>();
      final harness = _PlaybackHarness(openGate: openGate);
      addTearDown(harness.dispose);
      await harness.pumpScene(tester, dark: !selectSpeed);
      expect(harness.player.initialized, isFalse);
      final speedNode = harness.surfaceNode(tester, 'tv-player-speed');
      speedNode.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('播放速度'), findsOneWidget);
      final selectedChoice = Focus.of(
        tester.element(
          find.descendant(of: find.byType(Dialog), matching: find.text('1.0x')),
        ),
      );
      expect(selectedChoice.hasFocus, isTrue);

      openGate.complete();
      await tester.pump();
      await tester.pump();
      expect(harness.fake.state.playing, isTrue);
      await tester.pump(const Duration(seconds: 5));
      expect(find.text('播放速度'), findsOneWidget);
      expect(selectedChoice.hasFocus, isTrue, reason: '底层起播不得把焦点从弹窗抢走');
      expect(
        harness.player.controlsVisible,
        isTrue,
        reason: '弹窗打开期间持续暂停控制层自动隐藏',
      );

      if (selectSpeed) {
        await tester.tap(find.text('1.5x'));
      } else {
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      }
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('播放速度'), findsNothing);
      expect(harness.player.speed, selectSpeed ? 1.5 : 1.0);
      expect(harness.fake.state.rate, selectSpeed ? 1.5 : 1.0);
      expect(speedNode.hasFocus, isTrue);
      expect(harness.player.controlsVisible, isTrue);
      // 恢复的焦点必须仍可操作同一可见按钮。
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('播放速度'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(seconds: 5));
      expect(harness.player.controlsVisible, isFalse, reason: '关闭弹窗后继续正常自动隐藏');
    });
  }

  for (final desktop in [false, true]) {
    testWidgets('普通${desktop ? '宽屏键盘' : '手机触摸'}暂停与继续保持原生和可见按钮一致', (
      tester,
    ) async {
      final harness = _PlaybackHarness(television: false);
      addTearDown(harness.dispose);
      await harness.pumpScene(
        tester,
        desktop: desktop,
        dark: desktop,
        size: desktop ? const Size(1280, 720) : const Size(390, 844),
      );
      expect(find.byTooltip('暂停'), findsOneWidget);
      await tester.tap(find.byTooltip('暂停'));
      await tester.pump();
      expect(harness.fake.state.playing, isFalse);
      expect(find.byTooltip('播放'), findsOneWidget);
      if (desktop) {
        await tester.sendKeyEvent(LogicalKeyboardKey.space);
      } else {
        await tester.tap(find.byTooltip('播放'));
      }
      await tester.pump();
      expect(harness.fake.state.playing, isTrue);
      expect(find.byTooltip('暂停'), findsOneWidget);
    });
  }
}

class _PlaybackHarness {
  _PlaybackHarness({Completer<void>? openGate, bool television = true}) {
    dependencies = AppDependencies(
      mediaRepository: repository,
      connectionService: MockConnectionService(),
      deviceProfile: television
          ? AppDeviceProfile.television
          : AppDeviceProfile.standard,
    );
    final item = buildMediaFixtures()
        .firstWhere((item) => item.type == MediaType.video)
        .copyWith(streamUrl: 'http://127.0.0.1:19878/api/v1/media/v/stream');
    dependencies.media.remember(item, notify: false);
    player = PlayerController(
      item: item,
      media: dependencies.media,
      apiSession: dependencies.apiSession,
      startFromBeginning: true,
      debugPlatformPlayerFactory: (configuration) {
        fake = _QueuedPlatformPlayer(
          configuration: configuration,
          openGate: openGate,
        );
        return fake;
      },
      debugVideoControllerFactory: (_) => null,
    );
    interaction = PlayerInteractionController(
      player: player,
      deviceControls: _DeviceControls(),
    );
  }

  final repository = _ProgressRepository();
  late final AppDependencies dependencies;
  late final PlayerController player;
  late final PlayerInteractionController interaction;
  late _QueuedPlatformPlayer fake;
  bool _disposed = false;

  Future<void> start() async {
    player.start();
    await pumpEventQueue();
    expect(player.initialized, isTrue);
    expect(fake.state.playing, isTrue);
  }

  Future<void> pumpScene(
    WidgetTester tester, {
    bool desktop = false,
    bool dark = true,
    Size size = const Size(1280, 720),
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    player.start();
    await tester.pumpWidget(
      AppScope(
        dependencies: dependencies,
        child: MaterialApp(
          theme: dark ? LumaTheme.dark() : LumaTheme.light(),
          home: _SessionLifetime(
            onDispose: dispose,
            child: Scaffold(
              body: PlayerScene(
                controller: player,
                interaction: interaction,
                onBack: () {},
                onRotate: null,
                isDesktop: desktop,
                isTelevision: dependencies.deviceProfile.isTelevision,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  FocusNode surfaceNode(WidgetTester tester, String key) => tester
      .widget<InkWell>(
        find.descendant(
          of: find.byKey(ValueKey<String>(key)),
          matching: find.byType(InkWell),
        ),
      )
      .focusNode!;

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    interaction.dispose();
    player.dispose();
    dependencies.dispose();
  }
}

class _ProgressRepository extends MockMediaRepository {
  final List<int> positions = [];

  @override
  Future<MediaItem> updateProgress(String id, int positionMs) async {
    positions.add(positionMs);
    return super.updateProgress(id, positionMs);
  }
}

// 和 media_kit 命令锁一样按调用顺序落地；门闩只延迟一次命令，
// 原生状态与事件在命令执行时更新，不读取待测控制器的播放意图。
class _QueuedPlatformPlayer extends PlatformPlayer {
  _QueuedPlatformPlayer({required super.configuration, this.openGate});

  final Completer<void>? openGate;
  final List<Completer<void>> _gates = [];
  Future<void> _commands = Future<void>.value();
  Completer<void>? _nextPlay;
  Completer<void>? _nextPause;
  Completer<void>? _nextSeek;
  int pendingPlays = 0;
  int pendingPauses = 0;

  Completer<void> _gate() {
    final gate = Completer<void>();
    _gates.add(gate);
    return gate;
  }

  Completer<void> holdNextPlay() => _nextPlay = _gate();
  Completer<void> holdNextPause() => _nextPause = _gate();
  Completer<void> holdNextSeek() => _nextSeek = _gate();

  Future<void> _enqueue(Completer<void>? gate, void Function() action) {
    return _commands = _commands.then((_) async {
      if (gate != null) await gate.future;
      action();
    });
  }

  @override
  Future<void> open(Playable playable, {bool play = true}) async {
    state = state.copyWith(duration: const Duration(minutes: 10));
    if (openGate != null) await openGate!.future;
    if (play) await this.play();
  }

  @override
  Future<void> play() {
    final gate = _nextPlay;
    _nextPlay = null;
    pendingPlays++;
    return _enqueue(gate, () {
      pendingPlays--;
      state = state.copyWith(playing: true);
      playingController.add(true);
    });
  }

  @override
  Future<void> pause() {
    final gate = _nextPause;
    _nextPause = null;
    pendingPauses++;
    return _enqueue(gate, () {
      pendingPauses--;
      state = state.copyWith(playing: false);
      playingController.add(false);
    });
  }

  @override
  Future<void> seek(Duration position) {
    final gate = _nextSeek;
    _nextSeek = null;
    return _enqueue(gate, () => emitPosition(position));
  }

  void emitPosition(Duration position) {
    state = state.copyWith(position: position);
    positionController.add(position);
  }

  @override
  Future<void> setVolume(double volume) async {
    state = state.copyWith(volume: volume);
  }

  @override
  Future<void> setRate(double rate) async {
    state = state.copyWith(rate: rate);
  }

  @override
  Future<void> dispose() async {
    if (openGate != null && !openGate!.isCompleted) openGate!.complete();
    for (final gate in _gates) {
      if (!gate.isCompleted) gate.complete();
    }
    await _commands;
    await super.dispose();
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
  Future<bool> setBrightness(double value) async => true;

  @override
  Future<bool> setVolume(double value) async => true;
}

// widget 树卸载时先释放外部会话，避免测试框架检查到遗留计时器。
class _SessionLifetime extends StatefulWidget {
  const _SessionLifetime({required this.onDispose, required this.child});

  final VoidCallback onDispose;
  final Widget child;

  @override
  State<_SessionLifetime> createState() => _SessionLifetimeState();
}

class _SessionLifetimeState extends State<_SessionLifetime> {
  @override
  void dispose() {
    widget.onDispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
