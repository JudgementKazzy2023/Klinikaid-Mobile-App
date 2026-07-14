import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:klinikaid_mobile/core/cache/local_database.dart';
import 'package:klinikaid_mobile/core/models/patient.dart';
import 'package:klinikaid_mobile/core/supabase/supabase_client.dart';
import 'package:klinikaid_mobile/features/auth/presentation/providers/auth_provider.dart';
import 'package:klinikaid_mobile/features/documents/presentation/providers/document_submission_provider.dart';
import 'package:klinikaid_mobile/features/documents/presentation/screens/submit_document_screen.dart';
import 'package:klinikaid_mobile/features/patient/templates/presentation/providers/templates_provider.dart';
import 'package:klinikaid_mobile/features/patient/submissions/document_dedup.dart';

// Simple Mocks for Supabase Client query chain
class FakeFilterBuilder extends Fake implements PostgrestFilterBuilder<List<Map<String, dynamic>>> {
  final List<Map<String, dynamic>> data;
  FakeFilterBuilder(this.data);

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #eq || invocation.memberName == #select) {
      return this;
    }
    return super.noSuchMethod(invocation);
  }

  @override
  Future<S> then<S>(FutureOr<S> Function(List<Map<String, dynamic>> value) onValue, {Function? onError}) {
    return Future.value(data).then(onValue, onError: onError);
  }

  @override
  Future<List<Map<String, dynamic>>> timeout(Duration timeLimit, {FutureOr<List<Map<String, dynamic>>> Function()? onTimeout}) {
    return Future.value(data);
  }

  @override
  Future<List<Map<String, dynamic>>> catchError(Function onError, {bool Function(Object error)? test}) {
    return Future.value(data);
  }

  @override
  Future<List<Map<String, dynamic>>> whenComplete(FutureOr Function() action) {
    return Future.value(data);
  }

  @override
  Stream<List<Map<String, dynamic>>> asStream() {
    return Stream.value(data);
  }
}

class FakeQueryBuilder extends Fake implements SupabaseQueryBuilder {
  final List<Map<String, dynamic>> mockData;
  FakeQueryBuilder(this.mockData);

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #select) {
      return FakeFilterBuilder(mockData);
    }
    return super.noSuchMethod(invocation);
  }
}

class FakeSupabaseClient extends Fake implements SupabaseClient {
  List<Map<String, dynamic>> mockDocuments = [];

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #from) {
      return FakeQueryBuilder(mockDocuments);
    }
    return super.noSuchMethod(invocation);
  }
}

class MockAuthProvider extends AuthProvider {
  final Patient? mockPatient;
  MockAuthProvider({this.mockPatient});

  @override
  bool get isAuthenticated => true;
  @override
  bool get isLoading => false;
  @override
  Patient? get patient => mockPatient;
}

class MockDocumentSubmissionProvider extends DocumentSubmissionProvider {
  String? mockImagePath;
  Map<String, dynamic>? mockMetadata;
  String? mockErrorMessage;

  MockDocumentSubmissionProvider() : super(LocalDatabase());

  @override
  String? get selectedImagePath => mockImagePath;
  @override
  Map<String, dynamic>? get preScreenMetadata => mockMetadata;
  @override
  bool get hasCachedSubmission => mockImagePath != null;
  @override
  bool get isProcessing => false;
  @override
  bool get isProcessingOcr => false;
  @override
  List<OfflineDocument> get queuedSubmissions => [];
  @override
  List<OfflineDocument> get orphanedSubmissions => [];
  @override
  String? get errorMessage => mockErrorMessage;

