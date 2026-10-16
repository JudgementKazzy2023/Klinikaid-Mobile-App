import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../providers/specialist_provider.dart';
import '../widgets/add_patient_form.dart';

class SpecialistDirectoryScreen extends StatefulWidget {
  const SpecialistDirectoryScreen({super.key});

  @override
  State<SpecialistDirectoryScreen> createState() => _SpecialistDirectoryScreenState();
}

class _SpecialistDirectoryScreenState extends State<SpecialistDirectoryScreen> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _showAddPatientDialog(BuildContext context) {
    final provider = Provider.of<SpecialistProvider>(context, listen: false);
    showDialog(
      context: context,
      builder: (dialogContext) => ChangeNotifierProvider<SpecialistProvider>.value(
        value: provider,
        child: const AddPatientForm(),
      ),
    );
  }

  void _confirmArchive(BuildContext context, String patientId, String name) {
    final theme = Theme.of(context);
    final provider = Provider.of<SpecialistProvider>(context, listen: false);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => ListenableBuilder(
        listenable: provider,
        builder: (_, _) => PopScope(
        canPop: !provider.isArchiving,
        child: AlertDialog(
        title: const Text('Archive Private Patient'),
        content: Text(
          'Archive $name? The patient and associated records will be retained but hidden from active views. They cannot be restored through this app.',
        ),
        actions: [
          TextButton(
            onPressed: provider.isArchiving ? null : () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: theme.colorScheme.error,
              foregroundColor: theme.colorScheme.onError,
            ),
            onPressed: provider.isArchiving ? null : () async {
              final messenger = ScaffoldMessenger.of(context);
              final success = await provider.archivePatient(patientId);
              if (dialogContext.mounted) {
                Navigator.of(dialogContext).pop();
                if (success) {
                  messenger.showSnackBar(
                    SnackBar(content: Text(provider.errorMessage ?? 'Patient archived successfully.')),
                  );
                } else {
                  messenger.showSnackBar(
                    SnackBar(content: Text(provider.errorMessage ?? 'Patient could not be archived, refresh and try again.')),
                  );
                }
              }
            },
            child: Text(provider.isArchiving ? 'Archiving...' : 'Archive'),
          ),
        ],
      ))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Private Patient Directory'),
        centerTitle: true,
      ),
      body: Consumer<SpecialistProvider>(
        builder: (context, provider, _) {
          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header Details
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'My Private Patient Roster',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Secure, isolated roster invisible to administrators.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                            ),
                          ),
                        ],
                      ),
                    ),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.person_add_rounded, size: 18),
                      label: const Text('Add Patient'),
                      onPressed: () => _showAddPatientDialog(context),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Search Bar
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search by name or PT- code...',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded),
                            onPressed: () {
                              _searchController.clear();
                              provider.search('');
                              FocusScope.of(context).unfocus();
                            },
                          )
                        : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12.0),
                    ),
                  ),
                  onChanged: (val) {
                    setState(() {});
                    provider.search(val);
                  },
                ),
                const SizedBox(height: 16),

                // Directory List Roster
                Expanded(
                  child: provider.isLoading && provider.directoryPatients.isEmpty
                      ? const Center(child: CircularProgressIndicator())
                      : RefreshIndicator(
                          onRefresh: () => provider.loadDirectory(),
                          child: provider.searchResults.isEmpty
                              ? ListView(
                                  children: [
                                    SizedBox(height: MediaQuery.of(context).size.height * 0.15),
                                    Center(
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            Icons.group_off_rounded,
                                            size: 64,
                                            color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
                                          ),
                                          const SizedBox(height: 16),
                                          Text(
                                            _searchController.text.isEmpty
                                                ? 'Your private patient roster is empty.'
                                                : 'No private patients found matching search.',
                                            style: theme.textTheme.bodyLarge?.copyWith(
                                              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                                            ),
                                            textAlign: TextAlign.center,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                )
                              : ListView.builder(
                                  itemCount: provider.searchResults.length,
                                  itemBuilder: (context, index) {
                                    final patient = provider.searchResults[index];
                                    return Card(
                                      elevation: 1,
                                      margin: const EdgeInsets.symmetric(vertical: 6.0),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12.0),
                                        side: BorderSide(
                                          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
                                        ),
                                      ),
                                      child: Padding(
                                        padding: const EdgeInsets.all(16.0),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.stretch,
                                          children: [
                                            // Patient info header
                                            Row(
                                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                              children: [
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      Text(
                                                        patient.fullName,
                                                        style: theme.textTheme.titleMedium?.copyWith(
                                                          fontWeight: FontWeight.bold,
                                                        ),
                                                      ),
                                                      const SizedBox(height: 4),
                                                      Text(
                                                        'Code: ${patient.patientCode} • ${patient.age}y/o • ${patient.gender.toUpperCase()}',
                                                        style: theme.textTheme.bodySmall?.copyWith(
                                                          color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                                                        ),
                                                      ),
                                                      const SizedBox(height: 4),
                                                      Text(
                                                        'Email: ${patient.emailDisplay}',
                                                        style: theme.textTheme.bodySmall?.copyWith(
                                                          color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                                                        ),
                                                      ),
                                                      const SizedBox(height: 4),
                                                      Text(
                                                        'Contact: ${patient.contactNumberDisplay}',
                                                        style: theme.textTheme.bodySmall?.copyWith(
                                                          color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                IconButton(
                                                  icon: Icon(Icons.archive_outlined, color: theme.colorScheme.error),
                                                  tooltip: 'Archive Patient',
                                                  onPressed: provider.isArchiving ? null : () => _confirmArchive(context, patient.id, patient.fullName),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 12),
                                            const Divider(),
                                            const SizedBox(height: 8),

                                            // Action items
                                            Row(
                                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                              children: [
                                                 Expanded(
                                                   child: TextButton.icon(
                                                     key: Key('enter_record_button_${patient.id}'),
                                                     icon: const Icon(Icons.add_chart_rounded, size: 16),
                                                     label: const Text('Enter Record', style: TextStyle(fontSize: 10)),
                                                     onPressed: () {
                                                       context.push('/specialist/record-entry/${patient.id}');
                                                     },
                                                   ),
                                                 ),
                                                 const SizedBox(width: 8),
                                                 Expanded(
                                                   child: TextButton.icon(
                                                     key: Key('analytics_button_${patient.id}'),
                                                     icon: const Icon(Icons.insights_rounded, size: 16),
                                                     label: const Text('Analytics', style: TextStyle(fontSize: 10)),
                                                     onPressed: () {
                                                       context.push('/specialist/analytics/${patient.id}');
                                                     },
                                                   ),
                                                 ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                        ),
                ),
                const SizedBox(height: 16),

                // SO-C Compliance Banner
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'No AI Diagnostics Inference: This dashboard provides clinical descriptive analytics only. No machine learning diagnostics or automated diagnostic suggestions are applied to this patient data (SO-C Compliance).',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 10,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
