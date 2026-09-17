import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tongxingzhe_app/identity/identity_session.dart';
import 'package:tongxingzhe_app/organization_project_membership_assignment/http_organization_project_membership_assignment_gateway.dart';
import 'package:tongxingzhe_app/organization_project_membership_assignment/organization_project_membership_assignment.dart';

import '../support/fake_identity_session.dart';

void main() {
  test(
    'sends the exact assignment contract and canonicalizes all UUIDs',
    () async {
      late http.Request request;
      final gateway = _gateway((value) async {
        request = value;
        return _json(_receiptJson());
      });
      addTearDown(gateway.close);

      final result = await gateway.assign(
        requestId: _requestId.toUpperCase(),
        organizationWorkspaceId: _workspaceId.toUpperCase(),
        projectId: _projectId.toUpperCase(),
        targetOrganizationMembershipId: _targetMembershipId.toUpperCase(),
      );

      expect(request.method, 'POST');
      expect(
        request.url,
        Uri.parse(
          'https://backend.example.test/v1/organizations/$_workspaceId/projects/$_projectId/memberships',
        ),
      );
      expect(request.url.query, isEmpty);
      expect(request.url.fragment, isEmpty);
      expect(request.headers, {
        'accept': 'application/json',
        'authorization': 'Bearer test-only-access-token',
        'content-type': 'application/json; charset=utf-8',
      });
      expect(request.headers.containsKey('idempotency-key'), isFalse);
      expect(
        request.body,
        jsonEncode({
          'request_id': _requestId,
          'target_organization_membership_id': _targetMembershipId,
        }),
      );
      expect(jsonDecode(request.body), {
        'request_id': _requestId,
        'target_organization_membership_id': _targetMembershipId,
      });
      expect(result, isA<OrganizationProjectMembershipAssignmentSuccess>());
    },
  );

  test('rejects each invalid UUID before identity or HTTP access', () async {
    const invalidInputs = [
      (
        requestId: 'not-a-uuid',
        workspaceId: _workspaceId,
        projectId: _projectId,
        targetMembershipId: _targetMembershipId,
      ),
      (
        requestId: _requestId,
        workspaceId: 'not-a-uuid',
        projectId: _projectId,
        targetMembershipId: _targetMembershipId,
      ),
      (
        requestId: _requestId,
        workspaceId: _workspaceId,
        projectId: 'not-a-uuid',
        targetMembershipId: _targetMembershipId,
      ),
      (
        requestId: ' $_requestId',
        workspaceId: _workspaceId,
        projectId: _projectId,
        targetMembershipId: _targetMembershipId,
      ),
      (
        requestId: _requestId,
        workspaceId: '$_workspaceId ',
        projectId: _projectId,
        targetMembershipId: _targetMembershipId,
      ),
      (
        requestId: _requestId,
        workspaceId: _workspaceId,
        projectId: ' $_projectId',
        targetMembershipId: _targetMembershipId,
      ),
      (
        requestId: _requestId,
        workspaceId: _workspaceId,
        projectId: _projectId,
        targetMembershipId: '$_targetMembershipId ',
      ),
      (
        requestId: _requestId,
        workspaceId: _workspaceId,
        projectId: _projectId,
        targetMembershipId: 'not-a-uuid',
      ),
    ];

    for (final input in invalidInputs) {
      final identity = _identity();
      var requests = 0;
      final gateway = HttpOrganizationProjectMembershipAssignmentGateway(
        baseUri: Uri.parse('https://backend.example.test'),
        identitySession: identity,
        client: MockClient((_) async {
          requests++;
          return _json(_receiptJson());
        }),
      );

      final result = await gateway.assign(
        requestId: input.requestId,
        organizationWorkspaceId: input.workspaceId,
        projectId: input.projectId,
        targetOrganizationMembershipId: input.targetMembershipId,
      );
      await gateway.close();

      expect(result, isA<OrganizationProjectMembershipAssignmentRejected>());
      expect(
        (result as OrganizationProjectMembershipAssignmentRejected).code,
        OrganizationProjectMembershipAssignmentFailureCode.invalidRequest,
      );
      expect(identity.accessTokenForceRefreshValues, isEmpty);
      expect(requests, 0);
    }
  });

  test('deferred gateway is no-network and close is repeatable', () async {
    const gateway = DeferredOrganizationProjectMembershipAssignmentGateway();

    final result = await gateway.assign(
      requestId: _requestId,
      organizationWorkspaceId: _workspaceId,
      projectId: _projectId,
      targetOrganizationMembershipId: _targetMembershipId,
    );
    await gateway.close();
    await gateway.close();

    expect(result, isA<OrganizationProjectMembershipAssignmentRejected>());
    expect(
      (result as OrganizationProjectMembershipAssignmentRejected).code,
      OrganizationProjectMembershipAssignmentFailureCode.notConfigured,
    );
  });

  test(
    'production factory uses deferred gateway when base URL is empty',
    () async {
      final identity = _identity();
      final gateway = productionOrganizationProjectMembershipAssignmentGateway(
        identity,
      );

      expect(
        gateway,
        isA<DeferredOrganizationProjectMembershipAssignmentGateway>(),
      );
      await gateway.close();
      expect(identity.isClosed, isFalse);
    },
  );

  test('rejects invalid configured base URIs synchronously', () {
    final identity = _identity();
    final client = _TrackingMockClient((_) async => _json(_receiptJson()));

    expect(
      () => HttpOrganizationProjectMembershipAssignmentGateway(
        baseUri: Uri.parse('https://backend.example.test/path'),
        identitySession: identity,
        client: client,
      ),
      throwsArgumentError,
    );
    expect(
      () => HttpOrganizationProjectMembershipAssignmentGateway(
        baseUri: Uri.parse('http://backend.example.test'),
        identitySession: identity,
        client: client,
      ),
      throwsArgumentError,
    );
    expect(client.closed, isFalse);
  });

  test('maps identity failures without sending a request', () async {
    const cases = [
      (
        failure: IdentityFailureCode.notConfigured,
        expected:
            OrganizationProjectMembershipAssignmentFailureCode.notConfigured,
      ),
      (
        failure: IdentityFailureCode.networkUnavailable,
        expected: OrganizationProjectMembershipAssignmentFailureCode
            .networkUnavailable,
      ),
      (
        failure: IdentityFailureCode.sessionMissing,
        expected:
            OrganizationProjectMembershipAssignmentFailureCode.unauthorized,
      ),
      (
        failure: IdentityFailureCode.providerRejected,
        expected:
            OrganizationProjectMembershipAssignmentFailureCode.unauthorized,
      ),
      (
        failure: IdentityFailureCode.unknown,
        expected:
            OrganizationProjectMembershipAssignmentFailureCode.unauthorized,
      ),
    ];

    for (final testCase in cases) {
      final identity = _identity();
      identity.rejectNextAccessTokenWith = IdentityFailure(
        code: testCase.failure,
      );
      var requests = 0;
      final gateway = HttpOrganizationProjectMembershipAssignmentGateway(
        baseUri: Uri.parse('https://backend.example.test'),
        identitySession: identity,
        client: MockClient((_) async {
          requests++;
          return _json(_receiptJson());
        }),
      );

      final result = await gateway.assign(
        requestId: _requestId,
        organizationWorkspaceId: _workspaceId,
        projectId: _projectId,
        targetOrganizationMembershipId: _targetMembershipId,
      );
      await gateway.close();

      expect(result, isA<OrganizationProjectMembershipAssignmentRejected>());
      expect(
        (result as OrganizationProjectMembershipAssignmentRejected).code,
        testCase.expected,
        reason: '${testCase.failure}',
      );
      expect(requests, 0);
    }
  });

  test(
    'refreshes once for an exact 401 envelope and retries the same URL/body',
    () async {
      final identity = _ControllableIdentitySession();
      final requests = <http.Request>[];
      final gateway = HttpOrganizationProjectMembershipAssignmentGateway(
        baseUri: Uri.parse('https://backend.example.test'),
        identitySession: identity,
        client: MockClient((request) async {
          requests.add(request);
          return requests.length == 1
              ? _error('unauthenticated', 401)
              : _json(_receiptJson());
        }),
      );
      addTearDown(gateway.close);
      addTearDown(identity.close);

      final result = await gateway.assign(
        requestId: _requestId,
        organizationWorkspaceId: _workspaceId,
        projectId: _projectId,
        targetOrganizationMembershipId: _targetMembershipId,
      );

      expect(result, isA<OrganizationProjectMembershipAssignmentSuccess>());
      expect(requests, hasLength(2));
      expect(requests[0].method, requests[1].method);
      expect(requests[0].url, requests[1].url);
      expect(requests[0].headers['accept'], requests[1].headers['accept']);
      expect(
        requests[0].headers['content-type'],
        requests[1].headers['content-type'],
      );
      expect(requests[0].body, requests[1].body);
      expect(requests.map((request) => request.headers['authorization']), [
        'Bearer stale-test-access-token',
        'Bearer refreshed-test-access-token',
      ]);
      expect(identity.accessTokenForceRefreshValues, [false, true]);
    },
  );

  test('does not refresh a malformed 401 response', () async {
    final cases = <http.Response Function()>[
      () => _json(
        _errorJson('unauthenticated'),
        status: 401,
        headers: const {'cache-control': 'no-store'},
      ),
      () => _raw('{', status: 401),
      () => _error('other', 401),
    ];

    for (final response in cases) {
      final identity = _identity();
      var requests = 0;
      final gateway = _gateway((_) async {
        requests++;
        return response();
      }, identity: identity);

      final result = await gateway.assign(
        requestId: _requestId,
        organizationWorkspaceId: _workspaceId,
        projectId: _projectId,
        targetOrganizationMembershipId: _targetMembershipId,
      );
      await gateway.close();

      expect(result, isA<OrganizationProjectMembershipAssignmentRejected>());
      expect(
        (result as OrganizationProjectMembershipAssignmentRejected).code,
        OrganizationProjectMembershipAssignmentFailureCode.invalidResponse,
      );
      expect(requests, 1);
      expect(identity.accessTokenForceRefreshValues, [false]);
    }
  });

  test('does not issue a second request when forced refresh fails', () async {
    final identity = _identity();
    var requests = 0;
    final gateway = _gateway((_) async {
      requests++;
      if (requests == 1) {
        identity.rejectNextAccessTokenWith = const IdentityFailure(
          code: IdentityFailureCode.sessionMissing,
        );
      }
      return _error('unauthenticated', 401);
    }, identity: identity);
    addTearDown(gateway.close);

    final result = await gateway.assign(
      requestId: _requestId,
      organizationWorkspaceId: _workspaceId,
      projectId: _projectId,
      targetOrganizationMembershipId: _targetMembershipId,
    );

    expect(result, isA<OrganizationProjectMembershipAssignmentRejected>());
    expect(
      (result as OrganizationProjectMembershipAssignmentRejected).code,
      OrganizationProjectMembershipAssignmentFailureCode.unauthorized,
    );
    expect(requests, 1);
    expect(identity.accessTokenForceRefreshValues, [false, true]);
  });

  test('second exact 401 is unauthorized without a refresh loop', () async {
    final identity = _identity();
    var requests = 0;
    final gateway = _gateway((_) async {
      requests++;
      return _error('unauthenticated', 401);
    }, identity: identity);
    addTearDown(gateway.close);

    final result = await gateway.assign(
      requestId: _requestId,
      organizationWorkspaceId: _workspaceId,
      projectId: _projectId,
      targetOrganizationMembershipId: _targetMembershipId,
    );

    expect(result, isA<OrganizationProjectMembershipAssignmentRejected>());
    expect(
      (result as OrganizationProjectMembershipAssignmentRejected).code,
      OrganizationProjectMembershipAssignmentFailureCode.unauthorized,
    );
    expect(requests, 2);
    expect(identity.accessTokenForceRefreshValues, [false, true]);
  });

  test(
    'accepts the exact seven-field receipt and preserves UTC time',
    () async {
      final gateway = _gateway((_) async => _json(_receiptJson()));
      addTearDown(gateway.close);

      final result = await gateway.assign(
        requestId: _requestId,
        organizationWorkspaceId: _workspaceId,
        projectId: _projectId,
        targetOrganizationMembershipId: _targetMembershipId,
      );

      expect(result, isA<OrganizationProjectMembershipAssignmentSuccess>());
      final receipt =
          (result as OrganizationProjectMembershipAssignmentSuccess).receipt;
      expect(receipt.projectMembershipAssignmentContractId, _contractId);
      expect(receipt.organizationWorkspaceId, _workspaceId);
      expect(receipt.organizationMembershipId, _targetMembershipId);
      expect(receipt.projectId, _projectId);
      expect(receipt.inactiveFromUtc, isNull);
      expect(receipt.projectMembershipId, _projectMembershipId);
      expect(receipt.activeFromUtc, DateTime.utc(2030, 1, 2, 4, 4, 5));
      expect(receipt.activeFromUtc.isUtc, isTrue);
    },
  );

  test(
    'rejects receipt shape, identity, contract, workspace, and time drift',
    () async {
      final cases = <String, String>{
        'malformed JSON': '{',
        'non-object JSON': '[]',
        'extra field': jsonEncode({..._receiptJson(), 'extra': true}),
        'extra actor': jsonEncode({
          ..._receiptJson(),
          'actor_app_user_id': _requestId,
        }),
        'missing nullable parent end': jsonEncode(
          _receiptJson()..remove('inactive_from_utc'),
        ),
        'missing field': jsonEncode(
          _receiptJson()..remove('project_membership_id'),
        ),
        'bad contract': jsonEncode({
          ..._receiptJson(),
          'project_membership_assignment_contract_id': 'other:v1',
        }),
        'bad UUID': jsonEncode({
          ..._receiptJson(),
          'organization_membership_id': 'not-a-uuid',
        }),
        'wrong field type': jsonEncode({
          ..._receiptJson(),
          'active_from_utc': 20300102,
        }),
        'uppercase UUID': jsonEncode({
          ..._receiptJson(),
          'project_membership_id': _projectMembershipId.toUpperCase(),
        }),
        'wrong workspace': jsonEncode({
          ..._receiptJson(),
          'organization_workspace_id': _otherWorkspaceId,
        }),
        'wrong project': jsonEncode({
          ..._receiptJson(),
          'project_id': _otherWorkspaceId,
        }),
        'wrong target parent': jsonEncode({
          ..._receiptJson(),
          'organization_membership_id': _otherWorkspaceId,
        }),
        'end before start': jsonEncode({
          ..._receiptJson(),
          'inactive_from_utc': '2030-01-02T04:04:04.999Z',
        }),
        'non-canonical parent end': jsonEncode({
          ..._receiptJson(),
          'inactive_from_utc': '2030-01-02T04:04:06Z',
        }),
        'wrong parent end type': jsonEncode({
          ..._receiptJson(),
          'inactive_from_utc': false,
        }),
        'non-canonical UTC': jsonEncode({
          ..._receiptJson(),
          'active_from_utc': '2030-01-02T04:04:05Z',
        }),
        'offset timestamp': jsonEncode({
          ..._receiptJson(),
          'active_from_utc': '2030-01-01T22:04:05.000-06:00',
        }),
        'invalid calendar date': jsonEncode({
          ..._receiptJson(),
          'active_from_utc': '2030-02-30T04:04:05.000Z',
        }),
      };

      for (final entry in cases.entries) {
        final gateway = _gateway((_) async => _raw(entry.value));
        final result = await gateway.assign(
          requestId: _requestId,
          organizationWorkspaceId: _workspaceId,
          projectId: _projectId,
          targetOrganizationMembershipId: _targetMembershipId,
        );
        await gateway.close();

        expect(
          result,
          isA<OrganizationProjectMembershipAssignmentRejected>(),
          reason: entry.key,
        );
        expect(
          (result as OrganizationProjectMembershipAssignmentRejected).code,
          OrganizationProjectMembershipAssignmentFailureCode.invalidResponse,
          reason: entry.key,
        );
      }
    },
  );

  test(
    'preserves finite parent end and allows equal millisecond projection',
    () async {
      for (final end in [
        '2030-01-02T04:04:05.123Z',
        '2030-01-09T04:04:05.456Z',
      ]) {
        final gateway = _gateway(
          (_) async => _json({
            ..._receiptJson(),
            'active_from_utc': '2030-01-02T04:04:05.123Z',
            'inactive_from_utc': end,
          }),
        );
        final result = await gateway.assign(
          requestId: _requestId,
          organizationWorkspaceId: _workspaceId,
          projectId: _projectId,
          targetOrganizationMembershipId: _targetMembershipId,
        );
        await gateway.close();

        final receipt =
            (result as OrganizationProjectMembershipAssignmentSuccess).receipt;
        expect(receipt.activeFromUtc, DateTime.utc(2030, 1, 2, 4, 4, 5, 123));
        expect(receipt.inactiveFromUtc!.toIso8601String(), end);
        expect(receipt.inactiveFromUtc!.isUtc, isTrue);
      }
    },
  );

  test('requires exact JSON UTF-8 and no-store response headers', () async {
    const headers = <Map<String, String>>[
      {'cache-control': 'no-store'},
      {
        'content-type': 'text/plain; charset=utf-8',
        'cache-control': 'no-store',
      },
      {'content-type': 'application/json', 'cache-control': 'no-store'},
      {
        'content-type': 'application/json; charset=iso-8859-1',
        'cache-control': 'no-store',
      },
      {
        'content-type': 'application/json; charset=utf-8',
        'cache-control': 'private, max-age=0',
      },
    ];

    for (final responseHeaders in headers) {
      final gateway = _gateway(
        (_) async => _json(_receiptJson(), headers: responseHeaders),
      );
      final result = await gateway.assign(
        requestId: _requestId,
        organizationWorkspaceId: _workspaceId,
        projectId: _projectId,
        targetOrganizationMembershipId: _targetMembershipId,
      );
      await gateway.close();

      expect(result, isA<OrganizationProjectMembershipAssignmentRejected>());
      expect(
        (result as OrganizationProjectMembershipAssignmentRejected).code,
        OrganizationProjectMembershipAssignmentFailureCode.invalidResponse,
      );
    }
  });

  test('maps every stable error envelope', () async {
    const cases =
        <
          ({
            int status,
            String code,
            OrganizationProjectMembershipAssignmentFailureCode failure,
          })
        >[
          (
            status: 400,
            code: 'invalid_json',
            failure:
                OrganizationProjectMembershipAssignmentFailureCode.invalidJson,
          ),
          (
            status: 400,
            code: 'invalid_organization_project_membership_assignment_request',
            failure: OrganizationProjectMembershipAssignmentFailureCode
                .invalidRequest,
          ),
          (
            status: 401,
            code: 'unauthenticated',
            failure:
                OrganizationProjectMembershipAssignmentFailureCode.unauthorized,
          ),
          (
            status: 403,
            code: 'organization_project_membership_assignment_forbidden',
            failure:
                OrganizationProjectMembershipAssignmentFailureCode.forbidden,
          ),
          (
            status: 409,
            code: 'organization_project_membership_assignment_conflict',
            failure:
                OrganizationProjectMembershipAssignmentFailureCode.conflict,
          ),
          (
            status: 413,
            code: 'payload_too_large',
            failure: OrganizationProjectMembershipAssignmentFailureCode
                .payloadTooLarge,
          ),
          (
            status: 503,
            code: 'organization_project_membership_assignment_unavailable',
            failure: OrganizationProjectMembershipAssignmentFailureCode
                .serviceUnavailable,
          ),
        ];

    for (final testCase in cases) {
      final gateway = _gateway(
        (_) async => _error(testCase.code, testCase.status),
      );
      final result = await gateway.assign(
        requestId: _requestId,
        organizationWorkspaceId: _workspaceId,
        projectId: _projectId,
        targetOrganizationMembershipId: _targetMembershipId,
      );
      await gateway.close();

      expect(result, isA<OrganizationProjectMembershipAssignmentRejected>());
      expect(
        (result as OrganizationProjectMembershipAssignmentRejected).code,
        testCase.failure,
        reason: '${testCase.status} ${testCase.code}',
      );
    }
  });

  test('rejects mismatched status and stable code pairs', () async {
    const pairs = [
      (status: 400, code: 'invalid_json'),
      (
        status: 400,
        code: 'invalid_organization_project_membership_assignment_request',
      ),
      (status: 401, code: 'unauthenticated'),
      (
        status: 403,
        code: 'organization_project_membership_assignment_forbidden',
      ),
      (
        status: 409,
        code: 'organization_project_membership_assignment_conflict',
      ),
      (status: 413, code: 'payload_too_large'),
      (
        status: 503,
        code: 'organization_project_membership_assignment_unavailable',
      ),
    ];
    for (final pair in pairs) {
      for (final status in [400, 401, 403, 409, 413, 503]) {
        if (status == pair.status) continue;
        final gateway = _gateway((_) async => _error(pair.code, status));
        final result = await gateway.assign(
          requestId: _requestId,
          organizationWorkspaceId: _workspaceId,
          projectId: _projectId,
          targetOrganizationMembershipId: _targetMembershipId,
        );
        await gateway.close();
        expect(
          _failureCode(result),
          _Failure.invalidResponse,
          reason: '$status ${pair.code}',
        );
      }
    }
  });

  test(
    'maps unknown, 404, and drifting error envelopes to invalidResponse',
    () async {
      final cases = <http.Response Function()>[
        () => _error('not_found', 404),
        () => _error('unknown', 418),
        () => _json({
          'error': {'code': 'invalid_json'},
          'extra': true,
        }, status: 400),
        () => _json({
          'error': {'message': 'do not expose'},
        }, status: 503),
        () => _json(_receiptJson(), status: 201),
      ];

      for (final response in cases) {
        final gateway = _gateway((_) async => response());
        final result = await gateway.assign(
          requestId: _requestId,
          organizationWorkspaceId: _workspaceId,
          projectId: _projectId,
          targetOrganizationMembershipId: _targetMembershipId,
        );
        await gateway.close();

        expect(result, isA<OrganizationProjectMembershipAssignmentRejected>());
        expect(
          (result as OrganizationProjectMembershipAssignmentRejected).code,
          OrganizationProjectMembershipAssignmentFailureCode.invalidResponse,
        );
      }
    },
  );

  test('maps network, timeout, and client failures without details', () async {
    final networkGateway = _gateway(
      (_) => Future<http.Response>.error(
        http.ClientException('database secret: do not expose'),
      ),
    );
    final networkResult = await networkGateway.assign(
      requestId: _requestId,
      organizationWorkspaceId: _workspaceId,
      projectId: _projectId,
      targetOrganizationMembershipId: _targetMembershipId,
    );
    await networkGateway.close();
    expect(
      (networkResult as OrganizationProjectMembershipAssignmentRejected).code,
      OrganizationProjectMembershipAssignmentFailureCode.networkUnavailable,
    );

    final timeoutGateway = HttpOrganizationProjectMembershipAssignmentGateway(
      baseUri: Uri.parse('https://backend.example.test'),
      identitySession: _identity(),
      client: MockClient(
        (_) => Future<http.Response>.delayed(
          const Duration(milliseconds: 50),
          () => _json(_receiptJson()),
        ),
      ),
      timeout: const Duration(milliseconds: 1),
    );
    final timeoutResult = await timeoutGateway.assign(
      requestId: _requestId,
      organizationWorkspaceId: _workspaceId,
      projectId: _projectId,
      targetOrganizationMembershipId: _targetMembershipId,
    );
    await timeoutGateway.close();
    expect(
      (timeoutResult as OrganizationProjectMembershipAssignmentRejected).code,
      OrganizationProjectMembershipAssignmentFailureCode.networkUnavailable,
    );

    final adapterGateway = _gateway(
      (_) => Future<http.Response>.error(StateError('provider secret')),
    );
    final adapterResult = await adapterGateway.assign(
      requestId: _requestId,
      organizationWorkspaceId: _workspaceId,
      projectId: _projectId,
      targetOrganizationMembershipId: _targetMembershipId,
    );
    await adapterGateway.close();
    expect(
      (adapterResult as OrganizationProjectMembershipAssignmentRejected).code,
      OrganizationProjectMembershipAssignmentFailureCode.invalidResponse,
    );
  });

  test(
    'close owns the HTTP client, is repeatable, and keeps identity open',
    () async {
      final identity = _identity();
      final client = _TrackingMockClient((_) async => _json(_receiptJson()));
      final gateway = HttpOrganizationProjectMembershipAssignmentGateway(
        baseUri: Uri.parse('https://backend.example.test'),
        identitySession: identity,
        client: client,
      );

      await gateway.close();
      await gateway.close();

      expect(client.closed, isTrue);
      expect(identity.isClosed, isFalse);
    },
  );

  test('account change while awaiting a token sends no HTTP request', () async {
    final identity = _ControllableIdentitySession();
    final token = Completer<IdentityResult<IdentityAccessToken>>();
    identity.accessTokenHandler = (_) => token.future;
    var requests = 0;
    final gateway = _gateway((_) async {
      requests++;
      return _json(_receiptJson());
    }, identity: identity);
    addTearDown(gateway.close);
    addTearDown(identity.close);

    final pending = gateway.assign(
      requestId: _requestId,
      organizationWorkspaceId: _workspaceId,
      projectId: _projectId,
      targetOrganizationMembershipId: _targetMembershipId,
    );
    await identity.tokenRequested.future;
    identity.emit(_otherIdentity);
    token.complete(_accessToken('new-account-token'));

    expect(_failureCode(await pending), _Failure.unauthorized);
    expect(requests, 0);
  });

  test('account change while refreshing a 401 does not retry', () async {
    final identity = _ControllableIdentitySession();
    final refreshing = Completer<void>();
    final token = Completer<IdentityResult<IdentityAccessToken>>();
    identity.accessTokenHandler = (forceRefresh) async {
      if (!forceRefresh) return _accessToken('original-token');
      refreshing.complete();
      return token.future;
    };
    var requests = 0;
    final gateway = _gateway((_) async {
      requests++;
      return _error('unauthenticated', 401);
    }, identity: identity);
    addTearDown(gateway.close);
    addTearDown(identity.close);

    final pending = gateway.assign(
      requestId: _requestId,
      organizationWorkspaceId: _workspaceId,
      projectId: _projectId,
      targetOrganizationMembershipId: _targetMembershipId,
    );
    await refreshing.future;
    identity.emit(_otherIdentity);
    token.complete(_accessToken('new-account-token'));

    expect(_failureCode(await pending), _Failure.unauthorized);
    expect(requests, 1);
    expect(identity.accessTokenForceRefreshValues, [false, true]);
  });

  test('HTTP sign-out and same-account sign-in ABA is unauthorized', () async {
    final identity = _ControllableIdentitySession();
    final sent = Completer<void>();
    final response = Completer<http.Response>();
    final gateway = _gateway((_) {
      sent.complete();
      return response.future;
    }, identity: identity);
    addTearDown(gateway.close);
    addTearDown(identity.close);

    final pending = gateway.assign(
      requestId: _requestId,
      organizationWorkspaceId: _workspaceId,
      projectId: _projectId,
      targetOrganizationMembershipId: _targetMembershipId,
    );
    await sent.future;
    identity.emit(const IdentitySnapshot.signedOut());
    identity.emit(identity.initial);
    response.complete(_json(_receiptJson()));

    expect(_failureCode(await pending), _Failure.unauthorized);
  });

  test('silent current identity drift is unauthorized', () async {
    final identity = _ControllableIdentitySession();
    final sent = Completer<void>();
    final response = Completer<http.Response>();
    final gateway = _gateway((_) {
      sent.complete();
      return response.future;
    }, identity: identity);
    addTearDown(gateway.close);
    addTearDown(identity.close);

    final pending = gateway.assign(
      requestId: _requestId,
      organizationWorkspaceId: _workspaceId,
      projectId: _projectId,
      targetOrganizationMembershipId: _targetMembershipId,
    );
    await sent.future;
    identity.setCurrentWithoutEmit(_otherIdentity);
    response.complete(_json(_receiptJson()));

    expect(_failureCode(await pending), _Failure.unauthorized);
  });

  test(
    'identity changes stream error and done invalidate the request',
    () async {
      for (final endChanges in [false, true]) {
        final identity = _ControllableIdentitySession();
        final sent = Completer<void>();
        final response = Completer<http.Response>();
        final gateway = _gateway((_) {
          sent.complete();
          return response.future;
        }, identity: identity);
        addTearDown(gateway.close);

        final pending = gateway.assign(
          requestId: _requestId,
          organizationWorkspaceId: _workspaceId,
          projectId: _projectId,
          targetOrganizationMembershipId: _targetMembershipId,
        );
        await sent.future;
        if (endChanges) {
          identity.finishChanges();
        } else {
          identity.addChangesError(StateError('identity stream failed'));
        }
        response.complete(_json(_receiptJson()));

        expect(_failureCode(await pending), _Failure.unauthorized);
        await identity.close();
      }
    },
  );

  test('close during token wait prevents HTTP delivery', () async {
    final identity = _ControllableIdentitySession();
    final token = Completer<IdentityResult<IdentityAccessToken>>();
    identity.accessTokenHandler = (_) => token.future;
    var requests = 0;
    final gateway = _gateway((_) async {
      requests++;
      return _json(_receiptJson());
    }, identity: identity);

    final pending = gateway.assign(
      requestId: _requestId,
      organizationWorkspaceId: _workspaceId,
      projectId: _projectId,
      targetOrganizationMembershipId: _targetMembershipId,
    );
    await identity.tokenRequested.future;
    await gateway.close();
    token.complete(_accessToken('closed-gateway-token'));

    expect(_failureCode(await pending), _Failure.unauthorized);
    expect(requests, 0);
    await identity.close();
  });

  test('close during HTTP prevents late success delivery', () async {
    final identity = _ControllableIdentitySession();
    final sent = Completer<void>();
    final response = Completer<http.Response>();
    final gateway = _gateway((_) {
      sent.complete();
      return response.future;
    }, identity: identity);

    final pending = gateway.assign(
      requestId: _requestId,
      organizationWorkspaceId: _workspaceId,
      projectId: _projectId,
      targetOrganizationMembershipId: _targetMembershipId,
    );
    await sent.future;
    await gateway.close();
    response.complete(_json(_receiptJson()));

    expect(_failureCode(await pending), _Failure.unauthorized);
    await identity.close();
  });

  test(
    'late transport and parsing failures after a fence break are unauthorized',
    () async {
      for (final error in <Object>[
        http.ClientException('late old-account failure'),
        const FormatException('late old-account parse failure'),
      ]) {
        final identity = _ControllableIdentitySession();
        final sent = Completer<void>();
        final response = Completer<http.Response>();
        final gateway = _gateway((_) {
          sent.complete();
          return response.future;
        }, identity: identity);
        addTearDown(gateway.close);
        addTearDown(identity.close);

        final pending = gateway.assign(
          requestId: _requestId,
          organizationWorkspaceId: _workspaceId,
          projectId: _projectId,
          targetOrganizationMembershipId: _targetMembershipId,
        );
        await sent.future;
        identity.emit(_otherIdentity);
        response.completeError(error);

        expect(_failureCode(await pending), _Failure.unauthorized);
      }
    },
  );

  test('cleanup start is covered by the final identity check', () async {
    late _ControllableIdentitySession identity;
    identity = _ControllableIdentitySession(
      onChangesCancel: () {
        identity.setCurrentWithoutEmit(_otherIdentity);
      },
    );
    final gateway = _gateway(
      (_) async => _json(_receiptJson()),
      identity: identity,
    );
    addTearDown(gateway.close);
    addTearDown(identity.close);

    final result = await gateway.assign(
      requestId: _requestId,
      organizationWorkspaceId: _workspaceId,
      projectId: _projectId,
      targetOrganizationMembershipId: _targetMembershipId,
    );

    expect(_failureCode(result), _Failure.unauthorized);
  });

  test(
    'cleanup gate and future errors do not delay or escape results',
    () async {
      for (final failCleanup in [false, true]) {
        final cancelStarted = Completer<void>();
        final finishCancel = Completer<void>();
        final identity = _ControllableIdentitySession(
          onChangesCancel: () {
            cancelStarted.complete();
            return finishCancel.future;
          },
        );
        final gateway = _gateway(
          (_) async => _json(_receiptJson()),
          identity: identity,
        );
        addTearDown(gateway.close);
        addTearDown(identity.close);

        final resultDelivered =
            Completer<OrganizationProjectMembershipAssignmentResult>();
        gateway
            .assign(
              requestId: _requestId,
              organizationWorkspaceId: _workspaceId,
              projectId: _projectId,
              targetOrganizationMembershipId: _targetMembershipId,
            )
            .then(
              resultDelivered.complete,
              onError: resultDelivered.completeError,
            );
        await cancelStarted.future;
        await Future<void>.delayed(Duration.zero);

        expect(resultDelivered.isCompleted, isTrue);
        expect(
          await resultDelivered.future,
          isA<OrganizationProjectMembershipAssignmentSuccess>(),
        );
        if (failCleanup) {
          finishCancel.completeError(StateError('test-only cleanup failure'));
        } else {
          finishCancel.complete();
        }
        await Future<void>.delayed(Duration.zero);
      }
    },
  );

  test(
    'same-account identity refresh does not invalidate the request',
    () async {
      final identity = _ControllableIdentitySession();
      final token = Completer<IdentityResult<IdentityAccessToken>>();
      identity.accessTokenHandler = (_) => token.future;
      final gateway = _gateway(
        (_) async => _json(_receiptJson()),
        identity: identity,
      );
      addTearDown(gateway.close);
      addTearDown(identity.close);

      final pending = gateway.assign(
        requestId: _requestId,
        organizationWorkspaceId: _workspaceId,
        projectId: _projectId,
        targetOrganizationMembershipId: _targetMembershipId,
      );
      await identity.tokenRequested.future;
      identity.emit(
        IdentitySnapshot(
          stage: IdentityStage.signedIn,
          principal: identity.initial.principal,
          expiresAt: DateTime.utc(2031),
        ),
      );
      token.complete(_accessToken('refreshed-same-account-token'));

      expect(
        await pending,
        isA<OrganizationProjectMembershipAssignmentSuccess>(),
      );
    },
  );
}

