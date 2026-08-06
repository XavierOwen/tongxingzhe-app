import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tongxingzhe_app/identity/identity_session.dart';
import 'package:tongxingzhe_app/targets/http_promotion_target_gateway.dart';
import 'package:tongxingzhe_app/targets/promotion_target.dart';

import '../support/fake_identity_session.dart';

void main() {
  test(
    'creates a target with bearer auth and a server-generated target id',
    () async {
      final gateway = HttpPromotionTargetGateway(
        baseUri: Uri.parse('https://backend.example.test'),
        identitySession: _signedInIdentity(),
        client: MockClient((request) async {
          expect(request.method, 'POST');
          expect(request.url.path, '/v1/promotion-targets');
          expect(
            request.headers['authorization'],
            'Bearer test-only-access-token',
          );
          expect(jsonDecode(request.body), {
            'target_type': 'institution',
            'display_name': '社区中心',
            'phone': null,
            'email': 'contact@example.test',
            'request_id': 'request-1',
          });
          return http.Response.bytes(
            utf8.encode(
              jsonEncode({
                'target': {
                  'target_id': '44444444-4444-4444-8444-444444444444',
                  'target_type': 'institution',
                  'display_name': '社区中心',
                  'phone': null,
                  'email': 'contact@example.test',
                  'created_at': '2026-08-06T12:00:00Z',
                },
              }),
            ),
            201,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );

      final result = await gateway.create(
        type: PromotionTargetType.institution,
        displayName: '社区中心',
        phone: null,
        email: 'contact@example.test',
        requestId: 'request-1',
      );

      final target =
          (result as PromotionTargetSuccess<PromotionTargetProfile>).value;
      expect(target.id, '44444444-4444-4444-8444-444444444444');
      expect(target.type, PromotionTargetType.institution);
    },
  );

  test('loads only the assigned profiles returned by the server', () async {
    final gateway = HttpPromotionTargetGateway(
      baseUri: Uri.parse('https://backend.example.test'),
      identitySession: _signedInIdentity(),
      client: MockClient((request) async {
        expect(request.method, 'GET');
        return http.Response.bytes(
          utf8.encode(
            jsonEncode({
              'targets': [
                {
                  'target_id': '44444444-4444-4444-8444-444444444444',
                  'target_type': 'person',
                  'display_name': '王小明',
                  'phone': null,
                  'email': null,
                  'created_at': '2026-08-06T12:00:00Z',
                },
              ],
            }),
          ),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );

    final result = await gateway.loadAssigned();
    final targets =
        (result as PromotionTargetSuccess<List<PromotionTargetProfile>>).value;
    expect(targets.single.displayName, '王小明');
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
