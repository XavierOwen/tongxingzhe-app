import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tongxingzhe_app/foundation/backend_base_uri.dart';
import 'package:tongxingzhe_app/identity/identity_session.dart';
import 'package:tongxingzhe_app/organization_shareable_join/http_organization_shareable_join_gateway.dart';
import 'package:tongxingzhe_app/organization_shareable_join/organization_shareable_join.dart';

import '../support/fake_identity_session.dart';

void main() {
  test(
    'four operations send exact canonical routes, headers, and bodies',
    () async {
      const cases = [
        (
          operation: _Operation.createLink,
          method: 'POST',
          path: '/v1/organizations/$_workspaceId/shareable-join-links',
          body: '{"link_id":"$_linkId"}',
        ),
        (
          operation: _Operation.previewLink,
          method: 'GET',
          path: '/v1/organization-shareable-join-links/$_linkId',
          body: '',
        ),
        (
          operation: _Operation.submitApplication,
          method: 'POST',
          path: '/v1/organization-shareable-join-links/$_linkId/applications',
          body: '{"application_id":"$_applicationId"}',
        ),
        (
          operation: _Operation.approveApplication,
          method: 'POST',
          path:
              '/v1/organizations/$_workspaceId/shareable-join-applications/'
              '$_applicationId/approve',
          body: '{}',
        ),
      ];

      for (final testCase in cases) {
        late http.Request request;
        final gateway = _gateway((value) async {
          request = value;
          return _json(_successJson(testCase.operation));
        });

        final result = await _invokeOperation(
          gateway,
          testCase.operation,
          uppercase: true,
        );
        await gateway.close();

        expect(
          request.method,
          testCase.method,
          reason: testCase.operation.name,
        );
        expect(
          request.url,
          Uri.parse('https://backend.example.test${testCase.path}'),
          reason: testCase.operation.name,
        );
        expect(request.body, testCase.body, reason: testCase.operation.name);
        expect(request.url.query, isEmpty);
        expect(request.url.fragment, isEmpty);
        expect(request.headers['accept'], 'application/json');
        expect(
          request.headers['authorization'],
          'Bearer test-only-access-token',
        );
        expect(
          request.headers['content-type'],
          testCase.method == 'POST' ? 'application/json; charset=utf-8' : null,
        );
        expect(request.headers.containsKey('idempotency-key'), isFalse);
        _expectSuccess(result, testCase.operation);
      }
    },
  );

  test('four independent receipts preserve exact values and UTC', () async {
    final createGateway = _gateway(
      (_) async => _json(_linkCreateReceiptJson()),
    );
    final create = await createGateway.createLink(
      linkId: _linkId,
      organizationWorkspaceId: _workspaceId,
    );
    await createGateway.close();
    final createReceipt =
        (create as OrganizationShareableJoinLinkCreateSuccess).receipt;
    expect(
      createReceipt.organizationShareableJoinLinkContractId,
      _linkContract,
    );
    expect(createReceipt.linkId, _linkId);
    expect(createReceipt.organizationWorkspaceId, _workspaceId);
    expect(createReceipt.issuedAtUtc, DateTime.utc(2000));
    expect(createReceipt.expiresAtUtc, DateTime.utc(2000, 1, 8));
    expect(createReceipt.expiresAtUtc.isUtc, isTrue);

    final previewGateway = _gateway(
      (_) async => _json(_linkPreviewReceiptJson()),
    );
    final preview = await previewGateway.previewLink(linkId: _linkId);
    await previewGateway.close();
    final previewReceipt =
        (preview as OrganizationShareableJoinLinkPreviewSuccess).receipt;
    expect(
      previewReceipt.organizationShareableJoinLinkPreviewContractId,
      _previewContract,
    );
    expect(previewReceipt.linkId, _linkId);
    expect(previewReceipt.organizationName, ' 同行组织 ');
    expect(previewReceipt.expiresAtUtc, DateTime.utc(2030, 1, 8));

    final submitGateway = _gateway(
      (_) async => _json(_applicationSubmitReceiptJson()),
    );
    final submit = await submitGateway.submitApplication(
      applicationId: _applicationId,
      linkId: _linkId,
    );
    await submitGateway.close();
    final submitReceipt =
        (submit as OrganizationShareableJoinApplicationSubmitSuccess).receipt;
    expect(
      submitReceipt.organizationShareableJoinApplicationContractId,
      _applicationContract,
    );
    expect(submitReceipt.applicationId, _applicationId);
    expect(submitReceipt.linkId, _linkId);
    expect(submitReceipt.organizationWorkspaceId, _workspaceId);
    expect(submitReceipt.submittedAtUtc, DateTime.utc(2000));
    expect(submitReceipt.expiresAtUtc, DateTime.utc(2000, 1, 8));

    final approveGateway = _gateway(
      (_) async => _json(_applicationApproveReceiptJson()),
    );
    final approve = await approveGateway.approveApplication(
      organizationWorkspaceId: _workspaceId,
      applicationId: _applicationId,
    );
    await approveGateway.close();
    final approveReceipt =
        (approve as OrganizationShareableJoinApplicationApproveSuccess).receipt;
    expect(
      approveReceipt.organizationShareableJoinApplicationContractId,
      _applicationContract,
    );
    expect(approveReceipt.applicationId, _applicationId);
    expect(approveReceipt.organizationWorkspaceId, _workspaceId);
    expect(approveReceipt.organizationMembershipId, _membershipId);
    expect(approveReceipt.approvedAtUtc, DateTime.utc(2030, 1, 2, 4, 5, 6));
  });

  test('every input UUID fails before token or network access', () async {
    final invocations =
        <Future<Object> Function(OrganizationShareableJoinGateway)>[
          (gateway) => gateway.createLink(
            linkId: 'not-a-uuid',
            organizationWorkspaceId: _workspaceId,
          ),
          (gateway) => gateway.createLink(
            linkId: _linkId,
            organizationWorkspaceId: 'not-a-uuid',
          ),
          (gateway) => gateway.previewLink(linkId: 'not-a-uuid'),
          (gateway) => gateway.submitApplication(
            applicationId: 'not-a-uuid',
            linkId: _linkId,
          ),
          (gateway) => gateway.submitApplication(
            applicationId: _applicationId,
            linkId: 'not-a-uuid',
          ),
          (gateway) => gateway.approveApplication(
            organizationWorkspaceId: 'not-a-uuid',
            applicationId: _applicationId,
          ),
          (gateway) => gateway.approveApplication(
            organizationWorkspaceId: _workspaceId,
            applicationId: 'not-a-uuid',
          ),
        ];

    for (final invoke in invocations) {
      final identity = _identity();
      var requests = 0;
      final gateway = _gateway((_) async {
        requests++;
        return _json(_linkCreateReceiptJson());
      }, identity: identity);

      expect(_failureCode(await invoke(gateway)), _Failure.invalidRequest);
      expect(identity.accessTokenForceRefreshValues, isEmpty);
      expect(requests, 0);
      await gateway.close();
    }
  });

  test('deferred gateway rejects all operations without resources', () async {
    const gateway = DeferredOrganizationShareableJoinGateway();

    for (final operation in _Operation.values) {
      expect(
        _failureCode(await _invokeOperation(gateway, operation)),
        _Failure.notConfigured,
      );
    }
    await gateway.close();
    await gateway.close();
  });

  test(
    'factory defers empty config and HTTP rejects pathful base URI',
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
        final gateway = productionOrganizationShareableJoinGateway(identity);
        expect(
          gateway,
          validConfiguredUri
              ? isA<HttpOrganizationShareableJoinGateway>()
              : isA<DeferredOrganizationShareableJoinGateway>(),
        );
        await gateway.close();
      } else {
        expect(
          () => productionOrganizationShareableJoinGateway(identity),
          anyOf(throwsArgumentError, throwsFormatException),
        );
      }

      final client = _TrackingMockClient(
        (_) async => _json(_linkCreateReceiptJson()),
      );
      expect(
        () => HttpOrganizationShareableJoinGateway(
          baseUri: Uri.parse('https://backend.example.test/path'),
          identitySession: identity,
          client: client,
        ),
        throwsArgumentError,
      );
      expect(client.closeCount, 0);
      expect(identity.accessTokenForceRefreshValues, isEmpty);
      expect(identity.isClosed, isFalse);
    },
  );

  test(
    'operation-specific receipts reject shape, binding, UUID, and time drift',
    () async {
      final invalid = <(_Operation, http.Response)>[
        (_Operation.createLink, _raw('{')),
        (_Operation.previewLink, _raw('[]')),
        for (final operation in _Operation.values)
          (operation, _json({..._successJson(operation), 'extra': true})),
        (
          _Operation.createLink,
          _json(_linkCreateReceiptJson()..remove('expires_at_utc')),
        ),
        (
          _Operation.createLink,
          _json({
            ..._linkCreateReceiptJson(),
            'organization_shareable_join_link_contract_id': 'other:v1',
          }),
        ),
        (
          _Operation.previewLink,
          _json({
            ..._linkPreviewReceiptJson(),
            'organization_shareable_join_link_preview_contract_id': 'other:v1',
          }),
        ),
        (
          _Operation.submitApplication,
          _json({
            ..._applicationSubmitReceiptJson(),
            'organization_shareable_join_application_contract_id': 'other:v1',
          }),
        ),
        (
          _Operation.approveApplication,
          _json({
            ..._applicationApproveReceiptJson(),
            'organization_shareable_join_application_contract_id': 'other:v1',
          }),
        ),
        (
          _Operation.createLink,
          _json({..._linkCreateReceiptJson(), 'link_id': _otherId}),
        ),
        (
          _Operation.createLink,
          _json({
            ..._linkCreateReceiptJson(),
            'organization_workspace_id': _otherId,
          }),
        ),
        (
          _Operation.previewLink,
          _json({..._linkPreviewReceiptJson(), 'link_id': _otherId}),
        ),
        (
          _Operation.submitApplication,
          _json({
            ..._applicationSubmitReceiptJson(),
            'application_id': _otherId,
          }),
        ),
        (
          _Operation.submitApplication,
          _json({..._applicationSubmitReceiptJson(), 'link_id': _otherId}),
        ),
        (
          _Operation.approveApplication,
          _json({
            ..._applicationApproveReceiptJson(),
            'application_id': _otherId,
          }),
        ),
        (
          _Operation.approveApplication,
          _json({
            ..._applicationApproveReceiptJson(),
            'organization_workspace_id': _otherId,
          }),
        ),
        (
          _Operation.submitApplication,
          _json({
            ..._applicationSubmitReceiptJson(),
            'organization_workspace_id': _workspaceId.toUpperCase(),
          }),
        ),
        (
          _Operation.approveApplication,
          _json({
            ..._applicationApproveReceiptJson(),
            'organization_membership_id': 'not-a-uuid',
          }),
        ),
        (
          _Operation.previewLink,
          _json({..._linkPreviewReceiptJson(), 'organization_name': '   '}),
        ),
        (
          _Operation.createLink,
          _json({
            ..._linkCreateReceiptJson(),
            'issued_at_utc': '2000-02-30T00:00:00.000Z',
          }),
        ),
        (
          _Operation.previewLink,
          _json({
            ..._linkPreviewReceiptJson(),
            'expires_at_utc': '2030-01-07T18:00:00.000-06:00',
          }),
        ),
        (
          _Operation.approveApplication,
          _json({
            ..._applicationApproveReceiptJson(),
            'approved_at_utc': '2030-01-02T04:05:06Z',
          }),
        ),
        (
          _Operation.createLink,
          _json({
            ..._linkCreateReceiptJson(),
            'expires_at_utc': '2000-01-07T23:59:59.999Z',
          }),
        ),
        (
          _Operation.submitApplication,
          _json({
            ..._applicationSubmitReceiptJson(),
            'expires_at_utc': '2000-01-08T00:00:00.001Z',
          }),
        ),
      ];

      for (final (operation, response) in invalid) {
        final gateway = _gateway((_) async => response);
        final result = await _invokeOperation(gateway, operation);
        await gateway.close();
        expect(
          _failureCode(result),
          _Failure.invalidResponse,
          reason: operation.name,
        );
      }
    },
  );

  test(
    'success and error responses require exact JSON UTF-8 and no-store',
    () async {
      const invalidHeaders = <Map<String, String>>[
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
          'cache-control': 'private',
        },
      ];

      for (final headers in invalidHeaders) {
        final successGateway = _gateway(
          (_) async => _json(_linkPreviewReceiptJson(), headers: headers),
        );
        expect(
          _failureCode(await successGateway.previewLink(linkId: _linkId)),
          _Failure.invalidResponse,
        );
        await successGateway.close();

        final errorGateway = _gateway(
          (_) async => _json(
            _errorJson('organization_shareable_join_forbidden'),
            status: 403,
            headers: headers,
          ),
        );
        expect(
          _failureCode(await errorGateway.previewLink(linkId: _linkId)),
          _Failure.invalidResponse,
        );
        await errorGateway.close();
      }
    },
  );

  test(
    'stable errors map exactly and every operation returns its rejection',
    () async {
      const cases = [
        (400, 'invalid_json', _Failure.invalidJson),
        (
          400,
          'invalid_organization_shareable_join_request',
          _Failure.invalidRequest,
        ),
        (401, 'unauthenticated', _Failure.unauthorized),
        (403, 'organization_shareable_join_forbidden', _Failure.forbidden),
        (409, 'organization_shareable_join_conflict', _Failure.conflict),
        (413, 'payload_too_large', _Failure.payloadTooLarge),
        (
          503,
          'organization_shareable_join_unavailable',
          _Failure.serviceUnavailable,
        ),
      ];

      for (final testCase in cases) {
        final gateway = _gateway((_) async => _error(testCase.$2, testCase.$1));
        expect(
          _failureCode(
            await gateway.approveApplication(
              organizationWorkspaceId: _workspaceId,
              applicationId: _applicationId,
            ),
          ),
          testCase.$3,
        );
        await gateway.close();
      }

      for (final operation in _Operation.values) {
        final gateway = _gateway(
          (_) async => _error('organization_shareable_join_forbidden', 403),
        );
        expect(
          _failureCode(await _invokeOperation(gateway, operation)),
          _Failure.forbidden,
        );
        await gateway.close();
      }
    },
  );

  test('unknown status, code, or error envelope is invalidResponse', () async {
    final responses = <http.Response>[
      _error('not_found', 404),
      _error('expired', 403),
      _error('unknown', 418),
      _json({
        'error': {'code': 'invalid_json'},
        'extra': true,
      }, status: 400),
      _json({
        'error': {'message': 'provider detail'},
      }, status: 503),
      _json(_linkCreateReceiptJson(), status: 201),
    ];

    for (final response in responses) {
      final gateway = _gateway((_) async => response);
      expect(
        _failureCode(
          await gateway.createLink(
            linkId: _linkId,
            organizationWorkspaceId: _workspaceId,
          ),
        ),
        _Failure.invalidResponse,
      );
      await gateway.close();
    }
  });

  test('each operation refreshes once and retries the same request', () async {
    for (final operation in _Operation.values) {
      final identity = _RotatingTokenIdentitySession();
      final requests = <http.Request>[];
      final gateway = _gateway((request) async {
        requests.add(request);
        return requests.length == 1
            ? _error('unauthenticated', 401)
            : _json(_successJson(operation));
      }, identity: identity);

      final result = await _invokeOperation(gateway, operation);
      await gateway.close();
      await identity.close();

      _expectSuccess(result, operation);
      expect(requests, hasLength(2));
      expect(requests[0].method, requests[1].method);
      expect(requests[0].url, requests[1].url);
      expect(requests[0].body, requests[1].body);
      expect(requests.map((request) => request.headers['authorization']), [
        'Bearer stale-test-access-token',
        'Bearer refreshed-test-access-token',
      ]);
      expect(identity.accessTokenForceRefreshValues, [false, true]);
    }
  });

  test('malformed 401 does not refresh and a second 401 stops', () async {
    final malformedResponses = <http.Response>[
      _raw('{', status: 401),
      _error('other', 401),
      _json({
        'error': {'code': 'unauthenticated'},
        'extra': true,
      }, status: 401),
    ];
    for (final response in malformedResponses) {
      final identity = _identity();
      var requests = 0;
      final gateway = _gateway((_) async {
        requests++;
        return response;
      }, identity: identity);
      expect(
        _failureCode(await gateway.previewLink(linkId: _linkId)),
        _Failure.invalidResponse,
      );
      expect(requests, 1);
      expect(identity.accessTokenForceRefreshValues, [false]);
      await gateway.close();
    }

    final identity = _RotatingTokenIdentitySession();
    var requests = 0;
    final gateway = _gateway((_) async {
      requests++;
      return _error('unauthenticated', 401);
    }, identity: identity);
    expect(
      _failureCode(await gateway.previewLink(linkId: _linkId)),
      _Failure.unauthorized,
    );
    expect(requests, 2);
    expect(identity.accessTokenForceRefreshValues, [false, true]);
    await gateway.close();
    await identity.close();
  });

  test('identity failures map before network access', () async {
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
        return _json(_linkCreateReceiptJson());
      }, identity: identity);
      expect(
        _failureCode(
          await gateway.createLink(
            linkId: _linkId,
            organizationWorkspaceId: _workspaceId,
          ),
        ),
        testCase.$2,
      );
      expect(requests, 0);
      await gateway.close();
    }
  });

  test(
    'sign-out, account switch, and sign-in ABA fence every late result',
    () async {
      for (final transition in _IdentityTransition.values) {
        for (final operation in _Operation.values) {
          final sent = Completer<void>();
          final response = Completer<http.Response>();
          final identity = _RotatingTokenIdentitySession();
          final gateway = _gateway((_) {
            sent.complete();
            return response.future;
          }, identity: identity);

          final pending = _invokeOperation(gateway, operation);
          await sent.future;
          switch (transition) {
            case _IdentityTransition.signOut:
              identity.emit(const IdentitySnapshot.signedOut());
            case _IdentityTransition.switchAccount:
              identity.emit(_otherIdentity);
            case _IdentityTransition.aba:
              identity.emit(const IdentitySnapshot.signedOut());
              identity.emit(_initialIdentity);
          }
          response.complete(_json(_successJson(operation)));

          expect(
            _failureCode(await pending),
            _Failure.unauthorized,
            reason: '${operation.name}, ${transition.name}',
          );
          await gateway.close();
          await identity.close();
        }
      }
    },
  );

  test('identity change while waiting for token stops before HTTP', () async {
    for (final operation in _Operation.values) {
      final tokenRequested = Completer<void>();
      final token = Completer<IdentityResult<IdentityAccessToken>>();
      final identity = _RotatingTokenIdentitySession(
        accessTokenHandler: (_) {
          tokenRequested.complete();
          return token.future;
        },
      );
      var requests = 0;
      final gateway = _gateway((_) async {
        requests++;
        return _json(_successJson(operation));
      }, identity: identity);

      final pending = _invokeOperation(gateway, operation);
      await tokenRequested.future;
      identity.emit(_otherIdentity);
      token.complete(_accessToken('new-account-token'));

      expect(_failureCode(await pending), _Failure.unauthorized);
      expect(requests, 0);
      await gateway.close();
      await identity.close();
    }
  });

  test('401 refresh ABA cannot send credentials for a new session', () async {
    for (final operation in _Operation.values) {
      late _RotatingTokenIdentitySession identity;
      identity = _RotatingTokenIdentitySession(
        accessTokenHandler: (forceRefresh) async {
          if (forceRefresh) {
            identity.emit(const IdentitySnapshot.signedOut());
            identity.emit(_initialIdentity);
            return _accessToken('new-session-token');
          }
          return _accessToken('stale-test-access-token');
        },
      );
      var requests = 0;
      final gateway = _gateway((_) async {
        requests++;
        return _error('unauthenticated', 401);
      }, identity: identity);

      expect(
        _failureCode(await _invokeOperation(gateway, operation)),
        _Failure.unauthorized,
      );
      expect(requests, 1);
      await gateway.close();
      await identity.close();
    }
  });

  test(
    'timeout, network, and unknown adapter failures stay redacted',
    () async {
      final networkGateway = _gateway(
        (_) => Future<http.Response>.error(
          http.ClientException('provider detail'),
        ),
      );
      expect(
        _failureCode(await networkGateway.previewLink(linkId: _linkId)),
        _Failure.networkUnavailable,
      );
      await networkGateway.close();

      final timeoutGateway = _gateway(
        (_) => Future<http.Response>.delayed(
          const Duration(milliseconds: 50),
          () => _json(_linkPreviewReceiptJson()),
        ),
        timeout: const Duration(milliseconds: 1),
      );
      expect(
        _failureCode(await timeoutGateway.previewLink(linkId: _linkId)),
        _Failure.networkUnavailable,
      );
      await timeoutGateway.close();

      final adapterGateway = _gateway(
        (_) => Future<http.Response>.error(StateError('provider detail')),
      );
      expect(
        _failureCode(await adapterGateway.previewLink(linkId: _linkId)),
        _Failure.invalidResponse,
      );
      await adapterGateway.close();
    },
  );

  test('late transport failure honors the current identity fence', () async {
    final sent = Completer<void>();
    final response = Completer<http.Response>();
    final identity = _RotatingTokenIdentitySession();
    final gateway = _gateway((_) {
      sent.complete();
      return response.future;
    }, identity: identity);

    final pending = gateway.previewLink(linkId: _linkId);
    await sent.future;
    identity.setCurrentWithoutEmit(_otherIdentity);
    response.completeError(http.ClientException('old-account detail'));

    expect(_failureCode(await pending), _Failure.unauthorized);
    await gateway.close();
    await identity.close();
  });

  test('close during HTTP prevents stale delivery', () async {
    final sent = Completer<void>();
    final response = Completer<http.Response>();
    final identity = _RotatingTokenIdentitySession();
    final gateway = _gateway((_) {
      sent.complete();
      return response.future;
    }, identity: identity);

    final pending = gateway.previewLink(linkId: _linkId);
    await sent.future;
    await gateway.close();
    response.complete(_json(_linkPreviewReceiptJson()));

    expect(_failureCode(await pending), _Failure.unauthorized);
    await identity.close();
  });

  test('cleanup start is covered by the final identity fence', () async {
    for (final closeGateway in [false, true]) {
      late _RotatingTokenIdentitySession identity;
      late HttpOrganizationShareableJoinGateway gateway;
      identity = _RotatingTokenIdentitySession(
        onChangesCancel: () {
          if (closeGateway) {
            gateway.close();
          } else {
            identity.setCurrentWithoutEmit(_otherIdentity);
          }
        },
      );
      gateway = _gateway(
        (_) async => _json(_linkPreviewReceiptJson()),
        identity: identity,
      );

      expect(
        _failureCode(await gateway.previewLink(linkId: _linkId)),
        _Failure.unauthorized,
        reason: 'close=$closeGateway',
      );
      await gateway.close();
      await identity.close();
    }
  });

  test('async subscription cleanup does not delay typed delivery', () async {
    final cancelStarted = Completer<void>();
    final finishCancel = Completer<void>();
    final identity = _RotatingTokenIdentitySession(
      onChangesCancel: () {
        cancelStarted.complete();
        return finishCancel.future;
      },
    );
    final gateway = _gateway(
      (_) async => _json(_linkPreviewReceiptJson()),
      identity: identity,
    );
    final delivered = Completer<Object>();
    gateway
        .previewLink(linkId: _linkId)
        .then(delivered.complete, onError: delivered.completeError);

    await cancelStarted.future;
    await Future<void>.delayed(Duration.zero);
    expect(delivered.isCompleted, isTrue);
    expect(
      await delivered.future,
      isA<OrganizationShareableJoinLinkPreviewSuccess>(),
    );

    finishCancel.completeError(StateError('test-only cleanup failure'));
    await Future<void>.delayed(Duration.zero);
    await gateway.close();
    await identity.close();
  });

  test('close owns the HTTP client once and leaves identity open', () async {
    final identity = _identity();
    final client = _TrackingMockClient(
      (_) async => _json(_linkCreateReceiptJson()),
    );
    final gateway = _gateway(
      (_) async => _json(_linkCreateReceiptJson()),
      identity: identity,
      client: client,
    );

    await gateway.close();
    await gateway.close();

    expect(client.closeCount, 1);
    expect(identity.isClosed, isFalse);
    expect(
      _failureCode(await gateway.previewLink(linkId: _linkId)),
      _Failure.unauthorized,
    );
    expect(identity.accessTokenForceRefreshValues, isEmpty);
  });
}

