import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:drift/native.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:klinikaid_mobile/core/supabase/supabase_client.dart';
import 'package:klinikaid_mobile/core/cache/local_database.dart';
import 'package:klinikaid_mobile/core/models/patient.dart';
import 'package:klinikaid_mobile/core/models/profile.dart';
import 'package:klinikaid_mobile/features/auth/presentation/providers/auth_provider.dart';
import 'package:klinikaid_mobile/features/documents/presentation/providers/document_submission_provider.dart';
import 'package:klinikaid_mobile/features/documents/presentation/screens/submit_document_screen.dart';

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
  @override
  Profile? get profile => Profile(
        id: 'patient-uuid-123',
        fullName: 'Jane Miller',
        role: UserRole.patient,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
}

// Mock DocumentSubmissionProvider to inject different pre-screen states
class MockDocProvider extends DocumentSubmissionProvider {
  MockDocProvider(super.localDb);

  bool _mockIsProcessingOcr = false;
  Map<String, dynamic>? _mockMetadata;
  String? _mockImagePath;
  bool _mockSubmitSuccess = true;
  bool submitCalled = false;

  void setMockState({required bool isProcessing, Map<String, dynamic>? metadata}) {
    _mockIsProcessingOcr = isProcessing;
    _mockMetadata = metadata;
    _mockImagePath = metadata != null ? 'mock_image.jpg' : null;
    notifyListeners();
  }

  void setMockSubmitSuccess(bool val) {
    _mockSubmitSuccess = val;
  }

  @override
  bool get isProcessingOcr => _mockIsProcessingOcr;

  @override
  Map<String, dynamic>? get preScreenMetadata => _mockMetadata;

  @override
  String? get selectedImagePath => _mockImagePath;

  @override
  bool get hasCachedSubmission => _mockImagePath != null && _mockMetadata != null;

  @override
  void clearOcrState() {
    _mockIsProcessingOcr = false;
    _mockMetadata = null;
    _mockImagePath = null;
    super.clearOcrState();
  }

  @override
  Future<String> processOnDeviceOcr(String imagePath, Patient patient) async {
    _mockImagePath = imagePath;
    notifyListeners();
    return "Mock OCR Text";
  }

  @override
  Future<bool> submitDocument({
    required String localFilePath,
    required String originalFileName,
    required String fileExtension,
    required Patient patient,
    required String documentType,
    bool isTest = false,
  }) async {
    submitCalled = true;
    if (_mockSubmitSuccess) {
      clearOcrState();
      return true;
    }
    return false;
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

  group('OCR Poor Quality Confirmation Popup Tests', () {
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
      try {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      } catch (_) {}
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

    Future<void> selectDocumentType(WidgetTester tester) async {
      final picker = find.byKey(const Key('document_type_picker'));
      await tester.ensureVisible(picker);
      await tester.tap(picker);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Other / Uncategorized').last);
      await tester.pumpAndSettle();
    }

    testWidgets('1. Score 50 triggers the confirmation popup and warning card is displayed', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final metadata = {
        'ocr_text': 'Jane Miller Referral Doctor Robert',
        'quality_assessment': {
          'score': 50,
          'verdict': 'poor',
          'issues': [
            {
              'type': 'blur',
              'severity': 'high',
              'description': 'Blurry details.'
            }
          ]
        },
        'identity_match': true,
        'submitted_with_warnings': true,
      };

      docProvider.setMockState(isProcessing: false, metadata: metadata);

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();
      await selectDocumentType(tester);

      // Check that the warning card is displayed (additive warning card)
      expect(find.text('Low quality'), findsOneWidget);
      expect(find.textContaining('This document may be hard to read'), findsOneWidget);

      // Tap submit
      final submitBtn = find.widgetWithText(ElevatedButton, 'Submit Request');
      expect(submitBtn, findsOneWidget);
      await tester.ensureVisible(submitBtn);
      await tester.tap(submitBtn);
      await tester.pumpAndSettle();

      // Popup should be visible
      expect(find.text('Confirm Submission'), findsOneWidget);
      expect(find.textContaining('This document is poor quality. Are you sure you want to submit it?'), findsOneWidget);
    });

    testWidgets('2. Score 51 does NOT trigger the popup, submits directly', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final metadata = {
        'ocr_text': 'Jane Miller Referral Doctor Robert',
        'quality_assessment': {
          'score': 51,
          'verdict': 'poor',
          'issues': [
            {
              'type': 'blur',
              'severity': 'high',
              'description': 'Blurry details.'
            }
          ]
        },
        'identity_match': true,
        'submitted_with_warnings': true,
      };

      docProvider.setMockState(isProcessing: false, metadata: metadata);

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();
      await selectDocumentType(tester);

      // Warning card is still shown because score < 85
      expect(find.text('Low quality'), findsOneWidget);

      // Tap submit
      final submitBtn = find.widgetWithText(ElevatedButton, 'Submit Request');
      await tester.ensureVisible(submitBtn);
      await tester.tap(submitBtn);
      await tester.pumpAndSettle();

      // NO popup should appear, submits directly
      expect(find.text('Confirm Submission'), findsNothing);
      expect(docProvider.submitCalled, isTrue);
    });

    testWidgets('3. Score 30 triggers the popup', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final metadata = {
        'ocr_text': 'Jane Miller Referral Doctor Robert',
        'quality_assessment': {
          'score': 30,
          'verdict': 'poor',
          'issues': []
        },
        'identity_match': true,
        'submitted_with_warnings': true,
      };

      docProvider.setMockState(isProcessing: false, metadata: metadata);

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();
      await selectDocumentType(tester);

      final submitBtn = find.widgetWithText(ElevatedButton, 'Submit Request');
      await tester.ensureVisible(submitBtn);
      await tester.tap(submitBtn);
      await tester.pumpAndSettle();

      expect(find.text('Confirm Submission'), findsOneWidget);
    });

