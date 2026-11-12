import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:exalted/design/exalted_page.dart';
import 'package:exalted/design/exalted_segmented.dart';
import 'package:exalted/design/exalted_settings_kit.dart';
import 'package:exalted/design/exalted_tab_pills.dart';

Widget _app(Widget c) => MaterialApp(
  home: Scaffold(
    body: Center(child: SizedBox(width: 420, child: c)),
  ),
);

void main() {
  testWidgets('switch tile toggles when the row is tapped', (tester) async {
    var v = false;
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, set) => _app(
          ExaltedGroup(
            children: [
              ExaltedSwitchTile(
                icon: Icons.bolt,
                title: 'Auto scan',
                subtitle: 'Detect fast',
                value: v,
                onChanged: (x) => set(() => v = x),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.text('Auto scan'));
    await tester.pumpAndSettle();
    expect(v, isTrue);
  });

  testWidgets('segmented control reports the tapped option', (tester) async {
    var v = 'a';
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, set) => _app(
          ExaltedSegmented<String>(
            options: const [
              ExaltedSegment(value: 'a', label: 'Balanced'),
              ExaltedSegment(value: 'b', label: 'High'),
              ExaltedSegment(value: 'c', label: 'Ultra'),
            ],
            value: v,
            onChanged: (x) => set(() => v = x),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Ultra'));
    await tester.pumpAndSettle();
    expect(v, 'c');
  });

  testWidgets('tab pills report the tapped index', (tester) async {
    var i = 0;
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, set) => _app(
          ExaltedTabPills(
            items: const [
              ExaltedTabItem('General', Icons.tune),
              ExaltedTabItem('Scanning', Icons.qr_code_scanner),
            ],
            selected: i,
            onChanged: (x) => set(() => i = x),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Scanning'));
    await tester.pumpAndSettle();
    expect(i, 1);
  });

  testWidgets('page and section header build', (tester) async {
    await tester.pumpWidget(
      _app(
        const ExaltedPageFrame(
          child: ExaltedSectionHeader(title: 'Scanning', subtitle: 'Engine'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Scanning'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
