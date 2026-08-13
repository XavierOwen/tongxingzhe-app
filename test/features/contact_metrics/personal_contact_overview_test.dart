import 'package:flutter_test/flutter_test.dart';
import 'package:tongxingzhe_app/app_session/session_context_gateway.dart';
import 'package:tongxingzhe_app/features/contact_journal/contact_models.dart';
import 'package:tongxingzhe_app/features/contact_metrics/metric_contract.dart';
import 'package:tongxingzhe_app/features/contact_metrics/personal_contact_overview.dart';
import 'package:tongxingzhe_app/sync/sync_models.dart';

void main() {
  test('今日和最近七日使用 UTC 半开区间且同步覆盖单位是接触场次', () async {
    final source = _FakeOverviewSource();
    final repository = PersonalContactOverviewRepository(
      source: source,
      now: () => DateTime.utc(2030, 1, 8, 18, 30),
    );

    final today = await repository.loadSummary(
      context: _context,
      period: PersonalSummaryPeriod.today,
    );
    final week = await repository.loadSummary(
      context: _context,
      period: PersonalSummaryPeriod.recentSevenDays,
    );

    expect(today.fromUtc, DateTime.utc(2030, 1, 8));
    expect(today.untilUtc, DateTime.utc(2030, 1, 9));
    expect(week.fromUtc, DateTime.utc(2030, 1, 2));
    expect(week.untilUtc, DateTime.utc(2030, 1, 9));
    expect(today.syncedContactSessionCount, 3);
    expect(today.syncCoverageDenominator, 5);
    expect(today.metrics, hasLength(8));
    expect(
      today.metric(CoreMetricCatalog.contactSessions.reference).value,
      CountMetricValue(5),
    );
    expect(
      today.metric(CoreMetricCatalog.reachedPeople.reference).value,
      CountMetricValue(9),
    );
    expect(
      today.metric(CoreMetricCatalog.interestDistribution.reference).value,
      MetricDistributionValue(
        labels: ['0', '1', '2', '3', '4'],
        counts: [1, 1, 1, 1, 1],
      ),
    );
    expect(
      today.metric(CoreMetricCatalog.interestOrdinalSummary.reference).value,
      OrdinalSummaryMetricValue(
        labels: const ['0', '1', '2', '3', '4'],
        counts: const [1, 1, 1, 1, 1],
        totalCount: 5,
        medianLevel: 2,
      ),
    );
    final ratios =
        today.metric(CoreMetricCatalog.interestLevelRatios.reference).value
            as RatioMetricValue;
    expect(ratios.numerators, [1, 1, 1, 1, 1]);
    expect(ratios.denominator, 5);
    expect(ratios.basisPoints, [2000, 2000, 2000, 2000, 2000]);
    expect(ratios.unknownCount, 0);
    expect(ratios.refusedCount, 0);
    expect(ratios.notApplicableCount, 0);
    expect(ratios.unansweredCount, 0);
    expect(ratios.excludedCount, 0);
    final threeFourRatio =
        today.metric(CoreMetricCatalog.interestThreeFourRatio.reference).value
            as SubsetRatioMetricValue;
    final zeroRatio =
        today.metric(CoreMetricCatalog.interestZeroRatio.reference).value
            as SubsetRatioMetricValue;
    expect(threeFourRatio.label, '3_4');
    expect(threeFourRatio.numerator, 2);
    expect(threeFourRatio.denominator, 5);
    expect(threeFourRatio.percentageBasisPoints, 4000);
    expect(zeroRatio.label, '0');
    expect(zeroRatio.numerator, 1);
    expect(zeroRatio.denominator, 5);
    expect(zeroRatio.percentageBasisPoints, 2000);
    expect(
      threeFourRatio.numerator + zeroRatio.numerator,
      lessThan(threeFourRatio.denominator),
    );
    expect(
      today.metric(CoreMetricCatalog.channelDistribution.reference).value,
      MetricDistributionValue(
        labels: [
          'face_to_face',
          'voice_call',
          'video_call',
          'instant_text',
          'asynchronous_message',
          'mixed',
          'other_direct',
        ],
        counts: [1, 1, 1, 1, 1, 0, 0],
      ),
    );
    expect(
      today.metrics.every(
        (result) =>
            result.sourceTier == MetricSourceTier.localOperational &&
            result.privacyStatus == MetricPrivacyStatus.personalFact &&
            result.timeZone == 'UTC' &&
            result.dataCutoffUtc == DateTime.utc(2030, 1, 8, 18, 30) &&
            result.syncCoverage!.totalCount == 5 &&
            result.syncCoverage!.pendingCount == 2,
      ),
      isTrue,
    );
  });

  test('接触页读取草稿、今日指标和同一 scope 的同步健康状态', () async {
    final source = _FakeOverviewSource();
    final repository = PersonalContactOverviewRepository(
      source: source,
      now: () => DateTime.utc(2030, 1, 8, 18, 30),
      loadSyncHealth: () async => _health,
    );

    final result = await repository.loadContacts(context: _context);

    expect(result.contacts, isEmpty);
    expect(result.drafts, isEmpty);
    expect(result.todaySummary.contactSessionCount, 5);
    expect(result.syncHealth, same(_health));
    expect(source.lastAppUserId, _context.appUserId);
  });

  test('个人指标映射拒绝分布总数与接触场次不一致', () {
    expect(
      () => PersonalContactMetricMapper.map(
        summary: const PersonalContactSummary(
          contactSessionCount: 2,
          reachCount: 2,
          interestDistribution: [1, 0, 0, 0, 0],
          pendingSyncCount: 0,
          channelDistribution: [1, 0, 0, 0, 0, 0, 0],
        ),
        period: MetricPeriod(
          fromUtc: DateTime.utc(2030, 1, 8),
          untilUtc: DateTime.utc(2030, 1, 9),
        ),
        dataCutoffUtc: DateTime.utc(2030, 1, 8, 18, 30),
      ),
      throwsStateError,
    );
  });

  test('空期间的兴趣比例是 0/0 且没有百分比', () {
    final metrics = PersonalContactMetricMapper.map(
      summary: const PersonalContactSummary(
        contactSessionCount: 0,
        reachCount: 0,
        interestDistribution: [0, 0, 0, 0, 0],
        pendingSyncCount: 0,
        channelDistribution: [0, 0, 0, 0, 0, 0, 0],
      ),
      period: MetricPeriod(
        fromUtc: DateTime.utc(2030, 1, 8),
        untilUtc: DateTime.utc(2030, 1, 9),
      ),
      dataCutoffUtc: DateTime.utc(2030, 1, 8, 18, 30),
    );

    final ratios =
        metrics
                .singleWhere(
                  (result) =>
                      result.definition.reference ==
                      CoreMetricCatalog.interestLevelRatios.reference,
                )
                .value
            as RatioMetricValue;
    expect(ratios.denominator, 0);
    expect(ratios.numerators, [0, 0, 0, 0, 0]);
    expect(ratios.basisPoints, [null, null, null, null, null]);
    for (final definition in [
      CoreMetricCatalog.interestThreeFourRatio,
      CoreMetricCatalog.interestZeroRatio,
    ]) {
      final subset =
          metrics
                  .singleWhere(
                    (result) =>
                        result.definition.reference == definition.reference,
                  )
                  .value
              as SubsetRatioMetricValue;
      expect(subset.numerator, 0);
      expect(subset.denominator, 0);
      expect(subset.percentageBasisPoints, isNull);
    }
  });
}

