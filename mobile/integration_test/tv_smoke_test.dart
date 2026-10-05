// TV 真机冒烟测试：在注入的内存依赖上驱动「连接→浏览→搜索→详情→播放→返回→
// 图片→设置」完整链路。原生链路全部真实——media_kit/libmpv 解码、真实
// ApiSession、真实 LoopbackMediaRelay、本地 loopback HTTP 服务器（固定
// tv-smoke-token 鉴权、GET/HEAD、单段 Range 206、越界 416）。
// 不调用 AppDependencies.create/production、不恢复真实凭据、不注入假播放器；
// 测试 finally 中按「播放会话 → 依赖容器 → 测试服务器」顺序释放，不残留音频。
// 截图在支持的平台（Android integration_test 插件）落盘到
// TV_SMOKE_SCREENSHOT_DIR（默认系统临时目录）；Android 收尾断言视频像素可见。
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:luma/app/app_dependencies.dart';
import 'package:luma/app/app_device_profile.dart';
import 'package:luma/data/api/api_session.dart';
import 'package:luma/data/proxy/loopback_media_relay.dart';
import 'package:luma/features/catalog/catalog_detail_page.dart';
import 'package:luma/features/catalog/catalog_page.dart';
import 'package:luma/features/catalog/widgets/catalog_card.dart';
import 'package:luma/features/details/media_detail_page.dart';
import 'package:luma/features/library/library_page.dart';
import 'package:luma/features/search/search_page.dart';
import 'package:luma/main.dart';
import 'package:luma/shared/layout/section_header.dart';
import 'package:luma/shared/media/media_card.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'fixtures/tv_smoke_clip.dart';
import 'support/tv_smoke_repositories.dart';
import 'support/tv_smoke_server.dart';

