import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../foundation/backend_base_uri.dart';
import '../identity/identity_session.dart';
import 'organization_directed_account_invitation.dart';

const _backendBaseUrl = String.fromEnvironment('BACKEND_BASE_URL');
const _contractId = 'organization-directed-account-invitation:v1';
const _invitationLifetime = Duration(hours: 168);

/// 使用既有 Backend 配置创建网关；空配置不分配 HTTP client。
OrganizationDirectedAccountInvitationGateway
productionOrganizationDirectedAccountInvitationGateway(
  IdentitySession identitySession,
) {
  final configured = _backendBaseUrl.trim();
  if (configured.isEmpty) {
    return const DeferredOrganizationDirectedAccountInvitationGateway();
  }

  final baseUri = validatePathlessBackendBaseUri(Uri.parse(configured));
  return HttpOrganizationDirectedAccountInvitationGateway(
    baseUri: baseUri,
    identitySession: identitySession,
    client: http.Client(),
  );
}

/// 通过已配置的 Backend 创建或接受定向账号邀请。
///
/// 调用方提供不透明 UUID；本类通过 [identitySession] 取得身份凭证。响应只在
/// 内存中解析。实例拥有 [client]，但不拥有也不会关闭 [identitySession]。
final class HttpOrganizationDirectedAccountInvitationGateway
    implements OrganizationDirectedAccountInvitationGateway {
  factory HttpOrganizationDirectedAccountInvitationGateway({
    required Uri baseUri,
    required IdentitySession identitySession,
    required http.Client client,
    Duration timeout = const Duration(seconds: 15),
  }) => HttpOrganizationDirectedAccountInvitationGateway._(
    baseUri: validatePathlessBackendBaseUri(baseUri),
    identitySession: identitySession,
    client: client,
    timeout: timeout,
  );

  HttpOrganizationDirectedAccountInvitationGateway._({
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
  Future<OrganizationDirectedAccountInvitationCreateResult> create({
    required String invitationId,
    required String organizationWorkspaceId,
    required String targetAppUserId,
  }) {
    final invitation = _canonicalInputUuid(invitationId);
    final workspace = _canonicalInputUuid(organizationWorkspaceId);
    final target = _canonicalInputUuid(targetAppUserId);
    if (invitation == null || workspace == null || target == null) {
      return Future.value(
        const OrganizationDirectedAccountInvitationCreateRejected(
          OrganizationDirectedAccountInvitationFailureCode.invalidRequest,
        ),
      );
    }

    final uri = baseUri.resolve(
      '/v1/organizations/$workspace/directed-account-invitations',
    );
    final body = jsonEncode({
      'invitation_id': invitation,
      'target_app_user_id': target,
    });
    return _request(
      uri: uri,
      body: body,
      success: (root) => OrganizationDirectedAccountInvitationCreateSuccess(
        _parseCreateReceipt(root, invitation, workspace),
      ),
      rejected: OrganizationDirectedAccountInvitationCreateRejected.new,
    );
  }

  @override
  Future<OrganizationDirectedAccountInvitationAcceptResult> accept({
    required String invitationId,
  }) {
    final invitation = _canonicalInputUuid(invitationId);
    if (invitation == null) {
      return Future.value(
        const OrganizationDirectedAccountInvitationAcceptRejected(
          OrganizationDirectedAccountInvitationFailureCode.invalidRequest,
        ),
      );
    }

    final uri = baseUri.resolve(
      '/v1/organization-directed-account-invitations/$invitation/accept',
    );
    return _request(
      uri: uri,
      body: jsonEncode(const <String, Object?>{}),
      success: (root) => OrganizationDirectedAccountInvitationAcceptSuccess(
        _parseAcceptReceipt(root, invitation),
      ),
      rejected: OrganizationDirectedAccountInvitationAcceptRejected.new,
    );
  }

  Future<Result> _request<Result>({
    required Uri uri,
    required String body,
    required Result Function(Map<String, Object?>) success,
    required Result Function(OrganizationDirectedAccountInvitationFailureCode)
    rejected,
  }) async {
    try {
      var access = await identitySession.accessToken();
      if (access is! IdentitySuccess<IdentityAccessToken>) {
        return rejected(_identityFailure(access));
      }

      var response = await _send(uri, body, access.value);
      var root = _jsonObject(response);
      if (response.statusCode == 401) {
        if (_failure(response.statusCode, root) !=
            OrganizationDirectedAccountInvitationFailureCode.unauthorized) {
          return rejected(
            OrganizationDirectedAccountInvitationFailureCode.invalidResponse,
          );
        }
        access = await identitySession.accessToken(forceRefresh: true);
        if (access is! IdentitySuccess<IdentityAccessToken>) {
          return rejected(_identityFailure(access));
        }
        response = await _send(uri, body, access.value);
        root = _jsonObject(response);
      }

      return response.statusCode == 200
          ? success(root)
          : rejected(_failure(response.statusCode, root));
    } on TimeoutException {
      return rejected(
        OrganizationDirectedAccountInvitationFailureCode.networkUnavailable,
      );
    } on http.ClientException {
      return rejected(
        OrganizationDirectedAccountInvitationFailureCode.networkUnavailable,
      );
    } on FormatException {
      return rejected(
        OrganizationDirectedAccountInvitationFailureCode.invalidResponse,
      );
    } on Object {
      return rejected(
        OrganizationDirectedAccountInvitationFailureCode.invalidResponse,
      );
    }
  }

  Future<http.Response> _send(
    Uri uri,
    String body,
    IdentityAccessToken token,
  ) => client
      .post(
        uri,
        headers: {
          'accept': 'application/json',
          'authorization': 'Bearer ${token.value}',
          'content-type': 'application/json; charset=utf-8',
        },
        body: body,
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

OrganizationDirectedAccountInvitationCreateReceipt _parseCreateReceipt(
  Map<String, Object?> root,
  String expectedInvitationId,
  String expectedWorkspaceId,
) {
  _requireExactKeys(root, const [
    'organization_invitation_contract_id',
    'invitation_id',
    'organization_workspace_id',
    'issued_at_utc',
    'expires_at_utc',
  ]);
  _requireContract(root);

  final invitationId = _canonicalResponseUuid(root['invitation_id']);
  final workspaceId = _canonicalResponseUuid(root['organization_workspace_id']);
  if (invitationId != expectedInvitationId ||
      workspaceId != expectedWorkspaceId) {
    throw const FormatException('organization invitation create mismatch');
  }

  final issuedAtUtc = _canonicalUtcTimestamp(root['issued_at_utc']);
  final expiresAtUtc = _canonicalUtcTimestamp(root['expires_at_utc']);
  if (expiresAtUtc.difference(issuedAtUtc) != _invitationLifetime) {
    throw const FormatException('invalid organization invitation expiry');
  }

  return OrganizationDirectedAccountInvitationCreateReceipt(
    organizationInvitationContractId: _contractId,
    invitationId: invitationId,
    organizationWorkspaceId: workspaceId,
    issuedAtUtc: issuedAtUtc,
    expiresAtUtc: expiresAtUtc,
  );
}

OrganizationDirectedAccountInvitationAcceptReceipt _parseAcceptReceipt(
  Map<String, Object?> root,
  String expectedInvitationId,
) {
  _requireExactKeys(root, const [
    'organization_invitation_contract_id',
    'invitation_id',
    'organization_workspace_id',
    'organization_membership_id',
    'accepted_at_utc',
  ]);
  _requireContract(root);

  final invitationId = _canonicalResponseUuid(root['invitation_id']);
  if (invitationId != expectedInvitationId) {
    throw const FormatException('organization invitation accept mismatch');
  }

  return OrganizationDirectedAccountInvitationAcceptReceipt(
    organizationInvitationContractId: _contractId,
    invitationId: invitationId,
    organizationWorkspaceId: _canonicalResponseUuid(
      root['organization_workspace_id'],
    ),
    organizationMembershipId: _canonicalResponseUuid(
      root['organization_membership_id'],
    ),
    acceptedAtUtc: _canonicalUtcTimestamp(root['accepted_at_utc']),
  );
}

void _requireContract(Map<String, Object?> root) {
  if (root['organization_invitation_contract_id'] != _contractId) {
    throw const FormatException('invalid organization invitation contract');
  }
}

OrganizationDirectedAccountInvitationFailureCode _failure(
  int status,
  Map<String, Object?> root,
) {
  _requireExactKeys(root, const ['error']);
  final error = _object(root['error']);
  _requireExactKeys(error, const ['code']);
  final code = error['code'];
  if (code is! String || code.isEmpty || code.trim() != code) {
    throw const FormatException('invalid organization invitation error');
  }

  return switch ((status, code)) {
    (400, 'invalid_json') =>
      OrganizationDirectedAccountInvitationFailureCode.invalidJson,
    (400, 'invalid_organization_invitation_request') =>
      OrganizationDirectedAccountInvitationFailureCode.invalidRequest,
    (401, 'unauthenticated') =>
      OrganizationDirectedAccountInvitationFailureCode.unauthorized,
    (403, 'organization_invitation_forbidden') =>
      OrganizationDirectedAccountInvitationFailureCode.forbidden,
    (409, 'organization_invitation_conflict') =>
      OrganizationDirectedAccountInvitationFailureCode.conflict,
    (413, 'payload_too_large') =>
      OrganizationDirectedAccountInvitationFailureCode.payloadTooLarge,
    (503, 'organization_invitation_unavailable') =>
      OrganizationDirectedAccountInvitationFailureCode.serviceUnavailable,
    _ => OrganizationDirectedAccountInvitationFailureCode.invalidResponse,
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
    throw const FormatException('invalid organization invitation headers');
  }
}

String _requiredHeader(http.Response response, String name) {
  for (final entry in response.headers.entries) {
    if (entry.key.toLowerCase() == name) {
      return entry.value;
    }
  }
  throw const FormatException('missing organization invitation header');
}

Map<String, Object?> _object(Object? value) {
  if (value is! Map) {
    throw const FormatException('expected organization invitation JSON object');
  }
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    if (entry.key is! String) {
      throw const FormatException('invalid organization invitation JSON key');
    }
    result[entry.key as String] = entry.value;
  }
  return result;
}

void _requireExactKeys(Map<String, Object?> value, List<String> expected) {
  final expectedSet = expected.toSet();
  if (value.length != expectedSet.length ||
      !value.keys.every(expectedSet.contains)) {
    throw const FormatException('invalid organization invitation JSON fields');
  }
}

String? _canonicalInputUuid(String value) {
  return _uuidPattern.hasMatch(value) ? value.toLowerCase() : null;
}

String _canonicalResponseUuid(Object? value) {
  if (value is! String ||
      !_uuidPattern.hasMatch(value) ||
      value.toLowerCase() != value) {
    throw const FormatException('invalid organization invitation UUID');
  }
  return value;
}

DateTime _canonicalUtcTimestamp(Object? value) {
  if (value is! String || !_canonicalUtcPattern.hasMatch(value)) {
    throw const FormatException('invalid organization invitation timestamp');
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null || !parsed.isUtc || parsed.toIso8601String() != value) {
    throw const FormatException('invalid organization invitation timestamp');
  }
  return parsed;
}

OrganizationDirectedAccountInvitationFailureCode _identityFailure(
  IdentityResult<IdentityAccessToken> result,
) => switch (result) {
  IdentityRejected<IdentityAccessToken>(:final failure) =>
    switch (failure.code) {
      IdentityFailureCode.notConfigured =>
        OrganizationDirectedAccountInvitationFailureCode.notConfigured,
      IdentityFailureCode.networkUnavailable =>
        OrganizationDirectedAccountInvitationFailureCode.networkUnavailable,
      _ => OrganizationDirectedAccountInvitationFailureCode.unauthorized,
    },
  IdentitySuccess<IdentityAccessToken>() =>
    OrganizationDirectedAccountInvitationFailureCode.unauthorized,
};

final _uuidPattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  caseSensitive: false,
);
final _canonicalUtcPattern = RegExp(
  r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$',
);
