import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:klinikaid_mobile/core/models/patient.dart';
import 'package:klinikaid_mobile/core/patient_submission_containment.dart';
import 'package:klinikaid_mobile/features/auth/presentation/providers/auth_provider.dart';
import 'package:klinikaid_mobile/features/documents/presentation/providers/document_submission_provider.dart';
import 'package:klinikaid_mobile/features/documents/presentation/screens/submit_document_screen.dart';
import 'support/upload_fixture.dart';

class _Auth extends ChangeNotifier implements AuthProvider {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
  final Patient fixture;
  _Auth(this.fixture);
  @override
  Patient? get patient => fixture;
  @override
  bool get isLoading => false;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late UploadFixture f;
  setUp(() async {
    PatientSubmissionContainment.activeForTesting = false;
    f = UploadFixture();
    await f.init();
    await f.seed('legacy', UploadFixture.owner);
    await f.signIn(UploadFixture.owner);
    f.respond = (r) async => r.url.path.endsWith('/upload')
        ? f.json({
            'error_code': 'DUPLICATE_PENDING',
            'message': 'pending',
            'document_id': 'existing',
            'status': 'pending',
          }, 409)
        : f.defaults(r);
    await f.provider.resolveQueuedDraft('legacy');
  });
  tearDown(() async {
    try {
      await f.close();
    } finally {
      PatientSubmissionContainment.activeForTesting = true;
    }
  });
  testWidgets(
    'enabled screen opens/resumes without replay and renders PDF choice, saved drafts and duplicate link',
    (tester) async {
      tester.view.physicalSize = const Size(430, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final count = f.requests.length;
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthProvider>.value(
              value: _Auth(f.patient()),
            ),
            ChangeNotifierProvider<DocumentSubmissionProvider>.value(
              value: f.provider,
            ),
          ],
          child: const MaterialApp(home: SubmitDocumentScreen()),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Choose a PDF (up to 5 MB)'), findsOneWidget);
      expect(find.text('legacy.pdf'), findsOneWidget);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump(const Duration(milliseconds: 500));
      expect(f.requests.length, count);
      expect(find.text('View pending document in my records'), findsOneWidget);
      expect(find.text('You already have a pending Other'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