/// 退出播放后等待进度落库/解码器收尾、并验证无新增拉流的时间窗。
const _teardownGrace = Duration(seconds: 4);

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('TV 冒烟：连接→浏览→搜索→详情→播放→返回→图片→设置', (tester) async {
    MediaKit.ensureInitialized();

    final apiSession = ApiSession();
    final server = TvSmokeServer(videoBytes: tvSmokeClipBytes, imageCount: 20);
    final mediaRepo = TvSmokeMediaRepository();
    final catalogRepo = TvSmokeCatalogRepository();
    final relay = LoopbackMediaRelay(
      createHttpClient: () => HttpClient(),
      authorizationHeadersFor: apiSession.authorizationHeadersFor,
    );
    final dependencies = AppDependencies(
      mediaRepository: mediaRepo,
      connectionService: TvSmokeConnectionService(apiSession),
      deviceProfile: AppDeviceProfile.television,
      apiSession: apiSession,
      catalogRepository: catalogRepo,
      mediaRelay: relay,
    );

    try {
      // integration binding 默认不注册测试 IME；enterText/receiveAction 需要它。
      if (!tester.testTextInput.isRegistered) {
        tester.testTextInput.register();
        addTearDown(tester.testTextInput.unregister);
      }
      await server.start();
      await dependencies.initialize();
      expect(dependencies.deviceProfile.isTelevision, isTrue);
      // 未提供凭据存储：会话恢复必须是无操作，不得触碰真实凭据。
      expect(await dependencies.restoreSession(), isFalse);

      await tester.pumpWidget(LumaApp(dependencies: dependencies));
      // 开屏品牌遮罩最短展示 1 秒，收起后才授予内容初始焦点。
      await tester.pump(const Duration(milliseconds: 1100));
      await tester.pump();

      // ── 连接 ──────────────────────────────────────────────────────────
      // 未连接时路由重定向到 /connect；TV 字段外层闸门持浏览焦点。
      expect(find.text('IP 地址'), findsOneWidget);
      expect(_focusDebugLabel(), 'tv-field-gate');
      // OK 进入编辑：弹出（测试）IME，字段获得焦点。
      await _press(tester, LogicalKeyboardKey.select);
      final fields = find.byType(TextField);
      expect(fields.evaluate().length, 4);
      // 地址字段输入后经 Next 链显式推进，与 TV 焦点契约一致。
      await tester.enterText(fields.first, '127.0.0.1');
      await _submitIme(tester, TextInputAction.next);
      expect(_focusDebugLabel(), 'connection-field-port');
      await tester.enterText(fields.at(1), '${server.port}');
      await _submitIme(tester, TextInputAction.next);
      expect(_focusDebugLabel(), 'connection-field-username');
      await tester.enterText(fields.at(2), 'smoke-user');
      await _submitIme(tester, TextInputAction.next);
      expect(_focusDebugLabel(), 'connection-field-password');
      await tester.enterText(fields.at(3), 'smoke-pass');
      // 密码 Done 调既有提交链路。
      await _submitIme(tester, TextInputAction.done);
      await tester.pump();
      // 登录成功 → 会话写入 loopback origin 与固定 token → 重定向回首页。
      await _pumpUntil(
        tester,
        () =>
            dependencies.session.isConnected &&
            find.text('继续观看').evaluate().isNotEmpty,
        timeout: const Duration(seconds: 15),
        reason: '登录后未进入首页',
      );
      expect(apiSession.token, kTvSmokeToken);
      expect(apiSession.origin, server.origin);
      expect(dependencies.session.server!.address, server.origin);

      // ── 浏览 ──────────────────────────────────────────────────────────
      // 60 项媒体已加载；首页货架呈现继续观看与最近添加内容。
      expect(dependencies.media.items.length, 60);
      expect(find.text('夜行快车 0'), findsWidgets);
      // 登录后壳层首次挂载：内容被 ExcludeFocus，选中分支的导航项 autofocus
      // 必然获焦；此时绝不能发 Back（首页导航 Back 是退出系统）。
      expect(_focusDebugLabel(), 'tv-nav-home');
      // 向右进入首页内容，验证 TV 可见刷新按钮走既有媒体刷新。
      await _press(tester, LogicalKeyboardKey.arrowRight);
      final refresh = find.byTooltip('刷新媒体库');
      expect(refresh, findsOneWidget);
      final refreshCallsBefore = mediaRepo.refreshCalls;
      await tester.tap(refresh);
      await _pumpUntil(
        tester,
        () => mediaRepo.refreshCalls > refreshCallsBefore,
        reason: 'TV 首页刷新按钮未触发媒体刷新',
      );
      await _pumpUntil(
        tester,
        () => tester
            .widgetList<RawImage>(
              find.descendant(
                of: find.byType(MediaCard),
                matching: find.byType(RawImage),
              ),
            )
            .any(
              (image) => image.image?.width == 96 && image.image?.height == 64,
            ),
        reason: '首页媒体缩略图必须完成真实解码',
      );
      await _captureScreenshot(tester, binding, 'tv-home');
      expect(server.imageRequests, greaterThan(0), reason: '缩略图应经认证通道加载');
      expect(server.authFailures, 0, reason: '所有请求必须携带测试 token');

      // 影视库分支：CatalogStore 经内存作品仓储渲染电影货架。
      // 内容 Back 回导航，再下移两项切分支；分支 OK 后焦点仍在导航项上，
      // 因此切搜索分支时直接下移，不能再发 Back（会被判为「非首页回首页」）。
      await _popBack(tester);
      expect(_focusDebugLabel(), 'tv-nav-home');
      await _press(tester, LogicalKeyboardKey.arrowDown);
      await _press(tester, LogicalKeyboardKey.arrowDown);
      expect(_focusDebugLabel(), 'tv-nav-videos');
      await _press(tester, LogicalKeyboardKey.select);
      await _pumpUntil(
        tester,
        () => find.text('午夜影院 0').evaluate().isNotEmpty,
        timeout: const Duration(seconds: 10),
        reason: '影视库货架未加载作品数据',
      );
      expect(_focusDebugLabel(), 'tv-nav-videos');

      // 三类“查看全部”打开新路由后，不手动指定焦点，直接用遥控器操作。
      await _press(tester, LogicalKeyboardKey.arrowRight);
      for (final sectionTitle in ['电影', '电视剧', '个人视频']) {
        final section = find.byWidgetPredicate(
          (widget) => widget is SectionHeader && widget.title == sectionTitle,
        );
        final catalogScroll = find
            .descendant(
              of: find.byType(CatalogPage),
              matching: find.byWidgetPredicate(
                (widget) =>
                    widget is Scrollable &&
                    widget.axisDirection == AxisDirection.down,
              ),
            )
            .first;
        await tester.scrollUntilVisible(
          section,
          240,
          scrollable: catalogScroll,
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.descendant(of: section, matching: find.text('查看全部')),
        );
        await tester.pumpAndSettle();
        final collection = sectionTitle == '个人视频'
            ? find.byType(LibraryPage)
            : find.byType(CatalogCollectionPage);
        expect(collection, findsOneWidget);
        expect(
          FocusManager.instance.primaryFocus,
          isNot(isA<FocusScopeNode>()),
        );
        for (
          var step = 0;
          step < 8 && _focusedCollectionItemId() == null;
          step++
        ) {
          await _press(tester, LogicalKeyboardKey.arrowDown);
        }
        final initialId = _focusedCollectionItemId();
        expect(initialId, isNotNull, reason: '$sectionTitle 列表必须能用方向键进入卡片');
        await _press(tester, LogicalKeyboardKey.arrowRight);
        expect(_focusedCollectionItemId(), isNot(initialId));
        expect(_focusedCollectionItemId(), isNotNull);
        await _captureScreenshot(
          tester,
          binding,
          'tv-collection-${sectionTitle == '电影'
              ? 'movies'
              : sectionTitle == '电视剧'
              ? 'series'
              : 'personal'}',
        );
        await _press(tester, LogicalKeyboardKey.select);
        await _pumpUntil(
          tester,
          () => sectionTitle == '个人视频'
              ? find.byType(MediaDetailPage).evaluate().isNotEmpty
              : find.byType(CatalogDetailPage).evaluate().isNotEmpty,
          reason: '$sectionTitle 列表确认键必须打开详情',
        );
        await tester.pumpAndSettle();
        if (sectionTitle == '电影') {
          await _captureScreenshot(tester, binding, 'tv-catalog-detail');
          await tester.tap(find.byTooltip('返回'));
        } else if (sectionTitle == '电视剧') {
          await _press(tester, LogicalKeyboardKey.escape);
        } else {
          await _popBack(tester);
        }
        await tester.pumpAndSettle();
        expect(collection, findsOneWidget, reason: '详情返回必须保留原来的分类列表');
        expect(_focusedCollectionItemId(), isNotNull, reason: '返回后应能继续操作列表');
        await _press(tester, LogicalKeyboardKey.arrowLeft);
        expect(_focusedCollectionItemId(), initialId);
        await _popBack(tester);
        await tester.pumpAndSettle();
        expect(find.byType(CatalogPage), findsOneWidget, reason: '分类列表返回影视库');
      }
      await _popBack(tester);
      await tester.pumpAndSettle();
      expect(_focusDebugLabel(), 'tv-nav-videos');

      // ── 搜索 ──────────────────────────────────────────────────────────
      await _press(tester, LogicalKeyboardKey.arrowDown);
      expect(_focusDebugLabel(), 'tv-nav-search');
      await _press(tester, LogicalKeyboardKey.select);
      await _pumpUntil(
        tester,
        () => find.byType(SearchPage).evaluate().isNotEmpty,
        reason: '搜索分支未打开',
      );
      await _press(tester, LogicalKeyboardKey.arrowRight);
      // TV 不自动弹 IME：直接对输入框注入文本并显式提交（等价 IME Done）。
      final searchField = find.descendant(
        of: find.byType(SearchPage),
        matching: find.byType(TextField),
      );
      await tester.enterText(searchField.first, kTvSmokeSearchTerm);
      await _submitIme(tester, TextInputAction.done);
      await _pumpUntil(
        tester,
        () => _focusDebugLabel() == 'tv-first-result',
        timeout: const Duration(seconds: 15),
        reason: '搜索提交后首个结果未获焦',
      );
      await _captureScreenshot(tester, binding, 'tv-search');
      final firstResult = find.byWidgetPredicate(
        (widget) => widget is MediaCard && widget.item.id == 'video-0',
      );
      expect(firstResult.hitTestable(), findsOneWidget);
      expect(mediaRepo.searchPageCalls, greaterThan(0));

      // ── 详情 ──────────────────────────────────────────────────────────
      // OK 激活首结果（夜行快车 0，最新加入排序首位）打开媒体详情。
      await _press(tester, LogicalKeyboardKey.select);
      await _pumpUntil(
        tester,
        () => _focusDebugLabel() == 'media-detail-play',
        timeout: const Duration(seconds: 15),
        reason: '详情页主播放按钮未获焦',
      );
      await _captureScreenshot(tester, binding, 'tv-detail');
      // 进度 0.28 → 主按钮显示继续播放。
      expect(find.text('继续播放'), findsOneWidget);

      // ── 播放 ──────────────────────────────────────────────────────────
      await _press(tester, LogicalKeyboardKey.select);
      await _pumpUntil(
        tester,
        () =>
            dependencies.playerSession.player != null &&
            (dependencies.playerSession.player!.initialized ||
                dependencies.playerSession.player!.error != null),
        timeout: const Duration(seconds: 30),
        reason: '播放器初始化超时',
      );
      final player = dependencies.playerSession.player!;
      if (player.error != null) {
        fail('播放器初始化失败：${player.error}');
      }
      expect(player.playing, isTrue, reason: '正常进入播放器应自动播放');
      expect(player.videoController, isNotNull, reason: '必须创建真实视频纹理');
      expect(find.byType(Video), findsOneWidget);
      await _pumpUntil(
        tester,
        () => server.streamRequests > 0,
        timeout: const Duration(seconds: 10),
        reason: '播放器未向测试服务器拉流',
      );
      var firstFrameRendered = false;
      final firstFrame = player.videoController!.waitUntilFirstFrameRendered
          .then((_) {
            firstFrameRendered = true;
          });
      await _pumpUntil(
        tester,
        () => firstFrameRendered,
        reason: '原生播放器必须完成首帧绘制',
      );
      await firstFrame;

      // 位置推进：真实解码下 2 秒内位置必须前进。
      final progressedAt = player.position;
      await tester.pump(const Duration(seconds: 2));
      expect(
        player.position,
        greaterThan(progressedAt + const Duration(milliseconds: 800)),
        reason: '播放位置未推进，原生解码链路可疑',
      );

      // 控制层可见：OK 逐次切换播放/暂停（焦点在播放按钮上）。
      // playing 状态由原生事件异步确认，统一用有界等待而不是同步断言。
      expect(player.controlsVisible, isTrue);
      await _press(tester, LogicalKeyboardKey.select);
      await _pumpUntil(tester, () => !player.playing, reason: 'OK 应暂停');
      await _press(tester, LogicalKeyboardKey.select);
      await _pumpUntil(tester, () => player.playing, reason: '再次 OK 应恢复播放');

      // 生命周期：后台事件暂停并保存进度，回前台保持暂停，OK 才继续。
      binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await _pumpUntil(tester, () => !player.playing, reason: '后台事件应暂停播放');
      await _pumpUntil(
        tester,
        () => mediaRepo.updateProgressCalls > 0,
        reason: '生命周期暂停应保存进度',
      );
      binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      expect(player.playing, isFalse, reason: '后台必须保持暂停');
      binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(player.playing, isFalse, reason: '回前台必须保持暂停');
      await _press(tester, LogicalKeyboardKey.select);
      await _pumpUntil(tester, () => player.playing, reason: '回前台后 OK 应恢复播放');

      // 自动隐藏：计时 4 秒后控制层消失。
      await tester.pump(const Duration(seconds: 5));
      expect(player.controlsVisible, isFalse, reason: '播放中控制层应自动隐藏');

      // 隐藏态方向键：±10 秒定位，不显示控制层、不移交焦点。
      final beforeForward = player.position;
      await _press(tester, LogicalKeyboardKey.arrowRight);
      expect(player.controlsVisible, isFalse, reason: '隐藏态 seek 不应展开控制层');
      await _pumpUntil(
        tester,
        () =>
            !player.buffering &&
            player.position >= beforeForward + const Duration(seconds: 8),
        timeout: const Duration(seconds: 5),
        reason: '快进 10 秒未落到预期位置',
      );
      final beforeRewind = player.position;
      await _press(tester, LogicalKeyboardKey.arrowLeft);
      await _pumpUntil(
        tester,
        () =>
            !player.buffering &&
            player.position <= beforeRewind - const Duration(seconds: 8),
        timeout: const Duration(seconds: 5),
        reason: '快退 10 秒未落到预期位置',
      );
      expect(player.controlsVisible, isFalse);

      // 隐藏态 OK：切换播放并显示控制层（此时为暂停）。
      await _press(tester, LogicalKeyboardKey.select);
      expect(player.controlsVisible, isTrue);
      await _pumpUntil(tester, () => !player.playing, reason: '隐藏态 OK 应暂停');
      await _captureScreenshot(tester, binding, 'tv-player-controls');
      // 定位在 HTTP 流上必然产生新的 Range 请求。
      expect(
        server.rangeRequests,
        greaterThan(0),
        reason: 'seek 应以 Range 请求拉流',
      );

      // 返回分层：第一次 Back 只隐藏控制层，第二次才退出播放器。
      await _popBack(tester);
      expect(player.controlsVisible, isFalse, reason: '第一次 Back 应隐藏控制层');
      expect(dependencies.playerSession.player, isNotNull);
      await _popBack(tester);
      await _pumpUntil(
        tester,
        () => dependencies.playerSession.player == null,
        timeout: const Duration(seconds: 10),
        reason: '第二次 Back 应退出播放器并结束会话',
      );
      await _pumpUntil(
        tester,
        () => (mediaRepo.lastProgress['video-0'] ?? 0) > 0,
        timeout: _teardownGrace,
        reason: '退出播放必须保存进度',
      );
      expect(find.text('继续播放'), findsOneWidget, reason: '应回到媒体详情');

      // 退出后：relay 路由已回收、拉流计数不再增长（解码器已释放）。
      expect(relay.registeredTargetCount, 0, reason: '播放路由 token 必须回收');
      final streamRequestsAtExit = server.streamRequests;
      await tester.pump(_teardownGrace);
      expect(
        server.streamRequests,
        streamRequestsAtExit,
        reason: '退出后解码器应释放，不再产生网络请求',
      );

      // ── 图片 ──────────────────────────────────────────────────────────
      // 从详情逐层 Back 回搜索分支导航，再切到图片库。
      await _popBack(tester);
      await _pumpUntil(
        tester,
        () =>
            find.byType(SearchPage).evaluate().isNotEmpty &&
            firstResult.hitTestable().evaluate().isNotEmpty,
        timeout: const Duration(seconds: 10),
        reason: '媒体详情未返回搜索页',
      );
      await _popBack(tester);
      expect(_focusDebugLabel(), 'tv-nav-search');
      await _press(tester, LogicalKeyboardKey.arrowUp);
      await _press(tester, LogicalKeyboardKey.arrowUp);
      expect(_focusDebugLabel(), 'tv-nav-photos');
      await _press(tester, LogicalKeyboardKey.select);
      await _pumpUntil(
        tester,
        () => find.text('相册风景 0').evaluate().isNotEmpty,
        timeout: const Duration(seconds: 10),
        reason: '图片库网格未加载',
      );
      await tester.tap(find.text('相册风景 0').first);
      await _pumpUntil(
        tester,
        () => find.byTooltip('放大').evaluate().isNotEmpty,
        timeout: const Duration(seconds: 10),
        reason: '图片预览未打开',
      );
      await _pumpUntil(
        tester,
        () => tester
            .widgetList<RawImage>(
              find.descendant(
                of: find.byType(InteractiveViewer),
                matching: find.byType(RawImage),
              ),
            )
            .any(
              (image) => image.image?.width == 96 && image.image?.height == 64,
            ),
        reason: '测试图片必须完成真实解码，不能仅显示占位',
      );
      expect(_focusDebugLabel(), 'tv-preview-toolbar');
      // 明暗两条分支各有一个 InteractiveViewer，但共用同一个变换控制器。
      final viewer = tester.widget<InteractiveViewer>(
        find.byType(InteractiveViewer).first,
      );
      double previewScale() =>
          viewer.transformationController!.value.getMaxScaleOnAxis();
      expect(previewScale(), 1.0);
      // OK 放大一级；Back 先还原再关闭。
      await _press(tester, LogicalKeyboardKey.select);
      await _pumpUntil(tester, () => previewScale() > 1.0, reason: 'OK 应触发放大');
      await _captureScreenshot(tester, binding, 'tv-preview');
      await _popBack(tester);
      await _pumpUntil(
        tester,
        () => previewScale() == 1.0,
        reason: '第一次 Back 应还原缩放',
      );
      await _popBack(tester);
      await _pumpUntil(
        tester,
        () => find.byTooltip('放大').evaluate().isEmpty,
        timeout: const Duration(seconds: 10),
        reason: '第二次 Back 应关闭预览',
      );

      // ── 设置 ──────────────────────────────────────────────────────────
      // 弹出图片详情后焦点还原到导航项（进入详情前焦点在导航上），
      // 此时直接下移切设置分支，不能再发 Back（会被判为「非首页回首页」）。
      expect(_focusDebugLabel(), 'tv-nav-photos');
      await _press(tester, LogicalKeyboardKey.arrowDown);
      await _press(tester, LogicalKeyboardKey.arrowDown);
      await _press(tester, LogicalKeyboardKey.arrowDown);
      expect(_focusDebugLabel(), 'tv-nav-settings');
      await _press(tester, LogicalKeyboardKey.select);
      await _pumpUntil(
        tester,
        () => find.text('当前服务器').evaluate().isNotEmpty,
        timeout: const Duration(seconds: 10),
        reason: '设置分支未打开',
      );
      expect(find.text('烟测服务器'), findsOneWidget);
      await _captureScreenshot(tester, binding, 'tv-settings');

      // ── 全链路收尾断言 ────────────────────────────────────────────────
      expect(server.authFailures, 0, reason: '全链路不允许出现未认证请求');
      expect(mediaRepo.updateProgressCalls, greaterThan(0));
      binding.reportData ??= <String, dynamic>{};
      binding.reportData!['tvSmoke'] = {
        'server': {
          'streamRequests': server.streamRequests,
          'rangeRequests': server.rangeRequests,
          'imageRequests': server.imageRequests,
          'authFailures': server.authFailures,
        },
        'progress': {
          'lastVideo0Ms': mediaRepo.lastProgress['video-0'],
          'updateProgressCalls': mediaRepo.updateProgressCalls,
          'searchPageCalls': mediaRepo.searchPageCalls,
          'refreshCalls': mediaRepo.refreshCalls,
        },
        'screenshotsWritten': _screenshotsWritten,
        'screenshotErrors': _screenshotErrors,
        'videoPixelsVisible': _videoPixelsVisible,
      };
      if (Platform.isAndroid) {
        expect(
          _videoPixelsVisible,
          isTrue,
          reason: '视频截图必须包含测试图的红绿像素，进度和首帧回调不能代替画面验收',
        );
      }
    } finally {
      // 释放顺序：播放会话（保存进度+释放解码器）→ 依赖容器（停 relay）→
      // 测试服务器（关端口）。任何一步失败都不阻断后续清理。
      try {
        await dependencies.playerSession
            .close(invalidateCatalog: false)
            .timeout(_teardownGrace, onTimeout: () {});
      } on Object {
        // 播放会话已结束或超时，继续清理。
      }
      dependencies.dispose();
      await server.close();
    }
  });
}

