import 'dart:convert';
import 'dart:math';

import 'package:drift/drift.dart';

import '../data/local_database.dart';
import '../features/contact_journal/contact_models.dart';
import '../foundation/runtime_values.dart';
import '../questionnaires/questionnaire_answer_codec.dart';
import '../questionnaires/questionnaire_contract.dart'
    show QuestionnaireQuestionType;
import '../regions/region_catalog.dart';
import '../targets/promotion_target.dart';
import 'sync_models.dart';
import 'sync_transport.dart';

/// 独占 Outbox 领取、租约、ACK、退避与健康状态的同步深模块。
///
/// 前台调度器使用 [drainBatch]，一次只领取每个 aggregate 的最早
/// command。[drainOnce] 保留为单条合同和测试入口。页面不能直接读写
/// Outbox；跨进程互斥由 SQLite 租约表提供。
final class SyncEngine {
  factory SyncEngine({
    required LocalDatabase database,
    required AppClock clock,
    required String workerId,
    required SyncScope scope,
    required SyncTransport transport,
    required SyncJitter jitter,
    Duration leaseDuration = const Duration(seconds: 30),
  }) {
    if (workerId.trim().isEmpty) {
      throw ArgumentError.value(workerId, 'workerId', 'must not be empty');
    }
    return SyncEngine._(
      database,
      clock,
      workerId,
      scope,
      transport,
      jitter,
      leaseDuration,
      RegionCatalog(database),
    );
  }

  SyncEngine._(
    this._database,
    this._clock,
    this._workerId,
    this._scope,
    this._transport,
    this._jitter,
    this._leaseDuration,
    this._regionCatalog,
  );

  static const _drainerLeaseName = 'sync.global.v1';
  static const _maximumRetryDelay = Duration(minutes: 5);
  static const _maximumRetryAfter = Duration(hours: 1);
  static final _stableFailureCode = RegExp(r'^[a-z][a-z0-9_]{0,63}$');

  final LocalDatabase _database;
  final AppClock _clock;
  final String _workerId;
  final SyncScope _scope;
  final SyncTransport _transport;
  final SyncJitter _jitter;
  final Duration _leaseDuration;
  final RegionCatalog _regionCatalog;

  Future<SyncDrainResult> drainOnce() async {
    final claim = await _claimReadyCommand();
    if (claim case _ClaimBusy()) {
      return SyncDrainResult.busy;
    }
    if (claim case _ClaimIdle()) {
      return SyncDrainResult.idle;
    }
    final leased = (claim as _ClaimedCommand).row;

    SyncPushResult result;
    try {
      result = await _transport.push(_commandFromRow(leased));
    } on FormatException {
      result = const SyncPushPermanentFailure(
        failureCode: 'invalid_local_payload',
      );
    } catch (_) {
      result = const SyncPushRetryable(failureCode: 'network_unavailable');
    }

    return _acknowledge(leased, result);
  }

  /// 一次领取不同 aggregate 的最多 [limit] 条 command。
  ///
  /// 旧的单条 Transport 自动退化为 [drainOnce]；生产 HTTP Adapter
  /// 按 command ID 归位每条结果，不依赖服务端的返回顺序。
  Future<SyncBatchDrainResult> drainBatch({int limit = 20}) async {
    if (limit < 1 || limit > 20) {
      throw ArgumentError.value(limit, 'limit', 'must be between 1 and 20');
    }
    final transport = _transport;
    if (transport is! SyncBatchTransport) {
      return switch (await drainOnce()) {
        SyncDrainResult.idle => SyncBatchDrainResult.idle,
        SyncDrainResult.busy => SyncBatchDrainResult.busy,
        SyncDrainResult.lostLease => SyncBatchDrainResult.lostLease,
        _ => SyncBatchDrainResult.processed,
      };
    }
    final batchTransport = transport as SyncBatchTransport;

    final claim = await _claimReadyCommands(limit);
    if (claim case _BatchClaimBusy()) {
      return SyncBatchDrainResult.busy;
    }
    if (claim case _BatchClaimIdle()) {
      return SyncBatchDrainResult.idle;
    }
    final leased = (claim as _ClaimedCommands).rows;
    final commands = <SyncCommand>[];
    final resultsById = <String, SyncPushResult>{};
    for (final row in leased) {
      try {
        commands.add(_commandFromRow(row));
      } on FormatException {
        resultsById[row.commandId] = const SyncPushPermanentFailure(
          failureCode: 'invalid_local_payload',
        );
      }
    }

    if (commands.isNotEmpty) {
      try {
        final outcomes = await batchTransport.pushBatch(commands);
        final expectedIds = {for (final command in commands) command.commandId};
        final receivedIds = <String>{};
        final validResponse =
            outcomes.length == commands.length &&
            outcomes.every(
              (outcome) =>
                  expectedIds.contains(outcome.commandId) &&
                  receivedIds.add(outcome.commandId),
            );
        if (validResponse) {
          for (final outcome in outcomes) {
            resultsById[outcome.commandId] = outcome.result;
          }
        } else {
          for (final command in commands) {
            resultsById[command.commandId] = const SyncPushRetryable(
              failureCode: 'invalid_server_response',
            );
          }
        }
      } catch (_) {
        for (final command in commands) {
          resultsById[command.commandId] = const SyncPushRetryable(
            failureCode: 'network_unavailable',
          );
        }
      }
    }

    return _acknowledgeBatch(leased, resultsById);
  }

  Future<SyncHealth> health() async {
    final nowUtc = _clock.now().toUtc();
    final result = await _database
        .readSyncHealth(_scope.appUserId, _scope.workspaceId, _scope.projectId)
        .getSingle();
    final scopeQuery = _database.select(_database.dbSyncScopes)
      ..where(
        (row) =>
            row.appUserId.equals(_scope.appUserId) &
            row.workspaceId.equals(_scope.workspaceId) &
            row.projectId.equals(_scope.projectId),
      );
    final storedScope = await scopeQuery.getSingleOrNull();
    final oldest = result.oldestPendingAtUtc?.toUtc();
    final age = oldest == null ? null : nowUtc.difference(oldest);

    return SyncHealth(
      onlyOnDeviceCount: result.onlyOnDeviceCount,
      syncingCount: result.syncingCount,
      retryingCount: result.retryingCount,
      needsResolutionCount: result.needsResolutionCount,
      permanentFailureCount: result.permanentFailureCount,
      completedCount: result.completedCount,
      oldestPendingAge: age == null || age.isNegative ? Duration.zero : age,
      lastSuccessAtUtc: storedScope?.lastSuccessAtUtc?.toUtc(),
      lastFailureCode: storedScope?.lastFailureCode,
      serverCursor: storedScope?.serverCursor,
    );
  }

  /// 拉取一个远端 batch，并在同一 transaction 中应用全部变化和新 cursor。
  Future<SyncPullApplyResult> pullOnce() async {
    final scopeQuery = _database.select(_database.dbSyncScopes)
      ..where(
        (row) =>
            row.appUserId.equals(_scope.appUserId) &
            row.workspaceId.equals(_scope.workspaceId) &
            row.projectId.equals(_scope.projectId),
      );
    final existingScope = await scopeQuery.getSingleOrNull();
    final result = await _transport.pull(
      scope: _scope,
      cursor: existingScope?.serverCursor,
    );
    switch (result) {
      case final SyncPullRetryable retryable:
        await _writeScopeState(
          nowUtc: _clock.now().toUtc(),
          lastFailureCode: _failureCode(retryable.failureCode),
        );
        return SyncPullApplyResult.retryableFailure;
      case final SyncPullPermanentFailure failure:
        await _writeScopeState(
          nowUtc: _clock.now().toUtc(),
          lastFailureCode: _failureCode(failure.failureCode),
        );
        return SyncPullApplyResult.permanentFailure;
      case final SyncPullSucceeded succeeded:
        try {
          final parsed = [
            for (final change in succeeded.batch.changes)
              _parseRemoteChange(change),
          ];
          final nextCursor = succeeded.batch.nextCursor;
          if (parsed.isNotEmpty && (nextCursor == null || nextCursor.isEmpty)) {
            throw const FormatException('remote batch cursor is required');
          }
          final nowUtc = _clock.now().toUtc();
          await _database.transaction(() async {
            for (final change in parsed) {
              switch (change) {
                case final _RemoteContact contact:
                  await _applyRemoteContact(contact);
                case final _RemoteContactRevision revision:
                  await _applyRemoteContactRevision(revision);
                case final _RemoteContactAttempt attempt:
                  await _applyRemoteContactAttempt(attempt);
                case final _RemoteDraftUpsert draft:
                  await _applyRemoteDraftUpsert(draft);
                case final _RemoteDraftDelete draft:
                  await _applyRemoteDraftDelete(draft);
              }
            }
            await _writeScopeState(
              nowUtc: nowUtc,
              serverCursor: nextCursor ?? existingScope?.serverCursor,
              lastSuccessAtUtc: nowUtc,
              lastFailureCode: null,
            );
          });
          return parsed.isEmpty
              ? SyncPullApplyResult.idle
              : SyncPullApplyResult.applied;
        } on FormatException {
          await _writeScopeState(
            nowUtc: _clock.now().toUtc(),
            lastFailureCode: 'invalid_remote_change',
          );
          return SyncPullApplyResult.permanentFailure;
        } catch (_) {
          await _writeScopeState(
            nowUtc: _clock.now().toUtc(),
            lastFailureCode: 'remote_apply_failed',
          );
          return SyncPullApplyResult.retryableFailure;
        }
    }
  }

  Future<_ClaimResult> _claimReadyCommand() async {
    final result = await _claimReadyCommands(1);
    return switch (result) {
      _BatchClaimBusy() => const _ClaimBusy(),
      _BatchClaimIdle() => const _ClaimIdle(),
      _ClaimedCommands(:final rows) => _ClaimedCommand(rows.single),
    };
  }

  Future<_BatchClaimResult> _claimReadyCommands(int limit) async {
    try {
      return await _database.transaction(() async {
        final nowUtc = _clock.now().toUtc();
        final leaseQuery = _database.select(_database.dbSyncDrainerLeases)
          ..where((row) => row.leaseName.equals(_drainerLeaseName));
        final currentLease = await leaseQuery.getSingleOrNull();
        if (currentLease != null &&
            currentLease.leaseExpiresAtUtc.toUtc().isAfter(nowUtc)) {
          return const _BatchClaimBusy();
        }

        if (currentLease != null) {
          await (_database.delete(
            _database.dbSyncDrainerLeases,
          )..where((row) => row.leaseName.equals(_drainerLeaseName))).go();
        }
        final leaseExpiresAtUtc = nowUtc.add(_leaseDuration);
        await _database
            .into(_database.dbSyncDrainerLeases)
            .insert(
              DbSyncDrainerLeasesCompanion.insert(
                leaseName: _drainerLeaseName,
                leaseOwner: _workerId,
                leaseExpiresAtUtc: leaseExpiresAtUtc,
              ),
            );

        await (_database.update(_database.dbSyncOutbox)..where(
              (row) =>
                  row.status.equals('leased') &
                  row.leaseExpiresAtUtc.isSmallerOrEqualValue(nowUtc),
            ))
            .write(
              DbSyncOutboxCompanion(
                status: const Value('pending'),
                nextAttemptAtUtc: Value(nowUtc),
                leaseOwner: const Value(null),
                leaseExpiresAtUtc: const Value(null),
                lastFailureCode: const Value('lease_expired'),
              ),
            );

        final claimed = <DbSyncOutboxData>[];
        for (var index = 0; index < limit; index++) {
          final ready = await _database
              .readReadySyncCommand(
                _scope.appUserId,
                _scope.workspaceId,
                _scope.projectId,
                nowUtc,
              )
              .getSingleOrNull();
          if (ready == null) {
            break;
          }
          final changed =
              await (_database.update(_database.dbSyncOutbox)..where(
                    (row) =>
                        row.commandId.equals(ready.commandId) &
                        row.status.equals('pending'),
                  ))
                  .write(
                    DbSyncOutboxCompanion(
                      status: const Value('leased'),
                      attemptCount: Value(ready.attemptCount + 1),
                      leaseOwner: Value(_workerId),
                      leaseExpiresAtUtc: Value(leaseExpiresAtUtc),
                    ),
                  );
          if (changed != 1) {
            throw const _ClaimCollision();
          }
          claimed.add(
            ready.copyWith(
              status: 'leased',
              attemptCount: ready.attemptCount + 1,
              leaseOwner: Value(_workerId),
              leaseExpiresAtUtc: Value(leaseExpiresAtUtc),
            ),
          );
        }
        if (claimed.isEmpty) {
          await _releaseDrainerLease();
          return const _BatchClaimIdle();
        }
        return _ClaimedCommands(List.unmodifiable(claimed));
      });
    } on _ClaimCollision {
      return const _BatchClaimBusy();
    }
  }

