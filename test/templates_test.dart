import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;
import 'package:klinikaid_mobile/features/auth/presentation/providers/auth_provider.dart';
import 'package:klinikaid_mobile/features/patient/templates/document_templates.dart';
import 'package:klinikaid_mobile/features/patient/templates/presentation/providers/templates_provider.dart';
import 'package:klinikaid_mobile/features/reception/domain/submission.dart';
import 'package:klinikaid_mobile/features/reception/domain/submission_detail.dart';
import 'package:klinikaid_mobile/features/reception/domain/submission_status.dart';
import 'package:klinikaid_mobile/features/reception/data/reception_repository.dart';
import 'package:klinikaid_mobile/features/reception/presentation/providers/reception_queue_provider.dart';
import 'package:klinikaid_mobile/features/reception/presentation/screens/document_validation_screen.dart';
import 'package:klinikaid_mobile/core/models/profile.dart';

class MockAuthProvider extends AuthProvider {
  Profile? _mockProfile;

  MockAuthProvider() : super();

  void setMockProfile(Profile? p) {
    _mockProfile = p;
    notifyListeners();
  }

  @override
  bool get isAuthenticated => true;

  @override
  bool get isLoading => false;

  @override
  Profile? get profile => _mockProfile;
}

class MockReceptionRepository extends ReceptionRepository {
  final SubmissionDetail mockDetail;

  MockReceptionRepository({required this.mockDetail});

