import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:drift/native.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:klinikaid_mobile/core/supabase/supabase_client.dart';
import 'package:klinikaid_mobile/core/cache/local_database.dart';
import 'package:klinikaid_mobile/core/models/patient.dart';
import 'package:klinikaid_mobile/features/auth/presentation/providers/auth_provider.dart';
import 'package:klinikaid_mobile/features/documents/presentation/providers/document_submission_provider.dart';
import 'package:klinikaid_mobile/features/documents/presentation/screens/submit_document_screen.dart';
import 'package:klinikaid_mobile/features/ocr/domain/quality_assessment.dart';

// Mock AuthProvider subclass
class MockAuthProvider extends AuthProvider {
  Patient? _mockPatient;
  MockAuthProvider() : super();
  void setMockPatient(Patient? p) {
    _mockPatient = p;
  }
  @override
  Patient? get patient => _mockPatient;
  @override
  bool get isLoading => false;
  @override
  bool get isAuthenticated => true;
  @override
  bool get hasConsented => true;
  @override
  bool get isOnboarded => true;
}

// Mock DocumentSubmissionProvider to inject different pre-screen states
class MockDocProvider extends DocumentSubmissionProvider {
  MockDocProvider(super.localDb);

  bool _mockIsProcessingOcr = false;
  Map<String, dynamic>? _mockMetadata;

  void setMockState({required bool isProcessing, Map<String, dynamic>? metadata}) {
    _mockIsProcessingOcr = isProcessing;
    _mockMetadata = metadata;
    notifyListeners();
  }

  @override
  bool get isProcessingOcr => _mockIsProcessingOcr;

  @override
  Map<String, dynamic>? get preScreenMetadata => _mockMetadata;

  @override
  void clearOcrState() {
    _mockIsProcessingOcr = false;
    _mockMetadata = null;
    super.clearOcrState();
  }

  @override
  Future<String> processOnDeviceOcr(String imagePath, Patient patient) async {
    // Return early and notify listeners. In tests, we set mock state manually beforehand.
    notifyListeners();
    return "Mock OCR Text";
  }
}

// Fake ImagePickerPlatform subclass to mock image picking
class MockImagePickerPlatform extends ImagePickerPlatform {
  final String filePath;
  MockImagePickerPlatform(this.filePath);

  @override
  Future<XFile?> getImageFromSource({
    required ImageSource source,
    ImagePickerOptions options = const ImagePickerOptions(),
  }) async {
    return XFile(filePath);
  }

