// 音轨/字幕轨的展示文案：优先使用媒体自带的标题，其次按语言代码映射为中文，
// 都缺失时按序号兜底。供播放器控制层与 TV 控制层共用，无状态、无依赖。

/// 生成一条轨道的展示名称。
/// [title] 非空时直接使用；[language] 为 ISO 语言代码，映射到中文名；
/// 两者都为空时返回 `'$fallbackPrefix ${index + 1}'`。
/// title 与 language 同时存在且语言名与标题不完全相同时，返回 `'$title（$语言）'`。
String trackLabel({
  String? title,
  String? language,
  required int index,
  required String fallbackPrefix,
}) {
  final name = title?.trim();
  final lang = language?.trim();
  final langName = lang == null ? null : _languageName(lang);
  if (name != null && name.isNotEmpty) {
    if (langName != null && langName != name) return '$name（$langName）';
    return name;
  }
  if (langName != null) return langName;
  return '$fallbackPrefix ${index + 1}';
}

/// 把常见语言代码映射为中文名；无法识别时返回大写原码。
String _languageName(String code) {
  switch (code.toLowerCase()) {
    case 'chi':
    case 'zho':
    case 'zh':
      return '中文';
    case 'eng':
    case 'en':
      return '英语';
    case 'jpn':
    case 'ja':
      return '日语';
    case 'kor':
    case 'ko':
      return '韩语';
    default:
      return code.toUpperCase();
  }
}
