import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tongxingzhe_app/data/local_database.dart';

import '../generated_migrations/schema.dart';
import '../generated_migrations/schema_v5.dart' as v5;
import '../generated_migrations/schema_v6.dart' as v6;
import '../generated_migrations/schema_v8.dart' as v8;

void main() {
  test('保存的 schema v9 可以独立重建', () async {
    final verifier = SchemaVerifier(GeneratedHelper());
    final connection = await verifier.startAt(9);
    final database = LocalDatabase(connection);
    addTearDown(database.close);

    await verifier.migrateAndValidate(database, 9);
  });

  test('v8 升级到 v9 时保留草稿并加入同步版本和区域外键表', () async {
    final verifier = SchemaVerifier(GeneratedHelper());
    final schema = await verifier.schemaAt(8);
    addTearDown(schema.close);

    final v8Database = v8.DatabaseAtV8(schema.newConnection());
    await v8Database.customStatement('''
      INSERT INTO db_contact_drafts (
        draft_id,
        app_user_id,
        workspace_id,
        project_id,
        questionnaire_version_id,
        created_at_utc,
        updated_at_utc,
        channel,
        location_kind,
        reach_count,
        interest_level
      ) VALUES (
        'draft-before-v9',
        'app-user-1',
        'workspace-1',
        'project-1',
        'questionnaire-v1',
        1894122000,
        1894123800,
        'video_call',
        'not_applicable',
        2,
        3
      )
    ''');
    await v8Database.close();

    final database = LocalDatabase(schema.newConnection());
    addTearDown(database.close);
    await verifier.migrateAndValidate(database, 9);

    final draft = await database.select(database.dbContactDrafts).getSingle();
    expect(draft.draftId, 'draft-before-v9');
    expect(draft.localRevision, 1);
    expect(draft.serverRevision, 0);
    expect(draft.conflictOfDraftId, isNull);
    expect(draft.regionTreeVersion, isNull);
    expect(
      await database.select(database.dbCanonicalRegionVersions).get(),
      isEmpty,
    );
    expect(
      await database.select(database.dbDraftRegionAssignments).get(),
      isEmpty,
    );
  });

  test('v6 升级到 v9 时保留已提交接触并新增同步协调表', () async {
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
    await verifier.migrateAndValidate(database, 9);

    final contact = await database
        .select(database.dbContactRecords)
        .getSingle();
    expect(contact.contactId, 'contact-before-v7');
    expect(await database.select(database.dbContactDrafts).get(), isEmpty);
    expect(
      await database.select(database.dbContactDraftAnswers).get(),
      isEmpty,
    );
    expect(await database.select(database.dbSyncDrainerLeases).get(), isEmpty);
    expect(await database.select(database.dbSyncScopes).get(), isEmpty);
    expect(
      await database.select(database.dbCanonicalRegionVersions).get(),
      isEmpty,
    );
  });

  test('v5 升级到 v9 时保留 legacy 数据并新增现代空表', () async {
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
    await verifier.migrateAndValidate(database, 9);

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
    expect(await database.select(database.dbSyncDrainerLeases).get(), isEmpty);
    expect(await database.select(database.dbSyncScopes).get(), isEmpty);
    expect(
      await database.select(database.dbCanonicalRegionVersions).get(),
      isEmpty,
    );
    expect(
      await database.select(database.dbContactRegionAssignments).get(),
      isEmpty,
    );
  });
}
