import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tongxingzhe_app/features/contact_metrics/management_interest_distribution_policy.dart';
import 'package:tongxingzhe_app/features/contact_metrics/management_privacy_policy.dart';
import 'package:tongxingzhe_app/features/contact_metrics/metric_contract.dart';

void main() {
  test('returns a stable previous/current by 0..4 complete grid', () {
    final report = ManagementInterestDistributionPrivacyPolicyV1.protect(
      request: _request,
      contributions: [
        ..._safePeriod(ManagementReportPeriodKey.current),
        ..._safePeriod(ManagementReportPeriodKey.previous),
      ].reversed,
    );

    expect(report.reportId, 'contact_sessions_by_interest_level_two_periods');
    expect(report.reportVersion, 1);
    expect(report.cells, hasLength(10));
    expect(
      report.cells.map((cell) => (cell.periodKey, cell.interestLevel)).toList(),
      [
        for (final periodKey in ManagementReportPeriodKey.values)
          for (var interestLevel = 0; interestLevel <= 4; interestLevel++)
            (periodKey, interestLevel),
      ],
    );
    expect(
      report.cells.every(
        (cell) =>
            cell.privacyStatus == MetricPrivacyStatus.displayed &&
            cell.displayedCount == 10,
      ),
      isTrue,
    );
    expect(
      report.periodMetrics.values.every(
        (metric) =>
            metric.definition == CoreMetricCatalog.interestDistribution &&
            metric.sourceTier == MetricSourceTier.backendOperational &&
            metric.privacyStatus == MetricPrivacyStatus.displayed &&
            metric.syncCoverage == null,
      ),
      isTrue,
    );
    expect(
      (report.metric(ManagementReportPeriodKey.current).value
              as MetricDistributionValue)
          .counts,
      [10, 10, 10, 10, 10],
    );
  });

  test(
    'uses the same management request period and metadata for each period',
    () {
      final report = ManagementInterestDistributionPrivacyPolicyV1.protect(
        request: _request,
        contributions: [
          ..._safePeriod(ManagementReportPeriodKey.previous),
          ..._safePeriod(ManagementReportPeriodKey.current),
        ],
      );

      expect(
        report.metric(ManagementReportPeriodKey.previous).period,
        _request.previousPeriod,
      );
      expect(
        report.metric(ManagementReportPeriodKey.current).period,
        _request.currentPeriod,
      );
      expect(
        report.periodMetrics.values.every(
          (metric) =>
              metric.timeZone == _request.timeZone &&
              metric.dataCutoffUtc == _request.dataCutoffUtc,
        ),
        isTrue,
      );
    },
  );

  test('empty levels are suppressed rather than represented as exact zero', () {
    final contributions = _safePeriod(
      ManagementReportPeriodKey.current,
    ).where((item) => item.interestLevel != 2).toList();
    final report = ManagementInterestDistributionPrivacyPolicyV1.protect(
      request: _request,
      contributions: contributions,
    );

    for (final cell in report.cells.where(
      (cell) => cell.periodKey == ManagementReportPeriodKey.current,
    )) {
      expect(cell.privacyStatus, MetricPrivacyStatus.suppressed);
      expect(cell.displayedCount, isNull);
    }
    expect(
      report.metric(ManagementReportPeriodKey.current).value,
      isA<SuppressedMetricValue>(),
    );
    expect(
      report.metric(ManagementReportPeriodKey.previous).privacyStatus,
      MetricPrivacyStatus.suppressed,
    );
  });

  test('accepts exactly 10 units, three contributors, and 50 percent', () {
    final report = ManagementInterestDistributionPrivacyPolicyV1.protect(
      request: _request,
      contributions: [
        ..._periodWithCounts(ManagementReportPeriodKey.current, const [
          5,
          3,
          2,
        ]),
      ],
    );

    expect(
      report.cells
          .where((cell) => cell.periodKey == ManagementReportPeriodKey.current)
          .every(
            (cell) =>
                cell.privacyStatus == MetricPrivacyStatus.displayed &&
                cell.displayedCount == 10,
          ),
      isTrue,
    );
  });

  test('nine units suppress the complete period', () {
    final report = _reportForCurrent(const [3, 3, 3]);

    _expectPeriodSuppressed(report, ManagementReportPeriodKey.current);
  });

  test('two contributors suppress the complete period', () {
    final report = _reportForCurrent(const [5, 5]);

    _expectPeriodSuppressed(report, ManagementReportPeriodKey.current);
  });

  test(
    'six of ten units from one contributor suppress the complete period',
    () {
      final report = _reportForCurrent(const [6, 2, 2]);

      _expectPeriodSuppressed(report, ManagementReportPeriodKey.current);
    },
  );

  test('one unsafe level closes all five levels for that period', () {
    final contributions =
        <ManagementInterestMetricContribution>[
            ..._safePeriod(ManagementReportPeriodKey.previous),
            ..._safePeriod(ManagementReportPeriodKey.current),
          ]
          ..removeWhere(
            (item) =>
                item.periodKey == ManagementReportPeriodKey.current &&
                item.interestLevel == 3,
          )
          ..addAll(
            _periodWithCounts(
              ManagementReportPeriodKey.current,
              const [3, 3, 3],
              levels: const [3],
            ),
          );
    final report = ManagementInterestDistributionPrivacyPolicyV1.protect(
      request: _request,
      contributions: contributions,
    );

    _expectPeriodSuppressed(report, ManagementReportPeriodKey.current);
    expect(
      report.cells
          .where((cell) => cell.periodKey == ManagementReportPeriodKey.previous)
          .every((cell) => cell.privacyStatus == MetricPrivacyStatus.displayed),
      isTrue,
    );
  });

  test('period privacy decisions are independent', () {
    final report = ManagementInterestDistributionPrivacyPolicyV1.protect(
      request: _request,
      contributions: [
        ..._periodWithCounts(ManagementReportPeriodKey.previous, const [
          3,
          3,
          3,
        ]),
        ..._safePeriod(ManagementReportPeriodKey.current),
      ],
    );

    _expectPeriodSuppressed(report, ManagementReportPeriodKey.previous);
    expect(
      report.cells
          .where((cell) => cell.periodKey == ManagementReportPeriodKey.current)
          .every(
            (cell) =>
                cell.privacyStatus == MetricPrivacyStatus.displayed &&
                cell.displayedCount == 10,
          ),
      isTrue,
    );
  });

  test('duplicate period-level-contributor contributions fail closed', () {
    final contribution = ManagementInterestMetricContribution(
      periodKey: ManagementReportPeriodKey.current,
      interestLevel: 1,
      contributorKey: 'promoter-a',
      unitCount: 4,
    );

    expect(
      () => ManagementInterestDistributionPrivacyPolicyV1.protect(
        request: _request,
        contributions: [contribution, contribution],
      ),
      throwsArgumentError,
    );
  });

  test('rejects invalid levels, contributor keys, and unit counts', () {
    ManagementInterestMetricContribution contribution({
      int level = 0,
      String contributor = 'promoter-a',
      int units = 1,
    }) => ManagementInterestMetricContribution(
      periodKey: ManagementReportPeriodKey.current,
      interestLevel: level,
      contributorKey: contributor,
      unitCount: units,
    );

    expect(() => contribution(level: -1), throwsArgumentError);
    expect(() => contribution(level: 5), throwsArgumentError);
    expect(() => contribution(contributor: '   '), throwsArgumentError);
    expect(
      () => contribution(contributor: List.filled(121, 'a').join()),
      throwsArgumentError,
    );
    expect(() => contribution(units: 0), throwsArgumentError);
    expect(() => contribution(units: -1), throwsArgumentError);
    expect(() => contribution(units: 2147483648), throwsArgumentError);
    expect(
      () => ManagementInterestMetricContribution.fromStorage(
        period: 'future',
        interestLevel: 1,
        contributorKey: 'promoter-a',
        unitCount: 1,
      ),
      throwsArgumentError,
    );
  });

  test('normalizes contributor keys before uniqueness checks', () {
    final contributions = [
      ..._safePeriod(ManagementReportPeriodKey.previous),
      ..._safePeriod(ManagementReportPeriodKey.current),
    ];
    final first = contributions.first;
    final normalized = ManagementInterestMetricContribution(
      periodKey: first.periodKey,
      interestLevel: first.interestLevel,
      contributorKey: ' ${first.contributorKey} ',
      unitCount: first.unitCount,
    );

    expect(
      () => ManagementInterestDistributionPrivacyPolicyV1.protect(
        request: _request,
        contributions: [first, normalized],
      ),
      throwsArgumentError,
    );
  });

  test('keeps a safe aggregate exact when it exceeds one database integer', () {
    final report = ManagementInterestDistributionPrivacyPolicyV1.protect(
      request: _request,
      contributions: [
        ..._safePeriod(ManagementReportPeriodKey.previous),
        ..._periodWithCounts(ManagementReportPeriodKey.current, const [
          2147483647,
          2147483647,
          2147483647,
        ]),
      ],
    );

    expect(
      report.cells
          .where((cell) => cell.periodKey == ManagementReportPeriodKey.current)
          .every(
            (cell) =>
                cell.privacyStatus == MetricPrivacyStatus.displayed &&
                cell.displayedCount == 6442450941,
          ),
      isTrue,
    );
  });

  test('rejects displayed counts outside the cross-platform safe range', () {
    expect(
      () => ProtectedManagementInterestCell(
        periodKey: ManagementReportPeriodKey.current,
        interestLevel: 0,
        privacyStatus: MetricPrivacyStatus.displayed,
        count: 9,
      ),
      throwsArgumentError,
    );
    expect(
      () => ProtectedManagementInterestCell(
        periodKey: ManagementReportPeriodKey.current,
        interestLevel: 0,
        privacyStatus: MetricPrivacyStatus.displayed,
        count: 9007199254740992,
      ),
      throwsArgumentError,
    );
  });

  test('agrees with the shared fixture for safe and closed periods', () async {
    final fixture = await _loadFixture();
    expect(
      fixture.keys,
      containsAll(<String>[
        'safe',
        'small_sample',
        'two_contributors',
        'dominant',
        'cross_report_total',
      ]),
    );

    final safe = _protectFixture(fixture, 'safe');
    expect(_signature(safe), [
      for (final periodKey in ManagementReportPeriodKey.values)
        for (var interestLevel = 0; interestLevel <= 4; interestLevel++)
          (periodKey.name, interestLevel, 'displayed', 10),
    ]);

    final crossReportCurrent = fixture['cross_report_total']!
        .where((item) => item.periodKey == ManagementReportPeriodKey.current)
        .toList();
    expect(
      crossReportCurrent.fold<int>(0, (sum, item) => sum + item.unitCount),
      70,
    );
    expect(
      crossReportCurrent
          .where((item) => item.interestLevel == 0)
          .fold<int>(0, (sum, item) => sum + item.unitCount),
      9,
    );
    expect(
      crossReportCurrent
          .where((item) => item.interestLevel > 0)
          .fold<int>(0, (sum, item) => sum + item.unitCount),
      61,
    );

    for (final scenario in const [
      'small_sample',
      'two_contributors',
      'dominant',
      'cross_report_total',
    ]) {
      final report = _protectFixture(fixture, scenario);
      expect(
        report.cells
            .where(
              (cell) => cell.periodKey == ManagementReportPeriodKey.previous,
            )
            .every(
              (cell) =>
                  cell.privacyStatus == MetricPrivacyStatus.displayed &&
                  cell.count == 10,
            ),
        isTrue,
      );
      expect(
        report.cells
            .where(
              (cell) => cell.periodKey == ManagementReportPeriodKey.current,
            )
            .every(
              (cell) =>
                  cell.privacyStatus == MetricPrivacyStatus.suppressed &&
                  cell.count == null,
            ),
        isTrue,
      );
    }
  });
}

