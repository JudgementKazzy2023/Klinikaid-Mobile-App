import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../providers/analytics_provider.dart';
import '../../domain/analytics_series.dart';

class AnalyticsScreen extends StatefulWidget {
  final String patientId;

  const AnalyticsScreen({super.key, required this.patientId});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<AnalyticsProvider>(context, listen: false).init(widget.patientId);
    });
  }

  int _calculateAge(DateTime dob) {
    final now = DateTime.now();
    int age = now.year - dob.year;
    if (now.month < dob.month || (now.month == dob.month && now.day < dob.day)) {
      age--;
    }
    return age;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final provider = Provider.of<AnalyticsProvider>(context);

    if (provider.isLoading) {
      return Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        appBar: AppBar(
          title: const Text('Diagnostic Analytics'),
          centerTitle: true,
        ),
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (provider.errorMessage != null) {
      return Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        appBar: AppBar(
          title: const Text('Diagnostic Analytics'),
          centerTitle: true,
        ),
        body: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline_rounded, color: theme.colorScheme.error, size: 48),
                const SizedBox(height: 16),
                Text(
                  provider.errorMessage!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: theme.colorScheme.error, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () => provider.init(widget.patientId),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final patient = provider.patient;
    if (patient == null) {
      return Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        appBar: AppBar(
          title: const Text('Diagnostic Analytics'),
          centerTitle: true,
        ),
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    final hasData = provider.parameters.isNotEmpty &&
        provider.series != null &&
        provider.series!.points.isNotEmpty;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Diagnostic Analytics'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. Patient Demographics Header Card
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
                      Text(
                        'Patient: ${patient.fullName}',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Patient Code: ${patient.patientCode}',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Email: ${patient.emailDisplay}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Contact: ${patient.contactNumberDisplay}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Age: ${_calculateAge(patient.dateOfBirth)} • Gender: ${patient.gender} • DOB: ${patient.dateOfBirth.year}-${patient.dateOfBirth.month.toString().padLeft(2, '0')}-${patient.dateOfBirth.day.toString().padLeft(2, '0')}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              if (!hasData) ...[
                // Empty State
                Card(
                  key: const Key('analytics_empty_state'),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(32.0),
                    child: Column(
                      children: [
                        Icon(
                          Icons.stacked_line_chart_rounded,
                          size: 64,
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'No records to chart yet',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Select "Enter Record" on the patient directory to log diagnostic data first.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ] else ...[
                // 2. Trajectory selector
                DropdownButtonFormField<String>(
                  key: const Key('parameter_selector_dropdown'),
                  initialValue: provider.selectedParameter,
                  hint: const Text('Select parameter'),
                  decoration: InputDecoration(
                    labelText: 'Diagnostic Trajectory for parameter',
                    prefixIcon: const Icon(Icons.bar_chart_rounded),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  items: provider.parameters.map((p) {
                    return DropdownMenuItem<String>(
                      value: p,
                      child: Text(p),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      provider.selectParameter(val);
                    }
                  },
                ),
                const SizedBox(height: 20),

                // 3. Normal range limit badge & title
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        provider.selectedParameter!,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    if (provider.series!.referenceBandMin != null && provider.series!.referenceBandMax != null)
                      Container(
                        key: const Key('normal_limit_badge'),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.green.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.green.withValues(alpha: 0.5)),
                        ),
                        child: Text(
                          'NORMAL LIMIT: ${provider.series!.referenceBandMin} – ${provider.series!.referenceBandMax} ${provider.series!.unit ?? ""}',
                          style: const TextStyle(
                            color: Colors.green,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),

                // 4. fl_chart Trajectory Plot Container
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 24, 24, 16),
                    child: SizedBox(
                      height: 260,
                      child: _buildChart(provider.series!),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
              ],

              // 5. compliance banner
              Card(
                elevation: 0,
                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.15),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.gavel_rounded, size: 18, color: theme.colorScheme.primary),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'No AI Diagnostic Inference Applied: This longitudinal chart maps historical medical data points directly from stored records. No automated machine diagnostics, diagnostic suggestions, or predictive algorithms are used (Specific Objective C compliant).',
                          style: TextStyle(fontSize: 11, height: 1.4),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              if (hasData) ...[
                const SizedBox(height: 24),
                Text(
                  'Parameter History Records',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 10),

                // 6. Chronological audit history table
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        headingRowColor: WidgetStateProperty.all(
                          theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                        ),
                        columns: const [
                          DataColumn(label: Text('Timestamp', style: TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(label: Text('Technologist', style: TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(label: Text('Value', style: TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(label: Text('Reference Baseline', style: TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(label: Text('Status', style: TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(label: Text('Clinical Annotations', style: TextStyle(fontWeight: FontWeight.bold))),
                        ],
                        rows: _buildTableRows(provider.series!),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChart(ParameterSeries series) {
    final points = series.points;
    if (points.isEmpty) return const Center(child: Text('No points to plot.'));

    final bandMin = series.referenceBandMin;
    final bandMax = series.referenceBandMax;

    // Calculate Y range limits safely
    double minY = bandMin ?? 0.0;
    double maxY = bandMax ?? 10.0;
    if (minY.isNaN || minY.isInfinite) minY = 0.0;
    if (maxY.isNaN || maxY.isInfinite) maxY = 10.0;

    for (final p in points) {
      if (p.value < minY) minY = p.value;
      if (p.value > maxY) maxY = p.value;
    }

    if (minY > maxY) {
      final temp = minY;
      minY = maxY;
      maxY = temp;
    }

    if (minY == maxY) {
      minY = minY - 1.0;
      maxY = maxY + 1.0;
    }

    final rangeY = maxY - minY;
    // Pad bottom by 15%, pad top by 35% to give top label room and avoid collisions.
    final padBottom = rangeY == 0 ? 2.0 : rangeY * 0.15;
    final padTop = rangeY == 0 ? 2.0 : rangeY * 0.35;
    final double computedMinY = minY - padBottom < 0 && minY >= 0 ? 0.0 : minY - padBottom;
    final double computedMaxY = maxY + padTop;

    double totalRangeY = computedMaxY - computedMinY;
    if (totalRangeY.isNaN || totalRangeY.isInfinite || totalRangeY <= 0) {
      totalRangeY = 2.0;
    }
    double yInterval = totalRangeY / 4;
    if (yInterval.isNaN || yInterval.isInfinite || yInterval <= 0) {
      yInterval = 0.5;
    }
    if (yInterval < 0.01) yInterval = 0.01;

    // Use index-based X-axis to ensure exactly one label renders per actual data point
    double minX = 0.0;
    double maxX = (points.length - 1).toDouble();
    if (points.length == 1) {
      minX = -0.5;
      maxX = 0.5;
    }

    final spots = List.generate(points.length, (i) => FlSpot(i.toDouble(), points[i].value));

    return LineChart(
      LineChartData(
        minX: minX,
        maxX: maxX,
        minY: computedMinY,
        maxY: computedMaxY,
        gridData: const FlGridData(
          show: true,
          drawVerticalLine: false,
        ),
        borderData: FlBorderData(
          show: true,
          border: Border(
            bottom: BorderSide(color: Colors.grey.shade300),
            left: BorderSide(color: Colors.grey.shade300),
          ),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 48,
              interval: yInterval,
              getTitlesWidget: (value, meta) {
                return Text(
                  value.toStringAsFixed(1),
                  style: const TextStyle(fontSize: 9),
                );
              },
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 22,
              interval: 1.0,
              getTitlesWidget: (value, meta) {
                final index = value.round();
                if (index >= 0 && index < points.length && (value - index).abs() < 0.01) {
                  final rawDate = points[index].createdAt;
                  // Normalize to PHT (UTC+8)
                  final date = rawDate.toUtc().add(const Duration(hours: 8));
                  // Formatting date: if multiple records share a day, show time or dedupe
                  bool sharesDay = false;
                  for (int i = 0; i < points.length; i++) {
                    final otherDate = points[i].createdAt.toUtc().add(const Duration(hours: 8));
                    if (i != index &&
                        otherDate.year == date.year &&
                        otherDate.month == date.month &&
                        otherDate.day == date.day) {
                      sharesDay = true;
                      break;
                    }
                  }
                  final dateLabel = sharesDay
                      ? '${date.month}/${date.day} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}'
                      : '${date.month}/${date.day}';

                  return SideTitleWidget(
                    meta: meta,
                    child: Text(
                      dateLabel,
                      style: const TextStyle(fontSize: 8),
                    ),
                  );
                }
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (touchedSpots) {
              return touchedSpots.map((touchedSpot) {
                final p = points[touchedSpot.spotIndex];
                final dateStr = '${p.createdAt.year}-${p.createdAt.month.toString().padLeft(2, '0')}-${p.createdAt.day.toString().padLeft(2, '0')}';
                final statusStr = p.isFlagged ? 'Out of Range (Flagged)' : 'Normal';
                final limitStr = p.referenceRangeMin != null && p.referenceRangeMax != null
                    ? 'Limit: ${p.referenceRangeMin} - ${p.referenceRangeMax} ${p.unit ?? ""}'
                    : 'Limit: None';
                final noteStr = p.note != null && p.note!.isNotEmpty ? '\nNote: ${p.note}' : '';

                return LineTooltipItem(
                  'Date: $dateStr\n'
                  'Value: ${p.value} ${p.unit ?? ""}\n'
                  'Status: $statusStr\n'
                  '$limitStr'
                  '$noteStr',
                  const TextStyle(color: Colors.white, fontSize: 10),
                );
              }).toList();
            },
          ),
        ),
        rangeAnnotations: RangeAnnotations(
          horizontalRangeAnnotations: [
            if (bandMin != null && bandMax != null)
              HorizontalRangeAnnotation(
                y1: bandMin,
                y2: bandMax,
                color: Colors.green.withValues(alpha: 0.12),
              ),
          ],
        ),
        extraLinesData: ExtraLinesData(
          horizontalLines: [
            if (bandMin != null)
              HorizontalLine(
                y: bandMin,
                color: Colors.green.withValues(alpha: 0.4),
                strokeWidth: 1,
                dashArray: [5, 5],
              ),
            if (bandMax != null)
              HorizontalLine(
                y: bandMax,
                color: Colors.green.withValues(alpha: 0.4),
                strokeWidth: 1,
                dashArray: [5, 5],
              ),
          ],
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: false,
            barWidth: 2,
            color: Colors.blue.shade700,
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, percent, barData, index) {
                final p = points[index];
                if (p.isFlagged) {
                  return FlDotCirclePainter(
                    radius: 5,
                    color: const Color(0xFFEF4444),
                    strokeWidth: 1.5,
                    strokeColor: Colors.white,
                  );
                } else {
                  return FlDotCirclePainter(
                    radius: 4,
                    color: Colors.blue.shade700,
                    strokeWidth: 1,
                    strokeColor: Colors.white,
                  );
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  List<DataRow> _buildTableRows(ParameterSeries series) {
    final points = series.points.reversed.toList(); // Chronological: newest first
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final currentSpecName = authProvider.profile?.fullName ?? 'Dr. House';
    final currentSpecUid = authProvider.profile?.id ?? 'spec-123';

    return points.map((p) {
      final dateStr = '${p.createdAt.year}-${p.createdAt.month.toString().padLeft(2, '0')}-${p.createdAt.day.toString().padLeft(2, '0')}';
      final technologistName = p.technologist == currentSpecUid ? currentSpecName : p.technologist;

      return DataRow(
        cells: [
          DataCell(Text(dateStr)),
          DataCell(Text(technologistName)),
          DataCell(Text('${p.value} ${p.unit ?? ""}')),
          DataCell(Text(p.referenceRangeMin != null && p.referenceRangeMax != null
              ? '${p.referenceRangeMin} – ${p.referenceRangeMax} ${p.unit ?? ""}'
              : 'N/A')),
          DataCell(
            p.isFlagged
                ? Container(
                    key: const Key('table_flagged_badge'),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF4444),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      'Flagged',
                      style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                  )
                : const Text('Normal'),
          ),
          DataCell(Text(p.note ?? '')),
        ],
      );
    }).toList();
  }
}
