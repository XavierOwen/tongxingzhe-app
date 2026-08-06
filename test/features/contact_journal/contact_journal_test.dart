import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tongxingzhe_app/data/local_database.dart';
import 'package:tongxingzhe_app/features/contact_journal/contact_journal.dart';
import 'package:tongxingzhe_app/features/contact_journal/contact_models.dart';
import 'package:tongxingzhe_app/foundation/runtime_values.dart';
import 'package:tongxingzhe_app/regions/region_catalog.dart';
import 'package:tongxingzhe_app/regions/region_models.dart';

void main() {
  test('合法匿名接触提交后可立即读取并显示待同步', () async {
    final database = LocalDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    await RegionCatalog(database).installSnapshot(
      const CanonicalRegionSnapshot(
        version: 'regions-test-v1',
        nodes: [
          CanonicalRegionNode(
            regionId: 'region-chicago',
            canonicalName: 'Chicago',
            kind: RegionKind.city,
          ),
          CanonicalRegionNode(
            regionId: 'region-university-of-chicago',
            parentRegionId: 'region-chicago',
            canonicalName: 'University of Chicago',
            kind: RegionKind.institution,
            attributes: {'campus'},
          ),
        ],
      ),
    );
    final journal = ContactJournal(
      database: database,
      clock: _FixedClock(DateTime.utc(2030, 1, 8, 18, 30)),
      idGenerator: _SequenceIdGenerator([
        'contact-1',
        'revision-1',
        'command-1',
      ]),
    );

    final receipt = await journal.submitAnonymousContact(
      AnonymousContactSubmission(
        appUserId: 'app-user-1',
        workspaceId: 'personal-workspace-1',
        projectId: 'project-1',
        questionnaireVersionId: 'questionnaire-v1',
        deviceId: 'device-1',
        occurredAtUtc: DateTime.utc(2030, 1, 8, 17),
        occurredTimeZone: 'America/Chicago',
        channel: ContactChannel.faceToFace,
        location: const ResolvedContactLocation(
          placeName: 'University of Chicago',
          smallestRegionId: 'region-university-of-chicago',
          regionTreeVersion: 'regions-test-v1',
        ),
        reachCount: 3,
        interestLevel: 3,
      ),
    );

    expect(receipt.contactId, 'contact-1');
    expect(receipt.revisionNumber, 1);
    expect(receipt.syncState, LocalSyncState.pending);

    final stored = await journal.contactById('contact-1');
    expect(stored, isNotNull);
    expect(stored!.contactId, 'contact-1');
    expect(stored.revisionNumber, 1);
    expect(stored.channel, ContactChannel.faceToFace);
    expect(stored.reachCount, 3);
    expect(stored.interestLevel, 3);
    expect(
      stored.location,
      const ResolvedContactLocation(
        placeName: 'University of Chicago',
        smallestRegionId: 'region-university-of-chicago',
        regionTreeVersion: 'regions-test-v1',
      ),
    );
    expect(stored.syncState, LocalSyncState.pending);
  });

  test('纯线上接触把地点明确保存为 N/A 而不是空值', () async {
    final journal = _journal([
      'contact-online',
      'revision-online',
      'command-online',
    ]);

    await journal.submitAnonymousContact(
      AnonymousContactSubmission(
        appUserId: 'app-user-1',
        workspaceId: 'personal-workspace-1',
        projectId: 'project-1',
        questionnaireVersionId: 'questionnaire-v1',
        deviceId: 'device-1',
        occurredAtUtc: DateTime.utc(2030, 1, 8, 17),
        occurredTimeZone: 'America/Chicago',
        channel: ContactChannel.videoCall,
        location: const NotApplicableContactLocation(),
        reachCount: 1,
        interestLevel: 2,
      ),
    );

    final stored = await journal.contactById('contact-online');
    expect(stored!.location, const NotApplicableContactLocation());
  });

  test('面对面接触不能把地点记为 N/A', () async {
    final journal = _journal([
      'contact-invalid-location',
      'revision-invalid-location',
      'command-invalid-location',
    ]);

    await expectLater(
      journal.submitAnonymousContact(
        AnonymousContactSubmission(
          appUserId: 'app-user-1',
          workspaceId: 'personal-workspace-1',
          projectId: 'project-1',
          questionnaireVersionId: 'questionnaire-v1',
          deviceId: 'device-1',
          occurredAtUtc: DateTime.utc(2030, 1, 8, 17),
          occurredTimeZone: 'America/Chicago',
          channel: ContactChannel.faceToFace,
          location: const NotApplicableContactLocation(),
          reachCount: 1,
          interestLevel: 2,
        ),
      ),
      throwsA(
        isA<ContactValidationException>().having(
          (error) => error.code,
          'code',
          'face_to_face_location_required',
        ),
      ),
    );
    expect(await journal.contactById('contact-invalid-location'), isNull);
  });

  test('已有经纬度但尚无区域时明确保存为待解析', () async {
    final journal = _journal([
      'contact-pending-region',
      'revision-pending-region',
      'command-pending-region',
    ]);

    await journal.submitAnonymousContact(
      AnonymousContactSubmission(
        appUserId: 'app-user-1',
        workspaceId: 'personal-workspace-1',
        projectId: 'project-1',
        questionnaireVersionId: 'questionnaire-v1',
        deviceId: 'device-1',
        occurredAtUtc: DateTime.utc(2030, 1, 8, 17),
        occurredTimeZone: 'America/Chicago',
        channel: ContactChannel.faceToFace,
        location: const PendingContactLocation(
          latitude: 41.7886,
          longitude: -87.5987,
          accuracyMeters: 12,
        ),
        reachCount: 2,
        interestLevel: 4,
      ),
    );

    final stored = await journal.contactById('contact-pending-region');
    expect(
      stored!.location,
      const PendingContactLocation(
        latitude: 41.7886,
        longitude: -87.5987,
        accuracyMeters: 12,
      ),
    );
  });

  test('真实接触的触达人数必须至少为一人', () async {
    final journal = _journal([
      'contact-zero-reach',
      'revision-zero-reach',
      'command-zero-reach',
    ]);

    await expectLater(
      journal.submitAnonymousContact(
        AnonymousContactSubmission(
          appUserId: 'app-user-1',
          workspaceId: 'personal-workspace-1',
          projectId: 'project-1',
          questionnaireVersionId: 'questionnaire-v1',
          deviceId: 'device-1',
          occurredAtUtc: DateTime.utc(2030, 1, 8, 17),
          occurredTimeZone: 'America/Chicago',
          channel: ContactChannel.videoCall,
          location: const NotApplicableContactLocation(),
          reachCount: 0,
          interestLevel: 2,
        ),
      ),
      throwsA(
        isA<ContactValidationException>().having(
          (error) => error.code,
          'code',
          'reach_count_must_be_positive',
        ),
      ),
    );
  });

  test('单次兴趣只接受全平台固定的 0 到 4', () async {
    final journal = _journal([
      'contact-invalid-interest',
      'revision-invalid-interest',
      'command-invalid-interest',
    ]);

    await expectLater(
      journal.submitAnonymousContact(
        AnonymousContactSubmission(
          appUserId: 'app-user-1',
          workspaceId: 'personal-workspace-1',
          projectId: 'project-1',
          questionnaireVersionId: 'questionnaire-v1',
          deviceId: 'device-1',
          occurredAtUtc: DateTime.utc(2030, 1, 8, 17),
          occurredTimeZone: 'America/Chicago',
          channel: ContactChannel.videoCall,
          location: const NotApplicableContactLocation(),
          reachCount: 1,
          interestLevel: 5,
        ),
      ),
      throwsA(
        isA<ContactValidationException>().having(
          (error) => error.code,
          'code',
          'interest_level_out_of_range',
        ),
      ),
    );
  });

  test('布尔问卷答案与接触和首个 revision 一起保存', () async {
    final journal = _journal([
      'contact-with-answer',
      'revision-with-answer',
      'command-with-answer',
    ]);

    await journal.submitAnonymousContact(
      AnonymousContactSubmission(
        appUserId: 'app-user-1',
        workspaceId: 'personal-workspace-1',
        projectId: 'project-1',
        questionnaireVersionId: 'questionnaire-v1',
        deviceId: 'device-1',
        occurredAtUtc: DateTime.utc(2030, 1, 8, 17),
        occurredTimeZone: 'America/Chicago',
        channel: ContactChannel.voiceCall,
        location: const NotApplicableContactLocation(),
        reachCount: 1,
        interestLevel: 3,
        answers: const [
          BooleanQuestionnaireAnswer(
            questionId: 'follow_up_consent',
            value: true,
          ),
        ],
      ),
    );

    final stored = await journal.contactById('contact-with-answer');
    expect(stored!.answers, const [
      BooleanQuestionnaireAnswer(questionId: 'follow_up_consent', value: true),
    ]);
  });

  test('问卷的未知状态与布尔值分开保存', () async {
    final journal = _journal([
      'contact-unknown-answer',
      'revision-unknown-answer',
      'command-unknown-answer',
    ]);

    await journal.submitAnonymousContact(
      AnonymousContactSubmission(
        appUserId: 'app-user-1',
        workspaceId: 'personal-workspace-1',
        projectId: 'project-1',
        questionnaireVersionId: 'questionnaire-v1',
        deviceId: 'device-1',
        occurredAtUtc: DateTime.utc(2030, 1, 8, 17),
        occurredTimeZone: 'America/Chicago',
        channel: ContactChannel.voiceCall,
        location: const NotApplicableContactLocation(),
        reachCount: 1,
        interestLevel: 2,
        answers: const [
          BooleanQuestionnaireAnswer.unknown(questionId: 'follow_up_consent'),
        ],
      ),
    );

    final stored = await journal.contactById('contact-unknown-answer');
    expect(stored!.answers, const [
      BooleanQuestionnaireAnswer.unknown(questionId: 'follow_up_consent'),
    ]);
  });

  test('Outbox 写入失败会回滚同事务中的接触 revision 和答案', () async {
    final database = LocalDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final firstJournal = ContactJournal(
      database: database,
      clock: _FixedClock(DateTime.utc(2030, 1, 8, 18, 30)),
      idGenerator: _SequenceIdGenerator([
        'contact-first',
        'revision-first',
        'duplicate-command',
        'contact-rolled-back',
        'revision-rolled-back',
        'duplicate-command',
      ]),
    );
    final submission = AnonymousContactSubmission(
      appUserId: 'app-user-1',
      workspaceId: 'personal-workspace-1',
      projectId: 'project-1',
      questionnaireVersionId: 'questionnaire-v1',
      deviceId: 'device-1',
      occurredAtUtc: DateTime.utc(2030, 1, 8, 17),
      occurredTimeZone: 'America/Chicago',
      channel: ContactChannel.voiceCall,
      location: const NotApplicableContactLocation(),
      reachCount: 1,
      interestLevel: 3,
      answers: const [
        BooleanQuestionnaireAnswer(
          questionId: 'follow_up_consent',
          value: true,
        ),
      ],
    );

    await firstJournal.submitAnonymousContact(submission);
    await expectLater(
      firstJournal.submitAnonymousContact(submission),
      throwsA(
        isA<ContactPersistenceException>().having(
          (error) => error.code,
          'code',
          'contact_submission_failed',
        ),
      ),
    );
    expect(await firstJournal.contactById('contact-rolled-back'), isNull);

    final retryJournal = ContactJournal(
      database: database,
      clock: _FixedClock(DateTime.utc(2030, 1, 8, 18, 31)),
      idGenerator: _SequenceIdGenerator([
        'contact-rolled-back',
        'revision-retry',
        'command-retry',
      ]),
    );
    final retry = await retryJournal.submitAnonymousContact(submission);
    expect(retry.contactId, 'contact-rolled-back');
  });

  test('个人期间汇总按发生时间筛选并分开计算场次与触达人数', () async {
    final fixture = await _loadPersonalContactMetricFixture();
    final journal = _journal([
      for (final row in fixture) ...[
        row.contactId,
        '${row.contactId}-revision',
        '${row.contactId}-command',
      ],
    ], now: DateTime.utc(2030, 1, 15, 18, 30));

    for (final row in fixture) {
      await journal.submitAnonymousContact(
        _submission(
          appUserId: row.ownerKey == 'primary' ? 'app-user-1' : 'app-user-2',
          projectId: row.projectKey == 'default' ? 'project-1' : 'project-2',
          occurredAtUtc: row.occurredAtUtc,
          channel: ContactChannel.fromStorage(row.channel),
          reachCount: row.reachCount,
          interestLevel: row.interestLevel,
        ),
      );
    }

    final summary = await journal.summarizePersonalContacts(
      appUserId: 'app-user-1',
      workspaceId: 'personal-workspace-1',
      projectId: 'project-1',
      fromUtc: DateTime.utc(2030, 1, 8),
      untilUtc: DateTime.utc(2030, 1, 15),
    );

    final expected = fixture
        .where((row) => row.expectedInPrimaryScope)
        .toList();
    final expectedInterest = List<int>.filled(5, 0);
    final expectedChannels = List<int>.filled(ContactChannel.values.length, 0);
    for (final row in expected) {
      expectedInterest[row.interestLevel]++;
      expectedChannels[ContactChannel.fromStorage(row.channel).index]++;
    }
    expect(summary.contactSessionCount, expected.length);
    expect(
      summary.reachCount,
      expected.fold(0, (total, row) => total + row.reachCount),
    );
    expect(summary.interestDistribution, expectedInterest);
    expect(summary.pendingSyncCount, expected.length);
    expect(summary.channelDistribution, expectedChannels);
    expect(
      summary.latestOccurredAtUtc,
      expected
          .map((row) => row.occurredAtUtc)
          .reduce((first, second) => first.isAfter(second) ? first : second),
    );
  });

  test('实际发生时刻必须是 UTC 并另外保存 IANA 时区', () async {
    final journal = _journal([
      'contact-local-time',
      'revision-local-time',
      'command-local-time',
    ]);

    await expectLater(
      journal.submitAnonymousContact(
        _submission(
          occurredAtUtc: DateTime(2030, 1, 10, 9),
          reachCount: 1,
          interestLevel: 2,
        ),
      ),
      throwsA(
        isA<ContactValidationException>().having(
          (error) => error.code,
          'code',
          'occurred_at_must_be_utc',
        ),
      ),
    );
  });

  test('实际发生时区不能留空', () async {
    final journal = _journal([
      'contact-blank-time-zone',
      'revision-blank-time-zone',
      'command-blank-time-zone',
    ]);
    await expectLater(
      journal.submitAnonymousContact(
        _submission(
          occurredAtUtc: DateTime.utc(2030, 1, 10, 9),
          occurredTimeZone: '   ',
          reachCount: 1,
          interestLevel: 2,
        ),
      ),
      throwsA(
        isA<ContactValidationException>().having(
          (error) => error.code,
          'code',
          'occurred_time_zone_required',
        ),
      ),
    );
  });

  test('个人汇总要求有效的 UTC 半开时间区间', () async {
    final journal = _journal(const []);

    await expectLater(
      journal.summarizePersonalContacts(
        appUserId: 'app-user-1',
        workspaceId: 'personal-workspace-1',
        projectId: 'project-1',
        fromUtc: DateTime.utc(2030, 1, 15),
        untilUtc: DateTime.utc(2030, 1, 15),
      ),
      throwsA(
        isA<ContactValidationException>().having(
          (error) => error.code,
          'code',
          'invalid_summary_period',
        ),
      ),
    );
  });

  test('接触必须属于非空的当前用户空间项目和问卷版本', () async {
    final journal = _journal([
      'contact-blank-context',
      'revision-blank-context',
      'command-blank-context',
    ]);
    await expectLater(
      journal.submitAnonymousContact(
        _submission(
          projectId: '   ',
          occurredAtUtc: DateTime.utc(2030, 1, 10, 9),
          reachCount: 1,
          interestLevel: 2,
        ),
      ),
      throwsA(
        isA<ContactValidationException>().having(
          (error) => error.code,
          'code',
          'contact_context_required',
        ),
      ),
    );
  });

  test('待同步接触必须带有非空设备 ID', () async {
    final journal = _journal(const []);

    await expectLater(
      journal.submitAnonymousContact(
        _submission(
          deviceId: '   ',
          occurredAtUtc: DateTime.utc(2030, 1, 10, 9),
          reachCount: 1,
          interestLevel: 2,
        ),
      ),
      throwsA(
        isA<ContactValidationException>().having(
          (error) => error.code,
          'code',
          'contact_device_required',
        ),
      ),
    );
  });

  test('问卷答案必须带有非空问题 ID', () async {
    final journal = _journal(const []);

    await expectLater(
      journal.submitAnonymousContact(
        _submission(
          occurredAtUtc: DateTime.utc(2030, 1, 10, 9),
          reachCount: 1,
          interestLevel: 2,
          answers: const [
            BooleanQuestionnaireAnswer(questionId: '   ', value: true),
          ],
        ),
      ),
      throwsA(
        isA<ContactValidationException>().having(
          (error) => error.code,
          'code',
          'question_id_required',
        ),
      ),
    );
  });

  test('同一 revision 不能为同一道问卷题保存两个答案', () async {
    final journal = _journal([
      'contact-duplicate-answer',
      'revision-duplicate-answer',
      'command-duplicate-answer',
    ]);
    await expectLater(
      journal.submitAnonymousContact(
        _submission(
          occurredAtUtc: DateTime.utc(2030, 1, 10, 9),
          reachCount: 1,
          interestLevel: 2,
          answers: const [
            BooleanQuestionnaireAnswer(
              questionId: 'follow_up_consent',
              value: true,
            ),
            BooleanQuestionnaireAnswer.unknown(questionId: 'follow_up_consent'),
          ],
        ),
      ),
      throwsA(
        isA<ContactValidationException>().having(
          (error) => error.code,
          'code',
          'duplicate_question_answer',
        ),
      ),
    );
  });

  test('待解析地点必须提供有效经纬度和非负精度', () async {
    final journal = _journal([
      'contact-invalid-coordinate',
      'revision-invalid-coordinate',
      'command-invalid-coordinate',
    ]);
    await expectLater(
      journal.submitAnonymousContact(
        _submission(
          occurredAtUtc: DateTime.utc(2030, 1, 10, 9),
          channel: ContactChannel.faceToFace,
          location: const PendingContactLocation(
            latitude: 91,
            longitude: -87.5987,
            accuracyMeters: -1,
          ),
          reachCount: 1,
          interestLevel: 2,
        ),
      ),
      throwsA(
        isA<ContactValidationException>().having(
          (error) => error.code,
          'code',
          'invalid_pending_location',
        ),
      ),
    );
  });

  test('已解析线下地点必须同时有具体名称和最小区域', () async {
    final journal = _journal([
      'contact-blank-place',
      'revision-blank-place',
      'command-blank-place',
    ]);
    await expectLater(
      journal.submitAnonymousContact(
        _submission(
          occurredAtUtc: DateTime.utc(2030, 1, 10, 9),
          channel: ContactChannel.faceToFace,
          location: const ResolvedContactLocation(
            placeName: '   ',
            smallestRegionId: 'region-chicago',
            regionTreeVersion: 'regions-test-v1',
          ),
          reachCount: 1,
          interestLevel: 2,
        ),
      ),
      throwsA(
        isA<ContactValidationException>().having(
          (error) => error.code,
          'code',
          'resolved_location_required',
        ),
      ),
    );
  });

  test('其他直接渠道保存可解释的渠道明细', () async {
    final journal = _journal([
      'contact-other-channel',
      'revision-other-channel',
      'command-other-channel',
    ]);
    await journal.submitAnonymousContact(
      _submission(
        occurredAtUtc: DateTime.utc(2030, 1, 10, 9),
        channel: ContactChannel.otherDirect,
        channelDetail: '互动式语音导览',
        reachCount: 1,
        interestLevel: 2,
      ),
    );

    final stored = await journal.contactById('contact-other-channel');
    expect(stored!.channelDetail, '互动式语音导览');
  });

  test('其他直接渠道不能省略渠道明细', () async {
    final journal = _journal([
      'contact-other-without-detail',
      'revision-other-without-detail',
      'command-other-without-detail',
    ]);
    await expectLater(
      journal.submitAnonymousContact(
        _submission(
          occurredAtUtc: DateTime.utc(2030, 1, 10, 9),
          channel: ContactChannel.otherDirect,
          channelDetail: '   ',
          reachCount: 1,
          interestLevel: 2,
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

Future<List<_PersonalContactMetricFixtureRow>>
_loadPersonalContactMetricFixture() async {
  final lines = await File(
    'backend/database/fixtures/shared/personal_contact_metrics_v1.csv',
  ).readAsLines();
  return [
    for (final line in lines.skip(1))
      if (line.trim().isNotEmpty)
        _PersonalContactMetricFixtureRow.fromCsv(line),
  ];
}

final class _PersonalContactMetricFixtureRow {
  const _PersonalContactMetricFixtureRow({
    required this.contactId,
    required this.ownerKey,
    required this.projectKey,
    required this.occurredAtUtc,
    required this.channel,
    required this.reachCount,
    required this.interestLevel,
    required this.expectedInPrimaryScope,
  });

  factory _PersonalContactMetricFixtureRow.fromCsv(String line) {
    final columns = line.split(',');
    if (columns.length != 8) {
      throw FormatException('invalid personal contact metric fixture', line);
    }
    return _PersonalContactMetricFixtureRow(
      contactId: columns[0],
      ownerKey: columns[1],
      projectKey: columns[2],
      occurredAtUtc: DateTime.parse(columns[3]).toUtc(),
      channel: columns[4],
      reachCount: int.parse(columns[5]),
      interestLevel: int.parse(columns[6]),
      expectedInPrimaryScope: bool.parse(columns[7]),
    );
  }

  final String contactId;
  final String ownerKey;
  final String projectKey;
  final DateTime occurredAtUtc;
  final String channel;
  final int reachCount;
  final int interestLevel;
  final bool expectedInPrimaryScope;
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

final class _SequenceIdGenerator implements IdGenerator {
  _SequenceIdGenerator(this.values);

  final List<String> values;
  var _index = 0;

  @override
  String next() => values[_index++];
}