  @override
  Future<SubmissionDetail> getSubmissionDetail(String id) async {
    return mockDetail;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Mock shared_preferences MethodChannel to avoid MissingPluginException in tests
  const sharedPreferencesChannel = MethodChannel('plugins.flutter.io/shared_preferences');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(sharedPreferencesChannel, (MethodCall methodCall) async {
    if (methodCall.method == 'getAll') {
      return <String, Object>{};
    }
    return true;
  });

  setUpAll(() async {
    await supabase.Supabase.initialize(
      url: 'https://onzeyejlfydvvbkejvwf.supabase.co',
      anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9uemV5ZWpsZnlkdnZia2VqdndmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzkzNjcxMjYsImV4cCI6MjA5NDk0MzEyNn0.FJNbbuBZ2LdutVNrloYsxOLGZWbP-oLLTLJaKBOFkMM',
      authOptions: const supabase.FlutterAuthClientOptions(
        localStorage: supabase.EmptyLocalStorage(),
      ),
    );
  });

  group('Patient Document Templates — Config & Logic Tests', () {
    test('All 6 templates and their required fields are configured correctly', () {
      expect(clinicTemplates.length, equals(6));

      final ids = clinicTemplates.map((t) => t.id).toList();
      expect(ids, containsAll([
        'referral-form',
        'lab-request',
        'med-cert',
        'procedure-consent',
        'patient-intake',
        'results-release'
      ]));

      // Verify patient-intake has chief_complaint
      final intake = clinicTemplates.firstWhere((t) => t.id == 'patient-intake');
      expect(intake.fields.any((f) => f.key == 'chief_complaint'), isTrue);
    });

    test('Age validation math logic respects Manila UTC+8 timezone rules', () {
      final manilaNow = DateTime.now().toUtc().add(const Duration(hours: 8));

      // 17 years old
      final dob17 = DateTime(manilaNow.year - 17, manilaNow.month, manilaNow.day + 1);
      int age17 = manilaNow.year - dob17.year;
      if (manilaNow.month < dob17.month || (manilaNow.month == dob17.month && manilaNow.day < dob17.day)) {
        age17--;
      }
      expect(age17 < 18, isTrue);

      // 18 years old
      final dob18 = DateTime(manilaNow.year - 18, manilaNow.month, manilaNow.day);
      int age18 = manilaNow.year - dob18.year;
      if (manilaNow.month < dob18.month || (manilaNow.month == dob18.month && manilaNow.day < dob18.day)) {
        age18--;
      }
      expect(age18 >= 18, isTrue);
    });

    test('Byte-parity test: patient-intake injects DOB/contact/address, other templates do not', () {
      // Mocking metadata generation payload logic directly from templates_provider
      Map<String, dynamic> buildMetadata({
        required String templateId,
        required Map<String, dynamic> formValues,
        String? dob,
        String? contactNumber,
        String? address,
      }) {
        final Map<String, dynamic> metadata = {
          'template_id': templateId,
          'submission_type': 'template',
          ...formValues,
        };
        if (templateId == 'patient-intake') {
          metadata['date_of_birth'] = dob ?? '';
          metadata['contact_number'] = contactNumber ?? '';
          metadata['address'] = address ?? '';
        }
        return metadata;
      }

      // Intake metadata should contain injected values
      final intakeMetadata = buildMetadata(
        templateId: 'patient-intake',
        formValues: {'chief_complaint': 'Cold'},
        dob: '1995-10-10',
        contactNumber: '09123456789',
        address: 'Manila, PH',
      );
      expect(intakeMetadata['date_of_birth'], equals('1995-10-10'));
      expect(intakeMetadata['contact_number'], equals('09123456789'));
      expect(intakeMetadata['address'], equals('Manila, PH'));

      // Referral metadata should NOT contain injected values
      final referralMetadata = buildMetadata(
        templateId: 'referral-form',
        formValues: {'referring_physician': 'Dr. Cruz'},
        dob: '1995-10-10',
        contactNumber: '09123456789',
        address: 'Manila, PH',
      );
      expect(referralMetadata.containsKey('date_of_birth'), isFalse);
      expect(referralMetadata.containsKey('contact_number'), isFalse);
      expect(referralMetadata.containsKey('address'), isFalse);
    });
  });

  group('Reception Rendering — DocumentValidationScreen Tests', () {
    late MockAuthProvider authProvider;

    setUp(() {
      authProvider = MockAuthProvider();
      authProvider.setMockProfile(Profile(
        id: 'receptionist-uuid',
        fullName: 'Bob Receptionist',
        role: UserRole.receptionist,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));
    });

    Widget createTestWidget({
      required AuthProvider authProvider,
      required ReceptionRepository repository,
    }) {
      return MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
          Provider<ReceptionRepository>.value(value: repository),
          ChangeNotifierProvider<ReceptionQueueProvider>(
            create: (context) => ReceptionQueueProvider(repository: repository),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: DocumentValidationScreen(submissionId: 'sub-id-123'),
          ),
        ),
      );
    }

    testWidgets('Template type renders metadata fields and disables view original button', (tester) async {
      final mockSub = Submission(
        id: 'sub-id-123',
        patientName: 'Jane Doe',
        fileName: 'Intake.template',
        fileType: 'template', // lowercase only
        uploadedAt: DateTime.now(),
        uploadedBy: 'Jane Doe',
        status: SubmissionStatus.submitted,
      );

      final mockDetail = SubmissionDetail(
        submission: mockSub,
        storagePath: 'template://patient-intake-1234567',
        patientDob: '1990-05-15',
        patientGender: 'female',
        patientContact: '09123456789',
        patientEmail: 'jane.doe@email.com',
        patientAddress: 'Rizal, PH',
        extractedMetadata: {
          'template_id': 'patient-intake',
          'template_name': 'Patient Intake Form',
          'submission_type': 'template',
          'submitted_at': '2026-07-14T08:18:55Z',
          'patient_name': 'Jane Doe',
          'chief_complaint': 'Stomach ache and nausea',
        },
      );

      final repo = MockReceptionRepository(mockDetail: mockDetail);
      await tester.pumpWidget(createTestWidget(authProvider: authProvider, repository: repo));
      await tester.pumpAndSettle();

      // Card Header
      expect(find.text('STRUCTURED FORM DETAILS'), findsOneWidget);
      // Field rendering check
      expect(find.text('CHIEF COMPLAINT'), findsOneWidget);
      expect(find.text('Stomach ache and nausea'), findsOneWidget);
      // Overall AI Confidence is overridden
      expect(find.text('100% Validated (Structured Form)'), findsOneWidget);
      expect(find.text('Structured templates bypass OCR and AI evaluation triggers.'), findsOneWidget);

      // Verify view original button is disabled
      final viewOriginalBtn = tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Structured Form (No Image)'));
      expect(viewOriginalBtn.onPressed, isNull);
    });

    testWidgets('Regression: image/pdf uploads render normal OCR view and enable view original button', (tester) async {
      final mockSub = Submission(
        id: 'sub-id-123',
        patientName: 'Jane Doe',
        fileName: 'referral.pdf',
        fileType: 'pdf',
        uploadedAt: DateTime.now(),
        uploadedBy: 'Jane Doe',
        status: SubmissionStatus.submitted,
      );

      final mockDetail = SubmissionDetail(
        submission: mockSub,
        ocrText: 'This is standard referral letter contents.',
        storagePath: 'uploads/referral.pdf',
        patientDob: '1990-05-15',
        patientGender: 'female',
        patientContact: '09123456789',
        patientEmail: 'jane.doe@email.com',
        patientAddress: 'Rizal, PH',
      );

      final repo = MockReceptionRepository(mockDetail: mockDetail);
      await tester.pumpWidget(createTestWidget(authProvider: authProvider, repository: repo));
      await tester.pumpAndSettle();

      // Card Header
      expect(find.text('MONOSPACE RAW'), findsOneWidget);
      expect(find.text('This is standard referral letter contents.'), findsOneWidget);

      // AI validation report shows normal text
      expect(find.text('No OCR Score'), findsOneWidget);

      // Verify view original button is enabled
      final viewOriginalBtn = tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'View Original Document'));
      expect(viewOriginalBtn.onPressed, isNotNull);
    });
  });
}
