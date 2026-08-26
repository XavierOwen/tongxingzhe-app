import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tongxingzhe_app/features/management_reports/original_region_report_panel.dart';
import 'package:tongxingzhe_app/l10n/app_strings.dart';
import 'package:tongxingzhe_app/management_reports/original_region_report_gateway.dart';

void main() {
  testWidgets('目录不自动打开第一项，明确选择后显示原始区域报告', (tester) async {
    final semantics = tester.ensureSemantics();
    final gateway = _QueueGateway(
      directory: _directoryWithSummary,
      snapshotResult: OriginalRegionReportSuccess(_snapshot()),
    );

    await tester.pumpWidget(_app(gateway));
    await tester.pumpAndSettle();

    expect(gateway.listProjectIds, [_projectId]);
    expect(gateway.readRequests, isEmpty);
    final item = find.byKey(
      ValueKey('original-region-report-${_summary.snapshotId}'),
    );
    expect(item, findsOneWidget);
    expect(
      tester
          .getSemantics(
            find.byKey(const ValueKey('original-region-report-heading')),
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
              const ValueKey('original-region-report-directory-heading'),
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
      find.text('contact_sessions_by_original_region_two_periods@1'),
      findsOneWidget,
    );
    expect(find.text('original'), findsOneWidget);
    expect(find.text('city'), findsOneWidget);
    final firstCity = find.byKey(
      const ValueKey('original-region-report-city-city-00000'),
    );
    await tester.ensureVisible(firstCity);
    expect(find.textContaining('12 次'), findsOneWidget);
    expect(find.textContaining('20 次'), findsOneWidget);
    final cityList = find.byKey(
      const ValueKey('original-region-report-city-list'),
    );
    final hiddenCityFinder = find.byKey(
      const ValueKey('original-region-report-city-city-00001'),
    );
    await tester.scrollUntilVisible(
      hiddenCityFinder,
      120,
      scrollable: find
          .descendant(of: cityList, matching: find.byType(Scrollable))
          .first,
    );
    expect(find.textContaining('已隐藏'), findsNWidgets(2));
    expect(find.text('0'), findsNothing);
    expect(
      tester
          .getSemantics(
            find.byKey(const ValueKey('original-region-report-detail-heading')),
          )
          .getSemanticsData()
          .flagsCollection
          .isHeader,
      isTrue,
    );
    expect(
      tester
          .getSemantics(
            find.byKey(const ValueKey('original-region-report-period-heading')),
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
              const ValueKey('original-region-report-source-tree-heading'),
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
              const ValueKey('original-region-report-city-list-heading'),
            ),
          )
          .getSemanticsData()
          .flagsCollection
          .isHeader,
      isTrue,
    );
    final hiddenCity = tester.getSemantics(
      find.byKey(const ValueKey('original-region-report-city-city-00001')),
    );
    expect(hiddenCity.label, contains('已隐藏'));
    expect(hiddenCity.label, isNot(contains('：0 次')));
    expect(
      tester
          .getSemantics(
            find.byKey(const ValueKey('original-region-report-live-region')),
          )
          .getSemanticsData()
          .flagsCollection
          .isLiveRegion,
      isTrue,
    );
    semantics.dispose();
  });

  testWidgets('空目录是成功空态且不读取详情', (tester) async {
    final gateway = _QueueGateway(directory: _emptyDirectory);

    await tester.pumpWidget(_app(gateway));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('original-region-report-directory-heading')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('original-region-report-city-list')),
      findsNothing,
    );
    expect(gateway.readRequests, isEmpty);
  });

  testWidgets('320 宽与 200% 字号下城市成对列表不横向溢出', (tester) async {
    _compactView(tester);
    final semantics = tester.ensureSemantics();
    final gateway = _QueueGateway(
      directory: _directoryWithSummary,
      snapshotResult: OriginalRegionReportSuccess(_snapshot()),
    );

    await tester.pumpWidget(_app(gateway, textScaler: TextScaler.linear(2)));
    await tester.pumpAndSettle();
    final item = find.byKey(
      ValueKey('original-region-report-${_summary.snapshotId}'),
    );
    await tester.ensureVisible(item);
    await tester.tap(item);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final previousPeriod = find.text('较早期间');
    final currentPeriod = find.text('较晚期间');
    await tester.ensureVisible(previousPeriod.first);
    await tester.ensureVisible(currentPeriod.first);
    expect(previousPeriod, findsOneWidget);
    expect(currentPeriod, findsOneWidget);
    expect(
      tester
          .getSemantics(
            find.byKey(const ValueKey('original-region-report-live-region')),
          )
          .getSemanticsData()
          .flagsCollection
          .isLiveRegion,
      isTrue,
    );
    semantics.dispose();
  });

  testWidgets('项目切换淘汰旧目录焦点节点，新的摘要仍可返回聚焦', (tester) async {
    final gateway = _QueueGateway(
      directoryResults: [
        OriginalRegionReportSuccess(_directory(snapshots: [_summary])),
        OriginalRegionReportSuccess(
          _directory(projectId: _otherProjectId, snapshots: [_secondSummary]),
        ),
      ],
      snapshotResult: OriginalRegionReportSuccess(_snapshot()),
    );
    await tester.pumpWidget(_app(gateway));
    await tester.pumpAndSettle();

    final oldItem = find.byKey(
      ValueKey('original-region-report-${_summary.snapshotId}'),
    );
    final oldNode = tester
        .widget<ListTile>(
          find.descendant(of: oldItem, matching: find.byType(ListTile)),
        )
        .focusNode!;

    await tester.pumpWidget(_app(gateway, projectId: _otherProjectId));
    await tester.pumpAndSettle();

    expect(() => oldNode.addListener(() {}), throwsA(isA<FlutterError>()));
    final newItem = find.byKey(
      ValueKey('original-region-report-${_secondSummary.snapshotId}'),
    );
    expect(newItem, findsOneWidget);
    await _tabTo(tester, newItem);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(_containsPrimaryFocus(tester, newItem), isTrue);
  });

  testWidgets('键盘遍历、Enter/Space 打开、Escape 返回并恢复快照焦点', (tester) async {
    final gateway = _QueueGateway(
      directory: _directory(snapshots: [_summary, _secondSummary]),
      snapshotResult: OriginalRegionReportSuccess(_snapshot()),
    );

    await tester.pumpWidget(_app(gateway));
    await tester.pumpAndSettle();

    final item = find.byKey(
      ValueKey('original-region-report-${_summary.snapshotId}'),
    );
    await _tabTo(tester, item);
    final secondItem = find.byKey(
      ValueKey('original-region-report-${_secondSummary.snapshotId}'),
    );
    await _tabTo(tester, secondItem);
    await _shiftTab(tester);
    expect(_containsPrimaryFocus(tester, item), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    final back = find.byKey(const ValueKey('original-region-report-back'));
    expect(back, findsOneWidget);
    expect(_containsPrimaryFocus(tester, back), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('original-region-report-directory-heading')),
      findsOneWidget,
    );
    expect(_containsPrimaryFocus(tester, item), isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('original-region-report-detail-heading')),
      findsOneWidget,
    );
    expect(gateway.readRequests, [
      (_projectId, _summary),
      (_projectId, _summary),
    ]);
  });

  testWidgets('英文详情显示固定合同和受保护的城市格', (tester) async {
    final gateway = _QueueGateway(
      directory: _directoryWithSummary,
      snapshotResult: OriginalRegionReportSuccess(_snapshot()),
    );

    await tester.pumpWidget(_app(gateway, text: const AppStrings('en')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(ValueKey('original-region-report-${_summary.snapshotId}')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Report definition'), findsNWidgets(2));
    expect(find.text('Source-tree context'), findsOneWidget);
    expect(find.text('City cells'), findsOneWidget);
    expect(find.text('City ID：city-00000'), findsOneWidget);
    expect(find.textContaining('12 sessions'), findsOneWidget);
    expect(find.textContaining('20 sessions'), findsOneWidget);

    final cityList = find.byKey(
      const ValueKey('original-region-report-city-list'),
    );
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('original-region-report-city-city-00001')),
      120,
      scrollable: find
          .descendant(of: cityList, matching: find.byType(Scrollable))
          .first,
    );
    expect(find.textContaining('Hidden'), findsNWidgets(2));
    expect(find.text('0'), findsNothing);
  });

  testWidgets('失败是 live region，重试可恢复', (tester) async {
    final gateway = _QueueGateway(
      directoryResults: [
        const OriginalRegionReportRejected(
          OriginalRegionReportFailureCode.forbidden,
        ),
        OriginalRegionReportSuccess(_emptyDirectory),
      ],
    );
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(_app(gateway, text: const AppStrings('en')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('original-region-report-failure')),
      findsOneWidget,
    );
    expect(
      tester
          .getSemantics(
            find.byKey(const ValueKey('original-region-report-failure')),
          )
          .getSemanticsData()
          .flagsCollection
          .isLiveRegion,
      isTrue,
    );
    await tester.tap(
      find.byKey(const ValueKey('original-region-report-retry')),
    );
    await tester.pumpAndSettle();

    expect(gateway.listProjectIds, [_projectId, _projectId]);
    expect(
      find.byKey(const ValueKey('original-region-report-directory-heading')),
      findsOneWidget,
    );
    semantics.dispose();
  });

  testWidgets('10000 个城市成对数据使用纵向虚拟列表', (tester) async {
    final gateway = _QueueGateway(
      directory: _directoryWithSummary,
      snapshotResult: OriginalRegionReportSuccess(_snapshot(cityCount: 10000)),
    );

    await tester.pumpWidget(_app(gateway));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(ValueKey('original-region-report-${_summary.snapshotId}')),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const ValueKey('original-region-report-city-list')),
      findsOneWidget,
    );
    expect(find.text('城市 ID：city-00000'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('original-region-report-city-city-09999')),
      findsNothing,
    );
    expect(find.byType(ListView), findsOneWidget);
  });
}

