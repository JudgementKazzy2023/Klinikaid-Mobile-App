import '../../../core/models/profile.dart';

class AdminPermission {
  final String id;
  final String name;
  final String description;
  final String module;

  const AdminPermission({
    required this.id,
    required this.name,
    required this.description,
    required this.module,
  });

  factory AdminPermission.fromJson(Map<String, dynamic> json) {
    return AdminPermission(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      module: json['module'] as String? ?? 'general',
    );
  }
}

class AdminRole {
  final String id;
  final String name;
  final String description;
  final bool isSystem;
  final String? baseRole;
  final List<AdminPermission> permissions;

  const AdminRole({
    required this.id,
    required this.name,
    required this.description,
    required this.isSystem,
    this.baseRole,
    this.permissions = const [],
  });

  factory AdminRole.fromJson(
    Map<String, dynamic> json, {
    List<AdminPermission> permissions = const [],
  }) {
    return AdminRole(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      isSystem: json['is_system'] as bool? ?? false,
      baseRole: json['base_role'] as String?,
      permissions: permissions,
    );
  }

  String get displayName {
    if (isSystem) {
      return UserRole.fromString(name).displayName;
    }
    return name;
  }

  String get legacyProfileRole {
    return isSystem ? name : (baseRole ?? name);
  }

  bool get usesDepartment {
    return legacyProfileRole == UserRole.departmentStaff.toJsonValue();
  }
}

class AdminRbacCatalog {
  final List<AdminRole> roles;
  final List<AdminPermission> permissions;

  const AdminRbacCatalog({
    required this.roles,
    required this.permissions,
  });
}