const _contractId = 'organization-project-membership-assignment:v1';
// These are deliberately valid 8-4-4-4-12 UUID-shaped values with non-RFC
// version/variant nibbles; the Backend wire contract accepts the shape only.
const _workspaceId = 'abcdefab-cdef-0abc-0def-abcdefabcdef';
const _otherWorkspaceId = 'abcdefab-cdef-0abc-0def-abcdefabcdea';
const _targetMembershipId = 'abcdefab-cdef-0abc-0def-abcdefabcdeb';
const _projectId = 'abcdefab-cdef-0abc-0def-abcdefabcdec';
const _projectMembershipId = 'abcdefab-cdef-0abc-0def-abcdefabcded';
const _requestId = 'abcdefab-cdef-0abc-0def-abcdefabcdee';

FakeIdentitySession _identity() => FakeIdentitySession(
  initial: const IdentitySnapshot(
    stage: IdentityStage.signedIn,
    principal: IdentityPrincipal(
      externalSubject: 'subject-1',
      email: 'owner@example.test',
    ),
  ),
);

HttpOrganizationProjectMembershipAssignmentGateway _gateway(
  Future<http.Response> Function(http.Request) handler, {
  IdentitySession? identity,
  http.Client? client,
  Duration timeout = const Duration(seconds: 15),
}) => HttpOrganizationProjectMembershipAssignmentGateway(
  baseUri: Uri.parse('https://backend.example.test'),
  identitySession: identity ?? _identity(),
  client: client ?? MockClient(handler),
  timeout: timeout,
);

