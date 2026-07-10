import 'dart:convert';

/// Extracts the human-readable notes string from the triage_notes field.
///
/// The web portal stores triage_notes as a JSON object containing
/// queue_number, vitals, and a notes field. The mobile app only needs
/// to display the notes field to staff.
///
/// If the input is not valid JSON (e.g., a legacy entry stored as plain
/// text), the original string is returned as-is.
///
/// If the input is valid JSON but the notes field is empty or null,
/// returns null (caller should suppress display).
String? extractTriageNotes(String? rawTriageNotes) {
  if (rawTriageNotes == null || rawTriageNotes.trim().isEmpty) {
    return null;
  }
  try {
    final parsed = jsonDecode(rawTriageNotes);
    if (parsed is Map<String, dynamic>) {
      final notes = parsed['notes'];
      if (notes is String && notes.trim().isNotEmpty) {
        return notes.trim();
      }
      return null;
    }
    // JSON but not the expected shape — fall through to raw display
    return rawTriageNotes;
  } catch (_) {
    // Not JSON — likely a legacy plain-text entry. Display as-is.
    return rawTriageNotes;
  }
}

/// Extract queue number from triage notes JSON, returning "—" on missing/null/error.
String extractQueueNumber(String? rawTriageNotes) {
  if (rawTriageNotes == null || rawTriageNotes.trim().isEmpty) {
    return '—';
  }
  try {
    final parsed = jsonDecode(rawTriageNotes);
    if (parsed is Map<String, dynamic>) {
      final qNum = parsed['queue_number'];
      if (qNum != null && qNum.toString().trim().isNotEmpty) {
        return qNum.toString().trim();
      }
    }
  } catch (_) {}
  return '—';
}

/// Extract vitals summary from triage notes JSON, returning "—" on missing/null/error.
String extractVitalsSummary(String? rawTriageNotes) {
  if (rawTriageNotes == null || rawTriageNotes.trim().isEmpty) {
    return '—';
  }
  try {
    final parsed = jsonDecode(rawTriageNotes);
    if (parsed is Map<String, dynamic>) {
      final vitals = parsed['vitals'];
      if (vitals is Map<String, dynamic>) {
        final List<String> parts = [];
        final bp = vitals['blood_pressure'];
        if (bp != null && bp.toString().trim().isNotEmpty) {
          parts.add('BP: ${bp.toString().trim()}');
        }
        final wt = vitals['weight_kg'];
        if (wt != null) {
          parts.add('Wt: ${wt}kg');
        }
        final temp = vitals['temperature_c'];
        if (temp != null) {
          parts.add('Temp: ${temp}°C');
        }
        if (parts.isEmpty) return '—';
        return parts.join(' | ');
      }
    }
  } catch (_) {}
  return '—';
}

