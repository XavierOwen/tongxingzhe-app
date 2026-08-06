import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tongxingzhe_app/data/local_database.dart';
import 'package:tongxingzhe_app/features/contact_journal/contact_journal.dart';
import 'package:tongxingzhe_app/features/contact_journal/contact_models.dart';
import 'package:tongxingzhe_app/foundation/runtime_values.dart';
import 'package:tongxingzhe_app/questionnaires/questionnaire_contract.dart';
import 'package:tongxingzhe_app/questionnaires/questionnaire_draft_upgrade.dart';

void main() {
  test('空白接触页不创建草稿，首次有意义输入才创建', () async {
    final journal = _journal(['draft-1']);
    const contextOnly = ContactDraftInput(
      deviceId: 'device-1',
      appUserId: 'app-user-1',
      workspaceId: 'personal-workspace-1',
      projectId: 'project-1',
      questionnaireVersionId: 'questionnaire-v1',
    );

    expect(await journal.saveDraft(contextOnly), isNull);
    expect(await journal.listDrafts(appUserId: 'app-user-1'), isEmpty);

    final saved = await journal.saveDraft(
      const ContactDraftInput(
        deviceId: 'device-1',
        appUserId: 'app-user-1',
        workspaceId: 'personal-workspace-1',
        projectId: 'project-1',
        questionnaireVersionId: 'questionnaire-v1',
        channel: ContactChannel.videoCall,
      ),
    );

    expect(saved, isNotNull);
    expect(saved!.draftId, 'draft-1');
    expect(saved.channel, ContactChannel.videoCall);
    expect(saved.createdAtUtc, DateTime.utc(2030, 1, 8, 18, 30));
    expect(saved.updatedAtUtc, DateTime.utc(2030, 1, 8, 18, 30));
    final drafts = await journal.listDrafts(appUserId: 'app-user-1');
    expect(drafts, hasLength(1));
    expect(drafts.single.draftId, saved.draftId);
    expect(drafts.single.appUserId, saved.appUserId);
    expect(drafts.single.workspaceId, saved.workspaceId);
    expect(drafts.single.projectId, saved.projectId);
    expect(drafts.single.questionnaireVersionId, saved.questionnaireVersionId);
    expect(drafts.single.createdAtUtc, saved.createdAtUtc);
    expect(drafts.single.updatedAtUtc, saved.updatedAtUtc);
    expect(drafts.single.channel, saved.channel);
  });

  test('自动保存更新原草稿并保留创建时间', () async {
    final database = LocalDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final clock = _MutableClock(DateTime.utc(2030, 1, 8, 18, 30));
    final journal = ContactJournal(
      database: database,
      clock: clock,
      idGenerator: _SequenceIdGenerator(['draft-autosave']),
    );
    final created = await journal.saveDraft(
      const ContactDraftInput(
        deviceId: 'device-1',
        appUserId: 'app-user-1',
        workspaceId: 'personal-workspace-1',
        projectId: 'project-1',
        questionnaireVersionId: 'questionnaire-v1',
        channel: ContactChannel.videoCall,
      ),
    );

    clock.value = DateTime.utc(2030, 1, 8, 18, 35);
    final updated = await journal.saveDraft(
      ContactDraftInput(
        draftId: created!.draftId,
        deviceId: 'device-1',
        appUserId: created.appUserId,
        workspaceId: created.workspaceId,
        projectId: created.projectId,
        questionnaireVersionId: created.questionnaireVersionId,
        channel: ContactChannel.voiceCall,
      ),
    );

    expect(updated!.draftId, 'draft-autosave');
    expect(updated.createdAtUtc, DateTime.utc(2030, 1, 8, 18, 30));
    expect(updated.updatedAtUtc, DateTime.utc(2030, 1, 8, 18, 35));
    expect(updated.channel, ContactChannel.voiceCall);
    expect(await journal.listDrafts(appUserId: 'app-user-1'), hasLength(1));
  });

  test('本人私有草稿写入持久同步命令且连续自动保存只保留最新快照', () async {
    final database = LocalDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final clock = _MutableClock(DateTime.utc(2030, 1, 8, 18, 30));
    final journal = ContactJournal(
      database: database,
      clock: clock,
      idGenerator: _SequenceIdGenerator(['draft-private-sync']),
    );
    final created = await journal.saveDraft(
      const ContactDraftInput(
        deviceId: 'device-a',
        appUserId: 'app-user-1',
        workspaceId: 'personal-workspace-1',
        projectId: 'project-1',
        questionnaireVersionId: 'questionnaire-v1',
        channel: ContactChannel.videoCall,
      ),
    );

    clock.value = DateTime.utc(2030, 1, 8, 18, 31);
    await journal.saveDraft(
      ContactDraftInput(
        draftId: created!.draftId,
        deviceId: 'device-a',
        appUserId: created.appUserId,
        workspaceId: created.workspaceId,
        projectId: created.projectId,
        questionnaireVersionId: created.questionnaireVersionId,
        channel: ContactChannel.voiceCall,
      ),
    );

    final commands = await database.select(database.dbSyncOutbox).get();
    expect(commands, hasLength(1));
    expect(commands.single.commandType, 'draft.upsert.v1');
    expect(commands.single.deviceId, 'device-a');
    expect(commands.single.appUserId, 'app-user-1');
    expect(commands.single.baseRevision, 0);
    expect(commands.single.payloadJson, contains('voice_call'));
    expect(commands.single.payloadJson, isNot(contains('video_call')));
  });

  test('仅本设备草稿不写入跨设备同步命令', () async {
    final database = LocalDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final journal = ContactJournal(
      database: database,
      clock: _FixedClock(DateTime.utc(2030, 1, 8, 18, 30)),
      idGenerator: _SequenceIdGenerator(['draft-device-only']),
    );

    await journal.saveDraft(
      const ContactDraftInput(
        deviceId: 'device-a',
        appUserId: 'app-user-1',
        workspaceId: 'personal-workspace-1',
        projectId: 'project-1',
        questionnaireVersionId: 'questionnaire-v1',
        channel: ContactChannel.videoCall,
        syncMode: ContactDraftSyncMode.deviceOnly,
      ),
    );

    expect(await database.select(database.dbSyncOutbox).get(), isEmpty);
  });

  test('账号私有上传结果不确定时不假装已经切为仅本设备', () async {
    final database = LocalDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final journal = ContactJournal(
      database: database,
      clock: _FixedClock(DateTime.utc(2030, 1, 8, 18, 30)),
      idGenerator: _SequenceIdGenerator(['draft-transition']),
    );
    final draft = await journal.saveDraft(
      const ContactDraftInput(
        deviceId: 'device-a',
        appUserId: 'app-user-1',
        workspaceId: 'personal-workspace-1',
        projectId: 'project-1',
        questionnaireVersionId: 'questionnaire-v1',
        channel: ContactChannel.videoCall,
      ),
    );
    await database
        .update(database.dbSyncOutbox)
        .write(const DbSyncOutboxCompanion(attemptCount: Value(1)));

    await expectLater(
      journal.saveDraft(
        ContactDraftInput(
          draftId: draft!.draftId,
          deviceId: 'device-a',
          appUserId: draft.appUserId,
          workspaceId: draft.workspaceId,
          projectId: draft.projectId,
          questionnaireVersionId: draft.questionnaireVersionId,
          channel: draft.channel,
          syncMode: ContactDraftSyncMode.deviceOnly,
        ),
      ),
      throwsA(
        isA<ContactValidationException>().having(
          (error) => error.code,
          'code',
          'draft_sync_transition_waiting_for_confirmation',
        ),
      ),
    );
    expect(
      (await journal.listDrafts(appUserId: 'app-user-1')).single.syncMode,
      ContactDraftSyncMode.accountPrivate,
    );
  });

  test('草稿可恢复全部核心事实、类型化答案和同步模式', () async {
    final journal = _journal(['draft-complete']);
    final saved = await journal.saveDraft(
      ContactDraftInput(
        deviceId: 'device-1',
        appUserId: 'app-user-1',
        workspaceId: 'personal-workspace-1',
        projectId: 'project-1',
        questionnaireVersionId: 'questionnaire-v1',
        occurredAtUtc: DateTime.utc(2030, 1, 8, 17),
        occurredTimeZone: 'America/Chicago',
        channel: ContactChannel.faceToFace,
        channelDetail: '校园摊位',
        location: const PendingContactLocation(
          latitude: 41.7886,
          longitude: -87.5987,
          accuracyMeters: 12,
        ),
        reachCount: 3,
        interestLevel: 4,
        answers: const [
          BooleanQuestionnaireAnswer(
            questionId: 'follow_up_consent',
            value: true,
          ),
        ],
        syncMode: ContactDraftSyncMode.deviceOnly,
      ),
    );

    final restored = (await journal.listDrafts(appUserId: 'app-user-1')).single;
    expect(restored.draftId, saved!.draftId);
    expect(restored.occurredAtUtc, DateTime.utc(2030, 1, 8, 17));
    expect(restored.occurredTimeZone, 'America/Chicago');
    expect(restored.channel, ContactChannel.faceToFace);
    expect(restored.channelDetail, '校园摊位');
    expect(
      restored.location,
      const PendingContactLocation(
        latitude: 41.7886,
        longitude: -87.5987,
        accuracyMeters: 12,
      ),
    );
    expect(restored.reachCount, 3);
    expect(restored.interestLevel, 4);
    expect(restored.answers, const [
      BooleanQuestionnaireAnswer(questionId: 'follow_up_consent', value: true),
    ]);
    expect(restored.syncMode, ContactDraftSyncMode.deviceOnly);
    expect(restored.completedCoreFactCount, 5);
    expect(restored.requiredCoreFactCount, 5);
    expect(restored.hasCompleteCoreFacts, isTrue);
  });

  test('草稿按受控值列恢复八题型和非回答状态', () async {
    final journal = _journal(['draft-eight-types']);
    final answers = <QuestionnaireAnswer>[
      const BooleanQuestionnaireAnswer(
        questionId: 'boolean-question',
        value: true,
      ),
      const SingleChoiceQuestionnaireAnswer(
        questionId: 'single-question',
        value: 'option-a',
      ),
      const OrdinalChoiceQuestionnaireAnswer(
        questionId: 'ordinal-question',
        value: 'high',
      ),
      MultiChoiceQuestionnaireAnswer(
        questionId: 'multi-question',
        value: const ['option-a', 'option-b'],
      ),
      const NumberQuestionnaireAnswer(
        questionId: 'number-question',
        value: 2.5,
      ),
      const DateQuestionnaireAnswer(
        questionId: 'date-question',
        value: '2030-02-28',
      ),
      const ShortTextQuestionnaireAnswer(
        questionId: 'short-question',
        value: '简短备注',
      ),
      const LongTextQuestionnaireAnswer.refused(questionId: 'long-question'),
    ];

    await journal.saveDraft(
      ContactDraftInput(
        deviceId: 'device-1',
        appUserId: 'app-user-1',
        workspaceId: 'personal-workspace-1',
        projectId: 'project-1',
        questionnaireVersionId: 'questionnaire-v1',
        answers: answers,
        syncMode: ContactDraftSyncMode.deviceOnly,
      ),
    );

    final restored = (await journal.listDrafts(appUserId: 'app-user-1')).single;
    expect(restored.answers, unorderedEquals(answers));
  });

  test('草稿完成度不把缺少必要明细的其他渠道算作完成', () {
    final draft = ContactDraft(
      draftId: 'draft-progress',
      appUserId: 'app-user-1',
      workspaceId: 'personal-workspace-1',
      projectId: 'project-1',
      questionnaireVersionId: 'questionnaire-v1',
      createdAtUtc: DateTime.utc(2030, 1, 8, 18, 30),
      updatedAtUtc: DateTime.utc(2030, 1, 8, 18, 30),
      occurredAtUtc: DateTime.utc(2030, 1, 8, 17),
      occurredTimeZone: 'America/Chicago',
      channel: ContactChannel.otherDirect,
      channelDetail: null,
      location: const NotApplicableContactLocation(),
      reachCount: 1,
      interestLevel: null,
      answers: const [],
      syncMode: ContactDraftSyncMode.accountPrivate,
      localRevision: 1,
      serverRevision: 0,
      conflictOfDraftId: null,
    );

    expect(draft.completedCoreFactCount, 3);
    expect(draft.hasCompleteCoreFacts, isFalse);
  });

  test('关闭并重开后仍保留本人跨项目的多份私有草稿', () async {
    final temporaryDirectory = await Directory.systemTemp.createTemp(
      'tongxingzhe-contact-drafts-',
    );
    addTearDown(() => temporaryDirectory.delete(recursive: true));
    final databaseFile = File('${temporaryDirectory.path}/drafts.sqlite');
    final firstDatabase = LocalDatabase(NativeDatabase(databaseFile));
    final clock = _MutableClock(DateTime.utc(2030, 1, 8, 18, 30));
    final firstJournal = ContactJournal(
      database: firstDatabase,
      clock: clock,
      idGenerator: _SequenceIdGenerator([
        'draft-project-1',
        'draft-project-2',
        'draft-other-user',
      ]),
    );
    await firstJournal.saveDraft(
      const ContactDraftInput(
        deviceId: 'device-1',
        appUserId: 'app-user-1',
        workspaceId: 'personal-workspace-1',
        projectId: 'project-1',
        questionnaireVersionId: 'questionnaire-v1',
        channel: ContactChannel.voiceCall,
      ),
    );
    clock.value = DateTime.utc(2030, 1, 8, 18, 31);
    await firstJournal.saveDraft(
      const ContactDraftInput(
        deviceId: 'device-1',
        appUserId: 'app-user-1',
        workspaceId: 'personal-workspace-1',
        projectId: 'project-2',
        questionnaireVersionId: 'questionnaire-v2',
        channel: ContactChannel.videoCall,
      ),
    );
    await firstJournal.saveDraft(
      const ContactDraftInput(
        deviceId: 'device-1',
        appUserId: 'app-user-2',
        workspaceId: 'personal-workspace-2',
        projectId: 'project-other-user',
        questionnaireVersionId: 'questionnaire-other-user',
        channel: ContactChannel.instantText,
      ),
    );
    await firstDatabase.close();

    final reopenedDatabase = LocalDatabase(NativeDatabase(databaseFile));
    addTearDown(reopenedDatabase.close);
    final reopenedJournal = ContactJournal(
      database: reopenedDatabase,
      clock: clock,
      idGenerator: _SequenceIdGenerator(const []),
    );
    final restored = await reopenedJournal.listDrafts(appUserId: 'app-user-1');

    expect(restored.map((draft) => draft.draftId), [
      'draft-project-2',
      'draft-project-1',
    ]);
    expect(restored.map((draft) => draft.projectId), [
      'project-2',
      'project-1',
    ]);
  });

  test('稳定草稿地址按创建者读取并保留原项目归属', () async {
    final journal = _journal(['draft-project-2']);
    await journal.saveDraft(
      const ContactDraftInput(
        deviceId: 'device-1',
        appUserId: 'app-user-1',
        workspaceId: 'personal-workspace-1',
        projectId: 'project-2',
        questionnaireVersionId: 'questionnaire-v2',
        channel: ContactChannel.voiceCall,
      ),
    );

    final restored = await journal.draftByIdForOwner(
      draftId: 'draft-project-2',
      appUserId: 'app-user-1',
    );

    expect(restored, isNotNull);
    expect(restored!.projectId, 'project-2');
    expect(restored.questionnaireVersionId, 'questionnaire-v2');
    expect(
      await journal.draftByIdForOwner(
        draftId: 'draft-project-2',
        appUserId: 'app-user-2',
      ),
      isNull,
    );
  });

  test('正式提交把完整草稿原子转换为接触并从草稿列表移除', () async {
    final journal = _journal([
      'draft-to-submit',
      'contact-from-draft',
      'revision-from-draft',
      'command-from-draft',
    ]);
    final draft = await journal.saveDraft(
      ContactDraftInput(
        deviceId: 'device-1',
        appUserId: 'app-user-1',
        workspaceId: 'personal-workspace-1',
        projectId: 'project-1',
        questionnaireVersionId: 'questionnaire-v1',
        occurredAtUtc: DateTime.utc(2030, 1, 8, 17),
        occurredTimeZone: 'America/Chicago',
        channel: ContactChannel.videoCall,
        location: const NotApplicableContactLocation(),
        reachCount: 2,
        interestLevel: 3,
        answers: const [
          BooleanQuestionnaireAnswer(
            questionId: 'follow_up_consent',
            value: true,
          ),
        ],
      ),
    );

    final receipt = await journal.submitDraft(
      draftId: draft!.draftId,
      appUserId: 'app-user-1',
      deviceId: 'device-1',
    );

    expect(receipt.contactId, 'contact-from-draft');
    expect(await journal.listDrafts(appUserId: 'app-user-1'), isEmpty);
    final contact = await journal.contactById('contact-from-draft');
    expect(contact, isNotNull);
    expect(contact!.reachCount, 2);
    expect(contact.interestLevel, 3);
    expect(contact.answers, const [
      BooleanQuestionnaireAnswer(questionId: 'follow_up_consent', value: true),
    ]);
    final summary = await journal.summarizePersonalContacts(
      appUserId: 'app-user-1',
      workspaceId: 'personal-workspace-1',
      projectId: 'project-1',
      fromUtc: DateTime.utc(2030, 1, 8),
      untilUtc: DateTime.utc(2030, 1, 9),
    );
    expect(summary.contactSessionCount, 1);
    expect(summary.reachCount, 2);
  });

  test('正式提交失败会保留草稿并回滚部分接触写入以便重试', () async {
    final journal = _journal([
      'draft-atomic',
      'existing-contact',
      'existing-revision',
      'duplicate-command',
      'rolled-back-contact',
      'rolled-back-revision',
      'duplicate-command',
      'retry-contact',
      'retry-revision',
      'retry-command',
    ]);
    final draft = await journal.saveDraft(
      ContactDraftInput(
        deviceId: 'device-1',
        appUserId: 'app-user-1',
        workspaceId: 'personal-workspace-1',
        projectId: 'project-1',
        questionnaireVersionId: 'questionnaire-v1',
        occurredAtUtc: DateTime.utc(2030, 1, 8, 17),
        occurredTimeZone: 'America/Chicago',
        channel: ContactChannel.voiceCall,
        location: const NotApplicableContactLocation(),
        reachCount: 1,
        interestLevel: 2,
      ),
    );
    await journal.submitAnonymousContact(
      _submission(
        occurredAtUtc: DateTime.utc(2030, 1, 8, 16),
        reachCount: 1,
        interestLevel: 2,
      ),
    );

    await expectLater(
      journal.submitDraft(
        draftId: draft!.draftId,
        appUserId: 'app-user-1',
        deviceId: 'device-1',
      ),
      throwsA(
        isA<ContactPersistenceException>().having(
          (error) => error.code,
          'code',
          'contact_submission_failed',
        ),
      ),
    );
    expect(
      (await journal.listDrafts(appUserId: 'app-user-1')).single.draftId,
      'draft-atomic',
    );
    expect(await journal.contactById('rolled-back-contact'), isNull);

    final retry = await journal.submitDraft(
      draftId: draft.draftId,
      appUserId: 'app-user-1',
      deviceId: 'device-1',
    );
    expect(retry.contactId, 'retry-contact');
    expect(await journal.listDrafts(appUserId: 'app-user-1'), isEmpty);
  });

  test('本人明确放弃草稿后可在短暂期限内撤销恢复', () async {
    final database = LocalDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final clock = _MutableClock(DateTime.utc(2030, 1, 8, 18, 30));
    final journal = ContactJournal(
      database: database,
      clock: clock,
      idGenerator: _SequenceIdGenerator(['draft-to-abandon']),
    );
    final draft = await journal.saveDraft(
      const ContactDraftInput(
        deviceId: 'device-1',
        appUserId: 'app-user-1',
        workspaceId: 'personal-workspace-1',
        projectId: 'project-1',
        questionnaireVersionId: 'questionnaire-v1',
        channel: ContactChannel.instantText,
      ),
    );

    final abandoned = await journal.abandonDraft(
      draftId: draft!.draftId,
      appUserId: 'app-user-1',
      deviceId: 'device-1',
    );
    expect(abandoned.undoUntilUtc, DateTime.utc(2030, 1, 8, 18, 30, 10));
    expect(await journal.listDrafts(appUserId: 'app-user-1'), isEmpty);

    clock.value = DateTime.utc(2030, 1, 8, 18, 30, 9);
    final restored = await journal.undoAbandonDraft(
      draftId: draft.draftId,
      appUserId: 'app-user-1',
      deviceId: 'device-1',
    );
    expect(restored.draftId, 'draft-to-abandon');
    expect(
      (await journal.listDrafts(appUserId: 'app-user-1')).single.draftId,
      'draft-to-abandon',
    );
  });

  test('草稿放弃撤销期限过后保持隐藏', () async {
    final database = LocalDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final clock = _MutableClock(DateTime.utc(2030, 1, 8, 18, 30));
    final journal = ContactJournal(
      database: database,
      clock: clock,
      idGenerator: _SequenceIdGenerator(['draft-expired-undo']),
    );
    final draft = await journal.saveDraft(
      const ContactDraftInput(
        deviceId: 'device-1',
        appUserId: 'app-user-1',
        workspaceId: 'personal-workspace-1',
        projectId: 'project-1',
        questionnaireVersionId: 'questionnaire-v1',
        channel: ContactChannel.asynchronousMessage,
      ),
    );
    await journal.abandonDraft(
      draftId: draft!.draftId,
      appUserId: 'app-user-1',
      deviceId: 'device-1',
    );

    clock.value = DateTime.utc(2030, 1, 8, 18, 30, 11);
    await expectLater(
      journal.undoAbandonDraft(
        draftId: draft.draftId,
        appUserId: 'app-user-1',
        deviceId: 'device-1',
      ),
      throwsA(
        isA<ContactValidationException>().having(
          (error) => error.code,
          'code',
          'contact_draft_undo_expired',
        ),
      ),
    );
    expect(await journal.listDrafts(appUserId: 'app-user-1'), isEmpty);
  });

  test('问卷升级创建新草稿并保留原稿，重试不重复创建', () async {
    final database = LocalDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final journal = ContactJournal(
      database: database,
      clock: _FixedClock(DateTime.utc(2030, 1, 8, 18, 30)),
      idGenerator: _SequenceIdGenerator(['source-draft']),
    );
    final fixture = _draftUpgradeFixture();
    final catalog = QuestionnaireCatalog(database: database);
    await catalog.installPublishedVersion(fixture.source);
    await catalog.installPublishedVersion(fixture.target);
    final source = await journal.saveDraft(
      ContactDraftInput(
        deviceId: 'device-1',
        appUserId: 'app-user-1',
        workspaceId: 'workspace-1',
        projectId: fixture.source.projectId,
        questionnaireVersionId: fixture.source.id,
        channel: ContactChannel.videoCall,
        answers: fixture.sourceAnswers,
      ),
    );
    final plan = QuestionnaireDraftUpgradePlanner.plan(
      source: fixture.source,
      target: fixture.target,
      sourceAnswers: fixture.sourceAnswers,
      compatibilities: fixture.compatibilities,
    );

    final upgraded = await journal.upgradeDraft(
      sourceDraftId: source!.draftId,
      appUserId: source.appUserId,
      deviceId: 'device-1',
      targetVersion: fixture.target,
      copiedAnswers: plan.copiedAnswers,
    );
    final retried = await journal.upgradeDraft(
      sourceDraftId: source.draftId,
      appUserId: source.appUserId,
      deviceId: 'device-1',
      targetVersion: fixture.target,
      copiedAnswers: plan.copiedAnswers,
    );

    expect(retried, upgraded);
    expect(
      upgraded.draftId,
      '${source.draftId}:questionnaire-upgrade:${fixture.target.id}',
    );
    expect(upgraded.questionnaireVersionId, fixture.target.id);
    expect(upgraded.upgradedFromDraftId, source.draftId);
    expect(upgraded.answers, plan.copiedAnswers);
    final drafts = await journal.listDrafts(appUserId: source.appUserId);
    expect(drafts, hasLength(2));
    expect(
      drafts.singleWhere((draft) => draft.draftId == source.draftId).answers,
      unorderedEquals(fixture.sourceAnswers),
    );
    final targetCommands = await (database.select(
      database.dbSyncOutbox,
    )..where((row) => row.aggregateId.equals(upgraded.draftId))).get();
    expect(targetCommands, hasLength(1));
    expect(
      targetCommands.single.payloadJson,
      contains('"upgraded_from_draft_id":"${source.draftId}"'),
    );
  });

  test('问卷升级不允许他人读取来源，失败时不改写原稿', () async {
    final database = LocalDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final journal = ContactJournal(
      database: database,
      clock: _FixedClock(DateTime.utc(2030, 1, 8, 18, 30)),
      idGenerator: _SequenceIdGenerator(['source-private']),
    );
    final fixture = _draftUpgradeFixture();
    final catalog = QuestionnaireCatalog(database: database);
    await catalog.installPublishedVersion(fixture.source);
    await catalog.installPublishedVersion(fixture.target);
    final source = await journal.saveDraft(
      ContactDraftInput(
        deviceId: 'device-1',
        appUserId: 'app-user-1',
        workspaceId: 'workspace-1',
        projectId: fixture.source.projectId,
        questionnaireVersionId: fixture.source.id,
        channel: ContactChannel.videoCall,
        answers: fixture.sourceAnswers,
      ),
    );

    await expectLater(
      journal.upgradeDraft(
        sourceDraftId: source!.draftId,
        appUserId: 'app-user-2',
        deviceId: 'device-2',
        targetVersion: fixture.target,
        copiedAnswers: const [],
      ),
      throwsA(
        isA<ContactValidationException>().having(
          (error) => error.code,
          'code',
          'contact_draft_not_found',
        ),
      ),
    );
    await expectLater(
      journal.upgradeDraft(
        sourceDraftId: source.draftId,
        appUserId: source.appUserId,
        deviceId: 'device-1',
        targetVersion: fixture.target,
        copiedAnswers: const [
          ShortTextQuestionnaireAnswer(
            questionId: 'missing-target-question',
            value: 'invalid',
          ),
        ],
      ),
      throwsA(
        isA<ContactValidationException>().having(
          (error) => error.code,
          'code',
          'contact_draft_upgrade_answers_invalid',
        ),
      ),
    );

    final drafts = await journal.listDrafts(appUserId: source.appUserId);
    expect(drafts, hasLength(1));
    expect(drafts.single.draftId, source.draftId);
    expect(drafts.single.answers, unorderedEquals(fixture.sourceAnswers));
  });

  test('不完整草稿不能正式提交且不进入个人统计', () async {
    final journal = _journal(['draft-incomplete']);
    final draft = await journal.saveDraft(
      const ContactDraftInput(
        deviceId: 'device-1',
        appUserId: 'app-user-1',
        workspaceId: 'personal-workspace-1',
        projectId: 'project-1',
        questionnaireVersionId: 'questionnaire-v1',
        channel: ContactChannel.voiceCall,
      ),
    );

    await expectLater(
      journal.submitDraft(
        draftId: draft!.draftId,
        appUserId: 'app-user-1',
        deviceId: 'device-1',
      ),
      throwsA(
        isA<ContactValidationException>().having(
          (error) => error.code,
          'code',
          'contact_draft_incomplete',
        ),
      ),
    );
    final summary = await journal.summarizePersonalContacts(
      appUserId: 'app-user-1',
      workspaceId: 'personal-workspace-1',
      projectId: 'project-1',
      fromUtc: DateTime.utc(2030, 1, 8),
      untilUtc: DateTime.utc(2030, 1, 9),
    );
    expect(summary.contactSessionCount, 0);
    expect(
      (await journal.listDrafts(appUserId: 'app-user-1')).single.draftId,
      'draft-incomplete',
    );
  });
}

