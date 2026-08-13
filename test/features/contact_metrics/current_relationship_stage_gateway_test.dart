import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tongxingzhe_app/features/contact_metrics/current_relationship_stage.dart';
import 'package:tongxingzhe_app/features/contact_metrics/current_relationship_stage_gateway.dart';
import 'package:tongxingzhe_app/features/contact_metrics/metric_contract.dart';
import 'package:tongxingzhe_app/identity/identity_session.dart';

import '../../support/fake_identity_session.dart';

void main() {
  final scope = CurrentRelationshipStageScope(
    appUserId: 'user-1',
    workspaceId: 'workspace-1',
    projectId: 'project-1',
  );

  test(
    'GET current relationship snapshot strictly parses non-PII rows',
    () async {
      final identity = _signedInIdentity();
      final gateway = HttpCurrentRelationshipStageGateway(
        baseUri: Uri.parse('https://backend.example.test'),
        identitySession: identity,
        client: MockClient((request) async {
          expect(request.method, 'GET');
          expect(request.url.path, '/v1/personal/current-relationship-stage');
          expect(
            request.headers['authorization'],
            'Bearer test-only-access-token',
          );
          return _jsonResponse(_body(scope));
        }),
      );
      addTearDown(gateway.close);

      final result = await gateway.load(scope: scope);
      expect(result, isA<CurrentRelationshipStageGatewaySuccess>());
      final snapshot =
          (result as CurrentRelationshipStageGatewaySuccess).snapshot;
      expect(snapshot.rows.single.targetId, 'target-1');
      expect(snapshot.rows.single.stage, 3);
      expect(snapshot.coverage.totalCount, 1);
      expect(snapshot.freshness.status, MetricFreshnessStatus.fresh);
    },
  );

  test('401 refreshes once and succeeds with the refreshed bearer', () async {
    final identity = _signedInIdentity();
    var calls = 0;
    final gateway = HttpCurrentRelationshipStageGateway(
      baseUri: Uri.parse('https://backend.example.test'),
      identitySession: identity,
      client: MockClient((request) async {
        calls += 1;
        if (calls == 1) return http.Response('', 401);
        return _jsonResponse(_body(scope));
      }),
    );
    addTearDown(gateway.close);

    final result = await gateway.load(scope: scope);
    expect(result, isA<CurrentRelationshipStageGatewaySuccess>());
    expect(identity.accessTokenForceRefreshValues, [false, true]);
  });

  test('extra keys including PII are rejected as invalid response', () async {
    final body = _body(scope);
    (body['snapshot'] as Map<String, Object?>)['display_name'] =
        'must-not-cross-boundary';
    final gateway = HttpCurrentRelationshipStageGateway(
      baseUri: Uri.parse('https://backend.example.test'),
      identitySession: _signedInIdentity(),
      client: MockClient((request) async => _jsonResponse(body)),
    );
    addTearDown(gateway.close);

    final result = await gateway.load(scope: scope);
    expect(
      result,
      const TypeMatcher<CurrentRelationshipStageGatewayRejected>(),
    );
    expect(
      (result as CurrentRelationshipStageGatewayRejected).code,
      CurrentRelationshipStageGatewayFailureCode.invalidResponse,
    );
  });

  test('known empty coverage is represented without inventing rows', () async {
    final body = _body(scope);
    (body['snapshot'] as Map<String, Object?>)
      ..['relationships'] = <Object?>[]
      ..['coverage'] = {'total': 0, 'pending': 0};
    final gateway = HttpCurrentRelationshipStageGateway(
      baseUri: Uri.parse('https://backend.example.test'),
      identitySession: _signedInIdentity(),
      client: MockClient((request) async => _jsonResponse(body)),
    );
    addTearDown(gateway.close);

    final result = await gateway.load(scope: scope);
    final snapshot =
        (result as CurrentRelationshipStageGatewaySuccess).snapshot;
    expect(snapshot.rows, isEmpty);
    expect(snapshot.coverage.totalCount, 0);
    expect(snapshot.coverage.pendingCount, 0);
  });
}

FakeIdentitySession _signedInIdentity() => FakeIdentitySession(
  initial: IdentitySnapshot(
    stage: IdentityStage.signedIn,
    principal: const IdentityPrincipal(
      externalSubject: 'subject-1',
      email: 'user@example.test',
    ),
  ),
);

http.Response _jsonResponse(Map<String, Object?> body) => http.Response(
  jsonEncode(body),
  200,
  headers: const {'content-type': 'application/json; charset=utf-8'},
);

Map<String, Object?> _body(CurrentRelationshipStageScope scope) => {
  'snapshot': {
    'contract_id': 'current_relationship_stage_distribution@1',
    'statistical_unit': 'targetProjectRelationship',
    'project_key': scope.projectId,
    'snapshot_as_of_utc': '2030-01-15T12:00:00Z',
    'source_cutoff_utc': '2030-01-15T11:59:00Z',
    'authorized_at_utc': '2030-01-15T11:58:00Z',
    'coverage': {'total': 1, 'pending': 0},
    'relationships': [
      {
        'target_key': 'target-1',
        'stage': 3,
        'revision': 2,
        'updated_at_utc': '2030-01-15T11:00:00Z',
      },
    ],
  },
};
