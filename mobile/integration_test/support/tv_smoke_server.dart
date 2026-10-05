// TV 冒烟测试后端：真实 loopback HTTP 服务器，提供鉴权视频流与测试图片。
// 责任：仅服务内存测试数据——GET/HEAD、单段 Range 206、越界 416、缺 token 401；
// 生命周期：在测试内 start() 后使用，测试 finally 中 close()，不留监听端口。
// 视频字节来自 fixtures/tv_smoke_clip.dart，图片为运行时合成的双色棋盘 PNG。
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

/// 所有 /api/ 请求必须携带的固定测试 token；测试连接服务把它写进 ApiSession。
const String kTvSmokeToken = 'tv-smoke-token';

/// 视频流的相对路径模板；媒体仓储用同一规则生成 streamUrl。
String tvSmokeStreamPath(String mediaId) => '/api/media/$mediaId/stream';

/// 缩略图与海报等图片的相对路径模板。
String tvSmokeImagePath(String assetName) => '/api/img/$assetName.png';

/// 冒烟测试后端：绑定 127.0.0.1 随机端口，统计请求供断言原生播放链路。
final class TvSmokeServer {
  TvSmokeServer({required List<int> videoBytes, required int imageCount})
    : videoBytes = Uint8List.fromList(videoBytes) {
    for (var i = 0; i < imageCount; i++) {
      final name = 'asset-$i';
      // 双色棋盘在截图中易于辨认，避免把纯色图片误认为背景或占位。
      _images[tvSmokeImagePath(name)] = _encodeTestPng(
        width: 96,
        height: 64,
        r: 40 + (i * 37) % 200,
        g: 60 + (i * 53) % 180,
        b: 90 + (i * 71) % 160,
      );
    }
  }

  final Uint8List videoBytes;
  final Map<String, List<int>> _images = {};
  HttpServer? _server;

  /// 统计：流请求数、带 Range 的流请求数、图片请求数、缺 token 请求数。
  int streamRequests = 0;
  int rangeRequests = 0;
  int imageRequests = 0;
  int authFailures = 0;

  bool get isRunning => _server != null;

  /// 服务端口；必须在 start() 之后读取。
  int get port => _server!.port;

  /// 测试服务 origin；测试连接服务把它写入 ApiSession。
  String get origin => 'http://127.0.0.1:$port';

  /// 启动监听；重复调用为空操作。
  Future<void> start() async {
    if (_server != null) return;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server = server;
    server.listen(_handle, onError: (_) {});
  }

  /// 关闭监听并断开在途连接；重复调用为空操作。
  Future<void> close() async {
    final server = _server;
    _server = null;
    await server?.close(force: true);
  }

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    if (request.method != 'GET' && request.method != 'HEAD') {
      response.statusCode = HttpStatus.methodNotAllowed;
      response.headers.set(HttpHeaders.allowHeader, 'GET, HEAD');
      await response.close();
      return;
    }
    final auth = request.headers.value(HttpHeaders.authorizationHeader);
    if (auth != 'Bearer $kTvSmokeToken') {
      authFailures++;
      response.statusCode = HttpStatus.unauthorized;
      await response.close();
      return;
    }
    final path = request.uri.path;
    if (path.endsWith('/stream') && path.startsWith('/api/media/')) {
      streamRequests++;
      if (request.headers.value(HttpHeaders.rangeHeader) != null) {
        rangeRequests++;
      }
      await _serveBytes(request, response, videoBytes, 'video/mp4');
      return;
    }
    final image = _images[path];
    if (image != null) {
      imageRequests++;
      await _serveBytes(request, response, image, 'image/png');
      return;
    }
    response.statusCode = HttpStatus.notFound;
    await response.close();
  }

  /// 输出字节流：无 Range 返回 200 全量；单段 Range 返回 206；
  /// 越界或多段 Range 返回 416；HEAD 只给头部。
  Future<void> _serveBytes(
    HttpRequest request,
    HttpResponse response,
    List<int> bytes,
    String contentType,
  ) async {
    final length = bytes.length;
    response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
    response.headers.set(HttpHeaders.contentTypeHeader, contentType);
    final rangeHeader = request.headers.value(HttpHeaders.rangeHeader);
    int start;
    int end;
    if (rangeHeader == null) {
      start = 0;
      end = length - 1;
      response.statusCode = HttpStatus.ok;
      response.headers.set(HttpHeaders.contentLengthHeader, '$length');
      if (request.method == 'HEAD') {
        await response.close();
        return;
      }
      await response.addStream(Stream.value(bytes));
      await response.close();
      return;
    }
    final match = RegExp(r'^bytes=(\d*)-(\d*)$').firstMatch(rangeHeader);
    if (match == null || (match.group(1)!.isEmpty && match.group(2)!.isEmpty)) {
      response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
      response.headers.set(HttpHeaders.contentRangeHeader, 'bytes */$length');
      await response.close();
      return;
    }
    final startText = match.group(1)!;
    final endText = match.group(2)!;
    if (startText.isEmpty) {
      // 后缀语义 bytes=-N：取末尾 N 字节。
      final suffix = int.parse(endText);
      if (suffix <= 0) {
        response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
        response.headers.set(HttpHeaders.contentRangeHeader, 'bytes */$length');
        await response.close();
        return;
      }
      start = max(0, length - suffix);
      end = length - 1;
    } else {
      start = int.parse(startText);
      end = endText.isEmpty ? length - 1 : min(int.parse(endText), length - 1);
    }
    if (length == 0 || start >= length || start > end) {
      response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
      response.headers.set(HttpHeaders.contentRangeHeader, 'bytes */$length');
      await response.close();
      return;
    }
    response.statusCode = HttpStatus.partialContent;
    final slice = Uint8List.sublistView(
      Uint8List.fromList(bytes),
      start,
      end + 1,
    );
    response.headers.set(
      HttpHeaders.contentRangeHeader,
      'bytes $start-$end/$length',
    );
    response.headers.set(HttpHeaders.contentLengthHeader, '${slice.length}');
    if (request.method == 'HEAD') {
      await response.close();
      return;
    }
    await response.addStream(Stream.value(slice));
    await response.close();
  }
}

