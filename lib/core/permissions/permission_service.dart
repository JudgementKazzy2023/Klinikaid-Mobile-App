import 'package:supabase_flutter/supabase_flutter.dart';

import '../supabase/supabase_client.dart';
import 'permission_constants.dart';

/// How the last permission load ended.
///
/// The three outcomes are kept apart on purpose: a load that failed leaves
/// the grants *unknown*, which is not the same thing as an account that holds
/// no grants at all.
enum PermissionLoadState {
  /// No load was attempted for the active account.
  idle,

  /// A load is in flight.
  loading,

  /// The server answered. The answer may be empty: an account that holds no
  /// permission has no screen, and that is a different thing from a failure.
  loaded,

  /// The load failed. The grants are unknown, not empty, so the account is
  /// neither routed as if it held nothing nor as if it held everything.
  failed,
}

/// A permission read that did not complete.
class PermissionLoadException implements Exception {
  final String message;

  const PermissionLoadException(this.message);

  @override
  String toString() => message;
}

/// Reads the permissions of the signed-in account.
abstract class PermissionService {
  /// The permissions the signed-in account holds.
  ///
  /// The server decides: the read asks the shared `user_has_permission`
  /// function, the same function the web asks (web:
  /// `src/lib/auth/helpers.ts`), so the mobile app cannot come up with a
  /// different answer than the web for the same account.
  ///
  /// A read that does not complete throws. An empty answer is a successful
  /// read with no grants; the caller keeps the two apart.
  Future<Set<String>> loadPermissions();
}

/// Reads the grants of the signed-in account from the shared backend.
class SupabasePermissionService implements PermissionService {
  final SupabaseClient _client;

  SupabasePermissionService({SupabaseClient? client})
      : _client = client ?? SupabaseService.client;

  @override
  Future<Set<String>> loadPermissions() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null || userId.isEmpty) {
      throw const PermissionLoadException(
        'No signed-in account to read the permissions of.',
      );
    }

    // One call per permission name, all of them at once. The shared function
    // answers for one name at a time, and the names are the whole vocabulary
    // of the backend, so this asks the server the same question the web asks
    // instead of guessing the grants from the role text on the profile.
    //
    // A failed call fails the whole load: a partial answer must never be
    // mistaken for the complete set of grants.
    final names = PermissionConstants.all;
    final answers = await Future.wait(
      names.map((name) => _hasPermission(userId, name)),
    );

    final granted = <String>{};
    for (var i = 0; i < names.length; i++) {
      if (answers[i]) granted.add(names[i]);
    }
    return granted;
  }

  /// Whether the shared backend grants [name] to the signed-in account.
  Future<bool> _hasPermission(String userId, String name) async {
    final result = await _client.rpc('user_has_permission', params: {
      'p_user_id': userId,
      'p_permission_name': name,
    });
    return result == true;
  }
}

/// A permission service that answers from memory, for tests and previews.
class MockPermissionService implements PermissionService {
  Set<String> permissions;
  bool shouldFail;

  MockPermissionService({
    this.permissions = const <String>{},
    this.shouldFail = false,
  });

  @override
  Future<Set<String>> loadPermissions() async {
    if (shouldFail) {
      throw const PermissionLoadException('Mock permission load failed');
    }
    return permissions;
  }
}
