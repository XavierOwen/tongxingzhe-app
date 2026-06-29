import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

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
  tables: [
    DbUsers,
    DbConversationRecords,
    DbRecordContacts,
    DbAppSettings,
    DbSecurityEvents,
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
  int get schemaVersion => 5;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (migrator) => migrator.createAll(),
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
    },
  );
}
