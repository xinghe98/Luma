import 'dart:convert';
import 'dart:math';

import 'xray_bridge.dart';

final class VmessProxyProfile {
  const VmessProxyProfile({
    required this.id,
    required this.displayName,
    required this.shareLink,
  });

  final String id;
  final String displayName;
  final String shareLink;

  Map<String, Object?> toJson() => {
    'id': id,
    'display_name': displayName,
    'share_link': shareLink,
  };

  static VmessProxyProfile fromJson(Object? value) {
    if (value is! Map) throw const FormatException('代理配置格式无效');
    final id = value['id'];
    final displayName = value['display_name'];
    final shareLink = value['share_link'];
    if (id is! String ||
        id.isEmpty ||
        displayName is! String ||
        displayName.isEmpty ||
        shareLink is! String ||
        shareLink.isEmpty) {
      throw const FormatException('代理配置格式无效');
    }
    return VmessProxyProfile(
      id: id,
      displayName: displayName,
      shareLink: shareLink,
    );
  }
}

final class ParsedVmessOutbound {
  const ParsedVmessOutbound({
    required this.displayName,
    required this.outbound,
  });

  final String displayName;
  final Map<String, Object?> outbound;
}

/// 分享链接输入门禁与 libXray 转换结果的最小权限解析器。
final class VmessProfileParser {
  const VmessProfileParser(this._bridge);

  static const maxLinkLength = 32 * 1024;
  static const maxDisplayNameLength = 80;
  final XrayBridge _bridge;

  Future<VmessProxyProfile> createProfile(String clipboardText) async {
    final link = normalizeLink(clipboardText);
    final parsed = await parseOutbound(link);
    return VmessProxyProfile(
      id: _randomId(),
      displayName: parsed.displayName,
      shareLink: link,
    );
  }

  Future<ParsedVmessOutbound> parseOutbound(String shareLink) async {
    final link = normalizeLink(shareLink);
    final converted = await _bridge.invoke('convertShareLinksToXrayJson', {
      'text': link,
    });
    if (converted is! Map) {
      throw const XrayBridgeException(
        XrayBridgeException.invalidShareLinkMessage,
      );
    }
    final outbounds = converted['outbounds'];
    if (outbounds is! List || outbounds.length != 1) {
      throw const XrayBridgeException(
        XrayBridgeException.invalidShareLinkMessage,
      );
    }
    final rawOutbound = outbounds.single;
    if (rawOutbound is! Map ||
        rawOutbound['protocol'] != 'vmess' ||
        rawOutbound['settings'] is! Map) {
      throw const XrayBridgeException(
        XrayBridgeException.invalidShareLinkMessage,
      );
    }

    final outbound = _stringKeyedCopy(rawOutbound);
    final suppliedName = outbound.remove('sendThrough');
    final address = _extractAddress(outbound);
    final displayName = _sanitizeDisplayName(
      suppliedName is String && suppliedName.trim().isNotEmpty
          ? suppliedName
          : address,
    );
    if (displayName.isEmpty) {
      throw const XrayBridgeException(
        XrayBridgeException.invalidShareLinkMessage,
      );
    }
    return ParsedVmessOutbound(displayName: displayName, outbound: outbound);
  }

  static String normalizeLink(String value) {
    // 先拦多行，避免后续去控制字符时把换行吃掉拼成一行。
    if (value.contains('\n') || value.contains('\r')) {
      throw const XrayBridgeException('请粘贴单条 VMess 分享链接');
    }
    final link = _sanitizeClipboardLink(value);
    if (link.isEmpty ||
        link.length > maxLinkLength ||
        !link.startsWith('vmess://')) {
      throw const XrayBridgeException('请粘贴单条 VMess 分享链接');
    }
    final uri = Uri.tryParse(link);
    if (uri == null || uri.scheme != 'vmess') {
      throw const XrayBridgeException('请粘贴单条 VMess 分享链接');
    }
    return _rewriteLegacyCipherUserinfoLink(link) ?? link;
  }

