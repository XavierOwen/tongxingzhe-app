import 'package:flutter/foundation.dart';

import '../../management_reports/current_city_report_gateway.dart';

/// current-city 面板在一个明确管理项目范围内的读取阶段。
enum CurrentCityReportPanelStage {
  /// 当前没有可读取的管理项目。
  inactive,

  loadingDirectory,
  directory,
  loadingSnapshot,
  snapshot,
  failure,
}

/// current-city 面板的内存状态。
///
/// 这里故意只保存 current-city gateway 的 typed 结果。它不保存个人项目、
/// channel report DTO，也不负责缓存或持久化。
final class CurrentCityReportPanelState {
  CurrentCityReportPanelState({
    required this.projectId,
    required this.stage,
    this.directory,
    this.selectedSummary,
    this.snapshot,
    this.failureCode,
  });

  factory CurrentCityReportPanelState.initial(String? projectId) {
    final active = projectId != null;
    return CurrentCityReportPanelState(
      projectId: projectId,
      stage: active
          ? CurrentCityReportPanelStage.loadingDirectory
          : CurrentCityReportPanelStage.inactive,
    );
  }

  factory CurrentCityReportPanelState.inactive() =>
      CurrentCityReportPanelState.initial(null);

  final String? projectId;
  final CurrentCityReportPanelStage stage;
  final CurrentCityReportSnapshotDirectory? directory;
  final CurrentCityReportSnapshotSummary? selectedSummary;
  final CurrentCityReportSnapshot? snapshot;
  final CurrentCityReportFailureCode? failureCode;

  bool get isLoading =>
      stage == CurrentCityReportPanelStage.loadingDirectory ||
      stage == CurrentCityReportPanelStage.loadingSnapshot;

  bool get isEmpty =>
      stage == CurrentCityReportPanelStage.directory &&
      directory != null &&
      directory!.snapshots.isEmpty;
}

/// current-city 管理报告的独立读取状态机。
///
/// [projectId] 必须由上层已经解析并重新授权的 management context 提供；
/// `null` 表示面板停用。每次异步读取都绑定当前 generation，项目切换、返回
/// 目录和 dispose 会使旧响应失效。
final class CurrentCityReportPanelViewModel extends ChangeNotifier {
  CurrentCityReportPanelViewModel({
    required CurrentCityReportGateway gateway,
    required String? projectId,
  }) : _gateway = gateway,
       _projectId = projectId,
       _state = CurrentCityReportPanelState.initial(projectId);

  final CurrentCityReportGateway _gateway;
  String? _projectId;
  CurrentCityReportPanelState _state;
  _CurrentCityReportRetryOperation? _retryOperation;
  var _generation = 0;
  var _disposed = false;

  CurrentCityReportPanelState get state => _state;

  /// 初次读取当前明确项目的目录。
  Future<void> initialize() => loadDirectory();

