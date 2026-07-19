enum UserRole {
  admin,
  receptionist,
  @JsonKey(name: 'department_staff')
  departmentStaff,
  @JsonKey(name: 'medical_specialist')
  medicalSpecialist,
  patient;

  static UserRole fromString(String value) {
    switch (value) {
      case 'admin':
        return UserRole.admin;
      case 'receptionist':
        return UserRole.receptionist;
      case 'department_staff':
        return UserRole.departmentStaff;
      case 'medical_specialist':
        return UserRole.medicalSpecialist;
      case 'patient':
      default:
        return UserRole.patient;
    }
  }

  String toJsonValue() {
    switch (this) {
      case UserRole.admin:
        return 'admin';
      case UserRole.receptionist:
        return 'receptionist';
      case UserRole.departmentStaff:
        return 'department_staff';
      case UserRole.medicalSpecialist:
        return 'medical_specialist';
      case UserRole.patient:
        return 'patient';
    }
  }

  /// Human-readable display name for UI badges and labels.
  String get displayName {
    switch (this) {
      case UserRole.admin:
        return 'Admin';
      case UserRole.receptionist:
        return 'Receptionist';
      case UserRole.departmentStaff:
        return 'Department Staff';
      case UserRole.medicalSpecialist:
        return 'Medical Specialist';
      case UserRole.patient:
        return 'Patient';
    }
  }
}

enum Department {
  laboratory,
  imaging,
  ultrasound,
  ecg;

  static Department? fromString(String? value) {
    if (value == null) return null;
    switch (value.toLowerCase()) {
      case 'laboratory':
        return Department.laboratory;
      case 'imaging':
        return Department.imaging;
      case 'ultrasound':
        return Department.ultrasound;
      case 'ecg':
        return Department.ecg;
      default:
        return null;
    }
  }

  String toJsonValue() {
    return name;
  }
}

class Profile {
  final String id;
  final String fullName;
  final UserRole role;
  final String? roleId;
  final Department? department;
  final String? employeeType;
  final bool isActive;
  final DateTime? acceptedPrivacyAt;
  final DateTime? emailVerifiedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  Profile({
    required this.id,
    required this.fullName,
    required this.role,
    this.roleId,
    this.department,
    this.employeeType,
    this.isActive = true,
    this.acceptedPrivacyAt,
    this.emailVerifiedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Profile.fromJson(Map<String, dynamic> json) {
    return Profile(
      id: json['id'] as String,
      fullName: json['full_name'] as String? ?? 'New User',
      role: UserRole.fromString(json['role'] as String? ?? 'patient'),
      roleId: json['role_id'] as String?,
      department: Department.fromString(json['department'] as String?),
      employeeType: json['employee_type'] as String?,
      isActive: json['is_active'] as bool? ?? true,
      acceptedPrivacyAt: json['accepted_privacy_at'] != null
          ? DateTime.parse(json['accepted_privacy_at'] as String)
          : null,
      emailVerifiedAt: json['email_verified_at'] != null
          ? DateTime.parse(json['email_verified_at'] as String)
          : null,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'full_name': fullName,
      'role': role.toJsonValue(),
      'role_id': roleId,
      'department': department?.toJsonValue(),
      'employee_type': employeeType,
      'is_active': isActive,
      'accepted_privacy_at': acceptedPrivacyAt?.toIso8601String(),
      'email_verified_at': emailVerifiedAt?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}

// Annotation mock for json_serializable compat if they use it later
class JsonKey {
  final String name;
  const JsonKey({required this.name});
}
