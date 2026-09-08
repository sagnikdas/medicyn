import 'package:medicyn/core/privacy_policy.dart';
import 'package:medicyn/features/auth/sign_in_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the in-app policy is the bundled markdown, not a private GitHub URL', () {
    expect(privacyPolicyAsset, 'assets/PRIVACY.md');
  });

  testWidgets('tapping Privacy policy on sign-in opens the bundled policy', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SignInScreen()));
    await tester.tap(find.widgetWithText(TextButton, 'Privacy policy'));
    await tester.pumpAndSettle();
    expect(find.byType(PrivacyPolicyScreen), findsOneWidget);
    expect(find.textContaining('Doezly'), findsWidgets);
    expect(find.textContaining('contact@doezly.com'), findsWidgets);
  });
}
