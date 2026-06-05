import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../features/auth/presentation/providers/auth_provider.dart';
import '../../../../core/models/department_record.dart';
import '../providers/records_provider.dart';

class RecordsScreen extends StatefulWidget {
  const RecordsScreen({super.key});

  @override
  State<RecordsScreen> createState() => _RecordsScreenState();
}

class _RecordsScreenState extends State<RecordsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadRecords();
    });
  }

  void _loadRecords() {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (authProvider.patient != null) {
      context.read<RecordsProvider>().fetchRecords(authProvider.patient!.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0E14),
      appBar: AppBar(
        title: const Text(
          'My Medical Records',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontFamily: 'Outfit',
          ),
        ),
        backgroundColor: const Color(0xFF0F131D),
        elevation: 0,
      ),
      body: Consumer<RecordsProvider>(
        builder: (context, provider, child) {
          if (provider.isLoading) {
            return const Center(
              child: CircularProgressIndicator(color: Color(0xFF2E5BFF)),
            );
          }

          if (provider.errorMessage != null && provider.records.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 48),
                    const SizedBox(height: 16),
                    Text(
                      provider.errorMessage!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white70, fontFamily: 'Outfit'),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2E5BFF),
                      ),
                      onPressed: _loadRecords,
                      child: const Text('Try Again', style: TextStyle(color: Colors.white)),
                    ),
                  ],
                ),
              ),
            );
          }

          if (provider.records.isEmpty) {
            return RefreshIndicator(
              onRefresh: () async => _loadRecords(),
              color: const Color(0xFF2E5BFF),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  SizedBox(height: MediaQuery.of(context).size.height * 0.25),
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              color: const Color(0xFF2E5BFF).withAlpha(20),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.assignment_turned_in_outlined,
                              size: 64,
                              color: Color(0xFF2E5BFF),
                            ),
                          ),
                          const SizedBox(height: 24),
                          const Text(
                            'No Records Found',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'Outfit',
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Your completed lab tests and diagnostic reports will appear here.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white54,
                              fontSize: 14,
                              fontFamily: 'Outfit',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () async => _loadRecords(),
            color: const Color(0xFF2E5BFF),
            child: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              itemCount: provider.records.length,
              itemBuilder: (context, index) {
                final record = provider.records[index];
                return _buildRecordCard(record);
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildRecordCard(DepartmentRecord record) {
    return Card(
      color: const Color(0xFF0F131D),
      surfaceTintColor: Colors.transparent,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.white.withAlpha(5), width: 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _showRecordDetails(record),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2E5BFF).withAlpha(20),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      record.department.name.toUpperCase(),
                      style: const TextStyle(
                        color: Color(0xFF2E5BFF),
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Outfit',
                      ),
                    ),
                  ),
                  _buildStatusBadge(record.referenceRangeStatus),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                record.testType,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Outfit',
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Date: ${record.createdAt.toLocal().toString().substring(0, 16)}',
                style: const TextStyle(
                  color: Colors.white38,
                  fontSize: 13,
                  fontFamily: 'Outfit',
                ),
              ),
              const SizedBox(height: 8),
              const Row(
                children: [
                  Text(
                    'View Details',
                    style: TextStyle(
                      color: Color(0xFF2E5BFF),
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Outfit',
                    ),
                  ),
                  SizedBox(width: 4),
                  Icon(Icons.arrow_forward_rounded, color: Color(0xFF2E5BFF), size: 14),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBadge(ReferenceRangeStatus status) {
    Color color;
    switch (status) {
      case ReferenceRangeStatus.normal:
        color = const Color(0xFF30D158);
        break;
      case ReferenceRangeStatus.criticalHigh:
      case ReferenceRangeStatus.criticalLow:
        color = const Color(0xFFFF453A);
        break;
      case ReferenceRangeStatus.inconclusive:
        color = const Color(0xFFFF9F0A);
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withAlpha(30), width: 1),
      ),
      child: Text(
        status.name.toUpperCase().replaceAll('_', ' '),
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.bold,
          fontFamily: 'Outfit',
        ),
      ),
    );
  }

  void _showRecordDetails(DepartmentRecord record) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0F131D),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      isScrollControlled: true,
      builder: (context) {
        return DraggableScrollableSheet(
          expand: false,
          maxChildSize: 0.85,
          initialChildSize: 0.6,
          builder: (context, scrollController) {
            return SingleChildScrollView(
              controller: scrollController,
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        record.testType,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'Outfit',
                        ),
                      ),
                      _buildStatusBadge(record.referenceRangeStatus),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Department: ${record.department.name.toUpperCase()}',
                    style: const TextStyle(color: Colors.white54, fontSize: 14, fontFamily: 'Outfit'),
                  ),
                  const Divider(color: Colors.white10, height: 32),
                  
                  // Constraint #5: Strictly read-only key-value list (no charts or diagnoses)
                  const Text(
                    'Test Results',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Outfit',
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (record.testResults.isEmpty)
                    const Text(
                      'No quantitative values recorded.',
                      style: TextStyle(color: Colors.white38, fontSize: 14, fontStyle: FontStyle.italic, fontFamily: 'Outfit'),
                    )
                  else
                    Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF0B0E14),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white.withAlpha(5), width: 1),
                      ),
                      child: Table(
                        columnWidths: const {
                          0: FlexColumnWidth(1.2),
                          1: FlexColumnWidth(1.0),
                        },
                        border: TableBorder.symmetric(
                          inside: BorderSide(color: Colors.white.withAlpha(5), width: 1),
                        ),
                        children: record.testResults.entries.map((entry) {
                          return TableRow(
                            children: [
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                child: Text(
                                  entry.key.replaceAll('_', ' ').toUpperCase(),
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'Outfit',
                                  ),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                child: Text(
                                  entry.value.toString(),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontFamily: 'Outfit',
                                  ),
                                ),
                              ),
                            ],
                          );
                        }).toList(),
                      ),
                    ),
                  
                  const SizedBox(height: 24),
                  if (record.notes != null && record.notes!.isNotEmpty) ...[
                    const Text(
                      'Notes',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Outfit',
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0B0E14),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        record.notes!,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                          height: 1.4,
                          fontFamily: 'Outfit',
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],

                  // File / Document Attachment (PDF/Image link)
                  if (record.testResults.containsKey('pdf_path')) ...[
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2E5BFF),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        icon: const Icon(Icons.picture_as_pdf_rounded),
                        label: const Text('Open Result Attachment', style: TextStyle(fontFamily: 'Outfit')),
                        onPressed: () {
                          // Standard detail: in a real environment it loads pdfx,
                          // we trigger a snackbar for demo showing it would load the file.
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Loading report attachment: ${record.testResults['pdf_path']}'),
                              backgroundColor: const Color(0xFF0F131D),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }
}
