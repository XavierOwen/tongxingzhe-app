import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tongxingzhe_app/app_session/http_session_context_gateway.dart';
import 'package:tongxingzhe_app/app_session/session_context_gateway.dart';
import 'package:tongxingzhe_app/identity/identity_session.dart';

void main() {
  const accessToken = IdentityAccessToken(
    value: 'synthetic-access-token',
    expiresAt: null,
  );

  test('只把 bearer token 发送到自有上下文端点', () async {
    late http.Request captured;
    final gateway = HttpSessionContextGateway(
      baseUri: Uri.parse('https://api.example.test'),
      client: MockClient((request) async {
        captured = request;
        return http.Response.bytes(
          utf8.encode(_validResponse),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    addTearDown(gateway.close);

    final result = await gateway.resolve(accessToken);

    expect(result, isA<SessionContextSuccess>());
    final context = (result as SessionContextSuccess).context;
    expect(context.appUserId, '11111111-1111-4111-8111-111111111111');
    expect(context.workspace.kind, WorkspaceKind.personal);
    expect(context.project.name, '我的推广项目');
    expect(context.questionnaireVersion.versionNumber, 1);
    expect(context.capabilities, {'record_contact'});
    expect(captured.url.path, '/v1/session/context');
    expect(captured.headers['authorization'], 'Bearer synthetic-access-token');
  });

  test('无效内部 ID 使整个响应失败', () async {
    final gateway = HttpSessionContextGateway(
      baseUri: Uri.parse('https://api.example.test'),
      client: MockClient((_) async {
        return http.Response.bytes(
          utf8.encode(
            _validResponse.replaceFirst(
              '11111111-1111-4111-8111-111111111111',
              'external-subject',
            ),
          ),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    addTearDown(gateway.close);

    final result = await gateway.resolve(accessToken);

    expect(result, isA<SessionContextRejected>());
    expect(
      (result as SessionContextRejected).code,
      SessionContextFailureCode.invalidResponse,
    );
  });

  test('401 不保留上一次可信上下文', () async {
    final gateway = HttpSessionContextGateway(
      baseUri: Uri.parse('https://api.example.test'),
      client: MockClient((_) async => http.Response('{}', 401)),
    );
    addTearDown(gateway.close);

    final result = await gateway.resolve(accessToken);

    expect(result, isA<SessionContextRejected>());
    expect(
      (result as SessionContextRejected).code,
      SessionContextFailureCode.unauthorized,
    );
  });

  test('非本机 Backend 拒绝明文 HTTP', () {
    expect(
      () => HttpSessionContextGateway(
        baseUri: Uri.parse('http://api.example.test'),
        client: MockClient((_) async => http.Response('{}', 200)),
      ),
      throwsFormatException,
    );
  });
}

const _validResponse = '''
{
  "app_user_id": "11111111-1111-4111-8111-111111111111",
  "current_context": {
    "workspace": {
      "workspace_id": "22222222-2222-4222-8222-222222222222",
      "kind": "personal",
      "name": "个人空间"
    },
    "project": {
      "project_id": "33333333-3333-4333-8333-333333333333",
      "name": "我的推广项目"
    },
    "questionnaire_version": {
      "questionnaire_version_id": "44444444-4444-4444-8444-444444444444",
      "version_number": 1
    }
  },
  "capabilities": ["record_contact"]
}
''';
