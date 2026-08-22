import 'dart:async';

import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_settings.dart';
import 'device_lock.dart';
import 'motion.dart';

/// Covers the app with an unlock screen after it has been in the background
/// past [kDeviceLockGrace], then asks for the phone's existing PIN / pattern
/// / biometric. This is the automatic-logoff the Security Rule wants, without
/// a 15-minute logout that would strand the person the app is for.
///
/// Skipped until consents are recorded (onboarding has no medical record
/// yet) and skipped on a device with no screen lock — there is nothing to
/// prompt with, and a lock they cannot dismiss is worse than an open app.
class DeviceLockGate extends StatefulWidget {
  const DeviceLockGate({super.key, required this.child});

  final Widget child;

  @override
  State<DeviceLockGate> createState() => _DeviceLockGateState();
}

class _DeviceLockGateState extends State<DeviceLockGate>
    with WidgetsBindingObserver {
  final _auth = LocalAuthentication();
  DateTime? _pausedAt;
  bool _locked = false;
  bool _deviceProtected = false;
  bool _prompting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_readProtection());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _readProtection() async {
    try {
      final supported = await _auth.isDeviceSupported();
      if (mounted) setState(() => _deviceProtected = supported);
    } catch (_) {
      // Fail open: a plugin error is not evidence of a lock screen.
      if (mounted) setState(() => _deviceProtected = false);
    }
  }

  bool get _inScope {
    final settings = AppSettings.instance;
    if (!settings.hasRecordedConsents) return false;
    if (settings.localOnly) return true;
    return Supabase.instance.client.auth.currentUser != null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _pausedAt = DateTime.now();
      return;
    }
    if (state != AppLifecycleState.resumed) return;
    if (!_inScope) return;
    final shouldLock = shouldLockOnResume(
      pausedAt: _pausedAt,
      now: DateTime.now(),
      deviceProtected: _deviceProtected,
    );
    if (!shouldLock) return;
    setState(() => _locked = true);
    unawaited(_promptUnlock());
  }

  Future<void> _promptUnlock() async {
    if (_prompting) return;
    _prompting = true;
    try {
      final ok = await _auth.authenticate(
        localizedReason: 'Unlock to see your reminders',
        options: const AuthenticationOptions(
          biometricOnly: false,
          stickyAuth: true,
          useErrorDialogs: true,
        ),
      );
      if (ok && mounted) setState(() => _locked = false);
    } catch (_) {
      // Stay locked. The on-screen button lets them try again.
    } finally {
      _prompting = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Always stack so the navigator (and open database) stay mounted when
    // the cover appears, and so AnimatedOpacity can fade the lock in.
    return Stack(
      fit: StackFit.expand,
      children: [
        Offstage(offstage: _locked, child: widget.child),
        IgnorePointer(
          ignoring: !_locked,
          child: ExcludeSemantics(
            excluding: !_locked,
            child: AnimatedOpacity(
              opacity: _locked ? 1 : 0,
              duration: DoselyMotion.duration(context, DoselyMotion.fast),
              curve: DoselyMotion.decelerate,
              child: ColoredBox(
                color: scheme.surface,
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.lock_outline,
                          size: 48,
                          color: scheme.primary,
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'Unlock Dosely',
                          style: Theme.of(context).textTheme.headlineSmall,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Use the PIN, pattern, or fingerprint you already use on this phone.',
                          style: Theme.of(context).textTheme.bodyLarge,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 32),
                        FilledButton(
                          onPressed: _promptUnlock,
                          child: const Text('Unlock'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
