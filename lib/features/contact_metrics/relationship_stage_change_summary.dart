import 'metric_contract.dart';

/// Versioned response contract returned by the personal stage-change endpoint.
const personalRelationshipStageChangeSummaryContract =
    'personal_relationship_stage_change_summary_result_v1';

/// The stage-change endpoint's stable time basis.
const personalRelationshipStageChangeSummaryTimeBasis =
    'relationshipChangedAtUtc';

/// The four aggregate values returned by the stage-change summary endpoint.
final class RelationshipStageChangeSummaryValue {
  factory RelationshipStageChangeSummaryValue({
    required int eventCount,
    required int distinctRelationshipCount,
    required int upwardCount,
    required int downwardCount,
  }) {
    final counts = [
      eventCount,
      distinctRelationshipCount,
      upwardCount,
      downwardCount,
    ];
    if (counts.any(_unsafeCount)) {
      throw ArgumentError('invalid_relationship_stage_change_count');
    }
    final directionTotal =
        BigInt.from(upwardCount) + BigInt.from(downwardCount);
    if (directionTotal > BigInt.from(_maximumSafeInteger) ||
        eventCount != directionTotal.toInt() ||
        distinctRelationshipCount > eventCount) {
      throw ArgumentError('invalid_relationship_stage_change_value');
    }
    return RelationshipStageChangeSummaryValue._(
      eventCount: eventCount,
      distinctRelationshipCount: distinctRelationshipCount,
      upwardCount: upwardCount,
      downwardCount: downwardCount,
    );
  }

  const RelationshipStageChangeSummaryValue._({
    required this.eventCount,
    required this.distinctRelationshipCount,
    required this.upwardCount,
    required this.downwardCount,
  });

  final int eventCount;
  final int distinctRelationshipCount;
  final int upwardCount;
  final int downwardCount;

  @override
  bool operator ==(Object other) =>
      other is RelationshipStageChangeSummaryValue &&
      other.eventCount == eventCount &&
      other.distinctRelationshipCount == distinctRelationshipCount &&
      other.upwardCount == upwardCount &&
      other.downwardCount == downwardCount;

  @override
  int get hashCode => Object.hash(
    eventCount,
    distinctRelationshipCount,
    upwardCount,
    downwardCount,
  );
}

/// A typed, PII-free personal stage-change aggregate.
///
/// The backend resolves the current project from the trusted identity
/// context. [projectId] is retained in the result so callers can reject a
/// response that arrived for a different project scope.
final class PersonalRelationshipStageChangeSummary {
  factory PersonalRelationshipStageChangeSummary({
    required String projectId,
    required MetricPeriod period,
    required DateTime dataCutoffUtc,
    required DateTime authorizedAtUtc,
    required RelationshipStageChangeSummaryValue value,
    DateTime? retrievedAtUtc,
  }) {
    final normalizedProjectId = projectId.trim().toLowerCase();
    final receivedAt = retrievedAtUtc ?? dataCutoffUtc;
    if (!_isUuid(normalizedProjectId) ||
        !_validUtcBoundary(period.fromUtc) ||
        !_validUtcBoundary(period.untilUtc) ||
        !_validUtcBoundary(dataCutoffUtc) ||
        !_validUtcBoundary(authorizedAtUtc) ||
        dataCutoffUtc != authorizedAtUtc ||
        !receivedAt.isUtc ||
        dataCutoffUtc.isAfter(receivedAt)) {
      throw ArgumentError('invalid_relationship_stage_change_summary');
    }
    return PersonalRelationshipStageChangeSummary._(
      projectId: normalizedProjectId,
      period: period,
      dataCutoffUtc: dataCutoffUtc,
      authorizedAtUtc: authorizedAtUtc,
      retrievedAtUtc: receivedAt,
      value: value,
    );
  }

  factory PersonalRelationshipStageChangeSummary.fromCounts({
    required String projectId,
    required DateTime fromUtc,
    required DateTime untilUtc,
    required DateTime dataCutoffUtc,
    required DateTime authorizedAtUtc,
    DateTime? retrievedAtUtc,
    required int eventCount,
    required int distinctRelationshipCount,
    required int upwardCount,
    required int downwardCount,
  }) => PersonalRelationshipStageChangeSummary(
    projectId: projectId,
    period: MetricPeriod(fromUtc: fromUtc, untilUtc: untilUtc),
    dataCutoffUtc: dataCutoffUtc,
    authorizedAtUtc: authorizedAtUtc,
    retrievedAtUtc: retrievedAtUtc,
    value: RelationshipStageChangeSummaryValue(
      eventCount: eventCount,
      distinctRelationshipCount: distinctRelationshipCount,
      upwardCount: upwardCount,
      downwardCount: downwardCount,
    ),
  );

