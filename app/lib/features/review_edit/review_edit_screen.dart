import 'dart:async';

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/ids.dart';
import '../../core/motion.dart';
import '../../core/telemetry.dart';
import '../../core/widgets/medicyn_layout.dart';
import '../../core/widgets/medicyn_motion.dart';
import '../../data/local/database.dart';
import '../../data/local/lifecycle.dart';
import '../../data/local/tables.dart';
import '../../data/remote/care_notifier.dart';
import '../../data/remote/medicine_parser.dart';
import '../../data/remote/sync_service.dart';
import '../auth/auth_service.dart';
import '../care/care_remote_refresh.dart';
import '../care/care_service.dart';
import '../care/change_history_screen.dart';
import '../consent/consent_purpose.dart';
import '../consent/consent_service.dart';
import '../history/dose_history_screen.dart';
import '../notification_engine/notification_service.dart';
import '../notification_engine/schedule_validation.dart';
import '../reminders_home/refill.dart';
import 'parsed_medicine.dart';

/// The one gate everything else in the capture flow passes through: nothing
/// gets a reminder scheduled or saved anywhere without the user seeing and
/// confirming it here first, whether the fields came from AI parsing, were
/// typed by hand after a parse failure, or are being edited after the fact.
///
/// Two modes, same form: pass [ocrText]/[transcript] to parse a fresh
/// capture, or pass [existing] to edit an already-saved reminder (skips
/// parsing entirely and prefills from the current values). Saving always
/// upserts by ID, so the edit path updates in place rather than creating a
/// duplicate.
class ReviewEditScreen extends StatefulWidget {
  const ReviewEditScreen({
    super.key,
    this.ocrText = '',
    this.transcript = '',
    this.existing,
    required this.db,
    this.forPatientId,
  });

  final String ocrText;
  final String transcript;
  final ScheduleWithMedicine? existing;
  final AppDatabase db;

  /// When set to someone other than the signed-in user, save writes to
  /// Supabase under that id and does not arm alarms on this phone. Scan and
  /// voice are skipped — those would send the patient's label under the
  /// caregiver's Anthropic consent.
  final String? forPatientId;

  @override
  State<ReviewEditScreen> createState() => _ReviewEditScreenState();
}

enum _LoadState { loading, ready, failed }

class _ReviewEditScreenState extends State<ReviewEditScreen> {
  _LoadState _loadState = _LoadState.loading;
  String? _parseError;
  double? _confidence;

  final _drugNameController = TextEditingController();
  final _strengthController = TextEditingController();
  final _formController = TextEditingController();
  final _doseAmountController = TextEditingController();
  final _remainingController = TextEditingController();
  final _perDoseController = TextEditingController();
  final _notesController = TextEditingController();
  final _intervalController = TextEditingController(text: '8');

  FrequencyType _frequency = FrequencyType.daily;
  List<String> _times = [];
  final Set<int> _daysOfWeek = {};
  bool _saving = false;
  bool _drugNameFilled = false;

  static const _dayLabels = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

  bool get _isEditing => widget.existing != null;

  bool get _forSomeoneElse {
    final them = widget.forPatientId;
    final me = AuthService.instance.currentUser?.id;
    return them != null && me != null && them != me;
  }

  @override
  void initState() {
    super.initState();
    // _canSave reads the medicine-name field directly, but a TextField's own
    // keystrokes don't rebuild anything. Without this the Save button stays
    // disabled after the user types the one required field, until some other
    // control happens to call setState — which is exactly the path someone
    // takes after "Fill in manually".
    _drugNameController.addListener(_onDrugNameChanged);
    _load();
  }

