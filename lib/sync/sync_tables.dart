import 'package:drift/drift.dart';

/// 跨进程和 Web 多标签共享的同步执行租约。
///
/// 表中只在持有租约时存在一行。数据库 transaction 决定谁能插入或替换过期
/// 行，因此进程内 mutex 不是正确性边界。
class DbSyncDrainerLeases extends Table {
  TextColumn get leaseName => text()();
  TextColumn get leaseOwner => text()();
  DateTimeColumn get leaseExpiresAtUtc => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {leaseName};

  @override
  List<String> get customConstraints => const [
    'CHECK (length(trim(lease_name)) > 0)',
    'CHECK (length(trim(lease_owner)) > 0)',
  ];
}

/// 一个内部用户在一个推广项目上的远端同步进度。
///
/// Cursor 是 Backend 生成的不透明字符串。Flutter 只能保存和回传它，不能
/// 解析其中的顺序或时间含义。
class DbSyncScopes extends Table {
  TextColumn get appUserId => text()();
  TextColumn get workspaceId => text()();
  TextColumn get projectId => text()();
  TextColumn get serverCursor => text().nullable()();
  DateTimeColumn get lastSuccessAtUtc => dateTime().nullable()();
  TextColumn get lastFailureCode => text().nullable()();
  DateTimeColumn get updatedAtUtc => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {appUserId, workspaceId, projectId};

  @override
  List<String> get customConstraints => const [
    'CHECK (length(trim(app_user_id)) > 0)',
    'CHECK (length(trim(workspace_id)) > 0)',
    'CHECK (length(trim(project_id)) > 0)',
    'CHECK (server_cursor IS NULL OR length(server_cursor) > 0)',
    'CHECK (last_failure_code IS NULL OR '
        'length(trim(last_failure_code)) > 0)',
  ];
}
