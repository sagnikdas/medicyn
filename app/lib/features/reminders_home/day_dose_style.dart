import 'package:flutter/material.dart';

import 'day_occurrences.dart';

/// Paint and copy for a dose row on the day list.
///
/// Taken uses the brand teal, not [Colors.green] — the rest of the product
/// is a single accent, and a traffic-light green on home would read as a
/// different app from the calendar that sits above it.
class DayDoseStyle {
  DayDoseStyle._();

  static const _taken = Color(0xFF00685F);
  static const _pending = Color(0xFF3D6FA8);

  static Color color(BuildContext context, DayDoseStatus status) {
    final scheme = Theme.of(context).colorScheme;
    switch (status) {
      case DayDoseStatus.taken:
        return _taken;
      case DayDoseStatus.pending:
      case DayDoseStatus.upcoming:
        return _pending;
      case DayDoseStatus.snoozed:
        return scheme.tertiary;
      case DayDoseStatus.missed:
        return scheme.error;
      case DayDoseStatus.notRecorded:
        return scheme.outline;
    }
  }

  static String label(DayDoseStatus status) {
    switch (status) {
      case DayDoseStatus.taken:
        return 'Taken';
      case DayDoseStatus.pending:
        return 'Pending';
      case DayDoseStatus.upcoming:
        return 'Due';
      case DayDoseStatus.snoozed:
        return 'Snoozed';
      case DayDoseStatus.missed:
        return 'Missed';
      case DayDoseStatus.notRecorded:
        return 'Not recorded';
    }
  }
}