  /// Rebuilds only when the field crosses between empty and non-empty, which
  /// is the only transition [_canSave] cares about — not on every keystroke.
  void _onDrugNameChanged() {
    final filled = _drugNameController.text.trim().isNotEmpty;
    if (filled == _drugNameFilled) return;
    _drugNameFilled = filled;
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _drugNameController.removeListener(_onDrugNameChanged);
    _drugNameController.dispose();
    _strengthController.dispose();
    _formController.dispose();
    _doseAmountController.dispose();
    _remainingController.dispose();
    _perDoseController.dispose();
    _notesController.dispose();
    _intervalController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (_isEditing) {
      // Caregiver-editing-a-patient's-reminder skips this: patientReminders
      // does not select the stock columns at all yet (a separate, already
      // fixed fix waiting to land), so medicine.tabletsRemaining is always
      // null on that path today and there is nothing to derive.
      final takenSinceBaseline = _forSomeoneElse
          ? 0
          : await widget.db.takenCountSince(
              widget.existing!.schedule.id,
              widget.existing!.medicine.updatedAt,
            );
      _applyExisting(widget.existing!, takenSinceBaseline);
      setState(() => _loadState = _LoadState.ready);
      return;
    }
    if (_forSomeoneElse ||
        !shouldParseMedicine(
          anthropicGranted: ConsentService.instance.isGranted(
            ConsentPurpose.anthropicParse,
          ),
          ocrText: widget.ocrText,
          transcript: widget.transcript,
        )) {
      // Empty capture, Anthropic not granted, or editing someone else's
      // record — same empty/manual form, and parse-medicine is never called.
      setState(() => _loadState = _LoadState.ready);
      return;
    }
    try {
      final parsed = await MedicineParser().parse(
        ocrText: widget.ocrText,
        transcript: widget.transcript,
      );
      _applyParsed(parsed);
      setState(() {
        _loadState = _LoadState.ready;
        _parseError = null;
      });
    } on MedicineParseException catch (e) {
      setState(() {
        _loadState = _LoadState.failed;
        _parseError = e.message;
      });
    } catch (_) {
      setState(() {
        _loadState = _LoadState.failed;
        _parseError = null;
      });
    }
  }

  void _applyParsed(ParsedMedicine p) {
    _drugNameController.text = p.drugName;
    _strengthController.text = p.strength;
    _formController.text = p.form;
    _doseAmountController.text = p.doseAmount;
    _notesController.text = p.notes;
    _frequency = p.frequencyType;
    _times = schedulableTimes(p.times).map((t) => t.label).toList();
    // ParsedMedicine already filtered these; the form keeps its own state in
    // range so that a day it cannot draw a chip for can never be held.
    _daysOfWeek
      ..clear()
      ..addAll(schedulableDays(p.daysOfWeek));
    if (p.intervalHours != null) {
      _intervalController.text = '${p.intervalHours}';
    }
    _confidence = p.confidence;
  }

  void _applyExisting(ScheduleWithMedicine sm, int takenSinceBaseline) {
    final medicine = sm.medicine;
    final schedule = sm.schedule;
    _drugNameController.text = medicine.drugName;
    _strengthController.text = medicine.strength;
    _formController.text = medicine.form;
    _doseAmountController.text = medicine.doseAmount;
    _notesController.text = medicine.notes;
    // Derived, not the raw stored baseline: every save re-baselines the count
    // to whatever is shown here, so an edit that never touches this field
    // (renaming the drug, say) must still write back the current count, not
    // the stale one from whenever the baseline was last set.
    final derived = derivedTabletsRemaining(medicine, takenSinceBaseline);
    if (derived != null) {
      _remainingController.text = '$derived';
    }
    if (medicine.tabletsPerDose != null) {
      _perDoseController.text = '${medicine.tabletsPerDose}';
    }
    // A row saved before these fields were validated can still be sitting in
    // the database, and `byName` throws rather than defaulting. Clean it on
    // the way into the form so editing a poisoned reminder is how it gets
    // fixed, not another way to crash.
    _frequency =
        frequencyTypeFromName(schedule.frequencyType) ?? FrequencyType.daily;
    _times = schedulableTimes(schedule.times).map((t) => t.label).toList();
    _daysOfWeek
      ..clear()
      ..addAll(schedulableDays(schedule.daysOfWeek));
    if (schedule.intervalHours != null) {
      _intervalController.text = '${schedule.intervalHours}';
    }
    // No AI parse happened, so there's no confidence score to show.
    _confidence = null;
  }

  void _continueManually() => setState(() => _loadState = _LoadState.ready);

