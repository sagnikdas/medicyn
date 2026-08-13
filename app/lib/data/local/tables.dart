import 'package:drift/drift.dart';

import 'converters.dart';

/// Frequency types a schedule can have. Stored as plain text (`.name`) in
/// the DB — kept as an enum in Dart for exhaustiveness checks everywhere else.
enum FrequencyType { daily, specificDays, everyXHours, asNeeded }

/// What happened to a scheduled dose. Stored as plain text (`.name`).
enum DoseAction { taken, snoozed, missed }

class Medicines extends Table {
  TextColumn get id => text()(); // client-generated uuid, matches Supabase PK
  TextColumn get drugName => text()();
  TextColumn get strength => text().withDefault(const Constant(''))();
  TextColumn get form => text().withDefault(const Constant(''))();
  TextColumn get doseAmount => text().withDefault(const Constant(''))();
  TextColumn get notes => text().withDefault(const Constant(''))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  BoolColumn get pendingSync => boolean().withDefault(const Constant(true))();
  BoolColumn get deleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

class Schedules extends Table {
  TextColumn get id => text()();
  TextColumn get medicineId =>
      text().references(Medicines, #id, onDelete: KeyAction.cascade)();
  TextColumn get frequencyType => text()();
  TextColumn get times => text().map(const StringListConverter())();
  TextColumn get daysOfWeek =>
      text().map(const IntListConverter()).withDefault(const Constant('[]'))();
  // Only set when frequencyType == everyXHours; times[0] is the anchor time
  // of the first dose, repeats every intervalHours after that.
  IntColumn get intervalHours => integer().nullable()();
  BoolColumn get active => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  BoolColumn get pendingSync => boolean().withDefault(const Constant(true))();
  BoolColumn get deleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

class DoseLogs extends Table {
  TextColumn get id => text()();
  TextColumn get scheduleId =>
      text().references(Schedules, #id, onDelete: KeyAction.cascade)();
  DateTimeColumn get scheduledAt => dateTime()();
  TextColumn get action => text()();
  DateTimeColumn get loggedAt => dateTime().withDefault(currentDateAndTime)();
  TextColumn get source => text().withDefault(const Constant('notification'))();
  BoolColumn get pendingSync => boolean().withDefault(const Constant(true))();

  @override
  Set<Column> get primaryKey => {id};
}
