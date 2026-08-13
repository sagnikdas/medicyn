// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $MedicinesTable extends Medicines
    with TableInfo<$MedicinesTable, Medicine> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MedicinesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _drugNameMeta = const VerificationMeta(
    'drugName',
  );
  @override
  late final GeneratedColumn<String> drugName = GeneratedColumn<String>(
    'drug_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _strengthMeta = const VerificationMeta(
    'strength',
  );
  @override
  late final GeneratedColumn<String> strength = GeneratedColumn<String>(
    'strength',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _formMeta = const VerificationMeta('form');
  @override
  late final GeneratedColumn<String> form = GeneratedColumn<String>(
    'form',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _doseAmountMeta = const VerificationMeta(
    'doseAmount',
  );
  @override
  late final GeneratedColumn<String> doseAmount = GeneratedColumn<String>(
    'dose_amount',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _notesMeta = const VerificationMeta('notes');
  @override
  late final GeneratedColumn<String> notes = GeneratedColumn<String>(
    'notes',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _pendingSyncMeta = const VerificationMeta(
    'pendingSync',
  );
  @override
  late final GeneratedColumn<bool> pendingSync = GeneratedColumn<bool>(
    'pending_sync',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("pending_sync" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _deletedMeta = const VerificationMeta(
    'deleted',
  );
  @override
  late final GeneratedColumn<bool> deleted = GeneratedColumn<bool>(
    'deleted',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("deleted" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    drugName,
    strength,
    form,
    doseAmount,
    notes,
    createdAt,
    pendingSync,
    deleted,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'medicines';
  @override
  VerificationContext validateIntegrity(
    Insertable<Medicine> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('drug_name')) {
      context.handle(
        _drugNameMeta,
        drugName.isAcceptableOrUnknown(data['drug_name']!, _drugNameMeta),
      );
    } else if (isInserting) {
      context.missing(_drugNameMeta);
    }
    if (data.containsKey('strength')) {
      context.handle(
        _strengthMeta,
        strength.isAcceptableOrUnknown(data['strength']!, _strengthMeta),
      );
    }
    if (data.containsKey('form')) {
      context.handle(
        _formMeta,
        form.isAcceptableOrUnknown(data['form']!, _formMeta),
      );
    }
    if (data.containsKey('dose_amount')) {
      context.handle(
        _doseAmountMeta,
        doseAmount.isAcceptableOrUnknown(data['dose_amount']!, _doseAmountMeta),
      );
    }
    if (data.containsKey('notes')) {
      context.handle(
        _notesMeta,
        notes.isAcceptableOrUnknown(data['notes']!, _notesMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('pending_sync')) {
      context.handle(
        _pendingSyncMeta,
        pendingSync.isAcceptableOrUnknown(
          data['pending_sync']!,
          _pendingSyncMeta,
        ),
      );
    }
    if (data.containsKey('deleted')) {
      context.handle(
        _deletedMeta,
        deleted.isAcceptableOrUnknown(data['deleted']!, _deletedMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Medicine map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Medicine(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      drugName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}drug_name'],
      )!,
      strength: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}strength'],
      )!,
      form: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}form'],
      )!,
      doseAmount: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}dose_amount'],
      )!,
      notes: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}notes'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      pendingSync: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}pending_sync'],
      )!,
      deleted: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}deleted'],
      )!,
    );
  }

  @override
  $MedicinesTable createAlias(String alias) {
    return $MedicinesTable(attachedDatabase, alias);
  }
}

