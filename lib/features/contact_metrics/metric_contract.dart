/// 指标的稳定身份。修改口径时必须增加 [version]，不能覆盖旧定义。
final class MetricReference {
  const MetricReference(this.metricId, this.version);

  final String metricId;
  final int version;

  @override
  bool operator ==(Object other) =>
      other is MetricReference &&
      other.metricId == metricId &&
      other.version == version;

  @override
  int get hashCode => Object.hash(metricId, version);
}

enum MetricStatisticalUnit { contactSession, reachedPerson }

enum MetricValueShape {
  count,
  ordinalDistribution,
  categoricalDistribution,
  ordinalSummary,
}

enum MetricFormula {
  countContactSessions,
  sumReachedPeople,
  countContactSessionsByInterest,
  countContactSessionsByChannel,
  summarizeContactSessionsByInterest,
}

enum MetricTimeBasis { actualOccurrenceUtc }

enum MetricExclusion { draft, contactAttempt, voidedContact }

enum MetricPrivacyRule { managementProtectedByTrueUnit }

enum MetricSourceTier { localOperational, backendOperational, warehouse }

enum MetricPrivacyStatus { personalFact, displayed, suppressed }

/// 一个版本化指标的完整计算合同。
final class MetricDefinition {
  factory MetricDefinition({
    required MetricReference reference,
    required MetricStatisticalUnit statisticalUnit,
    required MetricValueShape valueShape,
    required MetricFormula formula,
    required MetricTimeBasis timeBasis,
    required Set<MetricExclusion> exclusions,
    required MetricPrivacyRule privacyRule,
    MetricReference? denominator,
    List<String> bucketLabels = const [],
  }) {
    if (reference.metricId.trim().isEmpty || reference.version < 1) {
      throw ArgumentError('invalid_metric_reference');
    }
    final isDistribution = valueShape != MetricValueShape.count;
    if (isDistribution != bucketLabels.isNotEmpty ||
        bucketLabels.toSet().length != bucketLabels.length ||
        bucketLabels.any((label) => label.isEmpty)) {
      throw ArgumentError('invalid_metric_definition_buckets');
    }
    if (isDistribution != (denominator != null)) {
      throw ArgumentError('invalid_metric_definition_denominator');
    }
    return MetricDefinition._(
      reference: reference,
      statisticalUnit: statisticalUnit,
      valueShape: valueShape,
      formula: formula,
      timeBasis: timeBasis,
      exclusions: Set.unmodifiable(exclusions),
      privacyRule: privacyRule,
      denominator: denominator,
      bucketLabels: List.unmodifiable(bucketLabels),
    );
  }

  const MetricDefinition._({
    required this.reference,
    required this.statisticalUnit,
    required this.valueShape,
    required this.formula,
    required this.timeBasis,
    required this.exclusions,
    required this.privacyRule,
    required this.denominator,
    required this.bucketLabels,
  });

  final MetricReference reference;
  final MetricStatisticalUnit statisticalUnit;
  final MetricValueShape valueShape;
  final MetricFormula formula;
  final MetricTimeBasis timeBasis;
  final Set<MetricExclusion> exclusions;
  final MetricPrivacyRule privacyRule;
  final MetricReference? denominator;
  final List<String> bucketLabels;
}

/// 一组经唯一性校验且不可修改的指标定义。
final class MetricCatalog {
  factory MetricCatalog(Iterable<MetricDefinition> definitions) {
    final immutableDefinitions = List<MetricDefinition>.unmodifiable(
      definitions,
    );
    if (immutableDefinitions.isEmpty ||
        immutableDefinitions.map((item) => item.reference).toSet().length !=
            immutableDefinitions.length) {
      throw ArgumentError('invalid_metric_catalog');
    }
    return MetricCatalog._(immutableDefinitions);
  }

  const MetricCatalog._(this.definitions);

  final List<MetricDefinition> definitions;
}

/// Slice 6 的第一版核心指标目录。
///
/// 目录只定义口径，不授予管理权限，也不实现管理端隐私抑制。
abstract final class CoreMetricCatalog {
  static const _commonExclusions = {
    MetricExclusion.draft,
    MetricExclusion.contactAttempt,
    MetricExclusion.voidedContact,
  };

