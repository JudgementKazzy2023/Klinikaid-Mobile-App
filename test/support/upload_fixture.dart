import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:http/http.dart' as http;
// ignore: depend_on_referenced_packages
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:klinikaid_mobile/core/cache/local_database.dart';
import 'package:klinikaid_mobile/core/models/patient.dart';
import 'package:klinikaid_mobile/features/documents/presentation/providers/document_submission_provider.dart';

class UploadFixture {
  static const owner = '11111111-1111-4111-8111-111111111111';
  static const other = '22222222-2222-4222-8222-222222222222';
  static const patientId = '33333333-3333-4333-8333-333333333333';
  late SupabaseClient client;
  late LocalDatabase db;
  late DocumentSubmissionProvider provider;
  late Directory temp;
  late File file;
  final requests = <http.Request>[];
  late Future<http.Response> Function(http.Request) respond;
  http.Response json(Object body, int status) => http.Response(
    jsonEncode(body),
    status,
    headers: {'content-type': 'application/json'},
  );
  Future<void> init() async {
    temp = await Directory.systemTemp.createTemp('upload-fixture-');
    file = File('${temp.path}/request.pdf');
    await file.writeAsString('%PDF-1.7 fixture');
    respond = defaults;
    client = SupabaseClient(
      'https://example.invalid',
      'fixture-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        requests.add(request);
        final response = await respond(request);
        return http.Response.bytes(
          response.bodyBytes,
          response.statusCode,
          headers: response.headers,
          request: request,
        );
      }),
    );
    await signIn(owner);
    db = LocalDatabase(NativeDatabase(File('${temp.path}/drafts.sqlite')));
    provider = DocumentSubmissionProvider(
      db,
      client: client,
      draftDirectory: temp,
    );
    await db.getQueuedDocuments(owner);
    await Future<void>.delayed(Duration.zero);
  }

  Future<http.Response> defaults(http.Request request) async {
    if (request.url.path.endsWith('/documents')) return json([], 200);
    if (request.url.path.endsWith('/logout')) return json({}, 200);
    if (request.url.path.endsWith('/upload/status'))
      return json({'state': 'not_found'}, 200);
    if (request.url.path.endsWith('/upload'))
      return json({
        'document_id': 'submitted-document',
        'status': 'pending',
        'replayed': false,
      }, 200);
    if (request.url.path.contains('/storage/'))
      return json({'Key': 'pending-file'}, 200);
    if (request.url.path.endsWith('/pending_document_ocr'))
      return http.Response('', 201);
    throw StateError('Unexpected mocked request ${request.url.path}');
  }

  Future<void> signIn(String owner) async {
    final jwt =
        '${base64Url.encode(utf8.encode('{"alg":"HS256"}'))}.${base64Url.encode(utf8.encode(jsonEncode({'sub': owner, 'exp': DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/ 1000})))}.fixture';
    await client.auth.setInitialSession(
      jsonEncode({
        'access_token': jwt,
        'refresh_token': 'fixture',
        'token_type': 'bearer',
        'expires_in': 3600,
        'user': {
          'id': owner,
          'app_metadata': {},
          'user_metadata': {},
          'aud': 'authenticated',
          'created_at': '2026-10-23T00:00:00Z',
        },
      }),
    );
    await Future<void>.delayed(Duration.zero);
  }

  Patient patient({String ownerId = owner}) => Patient(
    id: patientId,
    profileId: ownerId,
    firstName: 'Synthetic',
    lastName: 'Patient',
    dateOfBirth: DateTime(1990),
    gender: Gender.other,
    contactNumber: '',
    address: '',
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );
  Future<bool> submit({
    String category = 'lab-request',
    List<String>? selected,
    Patient? asPatient,
  }) => provider.submitDocument(
    localFilePath: file.path,
    originalFileName: 'request.pdf',
    fileExtension: 'pdf',
    patient: asPatient ?? patient(),
    documentType: category,
    selectedTestIds: selected,
  );
  Future<List<OfflineDocument>> drafts([String user = owner]) =>
      db.getQueuedDocuments(user);
  Future<void> seed(
    String id,
    String user, {
    String state = 'legacy',
    String? requestId,
  }) => db.queueOfflineDocument(
    OfflineDocument(
      id: id,
      patientId: patientId,
      uploaderId: user,
      fileName: 'legacy.pdf',
      localFilePath: file.path,
      fileType: 'pdf',
      ocrText: '',
      extractedMetadata: '{"document_type":"other"}',
      createdAt: DateTime(2026),
      requestId: requestId,
      uploadState: state,
    ),
  );
  Future<void> reopen({bool alreadyDisposed = false}) async {
    if (!alreadyDisposed) provider.dispose();
    await db.close();
    db = LocalDatabase(NativeDatabase(File('${temp.path}/drafts.sqlite')));
    provider = DocumentSubmissionProvider(
      db,
      client: client,
      draftDirectory: temp,
    );
    await db.getQueuedDocuments(owner);
    await Future<void>.delayed(Duration.zero);
  }

  Future<void> close() async {
    provider.dispose();
    await db.close();
    await client.dispose();
    await temp.delete(recursive: true);
  }
}
