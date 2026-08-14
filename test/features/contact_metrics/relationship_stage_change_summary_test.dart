import 'package:flutter_test/flutter_test.dart';
import 'package:tongxingzhe_app/features/contact_metrics/metric_contract.dart';
import 'package:tongxingzhe_app/features/contact_metrics/relationship_stage_change_summary.dart';

void main() {
  test('summary exposes trusted scope, period, cutoff, and four counts', () {
    final summary = PersonalRelationshipStageChangeSummary.fromCounts(
      projectId: _projectId,
      fromUtc: DateTime.utc(2030, 1, 1),
      untilUtc: DateTime.utc(2030, 1, 8),
      dataCutoffUtc: DateTime.utc(2030, 1, 8, 1),
      authorizedAtUtc: DateTime.utc(2030, 1, 8, 1),
      retrievedAtUtc: DateTime.utc(2030, 1, 8, 2),
      eventCount: 5,
      distinctRelationshipCount: 4,
      upwardCount: 3,
      downwardCount: 2,
    );

    expect(summary.projectId, _projectId);
    expect(summary.period.fromUtc, DateTime.utc(2030, 1, 1));
    expect(summary.period.untilUtc, DateTime.utc(2030, 1, 8));
    expect(summary.dataCutoffUtc, DateTime.utc(2030, 1, 8, 1));
    expect(summary.authorizedAtUtc, DateTime.utc(2030, 1, 8, 1));
    expect(summary.eventCount, 5);
    expect(summary.distinctRelationshipCount, 4);
    expect(summary.upwardCount, 3);
    expect(summary.downwardCount, 2);
    expect(summary.metrics, hasLength(3));
    expect(
      (summary
                  .metric(
                    CoreMetricCatalog.relationshipStageChangeEvents.reference,
                  )
                  .value
              as CountMetricValue)
          .value,
      5,
    );
    final directions =
        summary
                .metric(
                  CoreMetricCatalog
                      .relationshipStageChangeDirectionDistribution
                      .reference,
                )
                .value
            as MetricDistributionValue;
    expect(directions.labels, ['upward', 'downward']);
    expect(directions.counts, [3, 2]);
  });

  test('empty period remains four honest zero counts', () {
    final summary = PersonalRelationshipStageChangeSummary.fromCounts(
      projectId: _projectId,
      fromUtc: DateTime.utc(2030, 1, 1),
      untilUtc: DateTime.utc(2030, 1, 8),
      dataCutoffUtc: DateTime.utc(2030, 1, 8),
      authorizedAtUtc: DateTime.utc(2030, 1, 8),
      eventCount: 0,
      distinctRelationshipCount: 0,
      upwardCount: 0,
      downwardCount: 0,
    );

    expect(summary.eventCount, 0);
    expect(summary.distinctRelationshipCount, 0);
    expect(summary.upwardCount, 0);
    expect(summary.downwardCount, 0);
    expect(
      (summary
                  .metric(
                    CoreMetricCatalog.relationshipStageChangeEvents.reference,
                  )
                  .value
              as CountMetricValue)
          .value,
      0,
    );
  });

  test('rejects unsafe counts and arithmetic invariant drift', () {
    PersonalRelationshipStageChangeSummary build({
      int events = 5,
      int relationships = 4,
      int upward = 3,
      int downward = 2,
    }) => PersonalRelationshipStageChangeSummary.fromCounts(
      projectId: _projectId,
      fromUtc: DateTime.utc(2030, 1, 1),
      untilUtc: DateTime.utc(2030, 1, 8),
      dataCutoffUtc: DateTime.utc(2030, 1, 8),
      authorizedAtUtc: DateTime.utc(2030, 1, 8),
      eventCount: events,
      distinctRelationshipCount: relationships,
      upwardCount: upward,
      downwardCount: downward,
    );

    expect(() => build(events: -1), throwsArgumentError);
    expect(() => build(events: 9007199254740992), throwsArgumentError);
    expect(() => build(upward: 4), throwsArgumentError);
    expect(() => build(relationships: 6), throwsArgumentError);
    expect(
      () => build(upward: 9007199254740991, downward: 1),
      throwsArgumentError,
    );
  });

  test('rejects non-UTC period, mismatched cutoff, and future cutoff', () {
    PersonalRelationshipStageChangeSummary base({
      DateTime? fromUtc,
      DateTime? untilUtc,
      DateTime? dataCutoffUtc,
      DateTime? authorizedAtUtc,
      DateTime? retrievedAtUtc,
    }) => PersonalRelationshipStageChangeSummary.fromCounts(
      projectId: _projectId,
      fromUtc: fromUtc ?? DateTime.utc(2030, 1, 1),
      untilUtc: untilUtc ?? DateTime.utc(2030, 1, 8),
      dataCutoffUtc: dataCutoffUtc ?? DateTime.utc(2030, 1, 8),
      authorizedAtUtc: authorizedAtUtc ?? DateTime.utc(2030, 1, 8),
      retrievedAtUtc: retrievedAtUtc ?? DateTime.utc(2030, 1, 8, 1),
      eventCount: 0,
      distinctRelationshipCount: 0,
      upwardCount: 0,
      downwardCount: 0,
    );

    expect(
      () => base(fromUtc: DateTime(2030), untilUtc: DateTime.utc(2030, 1, 8)),
      throwsArgumentError,
    );
    expect(
      () => base(
        fromUtc: DateTime.utc(2030, 1, 8),
        untilUtc: DateTime.utc(2030, 1, 1),
      ),
      throwsArgumentError,
    );
    expect(
      () => base(authorizedAtUtc: DateTime.utc(2030, 1, 8, 0, 0, 1)),
      throwsArgumentError,
    );
    expect(
      () => base(
        dataCutoffUtc: DateTime.utc(2030, 1, 8, 2),
        retrievedAtUtc: DateTime.utc(2030, 1, 8, 1),
      ),
      throwsArgumentError,
    );
  });
}

const _projectId = '33333333-3333-4333-8333-333333333333';
