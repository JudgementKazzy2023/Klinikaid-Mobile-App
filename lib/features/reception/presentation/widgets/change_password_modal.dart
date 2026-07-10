import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:klinikaid_mobile/features/auth/presentation/providers/auth_provider.dart';
import 'package:klinikaid_mobile/features/auth/domain/password_change_result.dart';
import 'package:klinikaid_mobile/features/auth/domain/registration_validators.dart';

/// Modal dialog for self-service password change with current-password
/// reauthentication.
///
/// Available to all authenticated staff roles (receptionist, department
/// staff, specialist). Opened via [showDialog] from [ProfileScreen].
class ChangePasswordModal extends StatefulWidget {
  const ChangePasswordModal({super.key});

  @override
  State<ChangePasswordModal> createState() => _ChangePasswordModalState();
}

class _ChangePasswordModalState extends State<ChangePasswordModal> {
  final _currentController = TextEditingController();
  final _newController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _currentObscured = true;
  bool _newObscured = true;
  bool _confirmObscured = true;

  bool _isLoading = false;
  String? _errorMessage;

  // ─── Inline validation ────────────────────────────────────────────────────

  String? get _newPasswordError {
    final v = _newController.text;
    if (v.isEmpty) return null; // show error only after user types
    if (!RegistrationValidators.validatePassword(v)) {
      return 'Min 8 characters, 1 number, 1 special character';
    }
    if (v == _currentController.text && _currentController.text.isNotEmpty) {
      return 'New password must differ from current password';
    }
    return null;
  }

  String? get _confirmError {
    final v = _confirmController.text;
    if (v.isEmpty) return null;
    if (v != _newController.text) return 'Passwords do not match';
    return null;
  }

  bool get _canSubmit {
    if (_isLoading) return false;
    if (_currentController.text.isEmpty) return false;
    if (_newController.text.isEmpty || _confirmController.text.isEmpty) {
      return false;
    }
    if (_newPasswordError != null || _confirmError != null) return false;
    return true;
  }

  // ─── Submit ───────────────────────────────────────────────────────────────

  Future<void> _submit() async {
    if (!_canSubmit) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final result = await authProvider.changePassword(
      currentPassword: _currentController.text,
      newPassword: _newController.text,
    );

    if (!mounted) return;

    switch (result) {
      case PasswordChangeResult.success:
        final messenger = ScaffoldMessenger.of(context);
        final primaryColor = Theme.of(context).colorScheme.primary;
        Navigator.of(context).pop(true);
        messenger.showSnackBar(
          SnackBar(
            content: const Text('Password updated'),
            backgroundColor: primaryColor,
          ),
        );
      case PasswordChangeResult.wrongCurrentPassword:
        setState(() {
          _errorMessage = 'Current password is incorrect';
          _isLoading = false;
        });
      case PasswordChangeResult.notAuthenticated:
        setState(() {
          _errorMessage = 'No active session. Please sign in again.';
          _isLoading = false;
        });
      case PasswordChangeResult.error:
        setState(() {
          _errorMessage = 'An error occurred. Please try again.';
          _isLoading = false;
        });
    }
  }

  @override
  void dispose() {
    _currentController.dispose();
    _newController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      backgroundColor: Theme.of(context).cardColor,
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Header ──────────────────────────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Change Password',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: _isLoading ? null : () => Navigator.of(context).pop(false),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // ── Error banner ─────────────────────────────────────────────────
            if (_errorMessage != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.error.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.error.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline,
                        color: Theme.of(context).colorScheme.error, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // ── Current password ─────────────────────────────────────────────
            _PasswordField(
              key: const Key('field_current_password'),
              controller: _currentController,
              label: 'CURRENT PASSWORD',
              obscured: _currentObscured,
              onToggle: () => setState(() => _currentObscured = !_currentObscured),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),

            // ── New password ─────────────────────────────────────────────────
            _PasswordField(
              key: const Key('field_new_password'),
              controller: _newController,
              label: 'NEW PASSWORD',
              obscured: _newObscured,
              onToggle: () => setState(() => _newObscured = !_newObscured),
              onChanged: (_) => setState(() {}),
              errorText: _newController.text.isNotEmpty ? _newPasswordError : null,
            ),
            const SizedBox(height: 16),

            // ── Confirm password ─────────────────────────────────────────────
            _PasswordField(
              key: const Key('field_confirm_password'),
              controller: _confirmController,
              label: 'CONFIRM NEW PASSWORD',
              obscured: _confirmObscured,
              onToggle: () => setState(() => _confirmObscured = !_confirmObscured),
              onChanged: (_) => setState(() {}),
              errorText: _confirmController.text.isNotEmpty ? _confirmError : null,
            ),
            const SizedBox(height: 24),

            // ── Buttons ──────────────────────────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _isLoading ? null : () => Navigator.of(context).pop(false),
                  child: Text(
                    'Cancel',
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  key: const Key('btn_update_password'),
                  onPressed: _canSubmit ? _submit : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    disabledBackgroundColor:
                        Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
                    foregroundColor: Theme.of(context).colorScheme.onPrimary,
                    disabledForegroundColor:
                        Theme.of(context).colorScheme.onPrimary.withValues(alpha: 0.38),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Text('Update Password'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Private helper widget ────────────────────────────────────────────────────

class _PasswordField extends StatelessWidget {
  const _PasswordField({
    super.key,
    required this.controller,
    required this.label,
    required this.obscured,
    required this.onToggle,
    required this.onChanged,
    this.errorText,
  });

  final TextEditingController controller;
  final String label;
  final bool obscured;
  final VoidCallback onToggle;
  final ValueChanged<String> onChanged;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6.0, left: 4.0),
          child: Text(
            label,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
        ),
        TextField(
          controller: controller,
          obscureText: obscured,
          onChanged: onChanged,
          style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
          decoration: InputDecoration(
            filled: true,
            fillColor: Theme.of(context).scaffoldBackgroundColor,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            prefixIcon: Icon(
              Icons.lock_outline,
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.7),
              size: 20,
            ),
            suffixIcon: IconButton(
              icon: Icon(
                obscured ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                size: 20,
              ),
              onPressed: onToggle,
            ),
            errorText: errorText,
            errorStyle:
                TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 11),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide:
                  BorderSide(color: Theme.of(context).colorScheme.outline),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide:
                  BorderSide(color: Theme.of(context).colorScheme.outline),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                  color: Theme.of(context).colorScheme.primary, width: 1.5),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide:
                  BorderSide(color: Theme.of(context).colorScheme.error),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(
                  color: Theme.of(context).colorScheme.error, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }
}