  /// 去掉剪贴板常见杂质：BOM、零宽字符、首尾空白与尾部中英文标点。
  static String _sanitizeClipboardLink(String value) {
    var text = value.replaceAll(RegExp(r'[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f-\u009f]'), '');
    text = text.replaceAll(RegExp(r'[\u200b-\u200d\ufeff\u2060]'), '');
    text = text.trim();
    // 聊天复制时常带句读：vmess://...。 / ...，
    text = text.replaceFirst(
      RegExp(r'''[,\.;:，。；：、！？!?'"”’》〉】）)\]]+$'''),
      '',
    );
    return text.trim();
  }

  /// 兼容少数客户端导出的非标准形态：
  /// `vmess://base64(scy:uuid@host:port)` → 标准明文
  /// `vmess://uuid@host:port?encryption=scy`，再交给 libXray。
  /// Base64 解出 JSON QR 或无法识别时原样返回。
  static String? _rewriteLegacyCipherUserinfoLink(String link) {
    final payload = link.substring('vmess://'.length);
    if (payload.isEmpty || payload.contains('@') || payload.contains('?')) {
      return null;
    }

    final decoded = _tryDecodeBase64Utf8(payload);
    if (decoded == null) return null;
    final text = decoded.trim();
    if (text.isEmpty || text.startsWith('{')) return null;

    final match = _legacyCipherUserinfoPattern.firstMatch(text);
    if (match == null) return null;

    final security = match.group(1)!;
    final id = match.group(2)!;
    final host = match.group(3)!;
    final port = int.tryParse(match.group(4)!);
    if (port == null || port < 1 || port > 65535) return null;
    if (host.startsWith('[') && host.endsWith(']')) {
      // IPv6 literal already bracketed.
    } else if (host.contains(':') && !host.startsWith('[')) {
      return null;
    }

    return Uri(
      scheme: 'vmess',
      userInfo: id,
      host: host.startsWith('[') && host.endsWith(']')
          ? host.substring(1, host.length - 1)
          : host,
      port: port,
      queryParameters: {'encryption': security},
    ).toString();
  }

  static final RegExp _legacyCipherUserinfoPattern = RegExp(
    r'^([A-Za-z0-9_+\-]+):'
    r'([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})@'
    r'(\[[0-9a-fA-F:]+\]|[^:@\s/]+):'
    r'(\d{1,5})$',
  );

  static String? _tryDecodeBase64Utf8(String value) {
    final normalized = value.replaceAll(RegExp(r'\s'), '');
    if (normalized.isEmpty) return null;
    final padded = normalized.padRight(
      normalized.length + ((4 - normalized.length % 4) % 4),
      '=',
    );
    for (final decoder in [base64.decode, base64Url.decode]) {
      try {
        final bytes = decoder(padded);
        if (bytes.isEmpty) continue;
        return utf8.decode(bytes);
      } on FormatException {
        continue;
      }
    }
    return null;
  }

  static Map<String, Object?> _stringKeyedCopy(Map<dynamic, dynamic> value) {
    final decoded = jsonDecode(jsonEncode(value));
    if (decoded is! Map<String, dynamic>) {
      throw const XrayBridgeException(
        XrayBridgeException.invalidShareLinkMessage,
      );
    }
    return decoded;
  }

  static String _extractAddress(Map<String, Object?> outbound) {
    final settings = outbound['settings'];
    if (settings is! Map) return '';
    final directAddress = settings['address'];
    if (directAddress is String) return directAddress;
    final servers = settings['vnext'];
    if (servers is List && servers.isNotEmpty && servers.first is Map) {
      final address = (servers.first as Map)['address'];
      if (address is String) return address;
    }
    return '';
  }

  static String _sanitizeDisplayName(String value) {
    final withoutControls = value.replaceAll(
      RegExp(r'[\x00-\x1f\x7f-\x9f]'),
      ' ',
    );
    final compact = withoutControls.replaceAll(RegExp(r'\s+'), ' ').trim();
    return String.fromCharCodes(compact.runes.take(maxDisplayNameLength));
  }

  static String _randomId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }
}
