import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:klinikaid_mobile/core/utils/lab_validators.dart';
import 'package:klinikaid_mobile/features/reception/presentation/widgets/triage_routing_sheet.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Triage Vitals Validation — Unit Tests', () {
    test('MaxIntegerDigitsFormatter formats 3-digit and 4-digit fields correctly', () {
      const formatter3 = MaxIntegerDigitsFormatter(3, maxDecimalDigits: 1);
      const formatter4 = MaxIntegerDigitsFormatter(4, maxDecimalDigits: 2);

      // 3-digit configuration
      expect(
        formatter3.formatEditUpdate(
          TextEditingValue.empty,
          const TextEditingValue(text: '120.5'),
        ).text,
        equals('120.5'),
      );
      expect(
        formatter3.formatEditUpdate(
          const TextEditingValue(text: '120.5'),
          const TextEditingValue(text: '120.55'),
        ).text,
        equals('120.5'), // blocks 2nd decimal place
      );
      expect(
        formatter3.formatEditUpdate(
          TextEditingValue.empty,
          const TextEditingValue(text: '1200'),
        ).text,
        equals(''), // blocks 4th integer digit
      );

      // 4-digit configuration (Specialist / Department results entry behavior check)
      expect(
        formatter4.formatEditUpdate(
          TextEditingValue.empty,
          const TextEditingValue(text: '1200.55'),
        ).text,
        equals('1200.55'),
      );
      expect(
        formatter4.formatEditUpdate(
          const TextEditingValue(text: '1200.55'),
          const TextEditingValue(text: '1200.555'),
        ).text,
        equals('1200.55'), // blocks 3rd decimal place
      );
    });

    test('BloodPressureFormatter limits input at input time', () {
      final formatter = BloodPressureFormatter();

      // Basic input
      expect(
        formatter.formatEditUpdate(
          TextEditingValue.empty,
          const TextEditingValue(text: '120/80'),
        ).text,
        equals('120/80'),
      );

      // Reject letters
      expect(
        formatter.formatEditUpdate(
          const TextEditingValue(text: '120'),
          const TextEditingValue(text: '120a'),
        ).text,
        equals('120'),
      );

      // Block entering a second slash
      expect(
        formatter.formatEditUpdate(
          const TextEditingValue(text: '120/80'),
          const TextEditingValue(text: '120/80/'),
        ).text,
        equals('120/80'),
      );

      // Cap digits on both sides to 3
      expect(
        formatter.formatEditUpdate(
          const TextEditingValue(text: '120'),
          const TextEditingValue(text: '1200'),
        ).text,
        equals('120'),
      );
      expect(
        formatter.formatEditUpdate(
          const TextEditingValue(text: '120/80'),
          const TextEditingValue(text: '120/8000'),
        ).text,
        equals('120/80'),
      );
    });

    test('validateVitalsValue validates numeric weight/temp constraints correctly', () {
      // Weight & Temp configurations: max 3 integer digits, max 1 decimal digit
      expect(validateVitalsValue('36.5', maxIntegerDigits: 3, maxDecimalDigits: 1), isNull);
      expect(validateVitalsValue('70', maxIntegerDigits: 3, maxDecimalDigits: 1), isNull);
      expect(validateVitalsValue('999', maxIntegerDigits: 3, maxDecimalDigits: 1), isNull);
      expect(validateVitalsValue('120', maxIntegerDigits: 3, maxDecimalDigits: 1), isNull);
      expect(validateVitalsValue('', maxIntegerDigits: 3, maxDecimalDigits: 1), isNull); // optional
      expect(validateVitalsValue('   ', maxIntegerDigits: 3, maxDecimalDigits: 1), isNull); // optional

      // Invalid entries
      expect(validateVitalsValue('1000', maxIntegerDigits: 3, maxDecimalDigits: 1), isNotNull);
      expect(validateVitalsValue('36.55', maxIntegerDigits: 3, maxDecimalDigits: 1), isNotNull);
      expect(validateVitalsValue('weadaw', maxIntegerDigits: 3, maxDecimalDigits: 1), isNotNull);
      expect(validateVitalsValue('-5', maxIntegerDigits: 3, maxDecimalDigits: 1), isNotNull);
    });

    test('validateBloodPressure validates BP formats correctly', () {
      expect(validateBloodPressure('120/80'), isNull);
      expect(validateBloodPressure('90/60'), isNull);
      expect(validateBloodPressure(''), isNull); // optional
      expect(validateBloodPressure('   '), isNull); // optional

      // Invalid formats
      expect(validateBloodPressure('120'), isNotNull); // no slash
      expect(validateBloodPressure('1200/80'), isNotNull); // too many digits
      expect(validateBloodPressure('12//8'), isNotNull); // multiple slashes
      expect(validateBloodPressure('abc'), isNotNull); // alphabetic
    });
  });

  group('Triage Vitals Validation — Widget Tests', () {
    Widget buildTestWidget({
      required void Function({
        required String department,
        required String priority,
        String? bloodPressure,
        num? weightKg,
        num? temperatureC,
        String? triageNotes,
      }) onConfirm,
    }) {
      return MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return ElevatedButton(
                onPressed: () {
                  showModalBottomSheet(
                    context: context,
                    builder: (_) => TriageRoutingSheet(
                      patientName: 'Jane Doe',
                      onConfirm: onConfirm,
                    ),
                  );
                },
                child: const Text('Show Sheet'),
              );
            },
          ),
        ),
      );
    }

    testWidgets('Invalid vitals input blocks Confirm Routing, displays errors, and shows SnackBar', (tester) async {
      bool confirmCalled = false;
      await tester.pumpWidget(buildTestWidget(onConfirm: ({
        required String department,
        required String priority,
        String? bloodPressure,
        num? weightKg,
        num? temperatureC,
        String? triageNotes,
      }) {
        confirmCalled = true;
      }));

      // Open sheet
      await tester.tap(find.text('Show Sheet'));
      await tester.pumpAndSettle();

      // Choose valid department
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ultrasound').last);
      await tester.pumpAndSettle();

      // Enter invalid Blood Pressure (no slash)
      final bpField = find.byKey(const Key('bp_input_field'));
      expect(bpField, findsOneWidget);
      await tester.enterText(bpField, '120');

      // Tap Confirm Routing
      final confirmBtn = find.text('Confirm Routing');
      await tester.ensureVisible(confirmBtn);
      await tester.pumpAndSettle();
      await tester.tap(confirmBtn);
      await tester.pumpAndSettle();

      // Verify validation triggered: inline error is visible
      expect(find.text('BP must be in NNN/NNN format'), findsOneWidget);
      expect(confirmCalled, isFalse);

      // Verify Red SnackBar appears
      expect(find.text('Please correct the invalid vitals fields'), findsOneWidget);
    });

    testWidgets('Valid optional vitals inputs allow successful Confirm Routing', (tester) async {
      bool confirmCalled = false;
      String? routedDept;
      String? routedBp;
      num? routedWeight;
      num? routedTemp;

      await tester.pumpWidget(buildTestWidget(onConfirm: ({
        required String department,
        required String priority,
        String? bloodPressure,
        num? weightKg,
        num? temperatureC,
        String? triageNotes,
      }) {
        confirmCalled = true;
        routedDept = department;
        routedBp = bloodPressure;
        routedWeight = weightKg;
        routedTemp = temperatureC;
      }));

      // Open sheet
      await tester.tap(find.text('Show Sheet'));
      await tester.pumpAndSettle();

      // Choose valid department
      await tester.tap(find.byType(DropdownButtonFormField<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ultrasound').last);
      await tester.pumpAndSettle();

      // Enter valid vitals
      await tester.enterText(find.byKey(const Key('bp_input_field')), '120/80');
      await tester.enterText(find.byKey(const Key('weight_input_field')), '70.5');
      await tester.enterText(find.byKey(const Key('temp_input_field')), '36.5');

      // Tap Confirm Routing
      final confirmBtn = find.text('Confirm Routing');
      await tester.ensureVisible(confirmBtn);
      await tester.pumpAndSettle();
      await tester.tap(confirmBtn);
      await tester.pumpAndSettle();

      expect(confirmCalled, isTrue);
      expect(routedDept, equals('ultrasound'));
      expect(routedBp, equals('120/80'));
      expect(routedWeight, equals(70.5));
      expect(routedTemp, equals(36.5));
    });
  });
}