typedef _Failure = OrganizationShareableJoinFailureCode;

enum _Operation {
  createLink,
  previewLink,
  submitApplication,
  approveApplication,
}

enum _IdentityTransition { signOut, switchAccount, aba }

const _linkContract = 'organization-shareable-join-link:v1';
const _previewContract = 'organization-shareable-join-link-preview:v1';
const _applicationContract = 'organization-shareable-join-application:v1';
const _linkId = 'abcdefab-cdef-0abc-0def-abcdefabcdef';
const _applicationId = 'abcdefab-cdef-0abc-0def-abcdefabcdea';
const _workspaceId = 'abcdefab-cdef-0abc-0def-abcdefabcdeb';
const _membershipId = 'abcdefab-cdef-0abc-0def-abcdefabcdec';
const _otherId = 'abcdefab-cdef-0abc-0def-abcdefabcded';

FakeIdentitySession _identity() =>
    FakeIdentitySession(initial: _initialIdentity);

HttpOrganizationShareableJoinGateway _gateway(
  Future<http.Response> Function(http.Request) handler, {
  IdentitySession? identity,
  http.Client? client,
  Duration timeout = const Duration(seconds: 15),
}) => HttpOrganizationShareableJoinGateway(
  baseUri: Uri.parse('https://backend.example.test'),
  identitySession: identity ?? _identity(),
  client: client ?? MockClient(handler),
  timeout: timeout,
);

