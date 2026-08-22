import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Clinical Calm motion — short, decelerating, never decorative.
///
/// Built for the people this app is for (including older phones):
///  * Durations stay under 400ms so "Mark as Taken" is never waiting on
///    choreography.
///  * [reduce] honours the OS "Remove animations" / animator duration scale
///    of 0 by collapsing every duration to zero. No looping tickers.
///  * Curves are Material 3 emphasized: incoming work settles, outgoing
///    work gets out of the way. Implicit widgets (AnimatedContainer,
///    AnimatedOpacity, TweenAnimationBuilder) over hand-rolled controllers
///    except where a one-shot entrance needs [DoselyFadeIn].
class DoselyMotion {
  DoselyMotion._();

  /// Micro-interactions: press scale, nav pill, icon swap.
  static const Duration fast = Duration(milliseconds: 150);

  /// Standard: page fade, calendar expand, card enter.
  static const Duration medium = Duration(milliseconds: 280);

  /// Values that the eye tracks: progress rings, week bars.
  static const Duration slow = Duration(milliseconds: 400);

  /// Incoming elements (Material 3 emphasized decelerate).
  static const Curve decelerate = Cubic(0.05, 0.7, 0.1, 1.0);

  /// Outgoing elements (Material 3 emphasized accelerate).
  static const Curve accelerate = Cubic(0.3, 0.0, 0.8, 0.15);

  /// Shared with the collapsing calendar sliver.
  static const Curve standard = Curves.easeOutCubic;

  /// Paint-only slide for [DoselyFadeIn]. Small enough that a dropped
  /// frame on a Mali-400 still reads as a fade, not a stutter.
  static const Offset enterOffset = Offset(0, 10);

  static bool reduce(BuildContext context) =>
      MediaQuery.disableAnimationsOf(context);

  static Duration duration(BuildContext context, Duration wanted) =>
      reduce(context) ? Duration.zero : wanted;

  /// Light confirmation for marking a dose taken. No-op on devices
  /// without a vibrator and skipped when the user asked for less motion.
  static void confirm(BuildContext context) {
    if (reduce(context)) return;
    HapticFeedback.lightImpact();
  }

  /// Tab / segmented control. Selection click is quieter than impact.
  static void selection(BuildContext context) {
    if (reduce(context)) return;
    HapticFeedback.selectionClick();
  }
}
