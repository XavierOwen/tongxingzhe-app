import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final fixtureFile = File(
    'backend/database/fixtures/shared/follow_up_consent_ratio_v1.csv',
  );

  test('enabled consent fixture fixes the ratio unit and coverage', () {
    final rows = _parseFixture(fixtureFile.readAsLinesSync());
    final scenario = rows
        .where((row) => row.scenarioKey == 'enabled_primary')
        .toList(growable: false);

    expect(scenario, isNotEmpty);
    expect(scenario.map((row) => row.expectedStatus).toSet(), {'ready'});
    expect(scenario.map((row) => row.periodStartUtc).toSet(), hasLength(1));
    expect(scenario.map((row) => row.periodEndUtc).toSet(), hasLength(1));

    for (final row in scenario) {
      expect(_eligibilityReason(row), row.expectedReason);
      expect(row.expectedInCandidate, row.expectedReason == 'included');
    }

    final summary = _summarize(scenario);
    expect(summary, scenario.first.expectedSummary);
    expect(scenario.map((row) => row.expectedSummary).toSet(), {summary});
    expect(
      summary,
      const _ConsentSummary(
        yesCount: 2,
        noCount: 1,
        unknownCount: 0,
        refusedCount: 1,
        notApplicableCount: 1,
        unansweredCount: 2,
        excludedCount: 0,
        denominator: 3,
        basisPoints: 6667,
      ),
    );

    final sameContact = scenario
        .where(
          (row) => row.contactKey == 'contact-multi' && row.expectedInCandidate,
        )
        .toList(growable: false);
    expect(sameContact.map((row) => row.targetKey).toSet(), {
      'target-multi-yes',
      'target-multi-no',
    });
    expect(
      scenario
          .where((row) => row.sourceKind == 'questionnaire_answer')
          .single
          .expectedReason,
      'wrong_statistical_unit',
    );
  });

  test('enabled consent fixture keeps an empty denominator unknown', () {
    final rows = _parseFixture(fixtureFile.readAsLinesSync());
    final scenario = rows
        .where((row) => row.scenarioKey == 'enabled_no_answers')
        .toList(growable: false);

    expect(scenario, hasLength(3));
    final summary = _summarize(scenario);
    expect(summary, scenario.first.expectedSummary);
    expect(scenario.map((row) => row.expectedSummary).toSet(), {summary});
    expect(
      scenario.first.expectedSummary,
      const _ConsentSummary(
        yesCount: 0,
        noCount: 0,
        unknownCount: 0,
        refusedCount: 1,
        notApplicableCount: 1,
        unansweredCount: 1,
        excludedCount: 0,
        denominator: 0,
        basisPoints: null,
      ),
    );
  });

  test('disabled consent metric has no value or coverage', () {
    final rows = _parseFixture(fixtureFile.readAsLinesSync());
    final scenario = rows
        .where((row) => row.scenarioKey == 'disabled_project')
        .toList(growable: false);

    expect(scenario, hasLength(1));
    expect(scenario.single.analyticsEnabled, isFalse);
    expect(_eligibilityReason(scenario.single), 'metric_not_enabled');
    expect(scenario.single.expectedInCandidate, isFalse);
    expect(scenario.single.expectedStatus, 'not_enabled');
    expect(scenario.single.expectedSummary, isNull);
  });

  test('malformed consent fixture values fail closed', () {
    final lines = fixtureFile.readAsLinesSync();
    final values = lines[1].split(',');
    values[_header.indexOf('consent_state')] = 'unanswered';

    expect(
      () => _parseFixture([lines.first, values.join(',')]),
      throwsFormatException,
    );
  });
}

const _header = [
  'scenario_key',
  'row_key',
  'analytics_enabled',
  'query_project_key',
  'row_project_key',
  'source_kind',
  'contact_key',
  'target_key',
  'revision_number',
  'current_revision_number',
  'lifecycle_status',
  'occurred_at_utc',
  'period_start_utc',
  'period_end_utc',
  'consent_state',
  'expected_in_candidate',
  'expected_reason',
  'expected_status',
  'expected_yes_count',
  'expected_no_count',
  'expected_unknown_count',
  'expected_refused_count',
  'expected_not_applicable_count',
  'expected_unanswered_count',
  'expected_excluded_count',
  'expected_denominator',
  'expected_basis_points',
];

