import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/models/api_scan.dart';
import '../../data/repositories/scan_repository.dart';

class SettingsController extends ChangeNotifier {
  SettingsController({
    ScanRepository? scanRepository,
    this.scanPollInterval = const Duration(seconds: 1),
  }) : _scanRepository = scanRepository;

  final ScanRepository? _scanRepository;
  final Duration scanPollInterval;
  ThemeMode _themeMode = ThemeMode.light;
  double? _scanProgress;
  String? _scanError;
  int _scanGeneration = 0;
  int _scanDiscoveredCount = 0;
  List<ScanJob> _scanJobs = const [];

  ThemeMode get themeMode => _themeMode;
  double get cacheSizeMb =>
      PaintingBinding.instance.imageCache.currentSizeBytes / 1048576;
  double? get scanProgress => _scanProgress;
  bool get isScanning => _scanProgress != null;
  String? get scanError => _scanError;
  int get scanDiscoveredCount => _scanDiscoveredCount;

  List<ScanJob> get scanJobs => List.unmodifiable(_scanJobs);

  String get scanStatusLabel {
    if (isScanning) {
      if (_scanJobs.isEmpty) return '正在准备扫描';
      if (_scanJobs.any((job) => job.status == 'pending')) return '等待扫描';
      if (_scanJobs.any((job) => job.status == 'running')) return '正在扫描目录';
      if (_processing.thumbnailing > 0) return '正在生成缩略图';
      if (_processing.probing > 0) return '正在探测媒体';
      if (_processing.discovered > 0) return '等待媒体处理';
      if (_metadata.status == 'waiting') return '正在整理作品库';
      if (_metadata.status == 'running') return '正在匹配影视资料';
      return '正在完成扫描';
    }
    if (_scanJobs.any((job) => job.status == 'interrupted')) return '扫描已中断';
    if (_scanJobs.any((job) => job.status != 'completed')) return '扫描失败';
    if (_processing.failed > 0) return '完成但有错误';
    return '已就绪';
  }

  String get scanStatusDetails {
    if (_scanError != null) return _scanError!;
    final summary = _processing;
    if (isScanning && _scanJobs.isEmpty) return '正在创建扫描任务';
    if (_scanJobs.isEmpty) return '没有正在处理的扫描任务';
    final parts = <String>[
      '共 ${summary.total} 个文件',
      '已就绪 ${summary.ready}',
      if (summary.discovered > 0) '待处理 ${summary.discovered}',
      if (summary.probing > 0) '探测中 ${summary.probing}',
      if (summary.thumbnailing > 0) '缩略图中 ${summary.thumbnailing}',
      if (summary.failed > 0) '失败 ${summary.failed}',
    ];
    final metadata = _metadata;
    if (_isMetadataPhase) {
      parts.addAll([
        '资料 ${metadata.total} 部',
        '已匹配 ${metadata.ready}',
        if (metadata.pending > 0) '待匹配 ${metadata.pending}',
        if (metadata.refreshing > 0) '匹配中 ${metadata.refreshing}',
        if (metadata.unmatched > 0) '无候选 ${metadata.unmatched}',
        if (metadata.failed > 0) '资料失败 ${metadata.failed}',
      ]);
    }
    return parts.join(' · ');
  }

  bool get hasScanProblem =>
      _scanError != null ||
      _scanJobs.any((job) => job.status == 'interrupted') ||
      _processing.failed > 0 ||
      _metadata.failed > 0;

  void setThemeMode(ThemeMode value) {
    if (_themeMode == value) return;
    _themeMode = value;
    notifyListeners();
  }

  void clearCache() {
    final cache = PaintingBinding.instance.imageCache;
    cache.clear();
    cache.clearLiveImages();
    notifyListeners();
  }

  void startScan({VoidCallback? onComplete}) {
    if (isScanning) return;
    if (_scanRepository == null) {
      _scanError = '扫描服务不可用';
      notifyListeners();
      return;
    }
    unawaited(_startApiScan(onComplete));
  }

