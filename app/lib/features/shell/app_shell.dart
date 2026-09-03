import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/motion.dart';
import '../../core/widgets/medicyn_chrome.dart';
import '../../core/widgets/medicyn_layout.dart';
import '../../core/widgets/medicyn_motion.dart';
import '../../data/local/database.dart';
import '../auth/auth_service.dart';
import '../insights/insights_screen.dart';
import '../reminders_home/home_screen.dart';
import '../reminders_home/medicines_list_screen.dart';
import '../settings/settings_screen.dart';

/// Four tabs from the Stitch mobile chrome: Today, Plan, Insights, Profile.
///
/// [HomeScreen] stays mounted (IndexedStack) so the resume observer that
/// re-arms alarms and sweeps missed doses keeps running while the person
/// is on another tab.
class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.db});

  final AppDatabase db;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;
  Map<String, String> _names = {};
  final _homeKey = GlobalKey<HomeScreenState>();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: MedicynContent(
        child: MedicynIndexedStack(
          index: _index,
          sizing: StackFit.expand,
          children: [
            HomeScreen(
              key: _homeKey,
              db: widget.db,
              active: _index == 0,
              onNeedsAttention: () {
                if (_index == 0) return;
                setState(() => _index = 0);
              },
              onNames: (names) {
                if (!mounted) return;
                setState(() => _names = names);
              },
            ),
            MedicinesListScreen(
              db: widget.db,
              names: _names,
              embedded: true,
              active: _index == 1,
              onAdd: () {
                unawaited(
                  _homeKey.currentState?.startCapture() ?? Future.value(),
                );
              },
              onEdit: (item) async {
                await _homeKey.currentState?.edit(item);
              },
              onDelete: (item) async {
                await _homeKey.currentState?.delete(item);
              },
            ),
            InsightsScreen(db: widget.db, active: _index == 2),
            SettingsScreen(db: widget.db, embedded: true, active: _index == 3),
          ],
        ),
      ),
      bottomNavigationBar: MedicynBottomNav(
        index: _index,
        profileImageUrl: AuthService.instance.currentUserAvatarUrl,
        onChanged: (i) {
          if (i == _index) return;
          MedicynMotion.selection(context);
          setState(() => _index = i);
        },
      ),
    );
  }
}
