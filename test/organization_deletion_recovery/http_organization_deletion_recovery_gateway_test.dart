import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tongxingzhe_app/identity/identity_session.dart';
import 'package:tongxingzhe_app/organization_deletion_recovery/http_organization_deletion_recovery_gateway.dart';
import 'package:tongxingzhe_app/organization_deletion_recovery/organization_deletion_recovery.dart';

import '../support/fake_identity_session.dart';

void main() {
  test(
    'uses the exact recovery directory and lifecycle wire contracts',
    () async {
      final requests = <http.Request>[];
      final gateway = _gateway((request) async {
        requests.add(request);
        if (request.method == 'GET') {
          return _json({
            'organization_deletion_recovery_directory_contract_id':
                _directoryContract,
            'items': [_directoryItem],
          });
        }
        if (request.url.path.endsWith('/deletion-requests')) {
          return _json(_deletionReceipt);
        }
        return _json(_restorationReceipt);
      });
      addTearDown(gateway.close);

      final directory = await gateway.listRecoverableOrganizations();
      final deletion = await gateway.requestDeletion(
        requestId: _requestId.toUpperCase(),
        organizationWorkspaceId: _workspace.toUpperCase(),
      );
      final restoration = await gateway.restore(
        requestId: _requestId,
        organizationWorkspaceId: _workspace,
        deletionRequestId: _deletionId,
      );

      expect(
        directory,
        isA<
          OrganizationDeletionRecoverySuccess<
            OrganizationDeletionRecoveryDirectory
          >
        >(),
      );
      expect(
        (directory
                as OrganizationDeletionRecoverySuccess<
                  OrganizationDeletionRecoveryDirectory
                >)
            .value
            .items
            .single
            .displayName,
        'North team',
      );
      expect(
        deletion,
        isA<
          OrganizationDeletionRecoverySuccess<
            OrganizationDeletionRequestReceipt
          >
        >(),
      );
      expect(
        restoration,
        isA<
          OrganizationDeletionRecoverySuccess<OrganizationRestorationReceipt>
        >(),
      );
      expect(requests.map((request) => (request.method, request.url.path)), [
        ('GET', '/v1/organizations/deletion-recovery'),
        ('POST', '/v1/organizations/$_workspace/deletion-requests'),
        ('POST', '/v1/organizations/$_workspace/restorations'),
      ]);
      expect(requests[0].url.query, isEmpty);
      expect(requests[0].headers, {
        'accept': 'application/json',
        'authorization': 'Bearer test-only-access-token',
      });
      expect(requests[1].body, jsonEncode({'request_id': _requestId}));
      expect(
        requests[2].body,
        jsonEncode({
          'request_id': _requestId,
          'deletion_request_id': _deletionId,
        }),
      );
      expect(
        requests[1].headers['content-type'],
        'application/json; charset=utf-8',
      );
    },
  );

  test('rejects invalid identifiers before identity or HTTP access', () async {
    final identity = FakeIdentitySession();
    var requests = 0;
    final gateway = HttpOrganizationDeletionRecoveryGateway(
      baseUri: Uri.parse('https://backend.example.test'),
      identitySession: identity,
      client: MockClient((_) async {
        requests++;
        return _json({});
      }),
    );
    final result = await gateway.restore(
      requestId: 'invalid',
      organizationWorkspaceId: _workspace,
      deletionRequestId: _deletionId,
    );
    await gateway.close();
    expect(
      (result as OrganizationDeletionRecoveryRejected).code,
      OrganizationDeletionRecoveryFailureCode.invalidRequest,
    );
    expect(identity.accessTokenForceRefreshValues, isEmpty);
    expect(requests, 0);
  });

  test(
    'maps forbidden, conflict, unavailable, and malformed success',
    () async {
      final forbiddenGateway = _gateway(
        (_) async =>
            _error('organization_deletion_recovery_directory_forbidden', 403),
      );
      final forbidden = await forbiddenGateway.listRecoverableOrganizations();
      await forbiddenGateway.close();
      expect(
        (forbidden as OrganizationDeletionRecoveryRejected).code,
        OrganizationDeletionRecoveryFailureCode.forbidden,
      );

      final conflictGateway = _gateway(
        (_) async => _error('organization_restoration_conflict', 409),
      );
      final conflict = await conflictGateway.restore(
        requestId: _requestId,
        organizationWorkspaceId: _workspace,
        deletionRequestId: _deletionId,
      );
      await conflictGateway.close();
      expect(
        (conflict as OrganizationDeletionRecoveryRejected).code,
        OrganizationDeletionRecoveryFailureCode.conflict,
      );

      final unavailableGateway = _gateway(
        (_) async => _error('organization_deletion_unavailable', 503),
      );
      final unavailable = await unavailableGateway.requestDeletion(
        requestId: _requestId,
        organizationWorkspaceId: _workspace,
      );
      await unavailableGateway.close();
      expect(
        (unavailable as OrganizationDeletionRecoveryRejected).code,
        OrganizationDeletionRecoveryFailureCode.serviceUnavailable,
      );
      final gateway = _gateway(
        (_) async => _json({
          'organization_deletion_recovery_directory_contract_id':
              _directoryContract,
          'items': [
            {..._directoryItem, 'observed_at_utc': '2030-01-02T04:04:05.123Z'},
          ],
        }),
      );
      final result = await gateway.listRecoverableOrganizations();
      await gateway.close();
      expect(
        (result as OrganizationDeletionRecoveryRejected).code,
        OrganizationDeletionRecoveryFailureCode.invalidResponse,
      );
    },
  );

  test('refreshes exactly once for a valid unauthenticated envelope', () async {
    var calls = 0;
    final requests = <http.Request>[];
    final gateway = _gateway((request) async {
      requests.add(request);
      return ++calls == 1
          ? _error('unauthenticated', 401)
          : _json(_deletionReceipt);
    });
    final result = await gateway.requestDeletion(
      requestId: _requestId,
      organizationWorkspaceId: _workspace,
    );
    await gateway.close();
    expect(
      result,
      isA<
        OrganizationDeletionRecoverySuccess<OrganizationDeletionRequestReceipt>
      >(),
    );
    expect(calls, 2);
    expect(requests[0].url, requests[1].url);
    expect(requests[0].body, requests[1].body);
  });

  test('preserves directory order and accepts an empty result', () async {
    final second = {
      ..._directoryItem,
      'organization_workspace_id': _otherWorkspace,
      'deletion_request_id': _otherDeletionId,
      'display_name': 'South team',
    };
    final gateway = _gateway(
      (_) async => _json({
        'organization_deletion_recovery_directory_contract_id':
            _directoryContract,
        'items': [second, _directoryItem],
      }),
    );
    final result = await gateway.listRecoverableOrganizations();
    await gateway.close();
    expect(
      (result
              as OrganizationDeletionRecoverySuccess<
                OrganizationDeletionRecoveryDirectory
              >)
          .value
          .items
          .map((item) => item.organizationWorkspaceId),
      [_otherWorkspace, _workspace],
    );

    final emptyGateway = _gateway(
      (_) async => _json({
        'organization_deletion_recovery_directory_contract_id':
            _directoryContract,
        'items': <Object>[],
      }),
    );
    final empty = await emptyGateway.listRecoverableOrganizations();
    await emptyGateway.close();
    expect(
      (empty
              as OrganizationDeletionRecoverySuccess<
                OrganizationDeletionRecoveryDirectory
              >)
          .value
          .items,
      isEmpty,
    );
  });

  test('rejects a deletion receipt for a different request selector', () async {
    final gateway = _gateway(
      (_) async =>
          _json({..._deletionReceipt, 'deletion_request_id': _deletionId}),
    );
    final result = await gateway.requestDeletion(
      requestId: _requestId,
      organizationWorkspaceId: _workspace,
    );
    await gateway.close();
    expect(
      (result as OrganizationDeletionRecoveryRejected).code,
      OrganizationDeletionRecoveryFailureCode.invalidResponse,
    );
  });

  test(
    'identity change while the request is in flight discards its result',
    () async {
      final identity = _ChangingIdentitySession();
      final sent = Completer<void>();
      final response = Completer<http.Response>();
      final gateway = _gateway((_) {
        sent.complete();
        return response.future;
      }, identity: identity);
      addTearDown(gateway.close);
      addTearDown(identity.close);

      final pending = gateway.requestDeletion(
        requestId: _requestId,
        organizationWorkspaceId: _workspace,
      );
      await sent.future;
      identity.changeToAnotherAccount();
      response.complete(_json(_deletionReceipt));

      expect(
        (await pending as OrganizationDeletionRecoveryRejected).code,
        OrganizationDeletionRecoveryFailureCode.unauthorized,
      );
    },
  );

  test(
    'sign-out and same-account sign-in ABA invalidates an in-flight request',
    () async {
      final identity = _ChangingIdentitySession();
      final sent = Completer<void>();
      final response = Completer<http.Response>();
      final gateway = _gateway((_) {
        sent.complete();
        return response.future;
      }, identity: identity);
      addTearDown(gateway.close);
      addTearDown(identity.close);

      final pending = gateway.requestDeletion(
        requestId: _requestId,
        organizationWorkspaceId: _workspace,
      );
      await sent.future;
      identity.signOutAndSignBackIntoSameAccount();
      response.complete(_json(_deletionReceipt));

      expect(
        (await pending as OrganizationDeletionRecoveryRejected).code,
        OrganizationDeletionRecoveryFailureCode.unauthorized,
      );
    },
  );

  test('late response after close is discarded', () async {
    final identity = _ChangingIdentitySession();
    final sent = Completer<void>();
    final response = Completer<http.Response>();
    final gateway = _gateway((_) {
      sent.complete();
      return response.future;
    }, identity: identity);
    addTearDown(identity.close);

    final pending = gateway.requestDeletion(
      requestId: _requestId,
      organizationWorkspaceId: _workspace,
    );
    await sent.future;
    await gateway.close();
    response.complete(_json(_deletionReceipt));

    expect(
      (await pending as OrganizationDeletionRecoveryRejected).code,
      OrganizationDeletionRecoveryFailureCode.unauthorized,
    );
  });
}

