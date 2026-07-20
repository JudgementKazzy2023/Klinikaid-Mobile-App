import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/specialist_provider.dart';

class AddPatientForm extends StatefulWidget {
  const AddPatientForm({super.key});

  @override
  State<AddPatientForm> createState() => AddPatientFormState();
}

class AddPatientFormState extends State<AddPatientForm> {
  static const int _minimumPatientAge = 18;

  final _formKey = GlobalKey<FormState>();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _contactController = TextEditingController();
  final _emailController = TextEditingController();
  final _addressController = TextEditingController();

  DateTime? _selectedDob;
  DateTime? get selectedDob => _selectedDob;
  set selectedDob(DateTime? val) {
    if (mounted) {
      setState(() {
        _selectedDob = val;
      });
    } else {
      _selectedDob = val;
    }
  }
  String _gender = 'male';
  bool _isSubmitting = false;

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _contactController.dispose();
    _emailController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _selectDob(BuildContext context) async {
    final now = DateTime.now();
    final initialDate =
        selectedDob ?? now.subtract(const Duration(days: 365 * _minimumPatientAge));
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(now.year - 120),
      lastDate: now,
    );

    if (picked != null) {
      selectedDob = picked;
    }
  }

  void _submit() async {
    if (_isSubmitting) return;
    setState(() {
      _isSubmitting = true;
    });

    try {
      if (!_formKey.currentState!.validate()) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please correct the validation errors in the form.')),
        );
        setState(() {
          _isSubmitting = false;
        });
        return;
      }
      if (selectedDob == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select a date of birth.')),
        );
        setState(() {
          _isSubmitting = false;
        });
        return;
      }

      // Explicitly check the age restriction
      final now = DateTime.now();
      int age = now.year - selectedDob!.year;
      if (now.month < selectedDob!.month ||
          (now.month == selectedDob!.month && now.day < selectedDob!.day)) {
        age--;
      }
      if (age < _minimumPatientAge) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Patient must be 18 years or older.')),
        );
        setState(() {
          _isSubmitting = false;
        });
        return;
      }

      final provider = Provider.of<SpecialistProvider>(context, listen: false);
      final success = await provider.addPatient(
        firstName: _firstNameController.text.trim(),
        lastName: _lastNameController.text.trim(),
        dob: selectedDob!,
        gender: _gender,
        contactNumber: _contactController.text.trim(),
        email: _emailController.text.trim(),
        address: _addressController.text.trim(),
      );

      if (success && mounted) {
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Private patient added successfully.')),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(provider.errorMessage ?? 'Failed to add patient.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('An unexpected error occurred: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 500),
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        'Add Private Patient',
                        style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const Divider(),
                const SizedBox(height: 12),

                // First Name
                TextFormField(
                  key: const Key('firstNameField'),
                  controller: _firstNameController,
                  decoration: const InputDecoration(
                    labelText: 'First Name*',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'First name is required';
                    }
                    if (value.trim().length < 3) {
                      return 'Minimum 3 characters';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Last Name
                TextFormField(
                  key: const Key('lastNameField'),
                  controller: _lastNameController,
                  decoration: const InputDecoration(
                    labelText: 'Last Name*',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Last name is required';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // DOB Picker
                InkWell(
                  onTap: () => _selectDob(context),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                    decoration: BoxDecoration(
                      border: Border.all(color: theme.colorScheme.outline),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          selectedDob == null
                              ? 'Select Date of Birth*'
                              : 'DOB: ${selectedDob!.toLocal().toString().substring(0, 10)}',
                          style: TextStyle(
                            fontSize: 16,
                            color: selectedDob == null
                                ? theme.colorScheme.onSurfaceVariant
                                : theme.colorScheme.onSurface,
                          ),
                        ),
                        Icon(Icons.calendar_month_rounded, color: theme.colorScheme.primary),
                      ],
                    ),
                  ),
                ),
                if (selectedDob != null) ...[
                  const SizedBox(height: 4),
                  Builder(
                    builder: (context) {
                      final now = DateTime.now();
                      int age = now.year - selectedDob!.year;
                      if (now.month < selectedDob!.month ||
                          (now.month == selectedDob!.month && now.day < selectedDob!.day)) {
                        age--;
                      }
                      if (age < _minimumPatientAge) {
                        return Padding(
                          padding: const EdgeInsets.only(left: 12.0),
                          child: Text(
                            'Patient must be 18 years or older.',
                            style: TextStyle(color: theme.colorScheme.error, fontSize: 12),
                          ),
                        );
                      }
                      return const SizedBox.shrink();
                    },
                  ),
                ],
                const SizedBox(height: 16),

                // Gender Dropdown
                DropdownButtonFormField<String>(
                  initialValue: _gender,
                  decoration: const InputDecoration(
                    labelText: 'Gender*',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'male', child: Text('Male')),
                    DropdownMenuItem(value: 'female', child: Text('Female')),
                    DropdownMenuItem(value: 'other', child: Text('Other')),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      setState(() {
                        _gender = val;
                      });
                    }
                  },
                ),
                const SizedBox(height: 16),

                // Contact Number
                TextFormField(
                  key: const Key('contactNumberField'),
                  controller: _contactController,
                  decoration: const InputDecoration(
                    labelText: 'Contact Number',
                    border: OutlineInputBorder(),
                    hintText: '09xxxxxxxxx or +639xxxxxxxxx',
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) return null;
                    final reg = RegExp(r'^(09|\+639)\d{9}$');
                    if (!reg.hasMatch(value.trim())) {
                      return 'Invalid Philippine mobile format';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Email
                TextFormField(
                  key: const Key('emailField'),
                  controller: _emailController,
                  decoration: const InputDecoration(
                    labelText: 'Email Address',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) return null;
                    final reg = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
                    if (!reg.hasMatch(value.trim())) {
                      return 'Invalid email format';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Address
                TextFormField(
                  key: const Key('addressField'),
                  controller: _addressController,
                  decoration: const InputDecoration(
                    labelText: 'Address',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 24),

                // Action Buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      key: const Key('savePatientButton'),
                      onPressed: _isSubmitting ? null : _submit,
                      child: _isSubmitting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Save Patient'),
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
