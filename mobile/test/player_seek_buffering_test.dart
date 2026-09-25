// 覆盖定位等待链路：快进、拖动提交与取消在等待期间显示缓冲提示，
// 原生确认定位结束后才收束，过时位置不拉回滑块，被取代、重试或释放的请求不写回状态。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/app/controllers/media_controller.dart';
import 'package:luma/core/theme.dart';
import 'package:luma/data/api/api_session.dart';
import 'package:luma/data/fixtures/media_fixtures.dart';
import 'package:luma/data/mock/mock_media_repository.dart';
import 'package:luma/data/models/media_item.dart';
import 'package:luma/data/models/media_types.dart';
import 'package:luma/features/player/player_controller.dart';
import 'package:luma/features/player/player_device_controls.dart';
import 'package:luma/features/player/player_interaction_controller.dart';
import 'package:luma/features/player/widgets/player_scene.dart';
import 'package:luma/features/player/widgets/player_timeline.dart';
import 'package:media_kit/media_kit.dart';

void main() {
  test('快进等待期间立即显示缓冲，旧位置不会把滑块拉回', () async {
    final harness = _SeekHarness.create();
    addTearDown(harness.dispose);
    await harness.start();

    harness.fake.emitPosition(const Duration(seconds: 5));
    await pumpEventQueue();

    harness.player.seekBy(30);
    final target = harness.player.position;
    expect(target, const Duration(seconds: 35));
    expect(harness.player.buffering, isTrue);

    // 定位前的播放位置仍在推进，但不能把滑块拉走，也不能结束等待。
    harness.fake.emitPosition(const Duration(seconds: 7));
    await pumpEventQueue();
    expect(harness.player.position, target);
    expect(harness.player.buffering, isTrue);

    // mpv 可能在画面就绪前就报告目标位置，此时仍要保持缓冲提示。
    harness.fake.nativeSeeking = true;
    harness.fake.emitPosition(target);
    await pumpEventQueue();
    expect(harness.player.buffering, isTrue);

    // 原生定位结束且位置已到目标：收束并恢复播放。
    final playsBefore = harness.fake.playCount;
    harness.fake.nativeSeeking = false;
    harness.fake.nativePosition = target;
    harness.controller.pushSeeking(false);
    await pumpEventQueue();
    expect(harness.player.buffering, isFalse);
    expect(harness.fake.playCount, playsBefore + 1);
  });

  test('定位期间原生缓冲独立叠加，缓冲结束才收起提示', () async {
    final harness = _SeekHarness.create();
    addTearDown(harness.dispose);
    await harness.start();

    harness.fake.emitPosition(const Duration(seconds: 5));
    await pumpEventQueue();

    harness.player.seekBy(30);
    final target = harness.player.position;
    harness.fake.emitBuffering(true);
    harness.fake.nativePosition = target;
    harness.controller.pushSeeking(false);
    await pumpEventQueue();

    expect(harness.player.buffering, isTrue);

    harness.fake.emitBuffering(false);
    await pumpEventQueue();
    expect(harness.player.buffering, isFalse);
  });

  test('连续快进只让最后一次定位收束并恢复播放', () async {
    final harness = _SeekHarness.create();
    addTearDown(harness.dispose);
    await harness.start();

    harness.fake.emitPosition(const Duration(seconds: 5));
    await pumpEventQueue();

    final firstGate = harness.fake.holdSeek();
    harness.player.seekBy(30);
    final first = harness.player.position;
    final secondGate = harness.fake.holdSeek();
    harness.player.seekBy(30);
    final second = harness.player.position;
    expect(first, const Duration(seconds: 35));
    expect(second, const Duration(seconds: 65));

    final playsBefore = harness.fake.playCount;
    harness.fake.nativePosition = first;
    firstGate.complete();
    await pumpEventQueue();

    // 被取代的请求即使命令回执到达，也不能恢复播放或结束等待。
    expect(harness.fake.playCount, playsBefore);
    expect(harness.player.buffering, isTrue);
    expect(harness.player.position, second);

    harness.fake.nativePosition = second;
    secondGate.complete();
    await pumpEventQueue();

    expect(harness.fake.playCount, playsBefore + 1);
    expect(harness.player.buffering, isFalse);
  });

  test('连续拖动提交后仍按拖动前的播放状态恢复', () async {
    final harness = _SeekHarness.create();
    addTearDown(harness.dispose);
    await harness.start();

    harness.fake.emitPosition(const Duration(seconds: 5));
    await pumpEventQueue();
    expect(harness.player.playing, isTrue);

    harness.player
      ..beginScrub()
      ..updateScrub(const Duration(seconds: 40))
      ..commitScrub();
    expect(harness.fake.commands, contains('pause'));

    // 第一次提交的定位仍在等待，紧接着的第二次拖动必须记住此前正在播放。
    harness.player
      ..beginScrub()
      ..updateScrub(const Duration(seconds: 60))
      ..commitScrub();

    final playsBefore = harness.fake.playCount;
    harness.fake.nativePosition = const Duration(seconds: 60);
    harness.fake.emitPosition(const Duration(seconds: 60));
    await pumpEventQueue();

    expect(harness.fake.playCount, playsBefore + 1);
    expect(harness.player.buffering, isFalse);
  });

  test('暂停状态下连续拖动不会误恢复播放', () async {
    final harness = _SeekHarness.create();
    addTearDown(harness.dispose);
    await harness.start();

    harness.fake.emitPosition(const Duration(seconds: 5));
    await pumpEventQueue();
    harness.player.togglePlay();
    await pumpEventQueue();
    expect(harness.player.playing, isFalse);

    harness.player
      ..beginScrub()
      ..updateScrub(const Duration(seconds: 30))
      ..commitScrub();
    harness.player
      ..beginScrub()
      ..updateScrub(const Duration(seconds: 40))
      ..commitScrub();

    final playsBefore = harness.fake.playCount;
    harness.fake.nativePosition = const Duration(seconds: 40);
    harness.fake.emitPosition(const Duration(seconds: 40));
    await pumpEventQueue();

    expect(harness.fake.playCount, playsBefore);
    expect(harness.player.playing, isFalse);
    expect(harness.player.buffering, isFalse);
    // 暂停拖动保存的是用户拖到的目标位置，而不是旧位置。
    expect(harness.repository.lastPositionMs, 40000);
  });

  test('取消拖动回到起点并重新定位', () async {
    final harness = _SeekHarness.create();
    addTearDown(harness.dispose);
    await harness.start();

    harness.fake.emitPosition(const Duration(seconds: 5));
    await pumpEventQueue();

    final gate = harness.fake.holdSeek();
    harness.player
      ..beginScrub()
      ..updateScrub(const Duration(seconds: 40))
      ..commitScrub();
    gate.complete();
    await pumpEventQueue();
    expect(harness.player.buffering, isTrue);

    // 拖动取消：回到开始拖动时的位置，并用同一条链路让底层跟随。
    harness.player
      ..beginScrub()
      ..updateScrub(const Duration(seconds: 60))
      ..cancelScrub();

    expect(harness.player.position, const Duration(seconds: 40));
    expect(harness.fake.seeks.last, const Duration(seconds: 40));
    expect(harness.player.buffering, isTrue);

    harness.fake.emitPosition(const Duration(seconds: 40));
    await pumpEventQueue();
    expect(harness.player.buffering, isFalse);
  });

  test('等待定位时过时的完成事件不会改写进度', () async {
    final harness = _SeekHarness.create();
    addTearDown(harness.dispose);
    await harness.start();

    harness.fake.emitPosition(const Duration(seconds: 5));
    await pumpEventQueue();
    harness.player.seekBy(30);
    final target = harness.player.position;
    final updates = harness.repository.progressUpdates;

    harness.fake.emitCompleted(true);
    await pumpEventQueue();

    expect(harness.player.position, target);
    expect(harness.repository.progressUpdates, updates);
  });

  test('定位命令失败时以错误收束且不残留等待', () async {
    final harness = _SeekHarness.create();
    addTearDown(harness.dispose);
    await harness.start();

    harness.fake.seekError = StateError('原生定位失败');
    harness.player.seekBy(30);
    await pumpEventQueue();

    expect(harness.player.error, contains('原生定位失败'));
    expect(harness.player.buffering, isFalse);
  });

  test('无法读取原生状态时由位置事件收束', () async {
    final harness = _SeekHarness.create();
    addTearDown(harness.dispose);
    await harness.start();
    harness.controller.probeAvailable = false;

    harness.fake.emitPosition(const Duration(seconds: 5));
    await pumpEventQueue();
    harness.player.seekBy(30);
    final target = harness.player.position;
    expect(harness.player.buffering, isTrue);

    harness.fake.emitPosition(target);
    await pumpEventQueue();

    expect(harness.player.buffering, isFalse);
  });

  test('旧定位结束事件不能清除后续目标的等待', () async {
    final harness = _SeekHarness.create();
    addTearDown(harness.dispose);
    await harness.start();
    harness.fake.emitPosition(const Duration(seconds: 5));
    await pumpEventQueue();
    final gate = harness.fake.holdSeek();
    harness.player.seekBy(30);
    harness.player.seekBy(30);
    gate.complete();
    await pumpEventQueue();
    harness.controller.pushSeeking(true);
    harness.fake.nativePosition = const Duration(seconds: 35);
    harness.controller.pushSeeking(false);
    await pumpEventQueue();
    expect(harness.player.position, const Duration(seconds: 65));
    expect(harness.player.buffering, isTrue);
    harness.fake.emitPosition(const Duration(seconds: 65));
    await pumpEventQueue();
    expect(harness.player.buffering, isFalse);
  });

  test('拖动定位期间继续快进仍恢复原先的播放意图', () async {
    final harness = _SeekHarness.create();
    addTearDown(harness.dispose);
    await harness.start();
    harness.player
      ..beginScrub()
      ..updateScrub(const Duration(seconds: 40))
      ..commitScrub();
    await pumpEventQueue();
    expect(harness.player.playing, isFalse);
    harness.player.seekBy(10);
    harness.fake.emitPosition(const Duration(seconds: 50));
    await pumpEventQueue();
    expect(harness.player.playing, isTrue);
    expect(harness.player.buffering, isFalse);
  });

  test('初始化中从头播放取代尚未下发的旧定位', () async {
    final harness = _SeekHarness.create();
    addTearDown(harness.dispose);
    harness.player.start();
    harness.player.seekBy(60);
    await harness.player.restartFromBeginning();
    await pumpEventQueue();
    expect(harness.player.position, Duration.zero);
    expect(harness.fake.seeks, [Duration.zero]);
    expect(harness.player.buffering, isFalse);
  });

  test('当前暂停命令失败保留错误，旧会话失败不污染重试', () async {
    final harness = _SeekHarness.create();
    addTearDown(harness.dispose);
    await harness.start();
    harness.fake.pauseError = StateError('暂停失败');
    harness.player.togglePlay();
    await pumpEventQueue();
    expect(harness.player.error, contains('暂停失败'));
    await harness.player.retry();
    final old = harness.fake;
    final pause = old.pauseGate = Completer<void>();
    old.pauseError = StateError('旧暂停失败');
    harness.player.togglePlay();
    await harness.player.retry();
    pause.complete();
    await pumpEventQueue();
    expect(harness.player.error, isNull);
    expect(harness.player.playing, isTrue);
  });

  test('初始化期间的快进在起播后补发', () async {
    final harness = _SeekHarness.create();
    addTearDown(harness.dispose);

    harness.player.start();
    harness.player.seekBy(60);
    final target = harness.player.position;

    await pumpEventQueue();

    expect(harness.player.initialized, isTrue);
    expect(harness.fake.seeks, contains(target));
    // 补发的定位同样要等原生到位，不会直接生效。
    expect(harness.player.buffering, isTrue);

    harness.fake.emitPosition(target);
    await pumpEventQueue();
    expect(harness.player.buffering, isFalse);
  });

  test('释放播放器后等待中的定位不再写回状态', () async {
    final harness = _SeekHarness.create();
    addTearDown(harness.dispose);
    await harness.start();

    harness.fake.emitPosition(const Duration(seconds: 5));
    await pumpEventQueue();

    final gate = harness.fake.holdSeek();
    harness.player.seekBy(30);
    final playsBefore = harness.fake.playCount;
    var notifications = 0;
    harness.player.addListener(() => notifications++);

    harness.player.dispose();
    final notifiedAtDispose = notifications;
    gate.complete();
    await pumpEventQueue();

    expect(harness.fake.playCount, playsBefore);
    expect(harness.repository.progressUpdates, 0);
    expect(notifications, notifiedAtDispose);
  });

  test('重试后旧定位不再影响新会话', () async {
    final harness = _SeekHarness.create();
    addTearDown(harness.dispose);
    await harness.start();

    harness.fake.emitPosition(const Duration(seconds: 5));
    await pumpEventQueue();

    final oldPlayer = harness.fake;
    final gate = oldPlayer.holdSeek();
    harness.player.seekBy(30);
    final playsBefore = oldPlayer.playCount;

    await harness.player.retry();
    await pumpEventQueue();
    gate.complete();
    await pumpEventQueue();

    expect(harness.player.initialized, isTrue);
    expect(harness.player.buffering, isFalse);
    expect(oldPlayer.playCount, playsBefore);
    expect(harness.repository.progressUpdates, 0);
  });

  testWidgets('手机拖动进度时立即显示缓冲圈并在落地后移除', (tester) async {
    final harness = _SeekHarness.create();
    try {
      await harness.startWidgets(tester);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      harness.fake.nativeSeeking = true;
      await tester.drag(harness.timelineSlider, const Offset(160, 0));
      await tester.pump();

      expect(harness.player.scrubbing, isFalse);
      expect(harness.player.buffering, isTrue);
      expect(find.text('正在缓冲'), findsOneWidget);
      expect(harness.timelineSlider, findsOneWidget);
      final scene = tester.getRect(find.byType(PlayerScene));
      _expectCenteredHud(tester, scene);

      harness.fake.nativeSeeking = false;
      harness.fake.emitPosition(harness.player.position);
      harness.controller.pushSeeking(false);
      await tester.pump();

      expect(harness.player.buffering, isFalse);
      expect(find.text('正在缓冲'), findsNothing);
      expect(harness.timelineSlider, findsOneWidget);
    } finally {
      harness.dispose();
    }
  });

  testWidgets('宽屏键盘快进时显示缓冲圈且控件布局保持不变', (tester) async {
    final harness = _SeekHarness.create();
    try {
      await harness.startWidgets(tester, isDesktop: true);
      expect(find.byTooltip('静音'), findsOneWidget);
      expect(find.byTooltip('旋转屏幕'), findsNothing);

      harness.fake.nativeSeeking = true;
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();

      expect(harness.player.position, const Duration(seconds: 10));
      expect(harness.player.buffering, isTrue);
      expect(find.text('正在缓冲'), findsOneWidget);
      expect(find.byTooltip('静音'), findsOneWidget);
      final scene = tester.getRect(find.byType(PlayerScene));
      _expectCenteredHud(tester, scene);

      harness.fake.nativeSeeking = false;
      harness.fake.emitPosition(harness.player.position);
      harness.controller.pushSeeking(false);
      await tester.pump();

      expect(harness.player.buffering, isFalse);
      expect(find.text('正在缓冲'), findsNothing);
      expect(harness.timelineSlider, findsOneWidget);
      expect(find.byTooltip('静音'), findsOneWidget);
    } finally {
      harness.dispose();
    }
  });
  testWidgets('缓冲提示适应手机平板宽屏、浅深主题与桌面 DPI', (tester) async {
    for (final size in const [
      Size(320, 693),
      Size(390, 844),
      Size(768, 1024),
      Size(1024, 768),
      Size(960, 640),
      Size(1280, 800),
    ]) {
      final desktop = size.width >= 960;
      for (final brightness in Brightness.values) {
        for (final dpr in desktop ? [1.0, 1.25, 1.5] : [1.0]) {
          final harness = _SeekHarness.create();
          try {
            await harness.startWidgets(
              tester,
              isDesktop: desktop,
              size: size,
              brightness: brightness,
              devicePixelRatio: dpr,
            );
            harness.fake.nativeSeeking = true;
            harness.player.seekBy(30);
            await tester.pump();
            final scene = tester.getRect(find.byType(PlayerScene));
            _expectCenteredHud(tester, scene);
            final timeline = tester.getRect(harness.timelineSlider);
            expect(scene.contains(timeline.topLeft), isTrue);
            expect(scene.contains(timeline.bottomRight), isTrue);
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox.shrink());
          } finally {
            harness.dispose();
          }
        }
      }
    }
  });
}

