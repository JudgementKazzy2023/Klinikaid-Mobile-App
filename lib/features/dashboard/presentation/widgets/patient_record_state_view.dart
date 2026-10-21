import 'package:flutter/material.dart';

import '../../../auth/domain/patient_record_state.dart';

/// The surface shown when the patient record of the active account cannot be
/// shown.
///
/// A failed read and a missing row are different problems and get different
/// surfaces: the failed read is retryable, the missing row is not, so it
/// offers a way out instead of a retry that cannot succeed.
class PatientRecordStateView extends StatelessWidget {
  /// Outcome of the patient record lookup.
  final PatientRecordState state;

  /// Reason the lookup failed, shown when [state] is
  /// [PatientRecordState.failed].
  final String? errorMessage;

  /// Re-runs the patient record lookup.
  final Future<void> Function() onRetry;

  /// Ends the session, offered when the record is missing.
  final Future<void> Function() onSignOut;

  const PatientRecordStateView({
    super.key,
    required this.state,
    this.errorMessage,
    required this.onRetry,
    required this.onSignOut,
  });

  @override
  Widget build(BuildContext context) {
    switch (state) {
      case PatientRecordState.failed:
        return _PatientRecordNotice(
          icon: Icons.cloud_off_rounded,
          iconColor: Theme.of(context).colorScheme.error,
          title: 'Could not load your patient record',
          message: errorMessage ??
              'We could not retrieve your patient record details. Please try again.',
          actions: [
            ElevatedButton.icon(
              onPressed: () {
                onRetry();
              },
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Retry'),
            ),
          ],
        );
      case PatientRecordState.missing:
        return _PatientRecordNotice(
          icon: Icons.person_off_outlined,
          iconColor: Theme.of(context).colorScheme.primary,
          title: 'Patient record not found',
          message: 'We could not retrieve your patient record details. '
              'Please contact clinic staff to link your authentication account.',
          actions: [
            OutlinedButton.icon(
              onPressed: () {
                onRetry();
              },
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Try Again'),
            ),
            TextButton(
              onPressed: () {
                onSignOut();
              },
              child: const Text('Sign Out'),
            ),
          ],
        );
      case PatientRecordState.loaded:
      case PatientRecordState.loading:
      case PatientRecordState.unknown:
        return Center(
          child: CircularProgressIndicator(
            color: Theme.of(context).colorScheme.primary,
          ),
        );
    }
  }
}

/// Explains why there is no patient data and offers the way out.
class _PatientRecordNotice extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String message;
  final List<Widget> actions;

  const _PatientRecordNotice({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.message,
    required this.actions,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Container(
          padding: const EdgeInsets.all(24.0),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Theme.of(context).colorScheme.outline, width: 1),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(icon, color: iconColor, size: 48),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 24),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: actions,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
