import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Single-column frame used by every screen.
///
/// Phones are unchanged: the cap is wider than any handset. On a tablet
/// the body stays a readable 640px column instead of stretching cards
/// across the full iPad width. [Expanded] children still work because
/// the frame keeps a bounded height when the parent has one.
class MedicynContent extends StatelessWidget {
  const MedicynContent({super.key, required this.child});

  static const maxWidth = 640.0;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = math.min(constraints.maxWidth, maxWidth);
        final height = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : null;
        return Align(
          alignment: Alignment.topCenter,
          child: SizedBox(width: width, height: height, child: child),
        );
      },
    );
  }
}
