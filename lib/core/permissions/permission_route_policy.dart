import '../models/profile.dart';
import 'permission_constants.dart';

/// Which screens the permissions of an account open.
///
/// The groups and the per-screen permissions are the web's, not a second
/// set of mobile ones: the web asks the shared backend for the same
/// permission names before it lets an account into an area
/// (`src/app/(dashboard)/layout.tsx`) and before it renders a page
/// (`src/app/(dashboard)/**/page.tsx`). A mobile account therefore reaches
/// exactly the screens its web account reaches.
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

  /// Whether the account may open the admin area.
  bool get canUseAdminShell => hasAny(PermissionConstants.adminArea);

  /// Whether the account may open the reception area.
  bool get canUseReceptionShell => hasAny(PermissionConstants.receptionArea);

  /// Whether the account may open the department area.
  bool get canUseDepartmentShell => hasAny(PermissionConstants.departmentArea);

  /// Whether the account may open the specialist area.
  bool get canUseSpecialistShell => hasAny(PermissionConstants.specialistArea);

  /// The screen the account lands on, or null when it holds no permission
  /// that opens one.
  ///
  /// The order is the web's landing order (web: `getDefaultLandingPath` in
  /// `src/lib/auth/helpers.ts`), so both clients send the same account to the
  /// same screen. An account that holds no permission gets null: there is no
  /// screen for it, and the router shows the denial instead of guessing one
  /// from the role text on the profile.
  String? home() {
    if (legacyRole == UserRole.patient) return '/patient';

    if (legacyRole == UserRole.admin &&
        has(PermissionConstants.profilesManage)) {
      return '/admin/dashboard';
    }
    if (hasAll(PermissionConstants.receptionQueue)) return '/reception/queue';
    if (has(PermissionConstants.patientsManage)) return '/reception/dashboard';
    if (canUseDepartmentShell) return '/department/records';
    if (has(PermissionConstants.specialistPatients)) return '/specialist/dashboard';
    if (has(PermissionConstants.rolesRead)) return '/admin/rbac';
    if (has(PermissionConstants.systemLogsRead)) return '/admin/logs';
    if (has(PermissionConstants.ragDocumentsManage)) return '/admin/rag';
    if (has(PermissionConstants.staffManage)) return '/admin/staff';
    return null;
  }

  String specialistHome() {
    if (has(PermissionConstants.specialistAnalytics)) return '/specialist/dashboard';
    if (has(PermissionConstants.specialistPatients)) return '/specialist/patients';
    return '/specialist/profile';
  }

  /// Whether the account may open [location].
  ///
  /// Every area is guarded the way the web guards it: a route under an area
  /// prefix needs a permission of that area, and the screen itself needs the
  /// permission its web page requires.
  bool isAllowedPath(String location) {
    if (location.startsWith('/admin/')) {
      if (!canUseAdminShell) return false;
      if (location == '/admin/dashboard') {
        return has(PermissionConstants.profilesManage);
      }
      if (location == '/admin/staff') {
        return has(PermissionConstants.staffManage);
      }
      if (location == '/admin/queue' ||
          location.startsWith('/admin/document/')) {
        return has(PermissionConstants.documentsManage);
      }
      if (location == '/admin/records' ||
          location.startsWith('/admin/department/result-entry/')) {
        return hasAny(PermissionConstants.departmentRecordsAny);
      }
      if (location == '/admin/logs') {
        return has(PermissionConstants.systemLogsRead) ||
            has(PermissionConstants.chatbotLogsRead);
      }
      if (location == '/admin/rag') {
        return has(PermissionConstants.ragDocumentsManage);
      }
      if (location == '/admin/rbac') {
        return has(PermissionConstants.rolesRead);
      }
      if (location == '/admin/profile') return true;
      return false;
    }

    if (location.startsWith('/reception/')) {
      if (!canUseReceptionShell) return false;
      if (location == '/reception/dashboard') {
        return has(PermissionConstants.patientsManage);
      }
      if (location == '/reception/queue') {
        return hasAll(PermissionConstants.receptionQueue);
      }
      if (location.startsWith('/reception/document/')) {
        return has(PermissionConstants.documentsManage);
      }
      if (location == '/reception/profile') return true;
      return false;
    }

    if (location.startsWith('/department/')) {
      if (!canUseDepartmentShell) return false;
      if (location == '/department/queue') {
        return hasAny(PermissionConstants.departmentQueueAny);
      }
      if (location == '/department/records' ||
          location.startsWith('/department/result-entry/')) {
        return hasAny(PermissionConstants.departmentRecordsAny);
      }
      if (location == '/department/profile') return true;
      return false;
    }

    if (location.startsWith('/specialist/')) {
      if (!canUseSpecialistShell) return false;
      if (location == '/specialist/dashboard') {
        return has(PermissionConstants.specialistAnalytics);
      }
      if (location == '/specialist/patients') {
        return has(PermissionConstants.specialistPatients);
      }
      if (location == '/specialist/profile') return true;
      if (location.startsWith('/specialist/record-entry/')) {
        return has(PermissionConstants.specialistRecords);
      }
      if (location.startsWith('/specialist/analytics/')) {
        return has(PermissionConstants.specialistAnalytics);
      }
      return false;
    }

    return false;
  }
}
