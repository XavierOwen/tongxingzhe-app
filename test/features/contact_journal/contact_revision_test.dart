import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tongxingzhe_app/data/local_database.dart';
import 'package:tongxingzhe_app/features/contact_journal/contact_journal.dart';
import 'package:tongxingzhe_app/features/contact_journal/contact_models.dart';
import 'package:tongxingzhe_app/foundation/runtime_values.dart';

void main() {
  test('更正追加完整快照并按新发生时间重新归期', () async {
    final database = _database();
    final submittedAt = DateTime.utc(2030, 1, 10, 18);
    final journal = _journal(
      database,
      now: submittedAt,
      ids: ['contact-1', 'revision-1', 'command-1'],
    );
    await journal.submitAnonymousContact(
      _submission(
        occurredAtUtc: DateTime.utc(2030, 1, 9, 17),
        reachCount: 1,
        interestLevel: 2,
        answers: const [
          BooleanQuestionnaireAnswer(
            questionId: 'follow_up_consent',
            value: false,
          ),
        ],
      ),
    );

    final januaryBefore = await _summary(
      journal,
      fromUtc: DateTime.utc(2030, 1),
      untilUtc: DateTime.utc(2030, 2),
    );
    expect(januaryBefore.contactSessionCount, 1);

    final correctionJournal = _journal(
      database,
      now: DateTime.utc(2030, 2, 3, 12),
      ids: ['revision-2', 'command-2'],
    );
    final receipt = await correctionJournal.correctContact(
      ContactCorrectionSubmission(
        contactId: 'contact-1',
        appUserId: 'app-user-1',
        workspaceId: 'workspace-1',
        projectId: 'project-1',
        deviceId: 'device-1',
        baseRevision: 1,
        reason: '修正发生日期和触达人数',
        occurredAtUtc: DateTime.utc(2030, 2, 2, 16),
        occurredTimeZone: 'America/Chicago',
        channel: ContactChannel.voiceCall,
        location: const NotApplicableContactLocation(),
        reachCount: 3,
        interestLevel: 4,
        answers: const [
          BooleanQuestionnaireAnswer(
            questionId: 'follow_up_consent',
            value: true,
          ),
        ],
      ),
    );

    expect(receipt.revisionNumber, 2);
    expect(receipt.kind, ContactRevisionKind.corrected);
    final current = await correctionJournal.contactById('contact-1');
    expect(current!.revisionNumber, 2);
    expect(current.firstSubmittedAtUtc, submittedAt);
    expect(current.occurredAtUtc, DateTime.utc(2030, 2, 2, 16));
    expect(current.channel, ContactChannel.voiceCall);
    expect(current.reachCount, 3);
    expect(current.interestLevel, 4);
    expect(current.lifecycleStatus, ContactLifecycleStatus.active);
    expect(current.answers, const [
      BooleanQuestionnaireAnswer(questionId: 'follow_up_consent', value: true),
    ]);

    final history = await correctionJournal.listContactRevisions(
      contactId: 'contact-1',
      appUserId: 'app-user-1',
    );
    expect(history.map((revision) => revision.revisionNumber), [2, 1]);
    expect(history.first.kind, ContactRevisionKind.corrected);
    expect(history.first.reason, '修正发生日期和触达人数');
    expect(history.last.kind, ContactRevisionKind.submitted);
    expect(history.last.reason, isNull);
    expect(history.last.occurredAtUtc, DateTime.utc(2030, 1, 9, 17));
    expect(history.last.reachCount, 1);
    expect(history.last.answers, const [
      BooleanQuestionnaireAnswer(questionId: 'follow_up_consent', value: false),
    ]);

    final januaryAfter = await _summary(
      correctionJournal,
      fromUtc: DateTime.utc(2030, 1),
      untilUtc: DateTime.utc(2030, 2),
    );
    final februaryAfter = await _summary(
      correctionJournal,
      fromUtc: DateTime.utc(2030, 2),
      untilUtc: DateTime.utc(2030, 3),
    );
    expect(januaryAfter.contactSessionCount, 0);
    expect(februaryAfter.contactSessionCount, 1);
    expect(februaryAfter.reachCount, 3);

    final commands = await database.select(database.dbSyncOutbox).get();
    expect(commands.map((command) => command.commandType), [
      'contact.submit.v1',
      'contact.revise.v1',
    ]);
    expect(commands.last.baseRevision, 1);
    final payload =
        jsonDecode(commands.last.payloadJson) as Map<String, Object?>;
    expect(payload['reason'], '修正发生日期和触达人数');
    expect(payload['reach_count'], 3);
  });

  test('空原因和过期 base revision 都不会留下部分更改', () async {
    final database = _database();
    final journal = _journal(
      database,
      now: DateTime.utc(2030, 1, 10, 18),
      ids: [
        'contact-1',
        'revision-1',
        'command-1',
        'stale-revision',
        'stale-command',
      ],
    );
    await journal.submitAnonymousContact(
      _submission(
        occurredAtUtc: DateTime.utc(2030, 1, 9, 17),
        reachCount: 1,
        interestLevel: 2,
      ),
    );

    await expectLater(
      journal.correctContact(
        _correction(reason: '   ', baseRevision: 1, reachCount: 2),
      ),
      throwsA(
        isA<ContactValidationException>().having(
          (error) => error.code,
          'code',
          'contact_reason_required',
        ),
      ),
    );
    await expectLater(
      journal.correctContact(
        _correction(reason: '基于旧页面提交', baseRevision: 2, reachCount: 2),
      ),
      throwsA(
        isA<ContactValidationException>().having(
          (error) => error.code,
          'code',
          'contact_revision_conflict',
        ),
      ),
    );

    final current = await journal.contactById('contact-1');
    expect(current!.revisionNumber, 1);
    expect(current.reachCount, 1);
    expect(
      await journal.listContactRevisions(
        contactId: 'contact-1',
        appUserId: 'app-user-1',
      ),
      hasLength(1),
    );
    expect(await database.select(database.dbSyncOutbox).get(), hasLength(1));
  });

  test('作废追加历史、保留实体并退出个人指标', () async {
    final database = _database();
    final journal = _journal(
      database,
      now: DateTime.utc(2030, 1, 10, 18),
      ids: ['contact-1', 'revision-1', 'command-1', 'revision-2', 'command-2'],
    );
    await journal.submitAnonymousContact(
      _submission(
        occurredAtUtc: DateTime.utc(2030, 1, 9, 17),
        reachCount: 2,
        interestLevel: 3,
      ),
    );

    final receipt = await journal.voidContact(
      const ContactVoidSubmission(
        contactId: 'contact-1',
        appUserId: 'app-user-1',
        workspaceId: 'workspace-1',
        projectId: 'project-1',
        deviceId: 'device-1',
        baseRevision: 1,
        reason: '重复录入',
      ),
    );

    expect(receipt.kind, ContactRevisionKind.voided);
    final current = await journal.contactById('contact-1');
    expect(current, isNotNull);
    expect(current!.revisionNumber, 2);
    expect(current.lifecycleStatus, ContactLifecycleStatus.voided);
    final history = await journal.listContactRevisions(
      contactId: 'contact-1',
      appUserId: 'app-user-1',
    );
    expect(history, hasLength(2));
    expect(history.first.kind, ContactRevisionKind.voided);
    expect(history.first.reason, '重复录入');
    expect(history.first.reachCount, 2);

    final summary = await _summary(
      journal,
      fromUtc: DateTime.utc(2030, 1),
      untilUtc: DateTime.utc(2030, 2),
    );
    expect(summary.contactSessionCount, 0);
    expect(summary.reachCount, 0);

    final commands = await database.select(database.dbSyncOutbox).get();
    expect(commands.last.commandType, 'contact.void.v1');
    expect(commands.last.baseRevision, 1);
    expect(
      (jsonDecode(commands.last.payloadJson) as Map<String, Object?>)['reason'],
      '重复录入',
    );
  });

  test('其他用户不能读取、更正或作废接触历史', () async {
    final database = _database();
    final journal = _journal(
      database,
      now: DateTime.utc(2030, 1, 10, 18),
      ids: [
        'contact-1',
        'revision-1',
        'command-1',
        'revision-2',
        'command-2',
        'revision-3',
        'command-3',
      ],
    );
    await journal.submitAnonymousContact(
      _submission(
        occurredAtUtc: DateTime.utc(2030, 1, 9, 17),
        reachCount: 1,
        interestLevel: 2,
      ),
    );

    expect(
      await journal.contactByIdForOwner(
        contactId: 'contact-1',
        appUserId: 'app-user-2',
      ),
      isNull,
    );
    expect(
      await journal.listContactRevisions(
        contactId: 'contact-1',
        appUserId: 'app-user-2',
      ),
      isEmpty,
    );
    await expectLater(
      journal.correctContact(
        _correction(
          appUserId: 'app-user-2',
          reason: '不应允许',
          baseRevision: 1,
          reachCount: 2,
        ),
      ),
      throwsA(
        isA<ContactValidationException>().having(
          (error) => error.code,
          'code',
          'contact_not_found',
        ),
      ),
    );
    await expectLater(
      journal.voidContact(
        const ContactVoidSubmission(
          contactId: 'contact-1',
          appUserId: 'app-user-2',
          workspaceId: 'workspace-1',
          projectId: 'project-1',
          deviceId: 'device-1',
          baseRevision: 1,
          reason: '不应允许',
        ),
      ),
      throwsA(
        isA<ContactValidationException>().having(
          (error) => error.code,
          'code',
          'contact_not_found',
        ),
      ),
    );
    expect((await journal.contactById('contact-1'))!.revisionNumber, 1);
  });
}

