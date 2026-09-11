import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/locale_dates.dart';
import '../../core/widgets/medicyn_platform.dart';
import '../../data/local/tables.dart';

/// The medicine-specific input fields shared by [ReviewEditScreen]'s
/// single-item form and the multi-item prescription review screen: drug
/// name/strength/form/dose, frequency, days, interval, times, notes.
/// Deliberately excludes anything that only makes sense for a single
/// already-saved reminder (the "for someone else" banner, lifecycle
/// actions, dose/change history) -- those stay screen-specific.
///
/// Stateless on purpose: every field's value and every mutation is owned by
/// the caller (its `TextEditingController`s, its `frequency`/`daysOfWeek`/
/// `times`, its callbacks), the same shape [ReviewEditScreen] already used
/// inline before this was extracted. This keeps the extraction behavior-
/// preserving -- no new state, no new validation, just relocated widgets --
/// so a bug fixed here is fixed in both the single-item and multi-item
/// flows instead of drifting into two copies.
class MedicineFieldsForm extends StatelessWidget {
  const MedicineFieldsForm({
    super.key,
    required this.drugNameController,
    required this.strengthController,
    required this.formController,
    required this.doseAmountController,
    required this.remainingController,
    required this.perDoseController,
    required this.notesController,
    required this.intervalController,
    required this.frequency,
    required this.onFrequencyChanged,
    required this.daysOfWeek,
    required this.onDayToggled,
    required this.times,
    required this.onTimeRemoved,
    required this.onAddTime,
    required this.intervalError,
    required this.onIntervalChanged,
    this.confidence,
  });

  final TextEditingController drugNameController;
  final TextEditingController strengthController;
  final TextEditingController formController;
  final TextEditingController doseAmountController;
  final TextEditingController remainingController;
  final TextEditingController perDoseController;
  final TextEditingController notesController;
  final TextEditingController intervalController;

  final FrequencyType frequency;
  final ValueChanged<FrequencyType> onFrequencyChanged;

  final Set<int> daysOfWeek;
  final void Function(int day, bool selected) onDayToggled;

  final List<String> times;
  final ValueChanged<String> onTimeRemoved;
  final VoidCallback onAddTime;

  /// Why the interval field is unusable, or null when it is fine. Computed
  /// by the caller -- it depends on [frequency] and the controller's text,
  /// which the caller already has to track for [onIntervalChanged] anyway.
  final String? intervalError;
  final VoidCallback onIntervalChanged;

  /// AI extraction confidence for this one medicine, or null when the
  /// fields were entered by hand (manual entry, or editing an existing
  /// reminder) and there is no score to show.
  final double? confidence;

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

  @override
  Widget build(BuildContext context) {
    final confidenceValue = confidence;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (confidenceValue != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text(
              'AI read this with ${(confidenceValue * 100).round()}% confidence — check it over.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        TextField(
          controller: drugNameController,
          decoration: const InputDecoration(labelText: 'Medicine name *'),
        ),
        const SizedBox(height: 12),
        _fieldPair(
          TextField(
            controller: strengthController,
            decoration: const InputDecoration(
              labelText: 'Strength (e.g. 500mg)',
            ),
          ),
          TextField(
            controller: formController,
            decoration: const InputDecoration(
              labelText: 'Form (tablet, syrup…)',
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: doseAmountController,
          decoration: const InputDecoration(
            labelText: 'Dose amount (e.g. 1 tablet)',
          ),
        ),
        const SizedBox(height: 12),
        _fieldPair(
          TextField(
            controller: remainingController,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: 'Tablets left',
              helperText: 'Leave blank to skip',
            ),
          ),
          TextField(
            controller: perDoseController,
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
                selected: frequency == option,
                onSelected: (_) => onFrequencyChanged(option),
              ),
          ],
        ),
        const SizedBox(height: 16),
        if (frequency == FrequencyType.specificDays) ...[
          Wrap(
            spacing: 8,
            children: List.generate(7, (i) {
              final selected = daysOfWeek.contains(i);
              return FilterChip(
                label: Text(localeShortWeekdayForSundayIndex(i)),
                selected: selected,
                onSelected: (v) => onDayToggled(i, v),
              );
            }),
          ),
          const SizedBox(height: 16),
        ],
        if (frequency == FrequencyType.everyXHours) ...[
          TextField(
            controller: intervalController,
            keyboardType: TextInputType.number,
            // Digits only, so a stray character cannot reach int.tryParse and
            // arrive as a null interval. The range is checked separately —
            // formatters cannot express "not zero".
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onChanged: (_) => onIntervalChanged(),
            decoration: InputDecoration(
              labelText: 'Every how many hours?',
              // Typing 0 here used to be enough to leave the phone with no
              // medication alarms at all, so say why it is refused rather
              // than just disabling Save with no explanation.
              errorText: intervalError,
            ),
          ),
          const SizedBox(height: 16),
        ],
        if (frequency != FrequencyType.asNeeded) ...[
          Text(
            frequency == FrequencyType.everyXHours
                ? 'First dose time'
                : 'Times',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final t in times)
                Chip(label: Text(t), onDeleted: () => onTimeRemoved(t)),
              ActionChip(
                avatar: const Icon(Icons.add, size: 18),
                label: const Text('Add time'),
                onPressed: onAddTime,
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],
        TextField(
          controller: notesController,
          maxLines: 2,
          decoration: const InputDecoration(
            labelText: 'Instructions (optional)',
          ),
        ),
      ],
    );
  }
}

/// Shared by [MedicineFieldsForm]'s callers for the "Add time" chip: opens
/// the platform time picker and returns a formatted `HH:mm` string, or null
/// if cancelled.
Future<String?> pickMedicineTime(BuildContext context) async {
  final picked = await showMedicynTimePicker(context, initialTime: TimeOfDay.now());
  if (picked == null) return null;
  return '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
}
