import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tongxingzhe_app/features/management_reports/interest_report_panel.dart';
import 'package:tongxingzhe_app/l10n/app_strings.dart';
import 'package:tongxingzhe_app/management_reports/interest_report_gateway.dart';

void main() {
  testWidgets('目录不自动打开第一项，用户选择后显示固定十格报告', (tester) async {
    final semantics = tester.ensureSemantics();
    final gateway = _QueueGateway(
      directory: _directoryWithSummary,
      snapshotResult: InterestReportSuccess(_snapshot()),
    );

    await tester.pumpWidget(_app(gateway));
    await tester.pumpAndSettle();

    expect(gateway.listProjectIds, [_projectId]);
    expect(gateway.readRequests, isEmpty);
    expect(
      find.byKey(ValueKey('interest-report-${_summary.snapshotId}')),
      findsOneWidget,
    );
    expect(
      tester
          .getSemantics(
            find.byKey(ValueKey('interest-report-${_summary.snapshotId}')),
          )
          .label,
      contains('数据截止 2030-01-15T01:00:00.000Z'),
    );
    expect(find.byKey(const ValueKey('interest-report-back')), findsNothing);
    expect(
      tester
          .getSemantics(find.byKey(const ValueKey('interest-report-heading')))
          .getSemanticsData()
          .flagsCollection
          .isHeader,
      isTrue,
    );
    expect(
      tester
          .getSemantics(
            find.byKey(const ValueKey('interest-report-directory-heading')),
          )
          .getSemanticsData()
          .flagsCollection
          .isHeader,
      isTrue,
    );

    await tester.tap(
      find.byKey(ValueKey('interest-report-${_summary.snapshotId}')),
    );
    await tester.pumpAndSettle();

    expect(gateway.readRequests.single, (_projectId, _summary));
    expect(find.text('interest_distribution@1'), findsOneWidget);
    expect(find.text('contact_session'), findsOneWidget);
    expect(find.text('interest_level'), findsOneWidget);
    expect(
      tester
          .widget<ListView>(
            find.byKey(const ValueKey('interest-report-cell-list')),
          )
          .childrenDelegate
          .estimatedChildCount,
      10,
    );
    expect(find.textContaining(RegExp(r'^\d+ 次接触$')), findsNWidgets(5));
    expect(find.text('10 次接触'), findsOneWidget);
    expect(find.text('已隐藏'), findsNWidgets(5));
    expect(find.text('0 次接触'), findsNothing);
    expect(find.text('0'), findsNothing);
    expect(
      tester
          .getSemantics(
            find.byKey(const ValueKey('interest-report-detail-heading')),
          )
          .getSemanticsData()
          .flagsCollection
          .isHeader,
      isTrue,
    );
    expect(
      tester
          .getSemantics(
            find.byKey(const ValueKey('interest-report-period-heading')),
          )
          .getSemanticsData()
          .flagsCollection
          .isHeader,
      isTrue,
    );
    expect(
      tester
          .getSemantics(
            find.byKey(const ValueKey('interest-report-cell-list-heading')),
          )
          .getSemanticsData()
          .flagsCollection
          .isHeader,
      isTrue,
    );
    expect(
      tester
          .getSemantics(
            find.byKey(const ValueKey('interest-report-cell-current-0')),
          )
          .label,
      contains('已隐藏'),
    );
    expect(
      tester
          .getSemantics(
            find.byKey(const ValueKey('interest-report-live-region')),
          )
          .getSemanticsData()
          .flagsCollection
          .isLiveRegion,
      isTrue,
    );
    semantics.dispose();
  });

  testWidgets('空目录是成功空态，不读取详情', (tester) async {
    final gateway = _QueueGateway(directory: _emptyDirectory);

    await tester.pumpWidget(_app(gateway));
    await tester.pumpAndSettle();

    expect(find.text('当前项目没有可读取的兴趣报告快照。'), findsOneWidget);
    expect(gateway.readRequests, isEmpty);
  });

  testWidgets('320 宽与 200% 字号下十格列表不横向溢出', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final semantics = tester.ensureSemantics();
    final gateway = _QueueGateway(
      directory: _directoryWithSummary,
      snapshotResult: InterestReportSuccess(_snapshot()),
    );

    await tester.pumpWidget(_app(gateway, textScaler: TextScaler.linear(2)));
    await tester.pumpAndSettle();
    final item = find.byKey(ValueKey('interest-report-${_summary.snapshotId}'));
    await tester.ensureVisible(item);
    await tester.tap(item);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final firstCell = find.byKey(
      const ValueKey('interest-report-cell-previous-0'),
    );
    await tester.ensureVisible(firstCell);
    expect(firstCell, findsOneWidget);
    expect(tester.getSemantics(firstCell).label, contains('10 次接触'));
    final lastCell = find.byKey(
      const ValueKey('interest-report-cell-current-4'),
    );
    await tester.scrollUntilVisible(
      lastCell,
      120,
      scrollable: find
          .descendant(
            of: find.byKey(const ValueKey('interest-report-cell-list')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(lastCell, findsOneWidget);
    expect(tester.getSemantics(lastCell).label, contains('已隐藏'));
    expect(tester.takeException(), isNull);
    expect(
      tester
          .getSemantics(
            find.byKey(const ValueKey('interest-report-live-region')),
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
        InterestReportSuccess(_directory(snapshots: [_summary])),
        InterestReportSuccess(
          _directory(projectId: _otherProjectId, snapshots: [_secondSummary]),
        ),
      ],
      snapshotResult: InterestReportSuccess(_snapshot()),
    );
    await tester.pumpWidget(_app(gateway));
    await tester.pumpAndSettle();

    final oldItem = find.byKey(
      ValueKey('interest-report-${_summary.snapshotId}'),
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
      ValueKey('interest-report-${_secondSummary.snapshotId}'),
    );
    expect(newItem, findsOneWidget);
    await _tabTo(tester, newItem);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(_containsPrimaryFocus(tester, newItem), isTrue);
  });

  testWidgets('键盘正反向遍历、Enter 打开、Escape 返回并恢复快照焦点', (tester) async {
    final gateway = _QueueGateway(
      directory: _directory(snapshots: [_summary, _secondSummary]),
      snapshotResult: InterestReportSuccess(_snapshot()),
    );
    await tester.pumpWidget(_app(gateway));
    await tester.pumpAndSettle();

    final item = find.byKey(ValueKey('interest-report-${_summary.snapshotId}'));
    await _tabTo(tester, item);
    final secondItem = find.byKey(
      ValueKey('interest-report-${_secondSummary.snapshotId}'),
    );
    await _tabTo(tester, secondItem);
    await _shiftTab(tester);
    expect(_containsPrimaryFocus(tester, item), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    final back = find.byKey(const ValueKey('interest-report-back'));
    expect(back, findsOneWidget);
    expect(_containsPrimaryFocus(tester, back), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.text('兴趣报告快照目录'), findsOneWidget);
    expect(_containsPrimaryFocus(tester, item), isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('interest-report-back')), findsOneWidget);
  });

  testWidgets('失败是 live region，重试可恢复且英文文案不混入中文', (tester) async {
    final semantics = tester.ensureSemantics();
    final gateway = _QueueGateway(
      directoryResults: [
        const InterestReportRejected(InterestReportFailureCode.forbidden),
        InterestReportSuccess(_emptyDirectory),
      ],
    );

    await tester.pumpWidget(_app(gateway, text: const AppStrings('en')));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'This account cannot read interest reports for this management project.',
      ),
      findsOneWidget,
    );
    expect(find.text('重试'), findsNothing);
    expect(find.text('Retry'), findsOneWidget);
    expect(
      tester
          .getSemantics(find.byKey(const ValueKey('interest-report-failure')))
          .getSemanticsData()
          .flagsCollection
          .isLiveRegion,
      isTrue,
    );

    await tester.tap(find.byKey(const ValueKey('interest-report-retry')));
    await tester.pumpAndSettle();
    expect(
      find.text('This project has no interest report snapshots to read.'),
      findsOneWidget,
    );
    expect(gateway.listProjectIds, [_projectId, _projectId]);
    semantics.dispose();
  });
}