typedef _Failure = OrganizationProjectMembershipAssignmentFailureCode;

_Failure _failureCode(Object result) => switch (result) {
  OrganizationProjectMembershipAssignmentRejected(:final code) => code,
  _ => throw StateError(
    'expected rejected project membership assignment result',
  ),
};

http.Response _json(
  Object value, {
  int status = 200,
  Map<String, String> headers = _jsonHeaders,
}) => http.Response(jsonEncode(value), status, headers: headers);

http.Response _raw(
  String body, {
  int status = 200,
  Map<String, String> headers = _jsonHeaders,
}) => http.Response(body, status, headers: headers);

http.Response _error(String code, int status) =>
    _json(_errorJson(code), status: status);

Map<String, Object?> _errorJson(String code) => {
  'error': {'code': code},
};

Map<String, Object?> _receiptJson() => {
  'project_membership_assignment_contract_id': _contractId,
  'organization_workspace_id': _workspaceId,
  'project_id': _projectId,
  'organization_membership_id': _targetMembershipId,
  'project_membership_id': _projectMembershipId,
  'active_from_utc': '2030-01-02T04:04:05.000Z',
  'inactive_from_utc': null,
};

const _jsonHeaders = {
  'content-type': 'application/json; charset=utf-8',
  'cache-control': 'no-store',
};