class Medicine extends DataClass implements Insertable<Medicine> {
  final String id;
  final String drugName;
  final String strength;
  final String form;
  final String doseAmount;
  final String notes;
  final DateTime createdAt;
  final bool pendingSync;
  final bool deleted;
  const Medicine({
    required this.id,
    required this.drugName,
    required this.strength,
    required this.form,
    required this.doseAmount,
    required this.notes,
    required this.createdAt,
    required this.pendingSync,
    required this.deleted,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['drug_name'] = Variable<String>(drugName);
    map['strength'] = Variable<String>(strength);
    map['form'] = Variable<String>(form);
    map['dose_amount'] = Variable<String>(doseAmount);
    map['notes'] = Variable<String>(notes);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['pending_sync'] = Variable<bool>(pendingSync);
    map['deleted'] = Variable<bool>(deleted);
    return map;
  }

  MedicinesCompanion toCompanion(bool nullToAbsent) {
    return MedicinesCompanion(
      id: Value(id),
      drugName: Value(drugName),
      strength: Value(strength),
      form: Value(form),
      doseAmount: Value(doseAmount),
      notes: Value(notes),
      createdAt: Value(createdAt),
      pendingSync: Value(pendingSync),
      deleted: Value(deleted),
    );
  }

  factory Medicine.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Medicine(
      id: serializer.fromJson<String>(json['id']),
      drugName: serializer.fromJson<String>(json['drugName']),
      strength: serializer.fromJson<String>(json['strength']),
      form: serializer.fromJson<String>(json['form']),
      doseAmount: serializer.fromJson<String>(json['doseAmount']),
      notes: serializer.fromJson<String>(json['notes']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      pendingSync: serializer.fromJson<bool>(json['pendingSync']),
      deleted: serializer.fromJson<bool>(json['deleted']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'drugName': serializer.toJson<String>(drugName),
      'strength': serializer.toJson<String>(strength),
      'form': serializer.toJson<String>(form),
      'doseAmount': serializer.toJson<String>(doseAmount),
      'notes': serializer.toJson<String>(notes),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'pendingSync': serializer.toJson<bool>(pendingSync),
      'deleted': serializer.toJson<bool>(deleted),
    };
  }

  Medicine copyWith({
    String? id,
    String? drugName,
    String? strength,
    String? form,
    String? doseAmount,
    String? notes,
    DateTime? createdAt,
    bool? pendingSync,
    bool? deleted,
  }) => Medicine(
    id: id ?? this.id,
    drugName: drugName ?? this.drugName,
    strength: strength ?? this.strength,
    form: form ?? this.form,
    doseAmount: doseAmount ?? this.doseAmount,
    notes: notes ?? this.notes,
    createdAt: createdAt ?? this.createdAt,
    pendingSync: pendingSync ?? this.pendingSync,
    deleted: deleted ?? this.deleted,
  );
  Medicine copyWithCompanion(MedicinesCompanion data) {
    return Medicine(
      id: data.id.present ? data.id.value : this.id,
      drugName: data.drugName.present ? data.drugName.value : this.drugName,
      strength: data.strength.present ? data.strength.value : this.strength,
      form: data.form.present ? data.form.value : this.form,
      doseAmount: data.doseAmount.present
          ? data.doseAmount.value
          : this.doseAmount,
      notes: data.notes.present ? data.notes.value : this.notes,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      pendingSync: data.pendingSync.present
          ? data.pendingSync.value
          : this.pendingSync,
      deleted: data.deleted.present ? data.deleted.value : this.deleted,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Medicine(')
          ..write('id: $id, ')
          ..write('drugName: $drugName, ')
          ..write('strength: $strength, ')
          ..write('form: $form, ')
          ..write('doseAmount: $doseAmount, ')
          ..write('notes: $notes, ')
          ..write('createdAt: $createdAt, ')
          ..write('pendingSync: $pendingSync, ')
          ..write('deleted: $deleted')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    drugName,
    strength,
    form,
    doseAmount,
    notes,
    createdAt,
    pendingSync,
    deleted,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Medicine &&
          other.id == this.id &&
          other.drugName == this.drugName &&
          other.strength == this.strength &&
          other.form == this.form &&
          other.doseAmount == this.doseAmount &&
          other.notes == this.notes &&
          other.createdAt == this.createdAt &&
          other.pendingSync == this.pendingSync &&
          other.deleted == this.deleted);
}

class MedicinesCompanion extends UpdateCompanion<Medicine> {
  final Value<String> id;
  final Value<String> drugName;
  final Value<String> strength;
  final Value<String> form;
  final Value<String> doseAmount;
  final Value<String> notes;
  final Value<DateTime> createdAt;
  final Value<bool> pendingSync;
  final Value<bool> deleted;
  final Value<int> rowid;
  const MedicinesCompanion({
    this.id = const Value.absent(),
    this.drugName = const Value.absent(),
    this.strength = const Value.absent(),
    this.form = const Value.absent(),
    this.doseAmount = const Value.absent(),
    this.notes = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.pendingSync = const Value.absent(),
    this.deleted = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MedicinesCompanion.insert({
    required String id,
    required String drugName,
    this.strength = const Value.absent(),
    this.form = const Value.absent(),
    this.doseAmount = const Value.absent(),
    this.notes = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.pendingSync = const Value.absent(),
    this.deleted = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       drugName = Value(drugName);
  static Insertable<Medicine> custom({
    Expression<String>? id,
    Expression<String>? drugName,
    Expression<String>? strength,
    Expression<String>? form,
    Expression<String>? doseAmount,
    Expression<String>? notes,
    Expression<DateTime>? createdAt,
    Expression<bool>? pendingSync,
    Expression<bool>? deleted,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (drugName != null) 'drug_name': drugName,
      if (strength != null) 'strength': strength,
      if (form != null) 'form': form,
      if (doseAmount != null) 'dose_amount': doseAmount,
      if (notes != null) 'notes': notes,
      if (createdAt != null) 'created_at': createdAt,
      if (pendingSync != null) 'pending_sync': pendingSync,
      if (deleted != null) 'deleted': deleted,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MedicinesCompanion copyWith({
    Value<String>? id,
    Value<String>? drugName,
    Value<String>? strength,
    Value<String>? form,
    Value<String>? doseAmount,
    Value<String>? notes,
    Value<DateTime>? createdAt,
    Value<bool>? pendingSync,
    Value<bool>? deleted,
    Value<int>? rowid,
  }) {
    return MedicinesCompanion(
      id: id ?? this.id,
      drugName: drugName ?? this.drugName,
      strength: strength ?? this.strength,
      form: form ?? this.form,
      doseAmount: doseAmount ?? this.doseAmount,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      pendingSync: pendingSync ?? this.pendingSync,
      deleted: deleted ?? this.deleted,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (drugName.present) {
      map['drug_name'] = Variable<String>(drugName.value);
    }
    if (strength.present) {
      map['strength'] = Variable<String>(strength.value);
    }
    if (form.present) {
      map['form'] = Variable<String>(form.value);
    }
    if (doseAmount.present) {
      map['dose_amount'] = Variable<String>(doseAmount.value);
    }
    if (notes.present) {
      map['notes'] = Variable<String>(notes.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (pendingSync.present) {
      map['pending_sync'] = Variable<bool>(pendingSync.value);
    }
    if (deleted.present) {
      map['deleted'] = Variable<bool>(deleted.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MedicinesCompanion(')
          ..write('id: $id, ')
          ..write('drugName: $drugName, ')
          ..write('strength: $strength, ')
          ..write('form: $form, ')
          ..write('doseAmount: $doseAmount, ')
          ..write('notes: $notes, ')
          ..write('createdAt: $createdAt, ')
          ..write('pendingSync: $pendingSync, ')
          ..write('deleted: $deleted, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SchedulesTable extends Schedules
    with TableInfo<$SchedulesTable, Schedule> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SchedulesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _medicineIdMeta = const VerificationMeta(
    'medicineId',
  );
  @override
  late final GeneratedColumn<String> medicineId = GeneratedColumn<String>(
    'medicine_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES medicines (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _frequencyTypeMeta = const VerificationMeta(
    'frequencyType',
  );
  @override
  late final GeneratedColumn<String> frequencyType = GeneratedColumn<String>(
    'frequency_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<List<String>, String> times =
      GeneratedColumn<String>(
        'times',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<List<String>>($SchedulesTable.$convertertimes);
  @override
  late final GeneratedColumnWithTypeConverter<List<int>, String> daysOfWeek =
      GeneratedColumn<String>(
        'days_of_week',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('[]'),
      ).withConverter<List<int>>($SchedulesTable.$converterdaysOfWeek);
  static const VerificationMeta _intervalHoursMeta = const VerificationMeta(
    'intervalHours',
  );
  @override
  late final GeneratedColumn<int> intervalHours = GeneratedColumn<int>(
    'interval_hours',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _activeMeta = const VerificationMeta('active');
  @override
  late final GeneratedColumn<bool> active = GeneratedColumn<bool>(
    'active',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("active" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _pendingSyncMeta = const VerificationMeta(
    'pendingSync',
  );
  @override
  late final GeneratedColumn<bool> pendingSync = GeneratedColumn<bool>(
    'pending_sync',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("pending_sync" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _deletedMeta = const VerificationMeta(
    'deleted',
  );
  @override
  late final GeneratedColumn<bool> deleted = GeneratedColumn<bool>(
    'deleted',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("deleted" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    medicineId,
    frequencyType,
    times,
    daysOfWeek,
    intervalHours,
    active,
    createdAt,
    pendingSync,
    deleted,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'schedules';
  @override
  VerificationContext validateIntegrity(
    Insertable<Schedule> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('medicine_id')) {
      context.handle(
        _medicineIdMeta,
        medicineId.isAcceptableOrUnknown(data['medicine_id']!, _medicineIdMeta),
      );
    } else if (isInserting) {
      context.missing(_medicineIdMeta);
    }
    if (data.containsKey('frequency_type')) {
      context.handle(
        _frequencyTypeMeta,
        frequencyType.isAcceptableOrUnknown(
          data['frequency_type']!,
          _frequencyTypeMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_frequencyTypeMeta);
    }
    if (data.containsKey('interval_hours')) {
      context.handle(
        _intervalHoursMeta,
        intervalHours.isAcceptableOrUnknown(
          data['interval_hours']!,
          _intervalHoursMeta,
        ),
      );
    }
    if (data.containsKey('active')) {
      context.handle(
        _activeMeta,
        active.isAcceptableOrUnknown(data['active']!, _activeMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    if (data.containsKey('pending_sync')) {
      context.handle(
        _pendingSyncMeta,
        pendingSync.isAcceptableOrUnknown(
          data['pending_sync']!,
          _pendingSyncMeta,
        ),
      );
    }
    if (data.containsKey('deleted')) {
      context.handle(
        _deletedMeta,
        deleted.isAcceptableOrUnknown(data['deleted']!, _deletedMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Schedule map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Schedule(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      medicineId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}medicine_id'],
      )!,
      frequencyType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}frequency_type'],
      )!,
      times: $SchedulesTable.$convertertimes.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}times'],
        )!,
      ),
      daysOfWeek: $SchedulesTable.$converterdaysOfWeek.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}days_of_week'],
        )!,
      ),
      intervalHours: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}interval_hours'],
      ),
      active: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}active'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      pendingSync: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}pending_sync'],
      )!,
      deleted: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}deleted'],
      )!,
    );
  }

  @override
  $SchedulesTable createAlias(String alias) {
    return $SchedulesTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<List<String>, String, Object?> $convertertimes =
      const StringListConverter();
  static JsonTypeConverter2<List<int>, String, Object?> $converterdaysOfWeek =
      const IntListConverter();
}

class Schedule extends DataClass implements Insertable<Schedule> {
  final String id;
  final String medicineId;
  final String frequencyType;
  final List<String> times;
  final List<int> daysOfWeek;
  final int? intervalHours;
  final bool active;
  final DateTime createdAt;
  final bool pendingSync;
  final bool deleted;
  const Schedule({
    required this.id,
    required this.medicineId,
    required this.frequencyType,
    required this.times,
    required this.daysOfWeek,
    this.intervalHours,
    required this.active,
    required this.createdAt,
    required this.pendingSync,
    required this.deleted,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['medicine_id'] = Variable<String>(medicineId);
    map['frequency_type'] = Variable<String>(frequencyType);
    {
      map['times'] = Variable<String>(
        $SchedulesTable.$convertertimes.toSql(times),
      );
    }
    {
      map['days_of_week'] = Variable<String>(
        $SchedulesTable.$converterdaysOfWeek.toSql(daysOfWeek),
      );
    }
    if (!nullToAbsent || intervalHours != null) {
      map['interval_hours'] = Variable<int>(intervalHours);
    }
    map['active'] = Variable<bool>(active);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['pending_sync'] = Variable<bool>(pendingSync);
    map['deleted'] = Variable<bool>(deleted);
    return map;
  }

  SchedulesCompanion toCompanion(bool nullToAbsent) {
    return SchedulesCompanion(
      id: Value(id),
      medicineId: Value(medicineId),
      frequencyType: Value(frequencyType),
      times: Value(times),
      daysOfWeek: Value(daysOfWeek),
      intervalHours: intervalHours == null && nullToAbsent
          ? const Value.absent()
          : Value(intervalHours),
      active: Value(active),
      createdAt: Value(createdAt),
      pendingSync: Value(pendingSync),
      deleted: Value(deleted),
    );
  }

  factory Schedule.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Schedule(
      id: serializer.fromJson<String>(json['id']),
      medicineId: serializer.fromJson<String>(json['medicineId']),
      frequencyType: serializer.fromJson<String>(json['frequencyType']),
      times: $SchedulesTable.$convertertimes.fromJson(
        serializer.fromJson<Object?>(json['times']),
      ),
      daysOfWeek: $SchedulesTable.$converterdaysOfWeek.fromJson(
        serializer.fromJson<Object?>(json['daysOfWeek']),
      ),
      intervalHours: serializer.fromJson<int?>(json['intervalHours']),
      active: serializer.fromJson<bool>(json['active']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      pendingSync: serializer.fromJson<bool>(json['pendingSync']),
      deleted: serializer.fromJson<bool>(json['deleted']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'medicineId': serializer.toJson<String>(medicineId),
      'frequencyType': serializer.toJson<String>(frequencyType),
      'times': serializer.toJson<Object?>(
        $SchedulesTable.$convertertimes.toJson(times),
      ),
      'daysOfWeek': serializer.toJson<Object?>(
        $SchedulesTable.$converterdaysOfWeek.toJson(daysOfWeek),
      ),
      'intervalHours': serializer.toJson<int?>(intervalHours),
      'active': serializer.toJson<bool>(active),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'pendingSync': serializer.toJson<bool>(pendingSync),
      'deleted': serializer.toJson<bool>(deleted),
    };
  }

  Schedule copyWith({
    String? id,
    String? medicineId,
    String? frequencyType,
    List<String>? times,
    List<int>? daysOfWeek,
    Value<int?> intervalHours = const Value.absent(),
    bool? active,
    DateTime? createdAt,
    bool? pendingSync,
    bool? deleted,
  }) => Schedule(
    id: id ?? this.id,
    medicineId: medicineId ?? this.medicineId,
    frequencyType: frequencyType ?? this.frequencyType,
    times: times ?? this.times,
    daysOfWeek: daysOfWeek ?? this.daysOfWeek,
    intervalHours: intervalHours.present
        ? intervalHours.value
        : this.intervalHours,
    active: active ?? this.active,
    createdAt: createdAt ?? this.createdAt,
    pendingSync: pendingSync ?? this.pendingSync,
    deleted: deleted ?? this.deleted,
  );
  Schedule copyWithCompanion(SchedulesCompanion data) {
    return Schedule(
      id: data.id.present ? data.id.value : this.id,
      medicineId: data.medicineId.present
          ? data.medicineId.value
          : this.medicineId,
      frequencyType: data.frequencyType.present
          ? data.frequencyType.value
          : this.frequencyType,
      times: data.times.present ? data.times.value : this.times,
      daysOfWeek: data.daysOfWeek.present
          ? data.daysOfWeek.value
          : this.daysOfWeek,
      intervalHours: data.intervalHours.present
          ? data.intervalHours.value
          : this.intervalHours,
      active: data.active.present ? data.active.value : this.active,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      pendingSync: data.pendingSync.present
          ? data.pendingSync.value
          : this.pendingSync,
      deleted: data.deleted.present ? data.deleted.value : this.deleted,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Schedule(')
          ..write('id: $id, ')
          ..write('medicineId: $medicineId, ')
          ..write('frequencyType: $frequencyType, ')
          ..write('times: $times, ')
          ..write('daysOfWeek: $daysOfWeek, ')
          ..write('intervalHours: $intervalHours, ')
          ..write('active: $active, ')
          ..write('createdAt: $createdAt, ')
          ..write('pendingSync: $pendingSync, ')
          ..write('deleted: $deleted')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    medicineId,
    frequencyType,
    times,
    daysOfWeek,
    intervalHours,
    active,
    createdAt,
    pendingSync,
    deleted,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Schedule &&
          other.id == this.id &&
          other.medicineId == this.medicineId &&
          other.frequencyType == this.frequencyType &&
          other.times == this.times &&
          other.daysOfWeek == this.daysOfWeek &&
          other.intervalHours == this.intervalHours &&
          other.active == this.active &&
          other.createdAt == this.createdAt &&
          other.pendingSync == this.pendingSync &&
          other.deleted == this.deleted);
}

class SchedulesCompanion extends UpdateCompanion<Schedule> {
  final Value<String> id;
  final Value<String> medicineId;
  final Value<String> frequencyType;
  final Value<List<String>> times;
  final Value<List<int>> daysOfWeek;
  final Value<int?> intervalHours;
  final Value<bool> active;
  final Value<DateTime> createdAt;
  final Value<bool> pendingSync;
  final Value<bool> deleted;
  final Value<int> rowid;
  const SchedulesCompanion({
    this.id = const Value.absent(),
    this.medicineId = const Value.absent(),
    this.frequencyType = const Value.absent(),
    this.times = const Value.absent(),
    this.daysOfWeek = const Value.absent(),
    this.intervalHours = const Value.absent(),
    this.active = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.pendingSync = const Value.absent(),
    this.deleted = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SchedulesCompanion.insert({
    required String id,
    required String medicineId,
    required String frequencyType,
    required List<String> times,
    this.daysOfWeek = const Value.absent(),
    this.intervalHours = const Value.absent(),
    this.active = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.pendingSync = const Value.absent(),
    this.deleted = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       medicineId = Value(medicineId),
       frequencyType = Value(frequencyType),
       times = Value(times);
  static Insertable<Schedule> custom({
    Expression<String>? id,
    Expression<String>? medicineId,
    Expression<String>? frequencyType,
    Expression<String>? times,
    Expression<String>? daysOfWeek,
    Expression<int>? intervalHours,
    Expression<bool>? active,
    Expression<DateTime>? createdAt,
    Expression<bool>? pendingSync,
    Expression<bool>? deleted,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (medicineId != null) 'medicine_id': medicineId,
      if (frequencyType != null) 'frequency_type': frequencyType,
      if (times != null) 'times': times,
      if (daysOfWeek != null) 'days_of_week': daysOfWeek,
      if (intervalHours != null) 'interval_hours': intervalHours,
      if (active != null) 'active': active,
      if (createdAt != null) 'created_at': createdAt,
      if (pendingSync != null) 'pending_sync': pendingSync,
      if (deleted != null) 'deleted': deleted,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SchedulesCompanion copyWith({
    Value<String>? id,
    Value<String>? medicineId,
    Value<String>? frequencyType,
    Value<List<String>>? times,
    Value<List<int>>? daysOfWeek,
    Value<int?>? intervalHours,
    Value<bool>? active,
    Value<DateTime>? createdAt,
    Value<bool>? pendingSync,
    Value<bool>? deleted,
    Value<int>? rowid,
  }) {
    return SchedulesCompanion(
      id: id ?? this.id,
      medicineId: medicineId ?? this.medicineId,
      frequencyType: frequencyType ?? this.frequencyType,
      times: times ?? this.times,
      daysOfWeek: daysOfWeek ?? this.daysOfWeek,
      intervalHours: intervalHours ?? this.intervalHours,
      active: active ?? this.active,
      createdAt: createdAt ?? this.createdAt,
      pendingSync: pendingSync ?? this.pendingSync,
      deleted: deleted ?? this.deleted,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (medicineId.present) {
      map['medicine_id'] = Variable<String>(medicineId.value);
    }
    if (frequencyType.present) {
      map['frequency_type'] = Variable<String>(frequencyType.value);
    }
    if (times.present) {
      map['times'] = Variable<String>(
        $SchedulesTable.$convertertimes.toSql(times.value),
      );
    }
    if (daysOfWeek.present) {
      map['days_of_week'] = Variable<String>(
        $SchedulesTable.$converterdaysOfWeek.toSql(daysOfWeek.value),
      );
    }
    if (intervalHours.present) {
      map['interval_hours'] = Variable<int>(intervalHours.value);
    }
    if (active.present) {
      map['active'] = Variable<bool>(active.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (pendingSync.present) {
      map['pending_sync'] = Variable<bool>(pendingSync.value);
    }
    if (deleted.present) {
      map['deleted'] = Variable<bool>(deleted.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SchedulesCompanion(')
          ..write('id: $id, ')
          ..write('medicineId: $medicineId, ')
          ..write('frequencyType: $frequencyType, ')
          ..write('times: $times, ')
          ..write('daysOfWeek: $daysOfWeek, ')
          ..write('intervalHours: $intervalHours, ')
          ..write('active: $active, ')
          ..write('createdAt: $createdAt, ')
          ..write('pendingSync: $pendingSync, ')
          ..write('deleted: $deleted, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $DoseLogsTable extends DoseLogs with TableInfo<$DoseLogsTable, DoseLog> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DoseLogsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _scheduleIdMeta = const VerificationMeta(
    'scheduleId',
  );
  @override
  late final GeneratedColumn<String> scheduleId = GeneratedColumn<String>(
    'schedule_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES schedules (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _scheduledAtMeta = const VerificationMeta(
    'scheduledAt',
  );
  @override
  late final GeneratedColumn<DateTime> scheduledAt = GeneratedColumn<DateTime>(
    'scheduled_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _actionMeta = const VerificationMeta('action');
  @override
  late final GeneratedColumn<String> action = GeneratedColumn<String>(
    'action',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _loggedAtMeta = const VerificationMeta(
    'loggedAt',
  );
  @override
  late final GeneratedColumn<DateTime> loggedAt = GeneratedColumn<DateTime>(
    'logged_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  static const VerificationMeta _sourceMeta = const VerificationMeta('source');
  @override
  late final GeneratedColumn<String> source = GeneratedColumn<String>(
    'source',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('notification'),
  );
  static const VerificationMeta _pendingSyncMeta = const VerificationMeta(
    'pendingSync',
  );
  @override
  late final GeneratedColumn<bool> pendingSync = GeneratedColumn<bool>(
    'pending_sync',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("pending_sync" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    scheduleId,
    scheduledAt,
    action,
    loggedAt,
    source,
    pendingSync,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'dose_logs';
  @override
  VerificationContext validateIntegrity(
    Insertable<DoseLog> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('schedule_id')) {
      context.handle(
        _scheduleIdMeta,
        scheduleId.isAcceptableOrUnknown(data['schedule_id']!, _scheduleIdMeta),
      );
    } else if (isInserting) {
      context.missing(_scheduleIdMeta);
    }
    if (data.containsKey('scheduled_at')) {
      context.handle(
        _scheduledAtMeta,
        scheduledAt.isAcceptableOrUnknown(
          data['scheduled_at']!,
          _scheduledAtMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_scheduledAtMeta);
    }
    if (data.containsKey('action')) {
      context.handle(
        _actionMeta,
        action.isAcceptableOrUnknown(data['action']!, _actionMeta),
      );
    } else if (isInserting) {
      context.missing(_actionMeta);
    }
    if (data.containsKey('logged_at')) {
      context.handle(
        _loggedAtMeta,
        loggedAt.isAcceptableOrUnknown(data['logged_at']!, _loggedAtMeta),
      );
    }
    if (data.containsKey('source')) {
      context.handle(
        _sourceMeta,
        source.isAcceptableOrUnknown(data['source']!, _sourceMeta),
      );
    }
    if (data.containsKey('pending_sync')) {
      context.handle(
        _pendingSyncMeta,
        pendingSync.isAcceptableOrUnknown(
          data['pending_sync']!,
          _pendingSyncMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  DoseLog map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DoseLog(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      scheduleId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}schedule_id'],
      )!,
      scheduledAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}scheduled_at'],
      )!,
      action: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}action'],
      )!,
      loggedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}logged_at'],
      )!,
      source: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source'],
      )!,
      pendingSync: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}pending_sync'],
      )!,
    );
  }

  @override
  $DoseLogsTable createAlias(String alias) {
    return $DoseLogsTable(attachedDatabase, alias);
  }
}

class DoseLog extends DataClass implements Insertable<DoseLog> {
  final String id;
  final String scheduleId;
  final DateTime scheduledAt;
  final String action;
  final DateTime loggedAt;
  final String source;
  final bool pendingSync;
  const DoseLog({
    required this.id,
    required this.scheduleId,
    required this.scheduledAt,
    required this.action,
    required this.loggedAt,
    required this.source,
    required this.pendingSync,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['schedule_id'] = Variable<String>(scheduleId);
    map['scheduled_at'] = Variable<DateTime>(scheduledAt);
    map['action'] = Variable<String>(action);
    map['logged_at'] = Variable<DateTime>(loggedAt);
    map['source'] = Variable<String>(source);
    map['pending_sync'] = Variable<bool>(pendingSync);
    return map;
  }

  DoseLogsCompanion toCompanion(bool nullToAbsent) {
    return DoseLogsCompanion(
      id: Value(id),
      scheduleId: Value(scheduleId),
      scheduledAt: Value(scheduledAt),
      action: Value(action),
      loggedAt: Value(loggedAt),
      source: Value(source),
      pendingSync: Value(pendingSync),
    );
  }

  factory DoseLog.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DoseLog(
      id: serializer.fromJson<String>(json['id']),
      scheduleId: serializer.fromJson<String>(json['scheduleId']),
      scheduledAt: serializer.fromJson<DateTime>(json['scheduledAt']),
      action: serializer.fromJson<String>(json['action']),
      loggedAt: serializer.fromJson<DateTime>(json['loggedAt']),
      source: serializer.fromJson<String>(json['source']),
      pendingSync: serializer.fromJson<bool>(json['pendingSync']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'scheduleId': serializer.toJson<String>(scheduleId),
      'scheduledAt': serializer.toJson<DateTime>(scheduledAt),
      'action': serializer.toJson<String>(action),
      'loggedAt': serializer.toJson<DateTime>(loggedAt),
      'source': serializer.toJson<String>(source),
      'pendingSync': serializer.toJson<bool>(pendingSync),
    };
  }

  DoseLog copyWith({
    String? id,
    String? scheduleId,
    DateTime? scheduledAt,
    String? action,
    DateTime? loggedAt,
    String? source,
    bool? pendingSync,
  }) => DoseLog(
    id: id ?? this.id,
    scheduleId: scheduleId ?? this.scheduleId,
    scheduledAt: scheduledAt ?? this.scheduledAt,
    action: action ?? this.action,
    loggedAt: loggedAt ?? this.loggedAt,
    source: source ?? this.source,
    pendingSync: pendingSync ?? this.pendingSync,
  );
  DoseLog copyWithCompanion(DoseLogsCompanion data) {
    return DoseLog(
      id: data.id.present ? data.id.value : this.id,
      scheduleId: data.scheduleId.present
          ? data.scheduleId.value
          : this.scheduleId,
      scheduledAt: data.scheduledAt.present
          ? data.scheduledAt.value
          : this.scheduledAt,
      action: data.action.present ? data.action.value : this.action,
      loggedAt: data.loggedAt.present ? data.loggedAt.value : this.loggedAt,
      source: data.source.present ? data.source.value : this.source,
      pendingSync: data.pendingSync.present
          ? data.pendingSync.value
          : this.pendingSync,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DoseLog(')
          ..write('id: $id, ')
          ..write('scheduleId: $scheduleId, ')
          ..write('scheduledAt: $scheduledAt, ')
          ..write('action: $action, ')
          ..write('loggedAt: $loggedAt, ')
          ..write('source: $source, ')
          ..write('pendingSync: $pendingSync')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    scheduleId,
    scheduledAt,
    action,
    loggedAt,
    source,
    pendingSync,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DoseLog &&
          other.id == this.id &&
          other.scheduleId == this.scheduleId &&
          other.scheduledAt == this.scheduledAt &&
          other.action == this.action &&
          other.loggedAt == this.loggedAt &&
          other.source == this.source &&
          other.pendingSync == this.pendingSync);
}

class DoseLogsCompanion extends UpdateCompanion<DoseLog> {
  final Value<String> id;
  final Value<String> scheduleId;
  final Value<DateTime> scheduledAt;
  final Value<String> action;
  final Value<DateTime> loggedAt;
  final Value<String> source;
  final Value<bool> pendingSync;
  final Value<int> rowid;
  const DoseLogsCompanion({
    this.id = const Value.absent(),
    this.scheduleId = const Value.absent(),
    this.scheduledAt = const Value.absent(),
    this.action = const Value.absent(),
    this.loggedAt = const Value.absent(),
    this.source = const Value.absent(),
    this.pendingSync = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DoseLogsCompanion.insert({
    required String id,
    required String scheduleId,
    required DateTime scheduledAt,
    required String action,
    this.loggedAt = const Value.absent(),
    this.source = const Value.absent(),
    this.pendingSync = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       scheduleId = Value(scheduleId),
       scheduledAt = Value(scheduledAt),
       action = Value(action);
  static Insertable<DoseLog> custom({
    Expression<String>? id,
    Expression<String>? scheduleId,
    Expression<DateTime>? scheduledAt,
    Expression<String>? action,
    Expression<DateTime>? loggedAt,
    Expression<String>? source,
    Expression<bool>? pendingSync,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (scheduleId != null) 'schedule_id': scheduleId,
      if (scheduledAt != null) 'scheduled_at': scheduledAt,
      if (action != null) 'action': action,
      if (loggedAt != null) 'logged_at': loggedAt,
      if (source != null) 'source': source,
      if (pendingSync != null) 'pending_sync': pendingSync,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DoseLogsCompanion copyWith({
    Value<String>? id,
    Value<String>? scheduleId,
    Value<DateTime>? scheduledAt,
    Value<String>? action,
    Value<DateTime>? loggedAt,
    Value<String>? source,
    Value<bool>? pendingSync,
    Value<int>? rowid,
  }) {
    return DoseLogsCompanion(
      id: id ?? this.id,
      scheduleId: scheduleId ?? this.scheduleId,
      scheduledAt: scheduledAt ?? this.scheduledAt,
      action: action ?? this.action,
      loggedAt: loggedAt ?? this.loggedAt,
      source: source ?? this.source,
      pendingSync: pendingSync ?? this.pendingSync,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (scheduleId.present) {
      map['schedule_id'] = Variable<String>(scheduleId.value);
    }
    if (scheduledAt.present) {
      map['scheduled_at'] = Variable<DateTime>(scheduledAt.value);
    }
    if (action.present) {
      map['action'] = Variable<String>(action.value);
    }
    if (loggedAt.present) {
      map['logged_at'] = Variable<DateTime>(loggedAt.value);
    }
    if (source.present) {
      map['source'] = Variable<String>(source.value);
    }
    if (pendingSync.present) {
      map['pending_sync'] = Variable<bool>(pendingSync.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DoseLogsCompanion(')
          ..write('id: $id, ')
          ..write('scheduleId: $scheduleId, ')
          ..write('scheduledAt: $scheduledAt, ')
          ..write('action: $action, ')
          ..write('loggedAt: $loggedAt, ')
          ..write('source: $source, ')
          ..write('pendingSync: $pendingSync, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $MedicinesTable medicines = $MedicinesTable(this);
  late final $SchedulesTable schedules = $SchedulesTable(this);
  late final $DoseLogsTable doseLogs = $DoseLogsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    medicines,
    schedules,
    doseLogs,
  ];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules([
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'medicines',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('schedules', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'schedules',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('dose_logs', kind: UpdateKind.delete)],
    ),
  ]);
}

typedef $$MedicinesTableCreateCompanionBuilder =
    MedicinesCompanion Function({
      required String id,
      required String drugName,
      Value<String> strength,
      Value<String> form,
      Value<String> doseAmount,
      Value<String> notes,
      Value<DateTime> createdAt,
      Value<bool> pendingSync,
      Value<bool> deleted,
      Value<int> rowid,
    });
typedef $$MedicinesTableUpdateCompanionBuilder =
    MedicinesCompanion Function({
      Value<String> id,
      Value<String> drugName,
      Value<String> strength,
      Value<String> form,
      Value<String> doseAmount,
      Value<String> notes,
      Value<DateTime> createdAt,
      Value<bool> pendingSync,
      Value<bool> deleted,
      Value<int> rowid,
    });

final class $$MedicinesTableReferences
    extends BaseReferences<_$AppDatabase, $MedicinesTable, Medicine> {
  $$MedicinesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$SchedulesTable, List<Schedule>>
  _schedulesRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.schedules,
    aliasName: 'medicines__id__schedules__medicine_id',
  );

  $$SchedulesTableProcessedTableManager get schedulesRefs {
    final manager = $$SchedulesTableTableManager(
      $_db,
      $_db.schedules,
    ).filter((f) => f.medicineId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_schedulesRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$MedicinesTableFilterComposer
    extends Composer<_$AppDatabase, $MedicinesTable> {
  $$MedicinesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get drugName => $composableBuilder(
    column: $table.drugName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get strength => $composableBuilder(
    column: $table.strength,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get form => $composableBuilder(
    column: $table.form,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get doseAmount => $composableBuilder(
    column: $table.doseAmount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get pendingSync => $composableBuilder(
    column: $table.pendingSync,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get deleted => $composableBuilder(
    column: $table.deleted,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> schedulesRefs(
    Expression<bool> Function($$SchedulesTableFilterComposer f) f,
  ) {
    final $$SchedulesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.schedules,
      getReferencedColumn: (t) => t.medicineId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SchedulesTableFilterComposer(
            $db: $db,
            $table: $db.schedules,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$MedicinesTableOrderingComposer
    extends Composer<_$AppDatabase, $MedicinesTable> {
  $$MedicinesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get drugName => $composableBuilder(
    column: $table.drugName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get strength => $composableBuilder(
    column: $table.strength,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get form => $composableBuilder(
    column: $table.form,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get doseAmount => $composableBuilder(
    column: $table.doseAmount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get pendingSync => $composableBuilder(
    column: $table.pendingSync,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get deleted => $composableBuilder(
    column: $table.deleted,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$MedicinesTableAnnotationComposer
    extends Composer<_$AppDatabase, $MedicinesTable> {
  $$MedicinesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get drugName =>
      $composableBuilder(column: $table.drugName, builder: (column) => column);

  GeneratedColumn<String> get strength =>
      $composableBuilder(column: $table.strength, builder: (column) => column);

  GeneratedColumn<String> get form =>
      $composableBuilder(column: $table.form, builder: (column) => column);

  GeneratedColumn<String> get doseAmount => $composableBuilder(
    column: $table.doseAmount,
    builder: (column) => column,
  );

  GeneratedColumn<String> get notes =>
      $composableBuilder(column: $table.notes, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<bool> get pendingSync => $composableBuilder(
    column: $table.pendingSync,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get deleted =>
      $composableBuilder(column: $table.deleted, builder: (column) => column);

  Expression<T> schedulesRefs<T extends Object>(
    Expression<T> Function($$SchedulesTableAnnotationComposer a) f,
  ) {
    final $$SchedulesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.schedules,
      getReferencedColumn: (t) => t.medicineId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SchedulesTableAnnotationComposer(
            $db: $db,
            $table: $db.schedules,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$MedicinesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $MedicinesTable,
          Medicine,
          $$MedicinesTableFilterComposer,
          $$MedicinesTableOrderingComposer,
          $$MedicinesTableAnnotationComposer,
          $$MedicinesTableCreateCompanionBuilder,
          $$MedicinesTableUpdateCompanionBuilder,
          (Medicine, $$MedicinesTableReferences),
          Medicine,
          PrefetchHooks Function({bool schedulesRefs})
        > {
  $$MedicinesTableTableManager(_$AppDatabase db, $MedicinesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MedicinesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MedicinesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MedicinesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> drugName = const Value.absent(),
                Value<String> strength = const Value.absent(),
                Value<String> form = const Value.absent(),
                Value<String> doseAmount = const Value.absent(),
                Value<String> notes = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<bool> pendingSync = const Value.absent(),
                Value<bool> deleted = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MedicinesCompanion(
                id: id,
                drugName: drugName,
                strength: strength,
                form: form,
                doseAmount: doseAmount,
                notes: notes,
                createdAt: createdAt,
                pendingSync: pendingSync,
                deleted: deleted,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String drugName,
                Value<String> strength = const Value.absent(),
                Value<String> form = const Value.absent(),
                Value<String> doseAmount = const Value.absent(),
                Value<String> notes = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<bool> pendingSync = const Value.absent(),
                Value<bool> deleted = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MedicinesCompanion.insert(
                id: id,
                drugName: drugName,
                strength: strength,
                form: form,
                doseAmount: doseAmount,
                notes: notes,
                createdAt: createdAt,
                pendingSync: pendingSync,
                deleted: deleted,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$MedicinesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({schedulesRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (schedulesRefs) db.schedules],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (schedulesRefs)
                    await $_getPrefetchedData<
                      Medicine,
                      $MedicinesTable,
                      Schedule
                    >(
                      currentTable: table,
                      referencedTable: $$MedicinesTableReferences
                          ._schedulesRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $$MedicinesTableReferences(
                            db,
                            table,
                            p0,
                          ).schedulesRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.medicineId == item.id),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$MedicinesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $MedicinesTable,
      Medicine,
      $$MedicinesTableFilterComposer,
      $$MedicinesTableOrderingComposer,
      $$MedicinesTableAnnotationComposer,
      $$MedicinesTableCreateCompanionBuilder,
      $$MedicinesTableUpdateCompanionBuilder,
      (Medicine, $$MedicinesTableReferences),
      Medicine,
      PrefetchHooks Function({bool schedulesRefs})
    >;
typedef $$SchedulesTableCreateCompanionBuilder =
    SchedulesCompanion Function({
      required String id,
      required String medicineId,
      required String frequencyType,
      required List<String> times,
      Value<List<int>> daysOfWeek,
      Value<int?> intervalHours,
      Value<bool> active,
      Value<DateTime> createdAt,
      Value<bool> pendingSync,
      Value<bool> deleted,
      Value<int> rowid,
    });
typedef $$SchedulesTableUpdateCompanionBuilder =
    SchedulesCompanion Function({
      Value<String> id,
      Value<String> medicineId,
      Value<String> frequencyType,
      Value<List<String>> times,
      Value<List<int>> daysOfWeek,
      Value<int?> intervalHours,
      Value<bool> active,
      Value<DateTime> createdAt,
      Value<bool> pendingSync,
      Value<bool> deleted,
      Value<int> rowid,
    });

final class $$SchedulesTableReferences
    extends BaseReferences<_$AppDatabase, $SchedulesTable, Schedule> {
  $$SchedulesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $MedicinesTable _medicineIdTable(_$AppDatabase db) =>
      db.medicines.createAlias('schedules__medicine_id__medicines__id');

  $$MedicinesTableProcessedTableManager get medicineId {
    final $_column = $_itemColumn<String>('medicine_id')!;

    final manager = $$MedicinesTableTableManager(
      $_db,
      $_db.medicines,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_medicineIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<$DoseLogsTable, List<DoseLog>> _doseLogsRefsTable(
    _$AppDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.doseLogs,
    aliasName: 'schedules__id__dose_logs__schedule_id',
  );

  $$DoseLogsTableProcessedTableManager get doseLogsRefs {
    final manager = $$DoseLogsTableTableManager(
      $_db,
      $_db.doseLogs,
    ).filter((f) => f.scheduleId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_doseLogsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$SchedulesTableFilterComposer
    extends Composer<_$AppDatabase, $SchedulesTable> {
  $$SchedulesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get frequencyType => $composableBuilder(
    column: $table.frequencyType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<List<String>, List<String>, String>
  get times => $composableBuilder(
    column: $table.times,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnWithTypeConverterFilters<List<int>, List<int>, String> get daysOfWeek =>
      $composableBuilder(
        column: $table.daysOfWeek,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<int> get intervalHours => $composableBuilder(
    column: $table.intervalHours,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get active => $composableBuilder(
    column: $table.active,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get pendingSync => $composableBuilder(
    column: $table.pendingSync,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get deleted => $composableBuilder(
    column: $table.deleted,
    builder: (column) => ColumnFilters(column),
  );

  $$MedicinesTableFilterComposer get medicineId {
    final $$MedicinesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.medicineId,
      referencedTable: $db.medicines,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MedicinesTableFilterComposer(
            $db: $db,
            $table: $db.medicines,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> doseLogsRefs(
    Expression<bool> Function($$DoseLogsTableFilterComposer f) f,
  ) {
    final $$DoseLogsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.doseLogs,
      getReferencedColumn: (t) => t.scheduleId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DoseLogsTableFilterComposer(
            $db: $db,
            $table: $db.doseLogs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$SchedulesTableOrderingComposer
    extends Composer<_$AppDatabase, $SchedulesTable> {
  $$SchedulesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get frequencyType => $composableBuilder(
    column: $table.frequencyType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get times => $composableBuilder(
    column: $table.times,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get daysOfWeek => $composableBuilder(
    column: $table.daysOfWeek,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get intervalHours => $composableBuilder(
    column: $table.intervalHours,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get active => $composableBuilder(
    column: $table.active,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get pendingSync => $composableBuilder(
    column: $table.pendingSync,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get deleted => $composableBuilder(
    column: $table.deleted,
    builder: (column) => ColumnOrderings(column),
  );

  $$MedicinesTableOrderingComposer get medicineId {
    final $$MedicinesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.medicineId,
      referencedTable: $db.medicines,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MedicinesTableOrderingComposer(
            $db: $db,
            $table: $db.medicines,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SchedulesTableAnnotationComposer
    extends Composer<_$AppDatabase, $SchedulesTable> {
  $$SchedulesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get frequencyType => $composableBuilder(
    column: $table.frequencyType,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<List<String>, String> get times =>
      $composableBuilder(column: $table.times, builder: (column) => column);

  GeneratedColumnWithTypeConverter<List<int>, String> get daysOfWeek =>
      $composableBuilder(
        column: $table.daysOfWeek,
        builder: (column) => column,
      );

  GeneratedColumn<int> get intervalHours => $composableBuilder(
    column: $table.intervalHours,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get active =>
      $composableBuilder(column: $table.active, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<bool> get pendingSync => $composableBuilder(
    column: $table.pendingSync,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get deleted =>
      $composableBuilder(column: $table.deleted, builder: (column) => column);

  $$MedicinesTableAnnotationComposer get medicineId {
    final $$MedicinesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.medicineId,
      referencedTable: $db.medicines,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$MedicinesTableAnnotationComposer(
            $db: $db,
            $table: $db.medicines,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> doseLogsRefs<T extends Object>(
    Expression<T> Function($$DoseLogsTableAnnotationComposer a) f,
  ) {
    final $$DoseLogsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.doseLogs,
      getReferencedColumn: (t) => t.scheduleId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DoseLogsTableAnnotationComposer(
            $db: $db,
            $table: $db.doseLogs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$SchedulesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SchedulesTable,
          Schedule,
          $$SchedulesTableFilterComposer,
          $$SchedulesTableOrderingComposer,
          $$SchedulesTableAnnotationComposer,
          $$SchedulesTableCreateCompanionBuilder,
          $$SchedulesTableUpdateCompanionBuilder,
          (Schedule, $$SchedulesTableReferences),
          Schedule,
          PrefetchHooks Function({bool medicineId, bool doseLogsRefs})
        > {
  $$SchedulesTableTableManager(_$AppDatabase db, $SchedulesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SchedulesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SchedulesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SchedulesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> medicineId = const Value.absent(),
                Value<String> frequencyType = const Value.absent(),
                Value<List<String>> times = const Value.absent(),
                Value<List<int>> daysOfWeek = const Value.absent(),
                Value<int?> intervalHours = const Value.absent(),
                Value<bool> active = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<bool> pendingSync = const Value.absent(),
                Value<bool> deleted = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SchedulesCompanion(
                id: id,
                medicineId: medicineId,
                frequencyType: frequencyType,
                times: times,
                daysOfWeek: daysOfWeek,
                intervalHours: intervalHours,
                active: active,
                createdAt: createdAt,
                pendingSync: pendingSync,
                deleted: deleted,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String medicineId,
                required String frequencyType,
                required List<String> times,
                Value<List<int>> daysOfWeek = const Value.absent(),
                Value<int?> intervalHours = const Value.absent(),
                Value<bool> active = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<bool> pendingSync = const Value.absent(),
                Value<bool> deleted = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SchedulesCompanion.insert(
                id: id,
                medicineId: medicineId,
                frequencyType: frequencyType,
                times: times,
                daysOfWeek: daysOfWeek,
                intervalHours: intervalHours,
                active: active,
                createdAt: createdAt,
                pendingSync: pendingSync,
                deleted: deleted,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$SchedulesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({medicineId = false, doseLogsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (doseLogsRefs) db.doseLogs],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (medicineId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.medicineId,
                                referencedTable: $$SchedulesTableReferences
                                    ._medicineIdTable(db),
                                referencedColumn: $$SchedulesTableReferences
                                    ._medicineIdTable(db)
                                    .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [
                  if (doseLogsRefs)
                    await $_getPrefetchedData<
                      Schedule,
                      $SchedulesTable,
                      DoseLog
                    >(
                      currentTable: table,
                      referencedTable: $$SchedulesTableReferences
                          ._doseLogsRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $$SchedulesTableReferences(
                            db,
                            table,
                            p0,
                          ).doseLogsRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.scheduleId == item.id),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$SchedulesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SchedulesTable,
      Schedule,
      $$SchedulesTableFilterComposer,
      $$SchedulesTableOrderingComposer,
      $$SchedulesTableAnnotationComposer,
      $$SchedulesTableCreateCompanionBuilder,
      $$SchedulesTableUpdateCompanionBuilder,
      (Schedule, $$SchedulesTableReferences),
      Schedule,
      PrefetchHooks Function({bool medicineId, bool doseLogsRefs})
    >;
typedef $$DoseLogsTableCreateCompanionBuilder =
    DoseLogsCompanion Function({
      required String id,
      required String scheduleId,
      required DateTime scheduledAt,
      required String action,
      Value<DateTime> loggedAt,
      Value<String> source,
      Value<bool> pendingSync,
      Value<int> rowid,
    });
typedef $$DoseLogsTableUpdateCompanionBuilder =
    DoseLogsCompanion Function({
      Value<String> id,
      Value<String> scheduleId,
      Value<DateTime> scheduledAt,
      Value<String> action,
      Value<DateTime> loggedAt,
      Value<String> source,
      Value<bool> pendingSync,
      Value<int> rowid,
    });

final class $$DoseLogsTableReferences
    extends BaseReferences<_$AppDatabase, $DoseLogsTable, DoseLog> {
  $$DoseLogsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $SchedulesTable _scheduleIdTable(_$AppDatabase db) =>
      db.schedules.createAlias('dose_logs__schedule_id__schedules__id');

  $$SchedulesTableProcessedTableManager get scheduleId {
    final $_column = $_itemColumn<String>('schedule_id')!;

    final manager = $$SchedulesTableTableManager(
      $_db,
      $_db.schedules,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_scheduleIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$DoseLogsTableFilterComposer
    extends Composer<_$AppDatabase, $DoseLogsTable> {
  $$DoseLogsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get scheduledAt => $composableBuilder(
    column: $table.scheduledAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get action => $composableBuilder(
    column: $table.action,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get loggedAt => $composableBuilder(
    column: $table.loggedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get pendingSync => $composableBuilder(
    column: $table.pendingSync,
    builder: (column) => ColumnFilters(column),
  );

  $$SchedulesTableFilterComposer get scheduleId {
    final $$SchedulesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.scheduleId,
      referencedTable: $db.schedules,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SchedulesTableFilterComposer(
            $db: $db,
            $table: $db.schedules,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$DoseLogsTableOrderingComposer
    extends Composer<_$AppDatabase, $DoseLogsTable> {
  $$DoseLogsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get scheduledAt => $composableBuilder(
    column: $table.scheduledAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get action => $composableBuilder(
    column: $table.action,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get loggedAt => $composableBuilder(
    column: $table.loggedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get pendingSync => $composableBuilder(
    column: $table.pendingSync,
    builder: (column) => ColumnOrderings(column),
  );

  $$SchedulesTableOrderingComposer get scheduleId {
    final $$SchedulesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.scheduleId,
      referencedTable: $db.schedules,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SchedulesTableOrderingComposer(
            $db: $db,
            $table: $db.schedules,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$DoseLogsTableAnnotationComposer
    extends Composer<_$AppDatabase, $DoseLogsTable> {
  $$DoseLogsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<DateTime> get scheduledAt => $composableBuilder(
    column: $table.scheduledAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get action =>
      $composableBuilder(column: $table.action, builder: (column) => column);

  GeneratedColumn<DateTime> get loggedAt =>
      $composableBuilder(column: $table.loggedAt, builder: (column) => column);

  GeneratedColumn<String> get source =>
      $composableBuilder(column: $table.source, builder: (column) => column);

  GeneratedColumn<bool> get pendingSync => $composableBuilder(
    column: $table.pendingSync,
    builder: (column) => column,
  );

  $$SchedulesTableAnnotationComposer get scheduleId {
    final $$SchedulesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.scheduleId,
      referencedTable: $db.schedules,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SchedulesTableAnnotationComposer(
            $db: $db,
            $table: $db.schedules,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$DoseLogsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $DoseLogsTable,
          DoseLog,
          $$DoseLogsTableFilterComposer,
          $$DoseLogsTableOrderingComposer,
          $$DoseLogsTableAnnotationComposer,
          $$DoseLogsTableCreateCompanionBuilder,
          $$DoseLogsTableUpdateCompanionBuilder,
          (DoseLog, $$DoseLogsTableReferences),
          DoseLog,
          PrefetchHooks Function({bool scheduleId})
        > {
  $$DoseLogsTableTableManager(_$AppDatabase db, $DoseLogsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DoseLogsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DoseLogsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DoseLogsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> scheduleId = const Value.absent(),
                Value<DateTime> scheduledAt = const Value.absent(),
                Value<String> action = const Value.absent(),
                Value<DateTime> loggedAt = const Value.absent(),
                Value<String> source = const Value.absent(),
                Value<bool> pendingSync = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DoseLogsCompanion(
                id: id,
                scheduleId: scheduleId,
                scheduledAt: scheduledAt,
                action: action,
                loggedAt: loggedAt,
                source: source,
                pendingSync: pendingSync,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String scheduleId,
                required DateTime scheduledAt,
                required String action,
                Value<DateTime> loggedAt = const Value.absent(),
                Value<String> source = const Value.absent(),
                Value<bool> pendingSync = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DoseLogsCompanion.insert(
                id: id,
                scheduleId: scheduleId,
                scheduledAt: scheduledAt,
                action: action,
                loggedAt: loggedAt,
                source: source,
                pendingSync: pendingSync,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$DoseLogsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({scheduleId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (scheduleId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.scheduleId,
                                referencedTable: $$DoseLogsTableReferences
                                    ._scheduleIdTable(db),
                                referencedColumn: $$DoseLogsTableReferences
                                    ._scheduleIdTable(db)
                                    .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$DoseLogsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $DoseLogsTable,
      DoseLog,
      $$DoseLogsTableFilterComposer,
      $$DoseLogsTableOrderingComposer,
      $$DoseLogsTableAnnotationComposer,
      $$DoseLogsTableCreateCompanionBuilder,
      $$DoseLogsTableUpdateCompanionBuilder,
      (DoseLog, $$DoseLogsTableReferences),
      DoseLog,
      PrefetchHooks Function({bool scheduleId})
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$MedicinesTableTableManager get medicines =>
      $$MedicinesTableTableManager(_db, _db.medicines);
  $$SchedulesTableTableManager get schedules =>
      $$SchedulesTableTableManager(_db, _db.schedules);
  $$DoseLogsTableTableManager get doseLogs =>
      $$DoseLogsTableTableManager(_db, _db.doseLogs);
}
