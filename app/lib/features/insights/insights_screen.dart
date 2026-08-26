import 'package:flutter/material.dart';

import '../../core/app_settings.dart';
import '../../core/motion.dart';
import '../../core/theme.dart';
import '../../core/widgets/dosely_chrome.dart';
import '../../core/widgets/dosely_motion.dart';
import '../../data/local/database.dart';
import '../auth/auth_service.dart';
import '../care/care_service.dart';
import '../care/dose_feed_screen.dart';
import '../reminders_home/day_occurrences.dart';

/// Adherence for the current week, drawn from the same occurrence lattice
/// Home already uses. Nothing here is invented: a week with no doses due
/// shows empty copy rather than a fake 92%.
/// Stateful only to hold its two streams. Opening them in `build` made a
/// StreamBuilder re-subscribe — and both queries re-run over the whole of
/// dose_logs — every time this tab rebuilt for any reason.
class InsightsScreen extends StatefulWidget {
  const InsightsScreen({super.key, required this.db, this.onAvatarTap});

  final AppDatabase db;
  final VoidCallback? onAvatarTap;

  @override
  State<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends State<InsightsScreen> {
  late final Stream<List<ScheduleWithMedicine>> _schedulesStream = widget.db
      .watchSchedulesWithMedicines();
  late final Stream<List<DoseLog>> _doseLogsStream = widget.db.watchDoseLogs();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: DoselyTopBar(
        onAvatarTap: widget.onAvatarTap,
        avatarLabel: AuthService.instance.currentUser?.email,
      ),
      body: StreamBuilder<List<ScheduleWithMedicine>>(
        stream: _schedulesStream,
        builder: (context, scheduleSnap) {
          return StreamBuilder<List<DoseLog>>(
            stream: _doseLogsStream,
            builder: (context, logSnap) {
              return _InsightsBody(
                db: widget.db,
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
    // One index for all five walks below. Each of them would otherwise
    // rebuild it, and consistencyStreak alone walks a year of days.
    final logIndex = DoseRecordIndex(records);
    final snoozeWindow = Duration(minutes: AppSettings.instance.snoozeMinutes);
    final week = weekAdherence(
      items: schedules,
      index: logIndex,
      now: now,
      snoozeWindow: snoozeWindow,
    );
    final days = weekDayAdherence(
      items: schedules,
      index: logIndex,
      now: now,
      snoozeWindow: snoozeWindow,
    );
    final streak = consistencyStreak(
      items: schedules,
      index: logIndex,
      now: now,
      snoozeWindow: snoozeWindow,
    );
    final missedPart = mostMissedDayPart(
      items: schedules,
      index: logIndex,
      now: now,
      snoozeWindow: snoozeWindow,
    );
    var missed = 0;
    for (final day in days) {
      if (day.expected > day.taken) missed += day.expected - day.taken;
    }
    final avg = week.expected == 0 ? 0.0 : week.taken / week.expected;
    final partRates = [
      for (final part in DayPart.values)
        _partRate(
          days: days,
          index: logIndex,
          items: schedules,
          now: now,
          part: part,
          snoozeWindow: snoozeWindow,
        ),
    ];
    final mostConsistent = partRates
        .where((part) => part.expected > 0)
        .fold<({String label, double rate, int expected})?>(
          null,
          (best, part) => best == null || part.rate > best.rate ? part : best,
        );

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: [
        DoselyFadeIn(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Your health insights',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              Text(
                'What actually happened with your medicines this week.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
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
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          week.expected == 0
                              ? 'Nothing due this week yet.'
                              : '${week.taken} of ${week.expected} taken',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Theme.of(
                            context,
                          ).colorScheme.primaryContainer.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          week.expected == 0
                              ? '—'
                              : '${(avg * 100).round()}% avg',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(
                                color: Theme.of(context).colorScheme.primary,
                              ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              DoselyFadeIn(
                child: _WeekBars(days: days, now: now),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final streakCard = _StatHero(
              icon: Icons.local_fire_department,
              label: 'Consistency streak',
              value: '$streak',
              unit: streak == 1 ? 'day' : 'days',
              caption: streak == 0
                  ? 'A day counts when every due dose was taken.'
                  : 'Every due dose taken, walking back from today.',
            );
            final consistentCard = InsightsMostConsistentCard(
              label: mostConsistent?.label ?? 'No doses yet',
              rate: mostConsistent?.rate ?? 0,
              expected: mostConsistent?.expected ?? 0,
            );
            final pair = constraints.maxWidth < 420
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      streakCard,
                      const SizedBox(height: 12),
                      consistentCard,
                    ],
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: streakCard),
                      const SizedBox(width: 12),
                      Expanded(child: consistentCard),
                    ],
                  );
            return DoselyFadeIn(
              delay: const Duration(milliseconds: 40),
              child: pair,
            );
          },
        ),
        const SizedBox(height: 16),
        DoselyFadeIn(
          delay: const Duration(milliseconds: 80),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AmbientCard(
                child: Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: Theme.of(
                        context,
                      ).colorScheme.errorContainer,
                      foregroundColor: Theme.of(
                        context,
                      ).colorScheme.onErrorContainer,
                      child: const Icon(Icons.warning_amber_rounded),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Unanswered doses',
                            style: Theme.of(context).textTheme.labelLarge
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                          ),
                          Text(
                            '$missed',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          Text(
                            'This week',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
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
                            style: Theme.of(context).textTheme.labelLarge
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                          ),
                          Text(
                            '${week.taken}',
                            style: Theme.of(context).textTheme.titleLarge,
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
                      foregroundColor: Theme.of(
                        context,
                      ).colorScheme.onSurfaceVariant,
                      child: const Icon(Icons.info_outline),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Observation',
                            style: Theme.of(context).textTheme.labelLarge
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
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
    required DoseRecordIndex index,
    required List<ScheduleWithMedicine> items,
    required DateTime now,
    required DayPart part,
    required Duration snoozeWindow,
  }) {
    // Re-walk the week for this part only — cheap, and keeps scoring
    // identical to occurrencesOnDay.
    var taken = 0;
    var expected = 0;
    for (final day in days) {
      final occs = occurrencesOnDay(
        items: items,
        index: index,
        day: day.day,
        now: now,
        snoozeWindow: snoozeWindow,
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
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 40),
              child: AnimatedContainer(
                duration: DoselyMotion.duration(context, DoselyMotion.slow),
                curve: DoselyMotion.decelerate,
                width: double.infinity,
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

/// Half of the streak row. The title used to sit in an unbounded [Row]
/// next to the sun icon, so on a phone it overflowed the card by ~27px.
@visibleForTesting
class InsightsMostConsistentCard extends StatelessWidget {
  const InsightsMostConsistentCard({
    super.key,
    required this.label,
    required this.rate,
    required this.expected,
  });

  final String label;
  final double rate;
  final int expected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: double.infinity,
      child: AmbientCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.wb_sunny_outlined, color: scheme.tertiary, size: 18),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Most consistent',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: DoselyAnimatedValue(
                value: rate,
                builder: (context, value) => LinearProgressIndicator(
                  value: value,
                  minHeight: 8,
                  color: scheme.tertiary,
                  backgroundColor: scheme.surfaceContainerHigh,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                expected == 0
                    ? 'No scheduled doses'
                    : '${(rate * 100).round()}% taken',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
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
      width: double.infinity,
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
                  style: Theme.of(
                    context,
                  ).textTheme.headlineSmall?.copyWith(color: scheme.onPrimary),
                ),
                TextSpan(
                  text: ' $unit',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyLarge?.copyWith(color: scheme.onPrimary),
                ),
              ],
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
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
