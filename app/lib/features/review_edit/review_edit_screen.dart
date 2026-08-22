import 'dart:async';

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/ids.dart';
import '../../data/local/database.dart';
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
      _applyExisting(widget.existing!);
      setState(() => _loadState = _LoadState.ready);
      return;
    }
    if (_forSomeoneElse ||
        !shouldParseMedicine(
      anthropicGranted: ConsentService.instance.isGranted(ConsentPurpose.anthropicParse),
      ocrText: widget.ocrText,
      transcript: widget.transcript,
    )) {
      // Empty capture, Anthropic not granted, or editing someone else's
      // record — same empty/manual form, and parse-medicine is never called.
      setState(() => _loadState = _LoadState.ready);
      return;
    }
    try {
      final parsed = await MedicineParser().parse(ocrText: widget.ocrText, transcript: widget.transcript);
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
    if (p.intervalHours != null) _intervalController.text = '${p.intervalHours}';
    _confidence = p.confidence;
  }

  void _applyExisting(ScheduleWithMedicine sm) {
    final medicine = sm.medicine;
    final schedule = sm.schedule;
    _drugNameController.text = medicine.drugName;
    _strengthController.text = medicine.strength;
    _formController.text = medicine.form;
    _doseAmountController.text = medicine.doseAmount;
    _notesController.text = medicine.notes;
    if (medicine.tabletsRemaining != null) {
      _remainingController.text = '${medicine.tabletsRemaining}';
    }
    if (medicine.tabletsPerDose != null) {
      _perDoseController.text = '${medicine.tabletsPerDose}';
    }
    // A row saved before these fields were validated can still be sitting in
    // the database, and `byName` throws rather than defaulting. Clean it on
    // the way into the form so editing a poisoned reminder is how it gets
    // fixed, not another way to crash.
    _frequency = frequencyTypeFromName(schedule.frequencyType) ?? FrequencyType.daily;
    _times = schedulableTimes(schedule.times).map((t) => t.label).toList();
    _daysOfWeek
      ..clear()
      ..addAll(schedulableDays(schedule.daysOfWeek));
    if (schedule.intervalHours != null) _intervalController.text = '${schedule.intervalHours}';
    // No AI parse happened, so there's no confidence score to show.
    _confidence = null;
  }

  void _continueManually() => setState(() => _loadState = _LoadState.ready);

  void _viewHistory() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DoseHistoryScreen(scheduleId: widget.existing!.schedule.id, db: widget.db),
      ),
    );
  }

  void _viewChangeHistory() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChangeHistoryScreen(medicineId: widget.existing!.medicine.id),
      ),
    );
  }

  Future<void> _addTime() async {
    final picked = await showTimePicker(context: context, initialTime: TimeOfDay.now());
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
    if (schedulableIntervalHours(parsed) == null) return 'Must be between 1 and 24 hours';
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
    if (_frequency == FrequencyType.specificDays && _daysOfWeek.isEmpty) return false;
    if (_intervalError != null) return false;
    return true;
  }

  Future<void> _save() async {
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
        SnackBar(content: Text('Could not save: $e')),
      );
    }
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
      daysOfWeek: _frequency == FrequencyType.specificDays ? (_daysOfWeek.toList()..sort()) : const [],
      intervalHours: _frequency == FrequencyType.everyXHours ? _enteredIntervalHours : null,
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

      await widget.db.upsertMedicine(MedicinesCompanion.insert(
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
        updatedAt: Value(savedAt),
        updatedBy: Value(savedBy),
      ));

      final schedule = Schedule(
        id: scheduleId,
        medicineId: medicineId,
        frequencyType: _frequency.name,
        times: _times,
        daysOfWeek: _frequency == FrequencyType.specificDays ? (_daysOfWeek.toList()..sort()) : const [],
        // An empty field still means "use the default", as before. A value
        // that is present but out of range cannot reach here — _canSave
        // blocks it — and is mapped to null rather than trusted if it ever
        // does.
        intervalHours: _frequency == FrequencyType.everyXHours
            ? _enteredIntervalHours
            : null,
        active: true,
        createdAt: DateTime.now(),
        updatedAt: savedAt,
        updatedBy: savedBy,
        pendingSync: true,
        deleted: false,
      );
      await widget.db.upsertSchedule(SchedulesCompanion.insert(
        id: scheduleId,
        medicineId: medicineId,
        frequencyType: _frequency.name,
        times: _times,
        daysOfWeek: Value(schedule.daysOfWeek),
        intervalHours: Value(schedule.intervalHours),
        // Same reasoning as the medicine upsert above — force it dirty so an
        // edit to an already-synced schedule actually gets pushed.
        pendingSync: const Value(true),
        updatedAt: Value(savedAt),
        updatedBy: Value(savedBy),
      ));

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
              SnackBar(content: Text('Saved, but the alarm could not be scheduled: $e')),
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
        title: Text(
          _isEditing
              ? 'Edit reminder'
              : _forSomeoneElse
                  ? 'Add a reminder'
                  : 'Review reminder',
        ),
      ),
      body: SafeArea(child: _body()),
    );
  }

  Widget _body() {
    switch (_loadState) {
      case _LoadState.loading:
        return const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Reading the label and transcript…'),
            ],
          ),
        );
      case _LoadState.failed:
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_parseError ?? 'Could not understand that automatically.'),
                const SizedBox(height: 16),
                FilledButton(onPressed: _load, child: const Text('Try again')),
                const SizedBox(height: 8),
                OutlinedButton(onPressed: _continueManually, child: const Text('Fill in manually')),
              ],
            ),
          ),
        );
      case _LoadState.ready:
        return Column(
          children: [
            Expanded(child: _form()),
            Material(
              elevation: 8,
              color: Theme.of(context).colorScheme.surface,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                child: FilledButton(
                  onPressed: _canSave && !_saving ? _save : null,
                  child: _saving
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(_isEditing ? 'Save changes' : 'Save reminder'),
                ),
              ),
            ),
          ],
        );
    }
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
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _strengthController,
                decoration: const InputDecoration(labelText: 'Strength (e.g. 500mg)'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _formController,
                decoration: const InputDecoration(labelText: 'Form (tablet, syrup…)'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _doseAmountController,
          decoration: const InputDecoration(labelText: 'Dose amount (e.g. 1 tablet)'),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _remainingController,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'Tablets left',
                  helperText: 'Leave blank to skip',
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _perDoseController,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'Tablets per dose',
                  helperText: 'Defaults to 1',
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Text(
          'Frequency',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.secondary,
          ),
        ),
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
                onSelected: (v) => setState(() => v ? _daysOfWeek.add(i) : _daysOfWeek.remove(i)),
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
            _frequency == FrequencyType.everyXHours ? 'First dose time' : 'Times',
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
                  onDeleted: () => setState(() => _times = _times.where((x) => x != t).toList()),
                ),
              ActionChip(avatar: const Icon(Icons.add, size: 18), label: const Text('Add time'), onPressed: _addTime),
            ],
          ),
          const SizedBox(height: 16),
        ],
        TextField(
          controller: _notesController,
          maxLines: 2,
          decoration: const InputDecoration(labelText: 'Instructions (optional)'),
        ),
        if (_isEditing) ...[
          const SizedBox(height: 20),
          const Divider(),
          const SizedBox(height: 8),
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
}