Future<Object> _invokeOperation(
  OrganizationShareableJoinGateway gateway,
  _Operation operation, {
  bool uppercase = false,
}) {
  String value(String input) => uppercase ? input.toUpperCase() : input;
  return switch (operation) {
    _Operation.createLink => gateway.createLink(
      linkId: value(_linkId),
      organizationWorkspaceId: value(_workspaceId),
    ),
    _Operation.previewLink => gateway.previewLink(linkId: value(_linkId)),
    _Operation.submitApplication => gateway.submitApplication(
      applicationId: value(_applicationId),
      linkId: value(_linkId),
    ),
    _Operation.approveApplication => gateway.approveApplication(
      organizationWorkspaceId: value(_workspaceId),
      applicationId: value(_applicationId),
    ),
  };
}

OrganizationShareableJoinFailureCode _failureCode(Object result) =>
    switch (result) {
      OrganizationShareableJoinLinkCreateRejected(:final code) => code,
      OrganizationShareableJoinLinkPreviewRejected(:final code) => code,
      OrganizationShareableJoinApplicationSubmitRejected(:final code) => code,
      OrganizationShareableJoinApplicationApproveRejected(:final code) => code,
      _ => throw StateError('expected rejected shareable join result'),
    };

void _expectSuccess(Object result, _Operation operation) {
  expect(result, switch (operation) {
    _Operation.createLink => isA<OrganizationShareableJoinLinkCreateSuccess>(),
    _Operation.previewLink =>
      isA<OrganizationShareableJoinLinkPreviewSuccess>(),
    _Operation.submitApplication =>
      isA<OrganizationShareableJoinApplicationSubmitSuccess>(),
    _Operation.approveApplication =>
      isA<OrganizationShareableJoinApplicationApproveSuccess>(),
  });
}

