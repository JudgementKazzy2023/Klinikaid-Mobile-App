class DateFormatter {
  /// Converts any [DateTime] (normalized to UTC) to PHT (UTC+8) and formats it as 'YYYY-MM-DD HH:mm PHT'.
  static String formatPht(DateTime dateTime) {
    // Normalize to UTC first to avoid any device-specific timezone discrepancies
    final utcTime = dateTime.toUtc();
    
    // Add exactly 8 hours to get the Philippine Time (PHT) representation
    final phtTime = utcTime.add(const Duration(hours: 8));
    
    final year = phtTime.year;
    final month = phtTime.month.toString().padLeft(2, '0');
    final day = phtTime.day.toString().padLeft(2, '0');
    final hour = phtTime.hour.toString().padLeft(2, '0');
    final minute = phtTime.minute.toString().padLeft(2, '0');
    
    return '$year-$month-$day $hour:$minute PHT';
  }

  /// Converts any [DateTime] (normalized to UTC) to PHT (UTC+8) and formats it compactly as 'MM/DD HH:mm PHT'.
  /// Used for smaller UI elements (e.g. lists, cards).
  static String formatPhtCompact(DateTime dateTime) {
    final utcTime = dateTime.toUtc();
    final phtTime = utcTime.add(const Duration(hours: 8));
    
    final month = phtTime.month.toString().padLeft(2, '0');
    final day = phtTime.day.toString().padLeft(2, '0');
    final hour = phtTime.hour.toString().padLeft(2, '0');
    final minute = phtTime.minute.toString().padLeft(2, '0');
    
    return '$month/$day $hour:$minute PHT';
  }
}
