import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tongxingzhe_app/data/local_database.dart';
import 'package:tongxingzhe_app/features/contact_journal/contact_journal.dart';
import 'package:tongxingzhe_app/features/contact_journal/contact_models.dart';
import 'package:tongxingzhe_app/foundation/runtime_values.dart';
import 'package:tongxingzhe_app/sync/sync_engine.dart';
import 'package:tongxingzhe_app/sync/sync_models.dart';
import 'package:tongxingzhe_app/sync/sync_transport.dart';

void main() {
  test('accepted ACK 完成上传但不冒充已拉取 cursor', () async {
    final fixture = _Fixture();
    addTearDown(fixture.close);
    await fixture.submitContact();
    final transport = _QueueSyncTransport([
      const SyncPushAccepted(serverCursor: 'cursor-1'),
    ]);
    final engine = fixture.engine(workerId: 'worker-1', transport: transport);

    final result = await engine.drainOnce();

    expect(result, SyncDrainResult.completed);
    expect(transport.commands, hasLength(1));
    expect(transport.commands.single.commandType, 'contact.submit.v1');
    expect(transport.commands.single.payload['reach_count'], 2);
    final health = await engine.health();
    expect(health.onlyOnDeviceCount, 0);
    expect(health.syncingCount, 0);
    expect(health.completedCount, 1);
    expect(health.serverCursor, isNull);
    expect(health.lastSuccessAtUtc, fixture.clock.now().toUtc());
  });

  test('上传 ACK 不能跳过排在它之前的其他设备变化', () async {
    final fixture = _Fixture();
    addTearDown(fixture.close);
    await fixture.submitContact();
    final transport = _QueueSyncTransport(
      [const SyncPushAccepted(serverCursor: 'cursor-own-contact')],
      pullReplies: [
        SyncPullSucceeded(
          SyncPullBatch(
            nextCursor: 'cursor-own-contact',
            changes: [
              SyncRemoteChange(
                changeType: 'contact.submitted',
                revisionNumber: 1,
                payload: _remotePayload(contactId: 'other-device-contact'),
              ),
              SyncRemoteChange(
                changeType: 'contact.submitted',
                revisionNumber: 1,
                payload: _remotePayload(contactId: 'contact-1'),
              ),
            ],
          ),
        ),
      ],
    );
    final engine = fixture.engine(workerId: 'worker-1', transport: transport);

    expect(await engine.drainOnce(), SyncDrainResult.completed);
    expect(await engine.pullOnce(), SyncPullApplyResult.applied);

    expect(transport.pullCursors, [isNull]);
    final journal = ContactJournal(
      database: fixture.database,
      clock: fixture.clock,
      idGenerator: _SequenceIdGenerator(const []),
    );
    final summary = await journal.summarizePersonalContacts(
      appUserId: _Fixture.scope.appUserId,
      workspaceId: _Fixture.scope.workspaceId,
      projectId: _Fixture.scope.projectId,
      fromUtc: DateTime.utc(2030, 1, 8),
      untilUtc: DateTime.utc(2030, 1, 9),
    );
    expect(summary.contactSessionCount, 2);
    expect((await engine.health()).serverCursor, 'cursor-own-contact');
  });

  test('可重试失败先持久退避，期限到达后才再次发送', () async {
    final fixture = _Fixture();
    addTearDown(fixture.close);
    await fixture.submitContact();
    final transport = _QueueSyncTransport([
      const SyncPushRetryable(failureCode: 'server_unavailable'),
      const SyncPushAccepted(serverCursor: 'cursor-after-retry'),
    ]);
    final engine = fixture.engine(workerId: 'worker-1', transport: transport);

    expect(await engine.drainOnce(), SyncDrainResult.retryScheduled);
    var health = await engine.health();
    expect(health.retryingCount, 1);
    expect(health.lastFailureCode, 'server_unavailable');

    fixture.clock.advance(const Duration(seconds: 1));
    expect(await engine.drainOnce(), SyncDrainResult.idle);
    expect(transport.commands, hasLength(1));

    fixture.clock.advance(const Duration(seconds: 2));
    expect(await engine.drainOnce(), SyncDrainResult.completed);
    expect(transport.commands, hasLength(2));
    health = await engine.health();
    expect(health.completedCount, 1);
    expect(health.retryingCount, 0);
  });

  test('同步健康不持久服务端自由文本或 PII 失败码', () async {
    final fixture = _Fixture();
    addTearDown(fixture.close);
    await fixture.submitContact();
    final transport = _QueueSyncTransport([
      const SyncPushRetryable(failureCode: 'failed for person@example.test'),
    ]);
    final engine = fixture.engine(workerId: 'worker-1', transport: transport);

    expect(await engine.drainOnce(), SyncDrainResult.retryScheduled);

    final health = await engine.health();
    expect(health.lastFailureCode, 'unknown_sync_failure');
  });

  test('指数退避和 jitter 不超过五分钟本地上限', () async {
    final fixture = _Fixture();
    addTearDown(fixture.close);
    await fixture.submitContact();
    await (fixture.database.update(fixture.database.dbSyncOutbox)
          ..where((row) => row.commandId.equals('command-1')))
        .write(const DbSyncOutboxCompanion(attemptCount: Value(20)));
    final engine = fixture.engine(
      workerId: 'worker-1',
      transport: _QueueSyncTransport([
        const SyncPushRetryable(failureCode: 'server_unavailable'),
      ]),
      jitter: const FixedSyncJitter(0.999999),
    );

    expect(await engine.drainOnce(), SyncDrainResult.retryScheduled);

    final row = await fixture.database
        .select(fixture.database.dbSyncOutbox)
        .getSingle();
    expect(
      row.nextAttemptAtUtc.toUtc(),
      fixture.clock.now().toUtc().add(const Duration(minutes: 5)),
    );
  });

  test('可信 Retry-After 在状态机内最多延后一小时', () async {
    final fixture = _Fixture();
    addTearDown(fixture.close);
    await fixture.submitContact();
    final engine = fixture.engine(
      workerId: 'worker-1',
      transport: _QueueSyncTransport([
        const SyncPushRetryable(
          failureCode: 'rate_limited',
          retryAfter: Duration(hours: 2),
        ),
      ]),
    );

    expect(await engine.drainOnce(), SyncDrainResult.retryScheduled);

    final row = await fixture.database
        .select(fixture.database.dbSyncOutbox)
        .getSingle();
    expect(
      row.nextAttemptAtUtc.toUtc(),
      fixture.clock.now().toUtc().add(const Duration(hours: 1)),
    );
  });

  test('活动 drainer 阻止第二执行器，租约过期后可恢复命令', () async {
    final fixture = _Fixture();
    addTearDown(fixture.close);
    await fixture.submitContact();
    final blockedReply = Completer<SyncPushResult>();
    final firstTransport = _BlockingSyncTransport(blockedReply.future);
    final secondTransport = _QueueSyncTransport([
      const SyncPushAccepted(serverCursor: 'cursor-recovered'),
    ]);
    final first = fixture.engine(
      workerId: 'worker-crashed',
      transport: firstTransport,
    );
    final second = fixture.engine(
      workerId: 'worker-recovery',
      transport: secondTransport,
    );

    final abandonedRun = first.drainOnce();
    await firstTransport.commandReceived.future;

    expect(await second.drainOnce(), SyncDrainResult.busy);
    expect(secondTransport.commands, isEmpty);

    fixture.clock.advance(const Duration(seconds: 31));
    expect(await second.drainOnce(), SyncDrainResult.completed);
    expect(secondTransport.commands, hasLength(1));

    blockedReply.complete(const SyncPushAccepted(serverCursor: 'stale-cursor'));
    expect(await abandonedRun, SyncDrainResult.lostLease);
    final health = await second.health();
    expect(health.completedCount, 1);
    expect(health.serverCursor, isNull);
  });

  test('同一 aggregate 的早期冲突阻止后续命令越序发送', () async {
    final fixture = _Fixture();
    addTearDown(fixture.close);
    await fixture.submitContact();
    await fixture.database
        .into(fixture.database.dbSyncOutbox)
        .insert(
          DbSyncOutboxCompanion.insert(
            commandId: 'command-2',
            protocolVersion: 1,
            commandType: 'contact.revise.v1',
            deviceId: 'device-1',
            aggregateId: 'contact-1',
            baseRevision: 1,
            payloadJson: '{"interest_level":4}',
            createdAtUtc: fixture.clock.now().toUtc().add(
              const Duration(seconds: 1),
            ),
            status: 'pending',
            nextAttemptAtUtc: fixture.clock.now().toUtc(),
          ),
        );
    final transport = _QueueSyncTransport([
      const SyncPushConflict(),
      const SyncPushAccepted(serverCursor: 'must-not-be-used'),
    ]);
    final engine = fixture.engine(workerId: 'worker-1', transport: transport);

    expect(await engine.drainOnce(), SyncDrainResult.needsResolution);
    expect(await engine.drainOnce(), SyncDrainResult.idle);
    expect(transport.commands.map((command) => command.commandId), [
      'command-1',
    ]);
  });

  test('一个 aggregate 的冲突不阻塞其他 aggregate', () async {
    final fixture = _Fixture();
    addTearDown(fixture.close);
    await fixture.submitContact();
    await fixture.submitContact(suffix: '2');
    final transport = _QueueSyncTransport([
      const SyncPushConflict(),
      const SyncPushAccepted(serverCursor: 'cursor-contact-2'),
    ]);
    final engine = fixture.engine(workerId: 'worker-1', transport: transport);

    expect(await engine.drainOnce(), SyncDrainResult.needsResolution);
    expect(await engine.drainOnce(), SyncDrainResult.completed);
    expect(transport.commands.map((command) => command.commandId), [
      'command-1',
      'command-2',
    ]);
    final health = await engine.health();
    expect(health.needsResolutionCount, 1);
    expect(health.completedCount, 1);
  });

  test('修订冲突持久保留双方快照，解决后追加新 revision', () async {
    final fixture = _Fixture();
    addTearDown(fixture.close);
    await fixture.submitContact();
    final transport = _QueueSyncTransport([
      const SyncPushAccepted(serverCursor: 'cursor-submit'),
      SyncPushConflict(
        failureCode: 'contact_revision_conflict',
        conflict: SyncContactRevisionConflict(
          conflictId: 'conflict-1',
          contactId: 'contact-1',
          baseRevision: 1,
          currentRevision: 2,
          conflictingFields: ['reachCount'],
          questionnaireVersionId: 'questionnaire-v1',
          currentRevisionKind: ContactRevisionKind.corrected,
          currentRevisedAtUtc: DateTime.utc(2030, 1, 8, 19),
          currentReason: '另一台设备修正人数',
          currentSnapshot: _conflictSnapshot(reachCount: 4),
          proposedSnapshot: _conflictSnapshot(reachCount: 3),
        ),
      ),
      const SyncPushAccepted(serverCursor: 'cursor-resolution'),
    ]);
    final engine = fixture.engine(workerId: 'worker-1', transport: transport);
    expect(await engine.drainOnce(), SyncDrainResult.completed);

    final correctionJournal = ContactJournal(
      database: fixture.database,
      clock: fixture.clock,
      idGenerator: _SequenceIdGenerator([
        'revision-correction',
        'command-correction',
      ]),
    );
    await correctionJournal.correctContact(
      ContactCorrectionSubmission(
        contactId: 'contact-1',
        appUserId: _Fixture.scope.appUserId,
        workspaceId: _Fixture.scope.workspaceId,
        projectId: _Fixture.scope.projectId,
        deviceId: 'device-2',
        baseRevision: 1,
        reason: '本机修正人数',
        occurredAtUtc: DateTime.utc(2030, 1, 8, 18),
        occurredTimeZone: 'America/Chicago',
        channel: ContactChannel.videoCall,
        location: const NotApplicableContactLocation(),
        reachCount: 3,
        interestLevel: 3,
      ),
    );

    expect(await engine.drainOnce(), SyncDrainResult.needsResolution);
    var contact = await correctionJournal.contactByIdForOwner(
      contactId: 'contact-1',
      appUserId: _Fixture.scope.appUserId,
    );
    expect(contact?.revisionNumber, 2);
    expect(contact?.reachCount, 4);
    final conflicts = await correctionJournal.listContactRevisionConflicts(
      contactId: 'contact-1',
      appUserId: _Fixture.scope.appUserId,
    );
    expect(conflicts, hasLength(1));
    expect(conflicts.single.proposedSnapshot.reachCount, 3);

    final blockedJournal = ContactJournal(
      database: fixture.database,
      clock: fixture.clock,
      idGenerator: _SequenceIdGenerator([
        'blocked-revision',
        'blocked-command',
        'blocked-void-revision',
        'blocked-void-command',
      ]),
    );
    await expectLater(
      blockedJournal.correctContact(
        ContactCorrectionSubmission(
          contactId: 'contact-1',
          appUserId: _Fixture.scope.appUserId,
          workspaceId: _Fixture.scope.workspaceId,
          projectId: _Fixture.scope.projectId,
          deviceId: 'device-2',
          baseRevision: 2,
          reason: '冲突未解决时不应普通修订',
          occurredAtUtc: DateTime.utc(2030, 1, 8, 18),
          occurredTimeZone: 'America/Chicago',
          channel: ContactChannel.videoCall,
          location: const NotApplicableContactLocation(),
          reachCount: 5,
          interestLevel: 3,
        ),
      ),
      throwsA(
        isA<ContactValidationException>().having(
          (error) => error.code,
          'code',
          'contact_conflict_requires_resolution',
        ),
      ),
    );

    final resolutionJournal = ContactJournal(
      database: fixture.database,
      clock: fixture.clock,
      idGenerator: _SequenceIdGenerator([
        'revision-resolution',
        'command-resolution',
      ]),
    );
    await resolutionJournal.resolveContactRevisionConflict(
      ContactConflictResolutionSubmission(
        conflictId: 'conflict-1',
        appUserId: _Fixture.scope.appUserId,
        workspaceId: _Fixture.scope.workspaceId,
        projectId: _Fixture.scope.projectId,
        deviceId: 'device-2',
        reason: '采用本机修改',
        snapshot: conflicts.single.proposedSnapshot,
      ),
    );

    contact = await resolutionJournal.contactByIdForOwner(
      contactId: 'contact-1',
      appUserId: _Fixture.scope.appUserId,
    );
    expect(contact?.revisionNumber, 3);
    expect(contact?.reachCount, 3);
    await expectLater(
      blockedJournal.voidContact(
        ContactVoidSubmission(
          contactId: 'contact-1',
          appUserId: _Fixture.scope.appUserId,
          workspaceId: _Fixture.scope.workspaceId,
          projectId: _Fixture.scope.projectId,
          deviceId: 'device-2',
          baseRevision: 3,
          reason: '冲突解决等待同步时不应作废',
        ),
      ),
      throwsA(
        isA<ContactValidationException>().having(
          (error) => error.code,
          'code',
          'contact_conflict_already_resolving',
        ),
      ),
    );
    expect(await engine.drainOnce(), SyncDrainResult.completed);
    expect(transport.commands.last.commandType, 'contact.resolve.v1');
    expect(
      await resolutionJournal.listContactRevisionConflicts(
        contactId: 'contact-1',
        appUserId: _Fixture.scope.appUserId,
      ),
      isEmpty,
    );
  });

  test('自动合并的远端历史替换已确认的本机乐观 revision', () async {
    final fixture = _Fixture();
    addTearDown(fixture.close);
    await fixture.submitContact();
    final transport = _QueueSyncTransport(
      [
        const SyncPushAccepted(serverCursor: 'cursor-submit'),
        const SyncPushAccepted(serverCursor: 'cursor-auto-merge'),
      ],
      pullReplies: [
        SyncPullSucceeded(
          SyncPullBatch(
            nextCursor: 'cursor-auto-merge',
            changes: [
              SyncRemoteChange(
                changeType: 'contact.submitted',
                revisionNumber: 1,
                payload: _remotePayload(contactId: 'contact-1'),
              ),
              SyncRemoteChange(
                changeType: 'contact.revised',
                revisionNumber: 2,
                payload: {
                  ..._remoteRevisionPayload(
                    contactId: 'contact-1',
                    revisionKind: 'corrected',
                    reason: '另一台设备修正兴趣',
                    occurredAtUtc: '2030-01-08T18:00:00.000Z',
                    reachCount: 2,
                  ),
                  'channel': 'video_call',
                  'revisedAtUtc': '2030-01-08T18:31:00.000Z',
                },
              ),
              SyncRemoteChange(
                changeType: 'contact.revised',
                revisionNumber: 3,
                payload: {
                  ..._remoteRevisionPayload(
                    contactId: 'contact-1',
                    revisionKind: 'corrected',
                    reason: '本机修正人数',
                    occurredAtUtc: '2030-01-08T18:00:00.000Z',
                    reachCount: 3,
                  ),
                  'channel': 'video_call',
                  'revisedAtUtc': '2030-01-08T18:32:00.000Z',
                },
              ),
            ],
          ),
        ),
      ],
    );
    final engine = fixture.engine(workerId: 'worker-1', transport: transport);
    expect(await engine.drainOnce(), SyncDrainResult.completed);

    final journal = ContactJournal(
      database: fixture.database,
      clock: fixture.clock,
      idGenerator: _SequenceIdGenerator([
        'revision-correction',
        'command-correction',
      ]),
    );
    await journal.correctContact(
      ContactCorrectionSubmission(
        contactId: 'contact-1',
        appUserId: _Fixture.scope.appUserId,
        workspaceId: _Fixture.scope.workspaceId,
        projectId: _Fixture.scope.projectId,
        deviceId: 'device-1',
        baseRevision: 1,
        reason: '本机修正人数',
        occurredAtUtc: DateTime.utc(2030, 1, 8, 18),
        occurredTimeZone: 'America/Chicago',
        channel: ContactChannel.videoCall,
        location: const NotApplicableContactLocation(),
        reachCount: 3,
        interestLevel: 3,
      ),
    );
    expect(await engine.drainOnce(), SyncDrainResult.completed);

    expect(await engine.pullOnce(), SyncPullApplyResult.applied);
    final contact = await journal.contactByIdForOwner(
      contactId: 'contact-1',
      appUserId: _Fixture.scope.appUserId,
    );
    expect(contact?.revisionNumber, 3);
    expect(contact?.reachCount, 3);
    expect(contact?.interestLevel, 4);
    final history = await journal.listContactRevisions(
      contactId: 'contact-1',
      appUserId: _Fixture.scope.appUserId,
    );
    expect(history.map((revision) => revision.revisionNumber), [3, 2, 1]);
    expect(history[1].reason, '另一台设备修正兴趣');
    expect(history[1].revisedAtUtc, DateTime.utc(2030, 1, 8, 18, 31));
    expect((await engine.health()).serverCursor, 'cursor-auto-merge');
  });

  test('未确认的本机乐观 revision 不能被远端同编号覆盖', () async {
    final fixture = _Fixture();
    addTearDown(fixture.close);
    await fixture.submitContact();
    final journal = ContactJournal(
      database: fixture.database,
      clock: fixture.clock,
      idGenerator: _SequenceIdGenerator([
        'revision-correction',
        'command-correction',
      ]),
    );
    await journal.correctContact(
      ContactCorrectionSubmission(
        contactId: 'contact-1',
        appUserId: _Fixture.scope.appUserId,
        workspaceId: _Fixture.scope.workspaceId,
        projectId: _Fixture.scope.projectId,
        deviceId: 'device-1',
        baseRevision: 1,
        reason: '本机修正人数',
        occurredAtUtc: DateTime.utc(2030, 1, 8, 18),
        occurredTimeZone: 'America/Chicago',
        channel: ContactChannel.videoCall,
        location: const NotApplicableContactLocation(),
        reachCount: 3,
        interestLevel: 3,
      ),
    );
    final transport = _QueueSyncTransport(
      const [],
      pullReplies: [
        SyncPullSucceeded(
          SyncPullBatch(
            nextCursor: 'cursor-must-roll-back',
            changes: [
              SyncRemoteChange(
                changeType: 'contact.submitted',
                revisionNumber: 1,
                payload: _remotePayload(contactId: 'contact-1'),
              ),
              SyncRemoteChange(
                changeType: 'contact.revised',
                revisionNumber: 2,
                payload: {
                  ..._remoteRevisionPayload(
                    contactId: 'contact-1',
                    revisionKind: 'corrected',
                    reason: '另一台设备修正兴趣',
                    occurredAtUtc: '2030-01-08T18:00:00.000Z',
                    reachCount: 2,
                  ),
                  'channel': 'video_call',
                  'revisedAtUtc': '2030-01-08T18:31:00.000Z',
                },
              ),
            ],
          ),
        ),
      ],
    );
    final engine = fixture.engine(workerId: 'worker-1', transport: transport);

    expect(await engine.pullOnce(), SyncPullApplyResult.permanentFailure);
    final contact = await journal.contactByIdForOwner(
      contactId: 'contact-1',
      appUserId: _Fixture.scope.appUserId,
    );
    expect(contact?.revisionNumber, 2);
    expect(contact?.reachCount, 3);
    final health = await engine.health();
    expect(health.serverCursor, isNull);
    expect(health.lastFailureCode, 'invalid_remote_change');
  });

  test('一个 aggregate 的永久失败不阻塞其他 aggregate', () async {
    final fixture = _Fixture();
    addTearDown(fixture.close);
    await fixture.submitContact();
    await fixture.submitContact(suffix: '2');
    final transport = _QueueSyncTransport([
      const SyncPushPermanentFailure(failureCode: 'rejected'),
      const SyncPushAccepted(serverCursor: 'cursor-contact-2'),
    ]);
    final engine = fixture.engine(workerId: 'worker-1', transport: transport);

    expect(await engine.drainOnce(), SyncDrainResult.permanentFailure);
    expect(await engine.drainOnce(), SyncDrainResult.completed);
    expect(transport.commands.map((command) => command.commandId), [
      'command-1',
      'command-2',
    ]);
    final health = await engine.health();
    expect(health.permanentFailureCount, 1);
    expect(health.completedCount, 1);
  });

  test('批量部分成功按 command ID 归位，不重做已确认命令', () async {
    final fixture = _Fixture();
    addTearDown(fixture.close);
    await fixture.submitContact();
    await fixture.submitContact(suffix: '2');
    final transport = _BatchSyncTransport([
      const [
        SyncCommandPushOutcome(
          commandId: 'command-2',
          result: SyncPushAccepted(serverCursor: 'cursor-contact-2'),
        ),
        SyncCommandPushOutcome(
          commandId: 'command-1',
          result: SyncPushRetryable(failureCode: 'server_unavailable'),
        ),
      ],
      const [
        SyncCommandPushOutcome(
          commandId: 'command-1',
          result: SyncPushAccepted(serverCursor: 'cursor-contact-1'),
        ),
      ],
    ]);
    final engine = fixture.engine(workerId: 'worker-1', transport: transport);

    expect(await engine.drainBatch(), SyncBatchDrainResult.processed);
    var health = await engine.health();
    expect(health.completedCount, 1);
    expect(health.retryingCount, 1);
    expect(health.lastFailureCode, 'server_unavailable');

    fixture.clock.advance(const Duration(seconds: 2));
    expect(await engine.drainBatch(), SyncBatchDrainResult.processed);
    expect(
      transport.batches.map((batch) => batch.map((item) => item.commandId)),
      [
        ['command-1', 'command-2'],
        ['command-1'],
      ],
    );
    health = await engine.health();
    expect(health.completedCount, 2);
    expect(health.retryingCount, 0);
    expect(health.lastFailureCode, isNull);
  });

  test('远端 batch 原子写入本地事实后才推进不透明 cursor', () async {
    final fixture = _Fixture();
    addTearDown(fixture.close);
    final transport = _QueueSyncTransport(
      const [],
      pullReplies: [
        SyncPullSucceeded(
          SyncPullBatch(
            nextCursor: 'cursor-from-other-device',
            changes: [
              SyncRemoteChange(
                changeType: 'contact.submitted',
                revisionNumber: 1,
                payload: {
                  'contactId': 'remote-contact-1',
                  'workspaceId': _Fixture.scope.workspaceId,
                  'projectId': _Fixture.scope.projectId,
                  'questionnaireVersionId': 'questionnaire-v1',
                  'occurredAtUtc': '2030-01-08T18:00:00.000Z',
                  'occurredTimeZone': 'America/Chicago',
                  'firstSubmittedAtUtc': '2030-01-08T18:30:00.000Z',
                  'channel': 'video_call',
                  'channelDetail': null,
                  'location': {'kind': 'not_applicable'},
                  'reachCount': 2,
                  'interestLevel': 3,
                  'answers': <Object?>[],
                },
              ),
            ],
          ),
        ),
      ],
    );
    final engine = fixture.engine(workerId: 'worker-1', transport: transport);

    expect(await engine.pullOnce(), SyncPullApplyResult.applied);

    final journal = ContactJournal(
      database: fixture.database,
      clock: fixture.clock,
      idGenerator: _SequenceIdGenerator(const []),
    );
    final summary = await journal.summarizePersonalContacts(
      appUserId: _Fixture.scope.appUserId,
      workspaceId: _Fixture.scope.workspaceId,
      projectId: _Fixture.scope.projectId,
      fromUtc: DateTime.utc(2030, 1, 8),
      untilUtc: DateTime.utc(2030, 1, 9),
    );
    expect(summary.contactSessionCount, 1);
    expect(summary.reachCount, 2);
    final health = await engine.health();
    expect(health.completedCount, 1);
    expect(health.serverCursor, 'cursor-from-other-device');
  });

  test('远端更正按新发生时间归期，后续作废保留三条历史', () async {
    final fixture = _Fixture();
    addTearDown(fixture.close);
    final transport = _QueueSyncTransport(
      const [],
      pullReplies: [
        SyncPullSucceeded(
          SyncPullBatch(
            nextCursor: 'cursor-revision-2',
            changes: [
              SyncRemoteChange(
                changeType: 'contact.submitted',
                revisionNumber: 1,
                payload: _remotePayload(contactId: 'remote-revision-contact'),
              ),
              SyncRemoteChange(
                changeType: 'contact.revised',
                revisionNumber: 2,
                payload: _remoteRevisionPayload(
                  contactId: 'remote-revision-contact',
                  revisionKind: 'corrected',
                  reason: '修正发生日期和人数',
                  occurredAtUtc: '2030-02-08T18:00:00.000Z',
                  reachCount: 3,
                ),
              ),
            ],
          ),
        ),
        SyncPullSucceeded(
          SyncPullBatch(
            nextCursor: 'cursor-revision-3',
            changes: [
              SyncRemoteChange(
                changeType: 'contact.voided',
                revisionNumber: 3,
                payload: _remoteRevisionPayload(
                  contactId: 'remote-revision-contact',
                  revisionKind: 'voided',
                  reason: '重复录入',
                  occurredAtUtc: '2030-02-08T18:00:00.000Z',
                  reachCount: 3,
                ),
              ),
            ],
          ),
        ),
      ],
    );
    final engine = fixture.engine(workerId: 'worker-1', transport: transport);
    final journal = ContactJournal(
      database: fixture.database,
      clock: fixture.clock,
      idGenerator: _SequenceIdGenerator(const []),
    );

    expect(await engine.pullOnce(), SyncPullApplyResult.applied);
    final january = await journal.summarizePersonalContacts(
      appUserId: _Fixture.scope.appUserId,
      workspaceId: _Fixture.scope.workspaceId,
      projectId: _Fixture.scope.projectId,
      fromUtc: DateTime.utc(2030, 1),
      untilUtc: DateTime.utc(2030, 2),
    );
    final february = await journal.summarizePersonalContacts(
      appUserId: _Fixture.scope.appUserId,
      workspaceId: _Fixture.scope.workspaceId,
      projectId: _Fixture.scope.projectId,
      fromUtc: DateTime.utc(2030, 2),
      untilUtc: DateTime.utc(2030, 3),
    );
    expect(january.contactSessionCount, 0);
    expect(february.contactSessionCount, 1);
    expect(february.reachCount, 3);
    var history = await journal.listContactRevisions(
      contactId: 'remote-revision-contact',
      appUserId: _Fixture.scope.appUserId,
    );
    expect(history.map((revision) => revision.kind), [
      ContactRevisionKind.corrected,
      ContactRevisionKind.submitted,
    ]);
    expect(history.first.reason, '修正发生日期和人数');

    expect(await engine.pullOnce(), SyncPullApplyResult.applied);
    final afterVoid = await journal.summarizePersonalContacts(
      appUserId: _Fixture.scope.appUserId,
      workspaceId: _Fixture.scope.workspaceId,
      projectId: _Fixture.scope.projectId,
      fromUtc: DateTime.utc(2030, 2),
      untilUtc: DateTime.utc(2030, 3),
    );
    expect(afterVoid.contactSessionCount, 0);
    final current = await journal.contactById('remote-revision-contact');
    expect(current!.lifecycleStatus, ContactLifecycleStatus.voided);
    history = await journal.listContactRevisions(
      contactId: 'remote-revision-contact',
      appUserId: _Fixture.scope.appUserId,
    );
    expect(history.map((revision) => revision.kind), [
      ContactRevisionKind.voided,
      ContactRevisionKind.corrected,
      ContactRevisionKind.submitted,
    ]);
    expect(history.first.reason, '重复录入');
    expect((await engine.health()).serverCursor, 'cursor-revision-3');
  });

  test('本机已到 revision 3 时可幂等重放服务端完整历史', () async {
    final fixture = _Fixture();
    addTearDown(fixture.close);
    await fixture.submitContact();
    final journal = ContactJournal(
      database: fixture.database,
      clock: fixture.clock,
      idGenerator: _SequenceIdGenerator([
        'local-revision-2',
        'local-command-2',
        'local-revision-3',
        'local-command-3',
      ]),
    );
    await journal.correctContact(
      ContactCorrectionSubmission(
        contactId: 'contact-1',
        appUserId: _Fixture.scope.appUserId,
        workspaceId: _Fixture.scope.workspaceId,
        projectId: _Fixture.scope.projectId,
        deviceId: 'device-1',
        baseRevision: 1,
        reason: '修正发生日期和人数',
        occurredAtUtc: DateTime.utc(2030, 2, 8, 18),
        occurredTimeZone: 'America/Chicago',
        channel: ContactChannel.voiceCall,
        location: const NotApplicableContactLocation(),
        reachCount: 3,
        interestLevel: 4,
      ),
    );
    await journal.voidContact(
      ContactVoidSubmission(
        contactId: 'contact-1',
        appUserId: _Fixture.scope.appUserId,
        workspaceId: _Fixture.scope.workspaceId,
        projectId: _Fixture.scope.projectId,
        deviceId: 'device-1',
        baseRevision: 2,
        reason: '重复录入',
      ),
    );
    final transport = _QueueSyncTransport(
      const [],
      pullReplies: [
        SyncPullSucceeded(
          SyncPullBatch(
            nextCursor: 'cursor-replayed-revision-3',
            changes: [
              SyncRemoteChange(
                changeType: 'contact.submitted',
                revisionNumber: 1,
                payload: _remotePayload(contactId: 'contact-1'),
              ),
              SyncRemoteChange(
                changeType: 'contact.revised',
                revisionNumber: 2,
                payload: _remoteRevisionPayload(
                  contactId: 'contact-1',
                  revisionKind: 'corrected',
                  reason: '修正发生日期和人数',
                  occurredAtUtc: '2030-02-08T18:00:00.000Z',
                  reachCount: 3,
                ),
              ),
              SyncRemoteChange(
                changeType: 'contact.voided',
                revisionNumber: 3,
                payload: _remoteRevisionPayload(
                  contactId: 'contact-1',
                  revisionKind: 'voided',
                  reason: '重复录入',
                  occurredAtUtc: '2030-02-08T18:00:00.000Z',
                  reachCount: 3,
                ),
              ),
            ],
          ),
        ),
      ],
    );
    final engine = fixture.engine(workerId: 'worker-1', transport: transport);

    expect(await engine.pullOnce(), SyncPullApplyResult.applied);
    expect((await engine.health()).serverCursor, 'cursor-replayed-revision-3');
    final history = await journal.listContactRevisions(
      contactId: 'contact-1',
      appUserId: _Fixture.scope.appUserId,
    );
    expect(history.map((revision) => revision.revisionNumber), [3, 2, 1]);
  });

  test('远端尝试与后来回应保持两条事实并建立关联', () async {
    final fixture = _Fixture();
    addTearDown(fixture.close);
    final transport = _QueueSyncTransport(
      const [],
      pullReplies: [
        SyncPullSucceeded(
          SyncPullBatch(
            nextCursor: 'cursor-after-response',
            changes: [
              SyncRemoteChange(
                changeType: 'contact.attempt.submitted',
                revisionNumber: 1,
                payload: {
                  'attemptId': 'remote-attempt-1',
                  'workspaceId': _Fixture.scope.workspaceId,
                  'projectId': _Fixture.scope.projectId,
                  'occurredAtUtc': '2030-01-08T17:00:00.000Z',
                  'occurredTimeZone': 'America/Chicago',
                  'firstSubmittedAtUtc': '2030-01-08T17:30:00.000Z',
                  'channel': 'voice_call',
                  'channelDetail': null,
                  'linkedContactId': null,
                },
              ),
              SyncRemoteChange(
                changeType: 'contact.submitted',
                revisionNumber: 1,
                payload: {
                  ..._remotePayload(contactId: 'remote-response-1'),
                  'sourceAttemptId': 'remote-attempt-1',
                  'channel': 'voice_call',
                  'reachCount': 1,
                },
              ),
            ],
          ),
        ),
      ],
    );
    final engine = fixture.engine(workerId: 'worker-1', transport: transport);

    expect(await engine.pullOnce(), SyncPullApplyResult.applied);

    final journal = ContactJournal(
      database: fixture.database,
      clock: fixture.clock,
      idGenerator: _SequenceIdGenerator(const []),
    );
    final attempts = await journal.listContactAttempts(
      appUserId: _Fixture.scope.appUserId,
      workspaceId: _Fixture.scope.workspaceId,
      projectId: _Fixture.scope.projectId,
    );
    expect(attempts, hasLength(1));
    expect(attempts.single.linkedContactId, 'remote-response-1');
    final summary = await journal.summarizePersonalContacts(
      appUserId: _Fixture.scope.appUserId,
      workspaceId: _Fixture.scope.workspaceId,
      projectId: _Fixture.scope.projectId,
      fromUtc: DateTime.utc(2030, 1, 8),
      untilUtc: DateTime.utc(2030, 1, 9),
    );
    expect(summary.contactSessionCount, 1);
    expect(summary.reachCount, 1);
  });

  test('远端 batch 中一条无效变化会回滚全部事实和 cursor', () async {
    final fixture = _Fixture();
    addTearDown(fixture.close);
    final validPayload = <String, Object?>{
      'contactId': 'remote-contact-valid',
      'workspaceId': _Fixture.scope.workspaceId,
      'projectId': _Fixture.scope.projectId,
      'questionnaireVersionId': 'questionnaire-v1',
      'occurredAtUtc': '2030-01-08T18:00:00.000Z',
      'occurredTimeZone': 'America/Chicago',
      'firstSubmittedAtUtc': '2030-01-08T18:30:00.000Z',
      'channel': 'video_call',
      'channelDetail': null,
      'location': {'kind': 'not_applicable'},
      'reachCount': 2,
      'interestLevel': 3,
      'answers': <Object?>[],
    };
    final transport = _QueueSyncTransport(
      const [],
      pullReplies: [
        SyncPullSucceeded(
          SyncPullBatch(
            nextCursor: 'cursor-must-not-advance',
            changes: [
              SyncRemoteChange(
                changeType: 'contact.submitted',
                revisionNumber: 1,
                payload: validPayload,
              ),
              SyncRemoteChange(
                changeType: 'contact.submitted',
                revisionNumber: 1,
                payload: {
                  ...validPayload,
                  'contactId': 'remote-contact-invalid',
                  'channel': 'carrier_pigeon',
                },
              ),
            ],
          ),
        ),
      ],
    );
    final engine = fixture.engine(workerId: 'worker-1', transport: transport);

    expect(await engine.pullOnce(), SyncPullApplyResult.permanentFailure);

    final journal = ContactJournal(
      database: fixture.database,
      clock: fixture.clock,
      idGenerator: _SequenceIdGenerator(const []),
    );
    final summary = await journal.summarizePersonalContacts(
      appUserId: _Fixture.scope.appUserId,
      workspaceId: _Fixture.scope.workspaceId,
      projectId: _Fixture.scope.projectId,
      fromUtc: DateTime.utc(2030, 1, 8),
      untilUtc: DateTime.utc(2030, 1, 9),
    );
    expect(summary.contactSessionCount, 0);
    expect((await engine.health()).serverCursor, isNull);
  });

  test('同 ID 但不同内容的远端接触不能被当成幂等重放', () async {
    final fixture = _Fixture();
    addTearDown(fixture.close);
    await fixture.submitContact();
    final transport = _QueueSyncTransport(
      const [],
      pullReplies: [
        SyncPullSucceeded(
          SyncPullBatch(
            nextCursor: 'cursor-conflicting-copy',
            changes: [
              SyncRemoteChange(
                changeType: 'contact.submitted',
                revisionNumber: 1,
                payload: {
                  ..._remotePayload(contactId: 'contact-1'),
                  'reachCount': 99,
                },
              ),
            ],
          ),
        ),
      ],
    );
    final engine = fixture.engine(workerId: 'worker-1', transport: transport);

    expect(await engine.pullOnce(), SyncPullApplyResult.permanentFailure);

    final stored = await (fixture.database.select(
      fixture.database.dbContactRecords,
    )..where((row) => row.contactId.equals('contact-1'))).getSingle();
    expect(stored.reachCount, 2);
    final health = await engine.health();
    expect(health.serverCursor, isNull);
    expect(health.lastFailureCode, 'invalid_remote_change');
  });

  test('本人私有草稿通过同一持久队列上传并记录服务端 revision', () async {
    final fixture = _Fixture();
    addTearDown(fixture.close);
    await fixture.saveDraft();
    final transport = _QueueSyncTransport([
      const SyncPushAccepted(serverCursor: 'cursor-draft-1'),
    ]);
    final engine = fixture.engine(workerId: 'worker-1', transport: transport);

    expect(await engine.drainOnce(), SyncDrainResult.completed);

    expect(transport.commands, hasLength(1));
    expect(transport.commands.single.commandType, 'draft.upsert.v1');
    final draft = (await ContactJournal(
      database: fixture.database,
      clock: fixture.clock,
      idGenerator: _SequenceIdGenerator(const []),
    ).listDrafts(appUserId: _Fixture.scope.appUserId)).single;
    expect(draft.serverRevision, 1);
  });

  test('pull 读到已确认的旧草稿 revision 时保留本机后续编辑', () async {
    final fixture = _Fixture();
    addTearDown(fixture.close);
    await fixture.saveDraft();
    final transport = _QueueSyncTransport(
      [const SyncPushAccepted(serverCursor: 'cursor-draft-1')],
      pullReplies: [
        SyncPullSucceeded(
          SyncPullBatch(
            changes: [
              SyncRemoteChange(
                changeType: 'draft.upserted',
                revisionNumber: 1,
                payload: _remoteDraftPayload(
                  draftId: 'draft-1',
                  channel: 'video_call',
                  createdAtUtc: '2030-01-08T18:30:00.000Z',
                  updatedAtUtc: '2030-01-08T18:30:00.000Z',
                ),
              ),
            ],
            nextCursor: 'cursor-draft-pull-1',
          ),
        ),
      ],
    );
    final engine = fixture.engine(workerId: 'worker-1', transport: transport);
    expect(await engine.drainOnce(), SyncDrainResult.completed);

    final journal = ContactJournal(
      database: fixture.database,
      clock: fixture.clock,
      idGenerator: _SequenceIdGenerator(const []),
    );
    final draft = (await journal.listDrafts(
      appUserId: _Fixture.scope.appUserId,
    )).single;
    fixture.clock.advance(const Duration(minutes: 1));
    await journal.saveDraft(
      ContactDraftInput(
        draftId: draft.draftId,
        deviceId: 'device-1',
        appUserId: draft.appUserId,
        workspaceId: draft.workspaceId,
        projectId: draft.projectId,
        questionnaireVersionId: draft.questionnaireVersionId,
        channel: ContactChannel.voiceCall,
      ),
    );

    expect(await engine.pullOnce(), SyncPullApplyResult.applied);

    final retained = (await journal.listDrafts(
      appUserId: _Fixture.scope.appUserId,
    )).single;
    expect(retained.channel, ContactChannel.voiceCall);
    expect(retained.serverRevision, 1);
    expect(retained.isConflictCopy, isFalse);
  });

  test('已同步草稿切到仅本设备时删除远端副本但保留本机内容', () async {
    final fixture = _Fixture();
    addTearDown(fixture.close);
    await fixture.saveDraft();
    final transport = _QueueSyncTransport(
      [
        SyncPushAccepted(serverCursor: 'cursor-draft-upsert-1'),
        SyncPushAccepted(serverCursor: 'cursor-draft-delete-2'),
      ],
      pullReplies: [
        const SyncPullSucceeded(
          SyncPullBatch(
            changes: [
              SyncRemoteChange(
                changeType: 'draft.deleted',
                revisionNumber: 2,
                payload: {
                  'draftId': 'draft-1',
                  'workspaceId': 'personal-workspace-1',
                  'projectId': 'project-1',
                  'serverRevision': 2,
                  'sourceDeviceId': 'device-1',
                },
              ),
            ],
            nextCursor: 'cursor-draft-delete-2',
          ),
        ),
      ],
    );
    final engine = fixture.engine(workerId: 'worker-1', transport: transport);
    expect(await engine.drainOnce(), SyncDrainResult.completed);

    final journal = ContactJournal(
      database: fixture.database,
      clock: fixture.clock,
      idGenerator: _SequenceIdGenerator(const []),
    );
    final synced = (await journal.listDrafts(
      appUserId: _Fixture.scope.appUserId,
    )).single;
    fixture.clock.advance(const Duration(minutes: 1));
    await journal.saveDraft(
      ContactDraftInput(
        draftId: synced.draftId,
        deviceId: 'device-1',
        appUserId: synced.appUserId,
        workspaceId: synced.workspaceId,
        projectId: synced.projectId,
        questionnaireVersionId: synced.questionnaireVersionId,
        channel: synced.channel,
        syncMode: ContactDraftSyncMode.deviceOnly,
      ),
    );

    expect(await engine.drainOnce(), SyncDrainResult.completed);
    expect(transport.commands.last.commandType, 'draft.delete.v1');
    expect(transport.commands.last.baseRevision, 1);
    expect(await engine.pullOnce(), SyncPullApplyResult.applied);

    final retained = (await journal.listDrafts(
      appUserId: _Fixture.scope.appUserId,
    )).single;
    expect(retained.syncMode, ContactDraftSyncMode.deviceOnly);
    expect(retained.channel, ContactChannel.videoCall);
    expect(retained.serverRevision, 2);
  });

  test('其他设备的私有草稿变化只恢复到同一创建者的草稿库', () async {
    final fixture = _Fixture();
    addTearDown(fixture.close);
    final transport = _QueueSyncTransport(
      const [],
      pullReplies: [
        SyncPullSucceeded(
          SyncPullBatch(
            changes: [
              SyncRemoteChange(
                changeType: 'draft.upserted',
                revisionNumber: 1,
                payload: _remoteDraftPayload(
                  draftId: 'remote-draft-1',
                  channel: 'voice_call',
                ),
              ),
            ],
            nextCursor: 'cursor-remote-draft-1',
          ),
        ),
      ],
    );
    final engine = fixture.engine(workerId: 'worker-1', transport: transport);

    expect(await engine.pullOnce(), SyncPullApplyResult.applied);

    final drafts = await ContactJournal(
      database: fixture.database,
      clock: fixture.clock,
      idGenerator: _SequenceIdGenerator(const []),
    ).listDrafts(appUserId: _Fixture.scope.appUserId);
    expect(drafts, hasLength(1));
    expect(drafts.single.draftId, 'remote-draft-1');
    expect(drafts.single.channel, ContactChannel.voiceCall);
    expect(drafts.single.serverRevision, 1);
    expect(drafts.single.isConflictCopy, isFalse);
  });

  test('离线分叉的远端草稿保留本机冲突副本而不做最后写入胜出', () async {
    final fixture = _Fixture();
    addTearDown(fixture.close);
    await fixture.saveDraft();
    final transport = _QueueSyncTransport(
      const [],
      pullReplies: [
        SyncPullSucceeded(
          SyncPullBatch(
            changes: [
              SyncRemoteChange(
                changeType: 'draft.upserted',
                revisionNumber: 1,
                payload: _remoteDraftPayload(
                  draftId: 'draft-1',
                  channel: 'instant_text',
                ),
              ),
            ],
            nextCursor: 'cursor-conflicting-draft',
          ),
        ),
      ],
    );
    final engine = fixture.engine(workerId: 'worker-1', transport: transport);

    expect(await engine.pullOnce(), SyncPullApplyResult.applied);

    final drafts = await ContactJournal(
      database: fixture.database,
      clock: fixture.clock,
      idGenerator: _SequenceIdGenerator(const []),
    ).listDrafts(appUserId: _Fixture.scope.appUserId);
    expect(drafts, hasLength(2));
    expect(
      drafts.singleWhere((draft) => draft.draftId == 'draft-1').channel,
      ContactChannel.instantText,
    );
    final conflict = drafts.singleWhere((draft) => draft.isConflictCopy);
    expect(conflict.conflictOfDraftId, 'draft-1');
    expect(conflict.channel, ContactChannel.videoCall);
    expect(conflict.syncMode, ContactDraftSyncMode.deviceOnly);
  });
}