final class _TrackingMockClient extends MockClient {
  _TrackingMockClient(super.handler);

  bool closed = false;

  @override
  void close() {
    closed = true;
    super.close();
  }
}

final class _ControllableIdentitySession implements IdentitySession {
  _ControllableIdentitySession({FutureOr<void> Function()? onChangesCancel})
    : initial = const IdentitySnapshot(
        stage: IdentityStage.signedIn,
        principal: IdentityPrincipal(
          externalSubject: 'subject-1',
          email: 'owner@example.test',
        ),
      ),
      _current = const IdentitySnapshot(
        stage: IdentityStage.signedIn,
        principal: IdentityPrincipal(
          externalSubject: 'subject-1',
          email: 'owner@example.test',
        ),
      ),
      _changes = StreamController<IdentitySnapshot>(
        sync: true,
        onCancel: onChangesCancel,
      );

  final IdentitySnapshot initial;
  final StreamController<IdentitySnapshot> _changes;
  final List<bool> accessTokenForceRefreshValues = [];
  final Completer<void> tokenRequested = Completer<void>();
  IdentitySnapshot _current;
  Future<IdentityResult<IdentityAccessToken>> Function(bool)?
  accessTokenHandler;

  @override
  IdentitySnapshot get current => _current;

  @override
  Stream<IdentitySnapshot> get changes => _changes.stream;

