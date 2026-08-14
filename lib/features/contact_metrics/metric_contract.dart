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

enum MetricStatisticalUnit {
  contactSession,
  reachedPerson,
  contactTargetLink,

  /// 去重的“推广对象 × 项目”当前关系。
  targetProjectRelationship,

  /// 一次真正改变关系阶段的追加 revision。
  relationshipStageChangeEvent,
}

enum MetricValueShape {
  count,
  ordinalDistribution,
  categoricalDistribution,
  ordinalSummary,
  ratio,
  subsetRatio,
}

enum MetricFormula {
  countContactSessions,
  sumReachedPeople,
  countContactSessionsByInterest,
  countContactSessionsByChannel,
  countContactTargetLinksWithResponse,
  countContactTargetLinksByResponse,
  summarizeContactTargetLinksByResponse,
  summarizeContactSessionsByInterest,
  calculateContactSessionsByInterestRatio,
  calculateContactSessionsByInterestSubsetRatio,
  calculateContactTargetLinksByResponseRatio,
  countContactTargetLinksWithFollowUpConsentAnswer,
  calculateContactTargetLinksByFollowUpConsentRatio,
  countCurrentRelationshipStages,
  countCurrentRelationshipStagesByStage,
  countRelationshipStageChangeEvents,
  countDistinctRelationshipsWithStageChange,
  countRelationshipStageChangeEventsByDirection,
}

enum MetricTimeBasis {
  actualOccurrenceUtc,
  currentSnapshotUtc,
  relationshipChangedAtUtc,
}

