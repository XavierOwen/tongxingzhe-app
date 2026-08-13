import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tongxingzhe_app/features/contact_metrics/current_relationship_stage.dart';

void main() {
  final fixtureFile = File(
    'backend/database/fixtures/shared/current_relationship_stage_v1.csv',
  );

  test('current relationship snapshot fixture fixes the personal scope', () {
    final rows = _parseFixture(fixtureFile.readAsLinesSync());
    final scenario = rows
        .where((row) => row.scenarioKey == 'primary_current')
        .toList(growable: false);

    expect(scenario, isNotEmpty);
    expect(scenario.map((row) => row.expectedScenarioResult).toSet(), {
      'valid',
    });
    expect(scenario.map((row) => row.snapshotAsOfUtc).toSet(), hasLength(1));
    expect(_duplicateTargetProjects(scenario), isEmpty);

    for (final row in scenario) {
      expect(row.updatedAtUtc.isAfter(row.snapshotAsOfUtc), isFalse);
      expect(_eligibilityReason(row), row.expectedReason);
      expect(row.expectedInCurrentSnapshot, row.expectedReason == 'included');
    }

    final included = scenario
        .where((row) => row.expectedInCurrentSnapshot)
        .toList(growable: false);
    expect(included, hasLength(5));
    expect(
      [
        for (var stage = 0; stage <= 4; stage++)
          included.where((row) => row.stage == stage).length,
      ],
      [1, 1, 1, 1, 1],
    );
    expect(
      scenario
          .where((row) => !row.expectedInCurrentSnapshot)
          .map((row) => row.expectedReason)
          .toSet(),
      {
        'paused_relationship',
        'ended_relationship',
        'anonymized_target',
        'ended_assignment',
        'other_viewer',
        'other_project',
      },
    );
  });

  test('duplicate target-project projection fails closed', () {
    final rows = _parseFixture(fixtureFile.readAsLinesSync());
    final scenario = rows
        .where((row) => row.scenarioKey == 'duplicate_projection')
        .toList(growable: false);

    expect(scenario.map((row) => row.expectedScenarioResult).toSet(), {
      'duplicate_target_project',
    });
    expect(scenario.map((row) => row.snapshotAsOfUtc).toSet(), hasLength(1));
    expect(_duplicateTargetProjects(scenario), {
      (targetKey: 'target-duplicate', projectKey: 'default'),
    });
    expect(
      scenario.every(
        (row) =>
            !row.expectedInCurrentSnapshot &&
            row.expectedReason == 'duplicate_target_project',
      ),
      isTrue,
    );

    final scope = CurrentRelationshipStageScope(
      appUserId: 'primary',
      workspaceId: 'personal',
      projectId: 'default',
    );
    expect(
      () => CurrentRelationshipStageSnapshot(
        scope: scope,
        snapshotAsOfUtc: scenario.first.snapshotAsOfUtc,
        coverage: CurrentRelationshipStageCoverage.known(
          totalCount: scenario.length,
          pendingCount: 0,
        ),
        rows: [
          for (final row in scenario)
            CurrentRelationshipStageRow(
              targetId: row.targetKey,
              relationshipProjectId: row.relationshipProjectKey,
              assignedAppUserId: scope.appUserId,
              stage: row.stage,
              currentRevision: row.currentRevision,
              updatedAtUtc: row.updatedAtUtc,
            ),
        ],
      ),
      throwsArgumentError,
    );
  });

  test('malformed fixture values are rejected', () {
    final lines = fixtureFile.readAsLinesSync();
    final columns = lines[1].split(',');
    columns[_header.indexOf('stage')] = '5';

    expect(
      () => _parseFixture([lines.first, columns.join(',')]),
      throwsFormatException,
    );
  });
}

const _header = [
  'scenario_key',
  'row_key',
  'query_viewer_key',
  'query_project_key',
  'target_key',
  'relationship_project_key',
  'assigned_viewer_key',
  'stage',
  'lifecycle_status',
  'target_status',
  'assignment_status',
  'current_revision',
  'updated_at_utc',
  'snapshot_as_of_utc',
  'expected_in_current_snapshot',
  'expected_reason',
  'expected_scenario_result',
];

