import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Step 2 of the capture flow: speak the dosage/schedule instructions
/// ("one tablet twice a day, morning and night") and get a transcript.
/// On-device speech recognition — nothing is sent anywhere until the AI
/// structuring step, which the review screen triggers explicitly.
///
/// Pops with the transcript (possibly empty if skipped) — never null.
class VoiceCaptureScreen extends StatefulWidget {
  const VoiceCaptureScreen({super.key});

  @override
  State<VoiceCaptureScreen> createState() => _VoiceCaptureScreenState();
}

enum _Status { idle, initializing, listening, unavailable }

class _VoiceCaptureScreenState extends State<VoiceCaptureScreen> {
  final _speech = SpeechToText();
  _Status _status = _Status.idle;
  String _transcript = '';

  @override
  void dispose() {
    _speech.cancel();
    super.dispose();
  }

  Future<void> _startListening() async {
    setState(() => _status = _Status.initializing);
    final available = await _speech.initialize(
      onStatus: (status) {
        if (status == 'done' || status == 'notListening') {
          setState(() => _status = _Status.idle);
        }
      },
      onError: (_) => setState(() => _status = _Status.idle),
    );
    if (!available) {
      setState(() => _status = _Status.unavailable);
      return;
    }
    setState(() => _status = _Status.listening);
    await _speech.listen(
      onResult: (result) => setState(() => _transcript = result.recognizedWords),
      listenOptions: SpeechListenOptions(partialResults: true, cancelOnError: true),
    );
  }

  Future<void> _stopListening() async {
    await _speech.stop();
    setState(() => _status = _Status.idle);
  }

  void _done() => Navigator.of(context).pop(_transcript);

  @override
  Widget build(BuildContext context) {
    final listening = _status == _Status.listening;
    return Scaffold(
      appBar: AppBar(title: const Text('Say the dosage & schedule')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'e.g. "One tablet twice a day, morning and night, after food"',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 28),
              Container(
                padding: const EdgeInsets.all(20),
                constraints: const BoxConstraints(minHeight: 120),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _transcript.isEmpty ? (listening ? 'Listening…' : 'Tap the mic and speak') : _transcript,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ),
              const SizedBox(height: 28),
              if (_status == _Status.unavailable)
                Text(
                  'Speech recognition isn\'t available on this device.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                )
              else
                Center(
                  child: GestureDetector(
                    onTap: listening ? _stopListening : _startListening,
                    child: CircleAvatar(
                      radius: 40,
                      backgroundColor: listening
                          ? Theme.of(context).colorScheme.error
                          : Theme.of(context).colorScheme.primary,
                      child: Icon(
                        listening ? Icons.stop : Icons.mic,
                        color: Theme.of(context).colorScheme.onPrimary,
                        size: 32,
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 28),
              FilledButton(
                onPressed: _transcript.isEmpty ? null : _done,
                child: const Text('Continue'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.of(context).pop(''),
                child: const Text('Skip'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
