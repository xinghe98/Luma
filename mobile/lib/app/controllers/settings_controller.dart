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

  ThemeMode get themeMode => _themeMode;
  double get cacheSizeMb =>
      PaintingBinding.instance.imageCache.currentSizeBytes / 1048576;
  double? get scanProgress => _scanProgress;
  bool get isScanning => _scanProgress != null;
  String? get scanError => _scanError;
  int get scanDiscoveredCount => _scanDiscoveredCount;

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

  // Aggregates multiple source jobs into the existing single progress value.
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
    notifyListeners();
  }

  static double _averageProgress(List<ScanJob> jobs) {
    // 后端 total/ready/failed 都以本次扫描中的单个媒体为单位，按总量加权。
    final total = jobs.fold(0, (sum, job) => sum + job.processing.total);
    if (total <= 0) return 0;
    final completed = jobs.fold(
      0,
      (sum, job) => sum + job.processing.ready + job.processing.failed,
    );
    return (completed / total).clamp(0, 1);
  }

  static bool _requiresPolling(ScanJob job) {
    if (job.status == 'pending' || job.status == 'running') return true;
    return job.status == 'completed' && job.processing.status == 'running';
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
    }
    _scanError = messages.isEmpty ? null : messages.join('；');
  }

  @override
  void dispose() {
    _scanGeneration++;
    super.dispose();
  }
}
