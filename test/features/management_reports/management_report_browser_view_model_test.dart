import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tongxingzhe_app/features/management_reports/management_report_browser_view_model.dart';
import 'package:tongxingzhe_app/management_reports/management_report_gateway.dart';

void main() {
  test('载入当前管理项目后读取该项目目录', () async {
    final gateway = _Gateway(
      loadContextResult: _contextResult(current: _projectA),
      directoryResult: ManagementReportSuccess([_summaryA]),
    );
    final viewModel = ManagementReportBrowserViewModel(gateway);

    await viewModel.initialize();

    expect(gateway.listedProjectIds, [_projectA.projectId]);
    expect(viewModel.state.stage, ManagementReportBrowserStage.directory);
    expect(viewModel.state.currentContext, same(_projectA));
    expect(viewModel.state.snapshots, [_summaryA]);
  });

  test('没有保存的管理项目时等待用户明确选择', () async {
    final gateway = _Gateway(loadContextResult: _contextResult(current: null));
    final viewModel = ManagementReportBrowserViewModel(gateway);

    await viewModel.initialize();

    expect(
      viewModel.state.stage,
      ManagementReportBrowserStage.contextSelection,
    );
    expect(viewModel.state.availableContexts, [_projectA, _projectB]);
    expect(gateway.listedProjectIds, isEmpty);
  });

  test('选择新项目会先清除旧目录和详情，再读取新目录', () async {
    final selectionCompleter =
        Completer<ManagementReportResult<ManagementAnalysisContextSnapshot>>();
    final gateway = _Gateway(
      loadContextResult: _contextResult(current: _projectA),
      directoryResult: ManagementReportSuccess([_summaryA]),
      selectContextHandler: (_) => selectionCompleter.future,
    );
    final viewModel = ManagementReportBrowserViewModel(gateway);
    await viewModel.initialize();

    final pending = viewModel.selectContext(_projectB.projectId);

    expect(
      viewModel.state.stage,
      ManagementReportBrowserStage.selectingContext,
    );
    expect(viewModel.state.currentContext, isNull);
    expect(viewModel.state.snapshots, isEmpty);
    expect(viewModel.state.snapshot, isNull);

    gateway.directoryResult = ManagementReportSuccess([_summaryB]);
    selectionCompleter.complete(_contextResult(current: _projectB));
    await pending;

    expect(gateway.listedProjectIds, [
      _projectA.projectId,
      _projectB.projectId,
    ]);
    expect(viewModel.state.currentContext, same(_projectB));
    expect(viewModel.state.snapshots, [_summaryB]);
  });

  test('切换项目后忽略旧目录的迟到响应', () async {
    final oldDirectory =
        Completer<
          ManagementReportResult<List<ManagementReportSnapshotSummary>>
        >();
    final gateway = _Gateway(
      loadContextResult: _contextResult(current: _projectA),
      directoryHandler: (projectId) => projectId == _projectA.projectId
          ? oldDirectory.future
          : Future.value(ManagementReportSuccess([_summaryB])),
      selectContextHandler: (_) async => _contextResult(current: _projectB),
    );
    final viewModel = ManagementReportBrowserViewModel(gateway);

    final initialLoad = viewModel.initialize();
    await Future<void>.delayed(Duration.zero);
    await viewModel.selectContext(_projectB.projectId);
    oldDirectory.complete(ManagementReportSuccess([_summaryA]));
    await initialLoad;

    expect(viewModel.state.currentContext, same(_projectB));
    expect(viewModel.state.snapshots, [_summaryB]);
  });

  test('返回目录后忽略报告的迟到响应，并可再次打开', () async {
    final readCompleter =
        Completer<ManagementReportResult<ManagementReportSnapshot>>();
    final gateway = _Gateway(
      loadContextResult: _contextResult(current: _projectA),
      directoryResult: ManagementReportSuccess([_summaryA]),
      readHandler: (_, _) => readCompleter.future,
    );
    final viewModel = ManagementReportBrowserViewModel(gateway);
    await viewModel.initialize();

    final pending = viewModel.openSnapshot(_summaryA);
    expect(viewModel.state.stage, ManagementReportBrowserStage.loadingReport);
    viewModel.showDirectory();
    readCompleter.complete(ManagementReportSuccess(_snapshotA));
    await pending;

    expect(viewModel.state.stage, ManagementReportBrowserStage.directory);
    expect(viewModel.state.selectedSummary, isNull);
    expect(viewModel.state.snapshot, isNull);
  });

  test('目录失败保留项目但不保留旧报告，并可重试', () async {
    final gateway = _Gateway(
      loadContextResult: _contextResult(current: _projectA),
      directoryResult: const ManagementReportRejected(
        ManagementReportFailureCode.networkUnavailable,
      ),
    );
    final viewModel = ManagementReportBrowserViewModel(gateway);

    await viewModel.initialize();

    expect(viewModel.state.stage, ManagementReportBrowserStage.failure);
    expect(viewModel.state.currentContext, same(_projectA));
    expect(
      viewModel.state.failureCode,
      ManagementReportFailureCode.networkUnavailable,
    );

    gateway.directoryResult = const ManagementReportSuccess([]);
    await viewModel.retry();

    expect(viewModel.state.stage, ManagementReportBrowserStage.directory);
    expect(viewModel.state.snapshots, isEmpty);
  });

  test('读取失败保留选中目录项，并把重试限制在同一项目和快照', () async {
    final gateway = _Gateway(
      loadContextResult: _contextResult(current: _projectA),
      directoryResult: ManagementReportSuccess([_summaryA]),
      readResult: const ManagementReportRejected(
        ManagementReportFailureCode.notFound,
      ),
    );
    final viewModel = ManagementReportBrowserViewModel(gateway);
    await viewModel.initialize();

    await viewModel.openSnapshot(_summaryA);

    expect(viewModel.state.stage, ManagementReportBrowserStage.failure);
    expect(viewModel.state.selectedSummary, same(_summaryA));
    expect(viewModel.state.failureCode, ManagementReportFailureCode.notFound);

    gateway.readResult = ManagementReportSuccess(_snapshotA);
    await viewModel.retry();

    expect(viewModel.state.stage, ManagementReportBrowserStage.report);
    expect(viewModel.state.snapshot, same(_snapshotA));
    expect(gateway.readRequests, [
      (_projectA.projectId, _summaryA),
      (_projectA.projectId, _summaryA),
    ]);
  });
}

