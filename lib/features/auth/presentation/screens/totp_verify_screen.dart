import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../providers/auth_provider.dart';
import '../../data/mfa_service.dart';

class TotpVerifyScreen extends StatefulWidget {
  const TotpVerifyScreen({super.key});

  @override
  State<TotpVerifyScreen> createState() => _TotpVerifyScreenState();
}

class _TotpVerifyScreenState extends State<TotpVerifyScreen> {
  final List<FocusNode> _focusNodes = List.generate(6, (_) => FocusNode());
  final List<TextEditingController> _controllers = List.generate(6, (_) => TextEditingController());
  String? _localError;

  bool _enrollmentInitiated = false;
  String? _enrollSecret;
  String? _enrollmentError;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final authProvider = Provider.of<AuthProvider>(context);
    if (authProvider.needsMfaEnrollment && !_enrollmentInitiated) {
      _enrollmentInitiated = true;
      Future.microtask(() {
        if (mounted) {
          _startMfaEnrollment();
        }
      });
    }
  }

  Future<void> _startMfaEnrollment() async {
    setState(() {
      _enrollmentError = null;
    });
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final response = await authProvider.startMfaEnrollment();
      setState(() {
        _enrollSecret = response.totp.secret;
      });
    } catch (e) {
      setState(() {
        _enrollmentError = 'Failed to initiate MFA enrollment: $e';
        _enrollmentInitiated = false;
      });
    }
  }

  @override
  void dispose() {
    for (var node in _focusNodes) {
      node.dispose();
    }
    for (var controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  String _getEnteredCode() {
    return _controllers.map((c) => c.text).join();
  }

  bool _isCodeComplete() {
    return _controllers.every((c) => c.text.isNotEmpty);
  }

  void _onVerifyPressed() async {
    if (!_isCodeComplete()) return;

    setState(() {
      _localError = null;
    });

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final code = _getEnteredCode();

    final result = await authProvider.verifyMfa(code);
    if (!mounted) return;

    if (result == MfaVerifyResult.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Verification successful!'),
          backgroundColor: Theme.of(context).colorScheme.primary,
        ),
      );
      // GoRouter automatically redirects to home
    } else {
      setState(() {
        if (result == MfaVerifyResult.invalidCode) {
          _localError = 'Invalid verification code. Please try again.';
        } else if (result == MfaVerifyResult.expired) {
          _localError = 'Code has expired. Please use the latest code.';
        } else {
          _localError = 'An error occurred. Please try again.';
        }
      });
    }
  }

  void _onSignOutPressed() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    await authProvider.cancelMfaFlow();
    if (mounted) {
      context.go('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final size = MediaQuery.of(context).size;
    final isEnrollment = authProvider.needsMfaEnrollment;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Container(
            constraints: BoxConstraints(minHeight: size.height - MediaQuery.of(context).padding.vertical),
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 36.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Hero(
                    tag: 'app_logo',
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2)),
                      ),
                      child: Icon(
                        Icons.security_rounded,
                        size: 40,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  isEnrollment ? 'Setup Two-Factor Auth' : 'Two-Factor Verification',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  isEnrollment
                      ? 'Add this account to your authenticator app using the secret key below'
                      : 'Open your authenticator app and enter the 6-digit code',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 24),

                Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Enrollment UI
                        if (isEnrollment) ...[
                          if (_enrollSecret == null && _enrollmentError == null) ...[
                            const Center(
                              child: Padding(
                                padding: EdgeInsets.symmetric(vertical: 20.0),
                                child: CircularProgressIndicator(),
                              ),
                            ),
                          ] else if (_enrollmentError != null) ...[
                            Text(
                              _enrollmentError!,
                              style: TextStyle(color: Theme.of(context).colorScheme.error),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 12),
                            ElevatedButton(
                              onPressed: _startMfaEnrollment,
                              child: const Text('Retry Setup'),
                            ),
                          ] else if (_enrollSecret != null) ...[
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3)),
                              ),
                              child: Column(
                                children: [
                                  const Text(
                                    'SECRET SETUP KEY',
                                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.5),
                                  ),
                                  const SizedBox(height: 8),
                                  SelectableText(
                                    _enrollSecret!,
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      fontFamily: 'monospace',
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 8),
                                  ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                      minimumSize: Size.zero,
                                    ),
                                    onPressed: () {
                                      Clipboard.setData(ClipboardData(text: _enrollSecret!));
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content: Text('Setup key copied to clipboard!'),
                                          duration: Duration(seconds: 1),
                                        ),
                                      );
                                    },
                                    icon: const Icon(Icons.copy_rounded, size: 14),
                                    label: const Text('Copy Key', style: TextStyle(fontSize: 12)),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'Instructions:\n'
                              '1. Open Google Authenticator or Microsoft Authenticator.\n'
                              '2. Select "Enter a setup key".\n'
                              '3. Enter the key above and verify the 6-digit code below.',
                              style: TextStyle(fontSize: 12, height: 1.5),
                            ),
                            const SizedBox(height: 24),
                          ],
                        ],

                        // OTP Input Row
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: List.generate(6, (index) {
                            return SizedBox(
                              width: 42,
                              height: 54,
                              child: TextFormField(
                                controller: _controllers[index],
                                focusNode: _focusNodes[index],
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Theme.of(context).colorScheme.onSurface,
                                ),
                                textAlign: TextAlign.center,
                                keyboardType: TextInputType.number,
                                maxLength: 1,
                                decoration: InputDecoration(
                                  counterText: '',
                                  contentPadding: EdgeInsets.zero,
                                  enabledBorder: OutlineInputBorder(
                                    borderSide: BorderSide(color: Theme.of(context).colorScheme.outline),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderSide: BorderSide(color: Theme.of(context).colorScheme.primary, width: 2),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                                onChanged: (value) {
                                  if (value.isNotEmpty) {
                                    if (index < 5) {
                                      _focusNodes[index + 1].requestFocus();
                                    } else {
                                      _focusNodes[index].unfocus();
                                    }
                                  } else {
                                    if (index > 0) {
                                      _focusNodes[index - 1].requestFocus();
                                    }
                                  }
                                  setState(() {});
                                },
                              ),
                            );
                          }),
                        ),
                        const SizedBox(height: 24),

                        // Error display
                        if (_localError != null) ...[
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.error.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Theme.of(context).colorScheme.error.withValues(alpha: 0.3)),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.error_outline, color: Theme.of(context).colorScheme.error, size: 20),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    _localError!,
                                    style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 13),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),
                        ],

                        // Info / Timer hint
                        if (!isEnrollment)
                          Center(
                            child: Text(
                              'Codes refresh every 30 seconds',
                              style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                              ),
                            ),
                          ),
                        const SizedBox(height: 16),

                        // Verify button
                        SizedBox(
                          height: 54,
                          child: ElevatedButton(
                            onPressed: (authProvider.isLoading || !_isCodeComplete() || (isEnrollment && _enrollSecret == null))
                                ? null
                                : _onVerifyPressed,
                            child: authProvider.isLoading
                                ? SizedBox(
                                    height: 24,
                                    width: 24,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                      valueColor: AlwaysStoppedAnimation<Color>(Theme.of(context).colorScheme.onPrimary),
                                    ),
                                  )
                                : Text(
                                    isEnrollment ? 'Verify & Enable 2FA' : 'Verify',
                                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 32),

                // Sign Out Link
                Center(
                  child: TextButton(
                    onPressed: authProvider.isLoading ? null : _onSignOutPressed,
                    style: TextButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.logout_rounded, size: 16),
                        SizedBox(width: 8),
                        Text(
                          'Sign Out',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