  Future<SyncDrainResult> _acknowledge(
    DbSyncOutboxData leased,
    SyncPushResult result,
  ) {
    return _database.transaction(() async {
      final nowUtc = _clock.now().toUtc();
      final commandQuery = _database.select(_database.dbSyncOutbox)
        ..where((row) => row.commandId.equals(leased.commandId));
      final current = await commandQuery.getSingleOrNull();
      if (current == null ||
          current.status != 'leased' ||
          current.leaseOwner != _workerId) {
        await _releaseDrainerLease();
        return SyncDrainResult.lostLease;
      }

      final outcome = await _applyAcknowledgement(current, result, nowUtc);
      await _releaseDrainerLease();
      return outcome;
    });
  }

  Future<SyncBatchDrainResult> _acknowledgeBatch(
    List<DbSyncOutboxData> leased,
    Map<String, SyncPushResult> resultsById,
  ) {
    return _database.transaction(() async {
      final nowUtc = _clock.now().toUtc();
      var lostLease = false;
      String? lastFailureCode;
      for (final claimed in leased) {
        final commandQuery = _database.select(_database.dbSyncOutbox)
          ..where((row) => row.commandId.equals(claimed.commandId));
        final current = await commandQuery.getSingleOrNull();
        if (current == null ||
            current.status != 'leased' ||
            current.leaseOwner != _workerId) {
          lostLease = true;
          continue;
        }
        final result = resultsById[claimed.commandId];
        if (result == null) {
          lostLease = true;
          continue;
        }
        await _applyAcknowledgement(current, result, nowUtc);
        lastFailureCode = switch (result) {
          SyncPushAccepted() => lastFailureCode,
          SyncPushConflict(:final failureCode) => _failureCode(failureCode),
          SyncPushPermanentFailure(:final failureCode) => _failureCode(
            failureCode,
          ),
          SyncPushRetryable(:final failureCode) => _failureCode(failureCode),
        };
      }
      if (lastFailureCode != null) {
        await _writeScopeState(
          nowUtc: nowUtc,
          lastFailureCode: lastFailureCode,
        );
      }
      await _releaseDrainerLease();
      return lostLease
          ? SyncBatchDrainResult.lostLease
          : SyncBatchDrainResult.processed;
    });
  }

  Future<SyncDrainResult> _applyAcknowledgement(
    DbSyncOutboxData current,
    SyncPushResult result,
    DateTime nowUtc,
  ) async {
    if (result is SyncPushConflict &&
        current.commandType == 'draft.upsert.v1') {
      final draftQuery = _database.select(_database.dbContactDrafts)
        ..where((row) => row.draftId.equals(current.aggregateId));
      final draft = await draftQuery.getSingleOrNull();
      if (draft != null) {
        await _preserveLocalDraftAsConflict(draft);
      }
    }
    if (result case SyncPushConflict(:final conflict?)) {
      if (current.commandType == 'contact.revise.v1') {
        await _installContactRevisionConflict(current, conflict, nowUtc);
      }
    }

    return switch (result) {
      final SyncPushAccepted accepted => _completeCommand(
        current,
        accepted,
        nowUtc,
      ),
      final SyncPushConflict conflict => _stopCommand(
        current,
        status: 'needs_resolution',
        failureCode: conflict.failureCode,
        nowUtc: nowUtc,
        outcome: SyncDrainResult.needsResolution,
      ),
      final SyncPushPermanentFailure failure => _stopCommand(
        current,
        status: 'permanent_failure',
        failureCode: failure.failureCode,
        nowUtc: nowUtc,
        outcome: SyncDrainResult.permanentFailure,
      ),
      final SyncPushRetryable retryable => _retryCommand(
        current,
        retryable,
        nowUtc,
      ),
    };
  }

