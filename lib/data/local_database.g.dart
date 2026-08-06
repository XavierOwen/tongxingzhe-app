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
  static const VerificationMeta _appUserIdMeta = const VerificationMeta(
    'appUserId',
  );
  @override
  late final GeneratedColumn<String> appUserId = GeneratedColumn<String>(
    'app_user_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _workspaceIdMeta = const VerificationMeta(
    'workspaceId',
  );
  @override
  late final GeneratedColumn<String> workspaceId = GeneratedColumn<String>(
    'workspace_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _projectIdMeta = const VerificationMeta(
    'projectId',
  );
  @override
  late final GeneratedColumn<String> projectId = GeneratedColumn<String>(
    'project_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
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
    appUserId,
    workspaceId,
    projectId,
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
    if (data.containsKey('app_user_id')) {
      context.handle(
        _appUserIdMeta,
        appUserId.isAcceptableOrUnknown(data['app_user_id']!, _appUserIdMeta),
      );
    }
    if (data.containsKey('workspace_id')) {
      context.handle(
        _workspaceIdMeta,
        workspaceId.isAcceptableOrUnknown(
          data['workspace_id']!,
          _workspaceIdMeta,
        ),
      );
    }
    if (data.containsKey('project_id')) {
      context.handle(
        _projectIdMeta,
        projectId.isAcceptableOrUnknown(data['project_id']!, _projectIdMeta),
      );
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
      appUserId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}app_user_id'],
      ),
      workspaceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}workspace_id'],
      ),
      projectId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}project_id'],
      ),
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
  final String? appUserId;
  final String? workspaceId;
  final String? projectId;
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
    this.appUserId,
    this.workspaceId,
    this.projectId,
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
    if (!nullToAbsent || appUserId != null) {
      map['app_user_id'] = Variable<String>(appUserId);
    }
    if (!nullToAbsent || workspaceId != null) {
      map['workspace_id'] = Variable<String>(workspaceId);
    }
    if (!nullToAbsent || projectId != null) {
      map['project_id'] = Variable<String>(projectId);
    }
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
      appUserId: appUserId == null && nullToAbsent
          ? const Value.absent()
          : Value(appUserId),
      workspaceId: workspaceId == null && nullToAbsent
          ? const Value.absent()
          : Value(workspaceId),
      projectId: projectId == null && nullToAbsent
          ? const Value.absent()
          : Value(projectId),
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
      appUserId: serializer.fromJson<String?>(json['appUserId']),
      workspaceId: serializer.fromJson<String?>(json['workspaceId']),
      projectId: serializer.fromJson<String?>(json['projectId']),
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
      'appUserId': serializer.toJson<String?>(appUserId),
      'workspaceId': serializer.toJson<String?>(workspaceId),
      'projectId': serializer.toJson<String?>(projectId),
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
    Value<String?> appUserId = const Value.absent(),
    Value<String?> workspaceId = const Value.absent(),
    Value<String?> projectId = const Value.absent(),
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
    appUserId: appUserId.present ? appUserId.value : this.appUserId,
    workspaceId: workspaceId.present ? workspaceId.value : this.workspaceId,
    projectId: projectId.present ? projectId.value : this.projectId,
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
      appUserId: data.appUserId.present ? data.appUserId.value : this.appUserId,
      workspaceId: data.workspaceId.present
          ? data.workspaceId.value
          : this.workspaceId,
      projectId: data.projectId.present ? data.projectId.value : this.projectId,
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
          ..write('appUserId: $appUserId, ')
          ..write('workspaceId: $workspaceId, ')
          ..write('projectId: $projectId, ')
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
    appUserId,
    workspaceId,
    projectId,
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
          other.appUserId == this.appUserId &&
          other.workspaceId == this.workspaceId &&
          other.projectId == this.projectId &&
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
  final Value<String?> appUserId;
  final Value<String?> workspaceId;
  final Value<String?> projectId;
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
    this.appUserId = const Value.absent(),
    this.workspaceId = const Value.absent(),
    this.projectId = const Value.absent(),
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
    this.appUserId = const Value.absent(),
    this.workspaceId = const Value.absent(),
    this.projectId = const Value.absent(),
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
    Expression<String>? appUserId,
    Expression<String>? workspaceId,
    Expression<String>? projectId,
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
      if (appUserId != null) 'app_user_id': appUserId,
      if (workspaceId != null) 'workspace_id': workspaceId,
      if (projectId != null) 'project_id': projectId,
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
    Value<String?>? appUserId,
    Value<String?>? workspaceId,
    Value<String?>? projectId,
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
      appUserId: appUserId ?? this.appUserId,
      workspaceId: workspaceId ?? this.workspaceId,
      projectId: projectId ?? this.projectId,
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
    if (appUserId.present) {
      map['app_user_id'] = Variable<String>(appUserId.value);
    }
    if (workspaceId.present) {
      map['workspace_id'] = Variable<String>(workspaceId.value);
    }
    if (projectId.present) {
      map['project_id'] = Variable<String>(projectId.value);
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
          ..write('appUserId: $appUserId, ')
          ..write('workspaceId: $workspaceId, ')
          ..write('projectId: $projectId, ')
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
  static const VerificationMeta _regionTreeVersionMeta = const VerificationMeta(
    'regionTreeVersion',
  );
  @override
  late final GeneratedColumn<String> regionTreeVersion =
      GeneratedColumn<String>(
        'region_tree_version',
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
    regionTreeVersion,
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
    if (data.containsKey('region_tree_version')) {
      context.handle(
        _regionTreeVersionMeta,
        regionTreeVersion.isAcceptableOrUnknown(
          data['region_tree_version']!,
          _regionTreeVersionMeta,
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
      regionTreeVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}region_tree_version'],
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
  final String? regionTreeVersion;
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
    this.regionTreeVersion,
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
    if (!nullToAbsent || regionTreeVersion != null) {
      map['region_tree_version'] = Variable<String>(regionTreeVersion);
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
      regionTreeVersion: regionTreeVersion == null && nullToAbsent
          ? const Value.absent()
          : Value(regionTreeVersion),
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
      regionTreeVersion: serializer.fromJson<String?>(
        json['regionTreeVersion'],
      ),
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
      'regionTreeVersion': serializer.toJson<String?>(regionTreeVersion),
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
    Value<String?> regionTreeVersion = const Value.absent(),
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
    regionTreeVersion: regionTreeVersion.present
        ? regionTreeVersion.value
        : this.regionTreeVersion,
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
      regionTreeVersion: data.regionTreeVersion.present
          ? data.regionTreeVersion.value
          : this.regionTreeVersion,
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
          ..write('regionTreeVersion: $regionTreeVersion, ')
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
  int get hashCode => Object.hashAll([
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
    regionTreeVersion,
    latitude,
    longitude,
    locationAccuracyMeters,
    reachCount,
    interestLevel,
    currentRevision,
    lifecycleStatus,
  ]);
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
          other.regionTreeVersion == this.regionTreeVersion &&
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
  final Value<String?> regionTreeVersion;
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
    this.regionTreeVersion = const Value.absent(),
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
    this.regionTreeVersion = const Value.absent(),
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
    Expression<String>? regionTreeVersion,
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
      if (regionTreeVersion != null) 'region_tree_version': regionTreeVersion,
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
    Value<String?>? regionTreeVersion,
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
      regionTreeVersion: regionTreeVersion ?? this.regionTreeVersion,
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
    if (regionTreeVersion.present) {
      map['region_tree_version'] = Variable<String>(regionTreeVersion.value);
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
          ..write('regionTreeVersion: $regionTreeVersion, ')
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

class $DbContactAttemptsTable extends DbContactAttempts
    with TableInfo<$DbContactAttemptsTable, DbContactAttempt> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DbContactAttemptsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _attemptIdMeta = const VerificationMeta(
    'attemptId',
  );
  @override
  late final GeneratedColumn<String> attemptId = GeneratedColumn<String>(
    'attempt_id',
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
  static const VerificationMeta _linkedContactIdMeta = const VerificationMeta(
    'linkedContactId',
  );
  @override
  late final GeneratedColumn<String> linkedContactId = GeneratedColumn<String>(
    'linked_contact_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES db_contact_records (contact_id)',
    ),
  );
  @override
  List<GeneratedColumn> get $columns => [
    attemptId,
    appUserId,
    workspaceId,
    projectId,
    occurredAtUtc,
    occurredTimeZone,
    firstSubmittedAtUtc,
    channel,
    channelDetail,
    linkedContactId,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'db_contact_attempts';
  @override
  VerificationContext validateIntegrity(
    Insertable<DbContactAttempt> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('attempt_id')) {
      context.handle(
        _attemptIdMeta,
        attemptId.isAcceptableOrUnknown(data['attempt_id']!, _attemptIdMeta),
      );
    } else if (isInserting) {
      context.missing(_attemptIdMeta);
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
    if (data.containsKey('linked_contact_id')) {
      context.handle(
        _linkedContactIdMeta,
        linkedContactId.isAcceptableOrUnknown(
          data['linked_contact_id']!,
          _linkedContactIdMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {attemptId};
  @override
  DbContactAttempt map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DbContactAttempt(
      attemptId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}attempt_id'],
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
      linkedContactId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}linked_contact_id'],
      ),
    );
  }

  @override
  $DbContactAttemptsTable createAlias(String alias) {
    return $DbContactAttemptsTable(attachedDatabase, alias);
  }
}

class DbContactAttempt extends DataClass
    implements Insertable<DbContactAttempt> {
  final String attemptId;
  final String appUserId;
  final String workspaceId;
  final String projectId;
  final DateTime occurredAtUtc;
  final String occurredTimeZone;
  final DateTime firstSubmittedAtUtc;
  final String channel;
  final String? channelDetail;
  final String? linkedContactId;
  const DbContactAttempt({
    required this.attemptId,
    required this.appUserId,
    required this.workspaceId,
    required this.projectId,
    required this.occurredAtUtc,
    required this.occurredTimeZone,
    required this.firstSubmittedAtUtc,
    required this.channel,
    this.channelDetail,
    this.linkedContactId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['attempt_id'] = Variable<String>(attemptId);
    map['app_user_id'] = Variable<String>(appUserId);
    map['workspace_id'] = Variable<String>(workspaceId);
    map['project_id'] = Variable<String>(projectId);
    map['occurred_at_utc'] = Variable<DateTime>(occurredAtUtc);
    map['occurred_time_zone'] = Variable<String>(occurredTimeZone);
    map['first_submitted_at_utc'] = Variable<DateTime>(firstSubmittedAtUtc);
    map['channel'] = Variable<String>(channel);
    if (!nullToAbsent || channelDetail != null) {
      map['channel_detail'] = Variable<String>(channelDetail);
    }
    if (!nullToAbsent || linkedContactId != null) {
      map['linked_contact_id'] = Variable<String>(linkedContactId);
    }
    return map;
  }

  DbContactAttemptsCompanion toCompanion(bool nullToAbsent) {
    return DbContactAttemptsCompanion(
      attemptId: Value(attemptId),
      appUserId: Value(appUserId),
      workspaceId: Value(workspaceId),
      projectId: Value(projectId),
      occurredAtUtc: Value(occurredAtUtc),
      occurredTimeZone: Value(occurredTimeZone),
      firstSubmittedAtUtc: Value(firstSubmittedAtUtc),
      channel: Value(channel),
      channelDetail: channelDetail == null && nullToAbsent
          ? const Value.absent()
          : Value(channelDetail),
      linkedContactId: linkedContactId == null && nullToAbsent
          ? const Value.absent()
          : Value(linkedContactId),
    );
  }

  factory DbContactAttempt.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DbContactAttempt(
      attemptId: serializer.fromJson<String>(json['attemptId']),
      appUserId: serializer.fromJson<String>(json['appUserId']),
      workspaceId: serializer.fromJson<String>(json['workspaceId']),
      projectId: serializer.fromJson<String>(json['projectId']),
      occurredAtUtc: serializer.fromJson<DateTime>(json['occurredAtUtc']),
      occurredTimeZone: serializer.fromJson<String>(json['occurredTimeZone']),
      firstSubmittedAtUtc: serializer.fromJson<DateTime>(
        json['firstSubmittedAtUtc'],
      ),
      channel: serializer.fromJson<String>(json['channel']),
      channelDetail: serializer.fromJson<String?>(json['channelDetail']),
      linkedContactId: serializer.fromJson<String?>(json['linkedContactId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'attemptId': serializer.toJson<String>(attemptId),
      'appUserId': serializer.toJson<String>(appUserId),
      'workspaceId': serializer.toJson<String>(workspaceId),
      'projectId': serializer.toJson<String>(projectId),
      'occurredAtUtc': serializer.toJson<DateTime>(occurredAtUtc),
      'occurredTimeZone': serializer.toJson<String>(occurredTimeZone),
      'firstSubmittedAtUtc': serializer.toJson<DateTime>(firstSubmittedAtUtc),
      'channel': serializer.toJson<String>(channel),
      'channelDetail': serializer.toJson<String?>(channelDetail),
      'linkedContactId': serializer.toJson<String?>(linkedContactId),
    };
  }

  DbContactAttempt copyWith({
    String? attemptId,
    String? appUserId,
    String? workspaceId,
    String? projectId,
    DateTime? occurredAtUtc,
    String? occurredTimeZone,
    DateTime? firstSubmittedAtUtc,
    String? channel,
    Value<String?> channelDetail = const Value.absent(),
    Value<String?> linkedContactId = const Value.absent(),
  }) => DbContactAttempt(
    attemptId: attemptId ?? this.attemptId,
    appUserId: appUserId ?? this.appUserId,
    workspaceId: workspaceId ?? this.workspaceId,
    projectId: projectId ?? this.projectId,
    occurredAtUtc: occurredAtUtc ?? this.occurredAtUtc,
    occurredTimeZone: occurredTimeZone ?? this.occurredTimeZone,
    firstSubmittedAtUtc: firstSubmittedAtUtc ?? this.firstSubmittedAtUtc,
    channel: channel ?? this.channel,
    channelDetail: channelDetail.present
        ? channelDetail.value
        : this.channelDetail,
    linkedContactId: linkedContactId.present
        ? linkedContactId.value
        : this.linkedContactId,
  );
  DbContactAttempt copyWithCompanion(DbContactAttemptsCompanion data) {
    return DbContactAttempt(
      attemptId: data.attemptId.present ? data.attemptId.value : this.attemptId,
      appUserId: data.appUserId.present ? data.appUserId.value : this.appUserId,
      workspaceId: data.workspaceId.present
          ? data.workspaceId.value
          : this.workspaceId,
      projectId: data.projectId.present ? data.projectId.value : this.projectId,
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
      linkedContactId: data.linkedContactId.present
          ? data.linkedContactId.value
          : this.linkedContactId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DbContactAttempt(')
          ..write('attemptId: $attemptId, ')
          ..write('appUserId: $appUserId, ')
          ..write('workspaceId: $workspaceId, ')
          ..write('projectId: $projectId, ')
          ..write('occurredAtUtc: $occurredAtUtc, ')
          ..write('occurredTimeZone: $occurredTimeZone, ')
          ..write('firstSubmittedAtUtc: $firstSubmittedAtUtc, ')
          ..write('channel: $channel, ')
          ..write('channelDetail: $channelDetail, ')
          ..write('linkedContactId: $linkedContactId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    attemptId,
    appUserId,
    workspaceId,
    projectId,
    occurredAtUtc,
    occurredTimeZone,
    firstSubmittedAtUtc,
    channel,
    channelDetail,
    linkedContactId,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DbContactAttempt &&
          other.attemptId == this.attemptId &&
          other.appUserId == this.appUserId &&
          other.workspaceId == this.workspaceId &&
          other.projectId == this.projectId &&
          other.occurredAtUtc == this.occurredAtUtc &&
          other.occurredTimeZone == this.occurredTimeZone &&
          other.firstSubmittedAtUtc == this.firstSubmittedAtUtc &&
          other.channel == this.channel &&
          other.channelDetail == this.channelDetail &&
          other.linkedContactId == this.linkedContactId);
}

class DbContactAttemptsCompanion extends UpdateCompanion<DbContactAttempt> {
  final Value<String> attemptId;
  final Value<String> appUserId;
  final Value<String> workspaceId;
  final Value<String> projectId;
  final Value<DateTime> occurredAtUtc;
  final Value<String> occurredTimeZone;
  final Value<DateTime> firstSubmittedAtUtc;
  final Value<String> channel;
  final Value<String?> channelDetail;
  final Value<String?> linkedContactId;
  final Value<int> rowid;
  const DbContactAttemptsCompanion({
    this.attemptId = const Value.absent(),
    this.appUserId = const Value.absent(),
    this.workspaceId = const Value.absent(),
    this.projectId = const Value.absent(),
    this.occurredAtUtc = const Value.absent(),
    this.occurredTimeZone = const Value.absent(),
    this.firstSubmittedAtUtc = const Value.absent(),
    this.channel = const Value.absent(),
    this.channelDetail = const Value.absent(),
    this.linkedContactId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DbContactAttemptsCompanion.insert({
    required String attemptId,
    required String appUserId,
    required String workspaceId,
    required String projectId,
    required DateTime occurredAtUtc,
    required String occurredTimeZone,
    required DateTime firstSubmittedAtUtc,
    required String channel,
    this.channelDetail = const Value.absent(),
    this.linkedContactId = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : attemptId = Value(attemptId),
       appUserId = Value(appUserId),
       workspaceId = Value(workspaceId),
       projectId = Value(projectId),
       occurredAtUtc = Value(occurredAtUtc),
       occurredTimeZone = Value(occurredTimeZone),
       firstSubmittedAtUtc = Value(firstSubmittedAtUtc),
       channel = Value(channel);
  static Insertable<DbContactAttempt> custom({
    Expression<String>? attemptId,
    Expression<String>? appUserId,
    Expression<String>? workspaceId,
    Expression<String>? projectId,
    Expression<DateTime>? occurredAtUtc,
    Expression<String>? occurredTimeZone,
    Expression<DateTime>? firstSubmittedAtUtc,
    Expression<String>? channel,
    Expression<String>? channelDetail,
    Expression<String>? linkedContactId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (attemptId != null) 'attempt_id': attemptId,
      if (appUserId != null) 'app_user_id': appUserId,
      if (workspaceId != null) 'workspace_id': workspaceId,
      if (projectId != null) 'project_id': projectId,
      if (occurredAtUtc != null) 'occurred_at_utc': occurredAtUtc,
      if (occurredTimeZone != null) 'occurred_time_zone': occurredTimeZone,
      if (firstSubmittedAtUtc != null)
        'first_submitted_at_utc': firstSubmittedAtUtc,
      if (channel != null) 'channel': channel,
      if (channelDetail != null) 'channel_detail': channelDetail,
      if (linkedContactId != null) 'linked_contact_id': linkedContactId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DbContactAttemptsCompanion copyWith({
    Value<String>? attemptId,
    Value<String>? appUserId,
    Value<String>? workspaceId,
    Value<String>? projectId,
    Value<DateTime>? occurredAtUtc,
    Value<String>? occurredTimeZone,
    Value<DateTime>? firstSubmittedAtUtc,
    Value<String>? channel,
    Value<String?>? channelDetail,
    Value<String?>? linkedContactId,
    Value<int>? rowid,
  }) {
    return DbContactAttemptsCompanion(
      attemptId: attemptId ?? this.attemptId,
      appUserId: appUserId ?? this.appUserId,
      workspaceId: workspaceId ?? this.workspaceId,
      projectId: projectId ?? this.projectId,
      occurredAtUtc: occurredAtUtc ?? this.occurredAtUtc,
      occurredTimeZone: occurredTimeZone ?? this.occurredTimeZone,
      firstSubmittedAtUtc: firstSubmittedAtUtc ?? this.firstSubmittedAtUtc,
      channel: channel ?? this.channel,
      channelDetail: channelDetail ?? this.channelDetail,
      linkedContactId: linkedContactId ?? this.linkedContactId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (attemptId.present) {
      map['attempt_id'] = Variable<String>(attemptId.value);
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
    if (linkedContactId.present) {
      map['linked_contact_id'] = Variable<String>(linkedContactId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DbContactAttemptsCompanion(')
          ..write('attemptId: $attemptId, ')
          ..write('appUserId: $appUserId, ')
          ..write('workspaceId: $workspaceId, ')
          ..write('projectId: $projectId, ')
          ..write('occurredAtUtc: $occurredAtUtc, ')
          ..write('occurredTimeZone: $occurredTimeZone, ')
          ..write('firstSubmittedAtUtc: $firstSubmittedAtUtc, ')
          ..write('channel: $channel, ')
          ..write('channelDetail: $channelDetail, ')
          ..write('linkedContactId: $linkedContactId, ')
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
  static const VerificationMeta _revisionKindMeta = const VerificationMeta(
    'revisionKind',
  );
  @override
  late final GeneratedColumn<String> revisionKind = GeneratedColumn<String>(
    'revision_kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('submitted'),
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
  static const VerificationMeta _regionTreeVersionMeta = const VerificationMeta(
    'regionTreeVersion',
  );
  @override
  late final GeneratedColumn<String> regionTreeVersion =
      GeneratedColumn<String>(
        'region_tree_version',
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
    revisionKind,
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
    regionTreeVersion,
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
    if (data.containsKey('revision_kind')) {
      context.handle(
        _revisionKindMeta,
        revisionKind.isAcceptableOrUnknown(
          data['revision_kind']!,
          _revisionKindMeta,
        ),
      );
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
    if (data.containsKey('region_tree_version')) {
      context.handle(
        _regionTreeVersionMeta,
        regionTreeVersion.isAcceptableOrUnknown(
          data['region_tree_version']!,
          _regionTreeVersionMeta,
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
      revisionKind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}revision_kind'],
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
      regionTreeVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}region_tree_version'],
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
  final String revisionKind;
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
  final String? regionTreeVersion;
  final double? latitude;
  final double? longitude;
  final double? locationAccuracyMeters;
  final int reachCount;
  final int interestLevel;
  const DbContactRevision({
    required this.revisionId,
    required this.contactId,
    required this.revisionNumber,
    required this.revisionKind,
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
    this.regionTreeVersion,
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
    map['revision_kind'] = Variable<String>(revisionKind);
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
    if (!nullToAbsent || regionTreeVersion != null) {
      map['region_tree_version'] = Variable<String>(regionTreeVersion);
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
      revisionKind: Value(revisionKind),
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
      regionTreeVersion: regionTreeVersion == null && nullToAbsent
          ? const Value.absent()
          : Value(regionTreeVersion),
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
      revisionKind: serializer.fromJson<String>(json['revisionKind']),
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
      regionTreeVersion: serializer.fromJson<String?>(
        json['regionTreeVersion'],
      ),
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
      'revisionKind': serializer.toJson<String>(revisionKind),
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
      'regionTreeVersion': serializer.toJson<String?>(regionTreeVersion),
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
    String? revisionKind,
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
    Value<String?> regionTreeVersion = const Value.absent(),
    Value<double?> latitude = const Value.absent(),
    Value<double?> longitude = const Value.absent(),
    Value<double?> locationAccuracyMeters = const Value.absent(),
    int? reachCount,
    int? interestLevel,
  }) => DbContactRevision(
    revisionId: revisionId ?? this.revisionId,
    contactId: contactId ?? this.contactId,
    revisionNumber: revisionNumber ?? this.revisionNumber,
    revisionKind: revisionKind ?? this.revisionKind,
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
    regionTreeVersion: regionTreeVersion.present
        ? regionTreeVersion.value
        : this.regionTreeVersion,
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
      revisionKind: data.revisionKind.present
          ? data.revisionKind.value
          : this.revisionKind,
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
      regionTreeVersion: data.regionTreeVersion.present
          ? data.regionTreeVersion.value
          : this.regionTreeVersion,
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
          ..write('revisionKind: $revisionKind, ')
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
          ..write('regionTreeVersion: $regionTreeVersion, ')
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
    revisionKind,
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
    regionTreeVersion,
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
          other.revisionKind == this.revisionKind &&
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
          other.regionTreeVersion == this.regionTreeVersion &&
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
  final Value<String> revisionKind;
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
  final Value<String?> regionTreeVersion;
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
    this.revisionKind = const Value.absent(),
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
    this.regionTreeVersion = const Value.absent(),
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
    this.revisionKind = const Value.absent(),
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
    this.regionTreeVersion = const Value.absent(),
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
    Expression<String>? revisionKind,
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
    Expression<String>? regionTreeVersion,
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
      if (revisionKind != null) 'revision_kind': revisionKind,
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
      if (regionTreeVersion != null) 'region_tree_version': regionTreeVersion,
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
    Value<String>? revisionKind,
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
    Value<String?>? regionTreeVersion,
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
      revisionKind: revisionKind ?? this.revisionKind,
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
      regionTreeVersion: regionTreeVersion ?? this.regionTreeVersion,
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
    if (revisionKind.present) {
      map['revision_kind'] = Variable<String>(revisionKind.value);
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
    if (regionTreeVersion.present) {
      map['region_tree_version'] = Variable<String>(regionTreeVersion.value);
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
          ..write('revisionKind: $revisionKind, ')
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
          ..write('regionTreeVersion: $regionTreeVersion, ')
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
  static const VerificationMeta _answerStateReasonMeta = const VerificationMeta(
    'answerStateReason',
  );
  @override
  late final GeneratedColumn<String> answerStateReason =
      GeneratedColumn<String>(
        'answer_state_reason',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
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
  static const VerificationMeta _textValueMeta = const VerificationMeta(
    'textValue',
  );
  @override
  late final GeneratedColumn<String> textValue = GeneratedColumn<String>(
    'text_value',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _numberValueMeta = const VerificationMeta(
    'numberValue',
  );
  @override
  late final GeneratedColumn<double> numberValue = GeneratedColumn<double>(
    'number_value',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _multiChoiceValueJsonMeta =
      const VerificationMeta('multiChoiceValueJson');
  @override
  late final GeneratedColumn<String> multiChoiceValueJson =
      GeneratedColumn<String>(
        'multi_choice_value_json',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  @override
  List<GeneratedColumn> get $columns => [
    contactId,
    revisionNumber,
    questionId,
    answerState,
    answerStateReason,
    answerType,
    booleanValue,
    textValue,
    numberValue,
    multiChoiceValueJson,
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
    if (data.containsKey('answer_state_reason')) {
      context.handle(
        _answerStateReasonMeta,
        answerStateReason.isAcceptableOrUnknown(
          data['answer_state_reason']!,
          _answerStateReasonMeta,
        ),
      );
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
    if (data.containsKey('text_value')) {
      context.handle(
        _textValueMeta,
        textValue.isAcceptableOrUnknown(data['text_value']!, _textValueMeta),
      );
    }
    if (data.containsKey('number_value')) {
      context.handle(
        _numberValueMeta,
        numberValue.isAcceptableOrUnknown(
          data['number_value']!,
          _numberValueMeta,
        ),
      );
    }
    if (data.containsKey('multi_choice_value_json')) {
      context.handle(
        _multiChoiceValueJsonMeta,
        multiChoiceValueJson.isAcceptableOrUnknown(
          data['multi_choice_value_json']!,
          _multiChoiceValueJsonMeta,
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
      answerStateReason: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}answer_state_reason'],
      ),
      answerType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}answer_type'],
      )!,
      booleanValue: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}boolean_value'],
      ),
      textValue: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}text_value'],
      ),
      numberValue: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}number_value'],
      ),
      multiChoiceValueJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}multi_choice_value_json'],
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
  final String? answerStateReason;
  final String answerType;
  final bool? booleanValue;
  final String? textValue;
  final double? numberValue;
  final String? multiChoiceValueJson;
  const DbContactAnswer({
    required this.contactId,
    required this.revisionNumber,
    required this.questionId,
    required this.answerState,
    this.answerStateReason,
    required this.answerType,
    this.booleanValue,
    this.textValue,
    this.numberValue,
    this.multiChoiceValueJson,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['contact_id'] = Variable<String>(contactId);
    map['revision_number'] = Variable<int>(revisionNumber);
    map['question_id'] = Variable<String>(questionId);
    map['answer_state'] = Variable<String>(answerState);
    if (!nullToAbsent || answerStateReason != null) {
      map['answer_state_reason'] = Variable<String>(answerStateReason);
    }
    map['answer_type'] = Variable<String>(answerType);
    if (!nullToAbsent || booleanValue != null) {
      map['boolean_value'] = Variable<bool>(booleanValue);
    }
    if (!nullToAbsent || textValue != null) {
      map['text_value'] = Variable<String>(textValue);
    }
    if (!nullToAbsent || numberValue != null) {
      map['number_value'] = Variable<double>(numberValue);
    }
    if (!nullToAbsent || multiChoiceValueJson != null) {
      map['multi_choice_value_json'] = Variable<String>(multiChoiceValueJson);
    }
    return map;
  }

  DbContactAnswersCompanion toCompanion(bool nullToAbsent) {
    return DbContactAnswersCompanion(
      contactId: Value(contactId),
      revisionNumber: Value(revisionNumber),
      questionId: Value(questionId),
      answerState: Value(answerState),
      answerStateReason: answerStateReason == null && nullToAbsent
          ? const Value.absent()
          : Value(answerStateReason),
      answerType: Value(answerType),
      booleanValue: booleanValue == null && nullToAbsent
          ? const Value.absent()
          : Value(booleanValue),
      textValue: textValue == null && nullToAbsent
          ? const Value.absent()
          : Value(textValue),
      numberValue: numberValue == null && nullToAbsent
          ? const Value.absent()
          : Value(numberValue),
      multiChoiceValueJson: multiChoiceValueJson == null && nullToAbsent
          ? const Value.absent()
          : Value(multiChoiceValueJson),
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
      answerStateReason: serializer.fromJson<String?>(
        json['answerStateReason'],
      ),
      answerType: serializer.fromJson<String>(json['answerType']),
      booleanValue: serializer.fromJson<bool?>(json['booleanValue']),
      textValue: serializer.fromJson<String?>(json['textValue']),
      numberValue: serializer.fromJson<double?>(json['numberValue']),
      multiChoiceValueJson: serializer.fromJson<String?>(
        json['multiChoiceValueJson'],
      ),
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
      'answerStateReason': serializer.toJson<String?>(answerStateReason),
      'answerType': serializer.toJson<String>(answerType),
      'booleanValue': serializer.toJson<bool?>(booleanValue),
      'textValue': serializer.toJson<String?>(textValue),
      'numberValue': serializer.toJson<double?>(numberValue),
      'multiChoiceValueJson': serializer.toJson<String?>(multiChoiceValueJson),
    };
  }

  DbContactAnswer copyWith({
    String? contactId,
    int? revisionNumber,
    String? questionId,
    String? answerState,
    Value<String?> answerStateReason = const Value.absent(),
    String? answerType,
    Value<bool?> booleanValue = const Value.absent(),
    Value<String?> textValue = const Value.absent(),
    Value<double?> numberValue = const Value.absent(),
    Value<String?> multiChoiceValueJson = const Value.absent(),
  }) => DbContactAnswer(
    contactId: contactId ?? this.contactId,
    revisionNumber: revisionNumber ?? this.revisionNumber,
    questionId: questionId ?? this.questionId,
    answerState: answerState ?? this.answerState,
    answerStateReason: answerStateReason.present
        ? answerStateReason.value
        : this.answerStateReason,
    answerType: answerType ?? this.answerType,
    booleanValue: booleanValue.present ? booleanValue.value : this.booleanValue,
    textValue: textValue.present ? textValue.value : this.textValue,
    numberValue: numberValue.present ? numberValue.value : this.numberValue,
    multiChoiceValueJson: multiChoiceValueJson.present
        ? multiChoiceValueJson.value
        : this.multiChoiceValueJson,
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
      answerStateReason: data.answerStateReason.present
          ? data.answerStateReason.value
          : this.answerStateReason,
      answerType: data.answerType.present
          ? data.answerType.value
          : this.answerType,
      booleanValue: data.booleanValue.present
          ? data.booleanValue.value
          : this.booleanValue,
      textValue: data.textValue.present ? data.textValue.value : this.textValue,
      numberValue: data.numberValue.present
          ? data.numberValue.value
          : this.numberValue,
      multiChoiceValueJson: data.multiChoiceValueJson.present
          ? data.multiChoiceValueJson.value
          : this.multiChoiceValueJson,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DbContactAnswer(')
          ..write('contactId: $contactId, ')
          ..write('revisionNumber: $revisionNumber, ')
          ..write('questionId: $questionId, ')
          ..write('answerState: $answerState, ')
          ..write('answerStateReason: $answerStateReason, ')
          ..write('answerType: $answerType, ')
          ..write('booleanValue: $booleanValue, ')
          ..write('textValue: $textValue, ')
          ..write('numberValue: $numberValue, ')
          ..write('multiChoiceValueJson: $multiChoiceValueJson')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    contactId,
    revisionNumber,
    questionId,
    answerState,
    answerStateReason,
    answerType,
    booleanValue,
    textValue,
    numberValue,
    multiChoiceValueJson,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DbContactAnswer &&
          other.contactId == this.contactId &&
          other.revisionNumber == this.revisionNumber &&
          other.questionId == this.questionId &&
          other.answerState == this.answerState &&
          other.answerStateReason == this.answerStateReason &&
          other.answerType == this.answerType &&
          other.booleanValue == this.booleanValue &&
          other.textValue == this.textValue &&
          other.numberValue == this.numberValue &&
          other.multiChoiceValueJson == this.multiChoiceValueJson);
}

class DbContactAnswersCompanion extends UpdateCompanion<DbContactAnswer> {
  final Value<String> contactId;
  final Value<int> revisionNumber;
  final Value<String> questionId;
  final Value<String> answerState;
  final Value<String?> answerStateReason;
  final Value<String> answerType;
  final Value<bool?> booleanValue;
  final Value<String?> textValue;
  final Value<double?> numberValue;
  final Value<String?> multiChoiceValueJson;
  final Value<int> rowid;
  const DbContactAnswersCompanion({
    this.contactId = const Value.absent(),
    this.revisionNumber = const Value.absent(),
    this.questionId = const Value.absent(),
    this.answerState = const Value.absent(),
    this.answerStateReason = const Value.absent(),
    this.answerType = const Value.absent(),
    this.booleanValue = const Value.absent(),
    this.textValue = const Value.absent(),
    this.numberValue = const Value.absent(),
    this.multiChoiceValueJson = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DbContactAnswersCompanion.insert({
    required String contactId,
    required int revisionNumber,
    required String questionId,
    required String answerState,
    this.answerStateReason = const Value.absent(),
    required String answerType,
    this.booleanValue = const Value.absent(),
    this.textValue = const Value.absent(),
    this.numberValue = const Value.absent(),
    this.multiChoiceValueJson = const Value.absent(),
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
    Expression<String>? answerStateReason,
    Expression<String>? answerType,
    Expression<bool>? booleanValue,
    Expression<String>? textValue,
    Expression<double>? numberValue,
    Expression<String>? multiChoiceValueJson,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (contactId != null) 'contact_id': contactId,
      if (revisionNumber != null) 'revision_number': revisionNumber,
      if (questionId != null) 'question_id': questionId,
      if (answerState != null) 'answer_state': answerState,
      if (answerStateReason != null) 'answer_state_reason': answerStateReason,
      if (answerType != null) 'answer_type': answerType,
      if (booleanValue != null) 'boolean_value': booleanValue,
      if (textValue != null) 'text_value': textValue,
      if (numberValue != null) 'number_value': numberValue,
      if (multiChoiceValueJson != null)
        'multi_choice_value_json': multiChoiceValueJson,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DbContactAnswersCompanion copyWith({
    Value<String>? contactId,
    Value<int>? revisionNumber,
    Value<String>? questionId,
    Value<String>? answerState,
    Value<String?>? answerStateReason,
    Value<String>? answerType,
    Value<bool?>? booleanValue,
    Value<String?>? textValue,
    Value<double?>? numberValue,
    Value<String?>? multiChoiceValueJson,
    Value<int>? rowid,
  }) {
    return DbContactAnswersCompanion(
      contactId: contactId ?? this.contactId,
      revisionNumber: revisionNumber ?? this.revisionNumber,
      questionId: questionId ?? this.questionId,
      answerState: answerState ?? this.answerState,
      answerStateReason: answerStateReason ?? this.answerStateReason,
      answerType: answerType ?? this.answerType,
      booleanValue: booleanValue ?? this.booleanValue,
      textValue: textValue ?? this.textValue,
      numberValue: numberValue ?? this.numberValue,
      multiChoiceValueJson: multiChoiceValueJson ?? this.multiChoiceValueJson,
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
    if (answerStateReason.present) {
      map['answer_state_reason'] = Variable<String>(answerStateReason.value);
    }
    if (answerType.present) {
      map['answer_type'] = Variable<String>(answerType.value);
    }
    if (booleanValue.present) {
      map['boolean_value'] = Variable<bool>(booleanValue.value);
    }
    if (textValue.present) {
      map['text_value'] = Variable<String>(textValue.value);
    }
    if (numberValue.present) {
      map['number_value'] = Variable<double>(numberValue.value);
    }
    if (multiChoiceValueJson.present) {
      map['multi_choice_value_json'] = Variable<String>(
        multiChoiceValueJson.value,
      );
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
          ..write('answerStateReason: $answerStateReason, ')
          ..write('answerType: $answerType, ')
          ..write('booleanValue: $booleanValue, ')
          ..write('textValue: $textValue, ')
          ..write('numberValue: $numberValue, ')
          ..write('multiChoiceValueJson: $multiChoiceValueJson, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $DbContactRevisionConflictsTable extends DbContactRevisionConflicts
    with
        TableInfo<$DbContactRevisionConflictsTable, DbContactRevisionConflict> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DbContactRevisionConflictsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _conflictIdMeta = const VerificationMeta(
    'conflictId',
  );
  @override
  late final GeneratedColumn<String> conflictId = GeneratedColumn<String>(
    'conflict_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
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
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
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
  static const VerificationMeta _conflictingFieldsJsonMeta =
      const VerificationMeta('conflictingFieldsJson');
  @override
  late final GeneratedColumn<String> conflictingFieldsJson =
      GeneratedColumn<String>(
        'conflicting_fields_json',
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
  static const VerificationMeta _currentRevisionKindMeta =
      const VerificationMeta('currentRevisionKind');
  @override
  late final GeneratedColumn<String> currentRevisionKind =
      GeneratedColumn<String>(
        'current_revision_kind',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _currentRevisedAtUtcMeta =
      const VerificationMeta('currentRevisedAtUtc');
  @override
  late final GeneratedColumn<DateTime> currentRevisedAtUtc =
      GeneratedColumn<DateTime>(
        'current_revised_at_utc',
        aliasedName,
        false,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _currentReasonMeta = const VerificationMeta(
    'currentReason',
  );
  @override
  late final GeneratedColumn<String> currentReason = GeneratedColumn<String>(
    'current_reason',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _currentSnapshotJsonMeta =
      const VerificationMeta('currentSnapshotJson');
  @override
  late final GeneratedColumn<String> currentSnapshotJson =
      GeneratedColumn<String>(
        'current_snapshot_json',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _proposedSnapshotJsonMeta =
      const VerificationMeta('proposedSnapshotJson');
  @override
  late final GeneratedColumn<String> proposedSnapshotJson =
      GeneratedColumn<String>(
        'proposed_snapshot_json',
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
    requiredDuringInsert: false,
    defaultValue: const Constant('pending'),
  );
  static const VerificationMeta _resolutionCommandIdMeta =
      const VerificationMeta('resolutionCommandId');
  @override
  late final GeneratedColumn<String> resolutionCommandId =
      GeneratedColumn<String>(
        'resolution_command_id',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
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
  static const VerificationMeta _resolvedAtUtcMeta = const VerificationMeta(
    'resolvedAtUtc',
  );
  @override
  late final GeneratedColumn<DateTime> resolvedAtUtc =
      GeneratedColumn<DateTime>(
        'resolved_at_utc',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  @override
  List<GeneratedColumn> get $columns => [
    conflictId,
    commandId,
    contactId,
    appUserId,
    workspaceId,
    projectId,
    baseRevision,
    currentRevision,
    conflictingFieldsJson,
    questionnaireVersionId,
    currentRevisionKind,
    currentRevisedAtUtc,
    currentReason,
    currentSnapshotJson,
    proposedSnapshotJson,
    status,
    resolutionCommandId,
    createdAtUtc,
    resolvedAtUtc,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'db_contact_revision_conflicts';
  @override
  VerificationContext validateIntegrity(
    Insertable<DbContactRevisionConflict> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('conflict_id')) {
      context.handle(
        _conflictIdMeta,
        conflictId.isAcceptableOrUnknown(data['conflict_id']!, _conflictIdMeta),
      );
    } else if (isInserting) {
      context.missing(_conflictIdMeta);
    }
    if (data.containsKey('command_id')) {
      context.handle(
        _commandIdMeta,
        commandId.isAcceptableOrUnknown(data['command_id']!, _commandIdMeta),
      );
    } else if (isInserting) {
      context.missing(_commandIdMeta);
    }
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
    if (data.containsKey('conflicting_fields_json')) {
      context.handle(
        _conflictingFieldsJsonMeta,
        conflictingFieldsJson.isAcceptableOrUnknown(
          data['conflicting_fields_json']!,
          _conflictingFieldsJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_conflictingFieldsJsonMeta);
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
    if (data.containsKey('current_revision_kind')) {
      context.handle(
        _currentRevisionKindMeta,
        currentRevisionKind.isAcceptableOrUnknown(
          data['current_revision_kind']!,
          _currentRevisionKindMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_currentRevisionKindMeta);
    }
    if (data.containsKey('current_revised_at_utc')) {
      context.handle(
        _currentRevisedAtUtcMeta,
        currentRevisedAtUtc.isAcceptableOrUnknown(
          data['current_revised_at_utc']!,
          _currentRevisedAtUtcMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_currentRevisedAtUtcMeta);
    }
    if (data.containsKey('current_reason')) {
      context.handle(
        _currentReasonMeta,
        currentReason.isAcceptableOrUnknown(
          data['current_reason']!,
          _currentReasonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_currentReasonMeta);
    }
    if (data.containsKey('current_snapshot_json')) {
      context.handle(
        _currentSnapshotJsonMeta,
        currentSnapshotJson.isAcceptableOrUnknown(
          data['current_snapshot_json']!,
          _currentSnapshotJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_currentSnapshotJsonMeta);
    }
    if (data.containsKey('proposed_snapshot_json')) {
      context.handle(
        _proposedSnapshotJsonMeta,
        proposedSnapshotJson.isAcceptableOrUnknown(
          data['proposed_snapshot_json']!,
          _proposedSnapshotJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_proposedSnapshotJsonMeta);
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    }
    if (data.containsKey('resolution_command_id')) {
      context.handle(
        _resolutionCommandIdMeta,
        resolutionCommandId.isAcceptableOrUnknown(
          data['resolution_command_id']!,
          _resolutionCommandIdMeta,
        ),
      );
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
    if (data.containsKey('resolved_at_utc')) {
      context.handle(
        _resolvedAtUtcMeta,
        resolvedAtUtc.isAcceptableOrUnknown(
          data['resolved_at_utc']!,
          _resolvedAtUtcMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {conflictId};
  @override
  DbContactRevisionConflict map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DbContactRevisionConflict(
      conflictId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}conflict_id'],
      )!,
      commandId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}command_id'],
      )!,
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
      baseRevision: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}base_revision'],
      )!,
      currentRevision: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}current_revision'],
      )!,
      conflictingFieldsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}conflicting_fields_json'],
      )!,
      questionnaireVersionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}questionnaire_version_id'],
      )!,
      currentRevisionKind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}current_revision_kind'],
      )!,
      currentRevisedAtUtc: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}current_revised_at_utc'],
      )!,
      currentReason: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}current_reason'],
      )!,
      currentSnapshotJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}current_snapshot_json'],
      )!,
      proposedSnapshotJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}proposed_snapshot_json'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      resolutionCommandId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}resolution_command_id'],
      ),
      createdAtUtc: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at_utc'],
      )!,
      resolvedAtUtc: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}resolved_at_utc'],
      ),
    );
  }

  @override
  $DbContactRevisionConflictsTable createAlias(String alias) {
    return $DbContactRevisionConflictsTable(attachedDatabase, alias);
  }
}

class DbContactRevisionConflict extends DataClass
    implements Insertable<DbContactRevisionConflict> {
  final String conflictId;
  final String commandId;
  final String contactId;
  final String appUserId;
  final String workspaceId;
  final String projectId;
  final int baseRevision;
  final int currentRevision;
  final String conflictingFieldsJson;
  final String questionnaireVersionId;
  final String currentRevisionKind;
  final DateTime currentRevisedAtUtc;
  final String currentReason;
  final String currentSnapshotJson;
  final String proposedSnapshotJson;
  final String status;
  final String? resolutionCommandId;
  final DateTime createdAtUtc;
  final DateTime? resolvedAtUtc;
  const DbContactRevisionConflict({
    required this.conflictId,
    required this.commandId,
    required this.contactId,
    required this.appUserId,
    required this.workspaceId,
    required this.projectId,
    required this.baseRevision,
    required this.currentRevision,
    required this.conflictingFieldsJson,
    required this.questionnaireVersionId,
    required this.currentRevisionKind,
    required this.currentRevisedAtUtc,
    required this.currentReason,
    required this.currentSnapshotJson,
    required this.proposedSnapshotJson,
    required this.status,
    this.resolutionCommandId,
    required this.createdAtUtc,
    this.resolvedAtUtc,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['conflict_id'] = Variable<String>(conflictId);
    map['command_id'] = Variable<String>(commandId);
    map['contact_id'] = Variable<String>(contactId);
    map['app_user_id'] = Variable<String>(appUserId);
    map['workspace_id'] = Variable<String>(workspaceId);
    map['project_id'] = Variable<String>(projectId);
    map['base_revision'] = Variable<int>(baseRevision);
    map['current_revision'] = Variable<int>(currentRevision);
    map['conflicting_fields_json'] = Variable<String>(conflictingFieldsJson);
    map['questionnaire_version_id'] = Variable<String>(questionnaireVersionId);
    map['current_revision_kind'] = Variable<String>(currentRevisionKind);
    map['current_revised_at_utc'] = Variable<DateTime>(currentRevisedAtUtc);
    map['current_reason'] = Variable<String>(currentReason);
    map['current_snapshot_json'] = Variable<String>(currentSnapshotJson);
    map['proposed_snapshot_json'] = Variable<String>(proposedSnapshotJson);
    map['status'] = Variable<String>(status);
    if (!nullToAbsent || resolutionCommandId != null) {
      map['resolution_command_id'] = Variable<String>(resolutionCommandId);
    }
    map['created_at_utc'] = Variable<DateTime>(createdAtUtc);
    if (!nullToAbsent || resolvedAtUtc != null) {
      map['resolved_at_utc'] = Variable<DateTime>(resolvedAtUtc);
    }
    return map;
  }

  DbContactRevisionConflictsCompanion toCompanion(bool nullToAbsent) {
    return DbContactRevisionConflictsCompanion(
      conflictId: Value(conflictId),
      commandId: Value(commandId),
      contactId: Value(contactId),
      appUserId: Value(appUserId),
      workspaceId: Value(workspaceId),
      projectId: Value(projectId),
      baseRevision: Value(baseRevision),
      currentRevision: Value(currentRevision),
      conflictingFieldsJson: Value(conflictingFieldsJson),
      questionnaireVersionId: Value(questionnaireVersionId),
      currentRevisionKind: Value(currentRevisionKind),
      currentRevisedAtUtc: Value(currentRevisedAtUtc),
      currentReason: Value(currentReason),
      currentSnapshotJson: Value(currentSnapshotJson),
      proposedSnapshotJson: Value(proposedSnapshotJson),
      status: Value(status),
      resolutionCommandId: resolutionCommandId == null && nullToAbsent
          ? const Value.absent()
          : Value(resolutionCommandId),
      createdAtUtc: Value(createdAtUtc),
      resolvedAtUtc: resolvedAtUtc == null && nullToAbsent
          ? const Value.absent()
          : Value(resolvedAtUtc),
    );
  }

  factory DbContactRevisionConflict.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DbContactRevisionConflict(
      conflictId: serializer.fromJson<String>(json['conflictId']),
      commandId: serializer.fromJson<String>(json['commandId']),
      contactId: serializer.fromJson<String>(json['contactId']),
      appUserId: serializer.fromJson<String>(json['appUserId']),
      workspaceId: serializer.fromJson<String>(json['workspaceId']),
      projectId: serializer.fromJson<String>(json['projectId']),
      baseRevision: serializer.fromJson<int>(json['baseRevision']),
      currentRevision: serializer.fromJson<int>(json['currentRevision']),
      conflictingFieldsJson: serializer.fromJson<String>(
        json['conflictingFieldsJson'],
      ),
      questionnaireVersionId: serializer.fromJson<String>(
        json['questionnaireVersionId'],
      ),
      currentRevisionKind: serializer.fromJson<String>(
        json['currentRevisionKind'],
      ),
      currentRevisedAtUtc: serializer.fromJson<DateTime>(
        json['currentRevisedAtUtc'],
      ),
      currentReason: serializer.fromJson<String>(json['currentReason']),
      currentSnapshotJson: serializer.fromJson<String>(
        json['currentSnapshotJson'],
      ),
      proposedSnapshotJson: serializer.fromJson<String>(
        json['proposedSnapshotJson'],
      ),
      status: serializer.fromJson<String>(json['status']),
      resolutionCommandId: serializer.fromJson<String?>(
        json['resolutionCommandId'],
      ),
      createdAtUtc: serializer.fromJson<DateTime>(json['createdAtUtc']),
      resolvedAtUtc: serializer.fromJson<DateTime?>(json['resolvedAtUtc']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'conflictId': serializer.toJson<String>(conflictId),
      'commandId': serializer.toJson<String>(commandId),
      'contactId': serializer.toJson<String>(contactId),
      'appUserId': serializer.toJson<String>(appUserId),
      'workspaceId': serializer.toJson<String>(workspaceId),
      'projectId': serializer.toJson<String>(projectId),
      'baseRevision': serializer.toJson<int>(baseRevision),
      'currentRevision': serializer.toJson<int>(currentRevision),
      'conflictingFieldsJson': serializer.toJson<String>(conflictingFieldsJson),
      'questionnaireVersionId': serializer.toJson<String>(
        questionnaireVersionId,
      ),
      'currentRevisionKind': serializer.toJson<String>(currentRevisionKind),
      'currentRevisedAtUtc': serializer.toJson<DateTime>(currentRevisedAtUtc),
      'currentReason': serializer.toJson<String>(currentReason),
      'currentSnapshotJson': serializer.toJson<String>(currentSnapshotJson),
      'proposedSnapshotJson': serializer.toJson<String>(proposedSnapshotJson),
      'status': serializer.toJson<String>(status),
      'resolutionCommandId': serializer.toJson<String?>(resolutionCommandId),
      'createdAtUtc': serializer.toJson<DateTime>(createdAtUtc),
      'resolvedAtUtc': serializer.toJson<DateTime?>(resolvedAtUtc),
    };
  }

  DbContactRevisionConflict copyWith({
    String? conflictId,
    String? commandId,
    String? contactId,
    String? appUserId,
    String? workspaceId,
    String? projectId,
    int? baseRevision,
    int? currentRevision,
    String? conflictingFieldsJson,
    String? questionnaireVersionId,
    String? currentRevisionKind,
    DateTime? currentRevisedAtUtc,
    String? currentReason,
    String? currentSnapshotJson,
    String? proposedSnapshotJson,
    String? status,
    Value<String?> resolutionCommandId = const Value.absent(),
    DateTime? createdAtUtc,
    Value<DateTime?> resolvedAtUtc = const Value.absent(),
  }) => DbContactRevisionConflict(
    conflictId: conflictId ?? this.conflictId,
    commandId: commandId ?? this.commandId,
    contactId: contactId ?? this.contactId,
    appUserId: appUserId ?? this.appUserId,
    workspaceId: workspaceId ?? this.workspaceId,
    projectId: projectId ?? this.projectId,
    baseRevision: baseRevision ?? this.baseRevision,
    currentRevision: currentRevision ?? this.currentRevision,
    conflictingFieldsJson: conflictingFieldsJson ?? this.conflictingFieldsJson,
    questionnaireVersionId:
        questionnaireVersionId ?? this.questionnaireVersionId,
    currentRevisionKind: currentRevisionKind ?? this.currentRevisionKind,
    currentRevisedAtUtc: currentRevisedAtUtc ?? this.currentRevisedAtUtc,
    currentReason: currentReason ?? this.currentReason,
    currentSnapshotJson: currentSnapshotJson ?? this.currentSnapshotJson,
    proposedSnapshotJson: proposedSnapshotJson ?? this.proposedSnapshotJson,
    status: status ?? this.status,
    resolutionCommandId: resolutionCommandId.present
        ? resolutionCommandId.value
        : this.resolutionCommandId,
    createdAtUtc: createdAtUtc ?? this.createdAtUtc,
    resolvedAtUtc: resolvedAtUtc.present
        ? resolvedAtUtc.value
        : this.resolvedAtUtc,
  );
  DbContactRevisionConflict copyWithCompanion(
    DbContactRevisionConflictsCompanion data,
  ) {
    return DbContactRevisionConflict(
      conflictId: data.conflictId.present
          ? data.conflictId.value
          : this.conflictId,
      commandId: data.commandId.present ? data.commandId.value : this.commandId,
      contactId: data.contactId.present ? data.contactId.value : this.contactId,
      appUserId: data.appUserId.present ? data.appUserId.value : this.appUserId,
      workspaceId: data.workspaceId.present
          ? data.workspaceId.value
          : this.workspaceId,
      projectId: data.projectId.present ? data.projectId.value : this.projectId,
      baseRevision: data.baseRevision.present
          ? data.baseRevision.value
          : this.baseRevision,
      currentRevision: data.currentRevision.present
          ? data.currentRevision.value
          : this.currentRevision,
      conflictingFieldsJson: data.conflictingFieldsJson.present
          ? data.conflictingFieldsJson.value
          : this.conflictingFieldsJson,
      questionnaireVersionId: data.questionnaireVersionId.present
          ? data.questionnaireVersionId.value
          : this.questionnaireVersionId,
      currentRevisionKind: data.currentRevisionKind.present
          ? data.currentRevisionKind.value
          : this.currentRevisionKind,
      currentRevisedAtUtc: data.currentRevisedAtUtc.present
          ? data.currentRevisedAtUtc.value
          : this.currentRevisedAtUtc,
      currentReason: data.currentReason.present
          ? data.currentReason.value
          : this.currentReason,
      currentSnapshotJson: data.currentSnapshotJson.present
          ? data.currentSnapshotJson.value
          : this.currentSnapshotJson,
      proposedSnapshotJson: data.proposedSnapshotJson.present
          ? data.proposedSnapshotJson.value
          : this.proposedSnapshotJson,
      status: data.status.present ? data.status.value : this.status,
      resolutionCommandId: data.resolutionCommandId.present
          ? data.resolutionCommandId.value
          : this.resolutionCommandId,
      createdAtUtc: data.createdAtUtc.present
          ? data.createdAtUtc.value
          : this.createdAtUtc,
      resolvedAtUtc: data.resolvedAtUtc.present
          ? data.resolvedAtUtc.value
          : this.resolvedAtUtc,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DbContactRevisionConflict(')
          ..write('conflictId: $conflictId, ')
          ..write('commandId: $commandId, ')
          ..write('contactId: $contactId, ')
          ..write('appUserId: $appUserId, ')
          ..write('workspaceId: $workspaceId, ')
          ..write('projectId: $projectId, ')
          ..write('baseRevision: $baseRevision, ')
          ..write('currentRevision: $currentRevision, ')
          ..write('conflictingFieldsJson: $conflictingFieldsJson, ')
          ..write('questionnaireVersionId: $questionnaireVersionId, ')
          ..write('currentRevisionKind: $currentRevisionKind, ')
          ..write('currentRevisedAtUtc: $currentRevisedAtUtc, ')
          ..write('currentReason: $currentReason, ')
          ..write('currentSnapshotJson: $currentSnapshotJson, ')
          ..write('proposedSnapshotJson: $proposedSnapshotJson, ')
          ..write('status: $status, ')
          ..write('resolutionCommandId: $resolutionCommandId, ')
          ..write('createdAtUtc: $createdAtUtc, ')
          ..write('resolvedAtUtc: $resolvedAtUtc')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    conflictId,
    commandId,
    contactId,
    appUserId,
    workspaceId,
    projectId,
    baseRevision,
    currentRevision,
    conflictingFieldsJson,
    questionnaireVersionId,
    currentRevisionKind,
    currentRevisedAtUtc,
    currentReason,
    currentSnapshotJson,
    proposedSnapshotJson,
    status,
    resolutionCommandId,
    createdAtUtc,
    resolvedAtUtc,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DbContactRevisionConflict &&
          other.conflictId == this.conflictId &&
          other.commandId == this.commandId &&
          other.contactId == this.contactId &&
          other.appUserId == this.appUserId &&
          other.workspaceId == this.workspaceId &&
          other.projectId == this.projectId &&
          other.baseRevision == this.baseRevision &&
          other.currentRevision == this.currentRevision &&
          other.conflictingFieldsJson == this.conflictingFieldsJson &&
          other.questionnaireVersionId == this.questionnaireVersionId &&
          other.currentRevisionKind == this.currentRevisionKind &&
          other.currentRevisedAtUtc == this.currentRevisedAtUtc &&
          other.currentReason == this.currentReason &&
          other.currentSnapshotJson == this.currentSnapshotJson &&
          other.proposedSnapshotJson == this.proposedSnapshotJson &&
          other.status == this.status &&
          other.resolutionCommandId == this.resolutionCommandId &&
          other.createdAtUtc == this.createdAtUtc &&
          other.resolvedAtUtc == this.resolvedAtUtc);
}

class DbContactRevisionConflictsCompanion
    extends UpdateCompanion<DbContactRevisionConflict> {
  final Value<String> conflictId;
  final Value<String> commandId;
  final Value<String> contactId;
  final Value<String> appUserId;
  final Value<String> workspaceId;
  final Value<String> projectId;
  final Value<int> baseRevision;
  final Value<int> currentRevision;
  final Value<String> conflictingFieldsJson;
  final Value<String> questionnaireVersionId;
  final Value<String> currentRevisionKind;
  final Value<DateTime> currentRevisedAtUtc;
  final Value<String> currentReason;
  final Value<String> currentSnapshotJson;
  final Value<String> proposedSnapshotJson;
  final Value<String> status;
  final Value<String?> resolutionCommandId;
  final Value<DateTime> createdAtUtc;
  final Value<DateTime?> resolvedAtUtc;
  final Value<int> rowid;
  const DbContactRevisionConflictsCompanion({
    this.conflictId = const Value.absent(),
    this.commandId = const Value.absent(),
    this.contactId = const Value.absent(),
    this.appUserId = const Value.absent(),
    this.workspaceId = const Value.absent(),
    this.projectId = const Value.absent(),
    this.baseRevision = const Value.absent(),
    this.currentRevision = const Value.absent(),
    this.conflictingFieldsJson = const Value.absent(),
    this.questionnaireVersionId = const Value.absent(),
    this.currentRevisionKind = const Value.absent(),
    this.currentRevisedAtUtc = const Value.absent(),
    this.currentReason = const Value.absent(),
    this.currentSnapshotJson = const Value.absent(),
    this.proposedSnapshotJson = const Value.absent(),
    this.status = const Value.absent(),
    this.resolutionCommandId = const Value.absent(),
    this.createdAtUtc = const Value.absent(),
    this.resolvedAtUtc = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DbContactRevisionConflictsCompanion.insert({
    required String conflictId,
    required String commandId,
    required String contactId,
    required String appUserId,
    required String workspaceId,
    required String projectId,
    required int baseRevision,
    required int currentRevision,
    required String conflictingFieldsJson,
    required String questionnaireVersionId,
    required String currentRevisionKind,
    required DateTime currentRevisedAtUtc,
    required String currentReason,
    required String currentSnapshotJson,
    required String proposedSnapshotJson,
    this.status = const Value.absent(),
    this.resolutionCommandId = const Value.absent(),
    required DateTime createdAtUtc,
    this.resolvedAtUtc = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : conflictId = Value(conflictId),
       commandId = Value(commandId),
       contactId = Value(contactId),
       appUserId = Value(appUserId),
       workspaceId = Value(workspaceId),
       projectId = Value(projectId),
       baseRevision = Value(baseRevision),
       currentRevision = Value(currentRevision),
       conflictingFieldsJson = Value(conflictingFieldsJson),
       questionnaireVersionId = Value(questionnaireVersionId),
       currentRevisionKind = Value(currentRevisionKind),
       currentRevisedAtUtc = Value(currentRevisedAtUtc),
       currentReason = Value(currentReason),
       currentSnapshotJson = Value(currentSnapshotJson),
       proposedSnapshotJson = Value(proposedSnapshotJson),
       createdAtUtc = Value(createdAtUtc);
  static Insertable<DbContactRevisionConflict> custom({
    Expression<String>? conflictId,
    Expression<String>? commandId,
    Expression<String>? contactId,
    Expression<String>? appUserId,
    Expression<String>? workspaceId,
    Expression<String>? projectId,
    Expression<int>? baseRevision,
    Expression<int>? currentRevision,
    Expression<String>? conflictingFieldsJson,
    Expression<String>? questionnaireVersionId,
    Expression<String>? currentRevisionKind,
    Expression<DateTime>? currentRevisedAtUtc,
    Expression<String>? currentReason,
    Expression<String>? currentSnapshotJson,
    Expression<String>? proposedSnapshotJson,
    Expression<String>? status,
    Expression<String>? resolutionCommandId,
    Expression<DateTime>? createdAtUtc,
    Expression<DateTime>? resolvedAtUtc,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (conflictId != null) 'conflict_id': conflictId,
      if (commandId != null) 'command_id': commandId,
      if (contactId != null) 'contact_id': contactId,
      if (appUserId != null) 'app_user_id': appUserId,
      if (workspaceId != null) 'workspace_id': workspaceId,
      if (projectId != null) 'project_id': projectId,
      if (baseRevision != null) 'base_revision': baseRevision,
      if (currentRevision != null) 'current_revision': currentRevision,
      if (conflictingFieldsJson != null)
        'conflicting_fields_json': conflictingFieldsJson,
      if (questionnaireVersionId != null)
        'questionnaire_version_id': questionnaireVersionId,
      if (currentRevisionKind != null)
        'current_revision_kind': currentRevisionKind,
      if (currentRevisedAtUtc != null)
        'current_revised_at_utc': currentRevisedAtUtc,
      if (currentReason != null) 'current_reason': currentReason,
      if (currentSnapshotJson != null)
        'current_snapshot_json': currentSnapshotJson,
      if (proposedSnapshotJson != null)
        'proposed_snapshot_json': proposedSnapshotJson,
      if (status != null) 'status': status,
      if (resolutionCommandId != null)
        'resolution_command_id': resolutionCommandId,
      if (createdAtUtc != null) 'created_at_utc': createdAtUtc,
      if (resolvedAtUtc != null) 'resolved_at_utc': resolvedAtUtc,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DbContactRevisionConflictsCompanion copyWith({
    Value<String>? conflictId,
    Value<String>? commandId,
    Value<String>? contactId,
    Value<String>? appUserId,
    Value<String>? workspaceId,
    Value<String>? projectId,
    Value<int>? baseRevision,
    Value<int>? currentRevision,
    Value<String>? conflictingFieldsJson,
    Value<String>? questionnaireVersionId,
    Value<String>? currentRevisionKind,
    Value<DateTime>? currentRevisedAtUtc,
    Value<String>? currentReason,
    Value<String>? currentSnapshotJson,
    Value<String>? proposedSnapshotJson,
    Value<String>? status,
    Value<String?>? resolutionCommandId,
    Value<DateTime>? createdAtUtc,
    Value<DateTime?>? resolvedAtUtc,
    Value<int>? rowid,
  }) {
    return DbContactRevisionConflictsCompanion(
      conflictId: conflictId ?? this.conflictId,
      commandId: commandId ?? this.commandId,
      contactId: contactId ?? this.contactId,
      appUserId: appUserId ?? this.appUserId,
      workspaceId: workspaceId ?? this.workspaceId,
      projectId: projectId ?? this.projectId,
      baseRevision: baseRevision ?? this.baseRevision,
      currentRevision: currentRevision ?? this.currentRevision,
      conflictingFieldsJson:
          conflictingFieldsJson ?? this.conflictingFieldsJson,
      questionnaireVersionId:
          questionnaireVersionId ?? this.questionnaireVersionId,
      currentRevisionKind: currentRevisionKind ?? this.currentRevisionKind,
      currentRevisedAtUtc: currentRevisedAtUtc ?? this.currentRevisedAtUtc,
      currentReason: currentReason ?? this.currentReason,
      currentSnapshotJson: currentSnapshotJson ?? this.currentSnapshotJson,
      proposedSnapshotJson: proposedSnapshotJson ?? this.proposedSnapshotJson,
      status: status ?? this.status,
      resolutionCommandId: resolutionCommandId ?? this.resolutionCommandId,
      createdAtUtc: createdAtUtc ?? this.createdAtUtc,
      resolvedAtUtc: resolvedAtUtc ?? this.resolvedAtUtc,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (conflictId.present) {
      map['conflict_id'] = Variable<String>(conflictId.value);
    }
    if (commandId.present) {
      map['command_id'] = Variable<String>(commandId.value);
    }
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
    if (baseRevision.present) {
      map['base_revision'] = Variable<int>(baseRevision.value);
    }
    if (currentRevision.present) {
      map['current_revision'] = Variable<int>(currentRevision.value);
    }
    if (conflictingFieldsJson.present) {
      map['conflicting_fields_json'] = Variable<String>(
        conflictingFieldsJson.value,
      );
    }
    if (questionnaireVersionId.present) {
      map['questionnaire_version_id'] = Variable<String>(
        questionnaireVersionId.value,
      );
    }
    if (currentRevisionKind.present) {
      map['current_revision_kind'] = Variable<String>(
        currentRevisionKind.value,
      );
    }
    if (currentRevisedAtUtc.present) {
      map['current_revised_at_utc'] = Variable<DateTime>(
        currentRevisedAtUtc.value,
      );
    }
    if (currentReason.present) {
      map['current_reason'] = Variable<String>(currentReason.value);
    }
    if (currentSnapshotJson.present) {
      map['current_snapshot_json'] = Variable<String>(
        currentSnapshotJson.value,
      );
    }
    if (proposedSnapshotJson.present) {
      map['proposed_snapshot_json'] = Variable<String>(
        proposedSnapshotJson.value,
      );
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (resolutionCommandId.present) {
      map['resolution_command_id'] = Variable<String>(
        resolutionCommandId.value,
      );
    }
    if (createdAtUtc.present) {
      map['created_at_utc'] = Variable<DateTime>(createdAtUtc.value);
    }
    if (resolvedAtUtc.present) {
      map['resolved_at_utc'] = Variable<DateTime>(resolvedAtUtc.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DbContactRevisionConflictsCompanion(')
          ..write('conflictId: $conflictId, ')
          ..write('commandId: $commandId, ')
          ..write('contactId: $contactId, ')
          ..write('appUserId: $appUserId, ')
          ..write('workspaceId: $workspaceId, ')
          ..write('projectId: $projectId, ')
          ..write('baseRevision: $baseRevision, ')
          ..write('currentRevision: $currentRevision, ')
          ..write('conflictingFieldsJson: $conflictingFieldsJson, ')
          ..write('questionnaireVersionId: $questionnaireVersionId, ')
          ..write('currentRevisionKind: $currentRevisionKind, ')
          ..write('currentRevisedAtUtc: $currentRevisedAtUtc, ')
          ..write('currentReason: $currentReason, ')
          ..write('currentSnapshotJson: $currentSnapshotJson, ')
          ..write('proposedSnapshotJson: $proposedSnapshotJson, ')
          ..write('status: $status, ')
          ..write('resolutionCommandId: $resolutionCommandId, ')
          ..write('createdAtUtc: $createdAtUtc, ')
          ..write('resolvedAtUtc: $resolvedAtUtc, ')
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
  static const VerificationMeta _regionTreeVersionMeta = const VerificationMeta(
    'regionTreeVersion',
  );
  @override
  late final GeneratedColumn<String> regionTreeVersion =
      GeneratedColumn<String>(
        'region_tree_version',
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
  static const VerificationMeta _localRevisionMeta = const VerificationMeta(
    'localRevision',
  );
  @override
  late final GeneratedColumn<int> localRevision = GeneratedColumn<int>(
    'local_revision',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _serverRevisionMeta = const VerificationMeta(
    'serverRevision',
  );
  @override
  late final GeneratedColumn<int> serverRevision = GeneratedColumn<int>(
    'server_revision',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _sourceAttemptIdMeta = const VerificationMeta(
    'sourceAttemptId',
  );
  @override
  late final GeneratedColumn<String> sourceAttemptId = GeneratedColumn<String>(
    'source_attempt_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _conflictOfDraftIdMeta = const VerificationMeta(
    'conflictOfDraftId',
  );
  @override
  late final GeneratedColumn<String> conflictOfDraftId =
      GeneratedColumn<String>(
        'conflict_of_draft_id',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
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
    regionTreeVersion,
    latitude,
    longitude,
    locationAccuracyMeters,
    reachCount,
    interestLevel,
    syncMode,
    localRevision,
    serverRevision,
    sourceAttemptId,
    conflictOfDraftId,
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
    if (data.containsKey('region_tree_version')) {
      context.handle(
        _regionTreeVersionMeta,
        regionTreeVersion.isAcceptableOrUnknown(
          data['region_tree_version']!,
          _regionTreeVersionMeta,
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
    if (data.containsKey('local_revision')) {
      context.handle(
        _localRevisionMeta,
        localRevision.isAcceptableOrUnknown(
          data['local_revision']!,
          _localRevisionMeta,
        ),
      );
    }
    if (data.containsKey('server_revision')) {
      context.handle(
        _serverRevisionMeta,
        serverRevision.isAcceptableOrUnknown(
          data['server_revision']!,
          _serverRevisionMeta,
        ),
      );
    }
    if (data.containsKey('source_attempt_id')) {
      context.handle(
        _sourceAttemptIdMeta,
        sourceAttemptId.isAcceptableOrUnknown(
          data['source_attempt_id']!,
          _sourceAttemptIdMeta,
        ),
      );
    }
    if (data.containsKey('conflict_of_draft_id')) {
      context.handle(
        _conflictOfDraftIdMeta,
        conflictOfDraftId.isAcceptableOrUnknown(
          data['conflict_of_draft_id']!,
          _conflictOfDraftIdMeta,
        ),
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
      regionTreeVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}region_tree_version'],
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
      localRevision: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}local_revision'],
      )!,
      serverRevision: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}server_revision'],
      )!,
      sourceAttemptId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_attempt_id'],
      ),
      conflictOfDraftId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}conflict_of_draft_id'],
      ),
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
  final String? regionTreeVersion;
  final double? latitude;
  final double? longitude;
  final double? locationAccuracyMeters;
  final int? reachCount;
  final int? interestLevel;
  final String syncMode;
  final int localRevision;
  final int serverRevision;
  final String? sourceAttemptId;
  final String? conflictOfDraftId;
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
    this.regionTreeVersion,
    this.latitude,
    this.longitude,
    this.locationAccuracyMeters,
    this.reachCount,
    this.interestLevel,
    required this.syncMode,
    required this.localRevision,
    required this.serverRevision,
    this.sourceAttemptId,
    this.conflictOfDraftId,
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
    if (!nullToAbsent || regionTreeVersion != null) {
      map['region_tree_version'] = Variable<String>(regionTreeVersion);
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
    map['local_revision'] = Variable<int>(localRevision);
    map['server_revision'] = Variable<int>(serverRevision);
    if (!nullToAbsent || sourceAttemptId != null) {
      map['source_attempt_id'] = Variable<String>(sourceAttemptId);
    }
    if (!nullToAbsent || conflictOfDraftId != null) {
      map['conflict_of_draft_id'] = Variable<String>(conflictOfDraftId);
    }
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
      regionTreeVersion: regionTreeVersion == null && nullToAbsent
          ? const Value.absent()
          : Value(regionTreeVersion),
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
      localRevision: Value(localRevision),
      serverRevision: Value(serverRevision),
      sourceAttemptId: sourceAttemptId == null && nullToAbsent
          ? const Value.absent()
          : Value(sourceAttemptId),
      conflictOfDraftId: conflictOfDraftId == null && nullToAbsent
          ? const Value.absent()
          : Value(conflictOfDraftId),
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
      regionTreeVersion: serializer.fromJson<String?>(
        json['regionTreeVersion'],
      ),
      latitude: serializer.fromJson<double?>(json['latitude']),
      longitude: serializer.fromJson<double?>(json['longitude']),
      locationAccuracyMeters: serializer.fromJson<double?>(
        json['locationAccuracyMeters'],
      ),
      reachCount: serializer.fromJson<int?>(json['reachCount']),
      interestLevel: serializer.fromJson<int?>(json['interestLevel']),
      syncMode: serializer.fromJson<String>(json['syncMode']),
      localRevision: serializer.fromJson<int>(json['localRevision']),
      serverRevision: serializer.fromJson<int>(json['serverRevision']),
      sourceAttemptId: serializer.fromJson<String?>(json['sourceAttemptId']),
      conflictOfDraftId: serializer.fromJson<String?>(
        json['conflictOfDraftId'],
      ),
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
      'regionTreeVersion': serializer.toJson<String?>(regionTreeVersion),
      'latitude': serializer.toJson<double?>(latitude),
      'longitude': serializer.toJson<double?>(longitude),
      'locationAccuracyMeters': serializer.toJson<double?>(
        locationAccuracyMeters,
      ),
      'reachCount': serializer.toJson<int?>(reachCount),
      'interestLevel': serializer.toJson<int?>(interestLevel),
      'syncMode': serializer.toJson<String>(syncMode),
      'localRevision': serializer.toJson<int>(localRevision),
      'serverRevision': serializer.toJson<int>(serverRevision),
      'sourceAttemptId': serializer.toJson<String?>(sourceAttemptId),
      'conflictOfDraftId': serializer.toJson<String?>(conflictOfDraftId),
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
    Value<String?> regionTreeVersion = const Value.absent(),
    Value<double?> latitude = const Value.absent(),
    Value<double?> longitude = const Value.absent(),
    Value<double?> locationAccuracyMeters = const Value.absent(),
    Value<int?> reachCount = const Value.absent(),
    Value<int?> interestLevel = const Value.absent(),
    String? syncMode,
    int? localRevision,
    int? serverRevision,
    Value<String?> sourceAttemptId = const Value.absent(),
    Value<String?> conflictOfDraftId = const Value.absent(),
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
    regionTreeVersion: regionTreeVersion.present
        ? regionTreeVersion.value
        : this.regionTreeVersion,
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
    localRevision: localRevision ?? this.localRevision,
    serverRevision: serverRevision ?? this.serverRevision,
    sourceAttemptId: sourceAttemptId.present
        ? sourceAttemptId.value
        : this.sourceAttemptId,
    conflictOfDraftId: conflictOfDraftId.present
        ? conflictOfDraftId.value
        : this.conflictOfDraftId,
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
      regionTreeVersion: data.regionTreeVersion.present
          ? data.regionTreeVersion.value
          : this.regionTreeVersion,
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
      localRevision: data.localRevision.present
          ? data.localRevision.value
          : this.localRevision,
      serverRevision: data.serverRevision.present
          ? data.serverRevision.value
          : this.serverRevision,
      sourceAttemptId: data.sourceAttemptId.present
          ? data.sourceAttemptId.value
          : this.sourceAttemptId,
      conflictOfDraftId: data.conflictOfDraftId.present
          ? data.conflictOfDraftId.value
          : this.conflictOfDraftId,
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
          ..write('regionTreeVersion: $regionTreeVersion, ')
          ..write('latitude: $latitude, ')
          ..write('longitude: $longitude, ')
          ..write('locationAccuracyMeters: $locationAccuracyMeters, ')
          ..write('reachCount: $reachCount, ')
          ..write('interestLevel: $interestLevel, ')
          ..write('syncMode: $syncMode, ')
          ..write('localRevision: $localRevision, ')
          ..write('serverRevision: $serverRevision, ')
          ..write('sourceAttemptId: $sourceAttemptId, ')
          ..write('conflictOfDraftId: $conflictOfDraftId, ')
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
    regionTreeVersion,
    latitude,
    longitude,
    locationAccuracyMeters,
    reachCount,
    interestLevel,
    syncMode,
    localRevision,
    serverRevision,
    sourceAttemptId,
    conflictOfDraftId,
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
          other.regionTreeVersion == this.regionTreeVersion &&
          other.latitude == this.latitude &&
          other.longitude == this.longitude &&
          other.locationAccuracyMeters == this.locationAccuracyMeters &&
          other.reachCount == this.reachCount &&
          other.interestLevel == this.interestLevel &&
          other.syncMode == this.syncMode &&
          other.localRevision == this.localRevision &&
          other.serverRevision == this.serverRevision &&
          other.sourceAttemptId == this.sourceAttemptId &&
          other.conflictOfDraftId == this.conflictOfDraftId &&
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
  final Value<String?> regionTreeVersion;
  final Value<double?> latitude;
  final Value<double?> longitude;
  final Value<double?> locationAccuracyMeters;
  final Value<int?> reachCount;
  final Value<int?> interestLevel;
  final Value<String> syncMode;
  final Value<int> localRevision;
  final Value<int> serverRevision;
  final Value<String?> sourceAttemptId;
  final Value<String?> conflictOfDraftId;
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
    this.regionTreeVersion = const Value.absent(),
    this.latitude = const Value.absent(),
    this.longitude = const Value.absent(),
    this.locationAccuracyMeters = const Value.absent(),
    this.reachCount = const Value.absent(),
    this.interestLevel = const Value.absent(),
    this.syncMode = const Value.absent(),
    this.localRevision = const Value.absent(),
    this.serverRevision = const Value.absent(),
    this.sourceAttemptId = const Value.absent(),
    this.conflictOfDraftId = const Value.absent(),
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
    this.regionTreeVersion = const Value.absent(),
    this.latitude = const Value.absent(),
    this.longitude = const Value.absent(),
    this.locationAccuracyMeters = const Value.absent(),
    this.reachCount = const Value.absent(),
    this.interestLevel = const Value.absent(),
    this.syncMode = const Value.absent(),
    this.localRevision = const Value.absent(),
    this.serverRevision = const Value.absent(),
    this.sourceAttemptId = const Value.absent(),
    this.conflictOfDraftId = const Value.absent(),
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
    Expression<String>? regionTreeVersion,
    Expression<double>? latitude,
    Expression<double>? longitude,
    Expression<double>? locationAccuracyMeters,
    Expression<int>? reachCount,
    Expression<int>? interestLevel,
    Expression<String>? syncMode,
    Expression<int>? localRevision,
    Expression<int>? serverRevision,
    Expression<String>? sourceAttemptId,
    Expression<String>? conflictOfDraftId,
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
      if (regionTreeVersion != null) 'region_tree_version': regionTreeVersion,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      if (locationAccuracyMeters != null)
        'location_accuracy_meters': locationAccuracyMeters,
      if (reachCount != null) 'reach_count': reachCount,
      if (interestLevel != null) 'interest_level': interestLevel,
      if (syncMode != null) 'sync_mode': syncMode,
      if (localRevision != null) 'local_revision': localRevision,
      if (serverRevision != null) 'server_revision': serverRevision,
      if (sourceAttemptId != null) 'source_attempt_id': sourceAttemptId,
      if (conflictOfDraftId != null) 'conflict_of_draft_id': conflictOfDraftId,
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
    Value<String?>? regionTreeVersion,
    Value<double?>? latitude,
    Value<double?>? longitude,
    Value<double?>? locationAccuracyMeters,
    Value<int?>? reachCount,
    Value<int?>? interestLevel,
    Value<String>? syncMode,
    Value<int>? localRevision,
    Value<int>? serverRevision,
    Value<String?>? sourceAttemptId,
    Value<String?>? conflictOfDraftId,
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
      regionTreeVersion: regionTreeVersion ?? this.regionTreeVersion,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      locationAccuracyMeters:
          locationAccuracyMeters ?? this.locationAccuracyMeters,
      reachCount: reachCount ?? this.reachCount,
      interestLevel: interestLevel ?? this.interestLevel,
      syncMode: syncMode ?? this.syncMode,
      localRevision: localRevision ?? this.localRevision,
      serverRevision: serverRevision ?? this.serverRevision,
      sourceAttemptId: sourceAttemptId ?? this.sourceAttemptId,
      conflictOfDraftId: conflictOfDraftId ?? this.conflictOfDraftId,
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
    if (regionTreeVersion.present) {
      map['region_tree_version'] = Variable<String>(regionTreeVersion.value);
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
    if (localRevision.present) {
      map['local_revision'] = Variable<int>(localRevision.value);
    }
    if (serverRevision.present) {
      map['server_revision'] = Variable<int>(serverRevision.value);
    }
    if (sourceAttemptId.present) {
      map['source_attempt_id'] = Variable<String>(sourceAttemptId.value);
    }
    if (conflictOfDraftId.present) {
      map['conflict_of_draft_id'] = Variable<String>(conflictOfDraftId.value);
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
          ..write('regionTreeVersion: $regionTreeVersion, ')
          ..write('latitude: $latitude, ')
          ..write('longitude: $longitude, ')
          ..write('locationAccuracyMeters: $locationAccuracyMeters, ')
          ..write('reachCount: $reachCount, ')
          ..write('interestLevel: $interestLevel, ')
          ..write('syncMode: $syncMode, ')
          ..write('localRevision: $localRevision, ')
          ..write('serverRevision: $serverRevision, ')
          ..write('sourceAttemptId: $sourceAttemptId, ')
          ..write('conflictOfDraftId: $conflictOfDraftId, ')
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
  static const VerificationMeta _answerStateReasonMeta = const VerificationMeta(
    'answerStateReason',
  );
  @override
  late final GeneratedColumn<String> answerStateReason =
      GeneratedColumn<String>(
        'answer_state_reason',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
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
  static const VerificationMeta _textValueMeta = const VerificationMeta(
    'textValue',
  );
  @override
  late final GeneratedColumn<String> textValue = GeneratedColumn<String>(
    'text_value',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _numberValueMeta = const VerificationMeta(
    'numberValue',
  );
  @override
  late final GeneratedColumn<double> numberValue = GeneratedColumn<double>(
    'number_value',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _multiChoiceValueJsonMeta =
      const VerificationMeta('multiChoiceValueJson');
  @override
  late final GeneratedColumn<String> multiChoiceValueJson =
      GeneratedColumn<String>(
        'multi_choice_value_json',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  @override
  List<GeneratedColumn> get $columns => [
    draftId,
    questionId,
    answerState,
    answerStateReason,
    answerType,
    booleanValue,
    textValue,
    numberValue,
    multiChoiceValueJson,
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
    if (data.containsKey('answer_state_reason')) {
      context.handle(
        _answerStateReasonMeta,
        answerStateReason.isAcceptableOrUnknown(
          data['answer_state_reason']!,
          _answerStateReasonMeta,
        ),
      );
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
    if (data.containsKey('text_value')) {
      context.handle(
        _textValueMeta,
        textValue.isAcceptableOrUnknown(data['text_value']!, _textValueMeta),
      );
    }
    if (data.containsKey('number_value')) {
      context.handle(
        _numberValueMeta,
        numberValue.isAcceptableOrUnknown(
          data['number_value']!,
          _numberValueMeta,
        ),
      );
    }
    if (data.containsKey('multi_choice_value_json')) {
      context.handle(
        _multiChoiceValueJsonMeta,
        multiChoiceValueJson.isAcceptableOrUnknown(
          data['multi_choice_value_json']!,
          _multiChoiceValueJsonMeta,
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
      answerStateReason: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}answer_state_reason'],
      ),
      answerType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}answer_type'],
      )!,
      booleanValue: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}boolean_value'],
      ),
      textValue: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}text_value'],
      ),
      numberValue: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}number_value'],
      ),
      multiChoiceValueJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}multi_choice_value_json'],
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
  final String? answerStateReason;
  final String answerType;
  final bool? booleanValue;
  final String? textValue;
  final double? numberValue;
  final String? multiChoiceValueJson;
  const DbContactDraftAnswer({
    required this.draftId,
    required this.questionId,
    required this.answerState,
    this.answerStateReason,
    required this.answerType,
    this.booleanValue,
    this.textValue,
    this.numberValue,
    this.multiChoiceValueJson,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['draft_id'] = Variable<String>(draftId);
    map['question_id'] = Variable<String>(questionId);
    map['answer_state'] = Variable<String>(answerState);
    if (!nullToAbsent || answerStateReason != null) {
      map['answer_state_reason'] = Variable<String>(answerStateReason);
    }
    map['answer_type'] = Variable<String>(answerType);
    if (!nullToAbsent || booleanValue != null) {
      map['boolean_value'] = Variable<bool>(booleanValue);
    }
    if (!nullToAbsent || textValue != null) {
      map['text_value'] = Variable<String>(textValue);
    }
    if (!nullToAbsent || numberValue != null) {
      map['number_value'] = Variable<double>(numberValue);
    }
    if (!nullToAbsent || multiChoiceValueJson != null) {
      map['multi_choice_value_json'] = Variable<String>(multiChoiceValueJson);
    }
    return map;
  }

  DbContactDraftAnswersCompanion toCompanion(bool nullToAbsent) {
    return DbContactDraftAnswersCompanion(
      draftId: Value(draftId),
      questionId: Value(questionId),
      answerState: Value(answerState),
      answerStateReason: answerStateReason == null && nullToAbsent
          ? const Value.absent()
          : Value(answerStateReason),
      answerType: Value(answerType),
      booleanValue: booleanValue == null && nullToAbsent
          ? const Value.absent()
          : Value(booleanValue),
      textValue: textValue == null && nullToAbsent
          ? const Value.absent()
          : Value(textValue),
      numberValue: numberValue == null && nullToAbsent
          ? const Value.absent()
          : Value(numberValue),
      multiChoiceValueJson: multiChoiceValueJson == null && nullToAbsent
          ? const Value.absent()
          : Value(multiChoiceValueJson),
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
      answerStateReason: serializer.fromJson<String?>(
        json['answerStateReason'],
      ),
      answerType: serializer.fromJson<String>(json['answerType']),
      booleanValue: serializer.fromJson<bool?>(json['booleanValue']),
      textValue: serializer.fromJson<String?>(json['textValue']),
      numberValue: serializer.fromJson<double?>(json['numberValue']),
      multiChoiceValueJson: serializer.fromJson<String?>(
        json['multiChoiceValueJson'],
      ),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'draftId': serializer.toJson<String>(draftId),
      'questionId': serializer.toJson<String>(questionId),
      'answerState': serializer.toJson<String>(answerState),
      'answerStateReason': serializer.toJson<String?>(answerStateReason),
      'answerType': serializer.toJson<String>(answerType),
      'booleanValue': serializer.toJson<bool?>(booleanValue),
      'textValue': serializer.toJson<String?>(textValue),
      'numberValue': serializer.toJson<double?>(numberValue),
      'multiChoiceValueJson': serializer.toJson<String?>(multiChoiceValueJson),
    };
  }

  DbContactDraftAnswer copyWith({
    String? draftId,
    String? questionId,
    String? answerState,
    Value<String?> answerStateReason = const Value.absent(),
    String? answerType,
    Value<bool?> booleanValue = const Value.absent(),
    Value<String?> textValue = const Value.absent(),
    Value<double?> numberValue = const Value.absent(),
    Value<String?> multiChoiceValueJson = const Value.absent(),
  }) => DbContactDraftAnswer(
    draftId: draftId ?? this.draftId,
    questionId: questionId ?? this.questionId,
    answerState: answerState ?? this.answerState,
    answerStateReason: answerStateReason.present
        ? answerStateReason.value
        : this.answerStateReason,
    answerType: answerType ?? this.answerType,
    booleanValue: booleanValue.present ? booleanValue.value : this.booleanValue,
    textValue: textValue.present ? textValue.value : this.textValue,
    numberValue: numberValue.present ? numberValue.value : this.numberValue,
    multiChoiceValueJson: multiChoiceValueJson.present
        ? multiChoiceValueJson.value
        : this.multiChoiceValueJson,
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
      answerStateReason: data.answerStateReason.present
          ? data.answerStateReason.value
          : this.answerStateReason,
      answerType: data.answerType.present
          ? data.answerType.value
          : this.answerType,
      booleanValue: data.booleanValue.present
          ? data.booleanValue.value
          : this.booleanValue,
      textValue: data.textValue.present ? data.textValue.value : this.textValue,
      numberValue: data.numberValue.present
          ? data.numberValue.value
          : this.numberValue,
      multiChoiceValueJson: data.multiChoiceValueJson.present
          ? data.multiChoiceValueJson.value
          : this.multiChoiceValueJson,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DbContactDraftAnswer(')
          ..write('draftId: $draftId, ')
          ..write('questionId: $questionId, ')
          ..write('answerState: $answerState, ')
          ..write('answerStateReason: $answerStateReason, ')
          ..write('answerType: $answerType, ')
          ..write('booleanValue: $booleanValue, ')
          ..write('textValue: $textValue, ')
          ..write('numberValue: $numberValue, ')
          ..write('multiChoiceValueJson: $multiChoiceValueJson')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    draftId,
    questionId,
    answerState,
    answerStateReason,
    answerType,
    booleanValue,
    textValue,
    numberValue,
    multiChoiceValueJson,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DbContactDraftAnswer &&
          other.draftId == this.draftId &&
          other.questionId == this.questionId &&
          other.answerState == this.answerState &&
          other.answerStateReason == this.answerStateReason &&
          other.answerType == this.answerType &&
          other.booleanValue == this.booleanValue &&
          other.textValue == this.textValue &&
          other.numberValue == this.numberValue &&
          other.multiChoiceValueJson == this.multiChoiceValueJson);
}

class DbContactDraftAnswersCompanion
    extends UpdateCompanion<DbContactDraftAnswer> {
  final Value<String> draftId;
  final Value<String> questionId;
  final Value<String> answerState;
  final Value<String?> answerStateReason;
  final Value<String> answerType;
  final Value<bool?> booleanValue;
  final Value<String?> textValue;
  final Value<double?> numberValue;
  final Value<String?> multiChoiceValueJson;
  final Value<int> rowid;
  const DbContactDraftAnswersCompanion({
    this.draftId = const Value.absent(),
    this.questionId = const Value.absent(),
    this.answerState = const Value.absent(),
    this.answerStateReason = const Value.absent(),
    this.answerType = const Value.absent(),
    this.booleanValue = const Value.absent(),
    this.textValue = const Value.absent(),
    this.numberValue = const Value.absent(),
    this.multiChoiceValueJson = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DbContactDraftAnswersCompanion.insert({
    required String draftId,
    required String questionId,
    required String answerState,
    this.answerStateReason = const Value.absent(),
    required String answerType,
    this.booleanValue = const Value.absent(),
    this.textValue = const Value.absent(),
    this.numberValue = const Value.absent(),
    this.multiChoiceValueJson = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : draftId = Value(draftId),
       questionId = Value(questionId),
       answerState = Value(answerState),
       answerType = Value(answerType);
  static Insertable<DbContactDraftAnswer> custom({
    Expression<String>? draftId,
    Expression<String>? questionId,
    Expression<String>? answerState,
    Expression<String>? answerStateReason,
    Expression<String>? answerType,
    Expression<bool>? booleanValue,
    Expression<String>? textValue,
    Expression<double>? numberValue,
    Expression<String>? multiChoiceValueJson,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (draftId != null) 'draft_id': draftId,
      if (questionId != null) 'question_id': questionId,
      if (answerState != null) 'answer_state': answerState,
      if (answerStateReason != null) 'answer_state_reason': answerStateReason,
      if (answerType != null) 'answer_type': answerType,
      if (booleanValue != null) 'boolean_value': booleanValue,
      if (textValue != null) 'text_value': textValue,
      if (numberValue != null) 'number_value': numberValue,
      if (multiChoiceValueJson != null)
        'multi_choice_value_json': multiChoiceValueJson,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DbContactDraftAnswersCompanion copyWith({
    Value<String>? draftId,
    Value<String>? questionId,
    Value<String>? answerState,
    Value<String?>? answerStateReason,
    Value<String>? answerType,
    Value<bool?>? booleanValue,
    Value<String?>? textValue,
    Value<double?>? numberValue,
    Value<String?>? multiChoiceValueJson,
    Value<int>? rowid,
  }) {
    return DbContactDraftAnswersCompanion(
      draftId: draftId ?? this.draftId,
      questionId: questionId ?? this.questionId,
      answerState: answerState ?? this.answerState,
      answerStateReason: answerStateReason ?? this.answerStateReason,
      answerType: answerType ?? this.answerType,
      booleanValue: booleanValue ?? this.booleanValue,
      textValue: textValue ?? this.textValue,
      numberValue: numberValue ?? this.numberValue,
      multiChoiceValueJson: multiChoiceValueJson ?? this.multiChoiceValueJson,
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
    if (answerStateReason.present) {
      map['answer_state_reason'] = Variable<String>(answerStateReason.value);
    }
    if (answerType.present) {
      map['answer_type'] = Variable<String>(answerType.value);
    }
    if (booleanValue.present) {
      map['boolean_value'] = Variable<bool>(booleanValue.value);
    }
    if (textValue.present) {
      map['text_value'] = Variable<String>(textValue.value);
    }
    if (numberValue.present) {
      map['number_value'] = Variable<double>(numberValue.value);
    }
    if (multiChoiceValueJson.present) {
      map['multi_choice_value_json'] = Variable<String>(
        multiChoiceValueJson.value,
      );
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
          ..write('answerStateReason: $answerStateReason, ')
          ..write('answerType: $answerType, ')
          ..write('booleanValue: $booleanValue, ')
          ..write('textValue: $textValue, ')
          ..write('numberValue: $numberValue, ')
          ..write('multiChoiceValueJson: $multiChoiceValueJson, ')
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

class $DbCanonicalRegionVersionsTable extends DbCanonicalRegionVersions
    with TableInfo<$DbCanonicalRegionVersionsTable, DbCanonicalRegionVersion> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DbCanonicalRegionVersionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _regionVersionKeyMeta = const VerificationMeta(
    'regionVersionKey',
  );
  @override
  late final GeneratedColumn<String> regionVersionKey = GeneratedColumn<String>(
    'region_version_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _regionIdMeta = const VerificationMeta(
    'regionId',
  );
  @override
  late final GeneratedColumn<String> regionId = GeneratedColumn<String>(
    'region_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _treeVersionMeta = const VerificationMeta(
    'treeVersion',
  );
  @override
  late final GeneratedColumn<String> treeVersion = GeneratedColumn<String>(
    'tree_version',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _parentRegionVersionKeyMeta =
      const VerificationMeta('parentRegionVersionKey');
  @override
  late final GeneratedColumn<String> parentRegionVersionKey =
      GeneratedColumn<String>(
        'parent_region_version_key',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultConstraints: GeneratedColumn.constraintIsAlways(
          'REFERENCES db_canonical_region_versions (region_version_key)',
        ),
      );
  static const VerificationMeta _canonicalNameMeta = const VerificationMeta(
    'canonicalName',
  );
  @override
  late final GeneratedColumn<String> canonicalName = GeneratedColumn<String>(
    'canonical_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _attributesJsonMeta = const VerificationMeta(
    'attributesJson',
  );
  @override
  late final GeneratedColumn<String> attributesJson = GeneratedColumn<String>(
    'attributes_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    regionVersionKey,
    regionId,
    treeVersion,
    parentRegionVersionKey,
    canonicalName,
    kind,
    attributesJson,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'db_canonical_region_versions';
  @override
  VerificationContext validateIntegrity(
    Insertable<DbCanonicalRegionVersion> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('region_version_key')) {
      context.handle(
        _regionVersionKeyMeta,
        regionVersionKey.isAcceptableOrUnknown(
          data['region_version_key']!,
          _regionVersionKeyMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_regionVersionKeyMeta);
    }
    if (data.containsKey('region_id')) {
      context.handle(
        _regionIdMeta,
        regionId.isAcceptableOrUnknown(data['region_id']!, _regionIdMeta),
      );
    } else if (isInserting) {
      context.missing(_regionIdMeta);
    }
    if (data.containsKey('tree_version')) {
      context.handle(
        _treeVersionMeta,
        treeVersion.isAcceptableOrUnknown(
          data['tree_version']!,
          _treeVersionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_treeVersionMeta);
    }
    if (data.containsKey('parent_region_version_key')) {
      context.handle(
        _parentRegionVersionKeyMeta,
        parentRegionVersionKey.isAcceptableOrUnknown(
          data['parent_region_version_key']!,
          _parentRegionVersionKeyMeta,
        ),
      );
    }
    if (data.containsKey('canonical_name')) {
      context.handle(
        _canonicalNameMeta,
        canonicalName.isAcceptableOrUnknown(
          data['canonical_name']!,
          _canonicalNameMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_canonicalNameMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('attributes_json')) {
      context.handle(
        _attributesJsonMeta,
        attributesJson.isAcceptableOrUnknown(
          data['attributes_json']!,
          _attributesJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_attributesJsonMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {regionVersionKey};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {regionId, treeVersion},
  ];
  @override
  DbCanonicalRegionVersion map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DbCanonicalRegionVersion(
      regionVersionKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}region_version_key'],
      )!,
      regionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}region_id'],
      )!,
      treeVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tree_version'],
      )!,
      parentRegionVersionKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}parent_region_version_key'],
      ),
      canonicalName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}canonical_name'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      attributesJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}attributes_json'],
      )!,
    );
  }

  @override
  $DbCanonicalRegionVersionsTable createAlias(String alias) {
    return $DbCanonicalRegionVersionsTable(attachedDatabase, alias);
  }
}

class DbCanonicalRegionVersion extends DataClass
    implements Insertable<DbCanonicalRegionVersion> {
  final String regionVersionKey;
  final String regionId;
  final String treeVersion;
  final String? parentRegionVersionKey;
  final String canonicalName;
  final String kind;
  final String attributesJson;
  const DbCanonicalRegionVersion({
    required this.regionVersionKey,
    required this.regionId,
    required this.treeVersion,
    this.parentRegionVersionKey,
    required this.canonicalName,
    required this.kind,
    required this.attributesJson,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['region_version_key'] = Variable<String>(regionVersionKey);
    map['region_id'] = Variable<String>(regionId);
    map['tree_version'] = Variable<String>(treeVersion);
    if (!nullToAbsent || parentRegionVersionKey != null) {
      map['parent_region_version_key'] = Variable<String>(
        parentRegionVersionKey,
      );
    }
    map['canonical_name'] = Variable<String>(canonicalName);
    map['kind'] = Variable<String>(kind);
    map['attributes_json'] = Variable<String>(attributesJson);
    return map;
  }

  DbCanonicalRegionVersionsCompanion toCompanion(bool nullToAbsent) {
    return DbCanonicalRegionVersionsCompanion(
      regionVersionKey: Value(regionVersionKey),
      regionId: Value(regionId),
      treeVersion: Value(treeVersion),
      parentRegionVersionKey: parentRegionVersionKey == null && nullToAbsent
          ? const Value.absent()
          : Value(parentRegionVersionKey),
      canonicalName: Value(canonicalName),
      kind: Value(kind),
      attributesJson: Value(attributesJson),
    );
  }

  factory DbCanonicalRegionVersion.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DbCanonicalRegionVersion(
      regionVersionKey: serializer.fromJson<String>(json['regionVersionKey']),
      regionId: serializer.fromJson<String>(json['regionId']),
      treeVersion: serializer.fromJson<String>(json['treeVersion']),
      parentRegionVersionKey: serializer.fromJson<String?>(
        json['parentRegionVersionKey'],
      ),
      canonicalName: serializer.fromJson<String>(json['canonicalName']),
      kind: serializer.fromJson<String>(json['kind']),
      attributesJson: serializer.fromJson<String>(json['attributesJson']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'regionVersionKey': serializer.toJson<String>(regionVersionKey),
      'regionId': serializer.toJson<String>(regionId),
      'treeVersion': serializer.toJson<String>(treeVersion),
      'parentRegionVersionKey': serializer.toJson<String?>(
        parentRegionVersionKey,
      ),
      'canonicalName': serializer.toJson<String>(canonicalName),
      'kind': serializer.toJson<String>(kind),
      'attributesJson': serializer.toJson<String>(attributesJson),
    };
  }

  DbCanonicalRegionVersion copyWith({
    String? regionVersionKey,
    String? regionId,
    String? treeVersion,
    Value<String?> parentRegionVersionKey = const Value.absent(),
    String? canonicalName,
    String? kind,
    String? attributesJson,
  }) => DbCanonicalRegionVersion(
    regionVersionKey: regionVersionKey ?? this.regionVersionKey,
    regionId: regionId ?? this.regionId,
    treeVersion: treeVersion ?? this.treeVersion,
    parentRegionVersionKey: parentRegionVersionKey.present
        ? parentRegionVersionKey.value
        : this.parentRegionVersionKey,
    canonicalName: canonicalName ?? this.canonicalName,
    kind: kind ?? this.kind,
    attributesJson: attributesJson ?? this.attributesJson,
  );
  DbCanonicalRegionVersion copyWithCompanion(
    DbCanonicalRegionVersionsCompanion data,
  ) {
    return DbCanonicalRegionVersion(
      regionVersionKey: data.regionVersionKey.present
          ? data.regionVersionKey.value
          : this.regionVersionKey,
      regionId: data.regionId.present ? data.regionId.value : this.regionId,
      treeVersion: data.treeVersion.present
          ? data.treeVersion.value
          : this.treeVersion,
      parentRegionVersionKey: data.parentRegionVersionKey.present
          ? data.parentRegionVersionKey.value
          : this.parentRegionVersionKey,
      canonicalName: data.canonicalName.present
          ? data.canonicalName.value
          : this.canonicalName,
      kind: data.kind.present ? data.kind.value : this.kind,
      attributesJson: data.attributesJson.present
          ? data.attributesJson.value
          : this.attributesJson,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DbCanonicalRegionVersion(')
          ..write('regionVersionKey: $regionVersionKey, ')
          ..write('regionId: $regionId, ')
          ..write('treeVersion: $treeVersion, ')
          ..write('parentRegionVersionKey: $parentRegionVersionKey, ')
          ..write('canonicalName: $canonicalName, ')
          ..write('kind: $kind, ')
          ..write('attributesJson: $attributesJson')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    regionVersionKey,
    regionId,
    treeVersion,
    parentRegionVersionKey,
    canonicalName,
    kind,
    attributesJson,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DbCanonicalRegionVersion &&
          other.regionVersionKey == this.regionVersionKey &&
          other.regionId == this.regionId &&
          other.treeVersion == this.treeVersion &&
          other.parentRegionVersionKey == this.parentRegionVersionKey &&
          other.canonicalName == this.canonicalName &&
          other.kind == this.kind &&
          other.attributesJson == this.attributesJson);
}

class DbCanonicalRegionVersionsCompanion
    extends UpdateCompanion<DbCanonicalRegionVersion> {
  final Value<String> regionVersionKey;
  final Value<String> regionId;
  final Value<String> treeVersion;
  final Value<String?> parentRegionVersionKey;
  final Value<String> canonicalName;
  final Value<String> kind;
  final Value<String> attributesJson;
  final Value<int> rowid;
  const DbCanonicalRegionVersionsCompanion({
    this.regionVersionKey = const Value.absent(),
    this.regionId = const Value.absent(),
    this.treeVersion = const Value.absent(),
    this.parentRegionVersionKey = const Value.absent(),
    this.canonicalName = const Value.absent(),
    this.kind = const Value.absent(),
    this.attributesJson = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DbCanonicalRegionVersionsCompanion.insert({
    required String regionVersionKey,
    required String regionId,
    required String treeVersion,
    this.parentRegionVersionKey = const Value.absent(),
    required String canonicalName,
    required String kind,
    required String attributesJson,
    this.rowid = const Value.absent(),
  }) : regionVersionKey = Value(regionVersionKey),
       regionId = Value(regionId),
       treeVersion = Value(treeVersion),
       canonicalName = Value(canonicalName),
       kind = Value(kind),
       attributesJson = Value(attributesJson);
  static Insertable<DbCanonicalRegionVersion> custom({
    Expression<String>? regionVersionKey,
    Expression<String>? regionId,
    Expression<String>? treeVersion,
    Expression<String>? parentRegionVersionKey,
    Expression<String>? canonicalName,
    Expression<String>? kind,
    Expression<String>? attributesJson,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (regionVersionKey != null) 'region_version_key': regionVersionKey,
      if (regionId != null) 'region_id': regionId,
      if (treeVersion != null) 'tree_version': treeVersion,
      if (parentRegionVersionKey != null)
        'parent_region_version_key': parentRegionVersionKey,
      if (canonicalName != null) 'canonical_name': canonicalName,
      if (kind != null) 'kind': kind,
      if (attributesJson != null) 'attributes_json': attributesJson,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DbCanonicalRegionVersionsCompanion copyWith({
    Value<String>? regionVersionKey,
    Value<String>? regionId,
    Value<String>? treeVersion,
    Value<String?>? parentRegionVersionKey,
    Value<String>? canonicalName,
    Value<String>? kind,
    Value<String>? attributesJson,
    Value<int>? rowid,
  }) {
    return DbCanonicalRegionVersionsCompanion(
      regionVersionKey: regionVersionKey ?? this.regionVersionKey,
      regionId: regionId ?? this.regionId,
      treeVersion: treeVersion ?? this.treeVersion,
      parentRegionVersionKey:
          parentRegionVersionKey ?? this.parentRegionVersionKey,
      canonicalName: canonicalName ?? this.canonicalName,
      kind: kind ?? this.kind,
      attributesJson: attributesJson ?? this.attributesJson,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (regionVersionKey.present) {
      map['region_version_key'] = Variable<String>(regionVersionKey.value);
    }
    if (regionId.present) {
      map['region_id'] = Variable<String>(regionId.value);
    }
    if (treeVersion.present) {
      map['tree_version'] = Variable<String>(treeVersion.value);
    }
    if (parentRegionVersionKey.present) {
      map['parent_region_version_key'] = Variable<String>(
        parentRegionVersionKey.value,
      );
    }
    if (canonicalName.present) {
      map['canonical_name'] = Variable<String>(canonicalName.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (attributesJson.present) {
      map['attributes_json'] = Variable<String>(attributesJson.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DbCanonicalRegionVersionsCompanion(')
          ..write('regionVersionKey: $regionVersionKey, ')
          ..write('regionId: $regionId, ')
          ..write('treeVersion: $treeVersion, ')
          ..write('parentRegionVersionKey: $parentRegionVersionKey, ')
          ..write('canonicalName: $canonicalName, ')
          ..write('kind: $kind, ')
          ..write('attributesJson: $attributesJson, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $DbContactRegionAssignmentsTable extends DbContactRegionAssignments
    with
        TableInfo<$DbContactRegionAssignmentsTable, DbContactRegionAssignment> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DbContactRegionAssignmentsTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _regionVersionKeyMeta = const VerificationMeta(
    'regionVersionKey',
  );
  @override
  late final GeneratedColumn<String> regionVersionKey = GeneratedColumn<String>(
    'region_version_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES db_canonical_region_versions (region_version_key)',
    ),
  );
  @override
  List<GeneratedColumn> get $columns => [contactId, regionVersionKey];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'db_contact_region_assignments';
  @override
  VerificationContext validateIntegrity(
    Insertable<DbContactRegionAssignment> instance, {
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
    if (data.containsKey('region_version_key')) {
      context.handle(
        _regionVersionKeyMeta,
        regionVersionKey.isAcceptableOrUnknown(
          data['region_version_key']!,
          _regionVersionKeyMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_regionVersionKeyMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {contactId};
  @override
  DbContactRegionAssignment map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DbContactRegionAssignment(
      contactId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}contact_id'],
      )!,
      regionVersionKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}region_version_key'],
      )!,
    );
  }

  @override
  $DbContactRegionAssignmentsTable createAlias(String alias) {
    return $DbContactRegionAssignmentsTable(attachedDatabase, alias);
  }
}

class DbContactRegionAssignment extends DataClass
    implements Insertable<DbContactRegionAssignment> {
  final String contactId;
  final String regionVersionKey;
  const DbContactRegionAssignment({
    required this.contactId,
    required this.regionVersionKey,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['contact_id'] = Variable<String>(contactId);
    map['region_version_key'] = Variable<String>(regionVersionKey);
    return map;
  }

  DbContactRegionAssignmentsCompanion toCompanion(bool nullToAbsent) {
    return DbContactRegionAssignmentsCompanion(
      contactId: Value(contactId),
      regionVersionKey: Value(regionVersionKey),
    );
  }

  factory DbContactRegionAssignment.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DbContactRegionAssignment(
      contactId: serializer.fromJson<String>(json['contactId']),
      regionVersionKey: serializer.fromJson<String>(json['regionVersionKey']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'contactId': serializer.toJson<String>(contactId),
      'regionVersionKey': serializer.toJson<String>(regionVersionKey),
    };
  }

  DbContactRegionAssignment copyWith({
    String? contactId,
    String? regionVersionKey,
  }) => DbContactRegionAssignment(
    contactId: contactId ?? this.contactId,
    regionVersionKey: regionVersionKey ?? this.regionVersionKey,
  );
  DbContactRegionAssignment copyWithCompanion(
    DbContactRegionAssignmentsCompanion data,
  ) {
    return DbContactRegionAssignment(
      contactId: data.contactId.present ? data.contactId.value : this.contactId,
      regionVersionKey: data.regionVersionKey.present
          ? data.regionVersionKey.value
          : this.regionVersionKey,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DbContactRegionAssignment(')
          ..write('contactId: $contactId, ')
          ..write('regionVersionKey: $regionVersionKey')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(contactId, regionVersionKey);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DbContactRegionAssignment &&
          other.contactId == this.contactId &&
          other.regionVersionKey == this.regionVersionKey);
}

class DbContactRegionAssignmentsCompanion
    extends UpdateCompanion<DbContactRegionAssignment> {
  final Value<String> contactId;
  final Value<String> regionVersionKey;
  final Value<int> rowid;
  const DbContactRegionAssignmentsCompanion({
    this.contactId = const Value.absent(),
    this.regionVersionKey = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DbContactRegionAssignmentsCompanion.insert({
    required String contactId,
    required String regionVersionKey,
    this.rowid = const Value.absent(),
  }) : contactId = Value(contactId),
       regionVersionKey = Value(regionVersionKey);
  static Insertable<DbContactRegionAssignment> custom({
    Expression<String>? contactId,
    Expression<String>? regionVersionKey,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (contactId != null) 'contact_id': contactId,
      if (regionVersionKey != null) 'region_version_key': regionVersionKey,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DbContactRegionAssignmentsCompanion copyWith({
    Value<String>? contactId,
    Value<String>? regionVersionKey,
    Value<int>? rowid,
  }) {
    return DbContactRegionAssignmentsCompanion(
      contactId: contactId ?? this.contactId,
      regionVersionKey: regionVersionKey ?? this.regionVersionKey,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (contactId.present) {
      map['contact_id'] = Variable<String>(contactId.value);
    }
    if (regionVersionKey.present) {
      map['region_version_key'] = Variable<String>(regionVersionKey.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DbContactRegionAssignmentsCompanion(')
          ..write('contactId: $contactId, ')
          ..write('regionVersionKey: $regionVersionKey, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $DbDraftRegionAssignmentsTable extends DbDraftRegionAssignments
    with TableInfo<$DbDraftRegionAssignmentsTable, DbDraftRegionAssignment> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DbDraftRegionAssignmentsTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _regionVersionKeyMeta = const VerificationMeta(
    'regionVersionKey',
  );
  @override
  late final GeneratedColumn<String> regionVersionKey = GeneratedColumn<String>(
    'region_version_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES db_canonical_region_versions (region_version_key)',
    ),
  );
  @override
  List<GeneratedColumn> get $columns => [draftId, regionVersionKey];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'db_draft_region_assignments';
  @override
  VerificationContext validateIntegrity(
    Insertable<DbDraftRegionAssignment> instance, {
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
    if (data.containsKey('region_version_key')) {
      context.handle(
        _regionVersionKeyMeta,
        regionVersionKey.isAcceptableOrUnknown(
          data['region_version_key']!,
          _regionVersionKeyMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_regionVersionKeyMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {draftId};
  @override
  DbDraftRegionAssignment map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DbDraftRegionAssignment(
      draftId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}draft_id'],
      )!,
      regionVersionKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}region_version_key'],
      )!,
    );
  }

  @override
  $DbDraftRegionAssignmentsTable createAlias(String alias) {
    return $DbDraftRegionAssignmentsTable(attachedDatabase, alias);
  }
}

class DbDraftRegionAssignment extends DataClass
    implements Insertable<DbDraftRegionAssignment> {
  final String draftId;
  final String regionVersionKey;
  const DbDraftRegionAssignment({
    required this.draftId,
    required this.regionVersionKey,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['draft_id'] = Variable<String>(draftId);
    map['region_version_key'] = Variable<String>(regionVersionKey);
    return map;
  }

  DbDraftRegionAssignmentsCompanion toCompanion(bool nullToAbsent) {
    return DbDraftRegionAssignmentsCompanion(
      draftId: Value(draftId),
      regionVersionKey: Value(regionVersionKey),
    );
  }

  factory DbDraftRegionAssignment.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DbDraftRegionAssignment(
      draftId: serializer.fromJson<String>(json['draftId']),
      regionVersionKey: serializer.fromJson<String>(json['regionVersionKey']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'draftId': serializer.toJson<String>(draftId),
      'regionVersionKey': serializer.toJson<String>(regionVersionKey),
    };
  }

  DbDraftRegionAssignment copyWith({
    String? draftId,
    String? regionVersionKey,
  }) => DbDraftRegionAssignment(
    draftId: draftId ?? this.draftId,
    regionVersionKey: regionVersionKey ?? this.regionVersionKey,
  );
  DbDraftRegionAssignment copyWithCompanion(
    DbDraftRegionAssignmentsCompanion data,
  ) {
    return DbDraftRegionAssignment(
      draftId: data.draftId.present ? data.draftId.value : this.draftId,
      regionVersionKey: data.regionVersionKey.present
          ? data.regionVersionKey.value
          : this.regionVersionKey,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DbDraftRegionAssignment(')
          ..write('draftId: $draftId, ')
          ..write('regionVersionKey: $regionVersionKey')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(draftId, regionVersionKey);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DbDraftRegionAssignment &&
          other.draftId == this.draftId &&
          other.regionVersionKey == this.regionVersionKey);
}

class DbDraftRegionAssignmentsCompanion
    extends UpdateCompanion<DbDraftRegionAssignment> {
  final Value<String> draftId;
  final Value<String> regionVersionKey;
  final Value<int> rowid;
  const DbDraftRegionAssignmentsCompanion({
    this.draftId = const Value.absent(),
    this.regionVersionKey = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DbDraftRegionAssignmentsCompanion.insert({
    required String draftId,
    required String regionVersionKey,
    this.rowid = const Value.absent(),
  }) : draftId = Value(draftId),
       regionVersionKey = Value(regionVersionKey);
  static Insertable<DbDraftRegionAssignment> custom({
    Expression<String>? draftId,
    Expression<String>? regionVersionKey,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (draftId != null) 'draft_id': draftId,
      if (regionVersionKey != null) 'region_version_key': regionVersionKey,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DbDraftRegionAssignmentsCompanion copyWith({
    Value<String>? draftId,
    Value<String>? regionVersionKey,
    Value<int>? rowid,
  }) {
    return DbDraftRegionAssignmentsCompanion(
      draftId: draftId ?? this.draftId,
      regionVersionKey: regionVersionKey ?? this.regionVersionKey,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (draftId.present) {
      map['draft_id'] = Variable<String>(draftId.value);
    }
    if (regionVersionKey.present) {
      map['region_version_key'] = Variable<String>(regionVersionKey.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DbDraftRegionAssignmentsCompanion(')
          ..write('draftId: $draftId, ')
          ..write('regionVersionKey: $regionVersionKey, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $DbQuestionnaireVersionsTable extends DbQuestionnaireVersions
    with TableInfo<$DbQuestionnaireVersionsTable, DbQuestionnaireVersion> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DbQuestionnaireVersionsTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _versionNumberMeta = const VerificationMeta(
    'versionNumber',
  );
  @override
  late final GeneratedColumn<int> versionNumber = GeneratedColumn<int>(
    'version_number',
    aliasedName,
    false,
    type: DriftSqlType.int,
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
  static const VerificationMeta _installedAtUtcMeta = const VerificationMeta(
    'installedAtUtc',
  );
  @override
  late final GeneratedColumn<DateTime> installedAtUtc =
      GeneratedColumn<DateTime>(
        'installed_at_utc',
        aliasedName,
        false,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: true,
      );
  @override
  List<GeneratedColumn> get $columns => [
    questionnaireVersionId,
    projectId,
    versionNumber,
    status,
    installedAtUtc,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'db_questionnaire_versions';
  @override
  VerificationContext validateIntegrity(
    Insertable<DbQuestionnaireVersion> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
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
    if (data.containsKey('project_id')) {
      context.handle(
        _projectIdMeta,
        projectId.isAcceptableOrUnknown(data['project_id']!, _projectIdMeta),
      );
    } else if (isInserting) {
      context.missing(_projectIdMeta);
    }
    if (data.containsKey('version_number')) {
      context.handle(
        _versionNumberMeta,
        versionNumber.isAcceptableOrUnknown(
          data['version_number']!,
          _versionNumberMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_versionNumberMeta);
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    if (data.containsKey('installed_at_utc')) {
      context.handle(
        _installedAtUtcMeta,
        installedAtUtc.isAcceptableOrUnknown(
          data['installed_at_utc']!,
          _installedAtUtcMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_installedAtUtcMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {questionnaireVersionId};
  @override
  DbQuestionnaireVersion map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DbQuestionnaireVersion(
      questionnaireVersionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}questionnaire_version_id'],
      )!,
      projectId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}project_id'],
      )!,
      versionNumber: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}version_number'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      installedAtUtc: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}installed_at_utc'],
      )!,
    );
  }

  @override
  $DbQuestionnaireVersionsTable createAlias(String alias) {
    return $DbQuestionnaireVersionsTable(attachedDatabase, alias);
  }
}

class DbQuestionnaireVersion extends DataClass
    implements Insertable<DbQuestionnaireVersion> {
  final String questionnaireVersionId;
  final String projectId;
  final int versionNumber;
  final String status;
  final DateTime installedAtUtc;
  const DbQuestionnaireVersion({
    required this.questionnaireVersionId,
    required this.projectId,
    required this.versionNumber,
    required this.status,
    required this.installedAtUtc,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['questionnaire_version_id'] = Variable<String>(questionnaireVersionId);
    map['project_id'] = Variable<String>(projectId);
    map['version_number'] = Variable<int>(versionNumber);
    map['status'] = Variable<String>(status);
    map['installed_at_utc'] = Variable<DateTime>(installedAtUtc);
    return map;
  }

  DbQuestionnaireVersionsCompanion toCompanion(bool nullToAbsent) {
    return DbQuestionnaireVersionsCompanion(
      questionnaireVersionId: Value(questionnaireVersionId),
      projectId: Value(projectId),
      versionNumber: Value(versionNumber),
      status: Value(status),
      installedAtUtc: Value(installedAtUtc),
    );
  }

  factory DbQuestionnaireVersion.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DbQuestionnaireVersion(
      questionnaireVersionId: serializer.fromJson<String>(
        json['questionnaireVersionId'],
      ),
      projectId: serializer.fromJson<String>(json['projectId']),
      versionNumber: serializer.fromJson<int>(json['versionNumber']),
      status: serializer.fromJson<String>(json['status']),
      installedAtUtc: serializer.fromJson<DateTime>(json['installedAtUtc']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'questionnaireVersionId': serializer.toJson<String>(
        questionnaireVersionId,
      ),
      'projectId': serializer.toJson<String>(projectId),
      'versionNumber': serializer.toJson<int>(versionNumber),
      'status': serializer.toJson<String>(status),
      'installedAtUtc': serializer.toJson<DateTime>(installedAtUtc),
    };
  }

  DbQuestionnaireVersion copyWith({
    String? questionnaireVersionId,
    String? projectId,
    int? versionNumber,
    String? status,
    DateTime? installedAtUtc,
  }) => DbQuestionnaireVersion(
    questionnaireVersionId:
        questionnaireVersionId ?? this.questionnaireVersionId,
    projectId: projectId ?? this.projectId,
    versionNumber: versionNumber ?? this.versionNumber,
    status: status ?? this.status,
    installedAtUtc: installedAtUtc ?? this.installedAtUtc,
  );
  DbQuestionnaireVersion copyWithCompanion(
    DbQuestionnaireVersionsCompanion data,
  ) {
    return DbQuestionnaireVersion(
      questionnaireVersionId: data.questionnaireVersionId.present
          ? data.questionnaireVersionId.value
          : this.questionnaireVersionId,
      projectId: data.projectId.present ? data.projectId.value : this.projectId,
      versionNumber: data.versionNumber.present
          ? data.versionNumber.value
          : this.versionNumber,
      status: data.status.present ? data.status.value : this.status,
      installedAtUtc: data.installedAtUtc.present
          ? data.installedAtUtc.value
          : this.installedAtUtc,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DbQuestionnaireVersion(')
          ..write('questionnaireVersionId: $questionnaireVersionId, ')
          ..write('projectId: $projectId, ')
          ..write('versionNumber: $versionNumber, ')
          ..write('status: $status, ')
          ..write('installedAtUtc: $installedAtUtc')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    questionnaireVersionId,
    projectId,
    versionNumber,
    status,
    installedAtUtc,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DbQuestionnaireVersion &&
          other.questionnaireVersionId == this.questionnaireVersionId &&
          other.projectId == this.projectId &&
          other.versionNumber == this.versionNumber &&
          other.status == this.status &&
          other.installedAtUtc == this.installedAtUtc);
}

class DbQuestionnaireVersionsCompanion
    extends UpdateCompanion<DbQuestionnaireVersion> {
  final Value<String> questionnaireVersionId;
  final Value<String> projectId;
  final Value<int> versionNumber;
  final Value<String> status;
  final Value<DateTime> installedAtUtc;
  final Value<int> rowid;
  const DbQuestionnaireVersionsCompanion({
    this.questionnaireVersionId = const Value.absent(),
    this.projectId = const Value.absent(),
    this.versionNumber = const Value.absent(),
    this.status = const Value.absent(),
    this.installedAtUtc = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DbQuestionnaireVersionsCompanion.insert({
    required String questionnaireVersionId,
    required String projectId,
    required int versionNumber,
    required String status,
    required DateTime installedAtUtc,
    this.rowid = const Value.absent(),
  }) : questionnaireVersionId = Value(questionnaireVersionId),
       projectId = Value(projectId),
       versionNumber = Value(versionNumber),
       status = Value(status),
       installedAtUtc = Value(installedAtUtc);
  static Insertable<DbQuestionnaireVersion> custom({
    Expression<String>? questionnaireVersionId,
    Expression<String>? projectId,
    Expression<int>? versionNumber,
    Expression<String>? status,
    Expression<DateTime>? installedAtUtc,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (questionnaireVersionId != null)
        'questionnaire_version_id': questionnaireVersionId,
      if (projectId != null) 'project_id': projectId,
      if (versionNumber != null) 'version_number': versionNumber,
      if (status != null) 'status': status,
      if (installedAtUtc != null) 'installed_at_utc': installedAtUtc,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DbQuestionnaireVersionsCompanion copyWith({
    Value<String>? questionnaireVersionId,
    Value<String>? projectId,
    Value<int>? versionNumber,
    Value<String>? status,
    Value<DateTime>? installedAtUtc,
    Value<int>? rowid,
  }) {
    return DbQuestionnaireVersionsCompanion(
      questionnaireVersionId:
          questionnaireVersionId ?? this.questionnaireVersionId,
      projectId: projectId ?? this.projectId,
      versionNumber: versionNumber ?? this.versionNumber,
      status: status ?? this.status,
      installedAtUtc: installedAtUtc ?? this.installedAtUtc,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (questionnaireVersionId.present) {
      map['questionnaire_version_id'] = Variable<String>(
        questionnaireVersionId.value,
      );
    }
    if (projectId.present) {
      map['project_id'] = Variable<String>(projectId.value);
    }
    if (versionNumber.present) {
      map['version_number'] = Variable<int>(versionNumber.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (installedAtUtc.present) {
      map['installed_at_utc'] = Variable<DateTime>(installedAtUtc.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DbQuestionnaireVersionsCompanion(')
          ..write('questionnaireVersionId: $questionnaireVersionId, ')
          ..write('projectId: $projectId, ')
          ..write('versionNumber: $versionNumber, ')
          ..write('status: $status, ')
          ..write('installedAtUtc: $installedAtUtc, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $DbQuestionnaireQuestionsTable extends DbQuestionnaireQuestions
    with TableInfo<$DbQuestionnaireQuestionsTable, DbQuestionnaireQuestion> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DbQuestionnaireQuestionsTable(this.attachedDatabase, [this._alias]);
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
        defaultConstraints: GeneratedColumn.constraintIsAlways(
          'REFERENCES db_questionnaire_versions (questionnaire_version_id)',
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
  static const VerificationMeta _positionMeta = const VerificationMeta(
    'position',
  );
  @override
  late final GeneratedColumn<int> position = GeneratedColumn<int>(
    'position',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _promptMeta = const VerificationMeta('prompt');
  @override
  late final GeneratedColumn<String> prompt = GeneratedColumn<String>(
    'prompt',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _questionTypeMeta = const VerificationMeta(
    'questionType',
  );
  @override
  late final GeneratedColumn<String> questionType = GeneratedColumn<String>(
    'question_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _isRequiredMeta = const VerificationMeta(
    'isRequired',
  );
  @override
  late final GeneratedColumn<bool> isRequired = GeneratedColumn<bool>(
    'is_required',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_required" IN (0, 1))',
    ),
  );
  static const VerificationMeta _allowUnknownMeta = const VerificationMeta(
    'allowUnknown',
  );
  @override
  late final GeneratedColumn<bool> allowUnknown = GeneratedColumn<bool>(
    'allow_unknown',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("allow_unknown" IN (0, 1))',
    ),
  );
  static const VerificationMeta _allowRefusedMeta = const VerificationMeta(
    'allowRefused',
  );
  @override
  late final GeneratedColumn<bool> allowRefused = GeneratedColumn<bool>(
    'allow_refused',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("allow_refused" IN (0, 1))',
    ),
  );
  static const VerificationMeta _allowNotApplicableMeta =
      const VerificationMeta('allowNotApplicable');
  @override
  late final GeneratedColumn<bool> allowNotApplicable = GeneratedColumn<bool>(
    'allow_not_applicable',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("allow_not_applicable" IN (0, 1))',
    ),
  );
  static const VerificationMeta _minimumSelectionsMeta = const VerificationMeta(
    'minimumSelections',
  );
  @override
  late final GeneratedColumn<int> minimumSelections = GeneratedColumn<int>(
    'minimum_selections',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _maximumSelectionsMeta = const VerificationMeta(
    'maximumSelections',
  );
  @override
  late final GeneratedColumn<int> maximumSelections = GeneratedColumn<int>(
    'maximum_selections',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _numberKindMeta = const VerificationMeta(
    'numberKind',
  );
  @override
  late final GeneratedColumn<String> numberKind = GeneratedColumn<String>(
    'number_kind',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _unitMeta = const VerificationMeta('unit');
  @override
  late final GeneratedColumn<String> unit = GeneratedColumn<String>(
    'unit',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _minimumMeta = const VerificationMeta(
    'minimum',
  );
  @override
  late final GeneratedColumn<double> minimum = GeneratedColumn<double>(
    'minimum',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _maximumMeta = const VerificationMeta(
    'maximum',
  );
  @override
  late final GeneratedColumn<double> maximum = GeneratedColumn<double>(
    'maximum',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _maximumLengthMeta = const VerificationMeta(
    'maximumLength',
  );
  @override
  late final GeneratedColumn<int> maximumLength = GeneratedColumn<int>(
    'maximum_length',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _displayRuleJsonMeta = const VerificationMeta(
    'displayRuleJson',
  );
  @override
  late final GeneratedColumn<String> displayRuleJson = GeneratedColumn<String>(
    'display_rule_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    questionnaireVersionId,
    questionId,
    position,
    prompt,
    questionType,
    isRequired,
    allowUnknown,
    allowRefused,
    allowNotApplicable,
    minimumSelections,
    maximumSelections,
    numberKind,
    unit,
    minimum,
    maximum,
    maximumLength,
    displayRuleJson,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'db_questionnaire_questions';
  @override
  VerificationContext validateIntegrity(
    Insertable<DbQuestionnaireQuestion> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
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
    if (data.containsKey('question_id')) {
      context.handle(
        _questionIdMeta,
        questionId.isAcceptableOrUnknown(data['question_id']!, _questionIdMeta),
      );
    } else if (isInserting) {
      context.missing(_questionIdMeta);
    }
    if (data.containsKey('position')) {
      context.handle(
        _positionMeta,
        position.isAcceptableOrUnknown(data['position']!, _positionMeta),
      );
    } else if (isInserting) {
      context.missing(_positionMeta);
    }
    if (data.containsKey('prompt')) {
      context.handle(
        _promptMeta,
        prompt.isAcceptableOrUnknown(data['prompt']!, _promptMeta),
      );
    } else if (isInserting) {
      context.missing(_promptMeta);
    }
    if (data.containsKey('question_type')) {
      context.handle(
        _questionTypeMeta,
        questionType.isAcceptableOrUnknown(
          data['question_type']!,
          _questionTypeMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_questionTypeMeta);
    }
    if (data.containsKey('is_required')) {
      context.handle(
        _isRequiredMeta,
        isRequired.isAcceptableOrUnknown(data['is_required']!, _isRequiredMeta),
      );
    } else if (isInserting) {
      context.missing(_isRequiredMeta);
    }
    if (data.containsKey('allow_unknown')) {
      context.handle(
        _allowUnknownMeta,
        allowUnknown.isAcceptableOrUnknown(
          data['allow_unknown']!,
          _allowUnknownMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_allowUnknownMeta);
    }
    if (data.containsKey('allow_refused')) {
      context.handle(
        _allowRefusedMeta,
        allowRefused.isAcceptableOrUnknown(
          data['allow_refused']!,
          _allowRefusedMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_allowRefusedMeta);
    }
    if (data.containsKey('allow_not_applicable')) {
      context.handle(
        _allowNotApplicableMeta,
        allowNotApplicable.isAcceptableOrUnknown(
          data['allow_not_applicable']!,
          _allowNotApplicableMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_allowNotApplicableMeta);
    }
    if (data.containsKey('minimum_selections')) {
      context.handle(
        _minimumSelectionsMeta,
        minimumSelections.isAcceptableOrUnknown(
          data['minimum_selections']!,
          _minimumSelectionsMeta,
        ),
      );
    }
    if (data.containsKey('maximum_selections')) {
      context.handle(
        _maximumSelectionsMeta,
        maximumSelections.isAcceptableOrUnknown(
          data['maximum_selections']!,
          _maximumSelectionsMeta,
        ),
      );
    }
    if (data.containsKey('number_kind')) {
      context.handle(
        _numberKindMeta,
        numberKind.isAcceptableOrUnknown(data['number_kind']!, _numberKindMeta),
      );
    }
    if (data.containsKey('unit')) {
      context.handle(
        _unitMeta,
        unit.isAcceptableOrUnknown(data['unit']!, _unitMeta),
      );
    }
    if (data.containsKey('minimum')) {
      context.handle(
        _minimumMeta,
        minimum.isAcceptableOrUnknown(data['minimum']!, _minimumMeta),
      );
    }
    if (data.containsKey('maximum')) {
      context.handle(
        _maximumMeta,
        maximum.isAcceptableOrUnknown(data['maximum']!, _maximumMeta),
      );
    }
    if (data.containsKey('maximum_length')) {
      context.handle(
        _maximumLengthMeta,
        maximumLength.isAcceptableOrUnknown(
          data['maximum_length']!,
          _maximumLengthMeta,
        ),
      );
    }
    if (data.containsKey('display_rule_json')) {
      context.handle(
        _displayRuleJsonMeta,
        displayRuleJson.isAcceptableOrUnknown(
          data['display_rule_json']!,
          _displayRuleJsonMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {questionnaireVersionId, questionId};
  @override
  DbQuestionnaireQuestion map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DbQuestionnaireQuestion(
      questionnaireVersionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}questionnaire_version_id'],
      )!,
      questionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}question_id'],
      )!,
      position: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}position'],
      )!,
      prompt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}prompt'],
      )!,
      questionType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}question_type'],
      )!,
      isRequired: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_required'],
      )!,
      allowUnknown: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}allow_unknown'],
      )!,
      allowRefused: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}allow_refused'],
      )!,
      allowNotApplicable: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}allow_not_applicable'],
      )!,
      minimumSelections: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}minimum_selections'],
      ),
      maximumSelections: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}maximum_selections'],
      ),
      numberKind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}number_kind'],
      ),
      unit: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}unit'],
      ),
      minimum: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}minimum'],
      ),
      maximum: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}maximum'],
      ),
      maximumLength: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}maximum_length'],
      ),
      displayRuleJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}display_rule_json'],
      ),
    );
  }

  @override
  $DbQuestionnaireQuestionsTable createAlias(String alias) {
    return $DbQuestionnaireQuestionsTable(attachedDatabase, alias);
  }
}

class DbQuestionnaireQuestion extends DataClass
    implements Insertable<DbQuestionnaireQuestion> {
  final String questionnaireVersionId;
  final String questionId;
  final int position;
  final String prompt;
  final String questionType;
  final bool isRequired;
  final bool allowUnknown;
  final bool allowRefused;
  final bool allowNotApplicable;
  final int? minimumSelections;
  final int? maximumSelections;
  final String? numberKind;
  final String? unit;
  final double? minimum;
  final double? maximum;
  final int? maximumLength;
  final String? displayRuleJson;
  const DbQuestionnaireQuestion({
    required this.questionnaireVersionId,
    required this.questionId,
    required this.position,
    required this.prompt,
    required this.questionType,
    required this.isRequired,
    required this.allowUnknown,
    required this.allowRefused,
    required this.allowNotApplicable,
    this.minimumSelections,
    this.maximumSelections,
    this.numberKind,
    this.unit,
    this.minimum,
    this.maximum,
    this.maximumLength,
    this.displayRuleJson,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['questionnaire_version_id'] = Variable<String>(questionnaireVersionId);
    map['question_id'] = Variable<String>(questionId);
    map['position'] = Variable<int>(position);
    map['prompt'] = Variable<String>(prompt);
    map['question_type'] = Variable<String>(questionType);
    map['is_required'] = Variable<bool>(isRequired);
    map['allow_unknown'] = Variable<bool>(allowUnknown);
    map['allow_refused'] = Variable<bool>(allowRefused);
    map['allow_not_applicable'] = Variable<bool>(allowNotApplicable);
    if (!nullToAbsent || minimumSelections != null) {
      map['minimum_selections'] = Variable<int>(minimumSelections);
    }
    if (!nullToAbsent || maximumSelections != null) {
      map['maximum_selections'] = Variable<int>(maximumSelections);
    }
    if (!nullToAbsent || numberKind != null) {
      map['number_kind'] = Variable<String>(numberKind);
    }
    if (!nullToAbsent || unit != null) {
      map['unit'] = Variable<String>(unit);
    }
    if (!nullToAbsent || minimum != null) {
      map['minimum'] = Variable<double>(minimum);
    }
    if (!nullToAbsent || maximum != null) {
      map['maximum'] = Variable<double>(maximum);
    }
    if (!nullToAbsent || maximumLength != null) {
      map['maximum_length'] = Variable<int>(maximumLength);
    }
    if (!nullToAbsent || displayRuleJson != null) {
      map['display_rule_json'] = Variable<String>(displayRuleJson);
    }
    return map;
  }

  DbQuestionnaireQuestionsCompanion toCompanion(bool nullToAbsent) {
    return DbQuestionnaireQuestionsCompanion(
      questionnaireVersionId: Value(questionnaireVersionId),
      questionId: Value(questionId),
      position: Value(position),
      prompt: Value(prompt),
      questionType: Value(questionType),
      isRequired: Value(isRequired),
      allowUnknown: Value(allowUnknown),
      allowRefused: Value(allowRefused),
      allowNotApplicable: Value(allowNotApplicable),
      minimumSelections: minimumSelections == null && nullToAbsent
          ? const Value.absent()
          : Value(minimumSelections),
      maximumSelections: maximumSelections == null && nullToAbsent
          ? const Value.absent()
          : Value(maximumSelections),
      numberKind: numberKind == null && nullToAbsent
          ? const Value.absent()
          : Value(numberKind),
      unit: unit == null && nullToAbsent ? const Value.absent() : Value(unit),
      minimum: minimum == null && nullToAbsent
          ? const Value.absent()
          : Value(minimum),
      maximum: maximum == null && nullToAbsent
          ? const Value.absent()
          : Value(maximum),
      maximumLength: maximumLength == null && nullToAbsent
          ? const Value.absent()
          : Value(maximumLength),
      displayRuleJson: displayRuleJson == null && nullToAbsent
          ? const Value.absent()
          : Value(displayRuleJson),
    );
  }

  factory DbQuestionnaireQuestion.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DbQuestionnaireQuestion(
      questionnaireVersionId: serializer.fromJson<String>(
        json['questionnaireVersionId'],
      ),
      questionId: serializer.fromJson<String>(json['questionId']),
      position: serializer.fromJson<int>(json['position']),
      prompt: serializer.fromJson<String>(json['prompt']),
      questionType: serializer.fromJson<String>(json['questionType']),
      isRequired: serializer.fromJson<bool>(json['isRequired']),
      allowUnknown: serializer.fromJson<bool>(json['allowUnknown']),
      allowRefused: serializer.fromJson<bool>(json['allowRefused']),
      allowNotApplicable: serializer.fromJson<bool>(json['allowNotApplicable']),
      minimumSelections: serializer.fromJson<int?>(json['minimumSelections']),
      maximumSelections: serializer.fromJson<int?>(json['maximumSelections']),
      numberKind: serializer.fromJson<String?>(json['numberKind']),
      unit: serializer.fromJson<String?>(json['unit']),
      minimum: serializer.fromJson<double?>(json['minimum']),
      maximum: serializer.fromJson<double?>(json['maximum']),
      maximumLength: serializer.fromJson<int?>(json['maximumLength']),
      displayRuleJson: serializer.fromJson<String?>(json['displayRuleJson']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'questionnaireVersionId': serializer.toJson<String>(
        questionnaireVersionId,
      ),
      'questionId': serializer.toJson<String>(questionId),
      'position': serializer.toJson<int>(position),
      'prompt': serializer.toJson<String>(prompt),
      'questionType': serializer.toJson<String>(questionType),
      'isRequired': serializer.toJson<bool>(isRequired),
      'allowUnknown': serializer.toJson<bool>(allowUnknown),
      'allowRefused': serializer.toJson<bool>(allowRefused),
      'allowNotApplicable': serializer.toJson<bool>(allowNotApplicable),
      'minimumSelections': serializer.toJson<int?>(minimumSelections),
      'maximumSelections': serializer.toJson<int?>(maximumSelections),
      'numberKind': serializer.toJson<String?>(numberKind),
      'unit': serializer.toJson<String?>(unit),
      'minimum': serializer.toJson<double?>(minimum),
      'maximum': serializer.toJson<double?>(maximum),
      'maximumLength': serializer.toJson<int?>(maximumLength),
      'displayRuleJson': serializer.toJson<String?>(displayRuleJson),
    };
  }

  DbQuestionnaireQuestion copyWith({
    String? questionnaireVersionId,
    String? questionId,
    int? position,
    String? prompt,
    String? questionType,
    bool? isRequired,
    bool? allowUnknown,
    bool? allowRefused,
    bool? allowNotApplicable,
    Value<int?> minimumSelections = const Value.absent(),
    Value<int?> maximumSelections = const Value.absent(),
    Value<String?> numberKind = const Value.absent(),
    Value<String?> unit = const Value.absent(),
    Value<double?> minimum = const Value.absent(),
    Value<double?> maximum = const Value.absent(),
    Value<int?> maximumLength = const Value.absent(),
    Value<String?> displayRuleJson = const Value.absent(),
  }) => DbQuestionnaireQuestion(
    questionnaireVersionId:
        questionnaireVersionId ?? this.questionnaireVersionId,
    questionId: questionId ?? this.questionId,
    position: position ?? this.position,
    prompt: prompt ?? this.prompt,
    questionType: questionType ?? this.questionType,
    isRequired: isRequired ?? this.isRequired,
    allowUnknown: allowUnknown ?? this.allowUnknown,
    allowRefused: allowRefused ?? this.allowRefused,
    allowNotApplicable: allowNotApplicable ?? this.allowNotApplicable,
    minimumSelections: minimumSelections.present
        ? minimumSelections.value
        : this.minimumSelections,
    maximumSelections: maximumSelections.present
        ? maximumSelections.value
        : this.maximumSelections,
    numberKind: numberKind.present ? numberKind.value : this.numberKind,
    unit: unit.present ? unit.value : this.unit,
    minimum: minimum.present ? minimum.value : this.minimum,
    maximum: maximum.present ? maximum.value : this.maximum,
    maximumLength: maximumLength.present
        ? maximumLength.value
        : this.maximumLength,
    displayRuleJson: displayRuleJson.present
        ? displayRuleJson.value
        : this.displayRuleJson,
  );
  DbQuestionnaireQuestion copyWithCompanion(
    DbQuestionnaireQuestionsCompanion data,
  ) {
    return DbQuestionnaireQuestion(
      questionnaireVersionId: data.questionnaireVersionId.present
          ? data.questionnaireVersionId.value
          : this.questionnaireVersionId,
      questionId: data.questionId.present
          ? data.questionId.value
          : this.questionId,
      position: data.position.present ? data.position.value : this.position,
      prompt: data.prompt.present ? data.prompt.value : this.prompt,
      questionType: data.questionType.present
          ? data.questionType.value
          : this.questionType,
      isRequired: data.isRequired.present
          ? data.isRequired.value
          : this.isRequired,
      allowUnknown: data.allowUnknown.present
          ? data.allowUnknown.value
          : this.allowUnknown,
      allowRefused: data.allowRefused.present
          ? data.allowRefused.value
          : this.allowRefused,
      allowNotApplicable: data.allowNotApplicable.present
          ? data.allowNotApplicable.value
          : this.allowNotApplicable,
      minimumSelections: data.minimumSelections.present
          ? data.minimumSelections.value
          : this.minimumSelections,
      maximumSelections: data.maximumSelections.present
          ? data.maximumSelections.value
          : this.maximumSelections,
      numberKind: data.numberKind.present
          ? data.numberKind.value
          : this.numberKind,
      unit: data.unit.present ? data.unit.value : this.unit,
      minimum: data.minimum.present ? data.minimum.value : this.minimum,
      maximum: data.maximum.present ? data.maximum.value : this.maximum,
      maximumLength: data.maximumLength.present
          ? data.maximumLength.value
          : this.maximumLength,
      displayRuleJson: data.displayRuleJson.present
          ? data.displayRuleJson.value
          : this.displayRuleJson,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DbQuestionnaireQuestion(')
          ..write('questionnaireVersionId: $questionnaireVersionId, ')
          ..write('questionId: $questionId, ')
          ..write('position: $position, ')
          ..write('prompt: $prompt, ')
          ..write('questionType: $questionType, ')
          ..write('isRequired: $isRequired, ')
          ..write('allowUnknown: $allowUnknown, ')
          ..write('allowRefused: $allowRefused, ')
          ..write('allowNotApplicable: $allowNotApplicable, ')
          ..write('minimumSelections: $minimumSelections, ')
          ..write('maximumSelections: $maximumSelections, ')
          ..write('numberKind: $numberKind, ')
          ..write('unit: $unit, ')
          ..write('minimum: $minimum, ')
          ..write('maximum: $maximum, ')
          ..write('maximumLength: $maximumLength, ')
          ..write('displayRuleJson: $displayRuleJson')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    questionnaireVersionId,
    questionId,
    position,
    prompt,
    questionType,
    isRequired,
    allowUnknown,
    allowRefused,
    allowNotApplicable,
    minimumSelections,
    maximumSelections,
    numberKind,
    unit,
    minimum,
    maximum,
    maximumLength,
    displayRuleJson,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DbQuestionnaireQuestion &&
          other.questionnaireVersionId == this.questionnaireVersionId &&
          other.questionId == this.questionId &&
          other.position == this.position &&
          other.prompt == this.prompt &&
          other.questionType == this.questionType &&
          other.isRequired == this.isRequired &&
          other.allowUnknown == this.allowUnknown &&
          other.allowRefused == this.allowRefused &&
          other.allowNotApplicable == this.allowNotApplicable &&
          other.minimumSelections == this.minimumSelections &&
          other.maximumSelections == this.maximumSelections &&
          other.numberKind == this.numberKind &&
          other.unit == this.unit &&
          other.minimum == this.minimum &&
          other.maximum == this.maximum &&
          other.maximumLength == this.maximumLength &&
          other.displayRuleJson == this.displayRuleJson);
}

class DbQuestionnaireQuestionsCompanion
    extends UpdateCompanion<DbQuestionnaireQuestion> {
  final Value<String> questionnaireVersionId;
  final Value<String> questionId;
  final Value<int> position;
  final Value<String> prompt;
  final Value<String> questionType;
  final Value<bool> isRequired;
  final Value<bool> allowUnknown;
  final Value<bool> allowRefused;
  final Value<bool> allowNotApplicable;
  final Value<int?> minimumSelections;
  final Value<int?> maximumSelections;
  final Value<String?> numberKind;
  final Value<String?> unit;
  final Value<double?> minimum;
  final Value<double?> maximum;
  final Value<int?> maximumLength;
  final Value<String?> displayRuleJson;
  final Value<int> rowid;
  const DbQuestionnaireQuestionsCompanion({
    this.questionnaireVersionId = const Value.absent(),
    this.questionId = const Value.absent(),
    this.position = const Value.absent(),
    this.prompt = const Value.absent(),
    this.questionType = const Value.absent(),
    this.isRequired = const Value.absent(),
    this.allowUnknown = const Value.absent(),
    this.allowRefused = const Value.absent(),
    this.allowNotApplicable = const Value.absent(),
    this.minimumSelections = const Value.absent(),
    this.maximumSelections = const Value.absent(),
    this.numberKind = const Value.absent(),
    this.unit = const Value.absent(),
    this.minimum = const Value.absent(),
    this.maximum = const Value.absent(),
    this.maximumLength = const Value.absent(),
    this.displayRuleJson = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DbQuestionnaireQuestionsCompanion.insert({
    required String questionnaireVersionId,
    required String questionId,
    required int position,
    required String prompt,
    required String questionType,
    required bool isRequired,
    required bool allowUnknown,
    required bool allowRefused,
    required bool allowNotApplicable,
    this.minimumSelections = const Value.absent(),
    this.maximumSelections = const Value.absent(),
    this.numberKind = const Value.absent(),
    this.unit = const Value.absent(),
    this.minimum = const Value.absent(),
    this.maximum = const Value.absent(),
    this.maximumLength = const Value.absent(),
    this.displayRuleJson = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : questionnaireVersionId = Value(questionnaireVersionId),
       questionId = Value(questionId),
       position = Value(position),
       prompt = Value(prompt),
       questionType = Value(questionType),
       isRequired = Value(isRequired),
       allowUnknown = Value(allowUnknown),
       allowRefused = Value(allowRefused),
       allowNotApplicable = Value(allowNotApplicable);
  static Insertable<DbQuestionnaireQuestion> custom({
    Expression<String>? questionnaireVersionId,
    Expression<String>? questionId,
    Expression<int>? position,
    Expression<String>? prompt,
    Expression<String>? questionType,
    Expression<bool>? isRequired,
    Expression<bool>? allowUnknown,
    Expression<bool>? allowRefused,
    Expression<bool>? allowNotApplicable,
    Expression<int>? minimumSelections,
    Expression<int>? maximumSelections,
    Expression<String>? numberKind,
    Expression<String>? unit,
    Expression<double>? minimum,
    Expression<double>? maximum,
    Expression<int>? maximumLength,
    Expression<String>? displayRuleJson,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (questionnaireVersionId != null)
        'questionnaire_version_id': questionnaireVersionId,
      if (questionId != null) 'question_id': questionId,
      if (position != null) 'position': position,
      if (prompt != null) 'prompt': prompt,
      if (questionType != null) 'question_type': questionType,
      if (isRequired != null) 'is_required': isRequired,
      if (allowUnknown != null) 'allow_unknown': allowUnknown,
      if (allowRefused != null) 'allow_refused': allowRefused,
      if (allowNotApplicable != null)
        'allow_not_applicable': allowNotApplicable,
      if (minimumSelections != null) 'minimum_selections': minimumSelections,
      if (maximumSelections != null) 'maximum_selections': maximumSelections,
      if (numberKind != null) 'number_kind': numberKind,
      if (unit != null) 'unit': unit,
      if (minimum != null) 'minimum': minimum,
      if (maximum != null) 'maximum': maximum,
      if (maximumLength != null) 'maximum_length': maximumLength,
      if (displayRuleJson != null) 'display_rule_json': displayRuleJson,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DbQuestionnaireQuestionsCompanion copyWith({
    Value<String>? questionnaireVersionId,
    Value<String>? questionId,
    Value<int>? position,
    Value<String>? prompt,
    Value<String>? questionType,
    Value<bool>? isRequired,
    Value<bool>? allowUnknown,
    Value<bool>? allowRefused,
    Value<bool>? allowNotApplicable,
    Value<int?>? minimumSelections,
    Value<int?>? maximumSelections,
    Value<String?>? numberKind,
    Value<String?>? unit,
    Value<double?>? minimum,
    Value<double?>? maximum,
    Value<int?>? maximumLength,
    Value<String?>? displayRuleJson,
    Value<int>? rowid,
  }) {
    return DbQuestionnaireQuestionsCompanion(
      questionnaireVersionId:
          questionnaireVersionId ?? this.questionnaireVersionId,
      questionId: questionId ?? this.questionId,
      position: position ?? this.position,
      prompt: prompt ?? this.prompt,
      questionType: questionType ?? this.questionType,
      isRequired: isRequired ?? this.isRequired,
      allowUnknown: allowUnknown ?? this.allowUnknown,
      allowRefused: allowRefused ?? this.allowRefused,
      allowNotApplicable: allowNotApplicable ?? this.allowNotApplicable,
      minimumSelections: minimumSelections ?? this.minimumSelections,
      maximumSelections: maximumSelections ?? this.maximumSelections,
      numberKind: numberKind ?? this.numberKind,
      unit: unit ?? this.unit,
      minimum: minimum ?? this.minimum,
      maximum: maximum ?? this.maximum,
      maximumLength: maximumLength ?? this.maximumLength,
      displayRuleJson: displayRuleJson ?? this.displayRuleJson,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (questionnaireVersionId.present) {
      map['questionnaire_version_id'] = Variable<String>(
        questionnaireVersionId.value,
      );
    }
    if (questionId.present) {
      map['question_id'] = Variable<String>(questionId.value);
    }
    if (position.present) {
      map['position'] = Variable<int>(position.value);
    }
    if (prompt.present) {
      map['prompt'] = Variable<String>(prompt.value);
    }
    if (questionType.present) {
      map['question_type'] = Variable<String>(questionType.value);
    }
    if (isRequired.present) {
      map['is_required'] = Variable<bool>(isRequired.value);
    }
    if (allowUnknown.present) {
      map['allow_unknown'] = Variable<bool>(allowUnknown.value);
    }
    if (allowRefused.present) {
      map['allow_refused'] = Variable<bool>(allowRefused.value);
    }
    if (allowNotApplicable.present) {
      map['allow_not_applicable'] = Variable<bool>(allowNotApplicable.value);
    }
    if (minimumSelections.present) {
      map['minimum_selections'] = Variable<int>(minimumSelections.value);
    }
    if (maximumSelections.present) {
      map['maximum_selections'] = Variable<int>(maximumSelections.value);
    }
    if (numberKind.present) {
      map['number_kind'] = Variable<String>(numberKind.value);
    }
    if (unit.present) {
      map['unit'] = Variable<String>(unit.value);
    }
    if (minimum.present) {
      map['minimum'] = Variable<double>(minimum.value);
    }
    if (maximum.present) {
      map['maximum'] = Variable<double>(maximum.value);
    }
    if (maximumLength.present) {
      map['maximum_length'] = Variable<int>(maximumLength.value);
    }
    if (displayRuleJson.present) {
      map['display_rule_json'] = Variable<String>(displayRuleJson.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DbQuestionnaireQuestionsCompanion(')
          ..write('questionnaireVersionId: $questionnaireVersionId, ')
          ..write('questionId: $questionId, ')
          ..write('position: $position, ')
          ..write('prompt: $prompt, ')
          ..write('questionType: $questionType, ')
          ..write('isRequired: $isRequired, ')
          ..write('allowUnknown: $allowUnknown, ')
          ..write('allowRefused: $allowRefused, ')
          ..write('allowNotApplicable: $allowNotApplicable, ')
          ..write('minimumSelections: $minimumSelections, ')
          ..write('maximumSelections: $maximumSelections, ')
          ..write('numberKind: $numberKind, ')
          ..write('unit: $unit, ')
          ..write('minimum: $minimum, ')
          ..write('maximum: $maximum, ')
          ..write('maximumLength: $maximumLength, ')
          ..write('displayRuleJson: $displayRuleJson, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $DbQuestionnaireOptionsTable extends DbQuestionnaireOptions
    with TableInfo<$DbQuestionnaireOptionsTable, DbQuestionnaireOption> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DbQuestionnaireOptionsTable(this.attachedDatabase, [this._alias]);
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
        defaultConstraints: GeneratedColumn.constraintIsAlways(
          'REFERENCES db_questionnaire_versions (questionnaire_version_id)',
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
  static const VerificationMeta _optionIdMeta = const VerificationMeta(
    'optionId',
  );
  @override
  late final GeneratedColumn<String> optionId = GeneratedColumn<String>(
    'option_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _positionMeta = const VerificationMeta(
    'position',
  );
  @override
  late final GeneratedColumn<int> position = GeneratedColumn<int>(
    'position',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _labelMeta = const VerificationMeta('label');
  @override
  late final GeneratedColumn<String> label = GeneratedColumn<String>(
    'label',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    questionnaireVersionId,
    questionId,
    optionId,
    position,
    label,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'db_questionnaire_options';
  @override
  VerificationContext validateIntegrity(
    Insertable<DbQuestionnaireOption> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
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
    if (data.containsKey('question_id')) {
      context.handle(
        _questionIdMeta,
        questionId.isAcceptableOrUnknown(data['question_id']!, _questionIdMeta),
      );
    } else if (isInserting) {
      context.missing(_questionIdMeta);
    }
    if (data.containsKey('option_id')) {
      context.handle(
        _optionIdMeta,
        optionId.isAcceptableOrUnknown(data['option_id']!, _optionIdMeta),
      );
    } else if (isInserting) {
      context.missing(_optionIdMeta);
    }
    if (data.containsKey('position')) {
      context.handle(
        _positionMeta,
        position.isAcceptableOrUnknown(data['position']!, _positionMeta),
      );
    } else if (isInserting) {
      context.missing(_positionMeta);
    }
    if (data.containsKey('label')) {
      context.handle(
        _labelMeta,
        label.isAcceptableOrUnknown(data['label']!, _labelMeta),
      );
    } else if (isInserting) {
      context.missing(_labelMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {
    questionnaireVersionId,
    questionId,
    optionId,
  };
  @override
  DbQuestionnaireOption map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DbQuestionnaireOption(
      questionnaireVersionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}questionnaire_version_id'],
      )!,
      questionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}question_id'],
      )!,
      optionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}option_id'],
      )!,
      position: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}position'],
      )!,
      label: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}label'],
      )!,
    );
  }

  @override
  $DbQuestionnaireOptionsTable createAlias(String alias) {
    return $DbQuestionnaireOptionsTable(attachedDatabase, alias);
  }
}

class DbQuestionnaireOption extends DataClass
    implements Insertable<DbQuestionnaireOption> {
  final String questionnaireVersionId;
  final String questionId;
  final String optionId;
  final int position;
  final String label;
  const DbQuestionnaireOption({
    required this.questionnaireVersionId,
    required this.questionId,
    required this.optionId,
    required this.position,
    required this.label,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['questionnaire_version_id'] = Variable<String>(questionnaireVersionId);
    map['question_id'] = Variable<String>(questionId);
    map['option_id'] = Variable<String>(optionId);
    map['position'] = Variable<int>(position);
    map['label'] = Variable<String>(label);
    return map;
  }

  DbQuestionnaireOptionsCompanion toCompanion(bool nullToAbsent) {
    return DbQuestionnaireOptionsCompanion(
      questionnaireVersionId: Value(questionnaireVersionId),
      questionId: Value(questionId),
      optionId: Value(optionId),
      position: Value(position),
      label: Value(label),
    );
  }

  factory DbQuestionnaireOption.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DbQuestionnaireOption(
      questionnaireVersionId: serializer.fromJson<String>(
        json['questionnaireVersionId'],
      ),
      questionId: serializer.fromJson<String>(json['questionId']),
      optionId: serializer.fromJson<String>(json['optionId']),
      position: serializer.fromJson<int>(json['position']),
      label: serializer.fromJson<String>(json['label']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'questionnaireVersionId': serializer.toJson<String>(
        questionnaireVersionId,
      ),
      'questionId': serializer.toJson<String>(questionId),
      'optionId': serializer.toJson<String>(optionId),
      'position': serializer.toJson<int>(position),
      'label': serializer.toJson<String>(label),
    };
  }

  DbQuestionnaireOption copyWith({
    String? questionnaireVersionId,
    String? questionId,
    String? optionId,
    int? position,
    String? label,
  }) => DbQuestionnaireOption(
    questionnaireVersionId:
        questionnaireVersionId ?? this.questionnaireVersionId,
    questionId: questionId ?? this.questionId,
    optionId: optionId ?? this.optionId,
    position: position ?? this.position,
    label: label ?? this.label,
  );
  DbQuestionnaireOption copyWithCompanion(
    DbQuestionnaireOptionsCompanion data,
  ) {
    return DbQuestionnaireOption(
      questionnaireVersionId: data.questionnaireVersionId.present
          ? data.questionnaireVersionId.value
          : this.questionnaireVersionId,
      questionId: data.questionId.present
          ? data.questionId.value
          : this.questionId,
      optionId: data.optionId.present ? data.optionId.value : this.optionId,
      position: data.position.present ? data.position.value : this.position,
      label: data.label.present ? data.label.value : this.label,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DbQuestionnaireOption(')
          ..write('questionnaireVersionId: $questionnaireVersionId, ')
          ..write('questionId: $questionId, ')
          ..write('optionId: $optionId, ')
          ..write('position: $position, ')
          ..write('label: $label')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    questionnaireVersionId,
    questionId,
    optionId,
    position,
    label,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DbQuestionnaireOption &&
          other.questionnaireVersionId == this.questionnaireVersionId &&
          other.questionId == this.questionId &&
          other.optionId == this.optionId &&
          other.position == this.position &&
          other.label == this.label);
}

class DbQuestionnaireOptionsCompanion
    extends UpdateCompanion<DbQuestionnaireOption> {
  final Value<String> questionnaireVersionId;
  final Value<String> questionId;
  final Value<String> optionId;
  final Value<int> position;
  final Value<String> label;
  final Value<int> rowid;
  const DbQuestionnaireOptionsCompanion({
    this.questionnaireVersionId = const Value.absent(),
    this.questionId = const Value.absent(),
    this.optionId = const Value.absent(),
    this.position = const Value.absent(),
    this.label = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DbQuestionnaireOptionsCompanion.insert({
    required String questionnaireVersionId,
    required String questionId,
    required String optionId,
    required int position,
    required String label,
    this.rowid = const Value.absent(),
  }) : questionnaireVersionId = Value(questionnaireVersionId),
       questionId = Value(questionId),
       optionId = Value(optionId),
       position = Value(position),
       label = Value(label);
  static Insertable<DbQuestionnaireOption> custom({
    Expression<String>? questionnaireVersionId,
    Expression<String>? questionId,
    Expression<String>? optionId,
    Expression<int>? position,
    Expression<String>? label,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (questionnaireVersionId != null)
        'questionnaire_version_id': questionnaireVersionId,
      if (questionId != null) 'question_id': questionId,
      if (optionId != null) 'option_id': optionId,
      if (position != null) 'position': position,
      if (label != null) 'label': label,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DbQuestionnaireOptionsCompanion copyWith({
    Value<String>? questionnaireVersionId,
    Value<String>? questionId,
    Value<String>? optionId,
    Value<int>? position,
    Value<String>? label,
    Value<int>? rowid,
  }) {
    return DbQuestionnaireOptionsCompanion(
      questionnaireVersionId:
          questionnaireVersionId ?? this.questionnaireVersionId,
      questionId: questionId ?? this.questionId,
      optionId: optionId ?? this.optionId,
      position: position ?? this.position,
      label: label ?? this.label,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (questionnaireVersionId.present) {
      map['questionnaire_version_id'] = Variable<String>(
        questionnaireVersionId.value,
      );
    }
    if (questionId.present) {
      map['question_id'] = Variable<String>(questionId.value);
    }
    if (optionId.present) {
      map['option_id'] = Variable<String>(optionId.value);
    }
    if (position.present) {
      map['position'] = Variable<int>(position.value);
    }
    if (label.present) {
      map['label'] = Variable<String>(label.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DbQuestionnaireOptionsCompanion(')
          ..write('questionnaireVersionId: $questionnaireVersionId, ')
          ..write('questionId: $questionId, ')
          ..write('optionId: $optionId, ')
          ..write('position: $position, ')
          ..write('label: $label, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $DbQuestionnaireDraftWorkingCopiesTable
    extends DbQuestionnaireDraftWorkingCopies
    with
        TableInfo<
          $DbQuestionnaireDraftWorkingCopiesTable,
          DbQuestionnaireDraftWorkingCopy
        > {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DbQuestionnaireDraftWorkingCopiesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _questionnaireDraftIdMeta =
      const VerificationMeta('questionnaireDraftId');
  @override
  late final GeneratedColumn<String> questionnaireDraftId =
      GeneratedColumn<String>(
        'questionnaire_draft_id',
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
  static const VerificationMeta _sourceVersionIdMeta = const VerificationMeta(
    'sourceVersionId',
  );
  @override
  late final GeneratedColumn<String> sourceVersionId = GeneratedColumn<String>(
    'source_version_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
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
  static const VerificationMeta _definitionJsonMeta = const VerificationMeta(
    'definitionJson',
  );
  @override
  late final GeneratedColumn<String> definitionJson = GeneratedColumn<String>(
    'definition_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _hasLocalChangesMeta = const VerificationMeta(
    'hasLocalChanges',
  );
  @override
  late final GeneratedColumn<bool> hasLocalChanges = GeneratedColumn<bool>(
    'has_local_changes',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("has_local_changes" IN (0, 1))',
    ),
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
    questionnaireDraftId,
    projectId,
    sourceVersionId,
    baseRevision,
    definitionJson,
    hasLocalChanges,
    updatedAtUtc,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'db_questionnaire_draft_working_copies';
  @override
  VerificationContext validateIntegrity(
    Insertable<DbQuestionnaireDraftWorkingCopy> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('questionnaire_draft_id')) {
      context.handle(
        _questionnaireDraftIdMeta,
        questionnaireDraftId.isAcceptableOrUnknown(
          data['questionnaire_draft_id']!,
          _questionnaireDraftIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_questionnaireDraftIdMeta);
    }
    if (data.containsKey('project_id')) {
      context.handle(
        _projectIdMeta,
        projectId.isAcceptableOrUnknown(data['project_id']!, _projectIdMeta),
      );
    } else if (isInserting) {
      context.missing(_projectIdMeta);
    }
    if (data.containsKey('source_version_id')) {
      context.handle(
        _sourceVersionIdMeta,
        sourceVersionId.isAcceptableOrUnknown(
          data['source_version_id']!,
          _sourceVersionIdMeta,
        ),
      );
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
    if (data.containsKey('definition_json')) {
      context.handle(
        _definitionJsonMeta,
        definitionJson.isAcceptableOrUnknown(
          data['definition_json']!,
          _definitionJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_definitionJsonMeta);
    }
    if (data.containsKey('has_local_changes')) {
      context.handle(
        _hasLocalChangesMeta,
        hasLocalChanges.isAcceptableOrUnknown(
          data['has_local_changes']!,
          _hasLocalChangesMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_hasLocalChangesMeta);
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
  Set<GeneratedColumn> get $primaryKey => {questionnaireDraftId};
  @override
  DbQuestionnaireDraftWorkingCopy map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DbQuestionnaireDraftWorkingCopy(
      questionnaireDraftId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}questionnaire_draft_id'],
      )!,
      projectId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}project_id'],
      )!,
      sourceVersionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_version_id'],
      ),
      baseRevision: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}base_revision'],
      )!,
      definitionJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}definition_json'],
      )!,
      hasLocalChanges: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}has_local_changes'],
      )!,
      updatedAtUtc: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at_utc'],
      )!,
    );
  }

  @override
  $DbQuestionnaireDraftWorkingCopiesTable createAlias(String alias) {
    return $DbQuestionnaireDraftWorkingCopiesTable(attachedDatabase, alias);
  }
}

class DbQuestionnaireDraftWorkingCopy extends DataClass
    implements Insertable<DbQuestionnaireDraftWorkingCopy> {
  final String questionnaireDraftId;
  final String projectId;
  final String? sourceVersionId;
  final int baseRevision;
  final String definitionJson;
  final bool hasLocalChanges;
  final DateTime updatedAtUtc;
  const DbQuestionnaireDraftWorkingCopy({
    required this.questionnaireDraftId,
    required this.projectId,
    this.sourceVersionId,
    required this.baseRevision,
    required this.definitionJson,
    required this.hasLocalChanges,
    required this.updatedAtUtc,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['questionnaire_draft_id'] = Variable<String>(questionnaireDraftId);
    map['project_id'] = Variable<String>(projectId);
    if (!nullToAbsent || sourceVersionId != null) {
      map['source_version_id'] = Variable<String>(sourceVersionId);
    }
    map['base_revision'] = Variable<int>(baseRevision);
    map['definition_json'] = Variable<String>(definitionJson);
    map['has_local_changes'] = Variable<bool>(hasLocalChanges);
    map['updated_at_utc'] = Variable<DateTime>(updatedAtUtc);
    return map;
  }

  DbQuestionnaireDraftWorkingCopiesCompanion toCompanion(bool nullToAbsent) {
    return DbQuestionnaireDraftWorkingCopiesCompanion(
      questionnaireDraftId: Value(questionnaireDraftId),
      projectId: Value(projectId),
      sourceVersionId: sourceVersionId == null && nullToAbsent
          ? const Value.absent()
          : Value(sourceVersionId),
      baseRevision: Value(baseRevision),
      definitionJson: Value(definitionJson),
      hasLocalChanges: Value(hasLocalChanges),
      updatedAtUtc: Value(updatedAtUtc),
    );
  }

  factory DbQuestionnaireDraftWorkingCopy.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DbQuestionnaireDraftWorkingCopy(
      questionnaireDraftId: serializer.fromJson<String>(
        json['questionnaireDraftId'],
      ),
      projectId: serializer.fromJson<String>(json['projectId']),
      sourceVersionId: serializer.fromJson<String?>(json['sourceVersionId']),
      baseRevision: serializer.fromJson<int>(json['baseRevision']),
      definitionJson: serializer.fromJson<String>(json['definitionJson']),
      hasLocalChanges: serializer.fromJson<bool>(json['hasLocalChanges']),
      updatedAtUtc: serializer.fromJson<DateTime>(json['updatedAtUtc']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'questionnaireDraftId': serializer.toJson<String>(questionnaireDraftId),
      'projectId': serializer.toJson<String>(projectId),
      'sourceVersionId': serializer.toJson<String?>(sourceVersionId),
      'baseRevision': serializer.toJson<int>(baseRevision),
      'definitionJson': serializer.toJson<String>(definitionJson),
      'hasLocalChanges': serializer.toJson<bool>(hasLocalChanges),
      'updatedAtUtc': serializer.toJson<DateTime>(updatedAtUtc),
    };
  }

  DbQuestionnaireDraftWorkingCopy copyWith({
    String? questionnaireDraftId,
    String? projectId,
    Value<String?> sourceVersionId = const Value.absent(),
    int? baseRevision,
    String? definitionJson,
    bool? hasLocalChanges,
    DateTime? updatedAtUtc,
  }) => DbQuestionnaireDraftWorkingCopy(
    questionnaireDraftId: questionnaireDraftId ?? this.questionnaireDraftId,
    projectId: projectId ?? this.projectId,
    sourceVersionId: sourceVersionId.present
        ? sourceVersionId.value
        : this.sourceVersionId,
    baseRevision: baseRevision ?? this.baseRevision,
    definitionJson: definitionJson ?? this.definitionJson,
    hasLocalChanges: hasLocalChanges ?? this.hasLocalChanges,
    updatedAtUtc: updatedAtUtc ?? this.updatedAtUtc,
  );
  DbQuestionnaireDraftWorkingCopy copyWithCompanion(
    DbQuestionnaireDraftWorkingCopiesCompanion data,
  ) {
    return DbQuestionnaireDraftWorkingCopy(
      questionnaireDraftId: data.questionnaireDraftId.present
          ? data.questionnaireDraftId.value
          : this.questionnaireDraftId,
      projectId: data.projectId.present ? data.projectId.value : this.projectId,
      sourceVersionId: data.sourceVersionId.present
          ? data.sourceVersionId.value
          : this.sourceVersionId,
      baseRevision: data.baseRevision.present
          ? data.baseRevision.value
          : this.baseRevision,
      definitionJson: data.definitionJson.present
          ? data.definitionJson.value
          : this.definitionJson,
      hasLocalChanges: data.hasLocalChanges.present
          ? data.hasLocalChanges.value
          : this.hasLocalChanges,
      updatedAtUtc: data.updatedAtUtc.present
          ? data.updatedAtUtc.value
          : this.updatedAtUtc,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DbQuestionnaireDraftWorkingCopy(')
          ..write('questionnaireDraftId: $questionnaireDraftId, ')
          ..write('projectId: $projectId, ')
          ..write('sourceVersionId: $sourceVersionId, ')
          ..write('baseRevision: $baseRevision, ')
          ..write('definitionJson: $definitionJson, ')
          ..write('hasLocalChanges: $hasLocalChanges, ')
          ..write('updatedAtUtc: $updatedAtUtc')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    questionnaireDraftId,
    projectId,
    sourceVersionId,
    baseRevision,
    definitionJson,
    hasLocalChanges,
    updatedAtUtc,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DbQuestionnaireDraftWorkingCopy &&
          other.questionnaireDraftId == this.questionnaireDraftId &&
          other.projectId == this.projectId &&
          other.sourceVersionId == this.sourceVersionId &&
          other.baseRevision == this.baseRevision &&
          other.definitionJson == this.definitionJson &&
          other.hasLocalChanges == this.hasLocalChanges &&
          other.updatedAtUtc == this.updatedAtUtc);
}

class DbQuestionnaireDraftWorkingCopiesCompanion
    extends UpdateCompanion<DbQuestionnaireDraftWorkingCopy> {
  final Value<String> questionnaireDraftId;
  final Value<String> projectId;
  final Value<String?> sourceVersionId;
  final Value<int> baseRevision;
  final Value<String> definitionJson;
  final Value<bool> hasLocalChanges;
  final Value<DateTime> updatedAtUtc;
  final Value<int> rowid;
  const DbQuestionnaireDraftWorkingCopiesCompanion({
    this.questionnaireDraftId = const Value.absent(),
    this.projectId = const Value.absent(),
    this.sourceVersionId = const Value.absent(),
    this.baseRevision = const Value.absent(),
    this.definitionJson = const Value.absent(),
    this.hasLocalChanges = const Value.absent(),
    this.updatedAtUtc = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DbQuestionnaireDraftWorkingCopiesCompanion.insert({
    required String questionnaireDraftId,
    required String projectId,
    this.sourceVersionId = const Value.absent(),
    required int baseRevision,
    required String definitionJson,
    required bool hasLocalChanges,
    required DateTime updatedAtUtc,
    this.rowid = const Value.absent(),
  }) : questionnaireDraftId = Value(questionnaireDraftId),
       projectId = Value(projectId),
       baseRevision = Value(baseRevision),
       definitionJson = Value(definitionJson),
       hasLocalChanges = Value(hasLocalChanges),
       updatedAtUtc = Value(updatedAtUtc);
  static Insertable<DbQuestionnaireDraftWorkingCopy> custom({
    Expression<String>? questionnaireDraftId,
    Expression<String>? projectId,
    Expression<String>? sourceVersionId,
    Expression<int>? baseRevision,
    Expression<String>? definitionJson,
    Expression<bool>? hasLocalChanges,
    Expression<DateTime>? updatedAtUtc,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (questionnaireDraftId != null)
        'questionnaire_draft_id': questionnaireDraftId,
      if (projectId != null) 'project_id': projectId,
      if (sourceVersionId != null) 'source_version_id': sourceVersionId,
      if (baseRevision != null) 'base_revision': baseRevision,
      if (definitionJson != null) 'definition_json': definitionJson,
      if (hasLocalChanges != null) 'has_local_changes': hasLocalChanges,
      if (updatedAtUtc != null) 'updated_at_utc': updatedAtUtc,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DbQuestionnaireDraftWorkingCopiesCompanion copyWith({
    Value<String>? questionnaireDraftId,
    Value<String>? projectId,
    Value<String?>? sourceVersionId,
    Value<int>? baseRevision,
    Value<String>? definitionJson,
    Value<bool>? hasLocalChanges,
    Value<DateTime>? updatedAtUtc,
    Value<int>? rowid,
  }) {
    return DbQuestionnaireDraftWorkingCopiesCompanion(
      questionnaireDraftId: questionnaireDraftId ?? this.questionnaireDraftId,
      projectId: projectId ?? this.projectId,
      sourceVersionId: sourceVersionId ?? this.sourceVersionId,
      baseRevision: baseRevision ?? this.baseRevision,
      definitionJson: definitionJson ?? this.definitionJson,
      hasLocalChanges: hasLocalChanges ?? this.hasLocalChanges,
      updatedAtUtc: updatedAtUtc ?? this.updatedAtUtc,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (questionnaireDraftId.present) {
      map['questionnaire_draft_id'] = Variable<String>(
        questionnaireDraftId.value,
      );
    }
    if (projectId.present) {
      map['project_id'] = Variable<String>(projectId.value);
    }
    if (sourceVersionId.present) {
      map['source_version_id'] = Variable<String>(sourceVersionId.value);
    }
    if (baseRevision.present) {
      map['base_revision'] = Variable<int>(baseRevision.value);
    }
    if (definitionJson.present) {
      map['definition_json'] = Variable<String>(definitionJson.value);
    }
    if (hasLocalChanges.present) {
      map['has_local_changes'] = Variable<bool>(hasLocalChanges.value);
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
    return (StringBuffer('DbQuestionnaireDraftWorkingCopiesCompanion(')
          ..write('questionnaireDraftId: $questionnaireDraftId, ')
          ..write('projectId: $projectId, ')
          ..write('sourceVersionId: $sourceVersionId, ')
          ..write('baseRevision: $baseRevision, ')
          ..write('definitionJson: $definitionJson, ')
          ..write('hasLocalChanges: $hasLocalChanges, ')
          ..write('updatedAtUtc: $updatedAtUtc, ')
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
  late final $DbContactAttemptsTable dbContactAttempts =
      $DbContactAttemptsTable(this);
  late final $DbContactRevisionsTable dbContactRevisions =
      $DbContactRevisionsTable(this);
  late final $DbContactAnswersTable dbContactAnswers = $DbContactAnswersTable(
    this,
  );
  late final $DbContactRevisionConflictsTable dbContactRevisionConflicts =
      $DbContactRevisionConflictsTable(this);
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
  late final Index contactAttemptsPersonalPeriod = Index(
    'contact_attempts_personal_period',
    'CREATE INDEX contact_attempts_personal_period ON db_contact_attempts (app_user_id, workspace_id, project_id, occurred_at_utc)',
  );
  late final Index syncOutboxReady = Index(
    'sync_outbox_ready',
    'CREATE INDEX sync_outbox_ready ON db_sync_outbox (status, next_attempt_at_utc, created_at_utc)',
  );
  late final Index syncOutboxAggregateOrder = Index(
    'sync_outbox_aggregate_order',
    'CREATE INDEX sync_outbox_aggregate_order ON db_sync_outbox (aggregate_id, created_at_utc)',
  );
  late final Index contactRevisionConflictsOwnerContact = Index(
    'contact_revision_conflicts_owner_contact',
    'CREATE INDEX contact_revision_conflicts_owner_contact ON db_contact_revision_conflicts (app_user_id, contact_id, status)',
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
  late final $DbCanonicalRegionVersionsTable dbCanonicalRegionVersions =
      $DbCanonicalRegionVersionsTable(this);
  late final $DbContactRegionAssignmentsTable dbContactRegionAssignments =
      $DbContactRegionAssignmentsTable(this);
  late final $DbDraftRegionAssignmentsTable dbDraftRegionAssignments =
      $DbDraftRegionAssignmentsTable(this);
  late final $DbQuestionnaireVersionsTable dbQuestionnaireVersions =
      $DbQuestionnaireVersionsTable(this);
  late final $DbQuestionnaireQuestionsTable dbQuestionnaireQuestions =
      $DbQuestionnaireQuestionsTable(this);
  late final $DbQuestionnaireOptionsTable dbQuestionnaireOptions =
      $DbQuestionnaireOptionsTable(this);
  late final $DbQuestionnaireDraftWorkingCopiesTable
  dbQuestionnaireDraftWorkingCopies = $DbQuestionnaireDraftWorkingCopiesTable(
    this,
  );
  Selectable<DbSyncOutboxData> readReadySyncCommand(
    String appUserId,
    String workspaceId,
    String projectId,
    DateTime nowUtc,
  ) {
    return customSelect(
      'SELECT outbox.* FROM db_sync_outbox AS outbox LEFT JOIN db_contact_records AS contact ON contact.contact_id = outbox.aggregate_id WHERE COALESCE(outbox.app_user_id, contact.app_user_id) = ?1 AND COALESCE(outbox.workspace_id, contact.workspace_id) = ?2 AND COALESCE(outbox.project_id, contact.project_id) = ?3 AND outbox.status = \'pending\' AND outbox.next_attempt_at_utc <= ?4 AND NOT EXISTS (SELECT 1 AS _c0 FROM db_sync_outbox AS earlier WHERE earlier.aggregate_id = outbox.aggregate_id AND earlier.status != \'completed\' AND(earlier.created_at_utc < outbox.created_at_utc OR(earlier.created_at_utc = outbox.created_at_utc AND earlier.command_id < outbox.command_id))) ORDER BY outbox.created_at_utc, outbox.command_id LIMIT 1',
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
    dbContactAttempts,
    dbContactRevisions,
    dbContactAnswers,
    dbContactRevisionConflicts,
    dbContactDrafts,
    dbContactDraftAnswers,
    contactDraftsOwnerUpdated,
    contactRecordsPersonalPeriod,
    contactAttemptsPersonalPeriod,
    syncOutboxReady,
    syncOutboxAggregateOrder,
    contactRevisionConflictsOwnerContact,
    dbUsers,
    dbConversationRecords,
    dbRecordContacts,
    dbAppSettings,
    dbSecurityEvents,
    dbCanonicalRegionVersions,
    dbContactRegionAssignments,
    dbDraftRegionAssignments,
    dbQuestionnaireVersions,
    dbQuestionnaireQuestions,
    dbQuestionnaireOptions,
    dbQuestionnaireDraftWorkingCopies,
  ];
}

typedef $$DbSyncOutboxTableCreateCompanionBuilder =
    DbSyncOutboxCompanion Function({
      required String commandId,
      required int protocolVersion,
      required String commandType,
      required String deviceId,
      required String aggregateId,
      Value<String?> appUserId,
      Value<String?> workspaceId,
      Value<String?> projectId,
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
      Value<String?> appUserId,
      Value<String?> workspaceId,
      Value<String?> projectId,
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

  GeneratedColumn<String> get appUserId =>
      $composableBuilder(column: $table.appUserId, builder: (column) => column);

  GeneratedColumn<String> get workspaceId => $composableBuilder(
    column: $table.workspaceId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get projectId =>
      $composableBuilder(column: $table.projectId, builder: (column) => column);

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
                Value<String?> appUserId = const Value.absent(),
                Value<String?> workspaceId = const Value.absent(),
                Value<String?> projectId = const Value.absent(),
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
                appUserId: appUserId,
                workspaceId: workspaceId,
                projectId: projectId,
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
                Value<String?> appUserId = const Value.absent(),
                Value<String?> workspaceId = const Value.absent(),
                Value<String?> projectId = const Value.absent(),
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
                appUserId: appUserId,
                workspaceId: workspaceId,
                projectId: projectId,
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
      Value<String?> regionTreeVersion,
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
      Value<String?> regionTreeVersion,
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

  static MultiTypedResultKey<$DbContactAttemptsTable, List<DbContactAttempt>>
  _dbContactAttemptsRefsTable(
    _$LocalDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.dbContactAttempts,
    aliasName:
        'db_contact_records__contact_id__db_contact_attempts__linked_contact_id',
  );

  $$DbContactAttemptsTableProcessedTableManager get dbContactAttemptsRefs {
    final manager =
        $$DbContactAttemptsTableTableManager(
          $_db,
          $_db.dbContactAttempts,
        ).filter(
          (f) => f.linkedContactId.contactId.sqlEquals(
            $_itemColumn<String>('contact_id')!,
          ),
        );

    final cache = $_typedResult.readTableOrNull(
      _dbContactAttemptsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

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

  static MultiTypedResultKey<
    $DbContactRevisionConflictsTable,
    List<DbContactRevisionConflict>
  >
  _dbContactRevisionConflictsRefsTable(
    _$LocalDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.dbContactRevisionConflicts,
    aliasName:
        'db_contact_records__contact_id__db_contact_revision_conflicts__contact_id',
  );

  $$DbContactRevisionConflictsTableProcessedTableManager
  get dbContactRevisionConflictsRefs {
    final manager =
        $$DbContactRevisionConflictsTableTableManager(
          $_db,
          $_db.dbContactRevisionConflicts,
        ).filter(
          (f) => f.contactId.contactId.sqlEquals(
            $_itemColumn<String>('contact_id')!,
          ),
        );

    final cache = $_typedResult.readTableOrNull(
      _dbContactRevisionConflictsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<
    $DbContactRegionAssignmentsTable,
    List<DbContactRegionAssignment>
  >
  _dbContactRegionAssignmentsRefsTable(
    _$LocalDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.dbContactRegionAssignments,
    aliasName:
        'db_contact_records__contact_id__db_contact_region_assignments__contact_id',
  );

  $$DbContactRegionAssignmentsTableProcessedTableManager
  get dbContactRegionAssignmentsRefs {
    final manager =
        $$DbContactRegionAssignmentsTableTableManager(
          $_db,
          $_db.dbContactRegionAssignments,
        ).filter(
          (f) => f.contactId.contactId.sqlEquals(
            $_itemColumn<String>('contact_id')!,
          ),
        );

    final cache = $_typedResult.readTableOrNull(
      _dbContactRegionAssignmentsRefsTable($_db),
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

  ColumnFilters<String> get regionTreeVersion => $composableBuilder(
    column: $table.regionTreeVersion,
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

  Expression<bool> dbContactAttemptsRefs(
    Expression<bool> Function($$DbContactAttemptsTableFilterComposer f) f,
  ) {
    final $$DbContactAttemptsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.contactId,
      referencedTable: $db.dbContactAttempts,
      getReferencedColumn: (t) => t.linkedContactId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DbContactAttemptsTableFilterComposer(
            $db: $db,
            $table: $db.dbContactAttempts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

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

  Expression<bool> dbContactRevisionConflictsRefs(
    Expression<bool> Function($$DbContactRevisionConflictsTableFilterComposer f)
    f,
  ) {
    final $$DbContactRevisionConflictsTableFilterComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.contactId,
          referencedTable: $db.dbContactRevisionConflicts,
          getReferencedColumn: (t) => t.contactId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$DbContactRevisionConflictsTableFilterComposer(
                $db: $db,
                $table: $db.dbContactRevisionConflicts,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }

  Expression<bool> dbContactRegionAssignmentsRefs(
    Expression<bool> Function($$DbContactRegionAssignmentsTableFilterComposer f)
    f,
  ) {
    final $$DbContactRegionAssignmentsTableFilterComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.contactId,
          referencedTable: $db.dbContactRegionAssignments,
          getReferencedColumn: (t) => t.contactId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$DbContactRegionAssignmentsTableFilterComposer(
                $db: $db,
                $table: $db.dbContactRegionAssignments,
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

  ColumnOrderings<String> get regionTreeVersion => $composableBuilder(
    column: $table.regionTreeVersion,
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

  GeneratedColumn<String> get regionTreeVersion => $composableBuilder(
    column: $table.regionTreeVersion,
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

  Expression<T> dbContactAttemptsRefs<T extends Object>(
    Expression<T> Function($$DbContactAttemptsTableAnnotationComposer a) f,
  ) {
    final $$DbContactAttemptsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.contactId,
          referencedTable: $db.dbContactAttempts,
          getReferencedColumn: (t) => t.linkedContactId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$DbContactAttemptsTableAnnotationComposer(
                $db: $db,
                $table: $db.dbContactAttempts,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }

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

  Expression<T> dbContactRevisionConflictsRefs<T extends Object>(
    Expression<T> Function(
      $$DbContactRevisionConflictsTableAnnotationComposer a,
    )
    f,
  ) {
    final $$DbContactRevisionConflictsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.contactId,
          referencedTable: $db.dbContactRevisionConflicts,
          getReferencedColumn: (t) => t.contactId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$DbContactRevisionConflictsTableAnnotationComposer(
                $db: $db,
                $table: $db.dbContactRevisionConflicts,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }

  Expression<T> dbContactRegionAssignmentsRefs<T extends Object>(
    Expression<T> Function(
      $$DbContactRegionAssignmentsTableAnnotationComposer a,
    )
    f,
  ) {
    final $$DbContactRegionAssignmentsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.contactId,
          referencedTable: $db.dbContactRegionAssignments,
          getReferencedColumn: (t) => t.contactId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$DbContactRegionAssignmentsTableAnnotationComposer(
                $db: $db,
                $table: $db.dbContactRegionAssignments,
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
            bool dbContactAttemptsRefs,
            bool dbContactRevisionsRefs,
            bool dbContactAnswersRefs,
            bool dbContactRevisionConflictsRefs,
            bool dbContactRegionAssignmentsRefs,
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
                Value<String?> regionTreeVersion = const Value.absent(),
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
                regionTreeVersion: regionTreeVersion,
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
                Value<String?> regionTreeVersion = const Value.absent(),
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
                regionTreeVersion: regionTreeVersion,
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
              ({
                dbContactAttemptsRefs = false,
                dbContactRevisionsRefs = false,
                dbContactAnswersRefs = false,
                dbContactRevisionConflictsRefs = false,
                dbContactRegionAssignmentsRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (dbContactAttemptsRefs) db.dbContactAttempts,
                    if (dbContactRevisionsRefs) db.dbContactRevisions,
                    if (dbContactAnswersRefs) db.dbContactAnswers,
                    if (dbContactRevisionConflictsRefs)
                      db.dbContactRevisionConflicts,
                    if (dbContactRegionAssignmentsRefs)
                      db.dbContactRegionAssignments,
                  ],
                  addJoins: null,
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (dbContactAttemptsRefs)
                        await $_getPrefetchedData<
                          DbContactRecord,
                          $DbContactRecordsTable,
                          DbContactAttempt
                        >(
                          currentTable: table,
                          referencedTable: $$DbContactRecordsTableReferences
                              ._dbContactAttemptsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$DbContactRecordsTableReferences(
                                db,
                                table,
                                p0,
                              ).dbContactAttemptsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.linkedContactId == item.contactId,
                              ),
                          typedResults: items,
                        ),
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
                      if (dbContactRevisionConflictsRefs)
                        await $_getPrefetchedData<
                          DbContactRecord,
                          $DbContactRecordsTable,
                          DbContactRevisionConflict
                        >(
                          currentTable: table,
                          referencedTable: $$DbContactRecordsTableReferences
                              ._dbContactRevisionConflictsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$DbContactRecordsTableReferences(
                                db,
                                table,
                                p0,
                              ).dbContactRevisionConflictsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.contactId == item.contactId,
                              ),
                          typedResults: items,
                        ),
                      if (dbContactRegionAssignmentsRefs)
                        await $_getPrefetchedData<
                          DbContactRecord,
                          $DbContactRecordsTable,
                          DbContactRegionAssignment
                        >(
                          currentTable: table,
                          referencedTable: $$DbContactRecordsTableReferences
                              ._dbContactRegionAssignmentsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$DbContactRecordsTableReferences(
                                db,
                                table,
                                p0,
                              ).dbContactRegionAssignmentsRefs,
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
        bool dbContactAttemptsRefs,
        bool dbContactRevisionsRefs,
        bool dbContactAnswersRefs,
        bool dbContactRevisionConflictsRefs,
        bool dbContactRegionAssignmentsRefs,
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
typedef $$DbContactAttemptsTableCreateCompanionBuilder =
    DbContactAttemptsCompanion Function({
      required String attemptId,
      required String appUserId,
      required String workspaceId,
      required String projectId,
      required DateTime occurredAtUtc,
      required String occurredTimeZone,
      required DateTime firstSubmittedAtUtc,
      required String channel,
      Value<String?> channelDetail,
      Value<String?> linkedContactId,
      Value<int> rowid,
    });
typedef $$DbContactAttemptsTableUpdateCompanionBuilder =
    DbContactAttemptsCompanion Function({
      Value<String> attemptId,
      Value<String> appUserId,
      Value<String> workspaceId,
      Value<String> projectId,
      Value<DateTime> occurredAtUtc,
      Value<String> occurredTimeZone,
      Value<DateTime> firstSubmittedAtUtc,
      Value<String> channel,
      Value<String?> channelDetail,
      Value<String?> linkedContactId,
      Value<int> rowid,
    });

final class $$DbContactAttemptsTableReferences
    extends
        BaseReferences<
          _$LocalDatabase,
          $DbContactAttemptsTable,
          DbContactAttempt
        > {
  $$DbContactAttemptsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $DbContactRecordsTable _linkedContactIdTable(
    _$LocalDatabase db,
  ) => db.dbContactRecords.createAlias(
    'db_contact_attempts__linked_contact_id__db_contact_records__contact_id',
  );

  $$DbContactRecordsTableProcessedTableManager? get linkedContactId {
    final $_column = $_itemColumn<String>('linked_contact_id');
    if ($_column == null) return null;
    final manager = $$DbContactRecordsTableTableManager(
      $_db,
      $_db.dbContactRecords,
    ).filter((f) => f.contactId.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_linkedContactIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$DbContactAttemptsTableFilterComposer
    extends Composer<_$LocalDatabase, $DbContactAttemptsTable> {
  $$DbContactAttemptsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get attemptId => $composableBuilder(
    column: $table.attemptId,
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

  $$DbContactRecordsTableFilterComposer get linkedContactId {
    final $$DbContactRecordsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.linkedContactId,
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

class $$DbContactAttemptsTableOrderingComposer
    extends Composer<_$LocalDatabase, $DbContactAttemptsTable> {
  $$DbContactAttemptsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get attemptId => $composableBuilder(
    column: $table.attemptId,
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

  $$DbContactRecordsTableOrderingComposer get linkedContactId {
    final $$DbContactRecordsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.linkedContactId,
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

class $$DbContactAttemptsTableAnnotationComposer
    extends Composer<_$LocalDatabase, $DbContactAttemptsTable> {
  $$DbContactAttemptsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get attemptId =>
      $composableBuilder(column: $table.attemptId, builder: (column) => column);

  GeneratedColumn<String> get appUserId =>
      $composableBuilder(column: $table.appUserId, builder: (column) => column);

  GeneratedColumn<String> get workspaceId => $composableBuilder(
    column: $table.workspaceId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get projectId =>
      $composableBuilder(column: $table.projectId, builder: (column) => column);

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

  $$DbContactRecordsTableAnnotationComposer get linkedContactId {
    final $$DbContactRecordsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.linkedContactId,
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

class $$DbContactAttemptsTableTableManager
    extends
        RootTableManager<
          _$LocalDatabase,
          $DbContactAttemptsTable,
          DbContactAttempt,
          $$DbContactAttemptsTableFilterComposer,
          $$DbContactAttemptsTableOrderingComposer,
          $$DbContactAttemptsTableAnnotationComposer,
          $$DbContactAttemptsTableCreateCompanionBuilder,
          $$DbContactAttemptsTableUpdateCompanionBuilder,
          (DbContactAttempt, $$DbContactAttemptsTableReferences),
          DbContactAttempt,
          PrefetchHooks Function({bool linkedContactId})
        > {
  $$DbContactAttemptsTableTableManager(
    _$LocalDatabase db,
    $DbContactAttemptsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DbContactAttemptsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DbContactAttemptsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DbContactAttemptsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> attemptId = const Value.absent(),
                Value<String> appUserId = const Value.absent(),
                Value<String> workspaceId = const Value.absent(),
                Value<String> projectId = const Value.absent(),
                Value<DateTime> occurredAtUtc = const Value.absent(),
                Value<String> occurredTimeZone = const Value.absent(),
                Value<DateTime> firstSubmittedAtUtc = const Value.absent(),
                Value<String> channel = const Value.absent(),
                Value<String?> channelDetail = const Value.absent(),
                Value<String?> linkedContactId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DbContactAttemptsCompanion(
                attemptId: attemptId,
                appUserId: appUserId,
                workspaceId: workspaceId,
                projectId: projectId,
                occurredAtUtc: occurredAtUtc,
                occurredTimeZone: occurredTimeZone,
                firstSubmittedAtUtc: firstSubmittedAtUtc,
                channel: channel,
                channelDetail: channelDetail,
                linkedContactId: linkedContactId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String attemptId,
                required String appUserId,
                required String workspaceId,
                required String projectId,
                required DateTime occurredAtUtc,
                required String occurredTimeZone,
                required DateTime firstSubmittedAtUtc,
                required String channel,
                Value<String?> channelDetail = const Value.absent(),
                Value<String?> linkedContactId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DbContactAttemptsCompanion.insert(
                attemptId: attemptId,
                appUserId: appUserId,
                workspaceId: workspaceId,
                projectId: projectId,
                occurredAtUtc: occurredAtUtc,
                occurredTimeZone: occurredTimeZone,
                firstSubmittedAtUtc: firstSubmittedAtUtc,
                channel: channel,
                channelDetail: channelDetail,
                linkedContactId: linkedContactId,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$DbContactAttemptsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({linkedContactId = false}) {
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
                    if (linkedContactId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.linkedContactId,
                                referencedTable:
                                    $$DbContactAttemptsTableReferences
                                        ._linkedContactIdTable(db),
                                referencedColumn:
                                    $$DbContactAttemptsTableReferences
                                        ._linkedContactIdTable(db)
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

typedef $$DbContactAttemptsTableProcessedTableManager =
    ProcessedTableManager<
      _$LocalDatabase,
      $DbContactAttemptsTable,
      DbContactAttempt,
      $$DbContactAttemptsTableFilterComposer,
      $$DbContactAttemptsTableOrderingComposer,
      $$DbContactAttemptsTableAnnotationComposer,
      $$DbContactAttemptsTableCreateCompanionBuilder,
      $$DbContactAttemptsTableUpdateCompanionBuilder,
      (DbContactAttempt, $$DbContactAttemptsTableReferences),
      DbContactAttempt,
      PrefetchHooks Function({bool linkedContactId})
    >;
typedef $$DbContactRevisionsTableCreateCompanionBuilder =
    DbContactRevisionsCompanion Function({
      required String revisionId,
      required String contactId,
      required int revisionNumber,
      Value<String> revisionKind,
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
      Value<String?> regionTreeVersion,
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
      Value<String> revisionKind,
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
      Value<String?> regionTreeVersion,
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

  ColumnFilters<String> get revisionKind => $composableBuilder(
    column: $table.revisionKind,
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

  ColumnFilters<String> get regionTreeVersion => $composableBuilder(
    column: $table.regionTreeVersion,
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

  ColumnOrderings<String> get revisionKind => $composableBuilder(
    column: $table.revisionKind,
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

  ColumnOrderings<String> get regionTreeVersion => $composableBuilder(
    column: $table.regionTreeVersion,
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

  GeneratedColumn<String> get revisionKind => $composableBuilder(
    column: $table.revisionKind,
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

  GeneratedColumn<String> get regionTreeVersion => $composableBuilder(
    column: $table.regionTreeVersion,
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
                Value<String> revisionKind = const Value.absent(),
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
                Value<String?> regionTreeVersion = const Value.absent(),
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
                revisionKind: revisionKind,
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
                regionTreeVersion: regionTreeVersion,
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
                Value<String> revisionKind = const Value.absent(),
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
                Value<String?> regionTreeVersion = const Value.absent(),
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
                revisionKind: revisionKind,
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
                regionTreeVersion: regionTreeVersion,
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
      Value<String?> answerStateReason,
      required String answerType,
      Value<bool?> booleanValue,
      Value<String?> textValue,
      Value<double?> numberValue,
      Value<String?> multiChoiceValueJson,
      Value<int> rowid,
    });
typedef $$DbContactAnswersTableUpdateCompanionBuilder =
    DbContactAnswersCompanion Function({
      Value<String> contactId,
      Value<int> revisionNumber,
      Value<String> questionId,
      Value<String> answerState,
      Value<String?> answerStateReason,
      Value<String> answerType,
      Value<bool?> booleanValue,
      Value<String?> textValue,
      Value<double?> numberValue,
      Value<String?> multiChoiceValueJson,
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

  ColumnFilters<String> get answerStateReason => $composableBuilder(
    column: $table.answerStateReason,
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

  ColumnFilters<String> get textValue => $composableBuilder(
    column: $table.textValue,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get numberValue => $composableBuilder(
    column: $table.numberValue,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get multiChoiceValueJson => $composableBuilder(
    column: $table.multiChoiceValueJson,
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

  ColumnOrderings<String> get answerStateReason => $composableBuilder(
    column: $table.answerStateReason,
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

  ColumnOrderings<String> get textValue => $composableBuilder(
    column: $table.textValue,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get numberValue => $composableBuilder(
    column: $table.numberValue,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get multiChoiceValueJson => $composableBuilder(
    column: $table.multiChoiceValueJson,
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

  GeneratedColumn<String> get answerStateReason => $composableBuilder(
    column: $table.answerStateReason,
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

  GeneratedColumn<String> get textValue =>
      $composableBuilder(column: $table.textValue, builder: (column) => column);

  GeneratedColumn<double> get numberValue => $composableBuilder(
    column: $table.numberValue,
    builder: (column) => column,
  );

  GeneratedColumn<String> get multiChoiceValueJson => $composableBuilder(
    column: $table.multiChoiceValueJson,
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
                Value<String?> answerStateReason = const Value.absent(),
                Value<String> answerType = const Value.absent(),
                Value<bool?> booleanValue = const Value.absent(),
                Value<String?> textValue = const Value.absent(),
                Value<double?> numberValue = const Value.absent(),
                Value<String?> multiChoiceValueJson = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DbContactAnswersCompanion(
                contactId: contactId,
                revisionNumber: revisionNumber,
                questionId: questionId,
                answerState: answerState,
                answerStateReason: answerStateReason,
                answerType: answerType,
                booleanValue: booleanValue,
                textValue: textValue,
                numberValue: numberValue,
                multiChoiceValueJson: multiChoiceValueJson,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String contactId,
                required int revisionNumber,
                required String questionId,
                required String answerState,
                Value<String?> answerStateReason = const Value.absent(),
                required String answerType,
                Value<bool?> booleanValue = const Value.absent(),
                Value<String?> textValue = const Value.absent(),
                Value<double?> numberValue = const Value.absent(),
                Value<String?> multiChoiceValueJson = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DbContactAnswersCompanion.insert(
                contactId: contactId,
                revisionNumber: revisionNumber,
                questionId: questionId,
                answerState: answerState,
                answerStateReason: answerStateReason,
                answerType: answerType,
                booleanValue: booleanValue,
                textValue: textValue,
                numberValue: numberValue,
                multiChoiceValueJson: multiChoiceValueJson,
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
typedef $$DbContactRevisionConflictsTableCreateCompanionBuilder =
    DbContactRevisionConflictsCompanion Function({
      required String conflictId,
      required String commandId,
      required String contactId,
      required String appUserId,
      required String workspaceId,
      required String projectId,
      required int baseRevision,
      required int currentRevision,
      required String conflictingFieldsJson,
      required String questionnaireVersionId,
      required String currentRevisionKind,
      required DateTime currentRevisedAtUtc,
      required String currentReason,
      required String currentSnapshotJson,
      required String proposedSnapshotJson,
      Value<String> status,
      Value<String?> resolutionCommandId,
      required DateTime createdAtUtc,
      Value<DateTime?> resolvedAtUtc,
      Value<int> rowid,
    });
typedef $$DbContactRevisionConflictsTableUpdateCompanionBuilder =
    DbContactRevisionConflictsCompanion Function({
      Value<String> conflictId,
      Value<String> commandId,
      Value<String> contactId,
      Value<String> appUserId,
      Value<String> workspaceId,
      Value<String> projectId,
      Value<int> baseRevision,
      Value<int> currentRevision,
      Value<String> conflictingFieldsJson,
      Value<String> questionnaireVersionId,
      Value<String> currentRevisionKind,
      Value<DateTime> currentRevisedAtUtc,
      Value<String> currentReason,
      Value<String> currentSnapshotJson,
      Value<String> proposedSnapshotJson,
      Value<String> status,
      Value<String?> resolutionCommandId,
      Value<DateTime> createdAtUtc,
      Value<DateTime?> resolvedAtUtc,
      Value<int> rowid,
    });

final class $$DbContactRevisionConflictsTableReferences
    extends
        BaseReferences<
          _$LocalDatabase,
          $DbContactRevisionConflictsTable,
          DbContactRevisionConflict
        > {
  $$DbContactRevisionConflictsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $DbContactRecordsTable _contactIdTable(
    _$LocalDatabase db,
  ) => db.dbContactRecords.createAlias(
    'db_contact_revision_conflicts__contact_id__db_contact_records__contact_id',
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

class $$DbContactRevisionConflictsTableFilterComposer
    extends Composer<_$LocalDatabase, $DbContactRevisionConflictsTable> {
  $$DbContactRevisionConflictsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get conflictId => $composableBuilder(
    column: $table.conflictId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get commandId => $composableBuilder(
    column: $table.commandId,
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

  ColumnFilters<int> get baseRevision => $composableBuilder(
    column: $table.baseRevision,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get currentRevision => $composableBuilder(
    column: $table.currentRevision,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get conflictingFieldsJson => $composableBuilder(
    column: $table.conflictingFieldsJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get questionnaireVersionId => $composableBuilder(
    column: $table.questionnaireVersionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get currentRevisionKind => $composableBuilder(
    column: $table.currentRevisionKind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get currentRevisedAtUtc => $composableBuilder(
    column: $table.currentRevisedAtUtc,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get currentReason => $composableBuilder(
    column: $table.currentReason,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get currentSnapshotJson => $composableBuilder(
    column: $table.currentSnapshotJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get proposedSnapshotJson => $composableBuilder(
    column: $table.proposedSnapshotJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get resolutionCommandId => $composableBuilder(
    column: $table.resolutionCommandId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAtUtc => $composableBuilder(
    column: $table.createdAtUtc,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get resolvedAtUtc => $composableBuilder(
    column: $table.resolvedAtUtc,
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

class $$DbContactRevisionConflictsTableOrderingComposer
    extends Composer<_$LocalDatabase, $DbContactRevisionConflictsTable> {
  $$DbContactRevisionConflictsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get conflictId => $composableBuilder(
    column: $table.conflictId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get commandId => $composableBuilder(
    column: $table.commandId,
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

  ColumnOrderings<int> get baseRevision => $composableBuilder(
    column: $table.baseRevision,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get currentRevision => $composableBuilder(
    column: $table.currentRevision,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get conflictingFieldsJson => $composableBuilder(
    column: $table.conflictingFieldsJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get questionnaireVersionId => $composableBuilder(
    column: $table.questionnaireVersionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get currentRevisionKind => $composableBuilder(
    column: $table.currentRevisionKind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get currentRevisedAtUtc => $composableBuilder(
    column: $table.currentRevisedAtUtc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get currentReason => $composableBuilder(
    column: $table.currentReason,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get currentSnapshotJson => $composableBuilder(
    column: $table.currentSnapshotJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get proposedSnapshotJson => $composableBuilder(
    column: $table.proposedSnapshotJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get resolutionCommandId => $composableBuilder(
    column: $table.resolutionCommandId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAtUtc => $composableBuilder(
    column: $table.createdAtUtc,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get resolvedAtUtc => $composableBuilder(
    column: $table.resolvedAtUtc,
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

class $$DbContactRevisionConflictsTableAnnotationComposer
    extends Composer<_$LocalDatabase, $DbContactRevisionConflictsTable> {
  $$DbContactRevisionConflictsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get conflictId => $composableBuilder(
    column: $table.conflictId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get commandId =>
      $composableBuilder(column: $table.commandId, builder: (column) => column);

  GeneratedColumn<String> get appUserId =>
      $composableBuilder(column: $table.appUserId, builder: (column) => column);

  GeneratedColumn<String> get workspaceId => $composableBuilder(
    column: $table.workspaceId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get projectId =>
      $composableBuilder(column: $table.projectId, builder: (column) => column);

  GeneratedColumn<int> get baseRevision => $composableBuilder(
    column: $table.baseRevision,
    builder: (column) => column,
  );

  GeneratedColumn<int> get currentRevision => $composableBuilder(
    column: $table.currentRevision,
    builder: (column) => column,
  );

  GeneratedColumn<String> get conflictingFieldsJson => $composableBuilder(
    column: $table.conflictingFieldsJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get questionnaireVersionId => $composableBuilder(
    column: $table.questionnaireVersionId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get currentRevisionKind => $composableBuilder(
    column: $table.currentRevisionKind,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get currentRevisedAtUtc => $composableBuilder(
    column: $table.currentRevisedAtUtc,
    builder: (column) => column,
  );

  GeneratedColumn<String> get currentReason => $composableBuilder(
    column: $table.currentReason,
    builder: (column) => column,
  );

  GeneratedColumn<String> get currentSnapshotJson => $composableBuilder(
    column: $table.currentSnapshotJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get proposedSnapshotJson => $composableBuilder(
    column: $table.proposedSnapshotJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get resolutionCommandId => $composableBuilder(
    column: $table.resolutionCommandId,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAtUtc => $composableBuilder(
    column: $table.createdAtUtc,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get resolvedAtUtc => $composableBuilder(
    column: $table.resolvedAtUtc,
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

class $$DbContactRevisionConflictsTableTableManager
    extends
        RootTableManager<
          _$LocalDatabase,
          $DbContactRevisionConflictsTable,
          DbContactRevisionConflict,
          $$DbContactRevisionConflictsTableFilterComposer,
          $$DbContactRevisionConflictsTableOrderingComposer,
          $$DbContactRevisionConflictsTableAnnotationComposer,
          $$DbContactRevisionConflictsTableCreateCompanionBuilder,
          $$DbContactRevisionConflictsTableUpdateCompanionBuilder,
          (
            DbContactRevisionConflict,
            $$DbContactRevisionConflictsTableReferences,
          ),
          DbContactRevisionConflict,
          PrefetchHooks Function({bool contactId})
        > {
  $$DbContactRevisionConflictsTableTableManager(
    _$LocalDatabase db,
    $DbContactRevisionConflictsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DbContactRevisionConflictsTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$DbContactRevisionConflictsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$DbContactRevisionConflictsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> conflictId = const Value.absent(),
                Value<String> commandId = const Value.absent(),
                Value<String> contactId = const Value.absent(),
                Value<String> appUserId = const Value.absent(),
                Value<String> workspaceId = const Value.absent(),
                Value<String> projectId = const Value.absent(),
                Value<int> baseRevision = const Value.absent(),
                Value<int> currentRevision = const Value.absent(),
                Value<String> conflictingFieldsJson = const Value.absent(),
                Value<String> questionnaireVersionId = const Value.absent(),
                Value<String> currentRevisionKind = const Value.absent(),
                Value<DateTime> currentRevisedAtUtc = const Value.absent(),
                Value<String> currentReason = const Value.absent(),
                Value<String> currentSnapshotJson = const Value.absent(),
                Value<String> proposedSnapshotJson = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<String?> resolutionCommandId = const Value.absent(),
                Value<DateTime> createdAtUtc = const Value.absent(),
                Value<DateTime?> resolvedAtUtc = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DbContactRevisionConflictsCompanion(
                conflictId: conflictId,
                commandId: commandId,
                contactId: contactId,
                appUserId: appUserId,
                workspaceId: workspaceId,
                projectId: projectId,
                baseRevision: baseRevision,
                currentRevision: currentRevision,
                conflictingFieldsJson: conflictingFieldsJson,
                questionnaireVersionId: questionnaireVersionId,
                currentRevisionKind: currentRevisionKind,
                currentRevisedAtUtc: currentRevisedAtUtc,
                currentReason: currentReason,
                currentSnapshotJson: currentSnapshotJson,
                proposedSnapshotJson: proposedSnapshotJson,
                status: status,
                resolutionCommandId: resolutionCommandId,
                createdAtUtc: createdAtUtc,
                resolvedAtUtc: resolvedAtUtc,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String conflictId,
                required String commandId,
                required String contactId,
                required String appUserId,
                required String workspaceId,
                required String projectId,
                required int baseRevision,
                required int currentRevision,
                required String conflictingFieldsJson,
                required String questionnaireVersionId,
                required String currentRevisionKind,
                required DateTime currentRevisedAtUtc,
                required String currentReason,
                required String currentSnapshotJson,
                required String proposedSnapshotJson,
                Value<String> status = const Value.absent(),
                Value<String?> resolutionCommandId = const Value.absent(),
                required DateTime createdAtUtc,
                Value<DateTime?> resolvedAtUtc = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DbContactRevisionConflictsCompanion.insert(
                conflictId: conflictId,
                commandId: commandId,
                contactId: contactId,
                appUserId: appUserId,
                workspaceId: workspaceId,
                projectId: projectId,
                baseRevision: baseRevision,
                currentRevision: currentRevision,
                conflictingFieldsJson: conflictingFieldsJson,
                questionnaireVersionId: questionnaireVersionId,
                currentRevisionKind: currentRevisionKind,
                currentRevisedAtUtc: currentRevisedAtUtc,
                currentReason: currentReason,
                currentSnapshotJson: currentSnapshotJson,
                proposedSnapshotJson: proposedSnapshotJson,
                status: status,
                resolutionCommandId: resolutionCommandId,
                createdAtUtc: createdAtUtc,
                resolvedAtUtc: resolvedAtUtc,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$DbContactRevisionConflictsTableReferences(db, table, e),
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
                                    $$DbContactRevisionConflictsTableReferences
                                        ._contactIdTable(db),
                                referencedColumn:
                                    $$DbContactRevisionConflictsTableReferences
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

typedef $$DbContactRevisionConflictsTableProcessedTableManager =
    ProcessedTableManager<
      _$LocalDatabase,
      $DbContactRevisionConflictsTable,
      DbContactRevisionConflict,
      $$DbContactRevisionConflictsTableFilterComposer,
      $$DbContactRevisionConflictsTableOrderingComposer,
      $$DbContactRevisionConflictsTableAnnotationComposer,
      $$DbContactRevisionConflictsTableCreateCompanionBuilder,
      $$DbContactRevisionConflictsTableUpdateCompanionBuilder,
      (DbContactRevisionConflict, $$DbContactRevisionConflictsTableReferences),
      DbContactRevisionConflict,
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
      Value<String?> regionTreeVersion,
      Value<double?> latitude,
      Value<double?> longitude,
      Value<double?> locationAccuracyMeters,
      Value<int?> reachCount,
      Value<int?> interestLevel,
      Value<String> syncMode,
      Value<int> localRevision,
      Value<int> serverRevision,
      Value<String?> sourceAttemptId,
      Value<String?> conflictOfDraftId,
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
      Value<String?> regionTreeVersion,
      Value<double?> latitude,
      Value<double?> longitude,
      Value<double?> locationAccuracyMeters,
      Value<int?> reachCount,
      Value<int?> interestLevel,
      Value<String> syncMode,
      Value<int> localRevision,
      Value<int> serverRevision,
      Value<String?> sourceAttemptId,
      Value<String?> conflictOfDraftId,
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

  static MultiTypedResultKey<
    $DbDraftRegionAssignmentsTable,
    List<DbDraftRegionAssignment>
  >
  _dbDraftRegionAssignmentsRefsTable(
    _$LocalDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.dbDraftRegionAssignments,
    aliasName:
        'db_contact_drafts__draft_id__db_draft_region_assignments__draft_id',
  );

  $$DbDraftRegionAssignmentsTableProcessedTableManager
  get dbDraftRegionAssignmentsRefs {
    final manager =
        $$DbDraftRegionAssignmentsTableTableManager(
          $_db,
          $_db.dbDraftRegionAssignments,
        ).filter(
          (f) => f.draftId.draftId.sqlEquals($_itemColumn<String>('draft_id')!),
        );

    final cache = $_typedResult.readTableOrNull(
      _dbDraftRegionAssignmentsRefsTable($_db),
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

  ColumnFilters<String> get regionTreeVersion => $composableBuilder(
    column: $table.regionTreeVersion,
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

  ColumnFilters<int> get localRevision => $composableBuilder(
    column: $table.localRevision,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get serverRevision => $composableBuilder(
    column: $table.serverRevision,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceAttemptId => $composableBuilder(
    column: $table.sourceAttemptId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get conflictOfDraftId => $composableBuilder(
    column: $table.conflictOfDraftId,
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

  Expression<bool> dbDraftRegionAssignmentsRefs(
    Expression<bool> Function($$DbDraftRegionAssignmentsTableFilterComposer f)
    f,
  ) {
    final $$DbDraftRegionAssignmentsTableFilterComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.draftId,
          referencedTable: $db.dbDraftRegionAssignments,
          getReferencedColumn: (t) => t.draftId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$DbDraftRegionAssignmentsTableFilterComposer(
                $db: $db,
                $table: $db.dbDraftRegionAssignments,
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

  ColumnOrderings<String> get regionTreeVersion => $composableBuilder(
    column: $table.regionTreeVersion,
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

  ColumnOrderings<int> get localRevision => $composableBuilder(
    column: $table.localRevision,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get serverRevision => $composableBuilder(
    column: $table.serverRevision,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceAttemptId => $composableBuilder(
    column: $table.sourceAttemptId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get conflictOfDraftId => $composableBuilder(
    column: $table.conflictOfDraftId,
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

  GeneratedColumn<String> get regionTreeVersion => $composableBuilder(
    column: $table.regionTreeVersion,
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

  GeneratedColumn<int> get localRevision => $composableBuilder(
    column: $table.localRevision,
    builder: (column) => column,
  );

  GeneratedColumn<int> get serverRevision => $composableBuilder(
    column: $table.serverRevision,
    builder: (column) => column,
  );

  GeneratedColumn<String> get sourceAttemptId => $composableBuilder(
    column: $table.sourceAttemptId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get conflictOfDraftId => $composableBuilder(
    column: $table.conflictOfDraftId,
    builder: (column) => column,
  );

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

  Expression<T> dbDraftRegionAssignmentsRefs<T extends Object>(
    Expression<T> Function($$DbDraftRegionAssignmentsTableAnnotationComposer a)
    f,
  ) {
    final $$DbDraftRegionAssignmentsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.draftId,
          referencedTable: $db.dbDraftRegionAssignments,
          getReferencedColumn: (t) => t.draftId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$DbDraftRegionAssignmentsTableAnnotationComposer(
                $db: $db,
                $table: $db.dbDraftRegionAssignments,
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
          PrefetchHooks Function({
            bool dbContactDraftAnswersRefs,
            bool dbDraftRegionAssignmentsRefs,
          })
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
                Value<String?> regionTreeVersion = const Value.absent(),
                Value<double?> latitude = const Value.absent(),
                Value<double?> longitude = const Value.absent(),
                Value<double?> locationAccuracyMeters = const Value.absent(),
                Value<int?> reachCount = const Value.absent(),
                Value<int?> interestLevel = const Value.absent(),
                Value<String> syncMode = const Value.absent(),
                Value<int> localRevision = const Value.absent(),
                Value<int> serverRevision = const Value.absent(),
                Value<String?> sourceAttemptId = const Value.absent(),
                Value<String?> conflictOfDraftId = const Value.absent(),
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
                regionTreeVersion: regionTreeVersion,
                latitude: latitude,
                longitude: longitude,
                locationAccuracyMeters: locationAccuracyMeters,
                reachCount: reachCount,
                interestLevel: interestLevel,
                syncMode: syncMode,
                localRevision: localRevision,
                serverRevision: serverRevision,
                sourceAttemptId: sourceAttemptId,
                conflictOfDraftId: conflictOfDraftId,
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
                Value<String?> regionTreeVersion = const Value.absent(),
                Value<double?> latitude = const Value.absent(),
                Value<double?> longitude = const Value.absent(),
                Value<double?> locationAccuracyMeters = const Value.absent(),
                Value<int?> reachCount = const Value.absent(),
                Value<int?> interestLevel = const Value.absent(),
                Value<String> syncMode = const Value.absent(),
                Value<int> localRevision = const Value.absent(),
                Value<int> serverRevision = const Value.absent(),
                Value<String?> sourceAttemptId = const Value.absent(),
                Value<String?> conflictOfDraftId = const Value.absent(),
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
                regionTreeVersion: regionTreeVersion,
                latitude: latitude,
                longitude: longitude,
                locationAccuracyMeters: locationAccuracyMeters,
                reachCount: reachCount,
                interestLevel: interestLevel,
                syncMode: syncMode,
                localRevision: localRevision,
                serverRevision: serverRevision,
                sourceAttemptId: sourceAttemptId,
                conflictOfDraftId: conflictOfDraftId,
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
          prefetchHooksCallback:
              ({
                dbContactDraftAnswersRefs = false,
                dbDraftRegionAssignmentsRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (dbContactDraftAnswersRefs) db.dbContactDraftAnswers,
                    if (dbDraftRegionAssignmentsRefs)
                      db.dbDraftRegionAssignments,
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
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.draftId == item.draftId,
                              ),
                          typedResults: items,
                        ),
                      if (dbDraftRegionAssignmentsRefs)
                        await $_getPrefetchedData<
                          DbContactDraft,
                          $DbContactDraftsTable,
                          DbDraftRegionAssignment
                        >(
                          currentTable: table,
                          referencedTable: $$DbContactDraftsTableReferences
                              ._dbDraftRegionAssignmentsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$DbContactDraftsTableReferences(
                                db,
                                table,
                                p0,
                              ).dbDraftRegionAssignmentsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
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
      PrefetchHooks Function({
        bool dbContactDraftAnswersRefs,
        bool dbDraftRegionAssignmentsRefs,
      })
    >;
typedef $$DbContactDraftAnswersTableCreateCompanionBuilder =
    DbContactDraftAnswersCompanion Function({
      required String draftId,
      required String questionId,
      required String answerState,
      Value<String?> answerStateReason,
      required String answerType,
      Value<bool?> booleanValue,
      Value<String?> textValue,
      Value<double?> numberValue,
      Value<String?> multiChoiceValueJson,
      Value<int> rowid,
    });
typedef $$DbContactDraftAnswersTableUpdateCompanionBuilder =
    DbContactDraftAnswersCompanion Function({
      Value<String> draftId,
      Value<String> questionId,
      Value<String> answerState,
      Value<String?> answerStateReason,
      Value<String> answerType,
      Value<bool?> booleanValue,
      Value<String?> textValue,
      Value<double?> numberValue,
      Value<String?> multiChoiceValueJson,
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

  ColumnFilters<String> get answerStateReason => $composableBuilder(
    column: $table.answerStateReason,
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

  ColumnFilters<String> get textValue => $composableBuilder(
    column: $table.textValue,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get numberValue => $composableBuilder(
    column: $table.numberValue,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get multiChoiceValueJson => $composableBuilder(
    column: $table.multiChoiceValueJson,
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

  ColumnOrderings<String> get answerStateReason => $composableBuilder(
    column: $table.answerStateReason,
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

  ColumnOrderings<String> get textValue => $composableBuilder(
    column: $table.textValue,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get numberValue => $composableBuilder(
    column: $table.numberValue,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get multiChoiceValueJson => $composableBuilder(
    column: $table.multiChoiceValueJson,
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

  GeneratedColumn<String> get answerStateReason => $composableBuilder(
    column: $table.answerStateReason,
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

  GeneratedColumn<String> get textValue =>
      $composableBuilder(column: $table.textValue, builder: (column) => column);

  GeneratedColumn<double> get numberValue => $composableBuilder(
    column: $table.numberValue,
    builder: (column) => column,
  );

  GeneratedColumn<String> get multiChoiceValueJson => $composableBuilder(
    column: $table.multiChoiceValueJson,
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
                Value<String?> answerStateReason = const Value.absent(),
                Value<String> answerType = const Value.absent(),
                Value<bool?> booleanValue = const Value.absent(),
                Value<String?> textValue = const Value.absent(),
                Value<double?> numberValue = const Value.absent(),
                Value<String?> multiChoiceValueJson = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DbContactDraftAnswersCompanion(
                draftId: draftId,
                questionId: questionId,
                answerState: answerState,
                answerStateReason: answerStateReason,
                answerType: answerType,
                booleanValue: booleanValue,
                textValue: textValue,
                numberValue: numberValue,
                multiChoiceValueJson: multiChoiceValueJson,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String draftId,
                required String questionId,
                required String answerState,
                Value<String?> answerStateReason = const Value.absent(),
                required String answerType,
                Value<bool?> booleanValue = const Value.absent(),
                Value<String?> textValue = const Value.absent(),
                Value<double?> numberValue = const Value.absent(),
                Value<String?> multiChoiceValueJson = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DbContactDraftAnswersCompanion.insert(
                draftId: draftId,
                questionId: questionId,
                answerState: answerState,
                answerStateReason: answerStateReason,
                answerType: answerType,
                booleanValue: booleanValue,
                textValue: textValue,
                numberValue: numberValue,
                multiChoiceValueJson: multiChoiceValueJson,
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
typedef $$DbCanonicalRegionVersionsTableCreateCompanionBuilder =
    DbCanonicalRegionVersionsCompanion Function({
      required String regionVersionKey,
      required String regionId,
      required String treeVersion,
      Value<String?> parentRegionVersionKey,
      required String canonicalName,
      required String kind,
      required String attributesJson,
      Value<int> rowid,
    });
typedef $$DbCanonicalRegionVersionsTableUpdateCompanionBuilder =
    DbCanonicalRegionVersionsCompanion Function({
      Value<String> regionVersionKey,
      Value<String> regionId,
      Value<String> treeVersion,
      Value<String?> parentRegionVersionKey,
      Value<String> canonicalName,
      Value<String> kind,
      Value<String> attributesJson,
      Value<int> rowid,
    });

final class $$DbCanonicalRegionVersionsTableReferences
    extends
        BaseReferences<
          _$LocalDatabase,
          $DbCanonicalRegionVersionsTable,
          DbCanonicalRegionVersion
        > {
  $$DbCanonicalRegionVersionsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $DbCanonicalRegionVersionsTable _parentRegionVersionKeyTable(
    _$LocalDatabase db,
  ) => db.dbCanonicalRegionVersions.createAlias(
    'db_canonical_region_versions__parent_region_version_key__db_canonical_region_versions__region_version_key',
  );

  $$DbCanonicalRegionVersionsTableProcessedTableManager?
  get parentRegionVersionKey {
    final $_column = $_itemColumn<String>('parent_region_version_key');
    if ($_column == null) return null;
    final manager = $$DbCanonicalRegionVersionsTableTableManager(
      $_db,
      $_db.dbCanonicalRegionVersions,
    ).filter((f) => f.regionVersionKey.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(
      _parentRegionVersionKeyTable($_db),
    );
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<
    $DbContactRegionAssignmentsTable,
    List<DbContactRegionAssignment>
  >
  _dbContactRegionAssignmentsRefsTable(
    _$LocalDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.dbContactRegionAssignments,
    aliasName:
        'db_canonical_region_versions__region_version_key__db_contact_region_assignments__region_version_key',
  );

  $$DbContactRegionAssignmentsTableProcessedTableManager
  get dbContactRegionAssignmentsRefs {
    final manager =
        $$DbContactRegionAssignmentsTableTableManager(
          $_db,
          $_db.dbContactRegionAssignments,
        ).filter(
          (f) => f.regionVersionKey.regionVersionKey.sqlEquals(
            $_itemColumn<String>('region_version_key')!,
          ),
        );

    final cache = $_typedResult.readTableOrNull(
      _dbContactRegionAssignmentsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<
    $DbDraftRegionAssignmentsTable,
    List<DbDraftRegionAssignment>
  >
  _dbDraftRegionAssignmentsRefsTable(
    _$LocalDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.dbDraftRegionAssignments,
    aliasName:
        'db_canonical_region_versions__region_version_key__db_draft_region_assignments__region_version_key',
  );

  $$DbDraftRegionAssignmentsTableProcessedTableManager
  get dbDraftRegionAssignmentsRefs {
    final manager =
        $$DbDraftRegionAssignmentsTableTableManager(
          $_db,
          $_db.dbDraftRegionAssignments,
        ).filter(
          (f) => f.regionVersionKey.regionVersionKey.sqlEquals(
            $_itemColumn<String>('region_version_key')!,
          ),
        );

    final cache = $_typedResult.readTableOrNull(
      _dbDraftRegionAssignmentsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$DbCanonicalRegionVersionsTableFilterComposer
    extends Composer<_$LocalDatabase, $DbCanonicalRegionVersionsTable> {
  $$DbCanonicalRegionVersionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get regionVersionKey => $composableBuilder(
    column: $table.regionVersionKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get regionId => $composableBuilder(
    column: $table.regionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get treeVersion => $composableBuilder(
    column: $table.treeVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get canonicalName => $composableBuilder(
    column: $table.canonicalName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get attributesJson => $composableBuilder(
    column: $table.attributesJson,
    builder: (column) => ColumnFilters(column),
  );

  $$DbCanonicalRegionVersionsTableFilterComposer get parentRegionVersionKey {
    final $$DbCanonicalRegionVersionsTableFilterComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.parentRegionVersionKey,
          referencedTable: $db.dbCanonicalRegionVersions,
          getReferencedColumn: (t) => t.regionVersionKey,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$DbCanonicalRegionVersionsTableFilterComposer(
                $db: $db,
                $table: $db.dbCanonicalRegionVersions,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return composer;
  }

  Expression<bool> dbContactRegionAssignmentsRefs(
    Expression<bool> Function($$DbContactRegionAssignmentsTableFilterComposer f)
    f,
  ) {
    final $$DbContactRegionAssignmentsTableFilterComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.regionVersionKey,
          referencedTable: $db.dbContactRegionAssignments,
          getReferencedColumn: (t) => t.regionVersionKey,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$DbContactRegionAssignmentsTableFilterComposer(
                $db: $db,
                $table: $db.dbContactRegionAssignments,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }

  Expression<bool> dbDraftRegionAssignmentsRefs(
    Expression<bool> Function($$DbDraftRegionAssignmentsTableFilterComposer f)
    f,
  ) {
    final $$DbDraftRegionAssignmentsTableFilterComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.regionVersionKey,
          referencedTable: $db.dbDraftRegionAssignments,
          getReferencedColumn: (t) => t.regionVersionKey,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$DbDraftRegionAssignmentsTableFilterComposer(
                $db: $db,
                $table: $db.dbDraftRegionAssignments,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }
}

class $$DbCanonicalRegionVersionsTableOrderingComposer
    extends Composer<_$LocalDatabase, $DbCanonicalRegionVersionsTable> {
  $$DbCanonicalRegionVersionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get regionVersionKey => $composableBuilder(
    column: $table.regionVersionKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get regionId => $composableBuilder(
    column: $table.regionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get treeVersion => $composableBuilder(
    column: $table.treeVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get canonicalName => $composableBuilder(
    column: $table.canonicalName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get attributesJson => $composableBuilder(
    column: $table.attributesJson,
    builder: (column) => ColumnOrderings(column),
  );

  $$DbCanonicalRegionVersionsTableOrderingComposer get parentRegionVersionKey {
    final $$DbCanonicalRegionVersionsTableOrderingComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.parentRegionVersionKey,
          referencedTable: $db.dbCanonicalRegionVersions,
          getReferencedColumn: (t) => t.regionVersionKey,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$DbCanonicalRegionVersionsTableOrderingComposer(
                $db: $db,
                $table: $db.dbCanonicalRegionVersions,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return composer;
  }
}

class $$DbCanonicalRegionVersionsTableAnnotationComposer
    extends Composer<_$LocalDatabase, $DbCanonicalRegionVersionsTable> {
  $$DbCanonicalRegionVersionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get regionVersionKey => $composableBuilder(
    column: $table.regionVersionKey,
    builder: (column) => column,
  );

  GeneratedColumn<String> get regionId =>
      $composableBuilder(column: $table.regionId, builder: (column) => column);

  GeneratedColumn<String> get treeVersion => $composableBuilder(
    column: $table.treeVersion,
    builder: (column) => column,
  );

  GeneratedColumn<String> get canonicalName => $composableBuilder(
    column: $table.canonicalName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get attributesJson => $composableBuilder(
    column: $table.attributesJson,
    builder: (column) => column,
  );

  $$DbCanonicalRegionVersionsTableAnnotationComposer
  get parentRegionVersionKey {
    final $$DbCanonicalRegionVersionsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.parentRegionVersionKey,
          referencedTable: $db.dbCanonicalRegionVersions,
          getReferencedColumn: (t) => t.regionVersionKey,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$DbCanonicalRegionVersionsTableAnnotationComposer(
                $db: $db,
                $table: $db.dbCanonicalRegionVersions,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return composer;
  }

  Expression<T> dbContactRegionAssignmentsRefs<T extends Object>(
    Expression<T> Function(
      $$DbContactRegionAssignmentsTableAnnotationComposer a,
    )
    f,
  ) {
    final $$DbContactRegionAssignmentsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.regionVersionKey,
          referencedTable: $db.dbContactRegionAssignments,
          getReferencedColumn: (t) => t.regionVersionKey,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$DbContactRegionAssignmentsTableAnnotationComposer(
                $db: $db,
                $table: $db.dbContactRegionAssignments,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }

  Expression<T> dbDraftRegionAssignmentsRefs<T extends Object>(
    Expression<T> Function($$DbDraftRegionAssignmentsTableAnnotationComposer a)
    f,
  ) {
    final $$DbDraftRegionAssignmentsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.regionVersionKey,
          referencedTable: $db.dbDraftRegionAssignments,
          getReferencedColumn: (t) => t.regionVersionKey,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$DbDraftRegionAssignmentsTableAnnotationComposer(
                $db: $db,
                $table: $db.dbDraftRegionAssignments,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }
}

class $$DbCanonicalRegionVersionsTableTableManager
    extends
        RootTableManager<
          _$LocalDatabase,
          $DbCanonicalRegionVersionsTable,
          DbCanonicalRegionVersion,
          $$DbCanonicalRegionVersionsTableFilterComposer,
          $$DbCanonicalRegionVersionsTableOrderingComposer,
          $$DbCanonicalRegionVersionsTableAnnotationComposer,
          $$DbCanonicalRegionVersionsTableCreateCompanionBuilder,
          $$DbCanonicalRegionVersionsTableUpdateCompanionBuilder,
          (
            DbCanonicalRegionVersion,
            $$DbCanonicalRegionVersionsTableReferences,
          ),
          DbCanonicalRegionVersion,
          PrefetchHooks Function({
            bool parentRegionVersionKey,
            bool dbContactRegionAssignmentsRefs,
            bool dbDraftRegionAssignmentsRefs,
          })
        > {
  $$DbCanonicalRegionVersionsTableTableManager(
    _$LocalDatabase db,
    $DbCanonicalRegionVersionsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DbCanonicalRegionVersionsTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$DbCanonicalRegionVersionsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$DbCanonicalRegionVersionsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> regionVersionKey = const Value.absent(),
                Value<String> regionId = const Value.absent(),
                Value<String> treeVersion = const Value.absent(),
                Value<String?> parentRegionVersionKey = const Value.absent(),
                Value<String> canonicalName = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<String> attributesJson = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DbCanonicalRegionVersionsCompanion(
                regionVersionKey: regionVersionKey,
                regionId: regionId,
                treeVersion: treeVersion,
                parentRegionVersionKey: parentRegionVersionKey,
                canonicalName: canonicalName,
                kind: kind,
                attributesJson: attributesJson,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String regionVersionKey,
                required String regionId,
                required String treeVersion,
                Value<String?> parentRegionVersionKey = const Value.absent(),
                required String canonicalName,
                required String kind,
                required String attributesJson,
                Value<int> rowid = const Value.absent(),
              }) => DbCanonicalRegionVersionsCompanion.insert(
                regionVersionKey: regionVersionKey,
                regionId: regionId,
                treeVersion: treeVersion,
                parentRegionVersionKey: parentRegionVersionKey,
                canonicalName: canonicalName,
                kind: kind,
                attributesJson: attributesJson,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$DbCanonicalRegionVersionsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                parentRegionVersionKey = false,
                dbContactRegionAssignmentsRefs = false,
                dbDraftRegionAssignmentsRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (dbContactRegionAssignmentsRefs)
                      db.dbContactRegionAssignments,
                    if (dbDraftRegionAssignmentsRefs)
                      db.dbDraftRegionAssignments,
                  ],
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
                        if (parentRegionVersionKey) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.parentRegionVersionKey,
                                    referencedTable:
                                        $$DbCanonicalRegionVersionsTableReferences
                                            ._parentRegionVersionKeyTable(db),
                                    referencedColumn:
                                        $$DbCanonicalRegionVersionsTableReferences
                                            ._parentRegionVersionKeyTable(db)
                                            .regionVersionKey,
                                  )
                                  as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (dbContactRegionAssignmentsRefs)
                        await $_getPrefetchedData<
                          DbCanonicalRegionVersion,
                          $DbCanonicalRegionVersionsTable,
                          DbContactRegionAssignment
                        >(
                          currentTable: table,
                          referencedTable:
                              $$DbCanonicalRegionVersionsTableReferences
                                  ._dbContactRegionAssignmentsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$DbCanonicalRegionVersionsTableReferences(
                                db,
                                table,
                                p0,
                              ).dbContactRegionAssignmentsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) =>
                                    e.regionVersionKey == item.regionVersionKey,
                              ),
                          typedResults: items,
                        ),
                      if (dbDraftRegionAssignmentsRefs)
                        await $_getPrefetchedData<
                          DbCanonicalRegionVersion,
                          $DbCanonicalRegionVersionsTable,
                          DbDraftRegionAssignment
                        >(
                          currentTable: table,
                          referencedTable:
                              $$DbCanonicalRegionVersionsTableReferences
                                  ._dbDraftRegionAssignmentsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$DbCanonicalRegionVersionsTableReferences(
                                db,
                                table,
                                p0,
                              ).dbDraftRegionAssignmentsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) =>
                                    e.regionVersionKey == item.regionVersionKey,
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

typedef $$DbCanonicalRegionVersionsTableProcessedTableManager =
    ProcessedTableManager<
      _$LocalDatabase,
      $DbCanonicalRegionVersionsTable,
      DbCanonicalRegionVersion,
      $$DbCanonicalRegionVersionsTableFilterComposer,
      $$DbCanonicalRegionVersionsTableOrderingComposer,
      $$DbCanonicalRegionVersionsTableAnnotationComposer,
      $$DbCanonicalRegionVersionsTableCreateCompanionBuilder,
      $$DbCanonicalRegionVersionsTableUpdateCompanionBuilder,
      (DbCanonicalRegionVersion, $$DbCanonicalRegionVersionsTableReferences),
      DbCanonicalRegionVersion,
      PrefetchHooks Function({
        bool parentRegionVersionKey,
        bool dbContactRegionAssignmentsRefs,
        bool dbDraftRegionAssignmentsRefs,
      })
    >;
typedef $$DbContactRegionAssignmentsTableCreateCompanionBuilder =
    DbContactRegionAssignmentsCompanion Function({
      required String contactId,
      required String regionVersionKey,
      Value<int> rowid,
    });
typedef $$DbContactRegionAssignmentsTableUpdateCompanionBuilder =
    DbContactRegionAssignmentsCompanion Function({
      Value<String> contactId,
      Value<String> regionVersionKey,
      Value<int> rowid,
    });

final class $$DbContactRegionAssignmentsTableReferences
    extends
        BaseReferences<
          _$LocalDatabase,
          $DbContactRegionAssignmentsTable,
          DbContactRegionAssignment
        > {
  $$DbContactRegionAssignmentsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $DbContactRecordsTable _contactIdTable(
    _$LocalDatabase db,
  ) => db.dbContactRecords.createAlias(
    'db_contact_region_assignments__contact_id__db_contact_records__contact_id',
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

  static $DbCanonicalRegionVersionsTable _regionVersionKeyTable(
    _$LocalDatabase db,
  ) => db.dbCanonicalRegionVersions.createAlias(
    'db_contact_region_assignments__region_version_key__db_canonical_region_versions__region_version_key',
  );

  $$DbCanonicalRegionVersionsTableProcessedTableManager get regionVersionKey {
    final $_column = $_itemColumn<String>('region_version_key')!;

    final manager = $$DbCanonicalRegionVersionsTableTableManager(
      $_db,
      $_db.dbCanonicalRegionVersions,
    ).filter((f) => f.regionVersionKey.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_regionVersionKeyTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$DbContactRegionAssignmentsTableFilterComposer
    extends Composer<_$LocalDatabase, $DbContactRegionAssignmentsTable> {
  $$DbContactRegionAssignmentsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
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

  $$DbCanonicalRegionVersionsTableFilterComposer get regionVersionKey {
    final $$DbCanonicalRegionVersionsTableFilterComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.regionVersionKey,
          referencedTable: $db.dbCanonicalRegionVersions,
          getReferencedColumn: (t) => t.regionVersionKey,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$DbCanonicalRegionVersionsTableFilterComposer(
                $db: $db,
                $table: $db.dbCanonicalRegionVersions,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return composer;
  }
}

class $$DbContactRegionAssignmentsTableOrderingComposer
    extends Composer<_$LocalDatabase, $DbContactRegionAssignmentsTable> {
  $$DbContactRegionAssignmentsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
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

  $$DbCanonicalRegionVersionsTableOrderingComposer get regionVersionKey {
    final $$DbCanonicalRegionVersionsTableOrderingComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.regionVersionKey,
          referencedTable: $db.dbCanonicalRegionVersions,
          getReferencedColumn: (t) => t.regionVersionKey,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$DbCanonicalRegionVersionsTableOrderingComposer(
                $db: $db,
                $table: $db.dbCanonicalRegionVersions,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return composer;
  }
}

class $$DbContactRegionAssignmentsTableAnnotationComposer
    extends Composer<_$LocalDatabase, $DbContactRegionAssignmentsTable> {
  $$DbContactRegionAssignmentsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
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

  $$DbCanonicalRegionVersionsTableAnnotationComposer get regionVersionKey {
    final $$DbCanonicalRegionVersionsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.regionVersionKey,
          referencedTable: $db.dbCanonicalRegionVersions,
          getReferencedColumn: (t) => t.regionVersionKey,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$DbCanonicalRegionVersionsTableAnnotationComposer(
                $db: $db,
                $table: $db.dbCanonicalRegionVersions,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return composer;
  }
}

class $$DbContactRegionAssignmentsTableTableManager
    extends
        RootTableManager<
          _$LocalDatabase,
          $DbContactRegionAssignmentsTable,
          DbContactRegionAssignment,
          $$DbContactRegionAssignmentsTableFilterComposer,
          $$DbContactRegionAssignmentsTableOrderingComposer,
          $$DbContactRegionAssignmentsTableAnnotationComposer,
          $$DbContactRegionAssignmentsTableCreateCompanionBuilder,
          $$DbContactRegionAssignmentsTableUpdateCompanionBuilder,
          (
            DbContactRegionAssignment,
            $$DbContactRegionAssignmentsTableReferences,
          ),
          DbContactRegionAssignment,
          PrefetchHooks Function({bool contactId, bool regionVersionKey})
        > {
  $$DbContactRegionAssignmentsTableTableManager(
    _$LocalDatabase db,
    $DbContactRegionAssignmentsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DbContactRegionAssignmentsTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$DbContactRegionAssignmentsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$DbContactRegionAssignmentsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> contactId = const Value.absent(),
                Value<String> regionVersionKey = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DbContactRegionAssignmentsCompanion(
                contactId: contactId,
                regionVersionKey: regionVersionKey,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String contactId,
                required String regionVersionKey,
                Value<int> rowid = const Value.absent(),
              }) => DbContactRegionAssignmentsCompanion.insert(
                contactId: contactId,
                regionVersionKey: regionVersionKey,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$DbContactRegionAssignmentsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({contactId = false, regionVersionKey = false}) {
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
                                    $$DbContactRegionAssignmentsTableReferences
                                        ._contactIdTable(db),
                                referencedColumn:
                                    $$DbContactRegionAssignmentsTableReferences
                                        ._contactIdTable(db)
                                        .contactId,
                              )
                              as T;
                    }
                    if (regionVersionKey) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.regionVersionKey,
                                referencedTable:
                                    $$DbContactRegionAssignmentsTableReferences
                                        ._regionVersionKeyTable(db),
                                referencedColumn:
                                    $$DbContactRegionAssignmentsTableReferences
                                        ._regionVersionKeyTable(db)
                                        .regionVersionKey,
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

typedef $$DbContactRegionAssignmentsTableProcessedTableManager =
    ProcessedTableManager<
      _$LocalDatabase,
      $DbContactRegionAssignmentsTable,
      DbContactRegionAssignment,
      $$DbContactRegionAssignmentsTableFilterComposer,
      $$DbContactRegionAssignmentsTableOrderingComposer,
      $$DbContactRegionAssignmentsTableAnnotationComposer,
      $$DbContactRegionAssignmentsTableCreateCompanionBuilder,
      $$DbContactRegionAssignmentsTableUpdateCompanionBuilder,
      (DbContactRegionAssignment, $$DbContactRegionAssignmentsTableReferences),
      DbContactRegionAssignment,
      PrefetchHooks Function({bool contactId, bool regionVersionKey})
    >;
typedef $$DbDraftRegionAssignmentsTableCreateCompanionBuilder =
    DbDraftRegionAssignmentsCompanion Function({
      required String draftId,
      required String regionVersionKey,
      Value<int> rowid,
    });
typedef $$DbDraftRegionAssignmentsTableUpdateCompanionBuilder =
    DbDraftRegionAssignmentsCompanion Function({
      Value<String> draftId,
      Value<String> regionVersionKey,
      Value<int> rowid,
    });

final class $$DbDraftRegionAssignmentsTableReferences
    extends
        BaseReferences<
          _$LocalDatabase,
          $DbDraftRegionAssignmentsTable,
          DbDraftRegionAssignment
        > {
  $$DbDraftRegionAssignmentsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $DbContactDraftsTable _draftIdTable(_$LocalDatabase db) =>
      db.dbContactDrafts.createAlias(
        'db_draft_region_assignments__draft_id__db_contact_drafts__draft_id',
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

  static $DbCanonicalRegionVersionsTable _regionVersionKeyTable(
    _$LocalDatabase db,
  ) => db.dbCanonicalRegionVersions.createAlias(
    'db_draft_region_assignments__region_version_key__db_canonical_region_versions__region_version_key',
  );

  $$DbCanonicalRegionVersionsTableProcessedTableManager get regionVersionKey {
    final $_column = $_itemColumn<String>('region_version_key')!;

    final manager = $$DbCanonicalRegionVersionsTableTableManager(
      $_db,
      $_db.dbCanonicalRegionVersions,
    ).filter((f) => f.regionVersionKey.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_regionVersionKeyTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$DbDraftRegionAssignmentsTableFilterComposer
    extends Composer<_$LocalDatabase, $DbDraftRegionAssignmentsTable> {
  $$DbDraftRegionAssignmentsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
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

  $$DbCanonicalRegionVersionsTableFilterComposer get regionVersionKey {
    final $$DbCanonicalRegionVersionsTableFilterComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.regionVersionKey,
          referencedTable: $db.dbCanonicalRegionVersions,
          getReferencedColumn: (t) => t.regionVersionKey,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$DbCanonicalRegionVersionsTableFilterComposer(
                $db: $db,
                $table: $db.dbCanonicalRegionVersions,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return composer;
  }
}

class $$DbDraftRegionAssignmentsTableOrderingComposer
    extends Composer<_$LocalDatabase, $DbDraftRegionAssignmentsTable> {
  $$DbDraftRegionAssignmentsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
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

  $$DbCanonicalRegionVersionsTableOrderingComposer get regionVersionKey {
    final $$DbCanonicalRegionVersionsTableOrderingComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.regionVersionKey,
          referencedTable: $db.dbCanonicalRegionVersions,
          getReferencedColumn: (t) => t.regionVersionKey,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$DbCanonicalRegionVersionsTableOrderingComposer(
                $db: $db,
                $table: $db.dbCanonicalRegionVersions,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return composer;
  }
}

class $$DbDraftRegionAssignmentsTableAnnotationComposer
    extends Composer<_$LocalDatabase, $DbDraftRegionAssignmentsTable> {
  $$DbDraftRegionAssignmentsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
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

  $$DbCanonicalRegionVersionsTableAnnotationComposer get regionVersionKey {
    final $$DbCanonicalRegionVersionsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.regionVersionKey,
          referencedTable: $db.dbCanonicalRegionVersions,
          getReferencedColumn: (t) => t.regionVersionKey,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$DbCanonicalRegionVersionsTableAnnotationComposer(
                $db: $db,
                $table: $db.dbCanonicalRegionVersions,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return composer;
  }
}

class $$DbDraftRegionAssignmentsTableTableManager
    extends
        RootTableManager<
          _$LocalDatabase,
          $DbDraftRegionAssignmentsTable,
          DbDraftRegionAssignment,
          $$DbDraftRegionAssignmentsTableFilterComposer,
          $$DbDraftRegionAssignmentsTableOrderingComposer,
          $$DbDraftRegionAssignmentsTableAnnotationComposer,
          $$DbDraftRegionAssignmentsTableCreateCompanionBuilder,
          $$DbDraftRegionAssignmentsTableUpdateCompanionBuilder,
          (DbDraftRegionAssignment, $$DbDraftRegionAssignmentsTableReferences),
          DbDraftRegionAssignment,
          PrefetchHooks Function({bool draftId, bool regionVersionKey})
        > {
  $$DbDraftRegionAssignmentsTableTableManager(
    _$LocalDatabase db,
    $DbDraftRegionAssignmentsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DbDraftRegionAssignmentsTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$DbDraftRegionAssignmentsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$DbDraftRegionAssignmentsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> draftId = const Value.absent(),
                Value<String> regionVersionKey = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DbDraftRegionAssignmentsCompanion(
                draftId: draftId,
                regionVersionKey: regionVersionKey,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String draftId,
                required String regionVersionKey,
                Value<int> rowid = const Value.absent(),
              }) => DbDraftRegionAssignmentsCompanion.insert(
                draftId: draftId,
                regionVersionKey: regionVersionKey,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$DbDraftRegionAssignmentsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({draftId = false, regionVersionKey = false}) {
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
                                    $$DbDraftRegionAssignmentsTableReferences
                                        ._draftIdTable(db),
                                referencedColumn:
                                    $$DbDraftRegionAssignmentsTableReferences
                                        ._draftIdTable(db)
                                        .draftId,
                              )
                              as T;
                    }
                    if (regionVersionKey) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.regionVersionKey,
                                referencedTable:
                                    $$DbDraftRegionAssignmentsTableReferences
                                        ._regionVersionKeyTable(db),
                                referencedColumn:
                                    $$DbDraftRegionAssignmentsTableReferences
                                        ._regionVersionKeyTable(db)
                                        .regionVersionKey,
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

typedef $$DbDraftRegionAssignmentsTableProcessedTableManager =
    ProcessedTableManager<
      _$LocalDatabase,
      $DbDraftRegionAssignmentsTable,
      DbDraftRegionAssignment,
      $$DbDraftRegionAssignmentsTableFilterComposer,
      $$DbDraftRegionAssignmentsTableOrderingComposer,
      $$DbDraftRegionAssignmentsTableAnnotationComposer,
      $$DbDraftRegionAssignmentsTableCreateCompanionBuilder,
      $$DbDraftRegionAssignmentsTableUpdateCompanionBuilder,
      (DbDraftRegionAssignment, $$DbDraftRegionAssignmentsTableReferences),
      DbDraftRegionAssignment,
      PrefetchHooks Function({bool draftId, bool regionVersionKey})
    >;
typedef $$DbQuestionnaireVersionsTableCreateCompanionBuilder =
    DbQuestionnaireVersionsCompanion Function({
      required String questionnaireVersionId,
      required String projectId,
      required int versionNumber,
      required String status,
      required DateTime installedAtUtc,
      Value<int> rowid,
    });
typedef $$DbQuestionnaireVersionsTableUpdateCompanionBuilder =
    DbQuestionnaireVersionsCompanion Function({
      Value<String> questionnaireVersionId,
      Value<String> projectId,
      Value<int> versionNumber,
      Value<String> status,
      Value<DateTime> installedAtUtc,
      Value<int> rowid,
    });

final class $$DbQuestionnaireVersionsTableReferences
    extends
        BaseReferences<
          _$LocalDatabase,
          $DbQuestionnaireVersionsTable,
          DbQuestionnaireVersion
        > {
  $$DbQuestionnaireVersionsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static MultiTypedResultKey<
    $DbQuestionnaireQuestionsTable,
    List<DbQuestionnaireQuestion>
  >
  _dbQuestionnaireQuestionsRefsTable(
    _$LocalDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.dbQuestionnaireQuestions,
    aliasName:
        'db_questionnaire_versions__questionnaire_version_id__db_questionnaire_questions__questionnaire_version_id',
  );

  $$DbQuestionnaireQuestionsTableProcessedTableManager
  get dbQuestionnaireQuestionsRefs {
    final manager =
        $$DbQuestionnaireQuestionsTableTableManager(
          $_db,
          $_db.dbQuestionnaireQuestions,
        ).filter(
          (f) => f.questionnaireVersionId.questionnaireVersionId.sqlEquals(
            $_itemColumn<String>('questionnaire_version_id')!,
          ),
        );

    final cache = $_typedResult.readTableOrNull(
      _dbQuestionnaireQuestionsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<
    $DbQuestionnaireOptionsTable,
    List<DbQuestionnaireOption>
  >
  _dbQuestionnaireOptionsRefsTable(
    _$LocalDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.dbQuestionnaireOptions,
    aliasName:
        'db_questionnaire_versions__questionnaire_version_id__db_questionnaire_options__questionnaire_version_id',
  );

  $$DbQuestionnaireOptionsTableProcessedTableManager
  get dbQuestionnaireOptionsRefs {
    final manager =
        $$DbQuestionnaireOptionsTableTableManager(
          $_db,
          $_db.dbQuestionnaireOptions,
        ).filter(
          (f) => f.questionnaireVersionId.questionnaireVersionId.sqlEquals(
            $_itemColumn<String>('questionnaire_version_id')!,
          ),
        );

    final cache = $_typedResult.readTableOrNull(
      _dbQuestionnaireOptionsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$DbQuestionnaireVersionsTableFilterComposer
    extends Composer<_$LocalDatabase, $DbQuestionnaireVersionsTable> {
  $$DbQuestionnaireVersionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get questionnaireVersionId => $composableBuilder(
    column: $table.questionnaireVersionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get projectId => $composableBuilder(
    column: $table.projectId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get versionNumber => $composableBuilder(
    column: $table.versionNumber,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get installedAtUtc => $composableBuilder(
    column: $table.installedAtUtc,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> dbQuestionnaireQuestionsRefs(
    Expression<bool> Function($$DbQuestionnaireQuestionsTableFilterComposer f)
    f,
  ) {
    final $$DbQuestionnaireQuestionsTableFilterComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.questionnaireVersionId,
          referencedTable: $db.dbQuestionnaireQuestions,
          getReferencedColumn: (t) => t.questionnaireVersionId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$DbQuestionnaireQuestionsTableFilterComposer(
                $db: $db,
                $table: $db.dbQuestionnaireQuestions,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }

  Expression<bool> dbQuestionnaireOptionsRefs(
    Expression<bool> Function($$DbQuestionnaireOptionsTableFilterComposer f) f,
  ) {
    final $$DbQuestionnaireOptionsTableFilterComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.questionnaireVersionId,
          referencedTable: $db.dbQuestionnaireOptions,
          getReferencedColumn: (t) => t.questionnaireVersionId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$DbQuestionnaireOptionsTableFilterComposer(
                $db: $db,
                $table: $db.dbQuestionnaireOptions,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }
}

class $$DbQuestionnaireVersionsTableOrderingComposer
    extends Composer<_$LocalDatabase, $DbQuestionnaireVersionsTable> {
  $$DbQuestionnaireVersionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get questionnaireVersionId => $composableBuilder(
    column: $table.questionnaireVersionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get projectId => $composableBuilder(
    column: $table.projectId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get versionNumber => $composableBuilder(
    column: $table.versionNumber,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get installedAtUtc => $composableBuilder(
    column: $table.installedAtUtc,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$DbQuestionnaireVersionsTableAnnotationComposer
    extends Composer<_$LocalDatabase, $DbQuestionnaireVersionsTable> {
  $$DbQuestionnaireVersionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get questionnaireVersionId => $composableBuilder(
    column: $table.questionnaireVersionId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get projectId =>
      $composableBuilder(column: $table.projectId, builder: (column) => column);

  GeneratedColumn<int> get versionNumber => $composableBuilder(
    column: $table.versionNumber,
    builder: (column) => column,
  );

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<DateTime> get installedAtUtc => $composableBuilder(
    column: $table.installedAtUtc,
    builder: (column) => column,
  );

  Expression<T> dbQuestionnaireQuestionsRefs<T extends Object>(
    Expression<T> Function($$DbQuestionnaireQuestionsTableAnnotationComposer a)
    f,
  ) {
    final $$DbQuestionnaireQuestionsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.questionnaireVersionId,
          referencedTable: $db.dbQuestionnaireQuestions,
          getReferencedColumn: (t) => t.questionnaireVersionId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$DbQuestionnaireQuestionsTableAnnotationComposer(
                $db: $db,
                $table: $db.dbQuestionnaireQuestions,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }

  Expression<T> dbQuestionnaireOptionsRefs<T extends Object>(
    Expression<T> Function($$DbQuestionnaireOptionsTableAnnotationComposer a) f,
  ) {
    final $$DbQuestionnaireOptionsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.questionnaireVersionId,
          referencedTable: $db.dbQuestionnaireOptions,
          getReferencedColumn: (t) => t.questionnaireVersionId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$DbQuestionnaireOptionsTableAnnotationComposer(
                $db: $db,
                $table: $db.dbQuestionnaireOptions,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }
}

class $$DbQuestionnaireVersionsTableTableManager
    extends
        RootTableManager<
          _$LocalDatabase,
          $DbQuestionnaireVersionsTable,
          DbQuestionnaireVersion,
          $$DbQuestionnaireVersionsTableFilterComposer,
          $$DbQuestionnaireVersionsTableOrderingComposer,
          $$DbQuestionnaireVersionsTableAnnotationComposer,
          $$DbQuestionnaireVersionsTableCreateCompanionBuilder,
          $$DbQuestionnaireVersionsTableUpdateCompanionBuilder,
          (DbQuestionnaireVersion, $$DbQuestionnaireVersionsTableReferences),
          DbQuestionnaireVersion,
          PrefetchHooks Function({
            bool dbQuestionnaireQuestionsRefs,
            bool dbQuestionnaireOptionsRefs,
          })
        > {
  $$DbQuestionnaireVersionsTableTableManager(
    _$LocalDatabase db,
    $DbQuestionnaireVersionsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DbQuestionnaireVersionsTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$DbQuestionnaireVersionsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$DbQuestionnaireVersionsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> questionnaireVersionId = const Value.absent(),
                Value<String> projectId = const Value.absent(),
                Value<int> versionNumber = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<DateTime> installedAtUtc = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DbQuestionnaireVersionsCompanion(
                questionnaireVersionId: questionnaireVersionId,
                projectId: projectId,
                versionNumber: versionNumber,
                status: status,
                installedAtUtc: installedAtUtc,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String questionnaireVersionId,
                required String projectId,
                required int versionNumber,
                required String status,
                required DateTime installedAtUtc,
                Value<int> rowid = const Value.absent(),
              }) => DbQuestionnaireVersionsCompanion.insert(
                questionnaireVersionId: questionnaireVersionId,
                projectId: projectId,
                versionNumber: versionNumber,
                status: status,
                installedAtUtc: installedAtUtc,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$DbQuestionnaireVersionsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                dbQuestionnaireQuestionsRefs = false,
                dbQuestionnaireOptionsRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (dbQuestionnaireQuestionsRefs)
                      db.dbQuestionnaireQuestions,
                    if (dbQuestionnaireOptionsRefs) db.dbQuestionnaireOptions,
                  ],
                  addJoins: null,
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (dbQuestionnaireQuestionsRefs)
                        await $_getPrefetchedData<
                          DbQuestionnaireVersion,
                          $DbQuestionnaireVersionsTable,
                          DbQuestionnaireQuestion
                        >(
                          currentTable: table,
                          referencedTable:
                              $$DbQuestionnaireVersionsTableReferences
                                  ._dbQuestionnaireQuestionsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$DbQuestionnaireVersionsTableReferences(
                                db,
                                table,
                                p0,
                              ).dbQuestionnaireQuestionsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) =>
                                    e.questionnaireVersionId ==
                                    item.questionnaireVersionId,
                              ),
                          typedResults: items,
                        ),
                      if (dbQuestionnaireOptionsRefs)
                        await $_getPrefetchedData<
                          DbQuestionnaireVersion,
                          $DbQuestionnaireVersionsTable,
                          DbQuestionnaireOption
                        >(
                          currentTable: table,
                          referencedTable:
                              $$DbQuestionnaireVersionsTableReferences
                                  ._dbQuestionnaireOptionsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$DbQuestionnaireVersionsTableReferences(
                                db,
                                table,
                                p0,
                              ).dbQuestionnaireOptionsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) =>
                                    e.questionnaireVersionId ==
                                    item.questionnaireVersionId,
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

typedef $$DbQuestionnaireVersionsTableProcessedTableManager =
    ProcessedTableManager<
      _$LocalDatabase,
      $DbQuestionnaireVersionsTable,
      DbQuestionnaireVersion,
      $$DbQuestionnaireVersionsTableFilterComposer,
      $$DbQuestionnaireVersionsTableOrderingComposer,
      $$DbQuestionnaireVersionsTableAnnotationComposer,
      $$DbQuestionnaireVersionsTableCreateCompanionBuilder,
      $$DbQuestionnaireVersionsTableUpdateCompanionBuilder,
      (DbQuestionnaireVersion, $$DbQuestionnaireVersionsTableReferences),
      DbQuestionnaireVersion,
      PrefetchHooks Function({
        bool dbQuestionnaireQuestionsRefs,
        bool dbQuestionnaireOptionsRefs,
      })
    >;
typedef $$DbQuestionnaireQuestionsTableCreateCompanionBuilder =
    DbQuestionnaireQuestionsCompanion Function({
      required String questionnaireVersionId,
      required String questionId,
      required int position,
      required String prompt,
      required String questionType,
      required bool isRequired,
      required bool allowUnknown,
      required bool allowRefused,
      required bool allowNotApplicable,
      Value<int?> minimumSelections,
      Value<int?> maximumSelections,
      Value<String?> numberKind,
      Value<String?> unit,
      Value<double?> minimum,
      Value<double?> maximum,
      Value<int?> maximumLength,
      Value<String?> displayRuleJson,
      Value<int> rowid,
    });
typedef $$DbQuestionnaireQuestionsTableUpdateCompanionBuilder =
    DbQuestionnaireQuestionsCompanion Function({
      Value<String> questionnaireVersionId,
      Value<String> questionId,
      Value<int> position,
      Value<String> prompt,
      Value<String> questionType,
      Value<bool> isRequired,
      Value<bool> allowUnknown,
      Value<bool> allowRefused,
      Value<bool> allowNotApplicable,
      Value<int?> minimumSelections,
      Value<int?> maximumSelections,
      Value<String?> numberKind,
      Value<String?> unit,
      Value<double?> minimum,
      Value<double?> maximum,
      Value<int?> maximumLength,
      Value<String?> displayRuleJson,
      Value<int> rowid,
    });

final class $$DbQuestionnaireQuestionsTableReferences
    extends
        BaseReferences<
          _$LocalDatabase,
          $DbQuestionnaireQuestionsTable,
          DbQuestionnaireQuestion
        > {
  $$DbQuestionnaireQuestionsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $DbQuestionnaireVersionsTable _questionnaireVersionIdTable(
    _$LocalDatabase db,
  ) => db.dbQuestionnaireVersions.createAlias(
    'db_questionnaire_questions__questionnaire_version_id__db_questionnaire_versions__questionnaire_version_id',
  );

  $$DbQuestionnaireVersionsTableProcessedTableManager
  get questionnaireVersionId {
    final $_column = $_itemColumn<String>('questionnaire_version_id')!;

    final manager = $$DbQuestionnaireVersionsTableTableManager(
      $_db,
      $_db.dbQuestionnaireVersions,
    ).filter((f) => f.questionnaireVersionId.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(
      _questionnaireVersionIdTable($_db),
    );
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$DbQuestionnaireQuestionsTableFilterComposer
    extends Composer<_$LocalDatabase, $DbQuestionnaireQuestionsTable> {
  $$DbQuestionnaireQuestionsTableFilterComposer({
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

  ColumnFilters<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get prompt => $composableBuilder(
    column: $table.prompt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get questionType => $composableBuilder(
    column: $table.questionType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isRequired => $composableBuilder(
    column: $table.isRequired,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get allowUnknown => $composableBuilder(
    column: $table.allowUnknown,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get allowRefused => $composableBuilder(
    column: $table.allowRefused,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get allowNotApplicable => $composableBuilder(
    column: $table.allowNotApplicable,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get minimumSelections => $composableBuilder(
    column: $table.minimumSelections,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get maximumSelections => $composableBuilder(
    column: $table.maximumSelections,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get numberKind => $composableBuilder(
    column: $table.numberKind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get unit => $composableBuilder(
    column: $table.unit,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get minimum => $composableBuilder(
    column: $table.minimum,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get maximum => $composableBuilder(
    column: $table.maximum,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get maximumLength => $composableBuilder(
    column: $table.maximumLength,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get displayRuleJson => $composableBuilder(
    column: $table.displayRuleJson,
    builder: (column) => ColumnFilters(column),
  );

  $$DbQuestionnaireVersionsTableFilterComposer get questionnaireVersionId {
    final $$DbQuestionnaireVersionsTableFilterComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.questionnaireVersionId,
          referencedTable: $db.dbQuestionnaireVersions,
          getReferencedColumn: (t) => t.questionnaireVersionId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$DbQuestionnaireVersionsTableFilterComposer(
                $db: $db,
                $table: $db.dbQuestionnaireVersions,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return composer;
  }
}

class $$DbQuestionnaireQuestionsTableOrderingComposer
    extends Composer<_$LocalDatabase, $DbQuestionnaireQuestionsTable> {
  $$DbQuestionnaireQuestionsTableOrderingComposer({
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

  ColumnOrderings<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get prompt => $composableBuilder(
    column: $table.prompt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get questionType => $composableBuilder(
    column: $table.questionType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isRequired => $composableBuilder(
    column: $table.isRequired,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get allowUnknown => $composableBuilder(
    column: $table.allowUnknown,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get allowRefused => $composableBuilder(
    column: $table.allowRefused,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get allowNotApplicable => $composableBuilder(
    column: $table.allowNotApplicable,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get minimumSelections => $composableBuilder(
    column: $table.minimumSelections,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get maximumSelections => $composableBuilder(
    column: $table.maximumSelections,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get numberKind => $composableBuilder(
    column: $table.numberKind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get unit => $composableBuilder(
    column: $table.unit,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get minimum => $composableBuilder(
    column: $table.minimum,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get maximum => $composableBuilder(
    column: $table.maximum,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get maximumLength => $composableBuilder(
    column: $table.maximumLength,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get displayRuleJson => $composableBuilder(
    column: $table.displayRuleJson,
    builder: (column) => ColumnOrderings(column),
  );

  $$DbQuestionnaireVersionsTableOrderingComposer get questionnaireVersionId {
    final $$DbQuestionnaireVersionsTableOrderingComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.questionnaireVersionId,
          referencedTable: $db.dbQuestionnaireVersions,
          getReferencedColumn: (t) => t.questionnaireVersionId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$DbQuestionnaireVersionsTableOrderingComposer(
                $db: $db,
                $table: $db.dbQuestionnaireVersions,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return composer;
  }
}

class $$DbQuestionnaireQuestionsTableAnnotationComposer
    extends Composer<_$LocalDatabase, $DbQuestionnaireQuestionsTable> {
  $$DbQuestionnaireQuestionsTableAnnotationComposer({
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

  GeneratedColumn<int> get position =>
      $composableBuilder(column: $table.position, builder: (column) => column);

  GeneratedColumn<String> get prompt =>
      $composableBuilder(column: $table.prompt, builder: (column) => column);

  GeneratedColumn<String> get questionType => $composableBuilder(
    column: $table.questionType,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isRequired => $composableBuilder(
    column: $table.isRequired,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get allowUnknown => $composableBuilder(
    column: $table.allowUnknown,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get allowRefused => $composableBuilder(
    column: $table.allowRefused,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get allowNotApplicable => $composableBuilder(
    column: $table.allowNotApplicable,
    builder: (column) => column,
  );

  GeneratedColumn<int> get minimumSelections => $composableBuilder(
    column: $table.minimumSelections,
    builder: (column) => column,
  );

  GeneratedColumn<int> get maximumSelections => $composableBuilder(
    column: $table.maximumSelections,
    builder: (column) => column,
  );

  GeneratedColumn<String> get numberKind => $composableBuilder(
    column: $table.numberKind,
    builder: (column) => column,
  );

  GeneratedColumn<String> get unit =>
      $composableBuilder(column: $table.unit, builder: (column) => column);

  GeneratedColumn<double> get minimum =>
      $composableBuilder(column: $table.minimum, builder: (column) => column);

  GeneratedColumn<double> get maximum =>
      $composableBuilder(column: $table.maximum, builder: (column) => column);

  GeneratedColumn<int> get maximumLength => $composableBuilder(
    column: $table.maximumLength,
    builder: (column) => column,
  );

  GeneratedColumn<String> get displayRuleJson => $composableBuilder(
    column: $table.displayRuleJson,
    builder: (column) => column,
  );

  $$DbQuestionnaireVersionsTableAnnotationComposer get questionnaireVersionId {
    final $$DbQuestionnaireVersionsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.questionnaireVersionId,
          referencedTable: $db.dbQuestionnaireVersions,
          getReferencedColumn: (t) => t.questionnaireVersionId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$DbQuestionnaireVersionsTableAnnotationComposer(
                $db: $db,
                $table: $db.dbQuestionnaireVersions,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return composer;
  }
}

class $$DbQuestionnaireQuestionsTableTableManager
    extends
        RootTableManager<
          _$LocalDatabase,
          $DbQuestionnaireQuestionsTable,
          DbQuestionnaireQuestion,
          $$DbQuestionnaireQuestionsTableFilterComposer,
          $$DbQuestionnaireQuestionsTableOrderingComposer,
          $$DbQuestionnaireQuestionsTableAnnotationComposer,
          $$DbQuestionnaireQuestionsTableCreateCompanionBuilder,
          $$DbQuestionnaireQuestionsTableUpdateCompanionBuilder,
          (DbQuestionnaireQuestion, $$DbQuestionnaireQuestionsTableReferences),
          DbQuestionnaireQuestion,
          PrefetchHooks Function({bool questionnaireVersionId})
        > {
  $$DbQuestionnaireQuestionsTableTableManager(
    _$LocalDatabase db,
    $DbQuestionnaireQuestionsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DbQuestionnaireQuestionsTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$DbQuestionnaireQuestionsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$DbQuestionnaireQuestionsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> questionnaireVersionId = const Value.absent(),
                Value<String> questionId = const Value.absent(),
                Value<int> position = const Value.absent(),
                Value<String> prompt = const Value.absent(),
                Value<String> questionType = const Value.absent(),
                Value<bool> isRequired = const Value.absent(),
                Value<bool> allowUnknown = const Value.absent(),
                Value<bool> allowRefused = const Value.absent(),
                Value<bool> allowNotApplicable = const Value.absent(),
                Value<int?> minimumSelections = const Value.absent(),
                Value<int?> maximumSelections = const Value.absent(),
                Value<String?> numberKind = const Value.absent(),
                Value<String?> unit = const Value.absent(),
                Value<double?> minimum = const Value.absent(),
                Value<double?> maximum = const Value.absent(),
                Value<int?> maximumLength = const Value.absent(),
                Value<String?> displayRuleJson = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DbQuestionnaireQuestionsCompanion(
                questionnaireVersionId: questionnaireVersionId,
                questionId: questionId,
                position: position,
                prompt: prompt,
                questionType: questionType,
                isRequired: isRequired,
                allowUnknown: allowUnknown,
                allowRefused: allowRefused,
                allowNotApplicable: allowNotApplicable,
                minimumSelections: minimumSelections,
                maximumSelections: maximumSelections,
                numberKind: numberKind,
                unit: unit,
                minimum: minimum,
                maximum: maximum,
                maximumLength: maximumLength,
                displayRuleJson: displayRuleJson,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String questionnaireVersionId,
                required String questionId,
                required int position,
                required String prompt,
                required String questionType,
                required bool isRequired,
                required bool allowUnknown,
                required bool allowRefused,
                required bool allowNotApplicable,
                Value<int?> minimumSelections = const Value.absent(),
                Value<int?> maximumSelections = const Value.absent(),
                Value<String?> numberKind = const Value.absent(),
                Value<String?> unit = const Value.absent(),
                Value<double?> minimum = const Value.absent(),
                Value<double?> maximum = const Value.absent(),
                Value<int?> maximumLength = const Value.absent(),
                Value<String?> displayRuleJson = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DbQuestionnaireQuestionsCompanion.insert(
                questionnaireVersionId: questionnaireVersionId,
                questionId: questionId,
                position: position,
                prompt: prompt,
                questionType: questionType,
                isRequired: isRequired,
                allowUnknown: allowUnknown,
                allowRefused: allowRefused,
                allowNotApplicable: allowNotApplicable,
                minimumSelections: minimumSelections,
                maximumSelections: maximumSelections,
                numberKind: numberKind,
                unit: unit,
                minimum: minimum,
                maximum: maximum,
                maximumLength: maximumLength,
                displayRuleJson: displayRuleJson,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$DbQuestionnaireQuestionsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({questionnaireVersionId = false}) {
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
                    if (questionnaireVersionId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.questionnaireVersionId,
                                referencedTable:
                                    $$DbQuestionnaireQuestionsTableReferences
                                        ._questionnaireVersionIdTable(db),
                                referencedColumn:
                                    $$DbQuestionnaireQuestionsTableReferences
                                        ._questionnaireVersionIdTable(db)
                                        .questionnaireVersionId,
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

typedef $$DbQuestionnaireQuestionsTableProcessedTableManager =
    ProcessedTableManager<
      _$LocalDatabase,
      $DbQuestionnaireQuestionsTable,
      DbQuestionnaireQuestion,
      $$DbQuestionnaireQuestionsTableFilterComposer,
      $$DbQuestionnaireQuestionsTableOrderingComposer,
      $$DbQuestionnaireQuestionsTableAnnotationComposer,
      $$DbQuestionnaireQuestionsTableCreateCompanionBuilder,
      $$DbQuestionnaireQuestionsTableUpdateCompanionBuilder,
      (DbQuestionnaireQuestion, $$DbQuestionnaireQuestionsTableReferences),
      DbQuestionnaireQuestion,
      PrefetchHooks Function({bool questionnaireVersionId})
    >;
typedef $$DbQuestionnaireOptionsTableCreateCompanionBuilder =
    DbQuestionnaireOptionsCompanion Function({
      required String questionnaireVersionId,
      required String questionId,
      required String optionId,
      required int position,
      required String label,
      Value<int> rowid,
    });
typedef $$DbQuestionnaireOptionsTableUpdateCompanionBuilder =
    DbQuestionnaireOptionsCompanion Function({
      Value<String> questionnaireVersionId,
      Value<String> questionId,
      Value<String> optionId,
      Value<int> position,
      Value<String> label,
      Value<int> rowid,
    });

final class $$DbQuestionnaireOptionsTableReferences
    extends
        BaseReferences<
          _$LocalDatabase,
          $DbQuestionnaireOptionsTable,
          DbQuestionnaireOption
        > {
  $$DbQuestionnaireOptionsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $DbQuestionnaireVersionsTable _questionnaireVersionIdTable(
    _$LocalDatabase db,
  ) => db.dbQuestionnaireVersions.createAlias(
    'db_questionnaire_options__questionnaire_version_id__db_questionnaire_versions__questionnaire_version_id',
  );

  $$DbQuestionnaireVersionsTableProcessedTableManager
  get questionnaireVersionId {
    final $_column = $_itemColumn<String>('questionnaire_version_id')!;

    final manager = $$DbQuestionnaireVersionsTableTableManager(
      $_db,
      $_db.dbQuestionnaireVersions,
    ).filter((f) => f.questionnaireVersionId.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(
      _questionnaireVersionIdTable($_db),
    );
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$DbQuestionnaireOptionsTableFilterComposer
    extends Composer<_$LocalDatabase, $DbQuestionnaireOptionsTable> {
  $$DbQuestionnaireOptionsTableFilterComposer({
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

  ColumnFilters<String> get optionId => $composableBuilder(
    column: $table.optionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get label => $composableBuilder(
    column: $table.label,
    builder: (column) => ColumnFilters(column),
  );

  $$DbQuestionnaireVersionsTableFilterComposer get questionnaireVersionId {
    final $$DbQuestionnaireVersionsTableFilterComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.questionnaireVersionId,
          referencedTable: $db.dbQuestionnaireVersions,
          getReferencedColumn: (t) => t.questionnaireVersionId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$DbQuestionnaireVersionsTableFilterComposer(
                $db: $db,
                $table: $db.dbQuestionnaireVersions,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return composer;
  }
}

class $$DbQuestionnaireOptionsTableOrderingComposer
    extends Composer<_$LocalDatabase, $DbQuestionnaireOptionsTable> {
  $$DbQuestionnaireOptionsTableOrderingComposer({
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

  ColumnOrderings<String> get optionId => $composableBuilder(
    column: $table.optionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get label => $composableBuilder(
    column: $table.label,
    builder: (column) => ColumnOrderings(column),
  );

  $$DbQuestionnaireVersionsTableOrderingComposer get questionnaireVersionId {
    final $$DbQuestionnaireVersionsTableOrderingComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.questionnaireVersionId,
          referencedTable: $db.dbQuestionnaireVersions,
          getReferencedColumn: (t) => t.questionnaireVersionId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$DbQuestionnaireVersionsTableOrderingComposer(
                $db: $db,
                $table: $db.dbQuestionnaireVersions,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return composer;
  }
}

class $$DbQuestionnaireOptionsTableAnnotationComposer
    extends Composer<_$LocalDatabase, $DbQuestionnaireOptionsTable> {
  $$DbQuestionnaireOptionsTableAnnotationComposer({
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

  GeneratedColumn<String> get optionId =>
      $composableBuilder(column: $table.optionId, builder: (column) => column);

  GeneratedColumn<int> get position =>
      $composableBuilder(column: $table.position, builder: (column) => column);

  GeneratedColumn<String> get label =>
      $composableBuilder(column: $table.label, builder: (column) => column);

  $$DbQuestionnaireVersionsTableAnnotationComposer get questionnaireVersionId {
    final $$DbQuestionnaireVersionsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.questionnaireVersionId,
          referencedTable: $db.dbQuestionnaireVersions,
          getReferencedColumn: (t) => t.questionnaireVersionId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$DbQuestionnaireVersionsTableAnnotationComposer(
                $db: $db,
                $table: $db.dbQuestionnaireVersions,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return composer;
  }
}

class $$DbQuestionnaireOptionsTableTableManager
    extends
        RootTableManager<
          _$LocalDatabase,
          $DbQuestionnaireOptionsTable,
          DbQuestionnaireOption,
          $$DbQuestionnaireOptionsTableFilterComposer,
          $$DbQuestionnaireOptionsTableOrderingComposer,
          $$DbQuestionnaireOptionsTableAnnotationComposer,
          $$DbQuestionnaireOptionsTableCreateCompanionBuilder,
          $$DbQuestionnaireOptionsTableUpdateCompanionBuilder,
          (DbQuestionnaireOption, $$DbQuestionnaireOptionsTableReferences),
          DbQuestionnaireOption,
          PrefetchHooks Function({bool questionnaireVersionId})
        > {
  $$DbQuestionnaireOptionsTableTableManager(
    _$LocalDatabase db,
    $DbQuestionnaireOptionsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DbQuestionnaireOptionsTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$DbQuestionnaireOptionsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$DbQuestionnaireOptionsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> questionnaireVersionId = const Value.absent(),
                Value<String> questionId = const Value.absent(),
                Value<String> optionId = const Value.absent(),
                Value<int> position = const Value.absent(),
                Value<String> label = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DbQuestionnaireOptionsCompanion(
                questionnaireVersionId: questionnaireVersionId,
                questionId: questionId,
                optionId: optionId,
                position: position,
                label: label,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String questionnaireVersionId,
                required String questionId,
                required String optionId,
                required int position,
                required String label,
                Value<int> rowid = const Value.absent(),
              }) => DbQuestionnaireOptionsCompanion.insert(
                questionnaireVersionId: questionnaireVersionId,
                questionId: questionId,
                optionId: optionId,
                position: position,
                label: label,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$DbQuestionnaireOptionsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({questionnaireVersionId = false}) {
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
                    if (questionnaireVersionId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.questionnaireVersionId,
                                referencedTable:
                                    $$DbQuestionnaireOptionsTableReferences
                                        ._questionnaireVersionIdTable(db),
                                referencedColumn:
                                    $$DbQuestionnaireOptionsTableReferences
                                        ._questionnaireVersionIdTable(db)
                                        .questionnaireVersionId,
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

typedef $$DbQuestionnaireOptionsTableProcessedTableManager =
    ProcessedTableManager<
      _$LocalDatabase,
      $DbQuestionnaireOptionsTable,
      DbQuestionnaireOption,
      $$DbQuestionnaireOptionsTableFilterComposer,
      $$DbQuestionnaireOptionsTableOrderingComposer,
      $$DbQuestionnaireOptionsTableAnnotationComposer,
      $$DbQuestionnaireOptionsTableCreateCompanionBuilder,
      $$DbQuestionnaireOptionsTableUpdateCompanionBuilder,
      (DbQuestionnaireOption, $$DbQuestionnaireOptionsTableReferences),
      DbQuestionnaireOption,
      PrefetchHooks Function({bool questionnaireVersionId})
    >;
typedef $$DbQuestionnaireDraftWorkingCopiesTableCreateCompanionBuilder =
    DbQuestionnaireDraftWorkingCopiesCompanion Function({
      required String questionnaireDraftId,
      required String projectId,
      Value<String?> sourceVersionId,
      required int baseRevision,
      required String definitionJson,
      required bool hasLocalChanges,
      required DateTime updatedAtUtc,
      Value<int> rowid,
    });
typedef $$DbQuestionnaireDraftWorkingCopiesTableUpdateCompanionBuilder =
    DbQuestionnaireDraftWorkingCopiesCompanion Function({
      Value<String> questionnaireDraftId,
      Value<String> projectId,
      Value<String?> sourceVersionId,
      Value<int> baseRevision,
      Value<String> definitionJson,
      Value<bool> hasLocalChanges,
      Value<DateTime> updatedAtUtc,
      Value<int> rowid,
    });

class $$DbQuestionnaireDraftWorkingCopiesTableFilterComposer
    extends Composer<_$LocalDatabase, $DbQuestionnaireDraftWorkingCopiesTable> {
  $$DbQuestionnaireDraftWorkingCopiesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get questionnaireDraftId => $composableBuilder(
    column: $table.questionnaireDraftId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get projectId => $composableBuilder(
    column: $table.projectId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceVersionId => $composableBuilder(
    column: $table.sourceVersionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get baseRevision => $composableBuilder(
    column: $table.baseRevision,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get definitionJson => $composableBuilder(
    column: $table.definitionJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get hasLocalChanges => $composableBuilder(
    column: $table.hasLocalChanges,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAtUtc => $composableBuilder(
    column: $table.updatedAtUtc,
    builder: (column) => ColumnFilters(column),
  );
}

class $$DbQuestionnaireDraftWorkingCopiesTableOrderingComposer
    extends Composer<_$LocalDatabase, $DbQuestionnaireDraftWorkingCopiesTable> {
  $$DbQuestionnaireDraftWorkingCopiesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get questionnaireDraftId => $composableBuilder(
    column: $table.questionnaireDraftId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get projectId => $composableBuilder(
    column: $table.projectId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceVersionId => $composableBuilder(
    column: $table.sourceVersionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get baseRevision => $composableBuilder(
    column: $table.baseRevision,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get definitionJson => $composableBuilder(
    column: $table.definitionJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get hasLocalChanges => $composableBuilder(
    column: $table.hasLocalChanges,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAtUtc => $composableBuilder(
    column: $table.updatedAtUtc,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$DbQuestionnaireDraftWorkingCopiesTableAnnotationComposer
    extends Composer<_$LocalDatabase, $DbQuestionnaireDraftWorkingCopiesTable> {
  $$DbQuestionnaireDraftWorkingCopiesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get questionnaireDraftId => $composableBuilder(
    column: $table.questionnaireDraftId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get projectId =>
      $composableBuilder(column: $table.projectId, builder: (column) => column);

  GeneratedColumn<String> get sourceVersionId => $composableBuilder(
    column: $table.sourceVersionId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get baseRevision => $composableBuilder(
    column: $table.baseRevision,
    builder: (column) => column,
  );

  GeneratedColumn<String> get definitionJson => $composableBuilder(
    column: $table.definitionJson,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get hasLocalChanges => $composableBuilder(
    column: $table.hasLocalChanges,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get updatedAtUtc => $composableBuilder(
    column: $table.updatedAtUtc,
    builder: (column) => column,
  );
}

class $$DbQuestionnaireDraftWorkingCopiesTableTableManager
    extends
        RootTableManager<
          _$LocalDatabase,
          $DbQuestionnaireDraftWorkingCopiesTable,
          DbQuestionnaireDraftWorkingCopy,
          $$DbQuestionnaireDraftWorkingCopiesTableFilterComposer,
          $$DbQuestionnaireDraftWorkingCopiesTableOrderingComposer,
          $$DbQuestionnaireDraftWorkingCopiesTableAnnotationComposer,
          $$DbQuestionnaireDraftWorkingCopiesTableCreateCompanionBuilder,
          $$DbQuestionnaireDraftWorkingCopiesTableUpdateCompanionBuilder,
          (
            DbQuestionnaireDraftWorkingCopy,
            BaseReferences<
              _$LocalDatabase,
              $DbQuestionnaireDraftWorkingCopiesTable,
              DbQuestionnaireDraftWorkingCopy
            >,
          ),
          DbQuestionnaireDraftWorkingCopy,
          PrefetchHooks Function()
        > {
  $$DbQuestionnaireDraftWorkingCopiesTableTableManager(
    _$LocalDatabase db,
    $DbQuestionnaireDraftWorkingCopiesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DbQuestionnaireDraftWorkingCopiesTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$DbQuestionnaireDraftWorkingCopiesTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$DbQuestionnaireDraftWorkingCopiesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> questionnaireDraftId = const Value.absent(),
                Value<String> projectId = const Value.absent(),
                Value<String?> sourceVersionId = const Value.absent(),
                Value<int> baseRevision = const Value.absent(),
                Value<String> definitionJson = const Value.absent(),
                Value<bool> hasLocalChanges = const Value.absent(),
                Value<DateTime> updatedAtUtc = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DbQuestionnaireDraftWorkingCopiesCompanion(
                questionnaireDraftId: questionnaireDraftId,
                projectId: projectId,
                sourceVersionId: sourceVersionId,
                baseRevision: baseRevision,
                definitionJson: definitionJson,
                hasLocalChanges: hasLocalChanges,
                updatedAtUtc: updatedAtUtc,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String questionnaireDraftId,
                required String projectId,
                Value<String?> sourceVersionId = const Value.absent(),
                required int baseRevision,
                required String definitionJson,
                required bool hasLocalChanges,
                required DateTime updatedAtUtc,
                Value<int> rowid = const Value.absent(),
              }) => DbQuestionnaireDraftWorkingCopiesCompanion.insert(
                questionnaireDraftId: questionnaireDraftId,
                projectId: projectId,
                sourceVersionId: sourceVersionId,
                baseRevision: baseRevision,
                definitionJson: definitionJson,
                hasLocalChanges: hasLocalChanges,
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

typedef $$DbQuestionnaireDraftWorkingCopiesTableProcessedTableManager =
    ProcessedTableManager<
      _$LocalDatabase,
      $DbQuestionnaireDraftWorkingCopiesTable,
      DbQuestionnaireDraftWorkingCopy,
      $$DbQuestionnaireDraftWorkingCopiesTableFilterComposer,
      $$DbQuestionnaireDraftWorkingCopiesTableOrderingComposer,
      $$DbQuestionnaireDraftWorkingCopiesTableAnnotationComposer,
      $$DbQuestionnaireDraftWorkingCopiesTableCreateCompanionBuilder,
      $$DbQuestionnaireDraftWorkingCopiesTableUpdateCompanionBuilder,
      (
        DbQuestionnaireDraftWorkingCopy,
        BaseReferences<
          _$LocalDatabase,
          $DbQuestionnaireDraftWorkingCopiesTable,
          DbQuestionnaireDraftWorkingCopy
        >,
      ),
      DbQuestionnaireDraftWorkingCopy,
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
  $$DbContactAttemptsTableTableManager get dbContactAttempts =>
      $$DbContactAttemptsTableTableManager(_db, _db.dbContactAttempts);
  $$DbContactRevisionsTableTableManager get dbContactRevisions =>
      $$DbContactRevisionsTableTableManager(_db, _db.dbContactRevisions);
  $$DbContactAnswersTableTableManager get dbContactAnswers =>
      $$DbContactAnswersTableTableManager(_db, _db.dbContactAnswers);
  $$DbContactRevisionConflictsTableTableManager
  get dbContactRevisionConflicts =>
      $$DbContactRevisionConflictsTableTableManager(
        _db,
        _db.dbContactRevisionConflicts,
      );
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
  $$DbCanonicalRegionVersionsTableTableManager get dbCanonicalRegionVersions =>
      $$DbCanonicalRegionVersionsTableTableManager(
        _db,
        _db.dbCanonicalRegionVersions,
      );
  $$DbContactRegionAssignmentsTableTableManager
  get dbContactRegionAssignments =>
      $$DbContactRegionAssignmentsTableTableManager(
        _db,
        _db.dbContactRegionAssignments,
      );
  $$DbDraftRegionAssignmentsTableTableManager get dbDraftRegionAssignments =>
      $$DbDraftRegionAssignmentsTableTableManager(
        _db,
        _db.dbDraftRegionAssignments,
      );
  $$DbQuestionnaireVersionsTableTableManager get dbQuestionnaireVersions =>
      $$DbQuestionnaireVersionsTableTableManager(
        _db,
        _db.dbQuestionnaireVersions,
      );
  $$DbQuestionnaireQuestionsTableTableManager get dbQuestionnaireQuestions =>
      $$DbQuestionnaireQuestionsTableTableManager(
        _db,
        _db.dbQuestionnaireQuestions,
      );
  $$DbQuestionnaireOptionsTableTableManager get dbQuestionnaireOptions =>
      $$DbQuestionnaireOptionsTableTableManager(
        _db,
        _db.dbQuestionnaireOptions,
      );
  $$DbQuestionnaireDraftWorkingCopiesTableTableManager
  get dbQuestionnaireDraftWorkingCopies =>
      $$DbQuestionnaireDraftWorkingCopiesTableTableManager(
        _db,
        _db.dbQuestionnaireDraftWorkingCopies,
      );
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
