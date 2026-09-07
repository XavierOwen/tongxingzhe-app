import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tongxingzhe_app/foundation/backend_base_uri.dart';
import 'package:tongxingzhe_app/identity/identity_session.dart';
import 'package:tongxingzhe_app/organization_directed_account_invitation/http_organization_directed_account_invitation_gateway.dart';
import 'package:tongxingzhe_app/organization_directed_account_invitation/organization_directed_account_invitation.dart';

import '../support/fake_identity_session.dart';

void main() {
  test('create sends the exact route, headers, and canonical body', () async {
    late http.Request request;
    final gateway = _gateway((value) async {
      request = value;
      return _json(_createReceiptJson());
    });
    addTearDown(gateway.close);

    final result = await gateway.create(
      invitationId: _invitationId.toUpperCase(),
      organizationWorkspaceId: _workspaceId.toUpperCase(),
      targetAppUserId: _targetAppUserId.toUpperCase(),
    );

    expect(request.method, 'POST');
    expect(
      request.url,
      Uri.parse(
        'https://backend.example.test/v1/organizations/$_workspaceId/'
        'directed-account-invitations',
      ),
    );
    _expectHeaders(request);
    expect(
      request.body,
      jsonEncode({
        'invitation_id': _invitationId,
        'target_app_user_id': _targetAppUserId,
      }),
    );
    expect(result, isA<OrganizationDirectedAccountInvitationCreateSuccess>());
  });

  test('accept sends the invitation path and an exact empty object', () async {
    late http.Request request;
    final gateway = _gateway((value) async {
      request = value;
      return _json(_acceptReceiptJson());
    });
    addTearDown(gateway.close);

    final result = await gateway.accept(
      invitationId: _invitationId.toUpperCase(),
    );

    expect(request.method, 'POST');
    expect(
      request.url,
      Uri.parse(
        'https://backend.example.test/v1/'
        'organization-directed-account-invitations/$_invitationId/accept',
      ),
    );
    _expectHeaders(request);
    expect(request.body, '{}');
    expect(jsonDecode(request.body), <String, Object?>{});
    expect(result, isA<OrganizationDirectedAccountInvitationAcceptSuccess>());
  });

  test(
    'preview sends a bodyless GET and parses the exact preview snapshot',
    () async {
      late http.Request request;
      final gateway = _gateway((value) async {
        request = value;
        return _json(_previewJson());
      });
      addTearDown(gateway.close);

      final result = await gateway.preview(
        invitationId: _invitationId.toUpperCase(),
      );

      expect(request.method, 'GET');
      expect(
        request.url,
        Uri.parse(
          'https://backend.example.test/v1/'
          'organization-directed-account-invitations/$_invitationId',
        ),
      );
      expect(request.body, isEmpty);
      expect(request.headers, {
        'accept': 'application/json',
        'authorization': 'Bearer test-only-access-token',
      });
      final preview =
          (result as OrganizationDirectedAccountInvitationPreviewSuccess)
              .preview;
      expect(
        preview.organizationInvitationPreviewContractId,
        'organization-directed-account-invitation-preview:v1',
      );
      expect(preview.invitationId, _invitationId);
      expect(preview.organizationName, '同行组织');
      expect(preview.expiresAtUtc, DateTime.utc(2030, 1, 8));
    },
  );

  test(
    'preview late transport failure after identity change is unauthorized',
    () async {
      final identity = _RotatingTokenIdentitySession();
      final sent = Completer<void>();
      final response = Completer<http.Response>();
      final gateway = HttpOrganizationDirectedAccountInvitationGateway(
        baseUri: Uri.parse('https://backend.example.test'),
        identitySession: identity,
        client: MockClient((_) {
          sent.complete();
          return response.future;
        }),
      );
      addTearDown(gateway.close);
      addTearDown(identity.close);

      final pending = gateway.preview(invitationId: _invitationId);
      await sent.future;
      identity.emit(_otherIdentity);
      response.completeError(http.ClientException('late old-account failure'));

      expect(_failureCode(await pending), _Failure.unauthorized);
    },
  );

  test(
    'preview late transport failure checks the current identity fence',
    () async {
      final identity = _RotatingTokenIdentitySession();
      final sent = Completer<void>();
      final response = Completer<http.Response>();
      final gateway = HttpOrganizationDirectedAccountInvitationGateway(
        baseUri: Uri.parse('https://backend.example.test'),
        identitySession: identity,
        client: MockClient((_) {
          sent.complete();
          return response.future;
        }),
      );
      addTearDown(gateway.close);
      addTearDown(identity.close);

      final pending = gateway.preview(invitationId: _invitationId);
      await sent.future;
      identity.setCurrentWithoutEmit(_otherIdentity);
      response.completeError(http.ClientException('late old-account failure'));

      expect(_failureCode(await pending), _Failure.unauthorized);
    },
  );

  test(
    'preview rejects every invalid snapshot field and preserves name',
    () async {
      final invalid = <String, http.Response>{
        'malformed JSON': _raw('{'),
        'non-object': _raw('[]'),
        'extra sensitive field': _json({
          ..._previewJson(),
          'organization_workspace_id': _workspaceId,
        }),
        'missing field': _json(_previewJson()..remove('expires_at_utc')),
        'contract': _json({
          ..._previewJson(),
          'organization_invitation_preview_contract_id': 'other:v1',
        }),
        'invitation binding': _json({
          ..._previewJson(),
          'invitation_id': _otherId,
        }),
        'uppercase UUID': _json({
          ..._previewJson(),
          'invitation_id': _invitationId.toUpperCase(),
        }),
        'name type': _json({..._previewJson(), 'organization_name': 1}),
        'ordinary-space-only name': _json({
          ..._previewJson(),
          'organization_name': '   ',
        }),
        'offset time': _json({
          ..._previewJson(),
          'expires_at_utc': '2030-01-07T18:00:00.000-06:00',
        }),
        'invalid date': _json({
          ..._previewJson(),
          'expires_at_utc': '2030-02-30T00:00:00.000Z',
        }),
        'cacheable response': _json(
          _previewJson(),
          headers: const {
            'content-type': 'application/json; charset=utf-8',
            'cache-control': 'private',
          },
        ),
      };

      for (final entry in invalid.entries) {
        final gateway = _gateway((_) async => entry.value);
        final result = await gateway.preview(invitationId: _invitationId);
        await gateway.close();
        expect(
          _failureCode(result),
          _Failure.invalidResponse,
          reason: entry.key,
        );
      }

      const originalName = '\u00a0Legacy\u200b 0  ';
      final gateway = _gateway(
        (_) async =>
            _json({..._previewJson(), 'organization_name': originalName}),
      );
      final result = await gateway.preview(invitationId: _invitationId);
      await gateway.close();
      expect(
        (result as OrganizationDirectedAccountInvitationPreviewSuccess)
            .preview
            .organizationName,
        originalName,
      );
    },
  );

  test('invalid UUIDs stop before identity and HTTP access', () async {
    final createInputs = [
      (
        invitation: 'not-a-uuid',
        workspace: _workspaceId,
        target: _targetAppUserId,
      ),
      (
        invitation: _invitationId,
        workspace: 'not-a-uuid',
        target: _targetAppUserId,
      ),
      (
        invitation: _invitationId,
        workspace: _workspaceId,
        target: 'not-a-uuid',
      ),
    ];

    for (final input in createInputs) {
      final identity = _identity();
      var requests = 0;
      final gateway = _gateway((_) async {
        requests++;
        return _json(_createReceiptJson());
      }, identity: identity);
      final result = await gateway.create(
        invitationId: input.invitation,
        organizationWorkspaceId: input.workspace,
        targetAppUserId: input.target,
      );
      await gateway.close();

      expect(_failureCode(result), _Failure.invalidRequest);
      expect(identity.accessTokenForceRefreshValues, isEmpty);
      expect(requests, 0);
    }

    final identity = _identity();
    var requests = 0;
    final gateway = _gateway((_) async {
      requests++;
      return _json(_acceptReceiptJson());
    }, identity: identity);
    final result = await gateway.accept(invitationId: 'not-a-uuid');
    await gateway.close();
    expect(_failureCode(result), _Failure.invalidRequest);
    expect(identity.accessTokenForceRefreshValues, isEmpty);
    expect(requests, 0);

    final previewIdentity = _identity();
    final previewGateway = _gateway((_) async {
      requests++;
      return _json(_previewJson());
    }, identity: previewIdentity);
    final preview = await previewGateway.preview(invitationId: 'not-a-uuid');
    await previewGateway.close();
    expect(_failureCode(preview), _Failure.invalidRequest);
    expect(previewIdentity.accessTokenForceRefreshValues, isEmpty);
    expect(requests, 0);
  });

  test(
    'deferred create, preview, and accept are no-network and repeatably close',
    () async {
      const gateway = DeferredOrganizationDirectedAccountInvitationGateway();

      final create = await gateway.create(
        invitationId: _invitationId,
        organizationWorkspaceId: _workspaceId,
        targetAppUserId: _targetAppUserId,
      );
      final preview = await gateway.preview(invitationId: _invitationId);
      final accept = await gateway.accept(invitationId: _invitationId);
      await gateway.close();
      await gateway.close();

      expect(_failureCode(create), _Failure.notConfigured);
      expect(_failureCode(preview), _Failure.notConfigured);
      expect(_failureCode(accept), _Failure.notConfigured);
    },
  );

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
        final gateway = productionOrganizationDirectedAccountInvitationGateway(
          identity,
        );
        expect(
          gateway,
          validConfiguredUri
              ? isA<HttpOrganizationDirectedAccountInvitationGateway>()
              : isA<DeferredOrganizationDirectedAccountInvitationGateway>(),
        );
        await gateway.close();
      } else {
        expect(
          () =>
              productionOrganizationDirectedAccountInvitationGateway(identity),
          anyOf(throwsArgumentError, throwsFormatException),
        );
      }
      expect(identity.accessTokenForceRefreshValues, isEmpty);
      expect(identity.isClosed, isFalse);
    },
  );

  test('HTTP gateway rejects invalid base URIs synchronously', () {
    final identity = _identity();
    final client = _TrackingMockClient(
      (_) async => _json(_createReceiptJson()),
    );

    for (final uri in [
      Uri.parse('https://backend.example.test/path'),
      Uri.parse('http://backend.example.test'),
    ]) {
      expect(
        () => HttpOrganizationDirectedAccountInvitationGateway(
          baseUri: uri,
          identitySession: identity,
          client: client,
        ),
        throwsArgumentError,
      );
    }
    expect(client.closeCount, 0);
  });

  test('identity failures map without sending either operation', () async {
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
        return _json(_createReceiptJson());
      }, identity: identity);

      final result = await gateway.create(
        invitationId: _invitationId,
        organizationWorkspaceId: _workspaceId,
        targetAppUserId: _targetAppUserId,
      );
      await gateway.close();

      expect(_failureCode(result), testCase.$2);
      expect(requests, 0);
    }
  });

  test(
    'each operation refreshes once and retries the same URL and body',
    () async {
      for (final create in [true, false]) {
        final identity = _RotatingTokenIdentitySession();
        final requests = <http.Request>[];
        final gateway = HttpOrganizationDirectedAccountInvitationGateway(
          baseUri: Uri.parse('https://backend.example.test'),
          identitySession: identity,
          client: MockClient((request) async {
            requests.add(request);
            if (requests.length == 1) {
              return _error('unauthenticated', 401);
            }
            return _json(create ? _createReceiptJson() : _acceptReceiptJson());
          }),
        );
        final result = await _invoke(gateway, create: create);
        await gateway.close();

        expect(
          result,
          create
              ? isA<OrganizationDirectedAccountInvitationCreateSuccess>()
              : isA<OrganizationDirectedAccountInvitationAcceptSuccess>(),
        );
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
    },
  );

  test('a malformed 401 does not refresh', () async {
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
      final result = await gateway.accept(invitationId: _invitationId);
      await gateway.close();

      expect(_failureCode(result), _Failure.invalidResponse);
      expect(requests, 1);
      expect(identity.accessTokenForceRefreshValues, [false]);
    }
  });

  test('failed refresh stops retry and a second 401 stops the loop', () async {
    final failedRefreshIdentity = _identity();
    var requests = 0;
    final failedRefreshGateway = _gateway((_) async {
      requests++;
      failedRefreshIdentity.rejectNextAccessTokenWith = const IdentityFailure(
        code: IdentityFailureCode.sessionMissing,
      );
      return _error('unauthenticated', 401);
    }, identity: failedRefreshIdentity);
    final failedRefresh = await failedRefreshGateway.accept(
      invitationId: _invitationId,
    );
    await failedRefreshGateway.close();
    expect(_failureCode(failedRefresh), _Failure.unauthorized);
    expect(requests, 1);

    final secondIdentity = _identity();
    requests = 0;
    final secondGateway = _gateway((_) async {
      requests++;
      return _error('unauthenticated', 401);
    }, identity: secondIdentity);
    final second = await secondGateway.create(
      invitationId: _invitationId,
      organizationWorkspaceId: _workspaceId,
      targetAppUserId: _targetAppUserId,
    );
    await secondGateway.close();
    expect(_failureCode(second), _Failure.unauthorized);
    expect(requests, 2);
    expect(secondIdentity.accessTokenForceRefreshValues, [false, true]);
  });

  test('preview refreshes once and retries the same bodyless GET', () async {
    final identity = _RotatingTokenIdentitySession();
    final requests = <http.Request>[];
    final gateway = _gateway((request) async {
      requests.add(request);
      return requests.length == 1
          ? _error('unauthenticated', 401)
          : _json(_previewJson());
    }, identity: identity);

    final result = await gateway.preview(invitationId: _invitationId);
    await gateway.close();
    await identity.close();

    expect(result, isA<OrganizationDirectedAccountInvitationPreviewSuccess>());
    expect(requests, hasLength(2));
    expect(requests.every((request) => request.method == 'GET'), isTrue);
    expect(requests.every((request) => request.body.isEmpty), isTrue);
    expect(requests[0].url, requests[1].url);
    expect(requests.map((request) => request.headers['authorization']), [
      'Bearer stale-test-access-token',
      'Bearer refreshed-test-access-token',
    ]);
  });

  test(
    'strict independent receipts preserve UTC values and old create replay',
    () async {
      final createGateway = _gateway((_) async => _json(_createReceiptJson()));
      final create = await createGateway.create(
        invitationId: _invitationId,
        organizationWorkspaceId: _workspaceId,
        targetAppUserId: _targetAppUserId,
      );
      await createGateway.close();
      final createReceipt =
          (create as OrganizationDirectedAccountInvitationCreateSuccess)
              .receipt;
      expect(createReceipt.organizationInvitationContractId, _contractId);
      expect(createReceipt.invitationId, _invitationId);
      expect(createReceipt.organizationWorkspaceId, _workspaceId);
      expect(createReceipt.issuedAtUtc, DateTime.utc(2000));
      expect(createReceipt.expiresAtUtc, DateTime.utc(2000, 1, 8));
      expect(createReceipt.expiresAtUtc.isUtc, isTrue);

      final acceptGateway = _gateway((_) async => _json(_acceptReceiptJson()));
      final accept = await acceptGateway.accept(invitationId: _invitationId);
      await acceptGateway.close();
      final acceptReceipt =
          (accept as OrganizationDirectedAccountInvitationAcceptSuccess)
              .receipt;
      expect(acceptReceipt.organizationInvitationContractId, _contractId);
      expect(acceptReceipt.invitationId, _invitationId);
      expect(acceptReceipt.organizationWorkspaceId, _workspaceId);
      expect(acceptReceipt.organizationMembershipId, _membershipId);
      expect(acceptReceipt.acceptedAtUtc, DateTime.utc(2030, 1, 2, 4, 5, 6));
      expect(acceptReceipt.acceptedAtUtc.isUtc, isTrue);
    },
  );

  test(
    'create rejects receipt shape, binding, time, and expiry drift',
    () async {
      final cases = <String, String>{
        'malformed JSON': '{',
        'non-object': '[]',
        'extra field': jsonEncode({..._createReceiptJson(), 'extra': true}),
        'missing field': jsonEncode(
          _createReceiptJson()..remove('expires_at_utc'),
        ),
        'contract': jsonEncode({
          ..._createReceiptJson(),
          'organization_invitation_contract_id': 'other:v1',
        }),
        'invitation binding': jsonEncode({
          ..._createReceiptJson(),
          'invitation_id': _otherId,
        }),
        'workspace binding': jsonEncode({
          ..._createReceiptJson(),
          'organization_workspace_id': _otherId,
        }),
        'uppercase UUID': jsonEncode({
          ..._createReceiptJson(),
          'invitation_id': _invitationId.toUpperCase(),
        }),
        'timestamp type': jsonEncode({
          ..._createReceiptJson(),
          'issued_at_utc': 1,
        }),
        'non-canonical time': jsonEncode({
          ..._createReceiptJson(),
          'issued_at_utc': '2000-01-01T00:00:00Z',
        }),
        'invalid date': jsonEncode({
          ..._createReceiptJson(),
          'issued_at_utc': '2000-02-30T00:00:00.000Z',
        }),
        'expiry drift': jsonEncode({
          ..._createReceiptJson(),
          'expires_at_utc': '2000-01-07T23:59:59.999Z',
        }),
      };

      for (final entry in cases.entries) {
        final gateway = _gateway((_) async => _raw(entry.value));
        final result = await gateway.create(
          invitationId: _invitationId,
          organizationWorkspaceId: _workspaceId,
          targetAppUserId: _targetAppUserId,
        );
        await gateway.close();
        expect(
          _failureCode(result),
          _Failure.invalidResponse,
          reason: entry.key,
        );
      }
    },
  );

  test('accept rejects receipt shape, binding, UUID, and time drift', () async {
    final cases = <String, String>{
      'extra field': jsonEncode({..._acceptReceiptJson(), 'extra': true}),
      'missing field': jsonEncode(
        _acceptReceiptJson()..remove('organization_membership_id'),
      ),
      'contract': jsonEncode({
        ..._acceptReceiptJson(),
        'organization_invitation_contract_id': 'other:v1',
      }),
      'invitation binding': jsonEncode({
        ..._acceptReceiptJson(),
        'invitation_id': _otherId,
      }),
      'workspace UUID': jsonEncode({
        ..._acceptReceiptJson(),
        'organization_workspace_id': 'not-a-uuid',
      }),
      'membership UUID': jsonEncode({
        ..._acceptReceiptJson(),
        'organization_membership_id': _membershipId.toUpperCase(),
      }),
      'offset time': jsonEncode({
        ..._acceptReceiptJson(),
        'accepted_at_utc': '2030-01-01T22:05:06.000-06:00',
      }),
      'invalid date': jsonEncode({
        ..._acceptReceiptJson(),
        'accepted_at_utc': '2030-02-30T04:05:06.000Z',
      }),
    };

    for (final entry in cases.entries) {
      final gateway = _gateway((_) async => _raw(entry.value));
      final result = await gateway.accept(invitationId: _invitationId);
      await gateway.close();
      expect(_failureCode(result), _Failure.invalidResponse, reason: entry.key);
    }
  });

  test('responses require exact JSON UTF-8 and no-store headers', () async {
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
        'cache-control': 'private',
      },
    ];

    for (final responseHeaders in headers) {
      final gateway = _gateway(
        (_) async => _json(_acceptReceiptJson(), headers: responseHeaders),
      );
      final result = await gateway.accept(invitationId: _invitationId);
      await gateway.close();
      expect(_failureCode(result), _Failure.invalidResponse);
    }
  });

  test('both operations map every stable error envelope', () async {
    const cases = [
      (400, 'invalid_json', _Failure.invalidJson),
      (400, 'invalid_organization_invitation_request', _Failure.invalidRequest),
      (401, 'unauthenticated', _Failure.unauthorized),
      (403, 'organization_invitation_forbidden', _Failure.forbidden),
      (409, 'organization_invitation_conflict', _Failure.conflict),
      (413, 'payload_too_large', _Failure.payloadTooLarge),
      (503, 'organization_invitation_unavailable', _Failure.serviceUnavailable),
    ];

    for (final create in [true, false]) {
      for (final testCase in cases) {
        final gateway = _gateway((_) async => _error(testCase.$2, testCase.$1));
        final result = await _invoke(gateway, create: create);
        await gateway.close();
        expect(_failureCode(result), testCase.$3);
      }
    }
  });

  test('preview maps every stable error envelope', () async {
    const cases = [
      (400, 'invalid_json', _Failure.invalidJson),
      (400, 'invalid_organization_invitation_request', _Failure.invalidRequest),
      (401, 'unauthenticated', _Failure.unauthorized),
      (403, 'organization_invitation_forbidden', _Failure.forbidden),
      (409, 'organization_invitation_conflict', _Failure.conflict),
      (413, 'payload_too_large', _Failure.payloadTooLarge),
      (503, 'organization_invitation_unavailable', _Failure.serviceUnavailable),
    ];

    for (final testCase in cases) {
      final gateway = _gateway((_) async => _error(testCase.$2, testCase.$1));
      final result = await gateway.preview(invitationId: _invitationId);
      await gateway.close();
      expect(_failureCode(result), testCase.$3);
    }
  });

  test(
    'identity change while awaiting a token stops every operation',
    () async {
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
    },
  );

  test('HTTP sign-out and sign-in ABA invalidates every operation', () async {
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
      identity.emit(const IdentitySnapshot.signedOut());
      identity.emit(_initialIdentity);
      response.complete(_json(_successJson(operation)));

      expect(_failureCode(await pending), _Failure.unauthorized);
      await gateway.close();
      await identity.close();
    }
  });

  test(
    '401 refresh ABA cannot send new credentials for any operation',
    () async {
      for (final operation in _Operation.values) {
        late _RotatingTokenIdentitySession identity;
        identity = _RotatingTokenIdentitySession(
          accessTokenHandler: (forceRefresh) async {
            if (forceRefresh) {
              identity.emit(const IdentitySnapshot.signedOut());
              identity.emit(_initialIdentity);
              return _accessToken('new-account-token');
            }
            return _accessToken('stale-test-access-token');
          },
        );
        var requests = 0;
        final gateway = _gateway((_) async {
          requests++;
          return _error('unauthenticated', 401);
        }, identity: identity);

        final result = await _invokeOperation(gateway, operation);

        expect(_failureCode(result), _Failure.unauthorized);
        expect(requests, 1);
        expect(identity.accessTokenForceRefreshValues, [false, true]);
        await gateway.close();
        await identity.close();
      }
    },
  );

  test('close during HTTP prevents stale preview delivery', () async {
    final sent = Completer<void>();
    final response = Completer<http.Response>();
    final identity = _RotatingTokenIdentitySession();
    final gateway = _gateway((_) {
      sent.complete();
      return response.future;
    }, identity: identity);

    final pending = gateway.preview(invitationId: _invitationId);
    await sent.future;
    await gateway.close();
    response.complete(_json(_previewJson()));

    expect(_failureCode(await pending), _Failure.unauthorized);
    await identity.close();
  });

  test(
    'cleanup start is covered by the final identity check for every operation',
    () async {
      for (final closeGateway in [false, true]) {
        for (final operation in _Operation.values) {
          late _RotatingTokenIdentitySession identity;
          late HttpOrganizationDirectedAccountInvitationGateway gateway;
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
            (_) async => _json(_successJson(operation)),
            identity: identity,
          );
          addTearDown(gateway.close);
          addTearDown(identity.close);

          final result = await _invokeOperation(gateway, operation);

          expect(
            _failureCode(result),
            _Failure.unauthorized,
            reason: '${operation.name}, close=$closeGateway',
          );
        }
      }
    },
  );

  test(
    'cleanup gate and future errors do not delay or escape typed results',
    () async {
      for (final failCleanup in [false, true]) {
        for (final operation in _Operation.values) {
          final cancelStarted = Completer<void>();
          final finishCancel = Completer<void>();
          final identity = _RotatingTokenIdentitySession(
            onChangesCancel: () {
              cancelStarted.complete();
              return finishCancel.future;
            },
          );
          final gateway = _gateway(
            (_) async => _json(_successJson(operation)),
            identity: identity,
          );
          addTearDown(gateway.close);
          addTearDown(identity.close);
          addTearDown(() {
            if (!finishCancel.isCompleted) finishCancel.complete();
          });

          final resultDelivered = Completer<Object>();
          _invokeOperation(gateway, operation).then(
            resultDelivered.complete,
            onError: resultDelivered.completeError,
          );
          await cancelStarted.future;
          await Future<void>.delayed(Duration.zero);

          expect(
            resultDelivered.isCompleted,
            isTrue,
            reason: '${operation.name}, failCleanup=$failCleanup',
          );
          expect(await resultDelivered.future, switch (operation) {
            _Operation.create =>
              isA<OrganizationDirectedAccountInvitationCreateSuccess>(),
            _Operation.preview =>
              isA<OrganizationDirectedAccountInvitationPreviewSuccess>(),
            _Operation.accept =>
              isA<OrganizationDirectedAccountInvitationAcceptSuccess>(),
          });
          if (failCleanup) {
            finishCancel.completeError(StateError('test-only cleanup failure'));
          } else {
            finishCancel.complete();
          }
          await Future<void>.delayed(Duration.zero);
        }
      }
    },
  );

  test('unknown status, code, or envelope maps to invalidResponse', () async {
    final cases = <http.Response Function()>[
      () => _error('not_found', 404),
      () => _error('expired', 403),
      () => _error('unknown', 418),
      () => _json({
        'error': {'code': 'invalid_json'},
        'extra': true,
      }, status: 400),
      () => _json({
        'error': {'message': 'provider detail'},
      }, status: 503),
      () => _json(_createReceiptJson(), status: 201),
    ];

    for (final response in cases) {
      final gateway = _gateway((_) async => response());
      final result = await gateway.create(
        invitationId: _invitationId,
        organizationWorkspaceId: _workspaceId,
        targetAppUserId: _targetAppUserId,
      );
      await gateway.close();
      expect(_failureCode(result), _Failure.invalidResponse);
    }
  });

  test(
    'network, timeout, and unknown adapter failures stay redacted',
    () async {
      final networkGateway = _gateway(
        (_) => Future<http.Response>.error(
          http.ClientException('database detail'),
        ),
      );
      final network = await networkGateway.accept(invitationId: _invitationId);
      await networkGateway.close();
      expect(_failureCode(network), _Failure.networkUnavailable);

      final timeoutGateway = _gateway(
        (_) => Future<http.Response>.delayed(
          const Duration(milliseconds: 50),
          () => _json(_acceptReceiptJson()),
        ),
        timeout: const Duration(milliseconds: 1),
      );
      final timeout = await timeoutGateway.accept(invitationId: _invitationId);
      await timeoutGateway.close();
      expect(_failureCode(timeout), _Failure.networkUnavailable);

      final adapterGateway = _gateway(
        (_) => Future<http.Response>.error(StateError('provider detail')),
      );
      final adapter = await adapterGateway.accept(invitationId: _invitationId);
      await adapterGateway.close();
      expect(_failureCode(adapter), _Failure.invalidResponse);
    },
  );

  test('close owns the HTTP client once and leaves identity open', () async {
    final identity = _identity();
    final client = _TrackingMockClient(
      (_) async => _json(_createReceiptJson()),
    );
    final gateway = _gateway(
      (_) async => _json(_createReceiptJson()),
      identity: identity,
      client: client,
    );

    await gateway.close();
    await gateway.close();

    expect(client.closeCount, 1);
    expect(identity.isClosed, isFalse);
  });
}

