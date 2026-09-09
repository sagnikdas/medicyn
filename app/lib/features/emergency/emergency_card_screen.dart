import 'package:flutter/material.dart';

import '../../core/widgets/medicyn_chrome.dart';
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
  /// the small in-section spinner spinning indefinitely -- everything else
  /// on the card is local and already visible by the time this matters.
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
      // of the card.
    }
    if (mounted) {
      setState(() {
        _caregiverName = name?.trim().isNotEmpty == true ? name!.trim() : null;
        _caregiverPhone = phone;
        _loadingPhone = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) => _buildScaffold(context);

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

  Widget _buildScaffold(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
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
                  style: text.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                RepaintBoundary(
                  child: AmbientCard(
                    padding: const EdgeInsets.all(20),
                    borderColor: scheme.outlineVariant,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            _BloodGroupBadge(
                              bloodGroup:
                                  (info?.bloodGroup.trim().isNotEmpty ?? false)
                                  ? info!.bloodGroup
                                  : '',
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Emergency Medical Card',
                                    style: text.titleLarge?.copyWith(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    info?.updatedAt != null
                                        ? 'Updated ${_shortDate(info!.updatedAt)}'
                                        : 'Not set up yet',
                                    style: text.bodySmall?.copyWith(
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        Divider(color: scheme.outlineVariant, height: 1),
                        const SizedBox(height: 16),
                        _AllergyFact(
                          allergies:
                              (info?.allergies.trim().isNotEmpty ?? false)
                              ? info!.allergies
                              : 'Not set',
                          severe: info?.allergiesSevere ?? false,
                        ),
                        const SizedBox(height: 16),
                        _FactRow(
                          icon: Icons.medical_information_outlined,
                          label: 'Conditions',
                          value: (info?.conditions.trim().isNotEmpty ?? false)
                              ? info!.conditions
                              : 'Not set',
                        ),
                        if (info?.notes.trim().isNotEmpty ?? false) ...[
                          const SizedBox(height: 16),
                          _FactRow(
                            icon: Icons.sticky_note_2_outlined,
                            label: 'Notes',
                            value: info!.notes,
                          ),
                        ],
                        const SizedBox(height: 16),
                        OutlinedButton.icon(
                          onPressed: () => _edit(info),
                          icon: const Icon(Icons.edit_outlined),
                          label: const Text('Edit'),
                        ),
                        const SizedBox(height: 20),
                        Divider(color: scheme.outlineVariant, height: 1),
                        const SizedBox(height: 16),
                        _SectionTitle('Identification'),
                        const SizedBox(height: 12),
                        _FactRow(
                          icon: Icons.shield_outlined,
                          label: 'Insurance number',
                          value:
                              (info?.insuranceNumber.trim().isNotEmpty ?? false)
                              ? info!.insuranceNumber
                              : 'Not set',
                          monospace: true,
                        ),
                        const SizedBox(height: 12),
                        _FactRow(
                          icon: Icons.badge_outlined,
                          label: 'National ID (Aadhaar / SSN / etc.)',
                          value: (info?.nationalId.trim().isNotEmpty ?? false)
                              ? info!.nationalId
                              : 'Not set',
                          monospace: true,
                        ),
                        const SizedBox(height: 12),
                        _FactRow(
                          icon: Icons.local_hospital_outlined,
                          label: 'Health card no.',
                          value:
                              (info?.healthCardNumber.trim().isNotEmpty ??
                                  false)
                              ? info!.healthCardNumber
                              : 'Not set',
                          monospace: true,
                        ),
                        const SizedBox(height: 20),
                        Divider(color: scheme.outlineVariant, height: 1),
                        const SizedBox(height: 16),
                        _SectionTitle("Caregiver's number"),
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
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (_caregiverName != null) ...[
                                Text(
                                  _caregiverName!,
                                  style: text.bodyLarge?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 4),
                              ],
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      _caregiverPhone!,
                                      style: text.bodyLarge,
                                    ),
                                  ),
                                  FilledButton.tonalIcon(
                                    onPressed: () =>
                                        openDialer(_caregiverPhone!),
                                    icon: const Icon(Icons.phone),
                                    label: const Text('Call'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        const SizedBox(height: 20),
                        Divider(color: scheme.outlineVariant, height: 1),
                        const SizedBox(height: 16),
                        StreamBuilder<List<ScheduleWithMedicine>>(
                          stream: widget.db.watchActiveSchedules(),
                          builder: (context, medsSnapshot) {
                            final items = medsSnapshot.data ?? const [];
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _SectionTitle(
                                  items.isEmpty
                                      ? 'Current medicines'
                                      : 'Current medicines (${items.length})',
                                ),
                                const SizedBox(height: 8),
                                if (items.isEmpty)
                                  Text(
                                    'No medicines on this device.',
                                    style: text.bodyMedium,
                                  )
                                else
                                  for (final item in items)
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 4,
                                      ),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              medicineTitle(item.medicine),
                                              style: text.bodyLarge,
                                            ),
                                          ),
                                          if (item.medicine.doseAmount
                                              .trim()
                                              .isNotEmpty)
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
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
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

class _BloodGroupBadge extends StatelessWidget {
  const _BloodGroupBadge({required this.bloodGroup});

  final String bloodGroup;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final hasValue = bloodGroup.trim().isNotEmpty;
    return Container(
      width: 60,
      height: 60,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        shape: BoxShape.circle,
        border: Border.all(color: scheme.error, width: 1.5),
      ),
      child: Text(
        hasValue ? bloodGroup : '?',
        style: text.titleLarge?.copyWith(
          color: scheme.onErrorContainer,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
        color: Theme.of(context).colorScheme.primary,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _FactRow extends StatelessWidget {
  const _FactRow({
    required this.label,
    required this.value,
    this.icon,
    this.monospace = false,
  });

  final String label;
  final String value;
  final IconData? icon;
  final bool monospace;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 16, color: scheme.primary),
              const SizedBox(width: 6),
            ],
            Expanded(
              child: Text(
                label,
                style: text.titleSmall?.copyWith(color: scheme.primary),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: text.bodyLarge?.copyWith(
            fontFeatures: monospace
                ? const [FontFeature.tabularFigures()]
                : null,
            letterSpacing: monospace ? 0.6 : null,
          ),
        ),
      ],
    );
  }
}

/// The allergies fact, called out in a red-tinted box when marked severe --
/// the one field on this card where a rushed read is dangerous.
class _AllergyFact extends StatelessWidget {
  const _AllergyFact({required this.allergies, required this.severe});

  final String allergies;
  final bool severe;

  @override
  Widget build(BuildContext context) {
    if (!severe) {
      return _FactRow(
        icon: Icons.warning_amber_outlined,
        label: 'Allergies',
        value: allergies,
      );
    }
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.error),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber_rounded, size: 18, color: scheme.error),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'ALLERGIES — SEVERE / ANAPHYLAXIS RISK',
                  style: text.labelMedium?.copyWith(
                    color: scheme.error,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            allergies,
            style: text.bodyLarge?.copyWith(color: scheme.onErrorContainer),
          ),
        ],
      ),
    );
  }
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
