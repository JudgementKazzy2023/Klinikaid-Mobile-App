import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:klinikaid_mobile/core/errors/failures.dart';
import 'package:klinikaid_mobile/core/permissions/permission_constants.dart';
import 'package:klinikaid_mobile/core/permissions/permission_source.dart';
import 'package:klinikaid_mobile/features/admin/data/admin_repository.dart';

/// A client whose every read and write throws.
///
/// The preflight has to stop an operation before its first call reaches the
/// server. A call that gets through therefore fails loudly, and the test can
/// tell "the preflight stopped it" from "the preflight let it through".
class ExplodingSupabaseClient extends SupabaseClient {
  ExplodingSupabaseClient()
      : super('https://example.supabase.co', 'mock-anon-key');

  @override
  SupabaseQueryBuilder from(String table) {
    throw StateError('The operation reached the server without the permission.');
  }
}

/// The permissions of an account.
class FakePermissions implements PermissionSource {
  FakePermissions(this.grants);

  final Set<String> grants;

  @override
  bool hasPermission(String permission) => grants.contains(permission);

  @override
  bool hasAllPermissions(List<String> permissions) =>
      permissions.every(grants.contains);

  @override
  bool hasAnyPermission(List<String> permissions) =>
      permissions.any(grants.contains);
}

void main() {
  group('the staff and role reads are pinned to the permissions the web needs',
      () {
    test('the staff list is not read without staff.manage', () async {
      final repository = AdminRepository(
        client: ExplodingSupabaseClient(),
        permissionSource: FakePermissions(const <String>{}),
      );

      await expectLater(
        repository.getStaffPersonnel(),
        throwsA(isA<PermissionDeniedException>()),
      );
    });

    test('the staff list is read when the account holds staff.manage',
        () async {
      final repository = AdminRepository(
        client: ExplodingSupabaseClient(),
        permissionSource: FakePermissions(<String>{
          PermissionConstants.staffManage,
        }),
      );

      // The read starts, which is what the permission allows.
      await expectLater(
        repository.getStaffPersonnel(),
        throwsA(isA<Failure>().having(
          (failure) => failure.message,
          'message',
          contains('reached the server'),
        )),
      );
    });

    test('the role catalogue is not read without roles.read', () async {
      final repository = AdminRepository(
        client: ExplodingSupabaseClient(),
        permissionSource: FakePermissions(<String>{
          PermissionConstants.staffManage,
        }),
      );

      await expectLater(
        repository.getRbacCatalog(),
        throwsA(isA<PermissionDeniedException>()),
      );
    });

    test('the role catalogue is read when the account holds roles.read',
        () async {
      final repository = AdminRepository(
        client: ExplodingSupabaseClient(),
        permissionSource: FakePermissions(<String>{
          PermissionConstants.rolesRead,
        }),
      );

      await expectLater(
        repository.getRbacCatalog(),
        throwsA(isA<Failure>().having(
          (failure) => failure.message,
          'message',
          contains('reached the server'),
        )),
      );
    });
  });

  group('a staff mutation asks for every permission the web asks for', () {
    test('a staff update needs staff.manage, roles.read and profiles.manage',
        () async {
      final missingProfilesManage = AdminRepository(
        client: ExplodingSupabaseClient(),
        permissionSource: FakePermissions(<String>{
          PermissionConstants.staffManage,
          PermissionConstants.rolesRead,
        }),
      );

      await expectLater(
        missingProfilesManage.updateStaffProfile(
          userId: 'staff-uuid',
          fullName: 'New Name',
          role: 'receptionist',
          roleId: 'role-uuid',
        ),
        throwsA(isA<PermissionDeniedException>()),
      );

      final missingRolesRead = AdminRepository(
        client: ExplodingSupabaseClient(),
        permissionSource: FakePermissions(<String>{
          PermissionConstants.staffManage,
          PermissionConstants.profilesManage,
        }),
      );

      await expectLater(
        missingRolesRead.updateStaffProfile(
          userId: 'staff-uuid',
          fullName: 'New Name',
          role: 'receptionist',
          roleId: 'role-uuid',
        ),
        throwsA(isA<PermissionDeniedException>()),
      );

      final complete = AdminRepository(
        client: ExplodingSupabaseClient(),
        permissionSource: FakePermissions(<String>{
          PermissionConstants.staffManage,
          PermissionConstants.rolesRead,
          PermissionConstants.profilesManage,
        }),
      );

      // Every permission of the web's write is held, so the write starts.
      await expectLater(
        complete.updateStaffProfile(
          userId: 'staff-uuid',
          fullName: 'New Name',
          role: 'receptionist',
          roleId: 'role-uuid',
        ),
        throwsA(isA<Failure>().having(
          (failure) => failure.message,
          'message',
          contains('reached the server'),
        )),
      );
    });

    test('a status change needs staff.manage and profiles.manage', () async {
      final missingProfilesManage = AdminRepository(
        client: ExplodingSupabaseClient(),
        permissionSource: FakePermissions(<String>{
          PermissionConstants.staffManage,
        }),
      );

      await expectLater(
        missingProfilesManage.setStaffActive(userId: 'staff-uuid', isActive: false),
        throwsA(isA<PermissionDeniedException>()),
      );

      final complete = AdminRepository(
        client: ExplodingSupabaseClient(),
        permissionSource: FakePermissions(<String>{
          PermissionConstants.staffManage,
          PermissionConstants.profilesManage,
        }),
      );

      await expectLater(
        complete.setStaffActive(userId: 'staff-uuid', isActive: false),
        throwsA(isA<Failure>().having(
          (failure) => failure.message,
          'message',
          contains('reached the server'),
        )),
      );
    });

    test('a knowledge document is not deleted without rag_documents.manage',
        () async {
      final repository = AdminRepository(
        client: ExplodingSupabaseClient(),
        permissionSource: FakePermissions(const <String>{}),
      );

      await expectLater(
        repository.deleteRagDocument(documentId: 'doc-1'),
        throwsA(isA<PermissionDeniedException>()),
      );
    });
  });
}