/// 当前主焦点节点的调试名；用于 TV 焦点契约断言。
String? _focusDebugLabel() => FocusManager.instance.primaryFocus?.debugLabel;

// 从实际获焦卡片读取身份，避免测试通过手工 requestFocus 掩盖根路由焦点问题。
String? _focusedCollectionItemId() {
  final context = FocusManager.instance.primaryFocus?.context;
  return context?.findAncestorWidgetOfExactType<CatalogCard>()?.item.id ??
      context?.findAncestorWidgetOfExactType<MediaCard>()?.item.id;
}

/// 系统返回意图：统一经 PopScope 分层处理，避免按键路径与系统路径双执行。
Future<void> _popBack(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await tester.pump();
}

/// 有界轮询等待：每个 tick 泵一帧（live binding 下为真实时间），
/// 条件满足或超时为止；超时抛出 [reason] 的测试失败。
Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  required String reason,
  Duration timeout = const Duration(seconds: 10),
  Duration step = const Duration(milliseconds: 100),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('等待超时（${timeout.inMilliseconds}ms）：$reason');
    }
    await tester.pump(step);
  }
}

/// 发送一次按键并泵一帧，等待 Shortcuts / 焦点系统处理。
Future<void> _press(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pump();
}

/// 触发测试 IME 的动作键（Next/Done），驱动 TV 显式提交链路。
Future<void> _submitIme(WidgetTester tester, TextInputAction action) async {
  await tester.testTextInput.receiveAction(action);
  await tester.pump();
}

