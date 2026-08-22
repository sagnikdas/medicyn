import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/widgets/dosely_chrome.dart';
import '../../core/widgets/dosely_layout.dart';

/// Step 1 of the capture flow: photograph the medicine label, run OCR
/// on-device, then immediately delete the photo. Only the extracted text
/// ever leaves this screen (and later, the device) — the image itself is
/// never uploaded or kept, matching the privacy stance in the plan.
///
/// Pops with the recognized text (possibly empty if the user skips or OCR
/// finds nothing) — never null, so callers don't need to special-case
/// cancellation vs. an empty scan.
class OcrCaptureScreen extends StatefulWidget {
  const OcrCaptureScreen({super.key});

  @override
  State<OcrCaptureScreen> createState() => _OcrCaptureScreenState();
}

enum _Status { idle, capturing, recognizing, error }

class _OcrCaptureScreenState extends State<OcrCaptureScreen> {
  _Status _status = _Status.idle;
  String? _error;

  Future<void> _scan() async {
    setState(() {
      _status = _Status.capturing;
      _error = null;
    });

    final picker = ImagePicker();
    XFile? photo;
    try {
      photo = await picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
      );
    } catch (e) {
      setState(() {
        _status = _Status.error;
        _error = 'Could not open the camera.';
      });
      return;
    }

    if (photo == null) {
      setState(() => _status = _Status.idle);
      return;
    }

    setState(() => _status = _Status.recognizing);

    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    String text = '';
    try {
      final result = await recognizer.processImage(
        InputImage.fromFilePath(photo.path),
      );
      text = result.text;
    } catch (e) {
      setState(() {
        _status = _Status.error;
        _error =
            'Could not read the label. You can still continue with voice only.';
      });
    } finally {
      await recognizer.close();
      // The photo never leaves the device and isn't kept once OCR runs.
      try {
        await File(photo.path).delete();
      } catch (_) {
        // Best-effort cleanup; nothing to do if it's already gone.
      }
    }

    if (!mounted) return;
    if (_status != _Status.error) {
      Navigator.of(context).pop(text);
    }
  }

  void _skip() => Navigator.of(context).pop('');

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final busy = _status == _Status.capturing || _status == _Status.recognizing;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: 'Close',
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const DoselyBrandMark(compact: true),
        centerTitle: true,
      ),
      body: SafeArea(
        child: DoselyContent(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Scan Label',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  'Point your camera at the medicine label. Keep it steady.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 24),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainer,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: CustomPaint(
                      painter: _ViewfinderPainter(
                        color: scheme.primaryContainer,
                      ),
                      child: Center(
                        child: busy
                            ? CircularProgressIndicator(color: scheme.primary)
                            : Icon(
                                Icons.document_scanner_outlined,
                                size: 64,
                                color: scheme.primaryContainer,
                              ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                AmbientCard(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.lock_outline, color: scheme.primary),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'The photo stays on your device and is securely discarded immediately after reading it.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: scheme.error),
                  ),
                ],
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: busy ? null : _scan,
                  icon: _status == _Status.recognizing
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.photo_camera),
                  label: Text(
                    _status == _Status.recognizing
                        ? 'Reading label…'
                        : 'Take photo',
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: _status == _Status.recognizing ? null : _skip,
                  child: const Text('Skip — use voice only'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ViewfinderPainter extends CustomPainter {
  const _ViewfinderPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    const arm = 36.0;
    const inset = 40.0;
    final rect = Rect.fromLTWH(
      inset,
      inset,
      size.width - inset * 2,
      size.height - inset * 2,
    );
    // Four L-shaped corners.
    canvas.drawLine(rect.topLeft, rect.topLeft + const Offset(arm, 0), paint);
    canvas.drawLine(rect.topLeft, rect.topLeft + const Offset(0, arm), paint);
    canvas.drawLine(
      rect.topRight,
      rect.topRight + const Offset(-arm, 0),
      paint,
    );
    canvas.drawLine(rect.topRight, rect.topRight + const Offset(0, arm), paint);
    canvas.drawLine(
      rect.bottomLeft,
      rect.bottomLeft + const Offset(arm, 0),
      paint,
    );
    canvas.drawLine(
      rect.bottomLeft,
      rect.bottomLeft + const Offset(0, -arm),
      paint,
    );
    canvas.drawLine(
      rect.bottomRight,
      rect.bottomRight + const Offset(-arm, 0),
      paint,
    );
    canvas.drawLine(
      rect.bottomRight,
      rect.bottomRight + const Offset(0, -arm),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _ViewfinderPainter oldDelegate) =>
      oldDelegate.color != color;
}
