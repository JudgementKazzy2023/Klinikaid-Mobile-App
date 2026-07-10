import 'package:flutter/material.dart';
import '../../data/reject_reason_presets.dart';

/// Modal bottom sheet for document rejection.
///
/// Receptionists can select from common presets which REPLACE the textbox content.
/// The text field is editable, requiring a minimum of 20 characters.
class RejectDocumentSheet extends StatefulWidget {
  final String patientName;
  final void Function(String reason) onConfirm;
  final bool isLoading;

  const RejectDocumentSheet({
    super.key,
    required this.patientName,
    required this.onConfirm,
    this.isLoading = false,
  });

  @override
  State<RejectDocumentSheet> createState() => _RejectDocumentSheetState();
}

class _RejectDocumentSheetState extends State<RejectDocumentSheet> {
  final _formKey = GlobalKey<FormState>();
  final _reasonController = TextEditingController();
  int _charCount = 0;

  @override
  void initState() {
    super.initState();
    _reasonController.addListener(_updateCharCount);
  }

  @override
  void dispose() {
    _reasonController.removeListener(_updateCharCount);
    _reasonController.dispose();
    super.dispose();
  }

  void _updateCharCount() {
    setState(() {
      _charCount = _reasonController.text.trim().length;
    });
  }

  void _selectPreset(String text) {
    setState(() {
      _reasonController.text = text;
      // Places cursor at the end of the text
      _reasonController.selection = TextSelection.fromPosition(
        TextPosition(offset: text.length),
      );
    });
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    if (_charCount < 20) return;
    widget.onConfirm(_reasonController.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isMinCharsMet = _charCount >= 20;
    final confirmEnabled = isMinCharsMet && !widget.isLoading;

    return SingleChildScrollView(
      physics: const ClampingScrollPhysics(),
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 8,
          bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Handle bar
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.outline.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Title
              Text(
                'Reject Document Submission?',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Provide a clear reason so the patient can understand and resubmit.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
              const SizedBox(height: 20),

              // Common presets
              _SectionLabel(label: 'COMMON REASONS (tap to fill, then edit)'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: rejectPresets.entries.map((entry) {
                  return ActionChip(
                    label: Text(entry.key),
                    onPressed: () => _selectPreset(entry.value),
                    labelStyle: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    backgroundColor: theme.colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.3),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(
                        color: theme.colorScheme.outline.withValues(alpha: 0.15),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 20),

              // Rejection Reason
              _SectionLabel(label: 'REJECTION REASON * (minimum 20 characters)'),
              const SizedBox(height: 8),
              TextFormField(
                controller: _reasonController,
                maxLines: 4,
                decoration: InputDecoration(
                  hintText: 'Describe the reason for rejection...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return 'Please enter a rejection reason';
                  }
                  if (val.trim().length < 20) {
                    return 'Reason must be at least 20 characters';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 8),

              // Counter and help hint row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '$_charCount characters',
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
                    ),
                  ),
                  if (!isMinCharsMet)
                    Text(
                      'Needs ${20 - _charCount} more characters',
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.error,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 24),

              // Action buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: widget.isLoading ? null : () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 48),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: confirmEnabled ? _submit : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: theme.colorScheme.error,
                        foregroundColor: theme.colorScheme.onError,
                        minimumSize: const Size(0, 48),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: widget.isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : const Text('Confirm Rejection'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.8,
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55),
      ),
    );
  }
}
