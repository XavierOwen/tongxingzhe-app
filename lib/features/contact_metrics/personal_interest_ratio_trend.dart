import 'metric_contract.dart';

/// One personal metric result bound to the scope that produced it.
final class PersonalInterestRatioTrendObservation {
  const PersonalInterestRatioTrendObservation({
    required this.scope,
    required this.metric,
  });

  final PersonalMetricScope scope;
  final MetricResult metric;
}

/// A comparable pair of personal `interest_3_4_ratio@1` observations.
///
/// The constructor is deliberately fail-closed. A pair is created only when
/// both results carry the same metric contract, reporting metadata, complete
/// seven-day periods, and trusted personal-fact status. Callers therefore do
/// not need to re-check the comparison preconditions before using the values.
final class PersonalInterestRatioTrendComparison {
  factory PersonalInterestRatioTrendComparison({
    required PersonalInterestRatioTrendObservation previous,
    required PersonalInterestRatioTrendObservation current,
  }) {
    final previousMetric = previous.metric;
    final currentMetric = current.metric;
    final previousRatio = _validateMetric(previousMetric);
    final currentRatio = _validateMetric(currentMetric);
    final currentCutoffUtc = currentMetric.dataCutoffUtc;

    if (previous.scope != current.scope ||
        previousMetric.definition.statisticalUnit !=
            currentMetric.definition.statisticalUnit ||
        previousMetric.definition.formula != currentMetric.definition.formula ||
        previousMetric.definition.timeBasis !=
            currentMetric.definition.timeBasis ||
        previousMetric.sourceTier != MetricSourceTier.localOperational ||
        currentMetric.sourceTier != MetricSourceTier.localOperational ||
        previousMetric.timeZone != 'UTC' ||
        currentMetric.timeZone != 'UTC' ||
        previousMetric.timeZone != currentMetric.timeZone ||
        previousMetric.dataCutoffUtc == null ||
        currentCutoffUtc == null ||
        previousMetric.dataCutoffUtc != currentMetric.dataCutoffUtc ||
        previousMetric.privacyStatus != MetricPrivacyStatus.personalFact ||
        currentMetric.privacyStatus != MetricPrivacyStatus.personalFact ||
        !_isCompleteSevenDayPeriod(previousMetric.period) ||
        !_isCompleteSevenDayPeriod(currentMetric.period) ||
        previousMetric.period.untilUtc != currentMetric.period.fromUtc ||
        currentMetric.period.untilUtc != _utcMidnight(currentCutoffUtc)) {
      throw ArgumentError('invalid_personal_interest_ratio_trend');
    }

    return PersonalInterestRatioTrendComparison._(
      scope: previous.scope,
      previous: previousMetric,
      current: currentMetric,
      previousRatio: previousRatio,
      currentRatio: currentRatio,
    );
  }

  const PersonalInterestRatioTrendComparison._({
    required this.scope,
    required this.previous,
    required this.current,
    required this.previousRatio,
    required this.currentRatio,
  });

  /// The trusted identity, workspace, and project shared by both results.
  final PersonalMetricScope scope;

  /// The earlier complete seven-day result.
  final MetricResult previous;

  /// The later complete seven-day result.
  final MetricResult current;

  /// The earlier result's original integer numerator, denominator, coverage,
  /// and half-up percentage basis point value.
  final SubsetRatioMetricValue previousRatio;

  /// The later result's original integer numerator, denominator, coverage, and
  /// half-up percentage basis point value.
  final SubsetRatioMetricValue currentRatio;

  /// The fixed duration required for each compared period.
  Duration get periodDuration => const Duration(days: 7);

  /// The later percentage basis points minus the earlier percentage basis
  /// points. An empty denominator in either period makes the delta unknown.
  int? get deltaBasisPoints {
    final previousBasisPoints = previousRatio.percentageBasisPoints;
    final currentBasisPoints = currentRatio.percentageBasisPoints;
    if (previousBasisPoints == null || currentBasisPoints == null) return null;
    return currentBasisPoints - previousBasisPoints;
  }

  @override
  bool operator ==(Object other) =>
      other is PersonalInterestRatioTrendComparison &&
      other.previous == previous &&
      other.current == current;

  @override
  int get hashCode => Object.hash(previous, current);
}

/// Creates a fail-closed comparison of two adjacent personal interest ratio
/// results.
PersonalInterestRatioTrendComparison comparePersonalInterestRatioTrend({
  required PersonalInterestRatioTrendObservation previous,
  required PersonalInterestRatioTrendObservation current,
}) =>
    PersonalInterestRatioTrendComparison(previous: previous, current: current);

SubsetRatioMetricValue _validateMetric(MetricResult metric) {
  final expected = CoreMetricCatalog.interestThreeFourRatio;
  final definition = metric.definition;
  if (definition.reference != expected.reference ||
      definition.statisticalUnit != expected.statisticalUnit ||
      definition.valueShape != expected.valueShape ||
      definition.formula != expected.formula ||
      definition.timeBasis != expected.timeBasis ||
      definition.privacyRule != expected.privacyRule ||
      definition.managementPrivacyUnit != expected.managementPrivacyUnit ||
      definition.denominator != expected.denominator ||
      definition.exclusions.length != expected.exclusions.length ||
      !definition.exclusions.containsAll(expected.exclusions) ||
      definition.bucketLabels.length != expected.bucketLabels.length ||
      !_sameStrings(definition.bucketLabels, expected.bucketLabels) ||
      metric.privacyStatus != MetricPrivacyStatus.personalFact ||
      metric.syncCoverage == null ||
      !metric.syncCoverage!.isKnown ||
      metric.syncCoverage!.statisticalUnit !=
          MetricStatisticalUnit.contactSession ||
      metric.value is! SubsetRatioMetricValue) {
    throw ArgumentError('invalid_personal_interest_ratio_trend');
  }
  final value = metric.value as SubsetRatioMetricValue;
  if (metric.syncCoverage!.totalCount != value.denominator) {
    throw ArgumentError('invalid_personal_interest_ratio_trend');
  }
  return value;
}

bool _isCompleteSevenDayPeriod(MetricPeriod period) =>
    _isUtcMidnight(period.fromUtc) &&
    _isUtcMidnight(period.untilUtc) &&
    period.untilUtc.difference(period.fromUtc) == const Duration(days: 7);

bool _isUtcMidnight(DateTime value) =>
    value.isUtc &&
    value.hour == 0 &&
    value.minute == 0 &&
    value.second == 0 &&
    value.millisecond == 0 &&
    value.microsecond == 0;

DateTime _utcMidnight(DateTime value) =>
    DateTime.utc(value.year, value.month, value.day);

bool _sameStrings(List<String> left, List<String> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) return false;
  }
  return true;
}
