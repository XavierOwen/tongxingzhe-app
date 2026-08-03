import 'package:drift/drift.dart';

/// 已提交接触的当前有效投影。
///
/// 核心字段保持类型化，便于 SQLite 直接筛选和统计；姓名、电话、邮箱等 PII
/// 不属于这张表。历史值另存于 [DbContactRevisions]，不能覆盖后消失。
@TableIndex(
  name: 'contact_records_personal_period',
  columns: {#appUserId, #workspaceId, #projectId, #occurredAtUtc},
)
class DbContactRecords extends Table {
  TextColumn get contactId => text()();
  TextColumn get appUserId => text()();
  TextColumn get workspaceId => text()();
  TextColumn get projectId => text()();
  TextColumn get questionnaireVersionId => text()();
  DateTimeColumn get occurredAtUtc => dateTime()();
  TextColumn get occurredTimeZone => text()();
  DateTimeColumn get firstSubmittedAtUtc => dateTime()();
  TextColumn get channel => text()();
  TextColumn get channelDetail => text().nullable()();
  TextColumn get locationKind => text()();
  TextColumn get placeName => text().nullable()();
  TextColumn get smallestRegionId => text().nullable()();
  RealColumn get latitude => real().nullable()();
  RealColumn get longitude => real().nullable()();
  RealColumn get locationAccuracyMeters => real().nullable()();
  IntColumn get reachCount => integer()();
  IntColumn get interestLevel => integer()();
  IntColumn get currentRevision => integer()();
  TextColumn get lifecycleStatus => text()();

  @override
  Set<Column<Object>> get primaryKey => {contactId};

  @override
  List<String> get customConstraints => const [
    "CHECK ((location_kind = 'resolved' AND "
        'place_name IS NOT NULL AND length(trim(place_name)) > 0 AND '
        'smallest_region_id IS NOT NULL AND '
        'length(trim(smallest_region_id)) > 0) OR '
        "(location_kind = 'not_applicable' AND place_name IS NULL AND "
        'smallest_region_id IS NULL AND latitude IS NULL AND '
        'longitude IS NULL AND location_accuracy_meters IS NULL) OR '
        "(location_kind = 'pending_resolution' AND "
        'smallest_region_id IS NULL AND latitude BETWEEN -90 AND 90 AND '
        'longitude BETWEEN -180 AND 180 AND '
        '(location_accuracy_meters IS NULL OR '
        'location_accuracy_meters >= 0)))',
    "CHECK (lifecycle_status IN ('active', 'voided'))",
    'CHECK (reach_count > 0)',
    'CHECK (interest_level BETWEEN 0 AND 4)',
    'CHECK (current_revision > 0)',
    "CHECK (channel IN ('face_to_face', 'voice_call', 'video_call', "
        "'instant_text', 'asynchronous_message', 'mixed', "
        "'other_direct'))",
    "CHECK (channel != 'other_direct' OR "
        '(channel_detail IS NOT NULL AND '
        'length(trim(channel_detail)) > 0))',
  ];
}

/// 已提交接触的追加式修订历史。
///
/// 第一版提交也写入 revision 1；后续更正只追加新行，再更新当前投影。
class DbContactRevisions extends Table {
  TextColumn get revisionId => text()();
  TextColumn get contactId => text().references(DbContactRecords, #contactId)();
  IntColumn get revisionNumber => integer()();
  TextColumn get revisedByAppUserId => text()();
  DateTimeColumn get revisedAtUtc => dateTime()();
  TextColumn get reason => text().nullable()();
  DateTimeColumn get occurredAtUtc => dateTime()();
  TextColumn get occurredTimeZone => text()();
  TextColumn get channel => text()();
  TextColumn get channelDetail => text().nullable()();
  TextColumn get locationKind => text()();
  TextColumn get placeName => text().nullable()();
  TextColumn get smallestRegionId => text().nullable()();
  RealColumn get latitude => real().nullable()();
  RealColumn get longitude => real().nullable()();
  RealColumn get locationAccuracyMeters => real().nullable()();
  IntColumn get reachCount => integer()();
  IntColumn get interestLevel => integer()();

  @override
  Set<Column<Object>> get primaryKey => {revisionId};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {contactId, revisionNumber},
  ];

  @override
  List<String> get customConstraints => const [
    'CHECK (revision_number > 0)',
    'CHECK (reach_count > 0)',
    'CHECK (interest_level BETWEEN 0 AND 4)',
    "CHECK ((location_kind = 'resolved' AND "
        'place_name IS NOT NULL AND length(trim(place_name)) > 0 AND '
        'smallest_region_id IS NOT NULL AND '
        'length(trim(smallest_region_id)) > 0) OR '
        "(location_kind = 'not_applicable' AND place_name IS NULL AND "
        'smallest_region_id IS NULL AND latitude IS NULL AND '
        'longitude IS NULL AND location_accuracy_meters IS NULL) OR '
        "(location_kind = 'pending_resolution' AND "
        'smallest_region_id IS NULL AND latitude BETWEEN -90 AND 90 AND '
        'longitude BETWEEN -180 AND 180 AND '
        '(location_accuracy_meters IS NULL OR '
        'location_accuracy_meters >= 0)))',
    "CHECK (channel IN ('face_to_face', 'voice_call', 'video_call', "
        "'instant_text', 'asynchronous_message', 'mixed', "
        "'other_direct'))",
    "CHECK (channel != 'other_direct' OR "
        '(channel_detail IS NOT NULL AND '
        'length(trim(channel_detail)) > 0))',
  ];
}

/// 某个接触 revision 对场景问卷的类型化回答。
///
/// Slice 1A 先实现是／否题；后续题型通过独立值列和 CHECK 扩展，不改变既有
/// 布尔答案的语义。
class DbContactAnswers extends Table {
  TextColumn get contactId => text().references(DbContactRecords, #contactId)();
  IntColumn get revisionNumber => integer()();
  TextColumn get questionId => text()();
  TextColumn get answerState => text()();
  TextColumn get answerType => text()();
  BoolColumn get booleanValue => boolean().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {contactId, revisionNumber, questionId};

  @override
  List<String> get customConstraints => const [
    'CHECK (revision_number > 0)',
    'CHECK (length(trim(question_id)) > 0)',
    "CHECK (answer_type = 'boolean' AND "
        "((answer_state = 'answered' AND boolean_value IS NOT NULL) OR "
        "(answer_state IN ('unknown', 'refused', 'not_applicable', "
        "'unanswered') AND boolean_value IS NULL)))",
  ];
}

/// 设备重启后仍然存在的同步命令。
///
/// Slice 1A 只创建 `pending` 命令；领取、租约和 ACK 状态机在后续检查点通过
/// 同一张表实现，不把队列状态藏在页面内存中。
@TableIndex(
  name: 'sync_outbox_ready',
  columns: {#status, #nextAttemptAtUtc, #createdAtUtc},
)
@TableIndex(
  name: 'sync_outbox_aggregate_order',
  columns: {#aggregateId, #createdAtUtc},
)
class DbSyncOutbox extends Table {
  TextColumn get commandId => text()();
  IntColumn get protocolVersion => integer()();
  TextColumn get commandType => text()();
  TextColumn get deviceId => text()();
  TextColumn get aggregateId => text()();
  IntColumn get baseRevision => integer()();
  TextColumn get payloadJson => text()();
  DateTimeColumn get createdAtUtc => dateTime()();
  TextColumn get status => text()();
  IntColumn get attemptCount => integer().withDefault(const Constant(0))();
  DateTimeColumn get nextAttemptAtUtc => dateTime()();
  TextColumn get leaseOwner => text().nullable()();
  DateTimeColumn get leaseExpiresAtUtc => dateTime().nullable()();
  TextColumn get lastFailureCode => text().nullable()();
  DateTimeColumn get completedAtUtc => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {commandId};

  @override
  List<String> get customConstraints => const [
    "CHECK (status IN ('pending', 'leased', 'needs_resolution', "
        "'permanent_failure', 'completed'))",
    'CHECK (attempt_count >= 0)',
    'CHECK (protocol_version > 0 AND base_revision >= 0)',
  ];
}
