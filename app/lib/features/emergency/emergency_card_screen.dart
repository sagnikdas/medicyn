import 'package:flutter/material.dart';

import '../../core/widgets/medicyn_layout.dart';
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

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String _shortDate(DateTime value) {
  final local = value.toLocal();
  return '${local.day} ${_months[local.month - 1]} ${local.year}';
}

/// N3: one tap from Profile, plus a printable copy -- deliberately not a
/// lock-screen surface. Reads the medicines list live from the local
/// database (the same source Today and Insights use) and the caregiver's
/// name/number from whatever care link is currently active, so this card can
/// never say something the rest of the app disagrees with.
///
/// Deliberately plain text, no cards/badges/animation: a styled version of
/// this screen was found to render corrupted (misplaced text) on at least
/// one real device once the caregiver's name arrived a couple of seconds
/// after first paint. This trades the visual polish for something that
/// cannot have that class of bug.
class EmergencyCardScreen extends StatefulWidget {
  const EmergencyCardScreen({super.key, required this.db});

  final AppDatabase db;

  @override
  State<EmergencyCardScreen> createState() => _EmergencyCardScreenState();
}

class _EmergencyCardScreenState extends State<EmergencyCardScreen> {
  String? _caregiverName;
  String? _caregiverPhone;
  bool _loadingPhone = true;
  bool _sharing = false;

  @override
  void initState() {
    super.initState();
    _loadCaregiverContact();
  }

  /// Bounds the caregiver lookup so a slow or flaky connection can't leave
  /// the "Loading…" line stuck indefinitely -- everything else on this
  /// screen is local and already visible by the time this matters.
  static const _caregiverLookupTimeout = Duration(seconds: 5);