Map<String, Object?> _successJson(_Operation operation) => switch (operation) {
  _Operation.createLink => _linkCreateReceiptJson(),
  _Operation.previewLink => _linkPreviewReceiptJson(),
  _Operation.submitApplication => _applicationSubmitReceiptJson(),
  _Operation.approveApplication => _applicationApproveReceiptJson(),
};

Map<String, Object?> _linkCreateReceiptJson() => {
  'organization_shareable_join_link_contract_id': _linkContract,
  'link_id': _linkId,
  'organization_workspace_id': _workspaceId,
  'issued_at_utc': '2000-01-01T00:00:00.000Z',
  'expires_at_utc': '2000-01-08T00:00:00.000Z',
};

Map<String, Object?> _linkPreviewReceiptJson() => {
  'organization_shareable_join_link_preview_contract_id': _previewContract,
  'link_id': _linkId,
  'organization_name': ' 同行组织 ',
  'expires_at_utc': '2030-01-08T00:00:00.000Z',
};

Map<String, Object?> _applicationSubmitReceiptJson() => {
  'organization_shareable_join_application_contract_id': _applicationContract,
  'application_id': _applicationId,
  'link_id': _linkId,
  'organization_workspace_id': _workspaceId,
  'submitted_at_utc': '2000-01-01T00:00:00.000Z',
  'expires_at_utc': '2000-01-08T00:00:00.000Z',
};

