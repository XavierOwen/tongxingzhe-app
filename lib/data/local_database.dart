import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import '../features/contact_journal/contact_tables.dart';
import '../regions/region_tables.dart';
import '../sync/sync_tables.dart';

part 'local_database.g.dart';

class DbUsers extends Table {
  TextColumn get userId => text()();
  TextColumn get username => text().unique()();
  TextColumn get displayName => text()();
  TextColumn get email => text()();
  TextColumn get phone => text()();
  DateTimeColumn get birthday => dateTime().nullable()();
  TextColumn get gender => text().withDefault(const Constant('unknown'))();
  TextColumn get occupation => text().withDefault(const Constant(''))();
  TextColumn get contactJson => text().withDefault(const Constant('{}'))();
  IntColumn get roleLevel => integer()();
  TextColumn get cityNamesJson => text()();
  TextColumn get teamName => text()();
  TextColumn get passwordMd5 => text()();
  TextColumn get status => text()();
  IntColumn get failedLoginCount => integer().withDefault(const Constant(0))();
  BoolColumn get mustChangePassword =>
      boolean().withDefault(const Constant(false))();
  DateTimeColumn get lockedUntil => dateTime().nullable()();
  DateTimeColumn get lastSeenAt => dateTime().nullable()();
  DateTimeColumn get lastFailedLoginAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {userId};
}

class DbConversationRecords extends Table {
  // Drift table classes describe the SQLite schema in Dart. A useful rule:
  // keep columns for fields you need to filter, chart, permission-check, or
  // sync. Avoid storing sensitive free text unless the product really needs it.
  TextColumn get recordId => text()();
  DateTimeColumn get createdAt => dateTime()();
  TextColumn get collectorUserId => text()();
  TextColumn get cityName => text()();
  TextColumn get areaName => text().withDefault(const Constant('unassigned'))();
  TextColumn get teamName => text()();
  TextColumn get recorderName => text()();
  TextColumn get personName => text()();
  TextColumn get englishName => text()();
  RealColumn get averageHeartRate => real().nullable()();
  RealColumn get latitude => real().nullable()();
  RealColumn get longitude => real().nullable()();
  RealColumn get locationAccuracyMeters => real().nullable()();
  TextColumn get locationError => text().nullable()();
  TextColumn get manualPlaceName => text()();
  TextColumn get gender => text()();
  TextColumn get identity => text()();
  TextColumn get ageRange => text()();
  IntColumn get relationshipLevel => integer().withDefault(const Constant(1))();
  IntColumn get interestLevel => integer().withDefault(const Constant(2))();
  IntColumn get attitudeLevel => integer()();
  // `notes` remains the only optional narrative field. The separate prayer
  // sentence field was removed in schema v5 so new records never write it.
  TextColumn get notes => text()();
  BoolColumn get isLocationVerified =>
      boolean().withDefault(const Constant(false))();
  RealColumn get correctedLatitude => real().nullable()();
  RealColumn get correctedLongitude => real().nullable()();
  TextColumn get correctedPlaceName => text().nullable()();
  DateTimeColumn get correctedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {recordId};
}

class DbRecordContacts extends Table {
  TextColumn get contactId => text()();
  TextColumn get recordId => text()();
  TextColumn get channel => text()();
  TextColumn get value => text()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {contactId};
}

class DbAppSettings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column<Object>> get primaryKey => {key};
}

class DbSecurityEvents extends Table {
  TextColumn get eventId => text()();
  TextColumn get userId => text().nullable()();
  TextColumn get eventType => text()();
  TextColumn get eventDetailJson => text()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {eventId};
}

@DriftDatabase(
  include: {
    'package:tongxingzhe_app/features/contact_journal/contact_queries.drift',
    'package:tongxingzhe_app/sync/sync_queries.drift',
  },
  tables: [
    DbUsers,
    DbConversationRecords,
    DbRecordContacts,
    DbAppSettings,
    DbSecurityEvents,
    DbContactRecords,
    DbContactAttempts,
    DbContactRevisions,
    DbContactAnswers,
    DbSyncOutbox,
    DbContactDrafts,
    DbContactDraftAnswers,
    DbSyncDrainerLeases,
    DbSyncScopes,
    DbCanonicalRegionVersions,
    DbContactRegionAssignments,
    DbDraftRegionAssignments,
  ],
)
class LocalDatabase extends _$LocalDatabase {
  LocalDatabase(super.executor);

