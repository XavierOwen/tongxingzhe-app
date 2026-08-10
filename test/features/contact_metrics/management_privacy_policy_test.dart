import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tongxingzhe_app/features/contact_journal/contact_models.dart';
import 'package:tongxingzhe_app/features/contact_metrics/management_privacy_policy.dart';
import 'package:tongxingzhe_app/features/contact_metrics/metric_contract.dart';

void main() {
  test('安全边界形成稳定的双期间完整网格', () {
    final contributions = _safeContributions();

    final report = ManagementContactSessionPrivacyPolicyV1.protect(
      request: _request,
      contributions: contributions.reversed,
    );

    expect(report.cells, hasLength(16));
    expect(
      report.cells.map((cell) => (cell.periodKey, cell.categoryKey)).toList(),
      [
        for (final periodKey in ManagementReportPeriodKey.values) ...[
          (periodKey, ManagementContactSessionReportV1.totalCategoryKey),
          for (final channel in ContactChannel.values)
            (periodKey, channel.storageValue),
        ],
      ],
    );
    expect(
      report.cells.every(
        (cell) =>
            cell.result.privacyStatus == MetricPrivacyStatus.displayed &&
            cell.result.sourceTier == MetricSourceTier.backendOperational &&
            cell.result.syncCoverage == null,
      ),
      isTrue,
    );
    expect(
      report
          .cell(
            ManagementReportPeriodKey.previous,
            ManagementContactSessionReportV1.totalCategoryKey,
          )
          .result
          .value,
      CountMetricValue(70),
    );
    expect(
      report
          .cell(
            ManagementReportPeriodKey.current,
            ContactChannel.faceToFace.storageValue,
          )
          .result
          .value,
      CountMetricValue(10),
    );
  });

  test('不足样本隐藏渠道及同期总计但不污染另一期间', () {
    final contributions =
        _safeContributions()
            .where(
              (item) =>
                  item.periodKey != ManagementReportPeriodKey.previous ||
                  item.channel != ContactChannel.faceToFace,
            )
            .toList()
          ..addAll(
            _contributions(
              ManagementReportPeriodKey.previous,
              ContactChannel.faceToFace,
              const [3, 3, 3],
            ),
          );

    final report = ManagementContactSessionPrivacyPolicyV1.protect(
      request: _request,
      contributions: contributions,
    );

    _expectSuppressed(
      report.cell(
        ManagementReportPeriodKey.previous,
        ContactChannel.faceToFace.storageValue,
      ),
    );
    _expectSuppressed(
      report.cell(
        ManagementReportPeriodKey.previous,
        ManagementContactSessionReportV1.totalCategoryKey,
      ),
    );
    expect(
      report
          .cell(
            ManagementReportPeriodKey.current,
            ManagementContactSessionReportV1.totalCategoryKey,
          )
          .result
          .privacyStatus,
      MetricPrivacyStatus.displayed,
    );
  });

  test('两位贡献者和单人超过一半都隐藏精确值', () {
    final cases = <List<ManagementMetricContribution>>[
      _contributions(
        ManagementReportPeriodKey.current,
        ContactChannel.videoCall,
        const [5, 5],
      ),
      _contributions(
        ManagementReportPeriodKey.current,
        ContactChannel.videoCall,
        const [6, 2, 2],
      ),
    ];

    for (final unsafe in cases) {
      final contributions =
          _safeContributions()
              .where(
                (item) =>
                    item.periodKey != ManagementReportPeriodKey.current ||
                    item.channel != ContactChannel.videoCall,
              )
              .toList()
            ..addAll(unsafe);
      final report = ManagementContactSessionPrivacyPolicyV1.protect(
        request: _request,
        contributions: contributions,
      );

      _expectSuppressed(
        report.cell(
          ManagementReportPeriodKey.current,
          ContactChannel.videoCall.storageValue,
        ),
      );
      _expectSuppressed(
        report.cell(
          ManagementReportPeriodKey.current,
          ManagementContactSessionReportV1.totalCategoryKey,
        ),
      );
    }
  });

  test('空格进入完整网格并触发抑制', () {
    final report = ManagementContactSessionPrivacyPolicyV1.protect(
      request: _request,
      contributions: _safeContributions()
          .where(
            (item) =>
                item.periodKey != ManagementReportPeriodKey.previous ||
                item.channel != ContactChannel.otherDirect,
          )
          .toList(),
    );

    _expectSuppressed(
      report.cell(
        ManagementReportPeriodKey.previous,
        ContactChannel.otherDirect.storageValue,
      ),
    );
  });

  test('重复或无效贡献与非相邻期间被拒绝', () {
    final duplicate = _contributions(
      ManagementReportPeriodKey.current,
      ContactChannel.faceToFace,
      const [5, 3, 2],
    ).first;
    expect(
      () => ManagementContactSessionPrivacyPolicyV1.protect(
        request: _request,
        contributions: [duplicate, duplicate],
      ),
      throwsArgumentError,
    );
    expect(
      () => ManagementMetricContribution(
        periodKey: ManagementReportPeriodKey.current,
        channel: ContactChannel.faceToFace,
        contributorKey: ' ',
        unitCount: 1,
      ),
      throwsArgumentError,
    );
    expect(
      () => ManagementMetricContribution.fromStorage(
        periodKey: 'future',
        channel: 'face_to_face',
        contributorKey: 'promoter-a',
        unitCount: 1,
      ),
      throwsArgumentError,
    );
    expect(
      () => ManagementMetricContribution.fromStorage(
        periodKey: 'current',
        channel: 'unknown',
        contributorKey: 'promoter-a',
        unitCount: 1,
      ),
      throwsArgumentError,
    );
    expect(
      () => ManagementContactSessionReportRequestV1(
        previousPeriod: MetricPeriod(
          fromUtc: DateTime.utc(2030, 1, 1),
          untilUtc: DateTime.utc(2030, 1, 8),
        ),
        currentPeriod: MetricPeriod(
          fromUtc: DateTime.utc(2030, 1, 9),
          untilUtc: DateTime.utc(2030, 1, 16),
        ),
        timeZone: 'UTC',
        dataCutoffUtc: DateTime.utc(2030, 1, 16),
      ),
      throwsArgumentError,
    );
  });

  test('Dart 政策读取共享管理 fixture', () async {
    final fixture = await _loadFixture();

    final safe = ManagementContactSessionPrivacyPolicyV1.protect(
      request: _request,
      contributions: fixture['safe']!,
    );
    expect(
      safe.cells.every(
        (cell) => cell.result.privacyStatus == MetricPrivacyStatus.displayed,
      ),
      isTrue,
    );
    expect(
      safe
          .cell(
            ManagementReportPeriodKey.current,
            ManagementContactSessionReportV1.totalCategoryKey,
          )
          .result
          .value,
      CountMetricValue(70),
    );

    final small = ManagementContactSessionPrivacyPolicyV1.protect(
      request: _request,
      contributions: fixture['small_sample']!,
    );
    _expectSuppressed(
      small.cell(
        ManagementReportPeriodKey.current,
        ContactChannel.faceToFace.storageValue,
      ),
    );

    final two = ManagementContactSessionPrivacyPolicyV1.protect(
      request: _request,
      contributions: fixture['two_contributors']!,
    );
    _expectSuppressed(
      two.cell(
        ManagementReportPeriodKey.current,
        ContactChannel.videoCall.storageValue,
      ),
    );

    final dominant = ManagementContactSessionPrivacyPolicyV1.protect(
      request: _request,
      contributions: fixture['dominant']!,
    );
    _expectSuppressed(
      dominant.cell(
        ManagementReportPeriodKey.current,
        ContactChannel.voiceCall.storageValue,
      ),
    );

    final complementary = ManagementContactSessionPrivacyPolicyV1.protect(
      request: _request,
      contributions: fixture['complementary']!,
    );
    _expectSuppressed(
      complementary.cell(
        ManagementReportPeriodKey.current,
        ManagementContactSessionReportV1.totalCategoryKey,
      ),
    );
    expect(
      complementary
          .cell(
            ManagementReportPeriodKey.current,
            ContactChannel.voiceCall.storageValue,
          )
          .result
          .privacyStatus,
      MetricPrivacyStatus.displayed,
    );
  });
}

