import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tongxingzhe_app/features/contact_metrics/metric_contract.dart';

void main() {
  final fixtureFile = File(
    'backend/database/fixtures/shared/relationship_stage_changes_v1.csv',
  );

  test('shared fixture fixes actor-scoped stage change event semantics', () {
    final rows = _parseFixture(fixtureFile.readAsLinesSync());
    final scenario = rows
        .where((row) => row.scenarioKey == 'primary_events')
        .toList(growable: false);

    expect(scenario, isNotEmpty);
    expect(scenario.map((row) => row.expectedScenarioResult).toSet(), {
      'valid',
    });
    for (final row in scenario) {
      expect(_eligibilityReason(row), row.expectedReason, reason: row.rowKey);
      expect(
        row.expectedInPersonalMetric,
        row.expectedReason == 'included',
        reason: row.rowKey,
      );
    }

    final summary = _summarize(scenario);
    expect(summary.eventCount, 5);
    expect(summary.distinctRelationshipCount, 4);
    expect(summary.upwardCount, 3);
    expect(summary.downwardCount, 2);
    expect(summary, scenario.first.expectedSummary);
    expect(
      scenario.any(
        (row) =>
            row.expectedInPersonalMetric &&
            row.currentAssignmentStatus == 'ended',
      ),
      isTrue,
      reason: 'current assignment must not rewrite the actor historical fact',
    );
    expect(
      scenario.any(
        (row) =>
            row.expectedInPersonalMetric &&
            row.changedAtUtc == row.periodFromUtc,
      ),
      isTrue,
      reason: 'the lower bound is inclusive',
    );

    final period = MetricPeriod(
      fromUtc: scenario.first.periodFromUtc,
      untilUtc: scenario.first.periodUntilUtc,
    );
    final results = [
      MetricResult(
        definition: CoreMetricCatalog.relationshipStageChangeEvents,
        value: CountMetricValue(summary.eventCount),
        period: period,
        timeZone: 'UTC',
        dataCutoffUtc: period.untilUtc,
        sourceTier: MetricSourceTier.backendOperational,
        privacyStatus: MetricPrivacyStatus.personalFact,
      ),
      MetricResult(
        definition: CoreMetricCatalog.relationshipsWithStageChange,
        value: CountMetricValue(summary.distinctRelationshipCount),
        period: period,
        timeZone: 'UTC',
        dataCutoffUtc: period.untilUtc,
        sourceTier: MetricSourceTier.backendOperational,
        privacyStatus: MetricPrivacyStatus.personalFact,
      ),
      MetricResult(
        definition:
            CoreMetricCatalog.relationshipStageChangeDirectionDistribution,
        value: MetricDistributionValue(
          labels: const ['upward', 'downward'],
          counts: [summary.upwardCount, summary.downwardCount],
        ),
        period: period,
        timeZone: 'UTC',
        dataCutoffUtc: period.untilUtc,
        sourceTier: MetricSourceTier.backendOperational,
        privacyStatus: MetricPrivacyStatus.personalFact,
      ),
    ];
    expect(results, hasLength(3));
  });

  test('duplicate relationship revision fails closed', () {
    final rows = _parseFixture(fixtureFile.readAsLinesSync());
    final scenario = rows
        .where((row) => row.scenarioKey == 'duplicate_revision')
        .toList(growable: false);

    expect(scenario, hasLength(3));
    expect(scenario.map((row) => row.expectedScenarioResult).toSet(), {
      'duplicate_revision_fail_closed',
    });
    expect(scenario.every((row) => !row.expectedInPersonalMetric), isTrue);
    expect(scenario.map((row) => row.expectedReason).toSet(), {
      'duplicate_revision',
    });
    expect(scenario.map((row) => row.expectedSummary).toSet(), {
      const _StageChangeSummary.zero(),
    });
    expect(
      scenario.any(
        (row) =>
            row.rowKey == 'otherwise-valid-row' &&
            row.oldStage == 2 &&
            row.newStage == 3 &&
            row.changedFields.contains('stage'),
      ),
      isTrue,
      reason: 'one duplicate revision rejects the otherwise valid whole input',
    );
    expect(() => _summarize(scenario), throwsFormatException);
  });

  test('malformed fixture values fail closed', () {
    final lines = fixtureFile.readAsLinesSync();
    final columns = lines[1].split(',');
    columns[_header.indexOf('new_stage')] = '5';

    expect(
      () => _parseFixture([lines.first, columns.join(',')]),
      throwsFormatException,
    );
    expect(
      () => _parseFixture(['${lines.first},unexpected', '${lines[1]},value']),
      throwsFormatException,
    );

    List<String> changedRow(String column, String value) {
      final changed = lines[1].split(',');
      changed[_header.indexOf(column)] = value;
      return [lines.first, changed.join(',')];
    }

    expect(
      () => _parseFixture(changedRow('reason_code', 'invented_reason')),
      throwsFormatException,
    );
    expect(
      () => _parseFixture(changedRow('reason_code', 'project_entry')),
      throwsFormatException,
    );
    expect(
      () => _parseFixture(changedRow('old_stage', '')),
      throwsFormatException,
    );
  });
}