Widget _app(
  OriginalRegionReportGateway gateway, {
  AppStrings text = const AppStrings('zh'),
  TextScaler textScaler = TextScaler.noScaling,
  String projectId = _projectId,
}) => MaterialApp(
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: textScaler),
    child: child!,
  ),
  home: Scaffold(
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(8),
      child: OriginalRegionReportPanel(
        text: text,
        gateway: gateway,
        projectId: projectId,
      ),
    ),
  ),
);

final class _QueueGateway implements OriginalRegionReportGateway {
  _QueueGateway({
    OriginalRegionReportSnapshotDirectory? directory,
    this.snapshotResult,
    List<OriginalRegionReportResult<OriginalRegionReportSnapshotDirectory>>?
    directoryResults,
  }) : _directoryResults =
           directoryResults ??
           [OriginalRegionReportSuccess(directory ?? _emptyDirectory)];

  final List<OriginalRegionReportResult<OriginalRegionReportSnapshotDirectory>>
  _directoryResults;
  OriginalRegionReportResult<OriginalRegionReportSnapshot>? snapshotResult;
  final listProjectIds = <String>[];
  final readRequests = <(String, OriginalRegionReportSnapshotSummary)>[];
  var _directoryIndex = 0;

  @override
  Future<void> close() async {}

