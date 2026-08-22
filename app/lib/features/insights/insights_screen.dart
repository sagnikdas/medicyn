import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../core/widgets/dosely_chrome.dart';
import '../../data/local/database.dart';
import '../auth/auth_service.dart';
import '../care/care_service.dart';
import '../care/dose_feed_screen.dart';
import '../reminders_home/day_occurrences.dart';

/// Adherence for the current week, drawn from the same occurrence lattice
/// Home already uses. Nothing here is invented: a week with no doses due
/// shows empty copy rather than a fake 92%.
class InsightsScreen extends StatelessWidget {
  const InsightsScreen({
    super.key,
    required this.db,
    this.onAvatarTap,
  });

  final AppDatabase db;
  final VoidCallback? onAvatarTap;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: DoselyTopBar(
        onAvatarTap: onAvatarTap,
        avatarLabel: AuthService.instance.currentUser?.email,
      ),
      body: StreamBuilder<List<ScheduleWithMedicine>>(
        stream: db.watchSchedulesWithMedicines(),
        builder: (context, scheduleSnap) {
          return StreamBuilder<List<DoseLog>>(
            stream: db.watchDoseLogs(),
            builder: (context, logSnap) {
              return _InsightsBody(
                db: db,
                schedules: scheduleSnap.data ?? const [],
                logs: logSnap.data ?? const [],
              );
            },
          );
        },
      ),
    );
  }
}

class _InsightsBody extends StatelessWidget {
  const _InsightsBody({
    required this.db,
    required this.schedules,
    required this.logs,
  });

