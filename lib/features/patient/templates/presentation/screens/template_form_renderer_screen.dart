import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../../../auth/presentation/providers/auth_provider.dart';
import '../../../../../core/patient_submission_containment.dart';
import '../../../../../core/utils/manila_time.dart';
import '../../../../auth/presentation/screens/verification_code_screen.dart';
import '../../../../auth/presentation/screens/consent_screen.dart';
import '../../../../reception/presentation/widgets/change_password_modal.dart';
import '../../document_templates.dart';
import '../../template_answers.dart';
import '../providers/templates_provider.dart';

class TemplateFormRendererScreen extends StatefulWidget {
  final String templateId;

  const TemplateFormRendererScreen({super.key, required this.templateId});

  @override
  State<TemplateFormRendererScreen> createState() =>
      _TemplateFormRendererScreenState();
}

class _TemplateFormRendererScreenState
    extends State<TemplateFormRendererScreen> {
  final _formKey = GlobalKey<FormState>();
  late final DocumentTemplate _template;
  final Map<String, dynamic> _formValues = {};
  final _submission = TemplatesProvider();
  bool _isInitError = false;

  @override
  void dispose() {
    _submission.dispose();
    super.dispose();
  }

  void _answerChanged(String key, String value) {
    _formValues[key] = value;
    _submission.answersChanged(Map<String, String>.from(_formValues));
    setState(() {});
  }

  void _submissionChanged() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _submission.addListener(_submissionChanged);
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

  int _calculateAge(DateTime dob, DateTime now) {
    int age = now.year - dob.year;
    if (now.month < dob.month ||
        (now.month == dob.month && now.day < dob.day)) {
      age--;
    }
    return age;
  }

  /// The error for an answer, or null when the answer is acceptable.
  ///
  /// The bounds are the shared clinic rules: a text answer of 200 characters,
  /// a free-text answer of 2000, a date inside the clinic's window, and one of
  /// the allowed choices.
  String? _answerError(TemplateField field, String? value) {
    final answer = value ?? '';
    if (field.required && answer.trim().isEmpty) {
      return '${field.label} is required';
    }
    final problem = templateFieldProblem(field, answer, manilaToday());
    if (problem != null) return '${field.label} $problem.';
    return null;
  }

  /// True when the patient declined this consent question.
  ///
  /// A decline is a valid answer: the form is still submitted and reception
  /// reviews it. It is not the account's data-privacy consent, which is a
  /// separate thing entirely.
  bool _isDeclinedConsent(TemplateField field) {
    final value = _formValues[field.key]?.toString() ?? '';
    return isConsentField(field) && isDeclinedConsentAnswer(value);
  }

  void _selectDate(TemplateField field) async {
    final today = manilaToday();
    final firstDate = parseIsoDate(kTemplateDateMin) ?? DateTime(1900, 1, 1);
    // A date that records something already done (a referral, a consent given)
    // cannot be after today; a forward-looking date may be up to two years
    // ahead.
    final lastDate = field.notFuture ? today : latestTemplateDate(today);

    final pickedDate = await showDatePicker(
      context: context,
      initialDate: today,
      firstDate: firstDate,
      lastDate: lastDate,
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

    if (pickedDate != null && mounted) {
      _answerChanged(field.key, formatIsoDate(pickedDate));
    }
  }

  void _submit() async {
    if (PatientSubmissionContainment.isActive || !_submission.canSubmit) return;
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
      final now = manilaNow();
      final age = _calculateAge(patient.dateOfBirth, now);
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

    final provider = _submission;

    // Answers are stored trimmed, the way the shared rules count them.
    final answers = <String, String>{
      for (final entry in _formValues.entries)
        entry.key: entry.value.toString().trim(),
    };

    final success = await provider.submitTemplate(
      patientId: patient.id,
      uploaderId: user.id,
      templateId: _template.id,
      templateName: _template.name,
      formValues: answers,
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
      setState(() {});
      switch (provider.remediation) {
        case TemplateRemediation.signIn:
          await authProvider.signOut();
          if (mounted) context.go('/login');
        case TemplateRemediation.verifyEmail:
          await Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const VerificationCodeScreen(),
            ),
          );
          if (mounted) provider.resumeAfterAccountFlow();
        case TemplateRemediation.consent:
          await Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const ConsentScreen()),
          );
          if (mounted) provider.resumeAfterAccountFlow();
        case TemplateRemediation.changePassword:
          final changed = await showDialog<bool>(
            context: context,
            builder: (_) => const ChangePasswordModal(),
          );
          if (mounted && changed == true) provider.resumeAfterAccountFlow();
        case TemplateRemediation.none:
          break;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (PatientSubmissionContainment.isActive) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Submit Template'),
          leading: IconButton(
            tooltip: 'Back',
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.go('/patient/templates'),
          ),
        ),
        body: const SafeArea(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(PatientSubmissionContainment.message),
          ),
        ),
      );
    }
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

    return ChangeNotifierProvider.value(
      value: _submission,
      child: Scaffold(
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
                        ListenableBuilder(
                          listenable: _submission,
                          builder: (context, _) => Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (_submission.errorMessage != null)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: Text(
                                    _submission.errorMessage!,
                                    style: TextStyle(
                                      color: theme.colorScheme.error,
                                    ),
                                  ),
                                ),
                              if (_submission.advisoryMessage != null &&
                                  _submission.isLoading)
                                Text(_submission.advisoryMessage!),
                              if (_submission.duplicateDocumentId != null)
                                TextButton(
                                  onPressed: () => context.push(
                                    Uri(
                                      path: '/documents/status',
                                      queryParameters: {
                                        'document_id':
                                            _submission.duplicateDocumentId!,
                                      },
                                    ).toString(),
                                  ),
                                  child: const Text(
                                    'View pending document in my records',
                                  ),
                                ),
                            ],
                          ),
                        ),
                        // Identity Card (Read-Only Header)
                        Card(
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(
                              color: theme.colorScheme.outline.withValues(
                                alpha: 0.15,
                              ),
                            ),
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
                                _buildReadOnlyField(
                                  'Full Name',
                                  patient?.fullName ?? '—',
                                  theme,
                                ),
                                _buildReadOnlyField(
                                  'Date of Birth',
                                  patient != null
                                      ? "${patient.dateOfBirth.year}-${patient.dateOfBirth.month.toString().padLeft(2, '0')}-${patient.dateOfBirth.day.toString().padLeft(2, '0')}"
                                      : '—',
                                  theme,
                                ),
                                _buildReadOnlyField(
                                  'Contact Number',
                                  patient?.contactNumber ?? '—',
                                  theme,
                                ),
                                _buildReadOnlyField(
                                  'Address',
                                  patient?.address ?? '—',
                                  theme,
                                ),
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
                            side: BorderSide(
                              color: theme.colorScheme.outline.withValues(
                                alpha: 0.15,
                              ),
                            ),
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
                                    color: theme.colorScheme.onSurface
                                        .withValues(alpha: 0.6),
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                const Divider(height: 16),
                                ..._template.fields.map(
                                  (field) => _buildFormField(field, theme),
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
              // Bottom Action Button
              ListenableBuilder(
                listenable: _submission,
                builder: (context, child) {
                  final provider = _submission;
                  return Container(
                    padding: const EdgeInsets.all(16.0),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      border: Border(
                        top: BorderSide(
                          color: theme.colorScheme.outline.withValues(
                            alpha: 0.15,
                          ),
                        ),
                      ),
                    ),
                    child: SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton.icon(
                        onPressed: provider.canSubmit ? _submit : null,
                        icon: provider.isLoading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation(
                                    Colors.white,
                                  ),
                                ),
                              )
                            : const Icon(Icons.send_rounded),
                        label: Text(
                          provider.isLoading
                              ? 'Submitting...'
                              : 'Submit to Reception',
                        ),
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
                  style: TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.bold,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (field.type == 'text')
            TextFormField(
              key: ValueKey('field-${field.key}'),
              enabled: !_submission.isLoading,
              forceErrorText: _submission.fieldErrors[field.key],
              style: TextStyle(color: theme.colorScheme.onSurface),
              // The bound is shown as a counter but not enforced while typing:
              // an over-long answer is refused with a readable message rather
              // than silently cut down to an answer nobody wrote.
              maxLength: templateFieldMaxLength(field),
              maxLengthEnforcement: MaxLengthEnforcement.none,
              decoration: InputDecoration(
                hintText: 'Enter ${field.label.toLowerCase()}',
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
              ),
              validator: (value) => _answerError(field, value),
              onChanged: (val) => _answerChanged(field.key, val),
            ),
          if (field.type == 'textarea')
            TextFormField(
              key: ValueKey('field-${field.key}'),
              enabled: !_submission.isLoading,
              forceErrorText: _submission.fieldErrors[field.key],
              style: TextStyle(color: theme.colorScheme.onSurface),
              maxLines: 4,
              maxLength: templateFieldMaxLength(field),
              maxLengthEnforcement: MaxLengthEnforcement.none,
              decoration: InputDecoration(
                hintText:
                    'Provide detailed details for ${field.label.toLowerCase()}',
                contentPadding: const EdgeInsets.all(12),
              ),
              validator: (value) => _answerError(field, value),
              onChanged: (val) => _answerChanged(field.key, val),
            ),
          if (field.type == 'select') ...[
            DropdownButtonFormField<String>(
              key: ValueKey('field-${field.key}'),
              forceErrorText: _submission.fieldErrors[field.key],
              dropdownColor: theme.cardColor,
              decoration: const InputDecoration(
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
              ),
              initialValue: _formValues[field.key]?.isEmpty == true
                  ? null
                  : _formValues[field.key] as String?,
              hint: const Text(
                '-- Select option --',
                style: TextStyle(fontSize: 13),
              ),
              items: field.options?.map((opt) {
                return DropdownMenuItem<String>(
                  value: opt,
                  child: Text(opt, style: const TextStyle(fontSize: 13)),
                );
              }).toList(),
              onChanged: _submission.isLoading
                  ? null
                  : (val) => _answerChanged(field.key, val ?? ''),
              validator: (value) {
                if (field.required && (value == null || value.isEmpty)) {
                  return 'Please select an option';
                }
                if (value != null && value.isNotEmpty) {
                  final problem = templateFieldProblem(field, value, manilaToday());
                  if (problem != null) return '${field.label} $problem.';
                }
                return null;
              },
            ),
            if (_isDeclinedConsent(field))
              Padding(
                padding: const EdgeInsets.only(top: 8.0, left: 12.0),
                child: Text(
                  'Consent declined. This form is still sent to reception for review.',
                  style: TextStyle(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                    fontSize: 12,
                  ),
                ),
              ),
          ],
          if (field.type == 'date')
            InkWell(
              onTap: _submission.isLoading
                  ? null
                  : () => _selectDate(field),
              borderRadius: BorderRadius.circular(8.0),
              child: FormField<String>(
                key: ValueKey('field-${field.key}'),
                forceErrorText: _submission.fieldErrors[field.key],
                validator: (value) {
                  final currentVal = _formValues[field.key] as String?;
                  if (field.required &&
                      (currentVal == null || currentVal.isEmpty)) {
                    return '${field.label} is required';
                  }
                  if (currentVal == null || currentVal.trim().isEmpty) return null;
                  final problem = templateFieldProblem(field, currentVal, manilaToday());
                  if (problem != null) return '${field.label} $problem.';
                  return null;
                },
                builder: (formFieldState) {
                  final currentVal = _formValues[field.key] as String?;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          vertical: 14.0,
                          horizontal: 12.0,
                        ),
                        decoration: BoxDecoration(
                          color: theme.scaffoldBackgroundColor.withValues(
                            alpha: 0.5,
                          ),
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
                                  : theme.colorScheme.primary.withValues(
                                      alpha: 0.7,
                                    ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              (currentVal == null || currentVal.isEmpty)
                                  ? 'Select date'
                                  : currentVal,
                              style: TextStyle(
                                color:
                                    (currentVal == null || currentVal.isEmpty)
                                    ? theme.colorScheme.onSurface.withValues(
                                        alpha: 0.38,
                                      )
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
