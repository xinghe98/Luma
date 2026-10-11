// 图片上传会话控制器：持有队列、目标选择、逐张上传与记忆逻辑。
// 身份键绑定 server+userId；apiEpoch 每次上传前校验，会话切换
// 立即取消在途请求并冻结队列，不修改外部状态。
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../data/api/api_exception.dart';
import '../../data/models/api_source.dart';
import '../../data/models/image_upload_result.dart';
import '../../data/repositories/image_upload_repository.dart';
import '../../data/repositories/source_repository.dart';
import '../../data/storage/upload_target_store.dart';
import 'local_image_picker.dart';

/// 队列中单项的生命周期。
enum ImageUploadStatus { pending, uploading, success, failed }

/// 一张待上传图片的运行时状态；不可变地携带进度与结果。
final class ImageUploadEntry {
  const ImageUploadEntry({
    required this.image,
    this.status = ImageUploadStatus.pending,
    this.sentBytes = 0,
    this.result,
    this.errorMessage,
    this.retryable = false,
  });

  final LocalImage image;
  final ImageUploadStatus status;
  final int sentBytes;
  final ImageUploadResult? result;
  final String? errorMessage;

  /// 是否为可手动重试的失败；网络/取消/5xx/源离线为 true，
  /// 400/401/404/413 及文件校验失败为 false。
  final bool retryable;

  ImageUploadEntry copyWith({
    ImageUploadStatus? status,
    int? sentBytes,
    ImageUploadResult? result,
    String? errorMessage,
    bool? retryable,
    bool clearResult = false,
    bool clearError = false,
  }) => ImageUploadEntry(
    image: image,
    status: status ?? this.status,
    sentBytes: sentBytes ?? this.sentBytes,
    result: clearResult ? null : (result ?? this.result),
    errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    retryable: retryable ?? this.retryable,
  );
}

/// 来源列表的分辨结果；controller 只暴露 states，不暴露加载细节。
enum UploadSourcesState { loading, ready, error }

/// 一次“选图”动作中因校验失败被剔除的项；页面据此提示用户，
/// 不把它们当作静默消失或用户取消。
final class RejectedImage {
  const RejectedImage({required this.filename, required this.reason});

  final String filename;
  final String reason;
}

/// 上传页用的会话级控制器。
/// [identityKey] 绑定 `服务器地址|userId`；[apiEpochProvider] 每次
/// 上传前检查当前 epoch，切换即停传，防止把旧账号队列发到新身份。
final class ImageUploadController extends ChangeNotifier {
  ImageUploadController({
    required SourceRepository sources,
    required ImageUploadRepository uploads,
    required LocalImagePicker picker,
    required UploadTargetStore targets,
    required String identityKey,
    required int Function() apiEpochProvider,
  }) : _sources = sources,
       _uploads = uploads,
       _picker = picker,
       _targets = targets,
       _identityKey = identityKey,
       _apiEpochProvider = apiEpochProvider,
       _boundEpoch = apiEpochProvider();

  final SourceRepository _sources;
  final ImageUploadRepository _uploads;
  final LocalImagePicker _picker;
  final UploadTargetStore _targets;
  final String _identityKey;
  final int Function() _apiEpochProvider;

  /// 控制器创建时的 epoch；之后每次上传前与当前值比对。
  final int _boundEpoch;

  final List<ImageUploadEntry> _queue = [];
  List<Source>? _sourcesList;
  UploadSourcesState _sourcesState = UploadSourcesState.loading;
  Object? _sourcesError;
  String? _selectedSourceId;
  bool _picking = false;
  bool _uploading = false;
  bool _cancelRequested = false;
  bool _disposed = false;
  bool _sessionInvalidated = false;
  CancelToken? _activeToken;
  String? _pickError;
  List<RejectedImage> _lastRejected = const [];
  Completer<void>? _uploadLoop;

  List<Source>? get sources => _sourcesList;
  UploadSourcesState get sourcesState => _sourcesState;
  Object? get sourcesError => _sourcesError;
  String? get selectedSourceId => _selectedSourceId;
  bool get picking => _picking;
  bool get uploading => _uploading;

  /// 会话已被服务端 epoch 变化作废；队列保留展示但拒绝再上传。
  bool get sessionInvalidated => _sessionInvalidated;

  /// 最近一次选图的用户可见错误； picker 抛错或全部超限时不为空。
  String? get pickError => _pickError;
  List<RejectedImage> get lastRejected => _lastRejected;

