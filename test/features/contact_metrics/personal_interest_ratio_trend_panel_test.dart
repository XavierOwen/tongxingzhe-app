import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tongxingzhe_app/features/contact_metrics/metric_contract.dart';
import 'package:tongxingzhe_app/features/contact_metrics/personal_interest_ratio_trend.dart';
import 'package:tongxingzhe_app/features/contact_metrics/personal_interest_ratio_trend_panel.dart';
import 'package:tongxingzhe_app/l10n/app_strings.dart';

void main() {
  testWidgets('320×568 与 200% 字号显示两期原始值和百分点差', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          size: Size(320, 568),
          textScaler: TextScaler.linear(2),
        ),
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: PersonalInterestRatioTrendPanel(
                text: const AppStrings('zh'),
                comparison: _comparison(),
                isLoading: false,
                loadFailed: false,
                onRetry: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final heading = tester.widget<Semantics>(
      find.byKey(const ValueKey('personal-interest-ratio-trend-heading')),
    );
    expect(heading.properties.header, isTrue);
    expect(heading.properties.label, '兴趣 3–4 两期趋势');
    final previous = tester.widget<Semantics>(
      find.descendant(
        of: find.byKey(
          const ValueKey('personal-interest-ratio-trend-previous'),
        ),
        matching: find.byType(Semantics),
      ),
    );
    expect(
      previous.properties.label,
      '较早七日 [2030-01-01T00:00:00.000Z, '
      '2030-01-08T00:00:00.000Z)：1 / 3（33.33%）；本地待同步 1',
    );
    final delta = tester.widget<Semantics>(
      find.descendant(
        of: find.byKey(const ValueKey('personal-interest-ratio-trend-delta')),
        matching: find.byType(Semantics),
      ),
    );
    expect(delta.properties.label, '百分点差（较晚期 − 较早期）：+33.34 个百分点');
    expect(find.textContaining('不表示成功、失败或因果'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('空分母不显示 0% 或百分点差', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PersonalInterestRatioTrendPanel(
            text: const AppStrings('zh'),
            comparison: _comparison(
              previousNumerator: 0,
              previousDenominator: 0,
              previousPendingCount: 0,
            ),
            isLoading: false,
            loadFailed: false,
            onRetry: () {},
          ),
        ),
      ),
    );

    expect(find.textContaining('0 / 0（暂无可计算比例）'), findsOneWidget);
    expect(find.textContaining('因此不显示百分点差'), findsOneWidget);
    expect(find.textContaining('0.00%'), findsNothing);
  });

  testWidgets('失败状态保留稳定说明且可用键盘重试', (tester) async {
    var retryCalls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PersonalInterestRatioTrendPanel(
            text: const AppStrings('zh'),
            comparison: null,
            isLoading: false,
            loadFailed: true,
            onRetry: () => retryCalls++,
          ),
        ),
      ),
    );

    expect(find.textContaining('请稍后重试'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(retryCalls, 1);
  });

  testWidgets('英语 loading 状态提供 live region 标签', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PersonalInterestRatioTrendPanel(
            text: const AppStrings('en'),
            comparison: null,
            isLoading: true,
            loadFailed: false,
            onRetry: () {},
          ),
        ),
      ),
    );

    final loading = tester.widget<Semantics>(
      find.byKey(const ValueKey('personal-interest-ratio-trend-loading')),
    );
    expect(loading.properties.liveRegion, isTrue);
    expect(loading.properties.label, 'Loading the interest trend');
    semantics.dispose();
  });
}

PersonalInterestRatioTrendComparison _comparison({
  int previousNumerator = 1,
  int previousDenominator = 3,
  int previousPendingCount = 1,
  int currentNumerator = 2,
  int currentDenominator = 3,
  int currentPendingCount = 0,
}) {
  final scope = PersonalMetricScope(
    appUserId: 'app-user-1',
    workspaceId: 'workspace-1',
    projectId: 'project-1',
  );
  return comparePersonalInterestRatioTrend(
    previous: PersonalInterestRatioTrendObservation(
      scope: scope,
      metric: _metric(
        fromUtc: DateTime.utc(2030, 1, 1),
        untilUtc: DateTime.utc(2030, 1, 8),
        numerator: previousNumerator,
        denominator: previousDenominator,
        pendingCount: previousPendingCount,
      ),
    ),
    current: PersonalInterestRatioTrendObservation(
      scope: scope,
      metric: _metric(
        fromUtc: DateTime.utc(2030, 1, 8),
        untilUtc: DateTime.utc(2030, 1, 15),
        numerator: currentNumerator,
        denominator: currentDenominator,
        pendingCount: currentPendingCount,
      ),
    ),
  );
}

MetricResult _metric({
  required DateTime fromUtc,
  required DateTime untilUtc,
  required int numerator,
  required int denominator,
  required int pendingCount,
}) {
  return MetricResult(
    definition: CoreMetricCatalog.interestThreeFourRatio,
    value: SubsetRatioMetricValue(
      label: CoreMetricCatalog.interestThreeFourRatio.bucketLabels.single,
      numerator: numerator,
      denominator: denominator,
    ),
    period: MetricPeriod(fromUtc: fromUtc, untilUtc: untilUtc),
    timeZone: 'UTC',
    dataCutoffUtc: DateTime.utc(2030, 1, 15, 12),
    sourceTier: MetricSourceTier.localOperational,
    syncCoverage: MetricSyncCoverage(
      statisticalUnit: MetricStatisticalUnit.contactSession,
      totalCount: denominator,
      pendingCount: pendingCount,
    ),
    privacyStatus: MetricPrivacyStatus.personalFact,
  );
}
