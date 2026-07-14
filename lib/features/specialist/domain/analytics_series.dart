import '../../../../core/models/specialist_record.dart';
import '../../../../core/utils/lab_validators.dart';

class ChartDataPoint {
  final DateTime createdAt;
  final double value;
  final bool isFlagged;
  final double? referenceRangeMin;
  final double? referenceRangeMax;
  final String? note;
  final String testType;
  final String? unit;
  final String technologist;

  ChartDataPoint({
    required this.createdAt,
    required this.value,
    required this.isFlagged,
    this.referenceRangeMin,
    this.referenceRangeMax,
    this.note,
    required this.testType,
    this.unit,
    required this.technologist,
  });
}

class ParameterSeries {
  final String parameterName;
  final List<ChartDataPoint> points;
  final double? referenceBandMin;
  final double? referenceBandMax;
  final String? unit;

  ParameterSeries({
    required this.parameterName,
    required this.points,
    this.referenceBandMin,
    this.referenceBandMax,
    this.unit,
  });
}

/// Extracts all unique parameter names present in the records list in stable alphabetical order.
List<String> availableParameters(List<SpecialistRecord> records) {
  final Set<String> params = {};
  for (final record in records) {
    if (record.testName.trim().isNotEmpty) {
      params.add(record.testName.trim());
    }
  }
  return params.toList()..sort();
}

/// Builds a time series of chart points for a specific parameter name.
/// Keeps individual point flagged states from their stored `is_flagged` values.
/// Sets referenceBandMin/Max using the MOST RECENT record's stored range bounds.
ParameterSeries buildSeries(List<SpecialistRecord> records, String testName) {
  final filtered = records.where((r) => r.testName == testName).toList();

  // Sort chronologically (oldest to newest)
  filtered.sort((a, b) => a.createdAt.compareTo(b.createdAt));

  final List<ChartDataPoint> points = [];
  double? bandMin;
  double? bandMax;
  String? unit;

  for (final r in filtered) {
    if (!isDisplayableLabValue(r.testValue)) {
      // Skip null, NaN, Infinity, negative, or absurdly large values defensively
      continue;
    }
    final double val = double.parse(r.testValue.trim());

    points.add(ChartDataPoint(
      createdAt: r.createdAt,
      value: val,
      isFlagged: r.isFlagged,
      referenceRangeMin: r.referenceRangeMin,
      referenceRangeMax: r.referenceRangeMax,
      note: r.notes,
      testType: r.testType,
      unit: r.unit,
      technologist: r.specialistId ?? 'Unknown',
    ));

    // Update with most recent range bounds as loop progresses (last item is the newest)
    bandMin = r.referenceRangeMin;
    bandMax = r.referenceRangeMax;
    unit = r.unit;
  }

  return ParameterSeries(
    parameterName: testName,
    points: points,
    referenceBandMin: bandMin,
    referenceBandMax: bandMax,
    unit: unit,
  );
}