typedef _Failure = OrganizationDirectedAccountInvitationFailureCode;

enum _Operation { create, preview, accept }

const _contractId = 'organization-directed-account-invitation:v1';
const _invitationId = 'abcdefab-cdef-0abc-0def-abcdefabcdef';
const _workspaceId = 'abcdefab-cdef-0abc-0def-abcdefabcdea';
const _targetAppUserId = 'abcdefab-cdef-0abc-0def-abcdefabcdeb';
const _membershipId = 'abcdefab-cdef-0abc-0def-abcdefabcdec';
const _otherId = 'abcdefab-cdef-0abc-0def-abcdefabcded';

FakeIdentitySession _identity() => FakeIdentitySession(
  initial: const IdentitySnapshot(
    stage: IdentityStage.signedIn,
    principal: IdentityPrincipal(
      externalSubject: 'subject-1',
      email: 'owner@example.test',
    ),
  ),
);

HttpOrganizationDirectedAccountInvitationGateway _gateway(
  Future<http.Response> Function(http.Request) handler, {
  IdentitySession? identity,
  http.Client? client,
  Duration timeout = const Duration(seconds: 15),
}) => HttpOrganizationDirectedAccountInvitationGateway(
  baseUri: Uri.parse('https://backend.example.test'),
  identitySession: identity ?? _identity(),
  client: client ?? MockClient(handler),
  timeout: timeout,
);

