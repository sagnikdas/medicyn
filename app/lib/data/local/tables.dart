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

/// N3, the emergency card: a single local-only row (id is always [singletonId])
/// holding the facts a first responder or a new clinician needs that Medicyn
/// has no other reason to ask for. Deliberately not synced -- unlike
/// medicines and schedules, this never needs to reach a caregiver's phone;
/// the card's whole purpose is a physical or on-device copy that travels
/// with the person it describes, not a shared record. See N3's own note in
/// MEDICYN.md: it must never be a lock-screen surface.
class EmergencyInfo extends Table {
  TextColumn get id => text()();
  TextColumn get bloodGroup => text().withDefault(const Constant(''))();
  TextColumn get allergies => text().withDefault(const Constant(''))();
  // True marks an allergy severe/anaphylaxis-risk rather than mild, so the
  // card can call it out instead of burying it in the same plain text as
  // everything else.
  BoolColumn get allergiesSevere =>
      boolean().withDefault(const Constant(false))();
  TextColumn get conditions => text().withDefault(const Constant(''))();
  // Anything that doesn't fit the fields above -- pacemaker, pregnant, DNR
  // on file -- for a first responder who only has seconds to read this.
  TextColumn get notes => text().withDefault(const Constant(''))();
  TextColumn get insuranceNumber => text().withDefault(const Constant(''))();
  // Deliberately one generic field rather than a country-gated one: the app
  // has no reliable signal for which country's ID a person means (Aadhaar,
  // SSN, NHS number, ...), so the edit form labels this "National ID" and
  // lets the person write whichever applies.
  TextColumn get nationalId => text().withDefault(const Constant(''))();
  TextColumn get healthCardNumber => text().withDefault(const Constant(''))();
  // A person to call in an emergency, entered directly on this card --
  // independent of the Family care-link feature, which only ever names a
  // caregiver for whoever is the *patient* side of a link (and says
  // nothing for someone with no link at all, or who is themselves the
  // caregiver). Everyone filling out this card should be able to name
  // someone, whether or not they use Family sharing.
  TextColumn get emergencyContactName =>
      text().withDefault(const Constant(''))();
  TextColumn get emergencyContactPhone =>
      text().withDefault(const Constant(''))();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};

  static const singletonId = 'self';
}

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

/// Supabase-backed care agenda, cached in the encrypted per-account file
/// for offline access and notifications. Deleted rows remain as sync tombstones.
class TodayCareReminders extends Table {
  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get kind => text()();
  DateTimeColumn get scheduledAt => dateTime()();
  TextColumn get location => text().withDefault(const Constant(''))();
  TextColumn get notes => text().withDefault(const Constant(''))();
  IntColumn get reminderMinutes => integer().nullable()();
  BoolColumn get completed => boolean().withDefault(const Constant(false))();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  BoolColumn get pendingSync => boolean().withDefault(const Constant(true))();
  BoolColumn get deleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}
