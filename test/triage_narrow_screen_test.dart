import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:klinikaid_mobile/features/reception/presentation/widgets/triage_routing_sheet.dart';

/// Narrow-screen regression coverage for the reception triage routing sheet
/// (issue #13, PR #8).
///
/// PR #8 aligned the mobile blood-pressure contract with the web and verified
/// the inline error readability at 430px manually only. These checks pin that
/// behaviour down for the sizes staff actually use:
///
/// * 430x932 — the width PR #8 inspected by hand.
/// * 360x640 — the smallest common Android screen.
///
/// The blood-pressure error must stay fully readable (never clipped or
/// ellipsized), must not overflow the layout, and must keep blocking the
/// routing callback until the reading is corrected.
const _reversedBp = '80/120';
const _reversedBpError = 'Systolic must be higher than diastolic.';

const _outOfRangeBp = '39/20';
const _outOfRangeBpError =
    'Systolic must be 40-300 and diastolic 20-200 mmHg.';

const _validBp = '120/80';

const _narrowSizes = <String, Size>{
  '430x932': Size(430, 932),
  '360x640': Size(360, 640),
};

const _textScales = <double>[1.0, 1.3];

Widget _buildSheetHost({
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
                // Mirrors lib/features/reception/presentation/screens/
                // document_validation_screen.dart, which opens the sheet the
                // same way.
                isScrollControlled: true,
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                ),
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

/// Opens the triage sheet and picks a department so the submit action enables.
Future<void> _openSheetWithDepartment(WidgetTester tester) async {
  await tester.tap(find.text('Show Sheet'));
  await tester.pumpAndSettle();
  final department = find.byType(DropdownButtonFormField<String>).first;
  await tester.ensureVisible(department);
  await tester.pumpAndSettle();
  await tester.tap(department);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Ultrasound').last);
  await tester.pumpAndSettle();
}

/// Submits the sheet, scrolling the action row into view first.
Future<void> _tapConfirm(WidgetTester tester) async {
  final confirm = find.text('Confirm Routing');
  await tester.ensureVisible(confirm);
  await tester.pumpAndSettle();
  await tester.tap(confirm);
  await tester.pumpAndSettle();
}

/// Enters a blood-pressure reading and lets the focused field relayout settle,
/// so the field's own "keep the caret visible" scroll cannot race with the
/// scroll that brings the action row into view.
Future<void> _enterBloodPressure(
  WidgetTester tester,
  String reading,
) async {
  await tester.enterText(find.byKey(const Key('bp_input_field')), reading);
  await tester.pumpAndSettle();
}

/// Asserts the inline error is present, fully painted and inside the screen.
void _expectErrorReadable(
  WidgetTester tester,
  Size screen,
  String message,
) {
  final error = find.text(message);
  expect(error, findsOneWidget, reason: 'error "$message" must be shown');

  final paragraph = tester.renderObject<RenderParagraph>(error);
  expect(
    paragraph.text.toPlainText(),
    message,
    reason: 'the rendered error must carry the full correction text',
  );
  expect(
    paragraph.didExceedMaxLines,
    isFalse,
    reason:
        'the error "$message" must not be clipped/ellipsized on a $screen screen',
  );

  final box = tester.renderObject<RenderBox>(error);
  final topLeft = box.localToGlobal(Offset.zero);
  expect(
    topLeft.dx,
    greaterThanOrEqualTo(0.0),
    reason: 'the error must start inside the screen',
  );
  expect(
    topLeft.dx + box.size.width,
    lessThanOrEqualTo(screen.width),
    reason: 'the error must fit within the $screen screen width',
  );
}

/// Drives one invalid-reading case end to end on a narrow screen.
Future<void> _runNarrowScreenCase(
  WidgetTester tester, {
  required Size screen,
  required double textScale,
  required String invalidReading,
  required String expectedError,
}) async {
  tester.view.physicalSize = screen;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

  var submissions = 0;
  String? routedBloodPressure;
  await tester.pumpWidget(_buildSheetHost(onConfirm: ({
    required String department,
    required String priority,
    String? bloodPressure,
    num? weightKg,
    num? temperatureC,
    String? triageNotes,
  }) {
    submissions++;
    routedBloodPressure = bloodPressure;
  }));

  await _openSheetWithDepartment(tester);

  // Enter an invalid reading and trigger validation.
  await _enterBloodPressure(tester, invalidReading);
  await _tapConfirm(tester);

  // (a) No layout overflow and no framework exception.
  expect(tester.takeException(), isNull);

  // (b) The full error text is shown and fits the screen width.
  _expectErrorReadable(tester, screen, expectedError);

  // (c) An invalid reading never reaches the routing callback.
  expect(submissions, 0);

  // Correcting the reading allows exactly one submission.
  await _enterBloodPressure(tester, _validBp);
  await _tapConfirm(tester);

  expect(tester.takeException(), isNull);
  expect(submissions, 1);
  expect(routedBloodPressure, _validBp);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Triage routing sheet — narrow screen blood pressure error', () {
    for (final sizeEntry in _narrowSizes.entries) {
      for (final textScale in _textScales) {
        final screen = sizeEntry.value;
        final label = '${sizeEntry.key} at text scale $textScale';

        testWidgets(
          '$label keeps the reversed blood pressure error readable and blocks routing',
          (tester) async {
            await _runNarrowScreenCase(
              tester,
              screen: screen,
              textScale: textScale,
              invalidReading: _reversedBp,
              expectedError: _reversedBpError,
            );
          },
        );

        testWidgets(
          '$label keeps the out-of-range blood pressure error readable and blocks routing',
          (tester) async {
            await _runNarrowScreenCase(
              tester,
              screen: screen,
              textScale: textScale,
              invalidReading: _outOfRangeBp,
              expectedError: _outOfRangeBpError,
            );
          },
        );
      }
    }
  });
}