({
  QuestionnaireVersion source,
  QuestionnaireVersion target,
  List<QuestionnaireAnswer> sourceAnswers,
  List<AuditedQuestionnaireAnswerCompatibility> compatibilities,
})
_draftUpgradeFixture() {
  final raw =
      jsonDecode(
            File(
              'fixtures/questionnaire/questionnaire-draft-upgrade-contract-v1.json',
            ).readAsStringSync(),
          )
          as Map<String, Object?>;
  final source = QuestionnaireContract.parseVersion(raw['source']);
  final questionsById = {
    for (final question in source.questions) question.id: question,
  };
  return (
    source: source,
    target: QuestionnaireContract.parseVersion(raw['target']),
    sourceAnswers: [
      for (final rawAnswer in raw['source_answers']! as List<Object?>)
        if (QuestionnaireContract.parseAnswer(rawAnswer) case final answer)
          QuestionnaireAnswerFactory.create(
            question: questionsById[answer.questionId]!,
            state: answer.state,
            value: answer.value,
          ),
    ],
    compatibilities: [
      for (final value in raw['audited_compatibilities']! as List<Object?>)
        if (value case final Map<String, Object?> item)
          AuditedQuestionnaireAnswerCompatibility(
            decisionId: item['decision_id']! as String,
            sourceQuestionId: item['source_question_id']! as String,
            targetQuestionId: item['target_question_id']! as String,
          ),
    ],
  );
}

