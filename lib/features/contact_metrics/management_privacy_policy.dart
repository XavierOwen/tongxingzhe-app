import '../contact_journal/contact_models.dart';
import 'metric_contract.dart';

enum ManagementReportPeriodKey { previous, current }

extension ManagementReportPeriodKeyStorage on ManagementReportPeriodKey {
  String get storageValue => name;

  static ManagementReportPeriodKey fromStorage(String value) => switch (value) {
    'previous' => ManagementReportPeriodKey.previous,
    'current' => ManagementReportPeriodKey.current,
    _ => throw ArgumentError('unknown_management_report_period'),
  };
}

/// 固定管理报表中一位贡献者对一个渠道格的有效接触数。
final class ManagementMetricContribution {
  factory ManagementMetricContribution({
    required ManagementReportPeriodKey periodKey,
    required ContactChannel channel,
    required String contributorKey,
    required int unitCount,
  }) {
    final normalizedContributorKey = contributorKey.trim();
    if (normalizedContributorKey.isEmpty ||
        unitCount <= 0 ||
        unitCount > 2147483647) {
      throw ArgumentError('invalid_management_metric_contribution');
    }
    return ManagementMetricContribution._(
      periodKey: periodKey,
      channel: channel,
      contributorKey: normalizedContributorKey,
      unitCount: unitCount,
    );
  }

  factory ManagementMetricContribution.fromStorage({
    required String periodKey,
    required String channel,
    required String contributorKey,
    required int unitCount,
  }) {
    try {
      return ManagementMetricContribution(
        periodKey: ManagementReportPeriodKeyStorage.fromStorage(periodKey),
        channel: ContactChannel.fromStorage(channel),
        contributorKey: contributorKey,
        unitCount: unitCount,
      );
    } on StateError {
      throw ArgumentError('unknown_management_report_channel');
    }
  }

  const ManagementMetricContribution._({
    required this.periodKey,
    required this.channel,
    required this.contributorKey,
    required this.unitCount,
  });

  final ManagementReportPeriodKey periodKey;
  final ContactChannel channel;
  final String contributorKey;
  final int unitCount;
}

/// 双期间渠道报表的规范时间元数据。
final class ManagementContactSessionReportRequestV1 {
  factory ManagementContactSessionReportRequestV1({
    required MetricPeriod previousPeriod,
    required MetricPeriod currentPeriod,
    required String timeZone,
    required DateTime dataCutoffUtc,
  }) {
    if (previousPeriod.untilUtc != currentPeriod.fromUtc ||
        timeZone.trim().isEmpty ||
        !dataCutoffUtc.isUtc) {
      throw ArgumentError('invalid_management_report_request');
    }
    return ManagementContactSessionReportRequestV1._(
      previousPeriod: previousPeriod,
      currentPeriod: currentPeriod,
      timeZone: timeZone.trim(),
      dataCutoffUtc: dataCutoffUtc,
    );
  }

  const ManagementContactSessionReportRequestV1._({
    required this.previousPeriod,
    required this.currentPeriod,
    required this.timeZone,
    required this.dataCutoffUtc,
  });

  final MetricPeriod previousPeriod;
  final MetricPeriod currentPeriod;
  final String timeZone;
  final DateTime dataCutoffUtc;

  MetricPeriod period(ManagementReportPeriodKey key) => switch (key) {
    ManagementReportPeriodKey.previous => previousPeriod,
    ManagementReportPeriodKey.current => currentPeriod,
  };
}

/// 一个已经过服务端隐私政策的固定网格单元。
final class ProtectedManagementMetricCell {
  const ProtectedManagementMetricCell({
    required this.periodKey,
    required this.categoryKey,
    required this.result,
  });

  final ManagementReportPeriodKey periodKey;
  final String categoryKey;
  final MetricResult result;
}

/// 固定 v1 报表的结果。每期先返回总计，再返回七个渠道。
final class ManagementContactSessionReportV1 {
  ManagementContactSessionReportV1._(List<ProtectedManagementMetricCell> cells)
    : cells = List.unmodifiable(cells);

  static const totalCategoryKey = 'all';

  final List<ProtectedManagementMetricCell> cells;