final class _Fixture {
  _Fixture()
    : database = LocalDatabase(NativeDatabase.memory()),
      clock = _MutableClock(DateTime.utc(2030, 1, 8, 18, 30));

  final LocalDatabase database;
  final _MutableClock clock;

  static const scope = SyncScope(
    appUserId: 'app-user-1',
    workspaceId: 'personal-workspace-1',
    projectId: 'project-1',
  );

  Future<void> close() => database.close();

  Future<void> submitContact({String suffix = '1'}) async {
    final journal = ContactJournal(
      database: database,
      clock: clock,
      idGenerator: _SequenceIdGenerator([
        'contact-$suffix',
        'revision-$suffix',
        'command-$suffix',
      ]),
    );
    await journal.submitAnonymousContact(
      AnonymousContactSubmission(
        appUserId: scope.appUserId,
        workspaceId: scope.workspaceId,
        projectId: scope.projectId,
        questionnaireVersionId: 'questionnaire-v1',
        deviceId: 'device-1',
        occurredAtUtc: DateTime.utc(2030, 1, 8, 18),
        occurredTimeZone: 'America/Chicago',
        channel: ContactChannel.videoCall,
        location: const NotApplicableContactLocation(),
        reachCount: 2,
        interestLevel: 3,
      ),
    );
  }

