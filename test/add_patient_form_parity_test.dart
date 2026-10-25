import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:klinikaid_mobile/features/auth/domain/registration_validators.dart';
import 'package:klinikaid_mobile/features/specialist/presentation/providers/specialist_provider.dart';
import 'package:klinikaid_mobile/features/specialist/presentation/widgets/add_patient_form.dart';

// Mirrors web src/app/(dashboard)/specialist/patients/actions.ts.
class _RecordingProvider extends SpecialistProvider {
  final calls = <Map<String, Object?>>[];

  @override
  Future<bool> addPatient({
    required String firstName,
    required String lastName,
    required DateTime dob,
    required String gender,
    String? contactNumber,
    String? email,
    String? address,
  }) async {
    calls.add({'first': firstName, 'dob': dob, 'contact': contactNumber});
    return true;
  }
}

void main() {
  late _RecordingProvider provider;

  Future<void> openForm(WidgetTester tester) async {
    provider = _RecordingProvider();
    await tester.pumpWidget(ChangeNotifierProvider<SpecialistProvider>.value(
      value: provider,
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog(context: context, builder: (_) => const AddPatientForm()),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Future<void> fill(WidgetTester tester, {String first = 'Al', String last = 'Cruz', DateTime? dob}) async {
    await tester.enterText(find.byKey(const Key('firstNameField')), first);
    await tester.enterText(find.byKey(const Key('lastNameField')), last);
    tester.state<AddPatientFormState>(find.byType(AddPatientForm)).selectedDob =
        dob ?? DateTime(2015, 6, 1);
    await tester.pump();
  }

  Future<void> save(WidgetTester tester) async {
    await tester.ensureVisible(find.byKey(const Key('savePatientButton')));
    await tester.tap(find.byKey(const Key('savePatientButton')));
    await tester.pumpAndSettle();
  }

  testWidgets('a minor with a two-letter name is accepted, like web', (tester) async {
    await openForm(tester);
    await fill(tester);
    await tester.enterText(find.byKey(const Key('contactNumberField')), '+639171234567');
    await save(tester);

    expect(provider.calls, hasLength(1));
    expect(provider.calls.single['dob'], DateTime(2015, 6, 1));
    expect(provider.calls.single['contact'], '09171234567');
  });

  testWidgets('names outside the web character set are refused', (tester) async {
    await openForm(tester);
    await fill(tester, first: 'R2D2');
    await save(tester);

    expect(find.text(RegistrationValidators.nameFieldMessage('First name')), findsOneWidget);
    expect(provider.calls, isEmpty);
  });

  testWidgets('a filled email or address must pass the web checks', (tester) async {
    await openForm(tester);
    await fill(tester);
    await tester.enterText(find.byKey(const Key('emailField')), 'name@example');
    await tester.enterText(find.byKey(const Key('addressField')), 'a' * 256);
    await save(tester);

    expect(find.text('Invalid email address'), findsOneWidget);
    expect(find.text(RegistrationValidators.addressTooLongMessage), findsOneWidget);
    // The field is optional here, so it must not claim the address is required.
    expect(find.text(RegistrationValidators.addressFieldMessage), findsNothing);
    expect(provider.calls, isEmpty);
  });
}