  /// 重新读取当前项目的目录。
  ///
  /// 该操作会清除旧目录、选中项和详情，确保刷新期间不会继续显示旧快照。
  Future<void> loadDirectory() async {
    final projectId = _projectId;
    if (projectId == null) {
      _invalidateAndSet(CurrentCityReportPanelState.inactive());
      return;
    }
    final generation = ++_generation;
    _retryOperation = _RetryLoadDirectory(projectId);
    _setState(
      CurrentCityReportPanelState(
        projectId: projectId,
        stage: CurrentCityReportPanelStage.loadingDirectory,
      ),
    );

    CurrentCityReportResult<CurrentCityReportSnapshotDirectory> result;
    try {
      result = await _gateway.listSnapshots(projectId);
    } catch (_) {
      result = const CurrentCityReportRejected(
        CurrentCityReportFailureCode.networkUnavailable,
      );
    }
    if (!_isCurrent(generation)) return;

    switch (result) {
      case CurrentCityReportSuccess(:final value):
        _retryOperation = null;
        _setState(
          CurrentCityReportPanelState(
            projectId: projectId,
            stage: CurrentCityReportPanelStage.directory,
            directory: value,
          ),
        );
      case CurrentCityReportRejected(:final code):
        _setState(
          CurrentCityReportPanelState(
            projectId: projectId,
            stage: CurrentCityReportPanelStage.failure,
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
      _setState(CurrentCityReportPanelState.inactive());
      return;
    }

    _retryOperation = _RetryLoadDirectory(projectId);
    _setState(
      CurrentCityReportPanelState(
        projectId: projectId,
        stage: CurrentCityReportPanelStage.loadingDirectory,
      ),
    );
    await _readDirectory(projectId, generation);
  }

  /// 只允许打开当前目录中用户明确选中的摘要。
  Future<void> openSnapshot(CurrentCityReportSnapshotSummary summary) async {
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
      CurrentCityReportPanelState(
        projectId: projectId,
        stage: CurrentCityReportPanelStage.loadingSnapshot,
        directory: directory,
        selectedSummary: directorySummary,
      ),
    );

    CurrentCityReportResult<CurrentCityReportSnapshot> result;
    try {
      result = await _gateway.readSnapshot(
        projectId: projectId,
        summary: directorySummary,
      );
    } catch (_) {
      result = const CurrentCityReportRejected(
        CurrentCityReportFailureCode.networkUnavailable,
      );
    }
    if (!_isCurrent(generation)) return;

    switch (result) {
      case CurrentCityReportSuccess(:final value):
        _retryOperation = null;
        _setState(
          CurrentCityReportPanelState(
            projectId: projectId,
            stage: CurrentCityReportPanelStage.snapshot,
            directory: directory,
            selectedSummary: directorySummary,
            snapshot: value,
          ),
        );
      case CurrentCityReportRejected(:final code):
        _setState(
          CurrentCityReportPanelState(
            projectId: projectId,
            stage: CurrentCityReportPanelStage.failure,
            directory: directory,
            selectedSummary: directorySummary,
            failureCode: code,
          ),
        );
    }
  }

  /// 返回当前项目目录并清除详情；在详情读取进行中也会立即使其失效。
  void showDirectory() {
    final projectId = _projectId;
    final directory = _state.directory;
    if (projectId == null || directory == null) return;
    ++_generation;
    _retryOperation = null;
    _setState(
      CurrentCityReportPanelState(
        projectId: projectId,
        stage: CurrentCityReportPanelStage.directory,
        directory: directory,
      ),
    );
  }

  /// `showDirectory` 的语义别名，供面板按用户动作命名调用。
  void returnToDirectory() => showDirectory();

  /// 重试最近失败的阶段，不会自动跳到另一阶段或自动打开第一项。
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

    CurrentCityReportResult<CurrentCityReportSnapshotDirectory> result;
    try {
      result = await _gateway.listSnapshots(projectId);
    } catch (_) {
      result = const CurrentCityReportRejected(
        CurrentCityReportFailureCode.networkUnavailable,
      );
    }
    if (!_isCurrent(generation) || _projectId != projectId) return;

    switch (result) {
      case CurrentCityReportSuccess(:final value):
        _retryOperation = null;
        _setState(
          CurrentCityReportPanelState(
            projectId: projectId,
            stage: CurrentCityReportPanelStage.directory,
            directory: value,
          ),
        );
      case CurrentCityReportRejected(:final code):
        _setState(
          CurrentCityReportPanelState(
            projectId: projectId,
            stage: CurrentCityReportPanelStage.failure,
            failureCode: code,
          ),
        );
    }
  }

  bool _sameSummary(
    CurrentCityReportSnapshotSummary left,
    CurrentCityReportSnapshotSummary right,
  ) =>
      left.snapshotId == right.snapshotId &&
      left.reportId == right.reportId &&
      left.reportVersion == right.reportVersion &&
      left.reportingTimeZone == right.reportingTimeZone &&
      left.dataCutoffUtc == right.dataCutoffUtc &&
      left.releasedAtUtc == right.releasedAtUtc;

  bool _isCurrent(int generation) => !_disposed && generation == _generation;

  void _invalidateAndSet(CurrentCityReportPanelState state) {
    ++_generation;
    _retryOperation = null;
    _setState(state);
  }

  void _setState(CurrentCityReportPanelState state) {
    if (_disposed) return;
    _state = state;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    _retryOperation = null;
    _state = CurrentCityReportPanelState.inactive();
    super.dispose();
  }
}

sealed class _CurrentCityReportRetryOperation {
  const _CurrentCityReportRetryOperation();
}

final class _RetryLoadDirectory extends _CurrentCityReportRetryOperation {
  const _RetryLoadDirectory(this.projectId);

  final String projectId;
}

final class _RetryReadSnapshot extends _CurrentCityReportRetryOperation {
  const _RetryReadSnapshot(this.projectId, this.summary);

  final String projectId;
  final CurrentCityReportSnapshotSummary summary;
}
