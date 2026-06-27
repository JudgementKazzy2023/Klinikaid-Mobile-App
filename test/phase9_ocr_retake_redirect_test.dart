import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:drift/native.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:klinikaid_mobile/core/supabase/supabase_client.dart';
import 'package:klinikaid_mobile/core/cache/local_database.dart';
import 'package:klinikaid_mobile/features/auth/presentation/providers/auth_provider.dart';
import 'package:klinikaid_mobile/features/documents/presentation/providers/document_submission_provider.dart';
import 'package:klinikaid_mobile/features/documents/presentation/screens/submit_document_screen.dart';
import 'package:klinikaid_mobile/core/models/patient.dart';
import 'package:klinikaid_mobile/core/models/profile.dart';

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

// Mock DocumentSubmissionProvider subclass
class MockDocumentSubmissionProvider extends DocumentSubmissionProvider {
  MockDocumentSubmissionProvider(super.localDb);

  bool _mockIsProcessingOcr = false;
  Map<String, dynamic>? _mockPreScreenMetadata;

  @override
  bool get isProcessingOcr => _mockIsProcessingOcr;

  @override
  Map<String, dynamic>? get preScreenMetadata => _mockPreScreenMetadata;

  @override
  void clearOcrState() {
    _mockIsProcessingOcr = false;
    _mockPreScreenMetadata = null;
    super.clearOcrState();
  }

  @override
  Future<String> processOnDeviceOcr(String imagePath, Patient patient) async {
    _mockPreScreenMetadata = {
      'matched_fields': ['date', 'doctor', 'patient_name', 'request_keyword'],
      'missing_fields': [],
    };
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

  // Mock shared_preferences MethodChannel to avoid MissingPluginException in tests
  const channel = MethodChannel('plugins.flutter.io/shared_preferences');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
    if (methodCall.method == 'getAll') {
      return <String, Object>{};
    }
    return true;
  });

  late LocalDatabase db;
  late MockAuthProvider authProvider;
  late MockDocumentSubmissionProvider documentProvider;
  late Directory tempDir;
  late File tempFile;

  setUpAll(() async {
    await SupabaseService.initialize(localStorage: const EmptyLocalStorage());
  });

  setUp(() async {
    db = LocalDatabase(NativeDatabase.memory());
    authProvider = MockAuthProvider();
    documentProvider = MockDocumentSubmissionProvider(db);

    // Create a mock local file for the image picker to return
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
    authProvider.dispose();
    // Do not await db.close() in widget tests to avoid event loop hangs
    db.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  Widget createTestWidget() {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
        ChangeNotifierProvider<DocumentSubmissionProvider>.value(value: documentProvider),
      ],
      child: const MaterialApp(
        home: SubmitDocumentScreen(),
      ),
    );
  }

  group('Phase 9: OCR Retake Redirect Tests', () {
    testWidgets('Tapping Retake returns the patient to the OCR landing page and clears OCR state', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Assert that we are initially on the OCR landing page (Upload Diagnostic Referrals visible)
      expect(find.text('Upload Diagnostic Referrals'), findsOneWidget);
      expect(find.text('Document Review'), findsNothing);

      // Tap on the Camera button to trigger image pick and OCR processing
      final cameraButton = find.widgetWithText(ElevatedButton, 'Camera');
      expect(cameraButton, findsOneWidget);
      await tester.tap(cameraButton);
      await tester.pumpAndSettle();

      // Assert that we are now on the Preview screen (Document Review visible)
      expect(find.text('Upload Diagnostic Referrals'), findsNothing);
      expect(find.text('Document Review'), findsOneWidget);
      expect(documentProvider.preScreenMetadata, isNotNull);

      // Find the Retake button
      final retakeButton = find.widgetWithText(OutlinedButton, 'Retake');
      expect(retakeButton, findsOneWidget);

      // Tap the Retake button
      await tester.tap(retakeButton);
      await tester.pumpAndSettle();

      // Assert that we have returned to the OCR landing page
      expect(find.text('Upload Diagnostic Referrals'), findsOneWidget);
      expect(find.text('Document Review'), findsNothing);

      // Assert that the OCR provider's metadata state has been cleared
      expect(documentProvider.preScreenMetadata, isNull);
    });
  });
}
