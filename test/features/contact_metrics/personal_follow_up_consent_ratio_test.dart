import 'package:flutter_test/flutter_test.dart';
import 'package:tongxingzhe_app/features/contact_metrics/metric_contract.dart';
import 'package:tongxingzhe_app/features/contact_metrics/personal_follow_up_consent_ratio.dart';

void main() {
  test('optional consent ratio definition stays outside the core catalog', () {
    expect(CoreMetricCatalog.definitions, hasLength(12));
    expect(
      CoreMetricCatalog.followUpConsentRatio.reference,
      const MetricReference('follow_up_consent_ratio', 1),
    );
    expect(
      CoreMetricCatalog.followUpConsentRatio.statisticalUnit,
      MetricStatisticalUnit.contactTargetLink,
    );
    expect(
      CoreMetricCatalog.followUpConsentRatio.valueShape,
      MetricValueShape.ratio,
    );
    expect(CoreMetricCatalog.followUpConsentRatio.bucketLabels, ['yes', 'no']);
    expect(
      CoreMetricCatalog.definitions,
      isNot(contains(CoreMetricCatalog.followUpConsentRatio)),
    );
  });

  test('not enabled is an independent result without metric values', () {
    const result = PersonalFollowUpConsentRatioNotEnabled(
      projectId: _projectId,
    );

    expect(result.projectId, _projectId);
    expect(result, isA<PersonalFollowUpConsentRatioResult>());
    expect(result, isNot(isA<PersonalFollowUpConsentRatioReady>()));
  });

  test('ready carries a fixed, recomputable personal MetricResult', () {
    final metric = consentRatioMetricResult(
      fromUtc: DateTime.utc(2030, 1, 1),
      untilUtc: DateTime.utc(2030, 1, 8),
      dataCutoffUtc: DateTime.utc(2030, 1, 8, 1),
      retrievedAtUtc: DateTime.utc(2030, 1, 8, 2),
      yesCount: 2,
      noCount: 1,
      unknownCount: 0,
      refusedCount: 1,
      notApplicableCount: 1,
      unansweredCount: 2,
      excludedCount: 0,
    );
    final result = PersonalFollowUpConsentRatioReady(
      projectId: _projectId,
      metric: metric,
    );

    expect(result.projectId, _projectId);
    expect(result.metric, same(metric));
    expect(metric.definition, same(CoreMetricCatalog.followUpConsentRatio));
    expect(metric.sourceTier, MetricSourceTier.backendOperational);
    expect(metric.privacyStatus, MetricPrivacyStatus.personalFact);
    expect(metric.syncCoverage, isNull);
    final value = metric.value as RatioMetricValue;
    expect(value.numerators, [2, 1]);
    expect(value.denominator, 3);
    expect(value.basisPoints, [6667, 3333]);
    expect(value.unknownCount, 0);
    expect(value.refusedCount, 1);
    expect(value.notApplicableCount, 1);
    expect(value.unansweredCount, 2);
    expect(value.excludedCount, 0);
  });

  test('empty denominator retains no percentage', () {
    final metric = consentRatioMetricResult(
      fromUtc: DateTime.utc(2030, 1, 1),
      untilUtc: DateTime.utc(2030, 1, 8),
      dataCutoffUtc: DateTime.utc(2030, 1, 8, 1),
      retrievedAtUtc: DateTime.utc(2030, 1, 8, 2),
      yesCount: 0,
      noCount: 0,
      unknownCount: 0,
      refusedCount: 1,
      notApplicableCount: 1,
      unansweredCount: 1,
      excludedCount: 0,
    );

    final value = metric.value as RatioMetricValue;
    expect(value.denominator, 0);
    expect(value.basisPoints, [null, null]);
  });

  test(
    'v1 rejects unknown, excluded, and inconsistent authoritative counts',
    () {
      MetricResult build({
        int yes = 2,
        int no = 1,
        int numerator = 2,
        int denominator = 3,
        int? basisPoints = 6667,
        int unknown = 0,
        int excluded = 0,
      }) => consentRatioMetricResult(
        fromUtc: DateTime.utc(2030, 1, 1),
        untilUtc: DateTime.utc(2030, 1, 8),
        dataCutoffUtc: DateTime.utc(2030, 1, 8, 1),
        retrievedAtUtc: DateTime.utc(2030, 1, 8, 2),
        yesCount: yes,
        noCount: no,
        numerator: numerator,
        denominator: denominator,
        percentageBasisPoints: basisPoints,
        unknownCount: unknown,
        refusedCount: 0,
        notApplicableCount: 0,
        unansweredCount: 0,
        excludedCount: excluded,
      );

      expect(() => build(numerator: 1), throwsArgumentError);
      expect(() => build(denominator: 4), throwsArgumentError);
      expect(() => build(basisPoints: 6666), throwsArgumentError);
      expect(() => build(unknown: 1), throwsArgumentError);
      expect(() => build(excluded: 1), throwsArgumentError);
    },
  );
}

const _projectId = '33333333-3333-4333-8333-333333333333';
