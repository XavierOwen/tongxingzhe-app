import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tongxingzhe_app/identity/identity_session.dart';
import 'package:tongxingzhe_app/organization_owner_transfer/http_organization_owner_transfer_gateway.dart';
import 'package:tongxingzhe_app/organization_owner_transfer/organization_owner_transfer.dart';

import '../support/fake_identity_session.dart';

void main() {
  test('sends the exact transfer contract and canonicalizes all UUIDs', () async {
    late http.Request request;
    final gateway = _gateway((value) async {
      request = value;
      return _json(_receiptJson());
    });
    addTearDown(gateway.close);

    final result = await gateway.transfer(
      requestId: _requestId.toUpperCase(),
      organizationWorkspaceId: _workspaceId.toUpperCase(),
      targetOrganizationMembershipId: _targetMembershipId.toUpperCase(),
    );

    expect(request.method, 'POST');
    expect(
      request.url,
      Uri.parse(
        'https://backend.example.test/v1/organizations/$_workspaceId/owner-transfer',
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
    expect(result, isA<OrganizationOwnerTransferSuccess>());
  });

  test('rejects each invalid UUID before identity or HTTP access', () async {
    const invalidInputs = [
      (
        requestId: 'not-a-uuid',
        workspaceId: _workspaceId,
        targetMembershipId: _targetMembershipId,
      ),
      (
        requestId: _requestId,
        workspaceId: 'not-a-uuid',
        targetMembershipId: _targetMembershipId,
      ),
      (
        requestId: _requestId,
        workspaceId: _workspaceId,
        targetMembershipId: 'not-a-uuid',
      ),
    ];

    for (final input in invalidInputs) {
      final identity = _identity();
      var requests = 0;
      final gateway = HttpOrganizationOwnerTransferGateway(
        baseUri: Uri.parse('https://backend.example.test'),
        identitySession: identity,
        client: MockClient((_) async {
          requests++;
          return _json(_receiptJson());
        }),
      );

      final result = await gateway.transfer(
        requestId: input.requestId,
        organizationWorkspaceId: input.workspaceId,
        targetOrganizationMembershipId: input.targetMembershipId,
      );
      await gateway.close();

      expect(result, isA<OrganizationOwnerTransferRejected>());
      expect(
        (result as OrganizationOwnerTransferRejected).code,
        OrganizationOwnerTransferFailureCode.invalidRequest,
      );
      expect(identity.accessTokenForceRefreshValues, isEmpty);
      expect(requests, 0);
    }
  });

  test('deferred gateway is no-network and close is repeatable', () async {
    const gateway = DeferredOrganizationOwnerTransferGateway();

    final result = await gateway.transfer(
      requestId: _requestId,
      organizationWorkspaceId: _workspaceId,
      targetOrganizationMembershipId: _targetMembershipId,
    );
    await gateway.close();
    await gateway.close();

    expect(result, isA<OrganizationOwnerTransferRejected>());
    expect(
      (result as OrganizationOwnerTransferRejected).code,
      OrganizationOwnerTransferFailureCode.notConfigured,
    );
  });

  test(
    'production factory uses deferred gateway when base URL is empty',
    () async {
      final identity = _identity();
      final gateway = productionOrganizationOwnerTransferGateway(identity);

      expect(gateway, isA<DeferredOrganizationOwnerTransferGateway>());
      await gateway.close();
      expect(identity.isClosed, isFalse);
    },
  );

  test('rejects invalid configured base URIs synchronously', () {
    final identity = _identity();
    final client = _TrackingMockClient((_) async => _json(_receiptJson()));

    expect(
      () => HttpOrganizationOwnerTransferGateway(
        baseUri: Uri.parse('https://backend.example.test/path'),
        identitySession: identity,
        client: client,
      ),
      throwsArgumentError,
    );
    expect(
      () => HttpOrganizationOwnerTransferGateway(
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
        expected: OrganizationOwnerTransferFailureCode.notConfigured,
      ),
      (
        failure: IdentityFailureCode.networkUnavailable,
        expected: OrganizationOwnerTransferFailureCode.networkUnavailable,
      ),
      (
        failure: IdentityFailureCode.sessionMissing,
        expected: OrganizationOwnerTransferFailureCode.unauthorized,
      ),
      (
        failure: IdentityFailureCode.providerRejected,
        expected: OrganizationOwnerTransferFailureCode.unauthorized,
      ),
      (
        failure: IdentityFailureCode.unknown,
        expected: OrganizationOwnerTransferFailureCode.unauthorized,
      ),
    ];

    for (final testCase in cases) {
      final identity = _identity();
      identity.rejectNextAccessTokenWith = IdentityFailure(
        code: testCase.failure,
      );
      var requests = 0;
      final gateway = HttpOrganizationOwnerTransferGateway(
        baseUri: Uri.parse('https://backend.example.test'),
        identitySession: identity,
        client: MockClient((_) async {
          requests++;
          return _json(_receiptJson());
        }),
      );

      final result = await gateway.transfer(
        requestId: _requestId,
        organizationWorkspaceId: _workspaceId,
        targetOrganizationMembershipId: _targetMembershipId,
      );
      await gateway.close();

      expect(result, isA<OrganizationOwnerTransferRejected>());
      expect(
        (result as OrganizationOwnerTransferRejected).code,
        testCase.expected,
        reason: '${testCase.failure}',
      );
      expect(requests, 0);
    }
  });

  test(
    'refreshes once for an exact 401 envelope and retries the same URL/body',
    () async {
      final identity = _RotatingTokenIdentitySession();
      final requests = <http.Request>[];
      final gateway = HttpOrganizationOwnerTransferGateway(
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

      final result = await gateway.transfer(
        requestId: _requestId,
        organizationWorkspaceId: _workspaceId,
        targetOrganizationMembershipId: _targetMembershipId,
      );

      expect(result, isA<OrganizationOwnerTransferSuccess>());
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

      final result = await gateway.transfer(
        requestId: _requestId,
        organizationWorkspaceId: _workspaceId,
        targetOrganizationMembershipId: _targetMembershipId,
      );
      await gateway.close();

      expect(result, isA<OrganizationOwnerTransferRejected>());
      expect(
        (result as OrganizationOwnerTransferRejected).code,
        OrganizationOwnerTransferFailureCode.invalidResponse,
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

    final result = await gateway.transfer(
      requestId: _requestId,
      organizationWorkspaceId: _workspaceId,
      targetOrganizationMembershipId: _targetMembershipId,
    );

    expect(result, isA<OrganizationOwnerTransferRejected>());
    expect(
      (result as OrganizationOwnerTransferRejected).code,
      OrganizationOwnerTransferFailureCode.unauthorized,
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

    final result = await gateway.transfer(
      requestId: _requestId,
      organizationWorkspaceId: _workspaceId,
      targetOrganizationMembershipId: _targetMembershipId,
    );

    expect(result, isA<OrganizationOwnerTransferRejected>());
    expect(
      (result as OrganizationOwnerTransferRejected).code,
      OrganizationOwnerTransferFailureCode.unauthorized,
    );
    expect(requests, 2);
    expect(identity.accessTokenForceRefreshValues, [false, true]);
  });

  test('accepts the exact five-field receipt and preserves UTC time', () async {
    final gateway = _gateway((_) async => _json(_receiptJson()));
    addTearDown(gateway.close);

    final result = await gateway.transfer(
      requestId: _requestId,
      organizationWorkspaceId: _workspaceId,
      targetOrganizationMembershipId: _targetMembershipId,
    );

    expect(result, isA<OrganizationOwnerTransferSuccess>());
    final receipt = (result as OrganizationOwnerTransferSuccess).receipt;
    expect(receipt.ownerTransferContractId, _contractId);
    expect(receipt.organizationWorkspaceId, _workspaceId);
    expect(receipt.previousOwnerAssignmentId, _previousOwnerAssignmentId);
    expect(receipt.organizationOwnerAssignmentId, _ownerAssignmentId);
    expect(receipt.effectiveAtUtc, DateTime.utc(2030, 1, 2, 4, 4, 5));
    expect(receipt.effectiveAtUtc.isUtc, isTrue);
  });

  test(
    'rejects receipt shape, identity, contract, workspace, and time drift',
    () async {
      final cases = <String, String>{
        'malformed JSON': '{',
        'non-object JSON': '[]',
        'extra field': jsonEncode({..._receiptJson(), 'extra': true}),
        'missing field': jsonEncode(
          _receiptJson()..remove('organization_owner_assignment_id'),
        ),
        'bad contract': jsonEncode({
          ..._receiptJson(),
          'owner_transfer_contract_id': 'other:v1',
        }),
        'bad UUID': jsonEncode({
          ..._receiptJson(),
          'previous_owner_assignment_id': 'not-a-uuid',
        }),
        'wrong field type': jsonEncode({
          ..._receiptJson(),
          'effective_at_utc': 20300102,
        }),
        'uppercase UUID': jsonEncode({
          ..._receiptJson(),
          'organization_owner_assignment_id': _ownerAssignmentId.toUpperCase(),
        }),
        'wrong workspace': jsonEncode({
          ..._receiptJson(),
          'organization_workspace_id': _otherWorkspaceId,
        }),
        'non-canonical UTC': jsonEncode({
          ..._receiptJson(),
          'effective_at_utc': '2030-01-02T04:04:05Z',
        }),
        'offset timestamp': jsonEncode({
          ..._receiptJson(),
          'effective_at_utc': '2030-01-01T22:04:05.000-06:00',
        }),
        'invalid calendar date': jsonEncode({
          ..._receiptJson(),
          'effective_at_utc': '2030-02-30T04:04:05.000Z',
        }),
      };

      for (final entry in cases.entries) {
        final gateway = _gateway((_) async => _raw(entry.value));
        final result = await gateway.transfer(
          requestId: _requestId,
          organizationWorkspaceId: _workspaceId,
          targetOrganizationMembershipId: _targetMembershipId,
        );
        await gateway.close();

        expect(
          result,
          isA<OrganizationOwnerTransferRejected>(),
          reason: entry.key,
        );
        expect(
          (result as OrganizationOwnerTransferRejected).code,
          OrganizationOwnerTransferFailureCode.invalidResponse,
          reason: entry.key,
        );
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
      final result = await gateway.transfer(
        requestId: _requestId,
        organizationWorkspaceId: _workspaceId,
        targetOrganizationMembershipId: _targetMembershipId,
      );
      await gateway.close();

      expect(result, isA<OrganizationOwnerTransferRejected>());
      expect(
        (result as OrganizationOwnerTransferRejected).code,
        OrganizationOwnerTransferFailureCode.invalidResponse,
      );
    }
  });

  test('maps every stable error envelope', () async {
    const cases =
        <
          ({
            int status,
            String code,
            OrganizationOwnerTransferFailureCode failure,
          })
        >[
          (
            status: 400,
            code: 'invalid_json',
            failure: OrganizationOwnerTransferFailureCode.invalidJson,
          ),
          (
            status: 400,
            code: 'invalid_organization_owner_transfer_request',
            failure: OrganizationOwnerTransferFailureCode.invalidRequest,
          ),
          (
            status: 401,
            code: 'unauthenticated',
            failure: OrganizationOwnerTransferFailureCode.unauthorized,
          ),
          (
            status: 403,
            code: 'organization_owner_transfer_forbidden',
            failure: OrganizationOwnerTransferFailureCode.forbidden,
          ),
          (
            status: 409,
            code: 'organization_owner_transfer_conflict',
            failure: OrganizationOwnerTransferFailureCode.conflict,
          ),
          (
            status: 409,
            code: 'organization_owner_transfer_target_already_owner',
            failure: OrganizationOwnerTransferFailureCode.targetAlreadyOwner,
          ),
          (
            status: 413,
            code: 'payload_too_large',
            failure: OrganizationOwnerTransferFailureCode.payloadTooLarge,
          ),
          (
            status: 503,
            code: 'organization_owner_transfer_unavailable',
            failure: OrganizationOwnerTransferFailureCode.serviceUnavailable,
          ),
        ];

    for (final testCase in cases) {
      final gateway = _gateway(
        (_) async => _error(testCase.code, testCase.status),
      );
      final result = await gateway.transfer(
        requestId: _requestId,
        organizationWorkspaceId: _workspaceId,
        targetOrganizationMembershipId: _targetMembershipId,
      );
      await gateway.close();

      expect(result, isA<OrganizationOwnerTransferRejected>());
      expect(
        (result as OrganizationOwnerTransferRejected).code,
        testCase.failure,
        reason: '${testCase.status} ${testCase.code}',
      );
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
        final result = await gateway.transfer(
          requestId: _requestId,
          organizationWorkspaceId: _workspaceId,
          targetOrganizationMembershipId: _targetMembershipId,
        );
        await gateway.close();

        expect(result, isA<OrganizationOwnerTransferRejected>());
        expect(
          (result as OrganizationOwnerTransferRejected).code,
          OrganizationOwnerTransferFailureCode.invalidResponse,
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
    final networkResult = await networkGateway.transfer(
      requestId: _requestId,
      organizationWorkspaceId: _workspaceId,
      targetOrganizationMembershipId: _targetMembershipId,
    );
    await networkGateway.close();
    expect(
      (networkResult as OrganizationOwnerTransferRejected).code,
      OrganizationOwnerTransferFailureCode.networkUnavailable,
    );

    final timeoutGateway = HttpOrganizationOwnerTransferGateway(
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
    final timeoutResult = await timeoutGateway.transfer(
      requestId: _requestId,
      organizationWorkspaceId: _workspaceId,
      targetOrganizationMembershipId: _targetMembershipId,
    );
    await timeoutGateway.close();
    expect(
      (timeoutResult as OrganizationOwnerTransferRejected).code,
      OrganizationOwnerTransferFailureCode.networkUnavailable,
    );

    final adapterGateway = _gateway(
      (_) => Future<http.Response>.error(StateError('provider secret')),
    );
    final adapterResult = await adapterGateway.transfer(
      requestId: _requestId,
      organizationWorkspaceId: _workspaceId,
      targetOrganizationMembershipId: _targetMembershipId,
    );
    await adapterGateway.close();
    expect(
      (adapterResult as OrganizationOwnerTransferRejected).code,
      OrganizationOwnerTransferFailureCode.invalidResponse,
    );
  });

  test(
    'close owns the HTTP client, is repeatable, and keeps identity open',
    () async {
      final identity = _identity();
      final client = _TrackingMockClient((_) async => _json(_receiptJson()));
      final gateway = HttpOrganizationOwnerTransferGateway(
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
}

const _contractId = 'organization-owner-transfer:v1';
// These are deliberately valid 8-4-4-4-12 UUID-shaped values with non-RFC
// version/variant nibbles; the Backend wire contract accepts the shape only.
const _workspaceId = 'abcdefab-cdef-0abc-0def-abcdefabcdef';
const _otherWorkspaceId = 'abcdefab-cdef-0abc-0def-abcdefabcdea';
const _targetMembershipId = 'abcdefab-cdef-0abc-0def-abcdefabcdeb';
const _previousOwnerAssignmentId = 'abcdefab-cdef-0abc-0def-abcdefabcdec';
const _ownerAssignmentId = 'abcdefab-cdef-0abc-0def-abcdefabcded';
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

HttpOrganizationOwnerTransferGateway _gateway(
  Future<http.Response> Function(http.Request) handler, {
  FakeIdentitySession? identity,
  http.Client? client,
  Duration timeout = const Duration(seconds: 15),
}) => HttpOrganizationOwnerTransferGateway(
  baseUri: Uri.parse('https://backend.example.test'),
  identitySession: identity ?? _identity(),
  client: client ?? MockClient(handler),
  timeout: timeout,
);

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
  'owner_transfer_contract_id': _contractId,
  'organization_workspace_id': _workspaceId,
  'previous_owner_assignment_id': _previousOwnerAssignmentId,
  'organization_owner_assignment_id': _ownerAssignmentId,
  'effective_at_utc': '2030-01-02T04:04:05.000Z',
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

final class _RotatingTokenIdentitySession implements IdentitySession {
  final List<bool> accessTokenForceRefreshValues = [];

  @override
  Future<IdentityResult<IdentityAccessToken>> accessToken({
    bool forceRefresh = false,
  }) async {
    accessTokenForceRefreshValues.add(forceRefresh);
    return IdentitySuccess(
      IdentityAccessToken(
        value: forceRefresh
            ? 'refreshed-test-access-token'
            : 'stale-test-access-token',
        expiresAt: DateTime.utc(2030, 1, 2, 4, 4),
      ),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('unused test-only identity method');
}
