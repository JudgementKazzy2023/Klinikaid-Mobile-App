/// Asia/Manila is UTC+8 all year round (no daylight saving), so the Manila
/// calendar day is the UTC clock shifted by eight hours.
///
/// The clinic's date rules ("today", "cannot be after today", the earliest
/// accepted date) are written against the Manila day, never against the
/// device's own timezone: a patient in another timezone must still be held to
/// the clinic's calendar, and a device clock in the wrong zone must not widen
/// or narrow the window.
const Duration manilaUtcOffset = Duration(hours: 8);

/// The current instant, shifted into Manila's offset.
DateTime manilaNow() => DateTime.now().toUtc().add(manilaUtcOffset);

/// The Manila calendar day [instant] falls on, at local midnight.
///
/// Midnight is the boundary: 2026-02-28T16:30Z is already 2026-03-01 in
/// Manila, so the clinic's day rolls over eight hours before the device's own
/// date does.
DateTime manilaTodayFrom(DateTime instant) {
  final shifted = instant.toUtc().add(manilaUtcOffset);
  return DateTime(shifted.year, shifted.month, shifted.day);
}

/// The current Manila calendar day, at local midnight.
DateTime manilaToday() => manilaTodayFrom(DateTime.now());

/// A calendar date as `YYYY-MM-DD`.
String formatIsoDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

/// The current Manila calendar day as `YYYY-MM-DD`.
String manilaTodayIso() => formatIsoDate(manilaToday());

/// Parses `YYYY-MM-DD`; null when the shape is wrong or the day does not exist
/// (2026-02-30, month 13).
DateTime? parseIsoDate(String value) {
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value.trim());
  if (match == null) return null;

  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  final parsed = DateTime(year, month, day);

  if (parsed.year != year || parsed.month != month || parsed.day != day) {
    return null;
  }
  return parsed;
}

/// The same calendar day [years] later.
///
/// 29 February becomes 1 March in a non-leap year, which is what the shared
/// calendar arithmetic does on the web client too.
DateTime addYears(DateTime date, int years) =>
    DateTime(date.year + years, date.month, date.day);
