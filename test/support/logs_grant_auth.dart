import 'package:flutter/material.dart';
import 'package:klinikaid_mobile/features/auth/presentation/providers/auth_provider.dart';

/// An [AuthProvider] stand-in that answers only permission questions.
///
/// The admin log screen asks the auth provider which log tabs the account may
/// open. Since the screen now fails closed, a test that pumps it must supply
/// an auth provider with the grants under test instead of relying on a
/// thrown lookup.
class LogsGrantAuth extends ChangeNotifier implements AuthProvider {
  LogsGrantAuth(this.grants);

  final Set<String> grants;

  @override
  bool hasPermission(String permission) => grants.contains(permission);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}
