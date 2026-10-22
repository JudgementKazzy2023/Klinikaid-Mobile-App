/// The pure filter rules of the Personnel Registry (the mobile mirror of the
/// web module `src/app/(dashboard)/admin/staff/staff-filters.ts`).
///
/// The screen owns the picker, the role catalogue and the loaded rows; this
/// module owns one question: "which of these rows does this filter select?".
/// Keeping the two apart is what makes the rules testable without a widget
/// tree -- the acceptance criteria for this feature are all about which rows
/// survive a filter, and those are exactly the claims a unit test can make.
///
/// Nothing here reads a widget, a clock or the network.
library;

import '../../../core/models/profile.dart';
import 'admin_rbac.dart';

/// The value the "All ..." options carry in the picker. Never a real filter.
const String kStaffFilterAll = 'all';

/// The departments the registry can be filtered by.
///
/// The clinical departments of the clinic and "none", the staff without a
/// department. Web: `DepartmentFilterValue` in `staff-filters.ts`; the labels
/// are the web's `DEPARTMENTS` labels.
enum StaffDepartmentFilter {
  laboratory('laboratory', 'Laboratory'),
  imaging('imaging', 'Imaging (X-Ray)'),
  ultrasound('ultrasound', 'Ultrasound'),
  ecg('ecg', 'ECG'),
  none('none', 'No department');

  const StaffDepartmentFilter(this.value, this.label);

  /// The value the picker carries and the filter compares.
  final String value;

  /// The label the picker shows.
  final String label;
}

/// The statuses the registry can be filtered by.
///
/// Web: `StatusFilterValue` in `staff-filters.ts`.
enum StaffStatusFilter {
  active('active', 'Active'),
  inactive('inactive', 'Inactive');

  const StaffStatusFilter(this.value, this.label);

  /// The value the picker carries and the filter compares.
  final String value;

  /// The label the picker shows.
  final String label;
}

/// The role a filter points at.
class StaffRoleFilter {
  const StaffRoleFilter({required this.id, this.legacyName});

  /// `roles.id` of the selected role.
  final String id;

  /// The legacy `profiles.role` text a profile created before `role_id`
  /// existed may still carry -- or null when no profile can carry it.
  ///
  /// Only a system role has one. A custom role stores its *base* role in the
  /// legacy column, and the base role is a different role, so treating a
  /// custom role's base text as a synonym would file base-role staff under
  /// the custom role.
  final String? legacyName;
}

/// The filter state the registry table applies.
class StaffFilters {
  const StaffFilters({this.role, this.department, this.status});

  /// null means "every role".
  final StaffRoleFilter? role;

  /// null means "every department".
  final StaffDepartmentFilter? department;

  /// null means "both statuses".
  final StaffStatusFilter? status;

  /// Is any dimension filtered?
  ///
  /// The "Clear filters" action is only offered when there is something to
  /// clear.
  bool get hasActiveFilters =>
      role != null || department != null || status != null;
}

/// The label of a role in the filter picker.
///
/// The same rule the web uses (`roleLabel` in `staff-form.ts`): a system role
/// is its name with the underscores turned into spaces and the first letter
/// capitalised, a custom role keeps the name it was created with.
String staffRoleFilterLabel(AdminRole role) {
  if (!role.isSystem) return role.name;
  final spaced = role.name.replaceAll('_', ' ');
  if (spaced.isEmpty) return role.name;
  return spaced[0].toUpperCase() + spaced.substring(1);
}

/// Reads a department out of a picker value.
///
/// "all" and an empty value mean "no department filter"; a department the
/// clinic does not have is dropped, so the registry shows everything instead
/// of an unexplained empty list.
StaffDepartmentFilter? parseStaffDepartmentFilter(String? raw) {
  final value = (raw ?? '').trim().toLowerCase();
  if (value.isEmpty || value == kStaffFilterAll) return null;
  for (final option in StaffDepartmentFilter.values) {
    if (option.value == value) return option;
  }
  return null;
}

/// Reads a status out of a picker value.
///
/// "all" and an empty value mean "no status filter"; anything other than
/// active or inactive is dropped.
StaffStatusFilter? parseStaffStatusFilter(String? raw) {
  final value = (raw ?? '').trim().toLowerCase();
  if (value.isEmpty || value == kStaffFilterAll) return null;
  for (final option in StaffStatusFilter.values) {
    if (option.value == value) return option;
  }
  return null;
}

/// Resolves a role id against the live catalogue.
///
/// An id the catalogue does not know keeps its filter, as on the web
/// (`resolveRoleFilter`): the rows that carry it are not rows this registry
/// holds, and "no match" is truer than quietly dropping the chosen filter.
StaffRoleFilter? resolveStaffRoleFilter(String? roleId, List<AdminRole> catalogue) {
  final id = (roleId ?? '').trim();
  if (id.isEmpty || id == kStaffFilterAll) return null;
  for (final role in catalogue) {
    if (role.id != id) continue;
    return StaffRoleFilter(id: id, legacyName: role.isSystem ? role.name : null);
  }
  return StaffRoleFilter(id: id, legacyName: null);
}

/// The filter the table applies: the chosen dimensions with the role id
/// resolved against the live catalogue.
StaffFilters buildStaffFilters({
  String? roleId,
  StaffDepartmentFilter? department,
  StaffStatusFilter? status,
  List<AdminRole> catalogue = const <AdminRole>[],
}) {
  return StaffFilters(
    role: resolveStaffRoleFilter(roleId, catalogue),
    department: department,
    status: status,
  );
}

/// Does a staff member carry this role?
///
/// A profile with a role id is matched by that id. A profile created before
/// `role_id` existed only carries the legacy role text, and only a system
/// role has a text of its own: a custom role stores its base role there, and
/// that base role is a different role.
bool matchesStaffRole(Profile staff, StaffRoleFilter filter) {
  final roleId = staff.roleId;
  if (roleId != null && roleId.isNotEmpty) return roleId == filter.id;
  // No role id: only a system role can still be identified by its legacy text.
  final legacyName = filter.legacyName;
  if (legacyName == null) return false;
  return staff.role.toJsonValue() == legacyName;
}

/// Does a staff member belong to this department?
///
/// "none" is the members without a department, which is not the same as a
/// department that is spelled differently.
bool matchesStaffDepartment(Profile staff, StaffDepartmentFilter value) {
  if (value == StaffDepartmentFilter.none) return staff.department == null;
  return staff.department?.toJsonValue() == value.value;
}

/// Is this staff member in this status?
bool matchesStaffStatus(Profile staff, StaffStatusFilter value) {
  return value == StaffStatusFilter.active ? staff.isActive : !staff.isActive;
}

/// Does a staff member match the free-text search?
///
/// The search covers the same fields it always did: the name and the role.
/// An empty term matches everything.
bool matchesStaffSearch(Profile staff, String query) {
  final term = query.trim().toLowerCase();
  if (term.isEmpty) return true;
  return staff.fullName.toLowerCase().contains(term) ||
      staff.role.displayName.toLowerCase().contains(term);
}

/// The rows a filter selects.
///
/// Every dimension is optional and they combine with AND, so a filtered view
/// is always a subset of the unfiltered one.
List<Profile> filterStaff(
  List<Profile> staff,
  StaffFilters filters, {
  String search = '',
}) {
  return staff.where((member) {
    final role = filters.role;
    final department = filters.department;
    final status = filters.status;
    return (role == null || matchesStaffRole(member, role)) &&
        (department == null || matchesStaffDepartment(member, department)) &&
        (status == null || matchesStaffStatus(member, status)) &&
        matchesStaffSearch(member, search);
  }).toList();
}
