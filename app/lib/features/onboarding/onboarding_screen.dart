import 'package:flutter/material.dart';

import '../../core/app_settings.dart';

/// Shown once, before sign-in, on first launch only (see the
/// `_OnboardingGate` in main.dart). Three plain-language pages explaining
/// what the app does — no fine print, no jargon, large icon + headline +
/// one short sentence per page, matching the tone of the capture screens.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingPage {
  const _OnboardingPage({required this.icon, required this.headline, required this.body});
  final IconData icon;
  final String headline;
  final String body;
}

const _pages = [
  _OnboardingPage(
    icon: Icons.document_scanner_outlined,
    headline: 'Scan your medicine label',
    body: 'Point your camera at the label and Dosely reads the details for you.',
  ),
  _OnboardingPage(
    icon: Icons.mic_outlined,
    headline: 'Say your dosage out loud',
    body: 'Just speak how and when to take it — no typing needed.',
  ),
  _OnboardingPage(
    icon: Icons.notifications_active_outlined,
    headline: 'Get reminded — even offline',
    body: 'Dosely alerts you right on time, whether or not you\'re connected.',
  ),
];

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Nothing to call back to: persisting the flag notifies `AppSettings`,
  /// and the gate in main.dart rebuilds itself off that.
  Future<void> _finish() => AppSettings.instance.setHasSeenOnboarding();

  void _next() {
    if (_page == _pages.length - 1) {
      _finish();
      return;
    }
    _controller.nextPage(duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
  }

  @override
  Widget build(BuildContext context) {
    final isLast = _page == _pages.length - 1;
    return Scaffold(
      body: SafeArea(
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
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _pages.length,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (context, i) => _OnboardingPageView(page: _pages[i]),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  _pages.length,
                  (i) => AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: i == _page ? 20 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: i == _page
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.surfaceContainerHighest,
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
    );
  }
}

class _OnboardingPageView extends StatelessWidget {
  const _OnboardingPageView({required this.page});
  final _OnboardingPage page;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(page.icon, size: 120, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 32),
          Text(
            page.headline,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 12),
          Text(
            page.body,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ],
      ),
    );
  }
}
