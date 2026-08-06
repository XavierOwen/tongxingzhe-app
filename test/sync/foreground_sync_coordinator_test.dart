import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tongxingzhe_app/sync/foreground_sync_coordinator.dart';
import 'package:tongxingzhe_app/sync/sync_models.dart';

void main() {
  test('一次前台同步排空可发送命令，再拉取全部可应用批次', () async {
    final worker = _FakeSyncWorker(
      drains: [
        SyncBatchDrainResult.processed,
        SyncBatchDrainResult.processed,
        SyncBatchDrainResult.idle,
      ],
      pulls: [SyncPullApplyResult.applied, SyncPullApplyResult.idle],
    );
    final coordinator = ForegroundSyncCoordinator(worker: worker);
    var notifications = 0;
    coordinator.addListener(() => notifications++);

    await coordinator.synchronize();

    expect(worker.drainCalls, 3);
    expect(worker.pullCalls, 2);
    expect(notifications, greaterThanOrEqualTo(4));
    expect(coordinator.isRunning, isFalse);
  });

  test('已有同步运行时把重复唤醒合并为一次串行补跑', () async {
    final gate = Completer<void>();
    final worker = _FakeSyncWorker(
      drains: [SyncBatchDrainResult.idle, SyncBatchDrainResult.idle],
      pulls: [SyncPullApplyResult.idle, SyncPullApplyResult.idle],
      gate: gate,
    );
    final coordinator = ForegroundSyncCoordinator(worker: worker);

    final first = coordinator.synchronize();
    final second = coordinator.synchronize();
    gate.complete();
    await Future.wait([first, second]);

    expect(identical(first, second), isTrue);
    expect(worker.drainCalls, 2);
    expect(worker.maximumConcurrentDrains, 1);
  });

  test('项目切换发生在同步中时补跑使用最新 worker', () async {
    final gate = Completer<void>();
    final firstWorker = _FakeSyncWorker(gate: gate);
    final nextWorker = _FakeSyncWorker();
    final coordinator = ForegroundSyncCoordinator(worker: firstWorker);

    final synchronization = coordinator.synchronize();
    coordinator.replaceWorker(nextWorker);
    final repeated = coordinator.synchronize();
    gate.complete();
    await Future.wait([synchronization, repeated]);

    expect(firstWorker.drainCalls, 1);
    expect(nextWorker.drainCalls, 1);
  });
}

final class _FakeSyncWorker implements ForegroundSyncWorker {
  _FakeSyncWorker({
    List<SyncBatchDrainResult> drains = const [SyncBatchDrainResult.idle],
    List<SyncPullApplyResult> pulls = const [SyncPullApplyResult.idle],
    this.gate,
  }) : _drains = [...drains],
       _pulls = [...pulls];

  final List<SyncBatchDrainResult> _drains;
  final List<SyncPullApplyResult> _pulls;
  final Completer<void>? gate;
  int drainCalls = 0;
  int pullCalls = 0;
  int concurrentDrains = 0;
  int maximumConcurrentDrains = 0;

  @override
  Future<SyncBatchDrainResult> drainBatch() async {
    drainCalls++;
    concurrentDrains++;
    maximumConcurrentDrains = maximumConcurrentDrains < concurrentDrains
        ? concurrentDrains
        : maximumConcurrentDrains;
    try {
      await gate?.future;
      return _drains.removeAt(0);
    } finally {
      concurrentDrains--;
    }
  }

  @override
  Future<SyncHealth> health() async => const SyncHealth(
    onlyOnDeviceCount: 0,
    syncingCount: 0,
    retryingCount: 0,
    needsResolutionCount: 0,
    permanentFailureCount: 0,
    completedCount: 0,
    oldestPendingAge: null,
    lastSuccessAtUtc: null,
    lastFailureCode: null,
    serverCursor: null,
  );

  @override
  Future<SyncPullApplyResult> pullOnce() async {
    pullCalls++;
    return _pulls.removeAt(0);
  }
}
