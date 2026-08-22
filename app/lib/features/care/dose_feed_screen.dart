import 'package:flutter/material.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../core/app_navigation.dart';
import '../../core/widgets/dosely_layout.dart';
import '../../data/local/database.dart';
import '../../data/local/tables.dart';
import '../auth/auth_service.dart';
import '../reminders_home/day_dose_list.dart';
import '../reminders_home/day_occurrences.dart';
import '../reminders_home/dose_calendar.dart';
import '../notification_engine/expected_doses.dart';
import 'care_service.dart';
import 'phone_dial.dart';

/// Opens [patientId]'s feed from outside the widget tree — a tapped missed-dose
/// notification, whether it arrived as a push (see PushService) or was drawn
/// locally while the app was in the foreground.
///
/// A null navigator (no widget tree yet) makes this a harmless no-op, the same
/// contract [navigatorKey] carries everywhere else.
void openFeedForPatient(String patientId) {
  navigatorKey.currentState?.push(
    MaterialPageRoute(
      builder: (_) =>
          DoseFeedScreen(patientId: patientId, viewingOwnData: false),
    ),
  );
}

/// What actually happened with someone's medicines, newest first.
///
/// This is the payoff of a care link: the thing that lets someone in another
/// city stop wondering, and stop ringing to ask. Both sides see the identical
/// screen — the parent is not shown a lesser version of what their family can
/// see, which is the whole consent model made visible.
///
/// Two deliberate choices about time:
///
///  * Each entry leads with *punctuality* ("4 minutes late"), not a clock
///    time. The gap between when a dose was due and when it was answered is
///    an absolute quantity: it reads the same from Bangalore or Boston, and
///    it is the thing a worried person actually wants to know.
///  * Clock times render in the *patient's* timezone, because that is the
///    reminder they saw. A caregiver in another zone is told so once, at the
///    top, rather than being quietly shown times that never appeared on
///    anyone's phone.
class DoseFeedScreen extends StatefulWidget {
  const DoseFeedScreen({
    super.key,
    required this.patientId,
    required this.viewingOwnData,
  });

  /// Whose dose history to show. Row-level security is what decides whether
  /// anything comes back.
  final String patientId;

  /// True when the signed-in person is looking at their own record.
  final bool viewingOwnData;

  @override
  State<DoseFeedScreen> createState() => _DoseFeedScreenState();
}

class _DoseFeedScreenState extends State<DoseFeedScreen> {
  List<DoseEvent>? _events;
  List<ScheduleWithMedicine> _reminders = const [];
  CareProfile? _profile;
  String? _error;
  String? _callPhone;
  DateTime _selectedDay = calendarDay(DateTime.now());
  bool _choseDay = false;

