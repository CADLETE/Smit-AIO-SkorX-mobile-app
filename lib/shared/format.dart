/// Display formatting shared by every screen: money, dates, times.
library;

const weekdaysShort = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const monthsShort = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// ₹1,200 in Indian digit grouping (₹1,20,000). Zero reads "Free".
String formatInr(int rupees, {bool freeWhenZero = true}) {
  if (rupees == 0 && freeWhenZero) return 'Free';
  final digits = rupees.abs().toString();
  String grouped;
  if (digits.length <= 3) {
    grouped = digits;
  } else {
    final last3 = digits.substring(digits.length - 3);
    var rest = digits.substring(0, digits.length - 3);
    final parts = <String>[];
    while (rest.length > 2) {
      parts.insert(0, rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
    if (rest.isNotEmpty) parts.insert(0, rest);
    grouped = '${parts.join(',')},$last3';
  }
  return '${rupees < 0 ? '−' : ''}₹$grouped';
}

/// Paise as rupees: ₹999 for whole rupees, ₹1,178.82 otherwise. Zero is ₹0.
String formatPaise(int paise) {
  final rupees = formatInr(paise.abs() ~/ 100, freeWhenZero: false);
  final fraction = paise.abs() % 100;
  final text = fraction == 0 ? rupees : '$rupees.${fraction.toString().padLeft(2, '0')}';
  return paise < 0 ? '−$text' : text;
}

/// "7:30 PM".
String time12(DateTime t) {
  final hour = t.hour % 12 == 0 ? 12 : t.hour % 12;
  return '$hour:${t.minute.toString().padLeft(2, '0')} ${t.hour < 12 ? 'AM' : 'PM'}';
}

/// "7 PM" for whole hours, "7:30 PM" otherwise.
String timeShort(DateTime t) {
  if (t.minute != 0) return time12(t);
  final hour = t.hour % 12 == 0 ? 12 : t.hour % 12;
  return '$hour ${t.hour < 12 ? 'AM' : 'PM'}';
}

/// "Sat, 22 Aug".
String dayDate(DateTime d) => '${weekdaysShort[d.weekday - 1]}, ${d.day} ${monthsShort[d.month - 1]}';

/// "22 Aug 2026".
String longDate(DateTime d) => '${d.day} ${monthsShort[d.month - 1]} ${d.year}';

/// "22–24 Aug" or "30 Aug – 1 Sep".
String dateRange(DateTime start, DateTime end) {
  if (start.year == end.year && start.month == end.month) {
    if (start.day == end.day) return '${start.day} ${monthsShort[start.month - 1]}';
    return '${start.day}–${end.day} ${monthsShort[start.month - 1]}';
  }
  return '${start.day} ${monthsShort[start.month - 1]} – ${end.day} ${monthsShort[end.month - 1]}';
}

int daysBetween(DateTime from, DateTime to) =>
    DateTime(to.year, to.month, to.day).difference(DateTime(from.year, from.month, from.day)).inDays;

/// "Today", "Tomorrow", "Yesterday" or "Sat, 22 Aug".
String relativeDay(DateTime d, DateTime now) => switch (daysBetween(now, d)) {
      0 => 'Today',
      1 => 'Tomorrow',
      -1 => 'Yesterday',
      _ => dayDate(d),
    };

/// "Just now", "12m ago", "3h ago", "2d ago", then the date.
String timeAgo(DateTime t, DateTime now) {
  final diff = now.difference(t);
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inHours < 1) return '${diff.inMinutes}m ago';
  if (diff.inDays < 1) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return dayDate(t);
}

/// "+18" / "−12" / "0", with a real minus sign.
String signed(int value) => value > 0 ? '+$value' : value < 0 ? '−${value.abs()}' : '0';

/// "42.6", a SkorX Rating (0–100) as players see it.
String ratingText(double rating) => rating.toStringAsFixed(1);

/// Initials for an avatar: "Smit Ramani" → "SR".
String initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts.first[0].toUpperCase();
  return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
}

/// "+91 95865 45430" from "+919586545430"; anything else is returned as is.
String formatPhone(String phone) {
  final m = RegExp(r'^\+91(\d{5})(\d{5})$').firstMatch(phone.replaceAll(' ', ''));
  return m == null ? phone : '+91 ${m[1]} ${m[2]}';
}

/// "2026-09-26".
String isoDay(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// SkorX Points to 2 decimals with thousands grouped: "684.75", "1,842.30".
String sxpText(num sxp) {
  final hundredths = (sxp * 100).round();
  final whole = (hundredths.abs() ~/ 100).toString();
  final grouped = whole.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
  final text = '$grouped.${(hundredths.abs() % 100).toString().padLeft(2, '0')}';
  return hundredths < 0 ? '−$text' : text;
}

/// A signed SkorX Points change: "+0.28", "−1.10", "0.00".
String sxpDeltaText(num sxp) {
  final text = sxpText(sxp.abs());
  final hundredths = (sxp * 100).round();
  return hundredths > 0 ? '+$text' : hundredths < 0 ? '−$text' : text;
}
