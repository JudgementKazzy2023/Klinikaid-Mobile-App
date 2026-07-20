import 'package:flutter_test/flutter_test.dart';
import 'package:klinikaid_mobile/core/models/profile.dart';
import 'package:klinikaid_mobile/core/permissions/permission_constants.dart';
import 'package:klinikaid_mobile/core/permissions/permission_route_policy.dart';

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
}