  List<ImageUploadEntry> get queue => List.unmodifiable(_queue);
  bool get hasSuccessfulUpload =>
      _queue.any((entry) => entry.status == ImageUploadStatus.success);
  bool get hasPendingItems =>
      _queue.any((entry) => entry.status == ImageUploadStatus.pending);
  bool get hasRetryableFailure => _queue.any(
    (entry) => entry.status == ImageUploadStatus.failed && entry.retryable,
  );
  int get totalBytes =>
      _queue.fold(0, (sum, entry) => sum + entry.image.contentLength);
  int get selectedCount => _queue.length;

  Source? get selectedSource {
    final list = _sourcesList;
    final id = _selectedSourceId;
    if (list == null || id == null) return null;
    for (final source in list) {
      if (source.id == id) return source;
    }
    return null;
  }

  /// 初始化：拉来源列表并恢复该身份的上次成功目标。
  /// 已选文件在刷新/重试期间保持队列，不因来源加载而丢失。
  Future<void> load() async {
    if (_disposed || !_assertSession()) return;
    _sourcesState = UploadSourcesState.loading;
    _sourcesError = null;
    _notify();
    try {
      final list = await _sources.list();
      if (_disposed || !_assertSession()) return;
      _sourcesList = list;
      _sourcesState = UploadSourcesState.ready;
      await _restoreTarget();
    } on Object catch (error) {
      if (_disposed) return;
      _sourcesState = UploadSourcesState.error;
      _sourcesError = error;
    }
    _notify();
  }

  /// 刷新来源列表但保留已选队列；当前选中目标失效时清空选中。
  Future<void> refreshSources() => load();

  /// 打开系统多选；返回是否新增了图片。
  /// picker 抛错或全部项因校验失败被剔除时设置 [pickError]，返回 false。
  Future<bool> pickImages() async {
    if (_disposed || _picking || _uploading || !_assertSession()) {
      return false;
    }
    _picking = true;
    _pickError = null;
    _lastRejected = const [];
    _notify();
    try {
      final picked = await _picker.pick();
      if (_disposed || picked == null || !_assertSession()) return false;
      final existing = _queue.map((entry) => entry.image.path).toSet();
      final rejected = <RejectedImage>[];
      var added = false;
      for (final image in picked) {
        if (image.contentLength <= 0 ||
            image.contentLength > kUploadMaxBytes ||
            image.filename.isEmpty) {
          rejected.add(
            RejectedImage(
              filename: image.filename.isEmpty ? image.path : image.filename,
              reason: image.filename.isEmpty ? '无法读取文件名' : '超过 64 MB 或文件为空',
            ),
          );
          continue;
        }
        if (existing.add(image.path)) {
          _queue.add(ImageUploadEntry(image: image));
          added = true;
        }
      }
      _lastRejected = rejected;
      if (rejected.isNotEmpty) {
        _pickError = added
            ? '${rejected.length} 张图片不可用（${rejected.first.reason}），其余已加入队列'
            : '所选图片不可用：${rejected.first.reason}';
      }
      if (added || _pickError != null) _notify();
      return added;
    } on Object catch (error) {
      _pickError = '无法打开图片选择器：$error';
      _notify();
      return false;
    } finally {
      _picking = false;
      _notify();
    }
  }

  /// 清除最近一次选择错误提示。
  void clearPickError() {
    if (_pickError == null) return;
    _pickError = null;
    _notify();
  }

  /// 选择上传目标；仅接受当前列表内已启用的来源。
  void selectSource(String sourceId) {
    final list = _sourcesList;
    if (list == null || _disposed || _uploading || _sessionInvalidated) {
      return;
    }
    if (!list.any((source) => source.id == sourceId)) return;
    _selectedSourceId = sourceId;
    _notify();
  }

  /// 清除某个待传项；已成功或正在上传的项不可移除。
  void removeAt(int index) {
    if (_disposed ||
        _uploading ||
        index < 0 ||
        index >= _queue.length ||
        _queue[index].status != ImageUploadStatus.pending) {
      return;
    }
    _queue.removeAt(index);
    _notify();
  }

  /// 开始逐张上传队列中的 pending 项；跳过已成功项。
  /// 目标缺失、队列为空、会话已失效或已在传时立即返回。
  Future<void> start() async {
    if (_disposed ||
        _uploading ||
        _sessionInvalidated ||
        _selectedSourceId == null) {
      return;
    }
    if (!_queue.any((entry) => entry.status == ImageUploadStatus.pending)) {
      return;
    }
    _uploading = true;
    _cancelRequested = false;
    _uploadLoop = Completer<void>();
    _notify();
    try {
      for (var i = 0; i < _queue.length; i++) {
        if (_disposed || _cancelRequested || _sessionInvalidated) break;
        // 每张上传前校验 epoch：会话切换后立即停止，不把队列发到新账号。
        if (!_assertSession()) break;
        final entry = _queue[i];
        if (entry.status != ImageUploadStatus.pending) continue;
        await _uploadOne(i);
      }
    } finally {
      _uploading = false;
      _activeToken = null;
      final loop = _uploadLoop;
      _uploadLoop = null;
      if (loop != null && !loop.isCompleted) loop.complete();
      _notify();
    }
  }

