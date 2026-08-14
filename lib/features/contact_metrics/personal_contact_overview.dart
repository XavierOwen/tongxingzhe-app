import '../../app_session/session_context_gateway.dart';
import '../../sync/sync_models.dart';
import '../contact_journal/contact_journal.dart';
import '../contact_journal/contact_models.dart';
import 'metric_contract.dart';

/// 首页支持的两个稳定统计窗口。
enum PersonalSummaryPeriod { today, recentSevenDays }

/// 指标查询使用的 UTC 半开区间 `[fromUtc, untilUtc)`。
final class UtcMetricPeriod {
  const UtcMetricPeriod({required this.fromUtc, required this.untilUtc});

  final DateTime fromUtc;
  final DateTime untilUtc;
}

/// Returns the shared UTC boundary for a personal summary period.
UtcMetricPeriod personalSummaryPeriodBounds({
  required PersonalSummaryPeriod period,
  required DateTime now,
}) {
  final nowUtc = now.toUtc();
  final tomorrowUtc = DateTime.utc(nowUtc.year, nowUtc.month, nowUtc.day + 1);
  final todayUtc = tomorrowUtc.subtract(const Duration(days: 1));
  return switch (period) {
    PersonalSummaryPeriod.today => UtcMetricPeriod(
      fromUtc: todayUtc,
      untilUtc: tomorrowUtc,
    ),
    PersonalSummaryPeriod.recentSevenDays => UtcMetricPeriod(
      fromUtc: todayUtc.subtract(const Duration(days: 6)),
      untilUtc: tomorrowUtc,
    ),
  };
}

/// 汇总页需要的事实和已统一单位的同步覆盖。
final class PersonalSummarySnapshot {
  PersonalSummarySnapshot({
    required this.period,
    required this.fromUtc,
    required this.untilUtc,
    required this.summary,
    required List<MetricResult> metrics,
  }) : metrics = List.unmodifiable(metrics);

  final PersonalSummaryPeriod period;
  final DateTime fromUtc;
  final DateTime untilUtc;
  final PersonalContactSummary summary;
  final List<MetricResult> metrics;

  int get syncedContactSessionCount =>
      summary.contactSessionCount - summary.pendingSyncCount;

  int get syncCoverageDenominator => summary.contactSessionCount;

  MetricResult metric(MetricReference reference) =>
      metrics.singleWhere((result) => result.definition.reference == reference);
}

