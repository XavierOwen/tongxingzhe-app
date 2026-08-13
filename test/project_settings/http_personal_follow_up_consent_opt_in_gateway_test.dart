import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tongxingzhe_app/identity/identity_session.dart';
import 'package:tongxingzhe_app/project_settings/http_personal_follow_up_consent_opt_in_gateway.dart';
import 'package:tongxingzhe_app/project_settings/personal_follow_up_consent_opt_in.dart';

import '../support/fake_identity_session.dart';

void main() {
  test('GET reads the never-configured state with no body or query', () async {
    late http.Request request;
    final gateway = _gateway((value) async {
      request = value;
      return _json({'state': _state(configuration: null)});
    });
    addTearDown(gateway.close);

    final result = await gateway.load();

    expect(request.method, 'GET');
    expect(request.url.path, '/v1/personal/follow-up-consent-ratio/opt-in');
    expect(request.url.query, isEmpty);
    expect(request.body, isEmpty);
    expect(result, isA<PersonalFollowUpConsentOptInSuccess>());
    final state = (result as PersonalFollowUpConsentOptInSuccess).value;
    expect(state.status, PersonalFollowUpConsentOptInStatus.notEnabled);
    expect(state.configuration, isNull);
  });

  test('PUT sends exactly the optimistic-concurrency body', () async {
    late http.Request request;
    final gateway = _gateway((value) async {
      request = value;
      return _json({'configuration': _configuration(enabled: true)});
    });
    addTearDown(gateway.close);

    final result = await gateway.configure(
      expectedVersion: 0,
      enabled: true,
      requestId: _requestId,
    );

    expect(request.method, 'PUT');
    expect(request.url.path, '/v1/personal/follow-up-consent-ratio/opt-in');
    expect(jsonDecode(request.body), {
      'expected_version': 0,
      'enabled': true,
      'request_id': _requestId,
    });
    expect(result, isA<PersonalFollowUpConsentOptInSuccess>());
    expect(
      (result as PersonalFollowUpConsentOptInSuccess).value.enabled,
      isTrue,
    );
  });

  test(
    'parses enabled and explicitly disabled states without collapsing them',
    () async {
      for (final enabled in [true, false]) {
        final gateway = _gateway(
          (_) async => _json({
            'state': _state(
              configuration: _configuration(enabled: enabled),
              status: enabled ? 'enabled' : 'not_enabled',
            ),
          }),
        );
        addTearDown(gateway.close);
        final result = await gateway.load();
        expect(result, isA<PersonalFollowUpConsentOptInSuccess>());
        final state = (result as PersonalFollowUpConsentOptInSuccess).value;
        expect(state.configuration!.enabled, enabled);
        expect(
          state.status,
          enabled
              ? PersonalFollowUpConsentOptInStatus.enabled
              : PersonalFollowUpConsentOptInStatus.notEnabled,
        );
      }
    },
  );

  test('401 refreshes once and retries with refreshed bearer', () async {
    final identity = _identity();
    var calls = 0;
    final gateway = HttpPersonalFollowUpConsentOptInGateway(
      baseUri: Uri.parse('https://backend.example.test'),
      identitySession: identity,
      client: MockClient((request) async {
        calls++;
        expect(
          request.headers['authorization'],
          'Bearer test-only-access-token',
        );
        return calls == 1
            ? http.Response('', 401)
            : _json({'state': _state(configuration: null)});
      }),
      currentProjectId: () => _projectId,
    );
    addTearDown(gateway.close);

    final result = await gateway.load();

    expect(result, isA<PersonalFollowUpConsentOptInSuccess>());
    expect(calls, 2);
    expect(identity.accessTokenForceRefreshValues, [false, true]);
  });

  test('maps stable HTTP failures and network failures', () async {
    for (final entry in <int, PersonalFollowUpConsentOptInFailureCode>{
      400: PersonalFollowUpConsentOptInFailureCode.invalidRequest,
      403: PersonalFollowUpConsentOptInFailureCode.forbidden,
      409: PersonalFollowUpConsentOptInFailureCode.conflict,
      503: PersonalFollowUpConsentOptInFailureCode.serviceUnavailable,
    }.entries) {
      final gateway = _gateway((_) async => http.Response('', entry.key));
      addTearDown(gateway.close);
      final result = await gateway.load();
      expect(result, isA<PersonalFollowUpConsentOptInRejected>());
      expect(
        (result as PersonalFollowUpConsentOptInRejected).code,
        entry.value,
      );
    }

    final gateway = HttpPersonalFollowUpConsentOptInGateway(
      baseUri: Uri.parse('https://backend.example.test'),
      identitySession: _identity(),
      client: MockClient((_) => Future.error(http.ClientException('down'))),
      currentProjectId: () => _projectId,
    );
    addTearDown(gateway.close);
    final result = await gateway.load();
    expect(
      (result as PersonalFollowUpConsentOptInRejected).code,
      PersonalFollowUpConsentOptInFailureCode.networkUnavailable,
    );
  });

  test('rejects extra fields and contract/project/metric mismatches', () async {
    final cases = <Map<String, Object?>>[
      {..._state(configuration: null), 'extra': true},
      {..._state(configuration: null), 'metric_id': 'other@1'},
      {..._state(configuration: null), 'project_id': _otherProjectId},
      {
        'state_contract_id': 'wrong_v1',
        'metric_id': _metric,
        'project_id': _projectId,
        'status': 'not_enabled',
        'configuration': null,
      },
    ];
    for (final state in cases) {
      final gateway = _gateway((_) async => _json({'state': state}));
      addTearDown(gateway.close);
      final result = await gateway.load();
      expect(
        (result as PersonalFollowUpConsentOptInRejected).code,
        PersonalFollowUpConsentOptInFailureCode.invalidResponse,
      );
    }
  });

  test(
    'rejects actor leakage, invalid version bounds, UUID and timestamps',
    () async {
      final invalidConfigurations = <Map<String, Object?>>[
        {..._configuration(enabled: true), 'actor_app_user_id': _userId},
        {..._configuration(enabled: true), 'version_number': 2147483648},
        {..._configuration(enabled: true), 'expected_version': -1},
        {..._configuration(enabled: true), 'request_id': 'not-a-uuid'},
        {
          ..._configuration(enabled: true),
          'recorded_at_utc': '2030-01-01T00:00:00Z',
        },
        {
          ..._configuration(enabled: true),
          'recorded_at_utc': '2030-01-01T00:00:00-06:00',
        },
        {
          ..._configuration(enabled: true),
          'recorded_at_utc': '2030-02-30T00:00:00.000000Z',
        },
      ];
      for (final configuration in invalidConfigurations) {
        final gateway = _gateway(
          (_) async => _json({
            'state': _state(configuration: configuration, status: 'enabled'),
          }),
        );
        addTearDown(gateway.close);
        final result = await gateway.load();
        expect(
          (result as PersonalFollowUpConsentOptInRejected).code,
          PersonalFollowUpConsentOptInFailureCode.invalidResponse,
        );
      }
    },
  );

  test(
    'deferred gateway reports not configured and UUID generator emits v4 UUIDs',
    () async {
      const gateway = DeferredPersonalFollowUpConsentOptInGateway();
      final load = await gateway.load();
      expect(
        (load as PersonalFollowUpConsentOptInRejected).code,
        PersonalFollowUpConsentOptInFailureCode.notConfigured,
      );
      final save = await gateway.configure(
        expectedVersion: 0,
        enabled: true,
        requestId: _requestId,
      );
      expect(
        (save as PersonalFollowUpConsentOptInRejected).code,
        PersonalFollowUpConsentOptInFailureCode.notConfigured,
      );

      final generator = SecureConsentOptInRequestIdGenerator();
      final first = generator.next();
      final second = generator.next();
      expect(
        first,
        matches(
          RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
          ),
        ),
      );
      expect(second, isNot(first));
    },
  );
}

