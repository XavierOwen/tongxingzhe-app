import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tongxingzhe_app/features/management_reports/management_report_browser.dart';
import 'package:tongxingzhe_app/l10n/app_strings.dart';
import 'package:tongxingzhe_app/management_reports/current_city_report_gateway.dart';
import 'package:tongxingzhe_app/management_reports/management_report_export_delivery.dart';
import 'package:tongxingzhe_app/management_reports/management_report_gateway.dart';

void main() {
  testWidgets('渠道视图默认，明确选择 current-city 后才读取管理项目目录', (tester) async {
    final currentCityGateway = _CurrentCityGateway();
    await tester.pumpWidget(
      _app(
        _Gateway(
          context: _contextSnapshot(current: _projectA),
          summaries: [_summary],
        ),
        currentCityGateway: currentCityGateway,
      ),
    );
    await tester.pumpAndSettle();

    final channelView = find.byKey(
      const ValueKey('management-channel-report-view'),
    );
    final currentCityView = find.byKey(
      const ValueKey('management-current-city-report-view'),
    );
    expect(tester.widget<ChoiceChip>(channelView).selected, isTrue);
    expect(tester.widget<ChoiceChip>(currentCityView).selected, isFalse);
    expect(find.text('渠道报告'), findsOneWidget);
    expect(find.text('当前城市'), findsOneWidget);
    expect(find.text('managementReportChannelView'), findsNothing);
    expect(currentCityGateway.listedProjectIds, isEmpty);
    expect(currentCityGateway.readRequests, isEmpty);

    await _tabTo(tester, currentCityView);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();

    expect(tester.widget<ChoiceChip>(currentCityView).selected, isTrue);
    expect(currentCityGateway.listedProjectIds, [_projectA.projectId]);
    expect(currentCityGateway.readRequests, isEmpty);
    expect(
      find.byKey(ValueKey('management-report-${_summary.snapshotId}')),
      findsNothing,
    );

    await _shiftTab(tester);
    expect(_containsPrimaryFocus(tester, channelView), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(tester.widget<ChoiceChip>(channelView).selected, isTrue);
    expect(currentCityGateway.readRequests, isEmpty);
  });

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

  testWidgets('报告详情在窄屏大字号下显示中文固定元数据和隐私摘要', (tester) async {
    final semantics = tester.ensureSemantics();
    _compactView(tester);
    await tester.pumpWidget(
      _app(
        _Gateway(
          context: _contextSnapshot(current: _projectA),
          summaries: [_summary],
          snapshot: _snapshot,
        ),
        text: const AppStrings('zh'),
        textScaler: TextScaler.linear(2),
      ),
    );
    await tester.pumpAndSettle();

    await _openReport(tester);

    expect(tester.takeException(), isNull);
    _expectFixedMetadata(
      tester,
      metricLabel: '接触场次 (contact_sessions@1)',
      sourceLabel: '后端已接受的接触',
      privacyLabel: '接触场次隐私规则 v1',
      displayedLabel: '显示格数',
      suppressedLabel: '隐藏格数',
    );
    final summary = tester.getSemantics(
      find.byKey(const ValueKey('management-report-privacy-summary')),
    );
    expect(summary.label, contains('1'));
    expect(summary.label, contains('15'));
    expect(summary.label, isNot(contains('0')));
    expect(find.text('0'), findsNothing);
    expect(find.textContaining('降低披露风险'), findsOneWidget);
    expect(find.textContaining('形式化不可重识别'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('报告详情以英文显示固定元数据和非形式化匿名边界', (tester) async {
    final semantics = tester.ensureSemantics();
    _compactView(tester);
    await tester.pumpWidget(
      _app(
        _Gateway(
          context: _contextSnapshot(current: _projectA),
          summaries: [_summary],
          snapshot: _snapshot,
        ),
        text: const AppStrings('en'),
        textScaler: TextScaler.linear(2),
      ),
    );
    await tester.pumpAndSettle();

    await _openReport(tester);

    expect(tester.takeException(), isNull);
    _expectFixedMetadata(
      tester,
      metricLabel: 'Contact sessions (contact_sessions@1)',
      sourceLabel: 'Backend-accepted contacts',
      privacyLabel: 'Contact session privacy rules v1',
      displayedLabel: 'Displayed cells',
      suppressedLabel: 'Hidden cells',
    );
    final summary = tester.getSemantics(
      find.byKey(const ValueKey('management-report-privacy-summary')),
    );
    expect(summary.label, contains('1'));
    expect(summary.label, contains('15'));
    expect(summary.label, isNot(contains('0')));
    expect(find.text('0'), findsNothing);
    expect(find.textContaining('reduce disclosure risk'), findsOneWidget);
    expect(
      find.textContaining('formal non-re-identification guarantee'),
      findsOneWidget,
    );
    semantics.dispose();
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

  testWidgets('current-city 项目切换失败保留管理上下文重试入口', (tester) async {
    final gateway = _Gateway(
      context: _contextSnapshot(current: _projectA),
      summaries: [_summary],
      selectResult: const ManagementReportRejected(
        ManagementReportFailureCode.networkUnavailable,
      ),
    );
    final currentCityGateway = _CurrentCityGateway();
    await tester.pumpWidget(
      _app(gateway, currentCityGateway: currentCityGateway),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('management-current-city-report-view')),
    );
    await tester.pumpAndSettle();
    expect(currentCityGateway.listedProjectIds, [_projectA.projectId]);

    await tester.tap(find.byKey(const ValueKey('management-project-picker')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('第二组织 · 第二项目').last);
    await tester.pumpAndSettle();

    expect(gateway.selectProjectIds, [_projectB.projectId]);
    expect(find.text('无法连接管理报告服务，请检查网络后重试。'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('management-report-retry')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('current-city-report-panel')),
      findsNothing,
    );

    gateway.selectResult = ManagementReportSuccess(
      _contextSnapshot(current: _projectB),
    );
    await tester.tap(find.byKey(const ValueKey('management-report-retry')));
    await tester.pumpAndSettle();

    expect(gateway.selectProjectIds, [
      _projectB.projectId,
      _projectB.projectId,
    ]);
    expect(currentCityGateway.listedProjectIds, [
      _projectA.projectId,
      _projectB.projectId,
    ]);
    expect(
      find.byKey(const ValueKey('current-city-report-panel')),
      findsOneWidget,
    );
  });

  testWidgets('current-city 目录迟到响应不覆盖已切回的渠道视图', (tester) async {
    final currentCityGateway = _DeferredCurrentCityGateway();
    await tester.pumpWidget(
      _app(
        _Gateway(
          context: _contextSnapshot(current: _projectA),
          summaries: [_summary],
        ),
        currentCityGateway: currentCityGateway,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('management-current-city-report-view')),
    );
    await tester.pump();
    expect(currentCityGateway.listedProjectIds, [_projectA.projectId]);
    expect(
      find.byKey(const ValueKey('current-city-report-panel')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey('management-channel-report-view')),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<ChoiceChip>(
            find.byKey(const ValueKey('management-channel-report-view')),
          )
          .selected,
      isTrue,
    );
    expect(
      find.byKey(ValueKey('management-report-${_summary.snapshotId}')),
      findsOneWidget,
    );

    currentCityGateway.directory.complete(
      CurrentCityReportSuccess(
        CurrentCityReportSnapshotDirectory(
          accessEventId: '77777777-7777-4777-8777-777777777777',
          projectId: _projectA.projectId,
          snapshots: [_currentCitySummary],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<ChoiceChip>(
            find.byKey(const ValueKey('management-channel-report-view')),
          )
          .selected,
      isTrue,
    );
    expect(
      find.byKey(const ValueKey('current-city-report-panel')),
      findsNothing,
    );
    expect(
      find.byKey(ValueKey('management-report-${_summary.snapshotId}')),
      findsOneWidget,
    );
  });

  testWidgets('Backend 未配置时显示明确状态', (tester) async {
    await tester.pumpWidget(
      _app(
        _Gateway(
          contextResult: const ManagementReportRejected(
            ManagementReportFailureCode.notConfigured,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('管理报告服务尚未配置。'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('management-report-retry')),
      findsOneWidget,
    );
  });

  testWidgets('Web 报告先准备 artifact，再由第二次操作请求浏览器下载', (tester) async {
    final semantics = tester.ensureSemantics();
    _compactView(tester);
    final gateway = _Gateway(
      context: _contextSnapshot(current: _projectA),
      summaries: [_summary],
      snapshot: _snapshot,
      exportResult: ManagementReportSuccess(_artifact),
    );
    final delivery = _Delivery();
    await tester.pumpWidget(
      _app(gateway, delivery: delivery, textScaler: TextScaler.linear(2)),
    );
    await tester.pumpAndSettle();
    await _openReport(tester);

    final prepare = find.byKey(
      const ValueKey('management-report-export-prepare'),
    );
    await tester.ensureVisible(prepare);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('准备 JSON 文件'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('management-report-export-request')),
      findsNothing,
    );

    await tester.tap(prepare);
    await tester.pumpAndSettle();

    expect(gateway.exportRequests, [(_projectA.projectId, _summary)]);
    expect(delivery.requests, isEmpty);
    expect(find.textContaining('请再次选择下载'), findsOneWidget);
    final request = find.byKey(
      const ValueKey('management-report-export-request'),
    );
    expect(request, findsOneWidget);
    expect(_containsPrimaryFocus(tester, request), isTrue);
    await tester.ensureVisible(request);
    await tester.pumpAndSettle();

    await tester.tap(request);
    await tester.pumpAndSettle();

    expect(delivery.requests, hasLength(1));
    expect(delivery.requests.single, same(_artifact));
    expect(gateway.exportRequests, hasLength(1));
    expect(find.textContaining('不证明文件已保存'), findsOneWidget);
    expect(
      tester
          .getSemantics(
            find.byKey(const ValueKey('management-report-export-status')),
          )
          .label,
      contains('已向浏览器请求下载'),
    );
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets(
    'English export flow keeps two-stage controls and live status usable',
    (tester) async {
      final semantics = tester.ensureSemantics();
      _compactView(tester);
      final gateway = _Gateway(
        context: _contextSnapshot(current: _projectA),
        summaries: [_summary],
        snapshot: _snapshot,
        exportResult: ManagementReportSuccess(_artifact),
      );
      final delivery = _Delivery();
      await tester.pumpWidget(
        _app(
          gateway,
          text: const AppStrings('en'),
          delivery: delivery,
          textScaler: TextScaler.linear(2),
        ),
      );
      await tester.pumpAndSettle();
      await _openReport(tester);

      final prepare = find.byKey(
        const ValueKey('management-report-export-prepare'),
      );
      await tester.ensureVisible(prepare);
      await tester.pumpAndSettle();
      await tester.tap(prepare);
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Choose download again to continue'),
        findsOneWidget,
      );
      final request = find.byKey(
        const ValueKey('management-report-export-request'),
      );
      expect(find.text('Request browser download'), findsOneWidget);
      expect(_containsPrimaryFocus(tester, request), isTrue);
      await tester.ensureVisible(request);
      await tester.pumpAndSettle();
      await tester.tap(request);
      await tester.pumpAndSettle();

      expect(delivery.requests, hasLength(1));
      expect(gateway.exportRequests, hasLength(1));
      expect(
        tester
            .getSemantics(
              find.byKey(const ValueKey('management-report-export-status')),
            )
            .label,
        contains('Download requested'),
      );
      expect(
        find.textContaining('does not prove that the file was saved'),
        findsOne,
      );
      expect(tester.takeException(), isNull);
      semantics.dispose();
    },
  );

  testWidgets('delivery 失败保留已验证文件，并以同一 artifact 重试', (tester) async {
    final gateway = _Gateway(
      context: _contextSnapshot(current: _projectA),
      summaries: [_summary],
      snapshot: _snapshot,
      exportResult: ManagementReportSuccess(_artifact),
    );
    final delivery = _Delivery(result: const ManagementReportDownloadFailed());
    await tester.pumpWidget(_app(gateway, delivery: delivery));
    await tester.pumpAndSettle();
    await _openReport(tester);

    final prepare = find.byKey(
      const ValueKey('management-report-export-prepare'),
    );
    await tester.ensureVisible(prepare);
    await tester.pumpAndSettle();
    await tester.tap(prepare);
    await tester.pumpAndSettle();
    final request = find.byKey(
      const ValueKey('management-report-export-request'),
    );
    await tester.ensureVisible(request);
    await tester.pumpAndSettle();
    await tester.tap(request);
    await tester.pumpAndSettle();

    expect(find.textContaining('同一份已验证文件重试'), findsOneWidget);
    delivery.result = const ManagementReportDownloadRequested();
    await tester.tap(request);
    await tester.pumpAndSettle();

    expect(delivery.requests, hasLength(2));
    expect(gateway.exportRequests, hasLength(1));
    expect(find.textContaining('不证明文件已保存'), findsOneWidget);
  });

  testWidgets('独立导出权限失败不误写成报告读取权限失败', (tester) async {
    final gateway = _Gateway(
      context: _contextSnapshot(current: _projectA),
      summaries: [_summary],
      snapshot: _snapshot,
      exportResult: const ManagementReportRejected(
        ManagementReportFailureCode.unauthorized,
      ),
    );
    await tester.pumpWidget(_app(gateway, delivery: _Delivery()));
    await tester.pumpAndSettle();
    await _openReport(tester);

    final prepare = find.byKey(
      const ValueKey('management-report-export-prepare'),
    );
    await tester.ensureVisible(prepare);
    await tester.pumpAndSettle();
    await tester.tap(prepare);
    await tester.pumpAndSettle();

    expect(find.text('当前账号没有导出管理报告的权限。'), findsOneWidget);
    expect(find.text('当前账号没有读取管理报告的权限。'), findsNothing);
    expect(find.textContaining('报告版本'), findsWidgets);
    expect(
      find.byKey(const ValueKey('management-report-export-prepare')),
      findsOneWidget,
    );
  });

  testWidgets('非 Web 平台显示 unavailable，不请求导出或文件系统', (tester) async {
    final gateway = _Gateway(
      context: _contextSnapshot(current: _projectA),
      summaries: [_summary],
      snapshot: _snapshot,
      exportResult: ManagementReportSuccess(_artifact),
    );
    await tester.pumpWidget(
      _app(gateway, delivery: _Delivery(isAvailable: false)),
    );
    await tester.pumpAndSettle();
    await _openReport(tester);

    expect(find.text('当前平台不提供 Web 浏览器下载。'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('management-report-export-prepare')),
      findsNothing,
    );
    expect(gateway.exportRequests, isEmpty);
  });
}

Widget _app(
  _Gateway gateway, {
  AppStrings text = const AppStrings('zh'),
  TextScaler textScaler = TextScaler.noScaling,
  ManagementReportExportDelivery? delivery,
  CurrentCityReportGateway? currentCityGateway,
}) => MaterialApp(
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: textScaler),
    child: child!,
  ),
  home: Scaffold(
    body: ManagementReportBrowser(
      text: text,
      gateway: gateway,
      currentCityGateway:
          currentCityGateway ?? const DeferredCurrentCityReportGateway(),
      exportDelivery: delivery ?? _Delivery(isAvailable: false),
    ),
  ),
);

Future<void> _openReport(WidgetTester tester) async {
  final item = find.byKey(ValueKey('management-report-${_summary.snapshotId}'));
  final scrollable = find.byType(Scrollable).first;
  for (var attempt = 0; attempt < 8 && !tester.any(item); attempt++) {
    await tester.drag(scrollable, const Offset(0, -280));
    await tester.pump();
  }
  expect(item, findsOneWidget);
  await tester.ensureVisible(item);
  await tester.pumpAndSettle();
  await tester.tap(item);
  await tester.pumpAndSettle();
}

void _expectFixedMetadata(
  WidgetTester tester, {
  required String metricLabel,
  required String sourceLabel,
  required String privacyLabel,
  required String displayedLabel,
  required String suppressedLabel,
}) {
  expect(
    find.textContaining('contact_sessions_by_channel_two_periods@1'),
    findsOneWidget,
  );
  expect(find.textContaining('contact_sessions@1'), findsOneWidget);
  expect(find.textContaining(metricLabel), findsOneWidget);
  expect(find.textContaining('backend_accepted_contacts'), findsOneWidget);
  expect(find.textContaining(sourceLabel), findsOneWidget);
  expect(
    find.textContaining('management_contact_session_privacy_v1'),
    findsOneWidget,
  );
  expect(find.textContaining(privacyLabel), findsOneWidget);
  expect(find.textContaining(displayedLabel), findsOneWidget);
  expect(find.textContaining(suppressedLabel), findsOneWidget);
}

void _compactView(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(320, 568);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}

Future<void> _tabTo(WidgetTester tester, Finder target) async {
  for (var attempt = 0; attempt < 12; attempt++) {
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    if (_containsPrimaryFocus(tester, target)) return;
  }
  fail('Tab sequence did not reach $target');
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

final class _Gateway implements ManagementReportGateway {
  _Gateway({
    ManagementAnalysisContextSnapshot? context,
    ManagementReportResult<ManagementAnalysisContextSnapshot>? contextResult,
    this.summaries = const [],
    this.snapshot,
    ManagementReportResult<ManagementReportExportArtifact>? exportResult,
    this.selectResult,
  }) : contextResult =
           contextResult ??
           ManagementReportSuccess(context ?? _contextSnapshot(current: null)),
       exportResult =
           exportResult ??
           const ManagementReportRejected(ManagementReportFailureCode.notFound);

  ManagementReportResult<ManagementAnalysisContextSnapshot> contextResult;
  final List<ManagementReportSnapshotSummary> summaries;
  final ManagementReportSnapshot? snapshot;
  ManagementReportResult<ManagementReportExportArtifact> exportResult;
  ManagementReportResult<ManagementAnalysisContextSnapshot>? selectResult;
  final exportRequests = <(String, ManagementReportSnapshotSummary)>[];
  final selectProjectIds = <String>[];

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
  Future<ManagementReportResult<ManagementReportExportArtifact>>
  exportSnapshot({
    required String projectId,
    required ManagementReportSnapshotSummary summary,
  }) async {
    exportRequests.add((projectId, summary));
    return exportResult;
  }

  @override
  Future<ManagementReportResult<ManagementAnalysisContextSnapshot>>
  selectContext(String projectId) async {
    selectProjectIds.add(projectId);
    return selectResult ?? contextResult;
  }
}

final class _CurrentCityGateway implements CurrentCityReportGateway {
  final listedProjectIds = <String>[];
  final readRequests = <(String, CurrentCityReportSnapshotSummary)>[];

  @override
  Future<void> close() async {}

  @override
  Future<CurrentCityReportResult<CurrentCityReportSnapshotDirectory>>
  listSnapshots(String projectId) async {
    listedProjectIds.add(projectId);
    return CurrentCityReportSuccess(
      CurrentCityReportSnapshotDirectory(
        accessEventId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
        projectId: projectId,
        snapshots: [_currentCitySummary],
      ),
    );
  }

  @override
  Future<CurrentCityReportResult<CurrentCityReportSnapshot>> readSnapshot({
    required String projectId,
    required CurrentCityReportSnapshotSummary summary,
  }) async {
    readRequests.add((projectId, summary));
    return const CurrentCityReportRejected(
      CurrentCityReportFailureCode.notFound,
    );
  }
}

final class _DeferredCurrentCityGateway implements CurrentCityReportGateway {
  final directory =
      Completer<CurrentCityReportResult<CurrentCityReportSnapshotDirectory>>();
  final listedProjectIds = <String>[];

  @override
  Future<void> close() async {}

  @override
  Future<CurrentCityReportResult<CurrentCityReportSnapshotDirectory>>
  listSnapshots(String projectId) {
    listedProjectIds.add(projectId);
    return directory.future;
  }

  @override
  Future<CurrentCityReportResult<CurrentCityReportSnapshot>> readSnapshot({
    required String projectId,
    required CurrentCityReportSnapshotSummary summary,
  }) async =>
      const CurrentCityReportRejected(CurrentCityReportFailureCode.notFound);
}

final class _Delivery implements ManagementReportExportDelivery {
  _Delivery({
    this.isAvailable = true,
    ManagementReportExportDeliveryResult? result,
  }) : result = result ?? const ManagementReportDownloadRequested();

  @override
  final bool isAvailable;
  ManagementReportExportDeliveryResult result;
  final requests = <ManagementReportExportArtifact>[];

  @override
  Future<ManagementReportExportDeliveryResult> requestDownload(
    ManagementReportExportArtifact artifact,
  ) async {
    requests.add(artifact);
    return result;
  }
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

final _currentCitySummary = CurrentCityReportSnapshotSummary(
  snapshotId: '66666666-6666-4666-8666-666666666666',
  reportId: 'contact_sessions_by_current_city_two_periods',
  reportVersion: 1,
  reportingTimeZone: 'America/Chicago',
  dataCutoffUtc: DateTime.utc(2030, 1, 22),
  releasedAtUtc: DateTime.utc(2030, 1, 22, 0, 1),
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
final _artifact = ManagementReportExportArtifact(
  bytes: const [123, 125],
  fileName: 'management-report-snapshot-v1.json',
  contentType: 'application/json; charset=utf-8',
  exportEventId: '77777777-7777-4777-8777-777777777777',
  snapshot: _snapshot,
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
