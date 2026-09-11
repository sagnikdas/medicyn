/// Copy for "changed by Priya, Tuesday" — the reason last-write-wins is
/// safe to show a family rather than a version number.
library;

import '../../core/locale_dates.dart';

/// One line under a reminder, or null when there is nothing honest to say
/// (a row that predates `updated_by`, or an unknown actor with no name).
String? editAttributionLine({
  required String? updatedBy,
  required DateTime updatedAt,
  required DateTime createdAt,
  required String? currentUserId,
  String? Function(String userId)? nameOf,
  DateTime? now,
}) {
  if (updatedBy == null || updatedBy.isEmpty) return null;
  final who = _who(updatedBy, currentUserId: currentUserId, nameOf: nameOf);
  if (who == null) return null;
  final verb = _isCreate(createdAt, updatedAt) ? 'Added' : 'Changed';
  return '$verb by $who, ${describeRelativeDay(updatedAt, now: now)}';
}

String? _who(
  String updatedBy, {
  required String? currentUserId,
  String? Function(String userId)? nameOf,
}) {
  if (currentUserId != null && updatedBy == currentUserId) return 'you';
  final name = nameOf?.call(updatedBy)?.trim();
  if (name != null && name.isNotEmpty) return name;
  // A linked person whose profile has not landed yet. Better a true line
  // with a stand-in than a blank card that looks like nobody edited it.
  if (currentUserId != null && updatedBy != currentUserId) return 'someone';
  return null;
}

bool _isCreate(DateTime createdAt, DateTime updatedAt) {
  return updatedAt.difference(createdAt).abs() < const Duration(seconds: 2);
}

/// "today", "yesterday", a weekday inside the last week, otherwise a date.
String describeRelativeDay(DateTime at, {DateTime? now}) {
  final n = (now ?? DateTime.now()).toLocal();
  final local = at.toLocal();
  final today = DateTime(n.year, n.month, n.day);
  final day = DateTime(local.year, local.month, local.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return 'today';
  if (diff == 1) return 'yesterday';
  if (diff > 1 && diff < 7) return localeWeekdayName(local);
  return localeDayMonthYear(local);
}

/// Last check-in for the setup-health panel.
String describeLastSeen(DateTime? at, {DateTime? now}) {
  if (at == null) return 'Not yet';
  final n = now ?? DateTime.now();
  final delta = n.difference(at);
  if (delta.isNegative || delta.inSeconds < 45) return 'Just now';
  if (delta.inMinutes < 60) {
    final m = delta.inMinutes;
    return m == 1 ? '1 minute ago' : '$m minutes ago';
  }
  if (delta.inHours < 24 && _sameDay(at, n)) {
    final local = at.toLocal();
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return 'Today at $hh:$mm';
  }
  return describeRelativeDay(at, now: n);
}

bool _sameDay(DateTime a, DateTime b) {
  final la = a.toLocal();
  final lb = b.toLocal();
  return la.year == lb.year && la.month == lb.month && la.day == lb.day;
}

String describeHealthFlag(bool? value) {
  if (value == null) return 'Not reported yet';
  return value ? 'Yes' : 'No';
}