const _userId = '11111111-1111-4111-8111-111111111111';
const _projectId = '33333333-3333-4333-8333-333333333333';
const _otherProjectId = '99999999-9999-4999-8999-999999999999';
const _requestId = '55555555-5555-4555-8555-555555555555';
const _metric = 'follow_up_consent_ratio@1';

FakeIdentitySession _identity() => FakeIdentitySession(
  initial: const IdentitySnapshot(
    stage: IdentityStage.signedIn,
    principal: IdentityPrincipal(
      externalSubject: 'subject-1',
      email: 'owner@example.test',
    ),
  ),
);

HttpPersonalFollowUpConsentOptInGateway _gateway(
  Future<http.Response> Function(http.Request) handler,
) => HttpPersonalFollowUpConsentOptInGateway(
  baseUri: Uri.parse('https://backend.example.test'),
  identitySession: _identity(),
  client: MockClient(handler),
  currentProjectId: () => _projectId,
);

http.Response _json(Map<String, Object?> value, [int status = 200]) =>
    http.Response(
      jsonEncode(value),
      status,
      headers: const {'content-type': 'application/json'},
    );

Map<String, Object?> _state({
  required Object? configuration,
  String status = 'not_enabled',
}) => {
  'state_contract_id': 'project_follow_up_consent_opt_in_state_v1',
  'metric_id': _metric,
  'project_id': _projectId,
  'status': status,
  'configuration': configuration,
};

Map<String, Object?> _configuration({required bool enabled}) => {
  'configuration_contract_id':
      'project_follow_up_consent_opt_in_configuration_v1',
  'metric_id': _metric,
  'project_id': _projectId,
  'version_number': 1,
  'expected_version': 0,
  'enabled': enabled,
  'request_id': _requestId,
  'recorded_at_utc': '2030-01-01T00:00:00.000000Z',
};
