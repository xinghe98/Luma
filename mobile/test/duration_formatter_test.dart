// 播放器时钟标签在零值、负值和跨小时时仍保持可读。
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/shared/formatters/duration_formatter.dart';

void main() {
  test('formatClock 零值显示 00:00，卡片时长零值仍隐藏', () {
    expect(formatClock(Duration.zero), '00:00');
    expect(formatDuration(Duration.zero), '');
  });

  test('formatClock 负值按 0 处理', () {
    expect(formatClock(const Duration(seconds: -3)), '00:00');
  });

  test('formatClock 跨小时使用 h:mm:ss', () {
    expect(formatClock(const Duration(hours: 1, seconds: 5)), '1:00:05');
    expect(formatClock(const Duration(minutes: 9, seconds: 7)), '09:07');
  });
}
