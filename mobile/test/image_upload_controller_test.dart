import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/data/api/api_exception.dart';
import 'package:luma/data/models/api_source.dart';
import 'package:luma/data/models/image_upload_result.dart';
import 'package:luma/data/repositories/image_upload_repository.dart';
import 'package:luma/data/repositories/source_repository.dart';
import 'package:luma/data/storage/upload_target_store.dart';
import 'package:luma/features/uploads/image_upload_controller.dart';
import 'package:luma/features/uploads/local_image_picker.dart';

void main() {
  group('ImageUploadController', () {
    test(
      'single source auto-selects only when no saved target exists',
      () async {
        final controller = _controller(sources: [_source('s1')]);
        await controller.load();
        expect(controller.selectedSourceId, 's1');
        expect(controller.sourcesState, UploadSourcesState.ready);
        controller.dispose();
      },
    );

    test('saved target wins over multiple sources', () async {
      final targets = _MemoryTargetStore()..seed('origin|alice', 's2');
      final controller = _controller(
        sources: [_source('s1'), _source('s2')],
        targets: targets,
      );
      await controller.load();
      expect(controller.selectedSourceId, 's2');
      controller.dispose();
    });

    test(
      'saved target missing keeps selection empty even with single source',
      () async {
        final targets = _MemoryTargetStore()..seed('origin|alice', 'gone');
        final controller = _controller(
          sources: [_source('s1')],
          targets: targets,
        );
        await controller.load();
        expect(controller.selectedSourceId, isNull);
        controller.dispose();
      },
    );

    test('pickImages dedupes by path and keeps queue', () async {
      final picker = _FakePicker([
        _image('/tmp/a.jpg'),
        _image('/tmp/a.jpg'),
        _image('/tmp/b.jpg'),
      ]);
      final controller = _controller(sources: [_source('s1')], picker: picker);
      await controller.load();
      expect(await controller.pickImages(), isTrue);
      expect(controller.selectedCount, 2);
      controller.dispose();
    });

    test('oversized images surface pickError instead of silent drop', () async {
      final controller = _controller(
        sources: [_source('s1')],
        picker: _FakePicker([_image('/tmp/big.jpg', bytes: 65 * 1024 * 1024)]),
      );
      await controller.load();
      expect(await controller.pickImages(), isFalse);
      expect(controller.pickError, isNotNull);
      expect(controller.selectedCount, 0);
      controller.dispose();
    });

    test('picker throw exposes error rather than cancel', () async {
      final controller = _controller(
        sources: [_source('s1')],
        picker: _FakePicker.error('denied'),
      );
      await controller.load();
      expect(await controller.pickImages(), isFalse);
      expect(controller.pickError, contains('无法打开图片选择器'));
      controller.dispose();
    });

    test('successful upload marks item and remembers target', () async {
      final targets = _MemoryTargetStore();
      final uploads = _FakeUploadRepository();
      final controller = _controller(
        sources: [_source('s1')],
        uploads: uploads,
        targets: targets,
        picker: _FakePicker([_image('/tmp/a.jpg')]),
      );
      await controller.load();
      await controller.pickImages();
      await controller.start();
      expect(controller.queue.first.status, ImageUploadStatus.success);
      expect(controller.queue.first.result?.filename, 'a.jpg');
      expect(await targets.read('origin|alice'), 's1');
      expect(controller.hasSuccessfulUpload, isTrue);
      controller.dispose();
    });

    test('non-retryable error marks failed without retry option', () async {
      final uploads = _FakeUploadRepository(
        error: const ApiException(
          message: 'too large',
          code: 'UPLOAD_TOO_LARGE',
          statusCode: 413,
        ),
      );
      final controller = _controller(
        sources: [_source('s1')],
        uploads: uploads,
        picker: _FakePicker([_image('/tmp/big.jpg')]),
      );
      await controller.load();
      await controller.pickImages();
      await controller.start();
      expect(controller.queue.first.status, ImageUploadStatus.failed);
      expect(controller.queue.first.retryable, isFalse);
      expect(controller.hasRetryableFailure, isFalse);
      controller.dispose();
    });

    test('retryable failure goes back to pending on retryFailed', () async {
      var calls = 0;
      final uploads = _FakeUploadRepository(
        errorBuilder: () {
          calls++;
          if (calls == 1) {
            return const ApiException(
              message: 'offline',
              code: 'SOURCE_OFFLINE',
              statusCode: 503,
            );
          }
          return null;
        },
      );
      final controller = _controller(
        sources: [_source('s1')],
        uploads: uploads,
        picker: _FakePicker([_image('/tmp/a.jpg')]),
      );
      await controller.load();
      await controller.pickImages();
      await controller.start();
      expect(controller.queue.first.status, ImageUploadStatus.failed);
      expect(controller.queue.first.retryable, isTrue);
      await controller.retryFailed();
      expect(controller.queue.first.status, ImageUploadStatus.success);
      expect(calls, 2);
      controller.dispose();
    });

    test('cancel waits for in-flight item and preserves successes', () async {
      final gate = Completer<void>();
      final uploads = _FakeUploadRepository(gate: gate);
      final controller = _controller(
        sources: [_source('s1')],
        uploads: uploads,
        picker: _FakePicker([_image('/tmp/a.jpg'), _image('/tmp/b.jpg')]),
      );
      await controller.load();
      await controller.pickImages();
      final run = controller.start();
      await Future<void>.delayed(Duration.zero);
      final cancel = controller.cancel();
      gate.complete();
      await Future.wait([run, cancel]);
      final statuses = controller.queue.map((e) => e.status).toList();
      // 第一张已发出：成功或被取消；第二张必须保持 pending。
      expect(statuses.last, ImageUploadStatus.pending);
      expect(controller.uploading, isFalse);
      controller.dispose();
    });

    test('source revoked clears target and keeps files reselectable', () async {
      final targets = _MemoryTargetStore()..seed('origin|alice', 's1');
      final uploads = _FakeUploadRepository(
        error: const ApiException(
          message: 'not found',
          code: 'SOURCE_NOT_FOUND',
          statusCode: 404,
        ),
      );
      final controller = _controller(
        sources: [_source('s1'), _source('s2')],
        uploads: uploads,
        targets: targets,
        picker: _FakePicker([_image('/tmp/a.jpg')]),
      );
      await controller.load();
      await controller.pickImages();
      await controller.start();
      // 目标被清空并标记可重选；文件还在队列，换源后可继续。
      expect(controller.selectedSourceId, isNull);
      expect(await targets.read('origin|alice'), isNull);
      expect(controller.queue.first.status, ImageUploadStatus.pending);
      controller.selectSource('s2');
      // 换源后再次上传：让仓储这次成功。
      uploads.error = null;
      await controller.start();
      expect(controller.queue.first.status, ImageUploadStatus.success);
      expect(await targets.read('origin|alice'), 's2');
      controller.dispose();
    });

    test('unauthorized upload surfaces relogin hint not retry', () async {
      final uploads = _FakeUploadRepository(
        error: const ApiException(
          message: 'forbidden',
          code: 'UNAUTHORIZED',
          statusCode: 403,
        ),
      );
      final controller = _controller(
        sources: [_source('s1'), _source('s2')],
        uploads: uploads,
        picker: _FakePicker([_image('/tmp/a.jpg')]),
      );
      await controller.load();
      controller.selectSource('s1');
      await controller.pickImages();
      await controller.start();
      // 整账号失效：项退回 pending，文案提示重新登录而非换目录。
      expect(controller.queue.first.status, ImageUploadStatus.pending);
      expect(controller.queue.first.errorMessage, contains('重新登录'));
      controller.dispose();
    });

    test('session epoch change mid-queue freezes remaining uploads', () async {
      var epoch = 1;
      final gate = Completer<void>();
      final uploads = _FakeUploadRepository(
        gate: gate,
        onSent: () => epoch = 2,
      );
      final controller = ImageUploadController(
        sources: _StaticSourceRepository([_source('s1')]),
        uploads: uploads,
        picker: _FakePicker([_image('/tmp/a.jpg'), _image('/tmp/b.jpg')]),
        targets: _MemoryTargetStore(),
        identityKey: 'origin|alice',
        apiEpochProvider: () => epoch,
      );
      await controller.load();
      await controller.pickImages();
      final run = controller.start();
      gate.complete();
      await run;
      // epoch 在第一张上传后变化：第二张不得使用新账号凭据发送。
      expect(uploads.callCount, 1);
      expect(controller.sessionInvalidated, isTrue);
      controller.dispose();
    });

    test('invalidated session blocks start and pickImages', () async {
      var epoch = 1;
      final controller = ImageUploadController(
        sources: _StaticSourceRepository([_source('s1')]),
        uploads: _FakeUploadRepository(),
        picker: _FakePicker([_image('/tmp/a.jpg')]),
        targets: _MemoryTargetStore(),
        identityKey: 'origin|alice',
        apiEpochProvider: () => epoch,
      );
      await controller.load();
      await controller.pickImages();
      epoch = 2;
      await controller.start();
      expect(controller.sessionInvalidated, isTrue);
      expect(controller.queue.first.status, ImageUploadStatus.pending);
      expect(await controller.pickImages(), isFalse);
      controller.dispose();
    });
  });
}

