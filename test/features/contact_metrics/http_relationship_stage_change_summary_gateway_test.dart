import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tongxingzhe_app/features/contact_metrics/http_relationship_stage_change_summary_gateway.dart';
import 'package:tongxingzhe_app/features/contact_metrics/relationship_stage_change_summary.dart';
import 'package:tongxingzhe_app/identity/identity_session.dart';

import '../../support/fake_identity_session.dart';

void main() {
  test('GET sends exact UTC period and parses typed summary', () async {
    late http.Request captured;
    final gateway = _gateway((request) async {
      captured = request;
      return _json(_readyBody());
    });
    addTearDown(gateway.close);

    final result = await gateway.load(
      projectId: _projectId,
      fromUtc: _fromUtc,
      untilUtc: _untilUtc,
    );

    expect(captured.method, 'GET');
    expect(captured.url.path, '/v1/personal/relationship-stage-change-summary');
    expect(captured.url.queryParametersAll, {
      'from_utc': [_fromText],
      'until_utc': [_untilText],
    });
    expect(captured.body, isEmpty);
    expect(captured.headers['authorization'], 'Bearer test-only-access-token');
    final success =
        result as PersonalRelationshipStageChangeSummaryGatewaySuccess;
    expect(success.value.projectId, _projectId);
    expect(success.value.eventCount, 5);
    expect(success.value.distinctRelationshipCount, 4);
    expect(success.value.upwardCount, 3);
    expect(success.value.downwardCount, 2);
    expect(success.value.dataCutoffUtc, _cutoffUtc);
    expect(success.value.authorizedAtUtc, _cutoffUtc);
    expect(success.value.retrievedAtUtc, _receivedAtUtc);
  });

  test('empty response parses as zero summary', () async {
    final gateway = _gateway(
      (_) async => _json(
        _readyBody(
          eventCount: 0,
          distinctRelationshipCount: 0,
          upwardCount: 0,
          downwardCount: 0,
        ),
      ),
    );
    addTearDown(gateway.close);

    final result = await _load(gateway);
    final value =
        (result as PersonalRelationshipStageChangeSummaryGatewaySuccess).value;
    expect(value.eventCount, 0);
    expect(value.distinctRelationshipCount, 0);
    expect(value.upwardCount, 0);
    expect(value.downwardCount, 0);
  });

  test('401 refreshes bearer and retries exactly once', () async {
    final identity = _identity();
    var calls = 0;
    final gateway = HttpPersonalRelationshipStageChangeSummaryGateway(
      baseUri: Uri.parse('https://backend.example.test'),
      identitySession: identity,
      client: MockClient((_) async {
        calls += 1;
        return calls == 1 ? http.Response('', 401) : _json(_readyBody());
      }),
      now: () => _receivedAtUtc,
    );
    addTearDown(gateway.close);

    expect(
      await _load(gateway),
      isA<PersonalRelationshipStageChangeSummaryGatewaySuccess>(),
    );
    expect(calls, 2);
    expect(identity.accessTokenForceRefreshValues, [false, true]);
  });

  test('second 401 stops without a third request', () async {
    final identity = _identity();
    var calls = 0;
    final gateway = HttpPersonalRelationshipStageChangeSummaryGateway(
      baseUri: Uri.parse('https://backend.example.test'),
      identitySession: identity,
      client: MockClient((_) async {
        calls += 1;
        return http.Response('', 401);
      }),
    );
    addTearDown(gateway.close);

    expect(
      _rejectedCode(await _load(gateway)),
      PersonalRelationshipStageChangeSummaryFailureCode.unauthorized,
    );
    expect(calls, 2);
    expect(identity.accessTokenForceRefreshValues, [false, true]);
  });

  test('invalid project and period stop before token or HTTP access', () async {
    final identity = _identity();
    var calls = 0;
    final gateway = HttpPersonalRelationshipStageChangeSummaryGateway(
      baseUri: Uri.parse('https://backend.example.test'),
      identitySession: identity,
      client: MockClient((_) async {
        calls += 1;
        return _json(_readyBody());
      }),
    );
    addTearDown(gateway.close);

    final results = [
      await gateway.load(
        projectId: 'not-a-uuid',
        fromUtc: _fromUtc,
        untilUtc: _untilUtc,
      ),
      await gateway.load(
        projectId: _projectId,
        fromUtc: DateTime(2030),
        untilUtc: _untilUtc,
      ),
      await gateway.load(
        projectId: _projectId,
        fromUtc: _untilUtc,
        untilUtc: _fromUtc,
      ),
      await gateway.load(
        projectId: _projectId,
        fromUtc: DateTime.utc(2030, 1, 1, 0, 0, 0, 0, 1),
        untilUtc: _untilUtc,
      ),
    ];
    for (final result in results) {
      expect(
        _rejectedCode(result),
        PersonalRelationshipStageChangeSummaryFailureCode.invalidRequest,
      );
    }
    expect(identity.accessTokenForceRefreshValues, isEmpty);
    expect(calls, 0);
  });

  test(
    'status, identity, and transport failures use stable categories',
    () async {
      for (final entry
          in <(int, PersonalRelationshipStageChangeSummaryFailureCode)>[
            (
              400,
              PersonalRelationshipStageChangeSummaryFailureCode.invalidRequest,
            ),
            (403, PersonalRelationshipStageChangeSummaryFailureCode.forbidden),
            (
              408,
              PersonalRelationshipStageChangeSummaryFailureCode
                  .networkUnavailable,
            ),
            (
              404,
              PersonalRelationshipStageChangeSummaryFailureCode.serverRejected,
            ),
            (
              503,
              PersonalRelationshipStageChangeSummaryFailureCode
                  .serviceUnavailable,
            ),
          ]) {
        final gateway = _gateway((_) async => http.Response('', entry.$1));
        expect(_rejectedCode(await _load(gateway)), entry.$2);
        await gateway.close();
      }

      final networkGateway = _gateway((request) async {
        throw http.ClientException('offline', request.url);
      });
      expect(
        _rejectedCode(await _load(networkGateway)),
        PersonalRelationshipStageChangeSummaryFailureCode.networkUnavailable,
      );
      await networkGateway.close();

      final identity = _identity()
        ..rejectNextAccessTokenWith = const IdentityFailure(
          code: IdentityFailureCode.notConfigured,
        );
      final identityGateway = HttpPersonalRelationshipStageChangeSummaryGateway(
        baseUri: Uri.parse('https://backend.example.test'),
        identitySession: identity,
        client: MockClient((_) async => _json(_readyBody())),
      );
      expect(
        _rejectedCode(await _load(identityGateway)),
        PersonalRelationshipStageChangeSummaryFailureCode.notConfigured,
      );
      await identityGateway.close();
    },
  );

  test('exact keys and contract identity reject response drift', () async {
    final wrongEnvelope = <Map<String, Object?>>[
      {..._readyBody(), 'extra': true},
      {
        'result': {..._result(_readyBody()), 'email': 'must-not-cross'},
      },
    ];
    final missingValue = _mutableReady();
    _value(missingValue).remove('downward_count');
    final wrongContract = _mutableReady();
    _result(wrongContract)['contract_id'] = 'other_v1';
    final wrongBasis = _mutableReady();
    _result(wrongBasis)['time_basis'] = 'actualOccurrenceUtc';
    final wrongProject = _mutableReady();
    _result(wrongProject)['project_id'] = _otherProjectId;
    final wrongPeriod = _mutableReady();
    _period(wrongPeriod)['until_utc'] = '2030-01-09T00:00:00.000Z';
    final offsetPeriod = _mutableReady();
    _period(offsetPeriod)['from_utc'] = '2029-12-31T18:00:00.000-06:00';

    for (final body in [
      ...wrongEnvelope,
      missingValue,
      wrongContract,
      wrongBasis,
      wrongProject,
      wrongPeriod,
      offsetPeriod,
    ]) {
      final gateway = _gateway((_) async => _json(body));
      expect(
        _rejectedCode(await _load(gateway)),
        PersonalRelationshipStageChangeSummaryFailureCode.invalidResponse,
      );
      await gateway.close();
    }
  });

  test(
    'safe integer, cutoff, period, and count invariants fail closed',
    () async {
      final cases = <Map<String, Object?>>[];
      final negative = _mutableReady();
      _value(negative)['event_count'] = -1;
      cases.add(negative);
      final unsafe = _mutableReady();
      _value(unsafe)['event_count'] = 9007199254740992;
      cases.add(unsafe);
      final distinctTooLarge = _mutableReady();
      _value(distinctTooLarge)['distinct_relationship_count'] = 6;
      cases.add(distinctTooLarge);
      final directionMismatch = _mutableReady();
      _value(directionMismatch)['upward_count'] = 4;
      cases.add(directionMismatch);
      final mismatch = _mutableReady();
      _result(mismatch)['authorized_at_utc'] = '2030-01-08T00:00:01.000Z';
      cases.add(mismatch);
      final future = _mutableReady();
      _result(future)['data_cutoff_utc'] = '2030-01-08T00:00:01.000Z';
      cases.add(future);
      final futurePair = _mutableReady();
      _result(futurePair)['data_cutoff_utc'] = '2030-01-08T02:00:01.000Z';
      _result(futurePair)['authorized_at_utc'] = '2030-01-08T02:00:01.000Z';
      cases.add(futurePair);

      for (final body in cases) {
        final gateway = _gateway((_) async => _json(body));
        expect(
          _rejectedCode(await _load(gateway)),
          PersonalRelationshipStageChangeSummaryFailureCode.invalidResponse,
        );
        await gateway.close();
      }
    },
  );

  test(
    'malformed JSON, invalid transport URI, deferred, and close fail safely',
    () async {
      final malformed = _gateway((_) async => http.Response('{', 200));
      expect(
        _rejectedCode(await _load(malformed)),
        PersonalRelationshipStageChangeSummaryFailureCode.invalidResponse,
      );
      await malformed.close();

      expect(
        () => HttpPersonalRelationshipStageChangeSummaryGateway(
          baseUri: Uri.parse('http://backend.example.test'),
          identitySession: _identity(),
          client: MockClient((_) async => _json(_readyBody())),
        ),
        throwsArgumentError,
      );

      const deferred = DeferredPersonalRelationshipStageChangeSummaryGateway();
      expect(
        _rejectedCode(await _load(deferred)),
        PersonalRelationshipStageChangeSummaryFailureCode.notConfigured,
      );
      await deferred.close();
    },
  );
}

