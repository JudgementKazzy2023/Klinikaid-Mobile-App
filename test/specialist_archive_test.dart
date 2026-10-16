import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
// Supabase's HTTP transport is mocked; no live network or platform plugins run.
// ignore: depend_on_referenced_packages
import 'package:http/http.dart' as http;
// ignore: depend_on_referenced_packages
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:klinikaid_mobile/core/models/specialist_patient.dart';
import 'package:klinikaid_mobile/core/models/specialist_record.dart';
import 'package:klinikaid_mobile/features/specialist/data/specialist_repository.dart';
import 'package:klinikaid_mobile/features/specialist/presentation/providers/specialist_provider.dart';
import 'package:klinikaid_mobile/features/specialist/presentation/screens/specialist_directory_screen.dart';

SpecialistPatient patient() => SpecialistPatient(
  id: 'patient-1', specialistId: 'specialist-1', firstName: 'Archive',
  lastName: 'Test', dateOfBirth: DateTime(1990), gender: 'other',
  createdAt: DateTime(2026), updatedAt: DateTime(2026),
);

class ArchiveRepository extends SpecialistRepository {
  bool result = true;
  bool failRefresh = false;
  bool failArchive = false;
  int calls = 0;
  bool archived = false;
  Completer<bool>? pending;
  @override
  Future<bool> archivePatient(String id) async {
    calls++;
    if (failArchive) throw TimeoutException('timeout');
    archived = pending == null ? result : await pending!.future;
    return archived;
  }
  @override
  Future<List<SpecialistPatient>> getMyPatients() async {
    if (archived && failRefresh) throw Exception('offline');
    return archived ? [] : [patient()];
  }
  @override
  Future<Map<String, dynamic>> getDashboardRawData() async => {
    'patients': await getMyPatients(), 'records': <SpecialistRecord>[],
    'raw_records': <dynamic>[],
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('RPC uses POST and exact parameter; true/false/denied are handled', () async {
    for (final answer in ['true', 'false', '{"message":"not permitted","code":"42501"}']) {
      final status = answer.startsWith('{') ? 403 : 200;
      final client = SupabaseClient('https://example.supabase.co', 'fake',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((request) async {
          expect(request.method, 'POST');
          expect(request.url.path, '/rest/v1/rpc/archive_specialist_patient');
          expect(jsonDecode(request.body), {'p_patient_id': 'patient-1'});
          return http.Response(answer, status, request: request, headers: {'content-type': 'application/json'});
        }),
      );
      final repo = SpecialistRepository(client: client);
      if (status == 403) {
        await expectLater(repo.archivePatient('patient-1'), throwsA(anything));
      } else {
        expect(await repo.archivePatient('patient-1'), answer == 'true');
      }
      await client.dispose();
    }
  });
  test('false preserves patient and uses precise message', () async {
    final repo = ArchiveRepository()..result = false;
    final state = SpecialistProvider(repository: repo);
    await state.loadDirectory();
    expect(await state.archivePatient('patient-1'), isFalse);
    expect(state.directoryPatients, hasLength(1));
    expect(state.errorMessage, 'Patient could not be archived, refresh and try again.');
  });
  test('successful archive clears search and remains success if refresh fails', () async {
    final repo = ArchiveRepository()..failRefresh = true;
    final state = SpecialistProvider(repository: repo);
    await state.loadDirectory();
    state.search('Archive');
    expect(await state.archivePatient('patient-1'), isTrue);
    expect(state.directoryPatients, isEmpty);
    expect(state.searchResults, isEmpty);
    expect(state.errorMessage, startsWith('Patient archived, but'));
  });
  test('timeout does not claim success or remove patient', () async {
    final repo = ArchiveRepository()..failArchive = true;
    final state = SpecialistProvider(repository: repo);
    await state.loadDirectory();
    expect(await state.archivePatient('patient-1'), isFalse);
    expect(state.directoryPatients, hasLength(1));
    expect(state.errorMessage, contains('could not be confirmed'));
  });
  testWidgets('cancel does not call RPC; pending archive disables repeated taps', (tester) async {
    final repo = ArchiveRepository()..pending = Completer<bool>();
    final state = SpecialistProvider(repository: repo);
    await state.loadDirectory();
    await tester.pumpWidget(ChangeNotifierProvider.value(value: state,
      child: const MaterialApp(home: SpecialistDirectoryScreen())));
    await tester.tap(find.byTooltip('Archive Patient'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(repo.calls, 0);
    await tester.tap(find.byTooltip('Archive Patient'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Archive'));
    await tester.pump();
    expect(tester.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Archiving...')).onPressed, isNull);
    expect(await state.archivePatient('patient-1'), isFalse);
    expect(repo.calls, 1);
    repo.pending!.complete(true);
    await tester.pumpAndSettle();
    expect(find.text('Patient archived successfully.'), findsOneWidget);
    expect(state.directoryPatients, isEmpty);
  });
}
