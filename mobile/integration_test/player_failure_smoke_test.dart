// 隔离验证真实 libmpv 的失败提示与重试；只使用内存凭据、本机 HTTP 和测试视频。
// 复用生产中继、播放器与错误区域，结束时卸下视频纹理并释放会话和监听端口。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:luma/app/controllers/media_controller.dart';
import 'package:luma/core/theme.dart';
import 'package:luma/data/api/api_session.dart';
import 'package:luma/data/fixtures/media_fixtures.dart';
import 'package:luma/data/mock/mock_media_repository.dart';
import 'package:luma/data/models/media_types.dart';
import 'package:luma/data/proxy/loopback_media_relay.dart';
import 'package:luma/features/player/player_controller.dart';
import 'package:luma/features/player/player_device_controls.dart';
import 'package:luma/features/player/player_interaction_controller.dart';
import 'package:luma/features/player/widgets/player_scene.dart';
import 'package:media_kit/media_kit.dart';

import 'fixtures/tv_smoke_clip.dart';
import 'support/tv_smoke_server.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('真实播放器显示上游拒绝原因，重试后正常播放', (tester) async {
    MediaKit.ensureInitialized();
    final server = TvSmokeServer(videoBytes: tvSmokeClipBytes, imageCount: 0);
    final session = ApiSession();
    final relay = LoopbackMediaRelay(
      createHttpClient: () => HttpClient()..findProxy = (_) => 'DIRECT',
      authorizationHeadersFor: session.authorizationHeadersFor,
    );
    final media = MediaController(MockMediaRepository());
    final item = buildMediaFixtures()
        .firstWhere((item) => item.type == MediaType.video)
        .copyWith(progress: 0, streamUrl: tvSmokeStreamPath('failure-smoke'));
    final player = PlayerController(
      item: item,
      media: media,
      apiSession: session,
      mediaRequestRouter: relay,
    );
    final interaction = PlayerInteractionController(
      player: player,
      deviceControls: const MethodChannelPlayerDeviceControls(),
    );
    try {
      await server.start();
      await relay.start();
      session.update(origin: server.origin, token: 'invalid-isolated-token');
      await tester.pumpWidget(
        MaterialApp(
          theme: LumaTheme.dark(),
          home: Scaffold(
            body: PlayerScene(
              controller: player,
              interaction: interaction,
              isTelevision: true,
              onBack: () {},
              onRotate: null,
            ),
          ),
        ),
      );
      player.start();
      await _pumpUntil(
        tester,
        () => player.error?.contains('HTTP 401') ?? false,
        reason: '上游拒绝未出现在播放器错误中：${player.error}',
      );
      expect(server.authFailures, greaterThan(0));
      expect(player.error, isNot(contains('/media/')));
      expect(player.error, isNot(contains('invalid-isolated-token')));
      expect(find.text(player.error!), findsOneWidget);
      expect(find.text('重试播放'), findsOneWidget);
      expect(tester.takeException(), isNull);
      debugPrint('NATIVE_FAILURE_DIAGNOSTIC: ${player.error}');

      // 更新的是隔离会话，不读取设备原有凭据；重试必须创建新的播放路由。
      session.update(origin: server.origin, token: kTvSmokeToken);
      await tester.tap(find.text('重试播放'));
      await _pumpUntil(
        tester,
        () => player.position > const Duration(seconds: 1),
        reason: '重试未恢复播放',
      );
      expect(player.error, isNull);
      expect(player.playing, isTrue);
      expect(server.rangeRequests, greaterThan(0));
      expect(find.text('重试播放'), findsNothing);
      expect(tester.takeException(), isNull);
      debugPrint('NATIVE_RETRY_OK: position=${player.position}');
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      interaction.dispose();
      await player.shutdown();
      await relay.close();
      await server.close();
      media.dispose();
    }
  });
}

/// 等待原生事件并推进真实界面；超时给出对应阶段，不访问外部服务。
Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  required String reason,
}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 30));
  while (!condition() && DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(condition(), isTrue, reason: reason);
  await tester.pump();
}
