import 'package:klinikaid_mobile/core/models/department_record.dart';
import 'package:klinikaid_mobile/core/models/profile.dart';

class GroupedRecord {
  final String patientId;
  final Department department;
  final DateTime bucketStart; // truncated recordedAt (5-min bucket)
  final List<DepartmentRecord> records; // 1+ rows

  GroupedRecord({
    required this.patientId,
    required this.department,
    required this.bucketStart,
    required this.records,
  });

  String get displayTitle => records.first.testType;

  ReferenceRangeStatus get aggregateStatus => _aggregateStatus(records);

  String get aggregatedNotes => records
      .map((r) => r.notes)
      .whereType<String>()
      .map((n) => n.trim())
      .where((n) => n.isNotEmpty)
      .toSet()
      .join('\n');

  bool get isSingleParameter => records.length == 1;



  static ReferenceRangeStatus _aggregateStatus(List<DepartmentRecord> records) {
    if (records.any((r) => r.referenceRangeStatus == ReferenceRangeStatus.criticalHigh)) {
      return ReferenceRangeStatus.criticalHigh;
    }
    if (records.any((r) => r.referenceRangeStatus == ReferenceRangeStatus.criticalLow)) {
      return ReferenceRangeStatus.criticalLow;
    }
    if (records.any((r) => r.referenceRangeStatus == ReferenceRangeStatus.inconclusive)) {
      return ReferenceRangeStatus.inconclusive;
    }
    return ReferenceRangeStatus.normal;
  }
}

DateTime truncateToFiveMinutes(DateTime t) {
  final minutes = (t.minute ~/ 5) * 5;
  return DateTime(t.year, t.month, t.day, t.hour, minutes);
}

List<GroupedRecord> groupRecords(List<DepartmentRecord> raw) {
  if (raw.isEmpty) return [];

  // Sort raw records by createdAt descending (most recent first)
  final sortedRaw = List<DepartmentRecord>.from(raw)
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  final Map<String, List<DepartmentRecord>> buckets = {};
  for (final r in sortedRaw) {
    final bucket = truncateToFiveMinutes(r.createdAt.toLocal());
    final key = '${r.patientId}|${r.department.name}|${bucket.toIso8601String()}';
    buckets.putIfAbsent(key, () => []).add(r);
  }

  final groups = buckets.entries.map((entry) {
    final list = entry.value;
    final first = list.first;
    
    // Sort records inside the group by createdAt ascending (stable order)
    final sortedList = List<DepartmentRecord>.from(list)
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

    return GroupedRecord(
      patientId: first.patientId,
      department: first.department,
      bucketStart: truncateToFiveMinutes(first.createdAt.toLocal()),
      records: sortedList,
    );
  }).toList();

  // Sort groups by most recent bucket first
  groups.sort((a, b) => b.bucketStart.compareTo(a.bucketStart));
  return groups;
}
