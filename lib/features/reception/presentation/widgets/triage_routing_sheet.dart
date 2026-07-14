import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/utils/lab_validators.dart';
import '../../domain/routing_priority.dart';

/// Department values — must match patient_queue.department CHECK constraint.
const _departments = [
  'laboratory',
  'imaging',
  'ultrasound',
  'ecg',
];

const _departmentLabels = {
  'laboratory': 'Laboratory',
  'imaging': 'Imaging (X-Ray)',
  'ultrasound': 'Ultrasound',
  'ecg': 'ECG',
};

/// Bottom sheet for triage & department routing.
///
/// Caller provides [patientName], [documentId], [patientId], and [onConfirm].
/// The sheet validates inputs and calls [onConfirm] with the routing data.
class TriageRoutingSheet extends StatefulWidget {
  final String patientName;
  final void Function({
    required String department,
    required String priority,
    String? bloodPressure,
    num? weightKg,
    num? temperatureC,
    String? triageNotes,
  }) onConfirm;
  final bool isLoading;

  const TriageRoutingSheet({
    super.key,
    required this.patientName,
    required this.onConfirm,
    this.isLoading = false,
  });

  @override
  State<TriageRoutingSheet> createState() => _TriageRoutingSheetState();
}

class _TriageRoutingSheetState extends State<TriageRoutingSheet> {
  final _formKey = GlobalKey<FormState>();

  String? _selectedDepartment;
  RoutingPriority _selectedPriority = RoutingPriority.routine;

  final _bpController = TextEditingController();
  final _weightController = TextEditingController();
  final _tempController = TextEditingController();
  final _notesController = TextEditingController();

  @override
  void dispose() {
    _bpController.dispose();
    _weightController.dispose();
    _tempController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please correct the invalid vitals fields'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    if (_selectedDepartment == null) return;

    final weight = _weightController.text.trim().isNotEmpty
        ? num.tryParse(_weightController.text.trim())
        : null;
    final temp = _tempController.text.trim().isNotEmpty
        ? num.tryParse(_tempController.text.trim())
        : null;

    widget.onConfirm(
      department: _selectedDepartment!,
      priority: _selectedPriority.toDbValue(),
      bloodPressure:
          _bpController.text.trim().isNotEmpty ? _bpController.text.trim() : null,
      weightKg: weight,
      temperatureC: temp,
      triageNotes: _notesController.text.trim().isNotEmpty
          ? _notesController.text.trim()
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final confirmEnabled = _selectedDepartment != null && !widget.isLoading;

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
              'Triage & Department Routing',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Route ${widget.patientName} to a department',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 20),

            // Patient name (read-only)
            _SectionLabel(label: 'PATIENT NAME'),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: theme.colorScheme.outline.withValues(alpha: 0.2)),
              ),
              child: Text(
                widget.patientName,
                style: theme.textTheme.bodyMedium,
              ),
            ),
            const SizedBox(height: 16),

            // Department dropdown (required)
            _SectionLabel(label: 'SELECT DEPARTMENT *'),
            const SizedBox(height: 6),
            DropdownButtonFormField<String>(
              value: _selectedDepartment,
              decoration: InputDecoration(
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8)),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                hintText: 'Select department',
              ),
              items: _departments
                  .map((d) => DropdownMenuItem(
                        value: d,
                        child: Text(_departmentLabels[d]!),
                      ))
                  .toList(),
              onChanged: (val) => setState(() => _selectedDepartment = val),
              validator: (val) =>
                  val == null ? 'Please select a department' : null,
            ),
            const SizedBox(height: 16),

            // Vitals row (optional)
            _SectionLabel(label: 'VITALS (optional)'),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    key: const Key('bp_input_field'),
                    controller: _bpController,
                    decoration: InputDecoration(
                      labelText: 'Blood Press.',
                      hintText: '120/80',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8)),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 14),
                    ),
                    keyboardType: TextInputType.text,
                    inputFormatters: [BloodPressureFormatter()],
                    validator: validateBloodPressure,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    key: const Key('weight_input_field'),
                    controller: _weightController,
                    decoration: InputDecoration(
                      labelText: 'Weight (kg)',
                      hintText: '70',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8)),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 14),
                    ),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                      const MaxIntegerDigitsFormatter(3, maxDecimalDigits: 1),
                    ],
                    validator: (val) => validateVitalsValue(
                      val ?? '',
                      maxIntegerDigits: 3,
                      maxDecimalDigits: 1,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    key: const Key('temp_input_field'),
                    controller: _tempController,
                    decoration: InputDecoration(
                      labelText: 'Temp (°C)',
                      hintText: '36.5',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8)),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 14),
                    ),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                      const MaxIntegerDigitsFormatter(3, maxDecimalDigits: 1),
                    ],
                    validator: (val) => validateVitalsValue(
                      val ?? '',
                      maxIntegerDigits: 3,
                      maxDecimalDigits: 1,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Priority dropdown (optional, default routine)
            _SectionLabel(label: 'PRIORITY (optional)'),
            const SizedBox(height: 6),
            DropdownButtonFormField<RoutingPriority>(
              value: _selectedPriority,
              decoration: InputDecoration(
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8)),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              ),
              items: RoutingPriority.values
                  .map((p) => DropdownMenuItem(
                        value: p,
                        child: Text(p.toDisplayLabel()),
                      ))
                  .toList(),
              onChanged: (val) =>
                  setState(() => _selectedPriority = val ?? RoutingPriority.routine),
            ),
            const SizedBox(height: 16),

            // Triage notes (optional)
            _SectionLabel(label: 'TRIAGE NOTES / SYMPTOMS (optional)'),
            const SizedBox(height: 6),
            TextFormField(
              controller: _notesController,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: 'e.g. patient reports headache, fever since yesterday',
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              ),
            ),
            const SizedBox(height: 24),

            // Action buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed:
                        widget.isLoading ? null : () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 48),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: confirmEnabled ? _submit : null,
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(0, 48),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                    child: widget.isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Confirm Routing'),
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
