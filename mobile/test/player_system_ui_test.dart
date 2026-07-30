// 覆盖相邻播放器页面切换时系统 UI 异步操作的 generation 隔离。
// 测试通过平台通道阻塞旧 exit，确认它不会覆盖新会话的沉浸模式。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/features/player/player_system_ui.dart';

void main() {
  test('Windows 全屏由播放器原生宿主进入并在退出会话时恢复', () async {
    final events = <String>[];
    final session = PlayerSystemUiSession(
      desktop: true,
      enterDesktopFullScreen: () async => events.add('enter-native'),
      exitDesktopFullScreen: () async => events.add('exit-native'),
    );

    await session.enter(
      portraitVideo: false,
      entryOrientation: Orientation.landscape,
      shortestSide: 640,
    );
    expect(session.fullScreen, isFalse);

    expect(await session.toggleFullScreen(), isTrue);
    expect(session.fullScreen, isTrue);
    expect(events, ['enter-native']);

    expect(await session.exitFullScreen(), isTrue);
    expect(session.fullScreen, isFalse);
    expect(events, ['enter-native', 'exit-native']);

    await session.toggleFullScreen();
    await session.exit();
    expect(session.fullScreen, isFalse);
    expect(events, [
      'enter-native',
      'exit-native',
      'enter-native',
      'exit-native',
    ]);
  });

  testWidgets('a stale exit cannot override a newer player enter', (
    tester,
  ) async {
    final calls = <MethodCall>[];
    Completer<Object?>? blockedOrientation;
    var blockNextOrientation = false;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) {
        calls.add(call);
        if (call.method == 'SystemChrome.setPreferredOrientations' &&
            blockNextOrientation) {
          blockNextOrientation = false;
          blockedOrientation = Completer<Object?>();
          return blockedOrientation!.future;
        }
        return Future<Object?>.value();
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    final oldSession = PlayerSystemUiSession();
    await oldSession.enter(
      portraitVideo: true,
      entryOrientation: Orientation.portrait,
      shortestSide: 400,
    );

    blockNextOrientation = true;
    final staleExit = oldSession.exit();
    await tester.pump();
    expect(blockedOrientation, isNotNull);

    final newSession = PlayerSystemUiSession();
    await newSession.enter(
      portraitVideo: false,
      entryOrientation: Orientation.portrait,
      shortestSide: 400,
    );
    blockedOrientation!.complete();
    await staleExit;

    final modeCalls = calls
        .where((call) => call.method == 'SystemChrome.setEnabledSystemUIMode')
        .toList();
    expect(modeCalls.last.arguments.toString(), contains('immersiveSticky'));

    final cleanup = newSession.exit();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));
    await cleanup;
  });

  testWidgets(
    'platform failures do not escape system UI enter rotate or exit',
    (tester) async {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (_) => throw PlatformException(code: 'unavailable'),
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      final session = PlayerSystemUiSession();

      await session.enter(
        portraitVideo: true,
        entryOrientation: Orientation.portrait,
        shortestSide: 400,
      );
      await session.rotate();
      final exit = session.exit();
      await tester.pump(const Duration(milliseconds: 320));

      await expectLater(exit, completes);
    },
  );
}
