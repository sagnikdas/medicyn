import 'package:flutter/material.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../core/app_navigation.dart';
import 'care_service.dart';

/// Opens [patientId]'s feed from outside the widget tree — a tapped missed-dose
/// notification, whether it arrived as a push (see PushService) or was drawn
/// locally while the app was in the foreground.
///
/// A null navigator (no widget tree yet) makes this a harmless no-op, the same
/// contract [navigatorKey] carries everywhere else.
void openFeedForPatient(String patientId) {
  navigatorKey.currentState?.push(
    MaterialPageRoute(
      builder: (_) => DoseFeedScreen(patientId: patientId, viewingOwnData: false),
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
  CareProfile? _profile;
  String? _error;

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
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _patientZone = _resolveZone(profile?.timezone);
        _events = events;
        _error = null;
      });
    } on CareLinkFailure catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    }
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
      ),
      body: SafeArea(child: RefreshIndicator(onRefresh: _load, child: _body())),
    );
  }

  Widget _body() {
    if (_error != null) return _message(_error!, isError: true);
    final events = _events;
    if (events == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (events.isEmpty) {
      return _message(
        widget.viewingOwnData
            ? "Nothing yet. Once you start answering reminders, they'll show up here."
            : "Nothing yet. Doses will appear here as they're answered.",
      );
    }

    final groups = _groupByDay(events);
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      itemCount: groups.length + (_zonesDiffer ? 1 : 0),
      itemBuilder: (context, index) {
        if (_zonesDiffer) {
          if (index == 0) return _timezoneNote();
          index -= 1;
        }
        final group = groups[index];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 16, bottom: 8),
              child: Text(
                group.label,
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            for (final event in group.events)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _DoseEventCard(
                  event: event,
                  clockTime: _inPatientZone(event.scheduledAt),
                ),
              ),
          ],
        );
      },
    );
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
          Icon(Icons.schedule, size: 18, color: Theme.of(context).colorScheme.outline),
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

  List<_DayGroup> _groupByDay(List<DoseEvent> events) {
    final groups = <_DayGroup>[];
    for (final event in events) {
      final local = _inPatientZone(event.scheduledAt);
      final key = DateTime(local.year, local.month, local.day);
      if (groups.isNotEmpty && groups.last.date == key) {
        groups.last.events.add(event);
      } else {
        groups.add(_DayGroup(date: key, label: _dayLabel(key), events: [event]));
      }
    }
    return groups;
  }

  String _dayLabel(DateTime day) {
    // "Today" is relative to the patient's day, not the viewer's — otherwise
    // a caregiver several hours ahead sees yesterday's doses under today.
    final nowThere = _inPatientZone(DateTime.now());
    final today = DateTime(nowThere.year, nowThere.month, nowThere.day);
    final difference = today.difference(day).inDays;
    if (difference == 0) return 'Today';
    if (difference == 1) return 'Yesterday';
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    return '${day.day} ${months[day.month - 1]}';
  }
}

class _DayGroup {
  _DayGroup({required this.date, required this.label, required this.events});
  final DateTime date;
  final String label;
  final List<DoseEvent> events;
}

class _DoseEventCard extends StatelessWidget {
  const _DoseEventCard({required this.event, required this.clockTime});

  final DoseEvent event;

  /// [DoseEvent.scheduledAt] rendered in the patient's own zone.
  final DateTime clockTime;

  ({IconData icon, Color color, String label}) _visuals(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    switch (event.action) {
      case 'taken':
        return (icon: Icons.check_circle, color: Colors.green.shade600, label: 'Taken');
      case 'snoozed':
        return (icon: Icons.snooze, color: Colors.orange.shade700, label: 'Snoozed');
      case 'missed':
        return (icon: Icons.cancel, color: scheme.error, label: 'Missed');
      default:
        return (icon: Icons.help_outline, color: scheme.outline, label: event.action);
    }
  }

  static String _clock(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final visuals = _visuals(context);
    final text = Theme.of(context).textTheme;
    final punctuality = event.punctuality;
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
                  Text(event.title, style: text.titleMedium),
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
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
