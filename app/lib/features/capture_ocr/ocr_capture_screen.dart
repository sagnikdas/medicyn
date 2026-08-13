import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

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
      photo = await picker.pickImage(source: ImageSource.camera, imageQuality: 85);
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
      final result = await recognizer.processImage(InputImage.fromFilePath(photo.path));
      text = result.text;
    } catch (e) {
      setState(() {
        _status = _Status.error;
        _error = 'Could not read the label. You can still continue with voice only.';
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
    return Scaffold(
      appBar: AppBar(title: const Text('Scan label')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(
                Icons.document_scanner_outlined,
                size: 96,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 24),
              Text(
                'Point your camera at the medicine label',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'The photo stays on your device and is discarded after reading it.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 28),
              if (_error != null) ...[
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                const SizedBox(height: 16),
              ],
              FilledButton.icon(
                onPressed: _status == _Status.capturing || _status == _Status.recognizing ? null : _scan,
                icon: _status == _Status.recognizing
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.camera_alt),
                label: Text(_status == _Status.recognizing ? 'Reading label…' : 'Take photo'),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: _status == _Status.recognizing ? null : _skip,
                child: const Text('Skip — use voice only'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
