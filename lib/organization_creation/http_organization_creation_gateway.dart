import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../foundation/backend_base_uri.dart';
import '../identity/identity_session.dart';
import 'organization_creation.dart';

const _backendBaseUrl = String.fromEnvironment('BACKEND_BASE_URL');
const _path = '/v1/organizations';
const _creationContractId = 'organization-creation:v1';

OrganizationCreationGateway productionOrganizationCreationGateway(
  IdentitySession identitySession,
) {
  final configured = _backendBaseUrl.trim();
  if (configured.isEmpty) {
    return const DeferredOrganizationCreationGateway();
  }
  return HttpOrganizationCreationGateway(
    baseUri: Uri.parse(configured),
    identitySession: identitySession,
    client: http.Client(),
  );
}

/// Typed transport for the organization creation endpoint.
///
/// The server derives the actor from the bearer token. This adapter sends only
/// the caller-provided request UUID and display name, and keeps the receipt in
/// memory for the duration of the call.
final class HttpOrganizationCreationGateway
    implements OrganizationCreationGateway {
  factory HttpOrganizationCreationGateway({
    required Uri baseUri,
    required IdentitySession identitySession,
    required http.Client client,
    Duration timeout = const Duration(seconds: 15),
  }) => HttpOrganizationCreationGateway._(
    baseUri: validatePathlessBackendBaseUri(baseUri),
    identitySession: identitySession,
    client: client,
    timeout: timeout,
  );

  const HttpOrganizationCreationGateway._({
    required this.baseUri,
    required this.identitySession,
    required this.client,
    required this.timeout,
  });

  final Uri baseUri;
  final IdentitySession identitySession;
  final http.Client client;
  final Duration timeout;

  @override
  Future<OrganizationCreationResult> create({
    required String requestId,
    required String displayName,
  }) {
    if (!_isCanonicalUuid(requestId)) {
      return Future.value(
        const OrganizationCreationRejected(
          OrganizationCreationFailureCode.invalidRequest,
        ),
      );
    }

    final body = jsonEncode({
      'request_id': requestId,
      'display_name': displayName,
    });
    return _request(body);
  }

  Future<OrganizationCreationResult> _request(String body) async {
    try {
      var access = await identitySession.accessToken();
      if (access is! IdentitySuccess<IdentityAccessToken>) {
        return OrganizationCreationRejected(_identityFailure(access));
      }

      var response = await _send(access.value, body);
      var root = _jsonObject(response);
      if (response.statusCode == 401) {
        if (_failure(response.statusCode, root) !=
            OrganizationCreationFailureCode.unauthorized) {
          return const OrganizationCreationRejected(
            OrganizationCreationFailureCode.invalidResponse,
          );
        }
        access = await identitySession.accessToken(forceRefresh: true);
        if (access is! IdentitySuccess<IdentityAccessToken>) {
          return OrganizationCreationRejected(_identityFailure(access));
        }
        response = await _send(access.value, body);
        root = _jsonObject(response);
      }

      if (response.statusCode == 200) {
        return OrganizationCreationSuccess(_parseReceipt(root));
      }
      return OrganizationCreationRejected(_failure(response.statusCode, root));
    } on TimeoutException {
      return const OrganizationCreationRejected(
        OrganizationCreationFailureCode.networkUnavailable,
      );
    } on http.ClientException {
      return const OrganizationCreationRejected(
        OrganizationCreationFailureCode.networkUnavailable,
      );
    } on FormatException {
      return const OrganizationCreationRejected(
        OrganizationCreationFailureCode.invalidResponse,
      );
    } on Object {
      // Never expose provider, HTTP client, JSON, or database details.
      return const OrganizationCreationRejected(
        OrganizationCreationFailureCode.invalidResponse,
      );
    }
  }

  Future<http.Response> _send(IdentityAccessToken token, String body) => client
      .post(
        baseUri.resolve(_path),
        headers: {
          'accept': 'application/json',
          'authorization': 'Bearer ${token.value}',
          'content-type': 'application/json; charset=utf-8',
        },
        body: body,
      )
      .timeout(timeout);

  @override
  Future<void> close() async => client.close();
}

