import 'package:flutter/material.dart';

import '../theme.dart';

/// The "Premium Wellness" ground: a fixed, full-bleed teal→amber wash
/// painted once behind a screen's scrollable content, replacing the old
/// `ChartPaperTexture`/`ChartRuleLines` parchment pair. Because content
/// scrolls over a fixed gradient, no bare heading or body text should ever
/// sit directly on it — see [MedicynGlassHeader].
class MedicynGradientBackground extends StatelessWidget {
  const MedicynGradientBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: MedicynTheme.backgroundGradient(context),
      ),
      child: child,
    );
  }
}

/// A thin frosted band for page headings that would otherwise be bare text
/// directly over [MedicynGradientBackground]. Not a card — no shadow or
/// border, just enough fill to guarantee contrast regardless of where the
/// gradient sits behind it at any given scroll position.
class MedicynGlassHeader extends StatelessWidget {
  const MedicynGlassHeader({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest.withValues(alpha: 0.55),
        borderRadius: const BorderRadius.all(Radius.circular(16)),
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}
