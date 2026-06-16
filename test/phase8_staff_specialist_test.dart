import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:klinikaid_mobile/core/supabase/supabase_client.dart';
import 'package:klinikaid_mobile/core/models/patient.dart';
import 'package:klinikaid_mobile/core/models/profile.dart';
import 'package:klinikaid_mobile/core/models/department_record.dart';
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
  late String specialistEmail;
  late String labStaffEmail;
  late String password;
  late StaffQueueRepository staffRepo;

  setUpAll(() async {
    await SupabaseService.initialize(localStorage: const EmptyLocalStorage());
    staffRepo = StaffQueueRepository();

    rand = Random().nextInt(1000000).toString();
    patientEmail = 'patient.spec.$rand@gmail.com';
    specialistEmail = 'specialist.spec.$rand@gmail.com';
    labStaffEmail = 'lab.staff.spec.$rand@gmail.com';
    password = 'Password123!';
  });

  test('Phase 8: Medical Specialist Portal Integration & Cross-Department Timeline Verification', () async {
    final client = SupabaseService.client;

    print('=== SETUP: Create Test Patient and Records ===');
    // 1. Patient SignUp & Onboarding
    final authPatient = await client.auth.signUp(
      email: patientEmail,
      password: password,
      data: {'full_name': 'Specialist Test Patient', 'role': 'patient'},
    );
    final patientUid = authPatient.user!.id;
    await Future.delayed(const Duration(milliseconds: 1500));

    final patientRecordId = generateUuid();
    await client.from('patients').insert({
      'id': patientRecordId,
      'profile_id': patientUid,
      'first_name': 'SpecTest',
      'last_name': 'Patient',
      'date_of_birth': '1988-08-08',
      'gender': 'female',
      'contact_number': '09776655443',
      'address': 'Quezon City, PH',
    });
    await client.auth.signOut();

    // 2. Lab Staff SignUp & Create Record
    await client.auth.signUp(
      email: labStaffEmail,
      password: password,
      data: {
        'full_name': 'Spec Lab Tech',
        'role': 'department_staff',
        'department': 'laboratory',
      },
    );
    final labStaffUid = client.auth.currentUser!.id;
    await Future.delayed(const Duration(milliseconds: 1500));

    final labRecordId = generateUuid();
    await client.from('department_records').insert({
      'id': labRecordId,
      'patient_id': patientRecordId,
      'recorder_id': labStaffUid,
      'department': 'laboratory',
      'test_type': 'Lipid Profile',
      'test_name': 'Cholesterol',
      'test_value': '210',
      'unit': 'mg/dL',
      'is_flagged': true,
    });
    await client.auth.signOut();

    // 3. Specialist SignUp
    await client.auth.signUp(
      email: specialistEmail,
      password: password,
      data: {
        'full_name': 'Dr. House',
        'role': 'medical_specialist',
      },
    );
    final specialistUid = authPatient.user!.id;
    await Future.delayed(const Duration(milliseconds: 1500));

    await client.auth.signOut();
    await client.auth.signInWithPassword(email: specialistEmail, password: password);
    print('Signed in as medical specialist (Dr. House)');

    print('=== STEP 1: Search Patient by Name ===');
    final searchResults = await staffRepo.searchPatients('SpecTest');
    final hasOurPatient = searchResults.any((p) => p.id == patientRecordId);
    expect(hasOurPatient, isTrue);
    print('DB Confirmed: Patient found in search.');

    print('=== STEP 2: Retrieve Patient Cross-Department Timeline ===');
    final timeline = await staffRepo.getDepartmentRecordsForPatient(patientRecordId);
    
    // Expect our lab record to be in the timeline
    final hasLabRecord = timeline.any((r) => r.id == labRecordId);
    expect(hasLabRecord, isTrue);
    
    // Verify it is from the laboratory department
    final record = timeline.firstWhere((r) => r.id == labRecordId);
    expect(record.department, Department.laboratory);
    expect(record.testResults['test_value']?.toString(), '210');
    expect(record.referenceRangeStatus, ReferenceRangeStatus.criticalHigh);
    print('DB Confirmed: Specialist successfully retrieved the cross-department timeline containing laboratory records.');

    // Clean up session
    await client.auth.signOut();
  });
}
