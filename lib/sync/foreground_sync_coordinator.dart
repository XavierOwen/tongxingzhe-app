import 'package:flutter/foundation.dart';

import 'sync_engine.dart';
import 'sync_models.dart';

/// 前台同步调度只需要的三个 SyncEngine 操作。
abstract interface class ForegroundSyncWorker {
  Future<SyncDrainResult> drainOnce();

  Future<SyncPullApplyResult> pullOnce();

  Future<SyncHealth> health();
}

/// 正式 SyncEngine 的收窄 Adapter。
final class SyncEngineForegroundWorker implements ForegroundSyncWorker {
  const SyncEngineForegroundWorker(this._engine);

  final SyncEngine _engine;

  @override
  Future<SyncDrainResult> drainOnce() => _engine.drainOnce();

  @override
  Future<SyncHealth> health() => _engine.health();

  @override
  Future<SyncPullApplyResult> pullOnce() => _engine.pullOnce();
}

/// 合并前台唤醒并限制每轮工作量的同步协调器。
///
/// Widget 只在启动、恢复或提交后调用 [synchronize]。排空顺序、批次数上限和
/// 重复唤醒合并都属于这里，避免页面直接编排 SyncEngine。
final class ForegroundSyncCoordinator extends ChangeNotifier {
  factory ForegroundSyncCoordinator({
    required ForegroundSyncWorker? worker,
    int maximumBatches = 20,
  }) {
    if (maximumBatches < 1) {
      throw ArgumentError.value(maximumBatches, 'maximumBatches');
    }
    return ForegroundSyncCoordinator._(worker, maximumBatches);
  }

  ForegroundSyncCoordinator._(this._worker, this._maximumBatches);

  ForegroundSyncWorker? _worker;
  final int _maximumBatches;
  Future<void>? _activeSynchronization;
  bool _rerunRequested = false;
  bool _disposed = false;

  bool get isRunning => _activeSynchronization != null;

  void replaceWorker(ForegroundSyncWorker? worker) {
    _worker = worker;
    if (_activeSynchronization != null) {
      _rerunRequested = true;
    }
  }

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
        _notify();
      }
    });
    _activeSynchronization = operation;
    _notify();
    return operation;
  }

  Future<void> _runUntilSettled(ForegroundSyncWorker initialWorker) async {
    var worker = initialWorker;
    do {
      _rerunRequested = false;
      await _run(worker);
      final replacement = _worker;
      if (!_rerunRequested || replacement == null || _disposed) {
        return;
      }
      worker = replacement;
    } while (true);
  }

  Future<void> _run(ForegroundSyncWorker worker) async {
    for (var sent = 0; sent < _maximumBatches; sent++) {
      final result = await worker.drainOnce();
      _notify();
      if (result != SyncDrainResult.completed) {
        break;
      }
    }
    for (var received = 0; received < _maximumBatches; received++) {
      final result = await worker.pullOnce();
      _notify();
      if (result != SyncPullApplyResult.applied) {
        break;
      }
    }
  }

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
