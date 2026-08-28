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
    final coordinator = ForegroundSyncCoordinator(worker);

    await coordinator.synchronize();

    expect(worker.drainCalls, 3);
    expect(worker.pullCalls, 2);
  });

  test('已有同步运行时把重复唤醒合并为一次串行补跑', () async {
    final gate = Completer<void>();
    final worker = _FakeSyncWorker(
      drains: [SyncBatchDrainResult.idle, SyncBatchDrainResult.idle],
      pulls: [SyncPullApplyResult.idle, SyncPullApplyResult.idle],
      gate: gate,
    );
    final coordinator = ForegroundSyncCoordinator(worker);

    final first = coordinator.synchronize();
    final second = coordinator.synchronize();
    gate.complete();
    await Future.wait([first, second]);

    expect(identical(first, second), isTrue);
    expect(worker.drainCalls, 2);
    expect(worker.maximumConcurrentDrains, 1);
  });

  test('每轮发送与拉取分别限制为二十批', () async {
    final worker = _FakeSyncWorker(
      drains: List.filled(21, SyncBatchDrainResult.processed),
      pulls: List.filled(21, SyncPullApplyResult.applied),
    );
    final coordinator = ForegroundSyncCoordinator(worker);

    await coordinator.synchronize();

    expect(worker.drainCalls, 20);
    expect(worker.pullCalls, 20);
  });

  test('同步失败后清除运行状态并允许重试', () async {
    final worker = _FakeSyncWorker(failNextDrain: true);
    final coordinator = ForegroundSyncCoordinator(worker);

    await expectLater(coordinator.synchronize(), throwsStateError);
    await coordinator.synchronize();

    expect(worker.drainCalls, 2);
    expect(worker.pullCalls, 1);
  });
}

final class _FakeSyncWorker implements ForegroundSyncWorker {
  _FakeSyncWorker({
    List<SyncBatchDrainResult> drains = const [SyncBatchDrainResult.idle],
    List<SyncPullApplyResult> pulls = const [SyncPullApplyResult.idle],
    this.gate,
    this.failNextDrain = false,
  }) : _drains = [...drains],
       _pulls = [...pulls];

  final List<SyncBatchDrainResult> _drains;
  final List<SyncPullApplyResult> _pulls;
  final Completer<void>? gate;
  bool failNextDrain;
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
      if (failNextDrain) {
        failNextDrain = false;
        throw StateError('synthetic_sync_failure');
      }
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