  SyncCommand _commandFromRow(DbSyncOutboxData row) {
    final decoded = jsonDecode(row.payloadJson);
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('sync payload must be an object');
    }
    return SyncCommand(
      protocolVersion: row.protocolVersion,
      commandId: row.commandId,
      deviceId: row.deviceId,
      aggregateId: row.aggregateId,
      baseRevision: row.baseRevision,
      commandType: row.commandType,
      payload: Map.unmodifiable(decoded),
    );
  }

  Future<SyncDrainResult> _completeCommand(
    DbSyncOutboxData current,
    SyncPushAccepted accepted,
    DateTime nowUtc,
  ) async {
    if (accepted.serverCursor.isEmpty) {
      return _stopCommand(
        current,
        status: 'permanent_failure',
        failureCode: 'invalid_server_cursor',
        nowUtc: nowUtc,
        outcome: SyncDrainResult.permanentFailure,
      );
    }
    await (_database.update(
      _database.dbSyncOutbox,
    )..where((row) => row.commandId.equals(current.commandId))).write(
      DbSyncOutboxCompanion(
        status: const Value('completed'),
        leaseOwner: const Value(null),
        leaseExpiresAtUtc: const Value(null),
        lastFailureCode: const Value(null),
        completedAtUtc: Value(nowUtc),
      ),
    );
    if (current.commandType == 'draft.upsert.v1') {
      final acceptedRevision = current.baseRevision + 1;
      await (_database.update(
        _database.dbContactDrafts,
      )..where((row) => row.draftId.equals(current.aggregateId))).write(
        DbContactDraftsCompanion(serverRevision: Value(acceptedRevision)),
      );
      await (_database.update(_database.dbSyncOutbox)..where(
            (row) =>
                row.aggregateId.equals(current.aggregateId) &
                row.commandType.equals('draft.upsert.v1') &
                row.status.equals('pending'),
          ))
          .write(DbSyncOutboxCompanion(baseRevision: Value(acceptedRevision)));
    } else if (current.commandType == 'draft.delete.v1') {
      final acceptedRevision = current.baseRevision + 1;
      await (_database.update(
        _database.dbContactDrafts,
      )..where((row) => row.draftId.equals(current.aggregateId))).write(
        DbContactDraftsCompanion(serverRevision: Value(acceptedRevision)),
      );
    } else if (current.commandType == 'contact.resolve.v1') {
      await (_database.update(_database.dbContactRevisionConflicts)..where(
            (row) =>
                row.resolutionCommandId.equals(current.commandId) &
                row.status.equals('resolution_pending'),
          ))
          .write(
            DbContactRevisionConflictsCompanion(
              status: const Value('resolved'),
              resolvedAtUtc: Value(nowUtc),
            ),
          );
    }
    await _writeScopeState(
      nowUtc: nowUtc,
      lastSuccessAtUtc: nowUtc,
      lastFailureCode: null,
    );
    return SyncDrainResult.completed;
  }

  Future<void> _installContactRevisionConflict(
    DbSyncOutboxData command,
    SyncContactRevisionConflict conflict,
    DateTime nowUtc,
  ) async {
    if (conflict.contactId != command.aggregateId ||
        conflict.baseRevision != command.baseRevision ||
        conflict.currentRevision <= conflict.baseRevision ||
        conflict.questionnaireVersionId.trim().isEmpty ||
        conflict.conflictingFields.isEmpty) {
      throw const FormatException('revision conflict does not match command');
    }
    final contactQuery = _database.select(_database.dbContactRecords)
      ..where((row) => row.contactId.equals(command.aggregateId));
    final contact = await contactQuery.getSingleOrNull();
    if (contact == null ||
        contact.appUserId != _scope.appUserId ||
        contact.workspaceId != _scope.workspaceId ||
        contact.projectId != _scope.projectId ||
        contact.questionnaireVersionId != conflict.questionnaireVersionId ||
        contact.currentRevision < conflict.baseRevision + 1) {
      throw const FormatException('revision conflict scope is invalid');
    }
    if (!await _localRevisionMatchesSnapshot(
      contactId: command.aggregateId,
      revisionNumber: conflict.baseRevision + 1,
      snapshot: conflict.proposedSnapshot,
    )) {
      throw const FormatException('revision conflict lost the local proposal');
    }

    final currentLocation = _remoteLocationColumns(
      conflict.currentSnapshot.location,
    );
    if (conflict.currentSnapshot.location
        case final ResolvedContactLocation resolved) {
      await _regionCatalog.requireAnalyzableRegion(
        regionId: resolved.smallestRegionId,
        treeVersion: resolved.regionTreeVersion,
      );
    }

    await (_database.delete(_database.dbContactAnswers)..where(
          (row) =>
              row.contactId.equals(command.aggregateId) &
              row.revisionNumber.isBiggerThanValue(conflict.baseRevision),
        ))
        .go();
    await (_database.delete(_database.dbContactTargetLinks)..where(
          (row) =>
              row.contactId.equals(command.aggregateId) &
              row.revisionNumber.isBiggerThanValue(conflict.baseRevision),
        ))
        .go();
    await (_database.delete(_database.dbContactRevisions)..where(
          (row) =>
              row.contactId.equals(command.aggregateId) &
              row.revisionNumber.isBiggerThanValue(conflict.baseRevision),
        ))
        .go();
    await _database
        .into(_database.dbContactRevisions)
        .insert(
          DbContactRevisionsCompanion.insert(
            revisionId:
                '${command.aggregateId}:remote:${conflict.currentRevision}',
            contactId: command.aggregateId,
            revisionNumber: conflict.currentRevision,
            revisionKind: Value(conflict.currentRevisionKind.storageValue),
            revisedByAppUserId: _scope.appUserId,
            revisedAtUtc: conflict.currentRevisedAtUtc,
            reason: Value(conflict.currentReason),
            occurredAtUtc: conflict.currentSnapshot.occurredAtUtc,
            occurredTimeZone: conflict.currentSnapshot.occurredTimeZone,
            channel: conflict.currentSnapshot.channel.storageValue,
            channelDetail: Value(conflict.currentSnapshot.channelDetail),
            locationKind: currentLocation.kind,
            placeName: Value(currentLocation.placeName),
            smallestRegionId: Value(currentLocation.smallestRegionId),
            regionTreeVersion: Value(currentLocation.regionTreeVersion),
            latitude: Value(currentLocation.latitude),
            longitude: Value(currentLocation.longitude),
            locationAccuracyMeters: Value(currentLocation.accuracyMeters),
            reachCount: conflict.currentSnapshot.reachCount,
            interestLevel: conflict.currentSnapshot.interestLevel,
          ),
        );
    for (final answer in conflict.currentSnapshot.answers) {
      await _insertContactAnswer(
        contactId: command.aggregateId,
        revisionNumber: conflict.currentRevision,
        answer: answer,
      );
    }
    await _insertRemoteContactTargetLinks(
      contactId: command.aggregateId,
      revisionNumber: conflict.currentRevision,
      targetLinks: conflict.currentSnapshot.targetLinks,
    );
    await (_database.update(
      _database.dbContactRecords,
    )..where((row) => row.contactId.equals(command.aggregateId))).write(
      DbContactRecordsCompanion(
        occurredAtUtc: Value(conflict.currentSnapshot.occurredAtUtc),
        occurredTimeZone: Value(conflict.currentSnapshot.occurredTimeZone),
        channel: Value(conflict.currentSnapshot.channel.storageValue),
        channelDetail: Value(conflict.currentSnapshot.channelDetail),
        locationKind: Value(currentLocation.kind),
        placeName: Value(currentLocation.placeName),
        smallestRegionId: Value(currentLocation.smallestRegionId),
        regionTreeVersion: Value(currentLocation.regionTreeVersion),
        latitude: Value(currentLocation.latitude),
        longitude: Value(currentLocation.longitude),
        locationAccuracyMeters: Value(currentLocation.accuracyMeters),
        reachCount: Value(conflict.currentSnapshot.reachCount),
        interestLevel: Value(conflict.currentSnapshot.interestLevel),
        currentRevision: Value(conflict.currentRevision),
        lifecycleStatus: const Value('active'),
      ),
    );
    if (conflict.currentSnapshot.location
        case final ResolvedContactLocation resolved) {
      await _regionCatalog.assignContact(
        contactId: command.aggregateId,
        regionId: resolved.smallestRegionId,
        treeVersion: resolved.regionTreeVersion,
      );
    } else {
      await _regionCatalog.clearContactAssignment(command.aggregateId);
    }
    await _database
        .into(_database.dbContactRevisionConflicts)
        .insertOnConflictUpdate(
          DbContactRevisionConflictsCompanion.insert(
            conflictId: conflict.conflictId,
            commandId: command.commandId,
            contactId: command.aggregateId,
            appUserId: _scope.appUserId,
            workspaceId: _scope.workspaceId,
            projectId: _scope.projectId,
            baseRevision: conflict.baseRevision,
            currentRevision: conflict.currentRevision,
            conflictingFieldsJson: jsonEncode(conflict.conflictingFields),
            questionnaireVersionId: conflict.questionnaireVersionId,
            currentRevisionKind: conflict.currentRevisionKind.storageValue,
            currentRevisedAtUtc: conflict.currentRevisedAtUtc,
            currentReason: conflict.currentReason,
            currentSnapshotJson: jsonEncode(
              _conflictSnapshotPayload(conflict.currentSnapshot),
            ),
            proposedSnapshotJson: jsonEncode(
              _conflictSnapshotPayload(conflict.proposedSnapshot),
            ),
            createdAtUtc: nowUtc,
          ),
        );
  }

  Future<bool> _localRevisionMatchesSnapshot({
    required String contactId,
    required int revisionNumber,
    required ContactConflictSnapshot snapshot,
  }) async {
    final query = _database.select(_database.dbContactRevisions)
      ..where(
        (row) =>
            row.contactId.equals(contactId) &
            row.revisionNumber.equals(revisionNumber),
      );
    final stored = await query.getSingleOrNull();
    final location = _remoteLocationColumns(snapshot.location);
    if (stored == null ||
        stored.occurredAtUtc.toUtc() != snapshot.occurredAtUtc.toUtc() ||
        stored.occurredTimeZone != snapshot.occurredTimeZone ||
        stored.channel != snapshot.channel.storageValue ||
        stored.channelDetail != snapshot.channelDetail ||
        stored.locationKind != location.kind ||
        stored.placeName != location.placeName ||
        stored.smallestRegionId != location.smallestRegionId ||
        stored.regionTreeVersion != location.regionTreeVersion ||
        stored.latitude != location.latitude ||
        stored.longitude != location.longitude ||
        stored.locationAccuracyMeters != location.accuracyMeters ||
        stored.reachCount != snapshot.reachCount ||
        stored.interestLevel != snapshot.interestLevel) {
      return false;
    }
    final answers =
        await (_database.select(_database.dbContactAnswers)..where(
              (row) =>
                  row.contactId.equals(contactId) &
                  row.revisionNumber.equals(revisionNumber),
            ))
            .get();
    if (answers.length != snapshot.answers.length) {
      return false;
    }
    final expected = {
      for (final answer in snapshot.answers) answer.questionId: answer,
    };
    final answersMatch = answers.every((answer) {
      final value = expected[answer.questionId];
      return value != null && _storedContactAnswerMatches(answer, value);
    });
    return answersMatch &&
        await _contactTargetLinksMatchRemote(
          contactId,
          revisionNumber,
          snapshot.targetLinks,
        );
  }

  Map<String, Object?> _conflictSnapshotPayload(
    ContactConflictSnapshot snapshot,
  ) {
    final location = _remoteLocationColumns(snapshot.location);
    return {
      'occurredAtUtc': snapshot.occurredAtUtc.toUtc().toIso8601String(),
      'occurredTimeZone': snapshot.occurredTimeZone,
      'channel': snapshot.channel.storageValue,
      'channelDetail': snapshot.channelDetail,
      'location': {
        'kind': location.kind,
        'placeName': location.placeName,
        'smallestRegionId': location.smallestRegionId,
        'regionTreeVersion': location.regionTreeVersion,
        'latitude': location.latitude,
        'longitude': location.longitude,
        'accuracyMeters': location.accuracyMeters,
      },
      'reachCount': snapshot.reachCount,
      'interestLevel': snapshot.interestLevel,
      'answers': [
        for (final answer in snapshot.answers)
          {
            'questionId': answer.questionId,
            'state': answer.state.storageValue,
            'type': answer.type.storageValue,
            'value': answer.state == QuestionnaireAnswerState.answered
                ? answer.value
                : null,
          },
      ],
      'targetLinks': [
        for (final link in snapshot.targetLinks)
          {
            'targetId': link.targetId,
            'targetType': link.targetType.storageValue,
            'responseLevel': link.responseLevel,
            'followUpConsent': link.followUpConsent.storageValue,
            'institutionRepresentativeConfirmed':
                link.institutionRepresentativeConfirmed,
            'confirmStageZero': link.confirmStageZero,
          },
      ],
    };
  }

  Future<SyncDrainResult> _retryCommand(
    DbSyncOutboxData current,
    SyncPushRetryable retryable,
    DateTime nowUtc,
  ) async {
    final delay = _retryDelay(current.attemptCount, retryable.retryAfter);
    await (_database.update(
      _database.dbSyncOutbox,
    )..where((row) => row.commandId.equals(current.commandId))).write(
      DbSyncOutboxCompanion(
        status: const Value('pending'),
        nextAttemptAtUtc: Value(nowUtc.add(delay)),
        leaseOwner: const Value(null),
        leaseExpiresAtUtc: const Value(null),
        lastFailureCode: Value(_failureCode(retryable.failureCode)),
      ),
    );
    await _writeScopeState(
      nowUtc: nowUtc,
      lastFailureCode: _failureCode(retryable.failureCode),
    );
    return SyncDrainResult.retryScheduled;
  }

  Future<SyncDrainResult> _stopCommand(
    DbSyncOutboxData current, {
    required String status,
    required String failureCode,
    required DateTime nowUtc,
    required SyncDrainResult outcome,
  }) async {
    final stableCode = _failureCode(failureCode);
    await (_database.update(
      _database.dbSyncOutbox,
    )..where((row) => row.commandId.equals(current.commandId))).write(
      DbSyncOutboxCompanion(
        status: Value(status),
        leaseOwner: const Value(null),
        leaseExpiresAtUtc: const Value(null),
        lastFailureCode: Value(stableCode),
      ),
    );
    await _writeScopeState(nowUtc: nowUtc, lastFailureCode: stableCode);
    return outcome;
  }

  Future<void> _writeScopeState({
    required DateTime nowUtc,
    String? serverCursor,
    DateTime? lastSuccessAtUtc,
    String? lastFailureCode,
  }) async {
    final query = _database.select(_database.dbSyncScopes)
      ..where(
        (row) =>
            row.appUserId.equals(_scope.appUserId) &
            row.workspaceId.equals(_scope.workspaceId) &
            row.projectId.equals(_scope.projectId),
      );
    final existing = await query.getSingleOrNull();
    await _database
        .into(_database.dbSyncScopes)
        .insertOnConflictUpdate(
          DbSyncScopesCompanion.insert(
            appUserId: _scope.appUserId,
            workspaceId: _scope.workspaceId,
            projectId: _scope.projectId,
            serverCursor: Value(serverCursor ?? existing?.serverCursor),
            lastSuccessAtUtc: Value(
              lastSuccessAtUtc ?? existing?.lastSuccessAtUtc,
            ),
            lastFailureCode: Value(lastFailureCode),
            updatedAtUtc: nowUtc,
          ),
        );
  }

  Future<void> _releaseDrainerLease() async {
    await (_database.delete(_database.dbSyncDrainerLeases)..where(
          (row) =>
              row.leaseName.equals(_drainerLeaseName) &
              row.leaseOwner.equals(_workerId),
        ))
        .go();
  }

  Duration _retryDelay(int attemptCount, Duration? retryAfter) {
    final exponent = min(max(attemptCount - 1, 0), 8);
    final baseSeconds = min(2 * pow(2, exponent).toInt(), 300);
    final jitterValue = _jitter.nextUnitInterval().clamp(0, 0.999999);
    final jitteredMicroseconds =
        Duration(seconds: baseSeconds).inMicroseconds *
        (1 + (jitterValue * 0.25));
    var delay = Duration(microseconds: jitteredMicroseconds.round());
    if (delay > _maximumRetryDelay) {
      delay = _maximumRetryDelay;
    }
    if (retryAfter != null && retryAfter > delay) {
      delay = retryAfter > _maximumRetryAfter ? _maximumRetryAfter : retryAfter;
    }
    return delay;
  }

  String _failureCode(String value) {
    final trimmed = value.trim();
    return _stableFailureCode.hasMatch(trimmed)
        ? trimmed
        : 'unknown_sync_failure';
  }

  _ParsedRemoteChange _parseRemoteChange(SyncRemoteChange change) {
    return switch (change.changeType) {
      'contact.submitted' => _parseRemoteContact(change),
      'contact.revised' ||
      'contact.voided' => _parseRemoteContactRevision(change),
      'contact.attempt.submitted' => _parseRemoteContactAttempt(change),
      'draft.upserted' => _parseRemoteDraftUpsert(change),
      'draft.deleted' => _parseRemoteDraftDelete(change),
      _ => throw const FormatException('unsupported remote change'),
    };
  }

  _RemoteContact _parseRemoteContact(SyncRemoteChange change) {
    if (change.changeType != 'contact.submitted' ||
        change.revisionNumber != 1) {
      throw const FormatException('unsupported remote change');
    }
    final payload = change.payload;
    final workspaceId = _requiredString(payload['workspaceId']);
    final projectId = _requiredString(payload['projectId']);
    if (workspaceId != _scope.workspaceId || projectId != _scope.projectId) {
      throw const FormatException('remote change scope mismatch');
    }
    final occurredAtUtc = _utcDate(payload['occurredAtUtc']);
    final firstSubmittedAtUtc = _utcDate(payload['firstSubmittedAtUtc']);
    final channel = _remoteChannel(_requiredString(payload['channel']));
    final channelDetail = _optionalString(payload['channelDetail']);
    if (channel == ContactChannel.otherDirect && channelDetail == null) {
      throw const FormatException('remote channel detail is required');
    }
    final location = _remoteLocation(payload['location']);
    if (channel == ContactChannel.faceToFace &&
        location is NotApplicableContactLocation) {
      throw const FormatException('invalid remote contact location');
    }
    final reachCount = _integer(payload['reachCount']);
    final interestLevel = _integer(payload['interestLevel']);
    if (reachCount < 1 || interestLevel < 0 || interestLevel > 4) {
      throw const FormatException('invalid remote contact metric');
    }
    final answerValues = payload['answers'];
    if (answerValues is! List<Object?>) {
      throw const FormatException('remote answers must be a list');
    }
    final answers = [for (final value in answerValues) _remoteAnswer(value)];
    if (answers.map((answer) => answer.questionId).toSet().length !=
        answers.length) {
      throw const FormatException('remote answers contain duplicate IDs');
    }
    final targetLinks = _remoteTargetLinks(payload['targetLinks']);
    return _RemoteContact(
      contactId: _requiredString(payload['contactId']),
      questionnaireVersionId: _requiredString(
        payload['questionnaireVersionId'],
      ),
      occurredAtUtc: occurredAtUtc,
      occurredTimeZone: _requiredString(payload['occurredTimeZone']),
      firstSubmittedAtUtc: firstSubmittedAtUtc,
      channel: channel,
      channelDetail: channelDetail,
      location: location,
      reachCount: reachCount,
      interestLevel: interestLevel,
      answers: answers,
      targetLinks: targetLinks,
      sourceAttemptId: _optionalString(payload['sourceAttemptId']),
    );
  }

  _RemoteContactRevision _parseRemoteContactRevision(SyncRemoteChange change) {
    if (change.revisionNumber < 2) {
      throw const FormatException('invalid remote contact revision');
    }
    final payload = change.payload;
    _requireRemoteScope(payload);
    final kind = switch (_requiredString(payload['revisionKind'])) {
      'corrected' => ContactRevisionKind.corrected,
      'voided' => ContactRevisionKind.voided,
      _ => throw const FormatException('invalid remote revision kind'),
    };
    if ((change.changeType == 'contact.revised' &&
            kind != ContactRevisionKind.corrected) ||
        (change.changeType == 'contact.voided' &&
            kind != ContactRevisionKind.voided)) {
      throw const FormatException('remote revision kind mismatch');
    }
    final channel = _remoteChannel(_requiredString(payload['channel']));
    final channelDetail = _optionalString(payload['channelDetail']);
    if (channel == ContactChannel.otherDirect && channelDetail == null) {
      throw const FormatException('remote channel detail is required');
    }
    final location = _remoteLocation(payload['location']);
    if (channel == ContactChannel.faceToFace &&
        location is NotApplicableContactLocation) {
      throw const FormatException('invalid remote contact location');
    }
    final reachCount = _integer(payload['reachCount']);
    final interestLevel = _integer(payload['interestLevel']);
    if (reachCount < 1 || interestLevel < 0 || interestLevel > 4) {
      throw const FormatException('invalid remote contact metric');
    }
    final answerValues = payload['answers'];
    if (answerValues is! List<Object?>) {
      throw const FormatException('remote answers must be a list');
    }
    final answers = [for (final value in answerValues) _remoteAnswer(value)];
    if (answers.map((answer) => answer.questionId).toSet().length !=
        answers.length) {
      throw const FormatException('remote answers contain duplicate IDs');
    }
    final targetLinks = _remoteTargetLinks(payload['targetLinks']);
    return _RemoteContactRevision(
      contactId: _requiredString(payload['contactId']),
      revisionNumber: change.revisionNumber,
      kind: kind,
      questionnaireVersionId: _requiredString(
        payload['questionnaireVersionId'],
      ),
      revisedAtUtc: _utcDate(payload['revisedAtUtc']),
      reason: _requiredString(payload['reason']),
      occurredAtUtc: _utcDate(payload['occurredAtUtc']),
      occurredTimeZone: _requiredString(payload['occurredTimeZone']),
      firstSubmittedAtUtc: _utcDate(payload['firstSubmittedAtUtc']),
      channel: channel,
      channelDetail: channelDetail,
      location: location,
      reachCount: reachCount,
      interestLevel: interestLevel,
      answers: answers,
      targetLinks: targetLinks,
    );
  }

  _RemoteContactAttempt _parseRemoteContactAttempt(SyncRemoteChange change) {
    if (change.changeType != 'contact.attempt.submitted' ||
        change.revisionNumber != 1) {
      throw const FormatException('unsupported remote contact attempt');
    }
    final payload = change.payload;
    _requireRemoteScope(payload);
    final channel = _remoteChannel(_requiredString(payload['channel']));
    final channelDetail = _optionalString(payload['channelDetail']);
    if (channel == ContactChannel.otherDirect && channelDetail == null) {
      throw const FormatException('remote channel detail is required');
    }
    return _RemoteContactAttempt(
      attemptId: _requiredString(payload['attemptId']),
      occurredAtUtc: _utcDate(payload['occurredAtUtc']),
      occurredTimeZone: _requiredString(payload['occurredTimeZone']),
      firstSubmittedAtUtc: _utcDate(payload['firstSubmittedAtUtc']),
      channel: channel,
      channelDetail: channelDetail,
      linkedContactId: _optionalString(payload['linkedContactId']),
    );
  }

  _RemoteDraftUpsert _parseRemoteDraftUpsert(SyncRemoteChange change) {
    if (change.revisionNumber < 1) {
      throw const FormatException('invalid remote draft revision');
    }
    final payload = change.payload;
    _requireRemoteScope(payload);
    final serverRevision = _integer(payload['serverRevision']);
    if (serverRevision != change.revisionNumber) {
      throw const FormatException('remote draft revision mismatch');
    }
    final occurredAtUtc = _optionalUtcDate(payload['occurredAtUtc']);
    final occurredTimeZone = _optionalString(payload['occurredTimeZone']);
    if ((occurredAtUtc == null) != (occurredTimeZone == null)) {
      throw const FormatException('remote draft occurrence is incomplete');
    }
    final channelValue = payload['channel'];
    final channel = channelValue == null
        ? null
        : _remoteChannel(_requiredString(channelValue));
    final channelDetail = _optionalString(payload['channelDetail']);
    final locationValue = payload['location'];
    final location = locationValue == null
        ? null
        : _remoteLocation(locationValue);
    final reachCount = _optionalInteger(payload['reachCount']);
    final interestLevel = _optionalInteger(payload['interestLevel']);
    if ((reachCount != null && reachCount < 1) ||
        (interestLevel != null && (interestLevel < 0 || interestLevel > 4))) {
      throw const FormatException('invalid remote draft metric');
    }
    final answerValues = payload['answers'];
    if (answerValues is! List<Object?>) {
      throw const FormatException('remote answers must be a list');
    }
    final answers = [for (final value in answerValues) _remoteAnswer(value)];
    if (answers.map((answer) => answer.questionId).toSet().length !=
        answers.length) {
      throw const FormatException('remote answers contain duplicate IDs');
    }
    final targetLinks = _remoteTargetLinks(payload['targetLinks']);
    final draftId = _requiredString(payload['draftId']);
    final upgradedFromDraftId = _optionalString(payload['upgradedFromDraftId']);
    if (upgradedFromDraftId == draftId) {
      throw const FormatException('remote draft upgrade source is invalid');
    }
    return _RemoteDraftUpsert(
      draftId: draftId,
      questionnaireVersionId: _requiredString(
        payload['questionnaireVersionId'],
      ),
      createdAtUtc: _utcDate(payload['createdAtUtc']),
      updatedAtUtc: _utcDate(payload['updatedAtUtc']),
      occurredAtUtc: occurredAtUtc,
      occurredTimeZone: occurredTimeZone,
      channel: channel,
      channelDetail: channelDetail,
      location: location,
      reachCount: reachCount,
      interestLevel: interestLevel,
      answers: answers,
      targetLinks: targetLinks,
      serverRevision: serverRevision,
      sourceDeviceId: _requiredString(payload['sourceDeviceId']),
      sourceAttemptId: _optionalString(payload['sourceAttemptId']),
      upgradedFromDraftId: upgradedFromDraftId,
    );
  }

  _RemoteDraftDelete _parseRemoteDraftDelete(SyncRemoteChange change) {
    if (change.revisionNumber < 1) {
      throw const FormatException('invalid remote draft revision');
    }
    final payload = change.payload;
    _requireRemoteScope(payload);
    if (_integer(payload['serverRevision']) != change.revisionNumber) {
      throw const FormatException('remote draft revision mismatch');
    }
    return _RemoteDraftDelete(
      draftId: _requiredString(payload['draftId']),
      serverRevision: change.revisionNumber,
    );
  }

  void _requireRemoteScope(Map<String, Object?> payload) {
    if (_requiredString(payload['workspaceId']) != _scope.workspaceId ||
        _requiredString(payload['projectId']) != _scope.projectId) {
      throw const FormatException('remote change scope mismatch');
    }
  }

  Future<void> _applyRemoteContact(_RemoteContact contact) async {
    final existingQuery = _database.select(_database.dbContactRecords)
      ..where((row) => row.contactId.equals(contact.contactId));
    final existing = await existingQuery.getSingleOrNull();
    if (existing != null) {
      if (await _existingContactMatchesRemote(existing, contact)) {
        await _linkRemoteSourceAttempt(contact);
        return;
      }
      throw const FormatException('remote contact conflicts with local fact');
    }
    final location = _remoteLocationColumns(contact.location);
    if (contact.location case final ResolvedContactLocation resolved) {
      await _regionCatalog.requireAnalyzableRegion(
        regionId: resolved.smallestRegionId,
        treeVersion: resolved.regionTreeVersion,
      );
    }
    await _database
        .into(_database.dbContactRecords)
        .insert(
          DbContactRecordsCompanion.insert(
            contactId: contact.contactId,
            appUserId: _scope.appUserId,
            workspaceId: _scope.workspaceId,
            projectId: _scope.projectId,
            questionnaireVersionId: contact.questionnaireVersionId,
            occurredAtUtc: contact.occurredAtUtc,
            occurredTimeZone: contact.occurredTimeZone,
            firstSubmittedAtUtc: contact.firstSubmittedAtUtc,
            channel: contact.channel.storageValue,
            channelDetail: Value(contact.channelDetail),
            locationKind: location.kind,
            placeName: Value(location.placeName),
            smallestRegionId: Value(location.smallestRegionId),
            regionTreeVersion: Value(location.regionTreeVersion),
            latitude: Value(location.latitude),
            longitude: Value(location.longitude),
            locationAccuracyMeters: Value(location.accuracyMeters),
            reachCount: contact.reachCount,
            interestLevel: contact.interestLevel,
            currentRevision: 1,
            lifecycleStatus: 'active',
          ),
        );
    if (contact.location case final ResolvedContactLocation resolved) {
      await _regionCatalog.assignContact(
        contactId: contact.contactId,
        regionId: resolved.smallestRegionId,
        treeVersion: resolved.regionTreeVersion,
      );
    }
    await _database
        .into(_database.dbContactRevisions)
        .insert(
          DbContactRevisionsCompanion.insert(
            revisionId: '${contact.contactId}:remote:1',
            contactId: contact.contactId,
            revisionNumber: 1,
            revisionKind: Value(ContactRevisionKind.submitted.storageValue),
            revisedByAppUserId: _scope.appUserId,
            revisedAtUtc: contact.firstSubmittedAtUtc,
            occurredAtUtc: contact.occurredAtUtc,
            occurredTimeZone: contact.occurredTimeZone,
            channel: contact.channel.storageValue,
            channelDetail: Value(contact.channelDetail),
            locationKind: location.kind,
            placeName: Value(location.placeName),
            smallestRegionId: Value(location.smallestRegionId),
            regionTreeVersion: Value(location.regionTreeVersion),
            latitude: Value(location.latitude),
            longitude: Value(location.longitude),
            locationAccuracyMeters: Value(location.accuracyMeters),
            reachCount: contact.reachCount,
            interestLevel: contact.interestLevel,
          ),
        );
    for (final answer in contact.answers) {
      await _insertContactAnswer(
        contactId: contact.contactId,
        revisionNumber: 1,
        answer: answer,
      );
    }
    await _insertRemoteContactTargetLinks(
      contactId: contact.contactId,
      revisionNumber: 1,
      targetLinks: contact.targetLinks,
    );
    await _linkRemoteSourceAttempt(contact);
  }

  Future<void> _applyRemoteContactRevision(
    _RemoteContactRevision revision,
  ) async {
    final query = _database.select(_database.dbContactRecords)
      ..where((row) => row.contactId.equals(revision.contactId));
    final existing = await query.getSingleOrNull();
    if (existing == null ||
        existing.appUserId != _scope.appUserId ||
        existing.workspaceId != _scope.workspaceId ||
        existing.projectId != _scope.projectId ||
        existing.questionnaireVersionId != revision.questionnaireVersionId) {
      throw const FormatException('remote revision contact is unavailable');
    }

    var replacingAcknowledgedOptimisticRevision = false;
    if (existing.currentRevision >= revision.revisionNumber) {
      if (await _existingRevisionMatchesRemote(revision)) {
        if (existing.currentRevision == revision.revisionNumber &&
            !_currentProjectionMatchesRevision(existing, revision)) {
          throw const FormatException(
            'remote revision conflicts with local projection',
          );
        }
        return;
      }
      replacingAcknowledgedOptimisticRevision =
          existing.currentRevision == revision.revisionNumber &&
          await _isAcknowledgedOptimisticRevision(revision);
      if (!replacingAcknowledgedOptimisticRevision) {
        throw const FormatException(
          'remote revision conflicts with local history',
        );
      }
      await (_database.delete(_database.dbContactAnswers)..where(
            (row) =>
                row.contactId.equals(revision.contactId) &
                row.revisionNumber.equals(revision.revisionNumber),
          ))
          .go();
      await (_database.delete(_database.dbContactTargetLinks)..where(
            (row) =>
                row.contactId.equals(revision.contactId) &
                row.revisionNumber.equals(revision.revisionNumber),
          ))
          .go();
      await (_database.delete(_database.dbContactRevisions)..where(
            (row) =>
                row.contactId.equals(revision.contactId) &
                row.revisionNumber.equals(revision.revisionNumber),
          ))
          .go();
    }
    if (!replacingAcknowledgedOptimisticRevision &&
        existing.currentRevision != revision.revisionNumber - 1) {
      throw const FormatException('remote revision sequence is not contiguous');
    }
    if (revision.kind == ContactRevisionKind.voided &&
        !_currentProjectionMatchesRevision(
          existing,
          revision,
          ignoreLifecycle: true,
        )) {
      throw const FormatException('remote void snapshot differs from current');
    }
    if (revision.location case final ResolvedContactLocation resolved) {
      await _regionCatalog.requireAnalyzableRegion(
        regionId: resolved.smallestRegionId,
        treeVersion: resolved.regionTreeVersion,
      );
    }

    final location = _remoteLocationColumns(revision.location);
    await _database
        .into(_database.dbContactRevisions)
        .insert(
          DbContactRevisionsCompanion.insert(
            revisionId:
                '${revision.contactId}:remote:${revision.revisionNumber}',
            contactId: revision.contactId,
            revisionNumber: revision.revisionNumber,
            revisionKind: Value(revision.kind.storageValue),
            revisedByAppUserId: _scope.appUserId,
            revisedAtUtc: revision.revisedAtUtc,
            reason: Value(revision.reason),
            occurredAtUtc: revision.occurredAtUtc,
            occurredTimeZone: revision.occurredTimeZone,
            channel: revision.channel.storageValue,
            channelDetail: Value(revision.channelDetail),
            locationKind: location.kind,
            placeName: Value(location.placeName),
            smallestRegionId: Value(location.smallestRegionId),
            regionTreeVersion: Value(location.regionTreeVersion),
            latitude: Value(location.latitude),
            longitude: Value(location.longitude),
            locationAccuracyMeters: Value(location.accuracyMeters),
            reachCount: revision.reachCount,
            interestLevel: revision.interestLevel,
          ),
        );
    for (final answer in revision.answers) {
      await _insertContactAnswer(
        contactId: revision.contactId,
        revisionNumber: revision.revisionNumber,
        answer: answer,
      );
    }
    await _insertRemoteContactTargetLinks(
      contactId: revision.contactId,
      revisionNumber: revision.revisionNumber,
      targetLinks: revision.targetLinks,
    );
    await (_database.update(
      _database.dbContactRecords,
    )..where((row) => row.contactId.equals(revision.contactId))).write(
      DbContactRecordsCompanion(
        occurredAtUtc: Value(revision.occurredAtUtc),
        occurredTimeZone: Value(revision.occurredTimeZone),
        channel: Value(revision.channel.storageValue),
        channelDetail: Value(revision.channelDetail),
        locationKind: Value(location.kind),
        placeName: Value(location.placeName),
        smallestRegionId: Value(location.smallestRegionId),
        regionTreeVersion: Value(location.regionTreeVersion),
        latitude: Value(location.latitude),
        longitude: Value(location.longitude),
        locationAccuracyMeters: Value(location.accuracyMeters),
        reachCount: Value(revision.reachCount),
        interestLevel: Value(revision.interestLevel),
        currentRevision: Value(revision.revisionNumber),
        lifecycleStatus: Value(
          revision.kind == ContactRevisionKind.voided ? 'voided' : 'active',
        ),
      ),
    );
    if (revision.location case final ResolvedContactLocation resolved) {
      await _regionCatalog.assignContact(
        contactId: revision.contactId,
        regionId: resolved.smallestRegionId,
        treeVersion: resolved.regionTreeVersion,
      );
    } else {
      await _regionCatalog.clearContactAssignment(revision.contactId);
    }
  }

  /// 上传已被服务器确认后，pull 是本机乐观 revision 的权威对账。
  ///
  /// 普通更正的服务器审计时间与设备时间可能不同。自动合并时，拉取到的
  /// 同编号 revision 甚至可能是另一台设备的先行更正。只有同范围的
  /// revise、void 或 resolve command 已经 ACK，且 base 紧邻该 revision 时，
  /// 才允许服务器历史替换这条乐观记录。
  Future<bool> _isAcknowledgedOptimisticRevision(
    _RemoteContactRevision revision,
  ) async {
    final query = _database.select(_database.dbSyncOutbox)
      ..where(
        (row) =>
            row.aggregateId.equals(revision.contactId) &
            row.appUserId.equals(_scope.appUserId) &
            row.workspaceId.equals(_scope.workspaceId) &
            row.projectId.equals(_scope.projectId) &
            row.baseRevision.equals(revision.revisionNumber - 1) &
            row.status.equals('completed') &
            (revision.kind == ContactRevisionKind.voided
                ? row.commandType.equals('contact.void.v1')
                : (row.commandType.equals('contact.revise.v1') |
                      row.commandType.equals('contact.resolve.v1'))),
      )
      ..limit(1);
    return await query.getSingleOrNull() != null;
  }

  Future<void> _applyRemoteContactAttempt(_RemoteContactAttempt attempt) async {
    final query = _database.select(_database.dbContactAttempts)
      ..where((row) => row.attemptId.equals(attempt.attemptId));
    final existing = await query.getSingleOrNull();
    if (existing != null) {
      if (existing.appUserId == _scope.appUserId &&
          existing.workspaceId == _scope.workspaceId &&
          existing.projectId == _scope.projectId &&
          existing.occurredAtUtc.toUtc() == attempt.occurredAtUtc &&
          existing.occurredTimeZone == attempt.occurredTimeZone &&
          existing.channel == attempt.channel.storageValue &&
          existing.channelDetail == attempt.channelDetail &&
          existing.linkedContactId == attempt.linkedContactId) {
        return;
      }
      throw const FormatException(
        'remote contact attempt conflicts with local',
      );
    }
    await _database
        .into(_database.dbContactAttempts)
        .insert(
          DbContactAttemptsCompanion.insert(
            attemptId: attempt.attemptId,
            appUserId: _scope.appUserId,
            workspaceId: _scope.workspaceId,
            projectId: _scope.projectId,
            occurredAtUtc: attempt.occurredAtUtc,
            occurredTimeZone: attempt.occurredTimeZone,
            firstSubmittedAtUtc: attempt.firstSubmittedAtUtc,
            channel: attempt.channel.storageValue,
            channelDetail: Value(attempt.channelDetail),
            linkedContactId: Value(attempt.linkedContactId),
          ),
        );
  }

  Future<void> _linkRemoteSourceAttempt(_RemoteContact contact) async {
    final attemptId = contact.sourceAttemptId;
    if (attemptId == null) {
      return;
    }
    final changed =
        await (_database.update(_database.dbContactAttempts)..where(
              (row) =>
                  row.attemptId.equals(attemptId) &
                  row.appUserId.equals(_scope.appUserId) &
                  row.workspaceId.equals(_scope.workspaceId) &
                  row.projectId.equals(_scope.projectId) &
                  (row.linkedContactId.isNull() |
                      row.linkedContactId.equals(contact.contactId)),
            ))
            .write(
              DbContactAttemptsCompanion(
                linkedContactId: Value(contact.contactId),
              ),
            );
    if (changed != 1) {
      throw const FormatException('remote source attempt is unavailable');
    }
  }

  Future<void> _applyRemoteDraftUpsert(_RemoteDraftUpsert draft) async {
    if (draft.updatedAtUtc.isBefore(draft.createdAtUtc)) {
      throw const FormatException('remote draft time order is invalid');
    }
    if (draft.location case final ResolvedContactLocation resolved) {
      await _regionCatalog.requireAnalyzableRegion(
        regionId: resolved.smallestRegionId,
        treeVersion: resolved.regionTreeVersion,
      );
    }
    final query = _database.select(_database.dbContactDrafts)
      ..where(
        (row) =>
            row.draftId.equals(draft.draftId) &
            row.appUserId.equals(_scope.appUserId),
      );
    final existing = await query.getSingleOrNull();
    if (existing == null) {
      await _writeRemoteDraft(draft);
      return;
    }
    if (draft.serverRevision < existing.serverRevision) {
      return;
    }
    if (await _existingDraftMatchesRemote(existing, draft)) {
      await (_database.update(
        _database.dbContactDrafts,
      )..where((row) => row.draftId.equals(draft.draftId))).write(
        DbContactDraftsCompanion(serverRevision: Value(draft.serverRevision)),
      );
      await _completePendingDraftCommands(draft.draftId);
      return;
    }
    final hasPendingChanges = await _draftHasPendingChanges(draft.draftId);
    if (draft.serverRevision == existing.serverRevision && hasPendingChanges) {
      // push 与 pull 使用独立 cursor。本机可能已经确认这个 server revision，
      // 又在它之上继续编辑；迟到的 feed 快照只是 base，不是并发分叉。
      return;
    }
    if (draft.serverRevision == existing.serverRevision) {
      throw const FormatException('stale remote draft conflicts with local');
    }
    if (hasPendingChanges) {
      await _preserveLocalDraftAsConflict(existing);
    } else {
      await _deleteDraftRows(draft.draftId);
    }
    await _writeRemoteDraft(draft);
  }

  Future<void> _applyRemoteDraftDelete(_RemoteDraftDelete draft) async {
    final query = _database.select(_database.dbContactDrafts)
      ..where(
        (row) =>
            row.draftId.equals(draft.draftId) &
            row.appUserId.equals(_scope.appUserId),
      );
    final existing = await query.getSingleOrNull();
    if (existing == null) {
      return;
    }
    if (existing.syncMode == ContactDraftSyncMode.deviceOnly.storageValue) {
      if (draft.serverRevision > existing.serverRevision) {
        await (_database.update(
          _database.dbContactDrafts,
        )..where((row) => row.draftId.equals(draft.draftId))).write(
          DbContactDraftsCompanion(serverRevision: Value(draft.serverRevision)),
        );
      }
      return;
    }
    if (draft.serverRevision <= existing.serverRevision &&
        !await _draftHasPendingChanges(draft.draftId)) {
      return;
    }
    if (await _draftHasPendingChanges(draft.draftId)) {
      await _preserveLocalDraftAsConflict(existing);
      return;
    }
    await _deleteDraftRows(draft.draftId);
  }

  Future<void> _writeRemoteDraft(_RemoteDraftUpsert draft) async {
    final location = _optionalRemoteLocationColumns(draft.location);
    await _database
        .into(_database.dbContactDrafts)
        .insert(
          DbContactDraftsCompanion.insert(
            draftId: draft.draftId,
            appUserId: _scope.appUserId,
            workspaceId: _scope.workspaceId,
            projectId: _scope.projectId,
            questionnaireVersionId: draft.questionnaireVersionId,
            createdAtUtc: draft.createdAtUtc,
            updatedAtUtc: draft.updatedAtUtc,
            occurredAtUtc: Value(draft.occurredAtUtc),
            occurredTimeZone: Value(draft.occurredTimeZone),
            channel: Value(draft.channel?.storageValue),
            channelDetail: Value(draft.channelDetail),
            locationKind: Value(location.kind),
            placeName: Value(location.placeName),
            smallestRegionId: Value(location.smallestRegionId),
            regionTreeVersion: Value(location.regionTreeVersion),
            latitude: Value(location.latitude),
            longitude: Value(location.longitude),
            locationAccuracyMeters: Value(location.accuracyMeters),
            reachCount: Value(draft.reachCount),
            interestLevel: Value(draft.interestLevel),
            syncMode: const Value('account_private'),
            localRevision: Value(draft.serverRevision),
            serverRevision: Value(draft.serverRevision),
            sourceAttemptId: Value(draft.sourceAttemptId),
            upgradedFromDraftId: Value(draft.upgradedFromDraftId),
          ),
        );
    for (final answer in draft.answers) {
      await _insertDraftAnswer(draftId: draft.draftId, answer: answer);
    }
    await _insertRemoteDraftTargetLinks(draft.draftId, draft.targetLinks);
    if (draft.location case final ResolvedContactLocation resolved) {
      await _regionCatalog.assignDraft(
        draftId: draft.draftId,
        regionId: resolved.smallestRegionId,
        treeVersion: resolved.regionTreeVersion,
      );
    }
  }

  Future<bool> _existingDraftMatchesRemote(
    DbContactDraft existing,
    _RemoteDraftUpsert draft,
  ) async {
    final location = _optionalRemoteLocationColumns(draft.location);
    if (existing.workspaceId != _scope.workspaceId ||
        existing.projectId != _scope.projectId ||
        existing.questionnaireVersionId != draft.questionnaireVersionId ||
        existing.createdAtUtc.toUtc() != draft.createdAtUtc ||
        existing.updatedAtUtc.toUtc() != draft.updatedAtUtc ||
        existing.occurredAtUtc?.toUtc() != draft.occurredAtUtc ||
        existing.occurredTimeZone != draft.occurredTimeZone ||
        existing.channel != draft.channel?.storageValue ||
        existing.channelDetail != draft.channelDetail ||
        existing.locationKind != location.kind ||
        existing.placeName != location.placeName ||
        existing.smallestRegionId != location.smallestRegionId ||
        existing.regionTreeVersion != location.regionTreeVersion ||
        existing.latitude != location.latitude ||
        existing.longitude != location.longitude ||
        existing.locationAccuracyMeters != location.accuracyMeters ||
        existing.reachCount != draft.reachCount ||
        existing.interestLevel != draft.interestLevel ||
        existing.sourceAttemptId != draft.sourceAttemptId ||
        existing.upgradedFromDraftId != draft.upgradedFromDraftId ||
        existing.abandonedAtUtc != null) {
      return false;
    }
    final stored = await (_database.select(
      _database.dbContactDraftAnswers,
    )..where((row) => row.draftId.equals(draft.draftId))).get();
    if (stored.length != draft.answers.length) {
      return false;
    }
    final remoteById = {
      for (final answer in draft.answers) answer.questionId: answer,
    };
    final answersMatch = stored.every((answer) {
      final remote = remoteById[answer.questionId];
      return remote != null && _storedDraftAnswerMatches(answer, remote);
    });
    return answersMatch && await _draftTargetLinksMatchRemote(draft);
  }

  Future<bool> _draftHasPendingChanges(String draftId) async {
    final query = _database.select(_database.dbSyncOutbox)
      ..where(
        (row) =>
            row.aggregateId.equals(draftId) &
            row.commandType.equals('draft.upsert.v1') &
            row.status.isNotValue('completed'),
      );
    return (await query.get()).isNotEmpty;
  }

  Future<void> _preserveLocalDraftAsConflict(DbContactDraft existing) async {
    final conflictId =
        '${existing.draftId}:conflict:'
        '$_workerId:${existing.localRevision}';
    final answers = await (_database.select(
      _database.dbContactDraftAnswers,
    )..where((row) => row.draftId.equals(existing.draftId))).get();
    final targetLinks = await (_database.select(
      _database.dbContactDraftTargetLinks,
    )..where((row) => row.draftId.equals(existing.draftId))).get();
    final assignment = await (_database.select(
      _database.dbDraftRegionAssignments,
    )..where((row) => row.draftId.equals(existing.draftId))).getSingleOrNull();
    await _database
        .into(_database.dbContactDrafts)
        .insert(
          DbContactDraftsCompanion.insert(
            draftId: conflictId,
            appUserId: existing.appUserId,
            workspaceId: existing.workspaceId,
            projectId: existing.projectId,
            questionnaireVersionId: existing.questionnaireVersionId,
            createdAtUtc: existing.createdAtUtc,
            updatedAtUtc: existing.updatedAtUtc,
            occurredAtUtc: Value(existing.occurredAtUtc),
            occurredTimeZone: Value(existing.occurredTimeZone),
            channel: Value(existing.channel),
            channelDetail: Value(existing.channelDetail),
            locationKind: Value(existing.locationKind),
            placeName: Value(existing.placeName),
            smallestRegionId: Value(existing.smallestRegionId),
            regionTreeVersion: Value(existing.regionTreeVersion),
            latitude: Value(existing.latitude),
            longitude: Value(existing.longitude),
            locationAccuracyMeters: Value(existing.locationAccuracyMeters),
            reachCount: Value(existing.reachCount),
            interestLevel: Value(existing.interestLevel),
            syncMode: const Value('device_only'),
            localRevision: Value(existing.localRevision),
            serverRevision: const Value(0),
            conflictOfDraftId: Value(existing.draftId),
            sourceAttemptId: Value(existing.sourceAttemptId),
            upgradedFromDraftId: Value(existing.upgradedFromDraftId),
          ),
        );
    for (final answer in answers) {
      await _database
          .into(_database.dbContactDraftAnswers)
          .insert(
            DbContactDraftAnswersCompanion.insert(
              draftId: conflictId,
              questionId: answer.questionId,
              answerState: answer.answerState,
              answerType: answer.answerType,
              booleanValue: Value(answer.booleanValue),
              textValue: Value(answer.textValue),
              numberValue: Value(answer.numberValue),
              multiChoiceValueJson: Value(answer.multiChoiceValueJson),
            ),
          );
    }
    for (final link in targetLinks) {
      await _database
          .into(_database.dbContactDraftTargetLinks)
          .insert(
            DbContactDraftTargetLinksCompanion.insert(
              draftId: conflictId,
              targetId: link.targetId,
              targetType: link.targetType,
              responseLevel: Value(link.responseLevel),
              followUpConsent: link.followUpConsent,
              institutionRepresentativeConfirmed:
                  link.institutionRepresentativeConfirmed,
              confirmStageZero: link.confirmStageZero,
            ),
          );
    }
    if (assignment != null) {
      await _database
          .into(_database.dbDraftRegionAssignments)
          .insert(
            DbDraftRegionAssignmentsCompanion.insert(
              draftId: conflictId,
              regionVersionKey: assignment.regionVersionKey,
            ),
          );
    }
    await (_database.update(_database.dbSyncOutbox)..where(
          (row) =>
              row.aggregateId.equals(existing.draftId) &
              row.commandType.equals('draft.upsert.v1') &
              row.status.isNotValue('completed'),
        ))
        .write(
          const DbSyncOutboxCompanion(
            status: Value('needs_resolution'),
            lastFailureCode: Value('draft_conflict_preserved'),
            leaseOwner: Value(null),
            leaseExpiresAtUtc: Value(null),
          ),
        );
    await _deleteDraftRows(existing.draftId);
  }

  Future<void> _completePendingDraftCommands(String draftId) async {
    final nowUtc = _clock.now().toUtc();
    await (_database.update(_database.dbSyncOutbox)..where(
          (row) =>
              row.aggregateId.equals(draftId) &
              row.commandType.equals('draft.upsert.v1') &
              row.status.isNotValue('completed'),
        ))
        .write(
          DbSyncOutboxCompanion(
            status: const Value('completed'),
            lastFailureCode: const Value(null),
            leaseOwner: const Value(null),
            leaseExpiresAtUtc: const Value(null),
            completedAtUtc: Value(nowUtc),
          ),
        );
  }

  Future<void> _deleteDraftRows(String draftId) async {
    await _regionCatalog.clearDraftAssignment(draftId);
    await (_database.delete(
      _database.dbContactDraftAnswers,
    )..where((row) => row.draftId.equals(draftId))).go();
    await (_database.delete(
      _database.dbContactDraftTargetLinks,
    )..where((row) => row.draftId.equals(draftId))).go();
    await (_database.delete(
      _database.dbContactDrafts,
    )..where((row) => row.draftId.equals(draftId))).go();
  }

  /// 只有整个 revision 1 快照相同才是幂等重放。
  ///
  /// 只比较 ID、范围和 revision 会掩盖极小概率的 ID 碰撞，
  /// 也会掩盖服务端错误地返回了不同快照的问题。
  Future<bool> _existingContactMatchesRemote(
    DbContactRecord existing,
    _RemoteContact contact,
  ) async {
    final location = _remoteLocationColumns(contact.location);
    if (existing.appUserId != _scope.appUserId ||
        existing.workspaceId != _scope.workspaceId ||
        existing.projectId != _scope.projectId ||
        existing.questionnaireVersionId != contact.questionnaireVersionId) {
      return false;
    }

    final revisionQuery = _database.select(_database.dbContactRevisions)
      ..where(
        (row) =>
            row.contactId.equals(contact.contactId) &
            row.revisionNumber.equals(1),
      );
    final storedRevision = await revisionQuery.getSingleOrNull();
    if (storedRevision == null ||
        storedRevision.revisionKind !=
            ContactRevisionKind.submitted.storageValue ||
        storedRevision.reason != null ||
        storedRevision.occurredAtUtc.toUtc() != contact.occurredAtUtc ||
        storedRevision.occurredTimeZone != contact.occurredTimeZone ||
        storedRevision.channel != contact.channel.storageValue ||
        storedRevision.channelDetail != contact.channelDetail ||
        storedRevision.locationKind != location.kind ||
        storedRevision.placeName != location.placeName ||
        storedRevision.smallestRegionId != location.smallestRegionId ||
        storedRevision.regionTreeVersion != location.regionTreeVersion ||
        storedRevision.latitude != location.latitude ||
        storedRevision.longitude != location.longitude ||
        storedRevision.locationAccuracyMeters != location.accuracyMeters ||
        storedRevision.reachCount != contact.reachCount ||
        storedRevision.interestLevel != contact.interestLevel) {
      return false;
    }

    final answerQuery = _database.select(_database.dbContactAnswers)
      ..where(
        (row) =>
            row.contactId.equals(contact.contactId) &
            row.revisionNumber.equals(1),
      );
    final storedAnswers = await answerQuery.get();
    if (storedAnswers.length != contact.answers.length) {
      return false;
    }
    final remoteAnswers = {
      for (final answer in contact.answers) answer.questionId: answer,
    };
    final answersMatch = storedAnswers.every((stored) {
      final remote = remoteAnswers[stored.questionId];
      return remote != null && _storedContactAnswerMatches(stored, remote);
    });
    return answersMatch &&
        await _contactTargetLinksMatchRemote(
          contact.contactId,
          1,
          contact.targetLinks,
        );
  }

  Future<bool> _existingRevisionMatchesRemote(
    _RemoteContactRevision revision,
  ) async {
    final query = _database.select(_database.dbContactRevisions)
      ..where(
        (row) =>
            row.contactId.equals(revision.contactId) &
            row.revisionNumber.equals(revision.revisionNumber),
      );
    final stored = await query.getSingleOrNull();
    final location = _remoteLocationColumns(revision.location);
    if (stored == null ||
        stored.revisionKind != revision.kind.storageValue ||
        stored.reason != revision.reason ||
        stored.occurredAtUtc.toUtc() != revision.occurredAtUtc ||
        stored.occurredTimeZone != revision.occurredTimeZone ||
        stored.channel != revision.channel.storageValue ||
        stored.channelDetail != revision.channelDetail ||
        stored.locationKind != location.kind ||
        stored.placeName != location.placeName ||
        stored.smallestRegionId != location.smallestRegionId ||
        stored.regionTreeVersion != location.regionTreeVersion ||
        stored.latitude != location.latitude ||
        stored.longitude != location.longitude ||
        stored.locationAccuracyMeters != location.accuracyMeters ||
        stored.reachCount != revision.reachCount ||
        stored.interestLevel != revision.interestLevel) {
      return false;
    }
    final storedAnswers =
        await (_database.select(_database.dbContactAnswers)..where(
              (row) =>
                  row.contactId.equals(revision.contactId) &
                  row.revisionNumber.equals(revision.revisionNumber),
            ))
            .get();
    if (storedAnswers.length != revision.answers.length) {
      return false;
    }
    final remoteAnswers = {
      for (final answer in revision.answers) answer.questionId: answer,
    };
    final answersMatch = storedAnswers.every((storedAnswer) {
      final remote = remoteAnswers[storedAnswer.questionId];
      return remote != null &&
          _storedContactAnswerMatches(storedAnswer, remote);
    });
    return answersMatch &&
        await _contactTargetLinksMatchRemote(
          revision.contactId,
          revision.revisionNumber,
          revision.targetLinks,
        );
  }

  bool _currentProjectionMatchesRevision(
    DbContactRecord existing,
    _RemoteContactRevision revision, {
    bool ignoreLifecycle = false,
  }) {
    final location = _remoteLocationColumns(revision.location);
    final expectedLifecycle = revision.kind == ContactRevisionKind.voided
        ? 'voided'
        : 'active';
    return existing.occurredAtUtc.toUtc() == revision.occurredAtUtc &&
        existing.occurredTimeZone == revision.occurredTimeZone &&
        existing.channel == revision.channel.storageValue &&
        existing.channelDetail == revision.channelDetail &&
        existing.locationKind == location.kind &&
        existing.placeName == location.placeName &&
        existing.smallestRegionId == location.smallestRegionId &&
        existing.regionTreeVersion == location.regionTreeVersion &&
        existing.latitude == location.latitude &&
        existing.longitude == location.longitude &&
        existing.locationAccuracyMeters == location.accuracyMeters &&
        existing.reachCount == revision.reachCount &&
        existing.interestLevel == revision.interestLevel &&
        (ignoreLifecycle || existing.lifecycleStatus == expectedLifecycle);
  }

  ContactLocation _remoteLocation(Object? value) {
    if (value is! Map<String, Object?>) {
      throw const FormatException('remote location must be an object');
    }
    return switch (value['kind']) {
      'not_applicable' => const NotApplicableContactLocation(),
      'resolved' => ResolvedContactLocation(
        placeName: _requiredString(value['placeName']),
        smallestRegionId: _requiredString(value['smallestRegionId']),
        regionTreeVersion: _requiredString(value['regionTreeVersion']),
      ),
      'pending_resolution' => _pendingRemoteLocation(value),
      _ => throw const FormatException('unsupported remote location'),
    };
  }

  ContactChannel _remoteChannel(String value) {
    return switch (value) {
      'face_to_face' => ContactChannel.faceToFace,
      'voice_call' => ContactChannel.voiceCall,
      'video_call' => ContactChannel.videoCall,
      'instant_text' => ContactChannel.instantText,
      'asynchronous_message' => ContactChannel.asynchronousMessage,
      'mixed' => ContactChannel.mixed,
      'other_direct' => ContactChannel.otherDirect,
      _ => throw const FormatException('unsupported remote channel'),
    };
  }

  PendingContactLocation _pendingRemoteLocation(Map<String, Object?> value) {
    final latitude = _number(value['latitude']);
    final longitude = _number(value['longitude']);
    final accuracyMeters = _optionalNumber(value['accuracyMeters']);
    if (latitude < -90 ||
        latitude > 90 ||
        longitude < -180 ||
        longitude > 180 ||
        (accuracyMeters != null && accuracyMeters < 0)) {
      throw const FormatException('remote coordinates are out of range');
    }
    return PendingContactLocation(
      latitude: latitude,
      longitude: longitude,
      accuracyMeters: accuracyMeters,
    );
  }

  Future<void> _insertContactAnswer({
    required String contactId,
    required int revisionNumber,
    required QuestionnaireAnswer answer,
  }) async {
    final columns = QuestionnaireAnswerCodec.toColumns(answer);
    await _database
        .into(_database.dbContactAnswers)
        .insert(
          DbContactAnswersCompanion.insert(
            contactId: contactId,
            revisionNumber: revisionNumber,
            questionId: columns.questionId,
            answerState: columns.state,
            answerStateReason: Value(columns.stateReason),
            answerType: columns.type,
            booleanValue: Value(columns.booleanValue),
            textValue: Value(columns.textValue),
            numberValue: Value(columns.numberValue),
            multiChoiceValueJson: Value(columns.multiChoiceValueJson),
          ),
        );
  }

  Future<void> _insertRemoteContactTargetLinks({
    required String contactId,
    required int revisionNumber,
    required List<ContactTargetLink> targetLinks,
  }) async {
    for (final link in targetLinks) {
      await _database
          .into(_database.dbContactTargetLinks)
          .insert(
            DbContactTargetLinksCompanion.insert(
              contactId: contactId,
              revisionNumber: revisionNumber,
              targetId: link.targetId,
              targetType: link.targetType.storageValue,
              responseLevel: Value(link.responseLevel),
              followUpConsent: link.followUpConsent.storageValue,
              institutionRepresentativeConfirmed:
                  link.institutionRepresentativeConfirmed,
              confirmStageZero: link.confirmStageZero,
            ),
          );
    }
  }

  Future<void> _insertRemoteDraftTargetLinks(
    String draftId,
    List<ContactTargetLink> targetLinks,
  ) async {
    for (final link in targetLinks) {
      await _database
          .into(_database.dbContactDraftTargetLinks)
          .insert(
            DbContactDraftTargetLinksCompanion.insert(
              draftId: draftId,
              targetId: link.targetId,
              targetType: link.targetType.storageValue,
              responseLevel: Value(link.responseLevel),
              followUpConsent: link.followUpConsent.storageValue,
              institutionRepresentativeConfirmed:
                  link.institutionRepresentativeConfirmed,
              confirmStageZero: link.confirmStageZero,
            ),
          );
    }
  }

  Future<bool> _contactTargetLinksMatchRemote(
    String contactId,
    int revisionNumber,
    List<ContactTargetLink> remote,
  ) async {
    final stored =
        await (_database.select(_database.dbContactTargetLinks)..where(
              (row) =>
                  row.contactId.equals(contactId) &
                  row.revisionNumber.equals(revisionNumber),
            ))
            .get();
    return _storedTargetLinksMatch(stored, remote);
  }

  Future<bool> _draftTargetLinksMatchRemote(_RemoteDraftUpsert draft) async {
    final stored = await (_database.select(
      _database.dbContactDraftTargetLinks,
    )..where((row) => row.draftId.equals(draft.draftId))).get();
    return _storedDraftTargetLinksMatch(stored, draft.targetLinks);
  }

  bool _storedTargetLinksMatch(
    List<DbContactTargetLink> stored,
    List<ContactTargetLink> remote,
  ) {
    if (stored.length != remote.length) return false;
    final remoteById = {for (final link in remote) link.targetId: link};
    return stored.every((row) {
      final link = remoteById[row.targetId];
      return link != null &&
          row.targetType == link.targetType.storageValue &&
          row.responseLevel == link.responseLevel &&
          row.followUpConsent == link.followUpConsent.storageValue &&
          row.institutionRepresentativeConfirmed ==
              link.institutionRepresentativeConfirmed &&
          row.confirmStageZero == link.confirmStageZero;
    });
  }

  bool _storedDraftTargetLinksMatch(
    List<DbContactDraftTargetLink> stored,
    List<ContactTargetLink> remote,
  ) {
    if (stored.length != remote.length) return false;
    final remoteById = {for (final link in remote) link.targetId: link};
    return stored.every((row) {
      final link = remoteById[row.targetId];
      return link != null &&
          row.targetType == link.targetType.storageValue &&
          row.responseLevel == link.responseLevel &&
          row.followUpConsent == link.followUpConsent.storageValue &&
          row.institutionRepresentativeConfirmed ==
              link.institutionRepresentativeConfirmed &&
          row.confirmStageZero == link.confirmStageZero;
    });
  }

  Future<void> _insertDraftAnswer({
    required String draftId,
    required QuestionnaireAnswer answer,
  }) async {
    final columns = QuestionnaireAnswerCodec.toColumns(answer);
    await _database
        .into(_database.dbContactDraftAnswers)
        .insert(
          DbContactDraftAnswersCompanion.insert(
            draftId: draftId,
            questionId: columns.questionId,
            answerState: columns.state,
            answerStateReason: Value(columns.stateReason),
            answerType: columns.type,
            booleanValue: Value(columns.booleanValue),
            textValue: Value(columns.textValue),
            numberValue: Value(columns.numberValue),
            multiChoiceValueJson: Value(columns.multiChoiceValueJson),
          ),
        );
  }

  bool _storedContactAnswerMatches(
    DbContactAnswer stored,
    QuestionnaireAnswer remote,
  ) {
    final local = QuestionnaireAnswerCodec.fromColumns(
      questionId: stored.questionId,
      state: stored.answerState,
      stateReason: stored.answerStateReason,
      type: stored.answerType,
      booleanValue: stored.booleanValue,
      textValue: stored.textValue,
      numberValue: stored.numberValue,
      multiChoiceValueJson: stored.multiChoiceValueJson,
    );
    return _questionnaireAnswersEqual(local, remote);
  }

  bool _storedDraftAnswerMatches(
    DbContactDraftAnswer stored,
    QuestionnaireAnswer remote,
  ) {
    final local = QuestionnaireAnswerCodec.fromColumns(
      questionId: stored.questionId,
      state: stored.answerState,
      stateReason: stored.answerStateReason,
      type: stored.answerType,
      booleanValue: stored.booleanValue,
      textValue: stored.textValue,
      numberValue: stored.numberValue,
      multiChoiceValueJson: stored.multiChoiceValueJson,
    );
    return _questionnaireAnswersEqual(local, remote);
  }

  bool _questionnaireAnswersEqual(
    QuestionnaireAnswer left,
    QuestionnaireAnswer right,
  ) {
    if (left.questionId != right.questionId ||
        left.state != right.state ||
        left.stateReason != right.stateReason ||
        left.type != right.type) {
      return false;
    }
    if (left.type == QuestionnaireQuestionType.multiChoice &&
        left.state == QuestionnaireAnswerState.answered) {
      return (left.value! as List<String>).toSet().containsAll(
            (right.value! as List<String>).toSet(),
          ) &&
          (left.value! as List<String>).length ==
              (right.value! as List<String>).length;
    }
    return left.value == right.value;
  }

  QuestionnaireAnswer _remoteAnswer(Object? value) {
    if (value is! Map<String, Object?>) {
      throw const FormatException('unsupported remote answer');
    }
    return QuestionnaireAnswerCodec.fromJson({
      'question_id': value['questionId'],
      'state': value['state'],
      'state_reason': value['stateReason'],
      'type': value['type'],
      'value': value['value'],
    });
  }

  List<ContactTargetLink> _remoteTargetLinks(Object? value) {
    if (value == null) return const [];
    if (value is! List<Object?>) {
      throw const FormatException('remote target links must be a list');
    }
    final targetIds = <String>{};
    return [
      for (final candidate in value)
        (() {
          if (candidate is! Map<String, Object?>) {
            throw const FormatException('invalid remote target link');
          }
          final targetId = _requiredString(candidate['targetId']);
          if (!targetIds.add(targetId)) {
            throw const FormatException('duplicate remote target link');
          }
          final targetType = switch (_requiredString(candidate['targetType'])) {
            'person' => PromotionTargetType.person,
            'institution' => PromotionTargetType.institution,
            _ => throw const FormatException('invalid remote target type'),
          };
          final responseLevel = _optionalInteger(candidate['responseLevel']);
          final consent = switch (_requiredString(
            candidate['followUpConsent'],
          )) {
            'yes' => ContactFollowUpConsent.yes,
            'no' => ContactFollowUpConsent.no,
            'unknown' => ContactFollowUpConsent.unknown,
            'refused' => ContactFollowUpConsent.refused,
            'not_applicable' => ContactFollowUpConsent.notApplicable,
            _ => throw const FormatException('invalid remote consent'),
          };
          final representative =
              candidate['institutionRepresentativeConfirmed'];
          final confirmStageZero = candidate['confirmStageZero'];
          if (responseLevel != null &&
                  (responseLevel < 0 || responseLevel > 4) ||
              representative is! bool ||
              confirmStageZero is! bool ||
              targetType == PromotionTargetType.person && representative ||
              targetType == PromotionTargetType.institution &&
                  responseLevel != null &&
                  !representative) {
            throw const FormatException('invalid remote target link');
          }
          return ContactTargetLink(
            targetId: targetId,
            targetType: targetType,
            responseLevel: responseLevel,
            followUpConsent: consent,
            institutionRepresentativeConfirmed: representative,
            confirmStageZero: confirmStageZero,
          );
        })(),
    ];
  }

  ({
    String kind,
    String? placeName,
    String? smallestRegionId,
    String? regionTreeVersion,
    double? latitude,
    double? longitude,
    double? accuracyMeters,
  })
  _remoteLocationColumns(ContactLocation location) {
    return switch (location) {
      final ResolvedContactLocation resolved => (
        kind: 'resolved',
        placeName: resolved.placeName,
        smallestRegionId: resolved.smallestRegionId,
        regionTreeVersion: resolved.regionTreeVersion,
        latitude: null,
        longitude: null,
        accuracyMeters: null,
      ),
      NotApplicableContactLocation() => (
        kind: 'not_applicable',
        placeName: null,
        smallestRegionId: null,
        regionTreeVersion: null,
        latitude: null,
        longitude: null,
        accuracyMeters: null,
      ),
      final PendingContactLocation pending => (
        kind: 'pending_resolution',
        placeName: null,
        smallestRegionId: null,
        regionTreeVersion: null,
        latitude: pending.latitude,
        longitude: pending.longitude,
        accuracyMeters: pending.accuracyMeters,
      ),
    };
  }

  ({
    String? kind,
    String? placeName,
    String? smallestRegionId,
    String? regionTreeVersion,
    double? latitude,
    double? longitude,
    double? accuracyMeters,
  })
  _optionalRemoteLocationColumns(ContactLocation? location) {
    if (location == null) {
      return (
        kind: null,
        placeName: null,
        smallestRegionId: null,
        regionTreeVersion: null,
        latitude: null,
        longitude: null,
        accuracyMeters: null,
      );
    }
    final resolved = _remoteLocationColumns(location);
    return (
      kind: resolved.kind,
      placeName: resolved.placeName,
      smallestRegionId: resolved.smallestRegionId,
      regionTreeVersion: resolved.regionTreeVersion,
      latitude: resolved.latitude,
      longitude: resolved.longitude,
      accuracyMeters: resolved.accuracyMeters,
    );
  }

  DateTime _utcDate(Object? value) {
    final parsed = DateTime.tryParse(_requiredString(value));
    if (parsed == null || !parsed.isUtc) {
      throw const FormatException('remote date must be UTC');
    }
    return parsed;
  }

  DateTime? _optionalUtcDate(Object? value) =>
      value == null ? null : _utcDate(value);

  String _requiredString(Object? value) {
    if (value is! String || value.trim().isEmpty) {
      throw const FormatException('remote string is required');
    }
    return value;
  }

  String? _optionalString(Object? value) {
    if (value == null) {
      return null;
    }
    return _requiredString(value);
  }

  int _integer(Object? value) {
    if (value is! int) {
      throw const FormatException('remote integer is required');
    }
    return value;
  }

  int? _optionalInteger(Object? value) =>
      value == null ? null : _integer(value);

  double _number(Object? value) {
    if (value is! num || !value.isFinite) {
      throw const FormatException('remote number is required');
    }
    return value.toDouble();
  }

  double? _optionalNumber(Object? value) {
    return value == null ? null : _number(value);
  }
}

