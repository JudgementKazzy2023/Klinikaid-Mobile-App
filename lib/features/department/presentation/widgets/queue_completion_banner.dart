import 'package:flutter/material.dart';

/// No timer: partial-save feedback stays visible until explicitly dismissed.
/// [onRetry] completes the queue entry only; it never resubmits results.
MaterialBanner queueCompletionBanner(
  String message,
  VoidCallback onDismiss, {
  VoidCallback? onRetry,
}) {
  return MaterialBanner(
    leading: const Icon(Icons.warning_amber_rounded),
    content: Text(message),
    actions: [
      if (onRetry != null)
        TextButton(onPressed: onRetry, child: const Text('Retry queue update')),
      TextButton(onPressed: onDismiss, child: const Text('Dismiss')),
    ],
  );
}
