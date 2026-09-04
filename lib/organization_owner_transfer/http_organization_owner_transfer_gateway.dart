import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../foundation/backend_base_uri.dart';
import '../identity/identity_session.dart';
import 'organization_owner_transfer.dart';

const _backendBaseUrl = String.fromEnvironment('BACKEND_BASE_URL');
const _pathPrefix = '/v1/organizations/';
const _pathSuffix = '/owner-transfer';
const _contractId = 'organization-owner-transfer:v1';

OrganizationOwnerTransferGateway productionOrganizationOwnerTransferGateway(
  IdentitySession identitySession,
) {
  final configured = _backendBaseUrl.trim();
  if (configured.isEmpty) {
    return const DeferredOrganizationOwnerTransferGateway();
  }

  // Validate before constructing the client. A bad build-time configuration
  // must fail synchronously without allocating an HTTP resource.
  final baseUri = validatePathlessBackendBaseUri(Uri.parse(configured));
  return HttpOrganizationOwnerTransferGateway(
    baseUri: baseUri,
    identitySession: identitySession,
    client: http.Client(),
  );
}

/// Typed transport for the fixed organization owner-transfer route.
final class HttpOrganizationOwnerTransferGateway
    implements OrganizationOwnerTransferGateway {
  factory HttpOrganizationOwnerTransferGateway({
    required Uri baseUri,
    required IdentitySession identitySession,
    required http.Client client,
    Duration timeout = const Duration(seconds: 15),
  }) => HttpOrganizationOwnerTransferGateway._(
    baseUri: validatePathlessBackendBaseUri(baseUri),
    identitySession: identitySession,
    client: client,
    timeout: timeout,
  );

  HttpOrganizationOwnerTransferGateway._({
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
  Future<OrganizationOwnerTransferResult> transfer({
    required String requestId,
    required String organizationWorkspaceId,
    required String targetOrganizationMembershipId,
  }) {
    final request = _canonicalInputUuid(requestId);
    final workspace = _canonicalInputUuid(organizationWorkspaceId);
    final target = _canonicalInputUuid(targetOrganizationMembershipId);
    if (request == null || workspace == null || target == null) {
      return Future.value(
        const OrganizationOwnerTransferRejected(
          OrganizationOwnerTransferFailureCode.invalidRequest,
        ),
      );
    }

    final body = jsonEncode({
      'request_id': request,
      'target_organization_membership_id': target,
    });
    return _request(requestBody: body, organizationWorkspaceId: workspace);
  }

  Future<OrganizationOwnerTransferResult> _request({
    required String requestBody,
    required String organizationWorkspaceId,
  }) async {
    try {
      var access = await identitySession.accessToken();
      if (access is! IdentitySuccess<IdentityAccessToken>) {
        return OrganizationOwnerTransferRejected(_identityFailure(access));
      }

      var response = await _send(
        access.value,
        organizationWorkspaceId: organizationWorkspaceId,
        requestBody: requestBody,
      );
      var root = _jsonObject(response);

      if (response.statusCode == 401) {
        final firstFailure = _failure(response.statusCode, root);
        if (firstFailure != OrganizationOwnerTransferFailureCode.unauthorized) {
          return const OrganizationOwnerTransferRejected(
            OrganizationOwnerTransferFailureCode.invalidResponse,
          );
        }

        access = await identitySession.accessToken(forceRefresh: true);
        if (access is! IdentitySuccess<IdentityAccessToken>) {
          return OrganizationOwnerTransferRejected(_identityFailure(access));
        }
        response = await _send(
          access.value,
          organizationWorkspaceId: organizationWorkspaceId,
          requestBody: requestBody,
        );
        root = _jsonObject(response);
      }

      if (response.statusCode == 200) {
        return OrganizationOwnerTransferSuccess(
          _parseReceipt(root, organizationWorkspaceId),
        );
      }
      return OrganizationOwnerTransferRejected(
        _failure(response.statusCode, root),
      );
    } on TimeoutException {
      return const OrganizationOwnerTransferRejected(
        OrganizationOwnerTransferFailureCode.networkUnavailable,
      );
    } on http.ClientException {
      return const OrganizationOwnerTransferRejected(
        OrganizationOwnerTransferFailureCode.networkUnavailable,
      );
    } on FormatException {
      return const OrganizationOwnerTransferRejected(
        OrganizationOwnerTransferFailureCode.invalidResponse,
      );
    } on Object {
      // Do not expose provider, HTTP client, identity, or database details.
      return const OrganizationOwnerTransferRejected(
        OrganizationOwnerTransferFailureCode.invalidResponse,
      );
    }
  }

  Future<http.Response> _send(
    IdentityAccessToken token, {
    required String organizationWorkspaceId,
    required String requestBody,
  }) => client
      .post(
        baseUri.resolve('$_pathPrefix$organizationWorkspaceId$_pathSuffix'),
        headers: {
          'accept': 'application/json',
          'authorization': 'Bearer ${token.value}',
          'content-type': 'application/json; charset=utf-8',
        },
        body: requestBody,
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

OrganizationOwnerTransferReceipt _parseReceipt(
  Map<String, Object?> root,
  String expectedWorkspaceId,
) {
  _requireExactKeys(root, const [
    'owner_transfer_contract_id',
    'organization_workspace_id',
    'previous_owner_assignment_id',
    'organization_owner_assignment_id',
    'effective_at_utc',
  ]);
  if (root['owner_transfer_contract_id'] != _contractId) {
    throw const FormatException('invalid organization owner transfer contract');
  }

  final workspaceId = _canonicalResponseUuid(root['organization_workspace_id']);
  if (workspaceId != expectedWorkspaceId) {
    throw const FormatException(
      'organization owner transfer workspace mismatch',
    );
  }

  return OrganizationOwnerTransferReceipt(
    ownerTransferContractId: _contractId,
    organizationWorkspaceId: workspaceId,
    previousOwnerAssignmentId: _canonicalResponseUuid(
      root['previous_owner_assignment_id'],
    ),
    organizationOwnerAssignmentId: _canonicalResponseUuid(
      root['organization_owner_assignment_id'],
    ),
    effectiveAtUtc: _canonicalUtcTimestamp(root['effective_at_utc']),
  );
}

OrganizationOwnerTransferFailureCode _failure(
  int status,
  Map<String, Object?> root,
) {
  _requireExactKeys(root, const ['error']);
  final error = _object(root['error']);
  _requireExactKeys(error, const ['code']);
  final code = error['code'];
  if (code is! String || code.isEmpty || code.trim() != code) {
    throw const FormatException('invalid organization owner transfer error');
  }

  return switch ((status, code)) {
    (400, 'invalid_json') => OrganizationOwnerTransferFailureCode.invalidJson,
    (400, 'invalid_organization_owner_transfer_request') =>
      OrganizationOwnerTransferFailureCode.invalidRequest,
    (401, 'unauthenticated') =>
      OrganizationOwnerTransferFailureCode.unauthorized,
    (403, 'organization_owner_transfer_forbidden') =>
      OrganizationOwnerTransferFailureCode.forbidden,
    (409, 'organization_owner_transfer_conflict') =>
      OrganizationOwnerTransferFailureCode.conflict,
    (409, 'organization_owner_transfer_target_already_owner') =>
      OrganizationOwnerTransferFailureCode.targetAlreadyOwner,
    (413, 'payload_too_large') =>
      OrganizationOwnerTransferFailureCode.payloadTooLarge,
    (503, 'organization_owner_transfer_unavailable') =>
      OrganizationOwnerTransferFailureCode.serviceUnavailable,
    _ => OrganizationOwnerTransferFailureCode.invalidResponse,
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
      'invalid organization owner transfer response headers',
    );
  }
}

String _requiredHeader(http.Response response, String name) {
  for (final entry in response.headers.entries) {
    if (entry.key.toLowerCase() == name) {
      return entry.value;
    }
  }
  throw const FormatException(
    'missing organization owner transfer response header',
  );
}

Map<String, Object?> _object(Object? value) {
  if (value is! Map) {
    throw const FormatException(
      'expected organization owner transfer JSON object',
    );
  }
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    if (entry.key is! String) {
      throw const FormatException(
        'invalid organization owner transfer JSON key',
      );
    }
    result[entry.key as String] = entry.value;
  }
  return result;
}

void _requireExactKeys(Map<String, Object?> value, List<String> expected) {
  final expectedSet = expected.toSet();
  if (value.length != expectedSet.length ||
      !value.keys.every(expectedSet.contains)) {
    throw const FormatException(
      'invalid organization owner transfer JSON fields',
    );
  }
}

String? _canonicalInputUuid(String value) {
  if (!_uuidPattern.hasMatch(value)) {
    return null;
  }
  return value.toLowerCase();
}

String _canonicalResponseUuid(Object? value) {
  if (value is! String ||
      !_uuidPattern.hasMatch(value) ||
      value.toLowerCase() != value) {
    throw const FormatException('invalid organization owner transfer UUID');
  }
  return value;
}

DateTime _canonicalUtcTimestamp(Object? value) {
  if (value is! String || !_canonicalUtcPattern.hasMatch(value)) {
    throw const FormatException(
      'invalid organization owner transfer timestamp',
    );
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null || !parsed.isUtc || parsed.toIso8601String() != value) {
    throw const FormatException(
      'invalid organization owner transfer timestamp',
    );
  }
  return parsed;
}

OrganizationOwnerTransferFailureCode _identityFailure(
  IdentityResult<IdentityAccessToken> result,
) => switch (result) {
  IdentityRejected<IdentityAccessToken>(:final failure) =>
    switch (failure.code) {
      IdentityFailureCode.notConfigured =>
        OrganizationOwnerTransferFailureCode.notConfigured,
      IdentityFailureCode.networkUnavailable =>
        OrganizationOwnerTransferFailureCode.networkUnavailable,
      _ => OrganizationOwnerTransferFailureCode.unauthorized,
    },
  IdentitySuccess<IdentityAccessToken>() =>
    OrganizationOwnerTransferFailureCode.unauthorized,
};

final _uuidPattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  caseSensitive: false,
);
final _canonicalUtcPattern = RegExp(
  r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$',
);