  Future<void> _loadCaregiverContact() async {
    String? name;
    String? phone;
    try {
      final userId = AuthService.instance.currentUser?.id;
      if (userId != null) {
        final link = await CareService.instance.currentLink().timeout(
          _caregiverLookupTimeout,
        );
        phone = dialablePhone(link?.phoneToCall(userId));
        final otherPartyId = link?.otherPartyId(userId);
        if (otherPartyId != null) {
          name = await CareService.instance
              .displayName(otherPartyId)
              .timeout(_caregiverLookupTimeout);
        }
      }
    } catch (_) {
      // Leave both null. A failed or slow lookup should not block the rest
      // of the screen.
    }
    if (mounted) {
      setState(() {
        _caregiverName = name?.trim().isNotEmpty == true ? name!.trim() : null;
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
        allergiesSevere: current?.allergiesSevere ?? false,
        conditions: current?.conditions ?? '',
        notes: current?.notes ?? '',
        insuranceNumber: current?.insuranceNumber ?? '',
        nationalId: current?.nationalId ?? '',
        healthCardNumber: current?.healthCardNumber ?? '',
      ),
    );
    if (result == null) return;
    await widget.db.upsertEmergencyInfo(
      bloodGroup: result.bloodGroup,
      allergies: result.allergies,
      allergiesSevere: result.allergiesSevere,
      conditions: result.conditions,
      notes: result.notes,
      insuranceNumber: result.insuranceNumber,
      nationalId: result.nationalId,
      healthCardNumber: result.healthCardNumber,
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
    return Scaffold(
      appBar: AppBar(title: const Text('Emergency card')),
      body: SafeArea(
        child: MedicynContent(
          child: StreamBuilder<EmergencyInfoData?>(
            stream: widget.db.watchEmergencyInfo(),
            builder: (context, infoSnapshot) {
              final info = infoSnapshot.data;
              return ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  _line(
                    context,
                    'Blood group',
                    (info?.bloodGroup.trim().isNotEmpty ?? false)
                        ? info!.bloodGroup
                        : 'Not set',
                  ),
                  _line(
                    context,
                    'Allergies',
                    (info?.allergies.trim().isNotEmpty ?? false)
                        ? info!.allergies
                        : 'Not set',
                  ),
                  _line(
                    context,
                    'Allergies severe',
                    (info?.allergiesSevere ?? false) ? 'Yes' : 'No',
                  ),
                  _line(
                    context,
                    'Conditions',
                    (info?.conditions.trim().isNotEmpty ?? false)
                        ? info!.conditions
                        : 'Not set',
                  ),
                  _line(
                    context,
                    'Notes',
                    (info?.notes.trim().isNotEmpty ?? false)
                        ? info!.notes
                        : 'Not set',
                  ),
                  _line(
                    context,
                    'Insurance number',
                    (info?.insuranceNumber.trim().isNotEmpty ?? false)
                        ? info!.insuranceNumber
                        : 'Not set',
                  ),
                  _line(
                    context,
                    'National ID (Aadhaar / SSN / etc.)',
                    (info?.nationalId.trim().isNotEmpty ?? false)
                        ? info!.nationalId
                        : 'Not set',
                  ),
                  _line(
                    context,
                    'Health card no.',
                    (info?.healthCardNumber.trim().isNotEmpty ?? false)
                        ? info!.healthCardNumber
                        : 'Not set',
                  ),
                  _line(
                    context,
                    'Updated',
                    info?.updatedAt != null
                        ? _shortDate(info!.updatedAt)
                        : 'Not set up yet',
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: () => _edit(info),
                    child: const Text('Edit'),
                  ),
                  const SizedBox(height: 20),
                  _line(
                    context,
                    "Caregiver's number",
                    _loadingPhone
                        ? 'Loading…'
                        : (_caregiverPhone ?? 'No number on file.'),
                  ),
                  if (_caregiverName != null)
                    _line(context, 'Caregiver name', _caregiverName!),
                  if (_caregiverPhone != null)
                    OutlinedButton(
                      onPressed: () => openDialer(_caregiverPhone!),
                      child: const Text('Call'),
                    ),
                  const SizedBox(height: 20),
                  StreamBuilder<List<ScheduleWithMedicine>>(
                    stream: widget.db.watchActiveSchedules(),
                    builder: (context, medsSnapshot) {
                      final items = medsSnapshot.data ?? const [];
                      return _line(
                        context,
                        'Current medicines',
                        items.isEmpty
                            ? 'No medicines on this device.'
                            : items
                                  .map(
                                    (item) =>
                                        item.medicine.doseAmount.trim().isEmpty
                                        ? medicineTitle(item.medicine)
                                        : '${medicineTitle(item.medicine)} - ${item.medicine.doseAmount}',
                                  )
                                  .join('\n'),
                      );
                    },
                  ),
                  const SizedBox(height: 20),
                  OutlinedButton(
                    onPressed: _sharing ? null : _share,
                    child: Text(_sharing ? 'Preparing…' : 'Print or share'),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// One label+value fact. Merged into a single [Semantics] node (rather than
/// two separate `Text` widgets) so a screen reader announces "label, value"
/// as one stop instead of two -- this screen exists to be read fast, by a
/// human or by TalkBack/VoiceOver.
Widget _line(BuildContext context, String label, String value) {
  final text = Theme.of(context).textTheme;
  return Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Semantics(
      label: '$label: $value',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: text.labelLarge),
            Text(value, style: text.bodyLarge),
          ],
        ),
      ),
    ),
  );
}

class _EmergencyEditResult {
  const _EmergencyEditResult({
    required this.bloodGroup,
    required this.allergies,
    required this.allergiesSevere,
    required this.conditions,
    required this.notes,
    required this.insuranceNumber,
    required this.nationalId,
    required this.healthCardNumber,
  });

  final String bloodGroup;
  final String allergies;
  final bool allergiesSevere;
  final String conditions;
  final String notes;
  final String insuranceNumber;
  final String nationalId;
  final String healthCardNumber;
}

class _EmergencyEditDialog extends StatefulWidget {
  const _EmergencyEditDialog({
    required this.bloodGroup,
    required this.allergies,
    required this.allergiesSevere,
    required this.conditions,
    required this.notes,
    required this.insuranceNumber,
    required this.nationalId,
    required this.healthCardNumber,
  });

  final String bloodGroup;
  final String allergies;
  final bool allergiesSevere;
  final String conditions;
  final String notes;
  final String insuranceNumber;
  final String nationalId;
  final String healthCardNumber;

  @override
  State<_EmergencyEditDialog> createState() => _EmergencyEditDialogState();
}

class _EmergencyEditDialogState extends State<_EmergencyEditDialog> {
  late String _bloodGroup;
  late bool _allergiesSevere;
  late final TextEditingController _allergies;
  late final TextEditingController _conditions;
  late final TextEditingController _notes;
  late final TextEditingController _insuranceNumber;
  late final TextEditingController _nationalId;
  late final TextEditingController _healthCardNumber;

  @override
  void initState() {
    super.initState();
    _bloodGroup = _bloodGroups.contains(widget.bloodGroup)
        ? widget.bloodGroup
        : _bloodGroups.first;
    _allergiesSevere = widget.allergiesSevere;
    _allergies = TextEditingController(text: widget.allergies);
    _conditions = TextEditingController(text: widget.conditions);
    _notes = TextEditingController(text: widget.notes);
    _insuranceNumber = TextEditingController(text: widget.insuranceNumber);
    _nationalId = TextEditingController(text: widget.nationalId);
    _healthCardNumber = TextEditingController(text: widget.healthCardNumber);
  }

  @override
  void dispose() {
    _allergies.dispose();
    _conditions.dispose();
    _notes.dispose();
    _insuranceNumber.dispose();
    _nationalId.dispose();
    _healthCardNumber.dispose();
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
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Severe / anaphylaxis risk'),
              value: _allergiesSevere,
              onChanged: (value) => setState(() => _allergiesSevere = value),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _conditions,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Conditions',
                hintText: 'e.g. Type 2 diabetes, asthma',
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _notes,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Notes',
                hintText: 'e.g. Pacemaker, pregnant, DNR on file',
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _insuranceNumber,
              decoration: const InputDecoration(labelText: 'Insurance number'),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _nationalId,
              decoration: const InputDecoration(
                labelText: 'National ID',
                hintText: 'Aadhaar, SSN, NHS number, etc.',
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _healthCardNumber,
              decoration: const InputDecoration(labelText: 'Health card no.'),
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
              allergiesSevere: _allergiesSevere,
              conditions: _conditions.text.trim(),
              notes: _notes.text.trim(),
              insuranceNumber: _insuranceNumber.text.trim(),
              nationalId: _nationalId.text.trim(),
              healthCardNumber: _healthCardNumber.text.trim(),
            ),
          ),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
