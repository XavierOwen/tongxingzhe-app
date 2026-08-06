import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tongxingzhe_app/identity/identity_session.dart';
import 'package:tongxingzhe_app/sync/http_sync_transport.dart';
import 'package:tongxingzhe_app/sync/sync_models.dart';

import '../support/fake_identity_session.dart';

void main() {
  test('发送 bearer command envelope 并解析 accepted cursor', () async {
    final identity = _signedInIdentity();
    var requestBody = <String, Object?>{};
    final transport = HttpSyncTransport(
      baseUri: Uri.parse('https://backend.example.test'),
      identitySession: identity,
      client: MockClient((request) async {
        expect(request.url.path, '/v1/sync/commands');
        expect(
          request.headers['authorization'],
          'Bearer test-only-access-token',
        );
        requestBody = jsonDecode(request.body) as Map<String, Object?>;
        return http.Response(
          jsonEncode({'result': 'accepted', 'server_cursor': 'opaque-1'}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    final result = await transport.push(_command);

    expect(result, isA<SyncPushAccepted>());
    expect((result as SyncPushAccepted).serverCursor, 'opaque-1');
    expect(requestBody['command_id'], 'command-1');
    expect(requestBody['type'], 'contact.submit.v1');
    expect(requestBody['typed_payload'], {'reach_count': 2});
    expect(requestBody.containsKey('app_user_id'), isFalse);
  });

  test('429 使用可信 Retry-After 并返回可重试结果', () async {
    final transport = HttpSyncTransport(
      baseUri: Uri.parse('https://backend.example.test'),
      identitySession: _signedInIdentity(),
      client: MockClient(
        (_) async => http.Response('{}', 429, headers: {'retry-after': '45'}),
      ),
    );

    final result = await transport.push(_command);

    expect(result, isA<SyncPushRetryable>());
    expect((result as SyncPushRetryable).failureCode, 'rate_limited');
    expect(result.retryAfter, const Duration(seconds: 45));
  });

  test('409 解析经过授权的跨设备冲突详情', () async {
    final transport = HttpSyncTransport(
      baseUri: Uri.parse('https://backend.example.test'),
      identitySession: _signedInIdentity(),
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'result': 'conflict',
            'error': {'code': 'contact_revision_conflict'},
            'conflict': {
              'conflict_id': 'conflict-1',
              'contact_id': 'contact-1',
              'base_revision': 1,
              'current_revision': 2,
              'conflicting_fields': ['reachCount'],
              'questionnaire_version_id': 'questionnaire-v1',
              'current_revision_kind': 'corrected',
              'current_revised_at_utc': '2030-01-08T19:00:00.000Z',
              'current_reason': '另一台设备修正人数',
              'current_snapshot': _conflictSnapshot(reachCount: 4),
              'proposed_snapshot': _conflictSnapshot(reachCount: 3),
            },
          }),
          409,
          headers: {'content-type': 'application/json'},
        ),
      ),
    );

    final result = await transport.push(_command);

    expect(result, isA<SyncPushConflict>());
    final conflict = (result as SyncPushConflict).conflict!;
    expect(result.failureCode, 'contact_revision_conflict');
    expect(conflict.conflictingFields, ['reachCount']);
    expect(conflict.currentSnapshot.reachCount, 4);
    expect(conflict.proposedSnapshot.reachCount, 3);
  });

  test('过大 Retry-After 按本地一小时上限处理', () async {
    final transport = HttpSyncTransport(
      baseUri: Uri.parse('https://backend.example.test'),
      identitySession: _signedInIdentity(),
      client: MockClient(
        (_) async => http.Response('{}', 429, headers: {'retry-after': '7200'}),
      ),
    );

    final result = await transport.push(_command);

    expect(result, isA<SyncPushRetryable>());
    expect((result as SyncPushRetryable).retryAfter, const Duration(hours: 1));
  });

  test('批量结果保留 command ID，不依赖服务端返回顺序', () async {
    final transport = HttpSyncTransport(
      baseUri: Uri.parse('https://backend.example.test'),
      identitySession: _signedInIdentity(),
      client: MockClient((request) async {
        expect(request.url.path, '/v1/sync/commands/batch');
        final body = jsonDecode(request.body) as Map<String, Object?>;
        expect(body['commands'], hasLength(2));
        return http.Response(
          jsonEncode({
            'results': [
              {
                'command_id': 'command-2',
                'result': 'accepted',
                'server_cursor': 'opaque-2',
              },
              {
                'command_id': 'command-1',
                'result': 'conflict',
                'error': {'code': 'stale_revision'},
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    final results = await transport.pushBatch([_command, _secondCommand]);

    expect(results.map((outcome) => outcome.commandId), [
      'command-2',
      'command-1',
    ]);
    expect(results.first.result, isA<SyncPushAccepted>());
    expect(results.last.result, isA<SyncPushConflict>());
    expect(
      (results.last.result as SyncPushConflict).failureCode,
      'stale_revision',
    );
  });

  test('无效 Retry-After 不覆盖本地指数退避', () async {
    final transport = HttpSyncTransport(
      baseUri: Uri.parse('https://backend.example.test'),
      identitySession: _signedInIdentity(),
      client: MockClient(
        (_) async =>
            http.Response('{}', 429, headers: {'retry-after': 'not-a-delay'}),
      ),
    );

    final result = await transport.push(_command);

    expect(result, isA<SyncPushRetryable>());
    expect((result as SyncPushRetryable).retryAfter, isNull);
  });

  test('超时和 5xx 保留可重试分类', () async {
    final timedOut = HttpSyncTransport(
      baseUri: Uri.parse('https://backend.example.test'),
      identitySession: _signedInIdentity(),
      timeout: const Duration(milliseconds: 1),
      client: MockClient((_) async {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        return http.Response('{}', 200);
      }),
    );
    final unavailable = HttpSyncTransport(
      baseUri: Uri.parse('https://backend.example.test'),
      identitySession: _signedInIdentity(),
      client: MockClient(
        (_) async => http.Response('{}', 503, headers: {'retry-after': '7200'}),
      ),
    );

    final timeoutResult = await timedOut.push(_command);
    final unavailableResult = await unavailable.push(_command);

    expect(timeoutResult, isA<SyncPushRetryable>());
    expect((timeoutResult as SyncPushRetryable).failureCode, 'network_timeout');
    expect(unavailableResult, isA<SyncPushRetryable>());
    expect(
      (unavailableResult as SyncPushRetryable).retryAfter,
      const Duration(hours: 1),
    );
  });

  test('403 转成永久 forbidden，身份失败不发送 HTTP', () async {
    var requestCount = 0;
    final forbidden = HttpSyncTransport(
      baseUri: Uri.parse('https://backend.example.test'),
      identitySession: _signedInIdentity(),
      client: MockClient((_) async {
        requestCount++;
        return http.Response('{}', 403);
      }),
    );
    final forbiddenResult = await forbidden.push(_command);
    expect(forbiddenResult, isA<SyncPushPermanentFailure>());
    expect(
      (forbiddenResult as SyncPushPermanentFailure).failureCode,
      'forbidden',
    );

    final identity = _signedInIdentity()
      ..rejectNextWith = const IdentityFailure(
        code: IdentityFailureCode.networkUnavailable,
      );
    final unavailable = HttpSyncTransport(
      baseUri: Uri.parse('https://backend.example.test'),
      identitySession: identity,
      client: MockClient((_) async {
        requestCount++;
        return http.Response('{}', 200);
      }),
    );
    final unavailableResult = await unavailable.push(_command);
    expect(unavailableResult, isA<SyncPushRetryable>());
    expect(requestCount, 1);
  });

  test('拉取时传递不透明 cursor 并解析远端变化', () async {
    final transport = HttpSyncTransport(
      baseUri: Uri.parse('https://backend.example.test'),
      identitySession: _signedInIdentity(),
      client: MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/v1/sync/changes');
        expect(request.url.queryParameters, {
          'workspace_id': 'workspace-1',
          'project_id': 'project-1',
          'limit': '25',
          'cursor': 'opaque-before',
        });
        expect(
          request.headers['authorization'],
          'Bearer test-only-access-token',
        );
        return http.Response(
          jsonEncode({
            'changes': [
              {
                'change_type': 'contact.submitted',
                'revision_number': 1,
                'payload': {'contactId': 'contact-remote-1'},
              },
            ],
            'next_cursor': 'opaque-after',
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    final result = await transport.pull(
      scope: const SyncScope(
        appUserId: 'app-user-1',
        workspaceId: 'workspace-1',
        projectId: 'project-1',
      ),
      cursor: 'opaque-before',
      limit: 25,
    );

    expect(result, isA<SyncPullSucceeded>());
    final batch = (result as SyncPullSucceeded).batch;
    expect(batch.nextCursor, 'opaque-after');
    expect(batch.changes, hasLength(1));
    expect(batch.changes.single.changeType, 'contact.submitted');
    expect(batch.changes.single.payload['contactId'], 'contact-remote-1');
  });

  test('无效拉取响应不能被当成成功 batch', () async {
    final transport = HttpSyncTransport(
      baseUri: Uri.parse('https://backend.example.test'),
      identitySession: _signedInIdentity(),
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'changes': [
              {
                'change_type': 'contact.submitted',
                'revision_number': 'not-an-integer',
                'payload': <String, Object?>{},
              },
            ],
            'next_cursor': 'opaque-after',
          }),
          200,
        ),
      ),
    );

    final result = await transport.pull(
      scope: const SyncScope(
        appUserId: 'app-user-1',
        workspaceId: 'workspace-1',
        projectId: 'project-1',
      ),
      cursor: null,
    );

    expect(result, isA<SyncPullRetryable>());
    expect(
      (result as SyncPullRetryable).failureCode,
      'invalid_server_response',
    );
  });

  test('Backend 拒绝的 cursor 保留稳定永久失败码', () async {
    final transport = HttpSyncTransport(
      baseUri: Uri.parse('https://backend.example.test'),
      identitySession: _signedInIdentity(),
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'error': {'code': 'invalid_cursor'},
          }),
          400,
          headers: {'content-type': 'application/json'},
        ),
      ),
    );

    final result = await transport.pull(
      scope: const SyncScope(
        appUserId: 'app-user-1',
        workspaceId: 'workspace-1',
        projectId: 'project-1',
      ),
      cursor: 'cursor-from-another-scope',
    );

    expect(result, isA<SyncPullPermanentFailure>());
    expect((result as SyncPullPermanentFailure).failureCode, 'invalid_cursor');
  });
}

FakeIdentitySession _signedInIdentity() {
  return FakeIdentitySession(
    initial: IdentitySnapshot(
      stage: IdentityStage.signedIn,
      principal: const IdentityPrincipal(
        externalSubject: 'external-subject',
        email: 'person@example.test',
      ),
      expiresAt: DateTime.utc(2030, 1, 2, 4, 4),
    ),
  );
}

const _command = SyncCommand(
  protocolVersion: 1,
  commandId: 'command-1',
  deviceId: 'device-1',
  aggregateId: 'contact-1',
  baseRevision: 0,
  commandType: 'contact.submit.v1',
  payload: {'reach_count': 2},
);

const _secondCommand = SyncCommand(
  protocolVersion: 1,
  commandId: 'command-2',
  deviceId: 'device-1',
  aggregateId: 'contact-2',
  baseRevision: 0,
  commandType: 'contact.submit.v1',
  payload: {'reach_count': 3},
);

Map<String, Object?> _conflictSnapshot({required int reachCount}) => {
  'occurredAtUtc': '2030-01-08T18:00:00.000Z',
  'occurredTimeZone': 'America/Chicago',
  'channel': 'video_call',
  'channelDetail': null,
  'location': {'kind': 'not_applicable'},
  'reachCount': reachCount,
  'interestLevel': 3,
  'answers': <Object?>[],
};
