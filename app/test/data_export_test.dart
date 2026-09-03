import 'dart:convert';

import 'package:medicyn/core/app_settings.dart';
import 'package:medicyn/data/export/data_export_service.dart';
import 'package:medicyn/data/local/database.dart';
import 'package:medicyn/data/local/tables.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    AppSettings.instance.resetForTest();
    await AppSettings.instance.init();
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await db.upsertMedicine(
      MedicinesCompanion.insert(
        id: 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
        drugName: 'Metformin',
      ),
    );
    await db.upsertSchedule(
      SchedulesCompanion.insert(
        id: 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
        medicineId: 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
        frequencyType: FrequencyType.daily.name,
        times: const ['09:00'],
      ),
    );
    await db.recordDoseAction(
      id: 'cccccccc-cccc-cccc-cccc-cccccccccccc',
      scheduleId: 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
      scheduledAt: DateTime.utc(2026, 8, 20, 9),
      action: DoseAction.taken,
      loggedAt: DateTime.utc(2026, 8, 20, 9, 2),
    );
  });

  tearDown(() async {
    await db.close();
    AppSettings.instance.resetForTest();
  });

  test('export JSON contains the drug name and log action', () async {
    final export = await DataExportService(
      db,
    ).buildExport(now: DateTime.utc(2026, 8, 20, 12));
    final encoded = jsonEncode(export);

    expect(encoded, contains('Metformin'));
    expect(encoded, contains('taken'));

    expect(export['metadata']['app_version'], '0.1.0+1');
    expect(
      export['metadata']['schema_version'],
      DataExportService.exportSchemaVersion,
    );
    expect(export['metadata']['exported_at'], '2026-08-20T12:00:00.000Z');
    expect(export['metadata']['local_only'], isTrue);
    expect(export['medicines'], isNotEmpty);
    expect(export['dose_logs'], isNotEmpty);
    expect(export['consents'], isA<Map>());
    expect(export.containsKey('profile'), isFalse);

    for (final secret in exportExcludedSecrets) {
      expect(encoded.toLowerCase(), isNot(contains(secret)));
    }
  });

  test('works with no account and still includes local consents', () async {
    await AppSettings.instance.setConsentCloudBackup(true);
    final export = await DataExportService(db).buildExport();
    expect(export['consents']['cloud_backup'], isTrue);
    expect(export['consents']['anthropic_parse'], isFalse);
    expect(export['metadata']['local_only'], isTrue);
  });
}