final List<String> _screenshotsWritten = [];
final List<String> _screenshotErrors = [];
bool _surfaceConverted = false;
bool _videoPixelsVisible = false;

/// 尽力截图：Android 经 integration_test 插件捕获真实画面并落盘；
/// 平台不支持时记录原因继续测试，不阻断链路。
Future<void> _captureScreenshot(
  WidgetTester tester,
  IntegrationTestWidgetsFlutterBinding binding,
  String name,
) async {
  // 焦点和组件挂载可早于转场结束；静态截图必须等动画和重绘全部提交。
  await tester.pumpAndSettle(
    const Duration(milliseconds: 100),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 5),
  );
  try {
    if (Platform.isAndroid && !_surfaceConverted) {
      await binding.convertFlutterSurfaceToImage();
      _surfaceConverted = true;
    }
    await tester.pump();
    final bytes = await binding.takeScreenshot(name);
    final dir = Directory(
      Platform.environment['TV_SMOKE_SCREENSHOT_DIR'] ??
          '${Directory.systemTemp.path}${Platform.pathSeparator}luma_tv_smoke_screenshots',
    );
    await dir.create(recursive: true);
    final file = File('${dir.path}${Platform.pathSeparator}$name.png');
    await file.writeAsBytes(bytes, flush: true);
    _screenshotsWritten.add(file.path);
    if (name == 'tv-player-controls') {
      _videoPixelsVisible = await _containsVideoTestPattern(bytes);
    }
  } on Object catch (error) {
    _screenshotErrors.add('$name: $error');
  }
}

/// 从画面中央查找视频夹具的红绿条纹，排除黑屏、文字和蓝色控制层。
Future<bool> _containsVideoTestPattern(List<int> bytes) async {
  final codec = await ui.instantiateImageCodec(Uint8List.fromList(bytes));
  try {
    final frame = await codec.getNextFrame();
    final image = frame.image;
    try {
      final pixels = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (pixels == null) return false;
      var red = 0;
      var green = 0;
      for (var y = image.height * 3 ~/ 10; y < image.height * 6 ~/ 10; y += 8) {
        for (var x = image.width ~/ 10; x < image.width * 9 ~/ 10; x += 8) {
          final offset = (y * image.width + x) * 4;
          final r = pixels.getUint8(offset);
          final g = pixels.getUint8(offset + 1);
          final b = pixels.getUint8(offset + 2);
          if (r > g + 40 && r > b + 40) red++;
          if (g > r + 40 && g > b + 40) green++;
        }
      }
      return red >= 10 && green >= 10;
    } finally {
      image.dispose();
    }
  } finally {
    codec.dispose();
  }
}
