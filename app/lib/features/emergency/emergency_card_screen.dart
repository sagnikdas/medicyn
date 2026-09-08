import 'package:flutter/material.dart';

import '../../core/widgets/medicyn_motion.dart';
import '../../data/export/emergency_card_export_service.dart';
import '../../data/local/database.dart';
import '../auth/auth_service.dart';
import '../care/care_service.dart';
import '../care/phone_dial.dart';
import '../reminders_home/reminder_copy.dart';

const _bloodGroups = [
  'Unknown',
  'A+',
  'A-',
  'B+',
  'B-',
  'AB+',
  'AB-',
  'O+',
  'O-',
];

/// N3: one tap from Profile, plus a printable copy -- deliberately not a
/// lock-screen surface. Reads the medicines list live from the local
/// database (the same source Today and Insights use) and the caregiver's
/// number from whatever care link is currently active, so this card can
/// never say something the rest of the app disagrees with.
class EmergencyCardScreen extends StatefulWidget {
  const EmergencyCardScreen({super.key, required this.db});

  final AppDatabase db;

  @override
  State<EmergencyCardScreen> createState() => _EmergencyCardScreenState();
}

class _EmergencyCardScreenState extends State<EmergencyCardScreen> {
  String? _caregiverPhone;
  bool _loadingPhone = true;
  bool _sharing = false;

  @override
  void initState() {
    super.initState();
    _loadCaregiverPhone();
  }

  Future<void> _loadCaregiverPhone() async {
    String? phone;
    try {
      final userId = AuthService.instance.currentUser?.id;
      if (userId != null) {
        final link = await CareService.instance.currentLink();
        phone = dialablePhone(link?.phoneToCall(userId));
      }
    } catch (_) {
      // Leave it null. A failed lookup should not block the rest of the card.
    }
    if (mounted) {
      setState(() {
        _caregiverPhone = phone;
        _loadingPhone = false;
      });
    }
  }

  Future<void> _edit(EmergencyInfoData? current) async {
    final result = await showAdaptiveDialog<_EmergencyEditResult>(
      context: context,
      builder: (_) => _EmergencyEditDialog(
        bloodGroup: current?.bloodGroup ?? '',
        allergies: current?.allergies ?? '',
        conditions: current?.conditions ?? '',
      ),
    );
    if (result == null) return;
    await widget.db.upsertEmergencyInfo(
      bloodGroup: result.bloodGroup,
      allergies: result.allergies,
      conditions: result.conditions,
    );
  }

