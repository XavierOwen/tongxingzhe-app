import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tongxingzhe_app/features/management_reports/interest_report_panel_view_model.dart';
import 'package:tongxingzhe_app/management_reports/interest_report_gateway.dart';

void main() {
  test(
    'loads the explicit project directory and preserves a successful empty state',
    () async {
      final gateway = _Gateway(
        directoryResult: InterestReportSuccess(_emptyDirectory),
      );
      final viewModel = _viewModel(gateway);
      addTearDown(viewModel.dispose);

      await viewModel.initialize();

      expect(gateway.listedProjectIds, [_projectA]);
      expect(viewModel.state.stage, InterestReportPanelStage.directory);
      expect(viewModel.state.projectId, _projectA);
      expect(viewModel.state.directory, same(_emptyDirectory));
      expect(viewModel.state.isEmpty, isTrue);
      expect(gateway.readRequests, isEmpty);
    },
  );

  test('does not auto-open the first directory item', () async {
    final gateway = _Gateway(
      directoryResult: InterestReportSuccess(_directoryWithSummary),
      snapshotResult: InterestReportSuccess(_snapshot),
    );
    final viewModel = _viewModel(gateway);
    addTearDown(viewModel.dispose);

    await viewModel.initialize();

    expect(viewModel.state.stage, InterestReportPanelStage.directory);
    expect(viewModel.state.selectedSummary, isNull);
    expect(viewModel.state.snapshot, isNull);
    expect(gateway.readRequests, isEmpty);
  });

  test('opens only an explicitly selected directory summary', () async {
    final gateway = _Gateway(
      directoryResult: InterestReportSuccess(_directoryWithSummary),
      snapshotResult: InterestReportSuccess(_snapshot),
    );
    final viewModel = _viewModel(gateway);
    addTearDown(viewModel.dispose);
    await viewModel.initialize();

    await viewModel.openSnapshot(_summary);

    expect(viewModel.state.stage, InterestReportPanelStage.snapshot);
    expect(viewModel.state.selectedSummary, same(_summary));
    expect(viewModel.state.snapshot, same(_snapshot));
    expect(gateway.readRequests, [(_projectA, _summary)]);
  });

  test('rejects a summary that is not in the current directory', () async {
    final gateway = _Gateway(
      directoryResult: InterestReportSuccess(_directoryWithSummary),
      snapshotResult: InterestReportSuccess(_snapshot),
    );
    final viewModel = _viewModel(gateway);
    addTearDown(viewModel.dispose);
    await viewModel.initialize();

    await viewModel.openSnapshot(_otherSummary);

    expect(viewModel.state.stage, InterestReportPanelStage.directory);
    expect(gateway.readRequests, isEmpty);
  });

  test(
    'retries failed directory and detail stages without changing scope',
    () async {
      final gateway = _Gateway(
        directoryResult: const InterestReportRejected(
          InterestReportFailureCode.networkUnavailable,
        ),
        snapshotResult: const InterestReportRejected(
          InterestReportFailureCode.notFound,
        ),
      );
      final viewModel = _viewModel(gateway);
      addTearDown(viewModel.dispose);

      await viewModel.initialize();
      expect(viewModel.state.stage, InterestReportPanelStage.failure);

      gateway.directoryResult = InterestReportSuccess(_directoryWithSummary);
      await viewModel.retry();
      expect(viewModel.state.stage, InterestReportPanelStage.directory);

      await viewModel.openSnapshot(_summary);
      expect(viewModel.state.stage, InterestReportPanelStage.failure);

      gateway.snapshotResult = InterestReportSuccess(_snapshot);
      await viewModel.retry();

      expect(viewModel.state.stage, InterestReportPanelStage.snapshot);
      expect(viewModel.state.snapshot, same(_snapshot));
      expect(gateway.listedProjectIds, [_projectA, _projectA]);
      expect(gateway.readRequests, [
        (_projectA, _summary),
        (_projectA, _summary),
      ]);
    },
  );

  test('returnToDirectory invalidates a late detail response', () async {
    final detail = Completer<InterestReportResult<InterestReportSnapshot>>();
    final gateway = _Gateway(
      directoryResult: InterestReportSuccess(_directoryWithSummary),
      snapshotHandler: (_) => detail.future,
    );
    final viewModel = _viewModel(gateway);
    addTearDown(viewModel.dispose);
    await viewModel.initialize();

    final pending = viewModel.openSnapshot(_summary);
    expect(viewModel.state.stage, InterestReportPanelStage.loadingSnapshot);
    viewModel.returnToDirectory();
    detail.complete(InterestReportSuccess(_snapshot));
    await pending;

    expect(viewModel.state.stage, InterestReportPanelStage.directory);
    expect(viewModel.state.selectedSummary, isNull);
    expect(viewModel.state.snapshot, isNull);
  });

  test(
    'project update clears project A and ignores its late directory response',
    () async {
      final oldDirectory =
          Completer<InterestReportResult<InterestReportSnapshotDirectory>>();
      final gateway = _Gateway(
        directoryHandler: (projectId) => projectId == _projectA
            ? oldDirectory.future
            : Future.value(InterestReportSuccess(_directoryB)),
      );
      final viewModel = _viewModel(gateway);
      addTearDown(viewModel.dispose);

      final first = viewModel.initialize();
      await Future<void>.delayed(Duration.zero);
      final second = viewModel.updateProject(_projectB);
      expect(viewModel.state.projectId, _projectB);
      expect(viewModel.state.directory, isNull);
      expect(viewModel.state.snapshot, isNull);
      await second;

      oldDirectory.complete(InterestReportSuccess(_directoryWithSummary));
      await first;

      expect(viewModel.state.projectId, _projectB);
      expect(viewModel.state.directory, same(_directoryB));
      expect(gateway.listedProjectIds, [_projectA, _projectB]);
    },
  );

  test(
    'null project deactivates and invalidates a pending directory response',
    () async {
      final pendingDirectory =
          Completer<InterestReportResult<InterestReportSnapshotDirectory>>();
      final gateway = _Gateway(
        directoryHandler: (_) => pendingDirectory.future,
      );
      final viewModel = _viewModel(gateway);
      addTearDown(viewModel.dispose);

      final loading = viewModel.initialize();
      await Future<void>.delayed(Duration.zero);
      await viewModel.updateProject(null);
      pendingDirectory.complete(InterestReportSuccess(_directoryWithSummary));
      await loading;

      expect(viewModel.state.stage, InterestReportPanelStage.inactive);
      expect(viewModel.state.projectId, isNull);
      expect(viewModel.state.directory, isNull);
    },
  );

  test(
    'dispose invalidates a pending response without notifying afterward',
    () async {
      final pendingDirectory =
          Completer<InterestReportResult<InterestReportSnapshotDirectory>>();
      final gateway = _Gateway(
        directoryHandler: (_) => pendingDirectory.future,
      );
      final viewModel = _viewModel(gateway);
      var notifications = 0;
      viewModel.addListener(() => notifications++);

      final loading = viewModel.initialize();
      await Future<void>.delayed(Duration.zero);
      final beforeDispose = notifications;
      viewModel.dispose();
      pendingDirectory.complete(InterestReportSuccess(_directoryWithSummary));
      await loading;

      expect(notifications, beforeDispose);
    },
  );

  test(
    'maps gateway throws to networkUnavailable for directory and detail',
    () async {
      final gateway = _Gateway(
        directoryHandler: (_) => throw StateError('directory transport failed'),
      );
      final viewModel = _viewModel(gateway);
      addTearDown(viewModel.dispose);

      await viewModel.initialize();
      expect(viewModel.state.stage, InterestReportPanelStage.failure);
      expect(
        viewModel.state.failureCode,
        InterestReportFailureCode.networkUnavailable,
      );

      gateway.directoryHandler = (_) =>
          Future.value(InterestReportSuccess(_directoryWithSummary));
      gateway.snapshotHandler = (_) =>
          throw StateError('detail transport failed');
      await viewModel.retry();
      await viewModel.openSnapshot(_summary);

      expect(viewModel.state.stage, InterestReportPanelStage.failure);
      expect(
        viewModel.state.failureCode,
        InterestReportFailureCode.networkUnavailable,
      );
    },
  );
}

