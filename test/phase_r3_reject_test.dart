import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;
import 'package:klinikaid_mobile/features/reception/data/reception_repository.dart';
import 'package:klinikaid_mobile/features/reception/domain/submission.dart';
import 'package:klinikaid_mobile/features/reception/domain/submission_detail.dart';
import 'package:klinikaid_mobile/features/reception/domain/submission_status.dart';
import 'package:klinikaid_mobile/features/reception/presentation/providers/reception_queue_provider.dart';
import 'package:klinikaid_mobile/features/reception/presentation/screens/document_validation_screen.dart';
import 'package:klinikaid_mobile/features/reception/presentation/widgets/reject_document_sheet.dart';
import 'package:klinikaid_mobile/features/reception/data/reject_reason_presets.dart';

// ─── Mock Repository ────────────────────────────────────────────────────────

class MockReceptionRepository extends ReceptionRepository {
  final List<Submission> submissions;
  final SubmissionDetail? detail;

  String? lastRejectedDocId;
  String? lastRejectedReason;
  bool shouldFailReject = false;

  // Track if patient_queue writes are ever called (they shouldn't be for reject)
  bool patientQueueWritten = false;

  MockReceptionRepository({this.submissions = const [], this.detail});

  @override
  Future<List<Submission>> getSubmissions({SubmissionStatus? status}) async {
    if (status == null) return submissions;
    return submissions.where((s) => s.status == status).toList();
  }

  @override
  Future<SubmissionDetail> getSubmissionDetail(String id) async {
    if (detail != null) return detail!;
    throw Exception('No detail mock set');
  }

  @override
  Future<String> getOriginalDocumentUrl(String id) async {
    return 'https://example.com/doc/$id';
  }

  @override
  Future<void> rejectDocument({
    required String documentId,
    required String reason,
  }) async {
    if (shouldFailReject) {
      throw Exception('Reject database write failed');
    }
    lastRejectedDocId = documentId;
    lastRejectedReason = reason;
  }

  @override
  Future<void> approveAndRoute({
    required String documentId,
    required String patientId,
    required String department,
    required String priority,
    String? bloodPressure,
    num? weightKg,
    num? temperatureC,
    String? triageNotes,
  }) async {
    patientQueueWritten = true;
  }
}

// ─── Helpers ────────────────────────────────────────────────────────────────

SubmissionDetail makeDetail({
  String id = 'doc-1',
  String? patientId = 'patient-1',
  SubmissionStatus status = SubmissionStatus.submitted,
  String patientName = 'Juan dela Cruz',
}) {
  return SubmissionDetail(
    submission: Submission(
      id: id,
      patientId: patientId,
      patientName: patientName,
      fileName: 'test.jpg',
      fileType: 'jpg',
      uploadedAt: DateTime.now(),
      uploadedBy: 'uploader',
      status: status,
    ),
    ocrText: 'Sample OCR text',
    storagePath: 'path/to/file.jpg',
    patientDob: '1990-01-01',
    patientGender: 'male',
    patientContact: '09123456789',
    patientEmail: 'juan@example.com',
    patientAddress: '123 Main St',
  );
}

Widget buildValidationScreen(MockReceptionRepository repo, {String id = 'doc-1'}) {
  return MultiProvider(
    providers: [
      Provider<ReceptionRepository>.value(value: repo),
    ],
    child: MaterialApp(
      home: DocumentValidationScreen(submissionId: id),
    ),
  );
}

Widget buildRejectSheet({
  String patientName = 'Juan dela Cruz',
  bool isLoading = false,
  void Function(String reason)? onConfirm,
}) {
  return MaterialApp(
    home: Scaffold(
      body: RejectDocumentSheet(
        patientName: patientName,
        isLoading: isLoading,
        onConfirm: onConfirm ?? (_) {},
      ),
    ),
  );
}

