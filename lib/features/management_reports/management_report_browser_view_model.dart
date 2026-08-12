import 'package:flutter/foundation.dart';

import '../../management_reports/management_report_gateway.dart';

enum ManagementReportBrowserStage {
  loadingContext,
  contextSelection,
  selectingContext,
  loadingDirectory,
  directory,
  loadingReport,
  report,
  failure,
}

final class ManagementReportBrowserState {
  ManagementReportBrowserState({
    required this.stage,
    this.currentContext,
    List<ManagementAnalysisContext> availableContexts = const [],
    List<ManagementReportSnapshotSummary> snapshots = const [],
    this.selectedSummary,
    this.snapshot,
    this.failureCode,
  }) : availableContexts = List.unmodifiable(availableContexts),
       snapshots = List.unmodifiable(snapshots);

  factory ManagementReportBrowserState.initial() =>
      ManagementReportBrowserState(
        stage: ManagementReportBrowserStage.loadingContext,
      );

  final ManagementReportBrowserStage stage;
  final ManagementAnalysisContext? currentContext;
  final List<ManagementAnalysisContext> availableContexts;
  final List<ManagementReportSnapshotSummary> snapshots;
  final ManagementReportSnapshotSummary? selectedSummary;
  final ManagementReportSnapshot? snapshot;
  final ManagementReportFailureCode? failureCode;
}

/// 组织管理报告浏览状态机。
///
/// 管理项目和个人项目彼此独立。切换管理项目时先删除内存中的旧目录和报告；
/// 每个异步操作也带 generation，避免迟到响应把已切换的范围写回页面。
final class ManagementReportBrowserViewModel extends ChangeNotifier {
  ManagementReportBrowserViewModel(this._gateway);

  final ManagementReportGateway _gateway;
  ManagementReportBrowserState _state = ManagementReportBrowserState.initial();
  var _generation = 0;
  var _disposed = false;
  _RetryOperation? _retryOperation;

  ManagementReportBrowserState get state => _state;

  Future<void> initialize() async {
    final generation = ++_generation;
    _retryOperation = const _RetryLoadContext();
    _setState(ManagementReportBrowserState.initial());

    final result = await _gateway.loadContext();
    if (!_isCurrent(generation)) return;
    if (result case ManagementReportSuccess<ManagementAnalysisContextSnapshot>(
      :final value,
    )) {
      final current = value.current;
      if (current == null) {
        _retryOperation = null;
        _setState(
          ManagementReportBrowserState(
            stage: ManagementReportBrowserStage.contextSelection,
            availableContexts: value.available,
          ),
        );
        return;
      }
      await _loadDirectory(
        context: current,
        availableContexts: value.available,
        generation: generation,
      );
      return;
    }
    _fail(
      (result as ManagementReportRejected<ManagementAnalysisContextSnapshot>)
          .code,
      generation,
    );
  }

  Future<void> selectContext(String projectId) async {
    final generation = ++_generation;
    final available = _state.availableContexts;
    _retryOperation = _RetrySelectContext(projectId);
    _setState(
      ManagementReportBrowserState(
        stage: ManagementReportBrowserStage.selectingContext,
        availableContexts: available,
      ),
    );

    final result = await _gateway.selectContext(projectId);
    if (!_isCurrent(generation)) return;
    if (result case ManagementReportSuccess<ManagementAnalysisContextSnapshot>(
      :final value,
    )) {
      final current = value.current;
      if (current == null || current.projectId != projectId) {
        _fail(
          ManagementReportFailureCode.invalidResponse,
          generation,
          availableContexts: value.available,
        );
        return;
      }
      await _loadDirectory(
        context: current,
        availableContexts: value.available,
        generation: generation,
      );
      return;
    }
    _fail(
      (result as ManagementReportRejected<ManagementAnalysisContextSnapshot>)
          .code,
      generation,
      availableContexts: available,
    );
  }

