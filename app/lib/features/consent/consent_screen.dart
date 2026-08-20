import 'package:flutter/material.dart';

import '../../core/privacy_policy.dart';
import 'consent_purpose.dart';
import 'consent_service.dart';

/// Shown once after onboarding (and once for existing installs that already
/// skipped onboarding). Each purpose starts off. Continue is always enabled
/// — they can proceed with everything off. Care-share is not asked here.
class ConsentScreen extends StatefulWidget {
  const ConsentScreen({super.key});

  @override
  State<ConsentScreen> createState() => _ConsentScreenState();
}

class _ConsentScreenState extends State<ConsentScreen> {
  final Map<ConsentPurpose, bool> _granted = {
    for (final purpose in ConsentPurpose.firstScreen) purpose: false,
  };
  bool _saving = false;

  Future<void> _continue() async {
    if (_saving) return;
    setState(() => _saving = true);
    await ConsentService.instance.recordFirstScreenChoices(
      cloudBackup: _granted[ConsentPurpose.cloudBackup]!,
      anthropicParse: _granted[ConsentPurpose.anthropicParse]!,
      googleSpeech: _granted[ConsentPurpose.googleSpeech]!,
    );
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 12),
                children: [
                  Text('What Dosely may do', style: text.headlineSmall),
                  const SizedBox(height: 12),
                  Text(
                    'These are off unless you turn them on. You can change '
                    'your mind later in Settings. Reminders still work on '
                    'this phone either way.',
                    style: text.bodyLarge,
                  ),
                  const SizedBox(height: 24),
                  for (final purpose in ConsentPurpose.firstScreen) ...[
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(purpose.title, style: text.titleMedium),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(purpose.sentence, style: text.bodyMedium),
                      ),
                      value: _granted[purpose]!,
                      onChanged: (v) => setState(() => _granted[purpose] = v),
                    ),
                    const SizedBox(height: 8),
                  ],
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: () => openPrivacyPolicy(context),
                    child: Text(
                      'Privacy policy',
                      style: text.titleMedium?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: FilledButton(
                onPressed: _saving ? null : _continue,
                child: _saving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Continue'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Explicit, unticked prompt before creating or claiming a Care Link.
/// Continue stays disabled until the switch is on.
class CareShareConsentDialog extends StatefulWidget {
  const CareShareConsentDialog({super.key});

  @override
  State<CareShareConsentDialog> createState() => _CareShareConsentDialogState();
}

class _CareShareConsentDialogState extends State<CareShareConsentDialog> {
  bool _agreed = false;

  @override
  Widget build(BuildContext context) {
    final purpose = ConsentPurpose.careShare;
    return AlertDialog(
      title: Text(purpose.title),
      content: SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(purpose.sentence),
        value: _agreed,
        onChanged: (v) => setState(() => _agreed = v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Not now'),
        ),
        TextButton(
          onPressed: _agreed ? () => Navigator.of(context).pop(true) : null,
          child: const Text('Continue'),
        ),
      ],
    );
  }
}