List<_ConsentFixtureRow> _parseFixture(List<String> lines) {
  if (lines.isEmpty || lines.first.split(',').join('|') != _header.join('|')) {
    throw const FormatException('invalid consent fixture header');
  }
  return lines
      .skip(1)
      .where((line) => line.trim().isNotEmpty)
      .map((line) => _ConsentFixtureRow.parse(line.split(',')))
      .toList(growable: false);
}

String _eligibilityReason(_ConsentFixtureRow row) {
  if (!row.analyticsEnabled) return 'metric_not_enabled';
  if (row.rowProjectKey != row.queryProjectKey) return 'other_project';
  if (row.sourceKind != 'contact_target_link') {
    return switch (row.sourceKind) {
      'draft_target_link' => 'draft',
      'contact_attempt_target_link' => 'contact_attempt',
      'questionnaire_answer' => 'wrong_statistical_unit',
      _ => 'invalid_source_kind',
    };
  }
  if (row.lifecycleStatus == 'voided') return 'voided_contact';
  if (row.revisionNumber != row.currentRevisionNumber) return 'old_revision';
  if (row.occurredAtUtc.isBefore(row.periodStartUtc)) {
    return 'before_period';
  }
  if (!row.occurredAtUtc.isBefore(row.periodEndUtc)) {
    return 'right_boundary';
  }
  return 'included';
}

_ConsentSummary _summarize(List<_ConsentFixtureRow> rows) {
  var yes = 0;
  var no = 0;
  var refused = 0;
  var notApplicable = 0;
  var unanswered = 0;
  var excluded = 0;
  for (final row in rows) {
    if (_eligibilityReason(row) != 'included') {
      continue;
    }
    switch (row.consentState) {
      case 'yes':
        yes += 1;
      case 'no':
        no += 1;
      case 'unknown':
        unanswered += 1;
      case 'refused':
        refused += 1;
      case 'not_applicable':
        notApplicable += 1;
    }
  }
  final denominator = yes + no;
  return _ConsentSummary(
    yesCount: yes,
    noCount: no,
    unknownCount: 0,
    refusedCount: refused,
    notApplicableCount: notApplicable,
    unansweredCount: unanswered,
    excludedCount: excluded,
    denominator: denominator,
    basisPoints: denominator == 0
        ? null
        : ((yes * 10000) + denominator ~/ 2) ~/ denominator,
  );
}

final class _ConsentFixtureRow {
  const _ConsentFixtureRow({
    required this.scenarioKey,
    required this.analyticsEnabled,
    required this.queryProjectKey,
    required this.rowProjectKey,
    required this.sourceKind,
    required this.contactKey,
    required this.targetKey,
    required this.revisionNumber,
    required this.currentRevisionNumber,
    required this.lifecycleStatus,
    required this.occurredAtUtc,
    required this.periodStartUtc,
    required this.periodEndUtc,
    required this.consentState,
    required this.expectedInCandidate,
    required this.expectedReason,
    required this.expectedStatus,
    required this.expectedSummary,
  });

