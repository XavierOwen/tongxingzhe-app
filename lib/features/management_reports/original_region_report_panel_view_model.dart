import 'package:flutter/foundation.dart';

import '../../management_reports/original_region_report_gateway.dart';

/// original-region 面板在一个明确管理项目范围内的读取阶段。
enum OriginalRegionReportPanelStage {
  /// 当前没有可读取的管理项目。
  inactive,

  loadingDirectory,
  directory,
  loadingSnapshot,
  snapshot,
  failure,
}

/// original-region 面板的内存状态。
///
/// 这里只保存独立 original-region gateway 已严格解析的 typed 结果。它不
/// 保存个人项目、其他报告族、缓存或持久化数据。
final class OriginalRegionReportPanelState {
  OriginalRegionReportPanelState({
    required this.projectId,
    required this.stage,
    this.directory,
    this.selectedSummary,
    this.snapshot,
    this.failureCode,
  });

  factory OriginalRegionReportPanelState.initial(String? projectId) {
    final active = projectId != null;
    return OriginalRegionReportPanelState(
      projectId: projectId,
      stage: active
          ? OriginalRegionReportPanelStage.loadingDirectory
          : OriginalRegionReportPanelStage.inactive,
    );
  }

  factory OriginalRegionReportPanelState.inactive() =>
      OriginalRegionReportPanelState.initial(null);

  final String? projectId;
  final OriginalRegionReportPanelStage stage;
  final OriginalRegionReportSnapshotDirectory? directory;
  final OriginalRegionReportSnapshotSummary? selectedSummary;
  final OriginalRegionReportSnapshot? snapshot;
  final OriginalRegionReportFailureCode? failureCode;

  bool get isLoading =>
      stage == OriginalRegionReportPanelStage.loadingDirectory ||
      stage == OriginalRegionReportPanelStage.loadingSnapshot;

  bool get isEmpty =>
      stage == OriginalRegionReportPanelStage.directory &&
      directory != null &&
      directory!.snapshots.isEmpty;
}

/// original-region 管理报告的独立读取状态机。
///
/// [projectId] 必须来自已经重新授权的 management context；每次异步读取
/// 都绑定当前 generation，项目切换、返回目录和 dispose 会使旧响应失效。
final class OriginalRegionReportPanelViewModel extends ChangeNotifier {
  OriginalRegionReportPanelViewModel({
    required this._gateway,
    required String? projectId,
  }) : _projectId = projectId,
       _state = OriginalRegionReportPanelState.initial(projectId);

  final OriginalRegionReportGateway _gateway;
  String? _projectId;
  OriginalRegionReportPanelState _state;
  _OriginalRegionReportRetryOperation? _retryOperation;
  var _generation = 0;
  var _disposed = false;

  OriginalRegionReportPanelState get state => _state;

  /// 初次读取当前明确项目的目录。
  Future<void> initialize() => loadDirectory();

  /// 重新读取当前项目的目录，并清除旧目录、选中项和详情。
  Future<void> loadDirectory() async {
    final projectId = _projectId;
    if (projectId == null) {
      _invalidateAndSet(OriginalRegionReportPanelState.inactive());
      return;
    }
    final generation = ++_generation;
    _retryOperation = _RetryLoadDirectory(projectId);
    _setState(
      OriginalRegionReportPanelState(
        projectId: projectId,
        stage: OriginalRegionReportPanelStage.loadingDirectory,
      ),
    );

    OriginalRegionReportResult<OriginalRegionReportSnapshotDirectory> result;
    try {
      result = await _gateway.listSnapshots(projectId);
    } catch (_) {
      result = const OriginalRegionReportRejected(
        OriginalRegionReportFailureCode.networkUnavailable,
      );
    }
    if (!_isCurrent(generation)) return;

    switch (result) {
      case OriginalRegionReportSuccess(:final value):
        _retryOperation = null;
        _setState(
          OriginalRegionReportPanelState(
            projectId: projectId,
            stage: OriginalRegionReportPanelStage.directory,
            directory: value,
          ),
        );
      case OriginalRegionReportRejected(:final code):
        _setState(
          OriginalRegionReportPanelState(
            projectId: projectId,
            stage: OriginalRegionReportPanelStage.failure,
            failureCode: code,
          ),
        );
    }
  }

  /// 更新当前 management project；传入 `null` 会停用并清空面板。
  Future<void> updateProject(String? projectId) async {
    if (_disposed || projectId == _projectId) return;
    _projectId = projectId;
    final generation = ++_generation;
    _retryOperation = null;
    if (projectId == null) {
      _setState(OriginalRegionReportPanelState.inactive());
      return;
    }

    _retryOperation = _RetryLoadDirectory(projectId);
    _setState(
      OriginalRegionReportPanelState(
        projectId: projectId,
        stage: OriginalRegionReportPanelStage.loadingDirectory,
      ),
    );
    await _readDirectory(projectId, generation);
  }

