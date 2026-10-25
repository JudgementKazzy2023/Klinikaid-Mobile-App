import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../domain/temporary_password.dart';
import '../providers/auth_provider.dart';

/// Holds an account that still uses the temporary password reception set.
///
/// Mobile cannot replace it: the flag is cleared only by web's set-password
/// step, which uses the service role. Changing the password on web also ends
/// this session, so the patient signs in here again with the new one.
class TemporaryPasswordScreen extends StatelessWidget {
  const TemporaryPasswordScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final auth = Provider.of<AuthProvider>(context, listen: false);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.password_rounded,
                  size: 56,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  'Set a new password first',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Your account still uses the temporary password from reception. '
                  'Sign in on the KlinikAid website to choose your own password, '
                  'then sign in here with the new one.',
                  key: const Key('temporary_password_message'),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  key: const Key('temporary_password_open_web_button'),
                  onPressed: () async {
                    final opened = await launchUrl(
                      Uri.parse(kWebLoginUrl),
                      mode: LaunchMode.externalApplication,
                    );
                    if (!opened && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Could not open the browser. Go to $kWebLoginUrl'),
                        ),
                      );
                    }
                  },
                  icon: const Icon(Icons.open_in_new_rounded),
                  label: const Text('Open the KlinikAid website'),
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  key: const Key('temporary_password_sign_out_button'),
                  onPressed: () async {
                    await auth.signOut();
                  },
                  icon: const Icon(Icons.logout_rounded),
                  label: const Text('Sign out'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
