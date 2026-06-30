import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:klinikaid_mobile/core/models/patient.dart';
import 'package:klinikaid_mobile/core/repositories/patients_repository.dart';
import 'package:klinikaid_mobile/features/staff/data/repositories/staff_queue_repository.dart';
import 'package:klinikaid_mobile/features/staff/presentation/providers/specialist_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MockPatientsRepository extends PatientsRepository {
  final List<Patient> patients;

  MockPatientsRepository(this.patients);

  @override
  Future<List<Patient>> getAllPatients() async {
    return patients;
  }
}

class MockStaffQueueRepository extends StaffQueueRepository {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Mock shared_preferences MethodChannel to avoid MissingPluginException in tests
  const channel = MethodChannel('plugins.flutter.io/shared_preferences');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
    if (methodCall.method == 'getAll') {
      return <String, Object>{};
    }
    return true;
  });

  group('Phase 9: Specialist Patient Search Unit Tests', () {
    late List<Patient> testPatients;

    setUpAll(() async {
      await Supabase.initialize(
        url: 'https://onzeyejlfydvvbkejvwf.supabase.co',
        anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9uemV5ZWpsZnlkdnZia2VqdndmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzkzNjcxMjYsImV4cCI6MjA5NDk0MzEyNn0.FJNbbuBZ2LdutVNrloYsxOLGZWbP-oLLTLJaKBOFkMM',
        authOptions: const FlutterAuthClientOptions(
          localStorage: EmptyLocalStorage(),
        ),
      );
    });

    setUp(() {
      testPatients = [
        Patient(
          id: '1',
          firstName: 'Victor',
          lastName: 'Wembanyama',
          dateOfBirth: DateTime(2004, 1, 4),
          gender: Gender.male,
          contactNumber: '1234567890',
          address: 'France',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
        Patient(
          id: '2',
          firstName: 'Vicky',
          lastName: 'Smith',
          dateOfBirth: DateTime(1995, 5, 12),
          gender: Gender.female,
          contactNumber: '0987654321',
          address: 'USA',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
        Patient(
          id: '3',
          firstName: 'LeBron',
          lastName: 'James',
          dateOfBirth: DateTime(1984, 12, 30),
          gender: Gender.male,
          contactNumber: '5555555555',
          address: 'Akron, OH',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      ];
    });

    test('1. Empty query returns no search results (cleared state)', () async {
      final patientsRepo = MockPatientsRepository(testPatients);
      final provider = SpecialistProvider(patientsRepo: patientsRepo);

      await provider.loadAllPatients();
      provider.search('');

      expect(provider.searchResults, isEmpty);
    });

    test('2. Single term "Vic" finds Victor Wembanyama and Vicky Smith', () async {
      final patientsRepo = MockPatientsRepository(testPatients);
      final provider = SpecialistProvider(patientsRepo: patientsRepo);

      await provider.loadAllPatients();
      provider.search('Vic');

      expect(provider.searchResults.length, 2);
      expect(provider.searchResults.any((p) => p.firstName == 'Victor'), isTrue);
      expect(provider.searchResults.any((p) => p.firstName == 'Vicky'), isTrue);
    });

    test('3. Single term "Wem" finds Victor Wembanyama (last name match)', () async {
      final patientsRepo = MockPatientsRepository(testPatients);
      final provider = SpecialistProvider(patientsRepo: patientsRepo);

      await provider.loadAllPatients();
      provider.search('Wem');

      expect(provider.searchResults.length, 1);
      expect(provider.searchResults.first.firstName, 'Victor');
    });

    test('4. Two terms "Victor Wem" finds Victor Wembanyama', () async {
      final patientsRepo = MockPatientsRepository(testPatients);
      final provider = SpecialistProvider(patientsRepo: patientsRepo);

      await provider.loadAllPatients();
      provider.search('Victor Wem');

      expect(provider.searchResults.length, 1);
      expect(provider.searchResults.first.firstName, 'Victor');
    });

    test('5. Two terms reversed "Wem Victor" finds Victor Wembanyama (order-independent)', () async {
      final patientsRepo = MockPatientsRepository(testPatients);
      final provider = SpecialistProvider(patientsRepo: patientsRepo);

      await provider.loadAllPatients();
      provider.search('Wem Victor');

      expect(provider.searchResults.length, 1);
      expect(provider.searchResults.first.firstName, 'Victor');
    });

    test('6. Two terms with partial match "Vic Wem" finds Victor Wembanyama', () async {
      final patientsRepo = MockPatientsRepository(testPatients);
      final provider = SpecialistProvider(patientsRepo: patientsRepo);

      await provider.loadAllPatients();
      provider.search('Vic Wem');

      expect(provider.searchResults.length, 1);
      expect(provider.searchResults.first.firstName, 'Victor');
    });

    test('7. Case-insensitive: "victor wembanyama" finds Victor Wembanyama', () async {
      final patientsRepo = MockPatientsRepository(testPatients);
      final provider = SpecialistProvider(patientsRepo: patientsRepo);

      await provider.loadAllPatients();
      provider.search('victor wembanyama');

      expect(provider.searchResults.length, 1);
      expect(provider.searchResults.first.firstName, 'Victor');
    });

    test('8. Whitespace collapse: "   Victor   Wem   " finds Victor Wembanyama', () async {
      final patientsRepo = MockPatientsRepository(testPatients);
      final provider = SpecialistProvider(patientsRepo: patientsRepo);

      await provider.loadAllPatients();
      provider.search('   Victor   Wem   ');

      expect(provider.searchResults.length, 1);
      expect(provider.searchResults.first.firstName, 'Victor');
    });

    test('9. Non-matching term "Banks Victor" does NOT find Victor Wembanyama', () async {
      final patientsRepo = MockPatientsRepository(testPatients);
      final provider = SpecialistProvider(patientsRepo: patientsRepo);

      await provider.loadAllPatients();
      provider.search('Banks Victor');

      expect(provider.searchResults, isEmpty);
    });

    test('10. Multiple patients: "Smith" finds Vicky Smith', () async {
      final patientsRepo = MockPatientsRepository(testPatients);
      final provider = SpecialistProvider(patientsRepo: patientsRepo);

      await provider.loadAllPatients();
      provider.search('Smith');

      expect(provider.searchResults.length, 1);
      expect(provider.searchResults.first.firstName, 'Vicky');
    });

    test('11. Empty after trim: "   " returns no search results (treat as empty query)', () async {
      final patientsRepo = MockPatientsRepository(testPatients);
      final provider = SpecialistProvider(patientsRepo: patientsRepo);

      await provider.loadAllPatients();
      provider.search('   ');

      expect(provider.searchResults, isEmpty);
    });
  });
}