  Future<void> restoreScan() async {
    final repository = _scanRepository;
    if (repository == null || isScanning) return;
    final generation = ++_scanGeneration;
    try {
      final jobs = await repository.latestAll();
      if (generation != _scanGeneration) return;
      _scanJobs = jobs;
      if (jobs.isEmpty) return;
      final interrupted = jobs.where((job) => job.status == 'interrupted');
      if (interrupted.isNotEmpty) {
        _scanError = '扫描因服务器重启中断，请重新扫描';
      }
      final active = jobs.where(_requiresPolling).toList(growable: false);
      if (active.isEmpty) {
        _applyCompletedErrors(jobs);
        notifyListeners();
        return;
      }
      _scanProgress = _averageProgress(active);
      notifyListeners();
      final retained = jobs
          .where((job) => !_requiresPolling(job))
          .toList(growable: false);
      await _pollJobs(
        active.map((job) => job.id).toList(),
        null,
        generation,
        retained,
      );
    } on Object catch (error) {
      if (generation != _scanGeneration) return;
      _scanProgress = null;
      _scanError = error.toString();
      notifyListeners();
    }
  }

  Future<void> _startApiScan(VoidCallback? onComplete) async {
    final generation = ++_scanGeneration;
    _scanProgress = 0;
    _scanError = null;
    _scanDiscoveredCount = 0;
    notifyListeners();
    try {
      final jobs = await _scanRepository!.startAll();
      if (generation != _scanGeneration) return;
      if (jobs.isEmpty) throw StateError('没有可扫描的媒体源');
      _scanJobs = jobs;
      await _pollJobs(
        jobs.map((job) => job.id).toList(),
        onComplete,
        generation,
      );
    } on Object catch (error) {
      if (generation != _scanGeneration) return;
      _scanProgress = null;
      _scanError = error.toString();
      notifyListeners();
    }
  }

  Future<void> _pollJobs(
    List<String> ids,
    VoidCallback? onComplete, [
    int? generation,
    List<ScanJob> retainedJobs = const [],
  ]) async {
    final activeGeneration = generation ?? ++_scanGeneration;
    while (true) {
      await Future<void>.delayed(scanPollInterval);
      if (activeGeneration != _scanGeneration) return;
      final jobs = await Future.wait(ids.map(_scanRepository!.get));
      if (activeGeneration != _scanGeneration) return;
      _scanJobs = [...retainedJobs, ...jobs];
      _scanDiscoveredCount = jobs.fold(
        0,
        (total, job) => total + job.discoveredCount,
      );
      _scanProgress = _averageProgress(jobs);
      notifyListeners();
      if (jobs.every((job) => !_requiresPolling(job))) {
        final completedJobs = [...retainedJobs, ...jobs];
        _applyCompletedErrors(completedJobs);
        _scanProgress = null;
        notifyListeners();
        if (completedJobs.every((job) => job.status == 'completed')) {
          onComplete?.call();
        }
        return;
      }
    }
  }

  void resetConnection() {
    _scanGeneration++;
    _scanProgress = null;
    _scanError = null;
    _scanDiscoveredCount = 0;
    _scanJobs = const [];
    notifyListeners();
  }

  ProcessingSummary get _processing {
    final jobs = _scanJobs;
    return ProcessingSummary(
      status: jobs.any((job) => job.processing.status == 'running')
          ? 'running'
          : 'completed',
      total: jobs.fold(0, (total, job) => total + job.processing.total),
      discovered: jobs.fold(
        0,
        (total, job) => total + job.processing.discovered,
      ),
      probing: jobs.fold(0, (total, job) => total + job.processing.probing),
      thumbnailing: jobs.fold(
        0,
        (total, job) => total + job.processing.thumbnailing,
      ),
      ready: jobs.fold(0, (total, job) => total + job.processing.ready),
      failed: jobs.fold(0, (total, job) => total + job.processing.failed),
    );
  }