  ProtectedManagementMetricCell cell(
    ManagementReportPeriodKey periodKey,
    String categoryKey,
  ) => cells.singleWhere(
    (cell) => cell.periodKey == periodKey && cell.categoryKey == categoryKey,
  );
}

/// `contact_sessions_by_channel_two_periods` v1 的隐私政策。
///
/// 这是一段纯政策逻辑，不读取成员关系，也不授予查询权限。授权后的固定报告构造器
/// 才能在未来调用它。任何渠道被隐藏时，同期总计也隐藏，阻止用总计减去已显示
/// 渠道恢复该格的精确值。
abstract final class ManagementContactSessionPrivacyPolicyV1 {
  static const minimumUnitCount = 10;
  static const minimumContributorCount = 3;

  static ManagementContactSessionReportV1 protect({
    required ManagementContactSessionReportRequestV1 request,
    required Iterable<ManagementMetricContribution> contributions,
  }) {
    final byCell =
        <(ManagementReportPeriodKey, ContactChannel), Map<String, int>>{};
    final seenContributions =
        <(ManagementReportPeriodKey, ContactChannel, String)>{};
    for (final contribution in contributions) {
      final uniqueKey = (
        contribution.periodKey,
        contribution.channel,
        contribution.contributorKey,
      );
      if (!seenContributions.add(uniqueKey)) {
        throw ArgumentError('duplicate_management_metric_contribution');
      }
      final counts = byCell.putIfAbsent((
        contribution.periodKey,
        contribution.channel,
      ), () => <String, int>{});
      counts[contribution.contributorKey] = contribution.unitCount;
    }

    final cells = <ProtectedManagementMetricCell>[];
    for (final periodKey in ManagementReportPeriodKey.values) {
      final leafCounts = <ContactChannel, Map<String, int>>{
        for (final channel in ContactChannel.values)
          channel: byCell[(periodKey, channel)] ?? const {},
      };
      final hasSuppressedLeaf = leafCounts.values.any(
        (counts) => !_canDisplay(counts),
      );
      final totalCounts = <String, int>{};
      for (final counts in leafCounts.values) {
        for (final entry in counts.entries) {
          totalCounts.update(
            entry.key,
            (current) => current + entry.value,
            ifAbsent: () => entry.value,
          );
        }
      }
      cells.add(
        _cell(
          request: request,
          periodKey: periodKey,
          categoryKey: ManagementContactSessionReportV1.totalCategoryKey,
          counts: totalCounts,
          forceSuppress: hasSuppressedLeaf,
        ),
      );
      for (final channel in ContactChannel.values) {
        cells.add(
          _cell(
            request: request,
            periodKey: periodKey,
            categoryKey: channel.storageValue,
            counts: leafCounts[channel]!,
          ),
        );
      }
    }
    return ManagementContactSessionReportV1._(cells);
  }

  static ProtectedManagementMetricCell _cell({
    required ManagementContactSessionReportRequestV1 request,
    required ManagementReportPeriodKey periodKey,
    required String categoryKey,
    required Map<String, int> counts,
    bool forceSuppress = false,
  }) {
    final displayed = !forceSuppress && _canDisplay(counts);
    return ProtectedManagementMetricCell(
      periodKey: periodKey,
      categoryKey: categoryKey,
      result: MetricResult(
        definition: CoreMetricCatalog.contactSessions,
        value: displayed
            ? CountMetricValue(_total(counts))
            : const SuppressedMetricValue(),
        period: request.period(periodKey),
        timeZone: request.timeZone,
        dataCutoffUtc: request.dataCutoffUtc,
        sourceTier: MetricSourceTier.backendOperational,
        privacyStatus: displayed
            ? MetricPrivacyStatus.displayed
            : MetricPrivacyStatus.suppressed,
      ),
    );
  }

  static bool _canDisplay(Map<String, int> counts) {
    final total = _total(counts);
    if (total < minimumUnitCount || counts.length < minimumContributorCount) {
      return false;
    }
    final largestContribution = counts.values.reduce(
      (largest, value) => value > largest ? value : largest,
    );
    return largestContribution * 2 <= total;
  }

  static int _total(Map<String, int> counts) =>
      counts.values.fold(0, (sum, value) => sum + value);
}
