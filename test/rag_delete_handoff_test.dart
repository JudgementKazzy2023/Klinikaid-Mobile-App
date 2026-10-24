import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
// Supabase's HTTP transport is mocked; no live network or platform plugins run.
// ignore: depend_on_referenced_packages
import 'package:http/http.dart' as http;
// ignore: depend_on_referenced_packages
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:klinikaid_mobile/core/models/rag_document.dart';
import 'package:klinikaid_mobile/core/repositories/rag_documents_repository.dart';
import 'package:klinikaid_mobile/features/admin/data/admin_repository.dart';
import 'package:klinikaid_mobile/features/admin/presentation/providers/admin_provider.dart';
import 'package:klinikaid_mobile/features/admin/presentation/screens/admin_rag_screen.dart';

/// A knowledge document as the registry reads it.
final RagDocument kDocument = RagDocument(
  id: 'row-1',
  title: 'Triage Guidelines',
  content: 'Chunk text',
  embedding: const [],
  metadata: const {'document_id': 'doc-1'},
  createdAt: DateTime.utc(2026),
);

/// A RAG repository that answers the one read the knowledge screen makes.
class _FakeRagRepository implements RagDocumentsRepository {
  @override
  Future<List<RagDocument>> getRagDocuments() async => [kDocument];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected RAG access');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SupabaseClient client;

  setUp(() {
    client = SupabaseClient(
      'https://example.invalid',
      'fake-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient(
        (_) async => http.Response(
          '[]',
          200,
          headers: {'content-type': 'application/json'},
        ),
      ),
    );
  });

  tearDown(() async {
    await client.dispose();
  });

  testWidgets('the knowledge screen lists documents and offers no delete action',
      (tester) async {
    final provider = AdminProvider(
      repository: AdminRepository(client: client),
      ragRepository: _FakeRagRepository(),
    );
    await provider.loadRag();

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: provider,
        child: const MaterialApp(home: AdminRagScreen()),
      ),
    );
    await tester.pumpAndSettle();

    // The read still works.
    expect(find.text('Triage Guidelines'), findsOneWidget);

    // Removing a document is a web action: it also writes the audit record,
    // which the app cannot do. No card carries a delete control.
    expect(find.byKey(const ValueKey('delete_rag_row-1')), findsNothing);
    expect(find.byTooltip('Delete Document'), findsNothing);
    expect(find.byIcon(Icons.delete_outline_rounded), findsNothing);
    expect(
      find.text('Uploads and deletions are managed on the web portal.'),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox());
    provider.dispose();
  });
}
