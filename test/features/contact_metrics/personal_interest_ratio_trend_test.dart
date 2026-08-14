import 'package:flutter_test/flutter_test.dart';
import 'package:tongxingzhe_app/features/contact_metrics/metric_contract.dart';
import 'package:tongxingzhe_app/features/contact_metrics/personal_interest_ratio_trend.dart';

void main() {
  test('compares adjacent seven-day ratios and exposes original values', () {
    final comparison = _compare(
      previous: _metric(
        fromUtc: DateTime.utc(2030, 1, 1),
        untilUtc: DateTime.utc(2030, 1, 8),
        numerator: 1,
        denominator: 3,
      ),
      current: _metric(
        fromUtc: DateTime.utc(2030, 1, 8),
        untilUtc: DateTime.utc(2030, 1, 15),
        numerator: 2,
        denominator: 3,
      ),
    );

    expect(comparison.previous.period.fromUtc, DateTime.utc(2030, 1, 1));
    expect(comparison.current.period.untilUtc, DateTime.utc(2030, 1, 15));
    expect(comparison.previousRatio.numerator, 1);
    expect(comparison.previousRatio.denominator, 3);
    expect(comparison.previousRatio.percentageBasisPoints, 3333);
    expect(comparison.currentRatio.numerator, 2);
    expect(comparison.currentRatio.denominator, 3);
    expect(comparison.currentRatio.percentageBasisPoints, 6667);
    expect(comparison.periodDuration, const Duration(days: 7));
    expect(comparison.deltaBasisPoints, 3334);
  });

  test('reports positive, negative, and zero basis-point changes', () {
    PersonalInterestRatioTrendComparison build(int previous, int current) {
      return _compare(
        previous: _metric(
          fromUtc: DateTime.utc(2030, 1, 1),
          untilUtc: DateTime.utc(2030, 1, 8),
          numerator: previous,
          denominator: 4,
        ),
        current: _metric(
          fromUtc: DateTime.utc(2030, 1, 8),
          untilUtc: DateTime.utc(2030, 1, 15),
          numerator: current,
          denominator: 4,
        ),
      );
    }

    expect(build(1, 3).deltaBasisPoints, 5000);
    expect(build(3, 1).deltaBasisPoints, -5000);
    expect(build(2, 2).deltaBasisPoints, 0);
  });

  test(
    'uses the existing half-up basis-point values without floating point',
    () {
      final comparison = _compare(
        previous: _metric(
          fromUtc: DateTime.utc(2030, 1, 1),
          untilUtc: DateTime.utc(2030, 1, 8),
          numerator: 2,
          denominator: 3,
        ),
        current: _metric(
          fromUtc: DateTime.utc(2030, 1, 8),
          untilUtc: DateTime.utc(2030, 1, 15),
          numerator: 1,
          denominator: 3,
        ),
      );

      expect(comparison.previousRatio.percentageBasisPoints, 6667);
      expect(comparison.currentRatio.percentageBasisPoints, 3333);
      expect(comparison.deltaBasisPoints, -3334);
    },
  );

  test(
    'does not invent a delta when either period has an empty denominator',
    () {
      final previousEmpty = _compare(
        previous: _metric(
          fromUtc: DateTime.utc(2030, 1, 1),
          untilUtc: DateTime.utc(2030, 1, 8),
          numerator: 0,
          denominator: 0,
        ),
        current: _metric(
          fromUtc: DateTime.utc(2030, 1, 8),
          untilUtc: DateTime.utc(2030, 1, 15),
          numerator: 1,
          denominator: 2,
        ),
      );
      final currentEmpty = _compare(
        previous: _metric(
          fromUtc: DateTime.utc(2030, 1, 1),
          untilUtc: DateTime.utc(2030, 1, 8),
          numerator: 1,
          denominator: 2,
        ),
        current: _metric(
          fromUtc: DateTime.utc(2030, 1, 8),
          untilUtc: DateTime.utc(2030, 1, 15),
          numerator: 0,
          denominator: 0,
        ),
      );

      expect(previousEmpty.previousRatio.percentageBasisPoints, isNull);
      expect(previousEmpty.deltaBasisPoints, isNull);
      expect(currentEmpty.currentRatio.percentageBasisPoints, isNull);
      expect(currentEmpty.deltaBasisPoints, isNull);
    },
  );

  test('fails closed for every comparison contract mismatch', () {
    final validPrevious = _metric(
      fromUtc: DateTime.utc(2030, 1, 1),
      untilUtc: DateTime.utc(2030, 1, 8),
      numerator: 1,
      denominator: 2,
    );
    final validCurrent = _metric(
      fromUtc: DateTime.utc(2030, 1, 8),
      untilUtc: DateTime.utc(2030, 1, 15),
      numerator: 1,
      denominator: 2,
    );

    void expectRejected({
      MetricResult? previous,
      MetricResult? current,
      PersonalMetricScope? previousScope,
      PersonalMetricScope? currentScope,
    }) {
      expect(
        () => _compare(
          previous: previous ?? validPrevious,
          current: current ?? validCurrent,
          previousScope: previousScope,
          currentScope: currentScope,
        ),
        throwsArgumentError,
      );
    }

    expectRejected(
      currentScope: PersonalMetricScope(
        appUserId: 'app-user-1',
        workspaceId: 'workspace-1',
        projectId: 'project-2',
      ),
    );

    expectRejected(
      previous: _metric(
        fromUtc: DateTime.utc(2030, 1, 1),
        untilUtc: DateTime.utc(2030, 1, 8),
        numerator: 1,
        denominator: 2,
        definition: _definition(
          reference: const MetricReference('different_metric', 1),
        ),
      ),
    );
    expectRejected(
      current: _metric(
        fromUtc: DateTime.utc(2030, 1, 8),
        untilUtc: DateTime.utc(2030, 1, 15),
        numerator: 1,
        denominator: 2,
        definition: _definition(
          statisticalUnit: MetricStatisticalUnit.reachedPerson,
        ),
      ),
    );
    expectRejected(
      current: _metric(
        fromUtc: DateTime.utc(2030, 1, 8),
        untilUtc: DateTime.utc(2030, 1, 15),
        numerator: 1,
        denominator: 2,
        definition: _definition(
          formula: MetricFormula.calculateContactSessionsByInterestRatio,
        ),
      ),
    );
    expectRejected(
      current: _metric(
        fromUtc: DateTime.utc(2030, 1, 8),
        untilUtc: DateTime.utc(2030, 1, 15),
        numerator: 1,
        denominator: 2,
        definition: _definition(timeBasis: MetricTimeBasis.currentSnapshotUtc),
      ),
    );
    expectRejected(
      current: _metric(
        fromUtc: DateTime.utc(2030, 1, 8),
        untilUtc: DateTime.utc(2030, 1, 15),
        numerator: 1,
        denominator: 2,
        timeZone: 'America/Chicago',
      ),
    );
    expectRejected(
      previous: _metric(
        fromUtc: DateTime.utc(2030, 1, 1),
        untilUtc: DateTime.utc(2030, 1, 8),
        numerator: 1,
        denominator: 2,
        timeZone: 'America/Chicago',
      ),
      current: _metric(
        fromUtc: DateTime.utc(2030, 1, 8),
        untilUtc: DateTime.utc(2030, 1, 15),
        numerator: 1,
        denominator: 2,
        timeZone: 'America/Chicago',
      ),
    );
    expectRejected(
      previous: _metric(
        fromUtc: DateTime.utc(2030, 1, 1),
        untilUtc: DateTime.utc(2030, 1, 7),
        numerator: 1,
        denominator: 2,
      ),
    );
    expectRejected(
      current: _metric(
        fromUtc: DateTime.utc(2030, 1, 9),
        untilUtc: DateTime.utc(2030, 1, 16),
        numerator: 1,
        denominator: 2,
      ),
    );
    expectRejected(
      current: _metric(
        fromUtc: DateTime.utc(2030, 1, 8),
        untilUtc: DateTime.utc(2030, 1, 15),
        numerator: 1,
        denominator: 2,
        dataCutoffUtc: DateTime.utc(2030, 1, 15, 2),
      ),
    );
    expectRejected(
      current: _metric(
        fromUtc: DateTime.utc(2030, 1, 8),
        untilUtc: DateTime.utc(2030, 1, 15),
        numerator: 1,
        denominator: 2,
        privacyStatus: MetricPrivacyStatus.displayed,
      ),
    );
    expectRejected(
      current: _metric(
        fromUtc: DateTime.utc(2030, 1, 8, 1),
        untilUtc: DateTime.utc(2030, 1, 15, 1),
        numerator: 1,
        denominator: 2,
      ),
    );
    expectRejected(
      current: _metric(
        fromUtc: DateTime.utc(2030, 1, 8),
        untilUtc: DateTime.utc(2030, 1, 15),
        numerator: 1,
        denominator: 2,
        dataCutoffUtc: DateTime.utc(2030, 1, 16, 1),
      ),
    );
    expectRejected(
      previous: _metric(
        fromUtc: DateTime.utc(2030, 1, 1),
        untilUtc: DateTime.utc(2030, 1, 8),
        numerator: 1,
        denominator: 2,
        omitDataCutoff: true,
        sourceTier: MetricSourceTier.backendOperational,
        retrievedAtUtc: DateTime.utc(2030, 1, 15, 2),
      ),
    );
    expectRejected(
      current: _metric(
        fromUtc: DateTime.utc(2030, 1, 8),
        untilUtc: DateTime.utc(2030, 1, 15),
        numerator: 1,
        denominator: 2,
        omitDataCutoff: true,
        sourceTier: MetricSourceTier.backendOperational,
        retrievedAtUtc: DateTime.utc(2030, 1, 15, 2),
      ),
    );
    expectRejected(
      previous: _metric(
        fromUtc: DateTime.utc(2030, 1, 1),
        untilUtc: DateTime.utc(2030, 1, 8),
        numerator: 1,
        denominator: 2,
        sourceTier: MetricSourceTier.backendOperational,
      ),
      current: _metric(
        fromUtc: DateTime.utc(2030, 1, 8),
        untilUtc: DateTime.utc(2030, 1, 15),
        numerator: 1,
        denominator: 2,
        sourceTier: MetricSourceTier.backendOperational,
      ),
    );
  });
}

