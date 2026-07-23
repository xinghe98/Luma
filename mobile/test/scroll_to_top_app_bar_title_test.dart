import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luma/shared/layout/scroll_to_top_app_bar_title.dart';

void main() {
  testWidgets('double tapping an app bar title returns its list to the start', (
    tester,
  ) async {
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: AppBar(
            title: ScrollToTopAppBarTitle(title: '媒体库', controller: scroll),
          ),
          body: ListView.builder(
            controller: scroll,
            itemCount: 80,
            itemBuilder: (_, index) =>
                SizedBox(height: 72, child: Text('项目 $index')),
          ),
        ),
      ),
    );

    await tester.drag(find.byType(ListView), const Offset(0, -480));
    await tester.pumpAndSettle();
    expect(scroll.offset, greaterThan(0));

    final title = find.text('媒体库');
    await tester.tap(title);
    await tester.pump(const Duration(milliseconds: 80));
    await tester.tap(title);
    await tester.pumpAndSettle();

    expect(scroll.offset, 0);
  });
}
