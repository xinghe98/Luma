// 将唯一的应用元数据源同步到 Flutter、Android 和 Windows 构建文件，避免各端显示信息漂移。
// 仅允许 app_metadata.json 被人工编辑；--check 用于构建前验证生成文件仍是最新状态。
import 'dart:convert';
import 'dart:io';

/// 同步应用元数据；传入 --check 时只校验生成结果，不会写入文件。
void main(List<String> arguments) {
  if (arguments.length > 1 ||
      (arguments.length == 1 && arguments.single != '--check')) {
    stderr.writeln('用法：dart run tool/sync_app_metadata.dart [--check]');
    exitCode = 64;
    return;
  }

  final mobileDirectory = File(Platform.script.toFilePath()).parent.parent;
  final metadata = _AppMetadata.read(
    File(_join(mobileDirectory.path, 'app_metadata.json')),
  );
  final expectedFiles = <String, String>{
    _join(mobileDirectory.path, 'pubspec.yaml'): _pubspec(
      File(_join(mobileDirectory.path, 'pubspec.yaml')).readAsStringSync(),
      metadata,
    ),
    _join(mobileDirectory.path, 'lib', 'app', 'app_metadata.g.dart'):
        _dartMetadata(metadata),
    _join(mobileDirectory.path, 'android', 'app', 'app_metadata.gradle.kts'):
        _androidGradleMetadata(metadata),
    _join(
      mobileDirectory.path,
      'android',
      'app',
      'src',
      'main',
      'res',
      'values',
      'app_metadata.xml',
    ): _androidStringMetadata(
      metadata,
    ),
    _join(mobileDirectory.path, 'windows', 'app_metadata.cmake'):
        _windowsCmakeMetadata(metadata),
    _join(mobileDirectory.path, 'windows', 'runner', 'app_metadata.h'):
        _windowsHeaderMetadata(metadata),
    _join(mobileDirectory.path, 'windows', 'WINDOWS-README.txt'):
        _windowsReadme(metadata),
  };

  final isCheck = arguments.isNotEmpty;
  final stalePaths = <String>[];
  for (final entry in expectedFiles.entries) {
    final file = File(entry.key);
    if (file.existsSync() && file.readAsStringSync() == entry.value) continue;
    if (isCheck) {
      stalePaths.add(file.path);
    } else {
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(entry.value);
      stdout.writeln('已同步 ${file.path}');
    }
  }

  if (stalePaths.isNotEmpty) {
    stderr.writeln('以下应用元数据生成文件不是最新：');
    for (final path in stalePaths) {
      stderr.writeln('- $path');
    }
    stderr.writeln('请执行：dart run tool/sync_app_metadata.dart');
    exitCode = 1;
  }
}

String _pubspec(String current, _AppMetadata metadata) {
  final namePattern = RegExp(r'^name:\s*[^\r\n]+$', multiLine: true);
  final versionPattern = RegExp(r'^version:\s*[^\r\n]+$', multiLine: true);
  final metadataCommentPattern = RegExp(
    r'^# 此文件由 tool/sync_app_metadata\.dart 从 app_metadata\.json 生成，请勿手工修改。(?: 元数据指纹：[^\r\n]+)?$',
    multiLine: true,
  );
  if (namePattern.allMatches(current).length != 1) {
    throw const FormatException('pubspec.yaml 必须且只能包含一个 name 字段。');
  }
  if (versionPattern.allMatches(current).length != 1) {
    throw const FormatException('pubspec.yaml 必须且只能包含一个 version 字段。');
  }
  if (metadataCommentPattern.allMatches(current).length != 1) {
    throw const FormatException('pubspec.yaml 缺少唯一的应用元数据生成标记。');
  }
  return current
      .replaceFirst(namePattern, 'name: ${metadata.projectName}')
      .replaceFirst(metadataCommentPattern, _generatedComment(metadata, '#'))
      .replaceFirst(versionPattern, 'version: ${metadata.version}');
}

String _dartMetadata(_AppMetadata metadata) =>
    '''${_generatedComment(metadata, '//')}
// 应用内展示信息、原生包标识和构建元数据均以该唯一来源为准。

/// 应用的统一展示与发行元数据。
abstract final class AppMetadata {
  static const projectName = '${_dartString(metadata.projectName)}';
  static const displayName = '${_dartString(metadata.displayName)}';
  static const productName = '${_dartString(metadata.productName)}';
  static const androidApplicationId = '${_dartString(metadata.androidApplicationId)}';
  static const windowsExecutableName = '${_dartString(metadata.windowsExecutableName)}';
  static const companyName = '${_dartString(metadata.companyName)}';
  static const authorName = '${_dartString(metadata.authorName)}';
  static const copyright = '${_dartString(metadata.copyright)}';
  static const version = '${_dartString(metadata.versionName)}';
  static const buildNumber = ${metadata.buildNumber};
}
''';

String _androidGradleMetadata(_AppMetadata metadata) =>
    '''${_generatedComment(metadata, '//')}
rootProject.extra["luma.appMetadata.applicationId"] = "${_gradleString(metadata.androidApplicationId)}"
''';

String _androidStringMetadata(_AppMetadata metadata) =>
    '''<?xml version="1.0" encoding="utf-8"?>
<!-- ${_generatedComment(metadata, '').trim()} -->
<resources>
    <string name="app_name">${_xmlString(metadata.displayName)}</string>
</resources>
''';

String _windowsCmakeMetadata(_AppMetadata metadata) =>
    '''${_generatedComment(metadata, '#')}
set(LUMA_EXECUTABLE_NAME "${_cmakeString(metadata.windowsExecutableName)}")
''';

