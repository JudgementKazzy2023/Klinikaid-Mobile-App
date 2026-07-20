import '../models/profile.dart';
import 'permission_constants.dart';

class PermissionRoutePolicy {
  final Set<String> permissions;
  final UserRole? legacyRole;

  const PermissionRoutePolicy({
    required this.permissions,
    required this.legacyRole,
  });

  bool has(String permission) => permissions.contains(permission);
  bool hasAll(List<String> requiredPermissions) =>
      requiredPermissions.every(permissions.contains);
  bool hasAny(List<String> requiredPermissions) =>
      requiredPermissions.any(permissions.contains);

  bool get canUseAdminShell => hasAny(PermissionConstants.adminAny);
  bool get canUseReceptionShell => hasAll(PermissionConstants.receptionQueue);
  bool get canUseDepartmentShell => hasAny(PermissionConstants.departmentRecordsAny);
  bool get canUseSpecialistShell => hasAny(PermissionConstants.specialistAny);

  String? home() {
    if (legacyRole == UserRole.patient) return '/patient';

    if (legacyRole == UserRole.admin && canUseAdminShell) return '/admin/dashboard';
    if (legacyRole == UserRole.receptionist && canUseReceptionShell) {
      return '/reception/queue';
    }
    if (legacyRole == UserRole.departmentStaff && canUseDepartmentShell) {
      return '/department/queue';
    }
    if (legacyRole == UserRole.medicalSpecialist && canUseSpecialistShell) {
      return specialistHome();
    }

    if (canUseAdminShell) return '/admin/dashboard';
    if (canUseReceptionShell) return '/reception/queue';
    if (canUseDepartmentShell) return '/department/queue';
    if (canUseSpecialistShell) return specialistHome();
    return legacyHome();
  }

  String? legacyHome() {
    if (legacyRole == UserRole.patient) return '/patient';
    if (legacyRole == UserRole.admin) return '/admin/dashboard';
    if (legacyRole == UserRole.receptionist) return '/reception/queue';
    if (legacyRole == UserRole.departmentStaff) return '/department/queue';
    if (legacyRole == UserRole.medicalSpecialist) return '/specialist/dashboard';
    return null;
  }

  String specialistHome() {
    if (has(PermissionConstants.specialistAnalytics)) return '/specialist/dashboard';
    if (has(PermissionConstants.specialistPatients)) return '/specialist/patients';
    return '/specialist/profile';
  }

  bool isAllowedPath(String location) {
    if (location == '/admin/dashboard' || location == '/admin/profile') {
      return canUseAdminShell;
    }
    if (location == '/admin/staff') return has(PermissionConstants.staffManage);
    if (location == '/admin/queue' || location.startsWith('/admin/document/')) {
      return canUseReceptionShell;
    }
    if (location == '/admin/records' ||
        location.startsWith('/admin/department/result-entry/')) {
      return canUseDepartmentShell;
    }
    if (location == '/admin/logs') {
      return has(PermissionConstants.systemLogsRead) ||
          has(PermissionConstants.chatbotLogsRead);
    }
    if (location == '/admin/rag') return has(PermissionConstants.ragDocumentsManage);
    if (location == '/admin/rbac') return has(PermissionConstants.rolesRead);

    if (location == '/reception/dashboard' ||
        location == '/reception/queue' ||
        location == '/reception/profile' ||
        location.startsWith('/reception/document/')) {
      return canUseReceptionShell;
    }

    if (location == '/department/queue' ||
        location == '/department/records' ||
        location == '/department/profile' ||
        location.startsWith('/department/result-entry/')) {
      return canUseDepartmentShell;
    }

    if (location == '/specialist/dashboard') {
      return has(PermissionConstants.specialistAnalytics);
    }
    if (location == '/specialist/patients') {
      return has(PermissionConstants.specialistPatients);
    }
    if (location == '/specialist/profile') return canUseSpecialistShell;
    if (location.startsWith('/specialist/record-entry/')) {
      return has(PermissionConstants.specialistRecords);
    }
    if (location.startsWith('/specialist/analytics/')) {
      return has(PermissionConstants.specialistAnalytics);
    }

    return false;
  }
}