sealed class _ParsedRemoteChange {
  const _ParsedRemoteChange();
}

final class _RemoteContact extends _ParsedRemoteChange {
  const _RemoteContact({
    required this.contactId,
    required this.questionnaireVersionId,
    required this.occurredAtUtc,
    required this.occurredTimeZone,
    required this.firstSubmittedAtUtc,
    required this.channel,
    required this.channelDetail,
    required this.location,
    required this.reachCount,
    required this.interestLevel,
    required this.answers,
    required this.targetLinks,
    required this.sourceAttemptId,
  });

  final String contactId;
  final String questionnaireVersionId;
  final DateTime occurredAtUtc;
  final String occurredTimeZone;
  final DateTime firstSubmittedAtUtc;
  final ContactChannel channel;
  final String? channelDetail;
  final ContactLocation location;
  final int reachCount;
  final int interestLevel;
  final List<QuestionnaireAnswer> answers;
  final List<ContactTargetLink> targetLinks;
  final String? sourceAttemptId;
}

final class _RemoteContactRevision extends _ParsedRemoteChange {
  const _RemoteContactRevision({
    required this.contactId,
    required this.revisionNumber,
    required this.kind,
    required this.questionnaireVersionId,
    required this.revisedAtUtc,
    required this.reason,
    required this.occurredAtUtc,
    required this.occurredTimeZone,
    required this.firstSubmittedAtUtc,
    required this.channel,
    required this.channelDetail,
    required this.location,
    required this.reachCount,
    required this.interestLevel,
    required this.answers,
    required this.targetLinks,
  });