Future<Object> _invoke(
  OrganizationDirectedAccountInvitationGateway gateway, {
  required bool create,
}) async => create
    ? gateway.create(
        invitationId: _invitationId,
        organizationWorkspaceId: _workspaceId,
        targetAppUserId: _targetAppUserId,
      )
    : gateway.accept(invitationId: _invitationId);

Future<Object> _invokeOperation(
  OrganizationDirectedAccountInvitationGateway gateway,
  _Operation operation,
) => switch (operation) {
  _Operation.create => gateway.create(
    invitationId: _invitationId,
    organizationWorkspaceId: _workspaceId,
    targetAppUserId: _targetAppUserId,
  ),
  _Operation.preview => gateway.preview(invitationId: _invitationId),
  _Operation.accept => gateway.accept(invitationId: _invitationId),
};

OrganizationDirectedAccountInvitationFailureCode _failureCode(Object result) {
  return switch (result) {
    OrganizationDirectedAccountInvitationCreateRejected(:final code) => code,
    OrganizationDirectedAccountInvitationPreviewRejected(:final code) => code,
    OrganizationDirectedAccountInvitationAcceptRejected(:final code) => code,
    _ => throw StateError('expected rejected invitation result'),
  };
}

void _expectHeaders(http.Request request) {
  expect(request.url.query, isEmpty);
  expect(request.url.fragment, isEmpty);
  expect(request.headers, {
    'accept': 'application/json',
    'authorization': 'Bearer test-only-access-token',
    'content-type': 'application/json; charset=utf-8',
  });
  expect(request.headers.containsKey('idempotency-key'), isFalse);
}

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