LocalDatabase _database() {
  final database = LocalDatabase(NativeDatabase.memory());
  addTearDown(database.close);
  return database;
}

ContactJournal _journal(
  LocalDatabase database, {
  required DateTime now,
  required List<String> ids,
}) {
  return ContactJournal(
    database: database,
    clock: _FixedClock(now),
    idGenerator: _SequenceIdGenerator(ids),
  );
}

AnonymousContactSubmission _submission({
  required DateTime occurredAtUtc,
  required int reachCount,
  required int interestLevel,
  List<QuestionnaireAnswer> answers = const [],
}) {
  return AnonymousContactSubmission(
    appUserId: 'app-user-1',
    workspaceId: 'workspace-1',
    projectId: 'project-1',
    questionnaireVersionId: 'questionnaire-v1',
    deviceId: 'device-1',
    occurredAtUtc: occurredAtUtc,
    occurredTimeZone: 'America/Chicago',
    channel: ContactChannel.videoCall,
    location: const NotApplicableContactLocation(),
    reachCount: reachCount,
    interestLevel: interestLevel,
    answers: answers,
  );
}

ContactCorrectionSubmission _correction({
  String appUserId = 'app-user-1',
  required String reason,
  required int baseRevision,
  required int reachCount,
}) {
  return ContactCorrectionSubmission(
    contactId: 'contact-1',
    appUserId: appUserId,
    workspaceId: 'workspace-1',
    projectId: 'project-1',
    deviceId: 'device-1',
    baseRevision: baseRevision,
    reason: reason,
    occurredAtUtc: DateTime.utc(2030, 1, 9, 17),
    occurredTimeZone: 'America/Chicago',
    channel: ContactChannel.videoCall,
    location: const NotApplicableContactLocation(),
    reachCount: reachCount,
    interestLevel: 2,
  );
}

Future<PersonalContactSummary> _summary(
  ContactJournal journal, {
  required DateTime fromUtc,
  required DateTime untilUtc,
}) {
  return journal.summarizePersonalContacts(
    appUserId: 'app-user-1',
    workspaceId: 'workspace-1',
    projectId: 'project-1',
    fromUtc: fromUtc,
    untilUtc: untilUtc,
  );
}

final class _FixedClock implements AppClock {
  const _FixedClock(this.value);

  final DateTime value;

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
