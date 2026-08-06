/// 当前 bearer token 被授权处理的同步范围。
final class SyncScope {
  const SyncScope({
    required this.appUserId,
    required this.workspaceId,
    required this.projectId,
  });

  final String appUserId;
  final String workspaceId;
  final String projectId;
}

/// 交给同步 Transport 的稳定 command envelope。
final class SyncCommand {
  const SyncCommand({
    required this.protocolVersion,
    required this.commandId,
    required this.deviceId,
    required this.aggregateId,
    required this.baseRevision,
    required this.commandType,
    required this.payload,
  });

  final int protocolVersion;
  final String commandId;
  final String deviceId;
  final String aggregateId;
  final int baseRevision;
  final String commandType;
  final Map<String, Object?> payload;
}

sealed class SyncPushResult {
  const SyncPushResult();
}

/// Backend 已接受 command，或确认同一 command 已经处理。
final class SyncPushAccepted extends SyncPushResult {
  const SyncPushAccepted({required this.serverCursor, this.duplicate = false});

  final String serverCursor;
  final bool duplicate;
}

final class SyncPushConflict extends SyncPushResult {
  const SyncPushConflict({this.failureCode = 'conflict'});

  final String failureCode;
}

final class SyncPushPermanentFailure extends SyncPushResult {
  const SyncPushPermanentFailure({required this.failureCode});

  final String failureCode;
}

final class SyncPushRetryable extends SyncPushResult {
  const SyncPushRetryable({required this.failureCode, this.retryAfter});

  final String failureCode;
  final Duration? retryAfter;
}

final class SyncRemoteChange {
  const SyncRemoteChange({
    required this.changeType,
    required this.revisionNumber,
    required this.payload,
  });

  final String changeType;
  final int revisionNumber;
  final Map<String, Object?> payload;
}

final class SyncPullBatch {
  const SyncPullBatch({required this.changes, required this.nextCursor});

  final List<SyncRemoteChange> changes;
  final String? nextCursor;
}

sealed class SyncPullResult {
  const SyncPullResult();
}

final class SyncPullSucceeded extends SyncPullResult {
  const SyncPullSucceeded(this.batch);

  final SyncPullBatch batch;
}

final class SyncPullRetryable extends SyncPullResult {
  const SyncPullRetryable({required this.failureCode});

  final String failureCode;
}

final class SyncPullPermanentFailure extends SyncPullResult {
  const SyncPullPermanentFailure({required this.failureCode});

  final String failureCode;
}

enum SyncPullApplyResult { idle, applied, retryableFailure, permanentFailure }

enum SyncDrainResult {
  idle,
  busy,
  completed,
  retryScheduled,
  needsResolution,
  permanentFailure,
  lostLease,
}

/// UI 可见的最小同步健康状态，不含 command payload 或自由文本。
final class SyncHealth {
  const SyncHealth({
    required this.onlyOnDeviceCount,
    required this.syncingCount,
    required this.retryingCount,
    required this.needsResolutionCount,
    required this.permanentFailureCount,
    required this.completedCount,
    required this.oldestPendingAge,
    required this.lastSuccessAtUtc,
    required this.lastFailureCode,
    required this.serverCursor,
  });

  final int onlyOnDeviceCount;
  final int syncingCount;
  final int retryingCount;
  final int needsResolutionCount;
  final int permanentFailureCount;
  final int completedCount;
  final Duration? oldestPendingAge;
  final DateTime? lastSuccessAtUtc;
  final String? lastFailureCode;
  final String? serverCursor;
}
