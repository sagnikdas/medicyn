import 'package:camera/camera.dart';
import 'package:medicyn/core/theme.dart';
import 'package:medicyn/features/capture_ocr/ocr_capture_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  CameraDescription camera(String name, CameraLensDirection lens) {
    return CameraDescription(
      name: name,
      lensDirection: lens,
      sensorOrientation: 90,
    );
  }

  test('picks the back lens even when the selfie camera is listed first', () {
    final back = camera('0', CameraLensDirection.back);
    final picked = pickBackCamera([
      camera('1', CameraLensDirection.front),
      back,
      camera('2', CameraLensDirection.external),
    ]);
    expect(picked, same(back));
  });

  test('prefers the wide back camera over ultra-wide', () {
    final ultra = CameraDescription(
      name: 'uw',
      lensDirection: CameraLensDirection.back,
      sensorOrientation: 90,
      lensType: CameraLensType.ultraWide,
    );
    final wide = CameraDescription(
      name: 'wide',
      lensDirection: CameraLensDirection.back,
      sensorOrientation: 90,
      lensType: CameraLensType.wide,
    );
    expect(pickBackCamera([ultra, wide]), same(wide));
  });

  test('returns null when the device has no cameras', () {
    expect(pickBackCamera(const []), isNull);
  });

  test('falls back to the only camera if there is no back lens', () {
    final front = camera('1', CameraLensDirection.front);
    expect(pickBackCamera([front]), same(front));
  });

  testWidgets(
    'scan label stays on this screen instead of opening a camera app',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(theme: MedicynTheme.light(), home: const OcrCaptureScreen()),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('Scan Label'), findsOneWidget);
      expect(find.text('Take photo'), findsOneWidget);
      expect(find.text('Skip — use voice only'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
