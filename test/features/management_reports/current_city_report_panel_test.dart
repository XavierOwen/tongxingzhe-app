import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tongxingzhe_app/features/management_reports/current_city_report_panel.dart';
import 'package:tongxingzhe_app/l10n/app_strings.dart';
import 'package:tongxingzhe_app/management_reports/current_city_report_gateway.dart';

void main() {
  testWidgets('目录不自动打开第一项，用户选择后显示固定报告元数据', (tester) async {
    final semantics = tester.ensureSemantics();
    final gateway = _QueueGateway(
      directory: _directory(),
      snapshotResult: _snapshot(),
    );

    await tester.pumpWidget(_app(gateway));
    await tester.pumpAndSettle();

    expect(gateway.listProjectIds, [_projectId]);
    expect(gateway.readRequests, isEmpty);
    expect(
      find.byKey(ValueKey('current-city-report-${_summary.snapshotId}')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('current-city-report-back')),
      findsNothing,
    );
    expect(
      tester
          .getSemantics(
            find.byKey(const ValueKey('current-city-report-heading')),
          )
          .getSemanticsData()
          .flagsCollection
          .isHeader,
      isTrue,
    );
    expect(
      tester
          .getSemantics(
            find.byKey(const ValueKey('current-city-report-directory-heading')),
          )
          .getSemanticsData()
          .flagsCollection
          .isHeader,
      isTrue,
    );

    await tester.tap(
      find.byKey(ValueKey('current-city-report-${_summary.snapshotId}')),
    );
    await tester.pumpAndSettle();

    expect(gateway.readRequests.single, (_projectId, _summary));
    expect(find.textContaining('城市分布报告'), findsNWidgets(2));
    expect(find.text('报告定义'), findsNWidgets(2));
    expect(
      find.text('contact_sessions_by_current_city_two_periods@1'),
      findsOneWidget,
    );
    expect(find.text('报告时区'), findsOneWidget);
    expect(find.text('America/Chicago'), findsOneWidget);
    expect(find.text('目标上下文'), findsOneWidget);
    expect(find.text('management-region-target-context:v1'), findsOneWidget);
    expect(find.text('显示格数：2'), findsOneWidget);
    expect(find.textContaining('已隐藏'), findsNWidgets(2));
    expect(find.text('0'), findsNothing);
    expect(
      tester
          .getSemantics(
            find.byKey(const ValueKey('current-city-report-detail-heading')),
          )
          .getSemanticsData()
          .flagsCollection
          .isHeader,
      isTrue,
    );
    expect(
      tester
          .getSemantics(
            find.byKey(const ValueKey('current-city-report-period-heading')),
          )
          .getSemanticsData()
          .flagsCollection
          .isHeader,
      isTrue,
    );
    expect(
      tester
          .getSemantics(
            find.byKey(const ValueKey('current-city-report-city-list-heading')),
          )
          .getSemanticsData()
          .flagsCollection
          .isHeader,
      isTrue,
    );
    final hiddenCity = tester
        .getSemantics(
          find.byKey(const ValueKey('current-city-report-city-city-00001')),
        )
        .label;
    expect(hiddenCity, contains('已隐藏'));
    expect(hiddenCity, isNot(contains('：0 次')));
    expect(find.text('城市：city-00000'), findsOneWidget);
    expect(find.textContaining('最新'), findsNothing);
    expect(find.textContaining('latest'), findsNothing);
    semantics.dispose();
  });

  testWidgets('320 宽与 200% 字号下城市成对列表不横向溢出', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final semantics = tester.ensureSemantics();
    final gateway = _QueueGateway(
      directory: _directory(),
      snapshotResult: _snapshot(),
    );

    await tester.pumpWidget(_app(gateway, textScaler: TextScaler.linear(2)));
    await tester.pumpAndSettle();
    final item = find.byKey(
      ValueKey('current-city-report-${_summary.snapshotId}'),
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
            find.byKey(const ValueKey('current-city-report-live-region')),
          )
          .getSemanticsData()
          .flagsCollection
          .isLiveRegion,
      isTrue,
    );
    semantics.dispose();
  });

  testWidgets('键盘正反向遍历、进入、Escape 返回并恢复原快照焦点', (tester) async {
    final gateway = _QueueGateway(
      directory: _directory(snapshots: [_summary, _secondSummary]),
      snapshotResult: _snapshot(),
    );
    await tester.pumpWidget(_app(gateway));
    await tester.pumpAndSettle();

    final item = find.byKey(
      ValueKey('current-city-report-${_summary.snapshotId}'),
    );
    await _tabTo(tester, item);
    final secondItem = find.byKey(
      ValueKey('current-city-report-${_secondSummary.snapshotId}'),
    );
    await _tabTo(tester, secondItem);
    await _shiftTab(tester);
    expect(_containsPrimaryFocus(tester, item), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    final back = find.byKey(const ValueKey('current-city-report-back'));
    expect(back, findsOneWidget);
    expect(_containsPrimaryFocus(tester, back), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.text('城市快照目录'), findsOneWidget);
    expect(_containsPrimaryFocus(tester, item), isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('current-city-report-back')),
      findsOneWidget,
    );
  });

  testWidgets('失败是 live region，重试可恢复且英文不混入中文', (tester) async {
    final gateway = _QueueGateway(
      directoryResults: [
        CurrentCityReportRejected(CurrentCityReportFailureCode.forbidden),
        CurrentCityReportSuccess(_emptyDirectory),
      ],
    );
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(_app(gateway, text: const AppStrings('en')));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'This account cannot read city reports for this management project.',
      ),
      findsOneWidget,
    );
    expect(find.text('重试'), findsNothing);
    expect(find.text('Retry'), findsOneWidget);
    expect(
      tester
          .getSemantics(
            find.byKey(const ValueKey('current-city-report-failure')),
          )
          .getSemanticsData()
          .flagsCollection
          .isLiveRegion,
      isTrue,
    );

    await tester.tap(find.byKey(const ValueKey('current-city-report-retry')));
    await tester.pumpAndSettle();
    expect(
      find.text('This project has no city report snapshots to read.'),
      findsOneWidget,
    );
    expect(gateway.listProjectIds, [_projectId, _projectId]);
    semantics.dispose();
  });

  testWidgets('10000 个城市成对数据使用纵向虚拟列表', (tester) async {
    final gateway = _QueueGateway(
      directory: _directory(),
      snapshotResult: _snapshot(cityCount: 10000),
    );
    await tester.pumpWidget(_app(gateway));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(ValueKey('current-city-report-${_summary.snapshotId}')),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const ValueKey('current-city-report-city-list')),
      findsOneWidget,
    );
    expect(find.text('城市：city-00000'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('current-city-report-city-city-09999')),
      findsNothing,
    );
    expect(find.byType(ListView), findsOneWidget);
  });
}

