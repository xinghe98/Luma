// 验证 SearchInput 与 LumaTheme 在手机和宽屏约束下的文字布局，并在每次测试后还原窗口尺寸。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/core/theme.dart';
import 'package:luma/features/search/widgets/search_input.dart';

void main() {
  const viewports = <(String, Size)>[
    ('手机', Size(390, 844)),
    ('Windows 宽屏', Size(1200, 800)),
  ];

  for (final (name, size) in viewports) {
    testWidgets('搜索框中文字在$name下保持垂直居中', (tester) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final controller = TextEditingController(text: '中文字');
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: LumaTheme.light(),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: size.width > 720 ? 720 : size.width - 32,
                child: SearchInput(
                  textController: controller,
                  onChanged: (_) {},
                  onSubmitted: (_) {},
                  onClear: controller.clear,
                ),
              ),
            ),
          ),
        ),
      );

      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.textAlignVertical, TextAlignVertical.center);

      final frameCenter = tester.getCenter(
        find.byKey(const ValueKey('search-input-frame')),
      );
      final editableCenter = tester.getCenter(find.byType(EditableText));
      expect((frameCenter.dy - editableCenter.dy).abs(), lessThan(0.5));
      expect(tester.takeException(), isNull);
    });
  }
}