    testWidgets('4. Score 90 does NOT trigger popup', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final metadata = {
        'ocr_text': 'Jane Miller Referral Doctor Robert',
        'quality_assessment': {
          'score': 90,
          'verdict': 'good',
          'issues': []
        },
        'identity_match': true,
        'submitted_with_warnings': false,
      };

      docProvider.setMockState(isProcessing: false, metadata: metadata);

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();
      await selectDocumentType(tester);

      final submitBtn = find.widgetWithText(ElevatedButton, 'Submit Request');
      await tester.ensureVisible(submitBtn);
      await tester.tap(submitBtn);
      await tester.pumpAndSettle();

      expect(find.text('Confirm Submission'), findsNothing);
      expect(docProvider.submitCalled, isTrue);
    });

    testWidgets('5. Popup Cancel aborts submission', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final metadata = {
        'ocr_text': 'Jane Miller Referral Doctor Robert',
        'quality_assessment': {
          'score': 45,
          'verdict': 'poor',
          'issues': []
        },
        'identity_match': true,
        'submitted_with_warnings': true,
      };

      docProvider.setMockState(isProcessing: false, metadata: metadata);

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();
      await selectDocumentType(tester);

      final submitBtn = find.widgetWithText(ElevatedButton, 'Submit Request');
      await tester.ensureVisible(submitBtn);
      await tester.tap(submitBtn);
      await tester.pumpAndSettle();

      expect(find.text('Confirm Submission'), findsOneWidget);

      // Tap Cancel
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      // Dialog is gone, submission not executed
      expect(find.text('Confirm Submission'), findsNothing);
      expect(docProvider.submitCalled, isFalse);
    });

    testWidgets('6. Popup Submit Anyway proceeds with upload', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final metadata = {
        'ocr_text': 'Jane Miller Referral Doctor Robert',
        'quality_assessment': {
          'score': 45,
          'verdict': 'poor',
          'issues': []
        },
        'identity_match': true,
        'submitted_with_warnings': true,
      };

      docProvider.setMockState(isProcessing: false, metadata: metadata);

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();
      await selectDocumentType(tester);

      final submitBtn = find.widgetWithText(ElevatedButton, 'Submit Request');
      await tester.ensureVisible(submitBtn);
      await tester.tap(submitBtn);
      await tester.pumpAndSettle();

      expect(find.text('Confirm Submission'), findsOneWidget);

      // Tap Submit Anyway
      await tester.tap(find.text('Submit Anyway'));
      await tester.pumpAndSettle();

      // Dialog is gone, submission executed
      expect(find.text('Confirm Submission'), findsNothing);
      expect(docProvider.submitCalled, isTrue);
    });
  });
}