/// 状态提示位于场景中央：水平居中、垂直接近中线。
void _expectCenteredHud(WidgetTester tester, Rect scene) {
  expect(find.text('正在缓冲'), findsOneWidget);
  final hud = tester.getCenter(find.byType(CircularProgressIndicator));
  expect(hud.dx, moreOrLessEquals(scene.center.dx, epsilon: 1));
  expect((hud.dy - scene.center.dy).abs(), lessThan(scene.height * 0.1));
}

/// 假的平台播放器：记录命令与定位请求，并由测试推进原生事件。
class _FakePlatformPlayer extends PlatformPlayer {
  _FakePlatformPlayer({required super.configuration});

  final List<Duration> seeks = [];
  final List<String> commands = [];
  final List<Completer<void>> _gates = [];
  Object? seekError;
  Object? pauseError;
  Completer<void>? pauseGate;
  int playCount = 0;

  /// 原生 `seeking` 与 `time-pos` 的当前值，供定位确认读取。
  bool nativeSeeking = false;
  Duration nativePosition = Duration.zero;

  /// 让接下来的一次定位命令挂起，返回放行用的 completer。
  Completer<void> holdSeek() {
    final gate = Completer<void>();
    _gates.add(gate);
    return gate;
  }

  @override
  Future<void> open(Playable playable, {bool play = true}) async {
    commands.add('open');
    state = state.copyWith(duration: const Duration(minutes: 10));
    if (play) await this.play();
  }