Map<String, Object?> _createReceiptJson() => {
  'organization_invitation_contract_id': _contractId,
  'invitation_id': _invitationId,
  'organization_workspace_id': _workspaceId,
  'issued_at_utc': '2000-01-01T00:00:00.000Z',
  'expires_at_utc': '2000-01-08T00:00:00.000Z',
};

Map<String, Object?> _acceptReceiptJson() => {
  'organization_invitation_contract_id': _contractId,
  'invitation_id': _invitationId,
  'organization_workspace_id': _workspaceId,
  'organization_membership_id': _membershipId,
  'accepted_at_utc': '2030-01-02T04:05:06.000Z',
};

Map<String, Object?> _previewJson() => {
  'organization_invitation_preview_contract_id':
      'organization-directed-account-invitation-preview:v1',
  'invitation_id': _invitationId,
  'organization_name': '同行组织',
  'expires_at_utc': '2030-01-08T00:00:00.000Z',
};

Map<String, Object?> _successJson(_Operation operation) => switch (operation) {
  _Operation.create => _createReceiptJson(),
  _Operation.preview => _previewJson(),
  _Operation.accept => _acceptReceiptJson(),
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

const _otherIdentity = IdentitySnapshot(
  stage: IdentityStage.signedIn,
  principal: IdentityPrincipal(externalSubject: 'subject-2', email: null),
);

const _initialIdentity = IdentitySnapshot(
  stage: IdentityStage.signedIn,
  principal: IdentityPrincipal(externalSubject: 'subject-1', email: null),
);
