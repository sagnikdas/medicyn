import 'package:dosely/core/privacy_policy.dart';
import 'package:dosely/features/auth/sign_in_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('privacyPolicyUrl is the published GitHub policy', () {
    expect(
      privacyPolicyUrl,
      'https://github.com/sagnikdas/dosely/blob/main/PRIVACY.md',
    );
  });

  testWidgets('sign-in screen offers a Privacy policy control', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SignInScreen()));
    expect(find.widgetWithText(TextButton, 'Privacy policy'), findsOneWidget);
  });
}
