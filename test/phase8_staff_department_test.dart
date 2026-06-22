import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:klinikaid_mobile/core/supabase/supabase_client.dart';
import 'package:klinikaid_mobile/core/models/patient_queue.dart';
import 'package:klinikaid_mobile/features/staff/data/repositories/staff_queue_repository.dart';

String generateUuid() {
  final random = Random();
  String hexDigit(int value) => value.toRadixString(16);
  final buffer = StringBuffer();
  for (var i = 0; i < 36; i++) {
    if (i == 8 || i == 13 || i == 18 || i == 23) {
      buffer.write('-');
    } else if (i == 14) {
      buffer.write('4');
    } else if (i == 19) {
      buffer.write(hexDigit((random.nextInt(4) + 8)));
    } else {
      buffer.write(hexDigit(random.nextInt(16)));
    }
  }
  return buffer.toString();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  // Mock shared_preferences MethodChannel to avoid MissingPluginException in tests
  const channel = MethodChannel('plugins.flutter.io/shared_preferences');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
    if (methodCall.method == 'getAll') {
      return <String, Object>{};
    }
    return true;
  });

  late String rand;
  late String patientEmail;
  late String receptionistEmail;
  late String labStaffEmail;
  late String imagingStaffEmail;
  late String password;
  late StaffQueueRepository staffRepo;

  setUpAll(() async {
    await SupabaseService.initialize(localStorage: const EmptyLocalStorage());
    staffRepo = StaffQueueRepository();

    rand = Random().nextInt(1000000).toString();
    patientEmail = 'patient.dept.$rand@gmail.com';
    receptionistEmail = 'receptionist.dept.$rand@gmail.com';
    labStaffEmail = 'lab.staff.$rand@gmail.com';
    imagingStaffEmail = 'imaging.staff.$rand@gmail.com';
    password = 'Password123!';
  });

  group('Phase 8: Department Staff Portal RLS & Data Isolation Verification', () {
    late String patientRecordId;
    late String labStaffUid;
    late int labQueueId;

    test('Data Isolation and isolation checks', () async {
      final client = SupabaseService.client;
      late String imagingStaffUid;

      print('=== SETUP: Create Test Patient and Profiles ===');
      // 1. Patient SignUp & Onboarding
      final authPatient = await client.auth.signUp(
        email: patientEmail,
        password: password,
        data: {'full_name': 'Dept Test Patient', 'role': 'patient'},
      );
      final patientUid = authPatient.user!.id;
      await Future.delayed(const Duration(milliseconds: 1500));

      patientRecordId = generateUuid();
      await client.from('patients').insert({
        'id': patientRecordId,
        'profile_id': patientUid,
        'first_name': 'DeptTest',
        'last_name': 'Patient',
        'date_of_birth': '1995-10-10',
        'gender': 'male',
        'contact_number': '09876543210',
        'address': 'Manila, PH',
      });
      await client.auth.signOut();

      // 2. Receptionist SignUp
      await client.auth.signUp(
        email: receptionistEmail,
        password: password,
        data: {'full_name': 'Dept Test Receptionist', 'role': 'receptionist'},
      );
      await Future.delayed(const Duration(milliseconds: 1500));
      await client.auth.signOut();

      // 3. Laboratory Staff SignUp
      await client.auth.signUp(
        email: labStaffEmail,
        password: password,
        data: {
          'full_name': 'Lab Tech',
          'role': 'department_staff',
          'department': 'laboratory',
        },
      );
      labStaffUid = client.auth.currentUser!.id;
      await Future.delayed(const Duration(milliseconds: 1500));
      await client.auth.signOut();

      // 4. Imaging Staff SignUp
      await client.auth.signUp(
        email: imagingStaffEmail,
        password: password,
        data: {
          'full_name': 'Imaging Tech',
          'role': 'department_staff',
          'department': 'imaging',
        },
      );
      imagingStaffUid = client.auth.currentUser!.id;
      await Future.delayed(const Duration(milliseconds: 1500));
      await client.auth.signOut();

      print('=== STEP 1: Add Queue and Records for both Departments ===');
      // Log in as Receptionist to set up the queues
      await client.auth.signInWithPassword(email: receptionistEmail, password: password);
      final labQueueResponse = await client.from('patient_queue').insert({
        'patient_id': patientRecordId,
        'department': 'laboratory',
        'status': 'waiting',
        'priority_level': 'routine',
      }).select().single();
      labQueueId = labQueueResponse['id'] as int;

      await client.from('patient_queue').insert({
        'patient_id': patientRecordId,
        'department': 'imaging',
        'status': 'waiting',
        'priority_level': 'urgent',
      });

      await client.auth.signOut();

      // Log in as Lab Staff to enter a lab record
      await client.auth.signInWithPassword(email: labStaffEmail, password: password);
      final labRecordId = generateUuid();
      await client.from('department_records').insert({
        'id': labRecordId,
        'patient_id': patientRecordId,
        'recorder_id': labStaffUid,
        'department': 'laboratory',
        'test_type': 'CBC',
        'test_name': 'Hemoglobin',
        'test_value': '14.5',
        'unit': 'g/dL',
        'is_flagged': false,
      });
      await client.auth.signOut();

      // Log in as Imaging Staff to enter an imaging record
      await client.auth.signInWithPassword(email: imagingStaffEmail, password: password);
      final imgRecordId = generateUuid();
      await client.from('department_records').insert({
        'id': imgRecordId,
        'patient_id': patientRecordId,
        'recorder_id': imagingStaffUid,
        'department': 'imaging',
        'test_type': 'X-Ray',
        'test_name': 'Chest PA',
        'test_value': 'Clear',
        'unit': '',
        'is_flagged': false,
      });
      await client.auth.signOut();

      print('=== STEP 2: Authenticate as Laboratory Staff ===');
      await client.auth.signInWithPassword(email: labStaffEmail, password: password);

      print('=== STEP 3: RLS Queue Mismatch isolation check ===');
      // Lab staff queries with explicit imaging department filter
      final imagingQueue = await client
          .from('patient_queue')
          .select()
          .eq('department', 'imaging');
      
      // Expect zero rows due to RLS policy: "Department staff can view and update queue for their department"
      expect(imagingQueue.length, 0);
      print('DB Confirmed: Lab staff got 0 imaging queue entries due to RLS filter.');

      print('=== STEP 4: RLS Records Mismatch isolation check ===');
      // Lab staff queries for imaging records directly
      final imagingRecords = await client
          .from('department_records')
          .select()
          .eq('department', 'imaging');
      
      expect(imagingRecords.length, 0);
      print('DB Confirmed: Lab staff got 0 imaging department records due to RLS isolation.');

      print('=== STEP 5: RLS Write Bypass attempt check ===');
      // Lab staff attempts to insert an imaging record
      try {
        await client.from('department_records').insert({
          'id': generateUuid(),
          'patient_id': patientRecordId,
          'recorder_id': labStaffUid,
          'department': 'imaging', // Mismatch!
          'test_type': 'CT Scan',
          'test_name': 'Head CT',
          'test_value': 'Abnormal',
          'unit': '',
          'is_flagged': true,
        });
        fail('Security Failure: Lab staff successfully inserted an imaging department record!');
      } catch (e) {
        expect(e.toString().contains('Access denied') || e.toString().contains('violates row-level security'), isTrue);
        print('DB Confirmed: Lab staff write to imaging records blocked by RLS.');
      }

      await client.auth.signOut();
    });

    test('RLS permits department_staff to transition queue status (web portal action; not exposed on mobile UI)', () async {
      // Queue status transitions are intentionally not exposed in the mobile department UI per scope decision 2026-06-21.
      // This test continues to verify that the underlying RLS policy permits the action, which is correct since the same policy serves the web portal.
      final client = SupabaseService.client;
      await client.auth.signInWithPassword(email: labStaffEmail, password: password);

      print('=== STEP 6: Verification Chain - Department Queue transition ===');
      // Lab staff starts service on their own lab queue entry
      await staffRepo.updateQueueStatus(labQueueId, QueueStatus.inProgress);
      final labQueueCheck = await client
          .from('patient_queue')
          .select('status')
          .eq('id', labQueueId)
          .single();
      expect(labQueueCheck['status'], 'in_progress');
      print('DB Confirmed: Lab staff successfully started service on their department\'s queue entry.');

      // Clean up
      await client.auth.signOut();
    });
  });
}