const _directoryContract = 'organization-deletion-recovery-directory:v1';
const _workspace = 'abcdefab-cdef-0abc-0def-abcdefabcdef';
const _otherWorkspace = 'abcdefab-cdef-0abc-0def-abcdefabcdea';
const _deletionId = 'abcdefab-cdef-0abc-0def-abcdefabcdee';
const _otherDeletionId = 'abcdefab-cdef-0abc-0def-abcdefabcdcc';
const _requestId = 'abcdefab-cdef-0abc-0def-abcdefabcded';
const _directoryItem = {
  'organization_workspace_id': _workspace,
  'deletion_request_id': _deletionId,
  'display_name': 'North team',
  'observed_at_utc': '2030-01-02T04:04:05.123456Z',
  'effective_at_utc': '2030-01-02T04:04:05.000000Z',
  'purge_after_utc': '2030-02-01T04:04:05.000000Z',
  'status': 'deletion_pending',
};
const _deletionReceipt = {
  'organization_deletion_contract_id': 'organization-deletion-request:v1',
  'organization_workspace_id': _workspace,
  'deletion_request_id': _requestId,
  'effective_at_utc': '2030-01-02T04:04:05.123456Z',
  'purge_after_utc': '2030-02-01T04:04:05.123456Z',
};
const _restorationReceipt = {
  'organization_deletion_restore_contract_id':
      'organization-deletion-restore:v1',
  'organization_workspace_id': _workspace,
  'deletion_request_id': _deletionId,
  'restored_at_utc': '2030-01-03T04:04:05.123456Z',
};

