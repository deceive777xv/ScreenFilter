import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:screen_filter_app/ui/widgets/numeric_value_field.dart';

void main() {
  testWidgets('submits typed numeric values', (tester) async {
    final values = <double>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NumericValueField(
            value: 0.3,
            min: 0,
            max: 1,
            fractionDigits: 2,
            onChanged: values.add,
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), '0.75');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(values, [0.75]);
  });

  testWidgets('clamps submitted values to the allowed range', (tester) async {
    final values = <double>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NumericValueField(
            value: 0.3,
            min: 0,
            max: 1,
            fractionDigits: 2,
            onChanged: values.add,
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), '2');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(values, [1.0]);
    expect(find.text('1.00'), findsOneWidget);
  });

  testWidgets('restores the current value when input is invalid', (
    tester,
  ) async {
    final values = <double>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NumericValueField(
            value: 0.3,
            min: 0,
            max: 1,
            fractionDigits: 2,
            onChanged: values.add,
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'abc');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(values, isEmpty);
    expect(find.text('0.30'), findsOneWidget);
  });
}