  LocalDatabase.defaults()
    : super(
        driftDatabase(
          name: 'tongxingzhe_local',
          web: DriftWebOptions(
            sqlite3Wasm: Uri.parse('sqlite3.wasm'),
            driftWorker: Uri.parse('drift_worker.js'),
          ),
        ),
      );

  @override
  int get schemaVersion => 11;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (migrator) => migrator.createAll(),
    beforeOpen: (details) async {
      // SQLite 默认不会在每个连接上强制外键；显式开启后，revision 不可能
      // 指向不存在的接触。该设置同样作用于正式库和内存测试库。
      await customStatement('PRAGMA foreign_keys = ON');
    },
    onUpgrade: (migrator, from, to) async {
      // v2 adds the relationship/progress stage for the person being recorded.
      // Existing local demo records are treated as level 1 ("new contact").
      if (from < 2) {
        await migrator.addColumn(
          dbConversationRecords,
          dbConversationRecords.relationshipLevel,
        );
      }
      if (from < 3) {
        await migrator.addColumn(dbUsers, dbUsers.birthday);
        await migrator.addColumn(dbUsers, dbUsers.gender);
        await migrator.addColumn(dbUsers, dbUsers.occupation);
        await migrator.addColumn(dbUsers, dbUsers.contactJson);
        await migrator.addColumn(
          dbConversationRecords,
          dbConversationRecords.areaName,
        );
        await migrator.addColumn(
          dbConversationRecords,
          dbConversationRecords.interestLevel,
        );
      }
      // v4 keeps older local demo databases useful by assigning a reasonable
      // area and translating the legacy -2..2 attitude score into 0..4 interest.
      if (from < 4) {
        final recordTableExists = await customSelect(
          "SELECT name FROM sqlite_master "
          "WHERE type = 'table' AND name = 'db_conversation_records'",
        ).get();
        if (recordTableExists.isNotEmpty) {
          await customStatement('''
            UPDATE db_conversation_records
            SET area_name = CASE
              WHEN city_name = 'Chicago, IL' THEN 'IIT'
              WHEN city_name = 'New York, NY' THEN 'Campus'
              WHEN city_name = 'Los Angeles, CA' THEN 'Downtown'
              ELSE 'General Area'
            END
            WHERE area_name = 'unassigned'
          ''');
          await customStatement('''
            UPDATE db_conversation_records
            SET interest_level = CASE
              WHEN attitude_level <= -2 THEN 0
              WHEN attitude_level >= 2 THEN 4
              ELSE attitude_level + 2
            END
          ''');
        }
      }
      // v5 removes the old prayer free-text column. Some SQLite runtimes can
      // drop a column directly; if not, we at least wipe the old data and the
      // app no longer reads or writes that column.
      if (from < 5) {
        final prayerColumnExists = await customSelect(
          "SELECT name FROM pragma_table_info('db_conversation_records') "
          "WHERE name = 'prayer_sentence'",
        ).get();
        if (prayerColumnExists.isNotEmpty) {
          try {
            await customStatement(
              'ALTER TABLE db_conversation_records DROP COLUMN prayer_sentence',
            );
          } catch (_) {
            await customStatement(
              "UPDATE db_conversation_records SET prayer_sentence = ''",
            );
          }
        }
      }
      if (from < 6) {
        // v6 采用 expand-contract：保留五张 legacy 表为只读兼容证据，新增
        // 现代接触表。旧字段不能可靠推导空间、项目、问卷或匿名接触事实，
        // 因而这里不猜测、不回填、不删除。
        await migrator.createTable(dbContactRecords);
        await migrator.createTable(dbContactRevisions);
        await migrator.createTable(dbContactAnswers);
        await migrator.createTable(dbSyncOutbox);
        await migrator.createIndex(contactRecordsPersonalPeriod);
        await migrator.createIndex(syncOutboxReady);
        await migrator.createIndex(syncOutboxAggregateOrder);
      }
      if (from < 7) {
        // v7 新增私有多草稿。草稿是尚未提交的填写状态，不从 legacy 宽表
        // 或已提交接触反推，因而升级只建新表和创建者列表索引。
        await migrator.createTable(dbContactDrafts);
        await migrator.createTable(dbContactDraftAnswers);
        await migrator.createIndex(contactDraftsOwnerUpdated);
      }
      if (from < 8) {
        // v8 把同步执行租约和按用户项目保存的 server cursor 分开。
        // 旧 Outbox 行保持原样；首次运行 SyncEngine 时再领取它们。
        await migrator.createTable(dbSyncDrainerLeases);
        await migrator.createTable(dbSyncScopes);
      }
      if (from < 9) {
        // v9 的新列同时参与 CHECK 约束，SQLite `ADD COLUMN` 不会更新旧表
        // 约束。因此这里重建四张表并复制旧数据。跨多版升级时，v6/v7
        // 可能已按当前定义创建新列；动态 newColumns 避免随后重复加列。
        final contactRecordColumns = await _missingColumns(
          dbContactRecords.actualTableName,
          [dbContactRecords.regionTreeVersion],
        );
        await migrator.alterTable(
          TableMigration(dbContactRecords, newColumns: contactRecordColumns),
        );
        final contactRevisionColumns = await _missingColumns(
          dbContactRevisions.actualTableName,
          [
            dbContactRevisions.regionTreeVersion,
            // TableMigration uses the current table definition. Include
            // columns introduced after v9 so a direct upgrade from v6-v8
            // does not try to copy a column that the old table lacks.
            dbContactRevisions.revisionKind,
          ],
        );
        await migrator.alterTable(
          TableMigration(
            dbContactRevisions,
            newColumns: contactRevisionColumns,
          ),
        );
        final draftColumns =
            await _missingColumns(dbContactDrafts.actualTableName, [
              dbContactDrafts.regionTreeVersion,
              dbContactDrafts.localRevision,
              dbContactDrafts.serverRevision,
              dbContactDrafts.conflictOfDraftId,
              dbContactDrafts.sourceAttemptId,
            ]);
        await migrator.alterTable(
          TableMigration(dbContactDrafts, newColumns: draftColumns),
        );
        final outboxColumns = await _missingColumns(
          dbSyncOutbox.actualTableName,
          [
            dbSyncOutbox.appUserId,
            dbSyncOutbox.workspaceId,
            dbSyncOutbox.projectId,
          ],
        );
        await migrator.alterTable(
          TableMigration(dbSyncOutbox, newColumns: outboxColumns),
        );

        // 旧接触没有可证明的区域版本，因此不猜测、不自动分配。
        await migrator.createTable(dbCanonicalRegionVersions);
        await migrator.createTable(dbContactRegionAssignments);
        await migrator.createTable(dbDraftRegionAssignments);
      }
      if (from < 10) {
        // v10 新增独立接触尝试，并让由尝试发起的接触草稿保留来源 ID。
        // legacy 数据没有可证明的尝试语义，因此升级只建表，不猜测回填。
        await migrator.createTable(dbContactAttempts);
        await migrator.createIndex(contactAttemptsPersonalPeriod);
        final draftColumns = await _missingColumns(
          dbContactDrafts.actualTableName,
          [dbContactDrafts.sourceAttemptId],
        );
        if (draftColumns.isNotEmpty) {
          await migrator.alterTable(
            TableMigration(dbContactDrafts, newColumns: draftColumns),
          );
        }
      }
      if (from < 11) {
        // v11 把提交、更正和作废变成可约束的 revision 类型。该列参与
        // CHECK，必须重建表；只用 ADD COLUMN 会保留旧约束。
        final revisionColumns = await _missingColumns(
          dbContactRevisions.actualTableName,
          [dbContactRevisions.revisionKind],
        );
        await migrator.alterTable(
          TableMigration(dbContactRevisions, newColumns: revisionColumns),
        );
      }
    },
  );

  Future<List<GeneratedColumn<Object>>> _missingColumns(
    String tableName,
    List<GeneratedColumn<Object>> candidates,
  ) async {
    final rows = await customSelect(
      'SELECT name FROM pragma_table_info(?)',
      variables: [Variable<String>(tableName)],
    ).get();
    final existing = {for (final row in rows) row.read<String>('name')};
    return [
      for (final column in candidates)
        if (!existing.contains(column.$name)) column,
    ];
  }
}
