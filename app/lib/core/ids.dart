import 'dart:math';

final _rand = Random.secure();

/// A random UUID v4 string, generated locally so records can be created
/// offline and still match Supabase's uuid primary keys on sync.
String newUuid() {
  final bytes = List<int>.generate(16, (_) => _rand.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
  bytes[8] = (bytes[8] & 0x3f) | 0x80; // variant 10

  String hex(int start, int end) =>
      bytes.sublist(start, end).map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  return '${hex(0, 4)}-${hex(4, 6)}-${hex(6, 8)}-${hex(8, 10)}-${hex(10, 16)}';
}
