import 'dart:async';

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';

import '../../core/ids.dart';
import '../../data/local/database.dart';
import '../../data/local/tables.dart';
import '../../data/remote/medicine_parser.dart';
import '../../data/remote/sync_service.dart';
import '../history/dose_history_screen.dart';
import '../notification_engine/notification_service.dart';
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
  });

  final String ocrText;
  final String transcript;
  final ScheduleWithMedicine? existing;
  final AppDatabase db;

  @override
  State<ReviewEditScreen> createState() => _ReviewEditScreenState();
}

enum _LoadState { loading, ready, failed }

class _ReviewEditScreenState extends State<ReviewEditScreen> {
  _LoadState _loadState = _LoadState.loading;
  double? _confidence;

  final _drugNameController = TextEditingController();
  final _strengthController = TextEditingController();
  final _formController = TextEditingController();
  final _doseAmountController = TextEditingController();
  final _notesController = TextEditingController();
  final _intervalController = TextEditingController(text: '8');

  FrequencyType _frequency = FrequencyType.daily;
  List<String> _times = [];
  final Set<int> _daysOfWeek = {};
  bool _saving = false;

  static const _dayLabels = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _drugNameController.dispose();
    _strengthController.dispose();
    _formController.dispose();
    _doseAmountController.dispose();
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
    if (widget.ocrText.isEmpty && widget.transcript.isEmpty) {
      setState(() => _loadState = _LoadState.ready);
      return;
    }
    try {
      final parsed = await MedicineParser().parse(ocrText: widget.ocrText, transcript: widget.transcript);
      _applyParsed(parsed);
      setState(() => _loadState = _LoadState.ready);
    } catch (_) {
      setState(() => _loadState = _LoadState.failed);
    }
  }

  void _applyParsed(ParsedMedicine p) {
    _drugNameController.text = p.drugName;
    _strengthController.text = p.strength;
    _formController.text = p.form;
    _doseAmountController.text = p.doseAmount;
    _notesController.text = p.notes;
    _frequency = p.frequencyType;
    _times = List.of(p.times);
    _daysOfWeek
      ..clear()
      ..addAll(p.daysOfWeek);
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
    _frequency = FrequencyType.values.byName(schedule.frequencyType);
    _times = List.of(schedule.times);
    _daysOfWeek
      ..clear()
      ..addAll(schedule.daysOfWeek);
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

  bool get _canSave {
    if (_drugNameController.text.trim().isEmpty) return false;
    if (_frequency == FrequencyType.asNeeded) return true;
    if (_times.isEmpty) return false;
    if (_frequency == FrequencyType.specificDays && _daysOfWeek.isEmpty) return false;
    return true;
  }

  Future<void> _save() async {
    debugPrint('[SAVE-TRACE] _save() start');
    setState(() => _saving = true);
    try {
      final medicineId = _isEditing ? widget.existing!.medicine.id : newUuid();
      final scheduleId = _isEditing ? widget.existing!.schedule.id : newUuid();

      debugPrint('[SAVE-TRACE] before upsertMedicine');
      await widget.db.upsertMedicine(MedicinesCompanion.insert(
        id: medicineId,
        drugName: _drugNameController.text.trim(),
        strength: Value(_strengthController.text.trim()),
        form: Value(_formController.text.trim()),
        doseAmount: Value(_doseAmountController.text.trim()),
        notes: Value(_notesController.text.trim()),
        // insertOnConflictUpdate only touches columns present here — without
        // this, editing an already-synced medicine would silently leave
        // pendingSync at its old (false) value and the edit would never sync.
        pendingSync: const Value(true),
      ));
      debugPrint('[SAVE-TRACE] after upsertMedicine');

      final schedule = Schedule(
        id: scheduleId,
        medicineId: medicineId,
        frequencyType: _frequency.name,
        times: _times,
        daysOfWeek: _frequency == FrequencyType.specificDays ? (_daysOfWeek.toList()..sort()) : const [],
        intervalHours: _frequency == FrequencyType.everyXHours ? int.tryParse(_intervalController.text) : null,
        active: true,
        createdAt: DateTime.now(),
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
      ));
      debugPrint('[SAVE-TRACE] after upsertSchedule');

      final medicine = await widget.db.medicineById(medicineId);
      debugPrint('[SAVE-TRACE] after medicineById, medicine=${medicine?.id}');
      if (medicine != null) {
        try {
          debugPrint('[SAVE-TRACE] before scheduleForScheduleWithMedicine');
          await NotificationService.instance.scheduleForScheduleWithMedicine(
            ScheduleWithMedicine(schedule, medicine),
          );
          debugPrint('[SAVE-TRACE] after scheduleForScheduleWithMedicine');
        } catch (e) {
          debugPrint('[SAVE-TRACE] scheduleForScheduleWithMedicine threw: $e');
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
      unawaited(SyncService(widget.db).syncAll());

      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isEditing ? 'Edit reminder' : 'Review reminder')),
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
                const Text('Could not understand that automatically.'),
                const SizedBox(height: 16),
                FilledButton(onPressed: _load, child: const Text('Try again')),
                const SizedBox(height: 8),
                OutlinedButton(onPressed: _continueManually, child: const Text('Fill in manually')),
              ],
            ),
          ),
        );
      case _LoadState.ready:
        return _form();
    }
  }

  Widget _form() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
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
        const SizedBox(height: 20),
        Text('Frequency', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        SegmentedButton<FrequencyType>(
          segments: const [
            ButtonSegment(value: FrequencyType.daily, label: Text('Daily')),
            ButtonSegment(value: FrequencyType.specificDays, label: Text('Some days')),
            ButtonSegment(value: FrequencyType.everyXHours, label: Text('Every X hrs')),
            ButtonSegment(value: FrequencyType.asNeeded, label: Text('As needed')),
          ],
          selected: {_frequency},
          onSelectionChanged: (s) => setState(() => _frequency = s.first),
          showSelectedIcon: false,
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
            decoration: const InputDecoration(labelText: 'Every how many hours?'),
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
          decoration: const InputDecoration(labelText: 'Notes (optional)'),
        ),
        if (_isEditing) ...[
          const SizedBox(height: 20),
          const Divider(),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _viewHistory,
            icon: const Icon(Icons.history),
            label: const Text('View history'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
          ),
        ],
        const SizedBox(height: 28),
        FilledButton(
          onPressed: _canSave && !_saving ? _save : null,
          child: _saving
              ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(_isEditing ? 'Save changes' : 'Save reminder'),
        ),
      ],
    );
  }
}