  @override
  Future<bool> submitDocument({
    required String localFilePath,
    required String originalFileName,
    required String fileExtension,
    required Patient patient,
    required String documentType,
    bool isTest = false,
  }) async {
    final duplicateDate = await checkPendingDuplicate(patient.id, documentType);
    if (duplicateDate != null) {
      final label = getCategoryLabel(documentType);
      mockErrorMessage = "You already have a pending [$label] submitted on $duplicateDate. You can submit a new one once it's reviewed.";
      return false;
    }
    return true;
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
    await Supabase.initialize(
      url: 'https://onzeyejlfydvvbkejvwf.supabase.co',
      anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9uemV5ZWpsZnlkdnZia2VqdndmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzkzNjcxMjYsImV4cCI6MjA5NDk0MzEyNn0.FJNbbuBZ2LdutVNrloYsxOLGZWbP-oLLTLJaKBOFkMM',
      authOptions: const FlutterAuthClientOptions(
        localStorage: EmptyLocalStorage(),
      ),
    );
  });

  late FakeSupabaseClient fakeClient;
  late Patient testPatient;

  setUp(() {
    fakeClient = FakeSupabaseClient();
    SupabaseService.mockClient = fakeClient;

    testPatient = Patient(
      id: 'patient-row-id-123',
      profileId: 'profile-uuid-456',
      firstName: 'Alice',
      lastName: 'Smith',
      dateOfBirth: DateTime(1995, 8, 10),
      gender: Gender.female,
      contactNumber: '09171234567',
      address: 'Manila, PH',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  });

  tearDown(() {
    SupabaseService.mockClient = null;
  });

  group('Patient Upload Deduplication — Category Resolver Unit Tests', () {
    test('resolveDocumentCategory correctly resolves template and upload types', () {
      // Template
      expect(
        resolveDocumentCategory('template', {'template_id': 'lab-request'}),
        equals('lab-request'),
      );
      // Upload
      expect(
        resolveDocumentCategory('pdf', {'document_type': 'referral-form'}),
        equals('referral-form'),
      );
      // Legacy upload (missing type)
      expect(
        resolveDocumentCategory('jpg', {}),
        equals('other'),
      );
      // Legacy template missing id
      expect(
        resolveDocumentCategory('template', {}),
        equals('other'),
      );
    });

    test('getCategoryLabel resolves standard templates and fallback other', () {
      expect(getCategoryLabel('lab-request'), equals('Laboratory Request'));
      expect(getCategoryLabel('other'), equals('Other'));
      expect(getCategoryLabel('custom-type'), equals('custom-type'));
    });
  });

  group('Patient Upload Deduplication — Dedup Logic Unit Tests', () {
    test('Pending document of same type blocks submission; approved/rejected does not; other exempt', () async {
      // 1. Pending template lab-request blocks a new upload or template
      fakeClient.mockDocuments = [
        {
          'file_type': 'template',
          'status': 'pending',
          'extracted_metadata': {'template_id': 'lab-request'},
          'created_at': DateTime.now().toUtc().toIso8601String(),
        }
      ];

      final blockedDate = await checkPendingDuplicate(testPatient.id, 'lab-request');
      expect(blockedDate, isNotNull); // Blocked!

      final allowedDate = await checkPendingDuplicate(testPatient.id, 'referral-form');
      expect(allowedDate, isNull); // Allowed (different type)!

      final otherDate = await checkPendingDuplicate(testPatient.id, 'other');
      expect(otherDate, isNull); // Exempt!

      // 2. Approved same-type document does not block
      fakeClient.mockDocuments = [
        {
          'file_type': 'template',
          'status': 'approved',
          'extracted_metadata': {'template_id': 'lab-request'},
          'created_at': DateTime.now().toUtc().toIso8601String(),
        }
      ];
      final approvedCheck = await checkPendingDuplicate(testPatient.id, 'lab-request');
      expect(approvedCheck, isNull); // Allowed (no longer pending)!

      // 3. Rejected same-type document does not block
      fakeClient.mockDocuments = [
        {
          'file_type': 'template',
          'status': 'rejected',
          'extracted_metadata': {'template_id': 'lab-request'},
          'created_at': DateTime.now().toUtc().toIso8601String(),
        }
      ];
      final rejectedCheck = await checkPendingDuplicate(testPatient.id, 'lab-request');
      expect(rejectedCheck, isNull); // Allowed (no longer pending)!
    });
  });

  group('Patient Upload Deduplication — Widget & Provider Tests', () {
    testWidgets('Upload screen shows Document Type dropdown picker, requires selection, blocks duplicate', (tester) async {
      // Setup mock pending document
      fakeClient.mockDocuments = [
        {
          'file_type': 'template',
          'status': 'pending',
          'extracted_metadata': {'template_id': 'lab-request'},
          'created_at': DateTime.now().toUtc().toIso8601String(),
        }
      ];

      final submissionProvider = MockDocumentSubmissionProvider();
      submissionProvider.mockImagePath = 'test_image.jpg';
      submissionProvider.mockMetadata = {'quality_assessment': {'score': 90, 'verdict': 'pass', 'issues': []}};

      final authProvider = MockAuthProvider(mockPatient: testPatient);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
            ChangeNotifierProvider<DocumentSubmissionProvider>.value(value: submissionProvider),
          ],
          child: const MaterialApp(
            home: SubmitDocumentScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Submit without selecting category -> SnackBar warning
      final submitBtn = find.text('Submit Request');
      expect(submitBtn, findsOneWidget);
      await tester.ensureVisible(submitBtn);
      await tester.pumpAndSettle();
      await tester.tap(submitBtn);
      await tester.pumpAndSettle();

      expect(find.text('Please select a Document Type before submitting.'), findsOneWidget);

      // Select "Laboratory Request" (which is pending, so it should be blocked)
      final dropdown = find.byKey(const Key('document_type_picker'));
      expect(dropdown, findsOneWidget);
      await tester.ensureVisible(dropdown);
      await tester.pumpAndSettle();
      await tester.tap(dropdown);
      await tester.pumpAndSettle();

      // Find "Laboratory Request" item in drop down list and tap it
      await tester.tap(find.text('Laboratory Request').last);
      await tester.pumpAndSettle();

      // Tap submit again -> blocks with SnackBar duplicate error
      await tester.ensureVisible(submitBtn);
      await tester.pumpAndSettle();
      await tester.tap(submitBtn);
      await tester.pumpAndSettle();

      print('DEBUG mockErrorMessage is: ${submissionProvider.mockErrorMessage}');
      expect(
        find.textContaining('You already have a pending [Laboratory Request] submitted on'),
        findsOneWidget,
      );
    });
  });
}
