import 'metric_contract.dart';

const personalFollowUpConsentRatioContract =
    'personal_follow_up_consent_ratio_result_v1';
const personalFollowUpConsentRatioMetricId = 'follow_up_consent_ratio@1';

sealed class PersonalFollowUpConsentRatioResult {
  const PersonalFollowUpConsentRatioResult({required this.projectId});

  final String projectId;
}

/// 项目未启用时不携带期间、数值或覆盖字段。
final class PersonalFollowUpConsentRatioNotEnabled
    extends PersonalFollowUpConsentRatioResult {
  const PersonalFollowUpConsentRatioNotEnabled({required super.projectId});
}

final class PersonalFollowUpConsentRatioReady
    extends PersonalFollowUpConsentRatioResult {
  factory PersonalFollowUpConsentRatioReady({
    required String projectId,
    required MetricResult metric,
  }) {
    if (projectId.trim().isEmpty ||
        metric.definition != CoreMetricCatalog.followUpConsentRatio ||
        metric.sourceTier != MetricSourceTier.backendOperational ||
        metric.privacyStatus != MetricPrivacyStatus.personalFact ||
        metric.syncCoverage != null) {
      throw ArgumentError('invalid_personal_follow_up_consent_ratio_ready');
    }
    return PersonalFollowUpConsentRatioReady._(
      projectId: projectId,
      metric: metric,
    );
  }

  const PersonalFollowUpConsentRatioReady._({
    required super.projectId,
    required this.metric,
  });

  final MetricResult metric;
}

enum PersonalFollowUpConsentRatioFailureCode {
  notConfigured,
  unauthorized,
  invalidRequest,
  forbidden,
  networkUnavailable,
  invalidResponse,
  serviceUnavailable,
  serverRejected,
}

sealed class PersonalFollowUpConsentRatioGatewayResult {
  const PersonalFollowUpConsentRatioGatewayResult();
}

final class PersonalFollowUpConsentRatioGatewaySuccess
    extends PersonalFollowUpConsentRatioGatewayResult {
  const PersonalFollowUpConsentRatioGatewaySuccess(this.value);

  final PersonalFollowUpConsentRatioResult value;
}

final class PersonalFollowUpConsentRatioGatewayRejected
    extends PersonalFollowUpConsentRatioGatewayResult {
  const PersonalFollowUpConsentRatioGatewayRejected(this.code);

  final PersonalFollowUpConsentRatioFailureCode code;
}

abstract interface class PersonalFollowUpConsentRatioGateway {
  Future<PersonalFollowUpConsentRatioGatewayResult> load({
    required String projectId,
    required DateTime fromUtc,
    required DateTime untilUtc,
  });

  Future<void> close();
}

/// 把 Backend 已验证的 ready 数值装入共享指标合同。
MetricResult consentRatioMetricResult({
  required DateTime fromUtc,
  required DateTime untilUtc,
  DateTime? dataCutoffUtc,
  required DateTime retrievedAtUtc,
  required int yesCount,
  required int noCount,
  int? numerator,
  required int unknownCount,
  required int refusedCount,
  required int notApplicableCount,
  required int unansweredCount,
  required int excludedCount,
  int? denominator,
  int? percentageBasisPoints,
}) {
  final counts = [
    yesCount,
    noCount,
    unknownCount,
    refusedCount,
    notApplicableCount,
    unansweredCount,
    excludedCount,
  ];
  if (counts.any((count) => count < 0 || count > _maximumSafeInteger)) {
    throw ArgumentError('invalid_personal_follow_up_consent_ratio_count');
  }
  final expectedDenominator = yesCount + noCount;
  final resolvedNumerator = numerator ?? yesCount;
  final resolvedDenominator = denominator ?? expectedDenominator;
  final expectedBasisPoints = _basisPoints(yesCount, expectedDenominator);
  final resolvedBasisPoints = percentageBasisPoints ?? expectedBasisPoints;
  if (expectedDenominator > _maximumSafeInteger ||
      resolvedNumerator != yesCount ||
      resolvedDenominator != expectedDenominator ||
      unknownCount != 0 ||
      excludedCount != 0 ||
      resolvedBasisPoints != expectedBasisPoints) {
    throw ArgumentError('invalid_personal_follow_up_consent_ratio_value');
  }

  return MetricResult(
    definition: CoreMetricCatalog.followUpConsentRatio,
    value: RatioMetricValue.fromNumerators(
      labels: CoreMetricCatalog.followUpConsentRatio.bucketLabels,
      numerators: [yesCount, noCount],
      denominator: expectedDenominator,
      unknownCount: unknownCount,
      refusedCount: refusedCount,
      notApplicableCount: notApplicableCount,
      unansweredCount: unansweredCount,
      excludedCount: excludedCount,
    ),
    period: MetricPeriod(fromUtc: fromUtc, untilUtc: untilUtc),
    timeZone: 'UTC',
    dataCutoffUtc: dataCutoffUtc,
    retrievedAtUtc: retrievedAtUtc,
    sourceTier: MetricSourceTier.backendOperational,
    privacyStatus: MetricPrivacyStatus.personalFact,
  );
}

int? _basisPoints(int numerator, int denominator) {
  if (denominator == 0) return null;
  return ((BigInt.from(numerator) * BigInt.from(20000) +
              BigInt.from(denominator)) ~/
          (BigInt.from(denominator) * BigInt.from(2)))
      .toInt();
}

const _maximumSafeInteger = 9007199254740991;