  Future<void> openSnapshot(ManagementReportSnapshotSummary summary) async {
    final context = _state.currentContext;
    if (context == null) return;
    final generation = ++_generation;
    final available = _state.availableContexts;
    final snapshots = _state.snapshots;
    _retryOperation = _RetryReadSnapshot(context.projectId, summary);
    _setState(
      ManagementReportBrowserState(
        stage: ManagementReportBrowserStage.loadingReport,
        currentContext: context,
        availableContexts: available,
        snapshots: snapshots,
        selectedSummary: summary,
      ),
    );

    final result = await _gateway.readSnapshot(
      projectId: context.projectId,
      summary: summary,
    );
    if (!_isCurrent(generation)) return;
    if (result case ManagementReportSuccess<ManagementReportSnapshot>(
      :final value,
    )) {
      _retryOperation = null;
      _setState(
        ManagementReportBrowserState(
          stage: ManagementReportBrowserStage.report,
          currentContext: context,
          availableContexts: available,
          snapshots: snapshots,
          selectedSummary: summary,
          snapshot: value,
        ),
      );
      return;
    }
    _fail(
      (result as ManagementReportRejected<ManagementReportSnapshot>).code,
      generation,
      currentContext: context,
      availableContexts: available,
      snapshots: snapshots,
      selectedSummary: summary,
    );
  }

  void showDirectory() {
    final context = _state.currentContext;
    if (context == null) return;
    _generation++;
    _retryOperation = null;
    _setState(
      ManagementReportBrowserState(
        stage: ManagementReportBrowserStage.directory,
        currentContext: context,
        availableContexts: _state.availableContexts,
        snapshots: _state.snapshots,
      ),
    );
  }

  Future<void> retry() async {
    switch (_retryOperation) {
      case _RetryLoadContext():
        await initialize();
      case _RetrySelectContext(:final projectId):
        await selectContext(projectId);
      case _RetryLoadDirectory(:final context, :final availableContexts):
        final generation = ++_generation;
        await _loadDirectory(
          context: context,
          availableContexts: availableContexts,
          generation: generation,
        );
      case _RetryReadSnapshot(:final projectId, :final summary):
        if (_state.currentContext?.projectId != projectId) return;
        await openSnapshot(summary);
      case null:
        return;
    }
  }

  Future<void> _loadDirectory({
    required ManagementAnalysisContext context,
    required List<ManagementAnalysisContext> availableContexts,
    required int generation,
  }) async {
    if (!_isCurrent(generation)) return;
    _retryOperation = _RetryLoadDirectory(context, availableContexts);
    _setState(
      ManagementReportBrowserState(
        stage: ManagementReportBrowserStage.loadingDirectory,
        currentContext: context,
        availableContexts: availableContexts,
      ),
    );

    final result = await _gateway.listSnapshots(context.projectId);
    if (!_isCurrent(generation)) return;
    if (result
        case ManagementReportSuccess<List<ManagementReportSnapshotSummary>>(
          :final value,
        )) {
      _retryOperation = null;
      _setState(
        ManagementReportBrowserState(
          stage: ManagementReportBrowserStage.directory,
          currentContext: context,
          availableContexts: availableContexts,
          snapshots: value,
        ),
      );
      return;
    }
    _fail(
      (result
              as ManagementReportRejected<
                List<ManagementReportSnapshotSummary>
              >)
          .code,
      generation,
      currentContext: context,
      availableContexts: availableContexts,
    );
  }

  void _fail(
    ManagementReportFailureCode code,
    int generation, {
    ManagementAnalysisContext? currentContext,
    List<ManagementAnalysisContext> availableContexts = const [],
    List<ManagementReportSnapshotSummary> snapshots = const [],
    ManagementReportSnapshotSummary? selectedSummary,
  }) {
    if (!_isCurrent(generation)) return;
    _setState(
      ManagementReportBrowserState(
        stage: ManagementReportBrowserStage.failure,
        currentContext: currentContext,
        availableContexts: availableContexts,
        snapshots: snapshots,
        selectedSummary: selectedSummary,
        failureCode: code,
      ),
    );
  }

  bool _isCurrent(int generation) => !_disposed && generation == _generation;

  void _setState(ManagementReportBrowserState state) {
    if (_disposed) return;
    _state = state;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    super.dispose();
  }
}

sealed class _RetryOperation {
  const _RetryOperation();
}

final class _RetryLoadContext extends _RetryOperation {
  const _RetryLoadContext();
}

final class _RetrySelectContext extends _RetryOperation {
  const _RetrySelectContext(this.projectId);

  final String projectId;
}

final class _RetryLoadDirectory extends _RetryOperation {
  _RetryLoadDirectory(
    this.context,
    List<ManagementAnalysisContext> availableContexts,
  ) : availableContexts = List.unmodifiable(availableContexts);

  final ManagementAnalysisContext context;
  final List<ManagementAnalysisContext> availableContexts;
}

final class _RetryReadSnapshot extends _RetryOperation {
  const _RetryReadSnapshot(this.projectId, this.summary);

  final String projectId;
  final ManagementReportSnapshotSummary summary;
}
