import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../../../../core/models/patient.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _contactController = TextEditingController();
  final _addressController = TextEditingController();
  
  DateTime? _dateOfBirth;
  Gender _gender = Gender.male;

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _contactController.dispose();
    _addressController.dispose();
    super.dispose();
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
      setState(() => _dateOfBirth = pickedDate);
    }
  }

  void _submit() async {
    if (_formKey.currentState!.validate()) {
      if (_dateOfBirth == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Please select your date of birth.'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
        return;
      }

      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      await authProvider.submitOnboarding(
        firstName: _firstNameController.text.trim(),
        lastName: _lastNameController.text.trim(),
        dateOfBirth: _dateOfBirth!,
        gender: _gender,
        contactNumber: _contactController.text.trim(),
        address: _addressController.text.trim(),
      );
      // Onboarding state triggers redirection automatically in GoRouter
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Text(
                'Complete Profile',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Please set up your patient record to access clinical results.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 32),

              // Form inside Card
              Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // First Name
                        TextFormField(
                          controller: _firstNameController,
                          style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
                          decoration: InputDecoration(
                            hintText: 'First Name',
                            prefixIcon: Icon(Icons.person_outline, color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.7)),
                          ),
                          validator: (value) => value == null || value.trim().isEmpty ? 'Please enter your first name' : null,
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
                          validator: (value) => value == null || value.trim().isEmpty ? 'Please enter your last name' : null,
                        ),
                        const SizedBox(height: 16),

                        // Date of Birth selection
                        InkWell(
                          onTap: _selectDate,
                          borderRadius: BorderRadius.circular(12.0),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 18.0, horizontal: 12.0),
                            decoration: BoxDecoration(
                              color: Theme.of(context).scaffoldBackgroundColor.withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(8.0),
                              border: Border.all(color: Theme.of(context).colorScheme.outline),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.calendar_today_outlined, color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.7)),
                                const SizedBox(width: 12),
                                Text(
                                  _dateOfBirth == null
                                      ? 'Date of Birth'
                                      : '${_dateOfBirth!.year}-${_dateOfBirth!.month.toString().padLeft(2, '0')}-${_dateOfBirth!.day.toString().padLeft(2, '0')}',
                                  style: TextStyle(
                                    color: _dateOfBirth == null ? Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.38) : Theme.of(context).colorScheme.onSurface,
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Gender selection Dropdown
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
                                DropdownMenuItem(value: Gender.other, child: Text('Other')),
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
                            if (value == null || value.trim().isEmpty) {
                              return 'Please enter your contact number';
                            }
                            if (value.trim().length < 7) {
                              return 'Please enter a valid contact number';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),

                        // Home Address
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
                          validator: (value) => value == null || value.trim().isEmpty ? 'Please enter your address' : null,
                        ),
                        const SizedBox(height: 28),

                        // Error banner if any
                        if (authProvider.errorMessage != null) ...[
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.error.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Theme.of(context).colorScheme.error.withValues(alpha: 0.3)),
                            ),
                            child: Text(
                              authProvider.errorMessage!,
                              style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 13),
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],

                        // Complete Button
                        SizedBox(
                          height: 54,
                          child: ElevatedButton(
                            onPressed: authProvider.isLoading ? null : _submit,
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
                                    'Complete Onboarding',
                                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Log out Option
              TextButton(
                onPressed: () => authProvider.signOut(),
                style: TextButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                ),
                child: const Text('Cancel & Log Out'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
