// 设置状态组件测试覆盖可配置错误文案和大字体弹窗布局。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/features/settings/dialogs/server_alias_dialog.dart';
import 'package:luma/shared/states/error_state.dart';

void main() {
  testWidgets('error state exposes page-specific copy', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ErrorState(
          title: '刷新失败',
          message: '仍显示旧内容',
          retryLabel: '再试一次',
          onRetry: () {},
        ),
      ),
    );

    expect(find.text('刷新失败'), findsOneWidget);
    expect(find.text('仍显示旧内容'), findsOneWidget);
    expect(find.text('再试一次'), findsOneWidget);
  });

  testWidgets('server alias dialog wraps actions at large text scale', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2.5)),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showServerAliasDialog(context, '家庭服务器'),
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    expect(find.text('恢复默认'), findsOneWidget);
    expect(find.text('保存'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