  final AppDatabase db;
  final List<ScheduleWithMedicine> schedules;
  final List<DoseLog> logs;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final records = <DoseRecord>[
      for (final log in logs) ?DoseRecord.tryFromLog(log),
    ];
    final week = weekAdherence(items: schedules, logs: records, now: now);
    final days = weekDayAdherence(items: schedules, logs: records, now: now);
    final streak = consistencyStreak(items: schedules, logs: records, now: now);
    final missedPart = mostMissedDayPart(
      items: schedules,
      logs: records,
      now: now,
    );
    var missed = 0;
    for (final day in days) {
      if (day.expected > day.taken) missed += day.expected - day.taken;
    }
    final avg = week.expected == 0 ? 0.0 : week.taken / week.expected;
    final morning = _partRate(days: days, logs: records, items: schedules, now: now, part: DayPart.morning);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: [
        Text(
          'Your health insights',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 4),
        Text(
          'What actually happened with your medicines this week.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 24),
        AmbientCard(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Weekly adherence',
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          week.expected == 0
                              ? 'Nothing due this week yet.'
                              : '${week.taken} of ${week.expected} taken',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .primaryContainer
                          .withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      week.expected == 0
                          ? '—'
                          : '${(avg * 100).round()}% avg',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              _WeekBars(days: days, now: now),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _StatHero(
                icon: Icons.local_fire_department,
                label: 'Consistency streak',
                value: '$streak',
                unit: streak == 1 ? 'day' : 'days',
                caption: streak == 0
                    ? 'A day counts when every due dose was taken.'
                    : 'Every due dose taken, walking back from today.',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: AmbientCard(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.wb_sunny_outlined,
                          color: Theme.of(context).colorScheme.tertiary,
                          size: 18,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Most consistent',
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      morning.label,
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: morning.rate,
                        minHeight: 8,
                        color: Theme.of(context).colorScheme.tertiary,
                        backgroundColor: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHigh,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        morning.expected == 0
                            ? 'No morning doses'
                            : '${(morning.rate * 100).round()}% taken',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        AmbientCard(
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: Theme.of(context).colorScheme.errorContainer,
                foregroundColor: Theme.of(context).colorScheme.onErrorContainer,
                child: const Icon(Icons.warning_amber_rounded),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Unanswered doses',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      '$missed',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    Text(
                      'This week',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        AmbientCard(
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: Theme.of(
                  context,
                ).colorScheme.secondaryContainer,
                foregroundColor: Theme.of(
                  context,
                ).colorScheme.onSecondaryContainer,
                child: const Icon(Icons.medication_outlined),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Doses taken',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      '${week.taken}',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    Text(
                      'This week',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        AmbientCard(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                backgroundColor: Theme.of(
                  context,
                ).colorScheme.surfaceContainerHighest,
                foregroundColor: Theme.of(context).colorScheme.onSurfaceVariant,
                child: const Icon(Icons.info_outline),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Observation',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _observation(missedPart, missed),
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _FamilyInsightsLink(db: db),
      ],
    );
  }

  static ({String label, double rate, int expected}) _partRate({
    required List<({DateTime day, int taken, int expected})> days,
    required List<DoseRecord> logs,
    required List<ScheduleWithMedicine> items,
    required DateTime now,
    required DayPart part,
  }) {
    // Re-walk the week for this part only — cheap, and keeps scoring
    // identical to occurrencesOnDay.
    var taken = 0;
    var expected = 0;
    for (final day in days) {
      final occs = occurrencesOnDay(
        items: items,
        logs: logs,
        day: day.day,
        now: now,
      );
      for (final o in occs) {
        if (dayPartOf(o.scheduledAt) != part) continue;
        if (o.status == DayDoseStatus.taken) taken++;
        if (o.status == DayDoseStatus.upcoming) continue;
        if (calendarDay(o.scheduledAt).isAfter(calendarDay(now))) continue;
        expected++;
      }
    }
    return (
      label: part.label,
      rate: expected == 0 ? 0.0 : taken / expected,
      expected: expected,
    );
  }
}

extension on DayPart {
  String get label => switch (this) {
    DayPart.morning => 'Morning',
    DayPart.afternoon => 'Afternoon',
    DayPart.evening => 'Evening',
  };
}

String _observation(DayPart? missedPart, int missed) {
  if (missed == 0) {
    return 'No unanswered doses this week.';
  }
  if (missedPart == null) {
    return '$missed dose${missed == 1 ? '' : 's'} went unanswered this week.';
  }
  return '${missedPart.label} doses are the ones most often unanswered this week.';
}

class _WeekBars extends StatelessWidget {
  const _WeekBars({required this.days, required this.now});

  final List<({DateTime day, int taken, int expected})> days;
  final DateTime now;

  static const _letters = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final today = calendarDay(now);
    return SizedBox(
      height: 160,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < days.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(
              child: _Bar(
                fraction: days[i].expected == 0
                    ? 0
                    : days[i].taken / days[i].expected,
                label: _letters[i],
                isToday: isSameCalendarDay(days[i].day, today),
                color: isSameCalendarDay(days[i].day, today)
                    ? scheme.primaryContainer
                    : scheme.primary,
                track: scheme.surfaceContainerHigh,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({
    required this.fraction,
    required this.label,
    required this.isToday,
    required this.color,
    required this.track,
  });

  final double fraction;
  final String label;
  final bool isToday;
  final Color color;
  final Color track;

  @override
  Widget build(BuildContext context) {
    final h = (fraction.clamp(0.0, 1.0) * 120).clamp(4.0, 120.0);
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Expanded(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              width: 28,
              height: h,
              decoration: BoxDecoration(
                color: color,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(6),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: isToday
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.onSurfaceVariant,
            fontWeight: isToday ? FontWeight.w700 : FontWeight.w400,
          ),
        ),
      ],
    );
  }
}

class _StatHero extends StatelessWidget {
  const _StatHero({
    required this.icon,
    required this.label,
    required this.value,
    required this.unit,
    required this.caption,
  });

  final IconData icon;
  final String label;
  final String value;
  final String unit;
  final String caption;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: scheme.primary,
        borderRadius: BorderRadius.circular(12),
        boxShadow: DoselyTheme.ambientShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: scheme.inversePrimary, size: 18),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label.toUpperCase(),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: scheme.inversePrimary,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: value,
                  style: Theme.of(context).textTheme.displaySmall?.copyWith(
                    color: scheme.onPrimary,
                  ),
                ),
                TextSpan(
                  text: ' $unit',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: scheme.onPrimary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            caption,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: scheme.onPrimary.withValues(alpha: 0.8),
            ),
          ),
        ],
      ),
    );
  }
}

class _FamilyInsightsLink extends StatefulWidget {
  const _FamilyInsightsLink({required this.db});
  final AppDatabase db;

  @override
  State<_FamilyInsightsLink> createState() => _FamilyInsightsLinkState();
}

class _FamilyInsightsLinkState extends State<_FamilyInsightsLink> {
  CareLink? _link;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (AuthService.instance.currentUser == null) return;
    try {
      final link = await CareService.instance.currentLink();
      if (!mounted) return;
      setState(() => _link = link);
    } catch (_) {
      // Insights still works without a care link.
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = AuthService.instance.currentUser;
    final link = _link;
    if (me == null || link == null || link.status != CareLinkStatus.active) {
      return const SizedBox.shrink();
    }
    final amPatient = link.isPatient(me.id);
    return ProfileMenuRow(
      icon: Icons.people_outline,
      title: amPatient ? 'What they see' : "Their week's doses",
      subtitle: 'The same feed both sides of a care link share.',
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => DoseFeedScreen(
            patientId: link.patientId,
            viewingOwnData: amPatient,
          ),
        ),
      ),
    );
  }
}