  factory _ConsentFixtureRow.parse(List<String> values) {
    if (values.length != _header.length ||
        values.any((value) => value.isEmpty)) {
      throw const FormatException('invalid consent fixture row');
    }
    final analyticsEnabled = _parseBool(values[2]);
    final revisionNumber = int.tryParse(values[8]);
    final currentRevisionNumber = int.tryParse(values[9]);
    final occurredAtUtc = DateTime.tryParse(values[11]);
    final periodStartUtc = DateTime.tryParse(values[12]);
    final periodEndUtc = DateTime.tryParse(values[13]);
    final expectedInCandidate = _parseBool(values[15]);
    final expectedStatus = values[17];
    final expectedSummary = switch (expectedStatus) {
      'ready' => _ConsentSummary.parse(values.sublist(18)),
      'not_enabled' when values.sublist(18).every((value) => value == 'NA') =>
        null,
      _ => throw const FormatException('invalid consent fixture status'),
    };
    if (analyticsEnabled == null ||
        revisionNumber == null ||
        revisionNumber < 1 ||
        currentRevisionNumber == null ||
        currentRevisionNumber < 1 ||
        occurredAtUtc == null ||
        !occurredAtUtc.isUtc ||
        periodStartUtc == null ||
        !periodStartUtc.isUtc ||
        periodEndUtc == null ||
        !periodEndUtc.isUtc ||
        !periodStartUtc.isBefore(periodEndUtc) ||
        expectedInCandidate == null ||
        !const {
          'contact_target_link',
          'draft_target_link',
          'contact_attempt_target_link',
          'questionnaire_answer',
        }.contains(values[5]) ||
        !const {'active', 'voided'}.contains(values[10]) ||
        !const {
          'yes',
          'no',
          'unknown',
          'refused',
          'not_applicable',
        }.contains(values[14])) {
      throw const FormatException('invalid consent fixture value');
    }
    return _ConsentFixtureRow(
      scenarioKey: values[0],
      analyticsEnabled: analyticsEnabled,
      queryProjectKey: values[3],
      rowProjectKey: values[4],
      sourceKind: values[5],
      contactKey: values[6],
      targetKey: values[7],
      revisionNumber: revisionNumber,
      currentRevisionNumber: currentRevisionNumber,
      lifecycleStatus: values[10],
      occurredAtUtc: occurredAtUtc,
      periodStartUtc: periodStartUtc,
      periodEndUtc: periodEndUtc,
      consentState: values[14],
      expectedInCandidate: expectedInCandidate,
      expectedReason: values[16],
      expectedStatus: expectedStatus,
      expectedSummary: expectedSummary,
    );
  }

  final String scenarioKey;
  final bool analyticsEnabled;
  final String queryProjectKey;
  final String rowProjectKey;
  final String sourceKind;
  final String contactKey;
  final String targetKey;
  final int revisionNumber;
  final int currentRevisionNumber;
  final String lifecycleStatus;
  final DateTime occurredAtUtc;
  final DateTime periodStartUtc;
  final DateTime periodEndUtc;
  final String consentState;
  final bool expectedInCandidate;
  final String expectedReason;
  final String expectedStatus;
  final _ConsentSummary? expectedSummary;
}

final class _ConsentSummary {
  const _ConsentSummary({
    required this.yesCount,
    required this.noCount,
    required this.unknownCount,
    required this.refusedCount,
    required this.notApplicableCount,
    required this.unansweredCount,
    required this.excludedCount,
    required this.denominator,
    required this.basisPoints,
  });

  factory _ConsentSummary.parse(List<String> values) {
    if (values.length != 9) {
      throw const FormatException('invalid consent fixture summary');
    }
    final counts = values.take(8).map(int.tryParse).toList(growable: false);
    final basisPoints = values[8] == 'NA' ? null : int.tryParse(values[8]);
    if (counts.any((value) => value == null || value < 0) ||
        basisPoints != null && (basisPoints < 0 || basisPoints > 10000)) {
      throw const FormatException('invalid consent fixture summary value');
    }
    return _ConsentSummary(
      yesCount: counts[0]!,
      noCount: counts[1]!,
      unknownCount: counts[2]!,
      refusedCount: counts[3]!,
      notApplicableCount: counts[4]!,
      unansweredCount: counts[5]!,
      excludedCount: counts[6]!,
      denominator: counts[7]!,
      basisPoints: basisPoints,
    );
  }

  final int yesCount;
  final int noCount;
  final int unknownCount;
  final int refusedCount;
  final int notApplicableCount;
  final int unansweredCount;
  final int excludedCount;
  final int denominator;
  final int? basisPoints;

  @override
  bool operator ==(Object other) =>
      other is _ConsentSummary &&
      other.yesCount == yesCount &&
      other.noCount == noCount &&
      other.unknownCount == unknownCount &&
      other.refusedCount == refusedCount &&
      other.notApplicableCount == notApplicableCount &&
      other.unansweredCount == unansweredCount &&
      other.excludedCount == excludedCount &&
      other.denominator == denominator &&
      other.basisPoints == basisPoints;

  @override
  int get hashCode => Object.hash(
    yesCount,
    noCount,
    unknownCount,
    refusedCount,
    notApplicableCount,
    unansweredCount,
    excludedCount,
    denominator,
    basisPoints,
  );
}

bool? _parseBool(String value) => switch (value) {
  'true' => true,
  'false' => false,
  _ => null,
};
