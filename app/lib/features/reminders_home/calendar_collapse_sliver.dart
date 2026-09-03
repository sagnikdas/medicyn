import 'package:flutter/material.dart';

import '../../core/motion.dart';

/// Home calendar as a floating sliver: it takes its child's real height
/// (so large text cannot overflow a guessed header), scrolls away when
/// the dose list moves up, and expands again as soon as the user scrolls
/// down. The list is allowed to move out of the way while the calendar snaps
/// open; an overlaying snap paints the calendar on top of dose cards and makes
/// adjacent reminders look as if they are occupying the same row.
class HomeCalendarSliver extends StatelessWidget {
  const HomeCalendarSliver({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SliverFloatingHeader(
      snapMode: FloatingHeaderSnapMode.scroll,
      animationStyle: AnimationStyle(
        duration: MedicynMotion.medium,
        curve: MedicynMotion.standard,
        reverseDuration: MedicynMotion.medium,
        reverseCurve: MedicynMotion.standard,
      ),
      child: Material(
        key: const ValueKey('collapsing-calendar-header'),
        color: scheme.surface,
        child: child,
      ),
    );
  }
}
