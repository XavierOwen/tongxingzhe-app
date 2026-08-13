import 'package:flutter_test/flutter_test.dart';
import 'package:tongxingzhe_app/features/contact_metrics/metric_contract.dart';

void main() {
  test('核心指标目录使用唯一且不可变的版本标识', () {
    expect(CoreMetricCatalog.definitions, hasLength(12));
    expect(
      CoreMetricCatalog.definitions
          .map((definition) => definition.reference)
          .toSet(),
      {
        const MetricReference('contact_sessions', 1),
        const MetricReference('reached_people', 1),
        const MetricReference('target_responses', 1),
        const MetricReference('interest_distribution', 1),
        const MetricReference('interest_ordinal_summary', 1),
        const MetricReference('interest_level_ratios', 1),
        const MetricReference('interest_3_4_ratio', 1),
        const MetricReference('interest_0_ratio', 1),
        const MetricReference('channel_distribution', 1),
        const MetricReference('target_response_distribution', 1),
        const MetricReference('target_response_ordinal_summary', 1),
        const MetricReference('target_response_level_ratios', 1),
      },
    );
    expect(
      CoreMetricCatalog.interestDistribution.statisticalUnit,
      MetricStatisticalUnit.contactSession,
    );
    expect(
      CoreMetricCatalog.interestDistribution.denominator,
      CoreMetricCatalog.contactSessions.reference,
    );
    expect(
      CoreMetricCatalog.interestOrdinalSummary.valueShape,
      MetricValueShape.ordinalSummary,
    );
    expect(
      CoreMetricCatalog.interestOrdinalSummary.formula,
      MetricFormula.summarizeContactSessionsByInterest,
    );
    expect(
      CoreMetricCatalog.interestOrdinalSummary.denominator,
      CoreMetricCatalog.contactSessions.reference,
    );
    expect(
      CoreMetricCatalog.interestLevelRatios.valueShape,
      MetricValueShape.ratio,
    );
    expect(
      CoreMetricCatalog.interestLevelRatios.formula,
      MetricFormula.calculateContactSessionsByInterestRatio,
    );
    expect(
      CoreMetricCatalog.interestLevelRatios.denominator,
      CoreMetricCatalog.contactSessions.reference,
    );
    expect(CoreMetricCatalog.interestLevelRatios.bucketLabels, [
      '0',
      '1',
      '2',
      '3',
      '4',
    ]);
    expect(
      CoreMetricCatalog.interestThreeFourRatio.valueShape,
      MetricValueShape.subsetRatio,
    );
    expect(
      CoreMetricCatalog.interestThreeFourRatio.formula,
      MetricFormula.calculateContactSessionsByInterestSubsetRatio,
    );
    expect(
      CoreMetricCatalog.interestThreeFourRatio.denominator,
      CoreMetricCatalog.contactSessions.reference,
    );
    expect(CoreMetricCatalog.interestThreeFourRatio.bucketLabels, ['3_4']);
    expect(
      CoreMetricCatalog.interestZeroRatio.valueShape,
      MetricValueShape.subsetRatio,
    );
    expect(
      CoreMetricCatalog.interestZeroRatio.formula,
      MetricFormula.calculateContactSessionsByInterestSubsetRatio,
    );
    expect(
      CoreMetricCatalog.interestZeroRatio.denominator,
      CoreMetricCatalog.contactSessions.reference,
    );
    expect(CoreMetricCatalog.interestZeroRatio.bucketLabels, ['0']);
    expect(
      CoreMetricCatalog.reachedPeople.statisticalUnit,
      MetricStatisticalUnit.reachedPerson,
    );
    expect(
      CoreMetricCatalog.targetResponses.statisticalUnit,
      MetricStatisticalUnit.contactTargetLink,
    );
    expect(
      CoreMetricCatalog.targetResponses.formula,
      MetricFormula.countContactTargetLinksWithResponse,
    );
    expect(
      CoreMetricCatalog.targetResponseDistribution.statisticalUnit,
      MetricStatisticalUnit.contactTargetLink,
    );
    expect(
      CoreMetricCatalog.targetResponseDistribution.formula,
      MetricFormula.countContactTargetLinksByResponse,
    );
    expect(
      CoreMetricCatalog.targetResponseDistribution.denominator,
      CoreMetricCatalog.targetResponses.reference,
    );
    expect(
      CoreMetricCatalog.targetResponseOrdinalSummary.formula,
      MetricFormula.summarizeContactTargetLinksByResponse,
    );
    expect(
      CoreMetricCatalog.targetResponseOrdinalSummary.denominator,
      CoreMetricCatalog.targetResponses.reference,
    );
    expect(
      CoreMetricCatalog.targetResponseLevelRatios.valueShape,
      MetricValueShape.ratio,
    );
    expect(
      CoreMetricCatalog.targetResponseLevelRatios.formula,
      MetricFormula.calculateContactTargetLinksByResponseRatio,
    );
    expect(
      CoreMetricCatalog.targetResponseLevelRatios.denominator,
      CoreMetricCatalog.targetResponses.reference,
    );
    expect(CoreMetricCatalog.targetResponseLevelRatios.bucketLabels, [
      '0',
      '1',
      '2',
      '3',
      '4',
    ]);
    expect(
      CoreMetricCatalog.definitions.every(
        (definition) =>
            definition.exclusions.contains(MetricExclusion.draft) &&
            definition.exclusions.contains(MetricExclusion.contactAttempt) &&
            definition.exclusions.contains(MetricExclusion.voidedContact),
      ),
      isTrue,
    );
    expect(
      () =>
          CoreMetricCatalog.definitions.add(CoreMetricCatalog.contactSessions),
      throwsUnsupportedError,
    );
    expect(
      () => MetricCatalog([
        CoreMetricCatalog.contactSessions,
        CoreMetricCatalog.contactSessions,
      ]),
      throwsArgumentError,
    );
  });

  test('指标目录拒绝悬空或口径不一致的分母', () {
    MetricDefinition distribution(
      MetricReference denominator, {
      Set<MetricExclusion> exclusions = const {MetricExclusion.voidedContact},
    }) => MetricDefinition(
      reference: const MetricReference('test_distribution', 1),
      statisticalUnit: MetricStatisticalUnit.contactTargetLink,
      valueShape: MetricValueShape.ordinalDistribution,
      formula: MetricFormula.countContactTargetLinksByResponse,
      timeBasis: MetricTimeBasis.actualOccurrenceUtc,
      exclusions: exclusions,
      privacyRule: MetricPrivacyRule.managementProtectedByTrueUnit,
      denominator: denominator,
      bucketLabels: const ['0', '1', '2', '3', '4'],
    );

    expect(
      () => MetricCatalog([distribution(const MetricReference('missing', 1))]),
      throwsArgumentError,
    );
    expect(
      () => MetricCatalog([
        CoreMetricCatalog.contactSessions,
        distribution(CoreMetricCatalog.contactSessions.reference),
      ]),
      throwsArgumentError,
    );
    final denominator = MetricDefinition(
      reference: const MetricReference('target_response_denominator', 1),
      statisticalUnit: MetricStatisticalUnit.contactTargetLink,
      valueShape: MetricValueShape.count,
      formula: MetricFormula.countContactTargetLinksWithResponse,
      timeBasis: MetricTimeBasis.actualOccurrenceUtc,
      exclusions: const {MetricExclusion.draft},
      privacyRule: MetricPrivacyRule.managementProtectedByTrueUnit,
    );
    expect(
      () => MetricCatalog([denominator, distribution(denominator.reference)]),
      throwsArgumentError,
    );
    final wrongFormulaDenominator = MetricDefinition(
      reference: const MetricReference('wrong_formula_denominator', 1),
      statisticalUnit: MetricStatisticalUnit.contactTargetLink,
      valueShape: MetricValueShape.count,
      formula: MetricFormula.countContactSessions,
      timeBasis: MetricTimeBasis.actualOccurrenceUtc,
      exclusions: const {MetricExclusion.voidedContact},
      privacyRule: MetricPrivacyRule.managementProtectedByTrueUnit,
    );
    expect(
      () => MetricCatalog([
        wrongFormulaDenominator,
        distribution(wrongFormulaDenominator.reference),
      ]),
      throwsArgumentError,
    );
  });

  test('个人兴趣有序汇总使用奇偶下中位并保留空期间 null', () {
    final odd = OrdinalSummaryMetricValue.fromCounts(
      labels: const ['0', '1', '2', '3', '4'],
      counts: const [1, 1, 3, 0, 0],
    );
    final even = OrdinalSummaryMetricValue.fromCounts(
      labels: const ['0', '1', '2', '3', '4'],
      counts: const [1, 1, 2, 0, 0],
    );
    final empty = OrdinalSummaryMetricValue.fromCounts(
      labels: const ['0', '1', '2', '3', '4'],
      counts: const [0, 0, 0, 0, 0],
    );

    expect(odd.totalCount, 5);
    expect(odd.medianLevel, 2);
    expect(even.medianLevel, 1);
    expect(empty.medianLevel, isNull);
    expect(empty.counts, [0, 0, 0, 0, 0]);
    expect(
      MetricResult(
        definition: CoreMetricCatalog.interestOrdinalSummary,
        value: odd,
        period: _period,
        timeZone: 'UTC',
        dataCutoffUtc: DateTime.utc(2030, 1, 8, 18),
        sourceTier: MetricSourceTier.localOperational,
        syncCoverage: _coverage,
        privacyStatus: MetricPrivacyStatus.personalFact,
      ).value,
      odd,
    );
  });

  test('个人兴趣有序汇总严格校验总数、中位和空值', () {
    expect(
      () => OrdinalSummaryMetricValue(
        labels: const ['0', '1', '2', '3', '4'],
        counts: const [1, 1, 2, 0, 0],
        totalCount: 5,
        medianLevel: 1,
      ),
      throwsArgumentError,
    );
    expect(
      () => OrdinalSummaryMetricValue(
        labels: const ['0', '1', '2', '3', '4'],
        counts: const [1, 1, 2, 0, 0],
        totalCount: 4,
        medianLevel: 2,
      ),
      throwsArgumentError,
    );
    expect(
      () => OrdinalSummaryMetricValue(
        labels: const ['0', '1', '2', '3', '4'],
        counts: const [0, 0, 0, 0, 0],
        totalCount: 0,
        medianLevel: 0,
      ),
      throwsArgumentError,
    );
    expect(
      () => OrdinalSummaryMetricValue(
        labels: const ['0', '1', '2', '3', '4'],
        counts: const [1, 1, -1, 0, 0],
        totalCount: 1,
        medianLevel: 0,
      ),
      throwsArgumentError,
    );
  });

  test('对象反应分布保留未填写关联且拒绝负覆盖数', () {
    final distribution = TargetResponseDistributionMetricValue(
      labels: const ['0', '1', '2', '3', '4'],
      counts: const [1, 0, 0, 0, 1],
      unansweredCount: 2,
    );

    expect(distribution.unansweredCount, 2);
    expect(
      MetricResult(
        definition: CoreMetricCatalog.targetResponseDistribution,
        value: distribution,
        period: _period,
        timeZone: 'UTC',
        dataCutoffUtc: DateTime.utc(2030, 1, 8, 18),
        sourceTier: MetricSourceTier.localOperational,
        syncCoverage: _coverage,
        privacyStatus: MetricPrivacyStatus.personalFact,
      ).value,
      distribution,
    );
    expect(
      () => TargetResponseDistributionMetricValue(
        labels: const ['0', '1', '2', '3', '4'],
        counts: const [0, 0, 0, 0, 0],
        unansweredCount: -1,
      ),
      throwsArgumentError,
    );
    expect(
      () => MetricResult(
        definition: CoreMetricCatalog.interestDistribution,
        value: distribution,
        period: _period,
        timeZone: 'UTC',
        dataCutoffUtc: DateTime.utc(2030, 1, 8, 18),
        sourceTier: MetricSourceTier.localOperational,
        syncCoverage: _coverage,
        privacyStatus: MetricPrivacyStatus.personalFact,
      ),
      throwsArgumentError,
    );
    expect(
      () => MetricResult(
        definition: CoreMetricCatalog.targetResponseDistribution,
        value: MetricDistributionValue(
          labels: const ['0', '1', '2', '3', '4'],
          counts: const [1, 0, 0, 0, 1],
        ),
        period: _period,
        timeZone: 'UTC',
        dataCutoffUtc: DateTime.utc(2030, 1, 8, 18),
        sourceTier: MetricSourceTier.localOperational,
        syncCoverage: _coverage,
        privacyStatus: MetricPrivacyStatus.personalFact,
      ),
      throwsArgumentError,
    );
  });

  test('对象反应有序汇总只按已填写关联计算下中位', () {
    final even = OrdinalSummaryMetricValue.fromCounts(
      labels: const ['0', '1', '2', '3', '4'],
      counts: const [1, 0, 0, 0, 1],
    );
    final odd = OrdinalSummaryMetricValue.fromCounts(
      labels: const ['0', '1', '2', '3', '4'],
      counts: const [0, 1, 2, 0, 0],
    );
    final empty = OrdinalSummaryMetricValue.fromCounts(
      labels: const ['0', '1', '2', '3', '4'],
      counts: const [0, 0, 0, 0, 0],
    );

    expect(even.totalCount, 2);
    expect(even.medianLevel, 0);
    expect(odd.totalCount, 3);
    expect(odd.medianLevel, 2);
    expect(empty.totalCount, 0);
    expect(empty.medianLevel, isNull);
    expect(
      MetricResult(
        definition: CoreMetricCatalog.targetResponseOrdinalSummary,
        value: even,
        period: _period,
        timeZone: 'UTC',
        dataCutoffUtc: DateTime.utc(2030, 1, 8, 18),
        sourceTier: MetricSourceTier.localOperational,
        syncCoverage: _coverage,
        privacyStatus: MetricPrivacyStatus.personalFact,
      ).value,
      even,
    );
  });

  test('个人兴趣比例以五档共同分母生成整数 half-up 基点', () {
    final ratios = RatioMetricValue.fromNumerators(
      labels: const ['0', '1', '2', '3', '4'],
      numerators: const [1, 0, 0, 1, 1],
      denominator: 3,
      unknownCount: 0,
      refusedCount: 0,
      notApplicableCount: 0,
      unansweredCount: 0,
      excludedCount: 0,
    );

    expect(ratios.numerators, [1, 0, 0, 1, 1]);
    expect(ratios.denominator, 3);
    expect(ratios.basisPoints, [3333, 0, 0, 3333, 3333]);
    expect(ratios.unknownCount, 0);
    expect(ratios.refusedCount, 0);
    expect(ratios.notApplicableCount, 0);
    expect(ratios.unansweredCount, 0);
    expect(ratios.excludedCount, 0);
    expect(ratios.values, hasLength(5));
    expect(ratios.values[0].numerator, 1);
    expect(ratios.values[0].denominator, 3);
    expect(ratios.values[0].percentageBasisPoints, 3333);
    expect(ratios.values[0].unknownCount, 0);
    expect(ratios.values[0].excludedCount, 0);
    expect(
      MetricResult(
        definition: CoreMetricCatalog.interestLevelRatios,
        value: ratios,
        period: _period,
        timeZone: 'UTC',
        dataCutoffUtc: DateTime.utc(2030, 1, 8, 18),
        sourceTier: MetricSourceTier.localOperational,
        syncCoverage: _coverage,
        privacyStatus: MetricPrivacyStatus.personalFact,
      ).value,
      ratios,
    );
  });

  test('个人兴趣比例空分母保留 null，并由整数推导半上舍入', () {
    final empty = RatioMetricValue.fromCounts(
      labels: const ['0', '1', '2', '3', '4'],
      counts: const [0, 0, 0, 0, 0],
    );
    final tie = RatioMetricValue.fromNumerators(
      labels: const ['0', '1', '2', '3', '4'],
      numerators: const [2, 62, 0, 0, 0],
      denominator: 64,
    );

    expect(empty.denominator, 0);
    expect(empty.numerators, [0, 0, 0, 0, 0]);
    expect(empty.basisPoints, [null, null, null, null, null]);
    expect(tie.basisPoints, [313, 9688, 0, 0, 0]);
  });

  test('对象反应五档比例只用已填写关联作共同分母', () {
    final ratios = RatioMetricValue.fromCounts(
      labels: const ['0', '1', '2', '3', '4'],
      counts: const [2, 1, 2, 2, 2],
      unansweredCount: 3,
    );

    expect(ratios.numerators, [2, 1, 2, 2, 2]);
    expect(ratios.denominator, 9);
    expect(ratios.basisPoints, [2222, 1111, 2222, 2222, 2222]);
    expect(ratios.unansweredCount, 3);
    expect(
      MetricResult(
        definition: CoreMetricCatalog.targetResponseLevelRatios,
        value: ratios,
        period: _period,
        timeZone: 'UTC',
        dataCutoffUtc: DateTime.utc(2030, 1, 8, 18),
        sourceTier: MetricSourceTier.localOperational,
        syncCoverage: _coverage,
        privacyStatus: MetricPrivacyStatus.personalFact,
      ).value,
      ratios,
    );
  });

  test('个人兴趣比例拒绝负数、越界、标签错位和非共同分母', () {
    expect(
      () => RatioMetricValue.fromNumerators(
        labels: const ['0', '1', '2', '3', '4'],
        numerators: const [-1, 1, 0, 0, 0],
        denominator: 0,
      ),
      throwsArgumentError,
    );
    expect(
      () => RatioMetricValue.fromNumerators(
        labels: const ['0', '1', '2', '3', '4'],
        numerators: const [2, 1, 0, 0, 0],
        denominator: 2,
      ),
      throwsArgumentError,
    );
    expect(
      () => RatioMetricValue.fromNumerators(
        labels: const ['0', '1', '2', '3', '3'],
        numerators: const [1, 0, 0, 0, 0],
        denominator: 1,
      ),
      throwsArgumentError,
    );
    expect(
      () => RatioMetricValue.fromNumerators(
        labels: const ['0', '1', '2', '3', '4'],
        numerators: const [1, 0, 0, 0, 0],
        denominator: 1,
        unknownCount: -1,
      ),
      throwsArgumentError,
    );
    expect(
      () => RatioMetricValue.fromNumerators(
        labels: const ['0', '1', '2', '3', '4'],
        numerators: const [0, 0, 0, 0, 0],
        denominator: 0,
      ).numerators.add(1),
      throwsUnsupportedError,
    );
  });

  test('个人兴趣子集比例允许独立分子并使用整数 half-up 基点', () {
    // Inputs remain exactly representable on Web, while numerator * 20000
    // exceeds the JavaScript safe-integer range and requires BigInt math.
    const nearWebSafeScale = (1 << 47) - 1;
    final highInterest = SubsetRatioMetricValue(
      label: '3_4',
      numerator: 2,
      denominator: 5,
    );
    final rejection = SubsetRatioMetricValue(
      label: '0',
      numerator: 1,
      denominator: 5,
    );

    expect(highInterest.numerator, 2);
    expect(highInterest.denominator, 5);
    expect(highInterest.percentageBasisPoints, 4000);
    expect(rejection.percentageBasisPoints, 2000);
    expect(
      SubsetRatioMetricValue(
        label: '3_4',
        numerator: 2,
        denominator: 3,
      ).percentageBasisPoints,
      6667,
    );
    expect(
      SubsetRatioMetricValue(
        label: '3_4',
        numerator: 2 * nearWebSafeScale,
        denominator: 64 * nearWebSafeScale,
      ).percentageBasisPoints,
      313,
    );
    // These are independent subsets; their values do not form one exhaustive
    // distribution and therefore do not need to sum to a shared denominator.
    expect(
      highInterest.numerator + rejection.numerator,
      lessThan(highInterest.denominator),
    );
    expect(highInterest.label, '3_4');
    expect(
      MetricResult(
        definition: CoreMetricCatalog.interestThreeFourRatio,
        value: highInterest,
        period: _period,
        timeZone: 'UTC',
        dataCutoffUtc: DateTime.utc(2030, 1, 8, 18),
        sourceTier: MetricSourceTier.localOperational,
        syncCoverage: _coverage,
        privacyStatus: MetricPrivacyStatus.personalFact,
      ).value,
      highInterest,
    );
  });

  test('个人兴趣子集比例拒绝非法覆盖、标签和空分母状态', () {
    expect(
      () => SubsetRatioMetricValue(label: '', numerator: 0, denominator: 1),
      throwsArgumentError,
    );
    expect(
      () => SubsetRatioMetricValue(label: '3_4', numerator: 2, denominator: 1),
      throwsArgumentError,
    );
    expect(
      () => SubsetRatioMetricValue(
        label: '3_4',
        numerator: 0,
        denominator: 0,
      ).percentageBasisPoints,
      returnsNormally,
    );
    expect(
      SubsetRatioMetricValue(
        label: '3_4',
        numerator: 0,
        denominator: 0,
      ).percentageBasisPoints,
      isNull,
    );
    expect(
      () => SubsetRatioMetricValue(label: '3_4', numerator: 1, denominator: 0),
      throwsArgumentError,
    );
    expect(
      () => SubsetRatioMetricValue(
        label: '3_4',
        numerator: 0,
        denominator: 1,
        unknownCount: -1,
      ),
      throwsArgumentError,
    );
    expect(
      () => SubsetRatioMetricValue(
        label: '3_4',
        numerator: 0,
        denominator: 1,
        refusedCount: -1,
      ),
      throwsArgumentError,
    );
    expect(
      () => SubsetRatioMetricValue(
        label: '3_4',
        numerator: 0,
        denominator: 1,
        notApplicableCount: -1,
      ),
      throwsArgumentError,
    );
    expect(
      () => SubsetRatioMetricValue(
        label: '3_4',
        numerator: 0,
        denominator: 1,
        unansweredCount: -1,
      ),
      throwsArgumentError,
    );
    expect(
      () => SubsetRatioMetricValue(
        label: '3_4',
        numerator: 0,
        denominator: 1,
        excludedCount: -1,
      ),
      throwsArgumentError,
    );
  });

  test('指标结果拒绝错误值形状、期间、截止时间与同步覆盖', () {
    expect(
      () => MetricResult(
        definition: CoreMetricCatalog.interestDistribution,
        value: CountMetricValue(2),
        period: _period,
        timeZone: 'UTC',
        dataCutoffUtc: DateTime.utc(2030, 1, 8, 18),
        sourceTier: MetricSourceTier.localOperational,
        syncCoverage: _coverage,
        privacyStatus: MetricPrivacyStatus.personalFact,
      ),
      throwsArgumentError,
    );
    expect(() => CountMetricValue(-1), throwsArgumentError);
    expect(
      () => MetricDistributionValue(
        labels: const ['0', '1'],
        counts: const [1, -1],
      ),
      throwsArgumentError,
    );
    expect(
      () => MetricResult(
        definition: CoreMetricCatalog.interestLevelRatios,
        value: CountMetricValue(2),
        period: _period,
        timeZone: 'UTC',
        dataCutoffUtc: DateTime.utc(2030, 1, 8, 18),
        sourceTier: MetricSourceTier.localOperational,
        syncCoverage: _coverage,
        privacyStatus: MetricPrivacyStatus.personalFact,
      ),
      throwsArgumentError,
    );
    expect(
      () => MetricResult(
        definition: CoreMetricCatalog.interestThreeFourRatio,
        value: CountMetricValue(2),
        period: _period,
        timeZone: 'UTC',
        dataCutoffUtc: DateTime.utc(2030, 1, 8, 18),
        sourceTier: MetricSourceTier.localOperational,
        syncCoverage: _coverage,
        privacyStatus: MetricPrivacyStatus.personalFact,
      ),
      throwsArgumentError,
    );
    expect(
      () => MetricResult(
        definition: CoreMetricCatalog.interestThreeFourRatio,
        value: SubsetRatioMetricValue(label: '0', numerator: 1, denominator: 1),
        period: _period,
        timeZone: 'UTC',
        dataCutoffUtc: DateTime.utc(2030, 1, 8, 18),
        sourceTier: MetricSourceTier.localOperational,
        syncCoverage: _coverage,
        privacyStatus: MetricPrivacyStatus.personalFact,
      ),
      throwsArgumentError,
    );
    expect(
      () => MetricResult(
        definition: CoreMetricCatalog.interestLevelRatios,
        value: RatioMetricValue.fromNumerators(
          labels: const ['a', 'b', 'c', 'd', 'e'],
          numerators: const [1, 0, 0, 0, 0],
          denominator: 1,
        ),
        period: _period,
        timeZone: 'UTC',
        dataCutoffUtc: DateTime.utc(2030, 1, 8, 18),
        sourceTier: MetricSourceTier.localOperational,
        syncCoverage: _coverage,
        privacyStatus: MetricPrivacyStatus.personalFact,
      ),
      throwsArgumentError,
    );
    expect(
      () => MetricPeriod(
        fromUtc: DateTime.utc(2030, 1, 9),
        untilUtc: DateTime.utc(2030, 1, 8),
      ),
      throwsArgumentError,
    );
    expect(
      () => MetricSyncCoverage(
        statisticalUnit: MetricStatisticalUnit.contactSession,
        totalCount: 2,
        pendingCount: 3,
      ),
      throwsArgumentError,
    );
    expect(
      () => MetricResult(
        definition: CoreMetricCatalog.contactSessions,
        value: const SuppressedMetricValue(),
        period: _period,
        timeZone: 'UTC',
        dataCutoffUtc: null,
        retrievedAtUtc: DateTime.utc(2030, 1, 9),
        sourceTier: MetricSourceTier.backendOperational,
        privacyStatus: MetricPrivacyStatus.suppressed,
      ),
      throwsArgumentError,
    );
    expect(
      () => MetricResult(
        definition: CoreMetricCatalog.contactSessions,
        value: CountMetricValue(2),
        period: _period,
        timeZone: 'UTC',
        dataCutoffUtc: DateTime(2030, 1, 8, 18),
        sourceTier: MetricSourceTier.localOperational,
        syncCoverage: _coverage,
        privacyStatus: MetricPrivacyStatus.personalFact,
      ),
      throwsArgumentError,
    );
  });

  test('隐藏管理结果不携带精确值或伪造本地同步覆盖', () {
    final suppressed = MetricResult(
      definition: CoreMetricCatalog.contactSessions,
      value: const SuppressedMetricValue(),
      period: _period,
      timeZone: 'UTC',
      dataCutoffUtc: DateTime.utc(2030, 1, 9),
      sourceTier: MetricSourceTier.backendOperational,
      privacyStatus: MetricPrivacyStatus.suppressed,
    );

    expect(suppressed.value, const SuppressedMetricValue());
    expect(suppressed.syncCoverage, isNull);
    expect(
      () => MetricResult(
        definition: CoreMetricCatalog.contactSessions,
        value: CountMetricValue(9),
        period: _period,
        timeZone: 'UTC',
        dataCutoffUtc: DateTime.utc(2030, 1, 9),
        sourceTier: MetricSourceTier.backendOperational,
        privacyStatus: MetricPrivacyStatus.suppressed,
      ),
      throwsArgumentError,
    );
    expect(
      () => MetricResult(
        definition: CoreMetricCatalog.contactSessions,
        value: const SuppressedMetricValue(),
        period: _period,
        timeZone: 'UTC',
        dataCutoffUtc: DateTime.utc(2030, 1, 9),
        sourceTier: MetricSourceTier.backendOperational,
        privacyStatus: MetricPrivacyStatus.displayed,
      ),
      throwsArgumentError,
    );
    expect(
      () => MetricResult(
        definition: CoreMetricCatalog.contactSessions,
        value: CountMetricValue(10),
        period: _period,
        timeZone: 'UTC',
        dataCutoffUtc: DateTime.utc(2030, 1, 9),
        sourceTier: MetricSourceTier.localOperational,
        privacyStatus: MetricPrivacyStatus.personalFact,
      ),
      throwsArgumentError,
    );
  });

  test('Backend 可返回个人事实并区分未知截止与取回时间', () {
    final backendPersonal = MetricResult(
      definition: CoreMetricCatalog.contactSessions,
      value: CountMetricValue(2),
      period: _period,
      timeZone: 'UTC',
      dataCutoffUtc: null,
      retrievedAtUtc: DateTime.utc(2030, 1, 9),
      sourceTier: MetricSourceTier.backendOperational,
      privacyStatus: MetricPrivacyStatus.personalFact,
    );

    expect(backendPersonal.syncCoverage, isNull);
    expect(backendPersonal.dataCutoffUtc, isNull);
    expect(backendPersonal.retrievedAtUtc, DateTime.utc(2030, 1, 9));
    expect(
      () => MetricResult(
        definition: CoreMetricCatalog.contactSessions,
        value: CountMetricValue(2),
        period: _period,
        timeZone: 'UTC',
        dataCutoffUtc: null,
        retrievedAtUtc: DateTime.utc(2030, 1, 9),
        sourceTier: MetricSourceTier.localOperational,
        syncCoverage: _coverage,
        privacyStatus: MetricPrivacyStatus.personalFact,
      ),
      throwsArgumentError,
    );
    expect(
      () => MetricResult(
        definition: CoreMetricCatalog.contactSessions,
        value: CountMetricValue(2),
        period: _period,
        timeZone: 'UTC',
        dataCutoffUtc: DateTime.utc(2030, 1, 9),
        sourceTier: MetricSourceTier.warehouse,
        privacyStatus: MetricPrivacyStatus.personalFact,
      ),
      throwsArgumentError,
    );
  });
}

final _period = MetricPeriod(
  fromUtc: DateTime.utc(2030, 1, 8),
  untilUtc: DateTime.utc(2030, 1, 9),
);

final _coverage = MetricSyncCoverage(
  statisticalUnit: MetricStatisticalUnit.contactSession,
  totalCount: 2,
  pendingCount: 1,
);
