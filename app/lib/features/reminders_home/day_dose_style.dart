import 'package:flutter/material.dart';

import 'day_occurrences.dart';

/// Paint and copy for a dose row on the day list.
///
/// Taken uses the brand teal, not [Colors.green] — the rest of the product
/// is a single accent, and a traffic-light green on home would read as a
/// different app from the calendar that sits above it.
///
/// The No-Traffic-Light Rule extends one step further under The Bedside
/// Chart: every status also carries its own persistent glyph (see [glyph]),
/// so state reads by mark, not hue alone — the same reason a real chart
/// uses a distinct symbol per entry rather than trusting ink color under a
/// bedside lamp.
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

  /// The persistent mark for each status — check / dash / ring / triangle /
  /// hollow dash — paired with [color] wherever a status shows on screen.
  static IconData glyph(DayDoseStatus status) {
    switch (status) {
      case DayDoseStatus.taken:
        return Icons.check_rounded;
      case DayDoseStatus.pending:
      case DayDoseStatus.upcoming:
        return Icons.remove_rounded;
      case DayDoseStatus.snoozed:
        return Icons.panorama_fish_eye_rounded;
      case DayDoseStatus.missed:
        return Icons.change_history_rounded;
      case DayDoseStatus.notRecorded:
        return Icons.more_horiz_rounded;
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
