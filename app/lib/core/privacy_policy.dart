import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The privacy policy bundled with the app. `docs/compliance/PRIVACY.md` in
/// the repo is a symlink to this file, so there is one source of truth. The
/// GitHub blob URL is not used: the repository is private, so that link
/// 404s for anyone who is not signed in to GitHub.
const privacyPolicyAsset = 'assets/PRIVACY.md';

/// Public policy endpoint used for Play Console. The bundled asset remains
/// the offline source of truth for users who have no network.
const privacyPolicyWebUrl = 'https://sagnikdas.github.io/dosely/privacy/';

/// Opens the in-app policy so the user can actually read it, even offline.
void openPrivacyPolicy(BuildContext context) {
  Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => const PrivacyPolicyScreen()));
}

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Privacy policy')),
      body: SafeArea(
        child: FutureBuilder<String>(
          future: rootBundle.loadString(privacyPolicyAsset),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Could not load the privacy policy.',
                    style: text.bodyLarge,
                  ),
                ),
              );
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            return ListView(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
              children: [
                for (final block in _policyBlocks(snapshot.data!, text)) block,
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Turns the bundled markdown into large, selectable text. The policy is
/// short and uses only headings, bold, and bullets — enough to render
/// without a markdown package.
List<Widget> _policyBlocks(String markdown, TextTheme text) {
  final widgets = <Widget>[];
  for (final raw in markdown.split('\n')) {
    final line = raw.trimRight();
    if (line.isEmpty) {
      widgets.add(const SizedBox(height: 12));
      continue;
    }
    if (line.startsWith('# ')) {
      widgets.add(
        SelectableText(_unbold(line.substring(2)), style: text.headlineSmall),
      );
      continue;
    }
    if (line.startsWith('## ')) {
      widgets.add(const SizedBox(height: 8));
      widgets.add(
        SelectableText(_unbold(line.substring(3)), style: text.titleMedium),
      );
      continue;
    }
    if (line.startsWith('- ')) {
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(left: 8, bottom: 8),
          child: SelectableText(
            '• ${_unbold(line.substring(2))}',
            style: text.bodyLarge,
          ),
        ),
      );
      continue;
    }
    widgets.add(SelectableText(_unbold(line), style: text.bodyLarge));
  }
  return widgets;
}

String _unbold(String line) => line.replaceAll('**', '');
