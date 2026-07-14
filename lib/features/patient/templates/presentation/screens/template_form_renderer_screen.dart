import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../../../auth/presentation/providers/auth_provider.dart';
import '../../document_templates.dart';
import '../providers/templates_provider.dart';

class TemplateFormRendererScreen extends StatefulWidget {
  final String templateId;

  const TemplateFormRendererScreen({
    super.key,
    required this.templateId,
  });

  @override
  State<TemplateFormRendererScreen> createState() => _TemplateFormRendererScreenState();
}

class _TemplateFormRendererScreenState extends State<TemplateFormRendererScreen> {
  final _formKey = GlobalKey<FormState>();
  late final DocumentTemplate _template;
  final Map<String, dynamic> _formValues = {};
  bool _isInitError = false;

  @override
  void initState() {
    super.initState();
    final matching = clinicTemplates.where((t) => t.id == widget.templateId);
    if (matching.isEmpty) {
      _isInitError = true;
    } else {
      _template = matching.first;
      for (final field in _template.fields) {
        if (field.type == 'select') {
          _formValues[field.key] = '';
        } else {
          _formValues[field.key] = '';
        }
      }
    }
  }

  DateTime _getManilaNow() {
    return DateTime.now().toUtc().add(const Duration(hours: 8));
  }

  int _calculateAge(DateTime dob, DateTime now) {
    int age = now.year - dob.year;
    if (now.month < dob.month || (now.month == dob.month && now.day < dob.day)) {
      age--;
    }
    return age;
  }