  const PersonalRelationshipStageChangeSummary._({
    required this.projectId,
    required this.period,
    required this.dataCutoffUtc,
    required this.authorizedAtUtc,
    required this.retrievedAtUtc,
    required this.value,
  });

  final String projectId;
  final MetricPeriod period;
  final DateTime dataCutoffUtc;
  final DateTime authorizedAtUtc;
  final DateTime retrievedAtUtc;
  final RelationshipStageChangeSummaryValue value;

  String get contractId => personalRelationshipStageChangeSummaryContract;
  String get timeBasis => personalRelationshipStageChangeSummaryTimeBasis;
  int get eventCount => value.eventCount;
  int get distinctRelationshipCount => value.distinctRelationshipCount;
  int get upwardCount => value.upwardCount;
  int get downwardCount => value.downwardCount;

  /// The three metrics are created together so their shared period, cutoff,
  /// and arithmetic invariants cannot drift between consumers.
  List<MetricResult> get metrics => List.unmodifiable([
    _metric(
      CoreMetricCatalog.relationshipStageChangeEvents,
      CountMetricValue(eventCount),
    ),
    _metric(
      CoreMetricCatalog.relationshipsWithStageChange,
      CountMetricValue(distinctRelationshipCount),
    ),
    _metric(
      CoreMetricCatalog.relationshipStageChangeDirectionDistribution,
      MetricDistributionValue(
        labels: CoreMetricCatalog
            .relationshipStageChangeDirectionDistribution
            .bucketLabels,
        counts: [upwardCount, downwardCount],
      ),
    ),
  ]);

  MetricResult metric(MetricReference reference) =>
      metrics.singleWhere((result) => result.definition.reference == reference);

  @override
  bool operator ==(Object other) =>
      other is PersonalRelationshipStageChangeSummary &&
      other.projectId == projectId &&
      other.period.fromUtc == period.fromUtc &&
      other.period.untilUtc == period.untilUtc &&
      other.dataCutoffUtc == dataCutoffUtc &&
      other.authorizedAtUtc == authorizedAtUtc &&
      other.value == value;

  @override
  int get hashCode => Object.hash(
    projectId,
    period.fromUtc,
    period.untilUtc,
    dataCutoffUtc,
    authorizedAtUtc,
    value,
  );

  MetricResult _metric(MetricDefinition definition, MetricValue metricValue) =>
      MetricResult(
        definition: definition,
        value: metricValue,
        period: period,
        timeZone: 'UTC',
        dataCutoffUtc: dataCutoffUtc,
        retrievedAtUtc: retrievedAtUtc,
        sourceTier: MetricSourceTier.backendOperational,
        privacyStatus: MetricPrivacyStatus.personalFact,
      );
}

enum PersonalRelationshipStageChangeSummaryFailureCode {
  notConfigured,
  unauthorized,
  invalidRequest,
  forbidden,
  networkUnavailable,
  invalidResponse,
  serviceUnavailable,
  serverRejected,
}

sealed class PersonalRelationshipStageChangeSummaryGatewayResult {
  const PersonalRelationshipStageChangeSummaryGatewayResult();
}

final class PersonalRelationshipStageChangeSummaryGatewaySuccess
    extends PersonalRelationshipStageChangeSummaryGatewayResult {
  const PersonalRelationshipStageChangeSummaryGatewaySuccess(this.value);

  final PersonalRelationshipStageChangeSummary value;
}

final class PersonalRelationshipStageChangeSummaryGatewayRejected
    extends PersonalRelationshipStageChangeSummaryGatewayResult {
  const PersonalRelationshipStageChangeSummaryGatewayRejected(this.code);

  final PersonalRelationshipStageChangeSummaryFailureCode code;
}

abstract interface class PersonalRelationshipStageChangeSummaryGateway {
  Future<PersonalRelationshipStageChangeSummaryGatewayResult> load({
    required String projectId,
    required DateTime fromUtc,
    required DateTime untilUtc,
  });

  Future<void> close();
}

bool _unsafeCount(int value) => value < 0 || value > _maximumSafeInteger;

bool _validUtcBoundary(DateTime value) => value.isUtc && value.microsecond == 0;

bool _isUuid(String value) => _uuidPattern.hasMatch(value);

final _uuidPattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  caseSensitive: false,
);

const _maximumSafeInteger = 9007199254740991;
