import 'package:supabase_flutter/supabase_flutter.dart';

enum MfaVerifyResult {
  success,
  invalidCode,
  expired,
  error,
}

class MfaService {
  final SupabaseClient _supabase;

  MfaService(this._supabase);

  /// Returns list of verified TOTP factors for current session
  Future<List<Factor>> listVerifiedFactors() async {
    final result = await _supabase.auth.mfa.listFactors();
    return result.totp.where((f) => f.status == FactorStatus.verified).toList();
  }

  /// Returns true if current session requires step-up to AAL2
  bool requiresStepUp() {
    final aalResult = _supabase.auth.mfa.getAuthenticatorAssuranceLevel();
    return aalResult.currentLevel != aalResult.nextLevel &&
        aalResult.nextLevel == AuthenticatorAssuranceLevels.aal2;
  }

  /// Verify TOTP code → upgrades session to AAL2
  Future<MfaVerifyResult> verifyTotp({
    required String factorId,
    required String code,
  }) async {
    try {
      print('[MfaService verifyTotp] Initiating challenge for factorId: $factorId');
      final challenge = await _supabase.auth.mfa.challenge(
        factorId: factorId,
      );
      print('[MfaService verifyTotp] Challenge created: challengeId = ${challenge.id}');
      
      if (challenge.id.isEmpty) {
        print('[MfaService verifyTotp] Error: challengeId is empty or stale!');
        return MfaVerifyResult.error;
      }

      print('[MfaService verifyTotp] Verifying code with challengeId: ${challenge.id}');
      final response = await _supabase.auth.mfa.verify(
        factorId: factorId,
        challengeId: challenge.id,
        code: code,
      );
      print('[MfaService verifyTotp] Verify response user ID: ${response.user?.id}');
      return MfaVerifyResult.success;
    } on AuthException catch (e) {
      print('[MfaService verifyTotp] AuthException: $e');
      if (e.message.toLowerCase().contains('invalid')) {
        return MfaVerifyResult.invalidCode;
      }
      if (e.message.toLowerCase().contains('expired')) {
        return MfaVerifyResult.expired;
      }
      return MfaVerifyResult.error;
    } catch (e, stack) {
      print('[MfaService verifyTotp] UNKNOWN ERROR: $e');
      print('[MfaService verifyTotp] Stack: $stack');
      rethrow;  // let caller's try/finally clear _isLoading
    }
  }
}