  final String contactId;
  final int revisionNumber;
  final ContactRevisionKind kind;
  final String questionnaireVersionId;
  final DateTime revisedAtUtc;
  final String reason;
  final DateTime occurredAtUtc;
  final String occurredTimeZone;
  final DateTime firstSubmittedAtUtc;
  final ContactChannel channel;
  final String? channelDetail;
  final ContactLocation location;
  final int reachCount;
  final int interestLevel;
  final List<QuestionnaireAnswer> answers;
  final List<ContactTargetLink> targetLinks;
}

final class _RemoteContactAttempt extends _ParsedRemoteChange {
  const _RemoteContactAttempt({
    required this.attemptId,
    required this.occurredAtUtc,
    required this.occurredTimeZone,
    required this.firstSubmittedAtUtc,
    required this.channel,
    required this.channelDetail,
    required this.linkedContactId,
  });

  final String attemptId;
  final DateTime occurredAtUtc;
  final String occurredTimeZone;
  final DateTime firstSubmittedAtUtc;
  final ContactChannel channel;
  final String? channelDetail;
  final String? linkedContactId;
}

final class _RemoteDraftUpsert extends _ParsedRemoteChange {
  const _RemoteDraftUpsert({
    required this.draftId,
    required this.questionnaireVersionId,
    required this.createdAtUtc,
    required this.updatedAtUtc,
    required this.occurredAtUtc,
    required this.occurredTimeZone,
    required this.channel,
    required this.channelDetail,
    required this.location,
    required this.reachCount,
    required this.interestLevel,
    required this.answers,
    required this.targetLinks,
    required this.serverRevision,
    required this.sourceDeviceId,
    required this.sourceAttemptId,
    required this.upgradedFromDraftId,
  });

