import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:exalted/design/exalted_spring_up.dart';

void main() {
  testWidgets('spring up ends with the child visible', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: ExaltedSpringUp(child: Text('card'))),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('card'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('card'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