final _scope = PersonalMetricScope(
  appUserId: 'app-user-1',
  workspaceId: 'workspace-1',
  projectId: 'project-1',
);

PersonalInterestRatioTrendComparison _compare({
  required MetricResult previous,
  required MetricResult current,
  PersonalMetricScope? previousScope,
  PersonalMetricScope? currentScope,
}) => comparePersonalInterestRatioTrend(
  previous: PersonalInterestRatioTrendObservation(
    scope: previousScope ?? _scope,
    metric: previous,
  ),
  current: PersonalInterestRatioTrendObservation(
    scope: currentScope ?? _scope,
    metric: current,
  ),
);

MetricResult _metric({
  required DateTime fromUtc,
  required DateTime untilUtc,
  required int numerator,
  required int denominator,
  MetricDefinition? definition,
  String timeZone = 'UTC',
  DateTime? dataCutoffUtc,
  bool omitDataCutoff = false,
  DateTime? retrievedAtUtc,
  MetricSourceTier sourceTier = MetricSourceTier.localOperational,
  MetricPrivacyStatus privacyStatus = MetricPrivacyStatus.personalFact,
}) {
  final resolvedDefinition =
      definition ?? CoreMetricCatalog.interestThreeFourRatio;
  final resolvedDataCutoff = omitDataCutoff
      ? null
      : dataCutoffUtc ?? DateTime.utc(2030, 1, 15, 1);
  return MetricResult(
    definition: resolvedDefinition,
    value: SubsetRatioMetricValue(
      label: resolvedDefinition.bucketLabels.single,
      numerator: numerator,
      denominator: denominator,
    ),
    period: MetricPeriod(fromUtc: fromUtc, untilUtc: untilUtc),
    timeZone: timeZone,
    dataCutoffUtc: resolvedDataCutoff,
    retrievedAtUtc: retrievedAtUtc,
    sourceTier: sourceTier,
    syncCoverage: sourceTier == MetricSourceTier.localOperational
        ? MetricSyncCoverage(
            statisticalUnit: MetricStatisticalUnit.contactSession,
            totalCount: denominator,
            pendingCount: 0,
          )
        : null,
    privacyStatus: privacyStatus,
  );
}

MetricDefinition _definition({
  MetricReference? reference,
  MetricStatisticalUnit statisticalUnit = MetricStatisticalUnit.contactSession,
  MetricFormula formula =
      MetricFormula.calculateContactSessionsByInterestSubsetRatio,
  MetricTimeBasis timeBasis = MetricTimeBasis.actualOccurrenceUtc,
}) => MetricDefinition(
  reference: reference ?? CoreMetricCatalog.interestThreeFourRatio.reference,
  statisticalUnit: statisticalUnit,
  valueShape: MetricValueShape.subsetRatio,
  formula: formula,
  timeBasis: timeBasis,
  exclusions: const {
    MetricExclusion.draft,
    MetricExclusion.contactAttempt,
    MetricExclusion.voidedContact,
  },
  privacyRule: MetricPrivacyRule.managementProtectedByTrueUnit,
  denominator: CoreMetricCatalog.contactSessions.reference,
  bucketLabels: const ['3_4'],
);
