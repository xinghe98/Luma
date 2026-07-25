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

    expect(tester.getSize(card).width, greaterThan(before.width));
    await session.close();
  });
}
