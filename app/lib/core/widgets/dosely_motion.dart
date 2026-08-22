import 'package:flutter/material.dart';

import '../motion.dart';

/// One-shot fade + slight rise. Plays once per [State] lifetime so a
/// [StreamBuilder] rebuild does not replay it. Remount (new [Key]) to play
/// again — e.g. when the selected calendar day changes.
///
/// Under [DoselyMotion.reduce] the child is shown at rest immediately:
/// no [AnimationController], no delayed opacity of 0 that would eat the
/// first tap on a slow phone.
class DoselyFadeIn extends StatefulWidget {
  const DoselyFadeIn({
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
  State<DoselyFadeIn> createState() => _DoselyFadeInState();
}

class _DoselyFadeInState extends State<DoselyFadeIn>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;
  Animation<double>? _t;
  var _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (DoselyMotion.reduce(context)) return;
    final delay = widget.delay;
    final move = DoselyMotion.medium;
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
        curve: DoselyMotion.decelerate,
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
class DoselyPressable extends StatefulWidget {
  const DoselyPressable({
    super.key,
    required this.child,
    this.scale = 0.98,
    this.enabled = true,
  });

  final Widget child;
  final double scale;
  final bool enabled;

  @override
  State<DoselyPressable> createState() => _DoselyPressableState();
}

class _DoselyPressableState extends State<DoselyPressable> {
  var _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final reduce = !widget.enabled || DoselyMotion.reduce(context);
    return Listener(
      onPointerDown: reduce ? null : (_) => _setPressed(true),
      onPointerUp: reduce ? null : (_) => _setPressed(false),
      onPointerCancel: reduce ? null : (_) => _setPressed(false),
      child: AnimatedScale(
        scale: _pressed ? widget.scale : 1,
        duration: DoselyMotion.duration(context, DoselyMotion.fast),
        curve: DoselyMotion.decelerate,
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
class DoselyAnimatedValue extends StatefulWidget {
  const DoselyAnimatedValue({
    super.key,
    required this.value,
    required this.builder,
    this.duration = DoselyMotion.slow,
    this.curve = DoselyMotion.decelerate,
  });

  final double value;
  final Duration duration;
  final Curve curve;
  final Widget Function(BuildContext context, double value) builder;

  @override
  State<DoselyAnimatedValue> createState() => _DoselyAnimatedValueState();
}

class _DoselyAnimatedValueState extends State<DoselyAnimatedValue> {
  late Tween<double> _tween;

  @override
  void initState() {
    super.initState();
    _tween = Tween(begin: widget.value, end: widget.value);
  }

  @override
  void didUpdateWidget(covariant DoselyAnimatedValue oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _tween = Tween(begin: oldWidget.value, end: widget.value);
    }
  }

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: _tween,
      duration: DoselyMotion.duration(context, widget.duration),
      curve: widget.curve,
      builder: (context, value, _) => widget.builder(context, value),
    );
  }
}

/// [IndexedStack] that fades the incoming child. Off-stage children stay
/// mounted (Home's resume observer must keep running) and sit at opacity
/// 0 so the next visit can fade in from rest.
class DoselyIndexedStack extends StatelessWidget {
  const DoselyIndexedStack({
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
    final duration = DoselyMotion.duration(context, DoselyMotion.fast);
    return IndexedStack(
      index: index,
      sizing: sizing,
      children: [
        for (var i = 0; i < children.length; i++)
          AnimatedOpacity(
            opacity: i == index ? 1 : 0,
            duration: duration,
            curve: DoselyMotion.decelerate,
            child: children[i],
          ),
      ],
    );
  }
}

/// Fade between children. Duration collapses to zero when motion is reduced
/// so widget tests that [WidgetTester.pump] once still see the new child.
class DoselySwitcher extends StatelessWidget {
  const DoselySwitcher({
    super.key,
    required this.child,
    this.alignment = Alignment.center,
    this.duration = DoselyMotion.fast,
  });

  final Widget child;
  final AlignmentGeometry alignment;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: DoselyMotion.duration(context, duration),
      switchInCurve: DoselyMotion.decelerate,
      switchOutCurve: DoselyMotion.accelerate,
      layoutBuilder: (current, previous) =>
          Stack(alignment: alignment, children: [...previous, ?current]),
      child: child,
    );
  }
}

/// Lightweight fade + 4% horizontal slide. Cheaper than the platform zoom
/// transition on old Mali / PowerVR GPUs, and it respects reduced motion
/// by returning [child] with no transform.
class DoselyPageTransitionsBuilder extends PageTransitionsBuilder {
  const DoselyPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (DoselyMotion.reduce(context)) return child;
    final curved = CurvedAnimation(
      parent: animation,
      curve: DoselyMotion.decelerate,
      reverseCurve: DoselyMotion.accelerate,
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