  final String draftId;
  final String questionnaireVersionId;
  final DateTime createdAtUtc;
  final DateTime updatedAtUtc;
  final DateTime? occurredAtUtc;
  final String? occurredTimeZone;
  final ContactChannel? channel;
  final String? channelDetail;
  final ContactLocation? location;
  final int? reachCount;
  final int? interestLevel;
  final List<QuestionnaireAnswer> answers;
  final List<ContactTargetLink> targetLinks;
  final int serverRevision;
  final String sourceDeviceId;
  final String? sourceAttemptId;
  final String? upgradedFromDraftId;
}

final class _RemoteDraftDelete extends _ParsedRemoteChange {
  const _RemoteDraftDelete({
    required this.draftId,
    required this.serverRevision,
  });

  final String draftId;
  final int serverRevision;
}

sealed class _ClaimResult {
  const _ClaimResult();
}

final class _ClaimIdle extends _ClaimResult {
  const _ClaimIdle();
}

final class _ClaimBusy extends _ClaimResult {
  const _ClaimBusy();
}

final class _ClaimedCommand extends _ClaimResult {
  const _ClaimedCommand(this.row);

  final DbSyncOutboxData row;
}

sealed class _BatchClaimResult {
  const _BatchClaimResult();
}

final class _BatchClaimIdle extends _BatchClaimResult {
  const _BatchClaimIdle();
}

final class _BatchClaimBusy extends _BatchClaimResult {
  const _BatchClaimBusy();
}

final class _ClaimedCommands extends _BatchClaimResult {
  const _ClaimedCommands(this.rows);

  final List<DbSyncOutboxData> rows;
}

final class _ClaimCollision implements Exception {
  const _ClaimCollision();
}
