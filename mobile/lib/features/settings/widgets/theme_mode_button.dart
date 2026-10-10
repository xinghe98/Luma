// 设置页右上角的主题切换按钮：图标反映当前模式，点开菜单在三种模式间选择。
// 不持有状态，选中值与变更回调由 SettingsController 提供；持久化在控制器内完成。
import 'package:flutter/material.dart';

/// 主题模式菜单按钮；图标随 [value] 变化，菜单项带勾选态。
class ThemeModeButton extends StatelessWidget {
  const ThemeModeButton({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final ThemeMode value;

  /// 用户选中某个模式时调用，即使与当前值相同也不会重复写入（由控制器去重）。
  final ValueChanged<ThemeMode> onChanged;

  static const _options = [
    (ThemeMode.system, '跟随系统', Icons.brightness_auto_rounded),
    (ThemeMode.light, '浅色', Icons.light_mode_outlined),
    (ThemeMode.dark, '深色', Icons.dark_mode_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    final current = _options.firstWhere((option) => option.$1 == value);
    return MenuAnchor(
      menuChildren: [
        for (final (mode, label, icon) in _options)
          MenuItemButton(
            leadingIcon: Icon(icon),
            trailingIcon: mode == value
                ? const Icon(Icons.check_rounded)
                : null,
            onPressed: () => onChanged(mode),
            child: Text(label),
          ),
      ],
      builder: (context, menu, _) => IconButton(
        tooltip: '主题：${current.$2}',
        icon: Icon(current.$3),
        onPressed: () => menu.isOpen ? menu.close() : menu.open(),
      ),
    );
  }
}
