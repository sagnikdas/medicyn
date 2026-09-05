import 'package:drift/drift.dart';

import 'converters.dart';

/// Frequency types a schedule can have. Stored as plain text (`.name`) in
/// the DB — kept as an enum in Dart for exhaustiveness checks everywhere else.
enum FrequencyType { daily, specificDays, everyXHours, asNeeded }

/// Lifecycle state of a reminder definition. `null` on legacy rows means the
/// pre-Phase-3 model; callers should use [reminderStatus] to get the safe
/// backwards-compatible interpretation.
enum ReminderStatus { active, paused, completed, asNeeded }

/// What happened to a scheduled dose. Stored as plain text (`.name`).
enum DoseAction { taken, snoozed, missed }

class Medicines extends Table {
  TextColumn get id => text()(); // client-generated uuid, matches Supabase PK
  TextColumn get drugName => text()();
  TextColumn get strength => text().withDefault(const Constant(''))();
  TextColumn get form => text().withDefault(const Constant(''))();
  TextColumn get doseAmount => text().withDefault(const Constant(''))();
  // Null means the bottle is not being tracked. This is a baseline, not a
  // live count: it only changes when a save (either side of a care link)
  // writes a new number, which is how a refill is logged. The count actually
  // shown anywhere derives this against doses taken since [updatedAt] — see
  // `derivedTabletsRemaining` — rather than being decremented in place, so a
  // caregiver's concurrent edit can never revert a dose this device already
  // took.
  IntColumn get tabletsRemaining => integer().nullable()();
  IntColumn get tabletsPerDose => integer().nullable()();
  TextColumn get notes => text().withDefault(const Constant(''))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  // Client-stamped, and compared against the server's copy to decide which
  // version of a row wins. See the row_versioning migration for why this is
  // the client's clock and not the server's.
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  // Null for rows that predate versioning — their author is genuinely
  // unknown, and the UI should say so rather than guess.
  TextColumn get updatedBy => text().nullable()();
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

  /// Nullable so databases upgraded from v5 can be read before the migration
  /// has populated a value, and so existing callers remain source-compatible.
  TextColumn get status => text().nullable()();
  DateTimeColumn get startDate => dateTime().nullable()();
  DateTimeColumn get endDate => dateTime().nullable()();
  DateTimeColumn get pauseUntil => dateTime().nullable()();
  BoolColumn get active => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  TextColumn get updatedBy => text().nullable()();
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

/// A user correction attached to an immutable dose log. The log's [DoseLogs.action]
/// and timestamps never change; this row is the Art. 16 path.
class DoseLogContests extends Table {
  TextColumn get doseLogId =>
      text().references(DoseLogs, #id, onDelete: KeyAction.cascade)();
  TextColumn get note => text()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  BoolColumn get pendingSync => boolean().withDefault(const Constant(true))();

  @override
  Set<Column> get primaryKey => {doseLogId};
}

/// Optional, device-local care agenda on Android Today. Kept in the same
/// encrypted, per-account file as doses, but never treated as medication.
class TodayCareReminders extends Table {
  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get kind => text()();
  DateTimeColumn get scheduledAt => dateTime()();
  TextColumn get location => text().withDefault(const Constant(''))();
  TextColumn get notes => text().withDefault(const Constant(''))();
  IntColumn get reminderMinutes => integer().nullable()();
  BoolColumn get completed => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}