  static final contactSessions = MetricDefinition(
    reference: MetricReference('contact_sessions', 1),
    statisticalUnit: MetricStatisticalUnit.contactSession,
    valueShape: MetricValueShape.count,
    formula: MetricFormula.countContactSessions,
    timeBasis: MetricTimeBasis.actualOccurrenceUtc,
    exclusions: _commonExclusions,
    privacyRule: MetricPrivacyRule.managementProtectedByTrueUnit,
  );

  static final reachedPeople = MetricDefinition(
    reference: MetricReference('reached_people', 1),
    statisticalUnit: MetricStatisticalUnit.reachedPerson,
    valueShape: MetricValueShape.count,
    formula: MetricFormula.sumReachedPeople,
    timeBasis: MetricTimeBasis.actualOccurrenceUtc,
    exclusions: _commonExclusions,
    privacyRule: MetricPrivacyRule.managementProtectedByTrueUnit,
  );

  static final interestDistribution = MetricDefinition(
    reference: MetricReference('interest_distribution', 1),
    statisticalUnit: MetricStatisticalUnit.contactSession,
    valueShape: MetricValueShape.ordinalDistribution,
    formula: MetricFormula.countContactSessionsByInterest,
    timeBasis: MetricTimeBasis.actualOccurrenceUtc,
    exclusions: _commonExclusions,
    privacyRule: MetricPrivacyRule.managementProtectedByTrueUnit,
    denominator: const MetricReference('contact_sessions', 1),
    bucketLabels: ['0', '1', '2', '3', '4'],
  );

  static final interestOrdinalSummary = MetricDefinition(
    reference: MetricReference('interest_ordinal_summary', 1),
    statisticalUnit: MetricStatisticalUnit.contactSession,
    valueShape: MetricValueShape.ordinalSummary,
    formula: MetricFormula.summarizeContactSessionsByInterest,
    timeBasis: MetricTimeBasis.actualOccurrenceUtc,
    exclusions: _commonExclusions,
    privacyRule: MetricPrivacyRule.managementProtectedByTrueUnit,
    denominator: const MetricReference('contact_sessions', 1),
    bucketLabels: ['0', '1', '2', '3', '4'],
  );

  static final channelDistribution = MetricDefinition(
    reference: MetricReference('channel_distribution', 1),
    statisticalUnit: MetricStatisticalUnit.contactSession,
    valueShape: MetricValueShape.categoricalDistribution,
    formula: MetricFormula.countContactSessionsByChannel,
    timeBasis: MetricTimeBasis.actualOccurrenceUtc,
    exclusions: _commonExclusions,
    privacyRule: MetricPrivacyRule.managementProtectedByTrueUnit,
    denominator: const MetricReference('contact_sessions', 1),
    bucketLabels: [
      'face_to_face',
      'voice_call',
      'video_call',
      'instant_text',
      'asynchronous_message',
      'mixed',
      'other_direct',
    ],
  );

  static final catalog = MetricCatalog([
    contactSessions,
    reachedPeople,
    interestDistribution,
    channelDistribution,
    interestOrdinalSummary,
  ]);

  static List<MetricDefinition> get definitions => catalog.definitions;
}

sealed class MetricValue {
  const MetricValue();
}

/// 受管理隐私政策隐藏的值。
///
/// 此类型不保存真实值、贡献者数量或最大贡献值，避免 API 消费者从对象中恢复
/// 已被隐藏的精确数据。
final class SuppressedMetricValue extends MetricValue {
  const SuppressedMetricValue();

  @override
  bool operator ==(Object other) => other is SuppressedMetricValue;

  @override
  int get hashCode => runtimeType.hashCode;
}

final class CountMetricValue extends MetricValue {
  factory CountMetricValue(int value) {
    if (value < 0) throw ArgumentError('invalid_metric_count');
    return CountMetricValue._(value);
  }

  const CountMetricValue._(this.value);

  final int value;

