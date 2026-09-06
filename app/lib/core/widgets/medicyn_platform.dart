import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// Whether the current Flutter surface follows Apple's interaction language.
///
/// This deliberately uses the inherited ThemeData platform instead of
/// dart:io's Platform so widget tests and desktop previews can choose the
/// platform explicitly, while Android keeps the existing Material widgets.
bool isApplePlatform(BuildContext context) {
  final platform = Theme.of(context).platform;
  return platform == TargetPlatform.iOS || platform == TargetPlatform.macOS;
}

/// A platform-native toggle with identical semantics and state handling.
/// Android keeps the app's Material switch; iOS gets the familiar thumb/track
/// control used in Settings and consent flows.
class MedicynAdaptiveSwitch extends StatelessWidget {
  const MedicynAdaptiveSwitch({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return isApplePlatform(context)
        ? CupertinoSwitch(value: value, onChanged: onChanged)
        : Switch(value: value, onChanged: onChanged);
  }
}

/// A back affordance that uses Apple's chevron convention without changing
/// the shared navigation stack or Android's arrow convention.
class MedicynAdaptiveBackButton extends StatelessWidget {
  const MedicynAdaptiveBackButton({super.key, this.onPressed, this.tooltip});

  final VoidCallback? onPressed;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(
        isApplePlatform(context)
            ? CupertinoIcons.chevron_back
            : Icons.arrow_back,
      ),
      tooltip: tooltip ?? 'Back',
      onPressed: onPressed ?? () => Navigator.of(context).maybePop(),
    );
  }
}

/// Presents a native-feeling time picker on Apple platforms and preserves the
/// Material clock picker on Android. The returned value stays platform-neutral
/// so reminder scheduling code needs no platform branches.
Future<TimeOfDay?> showMedicynTimePicker(
  BuildContext context, {
  required TimeOfDay initialTime,
}) {
  if (!isApplePlatform(context)) {
    return showTimePicker(context: context, initialTime: initialTime);
  }

  final now = DateTime.now();
  var selected = DateTime(
    now.year,
    now.month,
    now.day,
    initialTime.hour,
    initialTime.minute,
  );
  final use24HourFormat = MediaQuery.alwaysUse24HourFormatOf(context);

  return showCupertinoModalPopup<TimeOfDay>(
    context: context,
    builder: (popupContext) => Container(
      height: 320,
      color: CupertinoColors.systemBackground.resolveFrom(popupContext),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: () => Navigator.of(popupContext).pop(
                      TimeOfDay(hour: selected.hour, minute: selected.minute),
                    ),
                    child: const Text('Done'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: CupertinoDatePicker(
                mode: CupertinoDatePickerMode.time,
                initialDateTime: selected,
                use24hFormat: use24HourFormat,
                onDateTimeChanged: (value) => selected = value,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