Future<PersonalRelationshipStageChangeSummaryGatewayResult> _load(
  PersonalRelationshipStageChangeSummaryGateway gateway,
) =>
    gateway.load(projectId: _projectId, fromUtc: _fromUtc, untilUtc: _untilUtc);

PersonalRelationshipStageChangeSummaryFailureCode _rejectedCode(
  PersonalRelationshipStageChangeSummaryGatewayResult result,
) => (result as PersonalRelationshipStageChangeSummaryGatewayRejected).code;

Map<String, Object?> _mutableReady() =>
    jsonDecode(jsonEncode(_readyBody())) as Map<String, Object?>;

Map<String, Object?> _result(Map<String, Object?> body) =>
    body['result']! as Map<String, Object?>;

Map<String, Object?> _period(Map<String, Object?> body) =>
    _result(body)['period']! as Map<String, Object?>;

Map<String, Object?> _value(Map<String, Object?> body) =>
    _result(body)['value']! as Map<String, Object?>;

HttpPersonalRelationshipStageChangeSummaryGateway _gateway(
  Future<http.Response> Function(http.Request) handler,
) => HttpPersonalRelationshipStageChangeSummaryGateway(
  baseUri: Uri.parse('https://backend.example.test'),
  identitySession: _identity(),
  client: MockClient(handler),
  now: () => _receivedAtUtc,
);