  void _selectDate(String fieldKey, String label) async {
    final now = _getManilaNow();
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(1900),
      lastDate: DateTime(2100),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: Theme.of(context).colorScheme.primary,
              onPrimary: Theme.of(context).colorScheme.onPrimary,
              surface: Theme.of(context).cardColor,
              onSurface: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          child: child!,
        );
      },
    );

    if (pickedDate != null) {
      setState(() {
        // Format YYYY-MM-DD
        _formValues[fieldKey] = "${pickedDate.year}-${pickedDate.month.toString().padLeft(2, '0')}-${pickedDate.day.toString().padLeft(2, '0')}";
      });
    }
  }

  void _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final patient = authProvider.patient;
    final user = authProvider.user;

    if (patient == null || user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Session error. Please log in again.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Age validation for patient-intake only
    if (_template.id == 'patient-intake') {
      final manilaNow = _getManilaNow();
      final age = _calculateAge(patient.dateOfBirth, manilaNow);
      if (age < 18) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Submission restricted: age must be 18 or above.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
    }

    final provider = Provider.of<TemplatesProvider>(context, listen: false);
    
    // Format DOB to YYYY-MM-DD string
    final dobStr = "${patient.dateOfBirth.year}-${patient.dateOfBirth.month.toString().padLeft(2, '0')}-${patient.dateOfBirth.day.toString().padLeft(2, '0')}";

    final success = await provider.submitTemplate(
      patientId: patient.id,
      uploaderId: user.id,
      templateId: _template.id,
      templateName: _template.name,
      formValues: Map<String, String>.from(_formValues.map((k, v) => MapEntry(k, v.toString()))),
      patientName: patient.fullName,
      dob: dobStr,
      contactNumber: patient.contactNumber,
      address: patient.address,
    );

    if (!mounted) return;

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Structured form submitted successfully!'),
          backgroundColor: Colors.green,
        ),
      );
      context.go('/patient');
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(provider.errorMessage ?? 'Submission failed'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isInitError) {
      return Scaffold(
        body: Center(
          child: Text(
            'Template not found',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      );
    }

    final theme = Theme.of(context);
    final authProvider = Provider.of<AuthProvider>(context);
    final patient = authProvider.patient;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(_template.name),
        elevation: 0,
        backgroundColor: theme.scaffoldBackgroundColor,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/patient/templates'),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16.0),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Identity Card (Read-Only Header)
                      Card(
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: theme.colorScheme.outline.withValues(alpha: 0.15)),
                        ),
                        color: theme.cardColor.withValues(alpha: 0.5),
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'PATIENT IDENTITY (AUTO-FILLED)',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: theme.colorScheme.primary,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              const Divider(height: 16),
                              _buildReadOnlyField('Full Name', patient?.fullName ?? '—', theme),
                              _buildReadOnlyField('Date of Birth', patient != null ? "${patient.dateOfBirth.year}-${patient.dateOfBirth.month.toString().padLeft(2, '0')}-${patient.dateOfBirth.day.toString().padLeft(2, '0')}" : '—', theme),
                              _buildReadOnlyField('Contact Number', patient?.contactNumber ?? '—', theme),
                              _buildReadOnlyField('Address', patient?.address ?? '—', theme),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Structured Input Form
                      Card(
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: theme.colorScheme.outline.withValues(alpha: 0.15)),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'STRUCTURED INPUT FIELDS',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                                  letterSpacing: 0.5,
                                ),
                              ),
                              const Divider(height: 16),
                              ..._template.fields.map((field) => _buildFormField(field, theme)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // Bottom Action Button
            Consumer<TemplatesProvider>(
              builder: (context, provider, child) {
                return Container(
                  padding: const EdgeInsets.all(16.0),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    border: Border(
                      top: BorderSide(color: theme.colorScheme.outline.withValues(alpha: 0.15)),
                    ),
                  ),
                  child: SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      onPressed: provider.isLoading ? null : _submit,
                      icon: provider.isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(Colors.white)),
                            )
                          : const Icon(Icons.send_rounded),
                      label: Text(provider.isLoading ? 'Submitting...' : 'Submit to Reception'),
                      style: ElevatedButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReadOnlyField(String label, String value, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFormField(TemplateField field, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                field.label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (field.required)
                const Text(
                  ' *',
                  style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (field.type == 'text')
            TextFormField(
              key: ValueKey('field-${field.key}'),
              style: TextStyle(color: theme.colorScheme.onSurface),
              decoration: InputDecoration(
                hintText: 'Enter ${field.label.toLowerCase()}',
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              validator: (value) {
                if (field.required && (value == null || value.trim().isEmpty)) {
                  return '${field.label} is required';
                }
                return null;
              },
              onChanged: (val) => _formValues[field.key] = val,
            ),
          if (field.type == 'textarea')
            TextFormField(
              key: ValueKey('field-${field.key}'),
              style: TextStyle(color: theme.colorScheme.onSurface),
              maxLines: 4,
              decoration: InputDecoration(
                hintText: 'Provide detailed details for ${field.label.toLowerCase()}',
                contentPadding: const EdgeInsets.all(12),
              ),
              validator: (value) {
                if (field.required && (value == null || value.trim().isEmpty)) {
                  return '${field.label} is required';
                }
                return null;
              },
              onChanged: (val) => _formValues[field.key] = val,
            ),
          if (field.type == 'select')
            DropdownButtonFormField<String>(
              key: ValueKey('field-${field.key}'),
              dropdownColor: theme.cardColor,
              decoration: const InputDecoration(
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              ),
              value: _formValues[field.key]?.isEmpty == true ? null : _formValues[field.key] as String?,
              hint: const Text('-- Select option --', style: TextStyle(fontSize: 13)),
              items: field.options?.map((opt) {
                return DropdownMenuItem<String>(
                  value: opt,
                  child: Text(opt, style: const TextStyle(fontSize: 13)),
                );
              }).toList(),
              onChanged: (val) {
                setState(() {
                  _formValues[field.key] = val ?? '';
                });
              },
              validator: (value) {
                if (field.required && (value == null || value.isEmpty)) {
                  return 'Please select an option';
                }
                return null;
              },
            ),
          if (field.type == 'date')
            InkWell(
              onTap: () => _selectDate(field.key, field.label),
              borderRadius: BorderRadius.circular(8.0),
              child: FormField<String>(
                key: ValueKey('field-${field.key}'),
                validator: (value) {
                  final currentVal = _formValues[field.key] as String?;
                  if (field.required && (currentVal == null || currentVal.isEmpty)) {
                    return '${field.label} is required';
                  }
                  return null;
                },
                builder: (formFieldState) {
                  final currentVal = _formValues[field.key] as String?;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 14.0, horizontal: 12.0),
                        decoration: BoxDecoration(
                          color: theme.scaffoldBackgroundColor.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(8.0),
                          border: Border.all(
                            color: formFieldState.hasError
                                ? theme.colorScheme.error
                                : theme.colorScheme.outline,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.calendar_today_outlined,
                              color: formFieldState.hasError
                                  ? theme.colorScheme.error
                                  : theme.colorScheme.primary.withValues(alpha: 0.7),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              (currentVal == null || currentVal.isEmpty)
                                  ? 'Select date'
                                  : currentVal,
                              style: TextStyle(
                                color: (currentVal == null || currentVal.isEmpty)
                                    ? theme.colorScheme.onSurface.withValues(alpha: 0.38)
                                    : theme.colorScheme.onSurface,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (formFieldState.hasError) ...[
                        const SizedBox(height: 6),
                        Padding(
                          padding: const EdgeInsets.only(left: 12.0),
                          child: Text(
                            formFieldState.errorText!,
                            style: TextStyle(
                              color: theme.colorScheme.error,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ],
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