/// 把本地个人事实映射到版本化结果合同。
///
/// 页面和导出层不得自行重算这些值或补造结果元数据。
abstract final class PersonalContactMetricMapper {
  static List<MetricResult> map({
    required PersonalContactSummary summary,
    required MetricPeriod period,
    required DateTime dataCutoffUtc,
  }) {
    _validateSummary(summary);
    final targetResponseCount = summary.targetResponseDistribution.fold<int>(
      0,
      (sum, count) => sum + count,
    );
    final coverage = MetricSyncCoverage(
      statisticalUnit: MetricStatisticalUnit.contactSession,
      totalCount: summary.contactSessionCount,
      pendingCount: summary.pendingSyncCount,
    );
    MetricResult result(MetricDefinition definition, MetricValue value) =>
        MetricResult(
          definition: definition,
          value: value,
          period: period,
          timeZone: 'UTC',
          dataCutoffUtc: dataCutoffUtc,
          sourceTier: MetricSourceTier.localOperational,
          syncCoverage: coverage,
          privacyStatus: MetricPrivacyStatus.personalFact,
        );

    return List.unmodifiable([
      result(
        CoreMetricCatalog.contactSessions,
        CountMetricValue(summary.contactSessionCount),
      ),
      result(
        CoreMetricCatalog.reachedPeople,
        CountMetricValue(summary.reachCount),
      ),
      result(
        CoreMetricCatalog.targetResponses,
        CountMetricValue(targetResponseCount),
      ),
      result(
        CoreMetricCatalog.interestDistribution,
        MetricDistributionValue(
          labels: CoreMetricCatalog.interestDistribution.bucketLabels,
          counts: summary.interestDistribution,
        ),
      ),
      result(
        CoreMetricCatalog.interestOrdinalSummary,
        OrdinalSummaryMetricValue.fromCounts(
          labels: CoreMetricCatalog.interestOrdinalSummary.bucketLabels,
          counts: summary.interestDistribution,
        ),
      ),
      result(
        CoreMetricCatalog.interestLevelRatios,
        RatioMetricValue.fromCounts(
          labels: CoreMetricCatalog.interestLevelRatios.bucketLabels,
          counts: summary.interestDistribution,
        ),
      ),
      result(
        CoreMetricCatalog.interestThreeFourRatio,
        SubsetRatioMetricValue(
          label: CoreMetricCatalog.interestThreeFourRatio.bucketLabels.single,
          numerator:
              summary.interestDistribution[3] + summary.interestDistribution[4],
          denominator: summary.contactSessionCount,
        ),
      ),
      result(
        CoreMetricCatalog.interestZeroRatio,
        SubsetRatioMetricValue(
          label: CoreMetricCatalog.interestZeroRatio.bucketLabels.single,
          numerator: summary.interestDistribution[0],
          denominator: summary.contactSessionCount,
        ),
      ),
      result(
        CoreMetricCatalog.channelDistribution,
        MetricDistributionValue(
          labels: CoreMetricCatalog.channelDistribution.bucketLabels,
          counts: summary.channelDistribution,
        ),
      ),
      result(
        CoreMetricCatalog.targetResponseDistribution,
        TargetResponseDistributionMetricValue(
          labels: CoreMetricCatalog.targetResponseDistribution.bucketLabels,
          counts: summary.targetResponseDistribution,
          unansweredCount: summary.targetResponseUnansweredCount,
        ),
      ),
      result(
        CoreMetricCatalog.targetResponseOrdinalSummary,
        OrdinalSummaryMetricValue.fromCounts(
          labels: CoreMetricCatalog.targetResponseOrdinalSummary.bucketLabels,
          counts: summary.targetResponseDistribution,
        ),
      ),
      result(
        CoreMetricCatalog.targetResponseLevelRatios,
        RatioMetricValue.fromCounts(
          labels: CoreMetricCatalog.targetResponseLevelRatios.bucketLabels,
          counts: summary.targetResponseDistribution,
          unansweredCount: summary.targetResponseUnansweredCount,
        ),
      ),
    ]);
  }

  static void _validateSummary(PersonalContactSummary summary) {
    if (summary.contactSessionCount < 0 ||
        summary.reachCount < 0 ||
        summary.pendingSyncCount < 0 ||
        summary.pendingSyncCount > summary.contactSessionCount ||
        summary.interestDistribution.length != 5 ||
        summary.channelDistribution.length != ContactChannel.values.length ||
        summary.interestDistribution.any((count) => count < 0) ||
        summary.channelDistribution.any((count) => count < 0) ||
        summary.interestDistribution.fold<int>(
              0,
              (sum, count) => sum + count,
            ) !=
            summary.contactSessionCount ||
        summary.channelDistribution.fold<int>(0, (sum, count) => sum + count) !=
            summary.contactSessionCount ||
        summary.targetResponseDistribution.length != 5 ||
        summary.targetResponseDistribution.any((count) => count < 0) ||
        summary.targetResponseUnansweredCount < 0) {
      throw StateError('invalid_personal_contact_summary');
    }
  }
}

/// 接触列表页的一致读取快照。
final class ContactOverviewSnapshot {
  const ContactOverviewSnapshot({
    required this.contacts,
    required this.drafts,
    required this.attempts,
    required this.todaySummary,
    required this.syncHealth,
  });

  final List<ContactRecord> contacts;
  final List<ContactDraft> drafts;
  final List<ContactAttempt> attempts;
  final PersonalContactSummary todaySummary;
  final SyncHealth? syncHealth;
}

/// 指标编排层依赖的最小事实接口。
abstract interface class PersonalContactOverviewSource {
  Future<List<ContactRecord>> listContactRecords({
    required String appUserId,
    required String workspaceId,
    required String projectId,
  });

  Future<List<ContactDraft>> listDrafts({required String appUserId});

  Future<List<ContactAttempt>> listContactAttempts({
    required String appUserId,
    required String workspaceId,
    required String projectId,
  });

  Future<PersonalContactSummary> summarizePersonalContacts({
    required String appUserId,
    required String workspaceId,
    required String projectId,
    required DateTime fromUtc,
    required DateTime untilUtc,
  });
}

