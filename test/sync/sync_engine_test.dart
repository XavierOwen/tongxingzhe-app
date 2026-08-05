import 'dart:async';

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

  SyncEngine engine({
    required String workerId,
    required SyncTransport transport,
  }) {
    return SyncEngine(
      database: database,
      clock: clock,
      workerId: workerId,
      scope: scope,
      transport: transport,
      jitter: const FixedSyncJitter(0),
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
