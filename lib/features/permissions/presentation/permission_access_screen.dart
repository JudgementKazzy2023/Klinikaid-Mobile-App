import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/permissions/permission_service.dart';
import '../../auth/presentation/providers/auth_provider.dart';

/// The screen the app shows when the account cannot be routed.
///
/// Three different things end up here, and they are told apart on purpose:
///
/// * the permission read failed - the grants are unknown, so the screen says
///   so and offers a retry;
/// * the read succeeded and the account holds no permission - the answer is
///   "nothing", so the screen says the account has no access and offers a way
///   out;
/// * the read succeeded and the account holds permissions, but none of them
///   opens a screen of the mobile app - the screen says exactly that instead
///   of claiming the account holds no permission.
///
/// The screen never treats a failure as an empty grant set, and it never
/// falls back to the role text on the profile.
class PermissionAccessScreen extends StatelessWidget {
  const PermissionAccessScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final auth = Provider.of<AuthProvider>(context, listen: true);
    final state = auth.permissionLoadState;

    if (state == PermissionLoadState.loading) {
      return Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final failed = state == PermissionLoadState.failed;
    final noGrants = auth.permissions.isEmpty;
    final title = failed
        ? 'Your permissions could not be loaded'
        : noGrants
            ? 'This account has no access yet'
            : 'No screen is available in the mobile app';
    final message = failed
        ? (auth.permissionLoadError ??
            'The server did not answer with your permissions. Nothing was changed; try again.')
        : noGrants
            ? 'Your account does not hold any permission, so no screen of KlinikAid is open to it. '
                'An administrator can assign a role with permissions.'
            : "Your account's permissions don't include a screen available in the mobile app. "
                'Your access is unchanged; an administrator can assign a role that opens a screen.';

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
                  failed ? Icons.cloud_off_rounded : Icons.lock_outline_rounded,
                  size: 56,
                  color: failed ? theme.colorScheme.error : theme.colorScheme.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  message,
                  key: const Key('permission_access_message'),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
                ),
                const SizedBox(height: 24),
                if (failed)
                  ElevatedButton.icon(
                    key: const Key('permission_access_retry_button'),
                    onPressed: () => auth.retryPermissionLoad(),
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Retry'),
                  )
                else
                  ElevatedButton.icon(
                    key: const Key('permission_access_sign_out_button'),
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
