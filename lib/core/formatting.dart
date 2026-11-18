import 'package:intl/intl.dart';

/// Number/date helpers ported from the RN app's src/utils/utils.js, so values display the same way.

/// calculatePercentage(part, whole): one decimal, as text ('84.3'); '0.0' when either side is
/// missing or the whole is 0.
String calculatePercentage(num? part, num? whole) {
  if (part == null || whole == null || whole == 0 || part.isNaN || whole.isNaN) return '0.0';
  final pct = part / whole * 100;
  if (pct.isNaN || pct.isInfinite) return '0.0';
  return pct.toStringAsFixed(1);
}

/// numberFormatWithDecimal(num, 2): '1,234,567.89'.
String numberWithDecimals(num value, [int decimals = 2]) {
  final pattern = decimals == 0 ? '#,##0' : '#,##0.${'0' * decimals}';
  return NumberFormat(pattern, 'en_US').format(value);
}

/// Math.round(x).toLocaleString('en-US'): '1,234,568'.
String roundedWithCommas(num value) => NumberFormat('#,##0', 'en_US').format(value.round());

/// The dashboard reads numbers the backend may send as numbers or numeric strings.
num? asNum(dynamic value) {
  if (value is num) return value;
  if (value is String) return num.tryParse(value.trim());
  return null;
}

/// getDataAndTime(date): 'November 17, 2026 (Tuesday)'.
String longDateWithWeekday(DateTime date) =>
    '${DateFormat('MMMM d, y', 'en_US').format(date)} (${DateFormat('EEEE', 'en_US').format(date)})';

/// 'YYYY-MM-DD' of a local date -- the unit the app's "is this still today's data?" checks use.
String dayKey(DateTime date) => DateFormat('yyyy-MM-dd').format(date);

/// The RN app sends `Number(value)` for some query parameters: '001234' -> '1234', 'R1' -> 'NaN',
/// '' -> '0', missing -> 'NaN'.
String jsNumberText(String? value) {
  if (value == null) return 'NaN';
  final parsed = num.tryParse(value.trim());
  if (parsed == null) return value.trim().isEmpty ? '0' : 'NaN';
  return parsed == parsed.roundToDouble() ? parsed.toInt().toString() : parsed.toString();
}
