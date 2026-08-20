import 'package:flutter/material.dart';

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

  String? get _me => AuthService.instance.currentUser?.id;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final edits = await CareService.instance.medicineEdits(widget.medicineId);
      final ids = {for (final e in edits) if (e.actorId != null) e.actorId!};
      final names = <String, String>{};
      for (final id in ids) {
        if (id == _me) continue;
        final name = await CareService.instance.displayName(id);
        if (name != null) names[id] = name;
      }
      if (!mounted) return;
      setState(() {
        _edits = edits;
        _names = names;
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
      body: SafeArea(child: RefreshIndicator(onRefresh: _load, child: _body())),
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
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(28),
        children: const [
          Text(
            'No changes recorded yet. Edits made after this update will show up here.',
            textAlign: TextAlign.center,
          ),
        ],
      );
    }
    return ListView.separated(
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
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(edit.summary, style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 4),
                Text(
                  '$who · ${describeRelativeDay(edit.createdAt)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
