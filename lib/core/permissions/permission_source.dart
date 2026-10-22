/// The permissions the signed-in account holds.
///
/// The auth provider knows the grants; the screens and the repositories that
/// gate a read or a write need to ask. This is the seam between the two, so
/// a repository can be given the answer without depending on the auth
/// feature.
abstract class PermissionSource {
  /// Whether the account holds [permission].
  bool hasPermission(String permission);

  /// Whether the account holds every permission of [permissions].
  bool hasAllPermissions(List<String> permissions);

  /// Whether the account holds at least one permission of [permissions].
  bool hasAnyPermission(List<String> permissions);
}

/// The account does not hold the permissions an operation needs.
///
/// This is a client-side preflight: it stops the app before it starts a side
/// effect it is not allowed to make. The server remains the authority - the
/// shared backend checks the same permissions again on every write, and a
/// request that slips past this check is refused there.
class PermissionDeniedException implements Exception {
  /// The permissions the operation needs.
  final List<String> required;

  /// What the operation is called, in words a user can read.
  final String operation;

  const PermissionDeniedException(this.operation, this.required);

  @override
  String toString() =>
      'You do not have the permissions this action needs ($operation). '
      'Required: ${required.join(', ')}.';
}