  /// The patient's zone, resolved once. Falls back to the device's own when
  /// the profile has no usable identifier, which only costs correctness for
  /// a caregiver in a different zone.
  tz.Location? _patientZone;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final profile = await CareService.instance.profile(widget.patientId);
      final events = await CareService.instance.doseFeed(widget.patientId);
      var reminders = const <ScheduleWithMedicine>[];
      try {
        reminders = await CareService.instance.patientReminders(
          widget.patientId,
        );
      } on CareLinkFailure {
        // Feed still works without pending slots — logs are enough to paint
        // taken/missed. Pending would be a guess from the viewer's clock.
      }
      final link = await CareService.instance.currentLink();
      final me = AuthService.instance.currentUser?.id;
      final callPhone = (link != null && me != null)
          ? dialablePhone(link.phoneToCall(me))
          : null;
      if (!mounted) return;
      final zone = _resolveZone(profile?.timezone);
      setState(() {
        _profile = profile;
        _patientZone = zone;
        _events = events;
        _reminders = reminders;
        _callPhone = callPhone;
        _error = null;
        if (!_choseDay) {
          _selectedDay = calendarDay(_nowThere(zone));
        }
      });
    } on CareLinkFailure catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    }
  }

  DateTime _nowThere(tz.Location? zone) {
    if (zone == null) return DateTime.now();
    return tz.TZDateTime.from(DateTime.now(), zone);
  }

  WallClock? _wallClock(tz.Location? zone) {
    if (zone == null) return null;
    return (y, m, d, h, min) => tz.TZDateTime(zone, y, m, d, h, min);
  }

  static tz.Location? _resolveZone(String? identifier) {
    if (identifier == null) return null;
    try {
      return tz.getLocation(identifier);
    } catch (_) {
      // An identifier the timezone database doesn't recognise. Better to
      // fall back to local time than to fail the whole screen over it.
      return null;
    }
  }

  DateTime _inPatientZone(DateTime instant) {
    final zone = _patientZone;
    if (zone == null) return instant.toLocal();
    return tz.TZDateTime.from(instant, zone);
  }

  /// Only worth mentioning when the two people are actually in different
  /// zones — saying it otherwise is noise.
  bool get _zonesDiffer {
    final zone = _patientZone;
    if (zone == null || widget.viewingOwnData) return false;
    final now = DateTime.now();
    return tz.TZDateTime.from(now, zone).timeZoneOffset != now.timeZoneOffset;
  }

  @override
  Widget build(BuildContext context) {
    final who = _profile?.displayName;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.viewingOwnData
              ? 'Your doses'
              : who == null
              ? 'Their doses'
              : "$who's doses",
        ),
        actions: [
          if (_callPhone != null)
            IconButton(
              tooltip: 'Call',
              icon: const Icon(Icons.phone),
              onPressed: () => openDialer(_callPhone!),
            ),
        ],
      ),
      body: SafeArea(
        child: DoselyContent(
          child: RefreshIndicator(onRefresh: _load, child: _body()),
        ),
      ),
    );
  }

  Widget _body() {
    if (_error != null) return _message(_error!, isError: true);
    final events = _events;
    if (events == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final zone = _patientZone;
    final now = _nowThere(zone);
    final clock = _wallClock(zone);
    final records = _doseRecords(events, zone);
    final rangeStart = _civilDate(now, now.year, now.month - 18, 1);
    final rangeEnd = _civilDate(now, now.year, now.month + 6, 1);
    final cellMarks = cellMarksForRange(
      items: _reminders,
      logs: records,
      rangeStart: rangeStart,
      rangeEnd: rangeEnd,
      now: now,
      wallClock: clock,
    );
    final calendarMarks = {
      for (final e in cellMarks.entries)
        DateTime(e.key.year, e.key.month, e.key.day): CalendarDayMarks(
          taken: e.value.hasTaken,
          pending: e.value.hasPending || e.value.hasUpcoming,
          missed: e.value.hasMissed,
          snoozed: e.value.hasSnoozed,
          notRecorded: e.value.hasNotRecorded,
        ),
    };
    final occurrences = occurrencesOnDay(
      items: _reminders,
      logs: records,
      day: _selectedDay,
      now: now,
      wallClock: clock,
    );
    final open = [
      for (final o in occurrences)
        if (o.status == DayDoseStatus.pending ||
            o.status == DayDoseStatus.upcoming ||
            o.status == DayDoseStatus.notRecorded)
          o,
    ];
    final dayEvents = [
      for (final event in events)
        if (isSameCalendarDay(_inPatientZone(event.scheduledAt), _selectedDay))
          event,
    ];
    final adherence = weekAdherence(
      items: _reminders,
      logs: records,
      now: now,
      wallClock: clock,
    );

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 32),
      children: [
        DoseCalendar(
          selectedDay: DateTime(
            _selectedDay.year,
            _selectedDay.month,
            _selectedDay.day,
          ),
          now: DateTime(now.year, now.month, now.day, now.hour, now.minute),
          marks: calendarMarks,
          onSelectDay: (day) => setState(() {
            _selectedDay = zone == null
                ? day
                : tz.TZDateTime(zone, day.year, day.month, day.day);
            _choseDay = true;
          }),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
          child: WeekAdherenceLine(
            taken: adherence.taken,
            expected: adherence.expected,
          ),
        ),
        if (_zonesDiffer) _timezoneNote(),
        DayDoseList(
          day: _selectedDay,
          now: now,
          occurrences: open,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
        ),
        for (final event in dayEvents)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: _DoseEventCard(
              event: event,
              clockTime: _inPatientZone(event.scheduledAt),
              patientId: widget.patientId,
            ),
          ),
      ],
    );
  }

  List<DoseRecord> _doseRecords(List<DoseEvent> events, tz.Location? zone) {
    final out = <DoseRecord>[];
    for (final event in events) {
      final scheduleId = event.scheduleId;
      if (scheduleId == null) continue;
      DoseAction? action;
      for (final value in DoseAction.values) {
        if (value.name == event.action) action = value;
      }
      if (action == null) continue;
      out.add(
        DoseRecord(
          scheduleId: scheduleId,
          scheduledAt: zone == null
              ? event.scheduledAt
              : tz.TZDateTime.from(event.scheduledAt, zone),
          loggedAt: zone == null
              ? event.loggedAt
              : tz.TZDateTime.from(event.loggedAt, zone),
          action: action,
        ),
      );
    }
    return out;
  }

  DateTime _civilDate(DateTime template, int year, int month, int day) {
    if (template is tz.TZDateTime) {
      return tz.TZDateTime(template.location, year, month, day);
    }
    return DateTime(year, month, day);
  }

  Widget _timezoneNote() {
    final who = _profile?.displayName ?? 'They';
    final zone = _profile?.timezone ?? '';
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(
            Icons.schedule,
            size: 18,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '$who is in a different timezone${zone.isEmpty ? '' : ' ($zone)'}. '
              'Times below are theirs — the times their reminders actually went off.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }

  Widget _message(String text, {bool isError = false}) {
    return ListView(
      padding: const EdgeInsets.all(32),
      children: [
        const SizedBox(height: 48),
        Text(
          text,
          textAlign: TextAlign.center,
          style: isError
              ? TextStyle(color: Theme.of(context).colorScheme.error)
              : Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    );
  }
}

class _DoseEventCard extends StatelessWidget {
  const _DoseEventCard({
    required this.event,
    required this.clockTime,
    required this.patientId,
  });

  final DoseEvent event;

  /// [DoseEvent.scheduledAt] rendered in the patient's own zone.
  final DateTime clockTime;

  /// Whose history this card is in — the feed is always for the patient, so
  /// a `recorded_by` that isn't this id is someone else writing their log.
  final String patientId;

  ({IconData icon, Color color, String label}) _visuals(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    switch (event.action) {
      case 'taken':
        return (
          icon: Icons.check_circle,
          color: Colors.green.shade600,
          label: 'Taken',
        );
      case 'snoozed':
        return (
          icon: Icons.snooze,
          color: Colors.orange.shade700,
          label: 'Snoozed',
        );
      case 'missed':
        return (icon: Icons.cancel, color: scheme.error, label: 'Missed');
      default:
        return (
          icon: Icons.help_outline,
          color: scheme.outline,
          label: event.action,
        );
    }
  }

  static String _clock(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final visuals = _visuals(context);
    final text = Theme.of(context).textTheme;
    final punctuality = event.punctuality;
    final attribution = event.attributionNote(patientId);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(visuals.icon, color: visuals.color, size: 32),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    event.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: text.titleMedium,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${visuals.label} · due ${_clock(clockTime)}',
                    style: text.bodyMedium?.copyWith(color: visuals.color),
                  ),
                  if (punctuality != null) ...[
                    const SizedBox(height: 2),
                    Text(punctuality, style: text.bodySmall),
                  ],
                  if (event.doseAmount.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(event.doseAmount, style: text.bodySmall),
                  ],
                  if (attribution != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      attribution,
                      style: text.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
