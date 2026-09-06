import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/motion.dart';
import '../../core/widgets/medicyn_chrome.dart';
import '../../core/widgets/medicyn_layout.dart';
import '../../core/widgets/medicyn_motion.dart';
import '../../data/local/database.dart';
import '../auth/auth_service.dart';
import '../care/edit_attribution.dart';
import 'reminder_card.dart';

/// The cabinet: every reminder, plus the place to add another. Home is the
/// calendar of a day; this screen is what you are taking.
class MedicinesListScreen extends StatefulWidget {
  const MedicinesListScreen({
    super.key,
    required this.db,
    required this.names,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
    this.embedded = false,
    this.active = true,
  });

  final AppDatabase db;
  final Map<String, String> names;
  final VoidCallback onAdd;
  final Future<void> Function(ScheduleWithMedicine) onEdit;
  final Future<void> Function(ScheduleWithMedicine) onDelete;
  final bool embedded;
  final bool active;

  @override
  State<MedicinesListScreen> createState() => _MedicinesListScreenState();
}

class _MedicinesListScreenState extends State<MedicinesListScreen> {
  late final ScrollController _scrollController = ScrollController();
  final _listKey = GlobalKey<SliverAnimatedListState>();

  /// Mirrors exactly what [SliverAnimatedList] currently displays. Every
  /// mutation goes through [_applyDiff] and its insertItem/removeItem calls
  /// — never replaced wholesale — so this can never drift out of sync with
  /// the animated list's own internal item count.
  final List<ScheduleWithMedicine> _items = [];

  StreamSubscription<List<ScheduleWithMedicine>>? _subscription;
  bool _loading = true;
  bool _hasError = false;

  /// How many remove animations are still playing. While this is above
  /// zero, an emptied [_items] does not yet swap to [_EmptyState] — that
  /// swap would tear down the very [SliverAnimatedList] mid-animation,
  /// snapping the last card away instead of letting it fade out.
  int _removingCount = 0;

  /// Tracks each pending "the remove animation finished" timer so [dispose]
  /// can cancel them. A bare `Future.delayed` has no handle to cancel —
  /// its `Timer` fires regardless, and even a `mounted`-guarded no-op
  /// callback still leaves that Timer live past teardown, which is a real
  /// leak outside tests and a hard failure inside them ("A Timer is still
  /// pending even after the widget tree was disposed").
  final Set<Timer> _removalTimers = {};

