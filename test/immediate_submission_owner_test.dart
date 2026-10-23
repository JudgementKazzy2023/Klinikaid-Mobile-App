import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:klinikaid_mobile/core/patient_submission_containment.dart';
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
  for (final stage in ['storage', 'assessment', 'submission']) {
    test(
      'identity switch during $stage dispatches nothing afterwards and reports no stale success',
      () async {
        final started = Completer<void>();
        final release = Completer<void>();
        f.respond = (r) async {
          final gate = stage == 'storage'
              ? r.url.path.contains('/storage/')
              : stage == 'assessment'
              ? r.url.path.endsWith('/pending_document_ocr')
              : r.url.path.endsWith('/upload');
          if (gate) {
            started.complete();
            await release.future;
          }
          return f.defaults(r);
        };
        final result = f.submit();
        await started.future;
        final before = f.requests.length;
        await f.signIn(UploadFixture.other);
        release.complete();
        expect(await result, false);
        expect(f.requests.length, before);
        expect(await f.drafts(), hasLength(1));
        expect(f.provider.queuedSubmissions, isEmpty);
        expect(await f.drafts(UploadFixture.other), isEmpty);
      },
    );
  }
  test(
    'patient linked to another profile is refused before any network operation',
    () async {
      expect(
        await f.submit(asPatient: f.patient(ownerId: UploadFixture.other)),
        false,
      );
      expect(f.requests, isEmpty);
      expect(await f.drafts(), isEmpty);
    },
  );
  test('signed out refuses before network or draft writes', () async {
    await f.client.auth.signOut(scope: SignOutScope.local);
    f.requests.clear();
    expect(await f.submit(), false);
    expect(f.requests, isEmpty);
    expect(await f.drafts(), isEmpty);
  });
  test(
    'concurrent submits cannot supersede one another or send twice',
    () async {
      final started = Completer<void>();
      final release = Completer<void>();
      f.respond = (r) async {
        if (r.url.path.contains('/storage/')) {
          started.complete();
          await release.future;
        }
        return f.defaults(r);
      };
      final first = f.submit();
      await started.future;
      expect(await f.submit(), false);
      release.complete();
      expect(await first, true);
      expect(
        f.requests.where((r) => r.url.path.endsWith('/upload')),
        hasLength(1),
      );
    },
  );
  test('completion after dispose does not mutate state or notify', () async {
    final started = Completer<void>();
    final release = Completer<void>();
    var notified = 0;
    f.provider.addListener(() => notified++);
    f.respond = (r) async {
      if (r.url.path.endsWith('/upload')) {
        started.complete();
        await release.future;
      }
      return f.defaults(r);
    };
    final operation = f.submit();
    await started.future;
    final before = notified;
    final loading = f.provider.isLoading;
    f.provider.dispose();
    release.complete();
    expect(await operation, false);
    expect(notified, before);
    expect(f.provider.isLoading, loading);
    // Restore a live provider for fixture cleanup.
    await f.reopen(alreadyDisposed: true);
  });
}