const _header = [
  'scenario_key',
  'row_key',
  'query_actor_key',
  'query_workspace_key',
  'query_project_key',
  'target_key',
  'relationship_workspace_key',
  'relationship_project_key',
  'revision_number',
  'old_stage',
  'new_stage',
  'changed_fields',
  'reason_code',
  'changed_by_actor_key',
  'changed_at_utc',
  'current_assignment_status',
  'period_from_utc',
  'period_until_utc',
  'expected_in_personal_metric',
  'expected_reason',
  'expected_scenario_result',
  'expected_event_count',
  'expected_distinct_relationship_count',
  'expected_upward_count',
  'expected_downward_count',
];

List<_StageChangeFixtureRow> _parseFixture(List<String> lines) {
  if (lines.isEmpty || lines.first.split(',').join('|') != _header.join('|')) {
    throw const FormatException('invalid stage change fixture header');
  }
  final rows = lines
      .skip(1)
      .where((line) => line.trim().isNotEmpty)
      .map((line) => _StageChangeFixtureRow.parse(line.split(',')))
      .toList(growable: false);
  if (rows.isEmpty ||
      rows.map((row) => row.rowKey).toSet().length != rows.length) {
    throw const FormatException('invalid stage change fixture row keys');
  }
  return rows;
}

_StageChangeSummary _summarize(List<_StageChangeFixtureRow> rows) {
  if (rows.isEmpty) {
    throw const FormatException('empty stage change scenario');
  }
  final first = rows.first;
  for (final row in rows.skip(1)) {
    if (row.scenarioKey != first.scenarioKey ||
        row.queryActorKey != first.queryActorKey ||
        row.queryWorkspaceKey != first.queryWorkspaceKey ||
        row.queryProjectKey != first.queryProjectKey ||
        row.periodFromUtc != first.periodFromUtc ||
        row.periodUntilUtc != first.periodUntilUtc ||
        row.expectedSummary != first.expectedSummary) {
      throw const FormatException('inconsistent stage change scenario');
    }
  }

  final revisionKeys = <String>{};
  for (final row in rows) {
    final key = [
      row.targetKey,
      row.relationshipWorkspaceKey,
      row.relationshipProjectKey,
      row.revisionNumber,
    ].join('|');
    if (!revisionKeys.add(key)) {
      throw const FormatException('duplicate relationship stage revision');
    }
  }

  final included = rows
      .where((row) => _eligibilityReason(row) == 'included')
      .toList(growable: false);
  final relationships = {
    for (final row in included)
      [
        row.targetKey,
        row.relationshipWorkspaceKey,
        row.relationshipProjectKey,
      ].join('|'),
  };
  return _StageChangeSummary(
    eventCount: included.length,
    distinctRelationshipCount: relationships.length,
    upwardCount: included.where((row) => row.newStage > row.oldStage!).length,
    downwardCount: included.where((row) => row.newStage < row.oldStage!).length,
  );
}