  @override
  Future<void> play() async {
    commands.add('play');
    playCount++;
    state = state.copyWith(playing: true);
    playingController.add(true);
  }

  @override
  Future<void> pause() async {
    commands.add('pause');
    await pauseGate?.future;
    final error = pauseError;
    if (error != null) throw error;
    state = state.copyWith(playing: false);
    playingController.add(false);
  }

  @override
  Future<void> seek(Duration duration) async {
    seeks.add(duration);
    if (_gates.isNotEmpty) await _gates.removeAt(0).future;
    final error = seekError;
    if (error != null) throw error;
  }

  @override
  Future<void> setVolume(double volume) async {
    state = state.copyWith(volume: volume);
  }

  @override
  Future<void> setRate(double rate) async {
    state = state.copyWith(rate: rate);
  }

  void emitPosition(Duration value) {
    nativePosition = value;
    state = state.copyWith(position: value);
    positionController.add(value);
  }

  void emitBuffering(bool value) => bufferingController.add(value);

  void emitCompleted(bool value) => completedController.add(value);
}

/// 测试控制器：注入假平台播放器与原生定位状态，不启动原生解码器。
class _SeekTestController extends PlayerController {
  _SeekTestController({
    required super.item,
    required super.media,
    required List<_FakePlatformPlayer> fakes,
  }) : _fakes = fakes,
       super(
         apiSession: ApiSession(),
         debugPlatformPlayerFactory: (configuration) {
           final fake = _FakePlatformPlayer(configuration: configuration);
           fakes.add(fake);
           return fake;
         },
         debugVideoControllerFactory: (_) => null,
       );

