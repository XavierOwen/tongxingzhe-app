import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tongxingzhe_app/data/local_database.dart';
import 'package:tongxingzhe_app/features/contact_journal/contact_journal.dart';
import 'package:tongxingzhe_app/features/contact_journal/contact_models.dart';
import 'package:tongxingzhe_app/foundation/runtime_values.dart';

void main() {
  test('双周期汇总分别读取两个相邻窗口的完整摘要', () async {
    final database = LocalDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    await _insertContact(
      database,
      contactId: 'previous-contact',
      occurredAtUtc: DateTime.utc(2029, 12, 31, 23, 59),
      reachCount: 2,
      interestLevel: 1,
      channel: 'voice_call',
    );
    await _insertContact(
      database,
      contactId: 'current-contact',
      occurredAtUtc: DateTime.utc(2030, 1, 1),
      reachCount: 3,
      interestLevel: 3,
      channel: 'face_to_face',
    );
    await _insertContact(
      database,
      contactId: 'other-project-contact',
      occurredAtUtc: DateTime.utc(2030, 1, 2),
      reachCount: 9,
      interestLevel: 4,
      channel: 'video_call',
      projectId: 'project-2',
    );
    await _insertContact(
      database,
      contactId: 'voided-contact',
      occurredAtUtc: DateTime.utc(2030, 1, 3),
      reachCount: 9,
      interestLevel: 4,
      channel: 'video_call',
      lifecycleStatus: 'voided',
    );
    await _insertContact(
      database,
      contactId: 'right-boundary-contact',
      occurredAtUtc: DateTime.utc(2030, 1, 8),
      reachCount: 9,
      interestLevel: 4,
      channel: 'video_call',
    );

    final journal = ContactJournal(
      database: database,
      clock: const _FixedClock(),
      idGenerator: _UnusedIdGenerator(),
    );
    final pair = await journal.summarizePersonalContactsForPeriods(
      appUserId: 'app-user-1',
      workspaceId: 'workspace-1',
      projectId: 'project-1',
      previousFromUtc: DateTime.utc(2029, 12, 25),
      previousUntilUtc: DateTime.utc(2030, 1, 1),
      currentFromUtc: DateTime.utc(2030, 1, 1),
      currentUntilUtc: DateTime.utc(2030, 1, 8),
    );

    expect(pair.previous.contactSessionCount, 1);
    expect(pair.previous.reachCount, 2);
    expect(pair.previous.interestDistribution, [0, 1, 0, 0, 0]);
    expect(pair.previous.channelDistribution, [0, 1, 0, 0, 0, 0, 0]);
    expect(pair.current.contactSessionCount, 1);
    expect(pair.current.reachCount, 3);
    expect(pair.current.interestDistribution, [0, 0, 0, 1, 0]);
    expect(pair.current.channelDistribution, [1, 0, 0, 0, 0, 0, 0]);
  });

  test('双周期汇总拒绝不相邻窗口', () async {
    final database = LocalDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final journal = ContactJournal(
      database: database,
      clock: const _FixedClock(),
      idGenerator: _UnusedIdGenerator(),
    );

    await expectLater(
      journal.summarizePersonalContactsForPeriods(
        appUserId: 'app-user-1',
        workspaceId: 'workspace-1',
        projectId: 'project-1',
        previousFromUtc: DateTime.utc(2029, 12, 25),
        previousUntilUtc: DateTime.utc(2030, 1, 1),
        currentFromUtc: DateTime.utc(2030, 1, 2),
        currentUntilUtc: DateTime.utc(2030, 1, 9),
      ),
      throwsA(
        isA<ContactValidationException>().having(
          (error) => error.code,
          'code',
          'invalid_comparison_summary_periods',
        ),
      ),
    );
  });

  test('双周期汇总拒绝非七日或非 UTC 午夜窗口', () async {
    final database = LocalDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final journal = ContactJournal(
      database: database,
      clock: const _FixedClock(),
      idGenerator: _UnusedIdGenerator(),
    );

    for (final periods in [
      (
        previousFrom: DateTime.utc(2029, 12, 26),
        previousUntil: DateTime.utc(2030, 1, 1),
        currentFrom: DateTime.utc(2030, 1, 1),
        currentUntil: DateTime.utc(2030, 1, 8),
      ),
      (
        previousFrom: DateTime.utc(2029, 12, 25, 1),
        previousUntil: DateTime.utc(2030, 1, 1, 1),
        currentFrom: DateTime.utc(2030, 1, 1, 1),
        currentUntil: DateTime.utc(2030, 1, 8, 1),
      ),
    ]) {
      await expectLater(
        journal.summarizePersonalContactsForPeriods(
          appUserId: 'app-user-1',
          workspaceId: 'workspace-1',
          projectId: 'project-1',
          previousFromUtc: periods.previousFrom,
          previousUntilUtc: periods.previousUntil,
          currentFromUtc: periods.currentFrom,
          currentUntilUtc: periods.currentUntil,
        ),
        throwsA(
          isA<ContactValidationException>().having(
            (error) => error.code,
            'code',
            'invalid_comparison_summary_periods',
          ),
        ),
      );
    }
  });
}

Future<void> _insertContact(
  LocalDatabase database, {
  required String contactId,
  required DateTime occurredAtUtc,
  required int reachCount,
  required int interestLevel,
  required String channel,
  String projectId = 'project-1',
  String lifecycleStatus = 'active',
}) => database
    .into(database.dbContactRecords)
    .insert(
      DbContactRecordsCompanion.insert(
        contactId: contactId,
        appUserId: 'app-user-1',
        workspaceId: 'workspace-1',
        projectId: projectId,
        questionnaireVersionId: 'questionnaire-1',
        occurredAtUtc: occurredAtUtc,
        occurredTimeZone: 'UTC',
        firstSubmittedAtUtc: DateTime.utc(2030, 1, 8, 12),
        channel: channel,
        locationKind: 'not_applicable',
        reachCount: reachCount,
        interestLevel: interestLevel,
        currentRevision: 1,
        lifecycleStatus: lifecycleStatus,
      ),
    );

final class _FixedClock implements AppClock {
  const _FixedClock();

  @override
  DateTime now() => DateTime.utc(2030, 1, 8, 18, 30);
}

final class _UnusedIdGenerator implements IdGenerator {
  @override
  String next() => 'unused';
}
