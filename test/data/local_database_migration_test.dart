import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tongxingzhe_app/data/local_database.dart';

import '../generated_migrations/schema.dart';
import '../generated_migrations/schema_v5.dart' as v5;
import '../generated_migrations/schema_v6.dart' as v6;

void main() {
  test('保存的 schema v7 可以独立重建', () async {
    final verifier = SchemaVerifier(GeneratedHelper());
    final connection = await verifier.startAt(7);
    final database = LocalDatabase(connection);
    addTearDown(database.close);

    await verifier.migrateAndValidate(database, 7);
  });

  test('v6 升级到 v7 时保留已提交接触并新增空草稿表', () async {
    final verifier = SchemaVerifier(GeneratedHelper());
    final schema = await verifier.schemaAt(6);
    addTearDown(schema.close);

    final v6Database = v6.DatabaseAtV6(schema.newConnection());
    await v6Database.customStatement('''
      INSERT INTO db_contact_records (
        contact_id,
        app_user_id,
        workspace_id,
        project_id,
        questionnaire_version_id,
        occurred_at_utc,
        occurred_time_zone,
        first_submitted_at_utc,
        channel,
        channel_detail,
        location_kind,
        place_name,
        smallest_region_id,
        latitude,
        longitude,
        location_accuracy_meters,
        reach_count,
        interest_level,
        current_revision,
        lifecycle_status
      ) VALUES (
        'contact-before-v7',
        'app-user-1',
        'workspace-1',
        'project-1',
        'questionnaire-v1',
        1894122000,
        'America/Chicago',
        1894123800,
        'video_call',
        NULL,
        'not_applicable',
        NULL,
        NULL,
        NULL,
        NULL,
        NULL,
        2,
        3,
        1,
        'active'
      )
    ''');
    await v6Database.close();

    final database = LocalDatabase(schema.newConnection());
    addTearDown(database.close);
    await verifier.migrateAndValidate(database, 7);

    final contact = await database
        .select(database.dbContactRecords)
        .getSingle();
    expect(contact.contactId, 'contact-before-v7');
    expect(await database.select(database.dbContactDrafts).get(), isEmpty);
    expect(
      await database.select(database.dbContactDraftAnswers).get(),
      isEmpty,
    );
  });

  test('v5 升级到 v7 时保留 legacy 数据并新增现代空表', () async {
    final verifier = SchemaVerifier(GeneratedHelper());
    final schema = await verifier.schemaAt(5);
    addTearDown(schema.close);

    final legacyDatabase = v5.DatabaseAtV5(schema.newConnection());
    await legacyDatabase.customStatement(
      "INSERT INTO db_app_settings (key, value) VALUES ('locale', 'zh')",
    );
    await legacyDatabase.close();

    final database = LocalDatabase(schema.newConnection());
    addTearDown(database.close);
    await verifier.migrateAndValidate(database, 7);

    final legacySetting = await (database.select(
      database.dbAppSettings,
    )..where((row) => row.key.equals('locale'))).getSingle();
    expect(legacySetting.value, 'zh');
    expect(await database.select(database.dbContactRecords).get(), isEmpty);
    expect(await database.select(database.dbContactRevisions).get(), isEmpty);
    expect(await database.select(database.dbContactAnswers).get(), isEmpty);
    expect(await database.select(database.dbSyncOutbox).get(), isEmpty);
    expect(await database.select(database.dbContactDrafts).get(), isEmpty);
    expect(
      await database.select(database.dbContactDraftAnswers).get(),
      isEmpty,
    );
  });
}
