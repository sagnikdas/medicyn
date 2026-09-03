import 'package:flutter/material.dart';

import '../motion.dart';

/// One-shot fade + slight rise. Plays once per [State] lifetime so a
/// [StreamBuilder] rebuild does not replay it. Remount (new [Key]) to play
/// again — e.g. when the selected calendar day changes.
///
/// Under [MedicynMotion.reduce] the child is shown at rest immediately:
/// no [AnimationController], no delayed opacity of 0 that would eat the
/// first tap on a slow phone.
class MedicynFadeIn extends StatefulWidget {
  const MedicynFadeIn({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.pixels = 10,
  });

  final Widget child;
  final Duration delay;

  /// Paint-only rise in logical pixels. [SlideTransition] is fractional
  /// and overshoots on a tall list; a 10px translate is cheaper and
  /// reads the same on a 720p panel as on a flagship.
  final double pixels;

  @override
  State<MedicynFadeIn> createState() => _MedicynFadeInState();
}

class _MedicynFadeInState extends State<MedicynFadeIn>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;
  Animation<double>? _t;
  var _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (MedicynMotion.reduce(context)) return;
    final delay = widget.delay;
    final move = MedicynMotion.medium;
    final total = delay + move;
    final start = total == Duration.zero
        ? 0.0
        : delay.inMilliseconds / total.inMilliseconds;
    final controller = AnimationController(vsync: this, duration: total);
    _controller = controller;
    _t = CurvedAnimation(
      parent: controller,
      curve: Interval(
        start.clamp(0.0, 0.85),
        1,
        curve: MedicynMotion.decelerate,
      ),
    );
    controller.forward();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = _t;
    if (t == null) return widget.child;
    return AnimatedBuilder(
      animation: t,
      builder: (context, child) {
        final v = t.value;
        return Opacity(
          opacity: v,
          child: Transform.translate(
            offset: Offset(0, widget.pixels * (1 - v)),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}

/// Scale-down on finger down, back on up/cancel. [Listener] does not
/// compete with an inner [InkWell] in the gesture arena.
///
/// Skipped entirely when motion is reduced — a 2% scale is motion, and
/// the ink splash already confirms the tap.
class MedicynPressable extends StatefulWidget {
  const MedicynPressable({
    super.key,
    required this.child,
    this.scale = 0.98,
    this.enabled = true,
  });

  final Widget child;
  final double scale;
  final bool enabled;

  @override
  State<MedicynPressable> createState() => _MedicynPressableState();
}

class _MedicynPressableState extends State<MedicynPressable> {
  var _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final reduce = !widget.enabled || MedicynMotion.reduce(context);
    return Listener(
      onPointerDown: reduce ? null : (_) => _setPressed(true),
      onPointerUp: reduce ? null : (_) => _setPressed(false),
      onPointerCancel: reduce ? null : (_) => _setPressed(false),
      child: AnimatedScale(
        scale: _pressed ? widget.scale : 1,
        duration: MedicynMotion.duration(context, MedicynMotion.fast),
        curve: MedicynMotion.decelerate,
        child: widget.child,
      ),
    );
  }
}

/// Tweens [value] when it changes, starting at the given value on first
/// paint so tests and first-frame layout see the real number, not 0.
///
/// Holds the [Tween] in [State] so a parent rebuild with the same value
/// does not restart the ticker (TweenAnimationBuilder compares tween
/// identity, and `Tween(end: x)` is a new object every build).
class MedicynAnimatedValue extends StatefulWidget {
  const MedicynAnimatedValue({
    super.key,
    required this.value,
    required this.builder,
    this.duration = MedicynMotion.slow,
    this.curve = MedicynMotion.decelerate,
  });

  final double value;
  final Duration duration;
  final Curve curve;
  final Widget Function(BuildContext context, double value) builder;

  @override
  State<MedicynAnimatedValue> createState() => _MedicynAnimatedValueState();
}

class _MedicynAnimatedValueState extends State<MedicynAnimatedValue> {
  late Tween<double> _tween;

  @override
  void initState() {
    super.initState();
    _tween = Tween(begin: widget.value, end: widget.value);
  }

  @override
  void didUpdateWidget(covariant MedicynAnimatedValue oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _tween = Tween(begin: oldWidget.value, end: widget.value);
    }
  }

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: _tween,
      duration: MedicynMotion.duration(context, widget.duration),
      curve: widget.curve,
      builder: (context, value, _) => widget.builder(context, value),
    );
  }
}

/// [IndexedStack] that fades the incoming child. Off-stage children stay
/// mounted (Home's resume observer must keep running) and sit at opacity
/// 0 so the next visit can fade in from rest.
class MedicynIndexedStack extends StatelessWidget {
  const MedicynIndexedStack({
    super.key,
    required this.index,
    required this.children,
    this.sizing = StackFit.loose,
  });

  final int index;
  final List<Widget> children;
  final StackFit sizing;

  @override
  Widget build(BuildContext context) {
    final duration = MedicynMotion.duration(context, MedicynMotion.fast);
    return IndexedStack(
      index: index,
      sizing: sizing,
      children: [
        for (var i = 0; i < children.length; i++)
          AnimatedOpacity(
            opacity: i == index ? 1 : 0,
            duration: duration,
            curve: MedicynMotion.decelerate,
            child: children[i],
          ),
      ],
    );
  }
}

/// Fade between children. Duration collapses to zero when motion is reduced
/// so widget tests that [WidgetTester.pump] once still see the new child.
class MedicynSwitcher extends StatelessWidget {
  const MedicynSwitcher({
    super.key,
    required this.child,
    this.alignment = Alignment.center,
    this.duration = MedicynMotion.fast,
  });

  final Widget child;
  final AlignmentGeometry alignment;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: MedicynMotion.duration(context, duration),
      switchInCurve: MedicynMotion.decelerate,
      switchOutCurve: MedicynMotion.accelerate,
      layoutBuilder: (current, previous) =>
          Stack(alignment: alignment, children: [...previous, ?current]),
      child: child,
    );
  }
}

/// Lightweight fade + 4% horizontal slide. Cheaper than the platform zoom
/// transition on old Mali / PowerVR GPUs, and it respects reduced motion
/// by returning [child] with no transform.
class MedicynPageTransitionsBuilder extends PageTransitionsBuilder {
  const MedicynPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (MedicynMotion.reduce(context)) return child;
    final curved = CurvedAnimation(
      parent: animation,
      curve: MedicynMotion.decelerate,
      reverseCurve: MedicynMotion.accelerate,
    );
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0.04, 0),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      ),
    );
  }
}