Widget _app(
  InterestReportGateway gateway, {
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
      child: InterestReportPanel(
        text: text,
        gateway: gateway,
        projectId: projectId,
      ),
    ),
  ),
);

final class _QueueGateway implements InterestReportGateway {
  _QueueGateway({
    InterestReportSnapshotDirectory? directory,
    this.snapshotResult,
    List<InterestReportResult<InterestReportSnapshotDirectory>>?
    directoryResults,
  }) : _directoryResults =
           directoryResults ??
           [InterestReportSuccess(directory ?? _emptyDirectory)];

  final List<InterestReportResult<InterestReportSnapshotDirectory>>
  _directoryResults;
  InterestReportResult<InterestReportSnapshot>? snapshotResult;
  final listProjectIds = <String>[];
  final readRequests = <(String, InterestReportSnapshotSummary)>[];
  var _directoryIndex = 0;

  @override
  Future<InterestReportResult<InterestReportSnapshotDirectory>> listSnapshots(
    String projectId,
  ) async {
    listProjectIds.add(projectId);
    return _directoryResults[_directoryIndex++];
  }

  @override
  Future<InterestReportResult<InterestReportSnapshot>> readSnapshot({
    required String projectId,
    required InterestReportSnapshotSummary summary,
  }) async {
    readRequests.add((projectId, summary));
    return snapshotResult ??
        const InterestReportRejected(InterestReportFailureCode.notFound);
  }

