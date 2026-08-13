import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tongxingzhe_app/features/contact_metrics/http_personal_follow_up_consent_ratio_gateway.dart';
import 'package:tongxingzhe_app/features/contact_metrics/metric_contract.dart';
import 'package:tongxingzhe_app/features/contact_metrics/personal_follow_up_consent_ratio.dart';
import 'package:tongxingzhe_app/identity/identity_session.dart';

import '../../support/fake_identity_session.dart';

void main() {
  test(
    'GET sends the exact UTC period and parses a ready MetricResult',
    () async {
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
      expect(captured.url.path, '/v1/personal/follow-up-consent-ratio');
      expect(captured.url.queryParametersAll, {
        'from_utc': [_fromText],
        'until_utc': [_untilText],
      });
      expect(captured.body, isEmpty);
      expect(
        captured.headers['authorization'],
        'Bearer test-only-access-token',
      );
      expect(result, isA<PersonalFollowUpConsentRatioGatewaySuccess>());
      final ready =
          (result as PersonalFollowUpConsentRatioGatewaySuccess).value
              as PersonalFollowUpConsentRatioReady;
      expect(ready.projectId, _projectId);
      expect(ready.metric.period.fromUtc, _fromUtc);
      expect(ready.metric.period.untilUtc, _untilUtc);
      expect(ready.metric.dataCutoffUtc, isNull);
      expect(ready.metric.retrievedAtUtc, _receivedAtUtc);
      final value = ready.metric.value as RatioMetricValue;
      expect(value.numerators, [2, 1]);
      expect(value.denominator, 3);
      expect(value.basisPoints.first, 6667);
      expect(value.refusedCount, 1);
      expect(value.notApplicableCount, 1);
      expect(value.unansweredCount, 2);
    },
  );

  test('not enabled remains an exact value-free result', () async {
    final gateway = _gateway(
      (_) async => _json({
        'result': {
          'contract_id': 'personal_follow_up_consent_ratio_result_v1',
          'metric_id': 'follow_up_consent_ratio@1',
          'project_id': _projectId,
          'status': 'not_enabled',
        },
      }),
    );
    addTearDown(gateway.close);

    final result = await _load(gateway);

    expect(result, isA<PersonalFollowUpConsentRatioGatewaySuccess>());
    final value = (result as PersonalFollowUpConsentRatioGatewaySuccess).value;
    expect(value, isA<PersonalFollowUpConsentRatioNotEnabled>());
    expect(value.projectId, _projectId);
  });

  test('401 refreshes the bearer and retries exactly once', () async {
    final identity = _identity();
    var requestCount = 0;
    final gateway = HttpPersonalFollowUpConsentRatioGateway(
      baseUri: Uri.parse('https://backend.example.test'),
      identitySession: identity,
      client: MockClient((_) async {
        requestCount += 1;
        return requestCount == 1 ? http.Response('', 401) : _json(_readyBody());
      }),
      now: () => _receivedAtUtc,
    );
    addTearDown(gateway.close);

    final result = await _load(gateway);

    expect(result, isA<PersonalFollowUpConsentRatioGatewaySuccess>());
    expect(requestCount, 2);
    expect(identity.accessTokenForceRefreshValues, [false, true]);
  });

  test('a second 401 stops without a third request', () async {
    final identity = _identity();
    var requestCount = 0;
    final gateway = HttpPersonalFollowUpConsentRatioGateway(
      baseUri: Uri.parse('https://backend.example.test'),
      identitySession: identity,
      client: MockClient((_) async {
        requestCount += 1;
        return http.Response('', 401);
      }),
    );
    addTearDown(gateway.close);

    final result = await _load(gateway);

    expect(
      _rejectedCode(result),
      PersonalFollowUpConsentRatioFailureCode.unauthorized,
    );
    expect(requestCount, 2);
    expect(identity.accessTokenForceRefreshValues, [false, true]);
  });

  test('invalid project and period stop before token or HTTP access', () async {
    final identity = _identity();
    var requestCount = 0;
    final gateway = HttpPersonalFollowUpConsentRatioGateway(
      baseUri: Uri.parse('https://backend.example.test'),
      identitySession: identity,
      client: MockClient((_) async {
        requestCount += 1;
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
        PersonalFollowUpConsentRatioFailureCode.invalidRequest,
      );
    }
    expect(identity.accessTokenForceRefreshValues, isEmpty);
    expect(requestCount, 0);
  });

  test('identity, HTTP, and network failures use stable categories', () async {
    for (final entry in <(int, PersonalFollowUpConsentRatioFailureCode)>[
      (400, PersonalFollowUpConsentRatioFailureCode.invalidRequest),
      (403, PersonalFollowUpConsentRatioFailureCode.forbidden),
      (408, PersonalFollowUpConsentRatioFailureCode.networkUnavailable),
      (404, PersonalFollowUpConsentRatioFailureCode.serverRejected),
      (503, PersonalFollowUpConsentRatioFailureCode.serviceUnavailable),
    ]) {
      final gateway = _gateway((_) async => http.Response('', entry.$1));
      final result = await _load(gateway);
      expect(_rejectedCode(result), entry.$2);
      await gateway.close();
    }

    final networkGateway = _gateway((request) async {
      throw http.ClientException('offline', request.url);
    });
    expect(
      _rejectedCode(await _load(networkGateway)),
      PersonalFollowUpConsentRatioFailureCode.networkUnavailable,
    );
    await networkGateway.close();

    final identity = _identity()
      ..rejectNextAccessTokenWith = const IdentityFailure(
        code: IdentityFailureCode.notConfigured,
      );
    final identityGateway = HttpPersonalFollowUpConsentRatioGateway(
      baseUri: Uri.parse('https://backend.example.test'),
      identitySession: identity,
      client: MockClient((_) async => _json(_readyBody())),
    );
    expect(
      _rejectedCode(await _load(identityGateway)),
      PersonalFollowUpConsentRatioFailureCode.notConfigured,
    );
    await identityGateway.close();
  });

  test('envelope and not-enabled branches reject every extra field', () async {
    final invalidBodies = <Map<String, Object?>>[
      {..._readyBody(), 'extra': true},
      {
        'result': {
          'contract_id': 'personal_follow_up_consent_ratio_result_v1',
          'metric_id': 'follow_up_consent_ratio@1',
          'project_id': _projectId,
          'status': 'not_enabled',
          'value': null,
        },
      },
      {
        'result': {..._result(_readyBody()), 'subject': 'must-not-cross'},
      },
    ];

    for (final body in invalidBodies) {
      final gateway = _gateway((_) async => _json(body));
      expect(
        _rejectedCode(await _load(gateway)),
        PersonalFollowUpConsentRatioFailureCode.invalidResponse,
      );
      await gateway.close();
    }
  });

  test('ready rejects identity, period, and nested key drift', () async {
    final wrongContract = _mutableReady();
    _result(wrongContract)['contract_id'] = 'other_v1';
    final wrongMetric = _mutableReady();
    _result(wrongMetric)['metric_id'] = 'other@1';
    final wrongProject = _mutableReady();
    _result(wrongProject)['project_id'] = _otherProjectId;
    final wrongPeriod = _mutableReady();
    _period(wrongPeriod)['until_utc'] = '2030-01-09T00:00:00.000Z';
    final offsetPeriod = _mutableReady();
    _period(offsetPeriod)['from_utc'] = '2029-12-31T18:00:00-06:00';
    final extraValue = _mutableReady();
    _value(extraValue)['email'] = 'must-not-cross';

    for (final body in [
      wrongContract,
      wrongMetric,
      wrongProject,
      wrongPeriod,
      offsetPeriod,
      extraValue,
    ]) {
      final gateway = _gateway((_) async => _json(body));
      expect(
        _rejectedCode(await _load(gateway)),
        PersonalFollowUpConsentRatioFailureCode.invalidResponse,
      );
      await gateway.close();
    }
  });

  test(
    'ready rejects unsafe counts and every arithmetic invariant drift',
    () async {
      final cases = <Map<String, Object?>>[];
      for (final mutation in <void Function(Map<String, Object?>)>[
        (value) => value['yes_count'] = -1,
        (value) => value['yes_count'] = 9007199254740992,
        (value) => value['numerator'] = 1,
        (value) => value['denominator'] = 4,
        (value) => value['unknown_count'] = 1,
        (value) => value['excluded_count'] = 1,
        (value) => value['percentage_basis_points'] = 6666,
        (value) => value['percentage_basis_points'] = null,
      ]) {
        final body = _mutableReady();
        mutation(_value(body));
        cases.add(body);
      }

      for (final body in cases) {
        final gateway = _gateway((_) async => _json(body));
        expect(
          _rejectedCode(await _load(gateway)),
          PersonalFollowUpConsentRatioFailureCode.invalidResponse,
        );
        await gateway.close();
      }
    },
  );

  test('empty denominator accepts only null basis points', () async {
    final body = _mutableReady();
    _value(body)
      ..['yes_count'] = 0
      ..['no_count'] = 0
      ..['numerator'] = 0
      ..['denominator'] = 0
      ..['percentage_basis_points'] = null;
    final gateway = _gateway((_) async => _json(body));
    addTearDown(gateway.close);

    final ready =
        (await _load(gateway) as PersonalFollowUpConsentRatioGatewaySuccess)
                .value
            as PersonalFollowUpConsentRatioReady;

    expect((ready.metric.value as RatioMetricValue).basisPoints, [null, null]);
  });

  test(
    'malformed JSON, transport URI, deferred, and close fail safely',
    () async {
      final malformed = _gateway((_) async => http.Response('{', 200));
      expect(
        _rejectedCode(await _load(malformed)),
        PersonalFollowUpConsentRatioFailureCode.invalidResponse,
      );
      await malformed.close();

      expect(
        () => HttpPersonalFollowUpConsentRatioGateway(
          baseUri: Uri.parse('http://backend.example.test'),
          identitySession: _identity(),
          client: MockClient((_) async => _json(_readyBody())),
        ),
        throwsArgumentError,
      );

      const deferred = DeferredPersonalFollowUpConsentRatioGateway();
      expect(
        _rejectedCode(await _load(deferred)),
        PersonalFollowUpConsentRatioFailureCode.notConfigured,
      );
      await deferred.close();

      final trackingClient = _TrackingClient(
        MockClient((_) async => _json(_readyBody())),
      );
      final closeGateway = HttpPersonalFollowUpConsentRatioGateway(
        baseUri: Uri.parse('http://127.0.0.1:8080'),
        identitySession: _identity(),
        client: trackingClient,
        now: () => _receivedAtUtc,
      );
      expect(
        await _load(closeGateway),
        isA<PersonalFollowUpConsentRatioGatewaySuccess>(),
      );
      await closeGateway.close();
      expect(trackingClient.isClosed, isTrue);
    },
  );
}

Future<PersonalFollowUpConsentRatioGatewayResult> _load(
  PersonalFollowUpConsentRatioGateway gateway,
) =>
    gateway.load(projectId: _projectId, fromUtc: _fromUtc, untilUtc: _untilUtc);

PersonalFollowUpConsentRatioFailureCode _rejectedCode(
  PersonalFollowUpConsentRatioGatewayResult result,
) => (result as PersonalFollowUpConsentRatioGatewayRejected).code;

Map<String, Object?> _mutableReady() =>
    jsonDecode(jsonEncode(_readyBody())) as Map<String, Object?>;

Map<String, Object?> _result(Map<String, Object?> body) =>
    body['result']! as Map<String, Object?>;

Map<String, Object?> _period(Map<String, Object?> body) =>
    _result(body)['period']! as Map<String, Object?>;

Map<String, Object?> _value(Map<String, Object?> body) =>
    _result(body)['value']! as Map<String, Object?>;

final class _TrackingClient extends http.BaseClient {
  _TrackingClient(this.inner);

  final http.Client inner;
  bool isClosed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      inner.send(request);

  @override
  void close() {
    isClosed = true;
    inner.close();
  }
}

HttpPersonalFollowUpConsentRatioGateway _gateway(
  Future<http.Response> Function(http.Request) handler,
) => HttpPersonalFollowUpConsentRatioGateway(
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

Map<String, Object?> _readyBody() => {
  'result': {
    'contract_id': 'personal_follow_up_consent_ratio_result_v1',
    'metric_id': 'follow_up_consent_ratio@1',
    'project_id': _projectId,
    'status': 'ready',
    'period': {'from_utc': _fromText, 'until_utc': _untilText},
    'value': {
      'yes_count': 2,
      'no_count': 1,
      'numerator': 2,
      'unknown_count': 0,
      'refused_count': 1,
      'not_applicable_count': 1,
      'unanswered_count': 2,
      'excluded_count': 0,
      'denominator': 3,
      'percentage_basis_points': 6667,
    },
  },
};

const _projectId = '33333333-3333-4333-8333-333333333333';
const _otherProjectId = '99999999-9999-4999-8999-999999999999';
const _fromText = '2030-01-01T00:00:00.000Z';
const _untilText = '2030-01-08T00:00:00.000Z';
final _fromUtc = DateTime.utc(2030, 1, 1);
final _untilUtc = DateTime.utc(2030, 1, 8);
final _receivedAtUtc = DateTime.utc(2030, 1, 8, 1);