  Future<void> saveDraft() async {
    final journal = ContactJournal(
      database: database,
      clock: clock,
      idGenerator: _SequenceIdGenerator(['draft-1']),
    );
    await journal.saveDraft(
      ContactDraftInput(
        deviceId: 'device-1',
        appUserId: scope.appUserId,
        workspaceId: scope.workspaceId,
        projectId: scope.projectId,
        questionnaireVersionId: 'questionnaire-v1',
        channel: ContactChannel.videoCall,
      ),
    );
  }

  SyncEngine engine({
    required String workerId,
    required SyncTransport transport,
    SyncJitter jitter = const FixedSyncJitter(0),
  }) {
    return SyncEngine(
      database: database,
      clock: clock,
      workerId: workerId,
      scope: scope,
      transport: transport,
      jitter: jitter,
    );
  }
}

final class _QueueSyncTransport implements SyncTransport {
  _QueueSyncTransport(
    this._replies, {
    List<SyncPullResult> pullReplies = const [],
  }) : _pullReplies = [...pullReplies];

  final List<SyncPushResult> _replies;
  final List<SyncPullResult> _pullReplies;
  final List<SyncCommand> commands = [];
  final List<String?> pullCursors = [];

  @override
  Future<void> close() async {}

  @override
  Future<SyncPullResult> pull({
    required SyncScope scope,
    required String? cursor,
    int limit = 100,
  }) async {
    pullCursors.add(cursor);
    if (_pullReplies.isNotEmpty) {
      return _pullReplies.removeAt(0);
    }
    return SyncPullSucceeded(
      SyncPullBatch(changes: const [], nextCursor: cursor),
    );
  }