const _context = TrustedSessionContext(
  appUserId: 'user-1',
  workspace: WorkspaceContext(
    id: 'workspace-1',
    kind: WorkspaceKind.personal,
    name: '个人空间',
  ),
  project: ProjectContext(id: 'project-1', name: '项目'),
  questionnaireVersion: QuestionnaireVersionContext(
    id: 'questionnaire-1',
    versionNumber: 1,
  ),
  capabilities: {'record_contact'},
);

const _summary = PersonalContactSummary(
  contactSessionCount: 5,
  reachCount: 9,
  interestDistribution: [1, 1, 1, 1, 1],
  pendingSyncCount: 2,
  channelDistribution: [1, 1, 1, 1, 1, 0, 0],
);

const _health = SyncHealth(
  onlyOnDeviceCount: 2,
  syncingCount: 0,
  retryingCount: 0,
  needsResolutionCount: 0,
  permanentFailureCount: 0,
  completedCount: 3,
  oldestPendingAge: Duration.zero,
  lastSuccessAtUtc: null,
  lastFailureCode: null,
  serverCursor: null,
);

final class _FakeOverviewSource implements PersonalContactOverviewSource {
  String? lastAppUserId;

  @override
  Future<List<ContactRecord>> listContactRecords({
    required String appUserId,
    required String workspaceId,
    required String projectId,
  }) async => const [];

  @override
  Future<List<ContactDraft>> listDrafts({required String appUserId}) async {
    lastAppUserId = appUserId;
    return const [];
  }

  @override
  Future<List<ContactAttempt>> listContactAttempts({
    required String appUserId,
    required String workspaceId,
    required String projectId,
  }) async => const [];

  @override
  Future<PersonalContactSummary> summarizePersonalContacts({
    required String appUserId,
    required String workspaceId,
    required String projectId,
    required DateTime fromUtc,
    required DateTime untilUtc,
  }) async {
    lastAppUserId = appUserId;
    return _summary;
  }
}
