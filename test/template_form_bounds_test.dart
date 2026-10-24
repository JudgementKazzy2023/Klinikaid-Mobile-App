import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'package:klinikaid_mobile/core/patient_submission_containment.dart';
import 'package:klinikaid_mobile/core/utils/manila_time.dart';
import 'package:klinikaid_mobile/features/auth/presentation/providers/auth_provider.dart';
import 'package:klinikaid_mobile/features/patient/templates/document_templates.dart';
import 'package:klinikaid_mobile/features/patient/templates/presentation/providers/templates_provider.dart';
import 'package:klinikaid_mobile/features/patient/templates/presentation/screens/template_form_renderer_screen.dart';
import 'package:klinikaid_mobile/features/patient/templates/template_answers.dart';

/// A stand-in for the signed-in patient. The account consent is a plain flag
/// here so a test can prove that a declined *form* consent never touches it.
class _StubAuthProvider extends AuthProvider {
  _StubAuthProvider() : super();

  bool accountConsentGiven = true;

  @override
  bool get hasConsented => accountConsentGiven;
}

Widget _app(
  Widget child, {
  required AuthProvider auth,
  required TemplatesProvider templates,
}) {
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(path: '/', builder: (context, state) => child),
      GoRoute(
        path: '/patient',
        builder: (context, state) => const Scaffold(body: Text('patient')),
      ),
      GoRoute(
        path: '/patient/templates',
        builder: (context, state) => const Scaffold(body: Text('templates')),
      ),
    ],
  );

  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthProvider>.value(value: auth),
      ChangeNotifierProvider<TemplatesProvider>.value(value: templates),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // The submission flows open only when the containment is lifted, and must
  // restore it afterwards.
  setUp(() => PatientSubmissionContainment.activeForTesting = false);
  tearDown(() => PatientSubmissionContainment.activeForTesting = true);

  const sharedPreferencesChannel =
      MethodChannel('plugins.flutter.io/shared_preferences');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(sharedPreferencesChannel, (MethodCall call) async {
    if (call.method == 'getAll') {
      return <String, Object>{};
    }
    return true;
  });

  setUpAll(() async {
    // A local placeholder client: nothing in these tests talks to a server.
    await supabase.Supabase.initialize(
      url: 'https://template-bounds-test.supabase.co',
      anonKey: 'template-bounds-test-anon-key',
      authOptions: const supabase.FlutterAuthClientOptions(
        localStorage: supabase.EmptyLocalStorage(),
      ),
    );
  });

  group('Catalogue parity with the canonical clinic rules', () {
    test('The six template ids are the canonical ones', () {
      expect(
        clinicTemplates.map((t) => t.id).toList(),
        equals([
          'referral-form',
          'lab-request',
          'med-cert',
          'procedure-consent',
          'patient-intake',
          'results-release',
        ]),
      );
    });

    test('Every template carries the canonical fields, flags and options', () {
      // key, type, required, options, notFuture, consent
      const expected = <String, List<List<Object?>>>{
        'referral-form': [
          ['referring_physician', 'text', true, null, false, false],
          ['referring_clinic', 'text', false, null, false, false],
          ['reason_for_referral', 'textarea', true, null, false, false],
          [
            'requested_service',
            'select',
            true,
            ['Laboratory', 'Imaging', 'Ultrasound', 'ECG'],
            false,
            false
          ],
          ['referral_date', 'date', true, null, true, false],
        ],
        'lab-request': [
          ['ordering_physician', 'text', true, null, false, false],
          ['tests_requested', 'textarea', true, null, false, false],
          ['fasting_required', 'select', false, ['Yes', 'No'], false, false],
          ['request_date', 'date', true, null, false, false],
        ],
        'med-cert': [
          ['purpose', 'textarea', true, null, false, false],
          ['date_needed', 'date', true, null, false, false],
        ],
        'procedure-consent': [
          ['procedure', 'text', true, null, false, false],
          ['consent_given', 'select', true, ['Yes', 'No'], false, true],
          ['consent_date', 'date', true, null, true, false],
        ],
        'patient-intake': [
          ['chief_complaint', 'textarea', true, null, false, false],
        ],
        'results-release': [
          ['release_to', 'text', true, null, false, false],
          [
            'results_type',
            'text',
            true,
            null,
            false,
            false
          ],
          ['authorization_date', 'date', true, null, false, false],
        ],
      };

      for (final template in clinicTemplates) {
        final fields = expected[template.id]!;
        expect(template.fields.length, fields.length,
            reason: '${template.id} must ask the canonical questions');

        for (var i = 0; i < fields.length; i++) {
          final field = template.fields[i];
          final want = fields[i];
          expect(field.key, want[0], reason: '${template.id} field $i');
          expect(field.type, want[1], reason: '${template.id}/${field.key}');
          expect(field.required, want[2], reason: '${template.id}/${field.key}');
          expect(field.options, want[3], reason: '${template.id}/${field.key}');
          expect(field.notFuture, want[4], reason: '${template.id}/${field.key}');
          expect(field.consent, want[5], reason: '${template.id}/${field.key}');
        }
      }
    });

    test('A text answer is bounded at 200 and a free-text answer at 2000', () {
      final referral = clinicTemplateById('referral-form')!;
      final text = referral.fields.firstWhere((f) => f.key == 'referring_physician');
      final textarea =
          referral.fields.firstWhere((f) => f.key == 'reason_for_referral');

      expect(templateFieldMaxLength(text), 200);
      expect(templateFieldMaxLength(textarea), 2000);
      expect(templateFieldMaxLength(referral.fields
          .firstWhere((f) => f.key == 'referral_date')), isNull);
    });
  });

  group('Answer length bounds', () {
    final today = DateTime(2026, 10, 18);
    final referral = clinicTemplateById('referral-form')!;
    final physician =
        referral.fields.firstWhere((f) => f.key == 'referring_physician');
    final reason =
        referral.fields.firstWhere((f) => f.key == 'reason_for_referral');

    test('A 201 character answer is refused and 200 is accepted', () {
      expect(
        templateFieldProblem(physician, 'x' * 201, today),
        'must be 200 characters or fewer (has 201)',
      );
      expect(templateFieldProblem(physician, 'x' * 200, today), isNull);
    });

    test('A 2001 character free-text answer is refused and 2000 is accepted',
        () {
      expect(
        templateFieldProblem(reason, 'x' * 2001, today),
        'must be 2000 characters or fewer (has 2001)',
      );
      expect(templateFieldProblem(reason, 'x' * 2000, today), isNull);
    });

    test('The length is counted after trimming, like the shared rules', () {
      expect(templateFieldProblem(physician, '  ${'x' * 200}  ', today), isNull);
      expect(
        templateFieldProblem(physician, '  ${'x' * 201}  ', today),
        'must be 200 characters or fewer (has 201)',
      );
    });
  });

  group('Date bounds', () {
    final today = DateTime(2026, 10, 18);
    final referral = clinicTemplateById('referral-form')!;
    final referralDate =
        referral.fields.firstWhere((f) => f.key == 'referral_date');
    final medCert = clinicTemplateById('med-cert')!;
    final dateNeeded = medCert.fields.firstWhere((f) => f.key == 'date_needed');

    test('A date before 1900-01-01 is refused and 1900-01-01 is accepted', () {
      expect(
        templateFieldProblem(referralDate, '1800-01-01', today),
        'must be on or after 1900-01-01',
      );
      expect(templateFieldProblem(referralDate, '1900-01-01', today), isNull);
    });

    test('A past-only date after today is refused and today is accepted', () {
      expect(
        templateFieldProblem(referralDate, '2026-10-19', today),
        'cannot be after today (2026-10-18)',
      );
      expect(templateFieldProblem(referralDate, '2026-10-18', today), isNull);
    });

    test('A forward-looking date is allowed two years ahead and no further',
        () {
      expect(templateFieldProblem(dateNeeded, '2026-12-01', today), isNull);
      expect(templateFieldProblem(dateNeeded, '2028-10-18', today), isNull);
      expect(
        templateFieldProblem(dateNeeded, '2028-10-19', today),
        'must be on or before 2028-10-18',
      );
      expect(
        templateFieldProblem(dateNeeded, '9999-12-31', today),
        'must be on or before 2028-10-18',
      );
    });

    test('An impossible date is refused', () {
      expect(
        templateFieldProblem(dateNeeded, '2026-02-30', today),
        'must be a valid date',
      );
    });
  });

  group('The Manila calendar day', () {
    test('The day rolls over at Manila midnight, eight hours before the device',
        () {
      // 2026-03-01 00:30 in Manila is still 2026-02-28 on the UTC clock.
      expect(
        manilaTodayFrom(DateTime.utc(2026, 2, 28, 16, 30)),
        DateTime(2026, 3, 1),
      );
      // One minute earlier is still the previous day in Manila.
      expect(
        manilaTodayFrom(DateTime.utc(2026, 2, 28, 15, 59)),
        DateTime(2026, 2, 28),
      );
    });

    test('A date is judged against the Manila day, not the device day', () {
      final manilaToday = DateTime(2026, 3, 1);
      final consent = clinicTemplateById('procedure-consent')!
          .fields
          .firstWhere((f) => f.key == 'consent_date');

      expect(
        templateFieldProblem(consent, '2026-03-01', manilaToday),
        isNull,
      );
      expect(
        templateFieldProblem(consent, '2026-03-02', manilaToday),
        'cannot be after today (2026-03-01)',
      );
    });
  });

  group('Declined form consent', () {
    test('The shared declined answers are recognised', () {
      for (final answer in [
        'no',
        'No',
        'n',
        'false',
        'declined',
        'decline',
        'refused',
        'refuse',
        'i do not consent',
      ]) {
        expect(isDeclinedConsentAnswer(answer), isTrue, reason: answer);
      }
      for (final answer in ['yes', 'maybe', 'no thanks', '']) {
        expect(isDeclinedConsentAnswer(answer), isFalse, reason: answer);
      }
    });

    test('A declined consent travels as the declined answer', () {
      final provider = TemplatesProvider();

      // The client no longer builds the stored metadata: the submission
      // endpoint stores the patient's own answers verbatim, and the declined
      // consent is recognised as the declined answer it is.
      expect(
        provider.declinedFormConsentFields('procedure-consent', {
          'procedure': 'Venipuncture',
          'consent_given': 'No',
          'consent_date': '2026-10-18',
        }),
        ['consent_given'],
      );
      expect(
        provider.declinedFormConsentFields('procedure-consent', {
          'consent_given': 'Yes',
        }),
        isEmpty,
      );
    });

    test('A declined form consent does not touch the account consent', () {
      final auth = _StubAuthProvider();
      final provider = TemplatesProvider();

      provider.declinedFormConsentFields('procedure-consent', {
        'procedure': 'Venipuncture',
        'consent_given': 'No',
        'consent_date': '2026-10-18',
      });

      // The account's data-privacy consent is untouched by a form decline.
      expect(auth.hasConsented, isTrue);
      expect(auth.accountConsentGiven, isTrue);
    });

    test('The stored answers carry no account-consent state', () {
      // Only the form's own questions travel with the submission; the client
      // no longer builds the stored metadata itself.
      final keys = clinicTemplateById('procedure-consent')!
          .fields
          .map((field) => field.key);

      expect(
        keys.where((key) => key.toLowerCase().contains('privacy')),
        isEmpty,
      );
      expect(keys.where((key) => key.toLowerCase().contains('terms')),
          isEmpty);
    });
  });

  group('The template form', () {
    late _StubAuthProvider auth;
    late TemplatesProvider templates;

    setUp(() {
      auth = _StubAuthProvider();
      templates = TemplatesProvider();
    });

    Future<void> pumpForm(WidgetTester tester, String templateId) async {
      await tester.pumpWidget(_app(
        TemplateFormRendererScreen(templateId: templateId),
        auth: auth,
        templates: templates,
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('A 201 character answer is refused with a readable message',
        (tester) async {
      await pumpForm(tester, 'referral-form');

      await tester.enterText(
          find.byKey(const ValueKey('field-referring_physician')), 'x' * 201);
      await tester.tap(find.text('Submit to Reception'));
      await tester.pumpAndSettle();

      expect(
        find.text('Referring Physician must be 200 characters or fewer (has 201).'),
        findsOneWidget,
      );
    });

    testWidgets('A 200 character answer is accepted', (tester) async {
      await pumpForm(tester, 'referral-form');

      await tester.enterText(
          find.byKey(const ValueKey('field-referring_physician')), 'x' * 200);
      await tester.tap(find.text('Submit to Reception'));
      await tester.pumpAndSettle();

      expect(find.textContaining('characters or fewer'), findsNothing);
    });

    testWidgets('A 2001 character free-text answer is refused and 2000 is not',
        (tester) async {
      await pumpForm(tester, 'referral-form');

      await tester.enterText(
          find.byKey(const ValueKey('field-reason_for_referral')), 'x' * 2001);
      await tester.tap(find.text('Submit to Reception'));
      await tester.pumpAndSettle();

      expect(
        find.text(
            'Reason for Referral must be 2000 characters or fewer (has 2001).'),
        findsOneWidget,
      );

      await tester.enterText(
          find.byKey(const ValueKey('field-reason_for_referral')), 'x' * 2000);
      await tester.tap(find.text('Submit to Reception'));
      await tester.pumpAndSettle();

      expect(find.textContaining('characters or fewer'), findsNothing);
    });

    testWidgets('A past-only date cannot be picked after today',
        (tester) async {
      await pumpForm(tester, 'procedure-consent');

      final field = find.byKey(const ValueKey('field-consent_date'));
      await tester.ensureVisible(field);
      await tester.pumpAndSettle();
      await tester.tap(field);
      await tester.pumpAndSettle();

      final picker = tester.widget<CalendarDatePicker>(
          find.byType(CalendarDatePicker));
      expect(picker.firstDate, DateTime(1900, 1, 1));
      expect(picker.lastDate, manilaToday());
    });

    testWidgets('A forward-looking date may be picked two years ahead',
        (tester) async {
      await pumpForm(tester, 'med-cert');

      final field = find.byKey(const ValueKey('field-date_needed'));
      await tester.ensureVisible(field);
      await tester.pumpAndSettle();
      await tester.tap(field);
      await tester.pumpAndSettle();

      final picker = tester.widget<CalendarDatePicker>(
          find.byType(CalendarDatePicker));
      expect(picker.firstDate, DateTime(1900, 1, 1));
      expect(picker.lastDate, latestTemplateDate(manilaToday()));
    });

    testWidgets('A declined consent is shown as a decline, not as an error',
        (tester) async {
      await pumpForm(tester, 'procedure-consent');

      final field = find.byKey(const ValueKey('field-consent_given'));
      await tester.ensureVisible(field);
      await tester.pumpAndSettle();
      await tester.tap(field);
      await tester.pumpAndSettle();
      await tester.tap(find.text('No'));
      await tester.pumpAndSettle();

      expect(
        find.text('Consent declined. This form is still sent to reception for review.'),
        findsOneWidget,
      );
      // The account consent is a different thing and is untouched.
      expect(auth.hasConsented, isTrue);
    });
  });
}
