import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tongxingzhe_app/identity/identity_session.dart';
import 'package:tongxingzhe_app/organization_creation/http_organization_creation_gateway.dart';
import 'package:tongxingzhe_app/organization_creation/organization_creation.dart';

import '../support/fake_identity_session.dart';

void main() {
  test(
    'sends the exact POST contract without rewriting the display name',
    () async {
      late http.Request request;
      const displayName = '  Café ／ 团队  ';
      final gateway = _gateway((value) async {
        request = value;
        return _json(_receiptJson());
      });
      addTearDown(gateway.close);

      final result = await gateway.create(
        requestId: _requestId,
        displayName: displayName,
      );

      expect(request.method, 'POST');
      expect(request.url.scheme, 'https');
      expect(request.url.host, 'backend.example.test');
      expect(request.url.path, '/v1/organizations');
      expect(request.url.query, isEmpty);
      expect(request.url.fragment, isEmpty);
      expect(request.headers, {
        'accept': 'application/json',
        'authorization': 'Bearer test-only-access-token',
        'content-type': 'application/json; charset=utf-8',
      });
      expect(
        request.body,
        jsonEncode({'request_id': _requestId, 'display_name': displayName}),
      );
      expect(jsonDecode(request.body), {
        'request_id': _requestId,
        'display_name': displayName,
      });
      expect(result, isA<OrganizationCreationSuccess>());
    },
  );

  test('rejects a non-canonical UUID before identity or HTTP access', () async {
    final identity = _identity();
    var requests = 0;
    final gateway = HttpOrganizationCreationGateway(
      baseUri: Uri.parse('https://backend.example.test'),
      identitySession: identity,
      client: MockClient((_) async {
        requests++;
        return _json(_receiptJson());
      }),
    );
    addTearDown(gateway.close);

    final result = await gateway.create(
      requestId: _requestId.toUpperCase(),
      displayName: 'Acme',
    );

    expect(result, isA<OrganizationCreationRejected>());
    expect(
      (result as OrganizationCreationRejected).code,
      OrganizationCreationFailureCode.invalidRequest,
    );
    expect(identity.accessTokenForceRefreshValues, isEmpty);
    expect(requests, 0);
  });

  test('accepts the exact five-field receipt', () async {
    final gateway = _gateway((_) async => _json(_receiptJson()));
    addTearDown(gateway.close);

    final result = await gateway.create(
      requestId: _requestId,
      displayName: 'Acme',
    );

    expect(result, isA<OrganizationCreationSuccess>());
    final receipt = (result as OrganizationCreationSuccess).receipt;
    expect(receipt.creationContractId, _contractId);
    expect(receipt.organizationWorkspaceId, _workspaceId);
    expect(receipt.organizationMembershipId, _membershipId);
    expect(receipt.organizationOwnerAssignmentId, _ownerAssignmentId);
    expect(receipt.createdAtUtc, DateTime.utc(2030, 1, 2, 4, 4, 5));
    expect(receipt.createdAtUtc.isUtc, isTrue);
  });

  test('401 refreshes once and retries the same body', () async {
    final identity = _identity();
    final requests = <http.Request>[];
    final gateway = HttpOrganizationCreationGateway(
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

    final result = await gateway.create(
      requestId: _requestId,
      displayName: '  Acme  ',
    );

    expect(result, isA<OrganizationCreationSuccess>());
    expect(requests, hasLength(2));
    expect(requests[0].body, requests[1].body);
    expect(requests.map((request) => request.headers['authorization']), [
      'Bearer test-only-access-token',
      'Bearer test-only-access-token',
    ]);
    expect(identity.accessTokenForceRefreshValues, [false, true]);
  });

  test('second 401 is a stable unauthorized rejection', () async {
    final identity = _identity();
    var requests = 0;
    final gateway = HttpOrganizationCreationGateway(
      baseUri: Uri.parse('https://backend.example.test'),
      identitySession: identity,
      client: MockClient((_) async {
        requests++;
        return _error('unauthenticated', 401);
      }),
    );
    addTearDown(gateway.close);

    final result = await gateway.create(
      requestId: _requestId,
      displayName: 'Acme',
    );

    expect(result, isA<OrganizationCreationRejected>());
    expect(
      (result as OrganizationCreationRejected).code,
      OrganizationCreationFailureCode.unauthorized,
    );
    expect(requests, 2);
    expect(identity.accessTokenForceRefreshValues, [false, true]);
  });

  test('a refresh failure does not issue a second HTTP request', () async {
    final identity = _identity();
    var requests = 0;
    final gateway = HttpOrganizationCreationGateway(
      baseUri: Uri.parse('https://backend.example.test'),
      identitySession: identity,
      client: MockClient((_) async {
        requests++;
        if (requests == 1) {
          identity.rejectNextAccessTokenWith = const IdentityFailure(
            code: IdentityFailureCode.sessionMissing,
          );
        }
        return _error('unauthenticated', 401);
      }),
    );
    addTearDown(gateway.close);

    final result = await gateway.create(
      requestId: _requestId,
      displayName: 'Acme',
    );

    expect(result, isA<OrganizationCreationRejected>());
    expect(
      (result as OrganizationCreationRejected).code,
      OrganizationCreationFailureCode.unauthorized,
    );
    expect(requests, 1);
    expect(identity.accessTokenForceRefreshValues, [false, true]);
  });

  test(
    'account change during token wait never sends the old creation intent',
    () async {
      final tokenRequested = Completer<void>();
      final token = Completer<IdentityResult<IdentityAccessToken>>();
      final identity = _RotatingTokenIdentitySession(
        accessTokenHandler: (_) {
          tokenRequested.complete();
          return token.future;
        },
      );
      var requests = 0;
      final gateway = HttpOrganizationCreationGateway(
        baseUri: Uri.parse('https://backend.example.test'),
        identitySession: identity,
        client: MockClient((_) async {
          requests++;
          return _json(_receiptJson());
        }),
      );
      addTearDown(gateway.close);
      addTearDown(identity.close);

      final pending = gateway.create(
        requestId: _requestId,
        displayName: 'Old account intent',
      );
      await tokenRequested.future;
      identity.emit(_otherIdentity);
      token.complete(_accessToken('new-account-token'));

      expect(
        _failureCode(await pending),
        OrganizationCreationFailureCode.unauthorized,
      );
      expect(requests, 0);
    },
  );

  test(
    'account change during 401 refresh never retries with the new token',
    () async {
      final refreshRequested = Completer<void>();
      final refreshToken = Completer<IdentityResult<IdentityAccessToken>>();
      final identity = _RotatingTokenIdentitySession(
        accessTokenHandler: (forceRefresh) {
          if (!forceRefresh) return Future.value(_accessToken('old-token'));
          refreshRequested.complete();
          return refreshToken.future;
        },
      );
      final requests = <http.Request>[];
      final gateway = HttpOrganizationCreationGateway(
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

      final pending = gateway.create(
        requestId: _requestId,
        displayName: 'Old account intent',
      );
      await refreshRequested.future;
      identity.emit(_otherIdentity);
      refreshToken.complete(_accessToken('new-account-token'));

      expect(
        _failureCode(await pending),
        OrganizationCreationFailureCode.unauthorized,
      );
      expect(requests, hasLength(1));
      expect(requests.single.headers['authorization'], 'Bearer old-token');
      expect(identity.accessTokenForceRefreshValues, [false, true]);
    },
  );

  test('HTTP sign-out and sign-in ABA invalidates creation', () async {
    final sent = Completer<void>();
    final response = Completer<http.Response>();
    final identity = _RotatingTokenIdentitySession();
    final gateway = HttpOrganizationCreationGateway(
      baseUri: Uri.parse('https://backend.example.test'),
      identitySession: identity,
      client: MockClient((_) {
        sent.complete();
        return response.future;
      }),
    );
    addTearDown(gateway.close);
    addTearDown(identity.close);

    final pending = gateway.create(requestId: _requestId, displayName: 'Acme');
    await sent.future;
    identity.emit(const IdentitySnapshot.signedOut());
    identity.emit(_initialIdentity);
    response.complete(_json(_receiptJson()));

    expect(
      _failureCode(await pending),
      OrganizationCreationFailureCode.unauthorized,
    );
  });

  test('HTTP completion checks a silently drifting current identity', () async {
    final sent = Completer<void>();
    final response = Completer<http.Response>();
    final identity = _RotatingTokenIdentitySession();
    final gateway = HttpOrganizationCreationGateway(
      baseUri: Uri.parse('https://backend.example.test'),
      identitySession: identity,
      client: MockClient((_) {
        sent.complete();
        return response.future;
      }),
    );
    addTearDown(gateway.close);
    addTearDown(identity.close);

    final pending = gateway.create(requestId: _requestId, displayName: 'Acme');
    await sent.future;
    identity.setCurrentWithoutEmit(_otherIdentity);
    response.complete(_json(_receiptJson()));

    expect(
      _failureCode(await pending),
      OrganizationCreationFailureCode.unauthorized,
    );
  });

  test('identity stream error or completion invalidates creation', () async {
    for (final endStream in [false, true]) {
      final sent = Completer<void>();
      final response = Completer<http.Response>();
      final identity = _RotatingTokenIdentitySession();
      final gateway = HttpOrganizationCreationGateway(
        baseUri: Uri.parse('https://backend.example.test'),
        identitySession: identity,
        client: MockClient((_) {
          sent.complete();
          return response.future;
        }),
      );
      addTearDown(gateway.close);
      addTearDown(identity.close);

      final pending = gateway.create(
        requestId: _requestId,
        displayName: 'Acme',
      );
      await sent.future;
      if (endStream) {
        await identity.endChanges();
      } else {
        identity.failChanges(StateError('test-only identity stream failure'));
      }
      await Future<void>.delayed(Duration.zero);
      response.complete(_json(_receiptJson()));

      expect(
        _failureCode(await pending),
        OrganizationCreationFailureCode.unauthorized,
        reason: endStream ? 'stream completed' : 'stream emitted an error',
      );
    }
  });

  test('close during token wait prevents creation HTTP', () async {
    final tokenRequested = Completer<void>();
    final token = Completer<IdentityResult<IdentityAccessToken>>();
    final identity = _RotatingTokenIdentitySession(
      accessTokenHandler: (_) {
        tokenRequested.complete();
        return token.future;
      },
    );
    var requests = 0;
    final gateway = HttpOrganizationCreationGateway(
      baseUri: Uri.parse('https://backend.example.test'),
      identitySession: identity,
      client: MockClient((_) async {
        requests++;
        return _json(_receiptJson());
      }),
    );
    addTearDown(identity.close);

    final pending = gateway.create(requestId: _requestId, displayName: 'Acme');
    await tokenRequested.future;
    await gateway.close();
    token.complete(_accessToken('old-token'));

    expect(
      _failureCode(await pending),
      OrganizationCreationFailureCode.unauthorized,
    );
    expect(requests, 0);
  });

  test('close during HTTP prevents stale creation delivery', () async {
    final sent = Completer<void>();
    final response = Completer<http.Response>();
    final identity = _RotatingTokenIdentitySession();
    final gateway = HttpOrganizationCreationGateway(
      baseUri: Uri.parse('https://backend.example.test'),
      identitySession: identity,
      client: MockClient((_) {
        sent.complete();
        return response.future;
      }),
    );
    addTearDown(identity.close);

    final pending = gateway.create(requestId: _requestId, displayName: 'Acme');
    await sent.future;
    await gateway.close();
    response.complete(_json(_receiptJson()));

    expect(
      _failureCode(await pending),
      OrganizationCreationFailureCode.unauthorized,
    );
  });

  test(
    'broken identity fence wins over late transport or parse errors',
    () async {
      for (final error in <Object>[
        http.ClientException('test-only late transport failure'),
        const FormatException('test-only late parse failure'),
      ]) {
        final sent = Completer<void>();
        final response = Completer<http.Response>();
        final identity = _RotatingTokenIdentitySession();
        final gateway = HttpOrganizationCreationGateway(
          baseUri: Uri.parse('https://backend.example.test'),
          identitySession: identity,
          client: MockClient((_) {
            sent.complete();
            return response.future;
          }),
        );
        addTearDown(gateway.close);
        addTearDown(identity.close);

        final pending = gateway.create(
          requestId: _requestId,
          displayName: 'Acme',
        );
        await sent.future;
        identity.emit(_otherIdentity);
        response.completeError(error);

        expect(
          _failureCode(await pending),
          OrganizationCreationFailureCode.unauthorized,
          reason: error.runtimeType.toString(),
        );
      }
    },
  );

  test('cleanup start is covered by the final identity check', () async {
    late _RotatingTokenIdentitySession identity;
    identity = _RotatingTokenIdentitySession(
      onChangesCancel: () {
        identity.setCurrentWithoutEmit(_otherIdentity);
      },
    );
    final gateway = HttpOrganizationCreationGateway(
      baseUri: Uri.parse('https://backend.example.test'),
      identitySession: identity,
      client: MockClient((_) async => _json(_receiptJson())),
    );
    addTearDown(gateway.close);
    addTearDown(identity.close);

    final result = await gateway.create(
      requestId: _requestId,
      displayName: 'Acme',
    );

    expect(_failureCode(result), OrganizationCreationFailureCode.unauthorized);
  });

  test(
    'cleanup gate and future errors do not delay or escape results',
    () async {
      for (final failCleanup in [false, true]) {
        final cancelStarted = Completer<void>();
        final finishCancel = Completer<void>();
        final identity = _RotatingTokenIdentitySession(
          onChangesCancel: () {
            cancelStarted.complete();
            return finishCancel.future;
          },
        );
        final gateway = HttpOrganizationCreationGateway(
          baseUri: Uri.parse('https://backend.example.test'),
          identitySession: identity,
          client: MockClient((_) async => _json(_receiptJson())),
        );
        addTearDown(gateway.close);
        addTearDown(identity.close);

        final resultDelivered = Completer<OrganizationCreationResult>();
        gateway
            .create(requestId: _requestId, displayName: 'Acme')
            .then(
              resultDelivered.complete,
              onError: resultDelivered.completeError,
            );
        await cancelStarted.future;
        await Future<void>.delayed(Duration.zero);

        expect(resultDelivered.isCompleted, isTrue);
        expect(
          await resultDelivered.future,
          isA<OrganizationCreationSuccess>(),
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

  test('maps the six stable error envelopes', () async {
    const cases =
        <({int status, String code, OrganizationCreationFailureCode failure})>[
          (
            status: 400,
            code: 'invalid_json',
            failure: OrganizationCreationFailureCode.invalidJson,
          ),
          (
            status: 413,
            code: 'payload_too_large',
            failure: OrganizationCreationFailureCode.payloadTooLarge,
          ),
          (
            status: 400,
            code: 'invalid_organization_creation_request',
            failure: OrganizationCreationFailureCode.invalidRequest,
          ),
          (
            status: 403,
            code: 'organization_creation_forbidden',
            failure: OrganizationCreationFailureCode.forbidden,
          ),
          (
            status: 409,
            code: 'organization_creation_conflict',
            failure: OrganizationCreationFailureCode.conflict,
          ),
          (
            status: 503,
            code: 'organization_creation_unavailable',
            failure: OrganizationCreationFailureCode.serviceUnavailable,
          ),
        ];

    for (final testCase in cases) {
      final gateway = _gateway(
        (_) async => _error(testCase.code, testCase.status),
      );
      final result = await gateway.create(
        requestId: _requestId,
        displayName: 'Acme',
      );
      await gateway.close();

      expect(result, isA<OrganizationCreationRejected>());
      expect(
        (result as OrganizationCreationRejected).code,
        testCase.failure,
        reason: '${testCase.status} ${testCase.code}',
      );
    }
  });

  test('identity failures are typed and do not send a request', () async {
    for (final testCase in const [
      (
        failure: IdentityFailureCode.notConfigured,
        expected: OrganizationCreationFailureCode.notConfigured,
      ),
      (
        failure: IdentityFailureCode.networkUnavailable,
        expected: OrganizationCreationFailureCode.networkUnavailable,
      ),
      (
        failure: IdentityFailureCode.sessionMissing,
        expected: OrganizationCreationFailureCode.unauthorized,
      ),
    ]) {
      final identity = _identity();
      identity.rejectNextAccessTokenWith = IdentityFailure(
        code: testCase.failure,
      );
      var requests = 0;
      final gateway = HttpOrganizationCreationGateway(
        baseUri: Uri.parse('https://backend.example.test'),
        identitySession: identity,
        client: MockClient((_) async {
          requests++;
          return _json(_receiptJson());
        }),
      );

      final result = await gateway.create(
        requestId: _requestId,
        displayName: 'Acme',
      );
      await gateway.close();

      expect(result, isA<OrganizationCreationRejected>());
      expect((result as OrganizationCreationRejected).code, testCase.expected);
      expect(requests, 0);
    }
  });

  test('rejects malformed, non-exact, and non-canonical receipts', () async {
    final cases = <String, Object>{
      'malformed JSON': '{',
      'non-object JSON': '[]',
      'extra field': jsonEncode({..._receiptJson(), 'extra': true}),
      'missing field': jsonEncode(
        _receiptJson()..remove('organization_membership_id'),
      ),
      'bad contract': jsonEncode({
        ..._receiptJson(),
        'creation_contract_id': 'other:v1',
      }),
      'bad UUID': jsonEncode({
        ..._receiptJson(),
        'organization_workspace_id': 'not-a-uuid',
      }),
      'uppercase UUID': jsonEncode({
        ..._receiptJson(),
        'organization_workspace_id': _workspaceId.toUpperCase(),
      }),
      'non-canonical UTC': jsonEncode({
        ..._receiptJson(),
        'created_at_utc': '2030-01-02T04:04:05Z',
      }),
      'offset timestamp': jsonEncode({
        ..._receiptJson(),
        'created_at_utc': '2030-01-01T22:04:05.000-06:00',
      }),
    };

    for (final entry in cases.entries) {
      final gateway = _gateway((_) async => _raw(entry.value as String));
      final result = await gateway.create(
        requestId: _requestId,
        displayName: 'Acme',
      );
      await gateway.close();

      expect(result, isA<OrganizationCreationRejected>(), reason: entry.key);
      expect(
        (result as OrganizationCreationRejected).code,
        OrganizationCreationFailureCode.invalidResponse,
        reason: entry.key,
      );
    }
  });

  test('rejects missing or incorrect JSON no-store headers', () async {
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
      final result = await gateway.create(
        requestId: _requestId,
        displayName: 'Acme',
      );
      await gateway.close();

      expect(result, isA<OrganizationCreationRejected>());
      expect(
        (result as OrganizationCreationRejected).code,
        OrganizationCreationFailureCode.invalidResponse,
      );
    }
  });

  test('maps unknown status or error envelope to invalidResponse', () async {
    final cases = <http.Response Function()>[
      () => _error('unknown', 418),
      () => _json({
        'error': {'code': 'invalid_json'},
        'extra': true,
      }, status: 400),
      () => _json({
        'error': {'message': 'invalid'},
      }, status: 503),
      () => _json(_receiptJson(), status: 201),
    ];

    for (final response in cases) {
      final gateway = _gateway((_) async => response());
      final result = await gateway.create(
        requestId: _requestId,
        displayName: 'Acme',
      );
      await gateway.close();

      expect(result, isA<OrganizationCreationRejected>());
      expect(
        (result as OrganizationCreationRejected).code,
        OrganizationCreationFailureCode.invalidResponse,
      );
    }
  });

  test('maps network and timeout failures without exposing details', () async {
    final networkGateway = _gateway(
      (_) => Future<http.Response>.error(
        http.ClientException('database secret: do not expose'),
      ),
    );
    final networkResult = await networkGateway.create(
      requestId: _requestId,
      displayName: 'Acme',
    );
    await networkGateway.close();
    expect(
      (networkResult as OrganizationCreationRejected).code,
      OrganizationCreationFailureCode.networkUnavailable,
    );

    final timeoutGateway = HttpOrganizationCreationGateway(
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
    final timeoutResult = await timeoutGateway.create(
      requestId: _requestId,
      displayName: 'Acme',
    );
    await timeoutGateway.close();
    expect(
      (timeoutResult as OrganizationCreationRejected).code,
      OrganizationCreationFailureCode.networkUnavailable,
    );
  });

  test('deferred gateway is explicit no-network and close is safe', () async {
    const gateway = DeferredOrganizationCreationGateway();

    final result = await gateway.create(
      requestId: _requestId,
      displayName: 'Acme',
    );
    await gateway.close();

    expect(result, isA<OrganizationCreationRejected>());
    expect(
      (result as OrganizationCreationRejected).code,
      OrganizationCreationFailureCode.notConfigured,
    );
  });

  test('close owns the HTTP client once and leaves identity open', () async {
    final client = _TrackingMockClient((_) async => _json(_receiptJson()));
    final identity = _identity();
    final gateway = HttpOrganizationCreationGateway(
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

const _contractId = 'organization-creation:v1';
const _workspaceId = 'abcdefab-cdef-4abc-8def-abcdefabcdef';
const _membershipId = 'abcdefab-cdef-4abc-8def-abcdefabcdea';
const _ownerAssignmentId = 'abcdefab-cdef-4abc-8def-abcdefabcdeb';
const _requestId = 'abcdefab-cdef-4abc-8def-abcdefabcdec';

FakeIdentitySession _identity() => FakeIdentitySession(
  initial: const IdentitySnapshot(
    stage: IdentityStage.signedIn,
    principal: IdentityPrincipal(
      externalSubject: 'subject-1',
      email: 'owner@example.test',
    ),
  ),
);

HttpOrganizationCreationGateway _gateway(
  Future<http.Response> Function(http.Request) handler,
) => HttpOrganizationCreationGateway(
  baseUri: Uri.parse('https://backend.example.test'),
  identitySession: _identity(),
  client: MockClient(handler),
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

http.Response _error(String code, int status) => _json({
  'error': {'code': code},
}, status: status);

Map<String, Object?> _receiptJson() => {
  'creation_contract_id': _contractId,
  'organization_workspace_id': _workspaceId,
  'organization_membership_id': _membershipId,
  'organization_owner_assignment_id': _ownerAssignmentId,
  'created_at_utc': '2030-01-02T04:04:05.000Z',
};

const _jsonHeaders = {
  'content-type': 'application/json; charset=utf-8',
  'cache-control': 'no-store',
};

OrganizationCreationFailureCode _failureCode(
  OrganizationCreationResult result,
) => (result as OrganizationCreationRejected).code;

IdentitySuccess<IdentityAccessToken> _accessToken(String value) =>
    IdentitySuccess(
      IdentityAccessToken(
        value: value,
        expiresAt: DateTime.utc(2030, 1, 2, 4, 4),
      ),
    );

final class _TrackingMockClient extends MockClient {
  _TrackingMockClient(super.handler);

  var closeCount = 0;

  @override
  void close() {
    closeCount++;
    super.close();
  }
}

final class _RotatingTokenIdentitySession implements IdentitySession {
  _RotatingTokenIdentitySession({
    this.accessTokenHandler,
    FutureOr<void> Function()? onChangesCancel,
  }) : _changes = StreamController<IdentitySnapshot>(
         sync: true,
         onCancel: onChangesCancel,
       );

  final Future<IdentityResult<IdentityAccessToken>> Function(bool forceRefresh)?
  accessTokenHandler;
  final accessTokenForceRefreshValues = <bool>[];
  final StreamController<IdentitySnapshot> _changes;
  IdentitySnapshot _current = _initialIdentity;

  @override
  IdentitySnapshot get current => _current;

  @override
  Stream<IdentitySnapshot> get changes => _changes.stream;

  void emit(IdentitySnapshot snapshot) {
    _current = snapshot;
    _changes.add(snapshot);
  }

  void setCurrentWithoutEmit(IdentitySnapshot snapshot) => _current = snapshot;

  void failChanges(Object error) => _changes.addError(error);

  Future<void> endChanges() => _changes.close();

  @override
  Future<void> close() => _changes.close();

  @override
  Future<IdentityResult<IdentityAccessToken>> accessToken({
    bool forceRefresh = false,
  }) async {
    accessTokenForceRefreshValues.add(forceRefresh);
    final handler = accessTokenHandler;
    if (handler != null) return handler(forceRefresh);
    return _accessToken(
      forceRefresh ? 'refreshed-test-access-token' : 'stale-test-access-token',
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('unused test-only identity method');
}

const _initialIdentity = IdentitySnapshot(
  stage: IdentityStage.signedIn,
  principal: IdentityPrincipal(externalSubject: 'subject-1', email: null),
);

const _otherIdentity = IdentitySnapshot(
  stage: IdentityStage.signedIn,
  principal: IdentityPrincipal(externalSubject: 'subject-2', email: null),
);