ImageUploadController _controller({
  required List<Source> sources,
  SourceRepository? sourceRepository,
  ImageUploadRepository? uploads,
  LocalImagePicker? picker,
  UploadTargetStore? targets,
  String identityKey = 'origin|alice',
  int Function()? apiEpochProvider,
}) => ImageUploadController(
  sources: sourceRepository ?? _StaticSourceRepository(sources),
  uploads: uploads ?? _FakeUploadRepository(),
  picker: picker ?? _FakePicker(const []),
  targets: targets ?? _MemoryTargetStore(),
  identityKey: identityKey,
  apiEpochProvider: apiEpochProvider ?? () => 1,
);

Source _source(String id, {bool enabled = true}) => Source(
  id: id,
  name: '源$id',
  type: 'local',
  libraryKind: 'personal',
  enabled: enabled,
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

class _StaticSourceRepository implements SourceRepository {
  const _StaticSourceRepository(this._sources);

  final List<Source> _sources;

  @override
  Future<Source?> find(String id) async {
    for (final source in _sources) {
      if (source.id == id) return source;
    }
    return null;
  }

  @override
  Future<List<Source>> list({bool refresh = false}) async => _sources;
}

class _FakePicker implements LocalImagePicker {
  _FakePicker(this._images) : _error = null;

  _FakePicker.error(this._error) : _images = const [];

  final List<LocalImage> _images;
  final Object? _error;

  @override
  Future<List<LocalImage>?> pick() async {
    if (_error != null) throw _error;
    return _images;
  }
}

class _FakeUploadRepository implements ImageUploadRepository {
  _FakeUploadRepository({
    this.error,
    this.errorBuilder,
    this.gate,
    this.onSent,
  });

  ApiException? error;
  final ApiException? Function()? errorBuilder;
  final Completer<void>? gate;
  final VoidCallback? onSent;
  var _callCount = 0;

  int get callCount => _callCount;

  @override
  Future<ImageUploadResult> upload({
    required String sourceId,
    required String filename,
    required Stream<List<int>> stream,
    required int contentLength,
    CancelToken? cancelToken,
    void Function(int sent, int total)? onProgress,
  }) async {
    _callCount++;
    onSent?.call();
    await gate?.future;
    if (cancelToken?.isCancelled ?? false) {
      throw DioException.requestCancelled(
        requestOptions: RequestOptions(),
        reason: 'cancelled',
      );
    }
    final failure = errorBuilder?.call() ?? error;
    if (failure != null) throw failure;
    await for (final _ in stream) {}
    onProgress?.call(contentLength, contentLength);
    return ImageUploadResult(mediaId: 'm-$_callCount', filename: filename);
  }
}

class _MemoryTargetStore implements UploadTargetStore {
  final _map = <String, String>{};

  void seed(String key, String value) => _map[key] = value;

  @override
  Future<void> clear(String identityKey) async => _map.remove(identityKey);

  @override
  Future<String?> read(String identityKey) async => _map[identityKey];

  @override
  Future<void> write(String identityKey, String sourceId) async =>
      _map[identityKey] = sourceId;
}