  /// 只允许打开当前目录中的显式 summary。
  Future<void> openSnapshot(OriginalRegionReportSnapshotSummary summary) async {
    final projectId = _projectId;
    final directory = _state.directory;
    if (projectId == null || directory == null) return;

    final directorySummary = directory.snapshots
        .where((candidate) => _sameSummary(candidate, summary))
        .firstOrNull;
    if (directorySummary == null) return;

    final generation = ++_generation;
    _retryOperation = _RetryReadSnapshot(projectId, directorySummary);
    _setState(
      OriginalRegionReportPanelState(
        projectId: projectId,
        stage: OriginalRegionReportPanelStage.loadingSnapshot,
        directory: directory,
        selectedSummary: directorySummary,
      ),
    );

    OriginalRegionReportResult<OriginalRegionReportSnapshot> result;
    try {
      result = await _gateway.readSnapshot(
        projectId: projectId,
        summary: directorySummary,
      );
    } catch (_) {
      result = const OriginalRegionReportRejected(
        OriginalRegionReportFailureCode.networkUnavailable,
      );
    }
    if (!_isCurrent(generation)) return;

    switch (result) {
      case OriginalRegionReportSuccess(:final value):
        _retryOperation = null;
        _setState(
          OriginalRegionReportPanelState(
            projectId: projectId,
            stage: OriginalRegionReportPanelStage.snapshot,
            directory: directory,
            selectedSummary: directorySummary,
            snapshot: value,
          ),
        );
      case OriginalRegionReportRejected(:final code):
        _setState(
          OriginalRegionReportPanelState(
            projectId: projectId,
            stage: OriginalRegionReportPanelStage.failure,
            directory: directory,
            selectedSummary: directorySummary,
            failureCode: code,
          ),
        );
    }
  }

  /// 返回当前项目目录并清除详情；也会使进行中的详情读取失效。
  void showDirectory() {
    final projectId = _projectId;
    final directory = _state.directory;
    if (projectId == null || directory == null) return;
    ++_generation;
    _retryOperation = null;
    _setState(
      OriginalRegionReportPanelState(
        projectId: projectId,
        stage: OriginalRegionReportPanelStage.directory,
        directory: directory,
      ),
    );
  }

  /// `showDirectory` 的语义别名，供面板按用户动作命名调用。
  void returnToDirectory() => showDirectory();

  /// 重试最近失败的阶段，不自动打开第一项。
  Future<void> retry() async {
    final operation = _retryOperation;
    switch (operation) {
      case _RetryLoadDirectory(:final projectId):
        if (_projectId != projectId) return;
        await loadDirectory();
      case _RetryReadSnapshot(:final projectId, :final summary):
        if (_projectId != projectId || _state.directory == null) return;
        await openSnapshot(summary);
      case null:
        return;
    }
  }

  Future<void> _readDirectory(String projectId, int generation) async {
    if (!_isCurrent(generation) || _projectId != projectId) return;

    OriginalRegionReportResult<OriginalRegionReportSnapshotDirectory> result;
    try {
      result = await _gateway.listSnapshots(projectId);
    } catch (_) {
      result = const OriginalRegionReportRejected(
        OriginalRegionReportFailureCode.networkUnavailable,
      );
    }
    if (!_isCurrent(generation) || _projectId != projectId) return;

    switch (result) {
      case OriginalRegionReportSuccess(:final value):
        _retryOperation = null;
        _setState(
          OriginalRegionReportPanelState(
            projectId: projectId,
            stage: OriginalRegionReportPanelStage.directory,
            directory: value,
          ),
        );
      case OriginalRegionReportRejected(:final code):
        _setState(
          OriginalRegionReportPanelState(
            projectId: projectId,
            stage: OriginalRegionReportPanelStage.failure,
            failureCode: code,
          ),
        );
    }
  }

  bool _sameSummary(
    OriginalRegionReportSnapshotSummary left,
    OriginalRegionReportSnapshotSummary right,
  ) =>
      left.snapshotId == right.snapshotId &&
      left.reportId == right.reportId &&
      left.reportVersion == right.reportVersion &&
      left.reportingTimeZone == right.reportingTimeZone &&
      left.dataCutoffUtc == right.dataCutoffUtc &&
      left.releasedAtUtc == right.releasedAtUtc;

  bool _isCurrent(int generation) => !_disposed && generation == _generation;

  void _invalidateAndSet(OriginalRegionReportPanelState state) {
    ++_generation;
    _retryOperation = null;
    _setState(state);
  }

  void _setState(OriginalRegionReportPanelState state) {
    if (_disposed) return;
    _state = state;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    _retryOperation = null;
    _state = OriginalRegionReportPanelState.inactive();
    super.dispose();
  }
}

sealed class _OriginalRegionReportRetryOperation {
  const _OriginalRegionReportRetryOperation();
}

final class _RetryLoadDirectory extends _OriginalRegionReportRetryOperation {
  const _RetryLoadDirectory(this.projectId);

  final String projectId;
}

final class _RetryReadSnapshot extends _OriginalRegionReportRetryOperation {
  const _RetryReadSnapshot(this.projectId, this.summary);

  final String projectId;
  final OriginalRegionReportSnapshotSummary summary;
}