  @override
  Future<SyncPushResult> push(SyncCommand command) async {
    commands.add(command);
    return _replies.removeAt(0);
  }
}

Map<String, Object?> _remotePayload({required String contactId}) {
  return {
    'contactId': contactId,
    'workspaceId': _Fixture.scope.workspaceId,
    'projectId': _Fixture.scope.projectId,
    'questionnaireVersionId': 'questionnaire-v1',
    'occurredAtUtc': '2030-01-08T18:00:00.000Z',
    'occurredTimeZone': 'America/Chicago',
    'firstSubmittedAtUtc': '2030-01-08T18:30:00.000Z',
    'channel': 'video_call',
    'channelDetail': null,
    'location': {'kind': 'not_applicable'},
    'reachCount': 2,
    'interestLevel': 3,
    'answers': <Object?>[],
  };
}

ContactConflictSnapshot _conflictSnapshot({required int reachCount}) =>
    ContactConflictSnapshot(
      occurredAtUtc: DateTime.utc(2030, 1, 8, 18),
      occurredTimeZone: 'America/Chicago',
      channel: ContactChannel.videoCall,
      channelDetail: null,
      location: const NotApplicableContactLocation(),
      reachCount: reachCount,
      interestLevel: 3,
      answers: const [],
    );

Map<String, Object?> _remoteRevisionPayload({
  required String contactId,
  required String revisionKind,
  required String reason,
  required String occurredAtUtc,
  required int reachCount,
}) {
  return {
    'contactId': contactId,
    'workspaceId': _Fixture.scope.workspaceId,
    'projectId': _Fixture.scope.projectId,
    'questionnaireVersionId': 'questionnaire-v1',
    'occurredAtUtc': occurredAtUtc,
    'occurredTimeZone': 'America/Chicago',
    'firstSubmittedAtUtc': '2030-01-08T18:30:00.000Z',
    'revisedAtUtc': revisionKind == 'voided'
        ? '2030-02-09T18:30:00.000Z'
        : '2030-02-08T18:30:00.000Z',
    'revisionKind': revisionKind,
    'reason': reason,
    'channel': 'voice_call',
    'channelDetail': null,
    'location': {'kind': 'not_applicable'},
    'reachCount': reachCount,
    'interestLevel': 4,
    'answers': <Object?>[],
  };
}