FakeIdentitySession _identity() => FakeIdentitySession(
  initial: const IdentitySnapshot(
    stage: IdentityStage.signedIn,
    principal: IdentityPrincipal(
      externalSubject: 'subject-1',
      email: 'owner@example.test',
    ),
  ),
);

http.Response _json(Object? value, [int status = 200]) => http.Response(
  jsonEncode(value),
  status,
  headers: const {'content-type': 'application/json; charset=utf-8'},
);

Map<String, Object?> _readyBody({
  int eventCount = 5,
  int distinctRelationshipCount = 4,
  int upwardCount = 3,
  int downwardCount = 2,
}) => {
  'result': {
    'contract_id': 'personal_relationship_stage_change_summary_result_v1',
    'project_id': _projectId,
    'time_basis': 'relationshipChangedAtUtc',
    'period': {'from_utc': _fromText, 'until_utc': _untilText},
    'data_cutoff_utc': _cutoffText,
    'authorized_at_utc': _cutoffText,
    'value': {
      'event_count': eventCount,
      'distinct_relationship_count': distinctRelationshipCount,
      'upward_count': upwardCount,
      'downward_count': downwardCount,
    },
  },
};

const _projectId = '33333333-3333-4333-8333-333333333333';
const _otherProjectId = '99999999-9999-4999-8999-999999999999';
const _fromText = '2030-01-01T00:00:00.000Z';
const _untilText = '2030-01-08T00:00:00.000Z';
const _cutoffText = '2030-01-08T01:00:00.000Z';
final _fromUtc = DateTime.utc(2030, 1, 1);
final _untilUtc = DateTime.utc(2030, 1, 8);
final _cutoffUtc = DateTime.utc(2030, 1, 8, 1);
final _receivedAtUtc = DateTime.utc(2030, 1, 8, 2);
