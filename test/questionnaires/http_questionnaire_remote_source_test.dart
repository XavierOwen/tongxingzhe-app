import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tongxingzhe_app/identity/identity_session.dart';
import 'package:tongxingzhe_app/questionnaires/http_questionnaire_remote_source.dart';

import '../support/fake_identity_session.dart';

void main() {
  final fixture =
      jsonDecode(
            File(
              'fixtures/questionnaire/questionnaire-contract-v1.json',
            ).readAsStringSync(),
          )
          as Map<String, Object?>;

  test('带身份读取指定发布版本且不把项目权限放进客户端参数', () async {
    late http.Request captured;
    final source = HttpQuestionnaireRemoteSource(
      baseUri: Uri.parse('https://api.example.test'),
      identitySession: _signedInIdentity(),
      client: MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({'questionnaire': fixture['questionnaire']}),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );

    final version = await source.fetchPublishedVersion(
      '44444444-4444-4444-8444-444444444444',
    );

    expect(version, isNotNull);
    expect(
      captured.url.path,
      '/v1/questionnaire-versions/44444444-4444-4444-8444-444444444444',
    );
    expect(captured.headers['authorization'], 'Bearer test-only-access-token');
    expect(captured.url.queryParameters, isEmpty);
  });

  test('无效或未授权响应不覆盖为一个空问卷', () async {
    final source = HttpQuestionnaireRemoteSource(
      baseUri: Uri.parse('https://api.example.test'),
      identitySession: _signedInIdentity(),
      client: MockClient((_) async => http.Response('{}', 403)),
    );

    expect(
      await source.fetchPublishedVersion(
        '44444444-4444-4444-8444-444444444444',
      ),
      isNull,
    );
  });
}

FakeIdentitySession _signedInIdentity() => FakeIdentitySession(
  initial: const IdentitySnapshot(
    stage: IdentityStage.signedIn,
    principal: IdentityPrincipal(
      externalSubject: 'test-subject',
      email: 'test@example.test',
    ),
  ),
);