/// 生成双色棋盘 PNG；不依赖 dart:ui，可在任意测试环境确定性构造。
Uint8List _encodeTestPng({
  required int width,
  required int height,
  required int r,
  required int g,
  required int b,
}) {
  final stride = width * 3;
  final raw = Uint8List(height * (stride + 1));
  for (var y = 0; y < height; y++) {
    final row = y * (stride + 1);
    raw[row] = 0; // 过滤器类型 0：None。
    for (var x = 0; x < width; x++) {
      final offset = row + 1 + x * 3;
      final alternate = (x ~/ 12 + y ~/ 8).isOdd;
      raw[offset] = alternate ? 255 - r : r;
      raw[offset + 1] = alternate ? 255 - g : g;
      raw[offset + 2] = alternate ? 255 - b : b;
    }
  }
  final idat = ZLibEncoder(level: 6).convert(raw);
  final chunks = BytesBuilder();
  chunks.add(_pngChunk('IHDR', _ihdr(width, height)));
  chunks.add(_pngChunk('IDAT', idat));
  chunks.add(_pngChunk('IEND', const []));
  final out = BytesBuilder();
  out.add(
    Uint8List.fromList(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]),
  );
  out.add(chunks.takeBytes());
  return out.takeBytes();
}

/// 组装 IHDR 块：8 位真彩色（颜色类型 2），无隔行。
Uint8List _ihdr(int width, int height) {
  final data = ByteData(13);
  data.setUint32(0, width);
  data.setUint32(4, height);
  data.setUint8(8, 8); // 位深
  data.setUint8(9, 2); // 颜色类型：RGB
  data.setUint8(10, 0); // 压缩
  data.setUint8(11, 0); // 过滤
  data.setUint8(12, 0); // 隔行
  return data.buffer.asUint8List();
}

/// 按块长度 + 类型 + 数据 + CRC 组装 PNG 块。
Uint8List _pngChunk(String type, List<int> payload) {
  final builder = BytesBuilder();
  final header = ByteData(4)..setUint32(0, payload.length);
  builder.add(header.buffer.asUint8List());
  final typeBytes = Uint8List.fromList(type.codeUnits);
  builder.add(typeBytes);
  builder.add(payload);
  final crcInput = BytesBuilder();
  crcInput.add(typeBytes);
  crcInput.add(payload);
  final crc = ByteData(4)..setUint32(0, _crc32(crcInput.takeBytes()));
  builder.add(crc.buffer.asUint8List());
  return builder.takeBytes();
}

/// 标准 CRC32（PNG 块校验用）。
int _crc32(List<int> bytes) {
  const polynomial = 0xEDB88320;
  final table = List<int>.generate(256, (index) {
    var value = index;
    for (var bit = 0; bit < 8; bit++) {
      value = (value & 1) == 1 ? (value >>> 1) ^ polynomial : value >>> 1;
    }
    return value;
  });
  var crc = 0xFFFFFFFF;
  for (final byte in bytes) {
    crc = table[(crc ^ byte) & 0xFF] ^ (crc >>> 8);
  }
  return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}
