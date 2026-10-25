import 'package:supabase_flutter/supabase_flutter.dart';

/// Accounts a receptionist creates start with a password the receptionist has
/// seen. `app_metadata.must_change_password` marks them until the patient
/// replaces it on web (web: `src/lib/auth/temporary-password.ts`). Only the
/// service role can clear the flag, so mobile holds the account at
/// [kTemporaryPasswordRoute] and sends it to web.
const String kMustChangePasswordKey = 'must_change_password';

const String kTemporaryPasswordRoute = '/temporary-password';

/// Where a flagged account replaces its password. Web's login sends a flagged
/// account to `/set-password`.
const String kWebLoginUrl = 'https://www.klinikaid.com/login';

/// Same rule as web's `mustChangePassword`: only a literal `true` counts.
bool mustChangePassword(User? user) =>
    user?.appMetadata[kMustChangePasswordKey] == true;
