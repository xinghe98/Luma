import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

typedef XrayRawInvoker = Future<String> Function(String requestJson);

typedef _CGoInvokeNative = Pointer<Utf8> Function(Pointer<Utf8> request);
typedef _CGoInvokeDart = Pointer<Utf8> Function(Pointer<Utf8> request);
typedef _CGoFreeNative = Void Function(Pointer<Utf8> value);
typedef _CGoFreeDart = void Function(Pointer<Utf8> value);

/// 对外只暴露可恢复的固定错误，不携带原生错误、分享链接或节点凭据。
final class XrayBridgeException implements Exception {
  const XrayBridgeException([this.message = serviceUnavailableMessage]);

  /// 原生桥、通道或 envelope 异常时的通用提示。
  static const serviceUnavailableMessage = '代理服务暂时不可用，请重试';

  /// 分享链接转换失败时的提示（不回传原生 error 细节）。
  static const invalidShareLinkMessage = 'VMess 分享链接无效';

  final String message;

  @override
  String toString() => message;
}

/// libXray invoke API v1 的串行、安全封装。
final class XrayBridge {
  XrayBridge({XrayRawInvoker? rawInvoker})
    : _rawInvoker = rawInvoker ?? _platformInvoke;

  static const supportedMethods = <String>{
    'convertShareLinksToXrayJson',
    'getFreePorts',
    'runXrayFromJson',
    'getXrayState',
    'stopXray',
    'xrayVersion',
  };
  static const _channel = MethodChannel('com.luma.luma/xray');

  final XrayRawInvoker _rawInvoker;
  Future<void> _tail = Future<void>.value();

  Future<Object?> invoke(
    String method, [
    Map<String, Object?> payload = const {},
  ]) {
    if (!supportedMethods.contains(method)) {
      return Future<Object?>.error(const XrayBridgeException());
    }
    return _serialized(() async {
      final request = jsonEncode({
        'apiVersion': 1,
        'method': method,
        'payload': payload,
      });
      String response;
      try {
        response = await _rawInvoker(request);
      } catch (_) {
        throw const XrayBridgeException();
      }
      return _decodeEnvelope(response, method: method);
    });
  }

  Future<T> _serialized<T>(Future<T> Function() operation) {
    final completer = Completer<T>();
    _tail = _tail.then((_) async {
      try {
        completer.complete(await operation());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  static Object? _decodeEnvelope(String response, {required String method}) {
    try {
      final decoded = jsonDecode(response);
      if (decoded is! Map<String, dynamic> ||
          decoded['success'] is! bool ||
          !decoded.containsKey('data') ||
          decoded['error'] is! String) {
        throw const FormatException();
      }
      if (decoded['success'] != true) {
        throw XrayBridgeException(_logicalFailureMessage(method));
      }
      return decoded['data'];
    } on XrayBridgeException {
      rethrow;
    } catch (_) {
      throw const XrayBridgeException();
    }
  }

  /// convert 逻辑失败与桥本身故障分流；仍不透出原生 error 文本。
  static String _logicalFailureMessage(String method) {
    if (method == 'convertShareLinksToXrayJson') {
      return XrayBridgeException.invalidShareLinkMessage;
    }
    return XrayBridgeException.serviceUnavailableMessage;
  }

  static Future<String> _platformInvoke(String request) async {
    if (kIsWeb) throw const XrayBridgeException();
    if (Platform.isAndroid) {
      final response = await _channel.invokeMethod<String>('invoke', request);
      if (response == null) throw const XrayBridgeException();
      return response;
    }
    if (Platform.isWindows) {
      return Isolate.run(() => _invokeWindows(request));
    }
    throw const XrayBridgeException();
  }
}

String _invokeWindows(String request) {
  final executableDirectory = File(Platform.resolvedExecutable).parent.path;
  final dllPath = '$executableDirectory${Platform.pathSeparator}libXray.dll';
  final library = DynamicLibrary.open(dllPath);
  final invoke = library.lookupFunction<_CGoInvokeNative, _CGoInvokeDart>(
    'CGoInvoke',
  );
  final free = library.lookupFunction<_CGoFreeNative, _CGoFreeDart>('CGoFree');
  final input = request.toNativeUtf8(allocator: calloc);
  Pointer<Utf8> output = nullptr;
  try {
    output = invoke(input);
    if (output == nullptr) throw const XrayBridgeException();
    return output.toDartString();
  } finally {
    calloc.free(input);
    if (output != nullptr) free(output);
  }
}
