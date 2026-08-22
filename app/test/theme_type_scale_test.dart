import 'package:dosely/core/theme.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('100% uses phone-sized type, not the Stitch artboard tokens', () {
    final text = DoselyTheme.light().textTheme;
    expect(text.bodyMedium?.fontSize, 14);
    expect(text.bodyLarge?.fontSize, 16);
    expect(text.titleMedium?.fontSize, 16);
    expect(text.titleLarge?.fontSize, 20);
    expect(text.headlineSmall?.fontSize, 22);
    expect(text.displaySmall?.fontSize, 28);
    expect(text.labelSmall?.fontSize, 11);
  });
}