  @override
  Future<OriginalRegionReportResult<OriginalRegionReportSnapshotDirectory>>
  listSnapshots(String projectId) async {
    listProjectIds.add(projectId);
    return _directoryResults[_directoryIndex++];
  }

  @override
  Future<OriginalRegionReportResult<OriginalRegionReportSnapshot>>
  readSnapshot({
    required String projectId,
    required OriginalRegionReportSnapshotSummary summary,
  }) async {
    readRequests.add((projectId, summary));
    return snapshotResult ??
        const OriginalRegionReportRejected(
          OriginalRegionReportFailureCode.notFound,
        );
  }
}

OriginalRegionReportSnapshotDirectory _directory({
  required List<OriginalRegionReportSnapshotSummary> snapshots,
  String projectId = _projectId,
}) => OriginalRegionReportSnapshotDirectory(
  accessEventId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  projectId: projectId,
  snapshots: snapshots,
);

final _emptyDirectory = _directory(snapshots: const []);
final _directoryWithSummary = _directory(snapshots: [_summary]);

final _summary = OriginalRegionReportSnapshotSummary(
  snapshotId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  reportId: 'contact_sessions_by_original_region_two_periods',
  reportVersion: 1,
  reportingTimeZone: 'America/Chicago',
  dataCutoffUtc: DateTime.utc(2030, 1, 15, 1),
  releasedAtUtc: DateTime.utc(2030, 1, 15, 2),
);

