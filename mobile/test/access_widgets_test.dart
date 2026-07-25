// 登录设备组件测试确保永久会话不会被当成已过期或触发空值错误。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/data/models/api_access.dart';
import 'package:luma/features/settings/access/access_widgets.dart';

void main() {
  testWidgets('永久会话显示为长期有效', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LoginSessionTile(
            session: LoginSession(
              id: 'session-1',
              userId: 'user-1',
              name: '测试设备',
              expiresAt: null,
              revokedAt: null,
              createdAt: DateTime.utc(2026, 7, 25),
            ),
            revoking: false,
            onRevoke: () {},
          ),
        ),
      ),
    );

    expect(find.text('长期有效'), findsOneWidget);
  });
}
