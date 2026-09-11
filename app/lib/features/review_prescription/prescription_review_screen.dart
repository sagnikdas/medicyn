import 'dart:async';

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';

import '../../core/ids.dart';
import '../../core/motion.dart';
import '../../core/widgets/medicyn_chrome.dart';
import '../../core/widgets/medicyn_layout.dart';
import '../../core/widgets/medicyn_motion.dart';
import '../../core/app_settings.dart';
import '../../data/local/database.dart';
import '../../data/local/tables.dart';
import '../../data/remote/care_notifier.dart';
import '../../data/remote/prescription_parser.dart';
import '../../data/remote/sync_service.dart';
import '../auth/auth_service.dart';
import '../consent/consent_purpose.dart';
import '../consent/consent_service.dart';
import '../notification_engine/notification_service.dart';
import '../notification_engine/schedule_validation.dart';
import '../reminders_home/today_care_editor.dart';
import '../reminders_home/today_care_store.dart';
import '../review_edit/medicine_fields_form.dart';
import '../review_edit/review_edit_screen.dart';
import '../review_edit/parsed_medicine.dart';
import 'care_recurrence.dart';
import 'parsed_prescription.dart';

/// One detected medicine, still being reviewed. Owns the same shape of
/// mutable state [ReviewEditScreen] keeps inline for its single medicine --
/// controllers, frequency, days, times -- so [MedicineFieldsForm] can drive
/// it exactly the same way.
class _MedicineDraft {
  _MedicineDraft(ParsedMedicine parsed)
    : drugNameController = TextEditingController(text: parsed.drugName),
      strengthController = TextEditingController(text: parsed.strength),
      formController = TextEditingController(text: parsed.form),
      doseAmountController = TextEditingController(text: parsed.doseAmount),
      remainingController = TextEditingController(),
      perDoseController = TextEditingController(),
      notesController = TextEditingController(text: parsed.notes),
      intervalController = TextEditingController(
        text: parsed.intervalHours != null ? '${parsed.intervalHours}' : '8',
      ),
      frequency = parsed.frequencyType,
      times = List.of(parsed.times),
      daysOfWeek = Set.of(parsed.daysOfWeek),
      confidence = parsed.confidence;

  final TextEditingController drugNameController;
  final TextEditingController strengthController;
  final TextEditingController formController;
  final TextEditingController doseAmountController;
  final TextEditingController remainingController;
  final TextEditingController perDoseController;
  final TextEditingController notesController;
  final TextEditingController intervalController;

  FrequencyType frequency;
  List<String> times;
  final Set<int> daysOfWeek;
  final double confidence;
  bool included = true;
  bool expanded = false;

  String? get intervalError {
    if (frequency != FrequencyType.everyXHours) return null;
    final raw = intervalController.text.trim();
    if (raw.isEmpty) return null;
    final parsed = int.tryParse(raw);
    if (parsed == null) return 'Enter a number of hours';
    if (schedulableIntervalHours(parsed) == null) {
      return 'Must be between 1 and 24 hours';
    }
    return null;
  }

  int? get _enteredIntervalHours {
    final parsed = int.tryParse(intervalController.text.trim());
    if (parsed == null) return null;
    return schedulableIntervalHours(parsed) == null ? null : parsed;
  }

  int? get _enteredRemaining {
    final raw = remainingController.text.trim();
    if (raw.isEmpty) return null;
    return int.tryParse(raw);
  }

  int? get _enteredPerDose {
    final raw = perDoseController.text.trim();
    if (raw.isEmpty) return null;
    final parsed = int.tryParse(raw);
    if (parsed == null || parsed < 1) return null;
    return parsed;
  }

  bool get canSave {
    if (drugNameController.text.trim().isEmpty) return false;
    if (frequency == FrequencyType.asNeeded) return true;
    if (times.isEmpty) return false;
    if (frequency == FrequencyType.specificDays && daysOfWeek.isEmpty) {
      return false;
    }
    if (intervalError != null) return false;
    return true;
  }

  void dispose() {
    drugNameController.dispose();
    strengthController.dispose();
    formController.dispose();
    doseAmountController.dispose();
    remainingController.dispose();
    perDoseController.dispose();
    notesController.dispose();
    intervalController.dispose();
  }
}