final class _Gateway implements InterestReportGateway {
  _Gateway({
    InterestReportResult<InterestReportSnapshotDirectory>? directoryResult,
    InterestReportResult<InterestReportSnapshot>? snapshotResult,
    this.directoryHandler,
    this.snapshotHandler,
  }) : directoryResult =
           directoryResult ?? InterestReportSuccess(_emptyDirectory),
       snapshotResult = snapshotResult ?? InterestReportSuccess(_snapshot);

  InterestReportResult<InterestReportSnapshotDirectory> directoryResult;
  InterestReportResult<InterestReportSnapshot> snapshotResult;
  Future<InterestReportResult<InterestReportSnapshotDirectory>> Function(
    String projectId,
  )?
  directoryHandler;
  Future<InterestReportResult<InterestReportSnapshot>> Function(
    InterestReportSnapshotSummary summary,
  )?
  snapshotHandler;
  final listedProjectIds = <String>[];
  final readRequests = <(String, InterestReportSnapshotSummary)>[];

  @override
  Future<void> close() async {}

  @override
  Future<InterestReportResult<InterestReportSnapshotDirectory>> listSnapshots(
    String projectId,
  ) {
    listedProjectIds.add(projectId);
    return directoryHandler?.call(projectId) ?? Future.value(directoryResult);
  }

