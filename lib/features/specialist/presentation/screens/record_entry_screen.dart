import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/models/specialist_patient.dart';
import '../../../department/domain/lab_reference_ranges.dart';
import '../../../department/domain/flag_calculator.dart';
import '../providers/specialist_provider.dart';
import '../providers/record_entry_provider.dart';

class RecordEntryScreen extends StatefulWidget {
  final String patientId;

  const RecordEntryScreen({super.key, required this.patientId});

  @override
  State<RecordEntryScreen> createState() => _RecordEntryScreenState();
}

class _RecordEntryScreenState extends State<RecordEntryScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<RecordEntryProvider>(context, listen: false).init(widget.patientId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final recordProvider = Provider.of<RecordEntryProvider>(context);
    final specialistProvider = Provider.of<SpecialistProvider>(context, listen: false);

    final patient = recordProvider.patient;
    if (patient == null) {
      return Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        appBar: AppBar(
          title: const Text('Enter Private Record'),
          centerTitle: true,
        ),
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    final isFemale = patient.gender.toLowerCase() == 'female';

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Enter Private Record'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header & Privacy Isolation Badge
              Card(
                elevation: 0,
                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              'Patient: ${patient.fullName}',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.teal.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: Colors.teal.withValues(alpha: 0.5)),
                            ),
                            child: const Text(
                              'End-to-End Isolated',
                              style: TextStyle(
                                color: Colors.teal,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Log clinical data for ${patient.fullName}. Records are completely isolated to this specialist session.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Error Banner
              if (recordProvider.errorMessage != null) ...[
                Container(
                  key: const Key('validation_error_banner'),
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: theme.colorScheme.error),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline_rounded, color: theme.colorScheme.error),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          recordProvider.errorMessage!,
                          style: TextStyle(
                            color: theme.colorScheme.onErrorContainer,
                            fontWeight: FontWeight.w500,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
              ],

              // Diagnostic Group Dropdown Selector
              DropdownButtonFormField<String>(
                key: const Key('diagnostic_group_dropdown'),
                value: recordProvider.selectedTestType,
                hint: const Text('Select Diagnostic Group'),
                decoration: InputDecoration(
                  labelText: 'Diagnostic Group',
                  prefixIcon: const Icon(Icons.category_outlined),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                items: kLabTestGroups.keys.map((group) {
                  return DropdownMenuItem<String>(
                    value: group,
                    child: Text(group),
                  );
                }).toList(),
                onChanged: recordProvider.isLoading
                    ? null
                    : (val) {
                        if (val != null) {
                          recordProvider.selectTestType(val);
                        }
                      },
              ),
              const SizedBox(height: 24),

              // Parameter inputs rendered dynamically
              if (recordProvider.selectedTestType != null) ...[
                Text(
                  'Record Parameter Values',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                ...kLabTestGroups[recordProvider.selectedTestType!]!.map((paramName) {
                  final controller = recordProvider.controllers[paramName];
                  if (controller == null) return const SizedBox.shrink();

                  // Reference values
                  final range = kLabReferenceRanges.firstWhere((r) => r.parameter == paramName);
                  final refMin = isFemale ? range.femaleMin : range.maleMin;
                  final refMax = isFemale ? range.femaleMax : range.maleMax;

                  // Live evaluation
                  return ListenableBuilder(
                    listenable: controller,
                    builder: (context, _) {
                      final valText = controller.text.trim();
                      final double? parsedVal = double.tryParse(valText);
                      final bool isFlagged = parsedVal != null &&
                          isValueFlagged(parsedVal, range, patient.gender);

                      return Card(
                        elevation: 0,
                        margin: const EdgeInsets.symmetric(vertical: 6.0),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: isFlagged
                                ? theme.colorScheme.error.withValues(alpha: 0.5)
                                : theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        paramName,
                                        style: const TextStyle(fontWeight: FontWeight.bold),
                                      ),
                                      if (isFlagged) ...[
                                        const SizedBox(width: 8),
                                        Container(
                                          key: const Key('flagged_badge'),
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFEF4444), // Vibrant Red
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: const Text(
                                            'Flagged',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 9,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                  Text(
                                    range.unit,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              TextField(
                                key: Key('param_input_${paramName}'),
                                controller: controller,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                enabled: !recordProvider.isLoading,
                                decoration: const InputDecoration(
                                  hintText: 'Enter value',
                                  isDense: true,
                                  contentPadding: EdgeInsets.symmetric(vertical: 12, horizontal: 14),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                isFemale
                                    ? 'Reference range: $refMin - $refMax ${range.unit} (matches female)'
                                    : 'Reference range: $refMin - $refMax ${range.unit} (matches male)',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontSize: 11,
                                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                }),
                const SizedBox(height: 20),

                // Clinical Notes Text Field
                TextField(
                  key: const Key('clinical_notes_input'),
                  controller: recordProvider.notesController,
                  enabled: !recordProvider.isLoading,
                  maxLines: 4,
                  decoration: InputDecoration(
                    labelText: 'Clinical Notes (Optional)',
                    hintText: 'Add clinical notes shared across all rows',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 28),

                // Action Buttons
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        key: const Key('cancel_record_button'),
                        onPressed: recordProvider.isLoading
                            ? null
                            : () => Navigator.of(context).pop(),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: ElevatedButton(
                        key: const Key('save_record_button'),
                        onPressed: recordProvider.isLoading
                            ? null
                            : () async {
                                final success = await recordProvider.submit(
                                  context,
                                  specialistProvider,
                                );
                                if (success && context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Record saved successfully.'),
                                      backgroundColor: Colors.green,
                                    ),
                                  );
                                  Navigator.of(context).pop();
                                }
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: theme.colorScheme.primary,
                          foregroundColor: theme.colorScheme.onPrimary,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: recordProvider.isLoading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Save Record', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ] else ...[
                const SizedBox(height: 40),
                Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.add_chart_rounded,
                        size: 64,
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Select a diagnostic group to begin log.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
