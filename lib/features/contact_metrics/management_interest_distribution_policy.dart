import 'management_privacy_policy.dart';
import 'metric_contract.dart';

/// 固定管理兴趣分布报告的稳定身份。
const managementInterestDistributionReportId =
    'contact_sessions_by_interest_level_two_periods';
const managementInterestDistributionReportVersion = 1;

/// 管理兴趣分布的输入贡献。
///
/// 一条贡献代表一个可信推广者在一个期间、一个兴趣等级上贡献的有效接触
/// 场次数。它不是可供客户端自由组合的维度查询；报告只接受固定的
/// `previous/current × 0..4` 网格。
final class ManagementInterestMetricContribution {
  factory ManagementInterestMetricContribution({
    required ManagementReportPeriodKey periodKey,
    required int interestLevel,
    required String contributorKey,
    required int unitCount,
  }) {
    final normalizedContributorKey = contributorKey.trim();
    if (interestLevel < 0 ||
        interestLevel > 4 ||
        normalizedContributorKey.isEmpty ||
        normalizedContributorKey.runes.length > _maximumContributorKeyLength ||
        unitCount <= 0 ||
        unitCount > _maximumContributionCount) {
      throw ArgumentError('invalid_management_interest_contribution');
    }
    return ManagementInterestMetricContribution._(
      periodKey: periodKey,
      interestLevel: interestLevel,
      contributorKey: normalizedContributorKey,
      unitCount: unitCount,
    );
  }

  /// 读取数据库或 HTTP 解码后的固定期间字符串。
  ///
  /// 不接受任意维度或未知期间；未知值在进入政策计算前失败关闭。
  factory ManagementInterestMetricContribution.fromStorage({
    required String period,
    required int interestLevel,
    required String contributorKey,
    required int unitCount,
  }) => ManagementInterestMetricContribution(
    periodKey: ManagementReportPeriodKeyStorage.fromStorage(period),
    interestLevel: interestLevel,
    contributorKey: contributorKey,
    unitCount: unitCount,
  );

  const ManagementInterestMetricContribution._({
    required this.periodKey,
    required this.interestLevel,
    required this.contributorKey,
    required this.unitCount,
  });

  final ManagementReportPeriodKey periodKey;
  final int interestLevel;
  final String contributorKey;
  final int unitCount;

  /// 与既有管理期间请求的字段命名保持一致，同时让输入合同更易读。
  ManagementReportPeriodKey get period => periodKey;
}

/// 保护后的管理兴趣五档网格单元。
///
/// 单元只携带固定报告合同允许的期间、等级、隐私状态和可选 count。完整的
/// [MetricResult] 仍由报告按期间保存，用于复用 [CoreMetricCatalog
/// .interestDistribution] 的版本化指标语义；它不被复制到每个输出单元，避免
/// 消费者从一个格子的对象中看到其他格子的值。
final class ProtectedManagementInterestCell {
  factory ProtectedManagementInterestCell({
    required ManagementReportPeriodKey periodKey,
    required int interestLevel,
    required MetricPrivacyStatus privacyStatus,
    required int? count,
  }) {
    if (interestLevel < 0 ||
        interestLevel > 4 ||
        privacyStatus != MetricPrivacyStatus.displayed &&
            privacyStatus != MetricPrivacyStatus.suppressed ||
        privacyStatus == MetricPrivacyStatus.suppressed && count != null ||
        privacyStatus != MetricPrivacyStatus.suppressed && count == null ||
        count != null &&
            (count <
                    ManagementInterestDistributionPrivacyPolicyV1
                        .minimumUnitCount ||
                count > _maximumOutputCount)) {
      throw ArgumentError('invalid_management_interest_cell');
    }
    return ProtectedManagementInterestCell._(
      periodKey: periodKey,
      interestLevel: interestLevel,
      privacyStatus: privacyStatus,
      count: count,
    );
  }

  const ProtectedManagementInterestCell._({
    required this.periodKey,
    required this.interestLevel,
    required this.privacyStatus,
    required this.count,
  });

  final ManagementReportPeriodKey periodKey;
  final int interestLevel;
  final MetricPrivacyStatus privacyStatus;
  final int? count;

  /// 显示格返回该等级的场次数；抑制格必须返回 `null`，绝不返回精确 0。
  int? get displayedCount => count;
}

/// `contact_sessions_by_interest_level_two_periods@1` 的纯 Dart 隐私政策。
///
/// 结果严格按 `previous/current × 0,1,2,3,4` 输出，不包含总计。每个期间
/// 独立判断：该期间任意等级不满足最小样本、贡献者和集中度条件时，五个等级
/// 全部抑制；另一期间的结果不受影响。
abstract final class ManagementInterestDistributionPrivacyPolicyV1 {
  static const minimumUnitCount = 10;
  static const minimumContributorCount = 3;
  static const maximumContributorShareNumerator = 1;
  static const maximumContributorShareDenominator = 2;