ContactJournal _journal(List<String> ids, {DateTime? now}) {
  final database = LocalDatabase(NativeDatabase.memory());
  addTearDown(database.close);
  return ContactJournal(
    database: database,
    clock: _FixedClock(now ?? DateTime.utc(2030, 1, 8, 18, 30)),
    idGenerator: _SequenceIdGenerator(ids),
  );
}

AnonymousContactSubmission _submission({
  String appUserId = 'app-user-1',
  String workspaceId = 'personal-workspace-1',
  String projectId = 'project-1',
  String questionnaireVersionId = 'questionnaire-v1',
  String deviceId = 'device-1',
  required DateTime occurredAtUtc,
  String occurredTimeZone = 'America/Chicago',
  ContactChannel channel = ContactChannel.videoCall,
  String? channelDetail,
  ContactLocation location = const NotApplicableContactLocation(),
  required int reachCount,
  required int interestLevel,
  List<QuestionnaireAnswer> answers = const [],
}) {
  return AnonymousContactSubmission(
    appUserId: appUserId,
    workspaceId: workspaceId,
    projectId: projectId,
    questionnaireVersionId: questionnaireVersionId,
    deviceId: deviceId,
    occurredAtUtc: occurredAtUtc,
    occurredTimeZone: occurredTimeZone,
    channel: channel,
    channelDetail: channelDetail,
    location: location,
    reachCount: reachCount,
    interestLevel: interestLevel,
    answers: answers,
  );
}

final class _FixedClock implements AppClock {
  const _FixedClock(this.value);

  final DateTime value;

  @override
  DateTime now() => value;
}

final class _MutableClock implements AppClock {
  _MutableClock(this.value);

  DateTime value;

  @override
  DateTime now() => value;
}

final class _SequenceIdGenerator implements IdGenerator {
  _SequenceIdGenerator(this.values);

  final List<String> values;
  var _index = 0;

  @override
  String next() => values[_index++];
}