final _request = ManagementContactSessionReportRequestV1(
  previousPeriod: MetricPeriod(
    fromUtc: DateTime.utc(2030, 1, 1),
    untilUtc: DateTime.utc(2030, 1, 8),
  ),
  currentPeriod: MetricPeriod(
    fromUtc: DateTime.utc(2030, 1, 8),
    untilUtc: DateTime.utc(2030, 1, 15),
  ),
  timeZone: 'Asia/Shanghai',
  dataCutoffUtc: DateTime.utc(2030, 1, 15),
);

List<ManagementInterestMetricContribution> _safePeriod(
  ManagementReportPeriodKey periodKey,
) => _periodWithCounts(periodKey, const [4, 3, 3]);

List<ManagementInterestMetricContribution> _periodWithCounts(
  ManagementReportPeriodKey periodKey,
  List<int> counts, {
  List<int> levels = const [0, 1, 2, 3, 4],
}) => [
  for (final level in levels)
    for (
      var contributorIndex = 0;
      contributorIndex < counts.length;
      contributorIndex++
    )
      ManagementInterestMetricContribution(
        periodKey: periodKey,
        interestLevel: level,
        contributorKey: 'promoter-$contributorIndex',
        unitCount: counts[contributorIndex],
      ),
];

ManagementInterestDistributionReportV1 _reportForCurrent(List<int> counts) =>
    ManagementInterestDistributionPrivacyPolicyV1.protect(
      request: _request,
      contributions: [
        ..._safePeriod(ManagementReportPeriodKey.previous),
        ..._periodWithCounts(ManagementReportPeriodKey.current, counts),
      ],
    );