HttpOrganizationDeletionRecoveryGateway _gateway(
  Future<http.Response> Function(http.Request) handler, {
  IdentitySession? identity,
}) => HttpOrganizationDeletionRecoveryGateway(
  baseUri: Uri.parse('https://backend.example.test'),
  identitySession:
      identity ??
      FakeIdentitySession(
        initial: const IdentitySnapshot(
          stage: IdentityStage.signedIn,
          principal: IdentityPrincipal(
            externalSubject: 'subject-1',
            email: null,
          ),
        ),
      ),
  client: MockClient(handler),
);

final class _ChangingIdentitySession implements IdentitySession {
  _ChangingIdentitySession()
    : _current = const IdentitySnapshot(
        stage: IdentityStage.signedIn,
        principal: IdentityPrincipal(externalSubject: 'subject-1', email: null),
      );

  final _changes = StreamController<IdentitySnapshot>.broadcast(sync: true);
  IdentitySnapshot _current;

  @override
  IdentitySnapshot get current => _current;

  @override
  Stream<IdentitySnapshot> get changes => _changes.stream;

  void changeToAnotherAccount() {
    _emit(
      const IdentitySnapshot(
        stage: IdentityStage.signedIn,
        principal: IdentityPrincipal(externalSubject: 'subject-2', email: null),
      ),
    );
  }

  void signOutAndSignBackIntoSameAccount() {
    _emit(const IdentitySnapshot.signedOut());
    _emit(
      const IdentitySnapshot(
        stage: IdentityStage.signedIn,
        principal: IdentityPrincipal(externalSubject: 'subject-1', email: null),
      ),
    );
  }

  void _emit(IdentitySnapshot snapshot) {
    _current = snapshot;
    _changes.add(snapshot);
  }

  @override
  Future<IdentityResult<IdentityAccessToken>> accessToken({
    bool forceRefresh = false,
  }) async => IdentitySuccess(
    IdentityAccessToken(value: 'test-token', expiresAt: DateTime.utc(2030)),
  );

  @override
  Future<void> close() => _changes.close();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('unused identity method');
}

http.Response _json(Object body, {int status = 200}) => http.Response(
  jsonEncode(body),
  status,
  headers: const {
    'content-type': 'application/json; charset=utf-8',
    'cache-control': 'no-store',
  },
);

http.Response _error(String code, int status) => _json({
  'error': {'code': code},
}, status: status);
