import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tongxingzhe_app/data/local_database.dart';
import 'package:tongxingzhe_app/features/contact_journal/contact_journal.dart';
import 'package:tongxingzhe_app/features/contact_journal/contact_models.dart';

import '../../support/fake_runtime_values.dart';

void main() {
  test('接触尝试独立保存且不进入接触指标', () async {
    final database = LocalDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final journal = ContactJournal(
      database: database,
      clock: FixedClock(DateTime.utc(2030, 1, 8, 18, 30)),
      idGenerator: SequenceIdGenerator(['attempt-1', 'command-1']),
    );

    final receipt = await journal.recordContactAttempt(
      ContactAttemptSubmission(
        appUserId: 'app-user-1',
        workspaceId: 'workspace-1',
        projectId: 'project-1',
        deviceId: 'device-1',
        occurredAtUtc: DateTime.utc(2030, 1, 8, 18),
        occurredTimeZone: 'America/Chicago',
        channel: ContactChannel.voiceCall,
      ),
    );

    expect(receipt.attemptId, 'attempt-1');
    final attempts = await journal.listContactAttempts(
      appUserId: 'app-user-1',
      workspaceId: 'workspace-1',
      projectId: 'project-1',
    );
    expect(attempts, hasLength(1));
    expect(attempts.single.channel, ContactChannel.voiceCall);
    expect(attempts.single.linkedContactId, isNull);

    final command = await database.select(database.dbSyncOutbox).getSingle();
    expect(command.commandType, 'contact.attempt.submit.v1');
    final payload = jsonDecode(command.payloadJson) as Map<String, Object?>;
    expect(payload['attempt_id'], 'attempt-1');
    expect(payload.containsKey('reach_count'), isFalse);
    expect(payload.containsKey('interest_level'), isFalse);
    expect(payload.containsKey('answers'), isFalse);

    final summary = await journal.summarizePersonalContacts(
      appUserId: 'app-user-1',
      workspaceId: 'workspace-1',
      projectId: 'project-1',
      fromUtc: DateTime.utc(2030, 1, 8),
      untilUtc: DateTime.utc(2030, 1, 9),
    );
    expect(summary.contactSessionCount, 0);
    expect(summary.reachCount, 0);
    expect(summary.interestDistribution, [0, 0, 0, 0, 0]);
  });

  test('其他直接渠道必须有明细', () async {
    final database = LocalDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final journal = ContactJournal(
      database: database,
      clock: FixedClock(DateTime.utc(2030, 1, 8, 18, 30)),
      idGenerator: SequenceIdGenerator(const []),
    );

    await expectLater(
      journal.recordContactAttempt(
        ContactAttemptSubmission(
          appUserId: 'app-user-1',
          workspaceId: 'workspace-1',
          projectId: 'project-1',
          deviceId: 'device-1',
          occurredAtUtc: DateTime.utc(2030, 1, 8, 18),
          occurredTimeZone: 'America/Chicago',
          channel: ContactChannel.otherDirect,
        ),
      ),
      throwsA(
        isA<ContactValidationException>().having(
          (error) => error.code,
          'code',
          'other_channel_detail_required',
        ),
      ),
    );
  });

  test('后来回应新建接触并保留原尝试', () async {
    final database = LocalDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final journal = ContactJournal(
      database: database,
      clock: FixedClock(DateTime.utc(2030, 1, 8, 18, 30)),
      idGenerator: SequenceIdGenerator([
        'attempt-1',
        'attempt-command-1',
        'contact-1',
        'revision-1',
        'contact-command-1',
      ]),
    );
    await journal.recordContactAttempt(
      ContactAttemptSubmission(
        appUserId: 'app-user-1',
        workspaceId: 'workspace-1',
        projectId: 'project-1',
        deviceId: 'device-1',
        occurredAtUtc: DateTime.utc(2030, 1, 8, 17),
        occurredTimeZone: 'America/Chicago',
        channel: ContactChannel.voiceCall,
      ),
    );

    final contact = await journal.submitAnonymousContact(
      AnonymousContactSubmission(
        appUserId: 'app-user-1',
        workspaceId: 'workspace-1',
        projectId: 'project-1',
        questionnaireVersionId: 'questionnaire-1',
        deviceId: 'device-1',
        occurredAtUtc: DateTime.utc(2030, 1, 8, 18),
        occurredTimeZone: 'America/Chicago',
        channel: ContactChannel.voiceCall,
        location: const NotApplicableContactLocation(),
        reachCount: 1,
        interestLevel: 2,
        sourceAttemptId: 'attempt-1',
      ),
    );

    expect(contact.contactId, 'contact-1');
    final attempt = await journal.contactAttemptByIdForOwner(
      attemptId: 'attempt-1',
      appUserId: 'app-user-1',
    );
    expect(attempt?.linkedContactId, 'contact-1');
    expect(
      await database.select(database.dbContactAttempts).get(),
      hasLength(1),
    );
    expect(
      await database.select(database.dbContactRecords).get(),
      hasLength(1),
    );

    final commands = await database.select(database.dbSyncOutbox).get();
    final contactCommand = commands.singleWhere(
      (row) => row.commandType == 'contact.submit.v1',
    );
    final payload =
        jsonDecode(contactCommand.payloadJson) as Map<String, Object?>;
    expect(payload['source_attempt_id'], 'attempt-1');
  });
}