  final List<_FakePlatformPlayer> _fakes;
  ValueChanged<bool>? _seekingCallback;

  /// 是否提供原生定位状态；false 时退化为位置事件判据。
  bool probeAvailable = true;

  @override
  Future<({bool seeking, Duration? position})?> readNativeSeekState(
    Player player,
  ) async {
    if (!probeAvailable) return null;
    final fake = _fakes.last;
    return (seeking: fake.nativeSeeking, position: fake.nativePosition);
  }

  @override
  Future<void> observeNativeSeeking(
    Player player,
    ValueChanged<bool> onChanged,
  ) async {
    _seekingCallback = onChanged;
  }

  /// 推送一次原生 `seeking` 变化。
  void pushSeeking(bool seeking) => _seekingCallback?.call(seeking);
}

class _SeekHarness {
  _SeekHarness._(this.repository, this.media, this.player, this.fakes);

  final _CountingMediaRepository repository;
  final MediaController media;
  final _SeekTestController player;
  final List<_FakePlatformPlayer> fakes;
  late final PlayerInteractionController interaction =
      PlayerInteractionController(
        player: player,
        deviceControls: _NoopDeviceControls(),
      );

  _FakePlatformPlayer get fake => fakes.last;
  _SeekTestController get controller => player;

  Finder get timelineSlider => find.descendant(
    of: find.byType(PlayerTimeline),
    matching: find.byType(Slider),
  );

