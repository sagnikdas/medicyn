import 'package:flutter/material.dart';

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
      animationStyle: const AnimationStyle(
        duration: Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
        reverseDuration: Duration(milliseconds: 280),
        reverseCurve: Curves.easeOutCubic,
      ),
      child: Material(
        key: const ValueKey('collapsing-calendar-header'),
        color: scheme.surface,
        child: child,
      ),
    );
  }
}
