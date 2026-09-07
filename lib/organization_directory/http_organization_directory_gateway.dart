import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../foundation/backend_base_uri.dart';
import '../identity/identity_session.dart';
import 'organization_directory.dart';

const _backendBaseUrl = String.fromEnvironment('BACKEND_BASE_URL');
const _path = '/v1/organizations';
const _contractId = 'organization-directory:v1';

/// 使用既有 Backend 配置创建组织目录网关；空配置不分配 HTTP client。
OrganizationDirectoryGateway productionOrganizationDirectoryGateway(
  IdentitySession identitySession,
) {
  final configured = _backendBaseUrl.trim();
  if (configured.isEmpty) {
    return const DeferredOrganizationDirectoryGateway();
  }

  final baseUri = validatePathlessBackendBaseUri(Uri.parse(configured));
  return HttpOrganizationDirectoryGateway(
    baseUri: baseUri,
    identitySession: identitySession,
    client: http.Client(),
  );
}

/// 通过当前 identity 读取组织目录的类型化 HTTP 网关。
///
/// 实例拥有 [client]，但不拥有或关闭 [identitySession]。返回值只保留
/// Backend 提供的组织 UUID 与原名称，不保存原始 JSON。
final class HttpOrganizationDirectoryGateway
    implements OrganizationDirectoryGateway {
  factory HttpOrganizationDirectoryGateway({
    required Uri baseUri,
    required IdentitySession identitySession,
    required http.Client client,
    Duration timeout = const Duration(seconds: 15),
  }) => HttpOrganizationDirectoryGateway._(
    baseUri: validatePathlessBackendBaseUri(baseUri),
    identitySession: identitySession,
    client: client,
    timeout: timeout,
  );

  HttpOrganizationDirectoryGateway._({
    required this.baseUri,
    required this.identitySession,
    required this.client,
    required this.timeout,
  });

  final Uri baseUri;
  final IdentitySession identitySession;
  final http.Client client;
  final Duration timeout;
  bool _closed = false;

  @override
  Future<OrganizationDirectoryResult> list() async {
    try {
      var access = await identitySession.accessToken();
      if (access is! IdentitySuccess<IdentityAccessToken>) {
        return OrganizationDirectoryRejected(_identityFailure(access));
      }

      var response = await _send(access.value);
      var root = _jsonObject(response);
      if (response.statusCode == 401) {
        if (_failure(response.statusCode, root) !=
            OrganizationDirectoryFailureCode.unauthorized) {
          return const OrganizationDirectoryRejected(
            OrganizationDirectoryFailureCode.invalidResponse,
          );
        }

        access = await identitySession.accessToken(forceRefresh: true);
        if (access is! IdentitySuccess<IdentityAccessToken>) {
          return OrganizationDirectoryRejected(_identityFailure(access));
        }
        response = await _send(access.value);
        root = _jsonObject(response);
      }

      return response.statusCode == 200
          ? OrganizationDirectorySuccess(_parseDirectory(root))
          : OrganizationDirectoryRejected(_failure(response.statusCode, root));
    } on TimeoutException {
      return const OrganizationDirectoryRejected(
        OrganizationDirectoryFailureCode.networkUnavailable,
      );
    } on http.ClientException {
      return const OrganizationDirectoryRejected(
        OrganizationDirectoryFailureCode.networkUnavailable,
      );
    } on FormatException {
      return const OrganizationDirectoryRejected(
        OrganizationDirectoryFailureCode.invalidResponse,
      );
    } on Object {
      return const OrganizationDirectoryRejected(
        OrganizationDirectoryFailureCode.invalidResponse,
      );
    }
  }

  Future<http.Response> _send(IdentityAccessToken token) => client
      .get(
        baseUri.resolve(_path),
        headers: {
          'accept': 'application/json',
          'authorization': 'Bearer ${token.value}',
        },
      )
      .timeout(timeout);

  @override
  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    client.close();
  }
}