  static _SeekHarness create() {
    final repository = _CountingMediaRepository();
    final media = MediaController(repository);
    final item = buildMediaFixtures()
        .firstWhere((item) => item.type == MediaType.video)
        .copyWith(
          streamUrl: 'http://127.0.0.1:19874/api/v1/media/video-0/stream',
        );
    media.remember(item, notify: false);
    final fakes = <_FakePlatformPlayer>[];
    final player = _SeekTestController(item: item, media: media, fakes: fakes);
    return _SeekHarness._(repository, media, player, fakes);
  }

  Future<void> start() async {
    player.start();
    await pumpEventQueue();
    expect(player.initialized, isTrue);
    expect(fakes, isNotEmpty);
  }

  Future<void> startWidgets(
    WidgetTester tester, {
    bool isDesktop = false,
    Size? size,
    Brightness brightness = Brightness.dark,
    double devicePixelRatio = 1,
  }) async {
    tester.view.devicePixelRatio = devicePixelRatio;
    tester.view.physicalSize =
        (size ?? (isDesktop ? const Size(1280, 800) : const Size(390, 844))) *
        devicePixelRatio;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    player.start();
    await tester.pumpWidget(
      MaterialApp(
        theme: brightness == Brightness.dark
            ? LumaTheme.dark()
            : LumaTheme.light(),
        home: Scaffold(
          body: PlayerScene(
            controller: player,
            interaction: interaction,
            onBack: () {},
            onMinimize: () {},
            onRotate: isDesktop ? null : () {},
            isDesktop: isDesktop,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(player.initialized, isTrue);
  }

  void dispose() {
    interaction.dispose();
    player.dispose();
    media.dispose();
  }
}

class _CountingMediaRepository extends MockMediaRepository {
  var progressUpdates = 0;
  var lastPositionMs = 0;

  @override
  Future<MediaItem> updateProgress(String id, int positionMs) {
    progressUpdates++;
    lastPositionMs = positionMs;
    return super.updateProgress(id, positionMs);
  }
}

class _NoopDeviceControls implements PlayerDeviceControls {
  @override
  Future<PlayerDeviceState> readState() async => const PlayerDeviceState(
    volume: 0.5,
    brightness: 0.5,
    volumeAvailable: true,
    brightnessAvailable: true,
  );

  @override
  Future<void> restoreBrightness() async {}

  @override
  Future<bool> setBrightness(double value) async => true;

  @override
  Future<bool> setVolume(double value) async => true;
}