List<_RelationshipFixtureRow> _parseFixture(List<String> lines) {
  if (lines.isEmpty || lines.first.split(',').join('|') != _header.join('|')) {
    throw const FormatException('invalid relationship fixture header');
  }
  return lines
      .skip(1)
      .where((line) => line.trim().isNotEmpty)
      .map((line) => _RelationshipFixtureRow.parse(line.split(',')))
      .toList(growable: false);
}

Set<({String targetKey, String projectKey})> _duplicateTargetProjects(
  List<_RelationshipFixtureRow> rows,
) {
  final seen = <({String targetKey, String projectKey})>{};
  final duplicates = <({String targetKey, String projectKey})>{};
  for (final row in rows) {
    final key = (
      targetKey: row.targetKey,
      projectKey: row.relationshipProjectKey,
    );
    if (!seen.add(key)) duplicates.add(key);
  }
  return duplicates;
}

String _eligibilityReason(_RelationshipFixtureRow row) {
  if (row.relationshipProjectKey != row.queryProjectKey) {
    return 'other_project';
  }
  if (row.assignedViewerKey != row.queryViewerKey) return 'other_viewer';
  if (row.targetStatus == 'anonymized') return 'anonymized_target';
  if (row.assignmentStatus == 'ended') return 'ended_assignment';
  if (row.lifecycleStatus == 'paused') return 'paused_relationship';
  if (row.lifecycleStatus == 'ended') return 'ended_relationship';
  return 'included';
}

final class _RelationshipFixtureRow {
  const _RelationshipFixtureRow({
    required this.scenarioKey,
    required this.queryViewerKey,
    required this.queryProjectKey,
    required this.targetKey,
    required this.relationshipProjectKey,
    required this.assignedViewerKey,
    required this.stage,
    required this.lifecycleStatus,
    required this.targetStatus,
    required this.assignmentStatus,
    required this.currentRevision,
    required this.updatedAtUtc,
    required this.snapshotAsOfUtc,
    required this.expectedInCurrentSnapshot,
    required this.expectedReason,
    required this.expectedScenarioResult,
  });

  factory _RelationshipFixtureRow.parse(List<String> values) {
    if (values.length != _header.length ||
        values.any((value) => value.isEmpty)) {
      throw const FormatException('invalid relationship fixture row');
    }
    final stage = int.tryParse(values[7]);
    final revision = int.tryParse(values[11]);
    final updatedAtUtc = DateTime.tryParse(values[12]);
    final snapshotAsOfUtc = DateTime.tryParse(values[13]);
    final included = switch (values[14]) {
      'true' => true,
      'false' => false,
      _ => null,
    };
    if (stage == null ||
        stage < 0 ||
        stage > 4 ||
        revision == null ||
        revision < 1 ||
        updatedAtUtc == null ||
        !updatedAtUtc.isUtc ||
        snapshotAsOfUtc == null ||
        !snapshotAsOfUtc.isUtc ||
        included == null ||
        !const {'active', 'paused', 'ended'}.contains(values[8]) ||
        !const {'active', 'anonymized'}.contains(values[9]) ||
        !const {'active', 'ended'}.contains(values[10]) ||
        !const {'valid', 'duplicate_target_project'}.contains(values[16])) {
      throw const FormatException('invalid relationship fixture value');
    }
    return _RelationshipFixtureRow(
      scenarioKey: values[0],
      queryViewerKey: values[2],
      queryProjectKey: values[3],
      targetKey: values[4],
      relationshipProjectKey: values[5],
      assignedViewerKey: values[6],
      stage: stage,
      lifecycleStatus: values[8],
      targetStatus: values[9],
      assignmentStatus: values[10],
      currentRevision: revision,
      updatedAtUtc: updatedAtUtc,
      snapshotAsOfUtc: snapshotAsOfUtc,
      expectedInCurrentSnapshot: included,
      expectedReason: values[15],
      expectedScenarioResult: values[16],
    );
  }

  final String scenarioKey;
  final String queryViewerKey;
  final String queryProjectKey;
  final String targetKey;
  final String relationshipProjectKey;
  final String assignedViewerKey;
  final int stage;
  final String lifecycleStatus;
  final String targetStatus;
  final String assignmentStatus;
  final int currentRevision;
  final DateTime updatedAtUtc;
  final DateTime snapshotAsOfUtc;
  final bool expectedInCurrentSnapshot;
  final String expectedReason;
  final String expectedScenarioResult;
}
