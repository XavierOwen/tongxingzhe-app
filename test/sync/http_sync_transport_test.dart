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
