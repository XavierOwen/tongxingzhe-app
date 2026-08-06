import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tongxingzhe_app/data/local_database.dart';

import '../generated_migrations/schema.dart';
import '../generated_migrations/schema_v5.dart' as v5;
import '../generated_migrations/schema_v6.dart' as v6;
import '../generated_migrations/schema_v8.dart' as v8;
import '../generated_migrations/schema_v9.dart' as v9;
import '../generated_migrations/schema_v10.dart' as v10;
import '../generated_migrations/schema_v11.dart' as v11;
import '../generated_migrations/schema_v12.dart' as v12;
import '../generated_migrations/schema_v13.dart' as v13;
import '../generated_migrations/schema_v14.dart' as v14;
import '../generated_migrations/schema_v15.dart' as v15;

void main() {
  test('保存的 schema v16 可以独立重建', () async {
    final verifier = SchemaVerifier(GeneratedHelper());
    final connection = await verifier.startAt(16);
    final database = LocalDatabase(connection);
    addTearDown(database.close);

    await verifier.migrateAndValidate(database, 16);
  });

  test('v15 升级到 v16 时保留旧草稿且不猜测升级来源', () async {
    final verifier = SchemaVerifier(GeneratedHelper());
    final schema = await verifier.schemaAt(15);
    addTearDown(schema.close);
    final oldDatabase = v15.DatabaseAtV15(schema.newConnection());
    await oldDatabase.customStatement('''
      INSERT INTO db_contact_drafts (
        draft_id, app_user_id, workspace_id, project_id,
        questionnaire_version_id, created_at_utc, updated_at_utc,
        channel, location_kind, reach_count, interest_level
      ) VALUES (
        'draft-before-v16', 'app-user-1', 'workspace-1', 'project-1',
        'questionnaire-v1', 1894122000, 1894123800, 'video_call',
        'not_applicable', 1, 2
      )
    ''');
    await oldDatabase.close();

    final database = LocalDatabase(schema.newConnection());
    addTearDown(database.close);
    await verifier.migrateAndValidate(database, 16);

    final draft = await database.select(database.dbContactDrafts).getSingle();
    expect(draft.draftId, 'draft-before-v16');
    expect(draft.upgradedFromDraftId, isNull);
  });

  test('从 v14 升级时保留旧设置并新增空问卷工作副本表', () async {
    final verifier = SchemaVerifier(GeneratedHelper());
    final schema = await verifier.schemaAt(14);
    addTearDown(schema.close);
    final oldDatabase = v14.DatabaseAtV14(schema.newConnection());
    await oldDatabase.customStatement(
      "INSERT INTO db_app_settings (key, value) VALUES ('locale', 'zh')",
    );
    await oldDatabase.close();

    final database = LocalDatabase(schema.newConnection());
    addTearDown(database.close);
    await verifier.migrateAndValidate(database, 16);

    expect(
      (await database.select(database.dbAppSettings).getSingle()).value,
      'zh',
    );
    expect(
      await database.select(database.dbQuestionnaireDraftWorkingCopies).get(),
      isEmpty,
    );
  });

  test('从 v13 升级时保留答案并新增规则与跳题原因列', () async {
    final verifier = SchemaVerifier(GeneratedHelper());
    final schema = await verifier.schemaAt(13);
    addTearDown(schema.close);

    final oldDatabase = v13.DatabaseAtV13(schema.newConnection());
    await oldDatabase.customStatement('''
      INSERT INTO db_questionnaire_versions (
        questionnaire_version_id, project_id, version_number,
        status, installed_at_utc
      ) VALUES ('questionnaire-v1', 'project-1', 1, 'published', 1894122000)
    ''');
    await oldDatabase.customStatement('''
      INSERT INTO db_questionnaire_questions (
        questionnaire_version_id, question_id, position, prompt,
        question_type, is_required, allow_unknown, allow_refused,
        allow_not_applicable
      ) VALUES (
        'questionnaire-v1', 'consent', 1, '是否同意？',
        'boolean', 1, 0, 1, 0
      )
    ''');
    await oldDatabase.customStatement('''
      INSERT INTO db_contact_records (
        contact_id, app_user_id, workspace_id, project_id,
        questionnaire_version_id, occurred_at_utc, occurred_time_zone,
        first_submitted_at_utc, channel, location_kind, reach_count,
        interest_level, current_revision, lifecycle_status
      ) VALUES (
        'contact-before-v14', 'app-user-1', 'workspace-1', 'project-1',
        'questionnaire-v1', 1894122000, 'America/Chicago', 1894123800,
        'video_call', 'not_applicable', 1, 2, 1, 'active'
      )
    ''');
    await oldDatabase.customStatement('''
      INSERT INTO db_contact_answers (
        contact_id, revision_number, question_id, answer_state,
        answer_type, boolean_value
      ) VALUES (
        'contact-before-v14', 1, 'consent', 'answered', 'boolean', 1
      )
    ''');
    await oldDatabase.close();

    final database = LocalDatabase(schema.newConnection());
    addTearDown(database.close);
    await verifier.migrateAndValidate(database, 16);

    final answer = await database.select(database.dbContactAnswers).getSingle();
    expect(answer.booleanValue, isTrue);
    expect(answer.answerStateReason, isNull);
    final question = await database
        .select(database.dbQuestionnaireQuestions)
        .getSingle();
    expect(question.displayRuleJson, isNull);
  });

  test('从 v12 升级时保留 boolean 答案并新增空问卷定义表', () async {
    final verifier = SchemaVerifier(GeneratedHelper());
    final schema = await verifier.schemaAt(12);
    addTearDown(schema.close);

    final oldDatabase = v12.DatabaseAtV12(schema.newConnection());
    await oldDatabase.customStatement('''
      INSERT INTO db_contact_records (
        contact_id, app_user_id, workspace_id, project_id,
        questionnaire_version_id, occurred_at_utc, occurred_time_zone,
        first_submitted_at_utc, channel, location_kind, reach_count,
        interest_level, current_revision, lifecycle_status
      ) VALUES (
        'contact-before-v13', 'app-user-1', 'workspace-1', 'project-1',
        'questionnaire-v1', 1894122000, 'America/Chicago', 1894123800,
        'video_call', 'not_applicable', 1, 2, 1, 'active'
      )
    ''');
    await oldDatabase.customStatement('''
      INSERT INTO db_contact_revisions (
        revision_id, contact_id, revision_number, revision_kind,
        revised_by_app_user_id, revised_at_utc, occurred_at_utc,
        occurred_time_zone, channel, location_kind, reach_count,
        interest_level
      ) VALUES (
        'revision-before-v13', 'contact-before-v13', 1, 'submitted',
        'app-user-1', 1894123800, 1894122000, 'America/Chicago',
        'video_call', 'not_applicable', 1, 2
      )
    ''');
    await oldDatabase.customStatement('''
      INSERT INTO db_contact_answers (
        contact_id, revision_number, question_id, answer_state,
        answer_type, boolean_value
      ) VALUES (
        'contact-before-v13', 1, 'follow_up', 'answered', 'boolean', 1
      )
    ''');
    await oldDatabase.customStatement('''
      INSERT INTO db_contact_drafts (
        draft_id, app_user_id, workspace_id, project_id,
        questionnaire_version_id, created_at_utc, updated_at_utc,
        channel, location_kind, reach_count, interest_level
      ) VALUES (
        'draft-before-v13', 'app-user-1', 'workspace-1', 'project-1',
        'questionnaire-v1', 1894122000, 1894123800, 'video_call',
        'not_applicable', 1, 2
      )
    ''');
    await oldDatabase.customStatement('''
      INSERT INTO db_contact_draft_answers (
        draft_id, question_id, answer_state, answer_type, boolean_value
      ) VALUES (
        'draft-before-v13', 'follow_up', 'answered', 'boolean', 0
      )
    ''');
    await oldDatabase.close();

    final database = LocalDatabase(schema.newConnection());
    addTearDown(database.close);
    await verifier.migrateAndValidate(database, 16);

    final submittedAnswer = await database
        .select(database.dbContactAnswers)
        .getSingle();
    expect(submittedAnswer.booleanValue, isTrue);
    expect(submittedAnswer.textValue, isNull);
    expect(submittedAnswer.numberValue, isNull);
    expect(submittedAnswer.multiChoiceValueJson, isNull);
    final draftAnswer = await database
        .select(database.dbContactDraftAnswers)
        .getSingle();
    expect(draftAnswer.booleanValue, isFalse);
    expect(draftAnswer.textValue, isNull);
    expect(
      await database.select(database.dbQuestionnaireVersions).get(),
      isEmpty,
    );
    expect(
      await database.select(database.dbQuestionnaireQuestions).get(),
      isEmpty,
    );
    expect(
      await database.select(database.dbQuestionnaireOptions).get(),
      isEmpty,
    );
  });

  test('从 v11 升级时保留接触并新增空冲突表', () async {
    final verifier = SchemaVerifier(GeneratedHelper());
    final schema = await verifier.schemaAt(11);
    addTearDown(schema.close);

    final oldDatabase = v11.DatabaseAtV11(schema.newConnection());
    await oldDatabase.customStatement('''
      INSERT INTO db_contact_records (
        contact_id, app_user_id, workspace_id, project_id,
        questionnaire_version_id, occurred_at_utc, occurred_time_zone,
        first_submitted_at_utc, channel, location_kind, reach_count,
        interest_level, current_revision, lifecycle_status
      ) VALUES (
        'contact-before-v12', 'app-user-1', 'workspace-1', 'project-1',
        'questionnaire-v1', 1894122000, 'America/Chicago', 1894123800,
        'video_call', 'not_applicable', 1, 2, 1, 'active'
      )
    ''');
    await oldDatabase.close();

    final database = LocalDatabase(schema.newConnection());
    addTearDown(database.close);
    await verifier.migrateAndValidate(database, 16);

    expect(
      (await database.select(database.dbContactRecords).getSingle()).contactId,
      'contact-before-v12',
    );
    expect(
      await database.select(database.dbContactRevisionConflicts).get(),
      isEmpty,
    );
  });

  test('从 v10 升级时保留初始 revision 并标记提交类型', () async {
    final verifier = SchemaVerifier(GeneratedHelper());
    final schema = await verifier.schemaAt(10);
    addTearDown(schema.close);

    final oldDatabase = v10.DatabaseAtV10(schema.newConnection());
    await oldDatabase.customStatement('''
      INSERT INTO db_contact_records (
        contact_id, app_user_id, workspace_id, project_id,
        questionnaire_version_id, occurred_at_utc, occurred_time_zone,
        first_submitted_at_utc, channel, location_kind, reach_count,
        interest_level, current_revision, lifecycle_status
      ) VALUES (
        'contact-before-v11', 'app-user-1', 'workspace-1', 'project-1',
        'questionnaire-v1', 1894122000, 'America/Chicago', 1894123800,
        'video_call', 'not_applicable', 1, 2, 1, 'active'
      )
    ''');
    await oldDatabase.customStatement('''
      INSERT INTO db_contact_revisions (
        revision_id, contact_id, revision_number, revised_by_app_user_id,
        revised_at_utc, occurred_at_utc, occurred_time_zone, channel,
        location_kind, reach_count, interest_level
      ) VALUES (
        'revision-before-v11', 'contact-before-v11', 1, 'app-user-1',
        1894123800, 1894122000, 'America/Chicago', 'video_call',
        'not_applicable', 1, 2
      )
    ''');
    await oldDatabase.close();

    final database = LocalDatabase(schema.newConnection());
    addTearDown(database.close);
    await verifier.migrateAndValidate(database, 16);

    final revision = await database
        .select(database.dbContactRevisions)
        .getSingle();
    expect(revision.revisionId, 'revision-before-v11');
    expect(revision.revisionKind, 'submitted');
    expect(revision.reason, isNull);
  });

  test('从 v9 升级时保留草稿并新增独立接触尝试', () async {
    final verifier = SchemaVerifier(GeneratedHelper());
    final schema = await verifier.schemaAt(9);
    addTearDown(schema.close);

    final v9Database = v9.DatabaseAtV9(schema.newConnection());
    await v9Database.customStatement('''
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
        'draft-before-v10',
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
    await v9Database.close();

    final database = LocalDatabase(schema.newConnection());
    addTearDown(database.close);
    await verifier.migrateAndValidate(database, 16);

    final draft = await database.select(database.dbContactDrafts).getSingle();
    expect(draft.draftId, 'draft-before-v10');
    expect(draft.sourceAttemptId, isNull);
    expect(await database.select(database.dbContactAttempts).get(), isEmpty);
  });

  test('从 v8 升级时保留草稿并加入同步版本和区域外键表', () async {
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
    await verifier.migrateAndValidate(database, 16);

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

  test('从 v6 升级时保留已提交接触并新增同步协调表', () async {
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
    await verifier.migrateAndValidate(database, 16);

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

  test('从 v5 升级时保留 legacy 数据并新增现代空表', () async {
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
    await verifier.migrateAndValidate(database, 16);

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
