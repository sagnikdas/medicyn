import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/app_settings.dart';
import '../../core/motion.dart';
import '../../core/telemetry.dart';
import '../../core/widgets/medicyn_chrome.dart';
import '../../core/widgets/medicyn_layout.dart';
import '../../core/widgets/medicyn_motion.dart';

/// Shown once, before sign-in, on first launch only (see the
/// `_OnboardingGate` in main.dart). One concise value/privacy screen keeps
/// the first session moving: the user sees what Medicyn does and that their
/// reminders work offline before choosing how to add a medicine.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingPage {
  const _OnboardingPage({
    required this.icon,
    required this.headline,
    required this.body,
  });
  final IconData icon;
  final String headline;
  final String body;
}

const _pages = [
  _OnboardingPage(
    icon: Icons.document_scanner_outlined,
    headline: 'Scan your medicine label',
    body:
        'Add a reminder by scanning, speaking, or typing. Your medicine details stay on this phone unless you choose backup, and reminders work offline.',
  ),
];

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _page = 0;

  @override
  void initState() {
    super.initState();
    unawaited(MedicynTelemetry.instance.record(MedicynEvent.onboardingViewed));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Nothing to call back to: persisting the flag notifies `AppSettings`,
  /// and the gate in main.dart rebuilds itself off that.
  Future<void> _finish() async {
    await AppSettings.instance.setHasSeenOnboarding();
    await MedicynTelemetry.instance.record(MedicynEvent.onboardingCompleted);
  }

  void _next() {
    if (_page == _pages.length - 1) {
      _finish();
      return;
    }
    _controller.nextPage(
      duration: MedicynMotion.duration(context, MedicynMotion.medium),
      curve: MedicynMotion.decelerate,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLast = _page == _pages.length - 1;
    return Scaffold(
      body: SafeArea(
        child: MedicynContent(
          child: Column(
            children: [
              Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.only(right: 8, top: 4),
                  child: TextButton(
                    onPressed: _finish,
                    child: const Text('Skip'),
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: MedicynBrandMark(compact: true),
              ),
              Expanded(
                child: PageView.builder(
                  controller: _controller,
                  itemCount: _pages.length,
                  onPageChanged: (i) => setState(() => _page = i),
                  itemBuilder: (context, i) =>
                      _OnboardingPageView(page: _pages[i]),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    _pages.length,
                    (i) => AnimatedContainer(
                      duration: MedicynMotion.duration(
                        context,
                        MedicynMotion.fast,
                      ),
                      curve: MedicynMotion.decelerate,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: i == _page ? 20 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: i == _page
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(
                                context,
                              ).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(28, 8, 28, 24),
                child: FilledButton(
                  onPressed: _next,
                  child: Text(isLast ? 'Get started' : 'Next'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OnboardingPageView extends StatelessWidget {
  const _OnboardingPageView({required this.page});
  final _OnboardingPage page;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxHeight < 420;
        return SingleChildScrollView(
          padding: EdgeInsets.symmetric(
            horizontal: 32,
            vertical: compact ? 16 : 32,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                MedicynFadeIn(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        page.icon,
                        size: compact ? 64 : 120,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      SizedBox(height: compact ? 16 : 32),
                      Text(
                        page.headline,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  page.body,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
