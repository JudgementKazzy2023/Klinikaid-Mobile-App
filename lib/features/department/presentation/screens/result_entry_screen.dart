import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/models/patient.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../data/department_repository.dart';
import '../../domain/flag_calculator.dart';
import '../../domain/lab_reference_ranges.dart';
import '../providers/result_entry_provider.dart';

class ResultEntryScreen extends StatefulWidget {
  final String patientId;
  final DepartmentRepository repo;
  final String? departmentOverride;

  ResultEntryScreen({
    super.key,
    required this.patientId,
    DepartmentRepository? repo,
    this.departmentOverride,
  }) : repo = (repo ?? DepartmentRepository())..adminDepartmentOverride = departmentOverride;

  @override
  State<ResultEntryScreen> createState() => _ResultEntryScreenState();
}

class _ResultEntryScreenState extends State<ResultEntryScreen> {
  Patient? _patient;
  bool _isLoadingPatient = true;
  String? _patientError;
  final TextEditingController _testNameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadPatientData();
  }

  @override
  void dispose() {
    _testNameController.dispose();
    super.dispose();
  }

  Future<void> _loadPatientData() async {
    try {
      final patient = await widget.repo.getPatient(widget.patientId);
      
      if (mounted) {
        setState(() {
          _patient = patient;
          _isLoadingPatient = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _patientError = 'Failed to load patient: $e';
          _isLoadingPatient = false;
        });
      }
    }
  }

  Color _getDeptColor(String department) {
    switch (department.toLowerCase()) {
      case 'laboratory':
        return const Color(0xFF047857); // Deep Emerald
      case 'imaging':
        return const Color(0xFF4338CA); // Deep Indigo
      case 'ultrasound':
        return const Color(0xFF0F766E); // Deep Teal
      case 'ecg':
        return const Color(0xFFBE123C); // Deep Rose
      default:
        return const Color(0xFF0284C7); // Sky Blue
    }
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<ResultEntryProvider>(
      create: (_) => ResultEntryProvider(widget.repo),
      child: Consumer2<AuthProvider, ResultEntryProvider>(
        builder: (context, authProvider, provider, child) {
          final department = widget.departmentOverride ?? authProvider.profile?.department?.toJsonValue() ?? '';
          final deptColor = _getDeptColor(department);
          final theme = Theme.of(context);

          return Scaffold(
            backgroundColor: theme.scaffoldBackgroundColor,
            appBar: AppBar(
              title: const Text('Enter Clinical Results'),
              centerTitle: true,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () => context.pop(),
              ),
            ),
            body: SafeArea(
              child: _isLoadingPatient
                  ? const Center(child: CircularProgressIndicator())
                  : _patientError != null
                      ? Center(child: Text(_patientError!))
                      : _buildForm(context, provider, department, deptColor),
            ),
          );
        },
      ),
    );
  }

  Widget _buildForm(
    BuildContext context,
    ResultEntryProvider provider,
    String department,
    Color deptColor,
  ) {
    final theme = Theme.of(context);
    final patient = _patient!;

    // Resolve age
    final age = DateTime.now().difference(patient.dateOfBirth).inDays ~/ 365;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Patient Summary Card
          Card(
            elevation: 0,
            color: deptColor.withValues(alpha: 0.05),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12.0),
              side: BorderSide(color: deptColor.withValues(alpha: 0.15)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: deptColor.withValues(alpha: 0.1),
                    radius: 24,
                    child: Icon(Icons.person_rounded, color: deptColor),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${patient.firstName} ${patient.lastName}',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Gender: ${patient.gender.name.toUpperCase()}  |  Age: $age yrs',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Render Input Form depending on Department Mode
          if (department.toLowerCase() == 'laboratory')
            _buildLabForm(context, provider, patient, deptColor)
          else
            _buildFreeTextForm(context, provider, deptColor),

          const SizedBox(height: 20),

          // Shared Notes field for both modes
          Text(
            'Technician Notes (Optional)',
            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          TextField(
            maxLines: 3,
            onChanged: provider.setNotes,
            decoration: InputDecoration(
              hintText: 'Enter any remarks, notes, or explanations...',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8.0),
              ),
              contentPadding: const EdgeInsets.all(12.0),
            ),
          ),
          const SizedBox(height: 24),

          // Error banner
          if (provider.errorMessage != null) ...[
            Container(
              padding: const EdgeInsets.all(12.0),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8.0),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.error_outline_rounded, color: Colors.red.shade800),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      provider.errorMessage!,
                      style: TextStyle(color: Colors.red.shade800, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Submit Button
          ElevatedButton(
            key: const Key('submit_result_btn'),
            onPressed: provider.isLoading ? null : () => _submitForm(context, provider, department),
            style: ElevatedButton.styleFrom(
              backgroundColor: deptColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: provider.isLoading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Text(
                    'Submit Test Results',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildLabForm(
    BuildContext context,
    ResultEntryProvider provider,
    Patient patient,
    Color deptColor,
  ) {
    final theme = Theme.of(context);
    final parameters = kLabTestGroups[provider.selectedLabGroup] ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Select Lab Panel / Test Group',
          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: provider.selectedLabGroup,
          items: kLabTestGroups.keys.map((group) {
            return DropdownMenuItem<String>(
              value: group,
              child: Text(group),
            );
          }).toList(),
          onChanged: (val) {
            if (val != null) {
              provider.setLabGroup(val);
            }
          },
          decoration: InputDecoration(
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8.0),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
          ),
        ),
        const SizedBox(height: 20),

        Text(
          'Parameter Values',
          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        ...parameters.map((param) {
          final range = kLabReferenceRanges.firstWhere(
            (r) => r.parameter == param,
            orElse: () => const LabReferenceRange(
              parameter: '',
              unit: '',
              maleMin: 0,
              maleMax: 0,
              femaleMin: 0,
              femaleMax: 0,
            ),
          );

          final isFemale = patient.gender == Gender.female;
          final min = isFemale ? range.femaleMin : range.maleMin;
          final max = isFemale ? range.femaleMax : range.maleMax;

          final valStr = provider.parameterValues[param] ?? '';
          final double? parsedVal = double.tryParse(valStr);
          final isFlagged = parsedVal != null && isValueFlagged(parsedVal, range, patient.gender.name);

          return Card(
            margin: const EdgeInsets.only(bottom: 12.0),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8.0),
              side: BorderSide(
                color: isFlagged
                    ? Colors.red.shade300
                    : theme.colorScheme.outlineVariant,
                width: isFlagged ? 1.5 : 1.0,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        param,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      if (isFlagged)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'Flagged',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.red.shade800,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Reference Range (${range.unit}): $min - $max',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    key: Key('param_input_$param'),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [MaxFourIntegerDigitsFormatter()],
                    decoration: InputDecoration(
                      hintText: 'Enter value (${range.unit})',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8.0),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
                    ),
                    onChanged: (val) => provider.setParameterValue(param, val),
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildFreeTextForm(
    BuildContext context,
    ResultEntryProvider provider,
    Color deptColor,
  ) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Test Name',
          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _testNameController,
          decoration: InputDecoration(
            hintText: 'e.g. Chest X-Ray, Obstetric Ultrasound',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8.0),
            ),
            contentPadding: const EdgeInsets.all(12.0),
          ),
        ),
        const SizedBox(height: 16),

        Text(
          'Findings',
          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        TextField(
          key: const Key('findings_input'),
          maxLines: 5,
          onChanged: provider.setFindings,
          decoration: InputDecoration(
            hintText: 'Enter clinical findings in detail...',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8.0),
            ),
            contentPadding: const EdgeInsets.all(12.0),
          ),
        ),
        const SizedBox(height: 16),

        Text(
          'Impression',
          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        TextField(
          key: const Key('impression_input'),
          maxLines: 3,
          onChanged: provider.setImpression,
          decoration: InputDecoration(
            hintText: 'Enter clinical impression / summary...',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8.0),
            ),
            contentPadding: const EdgeInsets.all(12.0),
          ),
        ),
      ],
    );
  }

  Future<void> _submitForm(
    BuildContext context,
    ResultEntryProvider provider,
    String department,
  ) async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final goRouter = GoRouter.of(context);

    final patient = _patient;
    if (department.toLowerCase() == 'laboratory' && patient != null) {
      final outOfRangeMessages = <String>[];
      final parameters = kLabTestGroups[provider.selectedLabGroup] ?? [];
      for (final param in parameters) {
        final valStr = provider.parameterValues[param] ?? '';
        final double? parsedVal = double.tryParse(valStr);
        if (parsedVal != null) {
          final range = kLabReferenceRanges.firstWhere(
            (r) => r.parameter == param,
            orElse: () => const LabReferenceRange(
              parameter: '',
              unit: '',
              maleMin: 0,
              maleMax: 0,
              femaleMin: 0,
              femaleMax: 0,
            ),
          );
          if (range.parameter.isNotEmpty) {
            if (isValueFlagged(parsedVal, range, patient.gender.name)) {
              final isFemale = patient.gender == Gender.female;
              final min = isFemale ? range.femaleMin : range.maleMin;
              final max = isFemale ? range.femaleMax : range.maleMax;
              final unitStr = range.unit.isEmpty ? '' : ' ${range.unit}';
              outOfRangeMessages.add(
                '$param: ${formatDouble(parsedVal)}$unitStr (normal ${formatDouble(min)}–${formatDouble(max)}). Please confirm this value was entered correctly.',
              );
            }
          }
        }
      }

      if (outOfRangeMessages.isNotEmpty) {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Confirm flagged value(s)'),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: outOfRangeMessages.map((msg) => Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: Text(msg),
                )).toList(),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Review'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Confirm & Save'),
              ),
            ],
          ),
        );

        if (confirmed != true) {
          return;
        }
      }
    }

    bool success = false;
    if (department.toLowerCase() == 'laboratory') {
      success = await provider.submitLabResults(
        patientId: widget.patientId,
        gender: _patient?.gender.name,
      );
    } else {
      success = await provider.submitFreeTextResult(
        patientId: widget.patientId,
        testName: _testNameController.text,
      );
    }

    if (success) {
      scaffoldMessenger.showSnackBar(
        const SnackBar(
          content: Text('Test results submitted successfully.'),
          backgroundColor: Color(0xFF047857),
        ),
      );
      goRouter.pop();
    }
  }
}

String formatDouble(double val) {
  if (val % 1 == 0) {
    return val.toInt().toString();
  }
  return val.toString();
}

class MaxFourIntegerDigitsFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty) {
      return newValue;
    }
    final regExp = RegExp(r'^\d{0,4}(\.\d*)?$');
    if (regExp.hasMatch(newValue.text)) {
      return newValue;
    }
    return oldValue;
  }
}