final _secondSummary = OriginalRegionReportSnapshotSummary(
  snapshotId: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
  reportId: 'contact_sessions_by_original_region_two_periods',
  reportVersion: 1,
  reportingTimeZone: 'America/Chicago',
  dataCutoffUtc: DateTime.utc(2030, 1, 8, 1),
  releasedAtUtc: DateTime.utc(2030, 1, 8, 2),
);

OriginalRegionReportSnapshot _snapshot({int cityCount = 2}) {
  final cells = <OriginalRegionReportCell>[
    for (var cityIndex = 0; cityIndex < cityCount; cityIndex++)
      OriginalRegionReportCell(
        periodKey: OriginalRegionReportPeriodKey.previous,
        cityId: 'city-${cityIndex.toString().padLeft(5, '0')}',
        cellOrder: cityIndex,
        valueCount: cityIndex.isEven ? 12 + cityIndex : null,
        privacyStatus: cityIndex.isEven
            ? OriginalRegionReportPrivacyStatus.displayed
            : OriginalRegionReportPrivacyStatus.suppressed,
      ),
    for (var cityIndex = 0; cityIndex < cityCount; cityIndex++)
      OriginalRegionReportCell(
        periodKey: OriginalRegionReportPeriodKey.current,
        cityId: 'city-${cityIndex.toString().padLeft(5, '0')}',
        cellOrder: cityCount + cityIndex,
        valueCount: cityIndex.isEven ? 20 + cityIndex : null,
        privacyStatus: cityIndex.isEven
            ? OriginalRegionReportPrivacyStatus.displayed
            : OriginalRegionReportPrivacyStatus.suppressed,
      ),
  ];
  return OriginalRegionReportSnapshot(
    accessEventId: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
    summary: _summary,
    report: OriginalRegionReportDocument(
      reportId: _summary.reportId,
      reportVersion: _summary.reportVersion,
      metricId: 'contact_sessions',
      metricVersion: 1,
      dimension: 'original_region',
      viewMode: 'original',
      regionGranularity: 'city',
      queryFingerprint:
          'management-report:contact_sessions_by_original_region_two_periods:v1',
      privacyPolicy: 'management_original_region_contact_session_privacy_v1',
      sourceScope: 'backend_accepted_active_contacts_original_current_revision',
      projectId: _projectId,
      periods: OriginalRegionReportPeriods(
        periodBoundaryId: 'iso_week_monday_v1',
        reportingTimeZone: _summary.reportingTimeZone,
        dataCutoffUtc: _summary.dataCutoffUtc,
        previousPeriod: OriginalRegionReportPeriod(
          startUtc: DateTime.utc(2029, 12, 30),
          untilUtc: DateTime.utc(2030, 1, 6),
        ),
        currentPeriod: OriginalRegionReportPeriod(
          startUtc: DateTime.utc(2030, 1, 6),
          untilUtc: DateTime.utc(2030, 1, 13),
        ),
      ),
      dataCutoffUtc: _summary.dataCutoffUtc,
      sourceChangeSequence: 12,
      sourceTreeContext: const OriginalRegionReportSourceTreeContext(
        contractId: 'management-original-region-source-tree:v1',
        resultStatus: 'selected',
        reasonCode: 'single_original_source_tree',
        sourceTreeVersion: 'tree-2030-01',
        sourceContentFingerprint:
            'abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789',
      ),
      resultStatus: 'completed',
      cells: cells,
    ),
  );
}

void _compactView(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(320, 568);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
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
const _otherProjectId = '44444444-4444-4444-8444-444444444444';
