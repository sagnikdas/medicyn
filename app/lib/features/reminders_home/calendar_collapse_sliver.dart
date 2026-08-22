import 'package:flutter/material.dart';

import '../../core/motion.dart';

/// Home calendar as a floating sliver: it takes its child's real height
/// (so large text cannot overflow a guessed header), scrolls away when
/// the dose list moves up, and expands again as soon as the user scrolls
/// down.
class HomeCalendarSliver extends StatelessWidget {
  const HomeCalendarSliver({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SliverFloatingHeader(
      snapMode: FloatingHeaderSnapMode.overlay,
      animationStyle: AnimationStyle(
        duration: DoselyMotion.medium,
        curve: DoselyMotion.standard,
        reverseDuration: DoselyMotion.medium,
        reverseCurve: DoselyMotion.standard,
      ),
      child: Material(
        key: const ValueKey('collapsing-calendar-header'),
        color: scheme.surface,
        child: child,
      ),
    );
  }
}