  static ManagementInterestDistributionReportV1 protect({
    required ManagementContactSessionReportRequestV1 request,
    required Iterable<ManagementInterestMetricContribution> contributions,
  }) {
    final byCell = <(ManagementReportPeriodKey, int), Map<String, int>>{};
    final seenContributions = <(ManagementReportPeriodKey, int, String)>{};

    for (final contribution in contributions) {
      final uniqueKey = (
        contribution.periodKey,
        contribution.interestLevel,
        contribution.contributorKey,
      );
      if (!seenContributions.add(uniqueKey)) {
        throw ArgumentError('duplicate_management_interest_contribution');
      }

      final counts = byCell.putIfAbsent((
        contribution.periodKey,
        contribution.interestLevel,
      ), () => <String, int>{});
      counts[contribution.contributorKey] = contribution.unitCount;
    }

    final metrics = <ManagementReportPeriodKey, MetricResult>{};
    final cells = <ProtectedManagementInterestCell>[];
    for (final periodKey in ManagementReportPeriodKey.values) {
      final countsByLevel = <int, Map<String, int>>{
        for (var interestLevel = 0; interestLevel <= 4; interestLevel++)
          interestLevel:
              byCell[(periodKey, interestLevel)] ?? const <String, int>{},
      };
      final isPeriodSafe = countsByLevel.values.every(_canDisplay);
      final metric = _metric(
        request: request,
        periodKey: periodKey,
        countsByLevel: countsByLevel,
        displayed: isPeriodSafe,
      );
      metrics[periodKey] = metric;

      for (var interestLevel = 0; interestLevel <= 4; interestLevel++) {
        cells.add(
          ProtectedManagementInterestCell(
            periodKey: periodKey,
            interestLevel: interestLevel,
            privacyStatus: metric.privacyStatus,
            count: isPeriodSafe ? _total(countsByLevel[interestLevel]!) : null,
          ),
        );
      }
    }

    return ManagementInterestDistributionReportV1._(
      cells: cells,
      periodMetrics: metrics,
    );
  }

  static MetricResult _metric({
    required ManagementContactSessionReportRequestV1 request,
    required ManagementReportPeriodKey periodKey,
    required Map<int, Map<String, int>> countsByLevel,
    required bool displayed,
  }) {
    final counts = displayed
        ? [
            for (var interestLevel = 0; interestLevel <= 4; interestLevel++)
              _total(countsByLevel[interestLevel]!),
          ]
        : null;
    if (counts != null) {
      // The five cells form one distribution. Its implied period total must
      // remain exact even though v1 does not expose a separate total cell.
      _sumExactCounts(counts);
    }
    return MetricResult(
      definition: CoreMetricCatalog.interestDistribution,
      value: displayed
          ? MetricDistributionValue(
              labels: CoreMetricCatalog.interestDistribution.bucketLabels,
              counts: counts!,
            )
          : const SuppressedMetricValue(),
      period: request.period(periodKey),
      timeZone: request.timeZone,
      dataCutoffUtc: request.dataCutoffUtc,
      sourceTier: MetricSourceTier.backendOperational,
      privacyStatus: displayed
          ? MetricPrivacyStatus.displayed
          : MetricPrivacyStatus.suppressed,
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
    return largestContribution * maximumContributorShareDenominator <=
        total * maximumContributorShareNumerator;
  }

  static int _total(Map<String, int> counts) => _sumExactCounts(counts.values);

  static int _sumExactCounts(Iterable<int> counts) {
    var total = 0;
    for (final value in counts) {
      if (value > _maximumOutputCount - total) {
        throw ArgumentError('management_interest_count_exceeds_safe_integer');
      }
      total += value;
    }
    return total;
  }
}

/// 固定兴趣报告的双期间结果。
final class ManagementInterestDistributionReportV1 {
  ManagementInterestDistributionReportV1._({
    required List<ProtectedManagementInterestCell> cells,
    required Map<ManagementReportPeriodKey, MetricResult> periodMetrics,
  }) : cells = List.unmodifiable(cells),
       periodMetrics = Map.unmodifiable(periodMetrics);

  static const contractId = managementInterestDistributionReportId;
  static const version = managementInterestDistributionReportVersion;

  final List<ProtectedManagementInterestCell> cells;
  final Map<ManagementReportPeriodKey, MetricResult> periodMetrics;

  String get reportId => contractId;
  int get reportVersion => version;

  MetricResult metric(ManagementReportPeriodKey periodKey) =>
      periodMetrics[periodKey]!;

  ProtectedManagementInterestCell cell(
    ManagementReportPeriodKey periodKey,
    int interestLevel,
  ) {
    if (interestLevel < 0 || interestLevel > 4) {
      throw ArgumentError('unknown_management_interest_level');
    }
    return cells.singleWhere(
      (cell) =>
          cell.periodKey == periodKey && cell.interestLevel == interestLevel,
    );
  }
}

// Contributions match PostgreSQL `integer`; displayed aggregates remain exact
// on every Dart target, including JavaScript runtimes.
const _maximumContributionCount = 2147483647;
const _maximumOutputCount = 9007199254740991;
const _maximumContributorKeyLength = 120;