  void emit(IdentitySnapshot snapshot) {
    _current = snapshot;
    _changes.add(snapshot);
  }

  void setCurrentWithoutEmit(IdentitySnapshot snapshot) => _current = snapshot;

  void addChangesError(Object error) => _changes.addError(error);

  Future<void> finishChanges() => _changes.close();

  @override
  Future<IdentityResult<IdentityAccessToken>> accessToken({
    bool forceRefresh = false,
  }) {
    accessTokenForceRefreshValues.add(forceRefresh);
    if (!tokenRequested.isCompleted) tokenRequested.complete();
    final handler = accessTokenHandler;
    return handler?.call(forceRefresh) ??
        Future.value(
          IdentitySuccess(
            IdentityAccessToken(
              value: forceRefresh
                  ? 'refreshed-test-access-token'
                  : 'stale-test-access-token',
              expiresAt: DateTime.utc(2030, 1, 2, 4, 4),
            ),
          ),
        );
  }

  @override
  Future<void> close() => _changes.close();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('unused test-only identity method');
}

IdentitySuccess<IdentityAccessToken> _accessToken(String value) =>
    IdentitySuccess(
      IdentityAccessToken(value: value, expiresAt: DateTime.utc(2030)),
    );

const _otherIdentity = IdentitySnapshot(
  stage: IdentityStage.signedIn,
  principal: IdentityPrincipal(externalSubject: 'subject-2', email: null),
);
