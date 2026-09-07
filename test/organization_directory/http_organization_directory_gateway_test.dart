import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tongxingzhe_app/foundation/backend_base_uri.dart';
import 'package:tongxingzhe_app/identity/identity_session.dart';
import 'package:tongxingzhe_app/organization_directory/http_organization_directory_gateway.dart';
import 'package:tongxingzhe_app/organization_directory/organization_directory.dart';

import '../support/fake_identity_session.dart';

void main() {
  test('GET 只发送身份 headers 并保留目录顺序与原名称', () async {
    late http.Request request;
    final gateway = _gateway((value) async {
      request = value;
      return _json(_directoryJson());
    });
    addTearDown(gateway.close);

    final result = await gateway.list();

    expect(request.method, 'GET');
    expect(
      request.url,
      Uri.parse('https://backend.example.test/v1/organizations'),
    );
    expect(request.url.query, isEmpty);
    expect(request.url.fragment, isEmpty);
    expect(request.bodyBytes, isEmpty);
    expect(request.headers, {
      'accept': 'application/json',
      'authorization': 'Bearer test-only-access-token',
    });
    expect(result, isA<OrganizationDirectorySuccess>());
    final organizations =
        (result as OrganizationDirectorySuccess).organizations;
    expect(
      organizations
          .map(
            (entry) => (entry.organizationWorkspaceId, entry.organizationName),
          )
          .toList(),
      [(_workspaceId, ' Same name '), (_otherWorkspaceId, ' Same name ')],
    );
  });

  test('success 复制列表并禁止修改', () {
    const entry = OrganizationDirectoryEntry(
      organizationWorkspaceId: _workspaceId,
      organizationName: 'Organization',
    );
    final source = <OrganizationDirectoryEntry>[entry];
    final result = OrganizationDirectorySuccess(source);

    source.clear();

    expect(result.organizations, [entry]);
    expect(() => result.organizations.add(entry), throwsUnsupportedError);
  });

  test('deferred 不访问网络且可重复 close', () async {
    const gateway = DeferredOrganizationDirectoryGateway();

    final result = await gateway.list();
    await gateway.close();
    await gateway.close();

    expect(
      _failureCode(result),
      OrganizationDirectoryFailureCode.notConfigured,
    );
  });

  test('production factory 校验配置且不关闭 identity', () async {
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
      final gateway = productionOrganizationDirectoryGateway(identity);
      expect(
        gateway,
        validConfiguredUri
            ? isA<HttpOrganizationDirectoryGateway>()
            : isA<DeferredOrganizationDirectoryGateway>(),
      );
      await gateway.close();
    } else {
      expect(
        () => productionOrganizationDirectoryGateway(identity),
        anyOf(throwsArgumentError, throwsFormatException),
      );
    }
    expect(identity.accessTokenForceRefreshValues, isEmpty);
    expect(identity.isClosed, isFalse);
  });

  test('HTTP gateway 在分配的 client 之前同步拒绝非 pathless URI', () {
    final identity = _identity();
    final client = _TrackingMockClient((_) async => _json(_directoryJson()));

    for (final uri in [
      Uri.parse('https://backend.example.test/path'),
      Uri.parse('http://backend.example.test'),
    ]) {
      expect(
        () => HttpOrganizationDirectoryGateway(
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

  test('identity 失败转换为稳定结果且不发请求', () async {
    const cases = [
      (
        IdentityFailureCode.notConfigured,
        OrganizationDirectoryFailureCode.notConfigured,
      ),
      (
        IdentityFailureCode.networkUnavailable,
        OrganizationDirectoryFailureCode.networkUnavailable,
      ),
      (
        IdentityFailureCode.sessionMissing,
        OrganizationDirectoryFailureCode.unauthorized,
      ),
      (
        IdentityFailureCode.providerRejected,
        OrganizationDirectoryFailureCode.unauthorized,
      ),
      (
        IdentityFailureCode.unknown,
        OrganizationDirectoryFailureCode.unauthorized,
      ),
    ];

    for (final testCase in cases) {
      final identity = _identity();
      identity.rejectNextAccessTokenWith = IdentityFailure(code: testCase.$1);
      var requests = 0;
      final gateway = _gateway((_) async {
        requests++;
        return _json(_directoryJson());
      }, identity: identity);

      final result = await gateway.list();
      await gateway.close();

      expect(_failureCode(result), testCase.$2, reason: '${testCase.$1}');
      expect(requests, 0);
    }
  });

  test('exact 401 只 refresh 一次并使用同一 URL', () async {
    final identity = _RotatingTokenIdentitySession();
    final requests = <http.Request>[];
    final gateway = HttpOrganizationDirectoryGateway(
      baseUri: Uri.parse('https://backend.example.test'),
      identitySession: identity,
      client: MockClient((request) async {
        requests.add(request);
        return requests.length == 1
            ? _error('unauthenticated', 401)
            : _json(_directoryJson());
      }),
    );
    addTearDown(gateway.close);

    final result = await gateway.list();

    expect(result, isA<OrganizationDirectorySuccess>());
    expect(requests, hasLength(2));
    expect(requests[0].method, requests[1].method);
    expect(requests[0].url, requests[1].url);
    expect(requests[0].bodyBytes, isEmpty);
    expect(requests[1].bodyBytes, isEmpty);
    expect(requests.map((request) => request.headers['authorization']), [
      'Bearer stale-test-access-token',
      'Bearer refreshed-test-access-token',
    ]);
    expect(identity.accessTokenForceRefreshValues, [false, true]);
  });

  test('malformed 401 不 refresh', () async {
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

      final result = await gateway.list();
      await gateway.close();

      expect(
        _failureCode(result),
        OrganizationDirectoryFailureCode.invalidResponse,
      );
      expect(requests, 1);
      expect(identity.accessTokenForceRefreshValues, [false]);
    }
  });

  test('refresh 失败停止重试，第二个 401 不形成循环', () async {
    final failedIdentity = _identity();
    var failedRequests = 0;
    final failedGateway = _gateway((_) async {
      failedRequests++;
      failedIdentity.rejectNextAccessTokenWith = const IdentityFailure(
        code: IdentityFailureCode.sessionMissing,
      );
      return _error('unauthenticated', 401);
    }, identity: failedIdentity);

    final failedResult = await failedGateway.list();
    await failedGateway.close();

    expect(
      _failureCode(failedResult),
      OrganizationDirectoryFailureCode.unauthorized,
    );
    expect(failedRequests, 1);
    expect(failedIdentity.accessTokenForceRefreshValues, [false, true]);

    final repeatedIdentity = _identity();
    var repeatedRequests = 0;
    final repeatedGateway = _gateway((_) async {
      repeatedRequests++;
      return _error('unauthenticated', 401);
    }, identity: repeatedIdentity);

    final repeatedResult = await repeatedGateway.list();
    await repeatedGateway.close();

    expect(
      _failureCode(repeatedResult),
      OrganizationDirectoryFailureCode.unauthorized,
    );
    expect(repeatedRequests, 2);
    expect(repeatedIdentity.accessTokenForceRefreshValues, [false, true]);
  });

  test('strict parser 拒绝 root、row、UUID、name 与重复漂移', () async {
    final cases = <String, String>{
      'malformed JSON': '{',
      'non-object root': '[]',
      'extra root field': jsonEncode({..._directoryJson(), 'extra': true}),
      'missing root field': jsonEncode(
        _directoryJson()..remove('organizations'),
      ),
      'bad contract': jsonEncode({
        ..._directoryJson(),
        'organization_directory_contract_id': 'other:v1',
      }),
      'non-list organizations': jsonEncode({
        ..._directoryJson(),
        'organizations': const <String, Object?>{},
      }),
      'non-object row': jsonEncode({
        ..._directoryJson(),
        'organizations': ['row'],
      }),
      'extra row field': jsonEncode(
        _directoryJson(
          rows: [
            {..._entryJson(_workspaceId, 'Name'), 'extra': true},
          ],
        ),
      ),
      'missing row field': jsonEncode(
        _directoryJson(
          rows: [
            {'organization_workspace_id': _workspaceId},
          ],
        ),
      ),
      'bad UUID': jsonEncode(
        _directoryJson(rows: [_entryJson('not-a-uuid', 'Name')]),
      ),
      'uppercase UUID': jsonEncode(
        _directoryJson(rows: [_entryJson(_workspaceId.toUpperCase(), 'Name')]),
      ),
      'non-string name': jsonEncode(
        _directoryJson(
          rows: [
            {'organization_workspace_id': _workspaceId, 'organization_name': 1},
          ],
        ),
      ),
      'empty name': jsonEncode(
        _directoryJson(rows: [_entryJson(_workspaceId, '')]),
      ),
      'ASCII-space name': jsonEncode(
        _directoryJson(rows: [_entryJson(_workspaceId, '   ')]),
      ),
      'duplicate UUID': jsonEncode(
        _directoryJson(
          rows: [
            _entryJson(_workspaceId, 'First'),
            _entryJson(_workspaceId, 'Second'),
          ],
        ),
      ),
    };

    for (final testCase in cases.entries) {
      final gateway = _gateway((_) async => _raw(testCase.value));
      final result = await gateway.list();
      await gateway.close();

      expect(
        _failureCode(result),
        OrganizationDirectoryFailureCode.invalidResponse,
        reason: testCase.key,
      );
    }
  });

  test('parser 保留空目录、任意数量和旧名称', () async {
    final emptyGateway = _gateway(
      (_) async => _json(_directoryJson(rows: const [])),
    );
    final emptyResult = await emptyGateway.list();
    await emptyGateway.close();
    expect(
      (emptyResult as OrganizationDirectorySuccess).organizations,
      isEmpty,
    );

    final rows = List.generate(
      300,
      (index) => _entryJson(_uuidFor(index), '\u00a0Legacy\u200b $index  '),
    );
    final largeGateway = _gateway(
      (_) async => _json(_directoryJson(rows: rows)),
    );
    final largeResult = await largeGateway.list();
    await largeGateway.close();

    final organizations =
        (largeResult as OrganizationDirectorySuccess).organizations;
    expect(organizations, hasLength(300));
    expect(organizations.first.organizationWorkspaceId, _uuidFor(0));
    expect(organizations.last.organizationWorkspaceId, _uuidFor(299));
    expect(organizations.first.organizationName, '\u00a0Legacy\u200b 0  ');
  });

  test('response 必须使用 exact JSON UTF-8 与 no-store headers', () async {
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
        (_) async => _json(_directoryJson(), headers: responseHeaders),
      );
      final result = await gateway.list();
      await gateway.close();

      expect(
        _failureCode(result),
        OrganizationDirectoryFailureCode.invalidResponse,
      );
    }
  });

  test('stable error envelopes 转换为七项共享 failure enum', () async {
    const cases = [
      (
        400,
        'invalid_organization_directory_request',
        OrganizationDirectoryFailureCode.invalidRequest,
      ),
      (401, 'unauthenticated', OrganizationDirectoryFailureCode.unauthorized),
      (
        403,
        'organization_directory_forbidden',
        OrganizationDirectoryFailureCode.forbidden,
      ),
      (
        503,
        'organization_directory_unavailable',
        OrganizationDirectoryFailureCode.serviceUnavailable,
      ),
    ];

    for (final testCase in cases) {
      final gateway = _gateway((_) async => _error(testCase.$2, testCase.$1));
      final result = await gateway.list();
      await gateway.close();

      expect(_failureCode(result), testCase.$3);
    }
  });

  test('unknown status、error 漂移和 adapter 异常均失败关闭', () async {
    final responses = <http.Response Function()>[
      () => _error('not_found', 404),
      () => _error('unknown', 418),
      () => _json({
        'error': {'message': 'database detail'},
      }, status: 503),
      () => _json(_directoryJson(), status: 201),
    ];

    for (final response in responses) {
      final gateway = _gateway((_) async => response());
      final result = await gateway.list();
      await gateway.close();
      expect(
        _failureCode(result),
        OrganizationDirectoryFailureCode.invalidResponse,
      );
    }

    final adapterGateway = _gateway(
      (_) => Future<http.Response>.error(StateError('provider secret')),
    );
    final adapterResult = await adapterGateway.list();
    await adapterGateway.close();
    expect(
      _failureCode(adapterResult),
      OrganizationDirectoryFailureCode.invalidResponse,
    );
  });

  test('network、client 与 timeout 失败不暴露原文', () async {
    final networkGateway = _gateway(
      (_) =>
          Future<http.Response>.error(http.ClientException('database secret')),
    );
    final networkResult = await networkGateway.list();
    await networkGateway.close();
    expect(
      _failureCode(networkResult),
      OrganizationDirectoryFailureCode.networkUnavailable,
    );

    final timeoutGateway = _gateway(
      (_) => Future<http.Response>.delayed(
        const Duration(milliseconds: 50),
        () => _json(_directoryJson()),
      ),
      timeout: const Duration(milliseconds: 1),
    );
    final timeoutResult = await timeoutGateway.list();
    await timeoutGateway.close();
    expect(
      _failureCode(timeoutResult),
      OrganizationDirectoryFailureCode.networkUnavailable,
    );
  });

  test('close 只关闭拥有的 HTTP client 一次', () async {
    final identity = _identity();
    final client = _TrackingMockClient((_) async => _json(_directoryJson()));
    final gateway = _gateway(
      (_) async => _json(_directoryJson()),
      identity: identity,
      client: client,
    );

    await gateway.close();
    await gateway.close();

    expect(client.closeCount, 1);
    expect(identity.isClosed, isFalse);
  });
}

const _contractId = 'organization-directory:v1';
const _workspaceId = 'abcdefab-cdef-0abc-0def-abcdefabcdef';
const _otherWorkspaceId = 'abcdefab-cdef-0abc-0def-abcdefabcdea';

FakeIdentitySession _identity() => FakeIdentitySession(
  initial: const IdentitySnapshot(
    stage: IdentityStage.signedIn,
    principal: IdentityPrincipal(
      externalSubject: 'subject-1',
      email: 'member@example.test',
    ),
  ),
);

HttpOrganizationDirectoryGateway _gateway(
  Future<http.Response> Function(http.Request) handler, {
  FakeIdentitySession? identity,
  http.Client? client,
  Duration timeout = const Duration(seconds: 15),
}) => HttpOrganizationDirectoryGateway(
  baseUri: Uri.parse('https://backend.example.test'),
  identitySession: identity ?? _identity(),
  client: client ?? MockClient(handler),
  timeout: timeout,
);

OrganizationDirectoryFailureCode _failureCode(
  OrganizationDirectoryResult result,
) => switch (result) {
  OrganizationDirectoryRejected(:final code) => code,
  OrganizationDirectorySuccess() => throw StateError('expected rejection'),
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

Map<String, Object?> _directoryJson({List<Object?>? rows}) => {
  'organization_directory_contract_id': _contractId,
  'organizations':
      rows ??
      [
        _entryJson(_workspaceId, ' Same name '),
        _entryJson(_otherWorkspaceId, ' Same name '),
      ],
};

Map<String, Object?> _entryJson(String workspaceId, Object? name) => {
  'organization_workspace_id': workspaceId,
  'organization_name': name,
};

String _uuidFor(int value) =>
    '00000000-0000-0000-0000-${value.toString().padLeft(12, '0')}';

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
