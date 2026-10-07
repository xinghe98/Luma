// 验证 TV 直接硬解的色彩边界，防止未知参数或 HDR 被转为低位深输出。
// 只使用 libmpv 参数模型，不创建播放器或平台资源。
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/features/player/player_video_decoding.dart';
import 'package:media_kit/media_kit.dart';

void main() {
  VideoParams params({
    String? format = 'yuv420p',
    String? primaries = 'bt.709',
    String? gamma = 'bt.1886',
    double? peak,
    int? rotation,
  }) => VideoParams(
    pixelformat: format,
    primaries: primaries,
    gamma: gamma,
    sigPeak: peak,
    rotate: rotation,
  );

  test('已确认的 8-bit SDR 可尝试直接路径', () {
    for (final format in ['yuv420p', 'yuvj420p', 'nv12', 'nv21']) {
      expect(supportsDirectTvDecoding(params(format: format)), isTrue);
    }
  });

  test('10-bit、HDR 与广色域保留兼容路径', () {
    for (final value in [
      params(format: 'yuv420p10le'),
      params(format: 'p010'),
      params(primaries: 'bt.2020', gamma: 'pq'),
      params(gamma: 'hlg'),
      params(primaries: 'display-p3'),
      params(peak: 10),
    ]) {
      expect(supportsDirectTvDecoding(value), isFalse);
    }
  });

  test('缺失或未知参数不能据此假定是安全 SDR', () {
    for (final value in [
      const VideoParams(),
      params(format: null),
      params(primaries: null),
      params(gamma: null),
      params(format: 'mediacodec'),
      params(format: 'rgb0'),
      params(gamma: 'auto'),
    ]) {
      expect(supportsDirectTvDecoding(value), isFalse);
    }
  });

  test('旋转视频保留兼容输出', () {
    expect(supportsDirectTvDecoding(params(rotation: 0)), isTrue);
    for (final rotation in [90, 180, 270]) {
      expect(supportsDirectTvDecoding(params(rotation: rotation)), isFalse);
    }
  });
}
