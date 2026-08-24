import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../../core/motion.dart';
import '../../core/widgets/dosely_layout.dart';
import '../../core/widgets/dosely_motion.dart';
import '../consent/consent_purpose.dart';
import '../consent/consent_service.dart';

/// Step 2 of the capture flow: speak the dosage/schedule instructions
/// ("one tablet twice a day, morning and night") and get a transcript.
///
/// Transcription goes through the *platform's* speech recogniser, not an
/// on-device one: `SpeechListenOptions.onDevice` is left at its default of
/// false, so on most Android devices the audio is handled by Google's speech
/// service. Dosely neither stores nor uploads the audio itself, but "nothing
/// leaves the phone" would be untrue — see docs/compliance/PRIVACY.md, which says so plainly.
/// Only the resulting text is sent onward, and only at the AI structuring
/// step the review screen triggers explicitly.
///
/// Pops with the transcript (possibly empty if skipped) — never null.
class VoiceCaptureScreen extends StatefulWidget {
  const VoiceCaptureScreen({super.key});

  @override
  State<VoiceCaptureScreen> createState() => _VoiceCaptureScreenState();
}

enum _Status { idle, initializing, listening, unavailable }

class _VoiceCaptureScreenState extends State<VoiceCaptureScreen> {
  SpeechToText? _speech;
  _Status _status = _Status.idle;
  String _transcript = '';
  String? _errorMessage;

  bool get _speechAllowed =>
      ConsentService.instance.isGranted(ConsentPurpose.googleSpeech);

  @override
  void dispose() {
    _speech?.cancel();
    super.dispose();
  }

  Future<void> _startListening() async {
    if (!_speechAllowed) return;
    setState(() {
      _status = _Status.initializing;
      _errorMessage = null;
    });
    _speech ??= SpeechToText();
    final available = await _speech!.initialize(
      onStatus: (status) {
        if (status == 'done' || status == 'notListening') {
          setState(() => _status = _Status.idle);
        }
      },
      // `error.errorMsg` is a code, not user-facing text (see package docs) —
      // a permanent error almost always means the mic permission was denied,
      // so check that directly rather than showing the raw code.
      onError: (error) async {
        final micDenied = await Permission.microphone.isPermanentlyDenied;
        setState(() {
          _status = _Status.idle;
          _errorMessage = error.permanent && micDenied
              ? 'Microphone access is off — turn it on in your phone\'s Settings to use voice input.'
              : 'Didn\'t catch that — tap the mic and try again.';
        });
      },
    );
    if (!available) {
      final micDenied = await Permission.microphone.isPermanentlyDenied;
      setState(() {
        _status = _Status.unavailable;
        _errorMessage = micDenied
            ? 'Microphone access is off — turn it on in your phone\'s Settings to use voice input.'
            : 'Speech recognition isn\'t available on this device.';
      });
      return;
    }
    setState(() => _status = _Status.listening);
    await _speech!.listen(
      onResult: (result) =>
          setState(() => _transcript = result.recognizedWords),
      listenOptions: SpeechListenOptions(
        partialResults: true,
        cancelOnError: true,
      ),
    );
  }

  Future<void> _stopListening() async {
    await _speech?.stop();
    setState(() => _status = _Status.idle);
  }

  void _done() => Navigator.of(context).pop(_transcript);

  @override
  Widget build(BuildContext context) {
    final listening = _status == _Status.listening;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: SafeArea(
        child: DoselyContent(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 16),
                DoselyFadeIn(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Say the dosage & schedule',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'e.g. "One tablet twice a day, morning and night, after food"',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                if (_errorMessage != null) ...[
                  Text(
                    _errorMessage!,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: scheme.error),
                  ),
                  const SizedBox(height: 16),
                ],
                if (!_speechAllowed)
                  Text(
                    'Voice input is off. You can skip this and type the details on the next screen.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge,
                  )
                else if (_status == _Status.unavailable)
                  OutlinedButton(
                    onPressed: () => openAppSettings(),
                    child: const Text('Open Settings'),
                  )
                else
                  Column(
                    children: [
                      GestureDetector(
                        onTap: listening ? _stopListening : _startListening,
                        child: AnimatedContainer(
                          duration: DoselyMotion.duration(
                            context,
                            DoselyMotion.fast,
                          ),
                          curve: DoselyMotion.decelerate,
                          width: 128,
                          height: 128,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: listening ? scheme.error : scheme.primary,
                            boxShadow: [
                              BoxShadow(
                                color:
                                    (listening ? scheme.error : scheme.primary)
                                        .withValues(alpha: 0.35),
                                blurRadius: listening ? 24 : 12,
                                spreadRadius: listening ? 8 : 0,
                              ),
                            ],
                          ),
                          child: Icon(
                            listening ? Icons.stop : Icons.mic,
                            color: scheme.onPrimary,
                            size: 48,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _transcript.isEmpty
                            ? (listening
                                  ? 'Listening…'
                                  : 'Tap the mic and speak')
                            : _transcript,
                        textAlign: TextAlign.center,
                        style: Theme.of(
                          context,
                        ).textTheme.labelLarge?.copyWith(color: scheme.primary),
                      ),
                    ],
                  ),
                const Spacer(),
                FilledButton(onPressed: _done, child: const Text('Continue')),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(''),
                  child: const Text('Type it instead'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
