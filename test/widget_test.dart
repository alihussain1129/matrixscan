import 'package:exalted/core/theme/app_colors.dart';
import 'package:exalted/core/widgets/exalted_button.dart';
import 'package:exalted/core/widgets/exalted_logo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('logo shows EXALTED', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: ExaltedLogo())),
    );
    expect(find.text('EXALTED'), findsOneWidget);
  });

  testWidgets('button fires onPressed', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          colorScheme: AppColors.lightScheme,
          extensions: const [AppColors.lightExtra],
        ),
        home: Scaffold(
          body: Center(
            child: ExaltedButton(label: 'SCAN', onPressed: () => taps++),
          ),
        ),
      ),
    );
    await tester.tap(find.text('SCAN'));
    await tester.pump();
    expect(taps, 1);
  });
}