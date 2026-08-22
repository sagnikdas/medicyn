import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/widgets/dosely_chrome.dart';
import '../../core/widgets/dosely_layout.dart';
import '../../core/widgets/dosely_motion.dart';

/// Step 1 of the capture flow: photograph the medicine label, run OCR
/// on-device, then immediately delete the photo. Only the extracted text
/// ever leaves this screen (and later, the device) — the image itself is
/// never uploaded or kept, matching the privacy stance in the plan.
///
/// The preview is an in-app rear camera, not the system camera app. OEM
/// camera apps ignore facing extras and reopen whichever lens was last
/// used — often the selfie camera. A medicine label is not a selfie.
///
/// Pops with the recognized text (possibly empty if the user skips or OCR
/// finds nothing) — never null, so callers don't need to special-case
/// cancellation vs. an empty scan.
class OcrCaptureScreen extends StatefulWidget {
  const OcrCaptureScreen({super.key});

  @override
  State<OcrCaptureScreen> createState() => _OcrCaptureScreenState();
}

/// Back lens for a medicine label. [availableCameras] often lists the
/// selfie camera first; never take the first entry on faith. Prefer the
/// wide back camera when the device reports lens types, so an ultra-wide
/// does not distort the label.
CameraDescription? pickBackCamera(List<CameraDescription> cameras) {
  if (cameras.isEmpty) return null;
  CameraDescription? back;
  for (final camera in cameras) {
    if (camera.lensDirection != CameraLensDirection.back) continue;
    if (camera.lensType == CameraLensType.wide) return camera;
    back ??= camera;
  }
  return back ?? cameras.first;
}

enum _Status { idle, capturing, recognizing, error }

class _OcrCaptureScreenState extends State<OcrCaptureScreen>
    with WidgetsBindingObserver {
  CameraController? _camera;
  _Status _status = _Status.idle;
  String? _error;
  var _opening = true;
  var _openGen = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_openBackCamera());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _openGen++;
    final camera = _camera;
    _camera = null;
    unawaited(camera?.dispose());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // paused/resumed, not inactive: the permission dialog also fires
    // inactive and would tear the camera down mid-prompt.
    if (state == AppLifecycleState.paused) {
      _openGen++;
      final camera = _camera;
      _camera = null;
      if (mounted) setState(() {});
      unawaited(camera?.dispose());
    } else if (state == AppLifecycleState.resumed) {
      unawaited(_openBackCamera());
    }
  }

  Future<void> _openBackCamera() async {
    final gen = ++_openGen;
    if (mounted) {
      setState(() {
        _opening = true;
        _error = null;
      });
    }

    try {
      final description = pickBackCamera(await availableCameras());
      if (description == null) {
        throw CameraException('noCameras', 'No cameras');
      }

      CameraController? opened;
      Object? lastError;
      for (final preset in const [
        ResolutionPreset.high,
        ResolutionPreset.medium,
      ]) {
        if (gen != _openGen) return;
        final next = CameraController(
          description,
          preset,
          enableAudio: false,
          imageFormatGroup: ImageFormatGroup.jpeg,
        );
        try {
          await next.initialize();
          opened = next;
          lastError = null;
          break;
        } catch (e) {
          lastError = e;
          await next.dispose();
        }
      }

      if (gen != _openGen) {
        await opened?.dispose();
        return;
      }
      if (opened == null) {
        Error.throwWithStackTrace(
          lastError ?? CameraException('failed', 'init'),
          StackTrace.current,
        );
      }

      final previous = _camera;
      _camera = opened;
      await previous?.dispose();
      if (!mounted || gen != _openGen) return;
      setState(() {
        _opening = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted || gen != _openGen) return;
      var denied = false;
      try {
        denied = await Permission.camera.isPermanentlyDenied;
      } catch (_) {
        // Tests and hosts without the permission plugin.
      }
      if (!mounted || gen != _openGen) return;
      setState(() {
        _opening = false;
        _status = _Status.error;
        _error = denied
            ? 'Camera access is off — turn it on in your phone\'s Settings to scan a label.'
            : 'Could not open the camera.';
      });
    }
  }

  Future<void> _scan() async {
    var camera = _camera;
    if (camera == null || !camera.value.isInitialized) {
      await _openBackCamera();
      camera = _camera;
      if (!mounted) return;
      if (camera == null || !camera.value.isInitialized) return;
    }
    if (camera.value.isTakingPicture) return;

    setState(() {
      _status = _Status.capturing;
      _error = null;
    });

    XFile photo;
    try {
      photo = await camera.takePicture();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _status = _Status.error;
        _error = 'Could not open the camera.';
      });
      return;
    }

    if (!mounted) {
      await _deletePhoto(photo.path);
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
      if (mounted) {
        setState(() {
          _status = _Status.error;
          _error =
              'Could not read the label. You can still continue with voice only.';
        });
      }
    } finally {
      await recognizer.close();
      await _deletePhoto(photo.path);
    }

    if (!mounted) return;
    if (_status != _Status.error) {
      Navigator.of(context).pop(text);
    }
  }

  Future<void> _deletePhoto(String path) async {
    try {
      await File(path).delete();
    } catch (_) {
      // Best-effort cleanup; nothing to do if it's already gone.
    }
  }

  void _skip() => Navigator.of(context).pop('');

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final busy = _status == _Status.capturing || _status == _Status.recognizing;
    final camera = _camera;
    final ready = camera != null && camera.value.isInitialized;
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
                Expanded(
                  child: DoselyFadeIn(
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
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: 24),
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(24),
                            child: ColoredBox(
                              color: ready
                                  ? Colors.black
                                  : scheme.surfaceContainer,
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  if (ready)
                                    Positioned.fill(
                                      child: CameraPreview(camera),
                                    )
                                  else
                                    Center(
                                      child: _opening
                                          ? CircularProgressIndicator(
                                              color: scheme.primary,
                                            )
                                          : Icon(
                                              Icons.document_scanner_outlined,
                                              size: 64,
                                              color: scheme.primaryContainer,
                                            ),
                                    ),
                                  CustomPaint(
                                    painter: _ViewfinderPainter(
                                      color: ready
                                          ? Colors.white.withValues(alpha: 0.9)
                                          : scheme.primaryContainer,
                                    ),
                                    child: const SizedBox.expand(),
                                  ),
                                  if (_status == _Status.recognizing)
                                    ColoredBox(
                                      color: Colors.black.withValues(
                                        alpha: 0.4,
                                      ),
                                      child: Center(
                                        child: CircularProgressIndicator(
                                          color: scheme.primary,
                                        ),
                                      ),
                                    ),
                                ],
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
                      ],
                    ),
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
                  onPressed: busy || _opening ? null : _scan,
                  icon: DoselySwitcher(
                    child: _status == _Status.recognizing
                        ? const SizedBox(
                            key: ValueKey('reading'),
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(
                            Icons.photo_camera,
                            key: ValueKey('camera'),
                          ),
                  ),
                  label: DoselySwitcher(
                    child: Text(
                      _status == _Status.recognizing
                          ? 'Reading label…'
                          : 'Take photo',
                      key: ValueKey(
                        _status == _Status.recognizing ? 'reading' : 'take',
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: busy ? null : _skip,
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