ManagementReportSuccess<ManagementAnalysisContextSnapshot> _contextResult({
  required ManagementAnalysisContext? current,
}) => ManagementReportSuccess(
  ManagementAnalysisContextSnapshot(
    current: current,
    available: const [_projectA, _projectB],
  ),
);

final class _Gateway implements ManagementReportGateway {
  _Gateway({
    required this.loadContextResult,
    ManagementReportResult<List<ManagementReportSnapshotSummary>>?
    directoryResult,
    ManagementReportResult<ManagementReportSnapshot>? readResult,
    this.selectContextHandler,
    this.directoryHandler,
    this.readHandler,
  }) : directoryResult = directoryResult ?? const ManagementReportSuccess([]),
       readResult = readResult ?? ManagementReportSuccess(_snapshotA);

  ManagementReportResult<ManagementAnalysisContextSnapshot> loadContextResult;
  ManagementReportResult<List<ManagementReportSnapshotSummary>> directoryResult;
  ManagementReportResult<ManagementReportSnapshot> readResult;
  final Future<ManagementReportResult<ManagementAnalysisContextSnapshot>>
  Function(String projectId)?
  selectContextHandler;
  final Future<ManagementReportResult<List<ManagementReportSnapshotSummary>>>
  Function(String projectId)?
  directoryHandler;
  final Future<ManagementReportResult<ManagementReportSnapshot>> Function(
    String projectId,
    ManagementReportSnapshotSummary summary,
  )?
  readHandler;
  final listedProjectIds = <String>[];
  final readRequests = <(String, ManagementReportSnapshotSummary)>[];

  @override
  Future<void> close() async {}

  @override
  Future<ManagementReportResult<ManagementAnalysisContextSnapshot>>
  loadContext() async => loadContextResult;

  @override
  Future<ManagementReportResult<List<ManagementReportSnapshotSummary>>>
  listSnapshots(String projectId) {
    listedProjectIds.add(projectId);
    return directoryHandler?.call(projectId) ?? Future.value(directoryResult);
  }

  @override
  Future<ManagementReportResult<ManagementReportSnapshot>> readSnapshot({
    required String projectId,
    required ManagementReportSnapshotSummary summary,
  }) {
    readRequests.add((projectId, summary));
    return readHandler?.call(projectId, summary) ?? Future.value(readResult);
  }

  @override
  Future<ManagementReportResult<ManagementAnalysisContextSnapshot>>
  selectContext(String projectId) =>
      selectContextHandler?.call(projectId) ??
      Future.value(_contextResult(current: _projectB));
}

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
final _summaryA = ManagementReportSnapshotSummary(
  snapshotId: '55555555-5555-4555-8555-555555555555',
  reportId: 'contact_sessions_by_channel_two_periods',
  reportVersion: 1,
  reportingTimeZone: 'America/Chicago',
  dataCutoffUtc: _cutoff,
  releasedAtUtc: _released,
);
final _summaryB = ManagementReportSnapshotSummary(
  snapshotId: '66666666-6666-4666-8666-666666666666',
  reportId: 'contact_sessions_by_channel_two_periods',
  reportVersion: 1,
  reportingTimeZone: 'UTC',
  dataCutoffUtc: _cutoff,
  releasedAtUtc: _released,
);
final _snapshotA = ManagementReportSnapshot(
  summary: _summaryA,
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
    projectId: '22222222-2222-4222-8222-222222222222',
    periodBoundaryId: 'iso_week_monday_v1',
    reportingTimeZone: 'America/Chicago',
    dataCutoffUtc: _cutoff,
    previousPeriod: ManagementReportPeriod(
      startUtc: _previousStart,
      untilUtc: _currentStart,
    ),
    currentPeriod: ManagementReportPeriod(
      startUtc: _currentStart,
      untilUtc: _currentUntil,
    ),
    cells: [],
  ),
);
final _previousStart = DateTime.utc(2030, 1, 7, 6);
final _currentStart = DateTime.utc(2030, 1, 14, 6);
final _currentUntil = DateTime.utc(2030, 1, 21, 6);
final _cutoff = DateTime.utc(2030, 1, 22);
final _released = DateTime.utc(2030, 1, 22, 0, 1);
