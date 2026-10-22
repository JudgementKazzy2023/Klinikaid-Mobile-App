import 'package:flutter_test/flutter_test.dart';
import 'package:klinikaid_mobile/core/models/profile.dart';
import 'package:klinikaid_mobile/core/permissions/permission_constants.dart';
import 'package:klinikaid_mobile/core/permissions/permission_route_policy.dart';

/// The permissions the shared backend grants each system role.
///
/// Transcribed from the shared schema (web: `src/lib/db/schema.sql`, the
/// `role_permissions` seed). The mobile app does not decide these: the
/// server resolves them for the signed-in account. The set is written down
/// here so the routes each role may open are pinned to the same grants the
/// web resolves for it.
const Map<String, Set<String>> kSystemRoleGrants = <String, Set<String>>{
  'admin': <String>{
    PermissionConstants.staffManage,
    PermissionConstants.profilesManage,
    PermissionConstants.profilesReadStaff,
    PermissionConstants.patientsManage,
    PermissionConstants.queueManage,
    PermissionConstants.documentsManage,
    PermissionConstants.recordsManage,
    PermissionConstants.systemLogsRead,
    PermissionConstants.chatbotLogsRead,
    PermissionConstants.ragDocumentsManage,
    PermissionConstants.storagePatientDocumentsRead,
    PermissionConstants.chatAccess,
    PermissionConstants.ocrRowsManageAll,
    PermissionConstants.rolesManage,
    PermissionConstants.rolesRead,
  },
  'receptionist': <String>{
    PermissionConstants.profilesReadStaff,
    PermissionConstants.patientsManage,
    PermissionConstants.queueManage,
    PermissionConstants.documentsManage,
    PermissionConstants.storagePatientDocumentsRead,
    PermissionConstants.rolesRead,
  },
  'department_staff': <String>{
    PermissionConstants.profilesReadStaff,
    PermissionConstants.patientsRead,
    PermissionConstants.queueManageOwnDept,
    PermissionConstants.recordsManageOwnDept,
    PermissionConstants.rolesRead,
  },
  'medical_specialist': <String>{
    PermissionConstants.profilesReadStaff,
    PermissionConstants.queueRead,
    PermissionConstants.specialistPatients,
    PermissionConstants.specialistAnalytics,
    PermissionConstants.specialistRecords,
    PermissionConstants.rolesRead,
  },
};

PermissionRoutePolicy policyFor(String role) => PermissionRoutePolicy(
      permissions: kSystemRoleGrants[role]!,
      legacyRole: UserRole.fromString(role),
    );

