import 'package:flutter/material.dart';

import '../../core/widgets/medicyn_layout.dart';
import '../../core/widgets/medicyn_motion.dart';
import '../auth/auth_service.dart';
import 'care_service.dart';
import 'edit_attribution.dart';

/// Append-only history for one medicine, newest first. Both sides of a link
/// see the same list — the parent is not shown a lesser version.
class ChangeHistoryScreen extends StatefulWidget {
  const ChangeHistoryScreen({super.key, required this.medicineId});

  final String medicineId;

  @override
  State<ChangeHistoryScreen> createState() => _ChangeHistoryScreenState();
}

class _ChangeHistoryScreenState extends State<ChangeHistoryScreen> {
  List<MedicineEdit>? _edits;
  Map<String, String> _names = {};
  String? _error;

  // Family-delivery status (#98): the medicine owner's (the patient's) last
  // confirmed-synced timestamp, fetched once per load and compared against
  // each edit's `createdAt`. Null means either the profile hasn't loaded yet
  // or that device has never confirmed a sync — both read as "pending".
  DateTime? _ownerLastSyncedAt;

  String? get _me => AuthService.instance.currentUser?.id;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final edits = await CareService.instance.medicineEdits(widget.medicineId);
      final ids = {
        for (final e in edits)
          if (e.actorId != null) e.actorId!,
      };
      final names = <String, String>{};
      for (final id in ids) {
        if (id == _me) continue;
        final name = await CareService.instance.displayName(id);
        if (name != null) names[id] = name;
      }
      // Every row shares one ownerId (they're all edits to the same
      // medicine), so one profile fetch covers the whole list.
      DateTime? lastSyncedAt;
      if (edits.isNotEmpty) {
        final owner = await CareService.instance.profile(edits.first.ownerId);
        lastSyncedAt = owner?.lastSyncedAt;
      }
      if (!mounted) return;
      setState(() {
        _edits = edits;
        _names = names;
        _ownerLastSyncedAt = lastSyncedAt;
        _error = null;
      });
    } on CareLinkFailure catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('What changed')),
      body: SafeArea(
        child: MedicynContent(
          child: RefreshIndicator(onRefresh: _load, child: _body()),
        ),
      ),
    );
  }

  Widget _body() {
    if (_error != null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(28),
        children: [Text(_error!, textAlign: TextAlign.center)],
      );
    }
    final edits = _edits;
    if (edits == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (edits.isEmpty) {
      return MedicynFadeIn(
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(28),
          children: const [
            Text(
              'No changes recorded yet. Edits made after this update will show up here.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }
    return MedicynFadeIn(
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        itemCount: edits.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (context, i) {
          final edit = edits[i];
          final who = edit.actorId == null
              ? 'Someone'
              : edit.actorId == _me
              ? 'You'
              : (_names[edit.actorId] ?? 'Someone');
          final delivered = editDelivered(
            editCreatedAt: edit.createdAt,
            recipientLastSyncedAt: _ownerLastSyncedAt,
          );
          final scheme = Theme.of(context).colorScheme;
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    edit.summary,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$who · ${describeRelativeDay(edit.createdAt)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        delivered
                            ? Icons.check_circle_outline
                            : Icons.schedule_outlined,
                        size: 14,
                        color: delivered
                            ? scheme.primary
                            : scheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        // "as of last sync" is the honest framing: this is a
                        // snapshot from the recipient's last confirmed pull,
                        // not a live read-receipt.
                        describeDeliveryStatus(delivered),
                        style: Theme.of(context).textTheme.labelSmall
                            ?.copyWith(
                              color: delivered
                                  ? scheme.primary
                                  : scheme.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
