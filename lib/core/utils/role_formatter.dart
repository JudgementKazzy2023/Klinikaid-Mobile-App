import '../models/profile.dart';

/// Returns a human-readable label for a staff role, incorporating the
/// assigned department for [UserRole.departmentStaff] so that the profile
/// badge shows e.g. "LABORATORY STAFF" instead of the generic
/// "DEPARTMENT STAFF".
///
/// All other roles fall through to [UserRole.displayName].
///
/// [department] is optional; if null or not recognised, falls back to
/// the generic "Department Staff" label.
String roleDisplayLabel(UserRole role, Department? department) {
  if (role == UserRole.departmentStaff) {
    switch (department) {
      case Department.laboratory:
        return 'Laboratory Staff';
      case Department.imaging:
        return 'Imaging Staff';
      case Department.ultrasound:
        return 'Ultrasound Staff';
      case Department.ecg:
        return 'ECG Staff';
      case null:
        return 'Department Staff';
    }
  }
  return role.displayName;
}
