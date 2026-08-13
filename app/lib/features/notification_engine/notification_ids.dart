/// Deterministic, stable notification IDs derived from a schedule id + a
/// slot key (a time-of-day like "08:00", or an occurrence index for
/// every-X-hours schedules). Same inputs always produce the same id, so
/// re-scheduling on reconciliation naturally overwrites the right alarm
/// instead of piling up duplicates.
int notificationIdFor(String scheduleId, String slotKey) {
  final combined = '$scheduleId|$slotKey';
  var hash = 0x811c9dc5; // FNV-1a 32-bit offset basis
  for (final codeUnit in combined.codeUnits) {
    hash ^= codeUnit;
    hash = (hash * 0x01000193) & 0x7fffffff; // keep positive, fits Android's int id
  }
  return hash == 0 ? 1 : hash;
}