  @override
  bool operator ==(Object other) =>
      other is CountMetricValue && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

final class MetricDistributionValue extends MetricValue {
  factory MetricDistributionValue({
    required List<String> labels,
    required List<int> counts,
  }) {
    if (labels.isEmpty ||
        labels.length != counts.length ||
        labels.toSet().length != labels.length ||
        labels.any((label) => label.isEmpty) ||
        counts.any((count) => count < 0)) {
      throw ArgumentError('invalid_metric_distribution');
    }
    return MetricDistributionValue._(
      List.unmodifiable(labels),
      List.unmodifiable(counts),
    );
  }

  const MetricDistributionValue._(this.labels, this.counts);

  final List<String> labels;
  final List<int> counts;

  @override
  bool operator ==(Object other) =>
      other is MetricDistributionValue &&
      _listEquals(other.labels, labels) &&
      _listEquals(other.counts, counts);

  @override
  int get hashCode =>
      Object.hash(Object.hashAll(labels), Object.hashAll(counts));
}

/// 单次兴趣有序量表的分布及下中位等级。
///
/// [medianLevel] 使用累计数量首次达到 `(totalCount + 1) ~/ 2` 的等级。
/// 空期间没有中位等级，必须使用 `null`，不能把空值编码成 `0`。
final class OrdinalSummaryMetricValue extends MetricValue {
  factory OrdinalSummaryMetricValue.fromCounts({
    required List<String> labels,
    required List<int> counts,
  }) {
    final totalCount = counts.fold<int>(0, (sum, count) => sum + count);
    return OrdinalSummaryMetricValue(
      labels: labels,
      counts: counts,
      totalCount: totalCount,
      medianLevel: totalCount <= 0
          ? null
          : _lowerMedianLevel(counts, totalCount),
    );
  }

  factory OrdinalSummaryMetricValue({
    required List<String> labels,
    required List<int> counts,
    required int totalCount,
    required int? medianLevel,
  }) {
    if (!_listEquals(labels, _fiveLevelOrdinalLabels) ||
        labels.length != counts.length ||
        labels.toSet().length != labels.length ||
        labels.any((label) => label.isEmpty) ||
        totalCount < 0 ||
        counts.any((count) => count < 0) ||
        counts.fold<int>(0, (sum, count) => sum + count) != totalCount) {
      throw ArgumentError('invalid_metric_ordinal_summary');
    }

    if (totalCount == 0) {
      if (medianLevel != null) {
        throw ArgumentError('invalid_metric_ordinal_summary_median');
      }
    } else {
      if (medianLevel == null) {
        throw ArgumentError('invalid_metric_ordinal_summary_median');
      }
      final expectedMedian = _lowerMedianLevel(counts, totalCount);
      if (medianLevel != expectedMedian) {
        throw ArgumentError('invalid_metric_ordinal_summary_median');
      }
    }

    return OrdinalSummaryMetricValue._(
      labels: List.unmodifiable(labels),
      counts: List.unmodifiable(counts),
      totalCount: totalCount,
      medianLevel: medianLevel,
    );
  }

  const OrdinalSummaryMetricValue._({
    required this.labels,
    required this.counts,
    required this.totalCount,
    required this.medianLevel,
  });

  final List<String> labels;
  final List<int> counts;
  final int totalCount;
  final int? medianLevel;

  @override
  bool operator ==(Object other) =>
      other is OrdinalSummaryMetricValue &&
      _listEquals(other.labels, labels) &&
      _listEquals(other.counts, counts) &&
      other.totalCount == totalCount &&
      other.medianLevel == medianLevel;

  @override
  int get hashCode => Object.hash(
    Object.hashAll(labels),
    Object.hashAll(counts),
    totalCount,
    medianLevel,
  );
}

final class MetricPeriod {
  factory MetricPeriod({
    required DateTime fromUtc,
    required DateTime untilUtc,
  }) {
    if (!fromUtc.isUtc || !untilUtc.isUtc || !fromUtc.isBefore(untilUtc)) {
      throw ArgumentError('invalid_metric_period');
    }
    return MetricPeriod._(fromUtc, untilUtc);
  }

  const MetricPeriod._(this.fromUtc, this.untilUtc);