/// One expanded occurrence of a detected care item -- e.g. one of the six
/// dated rows "physiotherapy, weekly, 6 sessions" becomes. [groupTitle]/
/// [groupTotal]/[groupIndex] are display-only, so occurrences from the same
/// source item can be shown together; each is otherwise an ordinary,
/// independently includable/editable future [TodayCareReminder].
class _CareOccurrenceDraft {
  _CareOccurrenceDraft({
    required this.reminder,
    required this.groupTitle,
    required this.groupIndex,
    required this.groupTotal,
    required this.confidence,
  });

  TodayCareReminder reminder;
  final String groupTitle;
  final int groupIndex;
  final int groupTotal;
  final double confidence;
  bool included = true;
}

enum _LoadState { loading, ready, failed }

/// Reviews everything `parse-prescription` found in one scanned or PDF-
/// uploaded document -- every medicine and every scheduled care item --
/// before any of it is saved. The trust boundary for the whole feature:
/// every row starts included but can be excluded or edited, and nothing
/// reaches the database until [_save] runs.
class PrescriptionReviewScreen extends StatefulWidget {
  const PrescriptionReviewScreen({
    super.key,
    required this.ocrText,
    required this.db,
    @visibleForTesting this.debugInitialPrescription,
  });

  final String ocrText;
  final AppDatabase db;

  /// Test-only seam: when set, [_load] uses this instead of calling
  /// [PrescriptionParser] over the network. Lets widget tests exercise the
  /// review/save logic without needing to mock Supabase Functions' internal
  /// isolate-based JSON decoding, which does not resolve inside the test
  /// harness's synthetic environment.
  @visibleForTesting
  final ParsedPrescription? debugInitialPrescription;

  @override
  State<PrescriptionReviewScreen> createState() =>
      _PrescriptionReviewScreenState();
}

class _PrescriptionReviewScreenState extends State<PrescriptionReviewScreen> {
  _LoadState _loadState = _LoadState.loading;
  String? _parseError;
  bool _saving = false;