String _eligibilityReason(_StageChangeFixtureRow row) {
  if (row.relationshipWorkspaceKey != row.queryWorkspaceKey) {
    return 'other_workspace';
  }
  if (row.relationshipProjectKey != row.queryProjectKey) {
    return 'other_project';
  }
  if (row.changedByActorKey != row.queryActorKey) return 'other_actor';
  if (row.changedAtUtc.isBefore(row.periodFromUtc)) return 'before_period';
  if (!row.changedAtUtc.isBefore(row.periodUntilUtc)) return 'period_until';
  if (row.oldStage == null || row.reasonCode == 'project_entry') {
    return 'project_entry';
  }
  if (!row.changedFields.contains('stage')) return 'lifecycle_only';
  if (row.oldStage == row.newStage) return 'same_stage';
  return 'included';
}

final class _StageChangeFixtureRow {
  const _StageChangeFixtureRow({
    required this.scenarioKey,
    required this.rowKey,
    required this.queryActorKey,
    required this.queryWorkspaceKey,
    required this.queryProjectKey,
    required this.targetKey,
    required this.relationshipWorkspaceKey,
    required this.relationshipProjectKey,
    required this.revisionNumber,
    required this.oldStage,
    required this.newStage,
    required this.changedFields,
    required this.reasonCode,
    required this.changedByActorKey,
    required this.changedAtUtc,
    required this.currentAssignmentStatus,
    required this.periodFromUtc,
    required this.periodUntilUtc,
    required this.expectedInPersonalMetric,
    required this.expectedReason,
    required this.expectedScenarioResult,
    required this.expectedSummary,
  });