OrganizationCreationReceipt _parseReceipt(Map<String, Object?> root) {
  _requireExactKeys(root, const [
    'creation_contract_id',
    'organization_workspace_id',
    'organization_membership_id',
    'organization_owner_assignment_id',
    'created_at_utc',
  ]);
  if (root['creation_contract_id'] != _creationContractId) {
    throw const FormatException('invalid organization creation contract');
  }
  return OrganizationCreationReceipt(
    creationContractId: _creationContractId,
    organizationWorkspaceId: _canonicalUuid(root['organization_workspace_id']),
    organizationMembershipId: _canonicalUuid(
      root['organization_membership_id'],
    ),
    organizationOwnerAssignmentId: _canonicalUuid(
      root['organization_owner_assignment_id'],
    ),
    createdAtUtc: _canonicalUtcTimestamp(root['created_at_utc']),
  );
}

OrganizationCreationFailureCode _failure(
  int status,
  Map<String, Object?> root,
) {
  _requireExactKeys(root, const ['error']);
  final error = _object(root['error']);
  _requireExactKeys(error, const ['code']);
  final code = error['code'];
  if (code is! String || code.isEmpty || code.trim() != code) {
    throw const FormatException('invalid organization creation error');
  }
  return switch ((status, code)) {
    (400, 'invalid_json') => OrganizationCreationFailureCode.invalidJson,
    (413, 'payload_too_large') =>
      OrganizationCreationFailureCode.payloadTooLarge,
    (400, 'invalid_organization_creation_request') =>
      OrganizationCreationFailureCode.invalidRequest,
    (401, 'unauthenticated') => OrganizationCreationFailureCode.unauthorized,
    (403, 'organization_creation_forbidden') =>
      OrganizationCreationFailureCode.forbidden,
    (409, 'organization_creation_conflict') =>
      OrganizationCreationFailureCode.conflict,
    (503, 'organization_creation_unavailable') =>
      OrganizationCreationFailureCode.serviceUnavailable,
    _ => OrganizationCreationFailureCode.invalidResponse,
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
    throw const FormatException(
      'invalid organization creation response headers',
    );
  }
}

String _requiredHeader(http.Response response, String name) {
  for (final entry in response.headers.entries) {
    if (entry.key.toLowerCase() == name) return entry.value;
  }
  throw const FormatException('missing organization creation response header');
}

Map<String, Object?> _object(Object? value) {
  if (value is! Map) {
    throw const FormatException('expected organization creation JSON object');
  }
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    if (entry.key is! String) {
      throw const FormatException('invalid organization creation JSON key');
    }
    result[entry.key as String] = entry.value;
  }
  return result;
}

void _requireExactKeys(Map<String, Object?> value, List<String> expected) {
  final expectedSet = expected.toSet();
  if (value.length != expectedSet.length ||
      !value.keys.every(expectedSet.contains)) {
    throw const FormatException('invalid organization creation JSON fields');
  }
}

String _canonicalUuid(Object? value) {
  if (value is! String || !_isCanonicalUuid(value)) {
    throw const FormatException('invalid organization creation UUID');
  }
  return value;
}

bool _isCanonicalUuid(String value) =>
    _uuidPattern.hasMatch(value) && value.toLowerCase() == value;

DateTime _canonicalUtcTimestamp(Object? value) {
  if (value is! String || !_canonicalUtcPattern.hasMatch(value)) {
    throw const FormatException('invalid organization creation timestamp');
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null || !parsed.isUtc || parsed.toIso8601String() != value) {
    throw const FormatException('invalid organization creation timestamp');
  }
  return parsed;
}

OrganizationCreationFailureCode _identityFailure(
  IdentityResult<IdentityAccessToken> result,
) => switch (result) {
  IdentityRejected<IdentityAccessToken>(:final failure) =>
    switch (failure.code) {
      IdentityFailureCode.notConfigured =>
        OrganizationCreationFailureCode.notConfigured,
      IdentityFailureCode.networkUnavailable =>
        OrganizationCreationFailureCode.networkUnavailable,
      _ => OrganizationCreationFailureCode.unauthorized,
    },
  IdentitySuccess<IdentityAccessToken>() =>
    OrganizationCreationFailureCode.unauthorized,
};

final _uuidPattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);
final _canonicalUtcPattern = RegExp(
  r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$',
);
