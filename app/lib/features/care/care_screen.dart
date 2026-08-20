import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/local/database.dart';
import '../auth/auth_service.dart';
import '../consent/consent_purpose.dart';
import '../consent/consent_screen.dart';
import '../consent/consent_service.dart';
import 'care_service.dart';
import 'dose_feed_screen.dart';
import 'patient_reminders_screen.dart';

/// Connecting one person who takes medicines with one person who helps them.
///
/// Deliberately one screen with one state at a time rather than a menu: at
/// any moment there is exactly one thing to do, and it fills the screen. The
/// person setting this up is often reading it aloud over a phone call to
/// someone in another city, so every state says what to do next in words
/// that survive being spoken.
///
/// Roles are never asked for. Whoever shows a code needs the help; whoever
/// types one in is giving it. That falls out of the flow, so nobody has to
/// answer a question about what they are.
class CareScreen extends StatefulWidget {
  const CareScreen({super.key, required this.db});

  final AppDatabase db;

  @override
  State<CareScreen> createState() => _CareScreenState();
}

class _CareScreenState extends State<CareScreen> {
  /// While an invite is outstanding the other side's action happens on their
  /// phone, so this one has to look for it. Once push exists this goes away.
  static const _pollInterval = Duration(seconds: 4);

  CareLink? _link;
  String? _otherName;
  CareClaimant? _claimant;
  bool _loading = true;
  String? _error;
  Timer? _poll;

  String get _myId => AuthService.instance.currentUser?.id ?? '';

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  void _schedulePoll() {
    _poll?.cancel();
    final status = _link?.status;
    // Only worth watching while the ball is in the other person's court.
    if (status != CareLinkStatus.pending && status != CareLinkStatus.claimed) return;
    _poll = Timer(_pollInterval, _refresh);
  }

