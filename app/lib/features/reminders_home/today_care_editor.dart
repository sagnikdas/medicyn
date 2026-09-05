import 'package:flutter/material.dart';

import '../../core/ids.dart';
import '../../core/motion.dart';
import '../../core/widgets/medicyn_motion.dart';
import '../../data/local/database.dart';
import 'today_care_store.dart';

Future<String?> showTodayAddMenu(
  BuildContext context,
) => showModalBottomSheet<String>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (context) => SafeArea(
    child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Add a reminder', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.medication_outlined),
            title: const Text('Medicine'),
            subtitle: const Text('Scan, speak or enter details'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.pop(context, 'medicine'),
          ),
          const Divider(height: 24),
          Text('OTHER CARE', style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: 8),
          for (final kind in TodayCareKind.values)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(kind.icon),
              title: Text(kind.label == 'Visit' ? 'Appointment' : kind.label),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.pop(context, kind.name),
            ),
        ],
      ),
    ),
  ),
);

class TodayCareEditor extends StatefulWidget {
  const TodayCareEditor({
    super.key,
    required this.kind,
    required this.onSave,
    this.existing,
    this.onDelete,
  });

  final TodayCareKind kind;
  final TodayCareReminder? existing;
  final Future<void> Function(TodayCareReminder) onSave;
  final Future<void> Function(TodayCareReminder)? onDelete;

  @override
  State<TodayCareEditor> createState() => _TodayCareEditorState();
}

class _TodayCareEditorState extends State<TodayCareEditor> {
  final _form = GlobalKey<FormState>();
  late final _title = TextEditingController(text: widget.existing?.title);
  late final _location = TextEditingController(text: widget.existing?.location);
  late final _notes = TextEditingController(text: widget.existing?.notes);
  late TodayCareKind _kind = widget.kind;
  late DateTime _at =
      widget.existing?.scheduledAt.toLocal() ??
      DateTime.now().add(const Duration(hours: 1));
  late int? _lead = widget.existing == null
      ? 30
      : widget.existing!.reminderMinutes;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _location.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _date() async {
    final now = DateUtils.dateOnly(DateTime.now());
    final date = await showDatePicker(
      context: context,
      initialDate: _at.isBefore(now) ? now : _at,
      firstDate: now,
      lastDate: DateTime(now.year + 10, 12, 31),
    );
    if (date == null || !mounted) return;
    setState(
      () =>
          _at = DateTime(date.year, date.month, date.day, _at.hour, _at.minute),
    );
  }

  Future<void> _time() async {
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_at),
    );
    if (time == null || !mounted) return;
    setState(
      () =>
          _at = DateTime(_at.year, _at.month, _at.day, time.hour, time.minute),
    );
  }

  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    final at = DateTime(_at.year, _at.month, _at.day, _at.hour, _at.minute);
    if (!at.isAfter(DateTime.now()) &&
        (widget.existing == null ||
            at != widget.existing!.scheduledAt.toLocal())) {
      setState(() => _error = 'Choose a date and time in the future.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onSave(
        TodayCareReminder(
          id: widget.existing?.id ?? newUuid(),
          title: _title.text.trim(),
          kind: _kind.name,
          scheduledAt: at,
          location: _location.text.trim(),
          notes: _notes.text.trim(),
          reminderMinutes: _lead,
          completed: widget.existing?.completed ?? false,
        ),
      );
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Could not save. Please try again.';
        });
      }
    }
  }

  Future<void> _delete() async {
    if (_busy || widget.existing == null || widget.onDelete == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onDelete!(widget.existing!);
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Could not remove. Please try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final localizations = MaterialLocalizations.of(context);
    return PopScope(
      canPop: !_busy,
      child: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            24,
            0,
            24,
            24 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  widget.existing == null ? 'Plan your care' : 'Care reminder',
                  style: theme.textTheme.headlineSmall,
                ),
                const SizedBox(height: 4),
                Text(
                  'A little space for the rest of your health.',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 20),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final kind in TodayCareKind.values)
                      ChoiceChip(
                        label: Text(kind.label),
                        selected: kind == _kind,
                        onSelected: _busy
                            ? null
                            : (_) => setState(() => _kind = kind),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _title,
                  enabled: !_busy,
                  maxLength: 100,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    labelText: 'What is planned?',
                    hintText: _kind.hint,
                    counterText: '',
                  ),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Add a name for your reminder.'
                      : null,
                ),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _busy ? null : _date,
                        icon: const Icon(
                          Icons.calendar_today_outlined,
                          size: 18,
                        ),
                        label: Text(localizations.formatCompactDate(_at)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _busy ? null : _time,
                        icon: const Icon(Icons.schedule_outlined, size: 18),
                        label: Text(
                          TimeOfDay.fromDateTime(_at).format(context),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _location,
                  enabled: !_busy,
                  maxLength: 150,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Location (optional)',
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _notes,
                  enabled: !_busy,
                  minLines: 1,
                  maxLines: 3,
                  maxLength: 500,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Notes (optional)',
                    hintText: 'Anything you want to remember',
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<int>(
                  initialValue: _lead ?? -1,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Remind me',
                    prefixIcon: Icon(Icons.notifications_none_rounded),
                  ),
                  items: const [
                    DropdownMenuItem(value: -1, child: Text('No notification')),
                    DropdownMenuItem(
                      value: 0,
                      child: Text('At the scheduled time'),
                    ),
                    DropdownMenuItem(
                      value: 15,
                      child: Text('15 minutes before'),
                    ),
                    DropdownMenuItem(
                      value: 30,
                      child: Text('30 minutes before'),
                    ),
                    DropdownMenuItem(value: 60, child: Text('1 hour before')),
                    DropdownMenuItem(value: 1440, child: Text('1 day before')),
                  ],
                  onChanged: _busy
                      ? null
                      : (value) =>
                            setState(() => _lead = value == -1 ? null : value),
                ),
                const SizedBox(height: 12),
                Text(
                  'Saved on this device. Add each session separately.',
                  style: theme.textTheme.bodySmall,
                ),
                AnimatedSize(
                  duration: MedicynMotion.duration(
                    context,
                    MedicynMotion.fast,
                  ),
                  curve: MedicynMotion.decelerate,
                  alignment: Alignment.topCenter,
                  child: _error == null
                      ? const SizedBox(width: double.infinity)
                      : Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(
                            _error!,
                            style: TextStyle(color: theme.colorScheme.error),
                          ),
                        ),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _busy ? null : _save,
                  child: MedicynSwitcher(
                    child: _busy
                        ? const SizedBox(
                            key: ValueKey('busy'),
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(
                            widget.existing == null
                                ? 'Add reminder'
                                : 'Save changes',
                            key: const ValueKey('idle'),
                          ),
                  ),
                ),
                if (widget.existing != null)
                  TextButton(
                    onPressed: _busy ? null : _delete,
                    child: const Text('Remove reminder'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
