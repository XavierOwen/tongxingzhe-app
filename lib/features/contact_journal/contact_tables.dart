import 'package:drift/drift.dart';

/// 尚未正式提交、只对创建者可见的接触草稿。
///
/// 草稿允许核心字段暂时为空，因为它保存的是填写过程，不是正式接触事实。
/// 项目和问卷版本在创建时固定，避免后续发布悄悄改变旧草稿的解释。
@TableIndex(
  name: 'contact_drafts_owner_updated',
  columns: {#appUserId, #abandonedAtUtc, #updatedAtUtc},
)
class DbContactDrafts extends Table {
  TextColumn get draftId => text()();
  TextColumn get appUserId => text()();
  TextColumn get workspaceId => text()();
  TextColumn get projectId => text()();
  TextColumn get questionnaireVersionId => text()();
  DateTimeColumn get createdAtUtc => dateTime()();
  DateTimeColumn get updatedAtUtc => dateTime()();
  DateTimeColumn get occurredAtUtc => dateTime().nullable()();
  TextColumn get occurredTimeZone => text().nullable()();
  TextColumn get channel => text().nullable()();
  TextColumn get channelDetail => text().nullable()();
  TextColumn get locationKind => text().nullable()();
  TextColumn get placeName => text().nullable()();
  TextColumn get smallestRegionId => text().nullable()();
  TextColumn get regionTreeVersion => text().nullable()();
  RealColumn get latitude => real().nullable()();
  RealColumn get longitude => real().nullable()();
  RealColumn get locationAccuracyMeters => real().nullable()();
  IntColumn get reachCount => integer().nullable()();
  IntColumn get interestLevel => integer().nullable()();
  TextColumn get syncMode =>
      text().withDefault(const Constant('account_private'))();
  IntColumn get localRevision => integer().withDefault(const Constant(1))();
  IntColumn get serverRevision => integer().withDefault(const Constant(0))();
  TextColumn get sourceAttemptId => text().nullable()();
  TextColumn get conflictOfDraftId => text().nullable()();
  DateTimeColumn get abandonedAtUtc => dateTime().nullable()();
  DateTimeColumn get undoUntilUtc => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {draftId};

  @override
  List<String> get customConstraints => const [
    'CHECK (length(trim(app_user_id)) > 0)',
    'CHECK (length(trim(workspace_id)) > 0)',
    'CHECK (length(trim(project_id)) > 0)',
    'CHECK (length(trim(questionnaire_version_id)) > 0)',
    'CHECK (updated_at_utc >= created_at_utc)',
    'CHECK ((occurred_at_utc IS NULL AND occurred_time_zone IS NULL) OR '
        '(occurred_at_utc IS NOT NULL AND occurred_time_zone IS NOT NULL '
        'AND length(trim(occurred_time_zone)) > 0))',
    "CHECK (channel IS NULL OR channel IN ('face_to_face', 'voice_call', "
        "'video_call', 'instant_text', 'asynchronous_message', 'mixed', "
        "'other_direct'))",
    "CHECK ((location_kind IS NULL AND place_name IS NULL AND "
        'smallest_region_id IS NULL AND region_tree_version IS NULL AND '
        'latitude IS NULL AND '
        'longitude IS NULL AND location_accuracy_meters IS NULL) OR '
        "(location_kind = 'resolved' AND place_name IS NOT NULL AND "
        'length(trim(place_name)) > 0 AND smallest_region_id IS NOT NULL '
        'AND length(trim(smallest_region_id)) > 0 '
        'AND region_tree_version IS NOT NULL '
        'AND length(trim(region_tree_version)) > 0 AND latitude IS NULL '
        'AND longitude IS NULL AND location_accuracy_meters IS NULL) OR '
        "(location_kind = 'not_applicable' AND place_name IS NULL AND "
        'smallest_region_id IS NULL AND region_tree_version IS NULL '
        'AND latitude IS NULL AND '
        'longitude IS NULL AND location_accuracy_meters IS NULL) OR '
        "(location_kind = 'pending_resolution' AND place_name IS NULL AND "
        'smallest_region_id IS NULL AND region_tree_version IS NULL '
        'AND latitude BETWEEN -90 AND 90 AND '
        'longitude BETWEEN -180 AND 180 AND '
        '(location_accuracy_meters IS NULL OR '
        'location_accuracy_meters >= 0)))',
    'CHECK (reach_count IS NULL OR reach_count > 0)',
    'CHECK (interest_level IS NULL OR interest_level BETWEEN 0 AND 4)',
    "CHECK (sync_mode IN ('account_private', 'device_only'))",
    'CHECK (local_revision > 0)',
    'CHECK (server_revision >= 0)',
    'CHECK (source_attempt_id IS NULL OR '
        'length(trim(source_attempt_id)) > 0)',
    'CHECK (conflict_of_draft_id IS NULL OR '
        'length(trim(conflict_of_draft_id)) > 0)',
    'CHECK ((abandoned_at_utc IS NULL AND undo_until_utc IS NULL) OR '
        '(abandoned_at_utc IS NOT NULL AND undo_until_utc IS NOT NULL AND '
        'undo_until_utc >= abandoned_at_utc))',
  ];
}

/// 草稿中的类型化问卷回答。
///
/// 它与已提交答案分表保存，使草稿不会进入接触事实或分析查询。每次自动保存
/// 会在同一 transaction 内用当前表单快照替换这些行。
class DbContactDraftAnswers extends Table {
  TextColumn get draftId => text().references(DbContactDrafts, #draftId)();
  TextColumn get questionId => text()();
  TextColumn get answerState => text()();
  TextColumn get answerType => text()();
  BoolColumn get booleanValue => boolean().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {draftId, questionId};

  @override
  List<String> get customConstraints => const [
    'CHECK (length(trim(question_id)) > 0)',
    "CHECK (answer_type = 'boolean' AND "
        "((answer_state = 'answered' AND boolean_value IS NOT NULL) OR "
        "(answer_state IN ('unknown', 'refused', 'not_applicable', "
        "'unanswered') AND boolean_value IS NULL)))",
  ];
}

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
  TextColumn get regionTreeVersion => text().nullable()();
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
        'length(trim(smallest_region_id)) > 0 AND '
        'region_tree_version IS NOT NULL AND '
        'length(trim(region_tree_version)) > 0) OR '
        "(location_kind = 'not_applicable' AND place_name IS NULL AND "
        'smallest_region_id IS NULL AND region_tree_version IS NULL AND '
        'latitude IS NULL AND '
        'longitude IS NULL AND location_accuracy_meters IS NULL) OR '
        "(location_kind = 'pending_resolution' AND "
        'smallest_region_id IS NULL AND region_tree_version IS NULL AND '
        'latitude BETWEEN -90 AND 90 AND '
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

/// 针对明确对象发起、但没有获得回应的直接联络。
///
/// 尝试与接触分表，因此它没有触达人数、兴趣或问卷答案列，统计 SQL 也无法
/// 把它误当作已发生互动。后来发生的接触只通过可选外键关联，不改写本行。
@TableIndex(
  name: 'contact_attempts_personal_period',
  columns: {#appUserId, #workspaceId, #projectId, #occurredAtUtc},
)
class DbContactAttempts extends Table {
  TextColumn get attemptId => text()();
  TextColumn get appUserId => text()();
  TextColumn get workspaceId => text()();
  TextColumn get projectId => text()();
  DateTimeColumn get occurredAtUtc => dateTime()();
  TextColumn get occurredTimeZone => text()();
  DateTimeColumn get firstSubmittedAtUtc => dateTime()();
  TextColumn get channel => text()();
  TextColumn get channelDetail => text().nullable()();
  TextColumn get linkedContactId =>
      text().nullable().references(DbContactRecords, #contactId)();

  @override
  Set<Column<Object>> get primaryKey => {attemptId};

  @override
  List<String> get customConstraints => const [
    'CHECK (length(trim(app_user_id)) > 0)',
    'CHECK (length(trim(workspace_id)) > 0)',
    'CHECK (length(trim(project_id)) > 0)',
    'CHECK (length(trim(occurred_time_zone)) > 0)',
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
  TextColumn get revisionKind =>
      text().withDefault(const Constant('submitted'))();
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
  TextColumn get regionTreeVersion => text().nullable()();
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
    "CHECK (revision_kind IN ('submitted', 'corrected', 'voided'))",
    "CHECK ((revision_number = 1 AND revision_kind = 'submitted' "
        'AND reason IS NULL) OR (revision_number > 1 '
        "AND revision_kind IN ('corrected', 'voided') "
        'AND reason IS NOT NULL AND length(trim(reason)) > 0))',
    'CHECK (reach_count > 0)',
    'CHECK (interest_level BETWEEN 0 AND 4)',
    "CHECK ((location_kind = 'resolved' AND "
        'place_name IS NOT NULL AND length(trim(place_name)) > 0 AND '
        'smallest_region_id IS NOT NULL AND '
        'length(trim(smallest_region_id)) > 0 AND '
        'region_tree_version IS NOT NULL AND '
        'length(trim(region_tree_version)) > 0) OR '
        "(location_kind = 'not_applicable' AND place_name IS NULL AND "
        'smallest_region_id IS NULL AND region_tree_version IS NULL AND '
        'latitude IS NULL AND '
        'longitude IS NULL AND location_accuracy_meters IS NULL) OR '
        "(location_kind = 'pending_resolution' AND "
        'smallest_region_id IS NULL AND region_tree_version IS NULL AND '
        'latitude BETWEEN -90 AND 90 AND '
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
  TextColumn get appUserId => text().nullable()();
  TextColumn get workspaceId => text().nullable()();
  TextColumn get projectId => text().nullable()();
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
    'CHECK ((app_user_id IS NULL AND workspace_id IS NULL AND '
        'project_id IS NULL) OR (app_user_id IS NOT NULL AND '
        'length(trim(app_user_id)) > 0 AND workspace_id IS NOT NULL AND '
        'length(trim(workspace_id)) > 0 AND project_id IS NOT NULL AND '
        'length(trim(project_id)) > 0))',
  ];
}

/// 同字段跨设备修订的本机持久比较资料。
///
/// 健康状态只从 Outbox 读取数量和错误码，不读取这里的业务快照。
@TableIndex(
  name: 'contact_revision_conflicts_owner_contact',
  columns: {#appUserId, #contactId, #status},
)
class DbContactRevisionConflicts extends Table {
  TextColumn get conflictId => text()();
  TextColumn get commandId => text().unique()();
  TextColumn get contactId => text().references(DbContactRecords, #contactId)();
  TextColumn get appUserId => text()();
  TextColumn get workspaceId => text()();
  TextColumn get projectId => text()();
  IntColumn get baseRevision => integer()();
  IntColumn get currentRevision => integer()();
  TextColumn get conflictingFieldsJson => text()();
  TextColumn get questionnaireVersionId => text()();
  TextColumn get currentRevisionKind => text()();
  DateTimeColumn get currentRevisedAtUtc => dateTime()();
  TextColumn get currentReason => text()();
  TextColumn get currentSnapshotJson => text()();
  TextColumn get proposedSnapshotJson => text()();
  TextColumn get status => text().withDefault(const Constant('pending'))();
  TextColumn get resolutionCommandId => text().nullable()();
  DateTimeColumn get createdAtUtc => dateTime()();
  DateTimeColumn get resolvedAtUtc => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {conflictId};

  @override
  List<String> get customConstraints => const [
    'CHECK (base_revision > 0 AND current_revision > base_revision)',
    "CHECK (current_revision_kind = 'corrected')",
    "CHECK (status IN ('pending', 'resolution_pending', 'resolved'))",
    "CHECK ((status = 'pending' AND resolution_command_id IS NULL "
        'AND resolved_at_utc IS NULL) OR '
        "(status = 'resolution_pending' AND resolution_command_id IS NOT NULL "
        'AND resolved_at_utc IS NULL) OR '
        "(status = 'resolved' AND resolution_command_id IS NOT NULL "
        'AND resolved_at_utc IS NOT NULL))',
  ];
}