  @override
  Future<XFile?> getImage({
    required ImageSource source,
    double? maxWidth,
    double? maxHeight,
    int? imageQuality,
    CameraDevice preferredCameraDevice = CameraDevice.rear,
  }) async {
    return XFile(filePath);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  // Mock shared_preferences to avoid MissingPluginException in tests
  const channel = MethodChannel('plugins.flutter.io/shared_preferences');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
    if (methodCall.method == 'getAll') {
      return <String, Object>{};
    }
    return true;
  });

  setUpAll(() async {
    await SupabaseService.initialize(localStorage: const EmptyLocalStorage());
  });

  group('QualityAssessment Model Tests', () {
    test('Correctly maps colors for each verdict', () {
      final good = QualityAssessment(score: 90, verdict: QualityVerdict.good, issues: []);
      final marginal = QualityAssessment(score: 65, verdict: QualityVerdict.marginal, issues: []);
      final poor = QualityAssessment(score: 30, verdict: QualityVerdict.poor, issues: []);

      expect(good.verdictColor, Colors.green);
      expect(marginal.verdictColor, Colors.amber);
      expect(poor.verdictColor, Colors.red);
    });

    test('Correctly maps labels for each verdict', () {
      final good = QualityAssessment(score: 90, verdict: QualityVerdict.good, issues: []);
      final marginal = QualityAssessment(score: 65, verdict: QualityVerdict.marginal, issues: []);
      final poor = QualityAssessment(score: 30, verdict: QualityVerdict.poor, issues: []);

      expect(good.verdictLabel, 'Looks good');
      expect(marginal.verdictLabel, 'Some issues found');
      expect(poor.verdictLabel, 'Quality may be too low');
    });

    test('Parses QualityAssessment JSON correctly', () {
      final jsonMap = {
        'score': 85,
        'verdict': 'good',
        'issues': [
          {
            'type': 'blur',
            'severity': 'low',
            'description': 'Minor blur detected.'
          }
        ]
      };

      final assessment = QualityAssessment.fromJson(jsonMap);
      expect(assessment.score, 85);
      expect(assessment.verdict, QualityVerdict.good);
      expect(assessment.issues.length, 1);
      expect(assessment.issues[0].type, QualityIssueType.blur);
      expect(assessment.issues[0].severity, QualityIssueSeverity.low);
      expect(assessment.issues[0].description, 'Minor blur detected.');
    });
  });

  group('Patient Name Cross-Reference Tests', () {
    late LocalDatabase db;
    late DocumentSubmissionProvider provider;

    setUp(() {
      db = LocalDatabase(NativeDatabase.memory());
      provider = DocumentSubmissionProvider(db);
    });

    tearDown(() async {
      await db.close();
    });

    test('Check patient name returns true on exact match', () {
      const ocrText = 'Referral for patient John Doe at clinic.';
      expect(provider.checkPatientName(ocrText, 'John', 'Doe'), true);
    });

    test('Check patient name is case-insensitive', () {
      const ocrText = 'referral for patient jOhN dOe at clinic.';
      expect(provider.checkPatientName(ocrText, 'John', 'Doe'), true);
    });

    test('Check patient name is whitespace-tolerant', () {
      const ocrText = 'Referral for patient John   Doe at clinic.';
      expect(provider.checkPatientName(ocrText, '  John  ', ' Doe  '), true);
    });

    test('Check patient name returns false when name is missing', () {
      const ocrText = 'Referral for patient Alice Smith at clinic.';
      expect(provider.checkPatientName(ocrText, 'John', 'Doe'), false);
    });
  });

  group('Widget Presentation & Traffic Light Tests', () {
    late LocalDatabase db;
    late MockAuthProvider authProvider;
    late MockDocProvider docProvider;
    late Directory tempDir;
    late File tempFile;

    setUp(() {
      db = LocalDatabase(NativeDatabase.memory());
      authProvider = MockAuthProvider();
      docProvider = MockDocProvider(db);

      tempDir = Directory.systemTemp.createTempSync();
      tempFile = File('${tempDir.path}/mock_image.jpg');
      tempFile.writeAsBytesSync([0, 1, 2, 3]);

      ImagePickerPlatform.instance = MockImagePickerPlatform(tempFile.path);

      authProvider.setMockPatient(Patient(
        id: 'patient-uuid-123',
        profileId: 'patient-uuid-123',
        firstName: 'Jane',
        lastName: 'Miller',
        dateOfBirth: DateTime(1988, 3, 14),
        gender: Gender.female,
        contactNumber: '09887766554',
        address: 'Rizal, PH',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));
    });

    tearDown(() async {
      db.close();
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    Widget createTestWidget() {
      return MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
          ChangeNotifierProvider<DocumentSubmissionProvider>.value(value: docProvider),
        ],
        child: const MaterialApp(
          home: SubmitDocumentScreen(),
        ),
      );
    }

    testWidgets('Renders Good verdict correctly', (tester) async {
      final goodMetadata = {
        'ocr_text': 'Jane Miller Referral Doctor Robert',
        'quality_assessment': {
          'score': 92,
          'verdict': 'good',
          'issues': []
        },
        'identity_match': true,
        'submitted_with_warnings': false,
      };

      docProvider.setMockState(isProcessing: false, metadata: goodMetadata);
      
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Tap on the Camera button to trigger image pick and OCR processing mock transition
      final cameraButton = find.widgetWithText(ElevatedButton, 'Camera');
      expect(cameraButton, findsOneWidget);
      await tester.tap(cameraButton);
      await tester.pumpAndSettle();

      // Check for green dot / verdict card
      expect(find.text('Looks good'), findsOneWidget);
      expect(find.text('Quality Score: 92/100'), findsOneWidget);
      expect(find.text('Identified Quality Issues'), findsNothing);
      expect(find.text('Name Mismatch Warning'), findsNothing);
      
      // Submit button should be ElevatedButton (filled)
      final submitButton = find.widgetWithText(ElevatedButton, 'Submit Request');
      expect(submitButton, findsOneWidget);
    });

    testWidgets('Renders Marginal verdict with issue list correctly', (tester) async {
      final marginalMetadata = {
        'ocr_text': 'Jane Miller Referral Doctor Robert',
        'quality_assessment': {
          'score': 68,
          'verdict': 'marginal',
          'issues': [
            {
              'type': 'blur',
              'severity': 'medium',
              'description': 'Your image appears slightly blurry.'
            }
          ]
        },
        'identity_match': true,
        'submitted_with_warnings': true,
      };

      docProvider.setMockState(isProcessing: false, metadata: marginalMetadata);

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      final cameraButton = find.widgetWithText(ElevatedButton, 'Camera');
      expect(cameraButton, findsOneWidget);
      await tester.tap(cameraButton);
      await tester.pumpAndSettle();

      expect(find.text('Some issues found'), findsOneWidget);
      expect(find.text('Quality Score: 68/100'), findsOneWidget);
      expect(find.text('Identified Quality Issues'), findsOneWidget);
      expect(find.text('Your image appears slightly blurry.'), findsOneWidget);
      expect(find.text('Name Mismatch Warning'), findsNothing);
      
      // Submit button should be ElevatedButton (filled)
      expect(find.widgetWithText(ElevatedButton, 'Submit Request'), findsOneWidget);
    });

    testWidgets('Renders Poor verdict with de-emphasized submit button correctly', (tester) async {
      final poorMetadata = {
        'ocr_text': 'Jane Miller Referral Doctor Robert',
        'quality_assessment': {
          'score': 35,
          'verdict': 'poor',
          'issues': [
            {
              'type': 'illegible_text',
              'severity': 'high',
              'description': 'Your text is highly illegible.'
            }
          ]
        },
        'identity_match': true,
        'submitted_with_warnings': true,
      };

      docProvider.setMockState(isProcessing: false, metadata: poorMetadata);

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      final cameraButton = find.widgetWithText(ElevatedButton, 'Camera');
      expect(cameraButton, findsOneWidget);
      await tester.tap(cameraButton);
      await tester.pumpAndSettle();

      expect(find.text('Quality may be too low'), findsOneWidget);
      expect(find.text('Quality Score: 35/100'), findsOneWidget);
      expect(find.text('Your text is highly illegible.'), findsOneWidget);
      
      // Submit button should be OutlinedButton (de-emphasized)
      final outlinedSubmit = find.widgetWithText(OutlinedButton, 'Submit Request');
      expect(outlinedSubmit, findsOneWidget);
    });

    testWidgets('Renders identity warning card correctly', (tester) async {
      final mismatchMetadata = {
        'ocr_text': 'Bob Smith Referral Doctor Robert',
        'quality_assessment': {
          'score': 85,
          'verdict': 'good',
          'issues': []
        },
        'identity_match': false,
        'submitted_with_warnings': true,
      };

      docProvider.setMockState(isProcessing: false, metadata: mismatchMetadata);

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      final cameraButton = find.widgetWithText(ElevatedButton, 'Camera');
      expect(cameraButton, findsOneWidget);
      await tester.tap(cameraButton);
      await tester.pumpAndSettle();

      expect(find.text('Name Mismatch Warning'), findsOneWidget);
      expect(find.text('Your name was not found on this document. If this document does belong to you, you may still submit it for receptionist review.'), findsOneWidget);
    });
  });
}