void main() {
  group('each role opens the screens its grants allow', () {
    test('the administrator opens the admin area and the clinical areas', () {
      final policy = policyFor('admin');

      expect(policy.home(), '/admin/dashboard');
      expect(policy.isAllowedPath('/admin/dashboard'), isTrue);
      expect(policy.isAllowedPath('/admin/staff'), isTrue);
      expect(policy.isAllowedPath('/admin/rbac'), isTrue);
      expect(policy.isAllowedPath('/admin/logs'), isTrue);
      expect(policy.isAllowedPath('/admin/rag'), isTrue);
      expect(policy.isAllowedPath('/admin/queue'), isTrue);
      expect(policy.isAllowedPath('/admin/records'), isTrue);
      expect(policy.isAllowedPath('/reception/queue'), isTrue);
      expect(policy.isAllowedPath('/reception/dashboard'), isTrue);
      expect(policy.isAllowedPath('/department/records'), isTrue);

      // A denied route: the administrator holds no specialist permission.
      expect(policy.isAllowedPath('/specialist/dashboard'), isFalse);
      expect(policy.isAllowedPath('/specialist/patients'), isFalse);
    });

    test('the receptionist opens the reception area only', () {
      final policy = policyFor('receptionist');

      expect(policy.home(), '/reception/queue');
      expect(policy.isAllowedPath('/reception/queue'), isTrue);
      expect(policy.isAllowedPath('/reception/dashboard'), isTrue);
      expect(policy.isAllowedPath('/reception/document/sub-1'), isTrue);
      expect(policy.isAllowedPath('/reception/profile'), isTrue);

      // A denied route: the staff list and the whole admin area.
      expect(policy.isAllowedPath('/admin/staff'), isFalse);
      expect(policy.isAllowedPath('/admin/dashboard'), isFalse);
      expect(policy.isAllowedPath('/admin/rbac'), isFalse);
      expect(policy.canUseAdminShell, isFalse);
    });

    test('the department staff member opens the department area only', () {
      final policy = policyFor('department_staff');

      expect(policy.home(), '/department/records');
      expect(policy.isAllowedPath('/department/queue'), isTrue);
      expect(policy.isAllowedPath('/department/records'), isTrue);
      expect(policy.isAllowedPath('/department/result-entry/patient-1'), isTrue);
      expect(policy.isAllowedPath('/department/profile'), isTrue);

      // A denied route: the reception queue needs the permissions the
      // department staff member does not hold.
      expect(policy.isAllowedPath('/reception/queue'), isFalse);
      expect(policy.isAllowedPath('/admin/staff'), isFalse);
    });

    test('the medical specialist opens the specialist area only', () {
      final policy = policyFor('medical_specialist');

      expect(policy.home(), '/specialist/dashboard');
      expect(policy.isAllowedPath('/specialist/dashboard'), isTrue);
      expect(policy.isAllowedPath('/specialist/patients'), isTrue);
      expect(policy.isAllowedPath('/specialist/record-entry/patient-1'), isTrue);
      expect(policy.isAllowedPath('/specialist/analytics/patient-1'), isTrue);
      expect(policy.isAllowedPath('/specialist/profile'), isTrue);

      // A denied route: the staff list and the reception queue.
      expect(policy.isAllowedPath('/admin/staff'), isFalse);
      expect(policy.isAllowedPath('/reception/queue'), isFalse);
    });
  });

  group('an account without a grant is turned away', () {
    test('one missing permission closes the screen that needs it', () {
      final policy = PermissionRoutePolicy(
        permissions: <String>{
          PermissionConstants.staffManage,
          PermissionConstants.rolesRead,
        },
        legacyRole: UserRole.admin,
      );

      // The staff list needs `staff.manage` only.
      expect(policy.isAllowedPath('/admin/staff'), isTrue);
      // The dashboard needs `profiles.manage`, which this account lacks.
      expect(policy.isAllowedPath('/admin/dashboard'), isFalse);
      // The role catalogue needs `roles.read`, which it holds.
      expect(policy.isAllowedPath('/admin/rbac'), isTrue);
      // A staff update needs `profiles.manage` as well, so the account may
      // not change a staff member.
      expect(policy.hasAll(const [
        PermissionConstants.staffManage,
        PermissionConstants.rolesRead,
        PermissionConstants.profilesManage,
      ]), isFalse);
    });

    test('an account with no grant at all opens no screen', () {
      const policy = PermissionRoutePolicy(
        permissions: <String>{},
        legacyRole: UserRole.admin,
      );

      expect(policy.home(), isNull);
      expect(policy.isAllowedPath('/admin/dashboard'), isFalse);
      expect(policy.isAllowedPath('/admin/staff'), isFalse);
      expect(policy.isAllowedPath('/reception/queue'), isFalse);
      expect(policy.isAllowedPath('/department/records'), isFalse);
      expect(policy.isAllowedPath('/specialist/patients'), isFalse);
    });

    test('the reception queue needs both of its permissions', () {
      final documentsOnly = PermissionRoutePolicy(
        permissions: <String>{PermissionConstants.documentsManage},
        legacyRole: UserRole.receptionist,
      );

      expect(documentsOnly.isAllowedPath('/reception/queue'), isFalse);
      expect(documentsOnly.isAllowedPath('/reception/document/sub-1'), isTrue);

      final queueOnly = PermissionRoutePolicy(
        permissions: <String>{PermissionConstants.queueManage},
        legacyRole: UserRole.receptionist,
      );

      expect(queueOnly.isAllowedPath('/reception/queue'), isFalse);
    });
  });
}
