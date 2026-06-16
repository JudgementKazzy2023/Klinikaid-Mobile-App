import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:klinikaid_mobile/core/supabase/supabase_client.dart';
import 'package:klinikaid_mobile/core/models/patient_queue.dart';
import 'package:klinikaid_mobile/core/models/document.dart';
import 'package:klinikaid_mobile/core/models/patient.dart';
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
  late String password;
  late StaffQueueRepository staffRepo;

  setUpAll(() async {
    await SupabaseService.initialize(localStorage: const EmptyLocalStorage());
    staffRepo = StaffQueueRepository();

    rand = Random().nextInt(1000000).toString();
    patientEmail = 'patient.$rand@gmail.com';
    receptionistEmail = 'receptionist.$rand@gmail.com';
    password = 'Password123!';
  });

  test('Phase 8: Receptionist Portal Integration & Verification Chain', () async {
    final client = SupabaseService.client;

    print('=== STEP 1: Register and Onboard Patient ===');
    final authResponsePatient = await client.auth.signUp(
      email: patientEmail,
      password: password,
      data: {'full_name': 'Patient A', 'role': 'patient'},
    );
    final patientUid = authResponsePatient.user!.id;

    // Wait for profile trigger
    await Future.delayed(const Duration(milliseconds: 1500));

    // Onboard patient
    final patientRecordId = generateUuid();
    final patientRecord = await client.from('patients').insert({
      'id': patientRecordId,
      'profile_id': patientUid,
      'first_name': 'Jane',
      'last_name': 'Doe',
      'date_of_birth': '1990-05-15',
      'gender': 'female',
      'contact_number': '09123456789',
      'address': 'Rizal, PH',
    }).select().single().then((val) => val['id'] as String);

    print('Patient record created with ID: $patientRecordId');

    // Create a pending document
    final docId = generateUuid();
    await client.from('documents').insert({
      'id': docId,
      'patient_id': patientRecordId,
      'uploader_id': patientUid,
      'file_name': 'referral.pdf',
      'file_path': 'uploads/referral.pdf',
      'file_type': 'pdf',
      'status': 'pending',
    });

    print('Pending document created with ID: $docId');
    await client.auth.signOut();

    print('=== STEP 2: Register and Sign in as Receptionist ===');
    final authResponseReceptionist = await client.auth.signUp(
      email: receptionistEmail,
      password: password,
      data: {
        'full_name': 'Bob Receptionist',
        'role': 'receptionist',
      },
    );
    final receptionistUid = authResponseReceptionist.user!.id;
    await Future.delayed(const Duration(milliseconds: 1500));

    await client.auth.signOut();
    await client.auth.signInWithPassword(email: receptionistEmail, password: password);
    print('Signed in as receptionist (UUID: $receptionistUid)');

    // Create a queue entry as Receptionist (tests "Receptionists can manage queue" policy)
    final qResponse = await client.from('patient_queue').insert({
      'patient_id': patientRecordId,
      'department': 'laboratory',
      'status': 'waiting',
      'priority_level': 'routine',
    }).select().single();
    final queueId = qResponse['id'] as int;
    print('Queue entry created with ID: $queueId');

    print('=== STEP 3: Verify today\'s queue retrieve ===');
    final todayQueue = await staffRepo.getQueueForToday();
    final hasOurEntry = todayQueue.any((q) => q.id == queueId);
    expect(hasOurEntry, isTrue);

    print('=== STEP 4: Verification Chain - Queue Arrived ===');
    // Call repository method to update queue status to in_progress
    await staffRepo.updateQueueStatus(queueId, QueueStatus.inProgress);

    // Database verification: Select status from patient_queue
    final qCheck = await client
        .from('patient_queue')
        .select('status')
        .eq('id', queueId)
        .single();
    expect(qCheck['status'], 'in_progress');
    print('DB Confirmed: Queue status updated to "in_progress"');

    print('=== STEP 5: Verification Chain - Approve Document ===');
    final pendingDocs = await staffRepo.getPendingDocuments();
    final hasOurDoc = pendingDocs.any((d) => d.id == docId);
    expect(hasOurDoc, isTrue);

    // Approve the document
    await staffRepo.updateDocumentStatus(docId, DocumentStatus.approved);

    // Database verification: Select status from documents
    final docCheckApprove = await client
        .from('documents')
        .select('status')
        .eq('id', docId)
        .single();
    expect(docCheckApprove['status'], 'approved');
    print('DB Confirmed: Document status updated to "approved"');

    print('=== STEP 6: Verification Chain - Reject Document ===');
    // Change back to pending to allow rejection
    await client
        .from('documents')
        .update({'status': 'pending'})
        .eq('id', docId);

    // Reject the document with reason
    const rejectionReason = 'Blurry Image';
    await staffRepo.updateDocumentStatus(
      docId,
      DocumentStatus.rejected,
      rejectionReason: rejectionReason,
    );

    // Database verification: Select status, rejection_reason from documents
    final docCheckReject = await client
        .from('documents')
        .select('status, rejection_reason')
        .eq('id', docId)
        .single();
    expect(docCheckReject['status'], 'rejected');
    expect(docCheckReject['rejection_reason'], rejectionReason);
    print('DB Confirmed: Document status updated to "rejected" with reason: $rejectionReason');

    // Clean up session
    await client.auth.signOut();
  });
}