List<OrganizationDirectoryEntry> _parseDirectory(Map<String, Object?> root) {
  _requireExactKeys(root, const [
    'organization_directory_contract_id',
    'organizations',
  ]);
  if (root['organization_directory_contract_id'] != _contractId) {
    throw const FormatException('invalid organization directory contract');
  }

  final rawOrganizations = root['organizations'];
  if (rawOrganizations is! List) {
    throw const FormatException('invalid organization directory list');
  }

  final seenWorkspaceIds = <String>{};
  final organizations = <OrganizationDirectoryEntry>[];
  for (final rawOrganization in rawOrganizations) {
    final organization = _object(rawOrganization);
    _requireExactKeys(organization, const [
      'organization_workspace_id',
      'organization_name',
    ]);
    final workspaceId = _canonicalResponseUuid(
      organization['organization_workspace_id'],
    );
    if (!seenWorkspaceIds.add(workspaceId)) {
      throw const FormatException('duplicate organization workspace UUID');
    }
    organizations.add(
      OrganizationDirectoryEntry(
        organizationWorkspaceId: workspaceId,
        organizationName: _organizationName(organization['organization_name']),
      ),
    );
  }
  return organizations;
}

OrganizationDirectoryFailureCode _failure(
  int status,
  Map<String, Object?> root,
) {
  _requireExactKeys(root, const ['error']);
  final error = _object(root['error']);
  _requireExactKeys(error, const ['code']);
  final code = error['code'];
  if (code is! String || code.isEmpty || code.trim() != code) {
    throw const FormatException('invalid organization directory error');
  }

  return switch ((status, code)) {
    (400, 'invalid_organization_directory_request') =>
      OrganizationDirectoryFailureCode.invalidRequest,
    (401, 'unauthenticated') => OrganizationDirectoryFailureCode.unauthorized,
    (403, 'organization_directory_forbidden') =>
      OrganizationDirectoryFailureCode.forbidden,
    (503, 'organization_directory_unavailable') =>
      OrganizationDirectoryFailureCode.serviceUnavailable,
    _ => OrganizationDirectoryFailureCode.invalidResponse,
  };
}

Map<String, Object?> _jsonObject(http.Response response) {
  _requireJsonNoStore(response);
  return _object(jsonDecode(response.body));
}

void _requireJsonNoStore(http.Response response) {
  final contentType = _requiredHeader(
    response,
    'content-type',
  ).split(';').map((part) => part.trim().toLowerCase()).toList(growable: false);
  final cacheControl = _requiredHeader(response, 'cache-control').trim();
  if (contentType.length != 2 ||
      contentType[0] != 'application/json' ||
      contentType[1] != 'charset=utf-8' ||
      cacheControl != 'no-store') {
    throw const FormatException('invalid organization directory headers');
  }
}

String _requiredHeader(http.Response response, String name) {
  for (final entry in response.headers.entries) {
    if (entry.key.toLowerCase() == name) {
      return entry.value;
    }
  }
  throw const FormatException('missing organization directory header');
}

Map<String, Object?> _object(Object? value) {
  if (value is! Map) {
    throw const FormatException('expected organization directory JSON object');
  }
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    if (entry.key is! String) {
      throw const FormatException('invalid organization directory JSON key');
    }
    result[entry.key as String] = entry.value;
  }
  return result;
}

void _requireExactKeys(Map<String, Object?> value, List<String> expected) {
  final expectedSet = expected.toSet();
  if (value.length != expectedSet.length ||
      !value.keys.every(expectedSet.contains)) {
    throw const FormatException('invalid organization directory JSON fields');
  }
}

String _canonicalResponseUuid(Object? value) {
  if (value is! String ||
      !_uuidPattern.hasMatch(value) ||
      value.toLowerCase() != value) {
    throw const FormatException('invalid organization directory UUID');
  }
  return value;
}

String _organizationName(Object? value) {
  if (value is! String ||
      !value.codeUnits.any((codeUnit) => codeUnit != 0x20)) {
    throw const FormatException('invalid organization directory name');
  }
  return value;
}

OrganizationDirectoryFailureCode _identityFailure(
  IdentityResult<IdentityAccessToken> result,
) => switch (result) {
  IdentityRejected<IdentityAccessToken>(:final failure) =>
    switch (failure.code) {
      IdentityFailureCode.notConfigured =>
        OrganizationDirectoryFailureCode.notConfigured,
      IdentityFailureCode.networkUnavailable =>
        OrganizationDirectoryFailureCode.networkUnavailable,
      _ => OrganizationDirectoryFailureCode.unauthorized,
    },
  IdentitySuccess<IdentityAccessToken>() =>
    OrganizationDirectoryFailureCode.unauthorized,
};

final _uuidPattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  caseSensitive: false,
);
