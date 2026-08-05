// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'local_database.dart';

// ignore_for_file: type=lint
class $DbSyncOutboxTable extends DbSyncOutbox
    with TableInfo<$DbSyncOutboxTable, DbSyncOutboxData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DbSyncOutboxTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _commandIdMeta = const VerificationMeta(
    'commandId',
  );
  @override
  late final GeneratedColumn<String> commandId = GeneratedColumn<String>(
    'command_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _protocolVersionMeta = const VerificationMeta(
    'protocolVersion',
  );
  @override
  late final GeneratedColumn<int> protocolVersion = GeneratedColumn<int>(
    'protocol_version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _commandTypeMeta = const VerificationMeta(
    'commandType',
  );
  @override
  late final GeneratedColumn<String> commandType = GeneratedColumn<String>(
    'command_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deviceIdMeta = const VerificationMeta(
    'deviceId',
  );
  @override
  late final GeneratedColumn<String> deviceId = GeneratedColumn<String>(
    'device_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _aggregateIdMeta = const VerificationMeta(
    'aggregateId',
  );
  @override
  late final GeneratedColumn<String> aggregateId = GeneratedColumn<String>(
    'aggregate_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _baseRevisionMeta = const VerificationMeta(
    'baseRevision',
  );
  @override
  late final GeneratedColumn<int> baseRevision = GeneratedColumn<int>(
    'base_revision',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _payloadJsonMeta = const VerificationMeta(
    'payloadJson',
  );
  @override
  late final GeneratedColumn<String> payloadJson = GeneratedColumn<String>(
    'payload_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtUtcMeta = const VerificationMeta(
    'createdAtUtc',
  );
  @override
  late final GeneratedColumn<DateTime> createdAtUtc = GeneratedColumn<DateTime>(
    'created_at_utc',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _attemptCountMeta = const VerificationMeta(
    'attemptCount',
  );
  @override
  late final GeneratedColumn<int> attemptCount = GeneratedColumn<int>(
    'attempt_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _nextAttemptAtUtcMeta = const VerificationMeta(
    'nextAttemptAtUtc',
  );
  @override
  late final GeneratedColumn<DateTime> nextAttemptAtUtc =
      GeneratedColumn<DateTime>(
        'next_attempt_at_utc',
        aliasedName,
        false,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _leaseOwnerMeta = const VerificationMeta(
    'leaseOwner',
  );
  @override
  late final GeneratedColumn<String> leaseOwner = GeneratedColumn<String>(
    'lease_owner',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _leaseExpiresAtUtcMeta = const VerificationMeta(
    'leaseExpiresAtUtc',
  );
  @override
  late final GeneratedColumn<DateTime> leaseExpiresAtUtc =
      GeneratedColumn<DateTime>(
        'lease_expires_at_utc',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _lastFailureCodeMeta = const VerificationMeta(
    'lastFailureCode',
  );
  @override
  late final GeneratedColumn<String> lastFailureCode = GeneratedColumn<String>(
    'last_failure_code',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _completedAtUtcMeta = const VerificationMeta(
    'completedAtUtc',
  );
  @override
  late final GeneratedColumn<DateTime> completedAtUtc =
      GeneratedColumn<DateTime>(
        'completed_at_utc',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  @override
  List<GeneratedColumn> get $columns => [
    commandId,
    protocolVersion,
    commandType,
    deviceId,
    aggregateId,
    baseRevision,
    payloadJson,
    createdAtUtc,
    status,
    attemptCount,
    nextAttemptAtUtc,
    leaseOwner,
    leaseExpiresAtUtc,
    lastFailureCode,
    completedAtUtc,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'db_sync_outbox';
  @override
  VerificationContext validateIntegrity(
    Insertable<DbSyncOutboxData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('command_id')) {
      context.handle(
        _commandIdMeta,
        commandId.isAcceptableOrUnknown(data['command_id']!, _commandIdMeta),
      );
    } else if (isInserting) {
      context.missing(_commandIdMeta);
    }
    if (data.containsKey('protocol_version')) {
      context.handle(
        _protocolVersionMeta,
        protocolVersion.isAcceptableOrUnknown(
          data['protocol_version']!,
          _protocolVersionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_protocolVersionMeta);
    }
    if (data.containsKey('command_type')) {
      context.handle(
        _commandTypeMeta,
        commandType.isAcceptableOrUnknown(
          data['command_type']!,
          _commandTypeMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_commandTypeMeta);
    }
    if (data.containsKey('device_id')) {
      context.handle(
        _deviceIdMeta,
        deviceId.isAcceptableOrUnknown(data['device_id']!, _deviceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_deviceIdMeta);
    }
    if (data.containsKey('aggregate_id')) {
      context.handle(
        _aggregateIdMeta,
        aggregateId.isAcceptableOrUnknown(
          data['aggregate_id']!,
          _aggregateIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_aggregateIdMeta);
    }
    if (data.containsKey('base_revision')) {
      context.handle(
        _baseRevisionMeta,
        baseRevision.isAcceptableOrUnknown(
          data['base_revision']!,
          _baseRevisionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_baseRevisionMeta);
    }
    if (data.containsKey('payload_json')) {
      context.handle(
        _payloadJsonMeta,
        payloadJson.isAcceptableOrUnknown(
          data['payload_json']!,
          _payloadJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_payloadJsonMeta);
    }
    if (data.containsKey('created_at_utc')) {
      context.handle(
        _createdAtUtcMeta,
        createdAtUtc.isAcceptableOrUnknown(
          data['created_at_utc']!,
          _createdAtUtcMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_createdAtUtcMeta);
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    if (data.containsKey('attempt_count')) {
      context.handle(
        _attemptCountMeta,
        attemptCount.isAcceptableOrUnknown(
          data['attempt_count']!,
          _attemptCountMeta,
        ),
      );
    }
    if (data.containsKey('next_attempt_at_utc')) {
      context.handle(
        _nextAttemptAtUtcMeta,
        nextAttemptAtUtc.isAcceptableOrUnknown(
          data['next_attempt_at_utc']!,
          _nextAttemptAtUtcMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_nextAttemptAtUtcMeta);
    }
    if (data.containsKey('lease_owner')) {
      context.handle(
        _leaseOwnerMeta,
        leaseOwner.isAcceptableOrUnknown(data['lease_owner']!, _leaseOwnerMeta),
      );
    }
    if (data.containsKey('lease_expires_at_utc')) {
      context.handle(
        _leaseExpiresAtUtcMeta,
        leaseExpiresAtUtc.isAcceptableOrUnknown(
          data['lease_expires_at_utc']!,
          _leaseExpiresAtUtcMeta,
        ),
      );
    }
    if (data.containsKey('last_failure_code')) {
      context.handle(
        _lastFailureCodeMeta,
        lastFailureCode.isAcceptableOrUnknown(
          data['last_failure_code']!,
          _lastFailureCodeMeta,
        ),
      );
    }
    if (data.containsKey('completed_at_utc')) {
      context.handle(
        _completedAtUtcMeta,
        completedAtUtc.isAcceptableOrUnknown(
          data['completed_at_utc']!,
          _completedAtUtcMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {commandId};
  @override
  DbSyncOutboxData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DbSyncOutboxData(
      commandId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}command_id'],
      )!,
      protocolVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}protocol_version'],
      )!,
      commandType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}command_type'],
      )!,
      deviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_id'],
      )!,
      aggregateId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}aggregate_id'],
      )!,
      baseRevision: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}base_revision'],
      )!,
      payloadJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload_json'],
      )!,
      createdAtUtc: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at_utc'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      attemptCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}attempt_count'],
      )!,
      nextAttemptAtUtc: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}next_attempt_at_utc'],
      )!,
      leaseOwner: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}lease_owner'],
      ),
      leaseExpiresAtUtc: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}lease_expires_at_utc'],
      ),
      lastFailureCode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_failure_code'],
      ),
      completedAtUtc: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}completed_at_utc'],
      ),
    );
  }

  @override
  $DbSyncOutboxTable createAlias(String alias) {
    return $DbSyncOutboxTable(attachedDatabase, alias);
  }
}

class DbSyncOutboxData extends DataClass
    implements Insertable<DbSyncOutboxData> {
  final String commandId;
  final int protocolVersion;
  final String commandType;
  final String deviceId;
  final String aggregateId;
  final int baseRevision;
  final String payloadJson;
  final DateTime createdAtUtc;
  final String status;
  final int attemptCount;
  final DateTime nextAttemptAtUtc;
  final String? leaseOwner;
  final DateTime? leaseExpiresAtUtc;
  final String? lastFailureCode;
  final DateTime? completedAtUtc;
  const DbSyncOutboxData({
    required this.commandId,
    required this.protocolVersion,
    required this.commandType,
    required this.deviceId,
    required this.aggregateId,
    required this.baseRevision,
    required this.payloadJson,
    required this.createdAtUtc,
    required this.status,
    required this.attemptCount,
    required this.nextAttemptAtUtc,
    this.leaseOwner,
    this.leaseExpiresAtUtc,
    this.lastFailureCode,
    this.completedAtUtc,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['command_id'] = Variable<String>(commandId);
    map['protocol_version'] = Variable<int>(protocolVersion);
    map['command_type'] = Variable<String>(commandType);
    map['device_id'] = Variable<String>(deviceId);
    map['aggregate_id'] = Variable<String>(aggregateId);
    map['base_revision'] = Variable<int>(baseRevision);
    map['payload_json'] = Variable<String>(payloadJson);
    map['created_at_utc'] = Variable<DateTime>(createdAtUtc);
    map['status'] = Variable<String>(status);
    map['attempt_count'] = Variable<int>(attemptCount);
    map['next_attempt_at_utc'] = Variable<DateTime>(nextAttemptAtUtc);
    if (!nullToAbsent || leaseOwner != null) {
      map['lease_owner'] = Variable<String>(leaseOwner);
    }
    if (!nullToAbsent || leaseExpiresAtUtc != null) {
      map['lease_expires_at_utc'] = Variable<DateTime>(leaseExpiresAtUtc);
    }
    if (!nullToAbsent || lastFailureCode != null) {
      map['last_failure_code'] = Variable<String>(lastFailureCode);
    }
    if (!nullToAbsent || completedAtUtc != null) {
      map['completed_at_utc'] = Variable<DateTime>(completedAtUtc);
    }
    return map;
  }

  DbSyncOutboxCompanion toCompanion(bool nullToAbsent) {
    return DbSyncOutboxCompanion(
      commandId: Value(commandId),
      protocolVersion: Value(protocolVersion),
      commandType: Value(commandType),
      deviceId: Value(deviceId),
      aggregateId: Value(aggregateId),
      baseRevision: Value(baseRevision),
      payloadJson: Value(payloadJson),
      createdAtUtc: Value(createdAtUtc),
      status: Value(status),
      attemptCount: Value(attemptCount),
      nextAttemptAtUtc: Value(nextAttemptAtUtc),
      leaseOwner: leaseOwner == null && nullToAbsent
          ? const Value.absent()
          : Value(leaseOwner),
      leaseExpiresAtUtc: leaseExpiresAtUtc == null && nullToAbsent
          ? const Value.absent()
          : Value(leaseExpiresAtUtc),
      lastFailureCode: lastFailureCode == null && nullToAbsent
          ? const Value.absent()
          : Value(lastFailureCode),
      completedAtUtc: completedAtUtc == null && nullToAbsent
          ? const Value.absent()
          : Value(completedAtUtc),
    );
  }

  factory DbSyncOutboxData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DbSyncOutboxData(
      commandId: serializer.fromJson<String>(json['commandId']),
      protocolVersion: serializer.fromJson<int>(json['protocolVersion']),
      commandType: serializer.fromJson<String>(json['commandType']),
      deviceId: serializer.fromJson<String>(json['deviceId']),
      aggregateId: serializer.fromJson<String>(json['aggregateId']),
      baseRevision: serializer.fromJson<int>(json['baseRevision']),
      payloadJson: serializer.fromJson<String>(json['payloadJson']),
      createdAtUtc: serializer.fromJson<DateTime>(json['createdAtUtc']),
      status: serializer.fromJson<String>(json['status']),
      attemptCount: serializer.fromJson<int>(json['attemptCount']),
      nextAttemptAtUtc: serializer.fromJson<DateTime>(json['nextAttemptAtUtc']),
      leaseOwner: serializer.fromJson<String?>(json['leaseOwner']),
      leaseExpiresAtUtc: serializer.fromJson<DateTime?>(
        json['leaseExpiresAtUtc'],
      ),
      lastFailureCode: serializer.fromJson<String?>(json['lastFailureCode']),
      completedAtUtc: serializer.fromJson<DateTime?>(json['completedAtUtc']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'commandId': serializer.toJson<String>(commandId),
      'protocolVersion': serializer.toJson<int>(protocolVersion),
      'commandType': serializer.toJson<String>(commandType),
      'deviceId': serializer.toJson<String>(deviceId),
      'aggregateId': serializer.toJson<String>(aggregateId),
      'baseRevision': serializer.toJson<int>(baseRevision),
      'payloadJson': serializer.toJson<String>(payloadJson),
      'createdAtUtc': serializer.toJson<DateTime>(createdAtUtc),
      'status': serializer.toJson<String>(status),
      'attemptCount': serializer.toJson<int>(attemptCount),
      'nextAttemptAtUtc': serializer.toJson<DateTime>(nextAttemptAtUtc),
      'leaseOwner': serializer.toJson<String?>(leaseOwner),
      'leaseExpiresAtUtc': serializer.toJson<DateTime?>(leaseExpiresAtUtc),
      'lastFailureCode': serializer.toJson<String?>(lastFailureCode),
      'completedAtUtc': serializer.toJson<DateTime?>(completedAtUtc),
    };
  }

  DbSyncOutboxData copyWith({
    String? commandId,
    int? protocolVersion,
    String? commandType,
    String? deviceId,
    String? aggregateId,
    int? baseRevision,
    String? payloadJson,
    DateTime? createdAtUtc,
    String? status,
    int? attemptCount,
    DateTime? nextAttemptAtUtc,
    Value<String?> leaseOwner = const Value.absent(),
    Value<DateTime?> leaseExpiresAtUtc = const Value.absent(),
    Value<String?> lastFailureCode = const Value.absent(),
    Value<DateTime?> completedAtUtc = const Value.absent(),
  }) => DbSyncOutboxData(
    commandId: commandId ?? this.commandId,
    protocolVersion: protocolVersion ?? this.protocolVersion,
    commandType: commandType ?? this.commandType,
    deviceId: deviceId ?? this.deviceId,
    aggregateId: aggregateId ?? this.aggregateId,
    baseRevision: baseRevision ?? this.baseRevision,
    payloadJson: payloadJson ?? this.payloadJson,
    createdAtUtc: createdAtUtc ?? this.createdAtUtc,
    status: status ?? this.status,
    attemptCount: attemptCount ?? this.attemptCount,
    nextAttemptAtUtc: nextAttemptAtUtc ?? this.nextAttemptAtUtc,
    leaseOwner: leaseOwner.present ? leaseOwner.value : this.leaseOwner,
    leaseExpiresAtUtc: leaseExpiresAtUtc.present
        ? leaseExpiresAtUtc.value
        : this.leaseExpiresAtUtc,
    lastFailureCode: lastFailureCode.present
        ? lastFailureCode.value
        : this.lastFailureCode,
    completedAtUtc: completedAtUtc.present
        ? completedAtUtc.value
        : this.completedAtUtc,
  );
  DbSyncOutboxData copyWithCompanion(DbSyncOutboxCompanion data) {
    return DbSyncOutboxData(
      commandId: data.commandId.present ? data.commandId.value : this.commandId,
      protocolVersion: data.protocolVersion.present
          ? data.protocolVersion.value
          : this.protocolVersion,
      commandType: data.commandType.present
          ? data.commandType.value
          : this.commandType,
      deviceId: data.deviceId.present ? data.deviceId.value : this.deviceId,
      aggregateId: data.aggregateId.present
          ? data.aggregateId.value
          : this.aggregateId,
      baseRevision: data.baseRevision.present
          ? data.baseRevision.value
          : this.baseRevision,
      payloadJson: data.payloadJson.present
          ? data.payloadJson.value
          : this.payloadJson,
      createdAtUtc: data.createdAtUtc.present
          ? data.createdAtUtc.value
          : this.createdAtUtc,
      status: data.status.present ? data.status.value : this.status,
      attemptCount: data.attemptCount.present
          ? data.attemptCount.value
          : this.attemptCount,
      nextAttemptAtUtc: data.nextAttemptAtUtc.present
          ? data.nextAttemptAtUtc.value
          : this.nextAttemptAtUtc,
      leaseOwner: data.leaseOwner.present
          ? data.leaseOwner.value
          : this.leaseOwner,
      leaseExpiresAtUtc: data.leaseExpiresAtUtc.present
          ? data.leaseExpiresAtUtc.value
          : this.leaseExpiresAtUtc,
      lastFailureCode: data.lastFailureCode.present
          ? data.lastFailureCode.value
          : this.lastFailureCode,
      completedAtUtc: data.completedAtUtc.present
          ? data.completedAtUtc.value
          : this.completedAtUtc,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DbSyncOutboxData(')
          ..write('commandId: $commandId, ')
          ..write('protocolVersion: $protocolVersion, ')
          ..write('commandType: $commandType, ')
          ..write('deviceId: $deviceId, ')
          ..write('aggregateId: $aggregateId, ')
          ..write('baseRevision: $baseRevision, ')
          ..write('payloadJson: $payloadJson, ')
          ..write('createdAtUtc: $createdAtUtc, ')
          ..write('status: $status, ')
          ..write('attemptCount: $attemptCount, ')
          ..write('nextAttemptAtUtc: $nextAttemptAtUtc, ')
          ..write('leaseOwner: $leaseOwner, ')
          ..write('leaseExpiresAtUtc: $leaseExpiresAtUtc, ')
          ..write('lastFailureCode: $lastFailureCode, ')
          ..write('completedAtUtc: $completedAtUtc')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    commandId,
    protocolVersion,
    commandType,
    deviceId,
    aggregateId,
    baseRevision,
    payloadJson,
    createdAtUtc,
    status,
    attemptCount,
    nextAttemptAtUtc,
    leaseOwner,
    leaseExpiresAtUtc,
    lastFailureCode,
    completedAtUtc,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DbSyncOutboxData &&
          other.commandId == this.commandId &&
          other.protocolVersion == this.protocolVersion &&
          other.commandType == this.commandType &&
          other.deviceId == this.deviceId &&
          other.aggregateId == this.aggregateId &&
          other.baseRevision == this.baseRevision &&
          other.payloadJson == this.payloadJson &&
          other.createdAtUtc == this.createdAtUtc &&
          other.status == this.status &&
          other.attemptCount == this.attemptCount &&
          other.nextAttemptAtUtc == this.nextAttemptAtUtc &&
          other.leaseOwner == this.leaseOwner &&
          other.leaseExpiresAtUtc == this.leaseExpiresAtUtc &&
          other.lastFailureCode == this.lastFailureCode &&
          other.completedAtUtc == this.completedAtUtc);
}

class DbSyncOutboxCompanion extends UpdateCompanion<DbSyncOutboxData> {
  final Value<String> commandId;
  final Value<int> protocolVersion;
  final Value<String> commandType;
  final Value<String> deviceId;
  final Value<String> aggregateId;
  final Value<int> baseRevision;
  final Value<String> payloadJson;
  final Value<DateTime> createdAtUtc;
  final Value<String> status;
  final Value<int> attemptCount;
  final Value<DateTime> nextAttemptAtUtc;
  final Value<String?> leaseOwner;
  final Value<DateTime?> leaseExpiresAtUtc;
  final Value<String?> lastFailureCode;
  final Value<DateTime?> completedAtUtc;
  final Value<int> rowid;
  const DbSyncOutboxCompanion({
    this.commandId = const Value.absent(),
    this.protocolVersion = const Value.absent(),
    this.commandType = const Value.absent(),
    this.deviceId = const Value.absent(),
    this.aggregateId = const Value.absent(),
    this.baseRevision = const Value.absent(),
    this.payloadJson = const Value.absent(),
    this.createdAtUtc = const Value.absent(),
    this.status = const Value.absent(),
    this.attemptCount = const Value.absent(),
    this.nextAttemptAtUtc = const Value.absent(),
    this.leaseOwner = const Value.absent(),
    this.leaseExpiresAtUtc = const Value.absent(),
    this.lastFailureCode = const Value.absent(),
    this.completedAtUtc = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DbSyncOutboxCompanion.insert({
    required String commandId,
    required int protocolVersion,
    required String commandType,
    required String deviceId,
    required String aggregateId,
    required int baseRevision,
    required String payloadJson,
    required DateTime createdAtUtc,
    required String status,
    this.attemptCount = const Value.absent(),
    required DateTime nextAttemptAtUtc,
    this.leaseOwner = const Value.absent(),
    this.leaseExpiresAtUtc = const Value.absent(),
    this.lastFailureCode = const Value.absent(),
    this.completedAtUtc = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : commandId = Value(commandId),
       protocolVersion = Value(protocolVersion),
       commandType = Value(commandType),
       deviceId = Value(deviceId),
       aggregateId = Value(aggregateId),
       baseRevision = Value(baseRevision),
       payloadJson = Value(payloadJson),
       createdAtUtc = Value(createdAtUtc),
       status = Value(status),
       nextAttemptAtUtc = Value(nextAttemptAtUtc);
  static Insertable<DbSyncOutboxData> custom({
    Expression<String>? commandId,
    Expression<int>? protocolVersion,
    Expression<String>? commandType,
    Expression<String>? deviceId,
    Expression<String>? aggregateId,
    Expression<int>? baseRevision,
    Expression<String>? payloadJson,
    Expression<DateTime>? createdAtUtc,
    Expression<String>? status,
    Expression<int>? attemptCount,
    Expression<DateTime>? nextAttemptAtUtc,
    Expression<String>? leaseOwner,
    Expression<DateTime>? leaseExpiresAtUtc,
    Expression<String>? lastFailureCode,
    Expression<DateTime>? completedAtUtc,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (commandId != null) 'command_id': commandId,
      if (protocolVersion != null) 'protocol_version': protocolVersion,
      if (commandType != null) 'command_type': commandType,
      if (deviceId != null) 'device_id': deviceId,
      if (aggregateId != null) 'aggregate_id': aggregateId,
      if (baseRevision != null) 'base_revision': baseRevision,
      if (payloadJson != null) 'payload_json': payloadJson,
      if (createdAtUtc != null) 'created_at_utc': createdAtUtc,
      if (status != null) 'status': status,
      if (attemptCount != null) 'attempt_count': attemptCount,
      if (nextAttemptAtUtc != null) 'next_attempt_at_utc': nextAttemptAtUtc,
      if (leaseOwner != null) 'lease_owner': leaseOwner,
      if (leaseExpiresAtUtc != null) 'lease_expires_at_utc': leaseExpiresAtUtc,
      if (lastFailureCode != null) 'last_failure_code': lastFailureCode,
      if (completedAtUtc != null) 'completed_at_utc': completedAtUtc,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DbSyncOutboxCompanion copyWith({
    Value<String>? commandId,
    Value<int>? protocolVersion,
    Value<String>? commandType,
    Value<String>? deviceId,
    Value<String>? aggregateId,
    Value<int>? baseRevision,
    Value<String>? payloadJson,
    Value<DateTime>? createdAtUtc,
    Value<String>? status,
    Value<int>? attemptCount,
    Value<DateTime>? nextAttemptAtUtc,
    Value<String?>? leaseOwner,
    Value<DateTime?>? leaseExpiresAtUtc,
    Value<String?>? lastFailureCode,
    Value<DateTime?>? completedAtUtc,
    Value<int>? rowid,
  }) {
    return DbSyncOutboxCompanion(
      commandId: commandId ?? this.commandId,
      protocolVersion: protocolVersion ?? this.protocolVersion,
      commandType: commandType ?? this.commandType,
      deviceId: deviceId ?? this.deviceId,
      aggregateId: aggregateId ?? this.aggregateId,
      baseRevision: baseRevision ?? this.baseRevision,
      payloadJson: payloadJson ?? this.payloadJson,
      createdAtUtc: createdAtUtc ?? this.createdAtUtc,
      status: status ?? this.status,
      attemptCount: attemptCount ?? this.attemptCount,
      nextAttemptAtUtc: nextAttemptAtUtc ?? this.nextAttemptAtUtc,
      leaseOwner: leaseOwner ?? this.leaseOwner,
      leaseExpiresAtUtc: leaseExpiresAtUtc ?? this.leaseExpiresAtUtc,
      lastFailureCode: lastFailureCode ?? this.lastFailureCode,
      completedAtUtc: completedAtUtc ?? this.completedAtUtc,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (commandId.present) {
      map['command_id'] = Variable<String>(commandId.value);
    }
    if (protocolVersion.present) {
      map['protocol_version'] = Variable<int>(protocolVersion.value);
    }
    if (commandType.present) {
      map['command_type'] = Variable<String>(commandType.value);
    }
    if (deviceId.present) {
      map['device_id'] = Variable<String>(deviceId.value);
    }
    if (aggregateId.present) {
      map['aggregate_id'] = Variable<String>(aggregateId.value);
    }
    if (baseRevision.present) {
      map['base_revision'] = Variable<int>(baseRevision.value);
    }
    if (payloadJson.present) {
      map['payload_json'] = Variable<String>(payloadJson.value);
    }
    if (createdAtUtc.present) {
      map['created_at_utc'] = Variable<DateTime>(createdAtUtc.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (attemptCount.present) {
      map['attempt_count'] = Variable<int>(attemptCount.value);
    }
    if (nextAttemptAtUtc.present) {
      map['next_attempt_at_utc'] = Variable<DateTime>(nextAttemptAtUtc.value);
    }
    if (leaseOwner.present) {
      map['lease_owner'] = Variable<String>(leaseOwner.value);
    }
    if (leaseExpiresAtUtc.present) {
      map['lease_expires_at_utc'] = Variable<DateTime>(leaseExpiresAtUtc.value);
    }
    if (lastFailureCode.present) {
      map['last_failure_code'] = Variable<String>(lastFailureCode.value);
    }
    if (completedAtUtc.present) {
      map['completed_at_utc'] = Variable<DateTime>(completedAtUtc.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DbSyncOutboxCompanion(')
          ..write('commandId: $commandId, ')
          ..write('protocolVersion: $protocolVersion, ')
          ..write('commandType: $commandType, ')
          ..write('deviceId: $deviceId, ')
          ..write('aggregateId: $aggregateId, ')
          ..write('baseRevision: $baseRevision, ')
          ..write('payloadJson: $payloadJson, ')
          ..write('createdAtUtc: $createdAtUtc, ')
          ..write('status: $status, ')
          ..write('attemptCount: $attemptCount, ')
          ..write('nextAttemptAtUtc: $nextAttemptAtUtc, ')
          ..write('leaseOwner: $leaseOwner, ')
          ..write('leaseExpiresAtUtc: $leaseExpiresAtUtc, ')
          ..write('lastFailureCode: $lastFailureCode, ')
          ..write('completedAtUtc: $completedAtUtc, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $DbContactRecordsTable extends DbContactRecords
    with TableInfo<$DbContactRecordsTable, DbContactRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DbContactRecordsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _contactIdMeta = const VerificationMeta(
    'contactId',
  );
  @override
  late final GeneratedColumn<String> contactId = GeneratedColumn<String>(
    'contact_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _appUserIdMeta = const VerificationMeta(
    'appUserId',
  );
  @override
  late final GeneratedColumn<String> appUserId = GeneratedColumn<String>(
    'app_user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _workspaceIdMeta = const VerificationMeta(
    'workspaceId',
  );
  @override
  late final GeneratedColumn<String> workspaceId = GeneratedColumn<String>(
    'workspace_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _projectIdMeta = const VerificationMeta(
    'projectId',
  );
  @override
  late final GeneratedColumn<String> projectId = GeneratedColumn<String>(
    'project_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _questionnaireVersionIdMeta =
      const VerificationMeta('questionnaireVersionId');
  @override
  late final GeneratedColumn<String> questionnaireVersionId =
      GeneratedColumn<String>(
        'questionnaire_version_id',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _occurredAtUtcMeta = const VerificationMeta(
    'occurredAtUtc',
  );
  @override
  late final GeneratedColumn<DateTime> occurredAtUtc =
      GeneratedColumn<DateTime>(
        'occurred_at_utc',
        aliasedName,
        false,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _occurredTimeZoneMeta = const VerificationMeta(
    'occurredTimeZone',
  );
  @override
  late final GeneratedColumn<String> occurredTimeZone = GeneratedColumn<String>(
    'occurred_time_zone',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _firstSubmittedAtUtcMeta =
      const VerificationMeta('firstSubmittedAtUtc');
  @override
  late final GeneratedColumn<DateTime> firstSubmittedAtUtc =
      GeneratedColumn<DateTime>(
        'first_submitted_at_utc',
        aliasedName,
        false,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _channelMeta = const VerificationMeta(
    'channel',
  );
  @override
  late final GeneratedColumn<String> channel = GeneratedColumn<String>(
    'channel',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _channelDetailMeta = const VerificationMeta(
    'channelDetail',
  );
  @override
  late final GeneratedColumn<String> channelDetail = GeneratedColumn<String>(
    'channel_detail',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _locationKindMeta = const VerificationMeta(
    'locationKind',
  );
  @override
  late final GeneratedColumn<String> locationKind = GeneratedColumn<String>(
    'location_kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _placeNameMeta = const VerificationMeta(
    'placeName',
  );
  @override
  late final GeneratedColumn<String> placeName = GeneratedColumn<String>(
    'place_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _smallestRegionIdMeta = const VerificationMeta(
    'smallestRegionId',
  );
  @override
  late final GeneratedColumn<String> smallestRegionId = GeneratedColumn<String>(
    'smallest_region_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _latitudeMeta = const VerificationMeta(
    'latitude',
  );
  @override
  late final GeneratedColumn<double> latitude = GeneratedColumn<double>(
    'latitude',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _longitudeMeta = const VerificationMeta(
    'longitude',
  );
  @override
  late final GeneratedColumn<double> longitude = GeneratedColumn<double>(
    'longitude',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _locationAccuracyMetersMeta =
      const VerificationMeta('locationAccuracyMeters');
  @override
  late final GeneratedColumn<double> locationAccuracyMeters =
      GeneratedColumn<double>(
        'location_accuracy_meters',
        aliasedName,
        true,
        type: DriftSqlType.double,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _reachCountMeta = const VerificationMeta(
    'reachCount',
  );
  @override
  late final GeneratedColumn<int> reachCount = GeneratedColumn<int>(
    'reach_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _interestLevelMeta = const VerificationMeta(
    'interestLevel',
  );
  @override
  late final GeneratedColumn<int> interestLevel = GeneratedColumn<int>(
    'interest_level',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _currentRevisionMeta = const VerificationMeta(
    'currentRevision',
  );
  @override
  late final GeneratedColumn<int> currentRevision = GeneratedColumn<int>(
    'current_revision',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lifecycleStatusMeta = const VerificationMeta(
    'lifecycleStatus',
  );
  @override
  late final GeneratedColumn<String> lifecycleStatus = GeneratedColumn<String>(
    'lifecycle_status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    contactId,
    appUserId,
    workspaceId,
    projectId,
    questionnaireVersionId,
    occurredAtUtc,
    occurredTimeZone,
    firstSubmittedAtUtc,
    channel,
    channelDetail,
    locationKind,
    placeName,
    smallestRegionId,
    latitude,
    longitude,
    locationAccuracyMeters,
    reachCount,
    interestLevel,
    currentRevision,
    lifecycleStatus,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'db_contact_records';
  @override
  VerificationContext validateIntegrity(
    Insertable<DbContactRecord> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('contact_id')) {
      context.handle(
        _contactIdMeta,
        contactId.isAcceptableOrUnknown(data['contact_id']!, _contactIdMeta),
      );
    } else if (isInserting) {
      context.missing(_contactIdMeta);
    }
    if (data.containsKey('app_user_id')) {
      context.handle(
        _appUserIdMeta,
        appUserId.isAcceptableOrUnknown(data['app_user_id']!, _appUserIdMeta),
      );
    } else if (isInserting) {
      context.missing(_appUserIdMeta);
    }
    if (data.containsKey('workspace_id')) {
      context.handle(
        _workspaceIdMeta,
        workspaceId.isAcceptableOrUnknown(
          data['workspace_id']!,
          _workspaceIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_workspaceIdMeta);
    }
    if (data.containsKey('project_id')) {
      context.handle(
        _projectIdMeta,
        projectId.isAcceptableOrUnknown(data['project_id']!, _projectIdMeta),
      );
    } else if (isInserting) {
      context.missing(_projectIdMeta);
    }
    if (data.containsKey('questionnaire_version_id')) {
      context.handle(
        _questionnaireVersionIdMeta,
        questionnaireVersionId.isAcceptableOrUnknown(
          data['questionnaire_version_id']!,
          _questionnaireVersionIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_questionnaireVersionIdMeta);
    }
    if (data.containsKey('occurred_at_utc')) {
      context.handle(
        _occurredAtUtcMeta,
        occurredAtUtc.isAcceptableOrUnknown(
          data['occurred_at_utc']!,
          _occurredAtUtcMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_occurredAtUtcMeta);
    }
    if (data.containsKey('occurred_time_zone')) {
      context.handle(
        _occurredTimeZoneMeta,
        occurredTimeZone.isAcceptableOrUnknown(
          data['occurred_time_zone']!,
          _occurredTimeZoneMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_occurredTimeZoneMeta);
    }
    if (data.containsKey('first_submitted_at_utc')) {
      context.handle(
        _firstSubmittedAtUtcMeta,
        firstSubmittedAtUtc.isAcceptableOrUnknown(
          data['first_submitted_at_utc']!,
          _firstSubmittedAtUtcMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_firstSubmittedAtUtcMeta);
    }
    if (data.containsKey('channel')) {
      context.handle(
        _channelMeta,
        channel.isAcceptableOrUnknown(data['channel']!, _channelMeta),
      );
    } else if (isInserting) {
      context.missing(_channelMeta);
    }
    if (data.containsKey('channel_detail')) {
      context.handle(
        _channelDetailMeta,
        channelDetail.isAcceptableOrUnknown(
          data['channel_detail']!,
          _channelDetailMeta,
        ),
      );
    }
    if (data.containsKey('location_kind')) {
      context.handle(
        _locationKindMeta,
        locationKind.isAcceptableOrUnknown(
          data['location_kind']!,
          _locationKindMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_locationKindMeta);
    }
    if (data.containsKey('place_name')) {
      context.handle(
        _placeNameMeta,
        placeName.isAcceptableOrUnknown(data['place_name']!, _placeNameMeta),
      );
    }
    if (data.containsKey('smallest_region_id')) {
      context.handle(
        _smallestRegionIdMeta,
        smallestRegionId.isAcceptableOrUnknown(
          data['smallest_region_id']!,
          _smallestRegionIdMeta,
        ),
      );
    }
    if (data.containsKey('latitude')) {
      context.handle(
        _latitudeMeta,
        latitude.isAcceptableOrUnknown(data['latitude']!, _latitudeMeta),
      );
    }
    if (data.containsKey('longitude')) {
      context.handle(
        _longitudeMeta,
        longitude.isAcceptableOrUnknown(data['longitude']!, _longitudeMeta),
      );
    }
    if (data.containsKey('location_accuracy_meters')) {
      context.handle(
        _locationAccuracyMetersMeta,
        locationAccuracyMeters.isAcceptableOrUnknown(
          data['location_accuracy_meters']!,
          _locationAccuracyMetersMeta,
        ),
      );
    }
    if (data.containsKey('reach_count')) {
      context.handle(
        _reachCountMeta,
        reachCount.isAcceptableOrUnknown(data['reach_count']!, _reachCountMeta),
      );
    } else if (isInserting) {
      context.missing(_reachCountMeta);
    }
    if (data.containsKey('interest_level')) {
      context.handle(
        _interestLevelMeta,
        interestLevel.isAcceptableOrUnknown(
          data['interest_level']!,
          _interestLevelMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_interestLevelMeta);
    }
    if (data.containsKey('current_revision')) {
      context.handle(
        _currentRevisionMeta,
        currentRevision.isAcceptableOrUnknown(
          data['current_revision']!,
          _currentRevisionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_currentRevisionMeta);
    }
    if (data.containsKey('lifecycle_status')) {
      context.handle(
        _lifecycleStatusMeta,
        lifecycleStatus.isAcceptableOrUnknown(
          data['lifecycle_status']!,
          _lifecycleStatusMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_lifecycleStatusMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {contactId};
  @override
  DbContactRecord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DbContactRecord(
      contactId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}contact_id'],
      )!,
      appUserId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}app_user_id'],
      )!,
      workspaceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}workspace_id'],
      )!,
      projectId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}project_id'],
      )!,
      questionnaireVersionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}questionnaire_version_id'],
      )!,
      occurredAtUtc: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}occurred_at_utc'],
      )!,
      occurredTimeZone: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}occurred_time_zone'],
      )!,
      firstSubmittedAtUtc: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}first_submitted_at_utc'],
      )!,
      channel: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}channel'],
      )!,
      channelDetail: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}channel_detail'],
      ),
      locationKind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}location_kind'],
      )!,
      placeName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}place_name'],
      ),
      smallestRegionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}smallest_region_id'],
      ),
      latitude: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}latitude'],
      ),
      longitude: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}longitude'],
      ),
      locationAccuracyMeters: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}location_accuracy_meters'],
      ),
      reachCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}reach_count'],
      )!,
      interestLevel: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}interest_level'],
      )!,
      currentRevision: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}current_revision'],
      )!,
      lifecycleStatus: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}lifecycle_status'],
      )!,
    );
  }

  @override
  $DbContactRecordsTable createAlias(String alias) {
    return $DbContactRecordsTable(attachedDatabase, alias);
  }
}

class DbContactRecord extends DataClass implements Insertable<DbContactRecord> {
  final String contactId;
  final String appUserId;
  final String workspaceId;
  final String projectId;
  final String questionnaireVersionId;
  final DateTime occurredAtUtc;
  final String occurredTimeZone;
  final DateTime firstSubmittedAtUtc;
  final String channel;
  final String? channelDetail;
  final String locationKind;
  final String? placeName;
  final String? smallestRegionId;
  final double? latitude;
  final double? longitude;
  final double? locationAccuracyMeters;
  final int reachCount;
  final int interestLevel;
  final int currentRevision;
  final String lifecycleStatus;
  const DbContactRecord({
    required this.contactId,
    required this.appUserId,
    required this.workspaceId,
    required this.projectId,
    required this.questionnaireVersionId,
    required this.occurredAtUtc,
    required this.occurredTimeZone,
    required this.firstSubmittedAtUtc,
    required this.channel,
    this.channelDetail,
    required this.locationKind,
    this.placeName,
    this.smallestRegionId,
    this.latitude,
    this.longitude,
    this.locationAccuracyMeters,
    required this.reachCount,
    required this.interestLevel,
    required this.currentRevision,
    required this.lifecycleStatus,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['contact_id'] = Variable<String>(contactId);
    map['app_user_id'] = Variable<String>(appUserId);
    map['workspace_id'] = Variable<String>(workspaceId);
    map['project_id'] = Variable<String>(projectId);
    map['questionnaire_version_id'] = Variable<String>(questionnaireVersionId);
    map['occurred_at_utc'] = Variable<DateTime>(occurredAtUtc);
    map['occurred_time_zone'] = Variable<String>(occurredTimeZone);
    map['first_submitted_at_utc'] = Variable<DateTime>(firstSubmittedAtUtc);
    map['channel'] = Variable<String>(channel);
    if (!nullToAbsent || channelDetail != null) {
      map['channel_detail'] = Variable<String>(channelDetail);
    }
    map['location_kind'] = Variable<String>(locationKind);
    if (!nullToAbsent || placeName != null) {
      map['place_name'] = Variable<String>(placeName);
    }
    if (!nullToAbsent || smallestRegionId != null) {
      map['smallest_region_id'] = Variable<String>(smallestRegionId);
    }
    if (!nullToAbsent || latitude != null) {
      map['latitude'] = Variable<double>(latitude);
    }
    if (!nullToAbsent || longitude != null) {
      map['longitude'] = Variable<double>(longitude);
    }
    if (!nullToAbsent || locationAccuracyMeters != null) {
      map['location_accuracy_meters'] = Variable<double>(
        locationAccuracyMeters,
      );
    }
    map['reach_count'] = Variable<int>(reachCount);
    map['interest_level'] = Variable<int>(interestLevel);
    map['current_revision'] = Variable<int>(currentRevision);
    map['lifecycle_status'] = Variable<String>(lifecycleStatus);
    return map;
  }

  DbContactRecordsCompanion toCompanion(bool nullToAbsent) {
    return DbContactRecordsCompanion(
      contactId: Value(contactId),
      appUserId: Value(appUserId),
      workspaceId: Value(workspaceId),
      projectId: Value(projectId),
      questionnaireVersionId: Value(questionnaireVersionId),
      occurredAtUtc: Value(occurredAtUtc),
      occurredTimeZone: Value(occurredTimeZone),
      firstSubmittedAtUtc: Value(firstSubmittedAtUtc),
      channel: Value(channel),
      channelDetail: channelDetail == null && nullToAbsent
          ? const Value.absent()
          : Value(channelDetail),
      locationKind: Value(locationKind),
      placeName: placeName == null && nullToAbsent
          ? const Value.absent()
          : Value(placeName),
      smallestRegionId: smallestRegionId == null && nullToAbsent
          ? const Value.absent()
          : Value(smallestRegionId),
      latitude: latitude == null && nullToAbsent
          ? const Value.absent()
          : Value(latitude),
      longitude: longitude == null && nullToAbsent
          ? const Value.absent()
          : Value(longitude),
      locationAccuracyMeters: locationAccuracyMeters == null && nullToAbsent
          ? const Value.absent()
          : Value(locationAccuracyMeters),
      reachCount: Value(reachCount),
      interestLevel: Value(interestLevel),
      currentRevision: Value(currentRevision),
      lifecycleStatus: Value(lifecycleStatus),
    );
  }

  factory DbContactRecord.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DbContactRecord(
      contactId: serializer.fromJson<String>(json['contactId']),
      appUserId: serializer.fromJson<String>(json['appUserId']),
      workspaceId: serializer.fromJson<String>(json['workspaceId']),
      projectId: serializer.fromJson<String>(json['projectId']),
      questionnaireVersionId: serializer.fromJson<String>(
        json['questionnaireVersionId'],
      ),
      occurredAtUtc: serializer.fromJson<DateTime>(json['occurredAtUtc']),
      occurredTimeZone: serializer.fromJson<String>(json['occurredTimeZone']),
      firstSubmittedAtUtc: serializer.fromJson<DateTime>(
        json['firstSubmittedAtUtc'],
      ),
      channel: serializer.fromJson<String>(json['channel']),
      channelDetail: serializer.fromJson<String?>(json['channelDetail']),
      locationKind: serializer.fromJson<String>(json['locationKind']),
      placeName: serializer.fromJson<String?>(json['placeName']),
      smallestRegionId: serializer.fromJson<String?>(json['smallestRegionId']),
      latitude: serializer.fromJson<double?>(json['latitude']),
      longitude: serializer.fromJson<double?>(json['longitude']),
      locationAccuracyMeters: serializer.fromJson<double?>(
        json['locationAccuracyMeters'],
      ),
      reachCount: serializer.fromJson<int>(json['reachCount']),
      interestLevel: serializer.fromJson<int>(json['interestLevel']),
      currentRevision: serializer.fromJson<int>(json['currentRevision']),
      lifecycleStatus: serializer.fromJson<String>(json['lifecycleStatus']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'contactId': serializer.toJson<String>(contactId),
      'appUserId': serializer.toJson<String>(appUserId),
      'workspaceId': serializer.toJson<String>(workspaceId),
      'projectId': serializer.toJson<String>(projectId),
      'questionnaireVersionId': serializer.toJson<String>(
        questionnaireVersionId,
      ),
      'occurredAtUtc': serializer.toJson<DateTime>(occurredAtUtc),
      'occurredTimeZone': serializer.toJson<String>(occurredTimeZone),
      'firstSubmittedAtUtc': serializer.toJson<DateTime>(firstSubmittedAtUtc),
      'channel': serializer.toJson<String>(channel),
      'channelDetail': serializer.toJson<String?>(channelDetail),
      'locationKind': serializer.toJson<String>(locationKind),
      'placeName': serializer.toJson<String?>(placeName),
      'smallestRegionId': serializer.toJson<String?>(smallestRegionId),
      'latitude': serializer.toJson<double?>(latitude),
      'longitude': serializer.toJson<double?>(longitude),
      'locationAccuracyMeters': serializer.toJson<double?>(
        locationAccuracyMeters,
      ),
      'reachCount': serializer.toJson<int>(reachCount),
      'interestLevel': serializer.toJson<int>(interestLevel),
      'currentRevision': serializer.toJson<int>(currentRevision),
      'lifecycleStatus': serializer.toJson<String>(lifecycleStatus),
    };
  }

  DbContactRecord copyWith({
    String? contactId,
    String? appUserId,
    String? workspaceId,
    String? projectId,
    String? questionnaireVersionId,
    DateTime? occurredAtUtc,
    String? occurredTimeZone,
    DateTime? firstSubmittedAtUtc,
    String? channel,
    Value<String?> channelDetail = const Value.absent(),
    String? locationKind,
    Value<String?> placeName = const Value.absent(),
    Value<String?> smallestRegionId = const Value.absent(),
    Value<double?> latitude = const Value.absent(),
    Value<double?> longitude = const Value.absent(),
    Value<double?> locationAccuracyMeters = const Value.absent(),
    int? reachCount,
    int? interestLevel,
    int? currentRevision,
    String? lifecycleStatus,
  }) => DbContactRecord(
    contactId: contactId ?? this.contactId,
    appUserId: appUserId ?? this.appUserId,
    workspaceId: workspaceId ?? this.workspaceId,
    projectId: projectId ?? this.projectId,
    questionnaireVersionId:
        questionnaireVersionId ?? this.questionnaireVersionId,
    occurredAtUtc: occurredAtUtc ?? this.occurredAtUtc,
    occurredTimeZone: occurredTimeZone ?? this.occurredTimeZone,
    firstSubmittedAtUtc: firstSubmittedAtUtc ?? this.firstSubmittedAtUtc,
    channel: channel ?? this.channel,
    channelDetail: channelDetail.present
        ? channelDetail.value
        : this.channelDetail,
    locationKind: locationKind ?? this.locationKind,
    placeName: placeName.present ? placeName.value : this.placeName,
    smallestRegionId: smallestRegionId.present
        ? smallestRegionId.value
        : this.smallestRegionId,
    latitude: latitude.present ? latitude.value : this.latitude,
    longitude: longitude.present ? longitude.value : this.longitude,
    locationAccuracyMeters: locationAccuracyMeters.present
        ? locationAccuracyMeters.value
        : this.locationAccuracyMeters,
    reachCount: reachCount ?? this.reachCount,
    interestLevel: interestLevel ?? this.interestLevel,
    currentRevision: currentRevision ?? this.currentRevision,
    lifecycleStatus: lifecycleStatus ?? this.lifecycleStatus,
  );
  DbContactRecord copyWithCompanion(DbContactRecordsCompanion data) {
    return DbContactRecord(
      contactId: data.contactId.present ? data.contactId.value : this.contactId,
      appUserId: data.appUserId.present ? data.appUserId.value : this.appUserId,
      workspaceId: data.workspaceId.present
          ? data.workspaceId.value
          : this.workspaceId,
      projectId: data.projectId.present ? data.projectId.value : this.projectId,
      questionnaireVersionId: data.questionnaireVersionId.present
          ? data.questionnaireVersionId.value
          : this.questionnaireVersionId,
      occurredAtUtc: data.occurredAtUtc.present
          ? data.occurredAtUtc.value
          : this.occurredAtUtc,
      occurredTimeZone: data.occurredTimeZone.present
          ? data.occurredTimeZone.value
          : this.occurredTimeZone,
      firstSubmittedAtUtc: data.firstSubmittedAtUtc.present
          ? data.firstSubmittedAtUtc.value
          : this.firstSubmittedAtUtc,
      channel: data.channel.present ? data.channel.value : this.channel,
      channelDetail: data.channelDetail.present
          ? data.channelDetail.value
          : this.channelDetail,
      locationKind: data.locationKind.present
          ? data.locationKind.value
          : this.locationKind,
      placeName: data.placeName.present ? data.placeName.value : this.placeName,
      smallestRegionId: data.smallestRegionId.present
          ? data.smallestRegionId.value
          : this.smallestRegionId,
      latitude: data.latitude.present ? data.latitude.value : this.latitude,
      longitude: data.longitude.present ? data.longitude.value : this.longitude,
      locationAccuracyMeters: data.locationAccuracyMeters.present
          ? data.locationAccuracyMeters.value
          : this.locationAccuracyMeters,
      reachCount: data.reachCount.present
          ? data.reachCount.value
          : this.reachCount,
      interestLevel: data.interestLevel.present
          ? data.interestLevel.value
          : this.interestLevel,
      currentRevision: data.currentRevision.present
          ? data.currentRevision.value
          : this.currentRevision,
      lifecycleStatus: data.lifecycleStatus.present
          ? data.lifecycleStatus.value
          : this.lifecycleStatus,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DbContactRecord(')
          ..write('contactId: $contactId, ')
          ..write('appUserId: $appUserId, ')
          ..write('workspaceId: $workspaceId, ')
          ..write('projectId: $projectId, ')
          ..write('questionnaireVersionId: $questionnaireVersionId, ')
          ..write('occurredAtUtc: $occurredAtUtc, ')
          ..write('occurredTimeZone: $occurredTimeZone, ')
          ..write('firstSubmittedAtUtc: $firstSubmittedAtUtc, ')
          ..write('channel: $channel, ')
          ..write('channelDetail: $channelDetail, ')
          ..write('locationKind: $locationKind, ')
          ..write('placeName: $placeName, ')
          ..write('smallestRegionId: $smallestRegionId, ')
          ..write('latitude: $latitude, ')
          ..write('longitude: $longitude, ')
          ..write('locationAccuracyMeters: $locationAccuracyMeters, ')
          ..write('reachCount: $reachCount, ')
          ..write('interestLevel: $interestLevel, ')
          ..write('currentRevision: $currentRevision, ')
          ..write('lifecycleStatus: $lifecycleStatus')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    contactId,
    appUserId,
    workspaceId,
    projectId,
    questionnaireVersionId,
    occurredAtUtc,
    occurredTimeZone,
    firstSubmittedAtUtc,
    channel,
    channelDetail,
    locationKind,
    placeName,
    smallestRegionId,
    latitude,
    longitude,
    locationAccuracyMeters,
    reachCount,
    interestLevel,
    currentRevision,
    lifecycleStatus,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DbContactRecord &&
          other.contactId == this.contactId &&
          other.appUserId == this.appUserId &&
          other.workspaceId == this.workspaceId &&
          other.projectId == this.projectId &&
          other.questionnaireVersionId == this.questionnaireVersionId &&
          other.occurredAtUtc == this.occurredAtUtc &&
          other.occurredTimeZone == this.occurredTimeZone &&
          other.firstSubmittedAtUtc == this.firstSubmittedAtUtc &&
          other.channel == this.channel &&
          other.channelDetail == this.channelDetail &&
          other.locationKind == this.locationKind &&
          other.placeName == this.placeName &&
          other.smallestRegionId == this.smallestRegionId &&
          other.latitude == this.latitude &&
          other.longitude == this.longitude &&
          other.locationAccuracyMeters == this.locationAccuracyMeters &&
          other.reachCount == this.reachCount &&
          other.interestLevel == this.interestLevel &&
          other.currentRevision == this.currentRevision &&
          other.lifecycleStatus == this.lifecycleStatus);
}

class DbContactRecordsCompanion extends UpdateCompanion<DbContactRecord> {
  final Value<String> contactId;
  final Value<String> appUserId;
  final Value<String> workspaceId;
  final Value<String> projectId;
  final Value<String> questionnaireVersionId;
  final Value<DateTime> occurredAtUtc;
  final Value<String> occurredTimeZone;
  final Value<DateTime> firstSubmittedAtUtc;
  final Value<String> channel;
  final Value<String?> channelDetail;
  final Value<String> locationKind;
  final Value<String?> placeName;
  final Value<String?> smallestRegionId;
  final Value<double?> latitude;
  final Value<double?> longitude;
  final Value<double?> locationAccuracyMeters;
  final Value<int> reachCount;
  final Value<int> interestLevel;
  final Value<int> currentRevision;
  final Value<String> lifecycleStatus;
  final Value<int> rowid;
  const DbContactRecordsCompanion({
    this.contactId = const Value.absent(),
    this.appUserId = const Value.absent(),
    this.workspaceId = const Value.absent(),
    this.projectId = const Value.absent(),
    this.questionnaireVersionId = const Value.absent(),
    this.occurredAtUtc = const Value.absent(),
    this.occurredTimeZone = const Value.absent(),
    this.firstSubmittedAtUtc = const Value.absent(),
    this.channel = const Value.absent(),
    this.channelDetail = const Value.absent(),
    this.locationKind = const Value.absent(),
    this.placeName = const Value.absent(),
    this.smallestRegionId = const Value.absent(),
    this.latitude = const Value.absent(),
    this.longitude = const Value.absent(),
    this.locationAccuracyMeters = const Value.absent(),
    this.reachCount = const Value.absent(),
    this.interestLevel = const Value.absent(),
    this.currentRevision = const Value.absent(),
    this.lifecycleStatus = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DbContactRecordsCompanion.insert({
    required String contactId,
    required String appUserId,
    required String workspaceId,
    required String projectId,
    required String questionnaireVersionId,
    required DateTime occurredAtUtc,
    required String occurredTimeZone,
    required DateTime firstSubmittedAtUtc,
    required String channel,
    this.channelDetail = const Value.absent(),
    required String locationKind,
    this.placeName = const Value.absent(),
    this.smallestRegionId = const Value.absent(),
    this.latitude = const Value.absent(),
    this.longitude = const Value.absent(),
    this.locationAccuracyMeters = const Value.absent(),
    required int reachCount,
    required int interestLevel,
    required int currentRevision,
    required String lifecycleStatus,
    this.rowid = const Value.absent(),
  }) : contactId = Value(contactId),
       appUserId = Value(appUserId),
       workspaceId = Value(workspaceId),
       projectId = Value(projectId),
       questionnaireVersionId = Value(questionnaireVersionId),
       occurredAtUtc = Value(occurredAtUtc),
       occurredTimeZone = Value(occurredTimeZone),
       firstSubmittedAtUtc = Value(firstSubmittedAtUtc),
       channel = Value(channel),
       locationKind = Value(locationKind),
       reachCount = Value(reachCount),
       interestLevel = Value(interestLevel),
       currentRevision = Value(currentRevision),
       lifecycleStatus = Value(lifecycleStatus);
  static Insertable<DbContactRecord> custom({
    Expression<String>? contactId,
    Expression<String>? appUserId,
    Expression<String>? workspaceId,
    Expression<String>? projectId,
    Expression<String>? questionnaireVersionId,
    Expression<DateTime>? occurredAtUtc,
    Expression<String>? occurredTimeZone,
    Expression<DateTime>? firstSubmittedAtUtc,
    Expression<String>? channel,
    Expression<String>? channelDetail,
    Expression<String>? locationKind,
    Expression<String>? placeName,
    Expression<String>? smallestRegionId,
    Expression<double>? latitude,
    Expression<double>? longitude,
    Expression<double>? locationAccuracyMeters,
    Expression<int>? reachCount,
    Expression<int>? interestLevel,
    Expression<int>? currentRevision,
    Expression<String>? lifecycleStatus,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (contactId != null) 'contact_id': contactId,
      if (appUserId != null) 'app_user_id': appUserId,
      if (workspaceId != null) 'workspace_id': workspaceId,
      if (projectId != null) 'project_id': projectId,
      if (questionnaireVersionId != null)
        'questionnaire_version_id': questionnaireVersionId,
      if (occurredAtUtc != null) 'occurred_at_utc': occurredAtUtc,
      if (occurredTimeZone != null) 'occurred_time_zone': occurredTimeZone,
      if (firstSubmittedAtUtc != null)
        'first_submitted_at_utc': firstSubmittedAtUtc,
      if (channel != null) 'channel': channel,
      if (channelDetail != null) 'channel_detail': channelDetail,
      if (locationKind != null) 'location_kind': locationKind,
      if (placeName != null) 'place_name': placeName,
      if (smallestRegionId != null) 'smallest_region_id': smallestRegionId,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      if (locationAccuracyMeters != null)
        'location_accuracy_meters': locationAccuracyMeters,
      if (reachCount != null) 'reach_count': reachCount,
      if (interestLevel != null) 'interest_level': interestLevel,
      if (currentRevision != null) 'current_revision': currentRevision,
      if (lifecycleStatus != null) 'lifecycle_status': lifecycleStatus,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DbContactRecordsCompanion copyWith({
    Value<String>? contactId,
    Value<String>? appUserId,
    Value<String>? workspaceId,
    Value<String>? projectId,
    Value<String>? questionnaireVersionId,
    Value<DateTime>? occurredAtUtc,
    Value<String>? occurredTimeZone,
    Value<DateTime>? firstSubmittedAtUtc,
    Value<String>? channel,
    Value<String?>? channelDetail,
    Value<String>? locationKind,
    Value<String?>? placeName,
    Value<String?>? smallestRegionId,
    Value<double?>? latitude,
    Value<double?>? longitude,
    Value<double?>? locationAccuracyMeters,
    Value<int>? reachCount,
    Value<int>? interestLevel,
    Value<int>? currentRevision,
    Value<String>? lifecycleStatus,
    Value<int>? rowid,
  }) {
    return DbContactRecordsCompanion(
      contactId: contactId ?? this.contactId,
      appUserId: appUserId ?? this.appUserId,
      workspaceId: workspaceId ?? this.workspaceId,
      projectId: projectId ?? this.projectId,
      questionnaireVersionId:
          questionnaireVersionId ?? this.questionnaireVersionId,
      occurredAtUtc: occurredAtUtc ?? this.occurredAtUtc,
      occurredTimeZone: occurredTimeZone ?? this.occurredTimeZone,
      firstSubmittedAtUtc: firstSubmittedAtUtc ?? this.firstSubmittedAtUtc,
      channel: channel ?? this.channel,
      channelDetail: channelDetail ?? this.channelDetail,
      locationKind: locationKind ?? this.locationKind,
      placeName: placeName ?? this.placeName,
      smallestRegionId: smallestRegionId ?? this.smallestRegionId,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      locationAccuracyMeters:
          locationAccuracyMeters ?? this.locationAccuracyMeters,
      reachCount: reachCount ?? this.reachCount,
      interestLevel: interestLevel ?? this.interestLevel,
      currentRevision: currentRevision ?? this.currentRevision,
      lifecycleStatus: lifecycleStatus ?? this.lifecycleStatus,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (contactId.present) {
      map['contact_id'] = Variable<String>(contactId.value);
    }
    if (appUserId.present) {
      map['app_user_id'] = Variable<String>(appUserId.value);
    }
    if (workspaceId.present) {
      map['workspace_id'] = Variable<String>(workspaceId.value);
    }
    if (projectId.present) {
      map['project_id'] = Variable<String>(projectId.value);
    }
    if (questionnaireVersionId.present) {
      map['questionnaire_version_id'] = Variable<String>(
        questionnaireVersionId.value,
      );
    }
    if (occurredAtUtc.present) {
      map['occurred_at_utc'] = Variable<DateTime>(occurredAtUtc.value);
    }
    if (occurredTimeZone.present) {
      map['occurred_time_zone'] = Variable<String>(occurredTimeZone.value);
    }
    if (firstSubmittedAtUtc.present) {
      map['first_submitted_at_utc'] = Variable<DateTime>(
        firstSubmittedAtUtc.value,
      );
    }
    if (channel.present) {
      map['channel'] = Variable<String>(channel.value);
    }
    if (channelDetail.present) {
      map['channel_detail'] = Variable<String>(channelDetail.value);
    }
    if (locationKind.present) {
      map['location_kind'] = Variable<String>(locationKind.value);
    }
    if (placeName.present) {
      map['place_name'] = Variable<String>(placeName.value);
    }
    if (smallestRegionId.present) {
      map['smallest_region_id'] = Variable<String>(smallestRegionId.value);
    }
    if (latitude.present) {
      map['latitude'] = Variable<double>(latitude.value);
    }
    if (longitude.present) {
      map['longitude'] = Variable<double>(longitude.value);
    }
    if (locationAccuracyMeters.present) {
      map['location_accuracy_meters'] = Variable<double>(
        locationAccuracyMeters.value,
      );
    }
    if (reachCount.present) {
      map['reach_count'] = Variable<int>(reachCount.value);
    }
    if (interestLevel.present) {
      map['interest_level'] = Variable<int>(interestLevel.value);
    }
    if (currentRevision.present) {
      map['current_revision'] = Variable<int>(currentRevision.value);
    }
    if (lifecycleStatus.present) {
      map['lifecycle_status'] = Variable<String>(lifecycleStatus.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DbContactRecordsCompanion(')
          ..write('contactId: $contactId, ')
          ..write('appUserId: $appUserId, ')
          ..write('workspaceId: $workspaceId, ')
          ..write('projectId: $projectId, ')
          ..write('questionnaireVersionId: $questionnaireVersionId, ')
          ..write('occurredAtUtc: $occurredAtUtc, ')
          ..write('occurredTimeZone: $occurredTimeZone, ')
          ..write('firstSubmittedAtUtc: $firstSubmittedAtUtc, ')
          ..write('channel: $channel, ')
          ..write('channelDetail: $channelDetail, ')
          ..write('locationKind: $locationKind, ')
          ..write('placeName: $placeName, ')
          ..write('smallestRegionId: $smallestRegionId, ')
          ..write('latitude: $latitude, ')
          ..write('longitude: $longitude, ')
          ..write('locationAccuracyMeters: $locationAccuracyMeters, ')
          ..write('reachCount: $reachCount, ')
          ..write('interestLevel: $interestLevel, ')
          ..write('currentRevision: $currentRevision, ')
          ..write('lifecycleStatus: $lifecycleStatus, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $DbSyncDrainerLeasesTable extends DbSyncDrainerLeases
    with TableInfo<$DbSyncDrainerLeasesTable, DbSyncDrainerLease> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DbSyncDrainerLeasesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _leaseNameMeta = const VerificationMeta(
    'leaseName',
  );
  @override
  late final GeneratedColumn<String> leaseName = GeneratedColumn<String>(
    'lease_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _leaseOwnerMeta = const VerificationMeta(
    'leaseOwner',
  );
  @override
  late final GeneratedColumn<String> leaseOwner = GeneratedColumn<String>(
    'lease_owner',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _leaseExpiresAtUtcMeta = const VerificationMeta(
    'leaseExpiresAtUtc',
  );
  @override
  late final GeneratedColumn<DateTime> leaseExpiresAtUtc =
      GeneratedColumn<DateTime>(
        'lease_expires_at_utc',
        aliasedName,
        false,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: true,
      );
  @override
  List<GeneratedColumn> get $columns => [
    leaseName,
    leaseOwner,
    leaseExpiresAtUtc,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'db_sync_drainer_leases';
  @override
  VerificationContext validateIntegrity(
    Insertable<DbSyncDrainerLease> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('lease_name')) {
      context.handle(
        _leaseNameMeta,
        leaseName.isAcceptableOrUnknown(data['lease_name']!, _leaseNameMeta),
      );
    } else if (isInserting) {
      context.missing(_leaseNameMeta);
    }
    if (data.containsKey('lease_owner')) {
      context.handle(
        _leaseOwnerMeta,
        leaseOwner.isAcceptableOrUnknown(data['lease_owner']!, _leaseOwnerMeta),
      );
    } else if (isInserting) {
      context.missing(_leaseOwnerMeta);
    }
    if (data.containsKey('lease_expires_at_utc')) {
      context.handle(
        _leaseExpiresAtUtcMeta,
        leaseExpiresAtUtc.isAcceptableOrUnknown(
          data['lease_expires_at_utc']!,
          _leaseExpiresAtUtcMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_leaseExpiresAtUtcMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {leaseName};
  @override
  DbSyncDrainerLease map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DbSyncDrainerLease(
      leaseName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}lease_name'],
      )!,
      leaseOwner: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}lease_owner'],
      )!,
      leaseExpiresAtUtc: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}lease_expires_at_utc'],
      )!,
    );
  }

  @override
  $DbSyncDrainerLeasesTable createAlias(String alias) {
    return $DbSyncDrainerLeasesTable(attachedDatabase, alias);
  }
}

class DbSyncDrainerLease extends DataClass
    implements Insertable<DbSyncDrainerLease> {
  final String leaseName;
  final String leaseOwner;
  final DateTime leaseExpiresAtUtc;
  const DbSyncDrainerLease({
    required this.leaseName,
    required this.leaseOwner,
    required this.leaseExpiresAtUtc,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['lease_name'] = Variable<String>(leaseName);
    map['lease_owner'] = Variable<String>(leaseOwner);
    map['lease_expires_at_utc'] = Variable<DateTime>(leaseExpiresAtUtc);
    return map;
  }

  DbSyncDrainerLeasesCompanion toCompanion(bool nullToAbsent) {
    return DbSyncDrainerLeasesCompanion(
      leaseName: Value(leaseName),
      leaseOwner: Value(leaseOwner),
      leaseExpiresAtUtc: Value(leaseExpiresAtUtc),
    );
  }

  factory DbSyncDrainerLease.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DbSyncDrainerLease(
      leaseName: serializer.fromJson<String>(json['leaseName']),
      leaseOwner: serializer.fromJson<String>(json['leaseOwner']),
      leaseExpiresAtUtc: serializer.fromJson<DateTime>(
        json['leaseExpiresAtUtc'],
      ),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'leaseName': serializer.toJson<String>(leaseName),
      'leaseOwner': serializer.toJson<String>(leaseOwner),
      'leaseExpiresAtUtc': serializer.toJson<DateTime>(leaseExpiresAtUtc),
    };
  }

  DbSyncDrainerLease copyWith({
    String? leaseName,
    String? leaseOwner,
    DateTime? leaseExpiresAtUtc,
  }) => DbSyncDrainerLease(
    leaseName: leaseName ?? this.leaseName,
    leaseOwner: leaseOwner ?? this.leaseOwner,
    leaseExpiresAtUtc: leaseExpiresAtUtc ?? this.leaseExpiresAtUtc,
  );
  DbSyncDrainerLease copyWithCompanion(DbSyncDrainerLeasesCompanion data) {
    return DbSyncDrainerLease(
      leaseName: data.leaseName.present ? data.leaseName.value : this.leaseName,
      leaseOwner: data.leaseOwner.present
          ? data.leaseOwner.value
          : this.leaseOwner,
      leaseExpiresAtUtc: data.leaseExpiresAtUtc.present
          ? data.leaseExpiresAtUtc.value
          : this.leaseExpiresAtUtc,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DbSyncDrainerLease(')
          ..write('leaseName: $leaseName, ')
          ..write('leaseOwner: $leaseOwner, ')
          ..write('leaseExpiresAtUtc: $leaseExpiresAtUtc')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(leaseName, leaseOwner, leaseExpiresAtUtc);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DbSyncDrainerLease &&
          other.leaseName == this.leaseName &&
          other.leaseOwner == this.leaseOwner &&
          other.leaseExpiresAtUtc == this.leaseExpiresAtUtc);
}

class DbSyncDrainerLeasesCompanion extends UpdateCompanion<DbSyncDrainerLease> {
  final Value<String> leaseName;
  final Value<String> leaseOwner;
  final Value<DateTime> leaseExpiresAtUtc;
  final Value<int> rowid;
  const DbSyncDrainerLeasesCompanion({
    this.leaseName = const Value.absent(),
    this.leaseOwner = const Value.absent(),
    this.leaseExpiresAtUtc = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DbSyncDrainerLeasesCompanion.insert({
    required String leaseName,
    required String leaseOwner,
    required DateTime leaseExpiresAtUtc,
    this.rowid = const Value.absent(),
  }) : leaseName = Value(leaseName),
       leaseOwner = Value(leaseOwner),
       leaseExpiresAtUtc = Value(leaseExpiresAtUtc);
  static Insertable<DbSyncDrainerLease> custom({
    Expression<String>? leaseName,
    Expression<String>? leaseOwner,
    Expression<DateTime>? leaseExpiresAtUtc,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (leaseName != null) 'lease_name': leaseName,
      if (leaseOwner != null) 'lease_owner': leaseOwner,
      if (leaseExpiresAtUtc != null) 'lease_expires_at_utc': leaseExpiresAtUtc,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DbSyncDrainerLeasesCompanion copyWith({
    Value<String>? leaseName,
    Value<String>? leaseOwner,
    Value<DateTime>? leaseExpiresAtUtc,
    Value<int>? rowid,
  }) {
    return DbSyncDrainerLeasesCompanion(
      leaseName: leaseName ?? this.leaseName,
      leaseOwner: leaseOwner ?? this.leaseOwner,
      leaseExpiresAtUtc: leaseExpiresAtUtc ?? this.leaseExpiresAtUtc,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (leaseName.present) {
      map['lease_name'] = Variable<String>(leaseName.value);
    }
    if (leaseOwner.present) {
      map['lease_owner'] = Variable<String>(leaseOwner.value);
    }
    if (leaseExpiresAtUtc.present) {
      map['lease_expires_at_utc'] = Variable<DateTime>(leaseExpiresAtUtc.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DbSyncDrainerLeasesCompanion(')
          ..write('leaseName: $leaseName, ')
          ..write('leaseOwner: $leaseOwner, ')
          ..write('leaseExpiresAtUtc: $leaseExpiresAtUtc, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $DbSyncScopesTable extends DbSyncScopes
    with TableInfo<$DbSyncScopesTable, DbSyncScope> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DbSyncScopesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _appUserIdMeta = const VerificationMeta(
    'appUserId',
  );
  @override
  late final GeneratedColumn<String> appUserId = GeneratedColumn<String>(
    'app_user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _workspaceIdMeta = const VerificationMeta(
    'workspaceId',
  );
  @override
  late final GeneratedColumn<String> workspaceId = GeneratedColumn<String>(
    'workspace_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _projectIdMeta = const VerificationMeta(
    'projectId',
  );
  @override
  late final GeneratedColumn<String> projectId = GeneratedColumn<String>(
    'project_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _serverCursorMeta = const VerificationMeta(
    'serverCursor',
  );
  @override
  late final GeneratedColumn<String> serverCursor = GeneratedColumn<String>(
    'server_cursor',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastSuccessAtUtcMeta = const VerificationMeta(
    'lastSuccessAtUtc',
  );
  @override
  late final GeneratedColumn<DateTime> lastSuccessAtUtc =
      GeneratedColumn<DateTime>(
        'last_success_at_utc',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _lastFailureCodeMeta = const VerificationMeta(
    'lastFailureCode',
  );
  @override
  late final GeneratedColumn<String> lastFailureCode = GeneratedColumn<String>(
    'last_failure_code',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _updatedAtUtcMeta = const VerificationMeta(
    'updatedAtUtc',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAtUtc = GeneratedColumn<DateTime>(
    'updated_at_utc',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    appUserId,
    workspaceId,
    projectId,
    serverCursor,
    lastSuccessAtUtc,
    lastFailureCode,
    updatedAtUtc,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'db_sync_scopes';
  @override
  VerificationContext validateIntegrity(
    Insertable<DbSyncScope> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('app_user_id')) {
      context.handle(
        _appUserIdMeta,
        appUserId.isAcceptableOrUnknown(data['app_user_id']!, _appUserIdMeta),
      );
    } else if (isInserting) {
      context.missing(_appUserIdMeta);
    }
    if (data.containsKey('workspace_id')) {
      context.handle(
        _workspaceIdMeta,
        workspaceId.isAcceptableOrUnknown(
          data['workspace_id']!,
          _workspaceIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_workspaceIdMeta);
    }
    if (data.containsKey('project_id')) {
      context.handle(
        _projectIdMeta,
        projectId.isAcceptableOrUnknown(data['project_id']!, _projectIdMeta),
      );
    } else if (isInserting) {
      context.missing(_projectIdMeta);
    }
    if (data.containsKey('server_cursor')) {
      context.handle(
        _serverCursorMeta,
        serverCursor.isAcceptableOrUnknown(
          data['server_cursor']!,
          _serverCursorMeta,
        ),
      );
    }
    if (data.containsKey('last_success_at_utc')) {
      context.handle(
        _lastSuccessAtUtcMeta,
        lastSuccessAtUtc.isAcceptableOrUnknown(
          data['last_success_at_utc']!,
          _lastSuccessAtUtcMeta,
        ),
      );
    }
    if (data.containsKey('last_failure_code')) {
      context.handle(
        _lastFailureCodeMeta,
        lastFailureCode.isAcceptableOrUnknown(
          data['last_failure_code']!,
          _lastFailureCodeMeta,
        ),
      );
    }
    if (data.containsKey('updated_at_utc')) {
      context.handle(
        _updatedAtUtcMeta,
        updatedAtUtc.isAcceptableOrUnknown(
          data['updated_at_utc']!,
          _updatedAtUtcMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_updatedAtUtcMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {appUserId, workspaceId, projectId};
  @override
  DbSyncScope map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DbSyncScope(
      appUserId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}app_user_id'],
      )!,
      workspaceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}workspace_id'],
      )!,
      projectId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}project_id'],
      )!,
      serverCursor: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}server_cursor'],
      ),
      lastSuccessAtUtc: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_success_at_utc'],
      ),
      lastFailureCode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_failure_code'],
      ),
      updatedAtUtc: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at_utc'],
      )!,
    );
  }

  @override
  $DbSyncScopesTable createAlias(String alias) {
    return $DbSyncScopesTable(attachedDatabase, alias);
  }
}

class DbSyncScope extends DataClass implements Insertable<DbSyncScope> {
  final String appUserId;
  final String workspaceId;
  final String projectId;
  final String? serverCursor;
  final DateTime? lastSuccessAtUtc;
  final String? lastFailureCode;
  final DateTime updatedAtUtc;
  const DbSyncScope({
    required this.appUserId,
    required this.workspaceId,
    required this.projectId,
    this.serverCursor,
    this.lastSuccessAtUtc,
    this.lastFailureCode,
    required this.updatedAtUtc,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['app_user_id'] = Variable<String>(appUserId);
    map['workspace_id'] = Variable<String>(workspaceId);
    map['project_id'] = Variable<String>(projectId);
    if (!nullToAbsent || serverCursor != null) {
      map['server_cursor'] = Variable<String>(serverCursor);
    }
    if (!nullToAbsent || lastSuccessAtUtc != null) {
      map['last_success_at_utc'] = Variable<DateTime>(lastSuccessAtUtc);
    }
    if (!nullToAbsent || lastFailureCode != null) {
      map['last_failure_code'] = Variable<String>(lastFailureCode);
    }
    map['updated_at_utc'] = Variable<DateTime>(updatedAtUtc);
    return map;
  }

  DbSyncScopesCompanion toCompanion(bool nullToAbsent) {
    return DbSyncScopesCompanion(
      appUserId: Value(appUserId),
      workspaceId: Value(workspaceId),
      projectId: Value(projectId),
      serverCursor: serverCursor == null && nullToAbsent
          ? const Value.absent()
          : Value(serverCursor),
      lastSuccessAtUtc: lastSuccessAtUtc == null && nullToAbsent
          ? const Value.absent()
          : Value(lastSuccessAtUtc),
      lastFailureCode: lastFailureCode == null && nullToAbsent
          ? const Value.absent()
          : Value(lastFailureCode),
      updatedAtUtc: Value(updatedAtUtc),
    );
  }

  factory DbSyncScope.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DbSyncScope(
      appUserId: serializer.fromJson<String>(json['appUserId']),
      workspaceId: serializer.fromJson<String>(json['workspaceId']),
      projectId: serializer.fromJson<String>(json['projectId']),
      serverCursor: serializer.fromJson<String?>(json['serverCursor']),
      lastSuccessAtUtc: serializer.fromJson<DateTime?>(
        json['lastSuccessAtUtc'],
      ),
      lastFailureCode: serializer.fromJson<String?>(json['lastFailureCode']),
      updatedAtUtc: serializer.fromJson<DateTime>(json['updatedAtUtc']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'appUserId': serializer.toJson<String>(appUserId),
      'workspaceId': serializer.toJson<String>(workspaceId),
      'projectId': serializer.toJson<String>(projectId),
      'serverCursor': serializer.toJson<String?>(serverCursor),
      'lastSuccessAtUtc': serializer.toJson<DateTime?>(lastSuccessAtUtc),
      'lastFailureCode': serializer.toJson<String?>(lastFailureCode),
      'updatedAtUtc': serializer.toJson<DateTime>(updatedAtUtc),
    };
  }

  DbSyncScope copyWith({
    String? appUserId,
    String? workspaceId,
    String? projectId,
    Value<String?> serverCursor = const Value.absent(),
    Value<DateTime?> lastSuccessAtUtc = const Value.absent(),
    Value<String?> lastFailureCode = const Value.absent(),
    DateTime? updatedAtUtc,
  }) => DbSyncScope(
    appUserId: appUserId ?? this.appUserId,
    workspaceId: workspaceId ?? this.workspaceId,
    projectId: projectId ?? this.projectId,
    serverCursor: serverCursor.present ? serverCursor.value : this.serverCursor,
    lastSuccessAtUtc: lastSuccessAtUtc.present
        ? lastSuccessAtUtc.value
        : this.lastSuccessAtUtc,
    lastFailureCode: lastFailureCode.present
        ? lastFailureCode.value
        : this.lastFailureCode,
    updatedAtUtc: updatedAtUtc ?? this.updatedAtUtc,
  );
  DbSyncScope copyWithCompanion(DbSyncScopesCompanion data) {
    return DbSyncScope(
      appUserId: data.appUserId.present ? data.appUserId.value : this.appUserId,
      workspaceId: data.workspaceId.present
          ? data.workspaceId.value
          : this.workspaceId,
      projectId: data.projectId.present ? data.projectId.value : this.projectId,
      serverCursor: data.serverCursor.present
          ? data.serverCursor.value
          : this.serverCursor,
      lastSuccessAtUtc: data.lastSuccessAtUtc.present
          ? data.lastSuccessAtUtc.value
          : this.lastSuccessAtUtc,
      lastFailureCode: data.lastFailureCode.present
          ? data.lastFailureCode.value
          : this.lastFailureCode,
      updatedAtUtc: data.updatedAtUtc.present
          ? data.updatedAtUtc.value
          : this.updatedAtUtc,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DbSyncScope(')
          ..write('appUserId: $appUserId, ')
          ..write('workspaceId: $workspaceId, ')
          ..write('projectId: $projectId, ')
          ..write('serverCursor: $serverCursor, ')
          ..write('lastSuccessAtUtc: $lastSuccessAtUtc, ')
          ..write('lastFailureCode: $lastFailureCode, ')
          ..write('updatedAtUtc: $updatedAtUtc')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    appUserId,
    workspaceId,
    projectId,
    serverCursor,
    lastSuccessAtUtc,
    lastFailureCode,
    updatedAtUtc,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DbSyncScope &&
          other.appUserId == this.appUserId &&
          other.workspaceId == this.workspaceId &&
          other.projectId == this.projectId &&
          other.serverCursor == this.serverCursor &&
          other.lastSuccessAtUtc == this.lastSuccessAtUtc &&
          other.lastFailureCode == this.lastFailureCode &&
          other.updatedAtUtc == this.updatedAtUtc);
}

class DbSyncScopesCompanion extends UpdateCompanion<DbSyncScope> {
  final Value<String> appUserId;
  final Value<String> workspaceId;
  final Value<String> projectId;
  final Value<String?> serverCursor;
  final Value<DateTime?> lastSuccessAtUtc;
  final Value<String?> lastFailureCode;
  final Value<DateTime> updatedAtUtc;
  final Value<int> rowid;
  const DbSyncScopesCompanion({
    this.appUserId = const Value.absent(),
    this.workspaceId = const Value.absent(),
    this.projectId = const Value.absent(),
    this.serverCursor = const Value.absent(),
    this.lastSuccessAtUtc = const Value.absent(),
    this.lastFailureCode = const Value.absent(),
    this.updatedAtUtc = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DbSyncScopesCompanion.insert({
    required String appUserId,
    required String workspaceId,
    required String projectId,
    this.serverCursor = const Value.absent(),
    this.lastSuccessAtUtc = const Value.absent(),
    this.lastFailureCode = const Value.absent(),
    required DateTime updatedAtUtc,
    this.rowid = const Value.absent(),
  }) : appUserId = Value(appUserId),
       workspaceId = Value(workspaceId),
       projectId = Value(projectId),
       updatedAtUtc = Value(updatedAtUtc);
  static Insertable<DbSyncScope> custom({
    Expression<String>? appUserId,
    Expression<String>? workspaceId,
    Expression<String>? projectId,
    Expression<String>? serverCursor,
    Expression<DateTime>? lastSuccessAtUtc,
    Expression<String>? lastFailureCode,
    Expression<DateTime>? updatedAtUtc,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (appUserId != null) 'app_user_id': appUserId,
      if (workspaceId != null) 'workspace_id': workspaceId,
      if (projectId != null) 'project_id': projectId,
      if (serverCursor != null) 'server_cursor': serverCursor,
      if (lastSuccessAtUtc != null) 'last_success_at_utc': lastSuccessAtUtc,
      if (lastFailureCode != null) 'last_failure_code': lastFailureCode,
      if (updatedAtUtc != null) 'updated_at_utc': updatedAtUtc,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DbSyncScopesCompanion copyWith({
    Value<String>? appUserId,
    Value<String>? workspaceId,
    Value<String>? projectId,
    Value<String?>? serverCursor,
    Value<DateTime?>? lastSuccessAtUtc,
    Value<String?>? lastFailureCode,
    Value<DateTime>? updatedAtUtc,
    Value<int>? rowid,
  }) {
    return DbSyncScopesCompanion(
      appUserId: appUserId ?? this.appUserId,
      workspaceId: workspaceId ?? this.workspaceId,
      projectId: projectId ?? this.projectId,
      serverCursor: serverCursor ?? this.serverCursor,
      lastSuccessAtUtc: lastSuccessAtUtc ?? this.lastSuccessAtUtc,
      lastFailureCode: lastFailureCode ?? this.lastFailureCode,
      updatedAtUtc: updatedAtUtc ?? this.updatedAtUtc,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (appUserId.present) {
      map['app_user_id'] = Variable<String>(appUserId.value);
    }
    if (workspaceId.present) {
      map['workspace_id'] = Variable<String>(workspaceId.value);
    }
    if (projectId.present) {
      map['project_id'] = Variable<String>(projectId.value);
    }
    if (serverCursor.present) {
      map['server_cursor'] = Variable<String>(serverCursor.value);
    }
    if (lastSuccessAtUtc.present) {
      map['last_success_at_utc'] = Variable<DateTime>(lastSuccessAtUtc.value);
    }
    if (lastFailureCode.present) {
      map['last_failure_code'] = Variable<String>(lastFailureCode.value);
    }
    if (updatedAtUtc.present) {
      map['updated_at_utc'] = Variable<DateTime>(updatedAtUtc.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DbSyncScopesCompanion(')
          ..write('appUserId: $appUserId, ')
          ..write('workspaceId: $workspaceId, ')
          ..write('projectId: $projectId, ')
          ..write('serverCursor: $serverCursor, ')
          ..write('lastSuccessAtUtc: $lastSuccessAtUtc, ')
          ..write('lastFailureCode: $lastFailureCode, ')
          ..write('updatedAtUtc: $updatedAtUtc, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $DbContactRevisionsTable extends DbContactRevisions
    with TableInfo<$DbContactRevisionsTable, DbContactRevision> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DbContactRevisionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _revisionIdMeta = const VerificationMeta(
    'revisionId',
  );
  @override
  late final GeneratedColumn<String> revisionId = GeneratedColumn<String>(
    'revision_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _contactIdMeta = const VerificationMeta(
    'contactId',
  );
  @override
  late final GeneratedColumn<String> contactId = GeneratedColumn<String>(
    'contact_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES db_contact_records (contact_id)',
    ),
  );
  static const VerificationMeta _revisionNumberMeta = const VerificationMeta(
    'revisionNumber',
  );
  @override
  late final GeneratedColumn<int> revisionNumber = GeneratedColumn<int>(
    'revision_number',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _revisedByAppUserIdMeta =
      const VerificationMeta('revisedByAppUserId');
  @override
  late final GeneratedColumn<String> revisedByAppUserId =
      GeneratedColumn<String>(
        'revised_by_app_user_id',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _revisedAtUtcMeta = const VerificationMeta(
    'revisedAtUtc',
  );
  @override
  late final GeneratedColumn<DateTime> revisedAtUtc = GeneratedColumn<DateTime>(
    'revised_at_utc',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _reasonMeta = const VerificationMeta('reason');
  @override
  late final GeneratedColumn<String> reason = GeneratedColumn<String>(
    'reason',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _occurredAtUtcMeta = const VerificationMeta(
    'occurredAtUtc',
  );
  @override
  late final GeneratedColumn<DateTime> occurredAtUtc =
      GeneratedColumn<DateTime>(
        'occurred_at_utc',
        aliasedName,
        false,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _occurredTimeZoneMeta = const VerificationMeta(
    'occurredTimeZone',
  );
  @override
  late final GeneratedColumn<String> occurredTimeZone = GeneratedColumn<String>(
    'occurred_time_zone',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _channelMeta = const VerificationMeta(
    'channel',
  );
  @override
  late final GeneratedColumn<String> channel = GeneratedColumn<String>(
    'channel',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _channelDetailMeta = const VerificationMeta(
    'channelDetail',
  );
  @override
  late final GeneratedColumn<String> channelDetail = GeneratedColumn<String>(
    'channel_detail',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _locationKindMeta = const VerificationMeta(
    'locationKind',
  );
  @override
  late final GeneratedColumn<String> locationKind = GeneratedColumn<String>(
    'location_kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _placeNameMeta = const VerificationMeta(
    'placeName',
  );
  @override
  late final GeneratedColumn<String> placeName = GeneratedColumn<String>(
    'place_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _smallestRegionIdMeta = const VerificationMeta(
    'smallestRegionId',
  );
  @override
  late final GeneratedColumn<String> smallestRegionId = GeneratedColumn<String>(
    'smallest_region_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _latitudeMeta = const VerificationMeta(
    'latitude',
  );
  @override
  late final GeneratedColumn<double> latitude = GeneratedColumn<double>(
    'latitude',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _longitudeMeta = const VerificationMeta(
    'longitude',
  );
  @override
  late final GeneratedColumn<double> longitude = GeneratedColumn<double>(
    'longitude',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _locationAccuracyMetersMeta =
      const VerificationMeta('locationAccuracyMeters');
  @override
  late final GeneratedColumn<double> locationAccuracyMeters =
      GeneratedColumn<double>(
        'location_accuracy_meters',
        aliasedName,
        true,
        type: DriftSqlType.double,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _reachCountMeta = const VerificationMeta(
    'reachCount',
  );
  @override
  late final GeneratedColumn<int> reachCount = GeneratedColumn<int>(
    'reach_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _interestLevelMeta = const VerificationMeta(
    'interestLevel',
  );
  @override
  late final GeneratedColumn<int> interestLevel = GeneratedColumn<int>(
    'interest_level',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    revisionId,
    contactId,
    revisionNumber,
    revisedByAppUserId,
    revisedAtUtc,
    reason,
    occurredAtUtc,
    occurredTimeZone,
    channel,
    channelDetail,
    locationKind,
    placeName,
    smallestRegionId,
    latitude,
    longitude,
    locationAccuracyMeters,
    reachCount,
    interestLevel,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'db_contact_revisions';
  @override
  VerificationContext validateIntegrity(
    Insertable<DbContactRevision> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('revision_id')) {
      context.handle(
        _revisionIdMeta,
        revisionId.isAcceptableOrUnknown(data['revision_id']!, _revisionIdMeta),
      );
    } else if (isInserting) {
      context.missing(_revisionIdMeta);
    }
    if (data.containsKey('contact_id')) {
      context.handle(
        _contactIdMeta,
        contactId.isAcceptableOrUnknown(data['contact_id']!, _contactIdMeta),
      );
    } else if (isInserting) {
      context.missing(_contactIdMeta);
    }
    if (data.containsKey('revision_number')) {
      context.handle(
        _revisionNumberMeta,
        revisionNumber.isAcceptableOrUnknown(
          data['revision_number']!,
          _revisionNumberMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_revisionNumberMeta);
    }
    if (data.containsKey('revised_by_app_user_id')) {
      context.handle(
        _revisedByAppUserIdMeta,
        revisedByAppUserId.isAcceptableOrUnknown(
          data['revised_by_app_user_id']!,
          _revisedByAppUserIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_revisedByAppUserIdMeta);
    }
    if (data.containsKey('revised_at_utc')) {
      context.handle(
        _revisedAtUtcMeta,
        revisedAtUtc.isAcceptableOrUnknown(
          data['revised_at_utc']!,
          _revisedAtUtcMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_revisedAtUtcMeta);
    }
    if (data.containsKey('reason')) {
      context.handle(
        _reasonMeta,
        reason.isAcceptableOrUnknown(data['reason']!, _reasonMeta),
      );
    }
    if (data.containsKey('occurred_at_utc')) {
      context.handle(
        _occurredAtUtcMeta,
        occurredAtUtc.isAcceptableOrUnknown(
          data['occurred_at_utc']!,
          _occurredAtUtcMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_occurredAtUtcMeta);
    }
    if (data.containsKey('occurred_time_zone')) {
      context.handle(
        _occurredTimeZoneMeta,
        occurredTimeZone.isAcceptableOrUnknown(
          data['occurred_time_zone']!,
          _occurredTimeZoneMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_occurredTimeZoneMeta);
    }
    if (data.containsKey('channel')) {
      context.handle(
        _channelMeta,
        channel.isAcceptableOrUnknown(data['channel']!, _channelMeta),
      );
    } else if (isInserting) {
      context.missing(_channelMeta);
    }
    if (data.containsKey('channel_detail')) {
      context.handle(
        _channelDetailMeta,
        channelDetail.isAcceptableOrUnknown(
          data['channel_detail']!,
          _channelDetailMeta,
        ),
      );
    }
    if (data.containsKey('location_kind')) {
      context.handle(
        _locationKindMeta,
        locationKind.isAcceptableOrUnknown(
          data['location_kind']!,
          _locationKindMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_locationKindMeta);
    }
    if (data.containsKey('place_name')) {
      context.handle(
        _placeNameMeta,
        placeName.isAcceptableOrUnknown(data['place_name']!, _placeNameMeta),
      );
    }
    if (data.containsKey('smallest_region_id')) {
      context.handle(
        _smallestRegionIdMeta,
        smallestRegionId.isAcceptableOrUnknown(
          data['smallest_region_id']!,
          _smallestRegionIdMeta,
        ),
      );
    }
    if (data.containsKey('latitude')) {
      context.handle(
        _latitudeMeta,
        latitude.isAcceptableOrUnknown(data['latitude']!, _latitudeMeta),
      );
    }
    if (data.containsKey('longitude')) {
      context.handle(
        _longitudeMeta,
        longitude.isAcceptableOrUnknown(data['longitude']!, _longitudeMeta),
      );
    }
    if (data.containsKey('location_accuracy_meters')) {
      context.handle(
        _locationAccuracyMetersMeta,
        locationAccuracyMeters.isAcceptableOrUnknown(
          data['location_accuracy_meters']!,
          _locationAccuracyMetersMeta,
        ),
      );
    }
    if (data.containsKey('reach_count')) {
      context.handle(
        _reachCountMeta,
        reachCount.isAcceptableOrUnknown(data['reach_count']!, _reachCountMeta),
      );
    } else if (isInserting) {
      context.missing(_reachCountMeta);
    }
    if (data.containsKey('interest_level')) {
      context.handle(
        _interestLevelMeta,
        interestLevel.isAcceptableOrUnknown(
          data['interest_level']!,
          _interestLevelMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_interestLevelMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {revisionId};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {contactId, revisionNumber},
  ];
  @override
  DbContactRevision map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DbContactRevision(
      revisionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}revision_id'],
      )!,
      contactId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}contact_id'],
      )!,
      revisionNumber: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}revision_number'],
      )!,
      revisedByAppUserId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}revised_by_app_user_id'],
      )!,
      revisedAtUtc: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}revised_at_utc'],
      )!,
      reason: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}reason'],
      ),
      occurredAtUtc: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}occurred_at_utc'],
      )!,
      occurredTimeZone: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}occurred_time_zone'],
      )!,
      channel: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}channel'],
      )!,
      channelDetail: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}channel_detail'],
      ),
      locationKind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}location_kind'],
      )!,
      placeName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}place_name'],
      ),
      smallestRegionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}smallest_region_id'],
      ),
      latitude: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}latitude'],
      ),
      longitude: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}longitude'],
      ),
      locationAccuracyMeters: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}location_accuracy_meters'],
      ),
      reachCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}reach_count'],
      )!,
      interestLevel: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}interest_level'],
      )!,
    );
  }

  @override
  $DbContactRevisionsTable createAlias(String alias) {
    return $DbContactRevisionsTable(attachedDatabase, alias);
  }
}

class DbContactRevision extends DataClass
    implements Insertable<DbContactRevision> {
  final String revisionId;
  final String contactId;
  final int revisionNumber;
  final String revisedByAppUserId;
  final DateTime revisedAtUtc;
  final String? reason;
  final DateTime occurredAtUtc;
  final String occurredTimeZone;
  final String channel;
  final String? channelDetail;
  final String locationKind;
  final String? placeName;
  final String? smallestRegionId;
  final double? latitude;
  final double? longitude;
  final double? locationAccuracyMeters;
  final int reachCount;
  final int interestLevel;
  const DbContactRevision({
    required this.revisionId,
    required this.contactId,
    required this.revisionNumber,
    required this.revisedByAppUserId,
    required this.revisedAtUtc,
    this.reason,
    required this.occurredAtUtc,
    required this.occurredTimeZone,
    required this.channel,
    this.channelDetail,
    required this.locationKind,
    this.placeName,
    this.smallestRegionId,
    this.latitude,
    this.longitude,
    this.locationAccuracyMeters,
    required this.reachCount,
    required this.interestLevel,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['revision_id'] = Variable<String>(revisionId);
    map['contact_id'] = Variable<String>(contactId);
    map['revision_number'] = Variable<int>(revisionNumber);
    map['revised_by_app_user_id'] = Variable<String>(revisedByAppUserId);
    map['revised_at_utc'] = Variable<DateTime>(revisedAtUtc);
    if (!nullToAbsent || reason != null) {
      map['reason'] = Variable<String>(reason);
    }
    map['occurred_at_utc'] = Variable<DateTime>(occurredAtUtc);
    map['occurred_time_zone'] = Variable<String>(occurredTimeZone);
    map['channel'] = Variable<String>(channel);
    if (!nullToAbsent || channelDetail != null) {
      map['channel_detail'] = Variable<String>(channelDetail);
    }
    map['location_kind'] = Variable<String>(locationKind);
    if (!nullToAbsent || placeName != null) {
      map['place_name'] = Variable<String>(placeName);
    }
    if (!nullToAbsent || smallestRegionId != null) {
      map['smallest_region_id'] = Variable<String>(smallestRegionId);
    }
    if (!nullToAbsent || latitude != null) {
      map['latitude'] = Variable<double>(latitude);
    }
    if (!nullToAbsent || longitude != null) {
      map['longitude'] = Variable<double>(longitude);
    }
    if (!nullToAbsent || locationAccuracyMeters != null) {
      map['location_accuracy_meters'] = Variable<double>(
        locationAccuracyMeters,
      );
    }
    map['reach_count'] = Variable<int>(reachCount);
    map['interest_level'] = Variable<int>(interestLevel);
    return map;
  }

  DbContactRevisionsCompanion toCompanion(bool nullToAbsent) {
    return DbContactRevisionsCompanion(
      revisionId: Value(revisionId),
      contactId: Value(contactId),
      revisionNumber: Value(revisionNumber),
      revisedByAppUserId: Value(revisedByAppUserId),
      revisedAtUtc: Value(revisedAtUtc),
      reason: reason == null && nullToAbsent
          ? const Value.absent()
          : Value(reason),
      occurredAtUtc: Value(occurredAtUtc),
      occurredTimeZone: Value(occurredTimeZone),
      channel: Value(channel),
      channelDetail: channelDetail == null && nullToAbsent
          ? const Value.absent()
          : Value(channelDetail),
      locationKind: Value(locationKind),
      placeName: placeName == null && nullToAbsent
          ? const Value.absent()
          : Value(placeName),
      smallestRegionId: smallestRegionId == null && nullToAbsent
          ? const Value.absent()
          : Value(smallestRegionId),
      latitude: latitude == null && nullToAbsent
          ? const Value.absent()
          : Value(latitude),
      longitude: longitude == null && nullToAbsent
          ? const Value.absent()
          : Value(longitude),
      locationAccuracyMeters: locationAccuracyMeters == null && nullToAbsent
          ? const Value.absent()
          : Value(locationAccuracyMeters),
      reachCount: Value(reachCount),
      interestLevel: Value(interestLevel),
    );
  }

  factory DbContactRevision.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DbContactRevision(
      revisionId: serializer.fromJson<String>(json['revisionId']),
      contactId: serializer.fromJson<String>(json['contactId']),
      revisionNumber: serializer.fromJson<int>(json['revisionNumber']),
      revisedByAppUserId: serializer.fromJson<String>(
        json['revisedByAppUserId'],
      ),
      revisedAtUtc: serializer.fromJson<DateTime>(json['revisedAtUtc']),
      reason: serializer.fromJson<String?>(json['reason']),
      occurredAtUtc: serializer.fromJson<DateTime>(json['occurredAtUtc']),
      occurredTimeZone: serializer.fromJson<String>(json['occurredTimeZone']),
      channel: serializer.fromJson<String>(json['channel']),
      channelDetail: serializer.fromJson<String?>(json['channelDetail']),
      locationKind: serializer.fromJson<String>(json['locationKind']),
      placeName: serializer.fromJson<String?>(json['placeName']),
      smallestRegionId: serializer.fromJson<String?>(json['smallestRegionId']),
      latitude: serializer.fromJson<double?>(json['latitude']),
      longitude: serializer.fromJson<double?>(json['longitude']),
      locationAccuracyMeters: serializer.fromJson<double?>(
        json['locationAccuracyMeters'],
      ),
      reachCount: serializer.fromJson<int>(json['reachCount']),
      interestLevel: serializer.fromJson<int>(json['interestLevel']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'revisionId': serializer.toJson<String>(revisionId),
      'contactId': serializer.toJson<String>(contactId),
      'revisionNumber': serializer.toJson<int>(revisionNumber),
      'revisedByAppUserId': serializer.toJson<String>(revisedByAppUserId),
      'revisedAtUtc': serializer.toJson<DateTime>(revisedAtUtc),
      'reason': serializer.toJson<String?>(reason),
      'occurredAtUtc': serializer.toJson<DateTime>(occurredAtUtc),
      'occurredTimeZone': serializer.toJson<String>(occurredTimeZone),
      'channel': serializer.toJson<String>(channel),
      'channelDetail': serializer.toJson<String?>(channelDetail),
      'locationKind': serializer.toJson<String>(locationKind),
      'placeName': serializer.toJson<String?>(placeName),
      'smallestRegionId': serializer.toJson<String?>(smallestRegionId),
      'latitude': serializer.toJson<double?>(latitude),
      'longitude': serializer.toJson<double?>(longitude),
      'locationAccuracyMeters': serializer.toJson<double?>(
        locationAccuracyMeters,
      ),
      'reachCount': serializer.toJson<int>(reachCount),
      'interestLevel': serializer.toJson<int>(interestLevel),
    };
  }

  DbContactRevision copyWith({
    String? revisionId,
    String? contactId,
    int? revisionNumber,
    String? revisedByAppUserId,
    DateTime? revisedAtUtc,
    Value<String?> reason = const Value.absent(),
    DateTime? occurredAtUtc,
    String? occurredTimeZone,
    String? channel,
    Value<String?> channelDetail = const Value.absent(),
    String? locationKind,
    Value<String?> placeName = const Value.absent(),
    Value<String?> smallestRegionId = const Value.absent(),
    Value<double?> latitude = const Value.absent(),
    Value<double?> longitude = const Value.absent(),
    Value<double?> locationAccuracyMeters = const Value.absent(),
    int? reachCount,
    int? interestLevel,
  }) => DbContactRevision(
    revisionId: revisionId ?? this.revisionId,
    contactId: contactId ?? this.contactId,
    revisionNumber: revisionNumber ?? this.revisionNumber,
    revisedByAppUserId: revisedByAppUserId ?? this.revisedByAppUserId,
    revisedAtUtc: revisedAtUtc ?? this.revisedAtUtc,
    reason: reason.present ? reason.value : this.reason,
    occurredAtUtc: occurredAtUtc ?? this.occurredAtUtc,
    occurredTimeZone: occurredTimeZone ?? this.occurredTimeZone,
    channel: channel ?? this.channel,
    channelDetail: channelDetail.present
        ? channelDetail.value
        : this.channelDetail,
    locationKind: locationKind ?? this.locationKind,
    placeName: placeName.present ? placeName.value : this.placeName,
    smallestRegionId: smallestRegionId.present
        ? smallestRegionId.value
        : this.smallestRegionId,
    latitude: latitude.present ? latitude.value : this.latitude,
    longitude: longitude.present ? longitude.value : this.longitude,
    locationAccuracyMeters: locationAccuracyMeters.present
        ? locationAccuracyMeters.value
        : this.locationAccuracyMeters,
    reachCount: reachCount ?? this.reachCount,
    interestLevel: interestLevel ?? this.interestLevel,
  );
  DbContactRevision copyWithCompanion(DbContactRevisionsCompanion data) {
    return DbContactRevision(
      revisionId: data.revisionId.present
          ? data.revisionId.value
          : this.revisionId,
      contactId: data.contactId.present ? data.contactId.value : this.contactId,
      revisionNumber: data.revisionNumber.present
          ? data.revisionNumber.value
          : this.revisionNumber,
      revisedByAppUserId: data.revisedByAppUserId.present
          ? data.revisedByAppUserId.value
          : this.revisedByAppUserId,
      revisedAtUtc: data.revisedAtUtc.present
          ? data.revisedAtUtc.value
          : this.revisedAtUtc,
      reason: data.reason.present ? data.reason.value : this.reason,
      occurredAtUtc: data.occurredAtUtc.present
          ? data.occurredAtUtc.value
          : this.occurredAtUtc,
      occurredTimeZone: data.occurredTimeZone.present
          ? data.occurredTimeZone.value
          : this.occurredTimeZone,
      channel: data.channel.present ? data.channel.value : this.channel,
      channelDetail: data.channelDetail.present
          ? data.channelDetail.value
          : this.channelDetail,
      locationKind: data.locationKind.present
          ? data.locationKind.value
          : this.locationKind,
      placeName: data.placeName.present ? data.placeName.value : this.placeName,
      smallestRegionId: data.smallestRegionId.present
          ? data.smallestRegionId.value
          : this.smallestRegionId,
      latitude: data.latitude.present ? data.latitude.value : this.latitude,
      longitude: data.longitude.present ? data.longitude.value : this.longitude,
      locationAccuracyMeters: data.locationAccuracyMeters.present
          ? data.locationAccuracyMeters.value
          : this.locationAccuracyMeters,
      reachCount: data.reachCount.present
          ? data.reachCount.value
          : this.reachCount,
      interestLevel: data.interestLevel.present
          ? data.interestLevel.value
          : this.interestLevel,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DbContactRevision(')
          ..write('revisionId: $revisionId, ')
          ..write('contactId: $contactId, ')
          ..write('revisionNumber: $revisionNumber, ')
          ..write('revisedByAppUserId: $revisedByAppUserId, ')
          ..write('revisedAtUtc: $revisedAtUtc, ')
          ..write('reason: $reason, ')
          ..write('occurredAtUtc: $occurredAtUtc, ')
          ..write('occurredTimeZone: $occurredTimeZone, ')
          ..write('channel: $channel, ')
          ..write('channelDetail: $channelDetail, ')
          ..write('locationKind: $locationKind, ')
          ..write('placeName: $placeName, ')
          ..write('smallestRegionId: $smallestRegionId, ')
          ..write('latitude: $latitude, ')
          ..write('longitude: $longitude, ')
          ..write('locationAccuracyMeters: $locationAccuracyMeters, ')
          ..write('reachCount: $reachCount, ')
          ..write('interestLevel: $interestLevel')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    revisionId,
    contactId,
    revisionNumber,
    revisedByAppUserId,
    revisedAtUtc,
    reason,
    occurredAtUtc,
    occurredTimeZone,
    channel,
    channelDetail,
    locationKind,
    placeName,
    smallestRegionId,
    latitude,
    longitude,
    locationAccuracyMeters,
    reachCount,
    interestLevel,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DbContactRevision &&
          other.revisionId == this.revisionId &&
          other.contactId == this.contactId &&
          other.revisionNumber == this.revisionNumber &&
          other.revisedByAppUserId == this.revisedByAppUserId &&
          other.revisedAtUtc == this.revisedAtUtc &&
          other.reason == this.reason &&
          other.occurredAtUtc == this.occurredAtUtc &&
          other.occurredTimeZone == this.occurredTimeZone &&
          other.channel == this.channel &&
          other.channelDetail == this.channelDetail &&
          other.locationKind == this.locationKind &&
          other.placeName == this.placeName &&
          other.smallestRegionId == this.smallestRegionId &&
          other.latitude == this.latitude &&
          other.longitude == this.longitude &&
          other.locationAccuracyMeters == this.locationAccuracyMeters &&
          other.reachCount == this.reachCount &&
          other.interestLevel == this.interestLevel);
}

class DbContactRevisionsCompanion extends UpdateCompanion<DbContactRevision> {
  final Value<String> revisionId;
  final Value<String> contactId;
  final Value<int> revisionNumber;
  final Value<String> revisedByAppUserId;
  final Value<DateTime> revisedAtUtc;
  final Value<String?> reason;
  final Value<DateTime> occurredAtUtc;
  final Value<String> occurredTimeZone;
  final Value<String> channel;
  final Value<String?> channelDetail;
  final Value<String> locationKind;
  final Value<String?> placeName;
  final Value<String?> smallestRegionId;
  final Value<double?> latitude;
  final Value<double?> longitude;
  final Value<double?> locationAccuracyMeters;
  final Value<int> reachCount;
  final Value<int> interestLevel;
  final Value<int> rowid;
  const DbContactRevisionsCompanion({
    this.revisionId = const Value.absent(),
    this.contactId = const Value.absent(),
    this.revisionNumber = const Value.absent(),
    this.revisedByAppUserId = const Value.absent(),
    this.revisedAtUtc = const Value.absent(),
    this.reason = const Value.absent(),
    this.occurredAtUtc = const Value.absent(),
    this.occurredTimeZone = const Value.absent(),
    this.channel = const Value.absent(),
    this.channelDetail = const Value.absent(),
    this.locationKind = const Value.absent(),
    this.placeName = const Value.absent(),
    this.smallestRegionId = const Value.absent(),
    this.latitude = const Value.absent(),
    this.longitude = const Value.absent(),
    this.locationAccuracyMeters = const Value.absent(),
    this.reachCount = const Value.absent(),
    this.interestLevel = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DbContactRevisionsCompanion.insert({
    required String revisionId,
    required String contactId,
    required int revisionNumber,
    required String revisedByAppUserId,
    required DateTime revisedAtUtc,
    this.reason = const Value.absent(),
    required DateTime occurredAtUtc,
    required String occurredTimeZone,
    required String channel,
    this.channelDetail = const Value.absent(),
    required String locationKind,
    this.placeName = const Value.absent(),
    this.smallestRegionId = const Value.absent(),
    this.latitude = const Value.absent(),
    this.longitude = const Value.absent(),
    this.locationAccuracyMeters = const Value.absent(),
    required int reachCount,
    required int interestLevel,
    this.rowid = const Value.absent(),
  }) : revisionId = Value(revisionId),
       contactId = Value(contactId),
       revisionNumber = Value(revisionNumber),
       revisedByAppUserId = Value(revisedByAppUserId),
       revisedAtUtc = Value(revisedAtUtc),
       occurredAtUtc = Value(occurredAtUtc),
       occurredTimeZone = Value(occurredTimeZone),
       channel = Value(channel),
       locationKind = Value(locationKind),
       reachCount = Value(reachCount),
       interestLevel = Value(interestLevel);
  static Insertable<DbContactRevision> custom({
    Expression<String>? revisionId,
    Expression<String>? contactId,
    Expression<int>? revisionNumber,
    Expression<String>? revisedByAppUserId,
    Expression<DateTime>? revisedAtUtc,
    Expression<String>? reason,
    Expression<DateTime>? occurredAtUtc,
    Expression<String>? occurredTimeZone,
    Expression<String>? channel,
    Expression<String>? channelDetail,
    Expression<String>? locationKind,
    Expression<String>? placeName,
    Expression<String>? smallestRegionId,
    Expression<double>? latitude,
    Expression<double>? longitude,
    Expression<double>? locationAccuracyMeters,
    Expression<int>? reachCount,
    Expression<int>? interestLevel,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (revisionId != null) 'revision_id': revisionId,
      if (contactId != null) 'contact_id': contactId,
      if (revisionNumber != null) 'revision_number': revisionNumber,
      if (revisedByAppUserId != null)
        'revised_by_app_user_id': revisedByAppUserId,
      if (revisedAtUtc != null) 'revised_at_utc': revisedAtUtc,
      if (reason != null) 'reason': reason,
      if (occurredAtUtc != null) 'occurred_at_utc': occurredAtUtc,
      if (occurredTimeZone != null) 'occurred_time_zone': occurredTimeZone,
      if (channel != null) 'channel': channel,
      if (channelDetail != null) 'channel_detail': channelDetail,
      if (locationKind != null) 'location_kind': locationKind,
      if (placeName != null) 'place_name': placeName,
      if (smallestRegionId != null) 'smallest_region_id': smallestRegionId,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      if (locationAccuracyMeters != null)
        'location_accuracy_meters': locationAccuracyMeters,
      if (reachCount != null) 'reach_count': reachCount,
      if (interestLevel != null) 'interest_level': interestLevel,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DbContactRevisionsCompanion copyWith({
    Value<String>? revisionId,
    Value<String>? contactId,
    Value<int>? revisionNumber,
    Value<String>? revisedByAppUserId,
    Value<DateTime>? revisedAtUtc,
    Value<String?>? reason,
    Value<DateTime>? occurredAtUtc,
    Value<String>? occurredTimeZone,
    Value<String>? channel,
    Value<String?>? channelDetail,
    Value<String>? locationKind,
    Value<String?>? placeName,
    Value<String?>? smallestRegionId,
    Value<double?>? latitude,
    Value<double?>? longitude,
    Value<double?>? locationAccuracyMeters,
    Value<int>? reachCount,
    Value<int>? interestLevel,
    Value<int>? rowid,
  }) {
    return DbContactRevisionsCompanion(
      revisionId: revisionId ?? this.revisionId,
      contactId: contactId ?? this.contactId,
      revisionNumber: revisionNumber ?? this.revisionNumber,
      revisedByAppUserId: revisedByAppUserId ?? this.revisedByAppUserId,
      revisedAtUtc: revisedAtUtc ?? this.revisedAtUtc,
      reason: reason ?? this.reason,
      occurredAtUtc: occurredAtUtc ?? this.occurredAtUtc,
      occurredTimeZone: occurredTimeZone ?? this.occurredTimeZone,
      channel: channel ?? this.channel,
      channelDetail: channelDetail ?? this.channelDetail,
      locationKind: locationKind ?? this.locationKind,
      placeName: placeName ?? this.placeName,
      smallestRegionId: smallestRegionId ?? this.smallestRegionId,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      locationAccuracyMeters:
          locationAccuracyMeters ?? this.locationAccuracyMeters,
      reachCount: reachCount ?? this.reachCount,
      interestLevel: interestLevel ?? this.interestLevel,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (revisionId.present) {
      map['revision_id'] = Variable<String>(revisionId.value);
    }
    if (contactId.present) {
      map['contact_id'] = Variable<String>(contactId.value);
    }
    if (revisionNumber.present) {
      map['revision_number'] = Variable<int>(revisionNumber.value);
    }
    if (revisedByAppUserId.present) {
      map['revised_by_app_user_id'] = Variable<String>(
        revisedByAppUserId.value,
      );
    }
    if (revisedAtUtc.present) {
      map['revised_at_utc'] = Variable<DateTime>(revisedAtUtc.value);
    }
    if (reason.present) {
      map['reason'] = Variable<String>(reason.value);
    }
    if (occurredAtUtc.present) {
      map['occurred_at_utc'] = Variable<DateTime>(occurredAtUtc.value);
    }
    if (occurredTimeZone.present) {
      map['occurred_time_zone'] = Variable<String>(occurredTimeZone.value);
    }
    if (channel.present) {
      map['channel'] = Variable<String>(channel.value);
    }
    if (channelDetail.present) {
      map['channel_detail'] = Variable<String>(channelDetail.value);
    }
    if (locationKind.present) {
      map['location_kind'] = Variable<String>(locationKind.value);
    }
    if (placeName.present) {
      map['place_name'] = Variable<String>(placeName.value);
    }
    if (smallestRegionId.present) {
      map['smallest_region_id'] = Variable<String>(smallestRegionId.value);
    }
    if (latitude.present) {
      map['latitude'] = Variable<double>(latitude.value);
    }
    if (longitude.present) {
      map['longitude'] = Variable<double>(longitude.value);
    }
    if (locationAccuracyMeters.present) {
      map['location_accuracy_meters'] = Variable<double>(
        locationAccuracyMeters.value,
      );
    }
    if (reachCount.present) {
      map['reach_count'] = Variable<int>(reachCount.value);
    }
    if (interestLevel.present) {
      map['interest_level'] = Variable<int>(interestLevel.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DbContactRevisionsCompanion(')
          ..write('revisionId: $revisionId, ')
          ..write('contactId: $contactId, ')
          ..write('revisionNumber: $revisionNumber, ')
          ..write('revisedByAppUserId: $revisedByAppUserId, ')
          ..write('revisedAtUtc: $revisedAtUtc, ')
          ..write('reason: $reason, ')
          ..write('occurredAtUtc: $occurredAtUtc, ')
          ..write('occurredTimeZone: $occurredTimeZone, ')
          ..write('channel: $channel, ')
          ..write('channelDetail: $channelDetail, ')
          ..write('locationKind: $locationKind, ')
          ..write('placeName: $placeName, ')
          ..write('smallestRegionId: $smallestRegionId, ')
          ..write('latitude: $latitude, ')
          ..write('longitude: $longitude, ')
          ..write('locationAccuracyMeters: $locationAccuracyMeters, ')
          ..write('reachCount: $reachCount, ')
          ..write('interestLevel: $interestLevel, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $DbContactAnswersTable extends DbContactAnswers
    with TableInfo<$DbContactAnswersTable, DbContactAnswer> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DbContactAnswersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _contactIdMeta = const VerificationMeta(
    'contactId',
  );
  @override
  late final GeneratedColumn<String> contactId = GeneratedColumn<String>(
    'contact_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES db_contact_records (contact_id)',
    ),
  );
  static const VerificationMeta _revisionNumberMeta = const VerificationMeta(
    'revisionNumber',
  );
  @override
  late final GeneratedColumn<int> revisionNumber = GeneratedColumn<int>(
    'revision_number',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _questionIdMeta = const VerificationMeta(
    'questionId',
  );
  @override
  late final GeneratedColumn<String> questionId = GeneratedColumn<String>(
    'question_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _answerStateMeta = const VerificationMeta(
    'answerState',
  );
  @override
  late final GeneratedColumn<String> answerState = GeneratedColumn<String>(
    'answer_state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _answerTypeMeta = const VerificationMeta(
    'answerType',
  );
  @override
  late final GeneratedColumn<String> answerType = GeneratedColumn<String>(
    'answer_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _booleanValueMeta = const VerificationMeta(
    'booleanValue',
  );
  @override
  late final GeneratedColumn<bool> booleanValue = GeneratedColumn<bool>(
    'boolean_value',
    aliasedName,
    true,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("boolean_value" IN (0, 1))',
    ),
  );
  @override
  List<GeneratedColumn> get $columns => [
    contactId,
    revisionNumber,
    questionId,
    answerState,
    answerType,
    booleanValue,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'db_contact_answers';
  @override
  VerificationContext validateIntegrity(
    Insertable<DbContactAnswer> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('contact_id')) {
      context.handle(
        _contactIdMeta,
        contactId.isAcceptableOrUnknown(data['contact_id']!, _contactIdMeta),
      );
    } else if (isInserting) {
      context.missing(_contactIdMeta);
    }
    if (data.containsKey('revision_number')) {
      context.handle(
        _revisionNumberMeta,
        revisionNumber.isAcceptableOrUnknown(
          data['revision_number']!,
          _revisionNumberMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_revisionNumberMeta);
    }
    if (data.containsKey('question_id')) {
      context.handle(
        _questionIdMeta,
        questionId.isAcceptableOrUnknown(data['question_id']!, _questionIdMeta),
      );
    } else if (isInserting) {
      context.missing(_questionIdMeta);
    }
    if (data.containsKey('answer_state')) {
      context.handle(
        _answerStateMeta,
        answerState.isAcceptableOrUnknown(
          data['answer_state']!,
          _answerStateMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_answerStateMeta);
    }
    if (data.containsKey('answer_type')) {
      context.handle(
        _answerTypeMeta,
        answerType.isAcceptableOrUnknown(data['answer_type']!, _answerTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_answerTypeMeta);
    }
    if (data.containsKey('boolean_value')) {
      context.handle(
        _booleanValueMeta,
        booleanValue.isAcceptableOrUnknown(
          data['boolean_value']!,
          _booleanValueMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {
    contactId,
    revisionNumber,
    questionId,
  };
  @override
  DbContactAnswer map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DbContactAnswer(
      contactId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}contact_id'],
      )!,
      revisionNumber: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}revision_number'],
      )!,
      questionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}question_id'],
      )!,
      answerState: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}answer_state'],
      )!,
      answerType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}answer_type'],
      )!,
      booleanValue: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}boolean_value'],
      ),
    );
  }

  @override
  $DbContactAnswersTable createAlias(String alias) {
    return $DbContactAnswersTable(attachedDatabase, alias);
  }
}

class DbContactAnswer extends DataClass implements Insertable<DbContactAnswer> {
  final String contactId;
  final int revisionNumber;
  final String questionId;
  final String answerState;
  final String answerType;
  final bool? booleanValue;
  const DbContactAnswer({
    required this.contactId,
    required this.revisionNumber,
    required this.questionId,
    required this.answerState,
    required this.answerType,
    this.booleanValue,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['contact_id'] = Variable<String>(contactId);
    map['revision_number'] = Variable<int>(revisionNumber);
    map['question_id'] = Variable<String>(questionId);
    map['answer_state'] = Variable<String>(answerState);
    map['answer_type'] = Variable<String>(answerType);
    if (!nullToAbsent || booleanValue != null) {
      map['boolean_value'] = Variable<bool>(booleanValue);
    }
    return map;
  }

  DbContactAnswersCompanion toCompanion(bool nullToAbsent) {
    return DbContactAnswersCompanion(
      contactId: Value(contactId),
      revisionNumber: Value(revisionNumber),
      questionId: Value(questionId),
      answerState: Value(answerState),
      answerType: Value(answerType),
      booleanValue: booleanValue == null && nullToAbsent
          ? const Value.absent()
          : Value(booleanValue),
    );
  }

  factory DbContactAnswer.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DbContactAnswer(
      contactId: serializer.fromJson<String>(json['contactId']),
      revisionNumber: serializer.fromJson<int>(json['revisionNumber']),
      questionId: serializer.fromJson<String>(json['questionId']),
      answerState: serializer.fromJson<String>(json['answerState']),
      answerType: serializer.fromJson<String>(json['answerType']),
      booleanValue: serializer.fromJson<bool?>(json['booleanValue']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'contactId': serializer.toJson<String>(contactId),
      'revisionNumber': serializer.toJson<int>(revisionNumber),
      'questionId': serializer.toJson<String>(questionId),
      'answerState': serializer.toJson<String>(answerState),
      'answerType': serializer.toJson<String>(answerType),
      'booleanValue': serializer.toJson<bool?>(booleanValue),
    };
  }

  DbContactAnswer copyWith({
    String? contactId,
    int? revisionNumber,
    String? questionId,
    String? answerState,
    String? answerType,
    Value<bool?> booleanValue = const Value.absent(),
  }) => DbContactAnswer(
    contactId: contactId ?? this.contactId,
    revisionNumber: revisionNumber ?? this.revisionNumber,
    questionId: questionId ?? this.questionId,
    answerState: answerState ?? this.answerState,
    answerType: answerType ?? this.answerType,
    booleanValue: booleanValue.present ? booleanValue.value : this.booleanValue,
  );
  DbContactAnswer copyWithCompanion(DbContactAnswersCompanion data) {
    return DbContactAnswer(
      contactId: data.contactId.present ? data.contactId.value : this.contactId,
      revisionNumber: data.revisionNumber.present
          ? data.revisionNumber.value
          : this.revisionNumber,
      questionId: data.questionId.present
          ? data.questionId.value
          : this.questionId,
      answerState: data.answerState.present
          ? data.answerState.value
          : this.answerState,
      answerType: data.answerType.present
          ? data.answerType.value
          : this.answerType,
      booleanValue: data.booleanValue.present
          ? data.booleanValue.value
          : this.booleanValue,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DbContactAnswer(')
          ..write('contactId: $contactId, ')
          ..write('revisionNumber: $revisionNumber, ')
          ..write('questionId: $questionId, ')
          ..write('answerState: $answerState, ')
          ..write('answerType: $answerType, ')
          ..write('booleanValue: $booleanValue')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    contactId,
    revisionNumber,
    questionId,
    answerState,
    answerType,
    booleanValue,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DbContactAnswer &&
          other.contactId == this.contactId &&
          other.revisionNumber == this.revisionNumber &&
          other.questionId == this.questionId &&
          other.answerState == this.answerState &&
          other.answerType == this.answerType &&
          other.booleanValue == this.booleanValue);
}

class DbContactAnswersCompanion extends UpdateCompanion<DbContactAnswer> {
  final Value<String> contactId;
  final Value<int> revisionNumber;
  final Value<String> questionId;
  final Value<String> answerState;
  final Value<String> answerType;
  final Value<bool?> booleanValue;
  final Value<int> rowid;
  const DbContactAnswersCompanion({
    this.contactId = const Value.absent(),
    this.revisionNumber = const Value.absent(),
    this.questionId = const Value.absent(),
    this.answerState = const Value.absent(),
    this.answerType = const Value.absent(),
    this.booleanValue = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DbContactAnswersCompanion.insert({
    required String contactId,
    required int revisionNumber,
    required String questionId,
    required String answerState,
    required String answerType,
    this.booleanValue = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : contactId = Value(contactId),
       revisionNumber = Value(revisionNumber),
       questionId = Value(questionId),
       answerState = Value(answerState),
       answerType = Value(answerType);
  static Insertable<DbContactAnswer> custom({
    Expression<String>? contactId,
    Expression<int>? revisionNumber,
    Expression<String>? questionId,
    Expression<String>? answerState,
    Expression<String>? answerType,
    Expression<bool>? booleanValue,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (contactId != null) 'contact_id': contactId,
      if (revisionNumber != null) 'revision_number': revisionNumber,
      if (questionId != null) 'question_id': questionId,
      if (answerState != null) 'answer_state': answerState,
      if (answerType != null) 'answer_type': answerType,
      if (booleanValue != null) 'boolean_value': booleanValue,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DbContactAnswersCompanion copyWith({
    Value<String>? contactId,
    Value<int>? revisionNumber,
    Value<String>? questionId,
    Value<String>? answerState,
    Value<String>? answerType,
    Value<bool?>? booleanValue,
    Value<int>? rowid,
  }) {
    return DbContactAnswersCompanion(
      contactId: contactId ?? this.contactId,
      revisionNumber: revisionNumber ?? this.revisionNumber,
      questionId: questionId ?? this.questionId,
      answerState: answerState ?? this.answerState,
      answerType: answerType ?? this.answerType,
      booleanValue: booleanValue ?? this.booleanValue,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (contactId.present) {
      map['contact_id'] = Variable<String>(contactId.value);
    }
    if (revisionNumber.present) {
      map['revision_number'] = Variable<int>(revisionNumber.value);
    }
    if (questionId.present) {
      map['question_id'] = Variable<String>(questionId.value);
    }
    if (answerState.present) {
      map['answer_state'] = Variable<String>(answerState.value);
    }
    if (answerType.present) {
      map['answer_type'] = Variable<String>(answerType.value);
    }
    if (booleanValue.present) {
      map['boolean_value'] = Variable<bool>(booleanValue.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DbContactAnswersCompanion(')
          ..write('contactId: $contactId, ')
          ..write('revisionNumber: $revisionNumber, ')
          ..write('questionId: $questionId, ')
          ..write('answerState: $answerState, ')
          ..write('answerType: $answerType, ')
          ..write('booleanValue: $booleanValue, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $DbContactDraftsTable extends DbContactDrafts
    with TableInfo<$DbContactDraftsTable, DbContactDraft> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DbContactDraftsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _draftIdMeta = const VerificationMeta(
    'draftId',
  );
  @override
  late final GeneratedColumn<String> draftId = GeneratedColumn<String>(
    'draft_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _appUserIdMeta = const VerificationMeta(
    'appUserId',
  );
  @override
  late final GeneratedColumn<String> appUserId = GeneratedColumn<String>(
    'app_user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _workspaceIdMeta = const VerificationMeta(
    'workspaceId',
  );
  @override
  late final GeneratedColumn<String> workspaceId = GeneratedColumn<String>(
    'workspace_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _projectIdMeta = const VerificationMeta(
    'projectId',
  );
  @override
  late final GeneratedColumn<String> projectId = GeneratedColumn<String>(
    'project_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _questionnaireVersionIdMeta =
      const VerificationMeta('questionnaireVersionId');
  @override
  late final GeneratedColumn<String> questionnaireVersionId =
      GeneratedColumn<String>(
        'questionnaire_version_id',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _createdAtUtcMeta = const VerificationMeta(
    'createdAtUtc',
  );
  @override
  late final GeneratedColumn<DateTime> createdAtUtc = GeneratedColumn<DateTime>(
    'created_at_utc',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtUtcMeta = const VerificationMeta(
    'updatedAtUtc',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAtUtc = GeneratedColumn<DateTime>(
    'updated_at_utc',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _occurredAtUtcMeta = const VerificationMeta(
    'occurredAtUtc',
  );
  @override
  late final GeneratedColumn<DateTime> occurredAtUtc =
      GeneratedColumn<DateTime>(
        'occurred_at_utc',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _occurredTimeZoneMeta = const VerificationMeta(
    'occurredTimeZone',
  );
  @override
  late final GeneratedColumn<String> occurredTimeZone = GeneratedColumn<String>(
    'occurred_time_zone',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _channelMeta = const VerificationMeta(
    'channel',
  );
  @override
  late final GeneratedColumn<String> channel = GeneratedColumn<String>(
    'channel',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _channelDetailMeta = const VerificationMeta(
    'channelDetail',
  );
  @override
  late final GeneratedColumn<String> channelDetail = GeneratedColumn<String>(
    'channel_detail',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _locationKindMeta = const VerificationMeta(
    'locationKind',
  );
  @override
  late final GeneratedColumn<String> locationKind = GeneratedColumn<String>(
    'location_kind',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _placeNameMeta = const VerificationMeta(
    'placeName',
  );
  @override
  late final GeneratedColumn<String> placeName = GeneratedColumn<String>(
    'place_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _smallestRegionIdMeta = const VerificationMeta(
    'smallestRegionId',
  );
  @override
  late final GeneratedColumn<String> smallestRegionId = GeneratedColumn<String>(
    'smallest_region_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _latitudeMeta = const VerificationMeta(
    'latitude',
  );
  @override
  late final GeneratedColumn<double> latitude = GeneratedColumn<double>(
    'latitude',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _longitudeMeta = const VerificationMeta(
    'longitude',
  );
  @override
  late final GeneratedColumn<double> longitude = GeneratedColumn<double>(
    'longitude',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _locationAccuracyMetersMeta =
      const VerificationMeta('locationAccuracyMeters');
  @override
  late final GeneratedColumn<double> locationAccuracyMeters =
      GeneratedColumn<double>(
        'location_accuracy_meters',
        aliasedName,
        true,
        type: DriftSqlType.double,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _reachCountMeta = const VerificationMeta(
    'reachCount',
  );
  @override
  late final GeneratedColumn<int> reachCount = GeneratedColumn<int>(
    'reach_count',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _interestLevelMeta = const VerificationMeta(
    'interestLevel',
  );
  @override
  late final GeneratedColumn<int> interestLevel = GeneratedColumn<int>(
    'interest_level',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _syncModeMeta = const VerificationMeta(
    'syncMode',
  );
  @override
  late final GeneratedColumn<String> syncMode = GeneratedColumn<String>(
    'sync_mode',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('account_private'),
  );
  static const VerificationMeta _abandonedAtUtcMeta = const VerificationMeta(
    'abandonedAtUtc',
  );
  @override
  late final GeneratedColumn<DateTime> abandonedAtUtc =
      GeneratedColumn<DateTime>(
        'abandoned_at_utc',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _undoUntilUtcMeta = const VerificationMeta(
    'undoUntilUtc',
  );
  @override
  late final GeneratedColumn<DateTime> undoUntilUtc = GeneratedColumn<DateTime>(
    'undo_until_utc',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    draftId,
    appUserId,
    workspaceId,
    projectId,
    questionnaireVersionId,
    createdAtUtc,
    updatedAtUtc,
    occurredAtUtc,
    occurredTimeZone,
    channel,
    channelDetail,
    locationKind,
    placeName,
    smallestRegionId,
    latitude,
    longitude,
    locationAccuracyMeters,
    reachCount,
    interestLevel,
    syncMode,
    abandonedAtUtc,
    undoUntilUtc,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'db_contact_drafts';
  @override
  VerificationContext validateIntegrity(
    Insertable<DbContactDraft> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('draft_id')) {
      context.handle(
        _draftIdMeta,
        draftId.isAcceptableOrUnknown(data['draft_id']!, _draftIdMeta),
      );
    } else if (isInserting) {
      context.missing(_draftIdMeta);
    }
    if (data.containsKey('app_user_id')) {
      context.handle(
        _appUserIdMeta,
        appUserId.isAcceptableOrUnknown(data['app_user_id']!, _appUserIdMeta),
      );
    } else if (isInserting) {
      context.missing(_appUserIdMeta);
    }
    if (data.containsKey('workspace_id')) {
      context.handle(
        _workspaceIdMeta,
        workspaceId.isAcceptableOrUnknown(
          data['workspace_id']!,
          _workspaceIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_workspaceIdMeta);
    }
    if (data.containsKey('project_id')) {
      context.handle(
        _projectIdMeta,
        projectId.isAcceptableOrUnknown(data['project_id']!, _projectIdMeta),
      );
    } else if (isInserting) {
      context.missing(_projectIdMeta);
    }
    if (data.containsKey('questionnaire_version_id')) {
      context.handle(
        _questionnaireVersionIdMeta,
        questionnaireVersionId.isAcceptableOrUnknown(
          data['questionnaire_version_id']!,
          _questionnaireVersionIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_questionnaireVersionIdMeta);
    }
    if (data.containsKey('created_at_utc')) {
      context.handle(
        _createdAtUtcMeta,
        createdAtUtc.isAcceptableOrUnknown(
          data['created_at_utc']!,
          _createdAtUtcMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_createdAtUtcMeta);
    }
    if (data.containsKey('updated_at_utc')) {
      context.handle(
        _updatedAtUtcMeta,
        updatedAtUtc.isAcceptableOrUnknown(
          data['updated_at_utc']!,
          _updatedAtUtcMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_updatedAtUtcMeta);
    }
    if (data.containsKey('occurred_at_utc')) {
      context.handle(
        _occurredAtUtcMeta,
        occurredAtUtc.isAcceptableOrUnknown(
          data['occurred_at_utc']!,
          _occurredAtUtcMeta,
        ),
      );
    }
    if (data.containsKey('occurred_time_zone')) {
      context.handle(
        _occurredTimeZoneMeta,
        occurredTimeZone.isAcceptableOrUnknown(
          data['occurred_time_zone']!,
          _occurredTimeZoneMeta,
        ),
      );
    }
    if (data.containsKey('channel')) {
      context.handle(
        _channelMeta,
        channel.isAcceptableOrUnknown(data['channel']!, _channelMeta),
      );
    }
    if (data.containsKey('channel_detail')) {
      context.handle(
        _channelDetailMeta,
        channelDetail.isAcceptableOrUnknown(
          data['channel_detail']!,
          _channelDetailMeta,
        ),
      );
    }
    if (data.containsKey('location_kind')) {
      context.handle(
        _locationKindMeta,
        locationKind.isAcceptableOrUnknown(
          data['location_kind']!,
          _locationKindMeta,
        ),
      );
    }
    if (data.containsKey('place_name')) {
      context.handle(
        _placeNameMeta,
        placeName.isAcceptableOrUnknown(data['place_name']!, _placeNameMeta),
      );
    }
    if (data.containsKey('smallest_region_id')) {
      context.handle(
        _smallestRegionIdMeta,
        smallestRegionId.isAcceptableOrUnknown(
          data['smallest_region_id']!,
          _smallestRegionIdMeta,
        ),
      );
    }
    if (data.containsKey('latitude')) {
      context.handle(
        _latitudeMeta,
        latitude.isAcceptableOrUnknown(data['latitude']!, _latitudeMeta),
      );
    }
    if (data.containsKey('longitude')) {
      context.handle(
        _longitudeMeta,
        longitude.isAcceptableOrUnknown(data['longitude']!, _longitudeMeta),
      );
    }
    if (data.containsKey('location_accuracy_meters')) {
      context.handle(
        _locationAccuracyMetersMeta,
        locationAccuracyMeters.isAcceptableOrUnknown(
          data['location_accuracy_meters']!,
          _locationAccuracyMetersMeta,
        ),
      );
    }
    if (data.containsKey('reach_count')) {
      context.handle(
        _reachCountMeta,
        reachCount.isAcceptableOrUnknown(data['reach_count']!, _reachCountMeta),
      );
    }
    if (data.containsKey('interest_level')) {
      context.handle(
        _interestLevelMeta,
        interestLevel.isAcceptableOrUnknown(
          data['interest_level']!,
          _interestLevelMeta,
        ),
      );
    }
    if (data.containsKey('sync_mode')) {
      context.handle(
        _syncModeMeta,
        syncMode.isAcceptableOrUnknown(data['sync_mode']!, _syncModeMeta),
      );
    }
    if (data.containsKey('abandoned_at_utc')) {
      context.handle(
        _abandonedAtUtcMeta,
        abandonedAtUtc.isAcceptableOrUnknown(
          data['abandoned_at_utc']!,
          _abandonedAtUtcMeta,
        ),
      );
    }
    if (data.containsKey('undo_until_utc')) {
      context.handle(
        _undoUntilUtcMeta,
        undoUntilUtc.isAcceptableOrUnknown(
          data['undo_until_utc']!,
          _undoUntilUtcMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {draftId};
  @override
  DbContactDraft map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DbContactDraft(
      draftId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}draft_id'],
      )!,
      appUserId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}app_user_id'],
      )!,
      workspaceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}workspace_id'],
      )!,
      projectId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}project_id'],
      )!,
      questionnaireVersionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}questionnaire_version_id'],
      )!,
      createdAtUtc: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at_utc'],
      )!,
      updatedAtUtc: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at_utc'],
      )!,
      occurredAtUtc: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}occurred_at_utc'],
      ),
      occurredTimeZone: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}occurred_time_zone'],
      ),
      channel: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}channel'],
      ),
      channelDetail: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}channel_detail'],
      ),
      locationKind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}location_kind'],
      ),
      placeName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}place_name'],
      ),
      smallestRegionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}smallest_region_id'],
      ),
      latitude: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}latitude'],
      ),
      longitude: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}longitude'],
      ),
      locationAccuracyMeters: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}location_accuracy_meters'],
      ),
      reachCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}reach_count'],
      ),
      interestLevel: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}interest_level'],
      ),
      syncMode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sync_mode'],
      )!,
      abandonedAtUtc: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}abandoned_at_utc'],
      ),
      undoUntilUtc: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}undo_until_utc'],
      ),
    );
  }

  @override
  $DbContactDraftsTable createAlias(String alias) {
    return $DbContactDraftsTable(attachedDatabase, alias);
  }
}

class DbContactDraft extends DataClass implements Insertable<DbContactDraft> {
  final String draftId;
  final String appUserId;
  final String workspaceId;
  final String projectId;
  final String questionnaireVersionId;
  final DateTime createdAtUtc;
  final DateTime updatedAtUtc;
  final DateTime? occurredAtUtc;
  final String? occurredTimeZone;
  final String? channel;
  final String? channelDetail;
  final String? locationKind;
  final String? placeName;
  final String? smallestRegionId;
  final double? latitude;
  final double? longitude;
  final double? locationAccuracyMeters;
  final int? reachCount;
  final int? interestLevel;
  final String syncMode;
  final DateTime? abandonedAtUtc;
  final DateTime? undoUntilUtc;
  const DbContactDraft({
    required this.draftId,
    required this.appUserId,
    required this.workspaceId,
    required this.projectId,
    required this.questionnaireVersionId,
    required this.createdAtUtc,
    required this.updatedAtUtc,
    this.occurredAtUtc,
    this.occurredTimeZone,
    this.channel,
    this.channelDetail,
    this.locationKind,
    this.placeName,
    this.smallestRegionId,
    this.latitude,
    this.longitude,
    this.locationAccuracyMeters,
    this.reachCount,
    this.interestLevel,
    required this.syncMode,
    this.abandonedAtUtc,
    this.undoUntilUtc,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['draft_id'] = Variable<String>(draftId);
    map['app_user_id'] = Variable<String>(appUserId);
    map['workspace_id'] = Variable<String>(workspaceId);
    map['project_id'] = Variable<String>(projectId);
    map['questionnaire_version_id'] = Variable<String>(questionnaireVersionId);
    map['created_at_utc'] = Variable<DateTime>(createdAtUtc);
    map['updated_at_utc'] = Variable<DateTime>(updatedAtUtc);
    if (!nullToAbsent || occurredAtUtc != null) {
      map['occurred_at_utc'] = Variable<DateTime>(occurredAtUtc);
    }
    if (!nullToAbsent || occurredTimeZone != null) {
      map['occurred_time_zone'] = Variable<String>(occurredTimeZone);
    }
    if (!nullToAbsent || channel != null) {
      map['channel'] = Variable<String>(channel);
    }
    if (!nullToAbsent || channelDetail != null) {
      map['channel_detail'] = Variable<String>(channelDetail);
    }
    if (!nullToAbsent || locationKind != null) {
      map['location_kind'] = Variable<String>(locationKind);
    }
    if (!nullToAbsent || placeName != null) {
      map['place_name'] = Variable<String>(placeName);
    }
    if (!nullToAbsent || smallestRegionId != null) {
      map['smallest_region_id'] = Variable<String>(smallestRegionId);
    }
    if (!nullToAbsent || latitude != null) {
      map['latitude'] = Variable<double>(latitude);
    }
    if (!nullToAbsent || longitude != null) {
      map['longitude'] = Variable<double>(longitude);
    }
    if (!nullToAbsent || locationAccuracyMeters != null) {
      map['location_accuracy_meters'] = Variable<double>(
        locationAccuracyMeters,
      );
    }
    if (!nullToAbsent || reachCount != null) {
      map['reach_count'] = Variable<int>(reachCount);
    }
    if (!nullToAbsent || interestLevel != null) {
      map['interest_level'] = Variable<int>(interestLevel);
    }
    map['sync_mode'] = Variable<String>(syncMode);
    if (!nullToAbsent || abandonedAtUtc != null) {
      map['abandoned_at_utc'] = Variable<DateTime>(abandonedAtUtc);
    }
    if (!nullToAbsent || undoUntilUtc != null) {
      map['undo_until_utc'] = Variable<DateTime>(undoUntilUtc);
    }
    return map;
  }

  DbContactDraftsCompanion toCompanion(bool nullToAbsent) {
    return DbContactDraftsCompanion(
      draftId: Value(draftId),
      appUserId: Value(appUserId),
      workspaceId: Value(workspaceId),
      projectId: Value(projectId),
      questionnaireVersionId: Value(questionnaireVersionId),
      createdAtUtc: Value(createdAtUtc),
      updatedAtUtc: Value(updatedAtUtc),
      occurredAtUtc: occurredAtUtc == null && nullToAbsent
          ? const Value.absent()
          : Value(occurredAtUtc),
      occurredTimeZone: occurredTimeZone == null && nullToAbsent
          ? const Value.absent()
          : Value(occurredTimeZone),
      channel: channel == null && nullToAbsent
          ? const Value.absent()
          : Value(channel),
      channelDetail: channelDetail == null && nullToAbsent
          ? const Value.absent()
          : Value(channelDetail),
      locationKind: locationKind == null && nullToAbsent
          ? const Value.absent()
          : Value(locationKind),
      placeName: placeName == null && nullToAbsent
          ? const Value.absent()
          : Value(placeName),
      smallestRegionId: smallestRegionId == null && nullToAbsent
          ? const Value.absent()
          : Value(smallestRegionId),
      latitude: latitude == null && nullToAbsent
          ? const Value.absent()
          : Value(latitude),
      longitude: longitude == null && nullToAbsent
          ? const Value.absent()
          : Value(longitude),
      locationAccuracyMeters: locationAccuracyMeters == null && nullToAbsent
          ? const Value.absent()
          : Value(locationAccuracyMeters),
      reachCount: reachCount == null && nullToAbsent
          ? const Value.absent()
          : Value(reachCount),
      interestLevel: interestLevel == null && nullToAbsent
          ? const Value.absent()
          : Value(interestLevel),
      syncMode: Value(syncMode),
      abandonedAtUtc: abandonedAtUtc == null && nullToAbsent
          ? const Value.absent()
          : Value(abandonedAtUtc),
      undoUntilUtc: undoUntilUtc == null && nullToAbsent
          ? const Value.absent()
          : Value(undoUntilUtc),
    );
  }

  factory DbContactDraft.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DbContactDraft(
      draftId: serializer.fromJson<String>(json['draftId']),
      appUserId: serializer.fromJson<String>(json['appUserId']),
      workspaceId: serializer.fromJson<String>(json['workspaceId']),
      projectId: serializer.fromJson<String>(json['projectId']),
      questionnaireVersionId: serializer.fromJson<String>(
        json['questionnaireVersionId'],
      ),
      createdAtUtc: serializer.fromJson<DateTime>(json['createdAtUtc']),
      updatedAtUtc: serializer.fromJson<DateTime>(json['updatedAtUtc']),
      occurredAtUtc: serializer.fromJson<DateTime?>(json['occurredAtUtc']),
      occurredTimeZone: serializer.fromJson<String?>(json['occurredTimeZone']),
      channel: serializer.fromJson<String?>(json['channel']),
      channelDetail: serializer.fromJson<String?>(json['channelDetail']),
      locationKind: serializer.fromJson<String?>(json['locationKind']),
      placeName: serializer.fromJson<String?>(json['placeName']),
      smallestRegionId: serializer.fromJson<String?>(json['smallestRegionId']),
      latitude: serializer.fromJson<double?>(json['latitude']),
      longitude: serializer.fromJson<double?>(json['longitude']),
      locationAccuracyMeters: serializer.fromJson<double?>(
        json['locationAccuracyMeters'],
      ),
      reachCount: serializer.fromJson<int?>(json['reachCount']),
      interestLevel: serializer.fromJson<int?>(json['interestLevel']),
      syncMode: serializer.fromJson<String>(json['syncMode']),
      abandonedAtUtc: serializer.fromJson<DateTime?>(json['abandonedAtUtc']),
      undoUntilUtc: serializer.fromJson<DateTime?>(json['undoUntilUtc']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'draftId': serializer.toJson<String>(draftId),
      'appUserId': serializer.toJson<String>(appUserId),
      'workspaceId': serializer.toJson<String>(workspaceId),
      'projectId': serializer.toJson<String>(projectId),
      'questionnaireVersionId': serializer.toJson<String>(
        questionnaireVersionId,
      ),
      'createdAtUtc': serializer.toJson<DateTime>(createdAtUtc),
      'updatedAtUtc': serializer.toJson<DateTime>(updatedAtUtc),
      'occurredAtUtc': serializer.toJson<DateTime?>(occurredAtUtc),
      'occurredTimeZone': serializer.toJson<String?>(occurredTimeZone),
      'channel': serializer.toJson<String?>(channel),
      'channelDetail': serializer.toJson<String?>(channelDetail),
      'locationKind': serializer.toJson<String?>(locationKind),
      'placeName': serializer.toJson<String?>(placeName),
      'smallestRegionId': serializer.toJson<String?>(smallestRegionId),
      'latitude': serializer.toJson<double?>(latitude),
      'longitude': serializer.toJson<double?>(longitude),
      'locationAccuracyMeters': serializer.toJson<double?>(
        locationAccuracyMeters,
      ),
      'reachCount': serializer.toJson<int?>(reachCount),
      'interestLevel': serializer.toJson<int?>(interestLevel),
      'syncMode': serializer.toJson<String>(syncMode),
      'abandonedAtUtc': serializer.toJson<DateTime?>(abandonedAtUtc),
      'undoUntilUtc': serializer.toJson<DateTime?>(undoUntilUtc),
    };
  }

  DbContactDraft copyWith({
    String? draftId,
    String? appUserId,
    String? workspaceId,
    String? projectId,
    String? questionnaireVersionId,
    DateTime? createdAtUtc,
    DateTime? updatedAtUtc,
    Value<DateTime?> occurredAtUtc = const Value.absent(),
    Value<String?> occurredTimeZone = const Value.absent(),
    Value<String?> channel = const Value.absent(),
    Value<String?> channelDetail = const Value.absent(),
    Value<String?> locationKind = const Value.absent(),
    Value<String?> placeName = const Value.absent(),
    Value<String?> smallestRegionId = const Value.absent(),
    Value<double?> latitude = const Value.absent(),
    Value<double?> longitude = const Value.absent(),
    Value<double?> locationAccuracyMeters = const Value.absent(),
    Value<int?> reachCount = const Value.absent(),
    Value<int?> interestLevel = const Value.absent(),
    String? syncMode,
    Value<DateTime?> abandonedAtUtc = const Value.absent(),
    Value<DateTime?> undoUntilUtc = const Value.absent(),
  }) => DbContactDraft(
    draftId: draftId ?? this.draftId,
    appUserId: appUserId ?? this.appUserId,
    workspaceId: workspaceId ?? this.workspaceId,
    projectId: projectId ?? this.projectId,
    questionnaireVersionId:
        questionnaireVersionId ?? this.questionnaireVersionId,
    createdAtUtc: createdAtUtc ?? this.createdAtUtc,
    updatedAtUtc: updatedAtUtc ?? this.updatedAtUtc,
    occurredAtUtc: occurredAtUtc.present
        ? occurredAtUtc.value
        : this.occurredAtUtc,
    occurredTimeZone: occurredTimeZone.present
        ? occurredTimeZone.value
        : this.occurredTimeZone,
    channel: channel.present ? channel.value : this.channel,
    channelDetail: channelDetail.present
        ? channelDetail.value
        : this.channelDetail,
    locationKind: locationKind.present ? locationKind.value : this.locationKind,
    placeName: placeName.present ? placeName.value : this.placeName,
    smallestRegionId: smallestRegionId.present
        ? smallestRegionId.value
        : this.smallestRegionId,
    latitude: latitude.present ? latitude.value : this.latitude,
    longitude: longitude.present ? longitude.value : this.longitude,
    locationAccuracyMeters: locationAccuracyMeters.present
        ? locationAccuracyMeters.value
        : this.locationAccuracyMeters,
    reachCount: reachCount.present ? reachCount.value : this.reachCount,
    interestLevel: interestLevel.present
        ? interestLevel.value
        : this.interestLevel,
    syncMode: syncMode ?? this.syncMode,
    abandonedAtUtc: abandonedAtUtc.present
        ? abandonedAtUtc.value
        : this.abandonedAtUtc,
    undoUntilUtc: undoUntilUtc.present ? undoUntilUtc.value : this.undoUntilUtc,
  );
  DbContactDraft copyWithCompanion(DbContactDraftsCompanion data) {
    return DbContactDraft(
      draftId: data.draftId.present ? data.draftId.value : this.draftId,
      appUserId: data.appUserId.present ? data.appUserId.value : this.appUserId,
      workspaceId: data.workspaceId.present
          ? data.workspaceId.value
          : this.workspaceId,
      projectId: data.projectId.present ? data.projectId.value : this.projectId,
      questionnaireVersionId: data.questionnaireVersionId.present
          ? data.questionnaireVersionId.value
          : this.questionnaireVersionId,
      createdAtUtc: data.createdAtUtc.present
          ? data.createdAtUtc.value
          : this.createdAtUtc,
      updatedAtUtc: data.updatedAtUtc.present
          ? data.updatedAtUtc.value
          : this.updatedAtUtc,
      occurredAtUtc: data.occurredAtUtc.present
          ? data.occurredAtUtc.value
          : this.occurredAtUtc,
      occurredTimeZone: data.occurredTimeZone.present
          ? data.occurredTimeZone.value
          : this.occurredTimeZone,
      channel: data.channel.present ? data.channel.value : this.channel,
      channelDetail: data.channelDetail.present
          ? data.channelDetail.value
          : this.channelDetail,
      locationKind: data.locationKind.present
          ? data.locationKind.value
          : this.locationKind,
      placeName: data.placeName.present ? data.placeName.value : this.placeName,
      smallestRegionId: data.smallestRegionId.present
          ? data.smallestRegionId.value
          : this.smallestRegionId,
      latitude: data.latitude.present ? data.latitude.value : this.latitude,
      longitude: data.longitude.present ? data.longitude.value : this.longitude,
      locationAccuracyMeters: data.locationAccuracyMeters.present
          ? data.locationAccuracyMeters.value
          : this.locationAccuracyMeters,
      reachCount: data.reachCount.present
          ? data.reachCount.value
          : this.reachCount,
      interestLevel: data.interestLevel.present
          ? data.interestLevel.value
          : this.interestLevel,
      syncMode: data.syncMode.present ? data.syncMode.value : this.syncMode,
      abandonedAtUtc: data.abandonedAtUtc.present
          ? data.abandonedAtUtc.value
          : this.abandonedAtUtc,
      undoUntilUtc: data.undoUntilUtc.present
          ? data.undoUntilUtc.value
          : this.undoUntilUtc,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DbContactDraft(')
          ..write('draftId: $draftId, ')
          ..write('appUserId: $appUserId, ')
          ..write('workspaceId: $workspaceId, ')
          ..write('projectId: $projectId, ')
          ..write('questionnaireVersionId: $questionnaireVersionId, ')
          ..write('createdAtUtc: $createdAtUtc, ')
          ..write('updatedAtUtc: $updatedAtUtc, ')
          ..write('occurredAtUtc: $occurredAtUtc, ')
          ..write('occurredTimeZone: $occurredTimeZone, ')
          ..write('channel: $channel, ')
          ..write('channelDetail: $channelDetail, ')
          ..write('locationKind: $locationKind, ')
          ..write('placeName: $placeName, ')
          ..write('smallestRegionId: $smallestRegionId, ')
          ..write('latitude: $latitude, ')
          ..write('longitude: $longitude, ')
          ..write('locationAccuracyMeters: $locationAccuracyMeters, ')
          ..write('reachCount: $reachCount, ')
          ..write('interestLevel: $interestLevel, ')
          ..write('syncMode: $syncMode, ')
          ..write('abandonedAtUtc: $abandonedAtUtc, ')
          ..write('undoUntilUtc: $undoUntilUtc')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
    draftId,
    appUserId,
    workspaceId,
    projectId,
    questionnaireVersionId,
    createdAtUtc,
    updatedAtUtc,
    occurredAtUtc,
    occurredTimeZone,
    channel,
    channelDetail,
    locationKind,
    placeName,
    smallestRegionId,
    latitude,
    longitude,
    locationAccuracyMeters,
    reachCount,
    interestLevel,
    syncMode,
    abandonedAtUtc,
    undoUntilUtc,
  ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DbContactDraft &&
          other.draftId == this.draftId &&
          other.appUserId == this.appUserId &&
          other.workspaceId == this.workspaceId &&
          other.projectId == this.projectId &&
          other.questionnaireVersionId == this.questionnaireVersionId &&
          other.createdAtUtc == this.createdAtUtc &&
          other.updatedAtUtc == this.updatedAtUtc &&
          other.occurredAtUtc == this.occurredAtUtc &&
          other.occurredTimeZone == this.occurredTimeZone &&
          other.channel == this.channel &&
          other.channelDetail == this.channelDetail &&
          other.locationKind == this.locationKind &&
          other.placeName == this.placeName &&
          other.smallestRegionId == this.smallestRegionId &&
          other.latitude == this.latitude &&
          other.longitude == this.longitude &&
          other.locationAccuracyMeters == this.locationAccuracyMeters &&
          other.reachCount == this.reachCount &&
          other.interestLevel == this.interestLevel &&
          other.syncMode == this.syncMode &&
          other.abandonedAtUtc == this.abandonedAtUtc &&
          other.undoUntilUtc == this.undoUntilUtc);
}

class DbContactDraftsCompanion extends UpdateCompanion<DbContactDraft> {
  final Value<String> draftId;
  final Value<String> appUserId;
  final Value<String> workspaceId;
  final Value<String> projectId;
  final Value<String> questionnaireVersionId;
  final Value<DateTime> createdAtUtc;
  final Value<DateTime> updatedAtUtc;
  final Value<DateTime?> occurredAtUtc;
  final Value<String?> occurredTimeZone;
  final Value<String?> channel;
  final Value<String?> channelDetail;
  final Value<String?> locationKind;
  final Value<String?> placeName;
  final Value<String?> smallestRegionId;
  final Value<double?> latitude;
  final Value<double?> longitude;
  final Value<double?> locationAccuracyMeters;
  final Value<int?> reachCount;
  final Value<int?> interestLevel;
  final Value<String> syncMode;
  final Value<DateTime?> abandonedAtUtc;
  final Value<DateTime?> undoUntilUtc;
  final Value<int> rowid;
  const DbContactDraftsCompanion({
    this.draftId = const Value.absent(),
    this.appUserId = const Value.absent(),
    this.workspaceId = const Value.absent(),
    this.projectId = const Value.absent(),
    this.questionnaireVersionId = const Value.absent(),
    this.createdAtUtc = const Value.absent(),
    this.updatedAtUtc = const Value.absent(),
    this.occurredAtUtc = const Value.absent(),
    this.occurredTimeZone = const Value.absent(),
    this.channel = const Value.absent(),
    this.channelDetail = const Value.absent(),
    this.locationKind = const Value.absent(),
    this.placeName = const Value.absent(),
    this.smallestRegionId = const Value.absent(),
    this.latitude = const Value.absent(),
    this.longitude = const Value.absent(),
    this.locationAccuracyMeters = const Value.absent(),
    this.reachCount = const Value.absent(),
    this.interestLevel = const Value.absent(),
    this.syncMode = const Value.absent(),
    this.abandonedAtUtc = const Value.absent(),
    this.undoUntilUtc = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DbContactDraftsCompanion.insert({
    required String draftId,
    required String appUserId,
    required String workspaceId,
    required String projectId,
    required String questionnaireVersionId,
    required DateTime createdAtUtc,
    required DateTime updatedAtUtc,
    this.occurredAtUtc = const Value.absent(),
    this.occurredTimeZone = const Value.absent(),
    this.channel = const Value.absent(),
    this.channelDetail = const Value.absent(),
    this.locationKind = const Value.absent(),
    this.placeName = const Value.absent(),
    this.smallestRegionId = const Value.absent(),
    this.latitude = const Value.absent(),
    this.longitude = const Value.absent(),
    this.locationAccuracyMeters = const Value.absent(),
    this.reachCount = const Value.absent(),
    this.interestLevel = const Value.absent(),
    this.syncMode = const Value.absent(),
    this.abandonedAtUtc = const Value.absent(),
    this.undoUntilUtc = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : draftId = Value(draftId),
       appUserId = Value(appUserId),
       workspaceId = Value(workspaceId),
       projectId = Value(projectId),
       questionnaireVersionId = Value(questionnaireVersionId),
       createdAtUtc = Value(createdAtUtc),
       updatedAtUtc = Value(updatedAtUtc);
  static Insertable<DbContactDraft> custom({
    Expression<String>? draftId,
    Expression<String>? appUserId,
    Expression<String>? workspaceId,
    Expression<String>? projectId,
    Expression<String>? questionnaireVersionId,
    Expression<DateTime>? createdAtUtc,
    Expression<DateTime>? updatedAtUtc,
    Expression<DateTime>? occurredAtUtc,
    Expression<String>? occurredTimeZone,
    Expression<String>? channel,
    Expression<String>? channelDetail,
    Expression<String>? locationKind,
    Expression<String>? placeName,
    Expression<String>? smallestRegionId,
    Expression<double>? latitude,
    Expression<double>? longitude,
    Expression<double>? locationAccuracyMeters,
    Expression<int>? reachCount,
    Expression<int>? interestLevel,
    Expression<String>? syncMode,
    Expression<DateTime>? abandonedAtUtc,
    Expression<DateTime>? undoUntilUtc,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (draftId != null) 'draft_id': draftId,
      if (appUserId != null) 'app_user_id': appUserId,
      if (workspaceId != null) 'workspace_id': workspaceId,
      if (projectId != null) 'project_id': projectId,
      if (questionnaireVersionId != null)
        'questionnaire_version_id': questionnaireVersionId,
      if (createdAtUtc != null) 'created_at_utc': createdAtUtc,
      if (updatedAtUtc != null) 'updated_at_utc': updatedAtUtc,
      if (occurredAtUtc != null) 'occurred_at_utc': occurredAtUtc,
      if (occurredTimeZone != null) 'occurred_time_zone': occurredTimeZone,
      if (channel != null) 'channel': channel,
      if (channelDetail != null) 'channel_detail': channelDetail,
      if (locationKind != null) 'location_kind': locationKind,
      if (placeName != null) 'place_name': placeName,
      if (smallestRegionId != null) 'smallest_region_id': smallestRegionId,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      if (locationAccuracyMeters != null)
        'location_accuracy_meters': locationAccuracyMeters,
      if (reachCount != null) 'reach_count': reachCount,
      if (interestLevel != null) 'interest_level': interestLevel,
      if (syncMode != null) 'sync_mode': syncMode,
      if (abandonedAtUtc != null) 'abandoned_at_utc': abandonedAtUtc,
      if (undoUntilUtc != null) 'undo_until_utc': undoUntilUtc,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DbContactDraftsCompanion copyWith({
    Value<String>? draftId,
    Value<String>? appUserId,
    Value<String>? workspaceId,
    Value<String>? projectId,
    Value<String>? questionnaireVersionId,
    Value<DateTime>? createdAtUtc,
    Value<DateTime>? updatedAtUtc,
    Value<DateTime?>? occurredAtUtc,
    Value<String?>? occurredTimeZone,
    Value<String?>? channel,
    Value<String?>? channelDetail,
    Value<String?>? locationKind,
    Value<String?>? placeName,
    Value<String?>? smallestRegionId,
    Value<double?>? latitude,
    Value<double?>? longitude,
    Value<double?>? locationAccuracyMeters,
    Value<int?>? reachCount,
    Value<int?>? interestLevel,
    Value<String>? syncMode,
    Value<DateTime?>? abandonedAtUtc,
    Value<DateTime?>? undoUntilUtc,
    Value<int>? rowid,
  }) {
    return DbContactDraftsCompanion(
      draftId: draftId ?? this.draftId,
      appUserId: appUserId ?? this.appUserId,
      workspaceId: workspaceId ?? this.workspaceId,
      projectId: projectId ?? this.projectId,
      questionnaireVersionId:
          questionnaireVersionId ?? this.questionnaireVersionId,
      createdAtUtc: createdAtUtc ?? this.createdAtUtc,
      updatedAtUtc: updatedAtUtc ?? this.updatedAtUtc,
      occurredAtUtc: occurredAtUtc ?? this.occurredAtUtc,
      occurredTimeZone: occurredTimeZone ?? this.occurredTimeZone,
      channel: channel ?? this.channel,
      channelDetail: channelDetail ?? this.channelDetail,
      locationKind: locationKind ?? this.locationKind,
      placeName: placeName ?? this.placeName,
      smallestRegionId: smallestRegionId ?? this.smallestRegionId,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      locationAccuracyMeters:
          locationAccuracyMeters ?? this.locationAccuracyMeters,
      reachCount: reachCount ?? this.reachCount,
      interestLevel: interestLevel ?? this.interestLevel,
      syncMode: syncMode ?? this.syncMode,
      abandonedAtUtc: abandonedAtUtc ?? this.abandonedAtUtc,
      undoUntilUtc: undoUntilUtc ?? this.undoUntilUtc,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (draftId.present) {
      map['draft_id'] = Variable<String>(draftId.value);
    }
    if (appUserId.present) {
      map['app_user_id'] = Variable<String>(appUserId.value);
    }
    if (workspaceId.present) {
      map['workspace_id'] = Variable<String>(workspaceId.value);
    }
    if (projectId.present) {
      map['project_id'] = Variable<String>(projectId.value);
    }
    if (questionnaireVersionId.present) {
      map['questionnaire_version_id'] = Variable<String>(
        questionnaireVersionId.value,
      );
    }
    if (createdAtUtc.present) {
      map['created_at_utc'] = Variable<DateTime>(createdAtUtc.value);
    }
    if (updatedAtUtc.present) {
      map['updated_at_utc'] = Variable<DateTime>(updatedAtUtc.value);
    }
    if (occurredAtUtc.present) {
      map['occurred_at_utc'] = Variable<DateTime>(occurredAtUtc.value);
    }
    if (occurredTimeZone.present) {
      map['occurred_time_zone'] = Variable<String>(occurredTimeZone.value);
    }
    if (channel.present) {
      map['channel'] = Variable<String>(channel.value);
    }
    if (channelDetail.present) {
      map['channel_detail'] = Variable<String>(channelDetail.value);
    }
    if (locationKind.present) {
      map['location_kind'] = Variable<String>(locationKind.value);
    }
    if (placeName.present) {
      map['place_name'] = Variable<String>(placeName.value);
    }
    if (smallestRegionId.present) {
      map['smallest_region_id'] = Variable<String>(smallestRegionId.value);
    }
    if (latitude.present) {
      map['latitude'] = Variable<double>(latitude.value);
    }
    if (longitude.present) {
      map['longitude'] = Variable<double>(longitude.value);
    }
    if (locationAccuracyMeters.present) {
      map['location_accuracy_meters'] = Variable<double>(
        locationAccuracyMeters.value,
      );
    }
    if (reachCount.present) {
      map['reach_count'] = Variable<int>(reachCount.value);
    }
    if (interestLevel.present) {
      map['interest_level'] = Variable<int>(interestLevel.value);
    }
    if (syncMode.present) {
      map['sync_mode'] = Variable<String>(syncMode.value);
    }
    if (abandonedAtUtc.present) {
      map['abandoned_at_utc'] = Variable<DateTime>(abandonedAtUtc.value);
    }
    if (undoUntilUtc.present) {
      map['undo_until_utc'] = Variable<DateTime>(undoUntilUtc.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DbContactDraftsCompanion(')
          ..write('draftId: $draftId, ')
          ..write('appUserId: $appUserId, ')
          ..write('workspaceId: $workspaceId, ')
          ..write('projectId: $projectId, ')
          ..write('questionnaireVersionId: $questionnaireVersionId, ')
          ..write('createdAtUtc: $createdAtUtc, ')
          ..write('updatedAtUtc: $updatedAtUtc, ')
          ..write('occurredAtUtc: $occurredAtUtc, ')
          ..write('occurredTimeZone: $occurredTimeZone, ')
          ..write('channel: $channel, ')
          ..write('channelDetail: $channelDetail, ')
          ..write('locationKind: $locationKind, ')
          ..write('placeName: $placeName, ')
          ..write('smallestRegionId: $smallestRegionId, ')
          ..write('latitude: $latitude, ')
          ..write('longitude: $longitude, ')
          ..write('locationAccuracyMeters: $locationAccuracyMeters, ')
          ..write('reachCount: $reachCount, ')
          ..write('interestLevel: $interestLevel, ')
          ..write('syncMode: $syncMode, ')
          ..write('abandonedAtUtc: $abandonedAtUtc, ')
          ..write('undoUntilUtc: $undoUntilUtc, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $DbContactDraftAnswersTable extends DbContactDraftAnswers
    with TableInfo<$DbContactDraftAnswersTable, DbContactDraftAnswer> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DbContactDraftAnswersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _draftIdMeta = const VerificationMeta(
    'draftId',
  );
  @override
  late final GeneratedColumn<String> draftId = GeneratedColumn<String>(
    'draft_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES db_contact_drafts (draft_id)',
    ),
  );
  static const VerificationMeta _questionIdMeta = const VerificationMeta(
    'questionId',
  );
  @override
  late final GeneratedColumn<String> questionId = GeneratedColumn<String>(
    'question_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _answerStateMeta = const VerificationMeta(
    'answerState',
  );
  @override
  late final GeneratedColumn<String> answerState = GeneratedColumn<String>(
    'answer_state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _answerTypeMeta = const VerificationMeta(
    'answerType',
  );
  @override
  late final GeneratedColumn<String> answerType = GeneratedColumn<String>(
    'answer_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _booleanValueMeta = const VerificationMeta(
    'booleanValue',
  );
  @override
  late final GeneratedColumn<bool> booleanValue = GeneratedColumn<bool>(
    'boolean_value',
    aliasedName,
    true,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("boolean_value" IN (0, 1))',
    ),
  );
  @override
  List<GeneratedColumn> get $columns => [
    draftId,
    questionId,
    answerState,
    answerType,
    booleanValue,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'db_contact_draft_answers';
  @override
  VerificationContext validateIntegrity(
    Insertable<DbContactDraftAnswer> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('draft_id')) {
      context.handle(
        _draftIdMeta,
        draftId.isAcceptableOrUnknown(data['draft_id']!, _draftIdMeta),
      );
    } else if (isInserting) {
      context.missing(_draftIdMeta);
    }
    if (data.containsKey('question_id')) {
      context.handle(
        _questionIdMeta,
        questionId.isAcceptableOrUnknown(data['question_id']!, _questionIdMeta),
      );
    } else if (isInserting) {
      context.missing(_questionIdMeta);
    }
    if (data.containsKey('answer_state')) {
      context.handle(
        _answerStateMeta,
        answerState.isAcceptableOrUnknown(
          data['answer_state']!,
          _answerStateMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_answerStateMeta);
    }
    if (data.containsKey('answer_type')) {
      context.handle(
        _answerTypeMeta,
        answerType.isAcceptableOrUnknown(data['answer_type']!, _answerTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_answerTypeMeta);
    }
    if (data.containsKey('boolean_value')) {
      context.handle(
        _booleanValueMeta,
        booleanValue.isAcceptableOrUnknown(
          data['boolean_value']!,
          _booleanValueMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {draftId, questionId};
  @override
  DbContactDraftAnswer map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DbContactDraftAnswer(
      draftId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}draft_id'],
      )!,
      questionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}question_id'],
      )!,
      answerState: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}answer_state'],
      )!,
      answerType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}answer_type'],
      )!,
      booleanValue: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}boolean_value'],
      ),
    );
  }

  @override
  $DbContactDraftAnswersTable createAlias(String alias) {
    return $DbContactDraftAnswersTable(attachedDatabase, alias);
  }
}

class DbContactDraftAnswer extends DataClass
    implements Insertable<DbContactDraftAnswer> {
  final String draftId;
  final String questionId;
  final String answerState;
  final String answerType;
  final bool? booleanValue;
  const DbContactDraftAnswer({
    required this.draftId,
    required this.questionId,
    required this.answerState,
    required this.answerType,
    this.booleanValue,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['draft_id'] = Variable<String>(draftId);
    map['question_id'] = Variable<String>(questionId);
    map['answer_state'] = Variable<String>(answerState);
    map['answer_type'] = Variable<String>(answerType);
    if (!nullToAbsent || booleanValue != null) {
      map['boolean_value'] = Variable<bool>(booleanValue);
    }
    return map;
  }

  DbContactDraftAnswersCompanion toCompanion(bool nullToAbsent) {
    return DbContactDraftAnswersCompanion(
      draftId: Value(draftId),
      questionId: Value(questionId),
      answerState: Value(answerState),
      answerType: Value(answerType),
      booleanValue: booleanValue == null && nullToAbsent
          ? const Value.absent()
          : Value(booleanValue),
    );
  }

  factory DbContactDraftAnswer.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DbContactDraftAnswer(
      draftId: serializer.fromJson<String>(json['draftId']),
      questionId: serializer.fromJson<String>(json['questionId']),
      answerState: serializer.fromJson<String>(json['answerState']),
      answerType: serializer.fromJson<String>(json['answerType']),
      booleanValue: serializer.fromJson<bool?>(json['booleanValue']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'draftId': serializer.toJson<String>(draftId),
      'questionId': serializer.toJson<String>(questionId),
      'answerState': serializer.toJson<String>(answerState),
      'answerType': serializer.toJson<String>(answerType),
      'booleanValue': serializer.toJson<bool?>(booleanValue),
    };
  }

  DbContactDraftAnswer copyWith({
    String? draftId,
    String? questionId,
    String? answerState,
    String? answerType,
    Value<bool?> booleanValue = const Value.absent(),
  }) => DbContactDraftAnswer(
    draftId: draftId ?? this.draftId,
    questionId: questionId ?? this.questionId,
    answerState: answerState ?? this.answerState,
    answerType: answerType ?? this.answerType,
    booleanValue: booleanValue.present ? booleanValue.value : this.booleanValue,
  );
  DbContactDraftAnswer copyWithCompanion(DbContactDraftAnswersCompanion data) {
    return DbContactDraftAnswer(
      draftId: data.draftId.present ? data.draftId.value : this.draftId,
      questionId: data.questionId.present
          ? data.questionId.value
          : this.questionId,
      answerState: data.answerState.present
          ? data.answerState.value
          : this.answerState,
      answerType: data.answerType.present
          ? data.answerType.value
          : this.answerType,
      booleanValue: data.booleanValue.present
          ? data.booleanValue.value
          : this.booleanValue,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DbContactDraftAnswer(')
          ..write('draftId: $draftId, ')
          ..write('questionId: $questionId, ')
          ..write('answerState: $answerState, ')
          ..write('answerType: $answerType, ')
          ..write('booleanValue: $booleanValue')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(draftId, questionId, answerState, answerType, booleanValue);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DbContactDraftAnswer &&
          other.draftId == this.draftId &&
          other.questionId == this.questionId &&
          other.answerState == this.answerState &&
          other.answerType == this.answerType &&
          other.booleanValue == this.booleanValue);
}

class DbContactDraftAnswersCompanion
    extends UpdateCompanion<DbContactDraftAnswer> {
  final Value<String> draftId;
  final Value<String> questionId;
  final Value<String> answerState;
  final Value<String> answerType;
  final Value<bool?> booleanValue;
  final Value<int> rowid;
  const DbContactDraftAnswersCompanion({
    this.draftId = const Value.absent(),
    this.questionId = const Value.absent(),
    this.answerState = const Value.absent(),
    this.answerType = const Value.absent(),
    this.booleanValue = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DbContactDraftAnswersCompanion.insert({
    required String draftId,
    required String questionId,
    required String answerState,
    required String answerType,
    this.booleanValue = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : draftId = Value(draftId),
       questionId = Value(questionId),
       answerState = Value(answerState),
       answerType = Value(answerType);
  static Insertable<DbContactDraftAnswer> custom({
    Expression<String>? draftId,
    Expression<String>? questionId,
    Expression<String>? answerState,
    Expression<String>? answerType,
    Expression<bool>? booleanValue,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (draftId != null) 'draft_id': draftId,
      if (questionId != null) 'question_id': questionId,
      if (answerState != null) 'answer_state': answerState,
      if (answerType != null) 'answer_type': answerType,
      if (booleanValue != null) 'boolean_value': booleanValue,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DbContactDraftAnswersCompanion copyWith({
    Value<String>? draftId,
    Value<String>? questionId,
    Value<String>? answerState,
    Value<String>? answerType,
    Value<bool?>? booleanValue,
    Value<int>? rowid,
  }) {
    return DbContactDraftAnswersCompanion(
      draftId: draftId ?? this.draftId,
      questionId: questionId ?? this.questionId,
      answerState: answerState ?? this.answerState,
      answerType: answerType ?? this.answerType,
      booleanValue: booleanValue ?? this.booleanValue,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (draftId.present) {
      map['draft_id'] = Variable<String>(draftId.value);
    }
    if (questionId.present) {
      map['question_id'] = Variable<String>(questionId.value);
    }
    if (answerState.present) {
      map['answer_state'] = Variable<String>(answerState.value);
    }
    if (answerType.present) {
      map['answer_type'] = Variable<String>(answerType.value);
    }
    if (booleanValue.present) {
      map['boolean_value'] = Variable<bool>(booleanValue.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DbContactDraftAnswersCompanion(')
          ..write('draftId: $draftId, ')
          ..write('questionId: $questionId, ')
          ..write('answerState: $answerState, ')
          ..write('answerType: $answerType, ')
          ..write('booleanValue: $booleanValue, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $DbUsersTable extends DbUsers with TableInfo<$DbUsersTable, DbUser> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DbUsersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _usernameMeta = const VerificationMeta(
    'username',
  );
  @override
  late final GeneratedColumn<String> username = GeneratedColumn<String>(
    'username',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _displayNameMeta = const VerificationMeta(
    'displayName',
  );
  @override
  late final GeneratedColumn<String> displayName = GeneratedColumn<String>(
    'display_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _emailMeta = const VerificationMeta('email');
  @override
  late final GeneratedColumn<String> email = GeneratedColumn<String>(
    'email',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _phoneMeta = const VerificationMeta('phone');
  @override
  late final GeneratedColumn<String> phone = GeneratedColumn<String>(
    'phone',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _birthdayMeta = const VerificationMeta(
    'birthday',
  );
  @override
  late final GeneratedColumn<DateTime> birthday = GeneratedColumn<DateTime>(
    'birthday',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _genderMeta = const VerificationMeta('gender');
  @override
  late final GeneratedColumn<String> gender = GeneratedColumn<String>(
    'gender',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('unknown'),
  );
  static const VerificationMeta _occupationMeta = const VerificationMeta(
    'occupation',
  );
  @override
  late final GeneratedColumn<String> occupation = GeneratedColumn<String>(
    'occupation',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _contactJsonMeta = const VerificationMeta(
    'contactJson',
  );
  @override
  late final GeneratedColumn<String> contactJson = GeneratedColumn<String>(
    'contact_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('{}'),
  );
  static const VerificationMeta _roleLevelMeta = const VerificationMeta(
    'roleLevel',
  );
  @override
  late final GeneratedColumn<int> roleLevel = GeneratedColumn<int>(
    'role_level',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _cityNamesJsonMeta = const VerificationMeta(
    'cityNamesJson',
  );
  @override
  late final GeneratedColumn<String> cityNamesJson = GeneratedColumn<String>(
    'city_names_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _teamNameMeta = const VerificationMeta(
    'teamName',
  );
  @override
  late final GeneratedColumn<String> teamName = GeneratedColumn<String>(
    'team_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _passwordMd5Meta = const VerificationMeta(
    'passwordMd5',
  );
  @override
  late final GeneratedColumn<String> passwordMd5 = GeneratedColumn<String>(
    'password_md5',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _failedLoginCountMeta = const VerificationMeta(
    'failedLoginCount',
  );
  @override
  late final GeneratedColumn<int> failedLoginCount = GeneratedColumn<int>(
    'failed_login_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _mustChangePasswordMeta =
      const VerificationMeta('mustChangePassword');
  @override
  late final GeneratedColumn<bool> mustChangePassword = GeneratedColumn<bool>(
    'must_change_password',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("must_change_password" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _lockedUntilMeta = const VerificationMeta(
    'lockedUntil',
  );
  @override
  late final GeneratedColumn<DateTime> lockedUntil = GeneratedColumn<DateTime>(
    'locked_until',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastSeenAtMeta = const VerificationMeta(
    'lastSeenAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastSeenAt = GeneratedColumn<DateTime>(
    'last_seen_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastFailedLoginAtMeta = const VerificationMeta(
    'lastFailedLoginAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastFailedLoginAt =
      GeneratedColumn<DateTime>(
        'last_failed_login_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  @override
  List<GeneratedColumn> get $columns => [
    userId,
    username,
    displayName,
    email,
    phone,
    birthday,
    gender,
    occupation,
    contactJson,
    roleLevel,
    cityNamesJson,
    teamName,
    passwordMd5,
    status,
    failedLoginCount,
    mustChangePassword,
    lockedUntil,
    lastSeenAt,
    lastFailedLoginAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'db_users';
  @override
  VerificationContext validateIntegrity(
    Insertable<DbUser> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('username')) {
      context.handle(
        _usernameMeta,
        username.isAcceptableOrUnknown(data['username']!, _usernameMeta),
      );
    } else if (isInserting) {
      context.missing(_usernameMeta);
    }
    if (data.containsKey('display_name')) {
      context.handle(
        _displayNameMeta,
        displayName.isAcceptableOrUnknown(
          data['display_name']!,
          _displayNameMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_displayNameMeta);
    }
    if (data.containsKey('email')) {
      context.handle(
        _emailMeta,
        email.isAcceptableOrUnknown(data['email']!, _emailMeta),
      );
    } else if (isInserting) {
      context.missing(_emailMeta);
    }
    if (data.containsKey('phone')) {
      context.handle(
        _phoneMeta,
        phone.isAcceptableOrUnknown(data['phone']!, _phoneMeta),
      );
    } else if (isInserting) {
      context.missing(_phoneMeta);
    }
    if (data.containsKey('birthday')) {
      context.handle(
        _birthdayMeta,
        birthday.isAcceptableOrUnknown(data['birthday']!, _birthdayMeta),
      );
    }
    if (data.containsKey('gender')) {
      context.handle(
        _genderMeta,
        gender.isAcceptableOrUnknown(data['gender']!, _genderMeta),
      );
    }
    if (data.containsKey('occupation')) {
      context.handle(
        _occupationMeta,
        occupation.isAcceptableOrUnknown(data['occupation']!, _occupationMeta),
      );
    }
    if (data.containsKey('contact_json')) {
      context.handle(
        _contactJsonMeta,
        contactJson.isAcceptableOrUnknown(
          data['contact_json']!,
          _contactJsonMeta,
        ),
      );
    }
    if (data.containsKey('role_level')) {
      context.handle(
        _roleLevelMeta,
        roleLevel.isAcceptableOrUnknown(data['role_level']!, _roleLevelMeta),
      );
    } else if (isInserting) {
      context.missing(_roleLevelMeta);
    }
    if (data.containsKey('city_names_json')) {
      context.handle(
        _cityNamesJsonMeta,
        cityNamesJson.isAcceptableOrUnknown(
          data['city_names_json']!,
          _cityNamesJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_cityNamesJsonMeta);
    }
    if (data.containsKey('team_name')) {
      context.handle(
        _teamNameMeta,
        teamName.isAcceptableOrUnknown(data['team_name']!, _teamNameMeta),
      );
    } else if (isInserting) {
      context.missing(_teamNameMeta);
    }
    if (data.containsKey('password_md5')) {
      context.handle(
        _passwordMd5Meta,
        passwordMd5.isAcceptableOrUnknown(
          data['password_md5']!,
          _passwordMd5Meta,
        ),
      );
    } else if (isInserting) {
      context.missing(_passwordMd5Meta);
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    if (data.containsKey('failed_login_count')) {
      context.handle(
        _failedLoginCountMeta,
        failedLoginCount.isAcceptableOrUnknown(
          data['failed_login_count']!,
          _failedLoginCountMeta,
        ),
      );
    }
    if (data.containsKey('must_change_password')) {
      context.handle(
        _mustChangePasswordMeta,
        mustChangePassword.isAcceptableOrUnknown(
          data['must_change_password']!,
          _mustChangePasswordMeta,
        ),
      );
    }
    if (data.containsKey('locked_until')) {
      context.handle(
        _lockedUntilMeta,
        lockedUntil.isAcceptableOrUnknown(
          data['locked_until']!,
          _lockedUntilMeta,
        ),
      );
    }
    if (data.containsKey('last_seen_at')) {
      context.handle(
        _lastSeenAtMeta,
        lastSeenAt.isAcceptableOrUnknown(
          data['last_seen_at']!,
          _lastSeenAtMeta,
        ),
      );
    }
    if (data.containsKey('last_failed_login_at')) {
      context.handle(
        _lastFailedLoginAtMeta,
        lastFailedLoginAt.isAcceptableOrUnknown(
          data['last_failed_login_at']!,
          _lastFailedLoginAtMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {userId};
  @override
  DbUser map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DbUser(
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      username: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}username'],
      )!,
      displayName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}display_name'],
      )!,
      email: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}email'],
      )!,
      phone: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}phone'],
      )!,
      birthday: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}birthday'],
      ),
      gender: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}gender'],
      )!,
      occupation: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}occupation'],
      )!,
      contactJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}contact_json'],
      )!,
      roleLevel: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}role_level'],
      )!,
      cityNamesJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}city_names_json'],
      )!,
      teamName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}team_name'],
      )!,
      passwordMd5: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}password_md5'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      failedLoginCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}failed_login_count'],
      )!,
      mustChangePassword: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}must_change_password'],
      )!,
      lockedUntil: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}locked_until'],
      ),
      lastSeenAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_seen_at'],
      ),
      lastFailedLoginAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_failed_login_at'],
      ),
    );
  }

  @override
  $DbUsersTable createAlias(String alias) {
    return $DbUsersTable(attachedDatabase, alias);
  }
}

class DbUser extends DataClass implements Insertable<DbUser> {
  final String userId;
  final String username;
  final String displayName;
  final String email;
  final String phone;
  final DateTime? birthday;
  final String gender;
  final String occupation;
  final String contactJson;
  final int roleLevel;
  final String cityNamesJson;
  final String teamName;
  final String passwordMd5;
  final String status;
  final int failedLoginCount;
  final bool mustChangePassword;
  final DateTime? lockedUntil;
  final DateTime? lastSeenAt;
  final DateTime? lastFailedLoginAt;
  const DbUser({
    required this.userId,
    required this.username,
    required this.displayName,
    required this.email,
    required this.phone,
    this.birthday,
    required this.gender,
    required this.occupation,
    required this.contactJson,
    required this.roleLevel,
    required this.cityNamesJson,
    required this.teamName,
    required this.passwordMd5,
    required this.status,
    required this.failedLoginCount,
    required this.mustChangePassword,
    this.lockedUntil,
    this.lastSeenAt,
    this.lastFailedLoginAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['user_id'] = Variable<String>(userId);
    map['username'] = Variable<String>(username);
    map['display_name'] = Variable<String>(displayName);
    map['email'] = Variable<String>(email);
    map['phone'] = Variable<String>(phone);
    if (!nullToAbsent || birthday != null) {
      map['birthday'] = Variable<DateTime>(birthday);
    }
    map['gender'] = Variable<String>(gender);
    map['occupation'] = Variable<String>(occupation);
    map['contact_json'] = Variable<String>(contactJson);
    map['role_level'] = Variable<int>(roleLevel);
    map['city_names_json'] = Variable<String>(cityNamesJson);
    map['team_name'] = Variable<String>(teamName);
    map['password_md5'] = Variable<String>(passwordMd5);
    map['status'] = Variable<String>(status);
    map['failed_login_count'] = Variable<int>(failedLoginCount);
    map['must_change_password'] = Variable<bool>(mustChangePassword);
    if (!nullToAbsent || lockedUntil != null) {
      map['locked_until'] = Variable<DateTime>(lockedUntil);
    }
    if (!nullToAbsent || lastSeenAt != null) {
      map['last_seen_at'] = Variable<DateTime>(lastSeenAt);
    }
    if (!nullToAbsent || lastFailedLoginAt != null) {
      map['last_failed_login_at'] = Variable<DateTime>(lastFailedLoginAt);
    }
    return map;
  }

  DbUsersCompanion toCompanion(bool nullToAbsent) {
    return DbUsersCompanion(
      userId: Value(userId),
      username: Value(username),
      displayName: Value(displayName),
      email: Value(email),
      phone: Value(phone),
      birthday: birthday == null && nullToAbsent
          ? const Value.absent()
          : Value(birthday),
      gender: Value(gender),
      occupation: Value(occupation),
      contactJson: Value(contactJson),
      roleLevel: Value(roleLevel),
      cityNamesJson: Value(cityNamesJson),
      teamName: Value(teamName),
      passwordMd5: Value(passwordMd5),
      status: Value(status),
      failedLoginCount: Value(failedLoginCount),
      mustChangePassword: Value(mustChangePassword),
      lockedUntil: lockedUntil == null && nullToAbsent
          ? const Value.absent()
          : Value(lockedUntil),
      lastSeenAt: lastSeenAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastSeenAt),
      lastFailedLoginAt: lastFailedLoginAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastFailedLoginAt),
    );
  }

  factory DbUser.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DbUser(
      userId: serializer.fromJson<String>(json['userId']),
      username: serializer.fromJson<String>(json['username']),
      displayName: serializer.fromJson<String>(json['displayName']),
      email: serializer.fromJson<String>(json['email']),
      phone: serializer.fromJson<String>(json['phone']),
      birthday: serializer.fromJson<DateTime?>(json['birthday']),
      gender: serializer.fromJson<String>(json['gender']),
      occupation: serializer.fromJson<String>(json['occupation']),
      contactJson: serializer.fromJson<String>(json['contactJson']),
      roleLevel: serializer.fromJson<int>(json['roleLevel']),
      cityNamesJson: serializer.fromJson<String>(json['cityNamesJson']),
      teamName: serializer.fromJson<String>(json['teamName']),
      passwordMd5: serializer.fromJson<String>(json['passwordMd5']),
      status: serializer.fromJson<String>(json['status']),
      failedLoginCount: serializer.fromJson<int>(json['failedLoginCount']),
      mustChangePassword: serializer.fromJson<bool>(json['mustChangePassword']),
      lockedUntil: serializer.fromJson<DateTime?>(json['lockedUntil']),
      lastSeenAt: serializer.fromJson<DateTime?>(json['lastSeenAt']),
      lastFailedLoginAt: serializer.fromJson<DateTime?>(
        json['lastFailedLoginAt'],
      ),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'userId': serializer.toJson<String>(userId),
      'username': serializer.toJson<String>(username),
      'displayName': serializer.toJson<String>(displayName),
      'email': serializer.toJson<String>(email),
      'phone': serializer.toJson<String>(phone),
      'birthday': serializer.toJson<DateTime?>(birthday),
      'gender': serializer.toJson<String>(gender),
      'occupation': serializer.toJson<String>(occupation),
      'contactJson': serializer.toJson<String>(contactJson),
      'roleLevel': serializer.toJson<int>(roleLevel),
      'cityNamesJson': serializer.toJson<String>(cityNamesJson),
      'teamName': serializer.toJson<String>(teamName),
      'passwordMd5': serializer.toJson<String>(passwordMd5),
      'status': serializer.toJson<String>(status),
      'failedLoginCount': serializer.toJson<int>(failedLoginCount),
      'mustChangePassword': serializer.toJson<bool>(mustChangePassword),
      'lockedUntil': serializer.toJson<DateTime?>(lockedUntil),
      'lastSeenAt': serializer.toJson<DateTime?>(lastSeenAt),
      'lastFailedLoginAt': serializer.toJson<DateTime?>(lastFailedLoginAt),
    };
  }

  DbUser copyWith({
    String? userId,
    String? username,
    String? displayName,
    String? email,
    String? phone,
    Value<DateTime?> birthday = const Value.absent(),
    String? gender,
    String? occupation,
    String? contactJson,
    int? roleLevel,
    String? cityNamesJson,
    String? teamName,
    String? passwordMd5,
    String? status,
    int? failedLoginCount,
    bool? mustChangePassword,
    Value<DateTime?> lockedUntil = const Value.absent(),
    Value<DateTime?> lastSeenAt = const Value.absent(),
    Value<DateTime?> lastFailedLoginAt = const Value.absent(),
  }) => DbUser(
    userId: userId ?? this.userId,
    username: username ?? this.username,
    displayName: displayName ?? this.displayName,
    email: email ?? this.email,
    phone: phone ?? this.phone,
    birthday: birthday.present ? birthday.value : this.birthday,
    gender: gender ?? this.gender,
    occupation: occupation ?? this.occupation,
    contactJson: contactJson ?? this.contactJson,
    roleLevel: roleLevel ?? this.roleLevel,
    cityNamesJson: cityNamesJson ?? this.cityNamesJson,
    teamName: teamName ?? this.teamName,
    passwordMd5: passwordMd5 ?? this.passwordMd5,
    status: status ?? this.status,
    failedLoginCount: failedLoginCount ?? this.failedLoginCount,
    mustChangePassword: mustChangePassword ?? this.mustChangePassword,
    lockedUntil: lockedUntil.present ? lockedUntil.value : this.lockedUntil,
    lastSeenAt: lastSeenAt.present ? lastSeenAt.value : this.lastSeenAt,
    lastFailedLoginAt: lastFailedLoginAt.present
        ? lastFailedLoginAt.value
        : this.lastFailedLoginAt,
  );
  DbUser copyWithCompanion(DbUsersCompanion data) {
    return DbUser(
      userId: data.userId.present ? data.userId.value : this.userId,
      username: data.username.present ? data.username.value : this.username,
      displayName: data.displayName.present
          ? data.displayName.value
          : this.displayName,
      email: data.email.present ? data.email.value : this.email,
      phone: data.phone.present ? data.phone.value : this.phone,
      birthday: data.birthday.present ? data.birthday.value : this.birthday,
      gender: data.gender.present ? data.gender.value : this.gender,
      occupation: data.occupation.present
          ? data.occupation.value
          : this.occupation,
      contactJson: data.contactJson.present
          ? data.contactJson.value
          : this.contactJson,
      roleLevel: data.roleLevel.present ? data.roleLevel.value : this.roleLevel,
      cityNamesJson: data.cityNamesJson.present
          ? data.cityNamesJson.value
          : this.cityNamesJson,
      teamName: data.teamName.present ? data.teamName.value : this.teamName,
      passwordMd5: data.passwordMd5.present
          ? data.passwordMd5.value
          : this.passwordMd5,
      status: data.status.present ? data.status.value : this.status,
      failedLoginCount: data.failedLoginCount.present
          ? data.failedLoginCount.value
          : this.failedLoginCount,
      mustChangePassword: data.mustChangePassword.present
          ? data.mustChangePassword.value
          : this.mustChangePassword,
      lockedUntil: data.lockedUntil.present
          ? data.lockedUntil.value
          : this.lockedUntil,
      lastSeenAt: data.lastSeenAt.present
          ? data.lastSeenAt.value
          : this.lastSeenAt,
      lastFailedLoginAt: data.lastFailedLoginAt.present
          ? data.lastFailedLoginAt.value
          : this.lastFailedLoginAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DbUser(')
          ..write('userId: $userId, ')
          ..write('username: $username, ')
          ..write('displayName: $displayName, ')
          ..write('email: $email, ')
          ..write('phone: $phone, ')
          ..write('birthday: $birthday, ')
          ..write('gender: $gender, ')
          ..write('occupation: $occupation, ')
          ..write('contactJson: $contactJson, ')
          ..write('roleLevel: $roleLevel, ')
          ..write('cityNamesJson: $cityNamesJson, ')
          ..write('teamName: $teamName, ')
          ..write('passwordMd5: $passwordMd5, ')
          ..write('status: $status, ')
          ..write('failedLoginCount: $failedLoginCount, ')
          ..write('mustChangePassword: $mustChangePassword, ')
          ..write('lockedUntil: $lockedUntil, ')
          ..write('lastSeenAt: $lastSeenAt, ')
          ..write('lastFailedLoginAt: $lastFailedLoginAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    userId,
    username,
    displayName,
    email,
    phone,
    birthday,
    gender,
    occupation,
    contactJson,
    roleLevel,
    cityNamesJson,
    teamName,
    passwordMd5,
    status,
    failedLoginCount,
    mustChangePassword,
    lockedUntil,
    lastSeenAt,
    lastFailedLoginAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DbUser &&
          other.userId == this.userId &&
          other.username == this.username &&
          other.displayName == this.displayName &&
          other.email == this.email &&
          other.phone == this.phone &&
          other.birthday == this.birthday &&
          other.gender == this.gender &&
          other.occupation == this.occupation &&
          other.contactJson == this.contactJson &&
          other.roleLevel == this.roleLevel &&
          other.cityNamesJson == this.cityNamesJson &&
          other.teamName == this.teamName &&
          other.passwordMd5 == this.passwordMd5 &&
          other.status == this.status &&
          other.failedLoginCount == this.failedLoginCount &&
          other.mustChangePassword == this.mustChangePassword &&
          other.lockedUntil == this.lockedUntil &&
          other.lastSeenAt == this.lastSeenAt &&
          other.lastFailedLoginAt == this.lastFailedLoginAt);
}

class DbUsersCompanion extends UpdateCompanion<DbUser> {
  final Value<String> userId;
  final Value<String> username;
  final Value<String> displayName;
  final Value<String> email;
  final Value<String> phone;
  final Value<DateTime?> birthday;
  final Value<String> gender;
  final Value<String> occupation;
  final Value<String> contactJson;
  final Value<int> roleLevel;
  final Value<String> cityNamesJson;
  final Value<String> teamName;
  final Value<String> passwordMd5;
  final Value<String> status;
  final Value<int> failedLoginCount;
  final Value<bool> mustChangePassword;
  final Value<DateTime?> lockedUntil;
  final Value<DateTime?> lastSeenAt;
  final Value<DateTime?> lastFailedLoginAt;
  final Value<int> rowid;
  const DbUsersCompanion({
    this.userId = const Value.absent(),
    this.username = const Value.absent(),
    this.displayName = const Value.absent(),
    this.email = const Value.absent(),
    this.phone = const Value.absent(),
    this.birthday = const Value.absent(),
    this.gender = const Value.absent(),
    this.occupation = const Value.absent(),
    this.contactJson = const Value.absent(),
    this.roleLevel = const Value.absent(),
    this.cityNamesJson = const Value.absent(),
    this.teamName = const Value.absent(),
    this.passwordMd5 = const Value.absent(),
    this.status = const Value.absent(),
    this.failedLoginCount = const Value.absent(),
    this.mustChangePassword = const Value.absent(),
    this.lockedUntil = const Value.absent(),
    this.lastSeenAt = const Value.absent(),
    this.lastFailedLoginAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DbUsersCompanion.insert({
    required String userId,
    required String username,
    required String displayName,
    required String email,
    required String phone,
    this.birthday = const Value.absent(),
    this.gender = const Value.absent(),
    this.occupation = const Value.absent(),
    this.contactJson = const Value.absent(),
    required int roleLevel,
    required String cityNamesJson,
    required String teamName,
    required String passwordMd5,
    required String status,
    this.failedLoginCount = const Value.absent(),
    this.mustChangePassword = const Value.absent(),
    this.lockedUntil = const Value.absent(),
    this.lastSeenAt = const Value.absent(),
    this.lastFailedLoginAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : userId = Value(userId),
       username = Value(username),
       displayName = Value(displayName),
       email = Value(email),
       phone = Value(phone),
       roleLevel = Value(roleLevel),
       cityNamesJson = Value(cityNamesJson),
       teamName = Value(teamName),
       passwordMd5 = Value(passwordMd5),
       status = Value(status);
  static Insertable<DbUser> custom({
    Expression<String>? userId,
    Expression<String>? username,
    Expression<String>? displayName,
    Expression<String>? email,
    Expression<String>? phone,
    Expression<DateTime>? birthday,
    Expression<String>? gender,
    Expression<String>? occupation,
    Expression<String>? contactJson,
    Expression<int>? roleLevel,
    Expression<String>? cityNamesJson,
    Expression<String>? teamName,
    Expression<String>? passwordMd5,
    Expression<String>? status,
    Expression<int>? failedLoginCount,
    Expression<bool>? mustChangePassword,
    Expression<DateTime>? lockedUntil,
    Expression<DateTime>? lastSeenAt,
    Expression<DateTime>? lastFailedLoginAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (userId != null) 'user_id': userId,
      if (username != null) 'username': username,
      if (displayName != null) 'display_name': displayName,
      if (email != null) 'email': email,
      if (phone != null) 'phone': phone,
      if (birthday != null) 'birthday': birthday,
      if (gender != null) 'gender': gender,
      if (occupation != null) 'occupation': occupation,
      if (contactJson != null) 'contact_json': contactJson,
      if (roleLevel != null) 'role_level': roleLevel,
      if (cityNamesJson != null) 'city_names_json': cityNamesJson,
      if (teamName != null) 'team_name': teamName,
      if (passwordMd5 != null) 'password_md5': passwordMd5,
      if (status != null) 'status': status,
      if (failedLoginCount != null) 'failed_login_count': failedLoginCount,
      if (mustChangePassword != null)
        'must_change_password': mustChangePassword,
      if (lockedUntil != null) 'locked_until': lockedUntil,
      if (lastSeenAt != null) 'last_seen_at': lastSeenAt,
      if (lastFailedLoginAt != null) 'last_failed_login_at': lastFailedLoginAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DbUsersCompanion copyWith({
    Value<String>? userId,
    Value<String>? username,
    Value<String>? displayName,
    Value<String>? email,
    Value<String>? phone,
    Value<DateTime?>? birthday,
    Value<String>? gender,
    Value<String>? occupation,
    Value<String>? contactJson,
    Value<int>? roleLevel,
    Value<String>? cityNamesJson,
    Value<String>? teamName,
    Value<String>? passwordMd5,
    Value<String>? status,
    Value<int>? failedLoginCount,
    Value<bool>? mustChangePassword,
    Value<DateTime?>? lockedUntil,
    Value<DateTime?>? lastSeenAt,
    Value<DateTime?>? lastFailedLoginAt,
    Value<int>? rowid,
  }) {
    return DbUsersCompanion(
      userId: userId ?? this.userId,
      username: username ?? this.username,
      displayName: displayName ?? this.displayName,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      birthday: birthday ?? this.birthday,
      gender: gender ?? this.gender,
      occupation: occupation ?? this.occupation,
      contactJson: contactJson ?? this.contactJson,
      roleLevel: roleLevel ?? this.roleLevel,
      cityNamesJson: cityNamesJson ?? this.cityNamesJson,
      teamName: teamName ?? this.teamName,
      passwordMd5: passwordMd5 ?? this.passwordMd5,
      status: status ?? this.status,
      failedLoginCount: failedLoginCount ?? this.failedLoginCount,
      mustChangePassword: mustChangePassword ?? this.mustChangePassword,
      lockedUntil: lockedUntil ?? this.lockedUntil,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
      lastFailedLoginAt: lastFailedLoginAt ?? this.lastFailedLoginAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (username.present) {
      map['username'] = Variable<String>(username.value);
    }
    if (displayName.present) {
      map['display_name'] = Variable<String>(displayName.value);
    }
    if (email.present) {
      map['email'] = Variable<String>(email.value);
    }
    if (phone.present) {
      map['phone'] = Variable<String>(phone.value);
    }
    if (birthday.present) {
      map['birthday'] = Variable<DateTime>(birthday.value);
    }
    if (gender.present) {
      map['gender'] = Variable<String>(gender.value);
    }
    if (occupation.present) {
      map['occupation'] = Variable<String>(occupation.value);
    }
    if (contactJson.present) {
      map['contact_json'] = Variable<String>(contactJson.value);
    }
    if (roleLevel.present) {
      map['role_level'] = Variable<int>(roleLevel.value);
    }
    if (cityNamesJson.present) {
      map['city_names_json'] = Variable<String>(cityNamesJson.value);
    }
    if (teamName.present) {
      map['team_name'] = Variable<String>(teamName.value);
    }
    if (passwordMd5.present) {
      map['password_md5'] = Variable<String>(passwordMd5.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (failedLoginCount.present) {
      map['failed_login_count'] = Variable<int>(failedLoginCount.value);
    }
    if (mustChangePassword.present) {
      map['must_change_password'] = Variable<bool>(mustChangePassword.value);
    }
    if (lockedUntil.present) {
      map['locked_until'] = Variable<DateTime>(lockedUntil.value);
    }
    if (lastSeenAt.present) {
      map['last_seen_at'] = Variable<DateTime>(lastSeenAt.value);
    }
    if (lastFailedLoginAt.present) {
      map['last_failed_login_at'] = Variable<DateTime>(lastFailedLoginAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DbUsersCompanion(')
          ..write('userId: $userId, ')
          ..write('username: $username, ')
          ..write('displayName: $displayName, ')
          ..write('email: $email, ')
          ..write('phone: $phone, ')
          ..write('birthday: $birthday, ')
          ..write('gender: $gender, ')
          ..write('occupation: $occupation, ')
          ..write('contactJson: $contactJson, ')
          ..write('roleLevel: $roleLevel, ')
          ..write('cityNamesJson: $cityNamesJson, ')
          ..write('teamName: $teamName, ')
          ..write('passwordMd5: $passwordMd5, ')
          ..write('status: $status, ')
          ..write('failedLoginCount: $failedLoginCount, ')
          ..write('mustChangePassword: $mustChangePassword, ')
          ..write('lockedUntil: $lockedUntil, ')
          ..write('lastSeenAt: $lastSeenAt, ')
          ..write('lastFailedLoginAt: $lastFailedLoginAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $DbConversationRecordsTable extends DbConversationRecords
    with TableInfo<$DbConversationRecordsTable, DbConversationRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DbConversationRecordsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _recordIdMeta = const VerificationMeta(
    'recordId',
  );
  @override
  late final GeneratedColumn<String> recordId = GeneratedColumn<String>(
    'record_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
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
    requiredDuringInsert: true,
  );
  static const VerificationMeta _collectorUserIdMeta = const VerificationMeta(
    'collectorUserId',
  );
  @override
  late final GeneratedColumn<String> collectorUserId = GeneratedColumn<String>(
    'collector_user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _cityNameMeta = const VerificationMeta(
    'cityName',
  );
  @override
  late final GeneratedColumn<String> cityName = GeneratedColumn<String>(
    'city_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _areaNameMeta = const VerificationMeta(
    'areaName',
  );
  @override
  late final GeneratedColumn<String> areaName = GeneratedColumn<String>(
    'area_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('unassigned'),
  );
  static const VerificationMeta _teamNameMeta = const VerificationMeta(
    'teamName',
  );
  @override
  late final GeneratedColumn<String> teamName = GeneratedColumn<String>(
    'team_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _recorderNameMeta = const VerificationMeta(
    'recorderName',
  );
  @override
  late final GeneratedColumn<String> recorderName = GeneratedColumn<String>(
    'recorder_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _personNameMeta = const VerificationMeta(
    'personName',
  );
  @override
  late final GeneratedColumn<String> personName = GeneratedColumn<String>(
    'person_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _englishNameMeta = const VerificationMeta(
    'englishName',
  );
  @override
  late final GeneratedColumn<String> englishName = GeneratedColumn<String>(
    'english_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _averageHeartRateMeta = const VerificationMeta(
    'averageHeartRate',
  );
  @override
  late final GeneratedColumn<double> averageHeartRate = GeneratedColumn<double>(
    'average_heart_rate',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _latitudeMeta = const VerificationMeta(
    'latitude',
  );
  @override
  late final GeneratedColumn<double> latitude = GeneratedColumn<double>(
    'latitude',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _longitudeMeta = const VerificationMeta(
    'longitude',
  );
  @override
  late final GeneratedColumn<double> longitude = GeneratedColumn<double>(
    'longitude',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _locationAccuracyMetersMeta =
      const VerificationMeta('locationAccuracyMeters');
  @override
  late final GeneratedColumn<double> locationAccuracyMeters =
      GeneratedColumn<double>(
        'location_accuracy_meters',
        aliasedName,
        true,
        type: DriftSqlType.double,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _locationErrorMeta = const VerificationMeta(
    'locationError',
  );
  @override
  late final GeneratedColumn<String> locationError = GeneratedColumn<String>(
    'location_error',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _manualPlaceNameMeta = const VerificationMeta(
    'manualPlaceName',
  );
  @override
  late final GeneratedColumn<String> manualPlaceName = GeneratedColumn<String>(
    'manual_place_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _genderMeta = const VerificationMeta('gender');
  @override
  late final GeneratedColumn<String> gender = GeneratedColumn<String>(
    'gender',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _identityMeta = const VerificationMeta(
    'identity',
  );
  @override
  late final GeneratedColumn<String> identity = GeneratedColumn<String>(
    'identity',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _ageRangeMeta = const VerificationMeta(
    'ageRange',
  );
  @override
  late final GeneratedColumn<String> ageRange = GeneratedColumn<String>(
    'age_range',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _relationshipLevelMeta = const VerificationMeta(
    'relationshipLevel',
  );
  @override
  late final GeneratedColumn<int> relationshipLevel = GeneratedColumn<int>(
    'relationship_level',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _interestLevelMeta = const VerificationMeta(
    'interestLevel',
  );
  @override
  late final GeneratedColumn<int> interestLevel = GeneratedColumn<int>(
    'interest_level',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(2),
  );
  static const VerificationMeta _attitudeLevelMeta = const VerificationMeta(
    'attitudeLevel',
  );
  @override
  late final GeneratedColumn<int> attitudeLevel = GeneratedColumn<int>(
    'attitude_level',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _notesMeta = const VerificationMeta('notes');
  @override
  late final GeneratedColumn<String> notes = GeneratedColumn<String>(
    'notes',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _isLocationVerifiedMeta =
      const VerificationMeta('isLocationVerified');
  @override
  late final GeneratedColumn<bool> isLocationVerified = GeneratedColumn<bool>(
    'is_location_verified',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_location_verified" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _correctedLatitudeMeta = const VerificationMeta(
    'correctedLatitude',
  );
  @override
  late final GeneratedColumn<double> correctedLatitude =
      GeneratedColumn<double>(
        'corrected_latitude',
        aliasedName,
        true,
        type: DriftSqlType.double,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _correctedLongitudeMeta =
      const VerificationMeta('correctedLongitude');
  @override
  late final GeneratedColumn<double> correctedLongitude =
      GeneratedColumn<double>(
        'corrected_longitude',
        aliasedName,
        true,
        type: DriftSqlType.double,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _correctedPlaceNameMeta =
      const VerificationMeta('correctedPlaceName');
  @override
  late final GeneratedColumn<String> correctedPlaceName =
      GeneratedColumn<String>(
        'corrected_place_name',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _correctedAtMeta = const VerificationMeta(
    'correctedAt',
  );
  @override
  late final GeneratedColumn<DateTime> correctedAt = GeneratedColumn<DateTime>(
    'corrected_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    recordId,
    createdAt,
    collectorUserId,
    cityName,
    areaName,
    teamName,
    recorderName,
    personName,
    englishName,
    averageHeartRate,
    latitude,
    longitude,
    locationAccuracyMeters,
    locationError,
    manualPlaceName,
    gender,
    identity,
    ageRange,
    relationshipLevel,
    interestLevel,
    attitudeLevel,
    notes,
    isLocationVerified,
    correctedLatitude,
    correctedLongitude,
    correctedPlaceName,
    correctedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'db_conversation_records';
  @override
  VerificationContext validateIntegrity(
    Insertable<DbConversationRecord> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('record_id')) {
      context.handle(
        _recordIdMeta,
        recordId.isAcceptableOrUnknown(data['record_id']!, _recordIdMeta),
      );
    } else if (isInserting) {
      context.missing(_recordIdMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('collector_user_id')) {
      context.handle(
        _collectorUserIdMeta,
        collectorUserId.isAcceptableOrUnknown(
          data['collector_user_id']!,
          _collectorUserIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_collectorUserIdMeta);
    }
    if (data.containsKey('city_name')) {
      context.handle(
        _cityNameMeta,
        cityName.isAcceptableOrUnknown(data['city_name']!, _cityNameMeta),
      );
    } else if (isInserting) {
      context.missing(_cityNameMeta);
    }
    if (data.containsKey('area_name')) {
      context.handle(
        _areaNameMeta,
        areaName.isAcceptableOrUnknown(data['area_name']!, _areaNameMeta),
      );
    }
    if (data.containsKey('team_name')) {
      context.handle(
        _teamNameMeta,
        teamName.isAcceptableOrUnknown(data['team_name']!, _teamNameMeta),
      );
    } else if (isInserting) {
      context.missing(_teamNameMeta);
    }
    if (data.containsKey('recorder_name')) {
      context.handle(
        _recorderNameMeta,
        recorderName.isAcceptableOrUnknown(
          data['recorder_name']!,
          _recorderNameMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_recorderNameMeta);
    }
    if (data.containsKey('person_name')) {
      context.handle(
        _personNameMeta,
        personName.isAcceptableOrUnknown(data['person_name']!, _personNameMeta),
      );
    } else if (isInserting) {
      context.missing(_personNameMeta);
    }
    if (data.containsKey('english_name')) {
      context.handle(
        _englishNameMeta,
        englishName.isAcceptableOrUnknown(
          data['english_name']!,
          _englishNameMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_englishNameMeta);
    }
    if (data.containsKey('average_heart_rate')) {
      context.handle(
        _averageHeartRateMeta,
        averageHeartRate.isAcceptableOrUnknown(
          data['average_heart_rate']!,
          _averageHeartRateMeta,
        ),
      );
    }
    if (data.containsKey('latitude')) {
      context.handle(
        _latitudeMeta,
        latitude.isAcceptableOrUnknown(data['latitude']!, _latitudeMeta),
      );
    }
    if (data.containsKey('longitude')) {
      context.handle(
        _longitudeMeta,
        longitude.isAcceptableOrUnknown(data['longitude']!, _longitudeMeta),
      );
    }
    if (data.containsKey('location_accuracy_meters')) {
      context.handle(
        _locationAccuracyMetersMeta,
        locationAccuracyMeters.isAcceptableOrUnknown(
          data['location_accuracy_meters']!,
          _locationAccuracyMetersMeta,
        ),
      );
    }
    if (data.containsKey('location_error')) {
      context.handle(
        _locationErrorMeta,
        locationError.isAcceptableOrUnknown(
          data['location_error']!,
          _locationErrorMeta,
        ),
      );
    }
    if (data.containsKey('manual_place_name')) {
      context.handle(
        _manualPlaceNameMeta,
        manualPlaceName.isAcceptableOrUnknown(
          data['manual_place_name']!,
          _manualPlaceNameMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_manualPlaceNameMeta);
    }
    if (data.containsKey('gender')) {
      context.handle(
        _genderMeta,
        gender.isAcceptableOrUnknown(data['gender']!, _genderMeta),
      );
    } else if (isInserting) {
      context.missing(_genderMeta);
    }
    if (data.containsKey('identity')) {
      context.handle(
        _identityMeta,
        identity.isAcceptableOrUnknown(data['identity']!, _identityMeta),
      );
    } else if (isInserting) {
      context.missing(_identityMeta);
    }
    if (data.containsKey('age_range')) {
      context.handle(
        _ageRangeMeta,
        ageRange.isAcceptableOrUnknown(data['age_range']!, _ageRangeMeta),
      );
    } else if (isInserting) {
      context.missing(_ageRangeMeta);
    }
    if (data.containsKey('relationship_level')) {
      context.handle(
        _relationshipLevelMeta,
        relationshipLevel.isAcceptableOrUnknown(
          data['relationship_level']!,
          _relationshipLevelMeta,
        ),
      );
    }
    if (data.containsKey('interest_level')) {
      context.handle(
        _interestLevelMeta,
        interestLevel.isAcceptableOrUnknown(
          data['interest_level']!,
          _interestLevelMeta,
        ),
      );
    }
    if (data.containsKey('attitude_level')) {
      context.handle(
        _attitudeLevelMeta,
        attitudeLevel.isAcceptableOrUnknown(
          data['attitude_level']!,
          _attitudeLevelMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_attitudeLevelMeta);
    }
    if (data.containsKey('notes')) {
      context.handle(
        _notesMeta,
        notes.isAcceptableOrUnknown(data['notes']!, _notesMeta),
      );
    } else if (isInserting) {
      context.missing(_notesMeta);
    }
    if (data.containsKey('is_location_verified')) {
      context.handle(
        _isLocationVerifiedMeta,
        isLocationVerified.isAcceptableOrUnknown(
          data['is_location_verified']!,
          _isLocationVerifiedMeta,
        ),
      );
    }
    if (data.containsKey('corrected_latitude')) {
      context.handle(
        _correctedLatitudeMeta,
        correctedLatitude.isAcceptableOrUnknown(
          data['corrected_latitude']!,
          _correctedLatitudeMeta,
        ),
      );
    }
    if (data.containsKey('corrected_longitude')) {
      context.handle(
        _correctedLongitudeMeta,
        correctedLongitude.isAcceptableOrUnknown(
          data['corrected_longitude']!,
          _correctedLongitudeMeta,
        ),
      );
    }
    if (data.containsKey('corrected_place_name')) {
      context.handle(
        _correctedPlaceNameMeta,
        correctedPlaceName.isAcceptableOrUnknown(
          data['corrected_place_name']!,
          _correctedPlaceNameMeta,
        ),
      );
    }
    if (data.containsKey('corrected_at')) {
      context.handle(
        _correctedAtMeta,
        correctedAt.isAcceptableOrUnknown(
          data['corrected_at']!,
          _correctedAtMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {recordId};
  @override
  DbConversationRecord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DbConversationRecord(
      recordId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}record_id'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      collectorUserId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}collector_user_id'],
      )!,
      cityName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}city_name'],
      )!,
      areaName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}area_name'],
      )!,
      teamName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}team_name'],
      )!,
      recorderName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}recorder_name'],
      )!,
      personName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}person_name'],
      )!,
      englishName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}english_name'],
      )!,
      averageHeartRate: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}average_heart_rate'],
      ),
      latitude: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}latitude'],
      ),
      longitude: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}longitude'],
      ),
      locationAccuracyMeters: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}location_accuracy_meters'],
      ),
      locationError: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}location_error'],
      ),
      manualPlaceName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}manual_place_name'],
      )!,
      gender: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}gender'],
      )!,
      identity: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}identity'],
      )!,
      ageRange: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}age_range'],
      )!,
      relationshipLevel: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}relationship_level'],
      )!,
      interestLevel: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}interest_level'],
      )!,
      attitudeLevel: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}attitude_level'],
      )!,
      notes: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}notes'],
      )!,
      isLocationVerified: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_location_verified'],
      )!,
      correctedLatitude: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}corrected_latitude'],
      ),
      correctedLongitude: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}corrected_longitude'],
      ),
      correctedPlaceName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}corrected_place_name'],
      ),
      correctedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}corrected_at'],
      ),
    );
  }

  @override
  $DbConversationRecordsTable createAlias(String alias) {
    return $DbConversationRecordsTable(attachedDatabase, alias);
  }
}

class DbConversationRecord extends DataClass
    implements Insertable<DbConversationRecord> {
  final String recordId;
  final DateTime createdAt;
  final String collectorUserId;
  final String cityName;
  final String areaName;
  final String teamName;
  final String recorderName;
  final String personName;
  final String englishName;
  final double? averageHeartRate;
  final double? latitude;
  final double? longitude;
  final double? locationAccuracyMeters;
  final String? locationError;
  final String manualPlaceName;
  final String gender;
  final String identity;
  final String ageRange;
  final int relationshipLevel;
  final int interestLevel;
  final int attitudeLevel;
  final String notes;
  final bool isLocationVerified;
  final double? correctedLatitude;
  final double? correctedLongitude;
  final String? correctedPlaceName;
  final DateTime? correctedAt;
  const DbConversationRecord({
    required this.recordId,
    required this.createdAt,
    required this.collectorUserId,
    required this.cityName,
    required this.areaName,
    required this.teamName,
    required this.recorderName,
    required this.personName,
    required this.englishName,
    this.averageHeartRate,
    this.latitude,
    this.longitude,
    this.locationAccuracyMeters,
    this.locationError,
    required this.manualPlaceName,
    required this.gender,
    required this.identity,
    required this.ageRange,
    required this.relationshipLevel,
    required this.interestLevel,
    required this.attitudeLevel,
    required this.notes,
    required this.isLocationVerified,
    this.correctedLatitude,
    this.correctedLongitude,
    this.correctedPlaceName,
    this.correctedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['record_id'] = Variable<String>(recordId);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['collector_user_id'] = Variable<String>(collectorUserId);
    map['city_name'] = Variable<String>(cityName);
    map['area_name'] = Variable<String>(areaName);
    map['team_name'] = Variable<String>(teamName);
    map['recorder_name'] = Variable<String>(recorderName);
    map['person_name'] = Variable<String>(personName);
    map['english_name'] = Variable<String>(englishName);
    if (!nullToAbsent || averageHeartRate != null) {
      map['average_heart_rate'] = Variable<double>(averageHeartRate);
    }
    if (!nullToAbsent || latitude != null) {
      map['latitude'] = Variable<double>(latitude);
    }
    if (!nullToAbsent || longitude != null) {
      map['longitude'] = Variable<double>(longitude);
    }
    if (!nullToAbsent || locationAccuracyMeters != null) {
      map['location_accuracy_meters'] = Variable<double>(
        locationAccuracyMeters,
      );
    }
    if (!nullToAbsent || locationError != null) {
      map['location_error'] = Variable<String>(locationError);
    }
    map['manual_place_name'] = Variable<String>(manualPlaceName);
    map['gender'] = Variable<String>(gender);
    map['identity'] = Variable<String>(identity);
    map['age_range'] = Variable<String>(ageRange);
    map['relationship_level'] = Variable<int>(relationshipLevel);
    map['interest_level'] = Variable<int>(interestLevel);
    map['attitude_level'] = Variable<int>(attitudeLevel);
    map['notes'] = Variable<String>(notes);
    map['is_location_verified'] = Variable<bool>(isLocationVerified);
    if (!nullToAbsent || correctedLatitude != null) {
      map['corrected_latitude'] = Variable<double>(correctedLatitude);
    }
    if (!nullToAbsent || correctedLongitude != null) {
      map['corrected_longitude'] = Variable<double>(correctedLongitude);
    }
    if (!nullToAbsent || correctedPlaceName != null) {
      map['corrected_place_name'] = Variable<String>(correctedPlaceName);
    }
    if (!nullToAbsent || correctedAt != null) {
      map['corrected_at'] = Variable<DateTime>(correctedAt);
    }
    return map;
  }

  DbConversationRecordsCompanion toCompanion(bool nullToAbsent) {
    return DbConversationRecordsCompanion(
      recordId: Value(recordId),
      createdAt: Value(createdAt),
      collectorUserId: Value(collectorUserId),
      cityName: Value(cityName),
      areaName: Value(areaName),
      teamName: Value(teamName),
      recorderName: Value(recorderName),
      personName: Value(personName),
      englishName: Value(englishName),
      averageHeartRate: averageHeartRate == null && nullToAbsent
          ? const Value.absent()
          : Value(averageHeartRate),
      latitude: latitude == null && nullToAbsent
          ? const Value.absent()
          : Value(latitude),
      longitude: longitude == null && nullToAbsent
          ? const Value.absent()
          : Value(longitude),
      locationAccuracyMeters: locationAccuracyMeters == null && nullToAbsent
          ? const Value.absent()
          : Value(locationAccuracyMeters),
      locationError: locationError == null && nullToAbsent
          ? const Value.absent()
          : Value(locationError),
      manualPlaceName: Value(manualPlaceName),
      gender: Value(gender),
      identity: Value(identity),
      ageRange: Value(ageRange),
      relationshipLevel: Value(relationshipLevel),
      interestLevel: Value(interestLevel),
      attitudeLevel: Value(attitudeLevel),
      notes: Value(notes),
      isLocationVerified: Value(isLocationVerified),
      correctedLatitude: correctedLatitude == null && nullToAbsent
          ? const Value.absent()
          : Value(correctedLatitude),
      correctedLongitude: correctedLongitude == null && nullToAbsent
          ? const Value.absent()
          : Value(correctedLongitude),
      correctedPlaceName: correctedPlaceName == null && nullToAbsent
          ? const Value.absent()
          : Value(correctedPlaceName),
      correctedAt: correctedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(correctedAt),
    );
  }

  factory DbConversationRecord.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DbConversationRecord(
      recordId: serializer.fromJson<String>(json['recordId']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      collectorUserId: serializer.fromJson<String>(json['collectorUserId']),
      cityName: serializer.fromJson<String>(json['cityName']),
      areaName: serializer.fromJson<String>(json['areaName']),
      teamName: serializer.fromJson<String>(json['teamName']),
      recorderName: serializer.fromJson<String>(json['recorderName']),
      personName: serializer.fromJson<String>(json['personName']),
      englishName: serializer.fromJson<String>(json['englishName']),
      averageHeartRate: serializer.fromJson<double?>(json['averageHeartRate']),
      latitude: serializer.fromJson<double?>(json['latitude']),
      longitude: serializer.fromJson<double?>(json['longitude']),
      locationAccuracyMeters: serializer.fromJson<double?>(
        json['locationAccuracyMeters'],
      ),
      locationError: serializer.fromJson<String?>(json['locationError']),
      manualPlaceName: serializer.fromJson<String>(json['manualPlaceName']),
      gender: serializer.fromJson<String>(json['gender']),
      identity: serializer.fromJson<String>(json['identity']),
      ageRange: serializer.fromJson<String>(json['ageRange']),
      relationshipLevel: serializer.fromJson<int>(json['relationshipLevel']),
      interestLevel: serializer.fromJson<int>(json['interestLevel']),
      attitudeLevel: serializer.fromJson<int>(json['attitudeLevel']),
      notes: serializer.fromJson<String>(json['notes']),
      isLocationVerified: serializer.fromJson<bool>(json['isLocationVerified']),
      correctedLatitude: serializer.fromJson<double?>(
        json['correctedLatitude'],
      ),
      correctedLongitude: serializer.fromJson<double?>(
        json['correctedLongitude'],
      ),
      correctedPlaceName: serializer.fromJson<String?>(
        json['correctedPlaceName'],
      ),
      correctedAt: serializer.fromJson<DateTime?>(json['correctedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'recordId': serializer.toJson<String>(recordId),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'collectorUserId': serializer.toJson<String>(collectorUserId),
      'cityName': serializer.toJson<String>(cityName),
      'areaName': serializer.toJson<String>(areaName),
      'teamName': serializer.toJson<String>(teamName),
      'recorderName': serializer.toJson<String>(recorderName),
      'personName': serializer.toJson<String>(personName),
      'englishName': serializer.toJson<String>(englishName),
      'averageHeartRate': serializer.toJson<double?>(averageHeartRate),
      'latitude': serializer.toJson<double?>(latitude),
      'longitude': serializer.toJson<double?>(longitude),
      'locationAccuracyMeters': serializer.toJson<double?>(
        locationAccuracyMeters,
      ),
      'locationError': serializer.toJson<String?>(locationError),
      'manualPlaceName': serializer.toJson<String>(manualPlaceName),
      'gender': serializer.toJson<String>(gender),
      'identity': serializer.toJson<String>(identity),
      'ageRange': serializer.toJson<String>(ageRange),
      'relationshipLevel': serializer.toJson<int>(relationshipLevel),
      'interestLevel': serializer.toJson<int>(interestLevel),
      'attitudeLevel': serializer.toJson<int>(attitudeLevel),
      'notes': serializer.toJson<String>(notes),
      'isLocationVerified': serializer.toJson<bool>(isLocationVerified),
      'correctedLatitude': serializer.toJson<double?>(correctedLatitude),
      'correctedLongitude': serializer.toJson<double?>(correctedLongitude),
      'correctedPlaceName': serializer.toJson<String?>(correctedPlaceName),
      'correctedAt': serializer.toJson<DateTime?>(correctedAt),
    };
  }

  DbConversationRecord copyWith({
    String? recordId,
    DateTime? createdAt,
    String? collectorUserId,
    String? cityName,
    String? areaName,
    String? teamName,
    String? recorderName,
    String? personName,
    String? englishName,
    Value<double?> averageHeartRate = const Value.absent(),
    Value<double?> latitude = const Value.absent(),
    Value<double?> longitude = const Value.absent(),
    Value<double?> locationAccuracyMeters = const Value.absent(),
    Value<String?> locationError = const Value.absent(),
    String? manualPlaceName,
    String? gender,
    String? identity,
    String? ageRange,
    int? relationshipLevel,
    int? interestLevel,
    int? attitudeLevel,
    String? notes,
    bool? isLocationVerified,
    Value<double?> correctedLatitude = const Value.absent(),
    Value<double?> correctedLongitude = const Value.absent(),
    Value<String?> correctedPlaceName = const Value.absent(),
    Value<DateTime?> correctedAt = const Value.absent(),
  }) => DbConversationRecord(
    recordId: recordId ?? this.recordId,
    createdAt: createdAt ?? this.createdAt,
    collectorUserId: collectorUserId ?? this.collectorUserId,
    cityName: cityName ?? this.cityName,
    areaName: areaName ?? this.areaName,
    teamName: teamName ?? this.teamName,
    recorderName: recorderName ?? this.recorderName,
    personName: personName ?? this.personName,
    englishName: englishName ?? this.englishName,
    averageHeartRate: averageHeartRate.present
        ? averageHeartRate.value
        : this.averageHeartRate,
    latitude: latitude.present ? latitude.value : this.latitude,
    longitude: longitude.present ? longitude.value : this.longitude,
    locationAccuracyMeters: locationAccuracyMeters.present
        ? locationAccuracyMeters.value
        : this.locationAccuracyMeters,
    locationError: locationError.present
        ? locationError.value
        : this.locationError,
    manualPlaceName: manualPlaceName ?? this.manualPlaceName,
    gender: gender ?? this.gender,
    identity: identity ?? this.identity,
    ageRange: ageRange ?? this.ageRange,
    relationshipLevel: relationshipLevel ?? this.relationshipLevel,
    interestLevel: interestLevel ?? this.interestLevel,
    attitudeLevel: attitudeLevel ?? this.attitudeLevel,
    notes: notes ?? this.notes,
    isLocationVerified: isLocationVerified ?? this.isLocationVerified,
    correctedLatitude: correctedLatitude.present
        ? correctedLatitude.value
        : this.correctedLatitude,
    correctedLongitude: correctedLongitude.present
        ? correctedLongitude.value
        : this.correctedLongitude,
    correctedPlaceName: correctedPlaceName.present
        ? correctedPlaceName.value
        : this.correctedPlaceName,
    correctedAt: correctedAt.present ? correctedAt.value : this.correctedAt,
  );
  DbConversationRecord copyWithCompanion(DbConversationRecordsCompanion data) {
    return DbConversationRecord(
      recordId: data.recordId.present ? data.recordId.value : this.recordId,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      collectorUserId: data.collectorUserId.present
          ? data.collectorUserId.value
          : this.collectorUserId,
      cityName: data.cityName.present ? data.cityName.value : this.cityName,
      areaName: data.areaName.present ? data.areaName.value : this.areaName,
      teamName: data.teamName.present ? data.teamName.value : this.teamName,
      recorderName: data.recorderName.present
          ? data.recorderName.value
          : this.recorderName,
      personName: data.personName.present
          ? data.personName.value
          : this.personName,
      englishName: data.englishName.present
          ? data.englishName.value
          : this.englishName,
      averageHeartRate: data.averageHeartRate.present
          ? data.averageHeartRate.value
          : this.averageHeartRate,
      latitude: data.latitude.present ? data.latitude.value : this.latitude,
      longitude: data.longitude.present ? data.longitude.value : this.longitude,
      locationAccuracyMeters: data.locationAccuracyMeters.present
          ? data.locationAccuracyMeters.value
          : this.locationAccuracyMeters,
      locationError: data.locationError.present
          ? data.locationError.value
          : this.locationError,
      manualPlaceName: data.manualPlaceName.present
          ? data.manualPlaceName.value
          : this.manualPlaceName,
      gender: data.gender.present ? data.gender.value : this.gender,
      identity: data.identity.present ? data.identity.value : this.identity,
      ageRange: data.ageRange.present ? data.ageRange.value : this.ageRange,
      relationshipLevel: data.relationshipLevel.present
          ? data.relationshipLevel.value
          : this.relationshipLevel,
      interestLevel: data.interestLevel.present
          ? data.interestLevel.value
          : this.interestLevel,
      attitudeLevel: data.attitudeLevel.present
          ? data.attitudeLevel.value
          : this.attitudeLevel,
      notes: data.notes.present ? data.notes.value : this.notes,
      isLocationVerified: data.isLocationVerified.present
          ? data.isLocationVerified.value
          : this.isLocationVerified,
      correctedLatitude: data.correctedLatitude.present
          ? data.correctedLatitude.value
          : this.correctedLatitude,
      correctedLongitude: data.correctedLongitude.present
          ? data.correctedLongitude.value
          : this.correctedLongitude,
      correctedPlaceName: data.correctedPlaceName.present
          ? data.correctedPlaceName.value
          : this.correctedPlaceName,
      correctedAt: data.correctedAt.present
          ? data.correctedAt.value
          : this.correctedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DbConversationRecord(')
          ..write('recordId: $recordId, ')
          ..write('createdAt: $createdAt, ')
          ..write('collectorUserId: $collectorUserId, ')
          ..write('cityName: $cityName, ')
          ..write('areaName: $areaName, ')
          ..write('teamName: $teamName, ')
          ..write('recorderName: $recorderName, ')
          ..write('personName: $personName, ')
          ..write('englishName: $englishName, ')
          ..write('averageHeartRate: $averageHeartRate, ')
          ..write('latitude: $latitude, ')
          ..write('longitude: $longitude, ')
          ..write('locationAccuracyMeters: $locationAccuracyMeters, ')
          ..write('locationError: $locationError, ')
          ..write('manualPlaceName: $manualPlaceName, ')
          ..write('gender: $gender, ')
          ..write('identity: $identity, ')
          ..write('ageRange: $ageRange, ')
          ..write('relationshipLevel: $relationshipLevel, ')
          ..write('interestLevel: $interestLevel, ')
          ..write('attitudeLevel: $attitudeLevel, ')
          ..write('notes: $notes, ')
          ..write('isLocationVerified: $isLocationVerified, ')
          ..write('correctedLatitude: $correctedLatitude, ')
          ..write('correctedLongitude: $correctedLongitude, ')
          ..write('correctedPlaceName: $correctedPlaceName, ')
          ..write('correctedAt: $correctedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
    recordId,
    createdAt,
    collectorUserId,
    cityName,
    areaName,
    teamName,
    recorderName,
    personName,
    englishName,
    averageHeartRate,
    latitude,
    longitude,
    locationAccuracyMeters,
    locationError,
    manualPlaceName,
    gender,
    identity,
    ageRange,
    relationshipLevel,
    interestLevel,
    attitudeLevel,
    notes,
    isLocationVerified,
    correctedLatitude,
    correctedLongitude,
    correctedPlaceName,
    correctedAt,
  ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DbConversationRecord &&
          other.recordId == this.recordId &&
          other.createdAt == this.createdAt &&
          other.collectorUserId == this.collectorUserId &&
          other.cityName == this.cityName &&
          other.areaName == this.areaName &&
          other.teamName == this.teamName &&
          other.recorderName == this.recorderName &&
          other.personName == this.personName &&
          other.englishName == this.englishName &&
          other.averageHeartRate == this.averageHeartRate &&
          other.latitude == this.latitude &&
          other.longitude == this.longitude &&
          other.locationAccuracyMeters == this.locationAccuracyMeters &&
          other.locationError == this.locationError &&
          other.manualPlaceName == this.manualPlaceName &&
          other.gender == this.gender &&
          other.identity == this.identity &&
          other.ageRange == this.ageRange &&
          other.relationshipLevel == this.relationshipLevel &&
          other.interestLevel == this.interestLevel &&
          other.attitudeLevel == this.attitudeLevel &&
          other.notes == this.notes &&
          other.isLocationVerified == this.isLocationVerified &&
          other.correctedLatitude == this.correctedLatitude &&
          other.correctedLongitude == this.correctedLongitude &&
          other.correctedPlaceName == this.correctedPlaceName &&
          other.correctedAt == this.correctedAt);
}

class DbConversationRecordsCompanion
    extends UpdateCompanion<DbConversationRecord> {
  final Value<String> recordId;
  final Value<DateTime> createdAt;
  final Value<String> collectorUserId;
  final Value<String> cityName;
  final Value<String> areaName;
  final Value<String> teamName;
  final Value<String> recorderName;
  final Value<String> personName;
  final Value<String> englishName;
  final Value<double?> averageHeartRate;
  final Value<double?> latitude;
  final Value<double?> longitude;
  final Value<double?> locationAccuracyMeters;
  final Value<String?> locationError;
  final Value<String> manualPlaceName;
  final Value<String> gender;
  final Value<String> identity;
  final Value<String> ageRange;
  final Value<int> relationshipLevel;
  final Value<int> interestLevel;
  final Value<int> attitudeLevel;
  final Value<String> notes;
  final Value<bool> isLocationVerified;
  final Value<double?> correctedLatitude;
  final Value<double?> correctedLongitude;
  final Value<String?> correctedPlaceName;
  final Value<DateTime?> correctedAt;
  final Value<int> rowid;
  const DbConversationRecordsCompanion({
    this.recordId = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.collectorUserId = const Value.absent(),
    this.cityName = const Value.absent(),
    this.areaName = const Value.absent(),
    this.teamName = const Value.absent(),
    this.recorderName = const Value.absent(),
    this.personName = const Value.absent(),
    this.englishName = const Value.absent(),
    this.averageHeartRate = const Value.absent(),
    this.latitude = const Value.absent(),
    this.longitude = const Value.absent(),
    this.locationAccuracyMeters = const Value.absent(),
    this.locationError = const Value.absent(),
    this.manualPlaceName = const Value.absent(),
    this.gender = const Value.absent(),
    this.identity = const Value.absent(),
    this.ageRange = const Value.absent(),
    this.relationshipLevel = const Value.absent(),
    this.interestLevel = const Value.absent(),
    this.attitudeLevel = const Value.absent(),
    this.notes = const Value.absent(),
    this.isLocationVerified = const Value.absent(),
    this.correctedLatitude = const Value.absent(),
    this.correctedLongitude = const Value.absent(),
    this.correctedPlaceName = const Value.absent(),
    this.correctedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DbConversationRecordsCompanion.insert({
    required String recordId,
    required DateTime createdAt,
    required String collectorUserId,
    required String cityName,
    this.areaName = const Value.absent(),
    required String teamName,
    required String recorderName,
    required String personName,
    required String englishName,
    this.averageHeartRate = const Value.absent(),
    this.latitude = const Value.absent(),
    this.longitude = const Value.absent(),
    this.locationAccuracyMeters = const Value.absent(),
    this.locationError = const Value.absent(),
    required String manualPlaceName,
    required String gender,
    required String identity,
    required String ageRange,
    this.relationshipLevel = const Value.absent(),
    this.interestLevel = const Value.absent(),
    required int attitudeLevel,
    required String notes,
    this.isLocationVerified = const Value.absent(),
    this.correctedLatitude = const Value.absent(),
    this.correctedLongitude = const Value.absent(),
    this.correctedPlaceName = const Value.absent(),
    this.correctedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : recordId = Value(recordId),
       createdAt = Value(createdAt),
       collectorUserId = Value(collectorUserId),
       cityName = Value(cityName),
       teamName = Value(teamName),
       recorderName = Value(recorderName),
       personName = Value(personName),
       englishName = Value(englishName),
       manualPlaceName = Value(manualPlaceName),
       gender = Value(gender),
       identity = Value(identity),
       ageRange = Value(ageRange),
       attitudeLevel = Value(attitudeLevel),
       notes = Value(notes);
  static Insertable<DbConversationRecord> custom({
    Expression<String>? recordId,
    Expression<DateTime>? createdAt,
    Expression<String>? collectorUserId,
    Expression<String>? cityName,
    Expression<String>? areaName,
    Expression<String>? teamName,
    Expression<String>? recorderName,
    Expression<String>? personName,
    Expression<String>? englishName,
    Expression<double>? averageHeartRate,
    Expression<double>? latitude,
    Expression<double>? longitude,
    Expression<double>? locationAccuracyMeters,
    Expression<String>? locationError,
    Expression<String>? manualPlaceName,
    Expression<String>? gender,
    Expression<String>? identity,
    Expression<String>? ageRange,
    Expression<int>? relationshipLevel,
    Expression<int>? interestLevel,
    Expression<int>? attitudeLevel,
    Expression<String>? notes,
    Expression<bool>? isLocationVerified,
    Expression<double>? correctedLatitude,
    Expression<double>? correctedLongitude,
    Expression<String>? correctedPlaceName,
    Expression<DateTime>? correctedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (recordId != null) 'record_id': recordId,
      if (createdAt != null) 'created_at': createdAt,
      if (collectorUserId != null) 'collector_user_id': collectorUserId,
      if (cityName != null) 'city_name': cityName,
      if (areaName != null) 'area_name': areaName,
      if (teamName != null) 'team_name': teamName,
      if (recorderName != null) 'recorder_name': recorderName,
      if (personName != null) 'person_name': personName,
      if (englishName != null) 'english_name': englishName,
      if (averageHeartRate != null) 'average_heart_rate': averageHeartRate,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      if (locationAccuracyMeters != null)
        'location_accuracy_meters': locationAccuracyMeters,
      if (locationError != null) 'location_error': locationError,
      if (manualPlaceName != null) 'manual_place_name': manualPlaceName,
      if (gender != null) 'gender': gender,
      if (identity != null) 'identity': identity,
      if (ageRange != null) 'age_range': ageRange,
      if (relationshipLevel != null) 'relationship_level': relationshipLevel,
      if (interestLevel != null) 'interest_level': interestLevel,
      if (attitudeLevel != null) 'attitude_level': attitudeLevel,
      if (notes != null) 'notes': notes,
      if (isLocationVerified != null)
        'is_location_verified': isLocationVerified,
      if (correctedLatitude != null) 'corrected_latitude': correctedLatitude,
      if (correctedLongitude != null) 'corrected_longitude': correctedLongitude,
      if (correctedPlaceName != null)
        'corrected_place_name': correctedPlaceName,
      if (correctedAt != null) 'corrected_at': correctedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DbConversationRecordsCompanion copyWith({
    Value<String>? recordId,
    Value<DateTime>? createdAt,
    Value<String>? collectorUserId,
    Value<String>? cityName,
    Value<String>? areaName,
    Value<String>? teamName,
    Value<String>? recorderName,
    Value<String>? personName,
    Value<String>? englishName,
    Value<double?>? averageHeartRate,
    Value<double?>? latitude,
    Value<double?>? longitude,
    Value<double?>? locationAccuracyMeters,
    Value<String?>? locationError,
    Value<String>? manualPlaceName,
    Value<String>? gender,
    Value<String>? identity,
    Value<String>? ageRange,
    Value<int>? relationshipLevel,
    Value<int>? interestLevel,
    Value<int>? attitudeLevel,
    Value<String>? notes,
    Value<bool>? isLocationVerified,
    Value<double?>? correctedLatitude,
    Value<double?>? correctedLongitude,
    Value<String?>? correctedPlaceName,
    Value<DateTime?>? correctedAt,
    Value<int>? rowid,
  }) {
    return DbConversationRecordsCompanion(
      recordId: recordId ?? this.recordId,
      createdAt: createdAt ?? this.createdAt,
      collectorUserId: collectorUserId ?? this.collectorUserId,
      cityName: cityName ?? this.cityName,
      areaName: areaName ?? this.areaName,
      teamName: teamName ?? this.teamName,
      recorderName: recorderName ?? this.recorderName,
      personName: personName ?? this.personName,
      englishName: englishName ?? this.englishName,
      averageHeartRate: averageHeartRate ?? this.averageHeartRate,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      locationAccuracyMeters:
          locationAccuracyMeters ?? this.locationAccuracyMeters,
      locationError: locationError ?? this.locationError,
      manualPlaceName: manualPlaceName ?? this.manualPlaceName,
      gender: gender ?? this.gender,
      identity: identity ?? this.identity,
      ageRange: ageRange ?? this.ageRange,
      relationshipLevel: relationshipLevel ?? this.relationshipLevel,
      interestLevel: interestLevel ?? this.interestLevel,
      attitudeLevel: attitudeLevel ?? this.attitudeLevel,
      notes: notes ?? this.notes,
      isLocationVerified: isLocationVerified ?? this.isLocationVerified,
      correctedLatitude: correctedLatitude ?? this.correctedLatitude,
      correctedLongitude: correctedLongitude ?? this.correctedLongitude,
      correctedPlaceName: correctedPlaceName ?? this.correctedPlaceName,
      correctedAt: correctedAt ?? this.correctedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (recordId.present) {
      map['record_id'] = Variable<String>(recordId.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (collectorUserId.present) {
      map['collector_user_id'] = Variable<String>(collectorUserId.value);
    }
    if (cityName.present) {
      map['city_name'] = Variable<String>(cityName.value);
    }
    if (areaName.present) {
      map['area_name'] = Variable<String>(areaName.value);
    }
    if (teamName.present) {
      map['team_name'] = Variable<String>(teamName.value);
    }
    if (recorderName.present) {
      map['recorder_name'] = Variable<String>(recorderName.value);
    }
    if (personName.present) {
      map['person_name'] = Variable<String>(personName.value);
    }
    if (englishName.present) {
      map['english_name'] = Variable<String>(englishName.value);
    }
    if (averageHeartRate.present) {
      map['average_heart_rate'] = Variable<double>(averageHeartRate.value);
    }
    if (latitude.present) {
      map['latitude'] = Variable<double>(latitude.value);
    }
    if (longitude.present) {
      map['longitude'] = Variable<double>(longitude.value);
    }
    if (locationAccuracyMeters.present) {
      map['location_accuracy_meters'] = Variable<double>(
        locationAccuracyMeters.value,
      );
    }
    if (locationError.present) {
      map['location_error'] = Variable<String>(locationError.value);
    }
    if (manualPlaceName.present) {
      map['manual_place_name'] = Variable<String>(manualPlaceName.value);
    }
    if (gender.present) {
      map['gender'] = Variable<String>(gender.value);
    }
    if (identity.present) {
      map['identity'] = Variable<String>(identity.value);
    }
    if (ageRange.present) {
      map['age_range'] = Variable<String>(ageRange.value);
    }
    if (relationshipLevel.present) {
      map['relationship_level'] = Variable<int>(relationshipLevel.value);
    }
    if (interestLevel.present) {
      map['interest_level'] = Variable<int>(interestLevel.value);
    }
    if (attitudeLevel.present) {
      map['attitude_level'] = Variable<int>(attitudeLevel.value);
    }
    if (notes.present) {
      map['notes'] = Variable<String>(notes.value);
    }
    if (isLocationVerified.present) {
      map['is_location_verified'] = Variable<bool>(isLocationVerified.value);
    }
    if (correctedLatitude.present) {
      map['corrected_latitude'] = Variable<double>(correctedLatitude.value);
    }
    if (correctedLongitude.present) {
      map['corrected_longitude'] = Variable<double>(correctedLongitude.value);
    }
    if (correctedPlaceName.present) {
      map['corrected_place_name'] = Variable<String>(correctedPlaceName.value);
    }
    if (correctedAt.present) {
      map['corrected_at'] = Variable<DateTime>(correctedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DbConversationRecordsCompanion(')
          ..write('recordId: $recordId, ')
          ..write('createdAt: $createdAt, ')
          ..write('collectorUserId: $collectorUserId, ')
          ..write('cityName: $cityName, ')
          ..write('areaName: $areaName, ')
          ..write('teamName: $teamName, ')
          ..write('recorderName: $recorderName, ')
          ..write('personName: $personName, ')
          ..write('englishName: $englishName, ')
          ..write('averageHeartRate: $averageHeartRate, ')
          ..write('latitude: $latitude, ')
          ..write('longitude: $longitude, ')
          ..write('locationAccuracyMeters: $locationAccuracyMeters, ')
          ..write('locationError: $locationError, ')
          ..write('manualPlaceName: $manualPlaceName, ')
          ..write('gender: $gender, ')
          ..write('identity: $identity, ')
          ..write('ageRange: $ageRange, ')
          ..write('relationshipLevel: $relationshipLevel, ')
          ..write('interestLevel: $interestLevel, ')
          ..write('attitudeLevel: $attitudeLevel, ')
          ..write('notes: $notes, ')
          ..write('isLocationVerified: $isLocationVerified, ')
          ..write('correctedLatitude: $correctedLatitude, ')
          ..write('correctedLongitude: $correctedLongitude, ')
          ..write('correctedPlaceName: $correctedPlaceName, ')
          ..write('correctedAt: $correctedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $DbRecordContactsTable extends DbRecordContacts
    with TableInfo<$DbRecordContactsTable, DbRecordContact> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DbRecordContactsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _contactIdMeta = const VerificationMeta(
    'contactId',
  );
  @override
  late final GeneratedColumn<String> contactId = GeneratedColumn<String>(
    'contact_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _recordIdMeta = const VerificationMeta(
    'recordId',
  );
  @override
  late final GeneratedColumn<String> recordId = GeneratedColumn<String>(
    'record_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _channelMeta = const VerificationMeta(
    'channel',
  );
  @override
  late final GeneratedColumn<String> channel = GeneratedColumn<String>(
    'channel',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
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
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    contactId,
    recordId,
    channel,
    value,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'db_record_contacts';
  @override
  VerificationContext validateIntegrity(
    Insertable<DbRecordContact> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('contact_id')) {
      context.handle(
        _contactIdMeta,
        contactId.isAcceptableOrUnknown(data['contact_id']!, _contactIdMeta),
      );
    } else if (isInserting) {
      context.missing(_contactIdMeta);
    }
    if (data.containsKey('record_id')) {
      context.handle(
        _recordIdMeta,
        recordId.isAcceptableOrUnknown(data['record_id']!, _recordIdMeta),
      );
    } else if (isInserting) {
      context.missing(_recordIdMeta);
    }
    if (data.containsKey('channel')) {
      context.handle(
        _channelMeta,
        channel.isAcceptableOrUnknown(data['channel']!, _channelMeta),
      );
    } else if (isInserting) {
      context.missing(_channelMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {contactId};
  @override
  DbRecordContact map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DbRecordContact(
      contactId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}contact_id'],
      )!,
      recordId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}record_id'],
      )!,
      channel: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}channel'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $DbRecordContactsTable createAlias(String alias) {
    return $DbRecordContactsTable(attachedDatabase, alias);
  }
}

class DbRecordContact extends DataClass implements Insertable<DbRecordContact> {
  final String contactId;
  final String recordId;
  final String channel;
  final String value;
  final DateTime createdAt;
  const DbRecordContact({
    required this.contactId,
    required this.recordId,
    required this.channel,
    required this.value,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['contact_id'] = Variable<String>(contactId);
    map['record_id'] = Variable<String>(recordId);
    map['channel'] = Variable<String>(channel);
    map['value'] = Variable<String>(value);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  DbRecordContactsCompanion toCompanion(bool nullToAbsent) {
    return DbRecordContactsCompanion(
      contactId: Value(contactId),
      recordId: Value(recordId),
      channel: Value(channel),
      value: Value(value),
      createdAt: Value(createdAt),
    );
  }

  factory DbRecordContact.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DbRecordContact(
      contactId: serializer.fromJson<String>(json['contactId']),
      recordId: serializer.fromJson<String>(json['recordId']),
      channel: serializer.fromJson<String>(json['channel']),
      value: serializer.fromJson<String>(json['value']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'contactId': serializer.toJson<String>(contactId),
      'recordId': serializer.toJson<String>(recordId),
      'channel': serializer.toJson<String>(channel),
      'value': serializer.toJson<String>(value),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  DbRecordContact copyWith({
    String? contactId,
    String? recordId,
    String? channel,
    String? value,
    DateTime? createdAt,
  }) => DbRecordContact(
    contactId: contactId ?? this.contactId,
    recordId: recordId ?? this.recordId,
    channel: channel ?? this.channel,
    value: value ?? this.value,
    createdAt: createdAt ?? this.createdAt,
  );
  DbRecordContact copyWithCompanion(DbRecordContactsCompanion data) {
    return DbRecordContact(
      contactId: data.contactId.present ? data.contactId.value : this.contactId,
      recordId: data.recordId.present ? data.recordId.value : this.recordId,
      channel: data.channel.present ? data.channel.value : this.channel,
      value: data.value.present ? data.value.value : this.value,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DbRecordContact(')
          ..write('contactId: $contactId, ')
          ..write('recordId: $recordId, ')
          ..write('channel: $channel, ')
          ..write('value: $value, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(contactId, recordId, channel, value, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DbRecordContact &&
          other.contactId == this.contactId &&
          other.recordId == this.recordId &&
          other.channel == this.channel &&
          other.value == this.value &&
          other.createdAt == this.createdAt);
}

class DbRecordContactsCompanion extends UpdateCompanion<DbRecordContact> {
  final Value<String> contactId;
  final Value<String> recordId;
  final Value<String> channel;
  final Value<String> value;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const DbRecordContactsCompanion({
    this.contactId = const Value.absent(),
    this.recordId = const Value.absent(),
    this.channel = const Value.absent(),
    this.value = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DbRecordContactsCompanion.insert({
    required String contactId,
    required String recordId,
    required String channel,
    required String value,
    required DateTime createdAt,
    this.rowid = const Value.absent(),
  }) : contactId = Value(contactId),
       recordId = Value(recordId),
       channel = Value(channel),
       value = Value(value),
       createdAt = Value(createdAt);
  static Insertable<DbRecordContact> custom({
    Expression<String>? contactId,
    Expression<String>? recordId,
    Expression<String>? channel,
    Expression<String>? value,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (contactId != null) 'contact_id': contactId,
      if (recordId != null) 'record_id': recordId,
      if (channel != null) 'channel': channel,
      if (value != null) 'value': value,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DbRecordContactsCompanion copyWith({
    Value<String>? contactId,
    Value<String>? recordId,
    Value<String>? channel,
    Value<String>? value,
    Value<DateTime>? createdAt,
    Value<int>? rowid,
  }) {
    return DbRecordContactsCompanion(
      contactId: contactId ?? this.contactId,
      recordId: recordId ?? this.recordId,
      channel: channel ?? this.channel,
      value: value ?? this.value,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (contactId.present) {
      map['contact_id'] = Variable<String>(contactId.value);
    }
    if (recordId.present) {
      map['record_id'] = Variable<String>(recordId.value);
    }
    if (channel.present) {
      map['channel'] = Variable<String>(channel.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DbRecordContactsCompanion(')
          ..write('contactId: $contactId, ')
          ..write('recordId: $recordId, ')
          ..write('channel: $channel, ')
          ..write('value: $value, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $DbAppSettingsTable extends DbAppSettings
    with TableInfo<$DbAppSettingsTable, DbAppSetting> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DbAppSettingsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [key, value];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'db_app_settings';
  @override
  VerificationContext validateIntegrity(
    Insertable<DbAppSetting> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  DbAppSetting map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DbAppSetting(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      )!,
    );
  }

  @override
  $DbAppSettingsTable createAlias(String alias) {
    return $DbAppSettingsTable(attachedDatabase, alias);
  }
}

class DbAppSetting extends DataClass implements Insertable<DbAppSetting> {
  final String key;
  final String value;
  const DbAppSetting({required this.key, required this.value});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    return map;
  }

  DbAppSettingsCompanion toCompanion(bool nullToAbsent) {
    return DbAppSettingsCompanion(key: Value(key), value: Value(value));
  }

  factory DbAppSetting.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DbAppSetting(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
    };
  }

  DbAppSetting copyWith({String? key, String? value}) =>
      DbAppSetting(key: key ?? this.key, value: value ?? this.value);
  DbAppSetting copyWithCompanion(DbAppSettingsCompanion data) {
    return DbAppSetting(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DbAppSetting(')
          ..write('key: $key, ')
          ..write('value: $value')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DbAppSetting &&
          other.key == this.key &&
          other.value == this.value);
}

class DbAppSettingsCompanion extends UpdateCompanion<DbAppSetting> {
  final Value<String> key;
  final Value<String> value;
  final Value<int> rowid;
  const DbAppSettingsCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DbAppSettingsCompanion.insert({
    required String key,
    required String value,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       value = Value(value);
  static Insertable<DbAppSetting> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DbAppSettingsCompanion copyWith({
    Value<String>? key,
    Value<String>? value,
    Value<int>? rowid,
  }) {
    return DbAppSettingsCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DbAppSettingsCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $DbSecurityEventsTable extends DbSecurityEvents
    with TableInfo<$DbSecurityEventsTable, DbSecurityEvent> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DbSecurityEventsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _eventIdMeta = const VerificationMeta(
    'eventId',
  );
  @override
  late final GeneratedColumn<String> eventId = GeneratedColumn<String>(
    'event_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _eventTypeMeta = const VerificationMeta(
    'eventType',
  );
  @override
  late final GeneratedColumn<String> eventType = GeneratedColumn<String>(
    'event_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _eventDetailJsonMeta = const VerificationMeta(
    'eventDetailJson',
  );
  @override
  late final GeneratedColumn<String> eventDetailJson = GeneratedColumn<String>(
    'event_detail_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
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
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    eventId,
    userId,
    eventType,
    eventDetailJson,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'db_security_events';
  @override
  VerificationContext validateIntegrity(
    Insertable<DbSecurityEvent> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('event_id')) {
      context.handle(
        _eventIdMeta,
        eventId.isAcceptableOrUnknown(data['event_id']!, _eventIdMeta),
      );
    } else if (isInserting) {
      context.missing(_eventIdMeta);
    }
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    }
    if (data.containsKey('event_type')) {
      context.handle(
        _eventTypeMeta,
        eventType.isAcceptableOrUnknown(data['event_type']!, _eventTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_eventTypeMeta);
    }
    if (data.containsKey('event_detail_json')) {
      context.handle(
        _eventDetailJsonMeta,
        eventDetailJson.isAcceptableOrUnknown(
          data['event_detail_json']!,
          _eventDetailJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_eventDetailJsonMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {eventId};
  @override
  DbSecurityEvent map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DbSecurityEvent(
      eventId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}event_id'],
      )!,
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      ),
      eventType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}event_type'],
      )!,
      eventDetailJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}event_detail_json'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $DbSecurityEventsTable createAlias(String alias) {
    return $DbSecurityEventsTable(attachedDatabase, alias);
  }
}

class DbSecurityEvent extends DataClass implements Insertable<DbSecurityEvent> {
  final String eventId;
  final String? userId;
  final String eventType;
  final String eventDetailJson;
  final DateTime createdAt;
  const DbSecurityEvent({
    required this.eventId,
    this.userId,
    required this.eventType,
    required this.eventDetailJson,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['event_id'] = Variable<String>(eventId);
    if (!nullToAbsent || userId != null) {
      map['user_id'] = Variable<String>(userId);
    }
    map['event_type'] = Variable<String>(eventType);
    map['event_detail_json'] = Variable<String>(eventDetailJson);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  DbSecurityEventsCompanion toCompanion(bool nullToAbsent) {
    return DbSecurityEventsCompanion(
      eventId: Value(eventId),
      userId: userId == null && nullToAbsent
          ? const Value.absent()
          : Value(userId),
      eventType: Value(eventType),
      eventDetailJson: Value(eventDetailJson),
      createdAt: Value(createdAt),
    );
  }

  factory DbSecurityEvent.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DbSecurityEvent(
      eventId: serializer.fromJson<String>(json['eventId']),
      userId: serializer.fromJson<String?>(json['userId']),
      eventType: serializer.fromJson<String>(json['eventType']),
      eventDetailJson: serializer.fromJson<String>(json['eventDetailJson']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'eventId': serializer.toJson<String>(eventId),
      'userId': serializer.toJson<String?>(userId),
      'eventType': serializer.toJson<String>(eventType),
      'eventDetailJson': serializer.toJson<String>(eventDetailJson),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  DbSecurityEvent copyWith({
    String? eventId,
    Value<String?> userId = const Value.absent(),
    String? eventType,
    String? eventDetailJson,
    DateTime? createdAt,
  }) => DbSecurityEvent(
    eventId: eventId ?? this.eventId,
    userId: userId.present ? userId.value : this.userId,
    eventType: eventType ?? this.eventType,
    eventDetailJson: eventDetailJson ?? this.eventDetailJson,
    createdAt: createdAt ?? this.createdAt,
  );
  DbSecurityEvent copyWithCompanion(DbSecurityEventsCompanion data) {
    return DbSecurityEvent(
      eventId: data.eventId.present ? data.eventId.value : this.eventId,
      userId: data.userId.present ? data.userId.value : this.userId,
      eventType: data.eventType.present ? data.eventType.value : this.eventType,
      eventDetailJson: data.eventDetailJson.present
          ? data.eventDetailJson.value
          : this.eventDetailJson,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DbSecurityEvent(')
          ..write('eventId: $eventId, ')
          ..write('userId: $userId, ')
          ..write('eventType: $eventType, ')
          ..write('eventDetailJson: $eventDetailJson, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(eventId, userId, eventType, eventDetailJson, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DbSecurityEvent &&
          other.eventId == this.eventId &&
          other.userId == this.userId &&
          other.eventType == this.eventType &&
          other.eventDetailJson == this.eventDetailJson &&
          other.createdAt == this.createdAt);
}

class DbSecurityEventsCompanion extends UpdateCompanion<DbSecurityEvent> {
  final Value<String> eventId;
  final Value<String?> userId;
  final Value<String> eventType;
  final Value<String> eventDetailJson;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const DbSecurityEventsCompanion({
    this.eventId = const Value.absent(),
    this.userId = const Value.absent(),
    this.eventType = const Value.absent(),
    this.eventDetailJson = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DbSecurityEventsCompanion.insert({
    required String eventId,
    this.userId = const Value.absent(),
    required String eventType,
    required String eventDetailJson,
    required DateTime createdAt,
    this.rowid = const Value.absent(),
  }) : eventId = Value(eventId),
       eventType = Value(eventType),
       eventDetailJson = Value(eventDetailJson),
       createdAt = Value(createdAt);
  static Insertable<DbSecurityEvent> custom({
    Expression<String>? eventId,
    Expression<String>? userId,
    Expression<String>? eventType,
    Expression<String>? eventDetailJson,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (eventId != null) 'event_id': eventId,
      if (userId != null) 'user_id': userId,
      if (eventType != null) 'event_type': eventType,
      if (eventDetailJson != null) 'event_detail_json': eventDetailJson,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DbSecurityEventsCompanion copyWith({
    Value<String>? eventId,
    Value<String?>? userId,
    Value<String>? eventType,
    Value<String>? eventDetailJson,
    Value<DateTime>? createdAt,
    Value<int>? rowid,
  }) {
    return DbSecurityEventsCompanion(
      eventId: eventId ?? this.eventId,
      userId: userId ?? this.userId,
      eventType: eventType ?? this.eventType,
      eventDetailJson: eventDetailJson ?? this.eventDetailJson,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (eventId.present) {
      map['event_id'] = Variable<String>(eventId.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (eventType.present) {
      map['event_type'] = Variable<String>(eventType.value);
    }
    if (eventDetailJson.present) {
      map['event_detail_json'] = Variable<String>(eventDetailJson.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DbSecurityEventsCompanion(')
          ..write('eventId: $eventId, ')
          ..write('userId: $userId, ')
          ..write('eventType: $eventType, ')
          ..write('eventDetailJson: $eventDetailJson, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$LocalDatabase extends GeneratedDatabase {
  _$LocalDatabase(QueryExecutor e) : super(e);
  $LocalDatabaseManager get managers => $LocalDatabaseManager(this);
  late final $DbSyncOutboxTable dbSyncOutbox = $DbSyncOutboxTable(this);
  late final $DbContactRecordsTable dbContactRecords = $DbContactRecordsTable(
    this,
  );
  late final $DbSyncDrainerLeasesTable dbSyncDrainerLeases =
      $DbSyncDrainerLeasesTable(this);
  late final $DbSyncScopesTable dbSyncScopes = $DbSyncScopesTable(this);
  late final $DbContactRevisionsTable dbContactRevisions =
      $DbContactRevisionsTable(this);
  late final $DbContactAnswersTable dbContactAnswers = $DbContactAnswersTable(
    this,
  );
  late final $DbContactDraftsTable dbContactDrafts = $DbContactDraftsTable(
    this,
  );
  late final $DbContactDraftAnswersTable dbContactDraftAnswers =
      $DbContactDraftAnswersTable(this);
  late final Index contactDraftsOwnerUpdated = Index(
    'contact_drafts_owner_updated',
    'CREATE INDEX contact_drafts_owner_updated ON db_contact_drafts (app_user_id, abandoned_at_utc, updated_at_utc)',
  );
  late final Index contactRecordsPersonalPeriod = Index(
    'contact_records_personal_period',
    'CREATE INDEX contact_records_personal_period ON db_contact_records (app_user_id, workspace_id, project_id, occurred_at_utc)',
  );
  late final Index syncOutboxReady = Index(
    'sync_outbox_ready',
    'CREATE INDEX sync_outbox_ready ON db_sync_outbox (status, next_attempt_at_utc, created_at_utc)',
  );
  late final Index syncOutboxAggregateOrder = Index(
    'sync_outbox_aggregate_order',
    'CREATE INDEX sync_outbox_aggregate_order ON db_sync_outbox (aggregate_id, created_at_utc)',
  );
  late final $DbUsersTable dbUsers = $DbUsersTable(this);
  late final $DbConversationRecordsTable dbConversationRecords =
      $DbConversationRecordsTable(this);
  late final $DbRecordContactsTable dbRecordContacts = $DbRecordContactsTable(
    this,
  );
  late final $DbAppSettingsTable dbAppSettings = $DbAppSettingsTable(this);
  late final $DbSecurityEventsTable dbSecurityEvents = $DbSecurityEventsTable(
    this,
  );
  Selectable<DbSyncOutboxData> readReadySyncCommand(
    String appUserId,
    String workspaceId,
    String projectId,
    DateTime nowUtc,
  ) {
    return customSelect(
      'SELECT outbox.* FROM db_sync_outbox AS outbox JOIN db_contact_records AS contact ON contact.contact_id = outbox.aggregate_id WHERE contact.app_user_id = ?1 AND contact.workspace_id = ?2 AND contact.project_id = ?3 AND outbox.status = \'pending\' AND outbox.next_attempt_at_utc <= ?4 AND NOT EXISTS (SELECT 1 AS _c0 FROM db_sync_outbox AS earlier WHERE earlier.aggregate_id = outbox.aggregate_id AND earlier.status != \'completed\' AND(earlier.created_at_utc < outbox.created_at_utc OR(earlier.created_at_utc = outbox.created_at_utc AND earlier.command_id < outbox.command_id))) ORDER BY outbox.created_at_utc, outbox.command_id LIMIT 1',
      variables: [
        Variable<String>(appUserId),
        Variable<String>(workspaceId),
        Variable<String>(projectId),
        Variable<DateTime>(nowUtc),
      ],
      readsFrom: {dbSyncOutbox, dbContactRecords},
    ).asyncMap(dbSyncOutbox.mapFromRow);
  }

  Selectable<ReadSyncHealthResult> readSyncHealth(
    String appUserId,
    String workspaceId,
    String projectId,
  ) {
    return customSelect(
      'WITH contact_sync AS (SELECT contact.contact_id, CASE WHEN COUNT(outbox.command_id) = 0 THEN \'completed\' WHEN SUM(CASE WHEN outbox.status = \'permanent_failure\' THEN 1 ELSE 0 END) > 0 THEN \'permanent_failure\' WHEN SUM(CASE WHEN outbox.status = \'needs_resolution\' THEN 1 ELSE 0 END) > 0 THEN \'needs_resolution\' WHEN SUM(CASE WHEN outbox.status = \'leased\' THEN 1 ELSE 0 END) > 0 THEN \'syncing\' WHEN SUM(CASE WHEN outbox.status = \'pending\' AND outbox.attempt_count > 0 THEN 1 ELSE 0 END) > 0 THEN \'retrying\' WHEN SUM(CASE WHEN outbox.status = \'pending\' AND outbox.attempt_count = 0 THEN 1 ELSE 0 END) > 0 THEN \'only_on_device\' ELSE \'completed\' END AS contact_status, MIN(CASE WHEN outbox.status IS NOT NULL AND outbox.status != \'completed\' THEN outbox.created_at_utc ELSE NULL END) AS oldest_pending_at_utc FROM db_contact_records AS contact LEFT JOIN db_sync_outbox AS outbox ON outbox.aggregate_id = contact.contact_id WHERE contact.app_user_id = ?1 AND contact.workspace_id = ?2 AND contact.project_id = ?3 GROUP BY contact.contact_id) SELECT COALESCE(SUM(CASE WHEN contact_status = \'only_on_device\' THEN 1 ELSE 0 END), 0) AS only_on_device_count, COALESCE(SUM(CASE WHEN contact_status = \'syncing\' THEN 1 ELSE 0 END), 0) AS syncing_count, COALESCE(SUM(CASE WHEN contact_status = \'retrying\' THEN 1 ELSE 0 END), 0) AS retrying_count, COALESCE(SUM(CASE WHEN contact_status = \'needs_resolution\' THEN 1 ELSE 0 END), 0) AS needs_resolution_count, COALESCE(SUM(CASE WHEN contact_status = \'permanent_failure\' THEN 1 ELSE 0 END), 0) AS permanent_failure_count, COALESCE(SUM(CASE WHEN contact_status = \'completed\' THEN 1 ELSE 0 END), 0) AS completed_count, MIN(oldest_pending_at_utc) AS oldest_pending_at_utc FROM contact_sync',
      variables: [
        Variable<String>(appUserId),
        Variable<String>(workspaceId),
        Variable<String>(projectId),
      ],
      readsFrom: {dbContactRecords, dbSyncOutbox},
    ).map(
      (QueryRow row) => ReadSyncHealthResult(
        onlyOnDeviceCount: row.read<int>('only_on_device_count'),
        syncingCount: row.read<int>('syncing_count'),
        retryingCount: row.read<int>('retrying_count'),
        needsResolutionCount: row.read<int>('needs_resolution_count'),
        permanentFailureCount: row.read<int>('permanent_failure_count'),
        completedCount: row.read<int>('completed_count'),
        oldestPendingAtUtc: row.readNullable<DateTime>('oldest_pending_at_utc'),
      ),
    );
  }

  Selectable<ReadPersonalContactSummaryResult> readPersonalContactSummary(
    String appUserId,
    String workspaceId,
    String projectId,
    DateTime fromUtc,
    DateTime untilUtc,
  ) {
    return customSelect(
      'SELECT COUNT(*) AS contact_session_count, COALESCE(SUM(contact.reach_count), 0) AS reach_count, COALESCE(SUM(CASE WHEN contact.interest_level = 0 THEN 1 ELSE 0 END), 0) AS interest_0_count, COALESCE(SUM(CASE WHEN contact.interest_level = 1 THEN 1 ELSE 0 END), 0) AS interest_1_count, COALESCE(SUM(CASE WHEN contact.interest_level = 2 THEN 1 ELSE 0 END), 0) AS interest_2_count, COALESCE(SUM(CASE WHEN contact.interest_level = 3 THEN 1 ELSE 0 END), 0) AS interest_3_count, COALESCE(SUM(CASE WHEN contact.interest_level = 4 THEN 1 ELSE 0 END), 0) AS interest_4_count, COALESCE(SUM(CASE WHEN EXISTS (SELECT 1 AS _c0 FROM db_sync_outbox AS outbox WHERE outbox.aggregate_id = contact.contact_id AND outbox.status != \'completed\') THEN 1 ELSE 0 END), 0) AS pending_sync_count, MAX(contact.occurred_at_utc) AS latest_occurred_at_utc FROM db_contact_records AS contact WHERE contact.app_user_id = ?1 AND contact.workspace_id = ?2 AND contact.project_id = ?3 AND contact.occurred_at_utc >= ?4 AND contact.occurred_at_utc < ?5 AND contact.lifecycle_status = \'active\'',
      variables: [
        Variable<String>(appUserId),
        Variable<String>(workspaceId),
        Variable<String>(projectId),
        Variable<DateTime>(fromUtc),
        Variable<DateTime>(untilUtc),
      ],
      readsFrom: {dbContactRecords, dbSyncOutbox},
    ).map(
      (QueryRow row) => ReadPersonalContactSummaryResult(
        contactSessionCount: row.read<int>('contact_session_count'),
        reachCount: row.read<int>('reach_count'),
        interest0Count: row.read<int>('interest_0_count'),
        interest1Count: row.read<int>('interest_1_count'),
        interest2Count: row.read<int>('interest_2_count'),
        interest3Count: row.read<int>('interest_3_count'),
        interest4Count: row.read<int>('interest_4_count'),
        pendingSyncCount: row.read<int>('pending_sync_count'),
        latestOccurredAtUtc: row.readNullable<DateTime>(
          'latest_occurred_at_utc',
        ),
      ),
    );
  }

  Selectable<ReadPersonalContactChannelSummaryResult>
  readPersonalContactChannelSummary(
    String appUserId,
    String workspaceId,
    String projectId,
    DateTime fromUtc,
    DateTime untilUtc,
  ) {
    return customSelect(
      'SELECT contact.channel AS channel, COUNT(*) AS contact_session_count FROM db_contact_records AS contact WHERE contact.app_user_id = ?1 AND contact.workspace_id = ?2 AND contact.project_id = ?3 AND contact.occurred_at_utc >= ?4 AND contact.occurred_at_utc < ?5 AND contact.lifecycle_status = \'active\' GROUP BY contact.channel ORDER BY contact.channel',
      variables: [
        Variable<String>(appUserId),
        Variable<String>(workspaceId),
        Variable<String>(projectId),
        Variable<DateTime>(fromUtc),
        Variable<DateTime>(untilUtc),
      ],
      readsFrom: {dbContactRecords},
    ).map(
      (QueryRow row) => ReadPersonalContactChannelSummaryResult(
        channel: row.read<String>('channel'),
        contactSessionCount: row.read<int>('contact_session_count'),
      ),
    );
  }

  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    dbSyncOutbox,
    dbContactRecords,
    dbSyncDrainerLeases,
    dbSyncScopes,
    dbContactRevisions,
    dbContactAnswers,
    dbContactDrafts,
    dbContactDraftAnswers,
    contactDraftsOwnerUpdated,
    contactRecordsPersonalPeriod,
    syncOutboxReady,
    syncOutboxAggregateOrder,
    dbUsers,
    dbConversationRecords,
    dbRecordContacts,
    dbAppSettings,
    dbSecurityEvents,
  ];
}

typedef $$DbSyncOutboxTableCreateCompanionBuilder =
    DbSyncOutboxCompanion Function({
      required String commandId,
      required int protocolVersion,
      required String commandType,
      required String deviceId,
      required String aggregateId,
      required int baseRevision,
      required String payloadJson,
      required DateTime createdAtUtc,
      required String status,
      Value<int> attemptCount,
      required DateTime nextAttemptAtUtc,
      Value<String?> leaseOwner,
      Value<DateTime?> leaseExpiresAtUtc,
      Value<String?> lastFailureCode,
      Value<DateTime?> completedAtUtc,
      Value<int> rowid,
    });
typedef $$DbSyncOutboxTableUpdateCompanionBuilder =
    DbSyncOutboxCompanion Function({
      Value<String> commandId,
      Value<int> protocolVersion,
      Value<String> commandType,
      Value<String> deviceId,
      Value<String> aggregateId,
      Value<int> baseRevision,
      Value<String> payloadJson,
      Value<DateTime> createdAtUtc,
      Value<String> status,
      Value<int> attemptCount,
      Value<DateTime> nextAttemptAtUtc,
      Value<String?> leaseOwner,
      Value<DateTime?> leaseExpiresAtUtc,
      Value<String?> lastFailureCode,
      Value<DateTime?> completedAtUtc,
      Value<int> rowid,
    });

class $$DbSyncOutboxTableFilterComposer
    extends Composer<_$LocalDatabase, $DbSyncOutboxTable> {
  $$DbSyncOutboxTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get commandId => $composableBuilder(
    column: $table.commandId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get protocolVersion => $composableBuilder(
    column: $table.protocolVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get commandType => $composableBuilder(
    column: $table.commandType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get aggregateId => $composableBuilder(
    column: $table.aggregateId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get baseRevision => $composableBuilder(
    column: $table.baseRevision,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAtUtc => $composableBuilder(
    column: $table.createdAtUtc,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get attemptCount => $composableBuilder(
    column: $table.attemptCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get nextAttemptAtUtc => $composableBuilder(
    column: $table.nextAttemptAtUtc,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get leaseOwner => $composableBuilder(
    column: $table.leaseOwner,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get leaseExpiresAtUtc => $composableBuilder(
    column: $table.leaseExpiresAtUtc,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastFailureCode => $composableBuilder(
    column: $table.lastFailureCode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get completedAtUtc => $composableBuilder(
    column: $table.completedAtUtc,
    builder: (column) => ColumnFilters(column),
  );
}

class $$DbSyncOutboxTableOrderingComposer
    extends Composer<_$LocalDatabase, $DbSyncOutboxTable> {
  $$DbSyncOutboxTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get commandId => $composableBuilder(
    column: $table.commandId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get protocolVersion => $composableBuilder(
    column: $table.protocolVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get commandType => $composableBuilder(
    column: $table.commandType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get aggregateId => $composableBuilder(
    column: $table.aggregateId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get baseRevision => $composableBuilder(
    column: $table.baseRevision,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAtUtc => $composableBuilder(
    column: $table.createdAtUtc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get attemptCount => $composableBuilder(
    column: $table.attemptCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get nextAttemptAtUtc => $composableBuilder(
    column: $table.nextAttemptAtUtc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get leaseOwner => $composableBuilder(
    column: $table.leaseOwner,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get leaseExpiresAtUtc => $composableBuilder(
    column: $table.leaseExpiresAtUtc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastFailureCode => $composableBuilder(
    column: $table.lastFailureCode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get completedAtUtc => $composableBuilder(
    column: $table.completedAtUtc,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$DbSyncOutboxTableAnnotationComposer
    extends Composer<_$LocalDatabase, $DbSyncOutboxTable> {
  $$DbSyncOutboxTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get commandId =>
      $composableBuilder(column: $table.commandId, builder: (column) => column);

  GeneratedColumn<int> get protocolVersion => $composableBuilder(
    column: $table.protocolVersion,
    builder: (column) => column,
  );

  GeneratedColumn<String> get commandType => $composableBuilder(
    column: $table.commandType,
    builder: (column) => column,
  );

  GeneratedColumn<String> get deviceId =>
      $composableBuilder(column: $table.deviceId, builder: (column) => column);

  GeneratedColumn<String> get aggregateId => $composableBuilder(
    column: $table.aggregateId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get baseRevision => $composableBuilder(
    column: $table.baseRevision,
    builder: (column) => column,
  );

  GeneratedColumn<String> get payloadJson => $composableBuilder(
    column: $table.payloadJson,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAtUtc => $composableBuilder(
    column: $table.createdAtUtc,
    builder: (column) => column,
  );

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<int> get attemptCount => $composableBuilder(
    column: $table.attemptCount,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get nextAttemptAtUtc => $composableBuilder(
    column: $table.nextAttemptAtUtc,
    builder: (column) => column,
  );

  GeneratedColumn<String> get leaseOwner => $composableBuilder(
    column: $table.leaseOwner,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get leaseExpiresAtUtc => $composableBuilder(
    column: $table.leaseExpiresAtUtc,
    builder: (column) => column,
  );

  GeneratedColumn<String> get lastFailureCode => $composableBuilder(
    column: $table.lastFailureCode,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get completedAtUtc => $composableBuilder(
    column: $table.completedAtUtc,
    builder: (column) => column,
  );
}

class $$DbSyncOutboxTableTableManager
    extends
        RootTableManager<
          _$LocalDatabase,
          $DbSyncOutboxTable,
          DbSyncOutboxData,
          $$DbSyncOutboxTableFilterComposer,
          $$DbSyncOutboxTableOrderingComposer,
          $$DbSyncOutboxTableAnnotationComposer,
          $$DbSyncOutboxTableCreateCompanionBuilder,
          $$DbSyncOutboxTableUpdateCompanionBuilder,
          (
            DbSyncOutboxData,
            BaseReferences<
              _$LocalDatabase,
              $DbSyncOutboxTable,
              DbSyncOutboxData
            >,
          ),
          DbSyncOutboxData,
          PrefetchHooks Function()
        > {
  $$DbSyncOutboxTableTableManager(_$LocalDatabase db, $DbSyncOutboxTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DbSyncOutboxTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DbSyncOutboxTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DbSyncOutboxTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> commandId = const Value.absent(),
                Value<int> protocolVersion = const Value.absent(),
                Value<String> commandType = const Value.absent(),
                Value<String> deviceId = const Value.absent(),
                Value<String> aggregateId = const Value.absent(),
                Value<int> baseRevision = const Value.absent(),
                Value<String> payloadJson = const Value.absent(),
                Value<DateTime> createdAtUtc = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<int> attemptCount = const Value.absent(),
                Value<DateTime> nextAttemptAtUtc = const Value.absent(),
                Value<String?> leaseOwner = const Value.absent(),
                Value<DateTime?> leaseExpiresAtUtc = const Value.absent(),
                Value<String?> lastFailureCode = const Value.absent(),
                Value<DateTime?> completedAtUtc = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DbSyncOutboxCompanion(
                commandId: commandId,
                protocolVersion: protocolVersion,
                commandType: commandType,
                deviceId: deviceId,
                aggregateId: aggregateId,
                baseRevision: baseRevision,
                payloadJson: payloadJson,
                createdAtUtc: createdAtUtc,
                status: status,
                attemptCount: attemptCount,
                nextAttemptAtUtc: nextAttemptAtUtc,
                leaseOwner: leaseOwner,
                leaseExpiresAtUtc: leaseExpiresAtUtc,
                lastFailureCode: lastFailureCode,
                completedAtUtc: completedAtUtc,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String commandId,
                required int protocolVersion,
                required String commandType,
                required String deviceId,
                required String aggregateId,
                required int baseRevision,
                required String payloadJson,
                required DateTime createdAtUtc,
                required String status,
                Value<int> attemptCount = const Value.absent(),
                required DateTime nextAttemptAtUtc,
                Value<String?> leaseOwner = const Value.absent(),
                Value<DateTime?> leaseExpiresAtUtc = const Value.absent(),
                Value<String?> lastFailureCode = const Value.absent(),
                Value<DateTime?> completedAtUtc = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DbSyncOutboxCompanion.insert(
                commandId: commandId,
                protocolVersion: protocolVersion,
                commandType: commandType,
                deviceId: deviceId,
                aggregateId: aggregateId,
                baseRevision: baseRevision,
                payloadJson: payloadJson,
                createdAtUtc: createdAtUtc,
                status: status,
                attemptCount: attemptCount,
                nextAttemptAtUtc: nextAttemptAtUtc,
                leaseOwner: leaseOwner,
                leaseExpiresAtUtc: leaseExpiresAtUtc,
                lastFailureCode: lastFailureCode,
                completedAtUtc: completedAtUtc,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$DbSyncOutboxTableProcessedTableManager =
    ProcessedTableManager<
      _$LocalDatabase,
      $DbSyncOutboxTable,
      DbSyncOutboxData,
      $$DbSyncOutboxTableFilterComposer,
      $$DbSyncOutboxTableOrderingComposer,
      $$DbSyncOutboxTableAnnotationComposer,
      $$DbSyncOutboxTableCreateCompanionBuilder,
      $$DbSyncOutboxTableUpdateCompanionBuilder,
      (
        DbSyncOutboxData,
        BaseReferences<_$LocalDatabase, $DbSyncOutboxTable, DbSyncOutboxData>,
      ),
      DbSyncOutboxData,
      PrefetchHooks Function()
    >;
typedef $$DbContactRecordsTableCreateCompanionBuilder =
    DbContactRecordsCompanion Function({
      required String contactId,
      required String appUserId,
      required String workspaceId,
      required String projectId,
      required String questionnaireVersionId,
      required DateTime occurredAtUtc,
      required String occurredTimeZone,
      required DateTime firstSubmittedAtUtc,
      required String channel,
      Value<String?> channelDetail,
      required String locationKind,
      Value<String?> placeName,
      Value<String?> smallestRegionId,
      Value<double?> latitude,
      Value<double?> longitude,
      Value<double?> locationAccuracyMeters,
      required int reachCount,
      required int interestLevel,
      required int currentRevision,
      required String lifecycleStatus,
      Value<int> rowid,
    });
typedef $$DbContactRecordsTableUpdateCompanionBuilder =
    DbContactRecordsCompanion Function({
      Value<String> contactId,
      Value<String> appUserId,
      Value<String> workspaceId,
      Value<String> projectId,
      Value<String> questionnaireVersionId,
      Value<DateTime> occurredAtUtc,
      Value<String> occurredTimeZone,
      Value<DateTime> firstSubmittedAtUtc,
      Value<String> channel,
      Value<String?> channelDetail,
      Value<String> locationKind,
      Value<String?> placeName,
      Value<String?> smallestRegionId,
      Value<double?> latitude,
      Value<double?> longitude,
      Value<double?> locationAccuracyMeters,
      Value<int> reachCount,
      Value<int> interestLevel,
      Value<int> currentRevision,
      Value<String> lifecycleStatus,
      Value<int> rowid,
    });

final class $$DbContactRecordsTableReferences
    extends
        BaseReferences<
          _$LocalDatabase,
          $DbContactRecordsTable,
          DbContactRecord
        > {
  $$DbContactRecordsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static MultiTypedResultKey<$DbContactRevisionsTable, List<DbContactRevision>>
  _dbContactRevisionsRefsTable(_$LocalDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.dbContactRevisions,
        aliasName:
            'db_contact_records__contact_id__db_contact_revisions__contact_id',
      );

  $$DbContactRevisionsTableProcessedTableManager get dbContactRevisionsRefs {
    final manager =
        $$DbContactRevisionsTableTableManager(
          $_db,
          $_db.dbContactRevisions,
        ).filter(
          (f) => f.contactId.contactId.sqlEquals(
            $_itemColumn<String>('contact_id')!,
          ),
        );

    final cache = $_typedResult.readTableOrNull(
      _dbContactRevisionsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$DbContactAnswersTable, List<DbContactAnswer>>
  _dbContactAnswersRefsTable(_$LocalDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.dbContactAnswers,
        aliasName:
            'db_contact_records__contact_id__db_contact_answers__contact_id',
      );

  $$DbContactAnswersTableProcessedTableManager get dbContactAnswersRefs {
    final manager =
        $$DbContactAnswersTableTableManager($_db, $_db.dbContactAnswers).filter(
          (f) => f.contactId.contactId.sqlEquals(
            $_itemColumn<String>('contact_id')!,
          ),
        );

    final cache = $_typedResult.readTableOrNull(
      _dbContactAnswersRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$DbContactRecordsTableFilterComposer
    extends Composer<_$LocalDatabase, $DbContactRecordsTable> {
  $$DbContactRecordsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get contactId => $composableBuilder(
    column: $table.contactId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get appUserId => $composableBuilder(
    column: $table.appUserId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get workspaceId => $composableBuilder(
    column: $table.workspaceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get projectId => $composableBuilder(
    column: $table.projectId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get questionnaireVersionId => $composableBuilder(
    column: $table.questionnaireVersionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get occurredAtUtc => $composableBuilder(
    column: $table.occurredAtUtc,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get occurredTimeZone => $composableBuilder(
    column: $table.occurredTimeZone,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get firstSubmittedAtUtc => $composableBuilder(
    column: $table.firstSubmittedAtUtc,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get channel => $composableBuilder(
    column: $table.channel,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get channelDetail => $composableBuilder(
    column: $table.channelDetail,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get locationKind => $composableBuilder(
    column: $table.locationKind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get placeName => $composableBuilder(
    column: $table.placeName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get smallestRegionId => $composableBuilder(
    column: $table.smallestRegionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get latitude => $composableBuilder(
    column: $table.latitude,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get longitude => $composableBuilder(
    column: $table.longitude,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get locationAccuracyMeters => $composableBuilder(
    column: $table.locationAccuracyMeters,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get reachCount => $composableBuilder(
    column: $table.reachCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get interestLevel => $composableBuilder(
    column: $table.interestLevel,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get currentRevision => $composableBuilder(
    column: $table.currentRevision,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lifecycleStatus => $composableBuilder(
    column: $table.lifecycleStatus,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> dbContactRevisionsRefs(
    Expression<bool> Function($$DbContactRevisionsTableFilterComposer f) f,
  ) {
    final $$DbContactRevisionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.contactId,
      referencedTable: $db.dbContactRevisions,
      getReferencedColumn: (t) => t.contactId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DbContactRevisionsTableFilterComposer(
            $db: $db,
            $table: $db.dbContactRevisions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> dbContactAnswersRefs(
    Expression<bool> Function($$DbContactAnswersTableFilterComposer f) f,
  ) {
    final $$DbContactAnswersTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.contactId,
      referencedTable: $db.dbContactAnswers,
      getReferencedColumn: (t) => t.contactId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DbContactAnswersTableFilterComposer(
            $db: $db,
            $table: $db.dbContactAnswers,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$DbContactRecordsTableOrderingComposer
    extends Composer<_$LocalDatabase, $DbContactRecordsTable> {
  $$DbContactRecordsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get contactId => $composableBuilder(
    column: $table.contactId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get appUserId => $composableBuilder(
    column: $table.appUserId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get workspaceId => $composableBuilder(
    column: $table.workspaceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get projectId => $composableBuilder(
    column: $table.projectId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get questionnaireVersionId => $composableBuilder(
    column: $table.questionnaireVersionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get occurredAtUtc => $composableBuilder(
    column: $table.occurredAtUtc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get occurredTimeZone => $composableBuilder(
    column: $table.occurredTimeZone,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get firstSubmittedAtUtc => $composableBuilder(
    column: $table.firstSubmittedAtUtc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get channel => $composableBuilder(
    column: $table.channel,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get channelDetail => $composableBuilder(
    column: $table.channelDetail,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get locationKind => $composableBuilder(
    column: $table.locationKind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get placeName => $composableBuilder(
    column: $table.placeName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get smallestRegionId => $composableBuilder(
    column: $table.smallestRegionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get latitude => $composableBuilder(
    column: $table.latitude,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get longitude => $composableBuilder(
    column: $table.longitude,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get locationAccuracyMeters => $composableBuilder(
    column: $table.locationAccuracyMeters,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get reachCount => $composableBuilder(
    column: $table.reachCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get interestLevel => $composableBuilder(
    column: $table.interestLevel,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get currentRevision => $composableBuilder(
    column: $table.currentRevision,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lifecycleStatus => $composableBuilder(
    column: $table.lifecycleStatus,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$DbContactRecordsTableAnnotationComposer
    extends Composer<_$LocalDatabase, $DbContactRecordsTable> {
  $$DbContactRecordsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get contactId =>
      $composableBuilder(column: $table.contactId, builder: (column) => column);

  GeneratedColumn<String> get appUserId =>
      $composableBuilder(column: $table.appUserId, builder: (column) => column);

  GeneratedColumn<String> get workspaceId => $composableBuilder(
    column: $table.workspaceId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get projectId =>
      $composableBuilder(column: $table.projectId, builder: (column) => column);

  GeneratedColumn<String> get questionnaireVersionId => $composableBuilder(
    column: $table.questionnaireVersionId,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get occurredAtUtc => $composableBuilder(
    column: $table.occurredAtUtc,
    builder: (column) => column,
  );

  GeneratedColumn<String> get occurredTimeZone => $composableBuilder(
    column: $table.occurredTimeZone,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get firstSubmittedAtUtc => $composableBuilder(
    column: $table.firstSubmittedAtUtc,
    builder: (column) => column,
  );

  GeneratedColumn<String> get channel =>
      $composableBuilder(column: $table.channel, builder: (column) => column);

  GeneratedColumn<String> get channelDetail => $composableBuilder(
    column: $table.channelDetail,
    builder: (column) => column,
  );

  GeneratedColumn<String> get locationKind => $composableBuilder(
    column: $table.locationKind,
    builder: (column) => column,
  );

  GeneratedColumn<String> get placeName =>
      $composableBuilder(column: $table.placeName, builder: (column) => column);

  GeneratedColumn<String> get smallestRegionId => $composableBuilder(
    column: $table.smallestRegionId,
    builder: (column) => column,
  );

  GeneratedColumn<double> get latitude =>
      $composableBuilder(column: $table.latitude, builder: (column) => column);

  GeneratedColumn<double> get longitude =>
      $composableBuilder(column: $table.longitude, builder: (column) => column);

  GeneratedColumn<double> get locationAccuracyMeters => $composableBuilder(
    column: $table.locationAccuracyMeters,
    builder: (column) => column,
  );

  GeneratedColumn<int> get reachCount => $composableBuilder(
    column: $table.reachCount,
    builder: (column) => column,
  );

  GeneratedColumn<int> get interestLevel => $composableBuilder(
    column: $table.interestLevel,
    builder: (column) => column,
  );

  GeneratedColumn<int> get currentRevision => $composableBuilder(
    column: $table.currentRevision,
    builder: (column) => column,
  );

  GeneratedColumn<String> get lifecycleStatus => $composableBuilder(
    column: $table.lifecycleStatus,
    builder: (column) => column,
  );

  Expression<T> dbContactRevisionsRefs<T extends Object>(
    Expression<T> Function($$DbContactRevisionsTableAnnotationComposer a) f,
  ) {
    final $$DbContactRevisionsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.contactId,
          referencedTable: $db.dbContactRevisions,
          getReferencedColumn: (t) => t.contactId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$DbContactRevisionsTableAnnotationComposer(
                $db: $db,
                $table: $db.dbContactRevisions,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }

  Expression<T> dbContactAnswersRefs<T extends Object>(
    Expression<T> Function($$DbContactAnswersTableAnnotationComposer a) f,
  ) {
    final $$DbContactAnswersTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.contactId,
      referencedTable: $db.dbContactAnswers,
      getReferencedColumn: (t) => t.contactId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DbContactAnswersTableAnnotationComposer(
            $db: $db,
            $table: $db.dbContactAnswers,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$DbContactRecordsTableTableManager
    extends
        RootTableManager<
          _$LocalDatabase,
          $DbContactRecordsTable,
          DbContactRecord,
          $$DbContactRecordsTableFilterComposer,
          $$DbContactRecordsTableOrderingComposer,
          $$DbContactRecordsTableAnnotationComposer,
          $$DbContactRecordsTableCreateCompanionBuilder,
          $$DbContactRecordsTableUpdateCompanionBuilder,
          (DbContactRecord, $$DbContactRecordsTableReferences),
          DbContactRecord,
          PrefetchHooks Function({
            bool dbContactRevisionsRefs,
            bool dbContactAnswersRefs,
          })
        > {
  $$DbContactRecordsTableTableManager(
    _$LocalDatabase db,
    $DbContactRecordsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DbContactRecordsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DbContactRecordsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DbContactRecordsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> contactId = const Value.absent(),
                Value<String> appUserId = const Value.absent(),
                Value<String> workspaceId = const Value.absent(),
                Value<String> projectId = const Value.absent(),
                Value<String> questionnaireVersionId = const Value.absent(),
                Value<DateTime> occurredAtUtc = const Value.absent(),
                Value<String> occurredTimeZone = const Value.absent(),
                Value<DateTime> firstSubmittedAtUtc = const Value.absent(),
                Value<String> channel = const Value.absent(),
                Value<String?> channelDetail = const Value.absent(),
                Value<String> locationKind = const Value.absent(),
                Value<String?> placeName = const Value.absent(),
                Value<String?> smallestRegionId = const Value.absent(),
                Value<double?> latitude = const Value.absent(),
                Value<double?> longitude = const Value.absent(),
                Value<double?> locationAccuracyMeters = const Value.absent(),
                Value<int> reachCount = const Value.absent(),
                Value<int> interestLevel = const Value.absent(),
                Value<int> currentRevision = const Value.absent(),
                Value<String> lifecycleStatus = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DbContactRecordsCompanion(
                contactId: contactId,
                appUserId: appUserId,
                workspaceId: workspaceId,
                projectId: projectId,
                questionnaireVersionId: questionnaireVersionId,
                occurredAtUtc: occurredAtUtc,
                occurredTimeZone: occurredTimeZone,
                firstSubmittedAtUtc: firstSubmittedAtUtc,
                channel: channel,
                channelDetail: channelDetail,
                locationKind: locationKind,
                placeName: placeName,
                smallestRegionId: smallestRegionId,
                latitude: latitude,
                longitude: longitude,
                locationAccuracyMeters: locationAccuracyMeters,
                reachCount: reachCount,
                interestLevel: interestLevel,
                currentRevision: currentRevision,
                lifecycleStatus: lifecycleStatus,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String contactId,
                required String appUserId,
                required String workspaceId,
                required String projectId,
                required String questionnaireVersionId,
                required DateTime occurredAtUtc,
                required String occurredTimeZone,
                required DateTime firstSubmittedAtUtc,
                required String channel,
                Value<String?> channelDetail = const Value.absent(),
                required String locationKind,
                Value<String?> placeName = const Value.absent(),
                Value<String?> smallestRegionId = const Value.absent(),
                Value<double?> latitude = const Value.absent(),
                Value<double?> longitude = const Value.absent(),
                Value<double?> locationAccuracyMeters = const Value.absent(),
                required int reachCount,
                required int interestLevel,
                required int currentRevision,
                required String lifecycleStatus,
                Value<int> rowid = const Value.absent(),
              }) => DbContactRecordsCompanion.insert(
                contactId: contactId,
                appUserId: appUserId,
                workspaceId: workspaceId,
                projectId: projectId,
                questionnaireVersionId: questionnaireVersionId,
                occurredAtUtc: occurredAtUtc,
                occurredTimeZone: occurredTimeZone,
                firstSubmittedAtUtc: firstSubmittedAtUtc,
                channel: channel,
                channelDetail: channelDetail,
                locationKind: locationKind,
                placeName: placeName,
                smallestRegionId: smallestRegionId,
                latitude: latitude,
                longitude: longitude,
                locationAccuracyMeters: locationAccuracyMeters,
                reachCount: reachCount,
                interestLevel: interestLevel,
                currentRevision: currentRevision,
                lifecycleStatus: lifecycleStatus,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$DbContactRecordsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({dbContactRevisionsRefs = false, dbContactAnswersRefs = false}) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (dbContactRevisionsRefs) db.dbContactRevisions,
                    if (dbContactAnswersRefs) db.dbContactAnswers,
                  ],
                  addJoins: null,
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (dbContactRevisionsRefs)
                        await $_getPrefetchedData<
                          DbContactRecord,
                          $DbContactRecordsTable,
                          DbContactRevision
                        >(
                          currentTable: table,
                          referencedTable: $$DbContactRecordsTableReferences
                              ._dbContactRevisionsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$DbContactRecordsTableReferences(
                                db,
                                table,
                                p0,
                              ).dbContactRevisionsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.contactId == item.contactId,
                              ),
                          typedResults: items,
                        ),
                      if (dbContactAnswersRefs)
                        await $_getPrefetchedData<
                          DbContactRecord,
                          $DbContactRecordsTable,
                          DbContactAnswer
                        >(
                          currentTable: table,
                          referencedTable: $$DbContactRecordsTableReferences
                              ._dbContactAnswersRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$DbContactRecordsTableReferences(
                                db,
                                table,
                                p0,
                              ).dbContactAnswersRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.contactId == item.contactId,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$DbContactRecordsTableProcessedTableManager =
    ProcessedTableManager<
      _$LocalDatabase,
      $DbContactRecordsTable,
      DbContactRecord,
      $$DbContactRecordsTableFilterComposer,
      $$DbContactRecordsTableOrderingComposer,
      $$DbContactRecordsTableAnnotationComposer,
      $$DbContactRecordsTableCreateCompanionBuilder,
      $$DbContactRecordsTableUpdateCompanionBuilder,
      (DbContactRecord, $$DbContactRecordsTableReferences),
      DbContactRecord,
      PrefetchHooks Function({
        bool dbContactRevisionsRefs,
        bool dbContactAnswersRefs,
      })
    >;
typedef $$DbSyncDrainerLeasesTableCreateCompanionBuilder =
    DbSyncDrainerLeasesCompanion Function({
      required String leaseName,
      required String leaseOwner,
      required DateTime leaseExpiresAtUtc,
      Value<int> rowid,
    });
typedef $$DbSyncDrainerLeasesTableUpdateCompanionBuilder =
    DbSyncDrainerLeasesCompanion Function({
      Value<String> leaseName,
      Value<String> leaseOwner,
      Value<DateTime> leaseExpiresAtUtc,
      Value<int> rowid,
    });

class $$DbSyncDrainerLeasesTableFilterComposer
    extends Composer<_$LocalDatabase, $DbSyncDrainerLeasesTable> {
  $$DbSyncDrainerLeasesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get leaseName => $composableBuilder(
    column: $table.leaseName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get leaseOwner => $composableBuilder(
    column: $table.leaseOwner,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get leaseExpiresAtUtc => $composableBuilder(
    column: $table.leaseExpiresAtUtc,
    builder: (column) => ColumnFilters(column),
  );
}

class $$DbSyncDrainerLeasesTableOrderingComposer
    extends Composer<_$LocalDatabase, $DbSyncDrainerLeasesTable> {
  $$DbSyncDrainerLeasesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get leaseName => $composableBuilder(
    column: $table.leaseName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get leaseOwner => $composableBuilder(
    column: $table.leaseOwner,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get leaseExpiresAtUtc => $composableBuilder(
    column: $table.leaseExpiresAtUtc,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$DbSyncDrainerLeasesTableAnnotationComposer
    extends Composer<_$LocalDatabase, $DbSyncDrainerLeasesTable> {
  $$DbSyncDrainerLeasesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get leaseName =>
      $composableBuilder(column: $table.leaseName, builder: (column) => column);

  GeneratedColumn<String> get leaseOwner => $composableBuilder(
    column: $table.leaseOwner,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get leaseExpiresAtUtc => $composableBuilder(
    column: $table.leaseExpiresAtUtc,
    builder: (column) => column,
  );
}

class $$DbSyncDrainerLeasesTableTableManager
    extends
        RootTableManager<
          _$LocalDatabase,
          $DbSyncDrainerLeasesTable,
          DbSyncDrainerLease,
          $$DbSyncDrainerLeasesTableFilterComposer,
          $$DbSyncDrainerLeasesTableOrderingComposer,
          $$DbSyncDrainerLeasesTableAnnotationComposer,
          $$DbSyncDrainerLeasesTableCreateCompanionBuilder,
          $$DbSyncDrainerLeasesTableUpdateCompanionBuilder,
          (
            DbSyncDrainerLease,
            BaseReferences<
              _$LocalDatabase,
              $DbSyncDrainerLeasesTable,
              DbSyncDrainerLease
            >,
          ),
          DbSyncDrainerLease,
          PrefetchHooks Function()
        > {
  $$DbSyncDrainerLeasesTableTableManager(
    _$LocalDatabase db,
    $DbSyncDrainerLeasesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DbSyncDrainerLeasesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DbSyncDrainerLeasesTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$DbSyncDrainerLeasesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> leaseName = const Value.absent(),
                Value<String> leaseOwner = const Value.absent(),
                Value<DateTime> leaseExpiresAtUtc = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DbSyncDrainerLeasesCompanion(
                leaseName: leaseName,
                leaseOwner: leaseOwner,
                leaseExpiresAtUtc: leaseExpiresAtUtc,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String leaseName,
                required String leaseOwner,
                required DateTime leaseExpiresAtUtc,
                Value<int> rowid = const Value.absent(),
              }) => DbSyncDrainerLeasesCompanion.insert(
                leaseName: leaseName,
                leaseOwner: leaseOwner,
                leaseExpiresAtUtc: leaseExpiresAtUtc,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$DbSyncDrainerLeasesTableProcessedTableManager =
    ProcessedTableManager<
      _$LocalDatabase,
      $DbSyncDrainerLeasesTable,
      DbSyncDrainerLease,
      $$DbSyncDrainerLeasesTableFilterComposer,
      $$DbSyncDrainerLeasesTableOrderingComposer,
      $$DbSyncDrainerLeasesTableAnnotationComposer,
      $$DbSyncDrainerLeasesTableCreateCompanionBuilder,
      $$DbSyncDrainerLeasesTableUpdateCompanionBuilder,
      (
        DbSyncDrainerLease,
        BaseReferences<
          _$LocalDatabase,
          $DbSyncDrainerLeasesTable,
          DbSyncDrainerLease
        >,
      ),
      DbSyncDrainerLease,
      PrefetchHooks Function()
    >;
typedef $$DbSyncScopesTableCreateCompanionBuilder =
    DbSyncScopesCompanion Function({
      required String appUserId,
      required String workspaceId,
      required String projectId,
      Value<String?> serverCursor,
      Value<DateTime?> lastSuccessAtUtc,
      Value<String?> lastFailureCode,
      required DateTime updatedAtUtc,
      Value<int> rowid,
    });
typedef $$DbSyncScopesTableUpdateCompanionBuilder =
    DbSyncScopesCompanion Function({
      Value<String> appUserId,
      Value<String> workspaceId,
      Value<String> projectId,
      Value<String?> serverCursor,
      Value<DateTime?> lastSuccessAtUtc,
      Value<String?> lastFailureCode,
      Value<DateTime> updatedAtUtc,
      Value<int> rowid,
    });

class $$DbSyncScopesTableFilterComposer
    extends Composer<_$LocalDatabase, $DbSyncScopesTable> {
  $$DbSyncScopesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get appUserId => $composableBuilder(
    column: $table.appUserId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get workspaceId => $composableBuilder(
    column: $table.workspaceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get projectId => $composableBuilder(
    column: $table.projectId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get serverCursor => $composableBuilder(
    column: $table.serverCursor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastSuccessAtUtc => $composableBuilder(
    column: $table.lastSuccessAtUtc,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastFailureCode => $composableBuilder(
    column: $table.lastFailureCode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAtUtc => $composableBuilder(
    column: $table.updatedAtUtc,
    builder: (column) => ColumnFilters(column),
  );
}

class $$DbSyncScopesTableOrderingComposer
    extends Composer<_$LocalDatabase, $DbSyncScopesTable> {
  $$DbSyncScopesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get appUserId => $composableBuilder(
    column: $table.appUserId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get workspaceId => $composableBuilder(
    column: $table.workspaceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get projectId => $composableBuilder(
    column: $table.projectId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get serverCursor => $composableBuilder(
    column: $table.serverCursor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastSuccessAtUtc => $composableBuilder(
    column: $table.lastSuccessAtUtc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastFailureCode => $composableBuilder(
    column: $table.lastFailureCode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAtUtc => $composableBuilder(
    column: $table.updatedAtUtc,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$DbSyncScopesTableAnnotationComposer
    extends Composer<_$LocalDatabase, $DbSyncScopesTable> {
  $$DbSyncScopesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get appUserId =>
      $composableBuilder(column: $table.appUserId, builder: (column) => column);

  GeneratedColumn<String> get workspaceId => $composableBuilder(
    column: $table.workspaceId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get projectId =>
      $composableBuilder(column: $table.projectId, builder: (column) => column);

  GeneratedColumn<String> get serverCursor => $composableBuilder(
    column: $table.serverCursor,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get lastSuccessAtUtc => $composableBuilder(
    column: $table.lastSuccessAtUtc,
    builder: (column) => column,
  );

  GeneratedColumn<String> get lastFailureCode => $composableBuilder(
    column: $table.lastFailureCode,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get updatedAtUtc => $composableBuilder(
    column: $table.updatedAtUtc,
    builder: (column) => column,
  );
}

class $$DbSyncScopesTableTableManager
    extends
        RootTableManager<
          _$LocalDatabase,
          $DbSyncScopesTable,
          DbSyncScope,
          $$DbSyncScopesTableFilterComposer,
          $$DbSyncScopesTableOrderingComposer,
          $$DbSyncScopesTableAnnotationComposer,
          $$DbSyncScopesTableCreateCompanionBuilder,
          $$DbSyncScopesTableUpdateCompanionBuilder,
          (
            DbSyncScope,
            BaseReferences<_$LocalDatabase, $DbSyncScopesTable, DbSyncScope>,
          ),
          DbSyncScope,
          PrefetchHooks Function()
        > {
  $$DbSyncScopesTableTableManager(_$LocalDatabase db, $DbSyncScopesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DbSyncScopesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DbSyncScopesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DbSyncScopesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> appUserId = const Value.absent(),
                Value<String> workspaceId = const Value.absent(),
                Value<String> projectId = const Value.absent(),
                Value<String?> serverCursor = const Value.absent(),
                Value<DateTime?> lastSuccessAtUtc = const Value.absent(),
                Value<String?> lastFailureCode = const Value.absent(),
                Value<DateTime> updatedAtUtc = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DbSyncScopesCompanion(
                appUserId: appUserId,
                workspaceId: workspaceId,
                projectId: projectId,
                serverCursor: serverCursor,
                lastSuccessAtUtc: lastSuccessAtUtc,
                lastFailureCode: lastFailureCode,
                updatedAtUtc: updatedAtUtc,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String appUserId,
                required String workspaceId,
                required String projectId,
                Value<String?> serverCursor = const Value.absent(),
                Value<DateTime?> lastSuccessAtUtc = const Value.absent(),
                Value<String?> lastFailureCode = const Value.absent(),
                required DateTime updatedAtUtc,
                Value<int> rowid = const Value.absent(),
              }) => DbSyncScopesCompanion.insert(
                appUserId: appUserId,
                workspaceId: workspaceId,
                projectId: projectId,
                serverCursor: serverCursor,
                lastSuccessAtUtc: lastSuccessAtUtc,
                lastFailureCode: lastFailureCode,
                updatedAtUtc: updatedAtUtc,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$DbSyncScopesTableProcessedTableManager =
    ProcessedTableManager<
      _$LocalDatabase,
      $DbSyncScopesTable,
      DbSyncScope,
      $$DbSyncScopesTableFilterComposer,
      $$DbSyncScopesTableOrderingComposer,
      $$DbSyncScopesTableAnnotationComposer,
      $$DbSyncScopesTableCreateCompanionBuilder,
      $$DbSyncScopesTableUpdateCompanionBuilder,
      (
        DbSyncScope,
        BaseReferences<_$LocalDatabase, $DbSyncScopesTable, DbSyncScope>,
      ),
      DbSyncScope,
      PrefetchHooks Function()
    >;
typedef $$DbContactRevisionsTableCreateCompanionBuilder =
    DbContactRevisionsCompanion Function({
      required String revisionId,
      required String contactId,
      required int revisionNumber,
      required String revisedByAppUserId,
      required DateTime revisedAtUtc,
      Value<String?> reason,
      required DateTime occurredAtUtc,
      required String occurredTimeZone,
      required String channel,
      Value<String?> channelDetail,
      required String locationKind,
      Value<String?> placeName,
      Value<String?> smallestRegionId,
      Value<double?> latitude,
      Value<double?> longitude,
      Value<double?> locationAccuracyMeters,
      required int reachCount,
      required int interestLevel,
      Value<int> rowid,
    });
typedef $$DbContactRevisionsTableUpdateCompanionBuilder =
    DbContactRevisionsCompanion Function({
      Value<String> revisionId,
      Value<String> contactId,
      Value<int> revisionNumber,
      Value<String> revisedByAppUserId,
      Value<DateTime> revisedAtUtc,
      Value<String?> reason,
      Value<DateTime> occurredAtUtc,
      Value<String> occurredTimeZone,
      Value<String> channel,
      Value<String?> channelDetail,
      Value<String> locationKind,
      Value<String?> placeName,
      Value<String?> smallestRegionId,
      Value<double?> latitude,
      Value<double?> longitude,
      Value<double?> locationAccuracyMeters,
      Value<int> reachCount,
      Value<int> interestLevel,
      Value<int> rowid,
    });

final class $$DbContactRevisionsTableReferences
    extends
        BaseReferences<
          _$LocalDatabase,
          $DbContactRevisionsTable,
          DbContactRevision
        > {
  $$DbContactRevisionsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $DbContactRecordsTable _contactIdTable(_$LocalDatabase db) =>
      db.dbContactRecords.createAlias(
        'db_contact_revisions__contact_id__db_contact_records__contact_id',
      );

  $$DbContactRecordsTableProcessedTableManager get contactId {
    final $_column = $_itemColumn<String>('contact_id')!;

    final manager = $$DbContactRecordsTableTableManager(
      $_db,
      $_db.dbContactRecords,
    ).filter((f) => f.contactId.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_contactIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$DbContactRevisionsTableFilterComposer
    extends Composer<_$LocalDatabase, $DbContactRevisionsTable> {
  $$DbContactRevisionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get revisionId => $composableBuilder(
    column: $table.revisionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get revisionNumber => $composableBuilder(
    column: $table.revisionNumber,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get revisedByAppUserId => $composableBuilder(
    column: $table.revisedByAppUserId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get revisedAtUtc => $composableBuilder(
    column: $table.revisedAtUtc,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get reason => $composableBuilder(
    column: $table.reason,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get occurredAtUtc => $composableBuilder(
    column: $table.occurredAtUtc,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get occurredTimeZone => $composableBuilder(
    column: $table.occurredTimeZone,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get channel => $composableBuilder(
    column: $table.channel,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get channelDetail => $composableBuilder(
    column: $table.channelDetail,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get locationKind => $composableBuilder(
    column: $table.locationKind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get placeName => $composableBuilder(
    column: $table.placeName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get smallestRegionId => $composableBuilder(
    column: $table.smallestRegionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get latitude => $composableBuilder(
    column: $table.latitude,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get longitude => $composableBuilder(
    column: $table.longitude,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get locationAccuracyMeters => $composableBuilder(
    column: $table.locationAccuracyMeters,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get reachCount => $composableBuilder(
    column: $table.reachCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get interestLevel => $composableBuilder(
    column: $table.interestLevel,
    builder: (column) => ColumnFilters(column),
  );

  $$DbContactRecordsTableFilterComposer get contactId {
    final $$DbContactRecordsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.contactId,
      referencedTable: $db.dbContactRecords,
      getReferencedColumn: (t) => t.contactId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DbContactRecordsTableFilterComposer(
            $db: $db,
            $table: $db.dbContactRecords,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$DbContactRevisionsTableOrderingComposer
    extends Composer<_$LocalDatabase, $DbContactRevisionsTable> {
  $$DbContactRevisionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get revisionId => $composableBuilder(
    column: $table.revisionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get revisionNumber => $composableBuilder(
    column: $table.revisionNumber,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get revisedByAppUserId => $composableBuilder(
    column: $table.revisedByAppUserId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get revisedAtUtc => $composableBuilder(
    column: $table.revisedAtUtc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get reason => $composableBuilder(
    column: $table.reason,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get occurredAtUtc => $composableBuilder(
    column: $table.occurredAtUtc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get occurredTimeZone => $composableBuilder(
    column: $table.occurredTimeZone,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get channel => $composableBuilder(
    column: $table.channel,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get channelDetail => $composableBuilder(
    column: $table.channelDetail,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get locationKind => $composableBuilder(
    column: $table.locationKind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get placeName => $composableBuilder(
    column: $table.placeName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get smallestRegionId => $composableBuilder(
    column: $table.smallestRegionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get latitude => $composableBuilder(
    column: $table.latitude,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get longitude => $composableBuilder(
    column: $table.longitude,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get locationAccuracyMeters => $composableBuilder(
    column: $table.locationAccuracyMeters,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get reachCount => $composableBuilder(
    column: $table.reachCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get interestLevel => $composableBuilder(
    column: $table.interestLevel,
    builder: (column) => ColumnOrderings(column),
  );

  $$DbContactRecordsTableOrderingComposer get contactId {
    final $$DbContactRecordsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.contactId,
      referencedTable: $db.dbContactRecords,
      getReferencedColumn: (t) => t.contactId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DbContactRecordsTableOrderingComposer(
            $db: $db,
            $table: $db.dbContactRecords,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$DbContactRevisionsTableAnnotationComposer
    extends Composer<_$LocalDatabase, $DbContactRevisionsTable> {
  $$DbContactRevisionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get revisionId => $composableBuilder(
    column: $table.revisionId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get revisionNumber => $composableBuilder(
    column: $table.revisionNumber,
    builder: (column) => column,
  );

  GeneratedColumn<String> get revisedByAppUserId => $composableBuilder(
    column: $table.revisedByAppUserId,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get revisedAtUtc => $composableBuilder(
    column: $table.revisedAtUtc,
    builder: (column) => column,
  );

  GeneratedColumn<String> get reason =>
      $composableBuilder(column: $table.reason, builder: (column) => column);

  GeneratedColumn<DateTime> get occurredAtUtc => $composableBuilder(
    column: $table.occurredAtUtc,
    builder: (column) => column,
  );

  GeneratedColumn<String> get occurredTimeZone => $composableBuilder(
    column: $table.occurredTimeZone,
    builder: (column) => column,
  );

  GeneratedColumn<String> get channel =>
      $composableBuilder(column: $table.channel, builder: (column) => column);

  GeneratedColumn<String> get channelDetail => $composableBuilder(
    column: $table.channelDetail,
    builder: (column) => column,
  );

  GeneratedColumn<String> get locationKind => $composableBuilder(
    column: $table.locationKind,
    builder: (column) => column,
  );

  GeneratedColumn<String> get placeName =>
      $composableBuilder(column: $table.placeName, builder: (column) => column);

  GeneratedColumn<String> get smallestRegionId => $composableBuilder(
    column: $table.smallestRegionId,
    builder: (column) => column,
  );

  GeneratedColumn<double> get latitude =>
      $composableBuilder(column: $table.latitude, builder: (column) => column);

  GeneratedColumn<double> get longitude =>
      $composableBuilder(column: $table.longitude, builder: (column) => column);

  GeneratedColumn<double> get locationAccuracyMeters => $composableBuilder(
    column: $table.locationAccuracyMeters,
    builder: (column) => column,
  );

  GeneratedColumn<int> get reachCount => $composableBuilder(
    column: $table.reachCount,
    builder: (column) => column,
  );

  GeneratedColumn<int> get interestLevel => $composableBuilder(
    column: $table.interestLevel,
    builder: (column) => column,
  );

  $$DbContactRecordsTableAnnotationComposer get contactId {
    final $$DbContactRecordsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.contactId,
      referencedTable: $db.dbContactRecords,
      getReferencedColumn: (t) => t.contactId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DbContactRecordsTableAnnotationComposer(
            $db: $db,
            $table: $db.dbContactRecords,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$DbContactRevisionsTableTableManager
    extends
        RootTableManager<
          _$LocalDatabase,
          $DbContactRevisionsTable,
          DbContactRevision,
          $$DbContactRevisionsTableFilterComposer,
          $$DbContactRevisionsTableOrderingComposer,
          $$DbContactRevisionsTableAnnotationComposer,
          $$DbContactRevisionsTableCreateCompanionBuilder,
          $$DbContactRevisionsTableUpdateCompanionBuilder,
          (DbContactRevision, $$DbContactRevisionsTableReferences),
          DbContactRevision,
          PrefetchHooks Function({bool contactId})
        > {
  $$DbContactRevisionsTableTableManager(
    _$LocalDatabase db,
    $DbContactRevisionsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DbContactRevisionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DbContactRevisionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DbContactRevisionsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> revisionId = const Value.absent(),
                Value<String> contactId = const Value.absent(),
                Value<int> revisionNumber = const Value.absent(),
                Value<String> revisedByAppUserId = const Value.absent(),
                Value<DateTime> revisedAtUtc = const Value.absent(),
                Value<String?> reason = const Value.absent(),
                Value<DateTime> occurredAtUtc = const Value.absent(),
                Value<String> occurredTimeZone = const Value.absent(),
                Value<String> channel = const Value.absent(),
                Value<String?> channelDetail = const Value.absent(),
                Value<String> locationKind = const Value.absent(),
                Value<String?> placeName = const Value.absent(),
                Value<String?> smallestRegionId = const Value.absent(),
                Value<double?> latitude = const Value.absent(),
                Value<double?> longitude = const Value.absent(),
                Value<double?> locationAccuracyMeters = const Value.absent(),
                Value<int> reachCount = const Value.absent(),
                Value<int> interestLevel = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DbContactRevisionsCompanion(
                revisionId: revisionId,
                contactId: contactId,
                revisionNumber: revisionNumber,
                revisedByAppUserId: revisedByAppUserId,
                revisedAtUtc: revisedAtUtc,
                reason: reason,
                occurredAtUtc: occurredAtUtc,
                occurredTimeZone: occurredTimeZone,
                channel: channel,
                channelDetail: channelDetail,
                locationKind: locationKind,
                placeName: placeName,
                smallestRegionId: smallestRegionId,
                latitude: latitude,
                longitude: longitude,
                locationAccuracyMeters: locationAccuracyMeters,
                reachCount: reachCount,
                interestLevel: interestLevel,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String revisionId,
                required String contactId,
                required int revisionNumber,
                required String revisedByAppUserId,
                required DateTime revisedAtUtc,
                Value<String?> reason = const Value.absent(),
                required DateTime occurredAtUtc,
                required String occurredTimeZone,
                required String channel,
                Value<String?> channelDetail = const Value.absent(),
                required String locationKind,
                Value<String?> placeName = const Value.absent(),
                Value<String?> smallestRegionId = const Value.absent(),
                Value<double?> latitude = const Value.absent(),
                Value<double?> longitude = const Value.absent(),
                Value<double?> locationAccuracyMeters = const Value.absent(),
                required int reachCount,
                required int interestLevel,
                Value<int> rowid = const Value.absent(),
              }) => DbContactRevisionsCompanion.insert(
                revisionId: revisionId,
                contactId: contactId,
                revisionNumber: revisionNumber,
                revisedByAppUserId: revisedByAppUserId,
                revisedAtUtc: revisedAtUtc,
                reason: reason,
                occurredAtUtc: occurredAtUtc,
                occurredTimeZone: occurredTimeZone,
                channel: channel,
                channelDetail: channelDetail,
                locationKind: locationKind,
                placeName: placeName,
                smallestRegionId: smallestRegionId,
                latitude: latitude,
                longitude: longitude,
                locationAccuracyMeters: locationAccuracyMeters,
                reachCount: reachCount,
                interestLevel: interestLevel,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$DbContactRevisionsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({contactId = false}) {
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
                    if (contactId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.contactId,
                                referencedTable:
                                    $$DbContactRevisionsTableReferences
                                        ._contactIdTable(db),
                                referencedColumn:
                                    $$DbContactRevisionsTableReferences
                                        ._contactIdTable(db)
                                        .contactId,
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

typedef $$DbContactRevisionsTableProcessedTableManager =
    ProcessedTableManager<
      _$LocalDatabase,
      $DbContactRevisionsTable,
      DbContactRevision,
      $$DbContactRevisionsTableFilterComposer,
      $$DbContactRevisionsTableOrderingComposer,
      $$DbContactRevisionsTableAnnotationComposer,
      $$DbContactRevisionsTableCreateCompanionBuilder,
      $$DbContactRevisionsTableUpdateCompanionBuilder,
      (DbContactRevision, $$DbContactRevisionsTableReferences),
      DbContactRevision,
      PrefetchHooks Function({bool contactId})
    >;
typedef $$DbContactAnswersTableCreateCompanionBuilder =
    DbContactAnswersCompanion Function({
      required String contactId,
      required int revisionNumber,
      required String questionId,
      required String answerState,
      required String answerType,
      Value<bool?> booleanValue,
      Value<int> rowid,
    });
typedef $$DbContactAnswersTableUpdateCompanionBuilder =
    DbContactAnswersCompanion Function({
      Value<String> contactId,
      Value<int> revisionNumber,
      Value<String> questionId,
      Value<String> answerState,
      Value<String> answerType,
      Value<bool?> booleanValue,
      Value<int> rowid,
    });

final class $$DbContactAnswersTableReferences
    extends
        BaseReferences<
          _$LocalDatabase,
          $DbContactAnswersTable,
          DbContactAnswer
        > {
  $$DbContactAnswersTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $DbContactRecordsTable _contactIdTable(_$LocalDatabase db) =>
      db.dbContactRecords.createAlias(
        'db_contact_answers__contact_id__db_contact_records__contact_id',
      );

  $$DbContactRecordsTableProcessedTableManager get contactId {
    final $_column = $_itemColumn<String>('contact_id')!;

    final manager = $$DbContactRecordsTableTableManager(
      $_db,
      $_db.dbContactRecords,
    ).filter((f) => f.contactId.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_contactIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$DbContactAnswersTableFilterComposer
    extends Composer<_$LocalDatabase, $DbContactAnswersTable> {
  $$DbContactAnswersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get revisionNumber => $composableBuilder(
    column: $table.revisionNumber,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get questionId => $composableBuilder(
    column: $table.questionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get answerState => $composableBuilder(
    column: $table.answerState,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get answerType => $composableBuilder(
    column: $table.answerType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get booleanValue => $composableBuilder(
    column: $table.booleanValue,
    builder: (column) => ColumnFilters(column),
  );

  $$DbContactRecordsTableFilterComposer get contactId {
    final $$DbContactRecordsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.contactId,
      referencedTable: $db.dbContactRecords,
      getReferencedColumn: (t) => t.contactId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DbContactRecordsTableFilterComposer(
            $db: $db,
            $table: $db.dbContactRecords,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$DbContactAnswersTableOrderingComposer
    extends Composer<_$LocalDatabase, $DbContactAnswersTable> {
  $$DbContactAnswersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get revisionNumber => $composableBuilder(
    column: $table.revisionNumber,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get questionId => $composableBuilder(
    column: $table.questionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get answerState => $composableBuilder(
    column: $table.answerState,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get answerType => $composableBuilder(
    column: $table.answerType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get booleanValue => $composableBuilder(
    column: $table.booleanValue,
    builder: (column) => ColumnOrderings(column),
  );

  $$DbContactRecordsTableOrderingComposer get contactId {
    final $$DbContactRecordsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.contactId,
      referencedTable: $db.dbContactRecords,
      getReferencedColumn: (t) => t.contactId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DbContactRecordsTableOrderingComposer(
            $db: $db,
            $table: $db.dbContactRecords,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$DbContactAnswersTableAnnotationComposer
    extends Composer<_$LocalDatabase, $DbContactAnswersTable> {
  $$DbContactAnswersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get revisionNumber => $composableBuilder(
    column: $table.revisionNumber,
    builder: (column) => column,
  );

  GeneratedColumn<String> get questionId => $composableBuilder(
    column: $table.questionId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get answerState => $composableBuilder(
    column: $table.answerState,
    builder: (column) => column,
  );

  GeneratedColumn<String> get answerType => $composableBuilder(
    column: $table.answerType,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get booleanValue => $composableBuilder(
    column: $table.booleanValue,
    builder: (column) => column,
  );

  $$DbContactRecordsTableAnnotationComposer get contactId {
    final $$DbContactRecordsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.contactId,
      referencedTable: $db.dbContactRecords,
      getReferencedColumn: (t) => t.contactId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DbContactRecordsTableAnnotationComposer(
            $db: $db,
            $table: $db.dbContactRecords,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$DbContactAnswersTableTableManager
    extends
        RootTableManager<
          _$LocalDatabase,
          $DbContactAnswersTable,
          DbContactAnswer,
          $$DbContactAnswersTableFilterComposer,
          $$DbContactAnswersTableOrderingComposer,
          $$DbContactAnswersTableAnnotationComposer,
          $$DbContactAnswersTableCreateCompanionBuilder,
          $$DbContactAnswersTableUpdateCompanionBuilder,
          (DbContactAnswer, $$DbContactAnswersTableReferences),
          DbContactAnswer,
          PrefetchHooks Function({bool contactId})
        > {
  $$DbContactAnswersTableTableManager(
    _$LocalDatabase db,
    $DbContactAnswersTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DbContactAnswersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DbContactAnswersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DbContactAnswersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> contactId = const Value.absent(),
                Value<int> revisionNumber = const Value.absent(),
                Value<String> questionId = const Value.absent(),
                Value<String> answerState = const Value.absent(),
                Value<String> answerType = const Value.absent(),
                Value<bool?> booleanValue = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DbContactAnswersCompanion(
                contactId: contactId,
                revisionNumber: revisionNumber,
                questionId: questionId,
                answerState: answerState,
                answerType: answerType,
                booleanValue: booleanValue,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String contactId,
                required int revisionNumber,
                required String questionId,
                required String answerState,
                required String answerType,
                Value<bool?> booleanValue = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DbContactAnswersCompanion.insert(
                contactId: contactId,
                revisionNumber: revisionNumber,
                questionId: questionId,
                answerState: answerState,
                answerType: answerType,
                booleanValue: booleanValue,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$DbContactAnswersTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({contactId = false}) {
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
                    if (contactId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.contactId,
                                referencedTable:
                                    $$DbContactAnswersTableReferences
                                        ._contactIdTable(db),
                                referencedColumn:
                                    $$DbContactAnswersTableReferences
                                        ._contactIdTable(db)
                                        .contactId,
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

typedef $$DbContactAnswersTableProcessedTableManager =
    ProcessedTableManager<
      _$LocalDatabase,
      $DbContactAnswersTable,
      DbContactAnswer,
      $$DbContactAnswersTableFilterComposer,
      $$DbContactAnswersTableOrderingComposer,
      $$DbContactAnswersTableAnnotationComposer,
      $$DbContactAnswersTableCreateCompanionBuilder,
      $$DbContactAnswersTableUpdateCompanionBuilder,
      (DbContactAnswer, $$DbContactAnswersTableReferences),
      DbContactAnswer,
      PrefetchHooks Function({bool contactId})
    >;
typedef $$DbContactDraftsTableCreateCompanionBuilder =
    DbContactDraftsCompanion Function({
      required String draftId,
      required String appUserId,
      required String workspaceId,
      required String projectId,
      required String questionnaireVersionId,
      required DateTime createdAtUtc,
      required DateTime updatedAtUtc,
      Value<DateTime?> occurredAtUtc,
      Value<String?> occurredTimeZone,
      Value<String?> channel,
      Value<String?> channelDetail,
      Value<String?> locationKind,
      Value<String?> placeName,
      Value<String?> smallestRegionId,
      Value<double?> latitude,
      Value<double?> longitude,
      Value<double?> locationAccuracyMeters,
      Value<int?> reachCount,
      Value<int?> interestLevel,
      Value<String> syncMode,
      Value<DateTime?> abandonedAtUtc,
      Value<DateTime?> undoUntilUtc,
      Value<int> rowid,
    });
typedef $$DbContactDraftsTableUpdateCompanionBuilder =
    DbContactDraftsCompanion Function({
      Value<String> draftId,
      Value<String> appUserId,
      Value<String> workspaceId,
      Value<String> projectId,
      Value<String> questionnaireVersionId,
      Value<DateTime> createdAtUtc,
      Value<DateTime> updatedAtUtc,
      Value<DateTime?> occurredAtUtc,
      Value<String?> occurredTimeZone,
      Value<String?> channel,
      Value<String?> channelDetail,
      Value<String?> locationKind,
      Value<String?> placeName,
      Value<String?> smallestRegionId,
      Value<double?> latitude,
      Value<double?> longitude,
      Value<double?> locationAccuracyMeters,
      Value<int?> reachCount,
      Value<int?> interestLevel,
      Value<String> syncMode,
      Value<DateTime?> abandonedAtUtc,
      Value<DateTime?> undoUntilUtc,
      Value<int> rowid,
    });

final class $$DbContactDraftsTableReferences
    extends
        BaseReferences<_$LocalDatabase, $DbContactDraftsTable, DbContactDraft> {
  $$DbContactDraftsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static MultiTypedResultKey<
    $DbContactDraftAnswersTable,
    List<DbContactDraftAnswer>
  >
  _dbContactDraftAnswersRefsTable(_$LocalDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.dbContactDraftAnswers,
        aliasName:
            'db_contact_drafts__draft_id__db_contact_draft_answers__draft_id',
      );

  $$DbContactDraftAnswersTableProcessedTableManager
  get dbContactDraftAnswersRefs {
    final manager =
        $$DbContactDraftAnswersTableTableManager(
          $_db,
          $_db.dbContactDraftAnswers,
        ).filter(
          (f) => f.draftId.draftId.sqlEquals($_itemColumn<String>('draft_id')!),
        );

    final cache = $_typedResult.readTableOrNull(
      _dbContactDraftAnswersRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$DbContactDraftsTableFilterComposer
    extends Composer<_$LocalDatabase, $DbContactDraftsTable> {
  $$DbContactDraftsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get draftId => $composableBuilder(
    column: $table.draftId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get appUserId => $composableBuilder(
    column: $table.appUserId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get workspaceId => $composableBuilder(
    column: $table.workspaceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get projectId => $composableBuilder(
    column: $table.projectId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get questionnaireVersionId => $composableBuilder(
    column: $table.questionnaireVersionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAtUtc => $composableBuilder(
    column: $table.createdAtUtc,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAtUtc => $composableBuilder(
    column: $table.updatedAtUtc,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get occurredAtUtc => $composableBuilder(
    column: $table.occurredAtUtc,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get occurredTimeZone => $composableBuilder(
    column: $table.occurredTimeZone,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get channel => $composableBuilder(
    column: $table.channel,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get channelDetail => $composableBuilder(
    column: $table.channelDetail,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get locationKind => $composableBuilder(
    column: $table.locationKind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get placeName => $composableBuilder(
    column: $table.placeName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get smallestRegionId => $composableBuilder(
    column: $table.smallestRegionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get latitude => $composableBuilder(
    column: $table.latitude,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get longitude => $composableBuilder(
    column: $table.longitude,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get locationAccuracyMeters => $composableBuilder(
    column: $table.locationAccuracyMeters,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get reachCount => $composableBuilder(
    column: $table.reachCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get interestLevel => $composableBuilder(
    column: $table.interestLevel,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get syncMode => $composableBuilder(
    column: $table.syncMode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get abandonedAtUtc => $composableBuilder(
    column: $table.abandonedAtUtc,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get undoUntilUtc => $composableBuilder(
    column: $table.undoUntilUtc,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> dbContactDraftAnswersRefs(
    Expression<bool> Function($$DbContactDraftAnswersTableFilterComposer f) f,
  ) {
    final $$DbContactDraftAnswersTableFilterComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.draftId,
          referencedTable: $db.dbContactDraftAnswers,
          getReferencedColumn: (t) => t.draftId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$DbContactDraftAnswersTableFilterComposer(
                $db: $db,
                $table: $db.dbContactDraftAnswers,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }
}

class $$DbContactDraftsTableOrderingComposer
    extends Composer<_$LocalDatabase, $DbContactDraftsTable> {
  $$DbContactDraftsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get draftId => $composableBuilder(
    column: $table.draftId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get appUserId => $composableBuilder(
    column: $table.appUserId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get workspaceId => $composableBuilder(
    column: $table.workspaceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get projectId => $composableBuilder(
    column: $table.projectId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get questionnaireVersionId => $composableBuilder(
    column: $table.questionnaireVersionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAtUtc => $composableBuilder(
    column: $table.createdAtUtc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAtUtc => $composableBuilder(
    column: $table.updatedAtUtc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get occurredAtUtc => $composableBuilder(
    column: $table.occurredAtUtc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get occurredTimeZone => $composableBuilder(
    column: $table.occurredTimeZone,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get channel => $composableBuilder(
    column: $table.channel,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get channelDetail => $composableBuilder(
    column: $table.channelDetail,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get locationKind => $composableBuilder(
    column: $table.locationKind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get placeName => $composableBuilder(
    column: $table.placeName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get smallestRegionId => $composableBuilder(
    column: $table.smallestRegionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get latitude => $composableBuilder(
    column: $table.latitude,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get longitude => $composableBuilder(
    column: $table.longitude,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get locationAccuracyMeters => $composableBuilder(
    column: $table.locationAccuracyMeters,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get reachCount => $composableBuilder(
    column: $table.reachCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get interestLevel => $composableBuilder(
    column: $table.interestLevel,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get syncMode => $composableBuilder(
    column: $table.syncMode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get abandonedAtUtc => $composableBuilder(
    column: $table.abandonedAtUtc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get undoUntilUtc => $composableBuilder(
    column: $table.undoUntilUtc,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$DbContactDraftsTableAnnotationComposer
    extends Composer<_$LocalDatabase, $DbContactDraftsTable> {
  $$DbContactDraftsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get draftId =>
      $composableBuilder(column: $table.draftId, builder: (column) => column);

  GeneratedColumn<String> get appUserId =>
      $composableBuilder(column: $table.appUserId, builder: (column) => column);

  GeneratedColumn<String> get workspaceId => $composableBuilder(
    column: $table.workspaceId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get projectId =>
      $composableBuilder(column: $table.projectId, builder: (column) => column);

  GeneratedColumn<String> get questionnaireVersionId => $composableBuilder(
    column: $table.questionnaireVersionId,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAtUtc => $composableBuilder(
    column: $table.createdAtUtc,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get updatedAtUtc => $composableBuilder(
    column: $table.updatedAtUtc,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get occurredAtUtc => $composableBuilder(
    column: $table.occurredAtUtc,
    builder: (column) => column,
  );

  GeneratedColumn<String> get occurredTimeZone => $composableBuilder(
    column: $table.occurredTimeZone,
    builder: (column) => column,
  );

  GeneratedColumn<String> get channel =>
      $composableBuilder(column: $table.channel, builder: (column) => column);

  GeneratedColumn<String> get channelDetail => $composableBuilder(
    column: $table.channelDetail,
    builder: (column) => column,
  );

  GeneratedColumn<String> get locationKind => $composableBuilder(
    column: $table.locationKind,
    builder: (column) => column,
  );

  GeneratedColumn<String> get placeName =>
      $composableBuilder(column: $table.placeName, builder: (column) => column);

  GeneratedColumn<String> get smallestRegionId => $composableBuilder(
    column: $table.smallestRegionId,
    builder: (column) => column,
  );

  GeneratedColumn<double> get latitude =>
      $composableBuilder(column: $table.latitude, builder: (column) => column);

  GeneratedColumn<double> get longitude =>
      $composableBuilder(column: $table.longitude, builder: (column) => column);

  GeneratedColumn<double> get locationAccuracyMeters => $composableBuilder(
    column: $table.locationAccuracyMeters,
    builder: (column) => column,
  );

  GeneratedColumn<int> get reachCount => $composableBuilder(
    column: $table.reachCount,
    builder: (column) => column,
  );

  GeneratedColumn<int> get interestLevel => $composableBuilder(
    column: $table.interestLevel,
    builder: (column) => column,
  );

  GeneratedColumn<String> get syncMode =>
      $composableBuilder(column: $table.syncMode, builder: (column) => column);

  GeneratedColumn<DateTime> get abandonedAtUtc => $composableBuilder(
    column: $table.abandonedAtUtc,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get undoUntilUtc => $composableBuilder(
    column: $table.undoUntilUtc,
    builder: (column) => column,
  );

  Expression<T> dbContactDraftAnswersRefs<T extends Object>(
    Expression<T> Function($$DbContactDraftAnswersTableAnnotationComposer a) f,
  ) {
    final $$DbContactDraftAnswersTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.draftId,
          referencedTable: $db.dbContactDraftAnswers,
          getReferencedColumn: (t) => t.draftId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$DbContactDraftAnswersTableAnnotationComposer(
                $db: $db,
                $table: $db.dbContactDraftAnswers,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }
}

class $$DbContactDraftsTableTableManager
    extends
        RootTableManager<
          _$LocalDatabase,
          $DbContactDraftsTable,
          DbContactDraft,
          $$DbContactDraftsTableFilterComposer,
          $$DbContactDraftsTableOrderingComposer,
          $$DbContactDraftsTableAnnotationComposer,
          $$DbContactDraftsTableCreateCompanionBuilder,
          $$DbContactDraftsTableUpdateCompanionBuilder,
          (DbContactDraft, $$DbContactDraftsTableReferences),
          DbContactDraft,
          PrefetchHooks Function({bool dbContactDraftAnswersRefs})
        > {
  $$DbContactDraftsTableTableManager(
    _$LocalDatabase db,
    $DbContactDraftsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DbContactDraftsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DbContactDraftsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DbContactDraftsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> draftId = const Value.absent(),
                Value<String> appUserId = const Value.absent(),
                Value<String> workspaceId = const Value.absent(),
                Value<String> projectId = const Value.absent(),
                Value<String> questionnaireVersionId = const Value.absent(),
                Value<DateTime> createdAtUtc = const Value.absent(),
                Value<DateTime> updatedAtUtc = const Value.absent(),
                Value<DateTime?> occurredAtUtc = const Value.absent(),
                Value<String?> occurredTimeZone = const Value.absent(),
                Value<String?> channel = const Value.absent(),
                Value<String?> channelDetail = const Value.absent(),
                Value<String?> locationKind = const Value.absent(),
                Value<String?> placeName = const Value.absent(),
                Value<String?> smallestRegionId = const Value.absent(),
                Value<double?> latitude = const Value.absent(),
                Value<double?> longitude = const Value.absent(),
                Value<double?> locationAccuracyMeters = const Value.absent(),
                Value<int?> reachCount = const Value.absent(),
                Value<int?> interestLevel = const Value.absent(),
                Value<String> syncMode = const Value.absent(),
                Value<DateTime?> abandonedAtUtc = const Value.absent(),
                Value<DateTime?> undoUntilUtc = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DbContactDraftsCompanion(
                draftId: draftId,
                appUserId: appUserId,
                workspaceId: workspaceId,
                projectId: projectId,
                questionnaireVersionId: questionnaireVersionId,
                createdAtUtc: createdAtUtc,
                updatedAtUtc: updatedAtUtc,
                occurredAtUtc: occurredAtUtc,
                occurredTimeZone: occurredTimeZone,
                channel: channel,
                channelDetail: channelDetail,
                locationKind: locationKind,
                placeName: placeName,
                smallestRegionId: smallestRegionId,
                latitude: latitude,
                longitude: longitude,
                locationAccuracyMeters: locationAccuracyMeters,
                reachCount: reachCount,
                interestLevel: interestLevel,
                syncMode: syncMode,
                abandonedAtUtc: abandonedAtUtc,
                undoUntilUtc: undoUntilUtc,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String draftId,
                required String appUserId,
                required String workspaceId,
                required String projectId,
                required String questionnaireVersionId,
                required DateTime createdAtUtc,
                required DateTime updatedAtUtc,
                Value<DateTime?> occurredAtUtc = const Value.absent(),
                Value<String?> occurredTimeZone = const Value.absent(),
                Value<String?> channel = const Value.absent(),
                Value<String?> channelDetail = const Value.absent(),
                Value<String?> locationKind = const Value.absent(),
                Value<String?> placeName = const Value.absent(),
                Value<String?> smallestRegionId = const Value.absent(),
                Value<double?> latitude = const Value.absent(),
                Value<double?> longitude = const Value.absent(),
                Value<double?> locationAccuracyMeters = const Value.absent(),
                Value<int?> reachCount = const Value.absent(),
                Value<int?> interestLevel = const Value.absent(),
                Value<String> syncMode = const Value.absent(),
                Value<DateTime?> abandonedAtUtc = const Value.absent(),
                Value<DateTime?> undoUntilUtc = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DbContactDraftsCompanion.insert(
                draftId: draftId,
                appUserId: appUserId,
                workspaceId: workspaceId,
                projectId: projectId,
                questionnaireVersionId: questionnaireVersionId,
                createdAtUtc: createdAtUtc,
                updatedAtUtc: updatedAtUtc,
                occurredAtUtc: occurredAtUtc,
                occurredTimeZone: occurredTimeZone,
                channel: channel,
                channelDetail: channelDetail,
                locationKind: locationKind,
                placeName: placeName,
                smallestRegionId: smallestRegionId,
                latitude: latitude,
                longitude: longitude,
                locationAccuracyMeters: locationAccuracyMeters,
                reachCount: reachCount,
                interestLevel: interestLevel,
                syncMode: syncMode,
                abandonedAtUtc: abandonedAtUtc,
                undoUntilUtc: undoUntilUtc,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$DbContactDraftsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({dbContactDraftAnswersRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (dbContactDraftAnswersRefs) db.dbContactDraftAnswers,
              ],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (dbContactDraftAnswersRefs)
                    await $_getPrefetchedData<
                      DbContactDraft,
                      $DbContactDraftsTable,
                      DbContactDraftAnswer
                    >(
                      currentTable: table,
                      referencedTable: $$DbContactDraftsTableReferences
                          ._dbContactDraftAnswersRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $$DbContactDraftsTableReferences(
                            db,
                            table,
                            p0,
                          ).dbContactDraftAnswersRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where(
                            (e) => e.draftId == item.draftId,
                          ),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$DbContactDraftsTableProcessedTableManager =
    ProcessedTableManager<
      _$LocalDatabase,
      $DbContactDraftsTable,
      DbContactDraft,
      $$DbContactDraftsTableFilterComposer,
      $$DbContactDraftsTableOrderingComposer,
      $$DbContactDraftsTableAnnotationComposer,
      $$DbContactDraftsTableCreateCompanionBuilder,
      $$DbContactDraftsTableUpdateCompanionBuilder,
      (DbContactDraft, $$DbContactDraftsTableReferences),
      DbContactDraft,
      PrefetchHooks Function({bool dbContactDraftAnswersRefs})
    >;
typedef $$DbContactDraftAnswersTableCreateCompanionBuilder =
    DbContactDraftAnswersCompanion Function({
      required String draftId,
      required String questionId,
      required String answerState,
      required String answerType,
      Value<bool?> booleanValue,
      Value<int> rowid,
    });
typedef $$DbContactDraftAnswersTableUpdateCompanionBuilder =
    DbContactDraftAnswersCompanion Function({
      Value<String> draftId,
      Value<String> questionId,
      Value<String> answerState,
      Value<String> answerType,
      Value<bool?> booleanValue,
      Value<int> rowid,
    });

final class $$DbContactDraftAnswersTableReferences
    extends
        BaseReferences<
          _$LocalDatabase,
          $DbContactDraftAnswersTable,
          DbContactDraftAnswer
        > {
  $$DbContactDraftAnswersTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $DbContactDraftsTable _draftIdTable(_$LocalDatabase db) =>
      db.dbContactDrafts.createAlias(
        'db_contact_draft_answers__draft_id__db_contact_drafts__draft_id',
      );

  $$DbContactDraftsTableProcessedTableManager get draftId {
    final $_column = $_itemColumn<String>('draft_id')!;

    final manager = $$DbContactDraftsTableTableManager(
      $_db,
      $_db.dbContactDrafts,
    ).filter((f) => f.draftId.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_draftIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$DbContactDraftAnswersTableFilterComposer
    extends Composer<_$LocalDatabase, $DbContactDraftAnswersTable> {
  $$DbContactDraftAnswersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get questionId => $composableBuilder(
    column: $table.questionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get answerState => $composableBuilder(
    column: $table.answerState,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get answerType => $composableBuilder(
    column: $table.answerType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get booleanValue => $composableBuilder(
    column: $table.booleanValue,
    builder: (column) => ColumnFilters(column),
  );

  $$DbContactDraftsTableFilterComposer get draftId {
    final $$DbContactDraftsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.draftId,
      referencedTable: $db.dbContactDrafts,
      getReferencedColumn: (t) => t.draftId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DbContactDraftsTableFilterComposer(
            $db: $db,
            $table: $db.dbContactDrafts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$DbContactDraftAnswersTableOrderingComposer
    extends Composer<_$LocalDatabase, $DbContactDraftAnswersTable> {
  $$DbContactDraftAnswersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get questionId => $composableBuilder(
    column: $table.questionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get answerState => $composableBuilder(
    column: $table.answerState,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get answerType => $composableBuilder(
    column: $table.answerType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get booleanValue => $composableBuilder(
    column: $table.booleanValue,
    builder: (column) => ColumnOrderings(column),
  );

  $$DbContactDraftsTableOrderingComposer get draftId {
    final $$DbContactDraftsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.draftId,
      referencedTable: $db.dbContactDrafts,
      getReferencedColumn: (t) => t.draftId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DbContactDraftsTableOrderingComposer(
            $db: $db,
            $table: $db.dbContactDrafts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$DbContactDraftAnswersTableAnnotationComposer
    extends Composer<_$LocalDatabase, $DbContactDraftAnswersTable> {
  $$DbContactDraftAnswersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get questionId => $composableBuilder(
    column: $table.questionId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get answerState => $composableBuilder(
    column: $table.answerState,
    builder: (column) => column,
  );

  GeneratedColumn<String> get answerType => $composableBuilder(
    column: $table.answerType,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get booleanValue => $composableBuilder(
    column: $table.booleanValue,
    builder: (column) => column,
  );

  $$DbContactDraftsTableAnnotationComposer get draftId {
    final $$DbContactDraftsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.draftId,
      referencedTable: $db.dbContactDrafts,
      getReferencedColumn: (t) => t.draftId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DbContactDraftsTableAnnotationComposer(
            $db: $db,
            $table: $db.dbContactDrafts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$DbContactDraftAnswersTableTableManager
    extends
        RootTableManager<
          _$LocalDatabase,
          $DbContactDraftAnswersTable,
          DbContactDraftAnswer,
          $$DbContactDraftAnswersTableFilterComposer,
          $$DbContactDraftAnswersTableOrderingComposer,
          $$DbContactDraftAnswersTableAnnotationComposer,
          $$DbContactDraftAnswersTableCreateCompanionBuilder,
          $$DbContactDraftAnswersTableUpdateCompanionBuilder,
          (DbContactDraftAnswer, $$DbContactDraftAnswersTableReferences),
          DbContactDraftAnswer,
          PrefetchHooks Function({bool draftId})
        > {
  $$DbContactDraftAnswersTableTableManager(
    _$LocalDatabase db,
    $DbContactDraftAnswersTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DbContactDraftAnswersTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$DbContactDraftAnswersTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$DbContactDraftAnswersTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> draftId = const Value.absent(),
                Value<String> questionId = const Value.absent(),
                Value<String> answerState = const Value.absent(),
                Value<String> answerType = const Value.absent(),
                Value<bool?> booleanValue = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DbContactDraftAnswersCompanion(
                draftId: draftId,
                questionId: questionId,
                answerState: answerState,
                answerType: answerType,
                booleanValue: booleanValue,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String draftId,
                required String questionId,
                required String answerState,
                required String answerType,
                Value<bool?> booleanValue = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DbContactDraftAnswersCompanion.insert(
                draftId: draftId,
                questionId: questionId,
                answerState: answerState,
                answerType: answerType,
                booleanValue: booleanValue,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$DbContactDraftAnswersTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({draftId = false}) {
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
                    if (draftId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.draftId,
                                referencedTable:
                                    $$DbContactDraftAnswersTableReferences
                                        ._draftIdTable(db),
                                referencedColumn:
                                    $$DbContactDraftAnswersTableReferences
                                        ._draftIdTable(db)
                                        .draftId,
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

typedef $$DbContactDraftAnswersTableProcessedTableManager =
    ProcessedTableManager<
      _$LocalDatabase,
      $DbContactDraftAnswersTable,
      DbContactDraftAnswer,
      $$DbContactDraftAnswersTableFilterComposer,
      $$DbContactDraftAnswersTableOrderingComposer,
      $$DbContactDraftAnswersTableAnnotationComposer,
      $$DbContactDraftAnswersTableCreateCompanionBuilder,
      $$DbContactDraftAnswersTableUpdateCompanionBuilder,
      (DbContactDraftAnswer, $$DbContactDraftAnswersTableReferences),
      DbContactDraftAnswer,
      PrefetchHooks Function({bool draftId})
    >;
typedef $$DbUsersTableCreateCompanionBuilder =
    DbUsersCompanion Function({
      required String userId,
      required String username,
      required String displayName,
      required String email,
      required String phone,
      Value<DateTime?> birthday,
      Value<String> gender,
      Value<String> occupation,
      Value<String> contactJson,
      required int roleLevel,
      required String cityNamesJson,
      required String teamName,
      required String passwordMd5,
      required String status,
      Value<int> failedLoginCount,
      Value<bool> mustChangePassword,
      Value<DateTime?> lockedUntil,
      Value<DateTime?> lastSeenAt,
      Value<DateTime?> lastFailedLoginAt,
      Value<int> rowid,
    });
typedef $$DbUsersTableUpdateCompanionBuilder =
    DbUsersCompanion Function({
      Value<String> userId,
      Value<String> username,
      Value<String> displayName,
      Value<String> email,
      Value<String> phone,
      Value<DateTime?> birthday,
      Value<String> gender,
      Value<String> occupation,
      Value<String> contactJson,
      Value<int> roleLevel,
      Value<String> cityNamesJson,
      Value<String> teamName,
      Value<String> passwordMd5,
      Value<String> status,
      Value<int> failedLoginCount,
      Value<bool> mustChangePassword,
      Value<DateTime?> lockedUntil,
      Value<DateTime?> lastSeenAt,
      Value<DateTime?> lastFailedLoginAt,
      Value<int> rowid,
    });

class $$DbUsersTableFilterComposer
    extends Composer<_$LocalDatabase, $DbUsersTable> {
  $$DbUsersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get username => $composableBuilder(
    column: $table.username,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get email => $composableBuilder(
    column: $table.email,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get phone => $composableBuilder(
    column: $table.phone,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get birthday => $composableBuilder(
    column: $table.birthday,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get gender => $composableBuilder(
    column: $table.gender,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get occupation => $composableBuilder(
    column: $table.occupation,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get contactJson => $composableBuilder(
    column: $table.contactJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get roleLevel => $composableBuilder(
    column: $table.roleLevel,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get cityNamesJson => $composableBuilder(
    column: $table.cityNamesJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get teamName => $composableBuilder(
    column: $table.teamName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get passwordMd5 => $composableBuilder(
    column: $table.passwordMd5,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get failedLoginCount => $composableBuilder(
    column: $table.failedLoginCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get mustChangePassword => $composableBuilder(
    column: $table.mustChangePassword,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lockedUntil => $composableBuilder(
    column: $table.lockedUntil,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastSeenAt => $composableBuilder(
    column: $table.lastSeenAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastFailedLoginAt => $composableBuilder(
    column: $table.lastFailedLoginAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$DbUsersTableOrderingComposer
    extends Composer<_$LocalDatabase, $DbUsersTable> {
  $$DbUsersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get username => $composableBuilder(
    column: $table.username,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get email => $composableBuilder(
    column: $table.email,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get phone => $composableBuilder(
    column: $table.phone,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get birthday => $composableBuilder(
    column: $table.birthday,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get gender => $composableBuilder(
    column: $table.gender,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get occupation => $composableBuilder(
    column: $table.occupation,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get contactJson => $composableBuilder(
    column: $table.contactJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get roleLevel => $composableBuilder(
    column: $table.roleLevel,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get cityNamesJson => $composableBuilder(
    column: $table.cityNamesJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get teamName => $composableBuilder(
    column: $table.teamName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get passwordMd5 => $composableBuilder(
    column: $table.passwordMd5,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get failedLoginCount => $composableBuilder(
    column: $table.failedLoginCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get mustChangePassword => $composableBuilder(
    column: $table.mustChangePassword,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lockedUntil => $composableBuilder(
    column: $table.lockedUntil,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastSeenAt => $composableBuilder(
    column: $table.lastSeenAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastFailedLoginAt => $composableBuilder(
    column: $table.lastFailedLoginAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$DbUsersTableAnnotationComposer
    extends Composer<_$LocalDatabase, $DbUsersTable> {
  $$DbUsersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<String> get username =>
      $composableBuilder(column: $table.username, builder: (column) => column);

  GeneratedColumn<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get email =>
      $composableBuilder(column: $table.email, builder: (column) => column);

  GeneratedColumn<String> get phone =>
      $composableBuilder(column: $table.phone, builder: (column) => column);

  GeneratedColumn<DateTime> get birthday =>
      $composableBuilder(column: $table.birthday, builder: (column) => column);

  GeneratedColumn<String> get gender =>
      $composableBuilder(column: $table.gender, builder: (column) => column);

  GeneratedColumn<String> get occupation => $composableBuilder(
    column: $table.occupation,
    builder: (column) => column,
  );

  GeneratedColumn<String> get contactJson => $composableBuilder(
    column: $table.contactJson,
    builder: (column) => column,
  );

  GeneratedColumn<int> get roleLevel =>
      $composableBuilder(column: $table.roleLevel, builder: (column) => column);

  GeneratedColumn<String> get cityNamesJson => $composableBuilder(
    column: $table.cityNamesJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get teamName =>
      $composableBuilder(column: $table.teamName, builder: (column) => column);

  GeneratedColumn<String> get passwordMd5 => $composableBuilder(
    column: $table.passwordMd5,
    builder: (column) => column,
  );

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<int> get failedLoginCount => $composableBuilder(
    column: $table.failedLoginCount,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get mustChangePassword => $composableBuilder(
    column: $table.mustChangePassword,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get lockedUntil => $composableBuilder(
    column: $table.lockedUntil,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get lastSeenAt => $composableBuilder(
    column: $table.lastSeenAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get lastFailedLoginAt => $composableBuilder(
    column: $table.lastFailedLoginAt,
    builder: (column) => column,
  );
}

class $$DbUsersTableTableManager
    extends
        RootTableManager<
          _$LocalDatabase,
          $DbUsersTable,
          DbUser,
          $$DbUsersTableFilterComposer,
          $$DbUsersTableOrderingComposer,
          $$DbUsersTableAnnotationComposer,
          $$DbUsersTableCreateCompanionBuilder,
          $$DbUsersTableUpdateCompanionBuilder,
          (DbUser, BaseReferences<_$LocalDatabase, $DbUsersTable, DbUser>),
          DbUser,
          PrefetchHooks Function()
        > {
  $$DbUsersTableTableManager(_$LocalDatabase db, $DbUsersTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DbUsersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DbUsersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DbUsersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> userId = const Value.absent(),
                Value<String> username = const Value.absent(),
                Value<String> displayName = const Value.absent(),
                Value<String> email = const Value.absent(),
                Value<String> phone = const Value.absent(),
                Value<DateTime?> birthday = const Value.absent(),
                Value<String> gender = const Value.absent(),
                Value<String> occupation = const Value.absent(),
                Value<String> contactJson = const Value.absent(),
                Value<int> roleLevel = const Value.absent(),
                Value<String> cityNamesJson = const Value.absent(),
                Value<String> teamName = const Value.absent(),
                Value<String> passwordMd5 = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<int> failedLoginCount = const Value.absent(),
                Value<bool> mustChangePassword = const Value.absent(),
                Value<DateTime?> lockedUntil = const Value.absent(),
                Value<DateTime?> lastSeenAt = const Value.absent(),
                Value<DateTime?> lastFailedLoginAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DbUsersCompanion(
                userId: userId,
                username: username,
                displayName: displayName,
                email: email,
                phone: phone,
                birthday: birthday,
                gender: gender,
                occupation: occupation,
                contactJson: contactJson,
                roleLevel: roleLevel,
                cityNamesJson: cityNamesJson,
                teamName: teamName,
                passwordMd5: passwordMd5,
                status: status,
                failedLoginCount: failedLoginCount,
                mustChangePassword: mustChangePassword,
                lockedUntil: lockedUntil,
                lastSeenAt: lastSeenAt,
                lastFailedLoginAt: lastFailedLoginAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String userId,
                required String username,
                required String displayName,
                required String email,
                required String phone,
                Value<DateTime?> birthday = const Value.absent(),
                Value<String> gender = const Value.absent(),
                Value<String> occupation = const Value.absent(),
                Value<String> contactJson = const Value.absent(),
                required int roleLevel,
                required String cityNamesJson,
                required String teamName,
                required String passwordMd5,
                required String status,
                Value<int> failedLoginCount = const Value.absent(),
                Value<bool> mustChangePassword = const Value.absent(),
                Value<DateTime?> lockedUntil = const Value.absent(),
                Value<DateTime?> lastSeenAt = const Value.absent(),
                Value<DateTime?> lastFailedLoginAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DbUsersCompanion.insert(
                userId: userId,
                username: username,
                displayName: displayName,
                email: email,
                phone: phone,
                birthday: birthday,
                gender: gender,
                occupation: occupation,
                contactJson: contactJson,
                roleLevel: roleLevel,
                cityNamesJson: cityNamesJson,
                teamName: teamName,
                passwordMd5: passwordMd5,
                status: status,
                failedLoginCount: failedLoginCount,
                mustChangePassword: mustChangePassword,
                lockedUntil: lockedUntil,
                lastSeenAt: lastSeenAt,
                lastFailedLoginAt: lastFailedLoginAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$DbUsersTableProcessedTableManager =
    ProcessedTableManager<
      _$LocalDatabase,
      $DbUsersTable,
      DbUser,
      $$DbUsersTableFilterComposer,
      $$DbUsersTableOrderingComposer,
      $$DbUsersTableAnnotationComposer,
      $$DbUsersTableCreateCompanionBuilder,
      $$DbUsersTableUpdateCompanionBuilder,
      (DbUser, BaseReferences<_$LocalDatabase, $DbUsersTable, DbUser>),
      DbUser,
      PrefetchHooks Function()
    >;
typedef $$DbConversationRecordsTableCreateCompanionBuilder =
    DbConversationRecordsCompanion Function({
      required String recordId,
      required DateTime createdAt,
      required String collectorUserId,
      required String cityName,
      Value<String> areaName,
      required String teamName,
      required String recorderName,
      required String personName,
      required String englishName,
      Value<double?> averageHeartRate,
      Value<double?> latitude,
      Value<double?> longitude,
      Value<double?> locationAccuracyMeters,
      Value<String?> locationError,
      required String manualPlaceName,
      required String gender,
      required String identity,
      required String ageRange,
      Value<int> relationshipLevel,
      Value<int> interestLevel,
      required int attitudeLevel,
      required String notes,
      Value<bool> isLocationVerified,
      Value<double?> correctedLatitude,
      Value<double?> correctedLongitude,
      Value<String?> correctedPlaceName,
      Value<DateTime?> correctedAt,
      Value<int> rowid,
    });
typedef $$DbConversationRecordsTableUpdateCompanionBuilder =
    DbConversationRecordsCompanion Function({
      Value<String> recordId,
      Value<DateTime> createdAt,
      Value<String> collectorUserId,
      Value<String> cityName,
      Value<String> areaName,
      Value<String> teamName,
      Value<String> recorderName,
      Value<String> personName,
      Value<String> englishName,
      Value<double?> averageHeartRate,
      Value<double?> latitude,
      Value<double?> longitude,
      Value<double?> locationAccuracyMeters,
      Value<String?> locationError,
      Value<String> manualPlaceName,
      Value<String> gender,
      Value<String> identity,
      Value<String> ageRange,
      Value<int> relationshipLevel,
      Value<int> interestLevel,
      Value<int> attitudeLevel,
      Value<String> notes,
      Value<bool> isLocationVerified,
      Value<double?> correctedLatitude,
      Value<double?> correctedLongitude,
      Value<String?> correctedPlaceName,
      Value<DateTime?> correctedAt,
      Value<int> rowid,
    });

class $$DbConversationRecordsTableFilterComposer
    extends Composer<_$LocalDatabase, $DbConversationRecordsTable> {
  $$DbConversationRecordsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get recordId => $composableBuilder(
    column: $table.recordId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get collectorUserId => $composableBuilder(
    column: $table.collectorUserId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get cityName => $composableBuilder(
    column: $table.cityName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get areaName => $composableBuilder(
    column: $table.areaName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get teamName => $composableBuilder(
    column: $table.teamName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get recorderName => $composableBuilder(
    column: $table.recorderName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get personName => $composableBuilder(
    column: $table.personName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get englishName => $composableBuilder(
    column: $table.englishName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get averageHeartRate => $composableBuilder(
    column: $table.averageHeartRate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get latitude => $composableBuilder(
    column: $table.latitude,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get longitude => $composableBuilder(
    column: $table.longitude,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get locationAccuracyMeters => $composableBuilder(
    column: $table.locationAccuracyMeters,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get locationError => $composableBuilder(
    column: $table.locationError,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get manualPlaceName => $composableBuilder(
    column: $table.manualPlaceName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get gender => $composableBuilder(
    column: $table.gender,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get identity => $composableBuilder(
    column: $table.identity,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get ageRange => $composableBuilder(
    column: $table.ageRange,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get relationshipLevel => $composableBuilder(
    column: $table.relationshipLevel,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get interestLevel => $composableBuilder(
    column: $table.interestLevel,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get attitudeLevel => $composableBuilder(
    column: $table.attitudeLevel,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isLocationVerified => $composableBuilder(
    column: $table.isLocationVerified,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get correctedLatitude => $composableBuilder(
    column: $table.correctedLatitude,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get correctedLongitude => $composableBuilder(
    column: $table.correctedLongitude,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get correctedPlaceName => $composableBuilder(
    column: $table.correctedPlaceName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get correctedAt => $composableBuilder(
    column: $table.correctedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$DbConversationRecordsTableOrderingComposer
    extends Composer<_$LocalDatabase, $DbConversationRecordsTable> {
  $$DbConversationRecordsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get recordId => $composableBuilder(
    column: $table.recordId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get collectorUserId => $composableBuilder(
    column: $table.collectorUserId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get cityName => $composableBuilder(
    column: $table.cityName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get areaName => $composableBuilder(
    column: $table.areaName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get teamName => $composableBuilder(
    column: $table.teamName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get recorderName => $composableBuilder(
    column: $table.recorderName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get personName => $composableBuilder(
    column: $table.personName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get englishName => $composableBuilder(
    column: $table.englishName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get averageHeartRate => $composableBuilder(
    column: $table.averageHeartRate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get latitude => $composableBuilder(
    column: $table.latitude,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get longitude => $composableBuilder(
    column: $table.longitude,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get locationAccuracyMeters => $composableBuilder(
    column: $table.locationAccuracyMeters,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get locationError => $composableBuilder(
    column: $table.locationError,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get manualPlaceName => $composableBuilder(
    column: $table.manualPlaceName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get gender => $composableBuilder(
    column: $table.gender,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get identity => $composableBuilder(
    column: $table.identity,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get ageRange => $composableBuilder(
    column: $table.ageRange,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get relationshipLevel => $composableBuilder(
    column: $table.relationshipLevel,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get interestLevel => $composableBuilder(
    column: $table.interestLevel,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get attitudeLevel => $composableBuilder(
    column: $table.attitudeLevel,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isLocationVerified => $composableBuilder(
    column: $table.isLocationVerified,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get correctedLatitude => $composableBuilder(
    column: $table.correctedLatitude,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get correctedLongitude => $composableBuilder(
    column: $table.correctedLongitude,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get correctedPlaceName => $composableBuilder(
    column: $table.correctedPlaceName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get correctedAt => $composableBuilder(
    column: $table.correctedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$DbConversationRecordsTableAnnotationComposer
    extends Composer<_$LocalDatabase, $DbConversationRecordsTable> {
  $$DbConversationRecordsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get recordId =>
      $composableBuilder(column: $table.recordId, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<String> get collectorUserId => $composableBuilder(
    column: $table.collectorUserId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get cityName =>
      $composableBuilder(column: $table.cityName, builder: (column) => column);

  GeneratedColumn<String> get areaName =>
      $composableBuilder(column: $table.areaName, builder: (column) => column);

  GeneratedColumn<String> get teamName =>
      $composableBuilder(column: $table.teamName, builder: (column) => column);

  GeneratedColumn<String> get recorderName => $composableBuilder(
    column: $table.recorderName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get personName => $composableBuilder(
    column: $table.personName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get englishName => $composableBuilder(
    column: $table.englishName,
    builder: (column) => column,
  );

  GeneratedColumn<double> get averageHeartRate => $composableBuilder(
    column: $table.averageHeartRate,
    builder: (column) => column,
  );

  GeneratedColumn<double> get latitude =>
      $composableBuilder(column: $table.latitude, builder: (column) => column);

  GeneratedColumn<double> get longitude =>
      $composableBuilder(column: $table.longitude, builder: (column) => column);

  GeneratedColumn<double> get locationAccuracyMeters => $composableBuilder(
    column: $table.locationAccuracyMeters,
    builder: (column) => column,
  );

  GeneratedColumn<String> get locationError => $composableBuilder(
    column: $table.locationError,
    builder: (column) => column,
  );

  GeneratedColumn<String> get manualPlaceName => $composableBuilder(
    column: $table.manualPlaceName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get gender =>
      $composableBuilder(column: $table.gender, builder: (column) => column);

  GeneratedColumn<String> get identity =>
      $composableBuilder(column: $table.identity, builder: (column) => column);

  GeneratedColumn<String> get ageRange =>
      $composableBuilder(column: $table.ageRange, builder: (column) => column);

  GeneratedColumn<int> get relationshipLevel => $composableBuilder(
    column: $table.relationshipLevel,
    builder: (column) => column,
  );

  GeneratedColumn<int> get interestLevel => $composableBuilder(
    column: $table.interestLevel,
    builder: (column) => column,
  );

  GeneratedColumn<int> get attitudeLevel => $composableBuilder(
    column: $table.attitudeLevel,
    builder: (column) => column,
  );

  GeneratedColumn<String> get notes =>
      $composableBuilder(column: $table.notes, builder: (column) => column);

  GeneratedColumn<bool> get isLocationVerified => $composableBuilder(
    column: $table.isLocationVerified,
    builder: (column) => column,
  );

  GeneratedColumn<double> get correctedLatitude => $composableBuilder(
    column: $table.correctedLatitude,
    builder: (column) => column,
  );

  GeneratedColumn<double> get correctedLongitude => $composableBuilder(
    column: $table.correctedLongitude,
    builder: (column) => column,
  );

  GeneratedColumn<String> get correctedPlaceName => $composableBuilder(
    column: $table.correctedPlaceName,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get correctedAt => $composableBuilder(
    column: $table.correctedAt,
    builder: (column) => column,
  );
}

class $$DbConversationRecordsTableTableManager
    extends
        RootTableManager<
          _$LocalDatabase,
          $DbConversationRecordsTable,
          DbConversationRecord,
          $$DbConversationRecordsTableFilterComposer,
          $$DbConversationRecordsTableOrderingComposer,
          $$DbConversationRecordsTableAnnotationComposer,
          $$DbConversationRecordsTableCreateCompanionBuilder,
          $$DbConversationRecordsTableUpdateCompanionBuilder,
          (
            DbConversationRecord,
            BaseReferences<
              _$LocalDatabase,
              $DbConversationRecordsTable,
              DbConversationRecord
            >,
          ),
          DbConversationRecord,
          PrefetchHooks Function()
        > {
  $$DbConversationRecordsTableTableManager(
    _$LocalDatabase db,
    $DbConversationRecordsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DbConversationRecordsTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$DbConversationRecordsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$DbConversationRecordsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> recordId = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<String> collectorUserId = const Value.absent(),
                Value<String> cityName = const Value.absent(),
                Value<String> areaName = const Value.absent(),
                Value<String> teamName = const Value.absent(),
                Value<String> recorderName = const Value.absent(),
                Value<String> personName = const Value.absent(),
                Value<String> englishName = const Value.absent(),
                Value<double?> averageHeartRate = const Value.absent(),
                Value<double?> latitude = const Value.absent(),
                Value<double?> longitude = const Value.absent(),
                Value<double?> locationAccuracyMeters = const Value.absent(),
                Value<String?> locationError = const Value.absent(),
                Value<String> manualPlaceName = const Value.absent(),
                Value<String> gender = const Value.absent(),
                Value<String> identity = const Value.absent(),
                Value<String> ageRange = const Value.absent(),
                Value<int> relationshipLevel = const Value.absent(),
                Value<int> interestLevel = const Value.absent(),
                Value<int> attitudeLevel = const Value.absent(),
                Value<String> notes = const Value.absent(),
                Value<bool> isLocationVerified = const Value.absent(),
                Value<double?> correctedLatitude = const Value.absent(),
                Value<double?> correctedLongitude = const Value.absent(),
                Value<String?> correctedPlaceName = const Value.absent(),
                Value<DateTime?> correctedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DbConversationRecordsCompanion(
                recordId: recordId,
                createdAt: createdAt,
                collectorUserId: collectorUserId,
                cityName: cityName,
                areaName: areaName,
                teamName: teamName,
                recorderName: recorderName,
                personName: personName,
                englishName: englishName,
                averageHeartRate: averageHeartRate,
                latitude: latitude,
                longitude: longitude,
                locationAccuracyMeters: locationAccuracyMeters,
                locationError: locationError,
                manualPlaceName: manualPlaceName,
                gender: gender,
                identity: identity,
                ageRange: ageRange,
                relationshipLevel: relationshipLevel,
                interestLevel: interestLevel,
                attitudeLevel: attitudeLevel,
                notes: notes,
                isLocationVerified: isLocationVerified,
                correctedLatitude: correctedLatitude,
                correctedLongitude: correctedLongitude,
                correctedPlaceName: correctedPlaceName,
                correctedAt: correctedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String recordId,
                required DateTime createdAt,
                required String collectorUserId,
                required String cityName,
                Value<String> areaName = const Value.absent(),
                required String teamName,
                required String recorderName,
                required String personName,
                required String englishName,
                Value<double?> averageHeartRate = const Value.absent(),
                Value<double?> latitude = const Value.absent(),
                Value<double?> longitude = const Value.absent(),
                Value<double?> locationAccuracyMeters = const Value.absent(),
                Value<String?> locationError = const Value.absent(),
                required String manualPlaceName,
                required String gender,
                required String identity,
                required String ageRange,
                Value<int> relationshipLevel = const Value.absent(),
                Value<int> interestLevel = const Value.absent(),
                required int attitudeLevel,
                required String notes,
                Value<bool> isLocationVerified = const Value.absent(),
                Value<double?> correctedLatitude = const Value.absent(),
                Value<double?> correctedLongitude = const Value.absent(),
                Value<String?> correctedPlaceName = const Value.absent(),
                Value<DateTime?> correctedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DbConversationRecordsCompanion.insert(
                recordId: recordId,
                createdAt: createdAt,
                collectorUserId: collectorUserId,
                cityName: cityName,
                areaName: areaName,
                teamName: teamName,
                recorderName: recorderName,
                personName: personName,
                englishName: englishName,
                averageHeartRate: averageHeartRate,
                latitude: latitude,
                longitude: longitude,
                locationAccuracyMeters: locationAccuracyMeters,
                locationError: locationError,
                manualPlaceName: manualPlaceName,
                gender: gender,
                identity: identity,
                ageRange: ageRange,
                relationshipLevel: relationshipLevel,
                interestLevel: interestLevel,
                attitudeLevel: attitudeLevel,
                notes: notes,
                isLocationVerified: isLocationVerified,
                correctedLatitude: correctedLatitude,
                correctedLongitude: correctedLongitude,
                correctedPlaceName: correctedPlaceName,
                correctedAt: correctedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$DbConversationRecordsTableProcessedTableManager =
    ProcessedTableManager<
      _$LocalDatabase,
      $DbConversationRecordsTable,
      DbConversationRecord,
      $$DbConversationRecordsTableFilterComposer,
      $$DbConversationRecordsTableOrderingComposer,
      $$DbConversationRecordsTableAnnotationComposer,
      $$DbConversationRecordsTableCreateCompanionBuilder,
      $$DbConversationRecordsTableUpdateCompanionBuilder,
      (
        DbConversationRecord,
        BaseReferences<
          _$LocalDatabase,
          $DbConversationRecordsTable,
          DbConversationRecord
        >,
      ),
      DbConversationRecord,
      PrefetchHooks Function()
    >;
typedef $$DbRecordContactsTableCreateCompanionBuilder =
    DbRecordContactsCompanion Function({
      required String contactId,
      required String recordId,
      required String channel,
      required String value,
      required DateTime createdAt,
      Value<int> rowid,
    });
typedef $$DbRecordContactsTableUpdateCompanionBuilder =
    DbRecordContactsCompanion Function({
      Value<String> contactId,
      Value<String> recordId,
      Value<String> channel,
      Value<String> value,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });

class $$DbRecordContactsTableFilterComposer
    extends Composer<_$LocalDatabase, $DbRecordContactsTable> {
  $$DbRecordContactsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get contactId => $composableBuilder(
    column: $table.contactId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get recordId => $composableBuilder(
    column: $table.recordId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get channel => $composableBuilder(
    column: $table.channel,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$DbRecordContactsTableOrderingComposer
    extends Composer<_$LocalDatabase, $DbRecordContactsTable> {
  $$DbRecordContactsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get contactId => $composableBuilder(
    column: $table.contactId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get recordId => $composableBuilder(
    column: $table.recordId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get channel => $composableBuilder(
    column: $table.channel,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$DbRecordContactsTableAnnotationComposer
    extends Composer<_$LocalDatabase, $DbRecordContactsTable> {
  $$DbRecordContactsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get contactId =>
      $composableBuilder(column: $table.contactId, builder: (column) => column);

  GeneratedColumn<String> get recordId =>
      $composableBuilder(column: $table.recordId, builder: (column) => column);

  GeneratedColumn<String> get channel =>
      $composableBuilder(column: $table.channel, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$DbRecordContactsTableTableManager
    extends
        RootTableManager<
          _$LocalDatabase,
          $DbRecordContactsTable,
          DbRecordContact,
          $$DbRecordContactsTableFilterComposer,
          $$DbRecordContactsTableOrderingComposer,
          $$DbRecordContactsTableAnnotationComposer,
          $$DbRecordContactsTableCreateCompanionBuilder,
          $$DbRecordContactsTableUpdateCompanionBuilder,
          (
            DbRecordContact,
            BaseReferences<
              _$LocalDatabase,
              $DbRecordContactsTable,
              DbRecordContact
            >,
          ),
          DbRecordContact,
          PrefetchHooks Function()
        > {
  $$DbRecordContactsTableTableManager(
    _$LocalDatabase db,
    $DbRecordContactsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DbRecordContactsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DbRecordContactsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DbRecordContactsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> contactId = const Value.absent(),
                Value<String> recordId = const Value.absent(),
                Value<String> channel = const Value.absent(),
                Value<String> value = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DbRecordContactsCompanion(
                contactId: contactId,
                recordId: recordId,
                channel: channel,
                value: value,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String contactId,
                required String recordId,
                required String channel,
                required String value,
                required DateTime createdAt,
                Value<int> rowid = const Value.absent(),
              }) => DbRecordContactsCompanion.insert(
                contactId: contactId,
                recordId: recordId,
                channel: channel,
                value: value,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$DbRecordContactsTableProcessedTableManager =
    ProcessedTableManager<
      _$LocalDatabase,
      $DbRecordContactsTable,
      DbRecordContact,
      $$DbRecordContactsTableFilterComposer,
      $$DbRecordContactsTableOrderingComposer,
      $$DbRecordContactsTableAnnotationComposer,
      $$DbRecordContactsTableCreateCompanionBuilder,
      $$DbRecordContactsTableUpdateCompanionBuilder,
      (
        DbRecordContact,
        BaseReferences<
          _$LocalDatabase,
          $DbRecordContactsTable,
          DbRecordContact
        >,
      ),
      DbRecordContact,
      PrefetchHooks Function()
    >;
typedef $$DbAppSettingsTableCreateCompanionBuilder =
    DbAppSettingsCompanion Function({
      required String key,
      required String value,
      Value<int> rowid,
    });
typedef $$DbAppSettingsTableUpdateCompanionBuilder =
    DbAppSettingsCompanion Function({
      Value<String> key,
      Value<String> value,
      Value<int> rowid,
    });

class $$DbAppSettingsTableFilterComposer
    extends Composer<_$LocalDatabase, $DbAppSettingsTable> {
  $$DbAppSettingsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );
}

class $$DbAppSettingsTableOrderingComposer
    extends Composer<_$LocalDatabase, $DbAppSettingsTable> {
  $$DbAppSettingsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$DbAppSettingsTableAnnotationComposer
    extends Composer<_$LocalDatabase, $DbAppSettingsTable> {
  $$DbAppSettingsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);
}

class $$DbAppSettingsTableTableManager
    extends
        RootTableManager<
          _$LocalDatabase,
          $DbAppSettingsTable,
          DbAppSetting,
          $$DbAppSettingsTableFilterComposer,
          $$DbAppSettingsTableOrderingComposer,
          $$DbAppSettingsTableAnnotationComposer,
          $$DbAppSettingsTableCreateCompanionBuilder,
          $$DbAppSettingsTableUpdateCompanionBuilder,
          (
            DbAppSetting,
            BaseReferences<_$LocalDatabase, $DbAppSettingsTable, DbAppSetting>,
          ),
          DbAppSetting,
          PrefetchHooks Function()
        > {
  $$DbAppSettingsTableTableManager(
    _$LocalDatabase db,
    $DbAppSettingsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DbAppSettingsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DbAppSettingsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DbAppSettingsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> key = const Value.absent(),
                Value<String> value = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) =>
                  DbAppSettingsCompanion(key: key, value: value, rowid: rowid),
          createCompanionCallback:
              ({
                required String key,
                required String value,
                Value<int> rowid = const Value.absent(),
              }) => DbAppSettingsCompanion.insert(
                key: key,
                value: value,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$DbAppSettingsTableProcessedTableManager =
    ProcessedTableManager<
      _$LocalDatabase,
      $DbAppSettingsTable,
      DbAppSetting,
      $$DbAppSettingsTableFilterComposer,
      $$DbAppSettingsTableOrderingComposer,
      $$DbAppSettingsTableAnnotationComposer,
      $$DbAppSettingsTableCreateCompanionBuilder,
      $$DbAppSettingsTableUpdateCompanionBuilder,
      (
        DbAppSetting,
        BaseReferences<_$LocalDatabase, $DbAppSettingsTable, DbAppSetting>,
      ),
      DbAppSetting,
      PrefetchHooks Function()
    >;
typedef $$DbSecurityEventsTableCreateCompanionBuilder =
    DbSecurityEventsCompanion Function({
      required String eventId,
      Value<String?> userId,
      required String eventType,
      required String eventDetailJson,
      required DateTime createdAt,
      Value<int> rowid,
    });
typedef $$DbSecurityEventsTableUpdateCompanionBuilder =
    DbSecurityEventsCompanion Function({
      Value<String> eventId,
      Value<String?> userId,
      Value<String> eventType,
      Value<String> eventDetailJson,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });

class $$DbSecurityEventsTableFilterComposer
    extends Composer<_$LocalDatabase, $DbSecurityEventsTable> {
  $$DbSecurityEventsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get eventId => $composableBuilder(
    column: $table.eventId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get eventType => $composableBuilder(
    column: $table.eventType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get eventDetailJson => $composableBuilder(
    column: $table.eventDetailJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$DbSecurityEventsTableOrderingComposer
    extends Composer<_$LocalDatabase, $DbSecurityEventsTable> {
  $$DbSecurityEventsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get eventId => $composableBuilder(
    column: $table.eventId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get eventType => $composableBuilder(
    column: $table.eventType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get eventDetailJson => $composableBuilder(
    column: $table.eventDetailJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$DbSecurityEventsTableAnnotationComposer
    extends Composer<_$LocalDatabase, $DbSecurityEventsTable> {
  $$DbSecurityEventsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get eventId =>
      $composableBuilder(column: $table.eventId, builder: (column) => column);

  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<String> get eventType =>
      $composableBuilder(column: $table.eventType, builder: (column) => column);

  GeneratedColumn<String> get eventDetailJson => $composableBuilder(
    column: $table.eventDetailJson,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$DbSecurityEventsTableTableManager
    extends
        RootTableManager<
          _$LocalDatabase,
          $DbSecurityEventsTable,
          DbSecurityEvent,
          $$DbSecurityEventsTableFilterComposer,
          $$DbSecurityEventsTableOrderingComposer,
          $$DbSecurityEventsTableAnnotationComposer,
          $$DbSecurityEventsTableCreateCompanionBuilder,
          $$DbSecurityEventsTableUpdateCompanionBuilder,
          (
            DbSecurityEvent,
            BaseReferences<
              _$LocalDatabase,
              $DbSecurityEventsTable,
              DbSecurityEvent
            >,
          ),
          DbSecurityEvent,
          PrefetchHooks Function()
        > {
  $$DbSecurityEventsTableTableManager(
    _$LocalDatabase db,
    $DbSecurityEventsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DbSecurityEventsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DbSecurityEventsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DbSecurityEventsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> eventId = const Value.absent(),
                Value<String?> userId = const Value.absent(),
                Value<String> eventType = const Value.absent(),
                Value<String> eventDetailJson = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DbSecurityEventsCompanion(
                eventId: eventId,
                userId: userId,
                eventType: eventType,
                eventDetailJson: eventDetailJson,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String eventId,
                Value<String?> userId = const Value.absent(),
                required String eventType,
                required String eventDetailJson,
                required DateTime createdAt,
                Value<int> rowid = const Value.absent(),
              }) => DbSecurityEventsCompanion.insert(
                eventId: eventId,
                userId: userId,
                eventType: eventType,
                eventDetailJson: eventDetailJson,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$DbSecurityEventsTableProcessedTableManager =
    ProcessedTableManager<
      _$LocalDatabase,
      $DbSecurityEventsTable,
      DbSecurityEvent,
      $$DbSecurityEventsTableFilterComposer,
      $$DbSecurityEventsTableOrderingComposer,
      $$DbSecurityEventsTableAnnotationComposer,
      $$DbSecurityEventsTableCreateCompanionBuilder,
      $$DbSecurityEventsTableUpdateCompanionBuilder,
      (
        DbSecurityEvent,
        BaseReferences<
          _$LocalDatabase,
          $DbSecurityEventsTable,
          DbSecurityEvent
        >,
      ),
      DbSecurityEvent,
      PrefetchHooks Function()
    >;

class $LocalDatabaseManager {
  final _$LocalDatabase _db;
  $LocalDatabaseManager(this._db);
  $$DbSyncOutboxTableTableManager get dbSyncOutbox =>
      $$DbSyncOutboxTableTableManager(_db, _db.dbSyncOutbox);
  $$DbContactRecordsTableTableManager get dbContactRecords =>
      $$DbContactRecordsTableTableManager(_db, _db.dbContactRecords);
  $$DbSyncDrainerLeasesTableTableManager get dbSyncDrainerLeases =>
      $$DbSyncDrainerLeasesTableTableManager(_db, _db.dbSyncDrainerLeases);
  $$DbSyncScopesTableTableManager get dbSyncScopes =>
      $$DbSyncScopesTableTableManager(_db, _db.dbSyncScopes);
  $$DbContactRevisionsTableTableManager get dbContactRevisions =>
      $$DbContactRevisionsTableTableManager(_db, _db.dbContactRevisions);
  $$DbContactAnswersTableTableManager get dbContactAnswers =>
      $$DbContactAnswersTableTableManager(_db, _db.dbContactAnswers);
  $$DbContactDraftsTableTableManager get dbContactDrafts =>
      $$DbContactDraftsTableTableManager(_db, _db.dbContactDrafts);
  $$DbContactDraftAnswersTableTableManager get dbContactDraftAnswers =>
      $$DbContactDraftAnswersTableTableManager(_db, _db.dbContactDraftAnswers);
  $$DbUsersTableTableManager get dbUsers =>
      $$DbUsersTableTableManager(_db, _db.dbUsers);
  $$DbConversationRecordsTableTableManager get dbConversationRecords =>
      $$DbConversationRecordsTableTableManager(_db, _db.dbConversationRecords);
  $$DbRecordContactsTableTableManager get dbRecordContacts =>
      $$DbRecordContactsTableTableManager(_db, _db.dbRecordContacts);
  $$DbAppSettingsTableTableManager get dbAppSettings =>
      $$DbAppSettingsTableTableManager(_db, _db.dbAppSettings);
  $$DbSecurityEventsTableTableManager get dbSecurityEvents =>
      $$DbSecurityEventsTableTableManager(_db, _db.dbSecurityEvents);
}

class ReadSyncHealthResult {
  final int onlyOnDeviceCount;
  final int syncingCount;
  final int retryingCount;
  final int needsResolutionCount;
  final int permanentFailureCount;
  final int completedCount;
  final DateTime? oldestPendingAtUtc;
  ReadSyncHealthResult({
    required this.onlyOnDeviceCount,
    required this.syncingCount,
    required this.retryingCount,
    required this.needsResolutionCount,
    required this.permanentFailureCount,
    required this.completedCount,
    this.oldestPendingAtUtc,
  });
}

class ReadPersonalContactSummaryResult {
  final int contactSessionCount;
  final int reachCount;
  final int interest0Count;
  final int interest1Count;
  final int interest2Count;
  final int interest3Count;
  final int interest4Count;
  final int pendingSyncCount;
  final DateTime? latestOccurredAtUtc;
  ReadPersonalContactSummaryResult({
    required this.contactSessionCount,
    required this.reachCount,
    required this.interest0Count,
    required this.interest1Count,
    required this.interest2Count,
    required this.interest3Count,
    required this.interest4Count,
    required this.pendingSyncCount,
    this.latestOccurredAtUtc,
  });
}

class ReadPersonalContactChannelSummaryResult {
  final String channel;
  final int contactSessionCount;
  ReadPersonalContactChannelSummaryResult({
    required this.channel,
    required this.contactSessionCount,
  });
}