  /// 仅重试可重试的失败项；成功与 pending 项保持不动。
  Future<void> retryFailed() async {
    if (_disposed || _uploading || _sessionInvalidated) return;
    var changed = false;
    for (var i = 0; i < _queue.length; i++) {
      final entry = _queue[i];
      if (entry.status == ImageUploadStatus.failed && entry.retryable) {
        _queue[i] = entry.copyWith(
          status: ImageUploadStatus.pending,
          sentBytes: 0,
          clearResult: true,
          clearError: true,
        );
        changed = true;
      }
    }
    if (!changed) return;
    _notify();
    await start();
  }

  /// 请求停止上传：取消在途请求并等待循环结束，已成功项保留。
  /// 页面离开前必须 await，确保图片流已释放。
  Future<void> cancel() async {
    if (_disposed) return;
    _cancelRequested = true;
    _activeToken?.cancel();
    _notify();
    final loop = _uploadLoop;
    if (loop != null) await loop.future;
  }

  /// 清空整个队列与选中态（例如用户确认放弃全部）。
  void reset() {
    if (_disposed || _uploading) return;
    _queue.clear();
    _selectedSourceId = null;
    _sourcesList = null;
    _sourcesState = UploadSourcesState.loading;
    _sourcesError = null;
    _pickError = null;
    _lastRejected = const [];
    _notify();
  }

  /// 会话 epoch 是否仍与绑定时一致；不一致即冻结并取消在途请求。
  bool _assertSession() {
    if (_sessionInvalidated) return false;
    if (_apiEpochProvider() == _boundEpoch) return true;
    _sessionInvalidated = true;
    _activeToken?.cancel();
    _notify();
    return false;
  }

  /// 上传单个队列项，并处理成功/失败的状态迁移与目标记忆。
  Future<void> _uploadOne(int index) async {
    final entry = _queue[index];
    final sourceId = _selectedSourceId;
    if (sourceId == null) return;
    final token = CancelToken();
    _activeToken = token;
    _queue[index] = entry.copyWith(
      status: ImageUploadStatus.uploading,
      sentBytes: 0,
      clearResult: true,
      clearError: true,
    );
    _notify();
    try {
      final result = await _uploads.upload(
        sourceId: sourceId,
        filename: entry.image.filename,
        stream: entry.image.openRead(),
        contentLength: entry.image.contentLength,
        cancelToken: token,
        onProgress: (sent, total) => _onProgress(index, sent),
      );
      if (_disposed) return;
      _queue[index] = entry.copyWith(
        status: ImageUploadStatus.success,
        sentBytes: entry.image.contentLength,
        result: result,
        clearError: true,
      );
      unawaited(_rememberTarget(sourceId));
    } on DioException catch (error) {
      if (_disposed) return;
      final inner = error.error;
      if (inner is ApiException && inner.code == 'SESSION_CHANGED') {
        _freezeSession();
        return;
      }
      if (inner is ApiException && _isSourceRevoked(inner)) {
        await _onSourceRevoked(
          index,
          entry,
          unauthorized: inner.code == 'UNAUTHORIZED',
        );
        return;
      }
      _queue[index] = _failedEntry(
        entry,
        message: inner is ApiException
            ? inner.message
            : (error.message ?? '网络请求失败'),
        retryable: _isRetryable(error),
      );
    } on ApiException catch (error) {
      if (_disposed) return;
      if (error.code == 'SESSION_CHANGED') {
        _freezeSession();
        return;
      }
      if (_isSourceRevoked(error)) {
        await _onSourceRevoked(
          index,
          entry,
          unauthorized: error.code == 'UNAUTHORIZED',
        );
        return;
      }
      _queue[index] = _failedEntry(
        entry,
        message: error.message,
        retryable: _isRetryableCode(error),
      );
    } on Object catch (error) {
      if (_disposed) return;
      _queue[index] = _failedEntry(
        entry,
        message: error.toString(),
        retryable: true,
      );
    }
    _notify();
  }

