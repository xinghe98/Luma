// 覆盖应用级播放会话在全屏和小窗之间复用播放器、关闭时释放会话的行为。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/app/controllers/media_controller.dart';
import 'package:luma/core/theme.dart';
import 'package:luma/data/api/api_session.dart';
import 'package:luma/data/fixtures/media_fixtures.dart';
import 'package:luma/data/mock/mock_media_repository.dart';
import 'package:luma/data/models/media_types.dart';
import 'package:luma/features/player/player_session_controller.dart';
import 'package:luma/features/player/widgets/mini_player_overlay.dart';

void main() {
  test('同一媒体在全屏和小窗间复用播放控制器', () async {
    final media = MediaController(MockMediaRepository());
    final session = PlayerSessionController(
      media: media,
      apiSession: ApiSession(),
    );
    addTearDown(() {
      session.dispose();
      media.dispose();
    });
    final item = buildMediaFixtures().firstWhere(
      (item) => item.type == MediaType.video,
    );

    session.start(item);
    final player = session.player;
    session.minimize();

    expect(session.minimized, isTrue);
    session.start(item);

    expect(session.player, same(player));
    expect(session.minimized, isFalse);

    session.minimize();
    await session.close();

    expect(session.player, isNull);
    expect(session.minimized, isFalse);
  });

  test('同一媒体选择从头播放会重置现有会话位置', () {
    final media = MediaController(MockMediaRepository());
    final session = PlayerSessionController(
      media: media,
      apiSession: ApiSession(),
    );
    addTearDown(() {
      session.dispose();
      media.dispose();
    });
    final item = buildMediaFixtures().firstWhere(
      (item) => item.type == MediaType.video && item.progress > 0,
    );

    session.start(item);
    expect(session.player!.position, greaterThan(Duration.zero));
    session.start(item, startFromBeginning: true);

    expect(session.player!.position, Duration.zero);
  });

  testWidgets('关闭小窗会结束会话并移除悬浮层', (tester) async {
    final media = MediaController(MockMediaRepository());
    final session = PlayerSessionController(
      media: media,
      apiSession: ApiSession(),
    );
    addTearDown(() {
      session.dispose();
      media.dispose();
    });
    final item = buildMediaFixtures().firstWhere(
      (item) => item.type == MediaType.video,
    );
    session.start(item);
    session.minimize();

    await tester.pumpWidget(
      MaterialApp(
        theme: LumaTheme.light(),
        darkTheme: LumaTheme.dark(),
        home: Scaffold(
          body: Stack(
            children: [MiniPlayerOverlay(session: session, onExpand: (_) {})],
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.close_rounded), findsOneWidget);
    expect(find.bySemanticsLabel('关闭小窗播放器'), findsOneWidget);
    expect(find.bySemanticsLabel('播放'), findsOneWidget);
    expect(find.bySemanticsLabel('快退 10 秒'), findsOneWidget);
    expect(find.bySemanticsLabel('快进 10 秒'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pump();

    expect(session.player, isNull);
    expect(find.byIcon(Icons.close_rounded), findsNothing);
  });

  testWidgets('双指缩放会放大小窗', (tester) async {
    final media = MediaController(MockMediaRepository());
    final session = PlayerSessionController(
      media: media,
      apiSession: ApiSession(),
    );
    addTearDown(() {
      session.dispose();
      media.dispose();
    });
    session
      ..start(
        buildMediaFixtures().firstWhere((item) => item.type == MediaType.video),
      )
      ..minimize();
    await tester.pumpWidget(
      MaterialApp(
        theme: LumaTheme.light(),
        home: Scaffold(
          body: Stack(
            children: [MiniPlayerOverlay(session: session, onExpand: (_) {})],
          ),
        ),
      ),
    );

    final card = find.byKey(const ValueKey('mini-player-card'));
    final before = tester.getSize(card);
    final center = tester.getCenter(card);
    final first = await tester.startGesture(center - const Offset(20, 0));
    final second = await tester.startGesture(center + const Offset(20, 0));
    await first.moveTo(center - const Offset(70, 0));
    await second.moveTo(center + const Offset(70, 0));
    await tester.pump();
    await first.up();
    await second.up();
    await tester.pump(const Duration(milliseconds: 100));

    expect(tester.getSize(card).width, greaterThan(before.width));
    await session.close();
  });

  testWidgets('小窗三区双击会快退、切换播放和快进', (tester) async {
    final media = MediaController(MockMediaRepository());
    final session = PlayerSessionController(
      media: media,
      apiSession: ApiSession(),
    );
    addTearDown(() {
      session.dispose();
      media.dispose();
    });
    session
      ..start(
        buildMediaFixtures().firstWhere((item) => item.type == MediaType.video),
      )
      ..minimize();
    await tester.pumpWidget(
      MaterialApp(
        theme: LumaTheme.light(),
        home: Scaffold(
          body: Stack(
            children: [MiniPlayerOverlay(session: session, onExpand: (_) {})],
          ),
        ),
      ),
    );

    final card = find.byKey(const ValueKey('mini-player-card'));
    final rect = tester.getRect(card);
    final player = session.player!;
    player.seekBy(30);
    final initial = player.position;

    await tester.tapAt(Offset(rect.left + rect.width / 6, rect.center.dy));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(Offset(rect.left + rect.width / 6, rect.center.dy));
    await tester.pump();
    expect(player.position, initial - const Duration(seconds: 10));
    expect(find.text('快退 10 秒'), findsOneWidget);

    final wasPlaying = player.playing;
    await tester.tapAt(rect.center);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(rect.center);
    await tester.pump();
    expect(player.playing, isNot(wasPlaying));

    final beforeForward = player.position;
    await tester.tapAt(Offset(rect.right - rect.width / 6, rect.center.dy));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(Offset(rect.right - rect.width / 6, rect.center.dy));
    await tester.pump();
    expect(player.position, beforeForward + const Duration(seconds: 10));
    expect(find.text('快进 10 秒'), findsOneWidget);

    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.text('快进 10 秒'), findsNothing);
    await session.close();
  });
}