  @override
  Future<void> close() async {}
}

InterestReportSnapshotDirectory _directory({
  required List<InterestReportSnapshotSummary> snapshots,
  String projectId = _projectId,
}) => InterestReportSnapshotDirectory(
  accessEventId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  projectId: projectId,
  snapshots: snapshots,
);

final _emptyDirectory = _directory(snapshots: const []);
final _directoryWithSummary = _directory(snapshots: [_summary]);

final _summary = InterestReportSnapshotSummary(
  snapshotId: '88888888-8888-4888-8888-888888888888',
  reportId: 'contact_sessions_by_interest_level_two_periods',
  reportVersion: 1,
  reportingTimeZone: 'America/Chicago',
  dataCutoffUtc: DateTime.utc(2030, 1, 15, 1),
  releasedAtUtc: DateTime.utc(2030, 1, 15, 2),
);

final _secondSummary = InterestReportSnapshotSummary(
  snapshotId: '77777777-7777-4777-8777-777777777777',
  reportId: 'contact_sessions_by_interest_level_two_periods',
  reportVersion: 1,
  reportingTimeZone: 'America/Chicago',
  dataCutoffUtc: DateTime.utc(2030, 1, 8, 1),
  releasedAtUtc: DateTime.utc(2030, 1, 8, 2),
);

InterestReportSnapshot _snapshot() => InterestReportSnapshot(
  accessEventId: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
  summary: _summary,
  report: InterestReportDocument(
    reportId: _summary.reportId,
    reportVersion: _summary.reportVersion,
    metricId: 'interest_distribution',
    metricVersion: 1,
    statisticalUnit: 'contact_session',
    dimension: 'interest_level',
    queryFingerprint:
        'management-report:contact_sessions_by_interest_level_two_periods:v1',
    privacyPolicy: 'management_interest_distribution_privacy_v1',
    sourceScope: 'backend_accepted_active_contacts_current_revision',
    projectId: _projectId,
    periods: InterestReportPeriods(
      periodBoundaryId: 'iso_week_monday_v1',
      reportingTimeZone: 'America/Chicago',
      dataCutoffUtc: _summary.dataCutoffUtc,
      previousPeriod: InterestReportPeriod(
        startUtc: DateTime.utc(2029, 12, 30),
        untilUtc: DateTime.utc(2030, 1, 6),
      ),
      currentPeriod: InterestReportPeriod(
        startUtc: DateTime.utc(2030, 1, 6),
        untilUtc: DateTime.utc(2030, 1, 13),
      ),
    ),
    cells: [
      for (var level = 0; level < 5; level++)
        InterestReportCell(
          periodKey: InterestReportPeriodKey.previous,
          interestLevel: level,
          cellOrder: level,
          valueCount: 10 + level,
          privacyStatus: InterestReportPrivacyStatus.displayed,
        ),
      for (var level = 0; level < 5; level++)
        InterestReportCell(
          periodKey: InterestReportPeriodKey.current,
          interestLevel: level,
          cellOrder: 5 + level,
          valueCount: null,
          privacyStatus: InterestReportPrivacyStatus.suppressed,
        ),
    ],
  ),
);

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
