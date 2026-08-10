import 'package:flutter_test/flutter_test.dart';
import 'package:tongxingzhe_app/features/contact_metrics/metric_contract.dart';

void main() {
  test('核心指标目录使用唯一且不可变的版本标识', () {
    expect(CoreMetricCatalog.definitions, hasLength(4));
    expect(
      CoreMetricCatalog.definitions
          .map((definition) => definition.reference)
          .toSet(),
      {
        const MetricReference('contact_sessions', 1),
        const MetricReference('reached_people', 1),
        const MetricReference('interest_distribution', 1),
        const MetricReference('channel_distribution', 1),
      },
    );
    expect(
      CoreMetricCatalog.interestDistribution.statisticalUnit,
      MetricStatisticalUnit.contactSession,
    );
    expect(
      CoreMetricCatalog.interestDistribution.denominator,
      CoreMetricCatalog.contactSessions.reference,
    );
    expect(
      CoreMetricCatalog.reachedPeople.statisticalUnit,
      MetricStatisticalUnit.reachedPerson,
    );
    expect(
      CoreMetricCatalog.definitions.every(
        (definition) =>
            definition.exclusions.contains(MetricExclusion.draft) &&
            definition.exclusions.contains(MetricExclusion.contactAttempt) &&
            definition.exclusions.contains(MetricExclusion.voidedContact),
      ),
      isTrue,
    );
    expect(
      () =>
          CoreMetricCatalog.definitions.add(CoreMetricCatalog.contactSessions),
      throwsUnsupportedError,
    );
    expect(
      () => MetricCatalog([
        CoreMetricCatalog.contactSessions,
        CoreMetricCatalog.contactSessions,
      ]),
      throwsArgumentError,
    );
  });

  test('指标结果拒绝错误值形状、期间、截止时间与同步覆盖', () {
    expect(
      () => MetricResult(
        definition: CoreMetricCatalog.interestDistribution,
        value: CountMetricValue(2),
        period: _period,
        timeZone: 'UTC',
        dataCutoffUtc: DateTime.utc(2030, 1, 8, 18),
        sourceTier: MetricSourceTier.localOperational,
        syncCoverage: _coverage,
        privacyStatus: MetricPrivacyStatus.personalFact,
      ),
      throwsArgumentError,
    );
    expect(() => CountMetricValue(-1), throwsArgumentError);
    expect(
      () => MetricDistributionValue(
        labels: const ['0', '1'],
        counts: const [1, -1],
      ),
      throwsArgumentError,
    );
    expect(
      () => MetricPeriod(
        fromUtc: DateTime.utc(2030, 1, 9),
        untilUtc: DateTime.utc(2030, 1, 8),
      ),
      throwsArgumentError,
    );
    expect(
      () => MetricSyncCoverage(
        statisticalUnit: MetricStatisticalUnit.contactSession,
        totalCount: 2,
        pendingCount: 3,
      ),
      throwsArgumentError,
    );
    expect(
      () => MetricResult(
        definition: CoreMetricCatalog.contactSessions,
        value: CountMetricValue(2),
        period: _period,
        timeZone: 'UTC',
        dataCutoffUtc: DateTime(2030, 1, 8, 18),
        sourceTier: MetricSourceTier.localOperational,
        syncCoverage: _coverage,
        privacyStatus: MetricPrivacyStatus.personalFact,
      ),
      throwsArgumentError,
    );
  });

  test('隐藏管理结果不携带精确值或伪造本地同步覆盖', () {
    final suppressed = MetricResult(
      definition: CoreMetricCatalog.contactSessions,
      value: const SuppressedMetricValue(),
      period: _period,
      timeZone: 'UTC',
      dataCutoffUtc: DateTime.utc(2030, 1, 9),
      sourceTier: MetricSourceTier.backendOperational,
      privacyStatus: MetricPrivacyStatus.suppressed,
    );

    expect(suppressed.value, const SuppressedMetricValue());
    expect(suppressed.syncCoverage, isNull);
    expect(
      () => MetricResult(
        definition: CoreMetricCatalog.contactSessions,
        value: CountMetricValue(9),
        period: _period,
        timeZone: 'UTC',
        dataCutoffUtc: DateTime.utc(2030, 1, 9),
        sourceTier: MetricSourceTier.backendOperational,
        privacyStatus: MetricPrivacyStatus.suppressed,
      ),
      throwsArgumentError,
    );
    expect(
      () => MetricResult(
        definition: CoreMetricCatalog.contactSessions,
        value: const SuppressedMetricValue(),
        period: _period,
        timeZone: 'UTC',
        dataCutoffUtc: DateTime.utc(2030, 1, 9),
        sourceTier: MetricSourceTier.backendOperational,
        privacyStatus: MetricPrivacyStatus.displayed,
      ),
      throwsArgumentError,
    );
    expect(
      () => MetricResult(
        definition: CoreMetricCatalog.contactSessions,
        value: CountMetricValue(10),
        period: _period,
        timeZone: 'UTC',
        dataCutoffUtc: DateTime.utc(2030, 1, 9),
        sourceTier: MetricSourceTier.localOperational,
        privacyStatus: MetricPrivacyStatus.personalFact,
      ),
      throwsArgumentError,
    );
  });
}

final _period = MetricPeriod(
  fromUtc: DateTime.utc(2030, 1, 8),
  untilUtc: DateTime.utc(2030, 1, 9),
);

final _coverage = MetricSyncCoverage(
  statisticalUnit: MetricStatisticalUnit.contactSession,
  totalCount: 2,
  pendingCount: 1,
);