  @override
  void initState() {
    super.initState();
    _subscription = widget.db.watchSchedulesWithMedicines().listen(
      (newItems) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _hasError = false;
        });
        _applyDiff(newItems);
      },
      onError: (Object _) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _hasError = true;
        });
      },
    );
  }

  @override
  void didUpdateWidget(covariant MedicinesListScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.active && widget.active) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scrollController.hasClients) return;
        _scrollController.jumpTo(0);
      });
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    for (final timer in _removalTimers) {
      timer.cancel();
    }
    _scrollController.dispose();
    super.dispose();
  }

  /// Reconciles [_items] (and the mounted [SliverAnimatedList]) with a new
  /// stream snapshot via each side's longest common subsequence of schedule
  /// ids. Surviving items keep their relative order — true for any plain
  /// insert or delete, which is all this table's un-ordered `SELECT` ever
  /// produces in practice — so this never needs to model a genuine
  /// reorder; a same-id item that did move would simply be treated as a
  /// remove-then-insert, which stays correct even if the assumption above
  /// were ever violated.
  void _applyDiff(List<ScheduleWithMedicine> newItems) {
    final oldIds = [for (final item in _items) item.schedule.id];
    final newIds = [for (final item in newItems) item.schedule.id];
    final matchInOld = _lcsMatch(oldIds, newIds);

    for (var i = oldIds.length - 1; i >= 0; i--) {
      if (matchInOld[i] != -1) continue;
      final removed = _items.removeAt(i);
      _removingCount++;
      final duration = MedicynMotion.duration(context, MedicynMotion.medium);
      _listKey.currentState?.removeItem(
        i,
        (context, animation) => _buildRow(removed, animation),
        duration: duration,
      );
      late final Timer timer;
      timer = Timer(duration, () {
        _removalTimers.remove(timer);
        if (!mounted) return;
        setState(() => _removingCount--);
      });
      _removalTimers.add(timer);
    }

    // `matchInOld` filtered to the kept ids, in original relative order,
    // gives each surviving item's target index in `newItems`.
    final keptTargets = [
      for (final target in matchInOld)
        if (target != -1) target,
    ];
    var kept = 0;
    for (var j = 0; j < newItems.length; j++) {
      if (kept < keptTargets.length && keptTargets[kept] == j) {
        _items[j] = newItems[j]; // same id; refresh in case content changed.
        kept++;
      } else {
        _items.insert(j, newItems[j]);
        _listKey.currentState?.insertItem(
          j,
          duration: MedicynMotion.duration(context, MedicynMotion.medium),
        );
      }
    }
  }

  /// For each index in [a], the matching index in [b] under their longest
  /// common subsequence, or -1 when that element of [a] isn't in the LCS.
  /// Lists here are a person's own medicine count — small enough that the
  /// classic O(n·m) DP is effectively instant.
  static List<int> _lcsMatch(List<String> a, List<String> b) {
    final n = a.length, m = b.length;
    final dp = List.generate(n + 1, (_) => List<int>.filled(m + 1, 0));
    for (var i = n - 1; i >= 0; i--) {
      for (var j = m - 1; j >= 0; j--) {
        dp[i][j] = a[i] == b[j]
            ? dp[i + 1][j + 1] + 1
            : (dp[i + 1][j] >= dp[i][j + 1] ? dp[i + 1][j] : dp[i][j + 1]);
      }
    }
    final match = List<int>.filled(n, -1);
    var i = 0, j = 0;
    while (i < n && j < m) {
      if (a[i] == b[j]) {
        match[i] = j;
        i++;
        j++;
      } else if (dp[i + 1][j] >= dp[i][j + 1]) {
        i++;
      } else {
        j++;
      }
    }
    return match;
  }

  Widget _buildRow(ScheduleWithMedicine item, Animation<double> animation) {
    return SizeTransition(
      key: ValueKey(item.schedule.id),
      sizeFactor: CurvedAnimation(
        parent: animation,
        curve: MedicynMotion.decelerate,
      ),
      child: FadeTransition(
        opacity: animation,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: ReminderCard(
            item: item,
            db: widget.db,
            attribution: editAttributionLine(
              updatedBy: item.schedule.updatedBy ?? item.medicine.updatedBy,
              updatedAt:
                  item.schedule.updatedAt.isAfter(item.medicine.updatedAt)
                  ? item.schedule.updatedAt
                  : item.medicine.updatedAt,
              createdAt: item.medicine.createdAt,
              currentUserId: AuthService.instance.currentUser?.id,
              nameOf: (id) => widget.names[id],
            ),
            onTap: () => widget.onEdit(item),
            onDelete: () => widget.onDelete(item),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: widget.embedded
          ? AppBar(
              automaticallyImplyLeading: false,
              toolbarHeight: 64,
              titleSpacing: 20,
              title: const MedicynBrandMark(compact: true),
            )
          : AppBar(title: const Text('My medicines')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: widget.onAdd,
        icon: const Icon(Icons.add),
        label: const Text('Add medicine'),
      ),
      body: MedicynContent(child: _body()),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_hasError) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_outlined, size: 48),
              const SizedBox(height: 12),
              const Text(
                'Could not load your reminders. Your saved data is still on this phone.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }
    // The last card's own remove animation is still playing — the empty
    // state waits for it rather than swapping the list out from under it.
    if (_items.isEmpty && _removingCount == 0) {
      return MedicynFadeIn(child: _EmptyState(embedded: widget.embedded));
    }
    return MedicynFadeIn(
      child: CustomScrollView(
        controller: _scrollController,
        slivers: [
          if (widget.embedded)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Your plan',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Everything you take, and when.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 96),
            sliver: SliverAnimatedList(
              key: _listKey,
              initialItemCount: _items.length,
              itemBuilder: (context, index, animation) =>
                  _buildRow(_items[index], animation),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({this.embedded = false});
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(32, 32, 32, 96),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (embedded) ...[
              Text(
                'Your plan',
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
            ],
            Icon(
              Icons.medication_outlined,
              size: 64,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              'No reminders yet',
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Scan a label or speak the details.',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