Map<String, Object?> _applicationApproveReceiptJson() => {
  'organization_shareable_join_application_contract_id': _applicationContract,
  'application_id': _applicationId,
  'organization_workspace_id': _workspaceId,
  'organization_membership_id': _membershipId,
  'approved_at_utc': '2030-01-02T04:05:06.000Z',
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

IdentitySuccess<IdentityAccessToken> _accessToken(String value) =>
    IdentitySuccess(
      IdentityAccessToken(value: value, expiresAt: DateTime.utc(2030)),
    );

const _jsonHeaders = {
  'content-type': 'application/json; charset=utf-8',
  'cache-control': 'no-store',
};

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
  final List<bool> accessTokenForceRefreshValues = [];
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

  @override
  Future<void> close() => _changes.close();

  @override
  Future<IdentityResult<IdentityAccessToken>> accessToken({
    bool forceRefresh = false,
  }) async {
    accessTokenForceRefreshValues.add(forceRefresh);
    final handler = accessTokenHandler;
    if (handler != null) return handler(forceRefresh);
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

const _initialIdentity = IdentitySnapshot(
  stage: IdentityStage.signedIn,
  principal: IdentityPrincipal(externalSubject: 'subject-1', email: null),
);

const _otherIdentity = IdentitySnapshot(
  stage: IdentityStage.signedIn,
  principal: IdentityPrincipal(externalSubject: 'subject-2', email: null),
);