  Future<void> _share() async {
    if (_sharing) return;
    setState(() => _sharing = true);
    try {
      final box = context.findRenderObject() as RenderBox?;
      await EmergencyCardExportService(widget.db).exportAndShare(
        sharePositionOrigin: box != null
            ? box.localToGlobal(Offset.zero) & box.size
            : null,
      );
    } catch (e) {
      if (!mounted) return;
      await showAdaptiveDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog.adaptive(
          title: const Text('Could not prepare the card'),
          content: const Text(
            'The PDF could not be prepared right now. Check your storage and try again.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Emergency card')),
      body: StreamBuilder<EmergencyInfoData?>(
        stream: widget.db.watchEmergencyInfo(),
        builder: (context, infoSnapshot) {
          final info = infoSnapshot.data;
          return MedicynFadeIn(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(
                  'For a first responder, a new clinician, or a caregiver to '
                  'check quickly. Keep it up to date.',
                  style: text.bodyLarge,
                ),
                const SizedBox(height: 20),
                _FactRow(
                  label: 'Blood group',
                  value: (info?.bloodGroup.trim().isNotEmpty ?? false)
                      ? info!.bloodGroup
                      : 'Not set',
                ),
                const SizedBox(height: 12),
                _FactRow(
                  label: 'Allergies',
                  value: (info?.allergies.trim().isNotEmpty ?? false)
                      ? info!.allergies
                      : 'Not set',
                ),
                const SizedBox(height: 12),
                _FactRow(
                  label: 'Conditions',
                  value: (info?.conditions.trim().isNotEmpty ?? false)
                      ? info!.conditions
                      : 'Not set',
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => _edit(info),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Edit'),
                ),
                const SizedBox(height: 24),
                Text(
                  "Caregiver's number",
                  style: text.titleSmall?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 8),
                if (_loadingPhone)
                  const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else if (_caregiverPhone == null)
                  Text(
                    'No number on file. Connect with family in Settings to add one.',
                    style: text.bodyMedium,
                  )
                else
                  Row(
                    children: [
                      Expanded(
                        child: Text(_caregiverPhone!, style: text.bodyLarge),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: () => openDialer(_caregiverPhone!),
                        icon: const Icon(Icons.phone),
                        label: const Text('Call'),
                      ),
                    ],
                  ),
                const SizedBox(height: 24),
                Text(
                  'Current medicines',
                  style: text.titleSmall?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 8),
                StreamBuilder<List<ScheduleWithMedicine>>(
                  stream: widget.db.watchActiveSchedules(),
                  builder: (context, medsSnapshot) {
                    final items = medsSnapshot.data ?? const [];
                    if (items.isEmpty) {
                      return Text(
                        'No medicines on this device.',
                        style: text.bodyMedium,
                      );
                    }
                    return Column(
                      children: [
                        for (final item in items)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    medicineTitle(item.medicine),
                                    style: text.bodyLarge,
                                  ),
                                ),
                                if (item.medicine.doseAmount.trim().isNotEmpty)
                                  Text(
                                    item.medicine.doseAmount,
                                    style: text.bodyMedium,
                                  ),
                              ],
                            ),
                          ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 28),
                OutlinedButton.icon(
                  onPressed: _sharing ? null : _share,
                  icon: MedicynSwitcher(
                    child: _sharing
                        ? const SizedBox(
                            key: ValueKey('busy'),
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(
                            Icons.picture_as_pdf_outlined,
                            key: ValueKey('pdf'),
                          ),
                  ),
                  label: Text(_sharing ? 'Preparing…' : 'Print or share'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _FactRow extends StatelessWidget {
  const _FactRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: text.titleSmall?.copyWith(
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        const SizedBox(height: 4),
        Text(value, style: text.bodyLarge),
      ],
    );
  }
}

class _EmergencyEditResult {
  const _EmergencyEditResult({
    required this.bloodGroup,
    required this.allergies,
    required this.conditions,
  });

  final String bloodGroup;
  final String allergies;
  final String conditions;
}

class _EmergencyEditDialog extends StatefulWidget {
  const _EmergencyEditDialog({
    required this.bloodGroup,
    required this.allergies,
    required this.conditions,
  });

  final String bloodGroup;
  final String allergies;
  final String conditions;

  @override
  State<_EmergencyEditDialog> createState() => _EmergencyEditDialogState();
}

class _EmergencyEditDialogState extends State<_EmergencyEditDialog> {
  late String _bloodGroup;
  late final TextEditingController _allergies;
  late final TextEditingController _conditions;

  @override
  void initState() {
    super.initState();
    _bloodGroup = _bloodGroups.contains(widget.bloodGroup)
        ? widget.bloodGroup
        : _bloodGroups.first;
    _allergies = TextEditingController(text: widget.allergies);
    _conditions = TextEditingController(text: widget.conditions);
  }

  @override
  void dispose() {
    _allergies.dispose();
    _conditions.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog.adaptive(
      title: const Text('Edit emergency card'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _bloodGroup,
              decoration: const InputDecoration(labelText: 'Blood group'),
              items: [
                for (final group in _bloodGroups)
                  DropdownMenuItem(value: group, child: Text(group)),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _bloodGroup = value);
              },
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _allergies,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Allergies',
                hintText: 'e.g. Penicillin, peanuts',
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _conditions,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Conditions',
                hintText: 'e.g. Type 2 diabetes, asthma',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(
            _EmergencyEditResult(
              bloodGroup: _bloodGroup == 'Unknown' ? '' : _bloodGroup,
              allergies: _allergies.text.trim(),
              conditions: _conditions.text.trim(),
            ),
          ),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
