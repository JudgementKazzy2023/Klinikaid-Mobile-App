import 'package:supabase_flutter/supabase_flutter.dart';

import '../supabase/supabase_client.dart';

abstract class PermissionService {
  Future<Set<String>> loadPermissionsForRole(String roleId);
}

class SupabasePermissionService implements PermissionService {
  final SupabaseClient _client;

  SupabasePermissionService({SupabaseClient? client})
      : _client = client ?? SupabaseService.client;

  @override
  Future<Set<String>> loadPermissionsForRole(String roleId) async {
    final response = await _client
        .from('role_permissions')
        .select('permission:permissions(name)')
        .eq('role_id', roleId);

    final rows = response as List;
    final permissions = <String>{};
    for (final row in rows) {
      final map = row as Map<String, dynamic>;
      final permission = map['permission'];
      if (permission is Map<String, dynamic>) {
        final name = permission['name'];
        if (name is String && name.trim().isNotEmpty) {
          permissions.add(name);
        }
      }
    }
    return permissions;
  }
}

class MockPermissionService implements PermissionService {
  Set<String> permissions;
  bool shouldFail;

  MockPermissionService({
    this.permissions = const <String>{},
    this.shouldFail = false,
  });

  @override
  Future<Set<String>> loadPermissionsForRole(String roleId) async {
    if (shouldFail) {
      throw Exception('Mock permission load failed');
    }
    return permissions;
  }
}
