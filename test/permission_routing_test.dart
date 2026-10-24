import 'package:flutter_test/flutter_test.dart';
import 'package:klinikaid_mobile/core/models/profile.dart';
import 'package:klinikaid_mobile/core/permissions/permission_constants.dart';
import 'package:klinikaid_mobile/core/permissions/permission_route_policy.dart';

import 'permission_role_routing_test.dart' show kSystemRoleGrants;

void main() {
  group('permission route policy', () {
    test('applies AND and ANY permission gates exactly', () {
      final documentsOnly = PermissionRoutePolicy(
        legacyRole: UserRole.receptionist,
        permissions: {
          PermissionConstants.documentsManage,
          PermissionConstants.recordsManageOwnDept,
        },
      );

      expect(documentsOnly.hasAll(PermissionConstants.receptionQueue), isFalse);
      expect(documentsOnly.isAllowedPath('/reception/queue'), isFalse);
      expect(documentsOnly.hasAny(PermissionConstants.departmentRecordsAny), isTrue);
      expect(documentsOnly.isAllowedPath('/department/records'), isTrue);

      final fullReception = PermissionRoutePolicy(
        legacyRole: UserRole.receptionist,
        permissions: {
          PermissionConstants.documentsManage,
          PermissionConstants.queueManage,
        },
      );

      expect(fullReception.hasAll(PermissionConstants.receptionQueue), isTrue);
      expect(fullReception.isAllowedPath('/reception/queue'), isTrue);
    });

    test('uses legacy role as shell tiebreaker only when permissions fit', () {
      final customSpecialist = PermissionRoutePolicy(
        legacyRole: UserRole.receptionist,
        permissions: {
          PermissionConstants.specialistAnalytics,
          PermissionConstants.specialistPatients,
        },
      );

      expect(customSpecialist.home(), '/specialist/dashboard');
      expect(customSpecialist.isAllowedPath('/specialist/dashboard'), isTrue);
      expect(customSpecialist.isAllowedPath('/reception/queue'), isFalse);

      final matchingReception = PermissionRoutePolicy(
        legacyRole: UserRole.receptionist,
        permissions: {
          PermissionConstants.documentsManage,
          PermissionConstants.queueManage,
          PermissionConstants.patientsManage,
          PermissionConstants.profilesReadStaff,
        },
      );

      expect(matchingReception.home(), '/reception/queue');
    });
  });

  group('home() only ever returns a path its own gate allows', () {
    // Every grant set below must satisfy this invariant: either home() is
    // null (the account is sent to the denial) or isAllowedPath(home()) is
    // true. A landing path the gate rejects would let go_router bypass the
    // area gate for the very first screen, because a redirect to the current
    // location is treated as "no change".
    void expectHomeInsideGate(PermissionRoutePolicy policy, String label) {
      final landing = policy.home();
      if (landing == null) return;
      expect(
        policy.isAllowedPath(landing),
        isTrue,
        reason: 'home() returned $landing for $label, but isAllowedPath '
            'rejects it',
      );
    }

    test('every single-permission grant set lands inside its own gate', () {
      for (final permission in PermissionConstants.all) {
        for (final legacyRole in <UserRole?>[null, UserRole.admin]) {
          final label = '{$permission} (legacyRole: $legacyRole)';
          final policy = PermissionRoutePolicy(
            permissions: <String>{permission},
            legacyRole: legacyRole,
          );
          expectHomeInsideGate(policy, label);
        }
      }
    });

    test('every seeded system-role grant set lands inside its own gate', () {
      for (final entry in kSystemRoleGrants.entries) {
        final policy = PermissionRoutePolicy(
          permissions: entry.value,
          legacyRole: UserRole.fromString(entry.key),
        );
        expectHomeInsideGate(policy, 'seeded role ${entry.key}');
        // Each seeded role keeps the screen it landed on before.
        expect(policy.home(), isNotNull);
      }
    });

    test('regression: roles.read alone no longer lands on the RBAC screen', () {
      final policy = PermissionRoutePolicy(
        permissions: <String>{PermissionConstants.rolesRead},
        legacyRole: null,
      );

      // `/admin/rbac` sits under the admin area, and `roles.read` is not one
      // of the permissions that open that area, so the gate rejects it.
      expect(policy.isAllowedPath('/admin/rbac'), isFalse);
      expect(policy.home(), isNull);
    });

    test('regression: queue.manage alone no longer lands on records', () {
      final policy = PermissionRoutePolicy(
        permissions: <String>{PermissionConstants.queueManage},
        legacyRole: null,
      );

      // `/department/records` needs a records permission, which this grant
      // set does not hold, so the gate rejects it.
      expect(policy.isAllowedPath('/department/records'), isFalse);
      expect(policy.home(), isNull);
    });

    test('a specialist with only specialist.patients lands on the directory', () {
      final policy = PermissionRoutePolicy(
        permissions: <String>{PermissionConstants.specialistPatients},
        legacyRole: null,
      );

      // The dashboard needs `specialist.analytics`, which this account does
      // not hold, so the landing falls back to the directory it may open.
      expect(policy.isAllowedPath('/specialist/dashboard'), isFalse);
      expect(policy.home(), '/specialist/patients');
      expect(policy.isAllowedPath(policy.home()!), isTrue);
    });
  });
}
