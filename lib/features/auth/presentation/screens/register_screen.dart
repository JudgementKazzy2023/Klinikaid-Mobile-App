import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../providers/auth_provider.dart';
import '../../domain/registration_validators.dart';
import '../../../../core/models/patient.dart';
import '../widgets/privacy_policy_modal.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _contactController = TextEditingController();
  final _addressController = TextEditingController();

  DateTime? _dateOfBirth;
  Gender _gender = Gender.male;
  bool _consentChecked = false;
  bool _hasReadPolicy = false;
  String? _dobError;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    _contactController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  void _validateDob() {
    _dobError = RegistrationValidators.validateDob(_dateOfBirth);
  }

  void _selectDate() async {
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: DateTime.now().subtract(const Duration(days: 365 * 18)), // Default to 18 years old
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: Theme.of(context).colorScheme.primary,
              onPrimary: Theme.of(context).colorScheme.onPrimary,
              surface: Theme.of(context).cardColor,
              onSurface: Theme.of(context).colorScheme.onSurface,
            ),
            dialogTheme: DialogThemeData(
              backgroundColor: Theme.of(context).scaffoldBackgroundColor,
            ),
          ),
          child: child!,
        );
      },
    );
    if (pickedDate != null) {
      setState(() {
        _dateOfBirth = pickedDate;
        _validateDob();
      });
    }
  }

  String _getPasswordStrength() {
    final password = _passwordController.text;
    if (password.isEmpty) return '';
    if (password.length < 8) return 'Weak (min 8 characters)';
    
    final hasDigit = RegExp(r'[0-9]').hasMatch(password);
    final hasSpecial = RegExp(r'[^a-zA-Z0-9]').hasMatch(password);
    
    if (hasDigit && hasSpecial) return 'Strong';
    if (hasDigit || hasSpecial) return 'Medium';
    return 'Weak (needs digit and special character)';
  }

  Color _getPasswordStrengthColor() {
    final strength = _getPasswordStrength();
    if (strength.startsWith('Weak')) return Colors.red;
    if (strength == 'Medium') return Colors.orange;
    if (strength == 'Strong') return Colors.green;
    return Colors.transparent;
  }

  void _submit() async {
    setState(() {
      _validateDob();
    });

    if (_formKey.currentState!.validate() && _dobError == null) {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final success = await authProvider.signUp(
        email: _emailController.text.trim(),
        password: _passwordController.text,
        firstName: _firstNameController.text.trim(),
        lastName: _lastNameController.text.trim(),
        dateOfBirth: _dateOfBirth!,
        gender: _gender,
        contactNumber: _contactController.text.trim(),
        address: _addressController.text.trim(),
      );

      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Registration successful! Please check your email for the verification code.'),
            backgroundColor: Theme.of(context).colorScheme.primary,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final size = MediaQuery.of(context).size;

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
                        Icons.medical_services_outlined,
                        size: 36,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Create Account',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Join the KlinikAid Patient Portal',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 36),

                Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Email Address
                          TextFormField(
                            controller: _emailController,
                            style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
                            decoration: InputDecoration(
                              hintText: 'Email Address',
                              prefixIcon: Icon(Icons.email_outlined, color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.7)),
                            ),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Please enter your email';
                              }
                              if (!RegistrationValidators.validateEmail(value)) {
                                return 'Please enter a valid email address';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),

                          // Password
                          TextFormField(
                            controller: _passwordController,
                            obscureText: true,
                            onChanged: (_) => setState(() {}),
                            style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
                            decoration: InputDecoration(
                              hintText: 'Password',
                              errorMaxLines: 3,
                              prefixIcon: Icon(Icons.lock_outline, color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.7)),
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Please enter a password';
                              }
                              if (!RegistrationValidators.validatePassword(value)) {
                                return 'Password must be at least 8 characters and contain at least 1 digit (e.g. 1, 2, 3) and 1 special character (e.g. \$, @, !)';
                              }
                              return null;
                            },
                          ),
                          if (_passwordController.text.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(4),
                                    child: LinearProgressIndicator(
                                      value: _getPasswordStrength() == 'Strong'
                                          ? 1.0
                                          : (_getPasswordStrength() == 'Medium' ? 0.6 : 0.3),
                                      backgroundColor: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
                                      valueColor: AlwaysStoppedAnimation<Color>(_getPasswordStrengthColor()),
                                      minHeight: 6,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  _getPasswordStrength(),
                                  style: TextStyle(
                                    color: _getPasswordStrengthColor(),
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ],
                          const SizedBox(height: 16),

                          // Confirm Password
                          TextFormField(
                            controller: _confirmPasswordController,
                            obscureText: true,
                            style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
                            decoration: InputDecoration(
                              hintText: 'Confirm Password',
                              prefixIcon: Icon(Icons.lock_outline, color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.7)),
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Please confirm your password';
                              }
                              if (value != _passwordController.text) {
                                return 'Passwords do not match';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),

                          // First Name
                          TextFormField(
                            controller: _firstNameController,
                            style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
                            decoration: InputDecoration(
                              hintText: 'First Name',
                              prefixIcon: Icon(Icons.person_outline, color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.7)),
                            ),
                            validator: (value) {
                              if (value == null || !RegistrationValidators.validateFirstName(value)) {
                                return 'First name must be at least 3 characters';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),

                          // Last Name
                          TextFormField(
                            controller: _lastNameController,
                            style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
                            decoration: InputDecoration(
                              hintText: 'Last Name',
                              prefixIcon: Icon(Icons.person_outline, color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.7)),
                            ),
                            validator: (value) {
                              if (value == null || !RegistrationValidators.validateLastName(value)) {
                                return 'Last name is required';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),

                          // Date of Birth selection widget
                          InkWell(
                            onTap: _selectDate,
                            borderRadius: BorderRadius.circular(8.0),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 18.0, horizontal: 12.0),
                              decoration: BoxDecoration(
                                color: Theme.of(context).scaffoldBackgroundColor.withValues(alpha: 0.5),
                                borderRadius: BorderRadius.circular(8.0),
                                border: Border.all(
                                  color: _dobError != null
                                      ? Theme.of(context).colorScheme.error
                                      : Theme.of(context).colorScheme.outline,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.calendar_today_outlined,
                                    color: _dobError != null
                                        ? Theme.of(context).colorScheme.error
                                        : Theme.of(context).colorScheme.primary.withValues(alpha: 0.7),
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    _dateOfBirth == null
                                        ? 'Date of Birth'
                                        : '${_dateOfBirth!.year}-${_dateOfBirth!.month.toString().padLeft(2, '0')}-${_dateOfBirth!.day.toString().padLeft(2, '0')}',
                                    style: TextStyle(
                                      color: _dateOfBirth == null
                                          ? Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.38)
                                          : Theme.of(context).colorScheme.onSurface,
                                      fontSize: 16,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          if (_dobError != null) ...[
                            const SizedBox(height: 6),
                            Padding(
                              padding: const EdgeInsets.only(left: 12.0),
                              child: Text(
                                _dobError!,
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(height: 16),

                          // Gender Dropdown
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12.0),
                            decoration: BoxDecoration(
                              color: Theme.of(context).scaffoldBackgroundColor.withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(8.0),
                              border: Border.all(color: Theme.of(context).colorScheme.outline),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<Gender>(
                                value: _gender,
                                dropdownColor: Theme.of(context).cardColor,
                                icon: Icon(Icons.arrow_drop_down, color: Theme.of(context).colorScheme.primary),
                                style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 16),
                                onChanged: (Gender? val) {
                                  if (val != null) {
                                    setState(() => _gender = val);
                                  }
                                },
                                items: const [
                                  DropdownMenuItem(value: Gender.male, child: Text('Male')),
                                  DropdownMenuItem(value: Gender.female, child: Text('Female')),
                                  DropdownMenuItem(value: Gender.other, child: Text('Prefer not to say')),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Contact Number
                          TextFormField(
                            controller: _contactController,
                            keyboardType: TextInputType.phone,
                            style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
                            decoration: InputDecoration(
                              hintText: 'Contact Number',
                              prefixIcon: Icon(Icons.phone_outlined, color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.7)),
                            ),
                            validator: (value) {
                              if (value == null || !RegistrationValidators.validateContactNumber(value)) {
                                return 'Invalid Philippine format (e.g. 09xx or +639xx)';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 4),
                          Padding(
                            padding: const EdgeInsets.only(left: 12.0),
                            child: Text(
                              'Format: 09xxxxxxxxx or +639xxxxxxxxx',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4),
                                fontSize: 11,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Address
                          TextFormField(
                            controller: _addressController,
                            maxLines: 2,
                            style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
                            decoration: InputDecoration(
                              hintText: 'Complete Address',
                              prefixIcon: Padding(
                                padding: const EdgeInsets.only(bottom: 24.0),
                                child: Icon(Icons.home_outlined, color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.7)),
                              ),
                            ),
                            validator: (value) {
                              if (value == null || !RegistrationValidators.validateAddress(value)) {
                                return 'Please enter your complete address';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),

                          // Consent Checkbox
                          Row(
                            children: [
                              Checkbox(
                                value: _consentChecked,
                                onChanged: _hasReadPolicy
                                    ? (val) => setState(() => _consentChecked = val ?? false)
                                    : null,
                              ),
                              Expanded(
                                child: Wrap(
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    Text(
                                      'I accept the ',
                                      style: TextStyle(
                                        color: Theme.of(context).colorScheme.onSurface,
                                        fontSize: 14,
                                      ),
                                    ),
                                    GestureDetector(
                                      onTap: () async {
                                        await showDialog(
                                          context: context,
                                          builder: (_) => const PrivacyPolicyModal(),
                                        );
                                        setState(() => _hasReadPolicy = true);
                                      },
                                      child: Text(
                                        'RA 10173 data privacy policy',
                                        style: TextStyle(
                                          color: Theme.of(context).colorScheme.primary,
                                          decoration: TextDecoration.underline,
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          if (!_hasReadPolicy) ...[
                            const SizedBox(height: 4),
                            Padding(
                              padding: const EdgeInsets.only(left: 48.0),
                              child: Text(
                                'Please tap the policy link above to review before accepting',
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(height: 16),

                          // Error message if any
                          if (authProvider.errorMessage != null) ...[
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
                                      authProvider.errorMessage!,
                                      style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 13),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 24),
                          ],

                          // Register Button
                          SizedBox(
                            height: 54,
                            child: ElevatedButton(
                              onPressed: (_consentChecked && !authProvider.isLoading) ? _submit : null,
                              child: authProvider.isLoading
                                  ? SizedBox(
                                      height: 24,
                                      width: 24,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.5,
                                        valueColor: AlwaysStoppedAnimation<Color>(Theme.of(context).colorScheme.onPrimary),
                                      ),
                                    )
                                  : const Text(
                                      'Register',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 32),

                // Back to Login Link
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      "Already have an account? ",
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6), fontSize: 14),
                    ),
                    TextButton(
                      onPressed: () {
                        authProvider.clearError();
                        context.go('/login');
                      },
                      style: TextButton.styleFrom(
                        foregroundColor: Theme.of(context).colorScheme.primary,
                      ),
                      child: const Text(
                        'Sign In',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