/// 把 ContactJournal 收窄为指标编排层所需的只读接口。
final class ContactJournalOverviewSource
    implements PersonalContactOverviewSource {
  const ContactJournalOverviewSource(this._journal);

  final ContactJournal _journal;

  @override
  Future<List<ContactRecord>> listContactRecords({
    required String appUserId,
    required String workspaceId,
    required String projectId,
  }) => _journal.listContactRecords(
    appUserId: appUserId,
    workspaceId: workspaceId,
    projectId: projectId,
  );

  @override
  Future<List<ContactDraft>> listDrafts({required String appUserId}) =>
      _journal.listDrafts(appUserId: appUserId);

  @override
  Future<List<ContactAttempt>> listContactAttempts({
    required String appUserId,
    required String workspaceId,
    required String projectId,
  }) => _journal.listContactAttempts(
    appUserId: appUserId,
    workspaceId: workspaceId,
    projectId: projectId,
  );

  @override
  Future<PersonalContactSummary> summarizePersonalContacts({
    required String appUserId,
    required String workspaceId,
    required String projectId,
    required DateTime fromUtc,
    required DateTime untilUtc,
  }) => _journal.summarizePersonalContacts(
    appUserId: appUserId,
    workspaceId: workspaceId,
    projectId: projectId,
    fromUtc: fromUtc,
    untilUtc: untilUtc,
  );
}

/// 统一统计时间边界、数据读取和同步覆盖口径。
///
/// 页面不再自行计算“七日”或用不同单位相减。以后项目拥有报告时区时，只需在
/// 此模块替换 [periodBounds]，所有消费者会同时采用新边界。
final class PersonalContactOverviewRepository {
  factory PersonalContactOverviewRepository({
    required PersonalContactOverviewSource source,
    required DateTime Function() now,
    Future<SyncHealth?> Function()? loadSyncHealth,
  }) => PersonalContactOverviewRepository._(source, now, loadSyncHealth);

  const PersonalContactOverviewRepository._(
    this._source,
    this._now,
    this._loadSyncHealth,
  );

  final PersonalContactOverviewSource _source;
  final DateTime Function() _now;
  final Future<SyncHealth?> Function()? _loadSyncHealth;

  UtcMetricPeriod periodBounds(PersonalSummaryPeriod period) {
    return personalSummaryPeriodBounds(period: period, now: _now());
  }

  Future<PersonalSummarySnapshot> loadSummary({
    required TrustedSessionContext context,
    required PersonalSummaryPeriod period,
  }) async {
    final bounds = periodBounds(period);
    final summary = await _source.summarizePersonalContacts(
      appUserId: context.appUserId,
      workspaceId: context.workspace.id,
      projectId: context.project.id,
      fromUtc: bounds.fromUtc,
      untilUtc: bounds.untilUtc,
    );
    final metricPeriod = MetricPeriod(
      fromUtc: bounds.fromUtc,
      untilUtc: bounds.untilUtc,
    );
    return PersonalSummarySnapshot(
      period: period,
      fromUtc: bounds.fromUtc,
      untilUtc: bounds.untilUtc,
      summary: summary,
      metrics: PersonalContactMetricMapper.map(
        summary: summary,
        period: metricPeriod,
        dataCutoffUtc: _now().toUtc(),
      ),
    );
  }

  Future<ContactOverviewSnapshot> loadContacts({
    required TrustedSessionContext context,
  }) async {
    final contacts = await _source.listContactRecords(
      appUserId: context.appUserId,
      workspaceId: context.workspace.id,
      projectId: context.project.id,
    );
    final drafts = await _source.listDrafts(appUserId: context.appUserId);
    final attempts = await _source.listContactAttempts(
      appUserId: context.appUserId,
      workspaceId: context.workspace.id,
      projectId: context.project.id,
    );
    final today = await loadSummary(
      context: context,
      period: PersonalSummaryPeriod.today,
    );
    final health = await _loadSyncHealth?.call();
    return ContactOverviewSnapshot(
      contacts: List.unmodifiable(contacts),
      drafts: List.unmodifiable(drafts),
      attempts: List.unmodifiable(attempts),
      todaySummary: today.summary,
      syncHealth: health,
    );
  }
}