void _expectPeriodSuppressed(
  ManagementInterestDistributionReportV1 report,
  ManagementReportPeriodKey periodKey,
) {
  final cells = report.cells.where((cell) => cell.periodKey == periodKey);
  expect(cells, hasLength(5));
  expect(
    cells.every(
      (cell) =>
          cell.privacyStatus == MetricPrivacyStatus.suppressed &&
          cell.displayedCount == null,
    ),
    isTrue,
  );
}

ManagementInterestDistributionReportV1 _protectFixture(
  Map<String, List<ManagementInterestMetricContribution>> fixture,
  String scenario,
) => ManagementInterestDistributionPrivacyPolicyV1.protect(
  request: _request,
  contributions: fixture[scenario]!,
);

List<(String, int, String, int?)> _signature(
  ManagementInterestDistributionReportV1 report,
) => [
  for (final cell in report.cells)
    (
      cell.periodKey.name,
      cell.interestLevel,
      cell.privacyStatus.name,
      cell.count,
    ),
];

Future<Map<String, List<ManagementInterestMetricContribution>>>
_loadFixture() async {
  final lines = await File(
    'backend/database/fixtures/shared/management_interest_distribution_v1.csv',
  ).readAsLines();
  const expectedHeader =
      'scenario,period_key,interest_level,contributor_key,unit_count';
  if (lines.isEmpty || lines.first != expectedHeader || lines.length < 2) {
    throw const FormatException(
      'invalid management interest distribution fixture header',
    );
  }

  final result = <String, List<ManagementInterestMetricContribution>>{};
  final seenRows = <(String, String, int, String)>{};
  for (final line in lines.skip(1)) {
    if (line.trim().isEmpty) {
      throw const FormatException(
        'blank management interest distribution fixture row',
      );
    }
    final columns = line.split(',');
    if (columns.length != 5 ||
        columns.any((column) => column.isEmpty || column != column.trim())) {
      throw FormatException(
        'invalid management interest distribution fixture row',
        line,
      );
    }
    final scenario = columns[0];
    final period = columns[1];
    final interestLevel = int.tryParse(columns[2]);
    final contributorKey = columns[3];
    final unitCount = int.tryParse(columns[4]);
    if (scenario.isEmpty ||
        !RegExp(r'^[0-4]$').hasMatch(columns[2]) ||
        !RegExp(r'^[1-9][0-9]*$').hasMatch(columns[4]) ||
        contributorKey.length > 120 ||
        interestLevel == null ||
        unitCount == null ||
        !seenRows.add((scenario, period, interestLevel, contributorKey))) {
      throw FormatException(
        'invalid management interest distribution fixture values',
        line,
      );
    }
    result
        .putIfAbsent(scenario, () => [])
        .add(
          ManagementInterestMetricContribution.fromStorage(
            period: period,
            interestLevel: interestLevel,
            contributorKey: contributorKey,
            unitCount: unitCount,
          ),
        );
  }
  return result;
}