Map<String, Object?> _remoteDraftPayload({
  required String draftId,
  required String channel,
  String createdAtUtc = '2030-01-08T18:00:00.000Z',
  String updatedAtUtc = '2030-01-08T18:30:00.000Z',
}) {
  return {
    'draftId': draftId,
    'workspaceId': _Fixture.scope.workspaceId,
    'projectId': _Fixture.scope.projectId,
    'questionnaireVersionId': 'questionnaire-v1',
    'createdAtUtc': createdAtUtc,
    'updatedAtUtc': updatedAtUtc,
    'occurredAtUtc': null,
    'occurredTimeZone': null,
    'channel': channel,
    'channelDetail': null,
    'location': null,
    'reachCount': null,
    'interestLevel': null,
    'answers': <Object?>[],
    'serverRevision': 1,
    'sourceDeviceId': 'device-other',
  };
}

final class _BlockingSyncTransport implements SyncTransport {
  _BlockingSyncTransport(this.reply);

  final Future<SyncPushResult> reply;
  final commandReceived = Completer<void>();

  @override
  Future<void> close() async {}

  @override
  Future<SyncPullResult> pull({
    required SyncScope scope,
    required String? cursor,
    int limit = 100,
  }) async {
    return SyncPullSucceeded(
      SyncPullBatch(changes: const [], nextCursor: cursor),
    );
  }

