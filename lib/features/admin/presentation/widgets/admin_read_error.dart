import 'package:flutter/material.dart';

class AdminReadError extends StatelessWidget {
  const AdminReadError({super.key, required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(padding: const EdgeInsets.all(16), child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [Text(message), const SizedBox(height: 12),
        ElevatedButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Retry'))],
    )),
  );
}