  @override
  Future<InterestReportResult<InterestReportSnapshot>> readSnapshot({
    required String projectId,
    required InterestReportSnapshotSummary summary,
  }) {
    readRequests.add((projectId, summary));
    return snapshotHandler?.call(summary) ?? Future.value(snapshotResult);
  }
}

InterestReportPanelViewModel _viewModel(_Gateway gateway) =>
    InterestReportPanelViewModel(gateway: gateway, projectId: _projectA);

const _projectA = 'project-a';
const _projectB = 'project-b';
const _reportId = 'contact_sessions_by_interest_level_two_periods';
const _snapshotId = 'snapshot-a';

final _summary = InterestReportSnapshotSummary(
  snapshotId: _snapshotId,
  reportId: _reportId,
  reportVersion: 1,
  reportingTimeZone: 'Asia/Shanghai',
  dataCutoffUtc: DateTime.utc(2030, 1, 22, 1),
  releasedAtUtc: DateTime.utc(2030, 1, 22, 2),
);

final _otherSummary = InterestReportSnapshotSummary(
  snapshotId: 'snapshot-other',
  reportId: _reportId,
  reportVersion: 1,
  reportingTimeZone: 'Asia/Shanghai',
  dataCutoffUtc: DateTime.utc(2030, 1, 23, 1),
  releasedAtUtc: DateTime.utc(2030, 1, 23, 2),
);

final _emptyDirectory = InterestReportSnapshotDirectory(
  accessEventId: 'event-a',
  projectId: _projectA,
  snapshots: const [],
);

final _directoryWithSummary = InterestReportSnapshotDirectory(
  accessEventId: 'event-a',
  projectId: _projectA,
  snapshots: [_summary],
);

final _directoryB = InterestReportSnapshotDirectory(
  accessEventId: 'event-b',
  projectId: _projectB,
  snapshots: const [],
);

final _snapshot = InterestReportSnapshot(
  accessEventId: 'event-a',
  summary: _summary,
  report: InterestReportDocument(
    reportId: _reportId,
    reportVersion: 1,
    metricId: 'interest_distribution',
    metricVersion: 1,
    statisticalUnit: 'contact_session',
    dimension: 'interest_level',
    queryFingerprint:
        'management-report:contact_sessions_by_interest_level_two_periods:v1',
    privacyPolicy: 'management_interest_distribution_privacy_v1',
    sourceScope: 'backend_accepted_active_contacts_current_revision',
    projectId: _projectA,
    periods: InterestReportPeriods(
      periodBoundaryId: 'iso_week_monday_v1',
      reportingTimeZone: _summary.reportingTimeZone,
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
      for (var index = 0; index < 10; index++)
        InterestReportCell(
          periodKey: index < 5
              ? InterestReportPeriodKey.previous
              : InterestReportPeriodKey.current,
          interestLevel: index % 5,
          cellOrder: index,
          valueCount: index < 5 ? 10 + index : null,
          privacyStatus: index < 5
              ? InterestReportPrivacyStatus.displayed
              : InterestReportPrivacyStatus.suppressed,
        ),
    ],
  ),
);
