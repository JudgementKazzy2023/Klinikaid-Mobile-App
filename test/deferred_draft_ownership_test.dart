import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:klinikaid_mobile/core/patient_submission_containment.dart';

import 'package:klinikaid_mobile/features/documents/presentation/screens/submit_document_screen.dart';
import 'support/upload_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late UploadFixture f;
  setUp(() async {
    PatientSubmissionContainment.activeForTesting = false;
    f = UploadFixture();
    await f.init();
  });
  tearDown(() async {
    try {
      await f.close();
    } finally {
      PatientSubmissionContainment.activeForTesting = true;
    }
  });
  test(
    'another account cannot see, resolve, sync or delete an owner draft',
    () async {
      await f.seed('owner-draft', UploadFixture.owner);
      await f.signIn(UploadFixture.other);
      expect(f.provider.queuedSubmissions, isEmpty);
      expect(await f.provider.resolveQueuedDraft('owner-draft'), false);
      await f.provider.removeQueuedItem('owner-draft');
      await f.provider.syncOfflineQueue();
      expect(await f.drafts(), hasLength(1));
      expect(f.requests, isEmpty);
      expect(await f.file.exists(), true);
    },
  );
  test('same-owner delete and bulk sync retain all drafts and files', () async {
    await f.seed('one', UploadFixture.owner);
    await f.seed('two', UploadFixture.owner);
    await f.provider.removeQueuedItem('one');
    await f.provider.syncOfflineQueue();
    expect(await f.drafts(), hasLength(2));
    expect(f.requests, isEmpty);
    expect(await f.file.exists(), true);
  });
  test(
    'account switch hides old rows immediately and restores them on owner login',
    () async {
      await f.seed('one', UploadFixture.owner);
      await f.seed('two', UploadFixture.other);
      await f.signIn(UploadFixture.other);
      expect(f.provider.queuedSubmissions.map((d) => d.id), ['two']);
      await f.signIn(UploadFixture.owner);
      expect(f.provider.queuedSubmissions.map((d) => d.id), ['one']);
      expect(f.requests, isEmpty);
    },
  );
  test(
    'unknown draft survives reopen with every field and stable request ID',
    () async {
      f.respond = (r) async => r.url.path.endsWith('/upload')
          ? f.json({'error_code': 'SERVER_ERROR', 'message': 'unknown'}, 503)
          : f.defaults(r);
      await f.submit();
      final before = (await f.drafts()).single;
      final bytes = await File(before.localFilePath).readAsBytes();
      await f.reopen();
      expect((await f.drafts()).single, before);
      expect(await File(before.localFilePath).readAsBytes(), bytes);
      final count = f.requests.length;
      expect(await f.submit(), false);
      expect(f.requests.length, count);
      expect(await f.drafts(), hasLength(1));
      f.respond = (r) async =>
          f.json({'error_code': 'SERVER_ERROR', 'message': 'unknown'}, 503);
      expect(await f.provider.resolveQueuedDraft(before.id), false);
      expect(f.requests.length, count + 1);
      expect(f.requests.last.url.path, endsWith('/upload/status'));
    },
  );
  test(
    'missing files are retained, never silently removed by sync or explicit review',
    () async {
      await f.seed('missing', UploadFixture.owner);
      await f.file.delete();
      await f.provider.syncOfflineQueue();
      expect(await f.provider.resolveQueuedDraft('missing'), false);
      expect(await f.drafts(), hasLength(1));
      expect(f.requests, hasLength(1));
      expect(f.requests.single.url.path, endsWith('/upload/status'));
    },
  );
  test(
    'explicit owner action submits exactly one legacy draft and leaves the other untouched',
    () async {
      await f.seed('one', UploadFixture.owner);
      await f.seed('two', UploadFixture.owner);
      await f.seed('foreign', UploadFixture.other);
      final original = (await f.drafts()).first;
      expect(await f.provider.resolveQueuedDraft('one'), true);
      expect((await f.drafts()).single.id, 'two');
      expect((await f.drafts(UploadFixture.other)).single.id, 'foreign');
      expect(
        f.requests.where((r) => r.url.path.endsWith('/upload')),
        hasLength(1),
      );
      expect(await f.file.exists(), true);
      expect(original.requestId, isNotNull);
      expect(f.requests.first.url.path, endsWith('/upload/status'));
    },
  );
  testWidgets(
    'opening and resuming the contained screen never replays or exposes removal controls',
    (tester) async {
      await f.seed('one', UploadFixture.owner);
      PatientSubmissionContainment.activeForTesting = true;
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: f.provider,
          child: const MaterialApp(home: SubmitDocumentScreen()),
        ),
      );
      await tester.pumpAndSettle();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text(PatientSubmissionContainment.message), findsOneWidget);
      expect(f.requests, isEmpty);
      expect(find.byIcon(Icons.delete_outline_rounded), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  test(
    'malformed saved metadata is preserved for clinic review without network',
    () async {
      await f.seed('malformed', UploadFixture.owner);
      await f.db.customStatement(
        'UPDATE offline_documents_queue SET extracted_metadata = ? WHERE id = ? AND uploader_id = ?',
        ['not valid JSON', 'malformed', UploadFixture.owner],
      );
      expect(await f.provider.resolveQueuedDraft('malformed'), false);
      expect(f.provider.errorCode, 'SERVER_DATA_INVALID');
      expect(f.requests, isEmpty);
      expect((await f.drafts()).single.extractedMetadata, 'not valid JSON');
      expect(await f.file.exists(), true);
    },
  );
}