const _contributorKeys = ['promoter-a', 'promoter-b', 'promoter-c'];

final _request = ManagementContactSessionReportRequestV1(
  previousPeriod: MetricPeriod(
    fromUtc: DateTime.utc(2030, 1, 1),
    untilUtc: DateTime.utc(2030, 1, 8),
  ),
  currentPeriod: MetricPeriod(
    fromUtc: DateTime.utc(2030, 1, 8),
    untilUtc: DateTime.utc(2030, 1, 15),
  ),
  timeZone: 'UTC',
  dataCutoffUtc: DateTime.utc(2030, 1, 15, 12),
);

List<ManagementMetricContribution> _safeContributions() => [
  for (final periodKey in ManagementReportPeriodKey.values)
    for (final channel in ContactChannel.values)
      ..._contributions(periodKey, channel, const [5, 3, 2]),
];

List<ManagementMetricContribution> _contributions(
  ManagementReportPeriodKey periodKey,
  ContactChannel channel,
  List<int> counts,
) => [
  for (var index = 0; index < counts.length; index += 1)
    ManagementMetricContribution(
      periodKey: periodKey,
      channel: channel,
      contributorKey: _contributorKeys[index],
      unitCount: counts[index],
    ),
];

void _expectSuppressed(ProtectedManagementMetricCell cell) {
  expect(cell.result.privacyStatus, MetricPrivacyStatus.suppressed);
  expect(cell.result.value, const SuppressedMetricValue());
  expect(cell.result.syncCoverage, isNull);
}

Future<Map<String, List<ManagementMetricContribution>>> _loadFixture() async {
  final lines = await File(
    'backend/database/fixtures/shared/management_contact_sessions_v1.csv',
  ).readAsLines();
  const expectedHeader =
      'scenario,period_key,channel,contributor_key,unit_count';
  if (lines.isEmpty || lines.first != expectedHeader) {
    throw const FormatException('invalid management metric fixture header');
  }
  final result = <String, List<ManagementMetricContribution>>{};
  for (final line in lines.skip(1)) {
    if (line.trim().isEmpty) continue;
    final columns = line.split(',');
    if (columns.length != 5 || columns[0].trim().isEmpty) {
      throw FormatException('invalid management metric fixture row', line);
    }
    result
        .putIfAbsent(columns[0], () => [])
        .add(
          ManagementMetricContribution.fromStorage(
            periodKey: columns[1],
            channel: columns[2],
            contributorKey: columns[3],
            unitCount: int.parse(columns[4]),
          ),
        );
  }
  return result;
}