  final DateTime fromUtc;
  final DateTime untilUtc;
}

/// 结果中与“数据是否已同步”有关的明确分母。
///
/// 覆盖单位可以与指标的统计单位不同。例如 reached_people 的值单位是人数，
/// 但当前本地同步队列只可靠地统计接触场次，不能虚构“已同步人数”。
final class MetricSyncCoverage {
  factory MetricSyncCoverage({
    required MetricStatisticalUnit statisticalUnit,
    required int totalCount,
    required int pendingCount,
  }) {
    if (totalCount < 0 || pendingCount < 0 || pendingCount > totalCount) {
      throw ArgumentError('invalid_metric_sync_coverage');
    }
    return MetricSyncCoverage._(statisticalUnit, totalCount, pendingCount);
  }

  const MetricSyncCoverage._(
    this.statisticalUnit,
    this.totalCount,
    this.pendingCount,
  );

  final MetricStatisticalUnit statisticalUnit;
  final int totalCount;
  final int pendingCount;

  int get synchronizedCount => totalCount - pendingCount;
}

/// 一个可审计、可跨层传递的指标结果。
final class MetricResult {
  factory MetricResult({
    required MetricDefinition definition,
    required MetricValue value,
    required MetricPeriod period,
    required String timeZone,
    required DateTime dataCutoffUtc,
    required MetricSourceTier sourceTier,
    MetricSyncCoverage? syncCoverage,
    required MetricPrivacyStatus privacyStatus,
  }) {
    if (timeZone.trim().isEmpty || !dataCutoffUtc.isUtc) {
      throw ArgumentError('invalid_metric_result_metadata');
    }
    final isSuppressedValue = value is SuppressedMetricValue;
    if ((privacyStatus == MetricPrivacyStatus.suppressed) !=
            isSuppressedValue ||
        (sourceTier == MetricSourceTier.localOperational) !=
            (syncCoverage != null) ||
        privacyStatus == MetricPrivacyStatus.personalFact &&
            sourceTier != MetricSourceTier.localOperational) {
      throw ArgumentError('invalid_metric_result_state');
    }
    if (!isSuppressedValue) _validateValue(definition, value);
    return MetricResult._(
      definition: definition,
      value: value,
      period: period,
      timeZone: timeZone,
      dataCutoffUtc: dataCutoffUtc,
      sourceTier: sourceTier,
      syncCoverage: syncCoverage,
      privacyStatus: privacyStatus,
    );
  }

  const MetricResult._({
    required this.definition,
    required this.value,
    required this.period,
    required this.timeZone,
    required this.dataCutoffUtc,
    required this.sourceTier,
    required this.syncCoverage,
    required this.privacyStatus,
  });

  final MetricDefinition definition;
  final MetricValue value;
  final MetricPeriod period;
  final String timeZone;
  final DateTime dataCutoffUtc;
  final MetricSourceTier sourceTier;
  final MetricSyncCoverage? syncCoverage;
  final MetricPrivacyStatus privacyStatus;

  static void _validateValue(MetricDefinition definition, MetricValue value) {
    final shapeMatches = switch (definition.valueShape) {
      MetricValueShape.count => value is CountMetricValue,
      MetricValueShape.ordinalDistribution ||
      MetricValueShape.categoricalDistribution =>
        value is MetricDistributionValue,
      MetricValueShape.ordinalSummary => value is OrdinalSummaryMetricValue,
    };
    if (!shapeMatches) {
      throw ArgumentError('metric_value_shape_mismatch');
    }
    if (value is MetricDistributionValue &&
        !_listEquals(value.labels, definition.bucketLabels)) {
      throw ArgumentError('metric_distribution_labels_mismatch');
    }
    if (value is OrdinalSummaryMetricValue &&
        !_listEquals(value.labels, definition.bucketLabels)) {
      throw ArgumentError('metric_ordinal_summary_labels_mismatch');
    }
  }
}

const _fiveLevelOrdinalLabels = ['0', '1', '2', '3', '4'];

int _lowerMedianLevel(List<int> counts, int totalCount) {
  final rank = (totalCount + 1) ~/ 2;
  var cumulative = 0;
  for (var level = 0; level < counts.length; level += 1) {
    cumulative += counts[level];
    if (cumulative >= rank) return level;
  }
  throw ArgumentError('invalid_metric_ordinal_summary_median');
}

bool _listEquals<T>(List<T> left, List<T> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) return false;
  }
  return true;
}
