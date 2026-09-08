import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medicyn/data/local/database.dart';
import 'package:medicyn/data/local/tables.dart';

/// N3: the emergency card's storage is a single local-only row. These cover
/// the upsert-by-singleton behaviour that the rest of the feature (the
/// screen, the PDF, the GDPR export) all build on.
void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('emergencyInfoOnce is null before anything is saved', () async {
    expect(await db.emergencyInfoOnce(), isNull);
  });

  test('upsertEmergencyInfo creates the singleton row', () async {
    await db.upsertEmergencyInfo(
      bloodGroup: 'O+',
      allergies: 'Penicillin',
      conditions: 'Type 2 diabetes',
    );

    final info = await db.emergencyInfoOnce();
    expect(info, isNotNull);
    expect(info!.id, EmergencyInfo.singletonId);
    expect(info.bloodGroup, 'O+');
    expect(info.allergies, 'Penicillin');
    expect(info.conditions, 'Type 2 diabetes');
  });

  test('a second save overwrites the same row rather than adding one', () async {
    await db.upsertEmergencyInfo(
      bloodGroup: 'O+',
      allergies: 'Penicillin',
      conditions: 'Type 2 diabetes',
    );
    await db.upsertEmergencyInfo(
      bloodGroup: 'AB-',
      allergies: '',
      conditions: 'Asthma',
    );

    final rows = await db.select(db.emergencyInfo).get();
    expect(rows, hasLength(1));
    expect(rows.single.bloodGroup, 'AB-');
    expect(rows.single.allergies, '');
    expect(rows.single.conditions, 'Asthma');
  });

  test('fields are trimmed before storage', () async {
    await db.upsertEmergencyInfo(
      bloodGroup: '  O+  ',
      allergies: '  Penicillin  ',
      conditions: '  ',
    );

    final info = await db.emergencyInfoOnce();
    expect(info!.bloodGroup, 'O+');
    expect(info.allergies, 'Penicillin');
    expect(info.conditions, '');
  });

  test('watchEmergencyInfo emits after a save', () async {
    final emissions = <EmergencyInfoData?>[];
    final sub = db.watchEmergencyInfo().listen(emissions.add);
    await pumpEventQueue();

    await db.upsertEmergencyInfo(
      bloodGroup: 'A+',
      allergies: '',
      conditions: '',
    );
    await pumpEventQueue();

    await sub.cancel();
    expect(emissions.first, isNull);
    expect(emissions.last?.bloodGroup, 'A+');
  });
}
