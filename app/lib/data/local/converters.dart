import 'dart:convert';

import 'package:drift/drift.dart';

/// Stores a `List<String>` (e.g. dose times as "HH:mm") as a JSON TEXT column.
class StringListConverter extends TypeConverter<List<String>, String>
    with JsonTypeConverter2<List<String>, String, Object?> {
  const StringListConverter();

  @override
  List<String> fromSql(String fromDb) =>
      (jsonDecode(fromDb) as List).map((e) => e as String).toList();

  @override
  String toSql(List<String> value) => jsonEncode(value);

  @override
  List<String> fromJson(Object? json) =>
      (json as List).map((e) => e as String).toList();

  @override
  Object? toJson(List<String> value) => value;
}

/// Stores a `List<int>` (e.g. days of week, 0=Sunday..6=Saturday) as JSON TEXT.
class IntListConverter extends TypeConverter<List<int>, String>
    with JsonTypeConverter2<List<int>, String, Object?> {
  const IntListConverter();

  @override
  List<int> fromSql(String fromDb) =>
      (jsonDecode(fromDb) as List).map((e) => e as int).toList();

  @override
  String toSql(List<int> value) => jsonEncode(value);

  @override
  List<int> fromJson(Object? json) =>
      (json as List).map((e) => e as int).toList();

  @override
  Object? toJson(List<int> value) => value;
}
