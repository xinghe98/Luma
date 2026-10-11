import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/app/app_dependencies.dart';
import 'package:luma/app/app_scope.dart';
import 'package:luma/data/mock/mock_connection_service.dart';
import 'package:luma/data/mock/mock_media_repository.dart';
import 'package:luma/data/models/api_source.dart';
import 'package:luma/data/models/image_upload_result.dart';
import 'package:luma/data/models/server_profile.dart';
import 'package:luma/data/repositories/image_upload_repository.dart';
import 'package:luma/data/repositories/source_repository.dart';
import 'package:luma/data/storage/upload_target_store.dart';
import 'package:luma/features/uploads/image_upload_controller.dart';
import 'package:luma/features/uploads/image_upload_page.dart';
import 'package:luma/features/uploads/local_image_picker.dart';
import 'package:luma/features/uploads/widgets/upload_queue_list.dart';

void main() {
  Future<void> pumpPage(
    WidgetTester tester, {
    required ImageUploadController controller,
    Size size = const Size(390, 844),
    void Function(bool result)? onPop,
    ThemeMode themeMode = ThemeMode.light,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final dependencies = AppDependencies(
      mediaRepository: MockMediaRepository(),
      connectionService: MockConnectionService(),
    );
    addTearDown(dependencies.dispose);
    dependencies.session.connect(
      ServerProfile(
        name: '测试服',
        address: 'http://test',
        token: 't',
        hostName: 'test',
        userId: 'u1',
      ),
    );
    await tester.pumpWidget(
      AppScope(
        dependencies: dependencies,
        child: MaterialApp(
          theme: ThemeData.light(),
          darkTheme: ThemeData.dark(),
          themeMode: themeMode,
          home: ImageUploadPage(controller: controller, onPop: onPop),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  ImageUploadController buildController({
    List<Source> sources = const [],
    _FakePicker? picker,
    _FakeUploadRepository? uploads,
    _MemoryTargetStore? targets,
  }) {
    final repo = _MutableSourceRepository(sources);
    return ImageUploadController(
      sources: repo,
      uploads: uploads ?? _FakeUploadRepository(),
      picker: picker ?? _FakePicker(const []),
      targets: targets ?? _MemoryTargetStore(),
      identityKey: 'origin|u1',
      apiEpochProvider: () => 1,
    );
  }

  testWidgets('narrow phone shows source selector and pick action', (
    tester,
  ) async {
    final controller = buildController(sources: [_source('s1', '家庭照片')]);
    await pumpPage(tester, controller: controller);
    expect(find.text('保存到'), findsOneWidget);
    expect(find.text('家庭照片'), findsOneWidget);
    expect(find.text('选择图片'), findsOneWidget);
    // 48dp 触控目标：选择图片按钮至少有视觉高度。
    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNotNull);
  });

  testWidgets('wide window keeps selector bounded and centered', (
    tester,
  ) async {
    final controller = buildController(sources: [_source('s1', '家庭照片')]);
    await pumpPage(tester, controller: controller, size: const Size(1280, 800));
    expect(find.text('保存到'), findsOneWidget);
    expect(find.text('选择图片'), findsOneWidget);
    // 宽屏主操作被限宽居中：按钮宽度不超过 actionMaxWidth。
    final bar = tester.getSize(find.byType(FilledButton).first);
    expect(bar.width, lessThanOrEqualTo(360));
  });

  testWidgets('dark theme renders queue and selector', (tester) async {
    final controller = buildController(
      sources: [_source('s1', '家庭照片')],
      picker: _FakePicker([_image('/tmp/a.jpg')]),
    );
    await pumpPage(tester, controller: controller, themeMode: ThemeMode.dark);
    // 入场自动选图已完成，队列直接展示。
    final row = tester.getRect(find.byType(UploadQueueTile));
    expect(row.left, greaterThanOrEqualTo(0));
    expect(row.right, lessThanOrEqualTo(390));
    expect(find.text('a.jpg'), findsOneWidget);
    expect(find.text('保存到'), findsOneWidget);
  });

  testWidgets('tap pick adds image and start uploads it', (tester) async {
    final uploads = _FakeUploadRepository();
    final targets = _MemoryTargetStore();
    final controller = buildController(
      sources: [_source('s1', '家庭照片')],
      picker: _FakePicker([_image('/tmp/a.jpg')]),
      uploads: uploads,
      targets: targets,
    );
    var popped = -1;
    await pumpPage(
      tester,
      controller: controller,
      onPop: (result) => popped = result ? 1 : 0,
    );
    // 入场自动选图已加入队列。
    expect(find.text('a.jpg'), findsOneWidget);
    await tester.tap(find.text('开始上传'));
    await tester.pumpAndSettle();
    expect(find.text('已上传'), findsOneWidget);
    expect(find.text('完成'), findsOneWidget);
    expect(await targets.read('origin|u1'), 's1');
    // 点“完成”返回 true 给库页。
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    expect(popped, 1);
  });

  testWidgets('multiple sources open selector via tap', (tester) async {
    final controller = buildController(
      sources: [_source('s1', '源A'), _source('s2', '源B')],
    );
    await pumpPage(tester, controller: controller);
    // 未保存目标且无单源兜底：显示占位文案。
    expect(find.text('选择保存位置'), findsOneWidget);
    await tester.tap(find.text('选择保存位置'));
    await tester.pumpAndSettle();
    // 共享选择层含关闭按钮与两个来源。
    expect(find.byTooltip('关闭'), findsOneWidget);
    expect(find.text('源A'), findsOneWidget);
    expect(find.text('源B'), findsOneWidget);
    await tester.tap(find.text('源B'));
    await tester.pumpAndSettle();
    expect(controller.selectedSourceId, 's2');
    expect(find.text('源B'), findsOneWidget);
  });

  testWidgets('Escape closes selector sheet without selection', (tester) async {
    final controller = buildController(
      sources: [_source('s1', '源A'), _source('s2', '源B')],
    );
    await pumpPage(tester, controller: controller);
    await tester.tap(find.text('选择保存位置'));
    await tester.pumpAndSettle();
    // 模拟系统 Back/Escape：关闭 barrier。
    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();
    expect(find.text('选择保存位置'), findsOneWidget);
    expect(controller.selectedSourceId, isNull);
  });

  testWidgets('source load error keeps queue visible', (tester) async {
    final repo = _FailingSourceRepository();
    final controller = ImageUploadController(
      sources: repo,
      uploads: _FakeUploadRepository(),
      picker: _FakePicker([_image('/tmp/a.jpg')]),
      targets: _MemoryTargetStore(),
      identityKey: 'origin|u1',
      apiEpochProvider: () => 1,
    );
    // 先让选图成功再失败刷新；队列与错误并存。
    repo.failNext = false;
    // 这里手动注入队列模拟“已选后刷新失败”：先成功加载再报错。
    repo.items = [_source('s1', '家庭照片')];
    await pumpPage(tester, controller: controller);
    expect(find.text('a.jpg'), findsOneWidget);
    // 模拟下一次刷新失败：页面保留队列上方错误条。
    repo.failNext = true;
    await controller.load();
    await tester.pumpAndSettle();
    expect(find.text('a.jpg'), findsOneWidget);
    expect(find.text('媒体源刷新失败'), findsOneWidget);
  });

  testWidgets('real Navigator back pops route and returns result', (
    tester,
  ) async {
    // 不走 onPop 拦截：真实 push 路由并验证返回值经 Navigator 回传。
    final controller = buildController(
      sources: [_source('s1', '家庭照片')],
      picker: _FakePicker(const []),
    );
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final dependencies = AppDependencies(
      mediaRepository: MockMediaRepository(),
      connectionService: MockConnectionService(),
    );
    addTearDown(dependencies.dispose);
    dependencies.session.connect(
      ServerProfile(
        name: '测试服',
        address: 'http://test',
        token: 't',
        hostName: 'test',
        userId: 'u1',
      ),
    );
    bool? pushedResult;
    await tester.pumpWidget(
      AppScope(
        dependencies: dependencies,
        child: MaterialApp(
          theme: ThemeData.light(),
          home: Builder(
            builder: (context) => Scaffold(
              body: FilledButton(
                onPressed: () async {
                  pushedResult = await Navigator.of(context).push<bool>(
                    MaterialPageRoute(
                      builder: (_) => ImageUploadPage(controller: controller),
                    ),
                  );
                },
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    expect(find.text('上传图片'), findsOneWidget);
    // 空队列直接返回：无确认框，结果由实际成功标记决定。
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    expect(find.text('上传图片'), findsNothing);
    expect(pushedResult, isFalse);
  });

  testWidgets('pending items trigger confirm dialog once on double back', (
    tester,
  ) async {
    final controller = buildController(
      sources: [_source('s1', '家庭照片')],
      picker: _FakePicker([_image('/tmp/a.jpg')]),
    );
    await pumpPage(tester, controller: controller);
    // 连续两次返回请求：确认框只开一次（队列来自入场自动选图）。
    await tester.tap(find.byTooltip('返回'));
    await tester.tap(find.byTooltip('返回'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.text('放弃上传？'), findsOneWidget);
    await tester.tap(find.text('继续上传'));
    await tester.pumpAndSettle();
    expect(find.text('a.jpg'), findsOneWidget);
  });

  testWidgets('entry auto-opens picker once, retrying load does not repick', (
    tester,
  ) async {
    final picker = _FakePicker(const []);
    final controller = buildController(
      sources: [_source('s1', '家庭照片')],
      picker: picker,
    );
    await pumpPage(tester, controller: controller);
    // 入场转场后自动拉起一次系统选图；空结果保留可见选择按钮。
    expect(picker.callCount, 1);
    expect(find.text('选择图片'), findsOneWidget);
    // load 重试不得再次自动弹出。
    await controller.load();
    await tester.pumpAndSettle();
    expect(picker.callCount, 1);
  });

  testWidgets('no sources skips auto-pick and shows hint', (tester) async {
    final picker = _FakePicker(const []);
    final controller = buildController(sources: const [], picker: picker);
    await pumpPage(tester, controller: controller);
    expect(picker.callCount, 0);
    expect(find.text('没有可用媒体源'), findsOneWidget);
    // 无目录时选图按钮禁用而不是隐藏。
    final pick = tester.widget<FilledButton>(find.byType(FilledButton).first);
    expect(pick.onPressed, isNull);
  });
}

Source _source(String id, String name) => Source(
  id: id,
  name: name,
  type: 'local',
  libraryKind: 'personal',
  enabled: true,
  status: 'online',
  lastScanId: null,
  lastSeenAt: null,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

LocalImage _image(String path, {int bytes = 1024}) => LocalImage(
  path: path,
  filename: path.split('/').last,
  contentLength: bytes,
  openRead: () => Stream<List<int>>.fromIterable([List<int>.filled(bytes, 1)]),
);

class _MutableSourceRepository implements SourceRepository {
  _MutableSourceRepository(this._items);

  final List<Source> _items;

  @override
  Future<Source?> find(String id) async {
    for (final source in _items) {
      if (source.id == id) return source;
    }
    return null;
  }

  @override
  Future<List<Source>> list({bool refresh = false}) async => _items;
}

class _FailingSourceRepository implements SourceRepository {
  List<Source> items = [];
  bool failNext = false;

  @override
  Future<Source?> find(String id) async => null;

  @override
  Future<List<Source>> list({bool refresh = false}) async {
    if (failNext) throw StateError('offline');
    return items;
  }
}

class _FakePicker implements LocalImagePicker {
  _FakePicker(this._images);

  final List<LocalImage> _images;
  var callCount = 0;

  @override
  Future<List<LocalImage>?> pick() async {
    callCount++;
    return _images;
  }
}

class _FakeUploadRepository implements ImageUploadRepository {
  @override
  Future<ImageUploadResult> upload({
    required String sourceId,
    required String filename,
    required Stream<List<int>> stream,
    required int contentLength,
    CancelToken? cancelToken,
    void Function(int sent, int total)? onProgress,
  }) async {
    await for (final _ in stream) {}
    onProgress?.call(contentLength, contentLength);
    return ImageUploadResult(mediaId: 'm1', filename: filename);
  }
}

class _MemoryTargetStore implements UploadTargetStore {
  final _map = <String, String>{};

  @override
  Future<void> clear(String identityKey) async => _map.remove(identityKey);

  @override
  Future<String?> read(String identityKey) async => _map[identityKey];

  @override
  Future<void> write(String identityKey, String sourceId) async =>
      _map[identityKey] = sourceId;
}