  Future<void> _refresh() async {
    try {
      final link = await CareService.instance.currentLink();
      final otherId = link?.otherPartyId(_myId);
      final name = otherId == null ? null : await CareService.instance.displayName(otherId);
      CareClaimant? claimant;
      if (link != null &&
          link.status == CareLinkStatus.claimed &&
          link.isPatient(_myId)) {
        claimant = await CareService.instance.claimedLinkClaimant(link.id);
      }
      if (!mounted) return;
      setState(() {
        _link = link;
        _otherName = name;
        _claimant = claimant;
        _loading = false;
        _error = null;
      });
    } on CareLinkFailure catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
    }
    _schedulePoll();
  }

  /// Runs [action], showing its failure in place rather than as a snackbar
  /// that vanishes before it can be read aloud to someone.
  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await action();
      await _refresh();
    } on CareLinkFailure catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
    }
  }

  Future<bool> _ensureCareShareConsent() async {
    if (ConsentService.instance.isGranted(ConsentPurpose.careShare)) return true;
    final granted = await showDialog<bool>(
      context: context,
      builder: (_) => const CareShareConsentDialog(),
    );
    if (granted == true) {
      await ConsentService.instance.setGranted(ConsentPurpose.careShare, true);
      return true;
    }
    return false;
  }

  Future<void> _invite() async {
    if (!await _ensureCareShareConsent()) return;
    if (!mounted) return;
    await _run(CareService.instance.createInvite);
  }

  Future<void> _enterCode() async {
    if (!await _ensureCareShareConsent()) return;
    if (!mounted) return;
    final code = await showDialog<String>(
      context: context,
      builder: (_) => const _CodeEntryDialog(),
    );
    if (code == null || !mounted) return;
    await _run(() => CareService.instance.claimInvite(code));
  }

  Future<void> _confirm() {
    // Fail closed: never offer confirmation when the claimant did not resolve.
    if (_claimant == null || _link == null) return Future.value();
    return _run(() => CareService.instance.confirmLink(_link!.id));
  }

  Future<void> _disconnect() async {
    final link = _link;
    if (link == null) return;
    final who = _otherName ?? 'this person';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Disconnect?'),
        content: Text(
          link.status == CareLinkStatus.active
              ? '$who will no longer see your medicines or be able to change them. '
                  'Your reminders stay exactly as they are.'
              : 'This invitation will be cancelled.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Disconnect'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _run(() => CareService.instance.revokeLink(link.id));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Family')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 48),
                  child: Center(child: CircularProgressIndicator()),
                )
              else
                _body(),
              if (_error != null) ...[
                const SizedBox(height: 20),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _body() {
    final link = _link;
    if (link == null) return _chooser();

    final amPatient = link.isPatient(_myId);
    switch (link.status) {
      case CareLinkStatus.pending:
        return _showingCode(link);
      case CareLinkStatus.claimed:
        return amPatient ? _confirmPrompt() : _waitingForConfirmation();
      case CareLinkStatus.active:
        return _connected(amPatient);
      case CareLinkStatus.revoked:
        // currentLink() filters these out; reaching here means the link ended
        // between the read and the build.
        return _chooser();
    }
  }

  // --- states ---------------------------------------------------------------

  Widget _chooser() {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Connect with family', style: text.headlineSmall),
        const SizedBox(height: 8),
        Text(
          'One person can help you keep track of your medicines — or you can '
          'help someone else with theirs.',
          style: text.bodyMedium,
        ),
        const SizedBox(height: 32),
        FilledButton(
          onPressed: _invite,
          child: const Text('Ask someone to help me'),
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: _enterCode,
          child: const Text("I'm helping someone"),
        ),
      ],
    );
  }

  Widget _showingCode(CareLink link) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final code = link.inviteCode ?? '------';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Read this number to them', style: text.headlineSmall),
        const SizedBox(height: 8),
        Text(
          'They should open Dosely on their own phone, tap '
          '"I\'m helping someone", and type it in.',
          style: text.bodyMedium,
        ),
        const SizedBox(height: 28),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 28),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Center(
            child: SelectableText(
              // Spaced so it can be read aloud a digit at a time without
              // losing your place.
              code.split('').join(' '),
              style: text.displaySmall?.copyWith(
                fontWeight: FontWeight.w600,
                letterSpacing: 2,
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              height: 16,
              width: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: scheme.outline),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                'Waiting for them to type it in…',
                style: text.bodySmall,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'This number stops working after 15 minutes. You can always come '
          'back for a new one.',
          style: text.bodySmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 28),
        TextButton(onPressed: _disconnect, child: const Text('Cancel')),
      ],
    );
  }

  Widget _confirmPrompt() {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final claimant = _claimant;
    if (claimant == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(Icons.error_outline, size: 64, color: scheme.error),
          const SizedBox(height: 20),
          Text(
            'We could not confirm who typed in your number',
            style: text.headlineSmall,
          ),
          const SizedBox(height: 12),
          Text(
            'Connecting would let them see your medicines. Disconnect this '
            'invitation and ask the person you meant to invite to try again.',
            style: text.bodyMedium,
          ),
          const SizedBox(height: 28),
          OutlinedButton(
            onPressed: _disconnect,
            child: const Text('Disconnect'),
          ),
        ],
      );
    }
    final who = claimant.displayName;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(
          Icons.person_add_alt_1,
          size: 64,
          color: scheme.primary,
        ),
        const SizedBox(height: 20),
        Text('$who typed in your number', style: text.headlineSmall),
        const SizedBox(height: 8),
        Text(claimant.email, style: text.titleMedium),
        const SizedBox(height: 12),
        Text(
          'If that is who you expected, connect with them. They will be able '
          'to see your medicines and when you take them, and to add or change '
          'a reminder for you.',
          style: text.bodyMedium,
        ),
        const SizedBox(height: 8),
        Text(
          'You will see everything they see, and you can disconnect at any time.',
          style: text.bodySmall,
        ),
        const SizedBox(height: 28),
        FilledButton(
          onPressed: _confirm,
          child: Text('Yes, connect with $who'),
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: _disconnect,
          child: const Text("No, that's not them"),
        ),
      ],
    );
  }

  Widget _waitingForConfirmation() {
    final text = Theme.of(context).textTheme;
    final who = _otherName ?? 'They';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Almost there', style: text.headlineSmall),
        const SizedBox(height: 12),
        Text(
          '$who needs to tap "Yes, connect" on their own phone before you can '
          'see anything. It may help to stay on the call while they do.',
          style: text.bodyMedium,
        ),
        const SizedBox(height: 28),
        const Center(child: CircularProgressIndicator()),
        const SizedBox(height: 28),
        TextButton(onPressed: _disconnect, child: const Text('Cancel')),
      ],
    );
  }

  Widget _connected(bool amPatient) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final who = _otherName ?? 'your family member';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.link, color: scheme.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                amPatient ? 'Connected with $who' : "You're helping $who",
                style: text.headlineSmall,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          amPatient
              ? '$who can see your medicines and when you take them, and can '
                  'add or change a reminder for you.'
              : 'You can see $who\'s medicines and when they take them, and '
                  'add or change a reminder for them.',
          style: text.bodyMedium,
        ),
        const SizedBox(height: 8),
        Text(
          amPatient
              ? 'You see everything they see. Nothing is hidden from you.'
              : '$who sees everything you see, including any change you make.',
          style: text.bodySmall,
        ),
        const SizedBox(height: 28),
        FilledButton.icon(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => DoseFeedScreen(
                // The patient's record either way — the caregiver has no dose
                // history of their own to show here, and the patient seeing
                // the identical screen is the point.
                patientId: _link!.patientId,
                viewingOwnData: amPatient,
              ),
            ),
          ),
          icon: const Icon(Icons.checklist),
          label: Text(amPatient ? 'See what they see' : 'See their doses'),
        ),
        if (!amPatient) ...[
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => PatientRemindersScreen(
                  patientId: _link!.patientId,
                  db: widget.db,
                  patientName: _otherName,
                ),
              ),
            ),
            icon: const Icon(Icons.edit_calendar_outlined),
            label: const Text('Add or change a reminder'),
          ),
        ],
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: _disconnect,
          child: const Text('Disconnect'),
        ),
      ],
    );
  }
}

/// Eight digits, nothing else. Kept as its own dialog so the number pad is the
/// only thing on screen while it's being read out over a phone call.
class _CodeEntryDialog extends StatefulWidget {
  const _CodeEntryDialog();

  @override
  State<_CodeEntryDialog> createState() => _CodeEntryDialogState();
}

class _CodeEntryDialogState extends State<_CodeEntryDialog> {
  final _controller = TextEditingController();
  bool _complete = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final complete = _controller.text.length == 8;
      if (complete != _complete) setState(() => _complete = complete);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Enter their number'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Ask them to open Dosely and tap "Ask someone to help me". '
            'They will read you an eight-digit number.',
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            maxLength: 8,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(letterSpacing: 8),
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(counterText: '', hintText: '00000000'),
            onSubmitted: (v) {
              if (v.length == 8) Navigator.of(context).pop(v);
            },
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: _complete ? () => Navigator.of(context).pop(_controller.text) : null,
          child: const Text('Connect'),
        ),
      ],
    );
  }
}
