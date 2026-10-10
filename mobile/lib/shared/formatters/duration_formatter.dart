/// 格式化媒体时长；零值返回空串，供卡片与元数据「没有时长就不显示」。
String formatDuration(Duration duration) {
  if (duration == Duration.zero) return '';
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
}

/// 格式化播放器时钟标签；零值返回 '00:00'，负值按 0 处理。
/// 与 [formatDuration] 分离是因为播放器在 0:00 也必须显示可读标签。
String formatClock(Duration duration) {
  final d = duration.isNegative ? Duration.zero : duration;
  final hours = d.inHours;
  final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
}