Widget _app(
  CurrentCityReportGateway gateway, {
  AppStrings text = const AppStrings('zh'),
  TextScaler textScaler = TextScaler.noScaling,
}) => MediaQuery(
  data: MediaQueryData(textScaler: textScaler),
  child: MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(8),
        child: CurrentCityReportPanel(
          text: text,
          gateway: gateway,
          projectId: _projectId,
        ),
      ),
    ),
  ),
);

CurrentCityReportSnapshotDirectory _directory({
  List<CurrentCityReportSnapshotSummary> snapshots = const [],
}) => CurrentCityReportSnapshotDirectory(
  accessEventId: 'access-directory-1',
  projectId: _projectId,
  snapshots: snapshots.isEmpty ? [_summary] : snapshots,
);

final _emptyDirectory = CurrentCityReportSnapshotDirectory(
  accessEventId: 'access-directory-empty',
  projectId: _projectId,
  snapshots: [],
);

final _summary = CurrentCityReportSnapshotSummary(
  snapshotId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  reportId: 'contact_sessions_by_current_city_two_periods',
  reportVersion: 1,
  reportingTimeZone: 'America/Chicago',
  dataCutoffUtc: DateTime.utc(2030, 1, 15, 1),
  releasedAtUtc: DateTime.utc(2030, 1, 15, 2),
);

final _secondSummary = CurrentCityReportSnapshotSummary(
  snapshotId: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
  reportId: 'contact_sessions_by_current_city_two_periods',
  reportVersion: 1,
  reportingTimeZone: 'America/Chicago',
  dataCutoffUtc: DateTime.utc(2030, 1, 22, 1),
  releasedAtUtc: DateTime.utc(2030, 1, 22, 2),
);