  /// 目标媒体源被撤权或删除：清除选中与记忆、当前项退回 pending 并刷新
  /// 来源列表（保留队列，让用户换目标而非反复选同一失效项）。
  /// [unauthorized] 表示整账号失效，提示重新登录而非仅换目录。
  Future<void> _onSourceRevoked(
    int index,
    ImageUploadEntry entry, {
    bool unauthorized = false,
  }) async {
    unawaited(_forgetTarget());
    _selectedSourceId = null;
    _queue[index] = entry.copyWith(
      status: ImageUploadStatus.pending,
      clearResult: true,
      errorMessage: unauthorized ? '登录已失效，请重新登录' : '目标媒体源不可用，请重新选择',
      retryable: true,
    );
    _notify();
    unawaited(_refreshAfterRevoke());
  }

  /// 会话被服务端 epoch 作废：取消在途请求并冻结；队列保留展示。
  void _freezeSession() {
    if (_sessionInvalidated) return;
    _sessionInvalidated = true;
    _activeToken?.cancel();
    _notify();
  }

  /// 撤权后重新拉取来源；失败不阻塞用户用现有列表重选。
  Future<void> _refreshAfterRevoke() async {
    if (_disposed) return;
    try {
      final list = await _sources.list(refresh: true);
      if (_disposed) return;
      _sourcesList = list;
      _sourcesState = UploadSourcesState.ready;
      _notify();
    } on Object {
      // 刷新失败不阻塞用户用现有列表重选。
    }
  }

  bool _isSourceRevoked(ApiException error) =>
      error.code == 'SOURCE_NOT_FOUND' || error.code == 'UNAUTHORIZED';

  ImageUploadEntry _failedEntry(
    ImageUploadEntry entry, {
    required String message,
    required bool retryable,
  }) => entry.copyWith(
    status: ImageUploadStatus.failed,
    errorMessage: message,
    retryable: retryable,
  );

  void _onProgress(int index, int sent) {
    if (_disposed || index >= _queue.length || _sessionInvalidated) return;
    final entry = _queue[index];
    if (entry.status != ImageUploadStatus.uploading) return;
    _queue[index] = entry.copyWith(sentBytes: sent);
    _notify();
  }

  /// 根据 Dio/ApiException 决定是否允许手动重试。
  bool _isRetryable(DioException error) {
    if (error.type == DioExceptionType.cancel) return false;
    final inner = error.error;
    if (inner is ApiException) return _isRetryableCode(inner);
    return true;
  }

  bool _isRetryableCode(ApiException error) {
    final code = error.code;
    // 客户端/权限/超限错误重试无意义；源离线、5xx、网络断开允许手动再送。
    // SOURCE_NOT_FOUND/UNAUTHORIZED 已在 _onSourceRevoked 分流，不走到这里。
    if (code == 'INVALID_REQUEST' ||
        code == 'UNSUPPORTED_IMAGE' ||
        code == 'UPLOAD_TOO_LARGE') {
      return false;
    }
    return true;
  }

  /// 恢复上次成功目标；保存目标已不在当前列表时保持未选，
  /// 不做兜底自动换源；仅首次进入且只有一个来源时自动选中。
  Future<void> _restoreTarget() async {
    final list = _sourcesList;
    if (list == null || list.isEmpty) {
      _selectedSourceId = null;
      return;
    }
    String? saved;
    try {
      saved = await _targets.read(_identityKey);
    } on Object {
      saved = null;
    }
    if (_disposed) return;
    if (saved != null && list.any((source) => source.id == saved)) {
      _selectedSourceId = saved;
    } else if (saved == null && list.length == 1) {
      // 只有从未保存过目标、且只有一个来源时才自动选中；
      // 保存目标失效必须让用户显式重选。
      _selectedSourceId = list.first.id;
    } else {
      _selectedSourceId = null;
    }
    _notify();
  }

  /// 上传成功后持久化目标；失败静默忽略，不阻塞队列推进。
  Future<void> _rememberTarget(String sourceId) async {
    try {
      await _targets.write(_identityKey, sourceId);
    } on Object {
      // 记忆失败不影响已成功的上传。
    }
  }

  /// 清除该身份保存的上传目标；目标被撤权/删除时调用。
  Future<void> _forgetTarget() async {
    try {
      await _targets.clear(_identityKey);
    } on Object {
      // 清理失败不阻塞用户重新选择。
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// 控制器失效后所有后续回调静默丢弃；在途请求由页面在 dispose 前取消。
  @override
  void dispose() {
    _disposed = true;
    _activeToken?.cancel();
    super.dispose();
  }
}