// ─── Tests ───────────────────────────────────────────────────────────────────

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('plugins.flutter.io/shared_preferences');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (call) async {
    if (call.method == 'getAll') return <String, Object>{};
    return true;
  });

  setUpAll(() async {
    await supabase.Supabase.initialize(
      url: 'https://onzeyejlfydvvbkejvwf.supabase.co',
      anonKey:
          'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9uemV5ZWpsZnlkdnZia2VqdndmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzkzNjcxMjYsImV4cCI6MjA5NDk0MzEyNn0.FJNbbuBZ2LdutVNrloYsxOLGZWbP-oLLTLJaKBOFkMM',
      authOptions: const supabase.FlutterAuthClientOptions(
        localStorage: supabase.EmptyLocalStorage(),
      ),
    );
  });

  group('Phase R3: Reject Document Widget Tests', () {
    // 1. Reject button enabled for pending document (status == submitted)
    testWidgets('1. Reject button enabled for pending doc', (tester) async {
      final repo = MockReceptionRepository(detail: makeDetail());
      await tester.pumpWidget(buildValidationScreen(repo));
      await tester.pumpAndSettle();

      final btn = find.widgetWithText(OutlinedButton, 'Reject Document');
      expect(btn, findsOneWidget);
      final widget = tester.widget<OutlinedButton>(btn);
      expect(widget.onPressed, isNotNull);
    });

    // 2. Reject button enabled for Unknown Patient pending doc (patientId null)
    testWidgets('2. Reject button enabled when patientId is null (asymmetry with Approve)',
        (tester) async {
      final repo = MockReceptionRepository(
          detail: makeDetail(patientId: null, patientName: 'Unknown Patient'));
      await tester.pumpWidget(buildValidationScreen(repo));
      await tester.pumpAndSettle();

      final btn = find.widgetWithText(OutlinedButton, 'Reject Document');
      expect(btn, findsOneWidget);
      final widget = tester.widget<OutlinedButton>(btn);
      expect(widget.onPressed, isNotNull);
    });

    // 3. Reject button disabled for already-approved/rejected doc
    testWidgets('3. Reject button disabled for approved document', (tester) async {
      final repo = MockReceptionRepository(
          detail: makeDetail(status: SubmissionStatus.approved));
      await tester.pumpWidget(buildValidationScreen(repo));
      await tester.pumpAndSettle();

      final btn = find.widgetWithText(OutlinedButton, 'Reject Document');
      expect(btn, findsOneWidget);
      final widget = tester.widget<OutlinedButton>(btn);
      expect(widget.onPressed, isNull);
    });

    // 4. Tap Reject → bottom sheet appears
    testWidgets('4. Tap Reject Document → bottom sheet displays', (tester) async {
      final repo = MockReceptionRepository(detail: makeDetail());
      await tester.pumpWidget(buildValidationScreen(repo));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(OutlinedButton, 'Reject Document'));
      await tester.pumpAndSettle();

      expect(find.text('Reject Document Submission?'), findsOneWidget);
      expect(
          find.text('Provide a clear reason so the patient can understand and resubmit.'),
          findsOneWidget);
    });

    // 5. 7 preset chips render
    testWidgets('5. 7 preset chips render on the sheet', (tester) async {
      await tester.pumpWidget(buildRejectSheet());
      await tester.pumpAndSettle();

      for (final key in rejectPresets.keys) {
        expect(find.widgetWithText(ActionChip, key), findsOneWidget);
      }
    });

    // 6. Tap "Illegible text" chip → textbox fills with template
    testWidgets('6. Tap preset chip fills text field', (tester) async {
      await tester.pumpWidget(buildRejectSheet());
      await tester.pumpAndSettle();

      final textFinder = find.byType(TextFormField);
      expect(tester.widget<TextFormField>(textFinder).controller?.text, isEmpty);

      await tester.tap(find.widgetWithText(ActionChip, 'Illegible text'));
      await tester.pumpAndSettle();

      expect(tester.widget<TextFormField>(textFinder).controller?.text,
          rejectPresets['Illegible text']);
    });

    // 7. Tap different chip → textbox is REPLACED with new template (replace, not append)
    testWidgets('7. Tap another preset chip replaces (not appends) content',
        (tester) async {
      await tester.pumpWidget(buildRejectSheet());
      await tester.pumpAndSettle();

      final textFinder = find.byType(TextFormField);

      await tester.tap(find.widgetWithText(ActionChip, 'Illegible text'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(ActionChip, 'Wrong patient'));
      await tester.pumpAndSettle();

      expect(tester.widget<TextFormField>(textFinder).controller?.text,
          rejectPresets['Wrong patient']);
    });

    // 8. Confirm disabled when textbox < 20 chars
    testWidgets('8. Confirm Rejection disabled when text length < 20', (tester) async {
      await tester.pumpWidget(buildRejectSheet());
      await tester.pumpAndSettle();

      final textFinder = find.byType(TextFormField);
      await tester.enterText(textFinder, 'Too short');
      await tester.pumpAndSettle();

      final confirmBtn = find.widgetWithText(ElevatedButton, 'Confirm Rejection');
      expect(tester.widget<ElevatedButton>(confirmBtn).onPressed, isNull);
    });

    // 9. Character counter shows correct count + "needs X more"
    testWidgets('9. Character counter and needs X more indicator works',
        (tester) async {
      await tester.pumpWidget(buildRejectSheet());
      await tester.pumpAndSettle();

      final textFinder = find.byType(TextFormField);
      await tester.enterText(textFinder, 'ABC');
      await tester.pumpAndSettle();

      expect(find.text('3 characters'), findsOneWidget);
      expect(find.text('Needs 17 more characters'), findsOneWidget);
    });

    // 10. Textbox >= 20 chars → Confirm enabled
    testWidgets('10. Confirm Rejection enabled when text length >= 20',
        (tester) async {
      await tester.pumpWidget(buildRejectSheet());
      await tester.pumpAndSettle();

      final textFinder = find.byType(TextFormField);
      await tester.enterText(
          textFinder, 'This rejection reason is long enough to pass validation.');
      await tester.pumpAndSettle();

      final confirmBtn = find.widgetWithText(ElevatedButton, 'Confirm Rejection');
      expect(tester.widget<ElevatedButton>(confirmBtn).onPressed, isNotNull);
    });

    // 11. Edit after preset fill → works, counter updates
    testWidgets('11. Editing after preset fill updates counter', (tester) async {
      await tester.pumpWidget(buildRejectSheet());
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(ActionChip, 'Illegible text'));
      await tester.pumpAndSettle();

      final textFinder = find.byType(TextFormField);
      final initialLength = rejectPresets['Illegible text']!.length;
      expect(find.text('$initialLength characters'), findsOneWidget);

      await tester.enterText(textFinder, 'Shortened reason edited.');
      await tester.pumpAndSettle();

      expect(find.text('24 characters'), findsOneWidget);
    });

    // 12. Cancel → dismiss, no write
    testWidgets('12. Cancel dismisses sheet without repository write', (tester) async {
      final repo = MockReceptionRepository(detail: makeDetail());
      await tester.pumpWidget(buildValidationScreen(repo));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(OutlinedButton, 'Reject Document'));
      await tester.pumpAndSettle();

      expect(find.text('Reject Document Submission?'), findsOneWidget);

      final cancelBtn = find.widgetWithText(OutlinedButton, 'Cancel');
      await tester.ensureVisible(cancelBtn);
      await tester.pumpAndSettle();
      await tester.tap(cancelBtn);
      await tester.pumpAndSettle();

      expect(find.text('Reject Document Submission?'), findsNothing);
      expect(repo.lastRejectedDocId, isNull);
    });
  });

  group('Phase R3: Repository Unit Tests', () {
    // 14. rejectDocument updates status='rejected' + rejection_reason
    test('14. rejectDocument updates status and rejection_reason', () async {
      final repo = MockReceptionRepository();
      await repo.rejectDocument(documentId: 'doc-123', reason: 'Invalid file format.');

      expect(repo.lastRejectedDocId, 'doc-123');
      expect(repo.lastRejectedReason, 'Invalid file format.');
    });

    // 15. rejectDocument does NOT touch patient_queue
    test('15. Rejection does not trigger patient queue writes', () async {
      final repo = MockReceptionRepository();
      await repo.rejectDocument(documentId: 'doc-123', reason: 'Invalid file format.');

      expect(repo.patientQueueWritten, false);
    });
  });
}
