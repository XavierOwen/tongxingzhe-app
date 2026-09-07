import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tongxingzhe_app/foundation/backend_base_uri.dart';
import 'package:tongxingzhe_app/identity/identity_session.dart';
import 'package:tongxingzhe_app/organization_membership_self_leave/http_organization_membership_self_leave_gateway.dart';
import 'package:tongxingzhe_app/organization_membership_self_leave/organization_membership_self_leave.dart';

import '../support/fake_identity_session.dart';

void main() {
  test('sends exact contract and canonicalizes input UUIDs', () async {
    late http.Request request;
    final gateway = _gateway((value) async {
      request = value;
      return _json(_receiptJson());
    });
    addTearDown(gateway.close);

    final result = await gateway.leave(
      requestId: _requestId.toUpperCase(),
      organizationWorkspaceId: _workspaceId.toUpperCase(),
    );

    expect(request.method, 'POST');
    expect(
      request.url,
      Uri.parse(
        'https://backend.example.test/v1/organizations/$_workspaceId/membership-self-leave',
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
    expect(request.body, jsonEncode({'request_id': _requestId}));
    expect(jsonDecode(request.body), {'request_id': _requestId});
    expect(result, isA<OrganizationMembershipSelfLeaveSuccess>());
  });

  test('rejects each invalid UUID before identity or HTTP access', () async {
    const inputs = [
      (requestId: 'not-a-uuid', workspaceId: _workspaceId),
      (requestId: _requestId, workspaceId: 'not-a-uuid'),
    ];

    for (final input in inputs) {
      final identity = _identity();
      var requests = 0;
      final gateway = HttpOrganizationMembershipSelfLeaveGateway(
        baseUri: Uri.parse('https://backend.example.test'),
        identitySession: identity,
        client: MockClient((_) async {
          requests++;
          return _json(_receiptJson());
        }),
      );

      final result = await gateway.leave(
        requestId: input.requestId,
        organizationWorkspaceId: input.workspaceId,
      );
      await gateway.close();

      expect(_failureCode(result), _Failure.invalidRequest);
      expect(identity.accessTokenForceRefreshValues, isEmpty);
      expect(requests, 0);
    }
  });

  test('deferred gateway is no-network and repeatably closeable', () async {
    const gateway = DeferredOrganizationMembershipSelfLeaveGateway();

    final result = await gateway.leave(
      requestId: _requestId,
      organizationWorkspaceId: _workspaceId,
    );
    await gateway.close();
    await gateway.close();

    expect(_failureCode(result), _Failure.notConfigured);
  });

  test(
    'production factory defers empty config, accepts valid, and rejects invalid',
    () async {
      const configured = String.fromEnvironment('BACKEND_BASE_URL');
      final identity = _identity();
      var validConfiguredUri = false;
      if (configured.trim().isNotEmpty) {
        try {
          validatePathlessBackendBaseUri(Uri.parse(configured.trim()));
          validConfiguredUri = true;
        } on ArgumentError {
          validConfiguredUri = false;
        } on FormatException {
          validConfiguredUri = false;
        }
      }

      if (configured.trim().isEmpty || validConfiguredUri) {
        final gateway = productionOrganizationMembershipSelfLeaveGateway(
          identity,
        );
        expect(
          gateway,
          validConfiguredUri
              ? isA<HttpOrganizationMembershipSelfLeaveGateway>()
              : isA<DeferredOrganizationMembershipSelfLeaveGateway>(),
        );
        await gateway.close();
      } else {
        expect(
          () => productionOrganizationMembershipSelfLeaveGateway(identity),
          anyOf(throwsArgumentError, throwsFormatException),
        );
      }
      expect(identity.accessTokenForceRefreshValues, isEmpty);
      expect(identity.isClosed, isFalse);
    },
  );

  test('rejects invalid base URIs synchronously', () {
    final identity = _identity();
    final client = _TrackingMockClient((_) async => _json(_receiptJson()));

    for (final uri in [
      Uri.parse('https://backend.example.test/path'),
      Uri.parse('http://backend.example.test'),
    ]) {
      expect(
        () => HttpOrganizationMembershipSelfLeaveGateway(
          baseUri: uri,
          identitySession: identity,
          client: client,
        ),
        throwsArgumentError,
      );
    }
    expect(client.closeCount, 0);
    expect(identity.accessTokenForceRefreshValues, isEmpty);
  });

  test('maps identity failures without sending a request', () async {
    const cases = [
      (IdentityFailureCode.notConfigured, _Failure.notConfigured),
      (IdentityFailureCode.networkUnavailable, _Failure.networkUnavailable),
      (IdentityFailureCode.sessionMissing, _Failure.unauthorized),
      (IdentityFailureCode.providerRejected, _Failure.unauthorized),
      (IdentityFailureCode.unknown, _Failure.unauthorized),
    ];

    for (final testCase in cases) {
      final identity = _identity();
      identity.rejectNextAccessTokenWith = IdentityFailure(code: testCase.$1);
      var requests = 0;
      final gateway = _gateway((_) async {
        requests++;
        return _json(_receiptJson());
      }, identity: identity);

      final result = await gateway.leave(
        requestId: _requestId,
        organizationWorkspaceId: _workspaceId,
      );
      await gateway.close();

      expect(_failureCode(result), testCase.$2, reason: '${testCase.$1}');
      expect(requests, 0);
    }
  });

  test('exact 401 refreshes once and retries identical URL/body', () async {
    final identity = _RotatingTokenIdentitySession();
    final requests = <http.Request>[];
    final gateway = HttpOrganizationMembershipSelfLeaveGateway(
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

    final result = await gateway.leave(
      requestId: _requestId,
      organizationWorkspaceId: _workspaceId,
    );

    expect(result, isA<OrganizationMembershipSelfLeaveSuccess>());
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
  });

  test(
    'account change during token wait never sends the old leave intent',
    () async {
      final identity = _RotatingTokenIdentitySession();
      final token = Completer<IdentityResult<IdentityAccessToken>>();
      identity.tokenResult = (_) => token.future;
      var requests = 0;
      final gateway = HttpOrganizationMembershipSelfLeaveGateway(
        baseUri: Uri.parse('https://backend.example.test'),
        identitySession: identity,
        client: MockClient((_) async {
          requests++;
          return _json(_receiptJson());
        }),
      );
      addTearDown(gateway.close);
      addTearDown(identity.close);

      final pending = gateway.leave(
        requestId: _requestId,
        organizationWorkspaceId: _workspaceId,
      );
      identity.emit(_otherIdentity);
      token.complete(
        const IdentitySuccess(
          IdentityAccessToken(value: 'new-account-token', expiresAt: null),
        ),
      );

      final result = await pending;
      expect(requests, 0);
      expect(_failureCode(result), _Failure.unauthorized);
    },
  );

  test(
    'account change during 401 refresh never retries with the new token',
    () async {
      final identity = _RotatingTokenIdentitySession();
      final refreshing = Completer<void>();
      final token = Completer<IdentityResult<IdentityAccessToken>>();
      identity.tokenResult = (forceRefresh) async {
        if (!forceRefresh) {
          return const IdentitySuccess(
            IdentityAccessToken(value: 'original-token', expiresAt: null),
          );
        }
        refreshing.complete();
        return token.future;
      };
      var requests = 0;
      final gateway = HttpOrganizationMembershipSelfLeaveGateway(
        baseUri: Uri.parse('https://backend.example.test'),
        identitySession: identity,
        client: MockClient((_) async {
          requests++;
          return requests == 1
              ? _error('unauthenticated', 401)
              : _json(_receiptJson());
        }),
      );
      addTearDown(gateway.close);
      addTearDown(identity.close);

      final pending = gateway.leave(
        requestId: _requestId,
        organizationWorkspaceId: _workspaceId,
      );
      await refreshing.future;
      identity.emit(_otherIdentity);
      token.complete(
        const IdentitySuccess(
          IdentityAccessToken(value: 'new-account-token', expiresAt: null),
        ),
      );

      final result = await pending;
      expect(requests, 1);
      expect(_failureCode(result), _Failure.unauthorized);
    },
  );

  test(
    'sign-out and return to the same account cannot revive an in-flight leave',
    () async {
      final identity = _RotatingTokenIdentitySession();
      final token = Completer<IdentityResult<IdentityAccessToken>>();
      identity.tokenResult = (_) => token.future;
      var requests = 0;
      final gateway = HttpOrganizationMembershipSelfLeaveGateway(
        baseUri: Uri.parse('https://backend.example.test'),
        identitySession: identity,
        client: MockClient((_) async {
          requests++;
          return _json(_receiptJson());
        }),
      );
      addTearDown(gateway.close);
      addTearDown(identity.close);

      final original = identity.current;
      final pending = gateway.leave(
        requestId: _requestId,
        organizationWorkspaceId: _workspaceId,
      );
      identity.emit(const IdentitySnapshot.signedOut());
      identity.emit(original);
      token.complete(
        const IdentitySuccess(
          IdentityAccessToken(value: 'returned-account-token', expiresAt: null),
        ),
      );

      final result = await pending;
      expect(requests, 0);
      expect(_failureCode(result), _Failure.unauthorized);
    },
  );

  test('malformed 401 does not refresh', () async {
    final cases = <http.Response Function()>[
      () => _json(
        _errorJson('unauthenticated'),
        status: 401,
        headers: const {'cache-control': 'no-store'},
      ),
      () => _raw('{', status: 401),
      () => _error('other', 401),
      () => _json({
        'error': {'code': 'unauthenticated'},
        'extra': true,
      }, status: 401),
    ];

    for (final response in cases) {
      final identity = _identity();
      var requests = 0;
      final gateway = _gateway((_) async {
        requests++;
        return response();
      }, identity: identity);

      final result = await gateway.leave(
        requestId: _requestId,
        organizationWorkspaceId: _workspaceId,
      );
      await gateway.close();

      expect(_failureCode(result), _Failure.invalidResponse);
      expect(requests, 1);
      expect(identity.accessTokenForceRefreshValues, [false]);
    }
  });

  test(
    'late success after account change is not returned to the new account',
    () async {
      final identity = _RotatingTokenIdentitySession();
      final sent = Completer<void>();
      final response = Completer<http.Response>();
      final gateway = HttpOrganizationMembershipSelfLeaveGateway(
        baseUri: Uri.parse('https://backend.example.test'),
        identitySession: identity,
        client: MockClient((_) {
          sent.complete();
          return response.future;
        }),
      );
      addTearDown(gateway.close);
      addTearDown(identity.close);

      final pending = gateway.leave(
        requestId: _requestId,
        organizationWorkspaceId: _workspaceId,
      );
      await sent.future;
      identity.emit(_otherIdentity);
      response.complete(_json(_receiptJson()));

      expect(_failureCode(await pending), _Failure.unauthorized);
      expect(identity.accessTokenForceRefreshValues, [false]);
    },
  );

  test(
    'close during token wait prevents HTTP, while same-account refresh remains valid',
    () async {
      for (final closeDuringWait in [true, false]) {
        final identity = _RotatingTokenIdentitySession();
        final token = Completer<IdentityResult<IdentityAccessToken>>();
        identity.tokenResult = (_) => token.future;
        var requests = 0;
        final gateway = HttpOrganizationMembershipSelfLeaveGateway(
          baseUri: Uri.parse('https://backend.example.test'),
          identitySession: identity,
          client: MockClient((_) async {
            requests++;
            return _json(_receiptJson());
          }),
        );
        final pending = gateway.leave(
          requestId: _requestId,
          organizationWorkspaceId: _workspaceId,
        );
        if (closeDuringWait) {
          await gateway.close();
        } else {
          identity.emit(
            IdentitySnapshot(
              stage: IdentityStage.signedIn,
              principal: identity.current.principal,
              expiresAt: DateTime.utc(2031),
            ),
          );
        }
        token.complete(
          const IdentitySuccess(
            IdentityAccessToken(
              value: 'refreshed-same-account-token',
              expiresAt: null,
            ),
          ),
        );
        final result = await pending;
        expect(requests, closeDuringWait ? 0 : 1);
        if (closeDuringWait) {
          expect(_failureCode(result), _Failure.unauthorized);
        } else {
          expect(result, isA<OrganizationMembershipSelfLeaveSuccess>());
        }
        await gateway.close();
        await identity.close();
      }
    },
  );

  test('forced refresh failure does not send a second request', () async {
    final identity = _identity();
    var requests = 0;
    final gateway = _gateway((_) async {
      requests++;
      identity.rejectNextAccessTokenWith = const IdentityFailure(
        code: IdentityFailureCode.sessionMissing,
      );
      return _error('unauthenticated', 401);
    }, identity: identity);
    addTearDown(gateway.close);

    final result = await gateway.leave(
      requestId: _requestId,
      organizationWorkspaceId: _workspaceId,
    );

    expect(_failureCode(result), _Failure.unauthorized);
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

    final result = await gateway.leave(
      requestId: _requestId,
      organizationWorkspaceId: _workspaceId,
    );

    expect(_failureCode(result), _Failure.unauthorized);
    expect(requests, 2);
    expect(identity.accessTokenForceRefreshValues, [false, true]);
  });

  test('accepts exact four-field receipt and preserves UTC time', () async {
    final gateway = _gateway((_) async => _json(_receiptJson()));
    addTearDown(gateway.close);

    final result = await gateway.leave(
      requestId: _requestId,
      organizationWorkspaceId: _workspaceId,
    );

    expect(result, isA<OrganizationMembershipSelfLeaveSuccess>());
    final receipt = (result as OrganizationMembershipSelfLeaveSuccess).receipt;
    expect(receipt.membershipSelfLeaveContractId, _contractId);
    expect(receipt.organizationWorkspaceId, _workspaceId);
    expect(receipt.organizationMembershipId, _membershipId);
    expect(receipt.effectiveAtUtc, DateTime.utc(2030, 1, 2, 4, 4, 5));
    expect(receipt.effectiveAtUtc.isUtc, isTrue);
  });

  test('rejects receipt shape, identity, contract, and time drift', () async {
    final cases = <String, String>{
      'malformed JSON': '{',
      'non-object JSON': '[]',
      'extra field': jsonEncode({..._receiptJson(), 'extra': true}),
      'missing field': jsonEncode(
        _receiptJson()..remove('organization_membership_id'),
      ),
      'bad contract': jsonEncode({
        ..._receiptJson(),
        'membership_self_leave_contract_id': 'other:v1',
      }),
      'bad UUID': jsonEncode({
        ..._receiptJson(),
        'organization_membership_id': 'not-a-uuid',
      }),
      'wrong type': jsonEncode({
        ..._receiptJson(),
        'effective_at_utc': 20300102,
      }),
      'uppercase workspace UUID': jsonEncode({
        ..._receiptJson(),
        'organization_workspace_id': _workspaceId.toUpperCase(),
      }),
      'uppercase membership UUID': jsonEncode({
        ..._receiptJson(),
        'organization_membership_id': _membershipId.toUpperCase(),
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
      final result = await gateway.leave(
        requestId: _requestId,
        organizationWorkspaceId: _workspaceId,
      );
      await gateway.close();

      expect(_failureCode(result), _Failure.invalidResponse, reason: entry.key);
    }
  });

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
      final result = await gateway.leave(
        requestId: _requestId,
        organizationWorkspaceId: _workspaceId,
      );
      await gateway.close();

      expect(_failureCode(result), _Failure.invalidResponse);
    }
  });

  test('maps every stable error envelope', () async {
    const cases = <({int status, String code, _Failure failure})>[
      (status: 400, code: 'invalid_json', failure: _Failure.invalidJson),
      (
        status: 400,
        code: 'invalid_organization_membership_self_leave_request',
        failure: _Failure.invalidRequest,
      ),
      (status: 401, code: 'unauthenticated', failure: _Failure.unauthorized),
      (
        status: 403,
        code: 'organization_membership_self_leave_forbidden',
        failure: _Failure.forbidden,
      ),
      (
        status: 409,
        code: 'organization_membership_self_leave_conflict',
        failure: _Failure.conflict,
      ),
      (
        status: 413,
        code: 'payload_too_large',
        failure: _Failure.payloadTooLarge,
      ),
      (
        status: 503,
        code: 'organization_membership_self_leave_unavailable',
        failure: _Failure.serviceUnavailable,
      ),
    ];

    for (final testCase in cases) {
      final gateway = _gateway(
        (_) async => _error(testCase.code, testCase.status),
      );
      final result = await gateway.leave(
        requestId: _requestId,
        organizationWorkspaceId: _workspaceId,
      );
      await gateway.close();

      expect(
        _failureCode(result),
        testCase.failure,
        reason: '${testCase.status} ${testCase.code}',
      );
    }
  });

  test('unknown or drifting responses fail closed', () async {
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
      final result = await gateway.leave(
        requestId: _requestId,
        organizationWorkspaceId: _workspaceId,
      );
      await gateway.close();

      expect(_failureCode(result), _Failure.invalidResponse);
    }
  });

  test('separates network and adapter failures without details', () async {
    final networkGateway = _gateway(
      (_) => Future<http.Response>.error(
        http.ClientException('database secret: do not expose'),
      ),
    );
    final networkResult = await networkGateway.leave(
      requestId: _requestId,
      organizationWorkspaceId: _workspaceId,
    );
    await networkGateway.close();
    expect(_failureCode(networkResult), _Failure.networkUnavailable);

    final timeoutGateway = HttpOrganizationMembershipSelfLeaveGateway(
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
    final timeoutResult = await timeoutGateway.leave(
      requestId: _requestId,
      organizationWorkspaceId: _workspaceId,
    );
    await timeoutGateway.close();
    expect(_failureCode(timeoutResult), _Failure.networkUnavailable);

    final adapterGateway = _gateway(
      (_) => Future<http.Response>.error(StateError('provider secret')),
    );
    final adapterResult = await adapterGateway.leave(
      requestId: _requestId,
      organizationWorkspaceId: _workspaceId,
    );
    await adapterGateway.close();
    expect(_failureCode(adapterResult), _Failure.invalidResponse);
  });

  test('close owns client once and keeps shared identity open', () async {
    final identity = _identity();
    final client = _TrackingMockClient((_) async => _json(_receiptJson()));
    final gateway = HttpOrganizationMembershipSelfLeaveGateway(
      baseUri: Uri.parse('https://backend.example.test'),
      identitySession: identity,
      client: client,
    );

    await gateway.close();
    await gateway.close();

    expect(client.closeCount, 1);
    expect(identity.isClosed, isFalse);
  });
}

typedef _Failure = OrganizationMembershipSelfLeaveFailureCode;

const _contractId = 'organization-membership-self-leave:v1';
const _workspaceId = 'abcdefab-cdef-0abc-0def-abcdefabcdef';
const _otherWorkspaceId = 'abcdefab-cdef-0abc-0def-abcdefabcdea';
const _membershipId = 'abcdefab-cdef-0abc-0def-abcdefabcdeb';
const _requestId = 'abcdefab-cdef-0abc-0def-abcdefabcdec';

_Failure _failureCode(OrganizationMembershipSelfLeaveResult result) =>
    (result as OrganizationMembershipSelfLeaveRejected).code;

FakeIdentitySession _identity() => FakeIdentitySession(
  initial: const IdentitySnapshot(
    stage: IdentityStage.signedIn,
    principal: IdentityPrincipal(
      externalSubject: 'subject-1',
      email: 'member@example.test',
    ),
  ),
);

HttpOrganizationMembershipSelfLeaveGateway _gateway(
  Future<http.Response> Function(http.Request) handler, {
  FakeIdentitySession? identity,
  http.Client? client,
  Duration timeout = const Duration(seconds: 15),
}) => HttpOrganizationMembershipSelfLeaveGateway(
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
  'membership_self_leave_contract_id': _contractId,
  'organization_workspace_id': _workspaceId,
  'organization_membership_id': _membershipId,
  'effective_at_utc': '2030-01-02T04:04:05.000Z',
};

const _jsonHeaders = {
  'content-type': 'application/json; charset=utf-8',
  'cache-control': 'no-store',
};

final class _TrackingMockClient extends MockClient {
  _TrackingMockClient(super.handler);

  int closeCount = 0;

  @override
  void close() {
    closeCount++;
    super.close();
  }
}

final class _RotatingTokenIdentitySession implements IdentitySession {
  final List<bool> accessTokenForceRefreshValues = [];
  final _changes = StreamController<IdentitySnapshot>.broadcast(sync: true);
  IdentitySnapshot _current = const IdentitySnapshot(
    stage: IdentityStage.signedIn,
    principal: IdentityPrincipal(externalSubject: 'subject-1', email: null),
  );
  Future<IdentityResult<IdentityAccessToken>> Function(bool)? tokenResult;

  @override
  IdentitySnapshot get current => _current;

  @override
  Stream<IdentitySnapshot> get changes => _changes.stream;

  void emit(IdentitySnapshot snapshot) {
    _current = snapshot;
    _changes.add(snapshot);
  }

  @override
  Future<void> close() => _changes.close();

  @override
  Future<IdentityResult<IdentityAccessToken>> accessToken({
    bool forceRefresh = false,
  }) async {
    accessTokenForceRefreshValues.add(forceRefresh);
    if (tokenResult case final result?) return result(forceRefresh);
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

const _otherIdentity = IdentitySnapshot(
  stage: IdentityStage.signedIn,
  principal: IdentityPrincipal(externalSubject: 'subject-2', email: null),
);
