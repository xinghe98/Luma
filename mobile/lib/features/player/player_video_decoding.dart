// 按 libmpv 实际视频参数判断 TV 的 Surface 输出色彩边界，供 PlayerController 使用。
// Surface 路径绕过 GPU 色彩处理；高位深、HDR 和未知格式保留兼容输出。
import 'package:media_kit/media_kit.dart';

/// 仅允许已确认的 8-bit BT.709 SDR 使用直接硬解，不根据分辨率或文件名猜测。
/// 缺少参数、较高位深或不同色域时返回 false，避免改变原有色彩处理。
bool supportsDirectTvDecoding(VideoParams params) =>
    const {
      'yuv420p',
      'yuvj420p',
      'nv12',
      'nv21',
    }.contains(params.pixelformat) &&
    params.primaries == 'bt.709' &&
    const {'bt.1886', 'srgb', 'gamma2.2', 'gamma2.8'}.contains(params.gamma) &&
    (params.sigPeak == null || params.sigPeak! <= 1.0) &&
    (params.rotate == null || params.rotate == 0);
