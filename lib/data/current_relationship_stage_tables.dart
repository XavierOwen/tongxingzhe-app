import 'package:drift/drift.dart';

/// 当前个人范围内，一个仍在跟进的“推广对象 × 项目”关系投影。
///
/// 这里只保存分析所需的稳定对象键、阶段和 revision 证据；姓名、联系方式、
/// 备注及 PII vault 内容不能进入此表。
@TableIndex(
  name: 'current_relationship_stage_scope_stage',
  columns: {#appUserId, #workspaceId, #projectId, #relationshipStage},
)
class DbCurrentRelationshipStageProjections extends Table {
  TextColumn get appUserId => text()();
  TextColumn get workspaceId => text()();
  TextColumn get projectId => text()();
  TextColumn get targetKey => text()();
  IntColumn get relationshipStage => integer()();
  IntColumn get relationshipRevision => integer()();
  DateTimeColumn get relationshipUpdatedAtUtc => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {
    appUserId,
    workspaceId,
    projectId,
    targetKey,
  };

  @override
  List<String> get customConstraints => const [
    'CHECK (length(trim(app_user_id)) > 0)',
    'CHECK (length(trim(workspace_id)) > 0)',
    'CHECK (length(trim(project_id)) > 0)',
    'CHECK (length(trim(target_key)) > 0)',
    'CHECK (relationship_stage BETWEEN 0 AND 4)',
    'CHECK (relationship_revision > 0)',
  ];
}

/// 一个个人项目范围最近成功安装的完整当前关系快照。
///
/// 元数据与投影行在同一事务中替换。零行快照仍保留此行，使“有效空结果”与
/// “从未取得快照”保持可区分。
class DbCurrentRelationshipStageSnapshots extends Table {
  TextColumn get appUserId => text()();
  TextColumn get workspaceId => text()();
  TextColumn get projectId => text()();
  DateTimeColumn get snapshotAsOfUtc => dateTime()();
  DateTimeColumn get sourceCutoffUtc => dateTime()();
  DateTimeColumn get authorizedAtUtc => dateTime()();
  DateTimeColumn get lastSuccessfulSyncAtUtc => dateTime()();
  IntColumn get totalCount => integer()();
  IntColumn get pendingSyncCount => integer()();

  @override
  Set<Column<Object>> get primaryKey => {appUserId, workspaceId, projectId};

  @override
  List<String> get customConstraints => const [
    'CHECK (length(trim(app_user_id)) > 0)',
    'CHECK (length(trim(workspace_id)) > 0)',
    'CHECK (length(trim(project_id)) > 0)',
    'CHECK (total_count >= 0)',
    'CHECK (pending_sync_count >= 0 AND pending_sync_count <= total_count)',
  ];
}
