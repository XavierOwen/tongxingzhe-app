import 'dart:convert';
import 'dart:math';

import 'package:drift/drift.dart';

import '../data/local_database.dart';
import '../features/contact_journal/contact_models.dart';
import '../foundation/runtime_values.dart';
import 'sync_models.dart';
import 'sync_transport.dart';

/// 独占 Outbox 领取、租约、ACK、退避与健康状态的同步深模块。
///
/// [drainOnce] 每次最多发送一条 command。调度器可以在前台重复调用，但页面
/// 不能直接读写 Outbox。跨进程互斥由 SQLite 租约表提供。
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
  );

  static const _drainerLeaseName = 'sync.global.v1';
  static const _maximumRetryDelay = Duration(minutes: 5);
  static const _maximumRetryAfter = Duration(hours: 1);

  final LocalDatabase _database;
  final AppClock _clock;
  final String _workerId;
  final SyncScope _scope;
  final SyncTransport _transport;
  final SyncJitter _jitter;
  final Duration _leaseDuration;

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
      final decoded = jsonDecode(leased.payloadJson);
      if (decoded is! Map<String, Object?>) {
        throw const FormatException('sync payload must be an object');
      }
      result = await _transport.push(
        SyncCommand(
          protocolVersion: leased.protocolVersion,
          commandId: leased.commandId,
          deviceId: leased.deviceId,
          aggregateId: leased.aggregateId,
          baseRevision: leased.baseRevision,
          commandType: leased.commandType,
          payload: Map.unmodifiable(decoded),
        ),
      );
    } on FormatException {
      result = const SyncPushPermanentFailure(
        failureCode: 'invalid_local_payload',
      );
    } catch (_) {
      result = const SyncPushRetryable(failureCode: 'network_unavailable');
    }

    return _acknowledge(leased, result);
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
              _parseRemoteContact(change),
          ];
          final nextCursor = succeeded.batch.nextCursor;
          if (parsed.isNotEmpty && (nextCursor == null || nextCursor.isEmpty)) {
            throw const FormatException('remote batch cursor is required');
          }
          final nowUtc = _clock.now().toUtc();
          await _database.transaction(() async {
            for (final contact in parsed) {
              await _applyRemoteContact(contact);
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

  Future<_ClaimResult> _claimReadyCommand() {
    return _database.transaction(() async {
      final nowUtc = _clock.now().toUtc();
      final leaseQuery = _database.select(_database.dbSyncDrainerLeases)
        ..where((row) => row.leaseName.equals(_drainerLeaseName));
      final currentLease = await leaseQuery.getSingleOrNull();
      if (currentLease != null &&
          currentLease.leaseExpiresAtUtc.toUtc().isAfter(nowUtc)) {
        return const _ClaimBusy();
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

      final ready = await _database
          .readReadySyncCommand(
            _scope.appUserId,
            _scope.workspaceId,
            _scope.projectId,
            nowUtc,
          )
          .getSingleOrNull();
      if (ready == null) {
        await _releaseDrainerLease();
        return const _ClaimIdle();
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
        await _releaseDrainerLease();
        return const _ClaimBusy();
      }
      return _ClaimedCommand(
        ready.copyWith(
          status: 'leased',
          attemptCount: ready.attemptCount + 1,
          leaseOwner: Value(_workerId),
          leaseExpiresAtUtc: Value(leaseExpiresAtUtc),
        ),
      );
    });
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

      final outcome = switch (result) {
        final SyncPushAccepted accepted => await _completeCommand(
          current,
          accepted,
          nowUtc,
        ),
        final SyncPushConflict conflict => await _stopCommand(
          current,
          status: 'needs_resolution',
          failureCode: conflict.failureCode,
          nowUtc: nowUtc,
          outcome: SyncDrainResult.needsResolution,
        ),
        final SyncPushPermanentFailure failure => await _stopCommand(
          current,
          status: 'permanent_failure',
          failureCode: failure.failureCode,
          nowUtc: nowUtc,
          outcome: SyncDrainResult.permanentFailure,
        ),
        final SyncPushRetryable retryable => await _retryCommand(
          current,
          retryable,
          nowUtc,
        ),
      };
      await _releaseDrainerLease();
      return outcome;
    });
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
    await _writeScopeState(
      nowUtc: nowUtc,
      lastSuccessAtUtc: nowUtc,
      lastFailureCode: null,
    );
    return SyncDrainResult.completed;
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
    final exponent = min(max(attemptCount - 1, 0), 7);
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
    return trimmed.isEmpty ? 'unknown_sync_failure' : trimmed;
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
    );
  }

  Future<void> _applyRemoteContact(_RemoteContact contact) async {
    final existingQuery = _database.select(_database.dbContactRecords)
      ..where((row) => row.contactId.equals(contact.contactId));
    final existing = await existingQuery.getSingleOrNull();
    if (existing != null) {
      if (await _existingContactMatchesRemote(existing, contact)) {
        return;
      }
      throw const FormatException('remote contact conflicts with local fact');
    }
    final location = _remoteLocationColumns(contact.location);
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
            latitude: Value(location.latitude),
            longitude: Value(location.longitude),
            locationAccuracyMeters: Value(location.accuracyMeters),
            reachCount: contact.reachCount,
            interestLevel: contact.interestLevel,
            currentRevision: 1,
            lifecycleStatus: 'active',
          ),
        );
    await _database
        .into(_database.dbContactRevisions)
        .insert(
          DbContactRevisionsCompanion.insert(
            revisionId: '${contact.contactId}:remote:1',
            contactId: contact.contactId,
            revisionNumber: 1,
            revisedByAppUserId: _scope.appUserId,
            revisedAtUtc: contact.firstSubmittedAtUtc,
            occurredAtUtc: contact.occurredAtUtc,
            occurredTimeZone: contact.occurredTimeZone,
            channel: contact.channel.storageValue,
            channelDetail: Value(contact.channelDetail),
            locationKind: location.kind,
            placeName: Value(location.placeName),
            smallestRegionId: Value(location.smallestRegionId),
            latitude: Value(location.latitude),
            longitude: Value(location.longitude),
            locationAccuracyMeters: Value(location.accuracyMeters),
            reachCount: contact.reachCount,
            interestLevel: contact.interestLevel,
          ),
        );
    for (final answer in contact.answers) {
      await _database
          .into(_database.dbContactAnswers)
          .insert(
            DbContactAnswersCompanion.insert(
              contactId: contact.contactId,
              revisionNumber: 1,
              questionId: answer.questionId,
              answerState: answer.state.storageValue,
              answerType: 'boolean',
              booleanValue: Value(answer.value),
            ),
          );
    }
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
        existing.questionnaireVersionId != contact.questionnaireVersionId ||
        existing.occurredAtUtc.toUtc() != contact.occurredAtUtc ||
        existing.occurredTimeZone != contact.occurredTimeZone ||
        existing.firstSubmittedAtUtc.toUtc() != contact.firstSubmittedAtUtc ||
        existing.channel != contact.channel.storageValue ||
        existing.channelDetail != contact.channelDetail ||
        existing.locationKind != location.kind ||
        existing.placeName != location.placeName ||
        existing.smallestRegionId != location.smallestRegionId ||
        existing.latitude != location.latitude ||
        existing.longitude != location.longitude ||
        existing.locationAccuracyMeters != location.accuracyMeters ||
        existing.reachCount != contact.reachCount ||
        existing.interestLevel != contact.interestLevel ||
        existing.currentRevision != 1 ||
        existing.lifecycleStatus != 'active') {
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
    return storedAnswers.every((stored) {
      final remote = remoteAnswers[stored.questionId];
      return remote != null &&
          stored.answerType == 'boolean' &&
          stored.answerState == remote.state.storageValue &&
          stored.booleanValue == remote.value;
    });
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

  BooleanQuestionnaireAnswer _remoteAnswer(Object? value) {
    if (value is! Map<String, Object?> || value['type'] != 'boolean') {
      throw const FormatException('unsupported remote answer');
    }
    final questionId = _requiredString(value['questionId']);
    return switch (value['state']) {
      'answered' when value['value'] is bool => BooleanQuestionnaireAnswer(
        questionId: questionId,
        value: value['value']! as bool,
      ),
      'unknown' when value['value'] == null =>
        BooleanQuestionnaireAnswer.unknown(questionId: questionId),
      'refused' when value['value'] == null =>
        BooleanQuestionnaireAnswer.refused(questionId: questionId),
      'not_applicable' when value['value'] == null =>
        BooleanQuestionnaireAnswer.notApplicable(questionId: questionId),
      'unanswered' when value['value'] == null =>
        BooleanQuestionnaireAnswer.unanswered(questionId: questionId),
      _ => throw const FormatException('invalid remote answer state'),
    };
  }

  ({
    String kind,
    String? placeName,
    String? smallestRegionId,
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
        latitude: null,
        longitude: null,
        accuracyMeters: null,
      ),
      NotApplicableContactLocation() => (
        kind: 'not_applicable',
        placeName: null,
        smallestRegionId: null,
        latitude: null,
        longitude: null,
        accuracyMeters: null,
      ),
      final PendingContactLocation pending => (
        kind: 'pending_resolution',
        placeName: null,
        smallestRegionId: null,
        latitude: pending.latitude,
        longitude: pending.longitude,
        accuracyMeters: pending.accuracyMeters,
      ),
    };
  }

  DateTime _utcDate(Object? value) {
    final parsed = DateTime.tryParse(_requiredString(value));
    if (parsed == null || !parsed.isUtc) {
      throw const FormatException('remote date must be UTC');
    }
    return parsed;
  }

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

final class _RemoteContact {
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
  final List<BooleanQuestionnaireAnswer> answers;
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
