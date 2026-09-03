import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';

/// The Bedside Chart's structural motif: a faint, always-present ruled
/// time-grid behind Today's list, echoing the horizontal lines on a real
/// bedside/vitals chart. Content sits on top of it; the grid never carries
/// information on its own; it's the "graticule" the eye locates against.
///
/// Painted once and cached — [CustomPainter.shouldRepaint] is false unless
/// the pitch or color actually changes, so scrolling never repaints it.
class ChartRuleLines extends StatelessWidget {
  const ChartRuleLines({super.key, required this.child, this.pitch = 96});

  final Widget child;

  /// Vertical distance between rules, in logical pixels. Loosely matches a
  /// dose row's resting height so a rule and a row feel like the same
  /// instrument, without either being pinned to the other.
  final double pitch;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _RuleLinePainter(
        color: MedicynTheme.chartGridLine,
        pitch: pitch,
      ),
      child: child,
    );
  }
}

class _RuleLinePainter extends CustomPainter {
  const _RuleLinePainter({required this.color, required this.pitch});

  final Color color;
  final double pitch;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    for (var y = pitch; y < size.height; y += pitch) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _RuleLinePainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.pitch != pitch;
}

/// A quiet paper-grain texture for the linen ground — sparse, low-opacity
/// flecks rather than a photographic texture, so it reads as material
/// without costing a bundled asset or fighting content for attention.
///
/// The fleck field is generated once from a fixed seed (same phone, same
/// grain every launch) and painted as a single [Picture] layer, so it costs
/// one paint regardless of how much content scrolls above it.
class ChartPaperTexture extends StatelessWidget {
  const ChartPaperTexture({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: const _PaperGrainPainter(), child: child);
  }
}

class _PaperGrainPainter extends CustomPainter {
  const _PaperGrainPainter();

  static const _density = 0.00028; // flecks per logical pixel²

  @override
  void paint(Canvas canvas, Size size) {
    final random = math.Random(7); // fixed seed: stable grain, not noise
    final paint = Paint()
      ..color = MedicynTheme.paperGrain.withValues(alpha: 0.5);
    final count = (size.width * size.height * _density).round();
    for (var i = 0; i < count; i++) {
      final dx = random.nextDouble() * size.width;
      final dy = random.nextDouble() * size.height;
      final r = 0.4 + random.nextDouble() * 0.7;
      canvas.drawCircle(Offset(dx, dy), r, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _PaperGrainPainter oldDelegate) => false;
}

/// A date/section heading rendered with a warm, hand-marked feel — italic
/// Public Sans (the brand face stays; only its slant changes) plus a short,
/// gently uneven underline stroke, standing in for an actual script face
/// the bundled type family doesn't have. Reserved for the one heading per
/// screen that plays the "chart annotation" role — never for body text.
class ChartHandLetteredText extends StatelessWidget {
  const ChartHandLetteredText(
    this.text, {
    super.key,
    this.style,
    this.maxLines,
    this.overflow,
  });

  final String text;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;

  @override
  Widget build(BuildContext context) {
    final base =
        style ?? Theme.of(context).textTheme.titleLarge ?? const TextStyle();
    return IntrinsicWidth(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            text,
            maxLines: maxLines,
            overflow: overflow,
            style: base.copyWith(
              fontStyle: FontStyle.italic,
              letterSpacing: (base.letterSpacing ?? 0) + 0.2,
            ),
          ),
          const SizedBox(height: 3),
          SizedBox(
            height: 6,
            child: CustomPaint(painter: _SquigglePainter(color: base.color)),
          ),
        ],
      ),
    );
  }
}

class _SquigglePainter extends CustomPainter {
  const _SquigglePainter({this.color});

  final Color? color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = (color ?? MedicynTheme.primary).withValues(alpha: 0.45)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    final path = Path()..moveTo(0, size.height * 0.6);
    const step = 9.0;
    var x = 0.0;
    var up = true;
    while (x < size.width) {
      final next = math.min(x + step, size.width);
      path.quadraticBezierTo(
        x + step / 2,
        up ? size.height * 0.1 : size.height * 0.95,
        next,
        size.height * 0.6,
      );
      x = next;
      up = !up;
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _SquigglePainter oldDelegate) =>
      oldDelegate.color != color;
}

/// The physical-clip motif: a small steel bedside-clip clasp, drawn at the
/// top of Today, holding the "page" of the chart in place. Purely
/// decorative and non-semantic — excluded from the semantics tree.
class MedicynClip extends StatelessWidget {
  const MedicynClip({super.key, this.width = 72});

  final double width;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: SizedBox(
        width: width,
        height: width * 0.44,
        child: CustomPaint(painter: _ClipPainter()),
      ),
    );
  }
}

class _ClipPainter extends CustomPainter {
  const _ClipPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final body = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, h * 0.28, w, h * 0.5),
      Radius.circular(h * 0.25),
    );
    final metal = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          const Color(0xFFCBC2AE),
          const Color(0xFF9C917A),
          const Color(0xFF7E7563),
        ],
        stops: const [0, 0.55, 1],
      ).createShader(Rect.fromLTWH(0, 0, w, h));
    canvas.drawRRect(body, metal);

    // The bail — the little loop at the top a real bulldog clip hangs by.
    final bailPaint = Paint()
      ..color = const Color(0xFF7E7563)
      ..style = PaintingStyle.stroke
      ..strokeWidth = h * 0.09
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCenter(
        center: Offset(w / 2, h * 0.22),
        width: w * 0.34,
        height: h * 0.34,
      ),
      math.pi * 0.15,
      math.pi * 0.7,
      false,
      bailPaint,
    );

    // A thin highlight down the body so it reads as metal, not a flat bar.
    final highlight = Paint()
      ..color = Colors.white.withValues(alpha: 0.35)
      ..strokeWidth = 1.5;
    canvas.drawLine(
      Offset(w * 0.5, h * 0.32),
      Offset(w * 0.5, h * 0.72),
      highlight,
    );
  }

  @override
  bool shouldRepaint(covariant _ClipPainter oldDelegate) => false;
}
