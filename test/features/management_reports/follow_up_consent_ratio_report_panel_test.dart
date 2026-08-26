import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tongxingzhe_app/features/management_reports/follow_up_consent_ratio_report_panel.dart';
import 'package:tongxingzhe_app/l10n/app_strings.dart';
import 'package:tongxingzhe_app/management_reports/follow_up_consent_ratio_report_gateway.dart';

void main() {
  testWidgets('英文目录使用本地化摘要和打开语义，详情显示查询指纹', (tester) async {
    final semantics = tester.ensureSemantics();
    final gateway = _QueueGateway(
      directory: _directory(snapshots: [_summary]),
      snapshotResult: FollowUpConsentRatioReportSuccess(_snapshot()),
    );

    await tester.pumpWidget(_app(gateway, text: const AppStrings('en')));
    await tester.pumpAndSettle();

    final item = find.byKey(
      ValueKey('follow-up-consent-ratio-report-${_summary.snapshotId}'),
    );
    final visibleDirectoryText = tester
        .widgetList<Text>(
          find.descendant(of: item, matching: find.byType(Text)),
        )
        .map((text) => text.data ?? '')
        .join('\n');
    expect(visibleDirectoryText, contains('Report version 1'));
    expect(visibleDirectoryText, isNot(contains('：')));
    expect(visibleDirectoryText, isNot(contains('，')));
    final itemSemantics = tester.getSemantics(item).label;
    expect(itemSemantics, contains('Open follow-up consent ratio report'));
    expect(itemSemantics, isNot(contains('：')));
    expect(itemSemantics, isNot(contains('，')));

    await tester.tap(item);
    await tester.pumpAndSettle();

    final fingerprint = find.byKey(
      const ValueKey('follow-up-consent-ratio-report-query-fingerprint'),
    );
    expect(fingerprint, findsOneWidget);
    expect(tester.getSemantics(fingerprint).label, contains(_queryFingerprint));
    expect(find.text('Query fingerprint'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('目录不自动打开第一项，明确摘要后显示两期比例和三项覆盖', (tester) async {
    final semantics = tester.ensureSemantics();
    final gateway = _QueueGateway(
      directory: _directory(snapshots: [_summary]),
      snapshotResult: FollowUpConsentRatioReportSuccess(_snapshot()),
    );

    await tester.pumpWidget(_app(gateway));
    await tester.pumpAndSettle();

    expect(gateway.listProjectIds, [_projectId]);
    expect(gateway.readRequests, isEmpty);
    final item = find.byKey(
      ValueKey('follow-up-consent-ratio-report-${_summary.snapshotId}'),
    );
    expect(item, findsOneWidget);
    expect(
      find.byKey(const ValueKey('follow-up-consent-ratio-report-back')),
      findsNothing,
    );
    expect(
      tester
          .getSemantics(
            find.byKey(
              const ValueKey('follow-up-consent-ratio-report-heading'),
            ),
          )
          .getSemanticsData()
          .flagsCollection
          .isHeader,
      isTrue,
    );
    expect(
      tester
          .getSemantics(
            find.byKey(
              const ValueKey(
                'follow-up-consent-ratio-report-directory-heading',
              ),
            ),
          )
          .getSemanticsData()
          .flagsCollection
          .isHeader,
      isTrue,
    );

    await tester.tap(item);
    await tester.pumpAndSettle();

    expect(gateway.readRequests.single, (_projectId, _summary));
    expect(
      find.text('contact_target_follow_up_consent_ratio_two_periods@1'),
      findsOneWidget,
    );
    expect(find.text('follow_up_consent_ratio@1'), findsOneWidget);
    expect(find.text('contact_target_link'), findsOneWidget);
    expect(find.text('consent_state'), findsOneWidget);
    expect(find.text('较早期间'), findsWidgets);
    expect(find.text('较晚期间'), findsWidgets);
    expect(find.textContaining('2029-12-30T00:00:00.000Z'), findsOneWidget);
    expect(find.textContaining('2030-01-13T00:00:00.000Z'), findsOneWidget);
    expect(find.textContaining('12 / 30'), findsOneWidget);
    expect(find.textContaining('40.00%'), findsOneWidget);
    expect(find.textContaining('10'), findsWidgets);
    expect(find.textContaining('11'), findsWidgets);
    expect(find.textContaining('7'), findsWidgets);
    expect(
      tester
          .getSemantics(
            find.byKey(
              const ValueKey('follow-up-consent-ratio-report-detail-heading'),
            ),
          )
          .getSemanticsData()
          .flagsCollection
          .isHeader,
      isTrue,
    );
    expect(
      tester
          .getSemantics(
            find.byKey(
              const ValueKey('follow-up-consent-ratio-report-period-heading'),
            ),
          )
          .getSemanticsData()
          .flagsCollection
          .isHeader,
      isTrue,
    );
    expect(
      tester
          .getSemantics(
            find.byKey(
              const ValueKey('follow-up-consent-ratio-report-ratio-heading'),
            ),
          )
          .getSemanticsData()
          .flagsCollection
          .isHeader,
      isTrue,
    );
    expect(
      tester
          .getSemantics(
            find.byKey(
              const ValueKey('follow-up-consent-ratio-report-coverage-heading'),
            ),
          )
          .getSemanticsData()
          .flagsCollection
          .isHeader,
      isTrue,
    );
    semantics.dispose();
  });

  testWidgets('目录摘要支持 Space 激活并读取明确摘要', (tester) async {
    final gateway = _QueueGateway(
      directory: _directory(snapshots: [_summary]),
      snapshotResult: FollowUpConsentRatioReportSuccess(_snapshot()),
    );

    await tester.pumpWidget(_app(gateway));
    await tester.pumpAndSettle();
    final item = find.byKey(
      ValueKey('follow-up-consent-ratio-report-${_summary.snapshotId}'),
    );
    await _tabTo(tester, item);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();

    expect(gateway.readRequests, [(_projectId, _summary)]);
    expect(
      find.byKey(
        const ValueKey('follow-up-consent-ratio-report-detail-heading'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('比例和覆盖格分别保留 displayed 或 suppressed，不填零或推算隐藏值', (tester) async {
    final semantics = tester.ensureSemantics();
    final gateway = _QueueGateway(
      directory: _directory(snapshots: [_summary]),
      snapshotResult: FollowUpConsentRatioReportSuccess(_snapshot()),
    );

    await tester.pumpWidget(_app(gateway));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(
        ValueKey('follow-up-consent-ratio-report-${_summary.snapshotId}'),
      ),
    );
    await tester.pumpAndSettle();

    final displayedRatio = tester.getSemantics(
      find.byKey(
        const ValueKey('follow-up-consent-ratio-report-ratio-previous'),
      ),
    );
    expect(displayedRatio.label, contains('12'));
    expect(displayedRatio.label, contains('18'));
    expect(displayedRatio.label, contains('30'));
    expect(displayedRatio.label, contains('40.00%'));

    final suppressedRatio = tester.getSemantics(
      find.byKey(
        const ValueKey('follow-up-consent-ratio-report-ratio-current'),
      ),
    );
    expect(suppressedRatio.label, contains('已隐藏'));
    expect(suppressedRatio.label, isNot(contains('12')));
    expect(suppressedRatio.label, isNot(contains('30')));
    expect(suppressedRatio.label, isNot(contains('40')));
    expect(suppressedRatio.label, isNot(contains('0 / 0')));

    final displayedCoverage = tester.getSemantics(
      find.byKey(
        const ValueKey(
          'follow-up-consent-ratio-report-coverage-previous-unanswered',
        ),
      ),
    );
    expect(displayedCoverage.label, contains('10'));
    expect(displayedCoverage.label, isNot(contains('已隐藏')));

    final suppressedCoverage = tester.getSemantics(
      find.byKey(
        const ValueKey(
          'follow-up-consent-ratio-report-coverage-previous-refused',
        ),
      ),
    );
    expect(suppressedCoverage.label, contains('已隐藏'));
    expect(suppressedCoverage.label, isNot(contains('0')));
    expect(suppressedCoverage.label, isNot(contains('1')));

    final independentlyDisplayedCoverage = tester.getSemantics(
      find.byKey(
        const ValueKey(
          'follow-up-consent-ratio-report-coverage-current-refused',
        ),
      ),
    );
    expect(independentlyDisplayedCoverage.label, contains('7'));
    expect(independentlyDisplayedCoverage.label, isNot(contains('已隐藏')));

    for (final value in [
      'target@example.test',
      'person-secret',
      'contributor-secret',
      'source-secret',
    ]) {
      expect(find.textContaining(value), findsNothing);
    }
    semantics.dispose();
  });

  testWidgets('空目录是成功空态且不读取详情', (tester) async {
    final gateway = _QueueGateway(directory: _directory(snapshots: const []));

    await tester.pumpWidget(_app(gateway));
    await tester.pumpAndSettle();

    expect(
      find.byKey(
        const ValueKey('follow-up-consent-ratio-report-directory-heading'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('follow-up-consent-ratio-report-empty')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('follow-up-consent-ratio-report-back')),
      findsNothing,
    );
    expect(gateway.readRequests, isEmpty);
  });

  testWidgets('projectId 为 null 时保持 inactive，不触发 gateway 或显示目录', (
    tester,
  ) async {
    final gateway = _QueueGateway(
      directory: _directory(snapshots: [_summary]),
      snapshotResult: FollowUpConsentRatioReportSuccess(_snapshot()),
    );

    await tester.pumpWidget(_app(gateway, projectId: null));
    await tester.pumpAndSettle();

    expect(gateway.listProjectIds, isEmpty);
    expect(gateway.readRequests, isEmpty);
    expect(
      find.byKey(const ValueKey('follow-up-consent-ratio-report-inactive')),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey('follow-up-consent-ratio-report-directory-heading'),
      ),
      findsNothing,
    );
  });

  testWidgets('失败是英文 live region，重试可恢复且不泄露错误详情', (tester) async {
    final semantics = tester.ensureSemantics();
    final gateway = _QueueGateway(
      directoryResults: [
        FollowUpConsentRatioReportSuccess(_directory(snapshots: const [])),
      ],
      thrownDirectoryError: StateError('target@example.test'),
    );

    await tester.pumpWidget(_app(gateway, text: const AppStrings('en')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('follow-up-consent-ratio-report-failure')),
      findsOneWidget,
    );
    expect(
      tester
          .getSemantics(
            find.byKey(
              const ValueKey('follow-up-consent-ratio-report-failure'),
            ),
          )
          .getSemanticsData()
          .flagsCollection
          .isLiveRegion,
      isTrue,
    );
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('重试'), findsNothing);
    expect(find.textContaining('target@example.test'), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey('follow-up-consent-ratio-report-retry')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('follow-up-consent-ratio-report-empty')),
      findsOneWidget,
    );
    expect(find.text('Retry'), findsNothing);
    expect(gateway.listProjectIds, [_projectId, _projectId]);
    expect(gateway.readRequests, isEmpty);
    semantics.dispose();
  });

  testWidgets('重试再次失败后焦点回到 retry 控件', (tester) async {
    final gateway = _QueueGateway(
      directoryResults: [
        const FollowUpConsentRatioReportRejected(
          FollowUpConsentRatioReportFailureCode.forbidden,
        ),
        const FollowUpConsentRatioReportRejected(
          FollowUpConsentRatioReportFailureCode.serviceUnavailable,
        ),
      ],
    );

    await tester.pumpWidget(_app(gateway));
    await tester.pumpAndSettle();
    final retry = find.byKey(
      const ValueKey('follow-up-consent-ratio-report-retry'),
    );
    await _tabTo(tester, retry);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(gateway.listProjectIds, [_projectId, _projectId]);
    expect(
      find.byKey(const ValueKey('follow-up-consent-ratio-report-failure')),
      findsOneWidget,
    );
    expect(_containsPrimaryFocus(tester, retry), isTrue);
  });

  testWidgets('suppressed coverage 即使带有错误数值也只显示隐藏状态', (tester) async {
    final semantics = tester.ensureSemantics();
    final gateway = _QueueGateway(
      directory: _directory(snapshots: [_summary]),
      snapshotResult: FollowUpConsentRatioReportSuccess(
        _snapshot(invalidSuppressedCoverage: true),
      ),
    );

    await tester.pumpWidget(_app(gateway));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(
        ValueKey('follow-up-consent-ratio-report-${_summary.snapshotId}'),
      ),
    );
    await tester.pumpAndSettle();

    final suppressed = tester.getSemantics(
      find.byKey(
        const ValueKey(
          'follow-up-consent-ratio-report-coverage-previous-refused',
        ),
      ),
    );
    expect(suppressed.label, contains('已隐藏'));
    expect(suppressed.label, isNot(contains('99')));
    expect(
      find.descendant(
        of: find.byKey(
          const ValueKey(
            'follow-up-consent-ratio-report-coverage-previous-refused',
          ),
        ),
        matching: find.textContaining('99'),
      ),
      findsNothing,
    );
    semantics.dispose();
  });

  testWidgets('Enter 打开、Escape 返回并恢复原摘要焦点', (tester) async {
    final gateway = _QueueGateway(
      directory: _directory(snapshots: [_summary, _secondSummary]),
      snapshotResult: FollowUpConsentRatioReportSuccess(_snapshot()),
    );

    await tester.pumpWidget(_app(gateway));
    await tester.pumpAndSettle();

    final item = find.byKey(
      ValueKey('follow-up-consent-ratio-report-${_summary.snapshotId}'),
    );
    await _tabTo(tester, item);
    final secondItem = find.byKey(
      ValueKey('follow-up-consent-ratio-report-${_secondSummary.snapshotId}'),
    );
    await _tabTo(tester, secondItem);
    await _shiftTab(tester);
    expect(_containsPrimaryFocus(tester, item), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    final back = find.byKey(
      const ValueKey('follow-up-consent-ratio-report-back'),
    );
    expect(back, findsOneWidget);
    expect(_containsPrimaryFocus(tester, back), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(
      find.byKey(
        const ValueKey('follow-up-consent-ratio-report-directory-heading'),
      ),
      findsOneWidget,
    );
    expect(_containsPrimaryFocus(tester, item), isTrue);
    expect(gateway.readRequests, [(_projectId, _summary)]);
  });

  testWidgets('320 宽与 200% 字号下详情可滚动且不横向溢出', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final semantics = tester.ensureSemantics();
    final gateway = _QueueGateway(
      directory: _directory(snapshots: [_summary]),
      snapshotResult: FollowUpConsentRatioReportSuccess(_snapshot()),
    );

    await tester.pumpWidget(_app(gateway, textScaler: TextScaler.linear(2)));
    await tester.pumpAndSettle();
    final item = find.byKey(
      ValueKey('follow-up-consent-ratio-report-${_summary.snapshotId}'),
    );
    await tester.ensureVisible(item);
    await tester.tap(item);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final currentCoverage = find.byKey(
      const ValueKey(
        'follow-up-consent-ratio-report-coverage-current-not_applicable',
      ),
    );
    await tester.ensureVisible(currentCoverage);
    expect(currentCoverage, findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(
      tester
          .getSemantics(
            find.byKey(
              const ValueKey('follow-up-consent-ratio-report-live-region'),
            ),
          )
          .getSemanticsData()
          .flagsCollection
          .isLiveRegion,
      isTrue,
    );
    semantics.dispose();
  });
}

Widget _app(
  FollowUpConsentRatioReportGateway gateway, {
  AppStrings text = const AppStrings('zh'),
  TextScaler textScaler = TextScaler.noScaling,
  String? projectId = _projectId,
}) => MaterialApp(
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: textScaler),
    child: child!,
  ),
  home: Scaffold(
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(8),
      child: FollowUpConsentRatioReportPanel(
        text: text,
        gateway: gateway,
        projectId: projectId,
      ),
    ),
  ),
);

FollowUpConsentRatioReportSnapshotDirectory _directory({
  required List<FollowUpConsentRatioReportSnapshotSummary> snapshots,
}) => FollowUpConsentRatioReportSnapshotDirectory(
  accessEventId: 'access-directory-1',
  projectId: _projectId,
  snapshots: snapshots,
);

final _summary = FollowUpConsentRatioReportSnapshotSummary(
  snapshotId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  reportId: _reportId,
  reportVersion: 1,
  reportingTimeZone: 'America/Chicago',
  dataCutoffUtc: DateTime.utc(2030, 1, 15, 1),
  releasedAtUtc: DateTime.utc(2030, 1, 15, 2),
);

final _secondSummary = FollowUpConsentRatioReportSnapshotSummary(
  snapshotId: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
  reportId: _reportId,
  reportVersion: 1,
  reportingTimeZone: 'America/Chicago',
  dataCutoffUtc: DateTime.utc(2030, 1, 8, 1),
  releasedAtUtc: DateTime.utc(2030, 1, 8, 2),
);

FollowUpConsentRatioReportSnapshot _snapshot({
  bool invalidSuppressedCoverage = false,
}) => FollowUpConsentRatioReportSnapshot(
  accessEventId: 'access-detail-1',
  summary: _summary,
  report: FollowUpConsentRatioReportDocument(
    reportId: _reportId,
    reportVersion: 1,
    metricId: 'follow_up_consent_ratio',
    metricVersion: 1,
    statisticalUnit: 'contact_target_link',
    dimension: 'consent_state',
    periodGrain: 'week',
    comparisonPeriodCount: 2,
    periodBoundaryId: 'iso_week_monday_v1',
    privacyPolicy: 'management_follow_up_consent_ratio_privacy_v1',
    queryFingerprint:
        'management-report:contact_target_follow_up_consent_ratio_two_periods:v1',
    sourceScope:
        'backend_accepted_active_contact_target_links_current_revision',
    projectId: _projectId,
    resultStatus: 'completed',
    periods: FollowUpConsentRatioReportPeriods(
      periodBoundaryId: 'iso_week_monday_v1',
      reportingTimeZone: 'America/Chicago',
      dataCutoffUtc: _summary.dataCutoffUtc,
      previousPeriod: FollowUpConsentRatioReportPeriod(
        startUtc: DateTime.utc(2029, 12, 30),
        untilUtc: DateTime.utc(2030, 1, 6),
      ),
      currentPeriod: FollowUpConsentRatioReportPeriod(
        startUtc: DateTime.utc(2030, 1, 6),
        untilUtc: DateTime.utc(2030, 1, 13),
      ),
    ),
    periodResults: [
      FollowUpConsentRatioReportPeriodResult(
        periodKey: FollowUpConsentRatioReportPeriodKey.previous,
        periodOrder: 0,
        ratio: const FollowUpConsentRatioReportRatio(
          privacyStatus: FollowUpConsentRatioReportPrivacyStatus.displayed,
          yesCount: 12,
          noCount: 18,
          numerator: 12,
          denominator: 30,
          percentageBasisPoints: 4000,
        ),
        coverage: [
          const FollowUpConsentRatioReportCoverageCell(
            consentState: 'unanswered',
            cellOrder: 0,
            valueCount: 10,
            privacyStatus: FollowUpConsentRatioReportPrivacyStatus.displayed,
          ),
          FollowUpConsentRatioReportCoverageCell(
            consentState: 'refused',
            cellOrder: 1,
            valueCount: invalidSuppressedCoverage ? 99 : null,
            privacyStatus: FollowUpConsentRatioReportPrivacyStatus.suppressed,
          ),
          const FollowUpConsentRatioReportCoverageCell(
            consentState: 'not_applicable',
            cellOrder: 2,
            valueCount: 11,
            privacyStatus: FollowUpConsentRatioReportPrivacyStatus.displayed,
          ),
        ],
        unknownCount: 0,
        excludedCount: 0,
      ),
      FollowUpConsentRatioReportPeriodResult(
        periodKey: FollowUpConsentRatioReportPeriodKey.current,
        periodOrder: 1,
        ratio: const FollowUpConsentRatioReportRatio(
          privacyStatus: FollowUpConsentRatioReportPrivacyStatus.suppressed,
          yesCount: null,
          noCount: null,
          numerator: null,
          denominator: null,
          percentageBasisPoints: null,
        ),
        coverage: [
          const FollowUpConsentRatioReportCoverageCell(
            consentState: 'unanswered',
            cellOrder: 3,
            valueCount: null,
            privacyStatus: FollowUpConsentRatioReportPrivacyStatus.suppressed,
          ),
          const FollowUpConsentRatioReportCoverageCell(
            consentState: 'refused',
            cellOrder: 4,
            valueCount: 7,
            privacyStatus: FollowUpConsentRatioReportPrivacyStatus.displayed,
          ),
          const FollowUpConsentRatioReportCoverageCell(
            consentState: 'not_applicable',
            cellOrder: 5,
            valueCount: null,
            privacyStatus: FollowUpConsentRatioReportPrivacyStatus.suppressed,
          ),
        ],
        unknownCount: 0,
        excludedCount: 0,
      ),
    ],
  ),
);

final class _QueueGateway implements FollowUpConsentRatioReportGateway {
  _QueueGateway({
    FollowUpConsentRatioReportSnapshotDirectory? directory,
    this.snapshotResult,
    List<
      FollowUpConsentRatioReportResult<
        FollowUpConsentRatioReportSnapshotDirectory
      >
    >?
    directoryResults,
    this.thrownDirectoryError,
  }) : _directoryResults =
           directoryResults ??
           [
             FollowUpConsentRatioReportSuccess(
               directory ?? _directory(snapshots: [_summary]),
             ),
           ];

  final List<
    FollowUpConsentRatioReportResult<
      FollowUpConsentRatioReportSnapshotDirectory
    >
  >
  _directoryResults;
  final FollowUpConsentRatioReportResult<FollowUpConsentRatioReportSnapshot>?
  snapshotResult;
  final Object? thrownDirectoryError;
  final listProjectIds = <String>[];
  final List<(String, FollowUpConsentRatioReportSnapshotSummary)> readRequests =
      [];
  var _directoryIndex = 0;

  @override
  Future<
    FollowUpConsentRatioReportResult<
      FollowUpConsentRatioReportSnapshotDirectory
    >
  >
  listSnapshots(String projectId) async {
    listProjectIds.add(projectId);
    final error = thrownDirectoryError;
    if (error != null && _directoryIndex == 0) {
      _directoryIndex++;
      throw error;
    }
    final resultIndex = thrownDirectoryError == null
        ? _directoryIndex
        : _directoryIndex - 1;
    _directoryIndex++;
    return _directoryResults[resultIndex];
  }

  @override
  Future<FollowUpConsentRatioReportResult<FollowUpConsentRatioReportSnapshot>>
  readSnapshot({
    required String projectId,
    required FollowUpConsentRatioReportSnapshotSummary summary,
  }) async {
    readRequests.add((projectId, summary));
    return snapshotResult ??
        const FollowUpConsentRatioReportRejected(
          FollowUpConsentRatioReportFailureCode.notFound,
        );
  }

  @override
  Future<void> close() async {}
}

Future<void> _tabTo(WidgetTester tester, Finder target) async {
  for (var index = 0; index < 30; index++) {
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    if (_containsPrimaryFocus(tester, target)) return;
  }
  fail('Unable to focus $target');
}

Future<void> _shiftTab(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
  await tester.sendKeyEvent(LogicalKeyboardKey.tab);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
  await tester.pump();
}

bool _containsPrimaryFocus(WidgetTester tester, Finder finder) {
  final target = tester.element(finder);
  final focused = FocusManager.instance.primaryFocus?.context;
  if (focused is! Element) return false;
  if (identical(focused, target)) return true;
  var contains = false;
  focused.visitAncestorElements((ancestor) {
    if (identical(ancestor, target)) {
      contains = true;
      return false;
    }
    return true;
  });
  return contains;
}

const _projectId = '33333333-3333-4333-8333-333333333333';
const _reportId = 'contact_target_follow_up_consent_ratio_two_periods';
const _queryFingerprint =
    'management-report:contact_target_follow_up_consent_ratio_two_periods:v1';
