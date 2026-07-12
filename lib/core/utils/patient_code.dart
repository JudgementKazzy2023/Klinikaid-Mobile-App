/// Utility function to derive a deterministic patient code from their UUID.
/// Strips dashes, takes the first 8 characters, converts to uppercase,
/// and prefixes with 'PT-'.
String patientCodeFromId(String id) {
  final clean = id.replaceAll('-', '');
  if (clean.length < 8) {
    return 'PT-${clean.toUpperCase()}';
  }
  return 'PT-${clean.substring(0, 8).toUpperCase()}';
}
