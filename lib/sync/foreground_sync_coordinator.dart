import 'sync_engine.dart';
import 'sync_models.dart';

/// 前台同步调度只需要的三个 SyncEngine 操作。
abstract interface class ForegroundSyncWorker {
  Future<SyncBatchDrainResult> drainBatch();

  Future<SyncPullApplyResult> pullOnce();

  Future<SyncHealth> health();
}

/// 正式 SyncEngine 的收窄 Adapter。
final class SyncEngineForegroundWorker implements ForegroundSyncWorker {
  const SyncEngineForegroundWorker(this._engine);

  final SyncEngine _engine;

  @override
  Future<SyncBatchDrainResult> drainBatch() => _engine.drainBatch();

  @override
  Future<SyncHealth> health() => _engine.health();

  @override
  Future<SyncPullApplyResult> pullOnce() => _engine.pullOnce();
}

/// 合并前台唤醒并限制每轮工作量的同步协调器。
///
/// Widget 只在启动、恢复或提交后调用 [synchronize]。排空顺序、批次数上限和
/// 重复唤醒合并都属于这里，避免页面直接编排 SyncEngine。
final class ForegroundSyncCoordinator {
  ForegroundSyncCoordinator(this._worker);

  static const _maximumBatches = 20;

  final ForegroundSyncWorker? _worker;
  Future<void>? _activeSynchronization;
  bool _rerunRequested = false;
  bool _disposed = false;

  Future<SyncHealth?> health() async => _worker?.health();

  Future<void> synchronize() {
    final active = _activeSynchronization;
    if (active != null) {
      _rerunRequested = true;
      return active;
    }
    final worker = _worker;
    if (worker == null || _disposed) {
      return Future.value();
    }
    late final Future<void> operation;
    operation = _runUntilSettled(worker).whenComplete(() {
      if (identical(_activeSynchronization, operation)) {
        _activeSynchronization = null;
      }
    });
    _activeSynchronization = operation;
    return operation;
  }

  Future<void> _runUntilSettled(ForegroundSyncWorker worker) async {
    do {
      _rerunRequested = false;
      await _run(worker);
      if (!_rerunRequested || _disposed) {
        return;
      }
    } while (true);
  }

  Future<void> _run(ForegroundSyncWorker worker) async {
    for (var sent = 0; sent < _maximumBatches; sent++) {
      final result = await worker.drainBatch();
      if (result != SyncBatchDrainResult.processed) {
        break;
      }
    }
    for (var received = 0; received < _maximumBatches; received++) {
      final result = await worker.pullOnce();
      if (result != SyncPullApplyResult.applied) {
        break;
      }
    }
  }

  void dispose() {
    _disposed = true;
  }
}
