import 'package:supabase_flutter/supabase_flutter.dart';

/// Asks the server to send a password reset link.
///
/// Only the address is sent. The server decides where the link leads, so the
/// client cannot choose a redirect destination.
abstract class PasswordResetService {
  /// Throws a [FunctionException] when the server answers with an error, and
  /// another exception when no answer arrives.
  Future<void> requestReset(String email);
}

/// Sends a request to the named Edge function with the given JSON body.
typedef ResetRequestSender = Future<void> Function(String functionName, Map<String, dynamic> body);

class SupabasePasswordResetService implements PasswordResetService {
  static const functionName = 'request-password-reset';

  final ResetRequestSender _send;

  SupabasePasswordResetService(this._send);

  factory SupabasePasswordResetService.forClient(SupabaseClient client) {
    return SupabasePasswordResetService(
      (name, body) async {
        await client.functions.invoke(name, body: body);
      },
    );
  }

  @override
  Future<void> requestReset(String email) {
    return _send(functionName, {'email': email});
  }
}