  factory _StageChangeFixtureRow.parse(List<String> columns) {
    if (columns.length != _header.length) {
      throw const FormatException('invalid stage change fixture columns');
    }
    final values = {
      for (var index = 0; index < _header.length; index += 1)
        _header[index]: columns[index],
    };
    String requiredValue(String key) {
      final value = values[key]!;
      if (value.trim().isEmpty) {
        throw FormatException('empty stage change fixture value: $key');
      }
      return value;
    }

    final revisionNumber = int.tryParse(requiredValue('revision_number'));
    final oldStageText = values['old_stage']!;
    final oldStage = oldStageText.isEmpty ? null : int.tryParse(oldStageText);
    final newStage = int.tryParse(requiredValue('new_stage'));
    final changedFields = requiredValue('changed_fields').split('|').toSet();
    final changedAtUtc = DateTime.tryParse(requiredValue('changed_at_utc'));
    final periodFromUtc = DateTime.tryParse(requiredValue('period_from_utc'));
    final periodUntilUtc = DateTime.tryParse(requiredValue('period_until_utc'));
    final assignmentStatus = requiredValue('current_assignment_status');
    final reasonCode = requiredValue('reason_code');
    final expectedScenarioResult = requiredValue('expected_scenario_result');
    if (revisionNumber == null ||
        revisionNumber < 1 ||
        oldStage != null && (oldStage < 0 || oldStage > 4) ||
        newStage == null ||
        newStage < 0 ||
        newStage > 4 ||
        changedFields.isEmpty ||
        !const {
          'stage',
          'lifecycle_status',
          'follow_up_note',
          'conflict_resolution',
        }.containsAll(changedFields) ||
        changedAtUtc == null ||
        !changedAtUtc.isUtc ||
        periodFromUtc == null ||
        !periodFromUtc.isUtc ||
        periodUntilUtc == null ||
        !periodUntilUtc.isUtc ||
        !periodFromUtc.isBefore(periodUntilUtc) ||
        !const {'active', 'ended', 'none'}.contains(assignmentStatus) ||
        !const {
          'project_entry',
          'progress_update',
          'contact_lost',
          'timing_changed',
          'requirements_changed',
          'target_request',
          'project_change',
          'correction',
          'other',
        }.contains(reasonCode) ||
        oldStage == null &&
            (revisionNumber != 1 || reasonCode != 'project_entry') ||
        oldStage != null && reasonCode == 'project_entry' ||
        !const {
          'valid',
          'duplicate_revision_fail_closed',
        }.contains(expectedScenarioResult)) {
      throw const FormatException('invalid stage change fixture value');
    }
    return _StageChangeFixtureRow(
      scenarioKey: requiredValue('scenario_key'),
      rowKey: requiredValue('row_key'),
      queryActorKey: requiredValue('query_actor_key'),
      queryWorkspaceKey: requiredValue('query_workspace_key'),
      queryProjectKey: requiredValue('query_project_key'),
      targetKey: requiredValue('target_key'),
      relationshipWorkspaceKey: requiredValue('relationship_workspace_key'),
      relationshipProjectKey: requiredValue('relationship_project_key'),
      revisionNumber: revisionNumber,
      oldStage: oldStage,
      newStage: newStage,
      changedFields: changedFields,
      reasonCode: reasonCode,
      changedByActorKey: requiredValue('changed_by_actor_key'),
      changedAtUtc: changedAtUtc,
      currentAssignmentStatus: assignmentStatus,
      periodFromUtc: periodFromUtc,
      periodUntilUtc: periodUntilUtc,
      expectedInPersonalMetric: _parseBoolean(
        requiredValue('expected_in_personal_metric'),
      ),
      expectedReason: requiredValue('expected_reason'),
      expectedScenarioResult: expectedScenarioResult,
      expectedSummary: _StageChangeSummary(
        eventCount: _parseNonNegativeInt(requiredValue('expected_event_count')),
        distinctRelationshipCount: _parseNonNegativeInt(
          requiredValue('expected_distinct_relationship_count'),
        ),
        upwardCount: _parseNonNegativeInt(
          requiredValue('expected_upward_count'),
        ),
        downwardCount: _parseNonNegativeInt(
          requiredValue('expected_downward_count'),
        ),
      ),
    );
  }

  final String scenarioKey;
  final String rowKey;
  final String queryActorKey;
  final String queryWorkspaceKey;
  final String queryProjectKey;
  final String targetKey;
  final String relationshipWorkspaceKey;
  final String relationshipProjectKey;
  final int revisionNumber;
  final int? oldStage;
  final int newStage;
  final Set<String> changedFields;
  final String reasonCode;
  final String changedByActorKey;
  final DateTime changedAtUtc;
  final String currentAssignmentStatus;
  final DateTime periodFromUtc;
  final DateTime periodUntilUtc;
  final bool expectedInPersonalMetric;
  final String expectedReason;
  final String expectedScenarioResult;
  final _StageChangeSummary expectedSummary;
}

final class _StageChangeSummary {
  const _StageChangeSummary({
    required this.eventCount,
    required this.distinctRelationshipCount,
    required this.upwardCount,
    required this.downwardCount,
  });

  const _StageChangeSummary.zero()
    : eventCount = 0,
      distinctRelationshipCount = 0,
      upwardCount = 0,
      downwardCount = 0;

  final int eventCount;
  final int distinctRelationshipCount;
  final int upwardCount;
  final int downwardCount;

  @override
  bool operator ==(Object other) =>
      other is _StageChangeSummary &&
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

bool _parseBoolean(String value) => switch (value) {
  'true' => true,
  'false' => false,
  _ => throw const FormatException('invalid stage change fixture boolean'),
};

int _parseNonNegativeInt(String value) {
  final parsed = int.tryParse(value);
  if (parsed == null || parsed < 0) {
    throw const FormatException('invalid stage change fixture count');
  }
  return parsed;
}