  MetadataSummary get _metadata {
    final jobs = _scanJobs;
    final active = jobs.any(
      (job) =>
          job.metadata.status == 'waiting' || job.metadata.status == 'running',
    );
    final failed = jobs.fold(0, (total, job) => total + job.metadata.failed);
    return MetadataSummary(
      status: active
          ? (jobs.any((job) => job.metadata.status == 'running')
                ? 'running'
                : 'waiting')
          : (failed > 0 ? 'completed_with_errors' : 'completed'),
      total: jobs.fold(0, (total, job) => total + job.metadata.total),
      pending: jobs.fold(0, (total, job) => total + job.metadata.pending),
      refreshing: jobs.fold(0, (total, job) => total + job.metadata.refreshing),
      ready: jobs.fold(0, (total, job) => total + job.metadata.ready),
      unmatched: jobs.fold(0, (total, job) => total + job.metadata.unmatched),
      failed: failed,
    );
  }

  bool get _isMetadataPhase =>
      _scanJobs.isNotEmpty &&
      _scanJobs.every(
        (job) =>
            job.status == 'completed' && job.processing.status != 'running',
      );

  static double _averageProgress(List<ScanJob> jobs) {
    // 媒体处理占前 70%，资料匹配占后 30%，各阶段均按后端总量加权。
    final total = jobs.fold(0, (sum, job) => sum + job.processing.total);
    final mediaProgress = total <= 0
        ? 1.0
        : (jobs.fold(
                    0,
                    (sum, job) =>
                        sum + job.processing.ready + job.processing.failed,
                  ) /
                  total)
              .clamp(0, 1);
    final mediaActive = jobs.any(
      (job) =>
          job.status == 'pending' ||
          job.status == 'running' ||
          job.processing.status == 'running',
    );
    if (mediaActive) return mediaProgress * 0.7;
    final metadata = jobs.fold<MetadataSummary>(
      const MetadataSummary.completed(),
      (value, job) => MetadataSummary(
        status: job.metadata.status,
        total: value.total + job.metadata.total,
        pending: value.pending + job.metadata.pending,
        refreshing: value.refreshing + job.metadata.refreshing,
        ready: value.ready + job.metadata.ready,
        unmatched: value.unmatched + job.metadata.unmatched,
        failed: value.failed + job.metadata.failed,
      ),
    );
    if (metadata.total <= 0) return 1;
    final completed = jobs.fold(
      0,
      (sum, job) =>
          sum +
          job.metadata.ready +
          job.metadata.unmatched +
          job.metadata.failed,
    );
    return 0.7 + 0.3 * (completed / metadata.total).clamp(0, 1);
  }

  static bool _requiresPolling(ScanJob job) {
    if (job.status == 'pending' || job.status == 'running') return true;
    return job.status == 'completed' &&
        (job.processing.status == 'running' ||
            job.metadata.status == 'waiting' ||
            job.metadata.status == 'running');
  }

  void _applyCompletedErrors(List<ScanJob> jobs) {
    final interrupted = jobs.any((job) => job.status == 'interrupted');
    if (interrupted) {
      _scanError = '扫描因服务器重启中断，请重新扫描';
      return;
    }
    final messages = <String>[];
    for (final job in jobs) {
      if (job.status != 'completed') {
        messages.add(job.errorMessage ?? job.status);
      } else if (job.processing.status == 'completed_with_errors') {
        messages.add('${job.processing.failed} 个媒体处理失败');
      }
      if (job.metadata.failed > 0) {
        messages.add('${job.metadata.failed} 部影视资料匹配失败');
      }
    }
    _scanError = messages.isEmpty ? null : messages.join('；');
  }

  @override
  void dispose() {
    _scanGeneration++;
    super.dispose();
  }
}
