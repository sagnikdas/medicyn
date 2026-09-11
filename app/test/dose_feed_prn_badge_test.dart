import 'package:medicyn/core/theme.dart';
import 'package:medicyn/data/local/tables.dart';
import 'package:medicyn/features/care/care_service.dart';
import 'package:medicyn/features/care/dose_feed_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Issue #99's acceptance criterion said a "Log now" PRN dose must be
/// distinguishable from a scheduled dose "in ... the caregiver's dose feed".
/// [DoseEvent] already carried `source` from Postgres, but [DoseEventCard]
/// (the feed's row widget) never read it — a PRN log rendered identically to
/// an on-time scheduled one. These tests pin the fix: an "As needed" badge
/// shown only when [DoseEvent.isAsNeededLog] is true (manual source *and* an
/// as-needed schedule), matching dose_history_prn_badge_test.dart's coverage
/// of the equivalent patient-facing screen.
///
/// [DoseEventCard] is pumped directly with a hand-built [DoseEvent] rather
/// than through [DoseFeedScreen], which loads via `CareService.instance` —
/// a live Supabase-backed singleton — the same way the rest of this file's
/// siblings (dose_feed_test.dart) test [DoseEvent] in isolation from the
/// network.
void main() {
  DoseEvent event({String source = 'notification', String? frequencyType}) {
    final at = DateTime(2026, 8, 26, 8, 0);
    return DoseEvent(
      id: 'log-1',
      scheduledAt: at,
      loggedAt: at,
      action: 'taken',
      drugName: 'Ibuprofen',
      strength: '',
      doseAmount: '1 tablet',
      source: source,
      recordedBy: 'patient-1',
      frequencyType: frequencyType ?? FrequencyType.daily.name,
    );
  }

  Future<void> pumpCard(WidgetTester tester, DoseEvent e) {
    return tester.pumpWidget(
      MaterialApp(
        theme: MedicynTheme.light(),
        home: Scaffold(
          body: DoseEventCard(
            event: e,
            clockTime: e.scheduledAt,
            patientId: 'patient-1',
          ),
        ),
      ),
    );
  }

  testWidgets(
    'shows the As needed badge for a manually logged PRN dose',
    (tester) async {
      await pumpCard(
        tester,
        event(source: 'manual', frequencyType: FrequencyType.asNeeded.name),
      );

      expect(find.text('Taken · due 08:00'), findsOneWidget);
      expect(find.text('As needed'), findsOneWidget);
    },
  );

  testWidgets(
    'does not show the badge for a normal scheduled dose',
    (tester) async {
      await pumpCard(tester, event());

      expect(find.text('Taken · due 08:00'), findsOneWidget);
      expect(find.text('As needed'), findsNothing);
    },
  );

  testWidgets(
    'does not show the badge for a manual-source log on a scheduled '
    '(non-as-needed) schedule',
    (tester) async {
      await pumpCard(
        tester,
        event(source: 'manual', frequencyType: FrequencyType.daily.name),
      );

      expect(find.text('As needed'), findsNothing);
    },
  );
}
