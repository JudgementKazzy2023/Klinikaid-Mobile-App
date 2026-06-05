import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../features/auth/presentation/providers/auth_provider.dart';
import '../../../../core/models/patient.dart';
import '../providers/dashboard_provider.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  
  late final TextEditingController _firstNameController;
  late final TextEditingController _lastNameController;
  late final TextEditingController _contactController;
  late final TextEditingController _addressController;
  
  DateTime? _selectedDateOfBirth;
  Gender _selectedGender = Gender.other;
  bool _isInit = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_isInit) {
      final authProvider = Provider.of<AuthProvider>(context);
      final patient = authProvider.patient;
      
      _firstNameController = TextEditingController(text: patient?.firstName ?? '');
      _lastNameController = TextEditingController(text: patient?.lastName ?? '');
      _contactController = TextEditingController(text: patient?.contactNumber ?? '');
      _addressController = TextEditingController(text: patient?.address ?? '');
      _selectedDateOfBirth = patient?.dateOfBirth;
      _selectedGender = patient?.gender ?? Gender.other;
      _isInit = true;
    }
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _contactController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _selectDateOfBirth() async {
    final initialDate = _selectedDateOfBirth ?? DateTime(2000, 1, 1);
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Color(0xFF2E5BFF),
              onPrimary: Colors.white,
              surface: Color(0xFF0F131D),
              onSurface: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );

    if (pickedDate != null) {
      setState(() {
        _selectedDateOfBirth = pickedDate;
      });
    }
  }

  Future<void> _saveProfile(bool isOffline) async {
    if (isOffline) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cannot update profile details while offline.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (!_formKey.currentState!.validate() || _selectedDateOfBirth == null) {
      if (_selectedDateOfBirth == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please select your Date of Birth.'),
            backgroundColor: Color(0xFFFF3B30),
          ),
        );
      }
      return;
    }

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final success = await authProvider.updatePatientDetails(
      firstName: _firstNameController.text.trim(),
      lastName: _lastNameController.text.trim(),
      dateOfBirth: _selectedDateOfBirth!,
      gender: _selectedGender,
      contactNumber: _contactController.text.trim(),
      address: _addressController.text.trim(),
    );

    if (mounted) {
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profile updated successfully!'),
            backgroundColor: Color(0xFF34C759),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(authProvider.errorMessage ?? 'Update failed.'),
            backgroundColor: const Color(0xFFFF3B30),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final dashboardProvider = Provider.of<DashboardProvider>(context);
    final patient = authProvider.patient;
    final user = authProvider.user;
    final isOffline = dashboardProvider.isOffline;

    if (patient == null) {
      return const Scaffold(
        backgroundColor: Color(0xFF0B0E14),
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFF2E5BFF)),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0B0E14),
      appBar: AppBar(
        title: const Text(
          'My Profile',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontFamily: 'Outfit'),
        ),
        backgroundColor: const Color(0xFF0F131D),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            // User Header Card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF0F131D),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withValues(alpha: 0.05), width: 1),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 30,
                    backgroundColor: const Color(0xFF2E5BFF).withValues(alpha: 0.15),
                    child: const Text(
                      'P',
                      style: TextStyle(color: Color(0xFF2E5BFF), fontSize: 24, fontWeight: FontWeight.bold, fontFamily: 'Outfit'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          patient.fullName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Outfit',
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          user?.email ?? '',
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 13,
                            fontFamily: 'Outfit',
                          ),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'ROLE: PATIENT',
                            style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold, fontFamily: 'Outfit'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 24),

            // Form container
            Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Clinical Demographic Details',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Outfit',
                    ),
                  ),
                  const SizedBox(height: 16),

                  // First Name
                  _buildLabel('First Name'),
                  TextFormField(
                    controller: _firstNameController,
                    keyboardType: TextInputType.name,
                    style: const TextStyle(color: Colors.white, fontFamily: 'Outfit'),
                    decoration: _buildInputDecoration(Icons.person_outline),
                    validator: (val) => val == null || val.trim().isEmpty ? 'First name is required' : null,
                  ),
                  const SizedBox(height: 16),

                  // Last Name
                  _buildLabel('Last Name'),
                  TextFormField(
                    controller: _lastNameController,
                    keyboardType: TextInputType.name,
                    style: const TextStyle(color: Colors.white, fontFamily: 'Outfit'),
                    decoration: _buildInputDecoration(Icons.person_outline),
                    validator: (val) => val == null || val.trim().isEmpty ? 'Last name is required' : null,
                  ),
                  const SizedBox(height: 16),

                  // Contact Number
                  _buildLabel('Contact Number'),
                  TextFormField(
                    controller: _contactController,
                    keyboardType: TextInputType.phone,
                    style: const TextStyle(color: Colors.white, fontFamily: 'Outfit'),
                    decoration: _buildInputDecoration(Icons.phone_outlined),
                    validator: (val) {
                      if (val == null || val.trim().isEmpty) return 'Contact number is required';
                      // basic pattern matching
                      if (!RegExp(r'^[0-9+() -]{7,15}$').hasMatch(val.trim())) {
                        return 'Please enter a valid phone number';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  // Date of Birth & Gender row
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Date of Birth
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildLabel('Date of Birth'),
                            InkWell(
                              onTap: _selectDateOfBirth,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 15),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF0F131D),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Colors.white.withValues(alpha: 0.1), width: 1),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.calendar_today_outlined, color: Colors.white54, size: 18),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        _selectedDateOfBirth != null
                                            ? '${_selectedDateOfBirth!.year}-${_selectedDateOfBirth!.month.toString().padLeft(2, '0')}-${_selectedDateOfBirth!.day.toString().padLeft(2, '0')}'
                                            : 'Select Date',
                                        style: TextStyle(
                                          color: _selectedDateOfBirth != null ? Colors.white : Colors.white54,
                                          fontSize: 14,
                                          fontFamily: 'Outfit',
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),

                      // Gender
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildLabel('Gender'),
                            DropdownButtonFormField<Gender>(
                              initialValue: _selectedGender,
                              dropdownColor: const Color(0xFF0F131D),
                              style: const TextStyle(color: Colors.white, fontSize: 14, fontFamily: 'Outfit'),
                              decoration: _buildInputDecoration(null),
                              items: Gender.values.map((Gender g) {
                                return DropdownMenuItem<Gender>(
                                  value: g,
                                  child: Text(
                                    g.name[0].toUpperCase() + g.name.substring(1),
                                    style: const TextStyle(fontFamily: 'Outfit'),
                                  ),
                                );
                              }).toList(),
                              onChanged: (Gender? val) {
                                if (val != null) {
                                  setState(() {
                                    _selectedGender = val;
                                  });
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Address
                  _buildLabel('Address'),
                  TextFormField(
                    controller: _addressController,
                    keyboardType: TextInputType.streetAddress,
                    maxLines: 2,
                    style: const TextStyle(color: Colors.white, fontFamily: 'Outfit'),
                    decoration: _buildInputDecoration(Icons.location_on_outlined),
                    validator: (val) => val == null || val.trim().isEmpty ? 'Address is required' : null,
                  ),
                  const SizedBox(height: 24),

                  // Save Changes button
                  if (isOffline)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF9900).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFFF9900).withValues(alpha: 0.2)),
                      ),
                      child: Row(
                        children: const [
                          Icon(Icons.warning_amber_rounded, color: Color(0xFFFF9900), size: 18),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Profile updates are disabled while offline.',
                              style: TextStyle(color: Color(0xFFFF9900), fontSize: 12, fontWeight: FontWeight.bold, fontFamily: 'Outfit'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2E5BFF),
                        disabledBackgroundColor: const Color(0xFF2E5BFF).withValues(alpha: 0.3),
                        foregroundColor: Colors.white,
                        disabledForegroundColor: Colors.white38,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: isOffline || authProvider.isLoading ? null : () => _saveProfile(isOffline),
                      child: authProvider.isLoading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                            )
                          : const Text(
                              'Save Changes',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, fontFamily: 'Outfit'),
                            ),
                    ),
                  ),

                  const SizedBox(height: 24),
                  const Divider(color: Colors.white10),
                  const SizedBox(height: 16),

                  // Logout Card
                  InkWell(
                    onTap: authProvider.isLoading ? null : () => authProvider.signOut(),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF3B30).withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFFF3B30).withValues(alpha: 0.2)),
                      ),
                      child: Row(
                        children: const [
                          Icon(Icons.logout_rounded, color: Color(0xFFFF3B30)),
                          SizedBox(width: 12),
                          Text(
                            'Sign Out of Session',
                            style: TextStyle(
                              color: Color(0xFFFF3B30),
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              fontFamily: 'Outfit',
                            ),
                          ),
                          Spacer(),
                          Icon(Icons.arrow_forward_ios_rounded, color: Color(0xFFFF3B30), size: 14),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6.0, left: 4.0),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white70,
          fontSize: 13,
          fontWeight: FontWeight.w500,
          fontFamily: 'Outfit',
        ),
      ),
    );
  }

  InputDecoration _buildInputDecoration(IconData? prefixIcon) {
    return InputDecoration(
      prefixIcon: prefixIcon != null ? Icon(prefixIcon, color: Colors.white30, size: 20) : null,
      filled: true,
      fillColor: const Color(0xFF0F131D),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      errorStyle: const TextStyle(color: Color(0xFFFF3B30), fontSize: 11, fontFamily: 'Outfit'),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1), width: 1),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1), width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF2E5BFF), width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFFF3B30), width: 1),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFFF3B30), width: 1.5),
      ),
    );
  }
}