  void _viewHistory() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DoseHistoryScreen(
          scheduleId: widget.existing!.schedule.id,
          db: widget.db,
        ),
      ),
    );
  }

  void _viewChangeHistory() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            ChangeHistoryScreen(medicineId: widget.existing!.medicine.id),
      ),
    );
  }

  Future<void> _changeLifecycle(
    ReminderStatus target, {
    DateTime? pauseUntil,
  }) async {
    if (_forSomeoneElse || widget.existing == null) return;
    final schedule = widget.existing!.schedule;
    final by = AuthService.instance.currentUser?.id;
    try {
      if (target == ReminderStatus.paused) {
        await widget.db.pauseSchedule(schedule.id, until: pauseUntil, by: by);
        await NotificationService.instance.cancelForSchedule(schedule);
      } else if (target == ReminderStatus.completed) {
        await widget.db.completeSchedule(schedule.id, by: by);
        await NotificationService.instance.cancelForSchedule(schedule);
      } else if (target == ReminderStatus.active) {
        await widget.db.resumeSchedule(schedule.id, by: by);
        final refreshed = await widget.db.schedulesWithMedicinesOnce(
          activeOnly: true,
        );
        final item = refreshed.where((x) => x.schedule.id == schedule.id);
        if (item.isNotEmpty) {
          await NotificationService.instance.scheduleForScheduleWithMedicine(
            item.first,
          );
        }
      }
      unawaited(SyncService(widget.db).syncAll());
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not update this reminder.')),
        );
      }
    }
  }

  Future<void> _pauseWithChoice() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              title: Text('Pause reminder'),
              subtitle: Text('You can resume it any time.'),
            ),
            ListTile(
              leading: const Icon(Icons.today_outlined),
              title: const Text('Until tomorrow'),
              onTap: () => Navigator.pop(sheetContext, 'tomorrow'),
            ),
            ListTile(
              leading: const Icon(Icons.date_range_outlined),
              title: const Text('For one week'),
              onTap: () => Navigator.pop(sheetContext, 'week'),
            ),
            ListTile(
              leading: const Icon(Icons.pause_circle_outline),
              title: const Text('Indefinitely'),
              onTap: () => Navigator.pop(sheetContext, 'forever'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;
    final now = DateTime.now();
    final until = switch (choice) {
      'tomorrow' => DateTime(now.year, now.month, now.day + 1),
      'week' => now.add(const Duration(days: 7)),
      _ => null,
    };
    await _changeLifecycle(ReminderStatus.paused, pauseUntil: until);
  }

  Future<void> _addTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (picked == null) return;
    final formatted =
        '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
    setState(() {
      if (_frequency == FrequencyType.everyXHours) {
        _times = [formatted];
      } else if (!_times.contains(formatted)) {
        _times = [..._times, formatted]..sort();
      }
    });
  }

  /// Why the interval field is unusable, or null when it is fine.
  ///
  /// Only meaningful for every-X-hours; any other frequency ignores the
  /// column entirely.
  String? get _intervalError {
    if (_frequency != FrequencyType.everyXHours) return null;
    final raw = _intervalController.text.trim();
    if (raw.isEmpty) return null; // falls back to the 8-hour default
    final parsed = int.tryParse(raw);
    if (parsed == null) return 'Enter a number of hours';
    if (schedulableIntervalHours(parsed) == null) {
      return 'Must be between 1 and 24 hours';
    }
    return null;
  }

  /// The interval the user typed, or null for "not set, use the default".
  int? get _enteredIntervalHours {
    final parsed = int.tryParse(_intervalController.text.trim());
    if (parsed == null) return null;
    return schedulableIntervalHours(parsed) == null ? null : parsed;
  }

  int? _enteredRemaining() {
    final raw = _remainingController.text.trim();
    if (raw.isEmpty) return null;
    return int.tryParse(raw);
  }

  int? _enteredPerDose() {
    final raw = _perDoseController.text.trim();
    if (raw.isEmpty) return null;
    final parsed = int.tryParse(raw);
    if (parsed == null || parsed < 1) return null;
    return parsed;
  }

  bool get _canSave {
    if (_drugNameController.text.trim().isEmpty) return false;
    if (_frequency == FrequencyType.asNeeded) return true;
    if (_times.isEmpty) return false;
    if (_frequency == FrequencyType.specificDays && _daysOfWeek.isEmpty) {
      return false;
    }
    if (_intervalError != null) return false;
    return true;
  }

  /// The lifecycle value must follow a frequency change. In particular, an
  /// as-needed reminder edited into a scheduled reminder must become active;
  /// carrying `asNeeded` into the saved schedule makes the scheduler ignore
  /// every time slot.
  ReminderStatus get _effectiveStatus {
    if (_frequency == FrequencyType.asNeeded) {
      return ReminderStatus.asNeeded;
    }
    if (!_isEditing) return ReminderStatus.active;
    final current = reminderStatus(widget.existing!.schedule);
    return current == ReminderStatus.asNeeded ? ReminderStatus.active : current;
  }

  Future<void> _save() async {
    if (!_forSomeoneElse && _frequency != FrequencyType.asNeeded) {
      await _prepareReminderAccess();
      if (!mounted) return;
    }
    setState(() => _saving = true);
    try {
      if (_forSomeoneElse) {
        await _saveRemote();
      } else {
        await _saveLocal();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e is UnschedulableSchedule
                ? 'This reminder needs a valid frequency, time, or interval.'
                : 'Could not save this reminder. Check the details and try again.',
          ),
        ),
      );
    }
  }

  /// Explains Android's reminder permissions at the moment they matter: when
  /// the user saves their first scheduled reminder. Declining never discards
  /// the medicine; the schedule is saved and the reliability center explains
  /// the degraded state with an inexact fallback or a fix action.
  Future<void> _prepareReminderAccess() async {
    final permission = await NotificationService.instance.readPermissionState();
    if (permission.notificationsAllowed && permission.exactAlarmsAllowed) {
      return;
    }
    await MedicynTelemetry.instance.record(
      MedicynEvent.permissionPrompted,
      properties: {'permission_type': 'reminder_access'},
    );
    if (!mounted) return;
    final proceed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Enable this reminder'),
        content: const Text(
          'Medicyn needs notification access to alert you. Exact timing is '
          'optional; if you skip it, Android may deliver the reminder a little later.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    if (proceed != true) return;
    if (!permission.notificationsAllowed) {
      await NotificationService.instance.requestNotificationPermission();
    }
    if (!permission.exactAlarmsAllowed) {
      await NotificationService.instance.requestExactAlarmPermission();
    }
    final after = await NotificationService.instance.readPermissionState();
    await MedicynTelemetry.instance.record(
      MedicynEvent.permissionResult,
      properties: {
        'permission_type': 'reminder_access',
        'result': after.notificationsAllowed
            ? 'notifications_granted'
            : 'notifications_denied',
      },
    );
  }

  Future<void> _saveRemote() async {
    final patientId = widget.forPatientId!;
    final medicineId = _isEditing ? widget.existing!.medicine.id : newUuid();
    final scheduleId = _isEditing ? widget.existing!.schedule.id : newUuid();
    final savedAt = DateTime.now();
    await CareService.instance.savePatientReminder(
      patientId: patientId,
      medicineId: medicineId,
      scheduleId: scheduleId,
      drugName: _drugNameController.text.trim(),
      strength: _strengthController.text.trim(),
      form: _formController.text.trim(),
      doseAmount: _doseAmountController.text.trim(),
      tabletsRemaining: _enteredRemaining(),
      tabletsPerDose: _enteredPerDose(),
      notes: _notesController.text.trim(),
      frequencyType: _frequency.name,
      times: _times,
      daysOfWeek: _frequency == FrequencyType.specificDays
          ? (_daysOfWeek.toList()..sort())
          : const [],
      intervalHours: _frequency == FrequencyType.everyXHours
          ? _enteredIntervalHours
          : null,
      status: _effectiveStatus.name,
      startDate: widget.existing?.schedule.startDate,
      endDate: widget.existing?.schedule.endDate,
      pauseUntil: widget.existing?.schedule.pauseUntil,
      savedAt: savedAt,
      medicineCreatedAt: widget.existing?.medicine.createdAt,
      scheduleCreatedAt: widget.existing?.schedule.createdAt,
    );
    unawaited(CareNotifier.instance.dataChanged());
    CareRemoteRefresh.instance.ping();
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  Future<void> _saveLocal() async {
    final medicineId = _isEditing ? widget.existing!.medicine.id : newUuid();
    final scheduleId = _isEditing ? widget.existing!.schedule.id : newUuid();
    // One timestamp for both rows, so a medicine and its schedule saved
    // together can never end up on opposite sides of a version comparison.
    final savedAt = DateTime.now();
    final savedBy = AuthService.instance.currentUser?.id;

    await widget.db.upsertMedicine(
      MedicinesCompanion.insert(
        id: medicineId,
        drugName: _drugNameController.text.trim(),
        strength: Value(_strengthController.text.trim()),
        form: Value(_formController.text.trim()),
        doseAmount: Value(_doseAmountController.text.trim()),
        notes: Value(_notesController.text.trim()),
        tabletsRemaining: Value(_enteredRemaining()),
        tabletsPerDose: Value(_enteredPerDose()),
        // insertOnConflictUpdate only touches columns present here — without
        // this, editing an already-synced medicine would silently leave
        // pendingSync at its old (false) value and the edit would never sync.
        pendingSync: const Value(true),
        // Absent on an edit, same as before: insertOnConflictUpdate then
        // leaves the existing createdAt alone rather than overwriting it with
        // now. Explicit on a genuine create, rather than leaning on the
        // column's own default.
        createdAt: _isEditing ? const Value.absent() : Value(savedAt),
        updatedAt: Value(savedAt),
        updatedBy: Value(savedBy),
      ),
    );

    final schedule = Schedule(
      id: scheduleId,
      medicineId: medicineId,
      frequencyType: _frequency.name,
      times: _times,
      daysOfWeek: _frequency == FrequencyType.specificDays
          ? (_daysOfWeek.toList()..sort())
          : const [],
      // An empty field still means "use the default", as before. A value
      // that is present but out of range cannot reach here — _canSave
      // blocks it — and is mapped to null rather than trusted if it ever
      // does.
      intervalHours: _frequency == FrequencyType.everyXHours
          ? _enteredIntervalHours
          : null,
      status: _effectiveStatus.name,
      startDate: widget.existing?.schedule.startDate,
      endDate: widget.existing?.schedule.endDate,
      pauseUntil: widget.existing?.schedule.pauseUntil,
      active:
          widget.existing?.schedule.status == ReminderStatus.paused.name ||
              widget.existing?.schedule.status == ReminderStatus.completed.name
          ? false
          : true,
      createdAt: DateTime.now(),
      updatedAt: savedAt,
      updatedBy: savedBy,
      pendingSync: true,
      deleted: false,
    );
    await widget.db.upsertSchedule(
      SchedulesCompanion.insert(
        id: scheduleId,
        medicineId: medicineId,
        frequencyType: _frequency.name,
        times: _times,
        daysOfWeek: Value(schedule.daysOfWeek),
        intervalHours: Value(schedule.intervalHours),
        status: Value(schedule.status),
        startDate: Value(schedule.startDate),
        endDate: Value(schedule.endDate),
        pauseUntil: Value(schedule.pauseUntil),
        // Same reasoning as the medicine upsert above — force it dirty so an
        // edit to an already-synced schedule actually gets pushed.
        pendingSync: const Value(true),
        // See the medicine upsert above: absent preserves createdAt on an
        // edit, explicit on a create.
        createdAt: _isEditing ? const Value.absent() : Value(savedAt),
        updatedAt: Value(savedAt),
        updatedBy: Value(savedBy),
      ),
    );

    final medicine = await widget.db.medicineById(medicineId);
    if (medicine != null) {
      try {
        await NotificationService.instance.scheduleForScheduleWithMedicine(
          ScheduleWithMedicine(schedule, medicine),
        );
      } catch (e) {
        // The reminder is saved either way; a scheduling failure (e.g. the
        // Android 12+ exact-alarm permission was revoked) shouldn't block
        // the save or strand the spinner — surface it and move on.
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Saved, but the reminder could not be armed. Check Reminder reliability in Settings.',
              ),
            ),
          );
        }
      }
    }
    // Fire-and-forget: sync is backup/multi-device only, never the source
    // of truth for the reminder itself (see SyncService's docs), so it
    // must not hold the Save button hostage to network conditions —
    // retries with backoff inside the client can otherwise take upwards
    // of 10+ seconds per row before this UI-blocking await gives up.
    unawaited(() async {
      final sync = SyncService(widget.db);
      await sync.syncAll();
      if (sync.pushedEdits) {
        await CareNotifier.instance.dataChanged();
      }
    }());

    if (!mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        // Keep the fixed app bar visually separate from the form while the
        // user scrolls. Without this, a wrapped chip row can appear to run
        // underneath the title bar when the form is positioned mid-scroll.
        scrolledUnderElevation: 2,
        title: Text(
          _isEditing
              ? 'Edit reminder'
              : _forSomeoneElse
              ? 'Add a reminder'
              : 'Review reminder',
        ),
      ),
      body: SafeArea(child: MedicynContent(child: _body())),
    );
  }

  Widget _body() {
    return MedicynSwitcher(
      alignment: Alignment.topCenter,
      duration: MedicynMotion.medium,
      child: switch (_loadState) {
        _LoadState.loading => const Center(
          key: ValueKey(_LoadState.loading),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Reading the label and transcript…'),
            ],
          ),
        ),
        _LoadState.failed => Center(
          key: const ValueKey(_LoadState.failed),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_parseError ?? 'Could not understand that automatically.'),
                const SizedBox(height: 16),
                FilledButton(onPressed: _load, child: const Text('Try again')),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: _continueManually,
                  child: const Text('Fill in manually'),
                ),
              ],
            ),
          ),
        ),
        _LoadState.ready => MedicynFadeIn(
          key: const ValueKey(_LoadState.ready),
          child: Column(
            children: [
              Expanded(child: _form()),
              Material(
                elevation: 8,
                color: Theme.of(context).colorScheme.surface,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                  child: FilledButton(
                    onPressed: _canSave && !_saving ? _save : null,
                    child: MedicynSwitcher(
                      child: _saving
                          ? const SizedBox(
                              key: ValueKey(true),
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(
                              _isEditing ? 'Save changes' : 'Save reminder',
                              key: const ValueKey(false),
                            ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      },
    );
  }

  Widget _fieldPair(Widget left, Widget right) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 360) {
          return Column(children: [left, const SizedBox(height: 12), right]);
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: left),
            const SizedBox(width: 12),
            Expanded(child: right),
          ],
        );
      },
    );
  }

  Widget _form() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        if (_forSomeoneElse)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text(
              'This saves on their account. Their phone will re-arm the alarm. '
              'Fill it in by hand — scan and voice stay on their phone.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        if (_confidence != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text(
              'AI read this with ${(_confidence! * 100).round()}% confidence — check it over.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        TextField(
          controller: _drugNameController,
          decoration: const InputDecoration(labelText: 'Medicine name *'),
        ),
        const SizedBox(height: 12),
        _fieldPair(
          TextField(
            controller: _strengthController,
            decoration: const InputDecoration(
              labelText: 'Strength (e.g. 500mg)',
            ),
          ),
          TextField(
            controller: _formController,
            decoration: const InputDecoration(
              labelText: 'Form (tablet, syrup…)',
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _doseAmountController,
          decoration: const InputDecoration(
            labelText: 'Dose amount (e.g. 1 tablet)',
          ),
        ),
        const SizedBox(height: 12),
        _fieldPair(
          TextField(
            controller: _remainingController,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: 'Tablets left',
              helperText: 'Leave blank to skip',
            ),
          ),
          TextField(
            controller: _perDoseController,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: 'Tablets per dose',
              helperText: 'Defaults to 1',
            ),
          ),
        ),
        const SizedBox(height: 20),
        Text('Frequency', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final option in FrequencyType.values)
              ChoiceChip(
                label: Text(switch (option) {
                  FrequencyType.daily => 'Daily',
                  FrequencyType.specificDays => 'Some days',
                  FrequencyType.everyXHours => 'Every X hrs',
                  FrequencyType.asNeeded => 'As needed',
                }),
                selected: _frequency == option,
                onSelected: (_) => setState(() => _frequency = option),
              ),
          ],
        ),
        const SizedBox(height: 16),
        if (_frequency == FrequencyType.specificDays) ...[
          Wrap(
            spacing: 8,
            children: List.generate(7, (i) {
              final selected = _daysOfWeek.contains(i);
              return FilterChip(
                label: Text(_dayLabels[i]),
                selected: selected,
                onSelected: (v) => setState(
                  () => v ? _daysOfWeek.add(i) : _daysOfWeek.remove(i),
                ),
              );
            }),
          ),
          const SizedBox(height: 16),
        ],
        if (_frequency == FrequencyType.everyXHours) ...[
          TextField(
            controller: _intervalController,
            keyboardType: TextInputType.number,
            // Digits only, so a stray character cannot reach int.tryParse and
            // arrive as a null interval. The range is checked separately —
            // formatters cannot express "not zero".
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: 'Every how many hours?',
              // Typing 0 here used to be enough to leave the phone with no
              // medication alarms at all, so say why it is refused rather
              // than just disabling Save with no explanation.
              errorText: _intervalError,
            ),
          ),
          const SizedBox(height: 16),
        ],
        if (_frequency != FrequencyType.asNeeded) ...[
          Text(
            _frequency == FrequencyType.everyXHours
                ? 'First dose time'
                : 'Times',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final t in _times)
                Chip(
                  label: Text(t),
                  onDeleted: () => setState(
                    () => _times = _times.where((x) => x != t).toList(),
                  ),
                ),
              ActionChip(
                avatar: const Icon(Icons.add, size: 18),
                label: const Text('Add time'),
                onPressed: _addTime,
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],
        TextField(
          controller: _notesController,
          maxLines: 2,
          decoration: const InputDecoration(
            labelText: 'Instructions (optional)',
          ),
        ),
        if (_isEditing) ...[
          const SizedBox(height: 20),
          const Divider(),
          const SizedBox(height: 8),
          if (!_forSomeoneElse) _lifecycleActions(),
          if (!_forSomeoneElse) const SizedBox(height: 8),
          if (!_forSomeoneElse)
            OutlinedButton.icon(
              onPressed: _viewHistory,
              icon: const Icon(Icons.history),
              label: const Text('View dose history'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
            ),
          if (AuthService.instance.currentUser != null) ...[
            if (!_forSomeoneElse) const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _viewChangeHistory,
              icon: const Icon(Icons.edit_note),
              label: const Text('What changed'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
            ),
          ],
        ],
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _lifecycleActions() {
    final status = _effectiveStatus;
    final label = switch (status) {
      ReminderStatus.active => 'Active',
      ReminderStatus.paused => 'Paused',
      ReminderStatus.completed => 'Completed',
      ReminderStatus.asNeeded => 'As needed',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Reminder status: $label'),
        const SizedBox(height: 8),
        if (status == ReminderStatus.active) ...[
          _lifecycleButton(
            onPressed: _pauseWithChoice,
            icon: Icons.pause_circle_outline,
            label: 'Pause reminder',
          ),
          const SizedBox(height: 8),
          _lifecycleButton(
            onPressed: () => _changeLifecycle(ReminderStatus.completed),
            icon: Icons.check_circle_outline,
            label: 'Mark course complete',
          ),
        ] else if (status == ReminderStatus.paused) ...[
          _lifecycleButton(
            onPressed: () => _changeLifecycle(ReminderStatus.active),
            icon: Icons.play_arrow,
            label: 'Resume reminder',
            filled: true,
          ),
          const SizedBox(height: 8),
          _lifecycleButton(
            onPressed: () => _changeLifecycle(ReminderStatus.completed),
            icon: Icons.check_circle_outline,
            label: 'Mark course complete',
          ),
        ] else if (status == ReminderStatus.completed) ...[
          _lifecycleButton(
            onPressed: () => _changeLifecycle(ReminderStatus.active),
            icon: Icons.play_arrow,
            label: 'Restart reminder',
            filled: true,
          ),
        ],
      ],
    );
  }

  Widget _lifecycleButton({
    required VoidCallback onPressed,
    required IconData icon,
    required String label,
    bool filled = false,
  }) {
    final child = filled
        ? FilledButton.icon(
            onPressed: onPressed,
            icon: Icon(icon),
            label: Text(label),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
          )
        : OutlinedButton.icon(
            onPressed: onPressed,
            icon: Icon(icon),
            label: Text(label),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
          );
    return child;
  }
}
