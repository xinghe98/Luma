// TV 播放器按键契约与生命周期测试：复用假平台播放器验证隐藏/可见两种
// 控制层状态下的遥控按键、幂等暂停、初始化期间的暂停意图、Back 分层与
// TV 系统 UI 会话不触碰系统方向/沉浸接口。
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
import 'package:luma/features/player/widgets/player_controls.dart';
import 'package:luma/features/player/widgets/player_gesture_layer.dart';
import 'package:luma/features/player/widgets/player_scene.dart';
import 'package:luma/features/player/widgets/tv_player_controls.dart';
import 'package:media_kit/media_kit.dart';

void main() {
  group('TV 幂等暂停与暂停意图', () {
    test('后台暂停先于初始化完成：open 放行后保持暂停，不自动出声', () async {
      final gate = Completer<void>();
      final harness = _TvControllerHarness.create(openGate: gate);
      addTearDown(harness.dispose);
      harness.player.start();
      await pumpEventQueue();
      // 初始化被 open 阻塞期间收到后台事件：只记录意图。
      await harness.player.pause(revealControls: false);
      expect(harness.player.playing, isFalse);

      final fake = harness.fake;
      gate.complete();
      await pumpEventQueue();

      expect(harness.player.initialized, isTrue);
      expect(harness.player.playing, isFalse);
      expect(fake.playCount, 0, reason: '后台收到的暂停意图必须阻止自动起播');

      // 返回前台后仍保持暂停，用户确认键才继续。
      harness.player.togglePlay();
      await pumpEventQueue();
      expect(fake.playCount, 1);
      expect(harness.player.playing, isTrue);
    });

    test('首次 play 阻塞期间后台暂停，命令放行后原生与页面都保持暂停', () async {
      final gate = Completer<void>();
      final harness = _TvControllerHarness.create(playGate: gate);
      addTearDown(harness.dispose);
      harness.player.start();
      await pumpEventQueue();
      expect(harness.fake.playCount, 1);
      await harness.player.pause(revealControls: false);
      gate.complete();
      await pumpEventQueue();
      expect(harness.player.initialized, isTrue);
      expect(harness.player.playing, isFalse);
      expect(harness.fake.state.playing, isFalse);
    });

    test('初始化前的明确播放清除暂停意图', () async {
      final gate = Completer<void>();
      final harness = _TvControllerHarness.create(openGate: gate);
      addTearDown(harness.dispose);
      harness.player.start();
      await pumpEventQueue();
      await harness.player.pause(revealControls: false);
      // 用户在初始化完成前明确要求播放：意图被清除，起播照常。
      harness.player.togglePlay();

      final fake = harness.fake;
      gate.complete();
      await pumpEventQueue();

      expect(harness.player.initialized, isTrue);
      expect(harness.player.playing, isTrue);
      expect(fake.playCount, 1);
    });

    test('定位阻塞期间后台暂停：定位落地后不恢复播放', () async {
      final harness = _TvControllerHarness.create();
      addTearDown(harness.dispose);
      await harness.start();

      harness.fake.emitPosition(const Duration(seconds: 5));
      await pumpEventQueue();

      final gate = harness.fake.holdSeek();
      harness.player.seekBy(30);
      final target = harness.player.position;
      expect(target, const Duration(seconds: 35));

      await harness.player.pause(revealControls: false);
      expect(harness.player.playing, isFalse);

      gate.complete();
      // 位置事件到达目标且命令已被接受：定位收束，暂停意图阻止续播。
      harness.fake.emitPosition(target);
      await pumpEventQueue();

      // 定位完成只保存进度，不恢复播放：后台无音频。
      expect(harness.player.playing, isFalse);
      expect(harness.fake.playCount, 1, reason: '只有初始化时的一次起播');
      expect(harness.player.position, target);
    });

    test('mediaPause 连按仍暂停且不重复写进度', () async {
      final harness = _TvControllerHarness.create();
      addTearDown(harness.dispose);
      await harness.start();

      harness.fake.emitPosition(const Duration(seconds: 10));
      await pumpEventQueue();

      await harness.player.pause(revealControls: false);
      await harness.player.pause(revealControls: false);
      await pumpEventQueue();

      expect(harness.player.playing, isFalse);
      expect(
        harness.fake.commands.where((command) => command == 'pause').length,
        1,
      );
      expect(harness.repository.progressUpdates, 1);
    });

    test('重试保留暂停意图：重试后仍保持暂停', () async {
      final harness = _TvControllerHarness.create(openError: Exception('流不可用'));
      addTearDown(harness.dispose);
      harness.player.start();
      await pumpEventQueue();
      expect(harness.player.error, isNotNull, reason: '初始化失败会保留错误');
      expect(harness.player.initialized, isFalse);

      await harness.player.pause(revealControls: false);
      await harness.player.retry();
      await pumpEventQueue();

      expect(harness.player.initialized, isTrue);
      expect(harness.player.playing, isFalse);
      expect(harness.fake.playCount, 0);
    });

    test('离线保存失败不阻塞暂停与退出', () async {
      final repository = _ThrowingProgressRepository();
      final media = MediaController(repository);
      final item = buildMediaFixtures()
          .firstWhere((item) => item.type == MediaType.video)
          .copyWith(streamUrl: 'http://127.0.0.1:19875/api/v1/media/v/stream');
      media.remember(item, notify: false);
      final fakes = <_FakePlatformPlayer>[];
      final player = PlayerController(
        item: item,
        media: media,
        apiSession: ApiSession(),
        debugPlatformPlayerFactory: (configuration) {
          final fake = _FakePlatformPlayer(configuration: configuration);
          fakes.add(fake);
          return fake;
        },
        debugVideoControllerFactory: (_) => null,
      );
      addTearDown(() {
        player.dispose();
        media.dispose();
      });

      player.start();
      await pumpEventQueue();
      expect(player.initialized, isTrue);

      await player.pause(revealControls: false);
      expect(player.playing, isFalse);

      final fake = fakes.last;
      // 保存失败被吞掉：退出流程照常完成并释放解码器。
      await player.shutdown();
      await pumpEventQueue();
      expect(fake.disposed, isTrue);
    });
  });

  group('TV 播放器按键契约', () {
    testWidgets('挂载后播放按钮获得焦点，且不渲染锁定/旋转/音量/小窗控件', (tester) async {
      final harness = _TvSceneHarness.create();
      addTearDown(harness.dispose);
      await harness.pump(tester);

      expect(find.byType(TvPlayerControls), findsOneWidget);
      expect(find.byType(PlayerControls), findsNothing);
      expect(harness.surfaceNode(tester, 'tv-player-play').hasFocus, isTrue);
      // TV 控制层不用 IconButton（锁定/旋转/音量/小窗等普通端控件不渲染），
      // 也不挂手机手势层。
      expect(find.byType(IconButton), findsNothing);
      expect(find.byType(PlayerGestureLayer), findsNothing);
    });

    testWidgets('电视控制层底部运输区、时间轴与标题分层，遥控可到倍速和关闭', (tester) async {
      final harness = _TvSceneHarness.create();
      addTearDown(harness.dispose);
      await harness.pump(tester);
      final transport = tester.getRect(
        find.byKey(const ValueKey('tv-player-transport')),
      );
      final timeline = tester.getRect(
        find.byKey(const ValueKey('tv-player-timeline')),
      );
      final title = tester.getRect(
        find.byKey(const ValueKey('tv-player-title')),
      );
      expect(transport.top, greaterThan(720 * 0.7));
      expect(timeline.bottom, lessThanOrEqualTo(transport.top));
      expect(title.bottom, lessThan(timeline.top));
      expect(
        find.byKey(const ValueKey('tv-player-close')).hitTestable(),
        findsOneWidget,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      expect(
        harness.surfaceNode(tester, 'tv-player-timeline').hasFocus,
        isTrue,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(harness.surfaceNode(tester, 'tv-player-play').hasFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(harness.surfaceNode(tester, 'tv-player-forward').hasFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(harness.surfaceNode(tester, 'tv-player-speed').hasFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(harness.surfaceNode(tester, 'tv-player-close').hasFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pump();
      expect(harness.backCalls, 1);
    });

    for (final width in [320.0, 390.0]) {
      testWidgets('TV 窄窗口 $width 次要播放器操作换行且全部可见', (tester) async {
        final harness = _TvSceneHarness.create();
        addTearDown(harness.dispose);
        await harness.pump(tester);
        tester.view.physicalSize = Size(width, 844);
        await tester.pump();
        final play = tester.getRect(
          find.byKey(const ValueKey('tv-player-play')),
        );
        final speed = tester.getRect(
          find.byKey(const ValueKey('tv-player-speed')),
        );
        expect(speed.top, greaterThan(play.bottom));
        for (final key in ['rewind', 'play', 'forward', 'speed', 'close']) {
          final finder = find.byKey(ValueKey('tv-player-$key'));
          expect(finder.hitTestable(), findsOneWidget);
          final rect = tester.getRect(finder);
          expect(rect.left, greaterThanOrEqualTo(0));
          expect(rect.right, lessThanOrEqualTo(width));
        }
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('控制层隐藏时确认键切换播放、显示控制层并把焦点交给播放按钮', (tester) async {
      final harness = _TvSceneHarness.create();
      addTearDown(harness.dispose);
      await harness.pump(tester);

      harness.player.toggleControls();
      await tester.pump();
      expect(harness.player.controlsVisible, isFalse);
      expect(harness.surfaceNode(tester, 'tv-player-play').hasFocus, isFalse);

      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pump();
      await tester.pump();

      expect(harness.player.playing, isFalse);
      expect(harness.player.controlsVisible, isTrue);
      expect(harness.surfaceNode(tester, 'tv-player-play').hasFocus, isTrue);
      expect(harness.backCalls, 0);
    });

    testWidgets('控制层隐藏时左右快进快退并显示短暂时间反馈，焦点不移动', (tester) async {
      final harness = _TvSceneHarness.create();
      addTearDown(harness.dispose);
      await harness.pump(tester);

      harness.fake.emitPosition(const Duration(seconds: 5));
      await tester.pump();
      harness.player.toggleControls();
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(harness.player.position, const Duration(seconds: 15));
      expect(harness.player.controlsVisible, isFalse);
      expect(harness.interaction.hudKind, PlayerHudKind.forward);
      expect(harness.interaction.hudVisible, isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(harness.player.position, const Duration(seconds: 5));
      expect(harness.interaction.hudKind, PlayerHudKind.backward);

      await tester.pump(const Duration(milliseconds: 800));
      expect(harness.interaction.hudVisible, isFalse);
      expect(harness.escapeCalls, 0);
    });

    testWidgets('控制层隐藏时上下仅显示控制层并聚焦播放，不修改音量', (tester) async {
      final harness = _TvSceneHarness.create();
      addTearDown(harness.dispose);
      await harness.pump(tester);

      harness.player.toggleControls();
      await tester.pump();
      final volumeBefore = harness.player.volume;
      final positionBefore = harness.player.position;

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      await tester.pump();

      expect(harness.player.controlsVisible, isTrue);
      expect(harness.player.volume, volumeBefore);
      expect(harness.player.position, positionBefore);
      expect(harness.surfaceNode(tester, 'tv-player-play').hasFocus, isTrue);

      harness.player.toggleControls();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.pump();
      expect(harness.player.controlsVisible, isTrue);
      expect(harness.player.volume, volumeBefore);
    });

    testWidgets('控制层可见时方向键只移动焦点，不触发整页 seek 与音量', (tester) async {
      final harness = _TvSceneHarness.create();
      addTearDown(harness.dispose);
      await harness.pump(tester);

      final playNode = harness.surfaceNode(tester, 'tv-player-play');
      expect(playNode.hasFocus, isTrue);
      final volumeBefore = harness.player.volume;
      final positionBefore = harness.player.position;

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      expect(playNode.hasFocus, isFalse, reason: '方向键只移动焦点');
      expect(harness.player.volume, volumeBefore);
      expect(harness.player.position, positionBefore);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(harness.player.volume, volumeBefore);
      expect(harness.player.position, positionBefore);
    });

    testWidgets('进度条聚焦时左右按 ±10 秒定位，确认键切换播放', (tester) async {
      final harness = _TvSceneHarness.create();
      addTearDown(harness.dispose);
      await harness.pump(tester);

      harness.fake.emitPosition(const Duration(seconds: 30));
      await tester.pump();

      final timelineNode = harness.surfaceNode(tester, 'tv-player-timeline');
      timelineNode.requestFocus();
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(harness.fake.seeks.last, const Duration(seconds: 40));
      expect(harness.player.scrubbing, isFalse, reason: '不进入拖动预览');

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(harness.fake.seeks.last, const Duration(seconds: 30));

      // 进度条聚焦时确认键切换播放：一次按键一次动作。
      final playCountBefore = harness.fake.playCount;
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pump();
      expect(harness.player.playing, isFalse);
      expect(harness.fake.playCount, playCountBefore);
      expect(
        harness.fake.commands.where((command) => command == 'pause').length,
        1,
      );
    });

    testWidgets('一次确认只触发一次动作：keyUp 与连按不重复执行', (tester) async {
      final harness = _TvSceneHarness.create();
      addTearDown(harness.dispose);
      await harness.pump(tester);

      // 隐藏控制层后确认键：keyDown 触发一次，keyUp 不再触发。
      harness.player.toggleControls();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(
        harness.fake.commands.where((command) => command == 'pause').length,
        1,
      );

      // 可见控制层且播放按钮聚焦：再次确认只切换一次。
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pump();
      expect(harness.player.playing, isTrue);
      expect(harness.fake.playCount, 2, reason: '初始化起播 + 明确播放各一次');
    });

    testWidgets('媒体键：mediaPause 幂等、mediaPlay 仅未播放时启动', (tester) async {
      final harness = _TvSceneHarness.create();
      addTearDown(harness.dispose);
      await harness.pump(tester);

      harness.fake.emitPosition(const Duration(seconds: 10));
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.mediaPause);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.mediaPause);
      await tester.pump();
      expect(harness.player.playing, isFalse);
      expect(harness.repository.progressUpdates, 1, reason: '幂等暂停只保存一次');

      // 暂停后 mediaPlay 启动播放；已在播放时 mediaPlay 不重复启动。
      await tester.sendKeyEvent(LogicalKeyboardKey.mediaPlay);
      await tester.pump();
      expect(harness.player.playing, isTrue);
      expect(harness.fake.playCount, 2, reason: '初始化起播 + mediaPlay 各一次');

      await tester.sendKeyEvent(LogicalKeyboardKey.mediaPlay);
      await tester.pump();
      expect(harness.fake.playCount, 2, reason: '播放中 mediaPlay 是空操作');

      // mediaPlayPause 在播放/暂停间切换。
      await tester.sendKeyEvent(LogicalKeyboardKey.mediaPlayPause);
      await tester.pump();
      expect(harness.player.playing, isFalse);

      await tester.sendKeyEvent(LogicalKeyboardKey.mediaPlayPause);
      await tester.pump();
      expect(harness.player.playing, isTrue);
    });

    testWidgets('Space 在可见控制层切换播放，确认键长按不重复激活', (tester) async {
      final harness = _TvSceneHarness.create();
      addTearDown(harness.dispose);
      await harness.pump(tester);
      harness.surfaceNode(tester, 'tv-player-speed').requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(harness.player.playing, isFalse);
      expect(find.text('播放速度'), findsNothing);
      harness.surfaceNode(tester, 'tv-player-play').requestFocus();
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(harness.player.playing, isTrue);
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(harness.player.playing, isTrue);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
    });

    testWidgets('媒体快进快退键按 ±10 秒定位', (tester) async {
      final harness = _TvSceneHarness.create();
      addTearDown(harness.dispose);
      await harness.pump(tester);

      harness.fake.emitPosition(const Duration(seconds: 20));
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.mediaFastForward);
      await tester.pump();
      expect(harness.fake.seeks.last, const Duration(seconds: 30));

      await tester.sendKeyEvent(LogicalKeyboardKey.mediaRewind);
      await tester.pump();
      expect(harness.fake.seeks.last, const Duration(seconds: 20));
    });

    testWidgets('速度弹窗：选择后回写速度并把焦点还给速度按钮', (tester) async {
      final harness = _TvSceneHarness.create();
      addTearDown(harness.dispose);
      await harness.pump(tester);

      final speedNode = harness.surfaceNode(tester, 'tv-player-speed');
      speedNode.requestFocus();
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('播放速度'), findsOneWidget);

      await tester.tap(find.text('1.5x'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(harness.player.speed, 1.5);
      expect(find.text('播放速度'), findsNothing);
      expect(speedNode.hasFocus, isTrue, reason: '弹窗关闭后焦点回到速度按钮');
      expect(harness.player.controlsVisible, isTrue);
    });

    testWidgets('速度弹窗：取消与 Escape 返回保持原速度并恢复焦点', (tester) async {
      final harness = _TvSceneHarness.create();
      addTearDown(harness.dispose);
      await harness.pump(tester);
      await harness.player.pause();
      await tester.pump();

      final speedNode = harness.surfaceNode(tester, 'tv-player-speed');
      speedNode.requestFocus();
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('播放速度'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('播放速度'), findsNothing);
      expect(harness.player.speed, 1.0);
      expect(speedNode.hasFocus, isTrue);
      expect(harness.player.controlsVisible, isTrue);
      await tester.pump(const Duration(seconds: 5));
      expect(harness.player.controlsVisible, isTrue);
      expect(speedNode.hasFocus, isTrue);
    });

    testWidgets('持续方向导航延长控制层显示，停止操作后才自动隐藏', (tester) async {
      final harness = _TvSceneHarness.create();
      addTearDown(harness.dispose);
      await harness.pump(tester);
      await tester.pump(const Duration(seconds: 3));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump(const Duration(seconds: 2));
      expect(harness.player.controlsVisible, isTrue);
      await tester.pump(const Duration(seconds: 3));
      expect(harness.player.controlsVisible, isFalse);
    });

    testWidgets('Back/Escape 分层：可见时先隐藏控制层，隐藏时才请求关闭', (tester) async {
      final harness = _TvSceneHarness.create();
      addTearDown(harness.dispose);
      // 复刻页面 _handleTvBack 的分层判定：可见（非错误态）先隐藏控制层，
      // 已隐藏或错误态才结束播放；场景把 Escape 交给该判定，不自行关闭。
      final scene = PlayerScene(
        controller: harness.player,
        interaction: harness.interaction,
        onBack: () => harness.backCalls++,
        onMinimize: null,
        onRotate: null,
        isTelevision: true,
        onEscape: () {
          harness.escapeCalls++;
          if (harness.player.controlsVisible && harness.player.error == null) {
            harness.player.toggleControls();
          } else {
            harness.backCalls++;
          }
        },
      );
      await harness.pumpScene(tester, scene);
      expect(harness.player.controlsVisible, isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(harness.escapeCalls, 1);
      expect(harness.player.controlsVisible, isFalse);
      expect(harness.backCalls, 0);

      // 控制层已隐藏：再次 Escape 才请求关闭播放。
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(harness.escapeCalls, 2);
      expect(harness.backCalls, 1);
    });
  });
}

class _TvSceneHarness {
  _TvSceneHarness._(this.repository, this.media, this.player, this.fakes);

  final _CountingRepository repository;
  final MediaController media;
  final PlayerController player;
  final List<_FakePlatformPlayer> fakes;
  var backCalls = 0;
  var escapeCalls = 0;

  late final PlayerInteractionController interaction =
      PlayerInteractionController(
        player: player,
        deviceControls: _NoopDeviceControls(),
      );

  _FakePlatformPlayer get fake => fakes.last;

  static _TvSceneHarness create() {
    final repository = _CountingRepository();
    final media = MediaController(repository);
    final item = buildMediaFixtures()
        .firstWhere((item) => item.type == MediaType.video)
        .copyWith(streamUrl: 'http://127.0.0.1:19876/api/v1/media/v/stream');
    media.remember(item, notify: false);
    final fakes = <_FakePlatformPlayer>[];
    final player = PlayerController(
      item: item,
      media: media,
      apiSession: ApiSession(),
      debugPlatformPlayerFactory: (configuration) {
        final fake = _FakePlatformPlayer(configuration: configuration);
        fakes.add(fake);
        return fake;
      },
      debugVideoControllerFactory: (_) => null,
    );
    return _TvSceneHarness._(repository, media, player, fakes);
  }

  Future<void> pump(WidgetTester tester) => pumpScene(
    tester,
    PlayerScene(
      controller: player,
      interaction: interaction,
      onBack: () => backCalls++,
      onMinimize: null,
      onRotate: null,
      isTelevision: true,
      onEscape: () => escapeCalls++,
    ),
  );

  Future<void> pumpScene(WidgetTester tester, Widget scene) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 720);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    player.start();
    await tester.pumpWidget(
      MaterialApp(
        theme: LumaTheme.dark(),
        home: _TvHarnessLifetime(
          onDispose: dispose,
          child: Scaffold(body: scene),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(player.initialized, isTrue);
  }

  /// 从按钮真实子树读取 Focus，兼容 InkWell 自己创建的焦点节点。
  FocusNode surfaceNode(WidgetTester tester, String key) {
    final surface = tester.widget<InkWell>(
      find.descendant(
        of: find.byKey(ValueKey<String>(key)),
        matching: find.byType(InkWell),
      ),
    );
    return Focus.of(tester.element(find.byWidget(surface.child!).first));
  }

  bool _disposed = false;

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    interaction.dispose();
    player.dispose();
    media.dispose();
  }
}

// 在 widget 测试检查计时器前释放外部持有的播放会话。
class _TvHarnessLifetime extends StatefulWidget {
  const _TvHarnessLifetime({required this.onDispose, required this.child});

  final VoidCallback onDispose;
  final Widget child;

  @override
  State<_TvHarnessLifetime> createState() => _TvHarnessLifetimeState();
}

class _TvHarnessLifetimeState extends State<_TvHarnessLifetime> {
  @override
  void dispose() {
    widget.onDispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _TvControllerHarness {
  _TvControllerHarness._(this.repository, this.media, this.player, this.fakes);

  final _CountingRepository repository;
  final MediaController media;
  final PlayerController player;
  final List<_FakePlatformPlayer> fakes;

  _FakePlatformPlayer get fake => fakes.last;

  static _TvControllerHarness create({
    Completer<void>? openGate,
    Object? openError,
    Completer<void>? playGate,
  }) {
    final repository = _CountingRepository();
    final media = MediaController(repository);
    final item = buildMediaFixtures()
        .firstWhere((item) => item.type == MediaType.video)
        .copyWith(streamUrl: 'http://127.0.0.1:19877/api/v1/media/v/stream');
    media.remember(item, notify: false);
    final fakes = <_FakePlatformPlayer>[];
    final player = PlayerController(
      item: item,
      media: media,
      apiSession: ApiSession(),
      debugPlatformPlayerFactory: (configuration) {
        final fake = _FakePlatformPlayer(configuration: configuration);
        if (fakes.isEmpty) {
          fake.openGate = openGate;
          fake.openError = openError;
          fake.playGate = playGate;
        }
        fakes.add(fake);
        return fake;
      },
      debugVideoControllerFactory: (_) => null,
    );
    return _TvControllerHarness._(repository, media, player, fakes);
  }

  Future<void> start() async {
    player.start();
    await pumpEventQueue();
    expect(player.initialized, isTrue);
  }

  void dispose() {
    player.dispose();
    media.dispose();
  }
}

class _CountingRepository extends MockMediaRepository {
  var progressUpdates = 0;

  @override
  Future<MediaItem> updateProgress(String id, int positionMs) async {
    progressUpdates++;
    return super.updateProgress(id, positionMs);
  }
}

class _ThrowingProgressRepository extends MockMediaRepository {
  @override
  Future<MediaItem> updateProgress(String id, int positionMs) async {
    throw Exception('离线保存失败');
  }
}

class _NoopDeviceControls implements PlayerDeviceControls {
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

/// 假的平台播放器：记录命令与定位请求，支持阻塞 open/play/seek 验证生命周期竞态。
class _FakePlatformPlayer extends PlatformPlayer {
  _FakePlatformPlayer({required super.configuration});

  final List<Duration> seeks = [];
  final List<String> commands = [];
  final List<Completer<void>> _gates = [];
  Completer<void>? openGate;
  Completer<void>? playGate;
  Object? openError;
  Object? seekError;
  int playCount = 0;
  bool disposed = false;

  bool nativeSeeking = false;
  Duration nativePosition = Duration.zero;

  Completer<void> holdSeek() {
    final gate = Completer<void>();
    _gates.add(gate);
    return gate;
  }

  @override
  Future<void> open(Playable playable, {bool play = true}) async {
    commands.add('open');
    state = state.copyWith(duration: const Duration(minutes: 10));
    final gate = openGate;
    if (gate != null) await gate.future;
    final error = openError;
    if (error != null) throw error;
    if (play) await this.play();
  }

  @override
  Future<void> play() async {
    commands.add('play');
    playCount++;
    final gate = playGate;
    if (gate != null) await gate.future;
    state = state.copyWith(playing: true);
    playingController.add(true);
  }

  @override
  Future<void> pause() async {
    commands.add('pause');
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

  @override
  Future<void> dispose() async {
    disposed = true;
    await super.dispose();
  }

  void emitPosition(Duration value) {
    nativePosition = value;
    state = state.copyWith(position: value);
    positionController.add(value);
  }
}
