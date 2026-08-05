import 'dart:math';

import 'sync_models.dart';

/// SyncEngine 唯一的远端写入接缝。
///
/// HTTP 状态、认证刷新和响应 JSON 都由生产 Adapter 转换为稳定结果。测试用
/// 内存 Adapter 可确定性制造重复、超时、冲突和拒绝。
abstract interface class SyncTransport {
  Future<SyncPushResult> push(SyncCommand command);

  Future<SyncPullResult> pull({
    required SyncScope scope,
    required String? cursor,
    int limit = 100,
  });

  Future<void> close();
}

abstract interface class SyncJitter {
  /// 返回 `[0, 1)` 的值，用于让多台设备的重试时刻分散。
  double nextUnitInterval();
}

final class FixedSyncJitter implements SyncJitter {
  const FixedSyncJitter(this.value) : assert(value >= 0), assert(value < 1);

  final double value;

  @override
  double nextUnitInterval() => value;
}

final class SecureSyncJitter implements SyncJitter {
  SecureSyncJitter() : _random = Random.secure();

  final Random _random;

  @override
  double nextUnitInterval() => _random.nextDouble();
}
