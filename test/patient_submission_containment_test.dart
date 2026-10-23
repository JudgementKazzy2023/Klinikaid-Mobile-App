import 'dart:convert';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:http/http.dart' as http;
// ignore: depend_on_referenced_packages
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:klinikaid_mobile/core/cache/local_database.dart';
import 'package:klinikaid_mobile/core/models/document.dart';
import 'package:klinikaid_mobile/core/models/patient.dart';
import 'package:klinikaid_mobile/core/patient_submission_containment.dart';
import 'package:klinikaid_mobile/core/repositories/documents_repository.dart';
import 'package:klinikaid_mobile/features/documents/presentation/providers/document_submission_provider.dart';
import 'package:klinikaid_mobile/features/documents/presentation/screens/submit_document_screen.dart';
import 'package:klinikaid_mobile/features/patient/templates/data/templates_repository.dart';
import 'package:klinikaid_mobile/features/patient/templates/document_templates.dart';
import 'package:klinikaid_mobile/features/patient/templates/presentation/providers/templates_provider.dart';
import 'package:klinikaid_mobile/features/patient/templates/presentation/screens/template_form_renderer_screen.dart';

// No global Supabase initialization, live credentials, realtime subscription,
// camera, OCR, or path-provider calls. All HTTP is intercepted (Storage too).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SupabaseClient client;
  late LocalDatabase db;
  late DocumentSubmissionProvider uploads;
  late Directory temp;
  late File savedFile;
  // Every row, all owners: getQueuedDocuments is owner-scoped (#27).
  Future<List<OfflineDocument>> allQueued() => db.select(db.offlineDocumentsQueue).get();
  final requests = <http.Request>[];
  final now = DateTime.utc(2026, 10, 20);
  final document = Document(
    id: 'doc', uploaderId: 'owner', fileName: 'fixture.txt',
    filePath: 'owner/fixture.txt', fileType: 'txt',
    status: DocumentStatus.pending, createdAt: now, updatedAt: now,
  );
  final patient = Patient(
    id: 'patient', firstName: 'Fixture', lastName: 'Patient',
    dateOfBirth: DateTime(1990), gender: Gender.other, contactNumber: '',
    address: '', createdAt: now, updatedAt: now,
  );

  setUp(() async {
    requests.clear();
    client = SupabaseClient('https://example.invalid', 'fake-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        requests.add(request);
        if (request.method != 'GET') {
          throw StateError('Unexpected network write: ${request.url.path}');
        }
        return http.Response(jsonEncode([document.toJson()]), 200,
          request: request,
          headers: {'content-type': 'application/json'});
      }),
    );
    // setInitialSession is a local-only assignment; never sign in or refresh.
    await client.auth.setInitialSession(jsonEncode({
      'access_token': '${base64Url.encode(utf8.encode('{"alg":"HS256"}'))}.'
          '${base64Url.encode(utf8.encode(jsonEncode({
            'sub': 'owner',
            'exp': DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/ 1000,
          })))}.fixture',
      'refresh_token': 'fixture-refresh',
      'token_type': 'bearer', 'expires_in': 3600,
      'user': {'id': 'owner', 'app_metadata': {}, 'user_metadata': {},
        'aud': 'authenticated', 'created_at': now.toIso8601String()},
    }));
    temp = await Directory.systemTemp.createTemp('containment-test-');
    savedFile = File('${temp.path}/draft.txt');
    await savedFile.writeAsString('Synthetic draft fixture');
    db = LocalDatabase(NativeDatabase(File('${temp.path}/queue.sqlite')));
    for (final id in ['saved', 'missing', 'other-owner']) {
      await db.queueOfflineDocument(OfflineDocument(
        id: id, patientId: 'patient',
        uploaderId: id == 'other-owner' ? 'another-owner' : 'owner',
        fileName: '$id.txt',
        localFilePath: id == 'missing' ? '${temp.path}/absent.txt' : savedFile.path,
        fileType: 'txt', ocrText: 'Fixture OCR',
        extractedMetadata: '{"document_type":"lab-request"}', createdAt: now,
      ));
    }
    uploads = DocumentSubmissionProvider(db, client: client);
    await Future<void>.delayed(Duration.zero);
    await allQueued();
  });

  tearDown(() async {
    uploads.dispose();
    await db.close();
    await client.dispose();
    await temp.delete(recursive: true);
  });

  test('repository writes are blocked; patient reads still work', () async {
    final repo = DocumentsRepository(client: client);
    await expectLater(repo.insertDocument(document), throwsStateError);
    await expectLater(repo.updatePendingDocument(document), throwsStateError);
    await expectLater(TemplatesRepository(client: client).submitTemplateDocument(
      patientId: 'patient', uploaderId: 'owner', templateId: 'lab-request',
      templateName: 'Lab', extractedMetadata: {},
    ), throwsStateError);
    expect(requests, isEmpty);
    expect((await repo.getDocumentsForPatient('owner')).single.id, 'doc');
    expect(requests.single.method, 'GET');
    expect(requests.single.url.queryParameters['uploader_id'], 'eq.owner');
  });

  test('template guard retains input and never reports success', () async {
    final provider = TemplatesProvider();
    final values = <String, dynamic>{'tests_requested': 'Fixture'};
    expect(await provider.submitTemplate(
      patientId: 'patient', uploaderId: 'owner', templateId: 'lab-request',
      templateName: 'Lab', formValues: values, patientName: 'Fixture',
    ), isFalse);
    expect(values, {'tests_requested': 'Fixture'});
    expect(provider.success, isFalse);
    expect(provider.isLoading, isFalse);
    expect(provider.errorMessage, PatientSubmissionContainment.message);
    expect(requests, isEmpty);
    provider.dispose();
  });

  test('upload blocks before Storage or offline fallback, retaining metadata', () async {
    final before = await allQueued();
    uploads.setTestDetectionStateForTest(
      ocrText: 'Fixture OCR', preScreenMetadata: {'document_type': 'lab-request'},
    );
    for (final offline in [false, true]) {
      expect(await uploads.submitDocument(
        localFilePath: savedFile.path, originalFileName: 'draft.txt',
        fileExtension: 'txt', patient: patient, documentType: 'lab-request',
        isTest: offline,
      ), isFalse);
    }
    expect(uploads.errorMessage, PatientSubmissionContainment.message);
    expect(uploads.isLoading, isFalse);
    expect(uploads.extractedOcrText, 'Fixture OCR');
    expect(uploads.preScreenMetadata, {'document_type': 'lab-request'});
    expect(await allQueued(), before);
    expect(await savedFile.readAsString(), 'Synthetic draft fixture');
    expect(requests, isEmpty);
  });

  test('manual sync holds every row and file across database reopen', () async {
    final before = await allQueued();
    for (var i = 0; i < 5; i++) {
      await uploads.syncOfflineQueue();
    }
    await uploads.removeQueuedItem('saved');
    expect(await allQueued(), before);
    uploads.dispose();
    await db.close();
    db = LocalDatabase(NativeDatabase(File('${temp.path}/queue.sqlite')));
    uploads = DocumentSubmissionProvider(db, client: client);
    await allQueued();
    await uploads.syncOfflineQueue();
    expect(await allQueued(), before);
    expect(await savedFile.readAsString(), 'Synthetic draft fixture');
    expect(requests, isEmpty);
  });

  testWidgets('opening and resuming upload never replays drafts', (tester) async {
    final before = await allQueued();
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: uploads, child: const MaterialApp(home: SubmitDocumentScreen()),
    ));
    await tester.pumpAndSettle();
    expect(find.text(PatientSubmissionContainment.message), findsOneWidget);
    expect(find.text('Submit Request'), findsNothing);
    expect(find.byType(Dismissible), findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 10));
    expect(find.text(PatientSubmissionContainment.message), findsOneWidget);
    expect(requests, isEmpty);
    await tester.runAsync(() async {
      expect(await allQueued(), before);
      expect(await savedFile.exists(), isTrue);
    });
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('all template routes prevent form entry with persistent notice', (tester) async {
    for (final template in clinicTemplates) {
      await tester.pumpWidget(MaterialApp(home: TemplateFormRendererScreen(
        key: ValueKey(template.id), templateId: template.id,
      )));
      await tester.pumpAndSettle();
      expect(find.text(PatientSubmissionContainment.message), findsOneWidget);
      expect(find.byType(Form), findsNothing);
      expect(find.byType(TextFormField), findsNothing);
      expect(find.byType(Dismissible), findsNothing);
    }
    expect(requests, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