  final List<_MedicineDraft> _medicines = [];
  final List<_CareOccurrenceDraft> _careItems = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final draft in _medicines) {
      draft.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loadState = _LoadState.loading;
      _parseError = null;
    });
    final injected = widget.debugInitialPrescription;
    if (injected != null) {
      _applyParsed(injected);
      setState(() {
        _loadState = _medicines.isEmpty && _careItems.isEmpty
            ? _LoadState.failed
            : _LoadState.ready;
      });
      return;
    }
    if (!shouldParseMedicine(
      anthropicGranted: ConsentService.instance.isGranted(
        ConsentPurpose.anthropicParse,
      ),
      ocrText: widget.ocrText,
      transcript: '',
    )) {
      setState(() => _loadState = _LoadState.failed);
      return;
    }
    try {
      final parsed = await PrescriptionParser().parse(ocrText: widget.ocrText);
      _applyParsed(parsed);
      if (!mounted) return;
      setState(() {
        _loadState = _medicines.isEmpty && _careItems.isEmpty
            ? _LoadState.failed
            : _LoadState.ready;
      });
    } on PrescriptionParseException catch (e) {
      if (!mounted) return;
      setState(() {
        _loadState = _LoadState.failed;
        _parseError = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadState = _LoadState.failed);
    }
  }

  void _applyParsed(ParsedPrescription parsed) {
    for (final draft in _medicines) {
      draft.dispose();
    }
    _medicines
      ..clear()
      ..addAll(parsed.medicines.map(_MedicineDraft.new));
    if (_medicines.length == 1) _medicines.single.expanded = true;

    _careItems.clear();
    for (final item in parsed.careItems) {
      final dates = expandCareOccurrences(item);
      final title = item.title.trim().isEmpty ? item.kind.label : item.title;
      for (var i = 0; i < dates.length; i++) {
        _careItems.add(
          _CareOccurrenceDraft(
            groupTitle: title,
            groupIndex: i + 1,
            groupTotal: dates.length,
            confidence: item.confidence,
            reminder: TodayCareReminder(
              id: newUuid(),
              title: title,
              kind: item.kind.name,
              scheduledAt: dates[i],
              location: '',
              notes: item.notes,
              reminderMinutes: 30,
              completed: false,
              updatedAt: DateTime.now().toUtc(),
              pendingSync: true,
              deleted: false,
            ),
          ),
        );
      }
    }
  }

  void _continueManually() => setState(() => _loadState = _LoadState.ready);

  Future<void> _addMedicineManually() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => ReviewEditScreen(db: widget.db)));
  }

  Future<void> _addCareManually() async {
    final choice = await showTodayAddMenu(context);
    if (choice == null || choice == 'medicine' || !mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => TodayCareEditor(
        kind: TodayCareKind.fromName(choice),
        onSave: (reminder) async {
          await TodayCareStore(widget.db).save(reminder);
          unawaited(TodayCareNotifications().schedule(reminder, newlySaved: true));
        },
      ),
    );
  }

  Future<void> _editCareOccurrence(_CareOccurrenceDraft draft) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => TodayCareEditor(
        kind: TodayCareKind.fromName(draft.reminder.kind),
        existing: draft.reminder,
        // Local-only: nothing persists here. The whole prescription saves
        // together in _save() once the user confirms every row.
        onSave: (reminder) async {
          setState(() => draft.reminder = reminder);
        },
      ),
    );
  }

  bool get _canSave {
    final includedMedicines = _medicines.where((d) => d.included);
    final includedCare = _careItems.where((d) => d.included);
    if (includedMedicines.isEmpty && includedCare.isEmpty) return false;
    return includedMedicines.every((d) => d.canSave);
  }

  bool get _cloudReady =>
      AuthService.instance.isSignedIn &&
      AppSettings.instance.consentCloudBackup &&
      AppSettings.instance.consentOwnerId ==
          AuthService.instance.currentUser?.id;

  Future<void> _save() async {
    if (!_canSave || _saving) return;
    final includedCare = _careItems.where((d) => d.included).toList();
    if (includedCare.isNotEmpty && !_cloudReady) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Other care needs sign-in and cloud backup so those plans save to your account. Medicines will still save.',
          ),
        ),
      );
    }

    setState(() => _saving = true);
    final failedMedicineNames = <String>[];
    final failedCareCount = <_CareOccurrenceDraft>[];

    for (final draft in _medicines.where((d) => d.included).toList()) {
      try {
        await _saveMedicine(draft);
        _medicines.remove(draft);
        draft.dispose();
      } catch (_) {
        failedMedicineNames.add(draft.drugNameController.text.trim());
      }
    }

    if (_cloudReady) {
      final store = TodayCareStore(widget.db);
      final notifications = TodayCareNotifications();
      for (final draft in includedCare) {
        try {
          await store.save(draft.reminder);
          unawaited(notifications.schedule(draft.reminder, newlySaved: true));
          _careItems.remove(draft);
        } catch (_) {
          failedCareCount.add(draft);
        }
      }
    }

    unawaited(() async {
      final sync = SyncService(widget.db);
      await sync.syncAll();
      if (sync.pushedEdits) await CareNotifier.instance.dataChanged();
    }());

    if (!mounted) return;
    setState(() => _saving = false);

    if (failedMedicineNames.isEmpty && failedCareCount.isEmpty) {
      Navigator.of(context).popUntil((route) => route.isFirst);
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Saved the rest, but ${failedMedicineNames.length + failedCareCount.length} '
          "item${failedMedicineNames.length + failedCareCount.length == 1 ? '' : 's'} could not be saved. Check the details and try again.",
        ),
      ),
    );
  }

  Future<void> _saveMedicine(_MedicineDraft draft) async {
    final medicineId = newUuid();
    final scheduleId = newUuid();
    final savedAt = DateTime.now();
    final savedBy = AuthService.instance.currentUser?.id;

    await widget.db.upsertMedicine(
      MedicinesCompanion.insert(
        id: medicineId,
        drugName: draft.drugNameController.text.trim(),
        strength: Value(draft.strengthController.text.trim()),
        form: Value(draft.formController.text.trim()),
        doseAmount: Value(draft.doseAmountController.text.trim()),
        notes: Value(draft.notesController.text.trim()),
        tabletsRemaining: Value(draft._enteredRemaining),
        tabletsPerDose: Value(draft._enteredPerDose),
        pendingSync: const Value(true),
        createdAt: Value(savedAt),
        updatedAt: Value(savedAt),
        updatedBy: Value(savedBy),
      ),
    );

    final daysOfWeek = draft.frequency == FrequencyType.specificDays
        ? (draft.daysOfWeek.toList()..sort())
        : const <int>[];
    final intervalHours = draft.frequency == FrequencyType.everyXHours
        ? draft._enteredIntervalHours
        : null;

    await widget.db.upsertSchedule(
      SchedulesCompanion.insert(
        id: scheduleId,
        medicineId: medicineId,
        frequencyType: draft.frequency.name,
        times: draft.times,
        daysOfWeek: Value(daysOfWeek),
        intervalHours: Value(intervalHours),
        status: Value(
          draft.frequency == FrequencyType.asNeeded
              ? ReminderStatus.asNeeded.name
              : ReminderStatus.active.name,
        ),
        pendingSync: const Value(true),
        createdAt: Value(savedAt),
        updatedAt: Value(savedAt),
        // A brand-new schedule: its timing is defined right now, same as
        // updatedAt. See [Schedules.timingDefinedAt].
        timingDefinedAt: Value(savedAt),
        updatedBy: Value(savedBy),
      ),
    );

    final medicine = await widget.db.medicineById(medicineId);
    if (medicine != null) {
      final schedule = await (widget.db.select(
        widget.db.schedules,
      )..where((s) => s.id.equals(scheduleId))).getSingleOrNull();
      if (schedule != null) {
        try {
          await NotificationService.instance.scheduleForScheduleWithMedicine(
            ScheduleWithMedicine(schedule, medicine),
            db: widget.db,
          );
        } catch (_) {
          // The medicine is saved either way -- Reminder reliability in
          // Settings is where a scheduling failure gets fixed, same as the
          // single-item review screen.
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Review prescription')),
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
              Text('Reading the prescription…'),
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
                Text(
                  _parseError ??
                      'Could not find any medicines or care instructions in that document.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FilledButton(onPressed: _load, child: const Text('Try again')),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: _addMedicineManually,
                  child: const Text('Add a medicine manually'),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: _addCareManually,
                  child: const Text('Add other care manually'),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _continueManually,
                  child: const Text('Close'),
                ),
              ],
            ),
          ),
        ),
        _LoadState.ready => MedicynFadeIn(
          key: const ValueKey(_LoadState.ready),
          child: Column(
            children: [
              Expanded(child: _list()),
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
                          : const Text('Save reminders', key: ValueKey(false)),
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

  Widget _list() {
    // Occurrences from the same source item stay adjacent, grouped by their
    // position in _careItems (already built that way in _applyParsed).
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      children: [
        if (_medicines.isEmpty && _careItems.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Text(
              'Everything here has been added. Tap Save reminders to confirm, or add anything else below.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        if (_medicines.isNotEmpty) ...[
          Text('Medicines', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          for (final draft in _medicines) _medicineCard(draft),
        ],
        if (_careItems.isNotEmpty) ...[
          if (_medicines.isNotEmpty) const SizedBox(height: 20),
          Text('Other care', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          for (final group in _careGroups()) _careGroupCard(group),
        ],
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: _addMedicineManually,
          icon: const Icon(Icons.add),
          label: const Text('Add another medicine'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _addCareManually,
          icon: const Icon(Icons.add),
          label: const Text('Add other care'),
        ),
      ],
    );
  }

  /// Splits [_careItems] back into its source groups for display -- adjacent
  /// runs sharing a [_CareOccurrenceDraft.groupTitle]/[groupTotal], which is
  /// how [_applyParsed] laid them out.
  List<List<_CareOccurrenceDraft>> _careGroups() {
    final groups = <List<_CareOccurrenceDraft>>[];
    for (final draft in _careItems) {
      if (groups.isNotEmpty &&
          groups.last.first.groupTitle == draft.groupTitle &&
          groups.last.first.groupTotal == draft.groupTotal &&
          groups.last.length < groups.last.first.groupTotal) {
        groups.last.add(draft);
      } else {
        groups.add([draft]);
      }
    }
    return groups;
  }

  Widget _medicineCard(_MedicineDraft draft) {
    final scheme = Theme.of(context).colorScheme;
    final summary = [
      if (draft.strengthController.text.trim().isNotEmpty)
        draft.strengthController.text.trim(),
      switch (draft.frequency) {
        FrequencyType.daily => 'Daily',
        FrequencyType.specificDays => 'Some days',
        FrequencyType.everyXHours => 'Every ${draft.intervalController.text.trim().isEmpty ? '8' : draft.intervalController.text.trim()} hrs',
        FrequencyType.asNeeded => 'As needed',
      },
      if (draft.times.isNotEmpty) draft.times.join(', '),
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AmbientCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Switch(
                  value: draft.included,
                  onChanged: (v) => setState(() => draft.included = v),
                ),
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => setState(() => draft.expanded = !draft.expanded),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          draft.drugNameController.text.trim().isEmpty
                              ? '(no medicine name read)'
                              : draft.drugNameController.text.trim(),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        if (summary.isNotEmpty)
                          Text(
                            summary,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                      ],
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(draft.expanded ? Icons.expand_less : Icons.expand_more),
                  onPressed: () => setState(() => draft.expanded = !draft.expanded),
                ),
              ],
            ),
            AnimatedSize(
              duration: MedicynMotion.duration(context, MedicynMotion.fast),
              curve: MedicynMotion.decelerate,
              alignment: Alignment.topCenter,
              child: !draft.expanded
                  ? const SizedBox(width: double.infinity)
                  : Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: MedicineFieldsForm(
                        drugNameController: draft.drugNameController,
                        strengthController: draft.strengthController,
                        formController: draft.formController,
                        doseAmountController: draft.doseAmountController,
                        remainingController: draft.remainingController,
                        perDoseController: draft.perDoseController,
                        notesController: draft.notesController,
                        intervalController: draft.intervalController,
                        frequency: draft.frequency,
                        onFrequencyChanged: (f) =>
                            setState(() => draft.frequency = f),
                        daysOfWeek: draft.daysOfWeek,
                        onDayToggled: (day, selected) => setState(
                          () => selected
                              ? draft.daysOfWeek.add(day)
                              : draft.daysOfWeek.remove(day),
                        ),
                        times: draft.times,
                        onTimeRemoved: (t) => setState(
                          () => draft.times =
                              draft.times.where((x) => x != t).toList(),
                        ),
                        onAddTime: () async {
                          final formatted = await pickMedicineTime(context);
                          if (formatted == null) return;
                          setState(() {
                            if (draft.frequency == FrequencyType.everyXHours) {
                              draft.times = [formatted];
                            } else if (!draft.times.contains(formatted)) {
                              draft.times = [...draft.times, formatted]..sort();
                            }
                          });
                        },
                        intervalError: draft.intervalError,
                        onIntervalChanged: () => setState(() {}),
                        confidence: draft.confidence,
                      ),
                    ),
            ),
            if (!draft.expanded && !draft.canSave)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Needs a medicine name and at least one time — tap to fix.',
                  style: TextStyle(color: scheme.error, fontSize: 12),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _careGroupCard(List<_CareOccurrenceDraft> group) {
    final first = group.first;
    final localizations = MaterialLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AmbientCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(TodayCareKind.fromName(first.reminder.kind).icon),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    first.groupTotal > 1
                        ? '${first.groupTitle} — ${first.groupTotal} sessions'
                        : first.groupTitle,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (final draft in group)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  children: [
                    Switch(
                      value: draft.included,
                      onChanged: (v) => setState(() => draft.included = v),
                    ),
                    Expanded(
                      child: Text(
                        first.groupTotal > 1
                            ? 'Session ${draft.groupIndex}: ${localizations.formatMediumDate(draft.reminder.scheduledAt)}'
                            : localizations.formatMediumDate(
                                draft.reminder.scheduledAt,
                              ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit_outlined),
                      tooltip: 'Edit',
                      onPressed: () => _editCareOccurrence(draft),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
