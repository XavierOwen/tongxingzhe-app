import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tongxingzhe_app/features/management_reports/management_report_browser.dart';
import 'package:tongxingzhe_app/l10n/app_strings.dart';
import 'package:tongxingzhe_app/management_reports/management_report_gateway.dart';

void main() {
  testWidgets('320 宽和 200% 文字下目录与项目选择不溢出', (tester) async {
    _compactView(tester);

    await tester.pumpWidget(
      _app(
        _Gateway(
          context: _contextSnapshot(current: _projectA),
          summaries: [_summary],
        ),
        textScaler: TextScaler.linear(2),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('management-project-picker')), findsOne);
    expect(
      find.byKey(ValueKey('management-report-${_summary.snapshotId}')),
      findsOne,
    );
  });

  testWidgets('键盘按视觉顺序打开报告，返回后恢复目录项焦点', (tester) async {
    _compactView(tester);
    await tester.pumpWidget(
      _app(
        _Gateway(
          context: _contextSnapshot(current: _projectA),
          summaries: [_summary],
          snapshot: _snapshot,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final picker = find.byKey(const ValueKey('management-project-picker'));
    final item = find.byKey(
      ValueKey('management-report-${_summary.snapshotId}'),
    );
    await _tabTo(tester, picker);
    await _tabTo(tester, item);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    final back = find.byKey(const ValueKey('management-report-back'));
    expect(back, findsOneWidget);
    expect(_containsPrimaryFocus(tester, back), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(item, findsOneWidget);
    expect(_containsPrimaryFocus(tester, item), isTrue);
  });

  testWidgets('报告逐格读出期间、渠道和隐私状态，隐藏格不显示零', (tester) async {
    final semantics = tester.ensureSemantics();
    _compactView(tester);
    await tester.pumpWidget(
      _app(
        _Gateway(
          context: _contextSnapshot(current: _projectA),
          summaries: [_summary],
          snapshot: _snapshot,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(ValueKey('management-report-${_summary.snapshotId}')),
    );
    await tester.pumpAndSettle();

    final previousFaceToFace = find.byKey(
      const ValueKey('management-report-cell-previous-face_to_face'),
    );
    await tester.scrollUntilVisible(
      previousFaceToFace,
      120,
      scrollable: find.byType(Scrollable).first,
    );
    expect(tester.getSemantics(previousFaceToFace).label, '较早完整周，面对面：已隐藏');
    final currentFaceToFace = find.byKey(
      const ValueKey('management-report-cell-current-face_to_face'),
    );
    await tester.scrollUntilVisible(
      currentFaceToFace,
      120,
      scrollable: find.byType(Scrollable).first,
    );
    expect(tester.getSemantics(currentFaceToFace).label, '较晚完整周，面对面：12 接触场次');
    expect(find.text('0'), findsNothing);
    expect(find.bySemanticsLabel(RegExp('打开报告')), findsNothing);
    semantics.dispose();
  });

  testWidgets('没有保存项目时明确要求选择，空授权列表不自动选择', (tester) async {
    await tester.pumpWidget(
      _app(_Gateway(context: _contextSnapshot(current: null, available: []))),
    );
    await tester.pumpAndSettle();

    expect(find.text('选择一个项目以查看受保护的管理报告。'), findsOneWidget);
    expect(find.text('没有可读取管理报告的项目。'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('management-project-picker')),
      findsNothing,
    );
  });

  testWidgets('网络失败显示 live region 和可重试动作', (tester) async {
    final gateway = _Gateway(
      contextResult: const ManagementReportRejected(
        ManagementReportFailureCode.networkUnavailable,
      ),
    );
    await tester.pumpWidget(_app(gateway));
    await tester.pumpAndSettle();

    expect(find.text('无法连接管理报告服务，请检查网络后重试。'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('management-report-retry')),
      findsOneWidget,
    );
  });
}

Widget _app(_Gateway gateway, {TextScaler textScaler = TextScaler.noScaling}) =>
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: textScaler),
        child: child!,
      ),
      home: Scaffold(
        body: ManagementReportBrowser(
          text: const AppStrings('zh'),
          gateway: gateway,
        ),
      ),
    );

void _compactView(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(320, 568);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}

Future<void> _tabTo(WidgetTester tester, Finder target) async {
  await tester.sendKeyEvent(LogicalKeyboardKey.tab);
  await tester.pump();
  expect(_containsPrimaryFocus(tester, target), isTrue);
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

final class _Gateway implements ManagementReportGateway {
  _Gateway({
    ManagementAnalysisContextSnapshot? context,
    ManagementReportResult<ManagementAnalysisContextSnapshot>? contextResult,
    this.summaries = const [],
    this.snapshot,
  }) : contextResult =
           contextResult ??
           ManagementReportSuccess(context ?? _contextSnapshot(current: null));

  ManagementReportResult<ManagementAnalysisContextSnapshot> contextResult;
  final List<ManagementReportSnapshotSummary> summaries;
  final ManagementReportSnapshot? snapshot;

  @override
  Future<void> close() async {}

  @override
  Future<ManagementReportResult<ManagementAnalysisContextSnapshot>>
  loadContext() async => contextResult;

  @override
  Future<ManagementReportResult<List<ManagementReportSnapshotSummary>>>
  listSnapshots(String projectId) async => ManagementReportSuccess(summaries);

  @override
  Future<ManagementReportResult<ManagementReportSnapshot>> readSnapshot({
    required String projectId,
    required ManagementReportSnapshotSummary summary,
  }) async => snapshot == null
      ? const ManagementReportRejected(ManagementReportFailureCode.notFound)
      : ManagementReportSuccess(snapshot!);

  @override
  Future<ManagementReportResult<ManagementAnalysisContextSnapshot>>
  selectContext(String projectId) async => contextResult;
}

ManagementAnalysisContextSnapshot _contextSnapshot({
  required ManagementAnalysisContext? current,
  List<ManagementAnalysisContext> available = const [_projectA, _projectB],
}) => ManagementAnalysisContextSnapshot(current: current, available: available);

const _projectA = ManagementAnalysisContext(
  organizationId: '11111111-1111-4111-8111-111111111111',
  organizationName: '第一组织',
  projectId: '22222222-2222-4222-8222-222222222222',
  projectName: '第一项目',
);
const _projectB = ManagementAnalysisContext(
  organizationId: '33333333-3333-4333-8333-333333333333',
  organizationName: '第二组织',
  projectId: '44444444-4444-4444-8444-444444444444',
  projectName: '第二项目',
);

final _summary = ManagementReportSnapshotSummary(
  snapshotId: '55555555-5555-4555-8555-555555555555',
  reportId: 'contact_sessions_by_channel_two_periods',
  reportVersion: 1,
  reportingTimeZone: 'America/Chicago',
  dataCutoffUtc: DateTime.utc(2030, 1, 22),
  releasedAtUtc: DateTime.utc(2030, 1, 22, 0, 1),
);

final _snapshot = ManagementReportSnapshot(
  summary: _summary,
  report: ProtectedManagementReport(
    reportId: 'contact_sessions_by_channel_two_periods',
    reportVersion: 1,
    metricId: 'contact_sessions',
    metricVersion: 1,
    dimension: 'channel',
    queryFingerprint:
        'management-report:contact_sessions_by_channel_two_periods:v1',
    privacyPolicy: 'management_contact_session_privacy_v1',
    sourceScope: 'backend_accepted_contacts',
    projectId: _projectA.projectId,
    periodBoundaryId: 'iso_week_monday_v1',
    reportingTimeZone: 'America/Chicago',
    dataCutoffUtc: DateTime.utc(2030, 1, 22),
    previousPeriod: ManagementReportPeriod(
      startUtc: DateTime.utc(2030, 1, 7, 6),
      untilUtc: DateTime.utc(2030, 1, 14, 6),
    ),
    currentPeriod: ManagementReportPeriod(
      startUtc: DateTime.utc(2030, 1, 14, 6),
      untilUtc: DateTime.utc(2030, 1, 21, 6),
    ),
    cells: [
      for (final period in ManagementReportPeriodKey.values)
        for (var index = 0; index < _categories.length; index++)
          ProtectedManagementReportCell(
            periodKey: period,
            categoryKey: _categories[index],
            cellOrder: period.index * _categories.length + index,
            valueCount:
                period == ManagementReportPeriodKey.current && index == 1
                ? 12
                : null,
            privacyStatus:
                period == ManagementReportPeriodKey.current && index == 1
                ? ManagementReportPrivacyStatus.displayed
                : ManagementReportPrivacyStatus.suppressed,
          ),
    ],
  ),
);

const _categories = [
  'all',
  'face_to_face',
  'voice_call',
  'video_call',
  'instant_text',
  'asynchronous_message',
  'mixed',
  'other_direct',
];