  @override
  Future<SyncPushResult> push(SyncCommand command) {
    commandReceived.complete();
    return reply;
  }
}

final class _BatchSyncTransport implements SyncTransport, SyncBatchTransport {
  _BatchSyncTransport(this._batchReplies);

  final List<List<SyncCommandPushOutcome>> _batchReplies;
  final List<List<SyncCommand>> batches = [];

  @override
  Future<void> close() async {}

  @override
  Future<SyncPullResult> pull({
    required SyncScope scope,
    required String? cursor,
    int limit = 100,
  }) async =>
      SyncPullSucceeded(SyncPullBatch(changes: const [], nextCursor: cursor));

  @override
  Future<SyncPushResult> push(SyncCommand command) {
    throw UnimplementedError('batch transport must use pushBatch');
  }

  @override
  Future<List<SyncCommandPushOutcome>> pushBatch(
    List<SyncCommand> commands,
  ) async {
    batches.add(commands);
    return _batchReplies.removeAt(0);
  }
}

final class _MutableClock implements AppClock {
  _MutableClock(this.value);

  DateTime value;

  void advance(Duration duration) {
    value = value.add(duration);
  }

  @override
  DateTime now() => value;
}

final class _SequenceIdGenerator implements IdGenerator {
  _SequenceIdGenerator(this.values);

  final List<String> values;
  var _index = 0;

  @override
  String next() => values[_index++];
}