CurrentCityReportSnapshot _snapshot({int cityCount = 2}) {
  final cells = <CurrentCityReportCell>[
    for (var cityIndex = 0; cityIndex < cityCount; cityIndex++)
      CurrentCityReportCell(
        periodKey: CurrentCityReportPeriodKey.previous,
        cityId: 'city-${cityIndex.toString().padLeft(5, '0')}',
        cellOrder: cityIndex,
        valueCount: cityIndex.isEven ? 10 + cityIndex : null,
        privacyStatus: cityIndex.isEven
            ? CurrentCityReportPrivacyStatus.displayed
            : CurrentCityReportPrivacyStatus.suppressed,
      ),
    for (var cityIndex = 0; cityIndex < cityCount; cityIndex++)
      CurrentCityReportCell(
        periodKey: CurrentCityReportPeriodKey.current,
        cityId: 'city-${cityIndex.toString().padLeft(5, '0')}',
        cellOrder: cityCount + cityIndex,
        valueCount: cityIndex.isEven ? 20 + cityIndex : null,
        privacyStatus: cityIndex.isEven
            ? CurrentCityReportPrivacyStatus.displayed
            : CurrentCityReportPrivacyStatus.suppressed,
      ),
  ];
  return CurrentCityReportSnapshot(
    accessEventId: 'access-detail-1',
    summary: _summary,
    report: CurrentCityReportDocument(
      reportId: _summary.reportId,
      reportVersion: _summary.reportVersion,
      metricId: 'contact_sessions',
      metricVersion: 1,
      dimension: 'current_city',
      viewMode: 'current',
      regionGranularity: 'city',
      queryFingerprint:
          'management-report:contact_sessions_by_current_city_two_periods:v1',
      privacyPolicy: 'management_current_city_contact_session_privacy_v1',
      sourceScope: 'backend_accepted_active_contacts_current_revision',
      projectId: _projectId,
      periods: CurrentCityReportPeriods(
        periodBoundaryId: 'iso_week_monday_v1',
        reportingTimeZone: 'America/Chicago',
        dataCutoffUtc: _summary.dataCutoffUtc,
        previousPeriod: CurrentCityReportPeriod(
          startUtc: DateTime.utc(2029, 12, 30),
          untilUtc: DateTime.utc(2030, 1, 6),
        ),
        currentPeriod: CurrentCityReportPeriod(
          startUtc: DateTime.utc(2030, 1, 6),
          untilUtc: DateTime.utc(2030, 1, 13),
        ),
      ),
      dataCutoffUtc: _summary.dataCutoffUtc,
      sourceChangeSequence: 12,
      targetContext: CurrentCityReportTargetContext(
        contractId: 'management-region-target-context:v1',
        resultStatus: 'selected',
        reasonCode: 'publication_selection',
        dataCutoffUtc: _summary.dataCutoffUtc,
        targetTreeVersion: 'tree-2030-01',
        targetContentFingerprint:
            'abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789',
        selectionSequence: 3,
        selectionSource: 'publication',
        selectionEvidenceAtUtc: DateTime.utc(2030, 1, 14),
        treePublishedAtUtc: DateTime.utc(2030, 1, 7),
      ),
      resultStatus: 'completed',
      cells: cells,
    ),
  );
}

final class _QueueGateway implements CurrentCityReportGateway {
  _QueueGateway({
    CurrentCityReportSnapshotDirectory? directory,
    this._snapshotResult,
    List<CurrentCityReportResult<CurrentCityReportSnapshotDirectory>>?
    directoryResults,
  }) : _directoryResults =
           directoryResults ??
           [CurrentCityReportSuccess(directory ?? _emptyDirectory)];

  final List<CurrentCityReportResult<CurrentCityReportSnapshotDirectory>>
  _directoryResults;
  final CurrentCityReportSnapshot? _snapshotResult;
  final listProjectIds = <String>[];
  final readRequests = <(String, CurrentCityReportSnapshotSummary)>[];
  var _directoryIndex = 0;

  @override
  Future<CurrentCityReportResult<CurrentCityReportSnapshotDirectory>>
  listSnapshots(String projectId) async {
    listProjectIds.add(projectId);
    return _directoryResults[_directoryIndex++];
  }

  @override
  Future<CurrentCityReportResult<CurrentCityReportSnapshot>> readSnapshot({
    required String projectId,
    required CurrentCityReportSnapshotSummary summary,
  }) async {
    readRequests.add((projectId, summary));
    final snapshot = _snapshotResult;
    if (snapshot == null) {
      return const CurrentCityReportRejected(
        CurrentCityReportFailureCode.notFound,
      );
    }
    return CurrentCityReportSuccess(snapshot);
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