enum MetricExclusion {
  draft,
  contactAttempt,
  voidedContact,
  initialRelationshipEntry,
  nonStageRelationshipRevision,
  unchangedRelationshipStage,
}

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
    MetricStatisticalUnit? managementPrivacyUnit,
    MetricReference? denominator,
    List<String> bucketLabels = const [],
  }) {
    if (reference.metricId.trim().isEmpty || reference.version < 1) {
      throw ArgumentError('invalid_metric_reference');
    }
    final hasBuckets = valueShape != MetricValueShape.count;
    if (hasBuckets != bucketLabels.isNotEmpty ||
        bucketLabels.toSet().length != bucketLabels.length ||
        bucketLabels.any((label) => label.isEmpty)) {
      throw ArgumentError('invalid_metric_definition_buckets');
    }
    if (hasBuckets != (denominator != null)) {
      throw ArgumentError('invalid_metric_definition_denominator');
    }
    if (valueShape == MetricValueShape.subsetRatio &&
        bucketLabels.length != 1) {
      throw ArgumentError('invalid_metric_subset_ratio_labels');
    }
    return MetricDefinition._(
      reference: reference,
      statisticalUnit: statisticalUnit,
      valueShape: valueShape,
      formula: formula,
      timeBasis: timeBasis,
      exclusions: Set.unmodifiable(exclusions),
      privacyRule: privacyRule,
      managementPrivacyUnit: managementPrivacyUnit ?? statisticalUnit,
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
    required this.managementPrivacyUnit,
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

  /// 管理报告执行最小群体阈值时使用的真实去重单位。
  ///
  /// 多个事件可以来自同一对象 × 项目关系，因此事件指标不能默认把事件数
  /// 当作管理 `k`。个人结果仍使用 [statisticalUnit] 表达值的单位。
  final MetricStatisticalUnit managementPrivacyUnit;
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
    final definitionsByReference = {
      for (final definition in immutableDefinitions)
        definition.reference: definition,
    };
    for (final definition in immutableDefinitions) {
      final denominator = definition.denominator;
      if (denominator == null) continue;
      final denominatorDefinition = definitionsByReference[denominator];
      if (denominatorDefinition == null ||
          denominatorDefinition.valueShape != MetricValueShape.count ||
          denominatorDefinition.statisticalUnit != definition.statisticalUnit ||
          denominatorDefinition.timeBasis != definition.timeBasis ||
          denominatorDefinition.exclusions.length !=
              definition.exclusions.length ||
          !denominatorDefinition.exclusions.containsAll(
            definition.exclusions,
          ) ||
          denominatorDefinition.privacyRule != definition.privacyRule ||
          denominatorDefinition.managementPrivacyUnit !=
              definition.managementPrivacyUnit ||
          !_usesDenominatorFormula(
            definition.formula,
            denominatorDefinition.formula,
          )) {
        throw ArgumentError('invalid_metric_catalog_denominator');
      }
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

  /// 已填写对象反应的接触对象关联数；它是对象反应分布的窄分母指标。
  static final targetResponses = MetricDefinition(
    reference: MetricReference('target_responses', 1),
    statisticalUnit: MetricStatisticalUnit.contactTargetLink,
    valueShape: MetricValueShape.count,
    formula: MetricFormula.countContactTargetLinksWithResponse,
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

  static final interestLevelRatios = MetricDefinition(
    reference: MetricReference('interest_level_ratios', 1),
    statisticalUnit: MetricStatisticalUnit.contactSession,
    valueShape: MetricValueShape.ratio,
    formula: MetricFormula.calculateContactSessionsByInterestRatio,
    timeBasis: MetricTimeBasis.actualOccurrenceUtc,
    exclusions: _commonExclusions,
    privacyRule: MetricPrivacyRule.managementProtectedByTrueUnit,
    denominator: const MetricReference('contact_sessions', 1),
    bucketLabels: ['0', '1', '2', '3', '4'],
  );

  static final interestThreeFourRatio = MetricDefinition(
    reference: MetricReference('interest_3_4_ratio', 1),
    statisticalUnit: MetricStatisticalUnit.contactSession,
    valueShape: MetricValueShape.subsetRatio,
    formula: MetricFormula.calculateContactSessionsByInterestSubsetRatio,
    timeBasis: MetricTimeBasis.actualOccurrenceUtc,
    exclusions: _commonExclusions,
    privacyRule: MetricPrivacyRule.managementProtectedByTrueUnit,
    denominator: const MetricReference('contact_sessions', 1),
    bucketLabels: ['3_4'],
  );

  static final interestZeroRatio = MetricDefinition(
    reference: MetricReference('interest_0_ratio', 1),
    statisticalUnit: MetricStatisticalUnit.contactSession,
    valueShape: MetricValueShape.subsetRatio,
    formula: MetricFormula.calculateContactSessionsByInterestSubsetRatio,
    timeBasis: MetricTimeBasis.actualOccurrenceUtc,
    exclusions: _commonExclusions,
    privacyRule: MetricPrivacyRule.managementProtectedByTrueUnit,
    denominator: const MetricReference('contact_sessions', 1),
    bucketLabels: ['0'],
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

  static final targetResponseDistribution = MetricDefinition(
    reference: MetricReference('target_response_distribution', 1),
    statisticalUnit: MetricStatisticalUnit.contactTargetLink,
    valueShape: MetricValueShape.ordinalDistribution,
    formula: MetricFormula.countContactTargetLinksByResponse,
    timeBasis: MetricTimeBasis.actualOccurrenceUtc,
    exclusions: _commonExclusions,
    privacyRule: MetricPrivacyRule.managementProtectedByTrueUnit,
    denominator: targetResponses.reference,
    bucketLabels: ['0', '1', '2', '3', '4'],
  );

  static final targetResponseOrdinalSummary = MetricDefinition(
    reference: MetricReference('target_response_ordinal_summary', 1),
    statisticalUnit: MetricStatisticalUnit.contactTargetLink,
    valueShape: MetricValueShape.ordinalSummary,
    formula: MetricFormula.summarizeContactTargetLinksByResponse,
    timeBasis: MetricTimeBasis.actualOccurrenceUtc,
    exclusions: _commonExclusions,
    privacyRule: MetricPrivacyRule.managementProtectedByTrueUnit,
    denominator: targetResponses.reference,
    bucketLabels: ['0', '1', '2', '3', '4'],
  );

  static final targetResponseLevelRatios = MetricDefinition(
    reference: MetricReference('target_response_level_ratios', 1),
    statisticalUnit: MetricStatisticalUnit.contactTargetLink,
    valueShape: MetricValueShape.ratio,
    formula: MetricFormula.calculateContactTargetLinksByResponseRatio,
    timeBasis: MetricTimeBasis.actualOccurrenceUtc,
    exclusions: _commonExclusions,
    privacyRule: MetricPrivacyRule.managementProtectedByTrueUnit,
    denominator: targetResponses.reference,
    bucketLabels: ['0', '1', '2', '3', '4'],
  );

  /// 可选同意占比的窄分母；不进入默认核心目录。
  static final followUpConsentAnswers = MetricDefinition(
    reference: MetricReference('follow_up_consent_answers', 1),
    statisticalUnit: MetricStatisticalUnit.contactTargetLink,
    valueShape: MetricValueShape.count,
    formula: MetricFormula.countContactTargetLinksWithFollowUpConsentAnswer,
    timeBasis: MetricTimeBasis.actualOccurrenceUtc,
    exclusions: _commonExclusions,
    privacyRule: MetricPrivacyRule.managementProtectedByTrueUnit,
  );

  /// 项目明确启用后才存在的固定 `yes / (yes + no)` 指标。
  static final followUpConsentRatio = MetricDefinition(
    reference: MetricReference('follow_up_consent_ratio', 1),
    statisticalUnit: MetricStatisticalUnit.contactTargetLink,
    valueShape: MetricValueShape.ratio,
    formula: MetricFormula.calculateContactTargetLinksByFollowUpConsentRatio,
    timeBasis: MetricTimeBasis.actualOccurrenceUtc,
    exclusions: _commonExclusions,
    privacyRule: MetricPrivacyRule.managementProtectedByTrueUnit,
    denominator: followUpConsentAnswers.reference,
    bucketLabels: ['yes', 'no'],
  );

  /// 当前关系阶段五档分布的宽分母。
  ///
  /// 它没有接触期间，也不能被解释为历史期间的计数。
  static final currentRelationshipStageCount = MetricDefinition(
    reference: MetricReference('current_relationship_stage_count', 1),
    statisticalUnit: MetricStatisticalUnit.targetProjectRelationship,
    valueShape: MetricValueShape.count,
    formula: MetricFormula.countCurrentRelationshipStages,
    timeBasis: MetricTimeBasis.currentSnapshotUtc,
    exclusions: const {},
    privacyRule: MetricPrivacyRule.managementProtectedByTrueUnit,
  );

  /// 当前快照中每个 active 对象 × 项目关系的阶段分布。
  static final currentRelationshipStageDistribution = MetricDefinition(
    reference: MetricReference('current_relationship_stage_distribution', 1),
    statisticalUnit: MetricStatisticalUnit.targetProjectRelationship,
    valueShape: MetricValueShape.ordinalDistribution,
    formula: MetricFormula.countCurrentRelationshipStagesByStage,
    timeBasis: MetricTimeBasis.currentSnapshotUtc,
    exclusions: const {},
    privacyRule: MetricPrivacyRule.managementProtectedByTrueUnit,
    denominator: currentRelationshipStageCount.reference,
    bucketLabels: ['0', '1', '2', '3', '4'],
  );

  /// 本人于期间内实际执行的关系阶段变更 revision 数。
  static final relationshipStageChangeEvents = MetricDefinition(
    reference: MetricReference('relationship_stage_change_events', 1),
    statisticalUnit: MetricStatisticalUnit.relationshipStageChangeEvent,
    valueShape: MetricValueShape.count,
    formula: MetricFormula.countRelationshipStageChangeEvents,
    timeBasis: MetricTimeBasis.relationshipChangedAtUtc,
    exclusions: const {
      MetricExclusion.initialRelationshipEntry,
      MetricExclusion.nonStageRelationshipRevision,
      MetricExclusion.unchangedRelationshipStage,
    },
    privacyRule: MetricPrivacyRule.managementProtectedByTrueUnit,
    managementPrivacyUnit: MetricStatisticalUnit.targetProjectRelationship,
  );

  /// 期间内至少发生过一次本人阶段变更的去重对象 × 项目关系数。
  static final relationshipsWithStageChange = MetricDefinition(
    reference: MetricReference('relationships_with_stage_change', 1),
    statisticalUnit: MetricStatisticalUnit.targetProjectRelationship,
    valueShape: MetricValueShape.count,
    formula: MetricFormula.countDistinctRelationshipsWithStageChange,
    timeBasis: MetricTimeBasis.relationshipChangedAtUtc,
    exclusions: relationshipStageChangeEvents.exclusions,
    privacyRule: MetricPrivacyRule.managementProtectedByTrueUnit,
  );

  /// 阶段变更事件按上升、下降的固定顺序分布。
  static final relationshipStageChangeDirectionDistribution = MetricDefinition(
    reference: MetricReference(
      'relationship_stage_change_direction_distribution',
      1,
    ),
    statisticalUnit: MetricStatisticalUnit.relationshipStageChangeEvent,
    valueShape: MetricValueShape.categoricalDistribution,
    formula: MetricFormula.countRelationshipStageChangeEventsByDirection,
    timeBasis: MetricTimeBasis.relationshipChangedAtUtc,
    exclusions: relationshipStageChangeEvents.exclusions,
    privacyRule: MetricPrivacyRule.managementProtectedByTrueUnit,
    managementPrivacyUnit: MetricStatisticalUnit.targetProjectRelationship,
    denominator: relationshipStageChangeEvents.reference,
    bucketLabels: ['upward', 'downward'],
  );

  static final catalog = MetricCatalog([
    contactSessions,
    reachedPeople,
    targetResponses,
    interestDistribution,
    channelDistribution,
    interestOrdinalSummary,
    interestLevelRatios,
    interestThreeFourRatio,
    interestZeroRatio,
    targetResponseDistribution,
    targetResponseOrdinalSummary,
    targetResponseLevelRatios,
  ]);

  /// 当前快照定义暂不并入旧的期间目录，避免改变既有页面的固定 12 项合同。
  /// 新页面可显式使用这份目录，保证期间指标与当前快照指标不会被混合。
  static final currentSnapshotCatalog = MetricCatalog([
    currentRelationshipStageCount,
    currentRelationshipStageDistribution,
  ]);

  /// 可选项目指标显式使用的独立目录；不得改变既有 12 项核心合同。
  static final followUpConsentCatalog = MetricCatalog([
    followUpConsentAnswers,
    followUpConsentRatio,
  ]);

  /// 阶段变更是独立的历史事件目录，不混入固定 12 项接触指标。
  static final relationshipStageChangeCatalog = MetricCatalog([
    relationshipStageChangeEvents,
    relationshipsWithStageChange,
    relationshipStageChangeDirectionDistribution,
  ]);

  static List<MetricDefinition> get definitions => catalog.definitions;

  static List<MetricDefinition> get currentSnapshotDefinitions =>
      currentSnapshotCatalog.definitions;

  static List<MetricDefinition> get relationshipStageChangeDefinitions =>
      relationshipStageChangeCatalog.definitions;
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

/// 对象当次反应的五档分布与未填写覆盖。
///
/// [unansweredCount] 只统计当前有效对象关联中没有填写 response 的数量，
/// 不进入 [counts] 的五档分母。独立类型防止兴趣或渠道分布误带对象覆盖语义。
final class TargetResponseDistributionMetricValue extends MetricValue {
  factory TargetResponseDistributionMetricValue({
    required List<String> labels,
    required List<int> counts,
    required int unansweredCount,
  }) {
    if (!_listEquals(labels, _fiveLevelOrdinalLabels) ||
        labels.length != counts.length ||
        counts.any((count) => count < 0) ||
        unansweredCount < 0) {
      throw ArgumentError('invalid_target_response_distribution');
    }
    return TargetResponseDistributionMetricValue._(
      labels: List.unmodifiable(labels),
      counts: List.unmodifiable(counts),
      unansweredCount: unansweredCount,
    );
  }

  const TargetResponseDistributionMetricValue._({
    required this.labels,
    required this.counts,
    required this.unansweredCount,
  });

  final List<String> labels;
  final List<int> counts;
  final int unansweredCount;

  @override
  bool operator ==(Object other) =>
      other is TargetResponseDistributionMetricValue &&
      _listEquals(other.labels, labels) &&
      _listEquals(other.counts, counts) &&
      other.unansweredCount == unansweredCount;

  @override
  int get hashCode => Object.hash(
    Object.hashAll(labels),
    Object.hashAll(counts),
    unansweredCount,
  );
}

/// 五级有序量表的分布及下中位等级。
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

/// 一个比例档位的不可变、可审计值。
///
/// 百分比不会从调用者传入，而是由 [numerator] 和 [denominator] 按整数
/// half-up 规则计算。分母为零时，比例基点为 `null`，而不是 `0`。
final class RatioMetricValueItem {
  factory RatioMetricValueItem({
    required String label,
    required int numerator,
    required int denominator,
    int unknownCount = 0,
    int refusedCount = 0,
    int notApplicableCount = 0,
    int unansweredCount = 0,
    int excludedCount = 0,
  }) {
    if (label.isEmpty ||
        numerator < 0 ||
        denominator < 0 ||
        numerator > denominator ||
        unknownCount < 0 ||
        refusedCount < 0 ||
        notApplicableCount < 0 ||
        unansweredCount < 0 ||
        excludedCount < 0) {
      throw ArgumentError('invalid_metric_ratio_item');
    }
    return RatioMetricValueItem._(
      label: label,
      numerator: numerator,
      denominator: denominator,
      unknownCount: unknownCount,
      refusedCount: refusedCount,
      notApplicableCount: notApplicableCount,
      unansweredCount: unansweredCount,
      excludedCount: excludedCount,
    );
  }

  const RatioMetricValueItem._({
    required this.label,
    required this.numerator,
    required this.denominator,
    required this.unknownCount,
    required this.refusedCount,
    required this.notApplicableCount,
    required this.unansweredCount,
    required this.excludedCount,
  });

  final String label;
  final int numerator;
  final int denominator;
  final int unknownCount;
  final int refusedCount;
  final int notApplicableCount;
  final int unansweredCount;
  final int excludedCount;

  int? get percentageBasisPoints => _ratioBasisPoints(numerator, denominator);

  @override
  bool operator ==(Object other) =>
      other is RatioMetricValueItem &&
      other.label == label &&
      other.numerator == numerator &&
      other.denominator == denominator &&
      other.unknownCount == unknownCount &&
      other.refusedCount == refusedCount &&
      other.notApplicableCount == notApplicableCount &&
      other.unansweredCount == unansweredCount &&
      other.excludedCount == excludedCount;

  @override
  int get hashCode => Object.hash(
    label,
    numerator,
    denominator,
    unknownCount,
    refusedCount,
    notApplicableCount,
    unansweredCount,
    excludedCount,
  );
}

/// 一个不要求穷尽分档的单一子集比例值。
///
/// [numerator] 是带有 [label] 的单一子集数量，[denominator] 是该指标的
/// 共同统计单位总数。不同子集指标可以共享分母，但它们的分子不需要相加
/// 为分母；例如兴趣 `3–4` 和兴趣 `0` 会分别覆盖同一批接触场次的两个子集。
/// 百分比基点由整数分子／分母按 half-up 规则派生，空分母保留 `null`。
final class SubsetRatioMetricValue extends MetricValue {
  factory SubsetRatioMetricValue({
    required String label,
    required int numerator,
    required int denominator,
    int unknownCount = 0,
    int refusedCount = 0,
    int notApplicableCount = 0,
    int unansweredCount = 0,
    int excludedCount = 0,
  }) {
    if (label.trim().isEmpty ||
        numerator < 0 ||
        denominator < 0 ||
        numerator > denominator ||
        unknownCount < 0 ||
        refusedCount < 0 ||
        notApplicableCount < 0 ||
        unansweredCount < 0 ||
        excludedCount < 0) {
      throw ArgumentError('invalid_metric_subset_ratio');
    }
    return SubsetRatioMetricValue._(
      label: label,
      numerator: numerator,
      denominator: denominator,
      unknownCount: unknownCount,
      refusedCount: refusedCount,
      notApplicableCount: notApplicableCount,
      unansweredCount: unansweredCount,
      excludedCount: excludedCount,
    );
  }

  const SubsetRatioMetricValue._({
    required this.label,
    required this.numerator,
    required this.denominator,
    required this.unknownCount,
    required this.refusedCount,
    required this.notApplicableCount,
    required this.unansweredCount,
    required this.excludedCount,
  });

  final String label;
  final int numerator;
  final int denominator;
  final int unknownCount;
  final int refusedCount;
  final int notApplicableCount;
  final int unansweredCount;
  final int excludedCount;

  int? get percentageBasisPoints => _ratioBasisPoints(numerator, denominator);

  @override
  bool operator ==(Object other) =>
      other is SubsetRatioMetricValue &&
      other.label == label &&
      other.numerator == numerator &&
      other.denominator == denominator &&
      other.unknownCount == unknownCount &&
      other.refusedCount == refusedCount &&
      other.notApplicableCount == notApplicableCount &&
      other.unansweredCount == unansweredCount &&
      other.excludedCount == excludedCount;

  @override
  int get hashCode => Object.hash(
    label,
    numerator,
    denominator,
    unknownCount,
    refusedCount,
    notApplicableCount,
    unansweredCount,
    excludedCount,
  );
}

/// 一组穷尽且互斥的分档比例及其覆盖边界。
///
/// [labels] 必须稳定、非空且唯一，全部分子之和必须等于共同 [denominator]。
/// 缺失和排除计数属于这一组比例的透明覆盖元数据；它们
/// 在每个档位条目中以相同值呈现。百分比基点由整数分子／分母派生，不接受
/// 外部传入的基点，因此不能伪造跨层权威值。
final class RatioMetricValue extends MetricValue {
  factory RatioMetricValue.fromCounts({
    required List<String> labels,
    required List<int> counts,
    int unknownCount = 0,
    int refusedCount = 0,
    int notApplicableCount = 0,
    int unansweredCount = 0,
    int excludedCount = 0,
  }) {
    return RatioMetricValue.fromNumerators(
      labels: labels,
      numerators: counts,
      denominator: counts.fold<int>(0, (sum, count) => sum + count),
      unknownCount: unknownCount,
      refusedCount: refusedCount,
      notApplicableCount: notApplicableCount,
      unansweredCount: unansweredCount,
      excludedCount: excludedCount,
    );
  }

  factory RatioMetricValue.fromNumerators({
    required List<String> labels,
    required List<int> numerators,
    required int denominator,
    int unknownCount = 0,
    int refusedCount = 0,
    int notApplicableCount = 0,
    int unansweredCount = 0,
    int excludedCount = 0,
  }) {
    if (labels.isEmpty ||
        labels.length != numerators.length ||
        labels.toSet().length != labels.length ||
        labels.any((label) => label.isEmpty) ||
        denominator < 0 ||
        numerators.any((numerator) => numerator < 0) ||
        numerators.any((numerator) => numerator > denominator) ||
        numerators.fold<int>(0, (sum, numerator) => sum + numerator) !=
            denominator ||
        unknownCount < 0 ||
        refusedCount < 0 ||
        notApplicableCount < 0 ||
        unansweredCount < 0 ||
        excludedCount < 0) {
      throw ArgumentError('invalid_metric_ratio');
    }
    return RatioMetricValue._(
      labels: List.unmodifiable(labels),
      numerators: List.unmodifiable(numerators),
      denominator: denominator,
      unknownCount: unknownCount,
      refusedCount: refusedCount,
      notApplicableCount: notApplicableCount,
      unansweredCount: unansweredCount,
      excludedCount: excludedCount,
    );
  }

  const RatioMetricValue._({
    required this.labels,
    required this.numerators,
    required this.denominator,
    required this.unknownCount,
    required this.refusedCount,
    required this.notApplicableCount,
    required this.unansweredCount,
    required this.excludedCount,
  });

  final List<String> labels;
  final List<int> numerators;
  final int denominator;
  final int unknownCount;
  final int refusedCount;
  final int notApplicableCount;
  final int unansweredCount;
  final int excludedCount;

  /// 每档确定性的百分比基点；空分母时各项均为 `null`。
  List<int?> get basisPoints => List<int?>.unmodifiable(
    numerators.map((numerator) => _ratioBasisPoints(numerator, denominator)),
  );

  List<RatioMetricValueItem> get values =>
      List<RatioMetricValueItem>.unmodifiable(
        List<RatioMetricValueItem>.generate(
          labels.length,
          (index) => RatioMetricValueItem._(
            label: labels[index],
            numerator: numerators[index],
            denominator: denominator,
            unknownCount: unknownCount,
            refusedCount: refusedCount,
            notApplicableCount: notApplicableCount,
            unansweredCount: unansweredCount,
            excludedCount: excludedCount,
          ),
        ),
      );

  @override
  bool operator ==(Object other) =>
      other is RatioMetricValue &&
      _listEquals(other.labels, labels) &&
      _listEquals(other.numerators, numerators) &&
      other.denominator == denominator &&
      other.unknownCount == unknownCount &&
      other.refusedCount == refusedCount &&
      other.notApplicableCount == notApplicableCount &&
      other.unansweredCount == unansweredCount &&
      other.excludedCount == excludedCount;

  @override
  int get hashCode => Object.hash(
    Object.hashAll(labels),
    Object.hashAll(numerators),
    denominator,
    unknownCount,
    refusedCount,
    notApplicableCount,
    unansweredCount,
    excludedCount,
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
    int? pendingCount,
  }) {
    if (totalCount < 0 ||
        pendingCount != null &&
            (pendingCount < 0 || pendingCount > totalCount)) {
      throw ArgumentError('invalid_metric_sync_coverage');
    }
    return MetricSyncCoverage._(statisticalUnit, totalCount, pendingCount);
  }

  factory MetricSyncCoverage.unknown({
    required MetricStatisticalUnit statisticalUnit,
  }) => MetricSyncCoverage._(statisticalUnit, null, null);

  const MetricSyncCoverage._(
    this.statisticalUnit,
    this.totalCount,
    this.pendingCount,
  );

  final MetricStatisticalUnit statisticalUnit;
  final int? totalCount;
  final int? pendingCount;

  bool get isKnown => totalCount != null && pendingCount != null;

  int? get synchronizedCount => isKnown ? totalCount! - pendingCount! : null;
}

/// 当前快照结果的来源新鲜度；它与 [snapshotAsOfUtc] 是两个不同的时刻。
enum MetricFreshnessStatus { fresh, stale, unknown }

final class MetricSourceFreshness {
  const MetricSourceFreshness({
    required this.status,
    this.sourceDataCutoffUtc,
    this.authorizedAtUtc,
    this.lastSuccessfulSyncAtUtc,
  });

  const MetricSourceFreshness.unknown()
    : this(status: MetricFreshnessStatus.unknown);

  const MetricSourceFreshness.fresh({
    DateTime? sourceDataCutoffUtc,
    DateTime? authorizedAtUtc,
    DateTime? lastSuccessfulSyncAtUtc,
  }) : this(
         status: MetricFreshnessStatus.fresh,
         sourceDataCutoffUtc: sourceDataCutoffUtc,
         authorizedAtUtc: authorizedAtUtc,
         lastSuccessfulSyncAtUtc: lastSuccessfulSyncAtUtc,
       );

  const MetricSourceFreshness.stale({
    DateTime? sourceDataCutoffUtc,
    DateTime? authorizedAtUtc,
    DateTime? lastSuccessfulSyncAtUtc,
  }) : this(
         status: MetricFreshnessStatus.stale,
         sourceDataCutoffUtc: sourceDataCutoffUtc,
         authorizedAtUtc: authorizedAtUtc,
         lastSuccessfulSyncAtUtc: lastSuccessfulSyncAtUtc,
       );

  final MetricFreshnessStatus status;
  final DateTime? sourceDataCutoffUtc;
  final DateTime? authorizedAtUtc;
  final DateTime? lastSuccessfulSyncAtUtc;
}

/// Identifies the trusted personal scope of a metric observation.
final class PersonalMetricScope {
  factory PersonalMetricScope({
    required String appUserId,
    required String workspaceId,
    required String projectId,
  }) {
    if (appUserId.trim().isEmpty ||
        workspaceId.trim().isEmpty ||
        projectId.trim().isEmpty) {
      throw ArgumentError('invalid_personal_metric_scope');
    }
    return PersonalMetricScope._(
      appUserId: appUserId,
      workspaceId: workspaceId,
      projectId: projectId,
    );
  }

  const PersonalMetricScope._({
    required this.appUserId,
    required this.workspaceId,
    required this.projectId,
  });

  final String appUserId;
  final String workspaceId;
  final String projectId;

  @override
  bool operator ==(Object other) =>
      other is PersonalMetricScope &&
      other.appUserId == appUserId &&
      other.workspaceId == workspaceId &&
      other.projectId == projectId;

  @override
  int get hashCode => Object.hash(appUserId, workspaceId, projectId);
}

/// 一个可审计、可跨层传递的指标结果。
final class MetricResult {
  factory MetricResult({
    required MetricDefinition definition,
    required MetricValue value,
    required MetricPeriod period,
    required String timeZone,
    required DateTime? dataCutoffUtc,
    DateTime? retrievedAtUtc,
    required MetricSourceTier sourceTier,
    MetricSyncCoverage? syncCoverage,
    required MetricPrivacyStatus privacyStatus,
  }) {
    if (timeZone.trim().isEmpty ||
        dataCutoffUtc != null && !dataCutoffUtc.isUtc ||
        retrievedAtUtc != null && !retrievedAtUtc.isUtc ||
        dataCutoffUtc == null &&
            (sourceTier != MetricSourceTier.backendOperational ||
                privacyStatus != MetricPrivacyStatus.personalFact ||
                retrievedAtUtc == null)) {
      throw ArgumentError('invalid_metric_result_metadata');
    }
    final isSuppressedValue = value is SuppressedMetricValue;
    final personalFactSourceAllowed =
        sourceTier == MetricSourceTier.localOperational ||
        sourceTier == MetricSourceTier.backendOperational;
    if ((privacyStatus == MetricPrivacyStatus.suppressed) !=
            isSuppressedValue ||
        (sourceTier == MetricSourceTier.localOperational) !=
            (syncCoverage != null) ||
        privacyStatus == MetricPrivacyStatus.personalFact &&
            !personalFactSourceAllowed) {
      throw ArgumentError('invalid_metric_result_state');
    }
    if (!isSuppressedValue) _validateValue(definition, value);
    return MetricResult._(
      definition: definition,
      value: value,
      period: period,
      timeZone: timeZone,
      dataCutoffUtc: dataCutoffUtc,
      retrievedAtUtc: retrievedAtUtc,
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
    required this.retrievedAtUtc,
    required this.sourceTier,
    required this.syncCoverage,
    required this.privacyStatus,
  });

  final MetricDefinition definition;
  final MetricValue value;
  final MetricPeriod period;
  final String timeZone;

  /// 可信来源截止点；动态 Backend 合同未返回该值时为 null。
  ///
  /// 调用方不得用客户端收包时间代替截止点；此时应填写 [retrievedAtUtc]。
  final DateTime? dataCutoffUtc;
  final DateTime? retrievedAtUtc;
  final MetricSourceTier sourceTier;
  final MetricSyncCoverage? syncCoverage;
  final MetricPrivacyStatus privacyStatus;

  /// 为不强制使用接触期间的调用方提供当前快照结果。
  ///
  /// 旧的 [MetricResult] 构造器仍然只接受 [MetricPeriod]；新指标使用这个
  /// 工厂得到 [CurrentSnapshotMetricResult]，因而不会把快照时刻伪装成期间。
  static CurrentSnapshotMetricResult currentSnapshot({
    required MetricDefinition definition,
    required MetricValue value,
    required DateTime snapshotAsOfUtc,
    required String timeZone,
    DateTime? sourceDataCutoffUtc,
    MetricSourceFreshness freshness = const MetricSourceFreshness.unknown(),
    required MetricSourceTier sourceTier,
    MetricSyncCoverage? syncCoverage,
    required MetricPrivacyStatus privacyStatus,
  }) => CurrentSnapshotMetricResult(
    definition: definition,
    value: value,
    snapshotAsOfUtc: snapshotAsOfUtc,
    timeZone: timeZone,
    sourceDataCutoffUtc: sourceDataCutoffUtc,
    freshness: freshness,
    sourceTier: sourceTier,
    syncCoverage: syncCoverage,
    privacyStatus: privacyStatus,
  );

  static void _validateValue(MetricDefinition definition, MetricValue value) {
    final shapeMatches = switch (definition.valueShape) {
      MetricValueShape.count => value is CountMetricValue,
      MetricValueShape.ordinalDistribution ||
      MetricValueShape.categoricalDistribution =>
        definition.formula == MetricFormula.countContactTargetLinksByResponse
            ? value is TargetResponseDistributionMetricValue
            : value is MetricDistributionValue,
      MetricValueShape.ordinalSummary => value is OrdinalSummaryMetricValue,
      MetricValueShape.ratio => value is RatioMetricValue,
      MetricValueShape.subsetRatio => value is SubsetRatioMetricValue,
    };
    if (!shapeMatches) {
      throw ArgumentError('metric_value_shape_mismatch');
    }
    if (value is MetricDistributionValue &&
        !_listEquals(value.labels, definition.bucketLabels)) {
      throw ArgumentError('metric_distribution_labels_mismatch');
    }
    if (value is TargetResponseDistributionMetricValue &&
        !_listEquals(value.labels, definition.bucketLabels)) {
      throw ArgumentError('metric_distribution_labels_mismatch');
    }
    if (value is OrdinalSummaryMetricValue &&
        !_listEquals(value.labels, definition.bucketLabels)) {
      throw ArgumentError('metric_ordinal_summary_labels_mismatch');
    }
    if (value is RatioMetricValue &&
        !_listEquals(value.labels, definition.bucketLabels)) {
      throw ArgumentError('metric_ratio_labels_mismatch');
    }
    if (value is SubsetRatioMetricValue &&
        (definition.bucketLabels.length != 1 ||
            value.label != definition.bucketLabels.single)) {
      throw ArgumentError('metric_subset_ratio_label_mismatch');
    }
  }
}

/// 不带 [MetricPeriod] 的当前快照指标结果。
///
/// [snapshotAsOfUtc] 只表示一致性读取判断当前状态的时刻；[freshness] 说明
/// 来源数据和授权是否新鲜。两者必须由调用方分别展示。
final class CurrentSnapshotMetricResult {
  factory CurrentSnapshotMetricResult({
    required MetricDefinition definition,
    required MetricValue value,
    required DateTime snapshotAsOfUtc,
    required String timeZone,
    DateTime? sourceDataCutoffUtc,
    MetricSourceFreshness freshness = const MetricSourceFreshness.unknown(),
    required MetricSourceTier sourceTier,
    MetricSyncCoverage? syncCoverage,
    required MetricPrivacyStatus privacyStatus,
  }) {
    if (definition.timeBasis != MetricTimeBasis.currentSnapshotUtc ||
        timeZone.trim().isEmpty ||
        !snapshotAsOfUtc.isUtc ||
        sourceDataCutoffUtc != null && !sourceDataCutoffUtc.isUtc ||
        freshness.sourceDataCutoffUtc != null &&
            sourceDataCutoffUtc != null &&
            freshness.sourceDataCutoffUtc != sourceDataCutoffUtc) {
      throw ArgumentError('invalid_current_snapshot_metric_metadata');
    }
    final isSuppressedValue = value is SuppressedMetricValue;
    if ((privacyStatus == MetricPrivacyStatus.suppressed) !=
            isSuppressedValue ||
        (sourceTier == MetricSourceTier.localOperational) !=
            (syncCoverage != null) ||
        privacyStatus == MetricPrivacyStatus.personalFact &&
            sourceTier != MetricSourceTier.localOperational) {
      throw ArgumentError('invalid_current_snapshot_metric_state');
    }
    if (!isSuppressedValue) {
      MetricResult._validateValue(definition, value);
    }
    return CurrentSnapshotMetricResult._(
      definition: definition,
      value: value,
      snapshotAsOfUtc: snapshotAsOfUtc,
      timeZone: timeZone,
      sourceDataCutoffUtc: sourceDataCutoffUtc,
      freshness: freshness,
      sourceTier: sourceTier,
      syncCoverage: syncCoverage,
      privacyStatus: privacyStatus,
    );
  }

  const CurrentSnapshotMetricResult._({
    required this.definition,
    required this.value,
    required this.snapshotAsOfUtc,
    required this.timeZone,
    required this.sourceDataCutoffUtc,
    required this.freshness,
    required this.sourceTier,
    required this.syncCoverage,
    required this.privacyStatus,
  });

  final MetricDefinition definition;
  final MetricValue value;
  final DateTime snapshotAsOfUtc;
  final String timeZone;
  final DateTime? sourceDataCutoffUtc;
  final MetricSourceFreshness freshness;
  final MetricSourceTier sourceTier;
  final MetricSyncCoverage? syncCoverage;
  final MetricPrivacyStatus privacyStatus;
}

/// 简短别名，便于页面和仓储代码表达“当前指标”而不混入期间术语。
typedef CurrentMetricResult = CurrentSnapshotMetricResult;

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

int? _ratioBasisPoints(int numerator, int denominator) {
  if (denominator == 0) return null;
  // BigInt keeps the contract exact on Web when an int exceeds JS safe range.
  final doubleScaledNumerator = BigInt.from(numerator) * BigInt.from(20000);
  final bigDenominator = BigInt.from(denominator);
  return ((doubleScaledNumerator + bigDenominator) ~/
          (bigDenominator * BigInt.from(2)))
      .toInt();
}

bool _usesDenominatorFormula(
  MetricFormula formula,
  MetricFormula denominatorFormula,
) => switch (formula) {
  MetricFormula.countContactSessionsByInterest ||
  MetricFormula.countContactSessionsByChannel ||
  MetricFormula.summarizeContactSessionsByInterest ||
  MetricFormula.calculateContactSessionsByInterestRatio ||
  MetricFormula.calculateContactSessionsByInterestSubsetRatio =>
    denominatorFormula == MetricFormula.countContactSessions,
  MetricFormula.countContactTargetLinksByResponse =>
    denominatorFormula == MetricFormula.countContactTargetLinksWithResponse,
  MetricFormula.summarizeContactTargetLinksByResponse ||
  MetricFormula.calculateContactTargetLinksByResponseRatio =>
    denominatorFormula == MetricFormula.countContactTargetLinksWithResponse,
  MetricFormula.calculateContactTargetLinksByFollowUpConsentRatio =>
    denominatorFormula ==
        MetricFormula.countContactTargetLinksWithFollowUpConsentAnswer,
  MetricFormula.countCurrentRelationshipStagesByStage =>
    denominatorFormula == MetricFormula.countCurrentRelationshipStages,
  MetricFormula.countRelationshipStageChangeEventsByDirection =>
    denominatorFormula == MetricFormula.countRelationshipStageChangeEvents,
  MetricFormula.countContactSessions ||
  MetricFormula.sumReachedPeople ||
  MetricFormula.countContactTargetLinksWithResponse ||
  MetricFormula.countContactTargetLinksWithFollowUpConsentAnswer ||
  MetricFormula.countCurrentRelationshipStages ||
  MetricFormula.countRelationshipStageChangeEvents ||
  MetricFormula.countDistinctRelationshipsWithStageChange => false,
};

bool _listEquals<T>(List<T> left, List<T> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) return false;
  }
  return true;
}