String _windowsHeaderMetadata(_AppMetadata metadata) =>
    '''${_generatedComment(metadata, '//')}
#pragma once

#define LUMA_WINDOW_TITLE L"${_cppString(metadata.productName)}"
#define LUMA_COMPANY_NAME "${_cppString(metadata.companyName)}"
#define LUMA_FILE_DESCRIPTION "${_cppString(metadata.productName)}"
#define LUMA_INTERNAL_NAME "${_cppString(metadata.windowsExecutableName)}"
#define LUMA_LEGAL_COPYRIGHT "${_cppString(metadata.copyright)}"
#define LUMA_ORIGINAL_FILENAME "${_cppString(metadata.windowsExecutableName)}.exe"
#define LUMA_PRODUCT_NAME "${_cppString(metadata.productName)}"
''';

String _windowsReadme(_AppMetadata metadata) =>
    '''${metadata.productName} for Windows

支持系统：Windows 10/11 x64
启动方式：解压整个压缩包后运行 ${metadata.windowsExecutableName}.exe，请勿单独移动 exe 或 data、DLL 文件。
压缩包已包含应用所需的 Visual C++ x64 运行库。

播放器使用内置 media_kit/libmpv 解码能力，直接播放服务端提供的认证媒体流。
首次运行请填写 ${metadata.companyName} 服务端地址、端口、用户名和密码。

快捷键：
Ctrl+F          打开搜索
Alt+Left        返回
Space / K       播放或暂停
Left / Right    快退或快进 10 秒
Up / Down       音量增减 5%
M               静音
F               切换全屏
Esc             退出全屏或关闭播放器

字体许可位于压缩包根目录的 MiSans-LICENSE.pdf。
第三方软件声明由 Flutter 生成在 data\\flutter_assets\\NOTICES.Z。

${_generatedComment(metadata, '')}
''';

String _generatedComment(_AppMetadata metadata, String prefix) =>
    '$prefix 此文件由 tool/sync_app_metadata.dart 从 app_metadata.json 生成，请勿手工修改。 元数据指纹：${metadata.sourceFingerprint}';

String _join(
  String first, [
  String? second,
  String? third,
  String? fourth,
  String? fifth,
  String? sixth,
  String? seventh,
  String? eighth,
]) {
  final parts = <String>[
    first,
    ...[
      second,
      third,
      fourth,
      fifth,
      sixth,
      seventh,
      eighth,
    ].whereType<String>(),
  ];
  return parts.join(Platform.pathSeparator);
}

String _dartString(String value) => value
    .replaceAll('\\', r'\\')
    .replaceAll("'", r"\'")
    .replaceAll('\n', r'\n')
    .replaceAll('\r', r'\r');

String _gradleString(String value) => value
    .replaceAll('\\', r'\\')
    .replaceAll('"', r'\"')
    .replaceAll(r'$', r'\$');

String _xmlString(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;');

String _cmakeString(String value) =>
    value.replaceAll('\\', r'\\').replaceAll('"', r'\"');

String _cppString(String value) => value
    .replaceAll('\\', r'\\')
    .replaceAll('"', r'\"')
    .replaceAll('\n', r'\n')
    .replaceAll('\r', r'\r');

class _AppMetadata {
  const _AppMetadata({
    required this.projectName,
    required this.displayName,
    required this.productName,
    required this.androidApplicationId,
    required this.windowsExecutableName,
    required this.companyName,
    required this.authorName,
    required this.copyright,
    required this.version,
    required this.sourceFingerprint,
  });

  final String projectName;
  final String displayName;
  final String productName;
  final String androidApplicationId;
  final String windowsExecutableName;
  final String companyName;
  final String authorName;
  final String copyright;
  final String version;
  final String sourceFingerprint;

  String get versionName => version.split('+').first;
  int get buildNumber => int.parse(version.split('+').last);

  static _AppMetadata read(File file) {
    final source = file.readAsStringSync();
    final decoded = jsonDecode(source);
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('app_metadata.json 的根节点必须是对象。');
    }
    final metadata = _AppMetadata(
      projectName: _requiredString(decoded, 'projectName'),
      displayName: _requiredString(decoded, 'displayName'),
      productName: _requiredString(decoded, 'productName'),
      androidApplicationId: _requiredString(decoded, 'androidApplicationId'),
      windowsExecutableName: _requiredString(decoded, 'windowsExecutableName'),
      companyName: _requiredString(decoded, 'companyName'),
      authorName: _requiredString(decoded, 'authorName'),
      copyright: _requiredString(decoded, 'copyright'),
      version: _requiredString(decoded, 'version'),
      sourceFingerprint: base64Url.encode(utf8.encode(source)),
    );
    metadata._validate();
    return metadata;
  }

  void _validate() {
    if (!RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(projectName)) {
      throw const FormatException('projectName 只能使用小写字母、数字和下划线。');
    }
    if (!RegExp(
      r'^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z][A-Za-z0-9_]*)+$',
    ).hasMatch(androidApplicationId)) {
      throw const FormatException('androidApplicationId 不是有效的 Android 应用标识。');
    }
    if (!RegExp(
      r'^[A-Za-z0-9][A-Za-z0-9._-]*$',
    ).hasMatch(windowsExecutableName)) {
      throw const FormatException(
        'windowsExecutableName 包含 Windows 文件名不支持的字符。',
      );
    }
    if (!RegExp(
      r'^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?\+[1-9]\d*$',
    ).hasMatch(version)) {
      throw const FormatException('version 必须符合 Flutter 的 x.y.z+构建号格式。');
    }
  }
}

String _requiredString(Map<String, Object?> value, String key) {
  final field = value[key];
  if (field is! String) {
    throw FormatException('app_metadata.json 缺少字符串字段：$key。');
  }
  return field;
}
