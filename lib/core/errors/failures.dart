import 'package:supabase_flutter/supabase_flutter.dart';

/// Base class representing any app-level failure or error.
abstract class Failure {
  final String message;
  const Failure(this.message);

  @override
  String toString() => message;
}

/// Represents errors originating from database queries or RLS denials.
class DatabaseFailure extends Failure {
  const DatabaseFailure(super.message);
}

/// Represents errors during sign-in, registration, or session validation.
class AuthFailure extends Failure {
  const AuthFailure(super.message);
}

/// Represents internet connection dropouts or server timeouts.
class NetworkFailure extends Failure {
  const NetworkFailure(super.message);
}

/// Represents unhandled or unexpected error cases.
class UnknownFailure extends Failure {
  const UnknownFailure(super.message);
}

/// Mapper utility to map raw library exceptions to structured [Failure] objects.
class FailureMapper {
  static Failure fromException(dynamic exception) {
    if (exception is AuthException) {
      return AuthFailure(exception.message);
    }

    if (exception is PostgrestException) {
      // Postgres error code for 'insufficient_privilege' (usually RLS violation) is '42501'
      if (exception.code == '42501') {
        return const DatabaseFailure(
          'Access denied: You do not have permission to view or modify this data.',
        );
      }
      return DatabaseFailure(exception.message);
    }

    // Socket exceptions or timeouts (network errors)
    final errStr = exception.toString();
    if (errStr.contains('SocketException') || errStr.contains('HandshakeException')) {
      return const NetworkFailure(
        'Connection failed: Please check your internet connection.',
      );
    }

    return UnknownFailure(errStr);
  }
}
