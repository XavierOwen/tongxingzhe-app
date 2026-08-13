import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tongxingzhe_app/data/local_database.dart';
import 'package:tongxingzhe_app/features/contact_journal/contact_journal.dart';
import 'package:tongxingzhe_app/features/contact_journal/contact_models.dart';
import 'package:tongxingzhe_app/features/contact_metrics/metric_contract.dart';
import 'package:tongxingzhe_app/features/contact_metrics/personal_contact_overview.dart';
import 'package:tongxingzhe_app/foundation/runtime_values.dart';
import 'package:tongxingzhe_app/regions/region_catalog.dart';
import 'package:tongxingzhe_app/regions/region_models.dart';
import 'package:tongxingzhe_app/targets/promotion_target.dart';

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
          source: _locationSource,
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
        source: _locationSource,
      ),
    );
    expect(stored.syncState, LocalSyncState.pending);
    final command = await database.select(database.dbSyncOutbox).getSingle();
    final payload = jsonDecode(command.payloadJson) as Map<String, Object?>;
    expect(payload['location_source'], {
      'kind': 'captured_coordinates',
      'latitude': 41.7886,
      'longitude': -87.5987,
      'accuracy_meters': 12.0,
      'resolver_contract_version': 'canonical-region-resolution:v1',
      'region_tree_content_fingerprint': _fingerprint,
    });
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

  test('已解析来源在草稿重启恢复和最新 Outbox 快照中保持完整', () async {
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
        ],
      ),
    );
    final journal = ContactJournal(
      database: database,
      clock: _FixedClock(DateTime.utc(2030, 1, 8, 18, 30)),
      idGenerator: _SequenceIdGenerator(['draft-source']),
    );
    const location = ResolvedContactLocation(
      placeName: 'Chicago',
      smallestRegionId: 'region-chicago',
      regionTreeVersion: 'regions-test-v1',
      source: _locationSource,
    );
    await journal.saveDraft(
      const ContactDraftInput(
        deviceId: 'device-1',
        appUserId: 'app-user-1',
        workspaceId: 'personal-workspace-1',
        projectId: 'project-1',
        questionnaireVersionId: 'questionnaire-v1',
        location: location,
      ),
    );

    final restarted = ContactJournal(
      database: database,
      clock: _FixedClock(DateTime.utc(2030, 1, 8, 18, 31)),
      idGenerator: _SequenceIdGenerator(const []),
    );
    expect(
      (await restarted.listDrafts(appUserId: 'app-user-1')).single.location,
      location,
    );
    final command = await database.select(database.dbSyncOutbox).getSingle();
    final payload = jsonDecode(command.payloadJson) as Map<String, Object?>;
    expect(
      (payload['location_source']
          as Map<String, Object?>)['region_tree_content_fingerprint'],
      _fingerprint,
    );
  });

  test('错误的已解析来源在写入前稳定拒绝', () async {
    final journal = _journal([
      'contact-invalid-source',
      'revision-invalid-source',
      'command-invalid-source',
    ]);
    await expectLater(
      journal.submitAnonymousContact(
        _submission(
          occurredAtUtc: DateTime.utc(2030, 1, 8, 17),
          channel: ContactChannel.faceToFace,
          location: const ResolvedContactLocation(
            placeName: 'Chicago',
            smallestRegionId: 'region-chicago',
            regionTreeVersion: 'regions-test-v1',
            source: CapturedCoordinatesLocationSource(
              latitude: 41.8781,
              longitude: -87.6298,
              resolverContractVersion: 'resolver-v2',
              regionTreeContentFingerprint: _fingerprint,
            ),
          ),
          reachCount: 1,
          interestLevel: 2,
        ),
      ),
      throwsA(
        isA<ContactValidationException>().having(
          (error) => error.code,
          'code',
          'invalid_location_source',
        ),
      ),
    );
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

    final metricResults = PersonalContactMetricMapper.map(
      summary: summary,
      period: MetricPeriod(
        fromUtc: DateTime.utc(2030, 1, 8),
        untilUtc: DateTime.utc(2030, 1, 15),
      ),
      dataCutoffUtc: DateTime.utc(2030, 1, 15, 18, 30),
    );
    expect(
      metricResults
          .singleWhere(
            (result) =>
                result.definition.reference ==
                CoreMetricCatalog.contactSessions.reference,
          )
          .value,
      CountMetricValue(expected.length),
    );
    expect(
      metricResults
          .singleWhere(
            (result) =>
                result.definition.reference ==
                CoreMetricCatalog.reachedPeople.reference,
          )
          .value,
      CountMetricValue(
        expected.fold(0, (total, row) => total + row.reachCount),
      ),
    );
    expect(
      metricResults
          .singleWhere(
            (result) =>
                result.definition.reference ==
                CoreMetricCatalog.interestThreeFourRatio.reference,
          )
          .value,
      SubsetRatioMetricValue(
        label: '3_4',
        numerator: expectedInterest[3] + expectedInterest[4],
        denominator: expected.length,
      ),
    );
    expect(
      metricResults
          .singleWhere(
            (result) =>
                result.definition.reference ==
                CoreMetricCatalog.interestZeroRatio.reference,
          )
          .value,
      SubsetRatioMetricValue(
        label: '0',
        numerator: expectedInterest[0],
        denominator: expected.length,
      ),
    );
    expect(
      metricResults
          .singleWhere(
            (result) =>
                result.definition.reference ==
                CoreMetricCatalog.interestOrdinalSummary.reference,
          )
          .value,
      OrdinalSummaryMetricValue(
        labels: CoreMetricCatalog.interestOrdinalSummary.bucketLabels,
        counts: expectedInterest,
        totalCount: expected.length,
        medianLevel: 3,
      ),
    );
    expect(
      metricResults
          .singleWhere(
            (result) =>
                result.definition.reference ==
                CoreMetricCatalog.interestDistribution.reference,
          )
          .value,
      MetricDistributionValue(
        labels: CoreMetricCatalog.interestDistribution.bucketLabels,
        counts: expectedInterest,
      ),
    );
    expect(
      metricResults
          .singleWhere(
            (result) =>
                result.definition.reference ==
                CoreMetricCatalog.interestLevelRatios.reference,
          )
          .value,
      RatioMetricValue.fromCounts(
        labels: CoreMetricCatalog.interestLevelRatios.bucketLabels,
        counts: expectedInterest,
      ),
    );
    expect(
      metricResults
          .singleWhere(
            (result) =>
                result.definition.reference ==
                CoreMetricCatalog.channelDistribution.reference,
          )
          .value,
      MetricDistributionValue(
        labels: CoreMetricCatalog.channelDistribution.bucketLabels,
        counts: expectedChannels,
      ),
    );
  });

  test('对象反应汇总按当前 scope 的对象关联计数并保留未填写', () async {
    final journal = _journal([
      'target-multi-contact',
      'target-multi-revision',
      'target-multi-command',
      'target-boundary-contact',
      'target-boundary-revision',
      'target-boundary-command',
      'target-other-contact',
      'target-other-revision',
      'target-other-command',
      'target-other-project-contact',
      'target-other-project-revision',
      'target-other-project-command',
    ], now: DateTime.utc(2030, 1, 15, 18, 30));

    await journal.submitAnonymousContact(
      _submission(
        occurredAtUtc: DateTime.utc(2030, 1, 14, 12),
        reachCount: 3,
        interestLevel: 2,
        targetLinks: const [
          ContactTargetLink(
            targetId: 'target-response-4',
            targetType: PromotionTargetType.person,
            responseLevel: 4,
          ),
          ContactTargetLink(
            targetId: 'target-response-1',
            targetType: PromotionTargetType.person,
            responseLevel: 1,
          ),
          ContactTargetLink(
            targetId: 'target-response-2',
            targetType: PromotionTargetType.person,
            responseLevel: 2,
          ),
          ContactTargetLink(
            targetId: 'target-response-institution-3',
            targetType: PromotionTargetType.institution,
            responseLevel: 3,
            institutionRepresentativeConfirmed: true,
          ),
          ContactTargetLink(
            targetId: 'target-response-unanswered',
            targetType: PromotionTargetType.person,
          ),
        ],
      ),
    );
    await journal.submitAnonymousContact(
      _submission(
        occurredAtUtc: DateTime.utc(2030, 1, 15),
        reachCount: 1,
        interestLevel: 2,
        targetLinks: const [
          ContactTargetLink(
            targetId: 'target-response-boundary',
            targetType: PromotionTargetType.person,
            responseLevel: 3,
          ),
        ],
      ),
    );
    await journal.submitAnonymousContact(
      _submission(
        appUserId: 'app-user-2',
        occurredAtUtc: DateTime.utc(2030, 1, 14, 13),
        reachCount: 1,
        interestLevel: 2,
        targetLinks: const [
          ContactTargetLink(
            targetId: 'target-response-other-owner',
            targetType: PromotionTargetType.person,
            responseLevel: 2,
          ),
        ],
      ),
    );
    await journal.submitAnonymousContact(
      _submission(
        projectId: 'project-other',
        occurredAtUtc: DateTime.utc(2030, 1, 14, 14),
        reachCount: 1,
        interestLevel: 2,
        targetLinks: const [
          ContactTargetLink(
            targetId: 'target-response-other-project',
            targetType: PromotionTargetType.person,
            responseLevel: 0,
          ),
        ],
      ),
    );

    final summary = await journal.summarizePersonalContacts(
      appUserId: 'app-user-1',
      workspaceId: 'personal-workspace-1',
      projectId: 'project-1',
      fromUtc: DateTime.utc(2030, 1, 8),
      untilUtc: DateTime.utc(2030, 1, 15),
    );

    expect(summary.targetResponseDistribution, [0, 1, 1, 1, 1]);
    expect(summary.targetResponseUnansweredCount, 1);
    final ratios =
        PersonalContactMetricMapper.map(
                  summary: summary,
                  period: MetricPeriod(
                    fromUtc: DateTime.utc(2030, 1, 8),
                    untilUtc: DateTime.utc(2030, 1, 15),
                  ),
                  dataCutoffUtc: DateTime.utc(2030, 1, 15, 18, 30),
                )
                .singleWhere(
                  (result) =>
                      result.definition.reference ==
                      CoreMetricCatalog.targetResponseLevelRatios.reference,
                )
                .value
            as RatioMetricValue;
    expect(ratios.numerators, [0, 1, 1, 1, 1]);
    expect(ratios.denominator, 4);
    expect(ratios.basisPoints, [0, 2500, 2500, 2500, 2500]);
    expect(ratios.unansweredCount, 1);
    expect(
      OrdinalSummaryMetricValue.fromCounts(
        labels: CoreMetricCatalog.targetResponseOrdinalSummary.bucketLabels,
        counts: summary.targetResponseDistribution,
      ),
      OrdinalSummaryMetricValue(
        labels: const ['0', '1', '2', '3', '4'],
        counts: const [0, 1, 1, 1, 1],
        totalCount: 4,
        medianLevel: 2,
      ),
      reason: '未填写关联不能进入偶数样本的下中位计算。',
    );
  });

  test('对象反应汇总只计 current revision 并排除作废接触', () async {
    final journal = _journal([
      'target-revision-contact',
      'target-revision-revision-1',
      'target-revision-command-1',
      'target-revision-revision-2',
      'target-revision-command-2',
      'target-void-contact',
      'target-void-revision-1',
      'target-void-command-1',
      'target-void-revision-2',
      'target-void-command-2',
    ], now: DateTime.utc(2030, 1, 15, 18, 30));

    await journal.submitAnonymousContact(
      _submission(
        occurredAtUtc: DateTime.utc(2030, 1, 12, 12),
        reachCount: 1,
        interestLevel: 2,
        targetLinks: const [
          ContactTargetLink(
            targetId: 'target-revision-old',
            targetType: PromotionTargetType.person,
            responseLevel: 0,
          ),
        ],
      ),
    );
    await journal.correctContact(
      ContactCorrectionSubmission(
        contactId: 'target-revision-contact',
        appUserId: 'app-user-1',
        workspaceId: 'personal-workspace-1',
        projectId: 'project-1',
        deviceId: 'device-1',
        baseRevision: 1,
        reason: '更新对象当次反应',
        occurredAtUtc: DateTime.utc(2030, 1, 12, 12),
        occurredTimeZone: 'America/Chicago',
        channel: ContactChannel.videoCall,
        location: NotApplicableContactLocation(),
        reachCount: 1,
        interestLevel: 2,
        targetLinks: [
          ContactTargetLink(
            targetId: 'target-revision-new',
            targetType: PromotionTargetType.person,
            responseLevel: 3,
          ),
        ],
      ),
    );
    await journal.submitAnonymousContact(
      _submission(
        occurredAtUtc: DateTime.utc(2030, 1, 12, 13),
        reachCount: 1,
        interestLevel: 2,
        targetLinks: const [
          ContactTargetLink(
            targetId: 'target-voided',
            targetType: PromotionTargetType.person,
            responseLevel: 4,
          ),
        ],
      ),
    );
    await journal.voidContact(
      const ContactVoidSubmission(
        contactId: 'target-void-contact',
        appUserId: 'app-user-1',
        workspaceId: 'personal-workspace-1',
        projectId: 'project-1',
        deviceId: 'device-1',
        baseRevision: 1,
        reason: '排除作废接触',
      ),
    );

    final summary = await journal.summarizePersonalContacts(
      appUserId: 'app-user-1',
      workspaceId: 'personal-workspace-1',
      projectId: 'project-1',
      fromUtc: DateTime.utc(2030, 1, 8),
      untilUtc: DateTime.utc(2030, 1, 15),
    );

    expect(summary.targetResponseDistribution, [0, 0, 0, 1, 0]);
    expect(summary.targetResponseUnansweredCount, 0);
    final ratios = RatioMetricValue.fromCounts(
      labels: CoreMetricCatalog.targetResponseLevelRatios.bucketLabels,
      counts: summary.targetResponseDistribution,
      unansweredCount: summary.targetResponseUnansweredCount,
    );
    expect(ratios.numerators, [0, 0, 0, 1, 0]);
    expect(ratios.denominator, 1);
    expect(ratios.basisPoints, [0, 0, 0, 10000, 0]);
    expect(
      OrdinalSummaryMetricValue.fromCounts(
        labels: CoreMetricCatalog.targetResponseOrdinalSummary.bucketLabels,
        counts: summary.targetResponseDistribution,
      ).medianLevel,
      3,
      reason: '旧 revision 和作废接触不得影响对象反应中位。',
    );
  });

  test('Drift 汇总与 Flutter 映射对兴趣子集比例场景保持一致', () async {
    const cases =
        <
          ({
            String projectId,
            List<int> levels,
            int highNumerator,
            int zeroNumerator,
            int? highBasisPoints,
            int? zeroBasisPoints,
          })
        >[
          (
            projectId: 'project-shared-golden',
            levels: [0, 3, 4],
            highNumerator: 2,
            zeroNumerator: 1,
            highBasisPoints: 6667,
            zeroBasisPoints: 3333,
          ),
          (
            projectId: 'project-all-zero',
            levels: [0, 0],
            highNumerator: 0,
            zeroNumerator: 2,
            highBasisPoints: 0,
            zeroBasisPoints: 10000,
          ),
          (
            projectId: 'project-all-high',
            levels: [3, 4],
            highNumerator: 2,
            zeroNumerator: 0,
            highBasisPoints: 10000,
            zeroBasisPoints: 0,
          ),
          (
            projectId: 'project-mixed',
            levels: [0, 1, 2, 3, 4],
            highNumerator: 2,
            zeroNumerator: 1,
            highBasisPoints: 4000,
            zeroBasisPoints: 2000,
          ),
          (
            projectId: 'project-rounding',
            levels: [1, 3, 4],
            highNumerator: 2,
            zeroNumerator: 0,
            highBasisPoints: 6667,
            zeroBasisPoints: 0,
          ),
          (
            projectId: 'project-empty',
            levels: [],
            highNumerator: 0,
            zeroNumerator: 0,
            highBasisPoints: null,
            zeroBasisPoints: null,
          ),
        ];
    final submittedCount = cases.fold<int>(
      0,
      (total, item) => total + item.levels.length,
    );
    final journal = _journal([
      for (var index = 0; index < submittedCount; index++) ...[
        'subset-contact-$index',
        'subset-revision-$index',
        'subset-command-$index',
      ],
    ], now: DateTime.utc(2030, 1, 15, 18, 30));

    var submittedIndex = 0;
    for (final item in cases) {
      for (final level in item.levels) {
        await journal.submitAnonymousContact(
          _submission(
            projectId: item.projectId,
            occurredAtUtc: DateTime.utc(2030, 1, 10, submittedIndex),
            reachCount: 1,
            interestLevel: level,
          ),
        );
        submittedIndex++;
      }

      final summary = await journal.summarizePersonalContacts(
        appUserId: 'app-user-1',
        workspaceId: 'personal-workspace-1',
        projectId: item.projectId,
        fromUtc: DateTime.utc(2030, 1, 8),
        untilUtc: DateTime.utc(2030, 1, 15),
      );
      final metrics = PersonalContactMetricMapper.map(
        summary: summary,
        period: MetricPeriod(
          fromUtc: DateTime.utc(2030, 1, 8),
          untilUtc: DateTime.utc(2030, 1, 15),
        ),
        dataCutoffUtc: DateTime.utc(2030, 1, 15, 18, 30),
      );
      final high =
          metrics
                  .singleWhere(
                    (result) =>
                        result.definition.reference ==
                        CoreMetricCatalog.interestThreeFourRatio.reference,
                  )
                  .value
              as SubsetRatioMetricValue;
      final zero =
          metrics
                  .singleWhere(
                    (result) =>
                        result.definition.reference ==
                        CoreMetricCatalog.interestZeroRatio.reference,
                  )
                  .value
              as SubsetRatioMetricValue;

      expect(high.numerator, item.highNumerator, reason: item.projectId);
      expect(zero.numerator, item.zeroNumerator, reason: item.projectId);
      expect(high.denominator, item.levels.length, reason: item.projectId);
      expect(zero.denominator, item.levels.length, reason: item.projectId);
      expect(
        high.percentageBasisPoints,
        item.highBasisPoints,
        reason: item.projectId,
      );
      expect(
        zero.percentageBasisPoints,
        item.zeroBasisPoints,
        reason: item.projectId,
      );
    }
  });

  test('Drift 兴趣子集比例排除作废记录并使用 UTC 右开边界', () async {
    final journal = _journal([
      'subset-active-contact',
      'subset-active-revision',
      'subset-active-command',
      'subset-void-contact',
      'subset-void-revision',
      'subset-void-command',
      'subset-boundary-contact',
      'subset-boundary-revision',
      'subset-boundary-command',
      'subset-void-revision-2',
      'subset-void-command-2',
    ], now: DateTime.utc(2030, 1, 15, 18, 30));
    await journal.submitAnonymousContact(
      _submission(
        occurredAtUtc: DateTime.utc(2030, 1, 14, 12),
        reachCount: 1,
        interestLevel: 3,
      ),
    );
    await journal.submitAnonymousContact(
      _submission(
        occurredAtUtc: DateTime.utc(2030, 1, 14, 13),
        reachCount: 1,
        interestLevel: 0,
      ),
    );
    await journal.submitAnonymousContact(
      _submission(
        occurredAtUtc: DateTime.utc(2030, 1, 15),
        reachCount: 1,
        interestLevel: 4,
      ),
    );
    await journal.voidContact(
      const ContactVoidSubmission(
        contactId: 'subset-void-contact',
        appUserId: 'app-user-1',
        workspaceId: 'personal-workspace-1',
        projectId: 'project-1',
        deviceId: 'device-1',
        baseRevision: 1,
        reason: 'Synthetic subset ratio exclusion',
      ),
    );

    final summary = await journal.summarizePersonalContacts(
      appUserId: 'app-user-1',
      workspaceId: 'personal-workspace-1',
      projectId: 'project-1',
      fromUtc: DateTime.utc(2030, 1, 8),
      untilUtc: DateTime.utc(2030, 1, 15),
    );
    final metrics = PersonalContactMetricMapper.map(
      summary: summary,
      period: MetricPeriod(
        fromUtc: DateTime.utc(2030, 1, 8),
        untilUtc: DateTime.utc(2030, 1, 15),
      ),
      dataCutoffUtc: DateTime.utc(2030, 1, 15, 18, 30),
    );
    final high =
        metrics
                .singleWhere(
                  (result) =>
                      result.definition.reference ==
                      CoreMetricCatalog.interestThreeFourRatio.reference,
                )
                .value
            as SubsetRatioMetricValue;
    final zero =
        metrics
                .singleWhere(
                  (result) =>
                      result.definition.reference ==
                      CoreMetricCatalog.interestZeroRatio.reference,
                )
                .value
            as SubsetRatioMetricValue;

    expect(high.numerator, 1);
    expect(high.denominator, 1);
    expect(high.percentageBasisPoints, 10000);
    expect(zero.numerator, 0);
    expect(zero.denominator, 1);
    expect(zero.percentageBasisPoints, 0);
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

const _fingerprint =
    '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

const _locationSource = CapturedCoordinatesLocationSource(
  latitude: 41.7886,
  longitude: -87.5987,
  accuracyMeters: 12,
  resolverContractVersion: 'canonical-region-resolution:v1',
  regionTreeContentFingerprint: _fingerprint,
);

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
  List<ContactTargetLink> targetLinks = const [],
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
    targetLinks: targetLinks,
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
