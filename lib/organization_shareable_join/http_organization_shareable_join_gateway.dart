import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../foundation/backend_base_uri.dart';
import '../identity/identity_session.dart';
import 'organization_shareable_join.dart';

const _backendBaseUrl = String.fromEnvironment('BACKEND_BASE_URL');
const _linkContractId = 'organization-shareable-join-link:v1';
const _linkPreviewContractId = 'organization-shareable-join-link-preview:v1';
const _applicationContractId = 'organization-shareable-join-application:v1';
const _lifetime = Duration(hours: 168);

/// 使用既有 Backend 配置创建网关；空配置不分配 HTTP client。
OrganizationShareableJoinGateway productionOrganizationShareableJoinGateway(
  IdentitySession identitySession,
) {
  final configured = _backendBaseUrl.trim();
  if (configured.isEmpty) {
    return const DeferredOrganizationShareableJoinGateway();
  }

  final baseUri = validatePathlessBackendBaseUri(Uri.parse(configured));
  return HttpOrganizationShareableJoinGateway(
    baseUri: baseUri,
    identitySession: identitySession,
    client: http.Client(),
  );
}

/// 通过已配置的 Backend 创建或预览 link、提交或批准 application。
final class HttpOrganizationShareableJoinGateway
    implements OrganizationShareableJoinGateway {
  factory HttpOrganizationShareableJoinGateway({
    required Uri baseUri,
    required IdentitySession identitySession,
    required http.Client client,
    Duration timeout = const Duration(seconds: 15),
  }) => HttpOrganizationShareableJoinGateway._(
    baseUri: validatePathlessBackendBaseUri(baseUri),
    identitySession: identitySession,
    client: client,
    timeout: timeout,
  );

  HttpOrganizationShareableJoinGateway._({
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
  Future<OrganizationShareableJoinLinkCreateResult> createLink({
    required String linkId,
    required String organizationWorkspaceId,
  }) {
    final link = _canonicalInputUuid(linkId);
    final workspace = _canonicalInputUuid(organizationWorkspaceId);
    if (link == null || workspace == null) {
      return Future.value(
        const OrganizationShareableJoinLinkCreateRejected(
          OrganizationShareableJoinFailureCode.invalidRequest,
        ),
      );
    }

    return _request(
      uri: baseUri.resolve('/v1/organizations/$workspace/shareable-join-links'),
      requestBody: jsonEncode({'link_id': link}),
      success: (root) => OrganizationShareableJoinLinkCreateSuccess(
        _parseLinkCreateReceipt(root, link, workspace),
      ),
      rejected: OrganizationShareableJoinLinkCreateRejected.new,
    );
  }

  @override
  Future<OrganizationShareableJoinLinkPreviewResult> previewLink({
    required String linkId,
  }) {
    final link = _canonicalInputUuid(linkId);
    if (link == null) {
      return Future.value(
        const OrganizationShareableJoinLinkPreviewRejected(
          OrganizationShareableJoinFailureCode.invalidRequest,
        ),
      );
    }

    return _request(
      uri: baseUri.resolve('/v1/organization-shareable-join-links/$link'),
      success: (root) => OrganizationShareableJoinLinkPreviewSuccess(
        _parseLinkPreviewReceipt(root, link),
      ),
      rejected: OrganizationShareableJoinLinkPreviewRejected.new,
    );
  }

  @override
  Future<OrganizationShareableJoinApplicationSubmitResult> submitApplication({
    required String applicationId,
    required String linkId,
  }) {
    final application = _canonicalInputUuid(applicationId);
    final link = _canonicalInputUuid(linkId);
    if (application == null || link == null) {
      return Future.value(
        const OrganizationShareableJoinApplicationSubmitRejected(
          OrganizationShareableJoinFailureCode.invalidRequest,
        ),
      );
    }

    return _request(
      uri: baseUri.resolve(
        '/v1/organization-shareable-join-links/$link/applications',
      ),
      requestBody: jsonEncode({'application_id': application}),
      success: (root) => OrganizationShareableJoinApplicationSubmitSuccess(
        _parseApplicationSubmitReceipt(root, application, link),
      ),
      rejected: OrganizationShareableJoinApplicationSubmitRejected.new,
    );
  }

  @override
  Future<OrganizationShareableJoinApplicationApproveResult> approveApplication({
    required String organizationWorkspaceId,
    required String applicationId,
  }) {
    final workspace = _canonicalInputUuid(organizationWorkspaceId);
    final application = _canonicalInputUuid(applicationId);
    if (workspace == null || application == null) {
      return Future.value(
        const OrganizationShareableJoinApplicationApproveRejected(
          OrganizationShareableJoinFailureCode.invalidRequest,
        ),
      );
    }

    return _request(
      uri: baseUri.resolve(
        '/v1/organizations/$workspace/shareable-join-applications/'
        '$application/approve',
      ),
      requestBody: jsonEncode(const <String, Object?>{}),
      success: (root) => OrganizationShareableJoinApplicationApproveSuccess(
        _parseApplicationApproveReceipt(root, application, workspace),
      ),
      rejected: OrganizationShareableJoinApplicationApproveRejected.new,
    );
  }

  Future<Result> _request<Result>({
    required Uri uri,
    String? requestBody,
    required Result Function(Map<String, Object?>) success,
    required Result Function(OrganizationShareableJoinFailureCode) rejected,
  }) async {
    StreamSubscription<IdentitySnapshot>? identitySubscription;
    String? subject;
    var identityChanged = false;
    bool matches(IdentitySnapshot snapshot) =>
        subject != null &&
        snapshot.stage == IdentityStage.signedIn &&
        snapshot.principal?.externalSubject == subject;
    bool isCurrent() =>
        !_closed && !identityChanged && matches(identitySession.current);
    bool fenceWasBroken() {
      if (_closed || identityChanged) return true;
      try {
        return !matches(identitySession.current);
      } on Object {
        return false;
      }
    }

    Result unauthorized() =>
        rejected(OrganizationShareableJoinFailureCode.unauthorized);

    Future<Result> performRequest() async {
      try {
        subject = identitySession.current.principal?.externalSubject;
        if (!isCurrent()) return unauthorized();

        // One request belongs to one uninterrupted sign-in. Comparing only the
        // final subject would miss a sign-out/sign-in ABA during token or HTTP IO.
        identitySubscription = identitySession.changes.listen(
          (snapshot) {
            if (!matches(snapshot)) identityChanged = true;
          },
          onError: (Object error, StackTrace stackTrace) =>
              identityChanged = true,
          onDone: () => identityChanged = true,
        );
        if (!isCurrent()) return unauthorized();
        var access = await identitySession.accessToken();
        if (!isCurrent()) return unauthorized();
        if (access is! IdentitySuccess<IdentityAccessToken>) {
          return rejected(_identityFailure(access));
        }

        var response = await _send(uri, requestBody, access.value);
        if (!isCurrent()) return unauthorized();
        var root = _jsonObject(response);
        if (response.statusCode == 401) {
          if (_failure(response.statusCode, root) !=
              OrganizationShareableJoinFailureCode.unauthorized) {
            return rejected(
              OrganizationShareableJoinFailureCode.invalidResponse,
            );
          }
          access = await identitySession.accessToken(forceRefresh: true);
          if (!isCurrent()) return unauthorized();
          if (access is! IdentitySuccess<IdentityAccessToken>) {
            return rejected(_identityFailure(access));
          }
          response = await _send(uri, requestBody, access.value);
          if (!isCurrent()) return unauthorized();
          root = _jsonObject(response);
        }

        final result = response.statusCode == 200
            ? success(root)
            : rejected(_failure(response.statusCode, root));
        return isCurrent() ? result : unauthorized();
      } on TimeoutException {
        if (fenceWasBroken()) return unauthorized();
        return rejected(
          OrganizationShareableJoinFailureCode.networkUnavailable,
        );
      } on http.ClientException {
        if (fenceWasBroken()) return unauthorized();
        return rejected(
          OrganizationShareableJoinFailureCode.networkUnavailable,
        );
      } on FormatException {
        if (fenceWasBroken()) return unauthorized();
        return rejected(OrganizationShareableJoinFailureCode.invalidResponse);
      } on Object {
        if (fenceWasBroken()) return unauthorized();
        return rejected(OrganizationShareableJoinFailureCode.invalidResponse);
      }
    }

    final result = await performRequest();
    try {
      // cancel() stops events before its cleanup Future completes. Awaiting it
      // would hide identity changes before delivery.
      identitySubscription?.cancel().ignore();
    } on Object {
      if (fenceWasBroken()) return unauthorized();
      return rejected(OrganizationShareableJoinFailureCode.invalidResponse);
    }
    try {
      return isCurrent() ? result : unauthorized();
    } on Object {
      return rejected(OrganizationShareableJoinFailureCode.invalidResponse);
    }
  }

  Future<http.Response> _send(
    Uri uri,
    String? requestBody,
    IdentityAccessToken token,
  ) {
    final headers = {
      'accept': 'application/json',
      'authorization': 'Bearer ${token.value}',
    };
    final response = requestBody == null
        ? client.get(uri, headers: headers)
        : client.post(
            uri,
            headers: {
              ...headers,
              'content-type': 'application/json; charset=utf-8',
            },
            body: requestBody,
          );
    return response.timeout(timeout);
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    client.close();
  }
}

OrganizationShareableJoinLinkCreateReceipt _parseLinkCreateReceipt(
  Map<String, Object?> root,
  String expectedLinkId,
  String expectedWorkspaceId,
) {
  _requireExactKeys(root, const [
    'organization_shareable_join_link_contract_id',
    'link_id',
    'organization_workspace_id',
    'issued_at_utc',
    'expires_at_utc',
  ]);
  _requireContract(
    root,
    'organization_shareable_join_link_contract_id',
    _linkContractId,
  );
  final linkId = _canonicalResponseUuid(root['link_id']);
  final workspaceId = _canonicalResponseUuid(root['organization_workspace_id']);
  if (linkId != expectedLinkId || workspaceId != expectedWorkspaceId) {
    throw const FormatException('organization shareable join create mismatch');
  }
  final issuedAtUtc = _canonicalUtcTimestamp(root['issued_at_utc']);
  final expiresAtUtc = _canonicalUtcTimestamp(root['expires_at_utc']);
  _requireLifetime(issuedAtUtc, expiresAtUtc);
  return OrganizationShareableJoinLinkCreateReceipt(
    organizationShareableJoinLinkContractId: _linkContractId,
    linkId: linkId,
    organizationWorkspaceId: workspaceId,
    issuedAtUtc: issuedAtUtc,
    expiresAtUtc: expiresAtUtc,
  );
}

OrganizationShareableJoinLinkPreviewReceipt _parseLinkPreviewReceipt(
  Map<String, Object?> root,
  String expectedLinkId,
) {
  _requireExactKeys(root, const [
    'organization_shareable_join_link_preview_contract_id',
    'link_id',
    'organization_name',
    'expires_at_utc',
  ]);
  _requireContract(
    root,
    'organization_shareable_join_link_preview_contract_id',
    _linkPreviewContractId,
  );
  final linkId = _canonicalResponseUuid(root['link_id']);
  if (linkId != expectedLinkId) {
    throw const FormatException('organization shareable join preview mismatch');
  }
  return OrganizationShareableJoinLinkPreviewReceipt(
    organizationShareableJoinLinkPreviewContractId: _linkPreviewContractId,
    linkId: linkId,
    organizationName: _organizationName(root['organization_name']),
    expiresAtUtc: _canonicalUtcTimestamp(root['expires_at_utc']),
  );
}

OrganizationShareableJoinApplicationSubmitReceipt
_parseApplicationSubmitReceipt(
  Map<String, Object?> root,
  String expectedApplicationId,
  String expectedLinkId,
) {
  _requireExactKeys(root, const [
    'organization_shareable_join_application_contract_id',
    'application_id',
    'link_id',
    'organization_workspace_id',
    'submitted_at_utc',
    'expires_at_utc',
  ]);
  _requireContract(
    root,
    'organization_shareable_join_application_contract_id',
    _applicationContractId,
  );
  final applicationId = _canonicalResponseUuid(root['application_id']);
  final linkId = _canonicalResponseUuid(root['link_id']);
  if (applicationId != expectedApplicationId || linkId != expectedLinkId) {
    throw const FormatException('organization shareable join submit mismatch');
  }
  final submittedAtUtc = _canonicalUtcTimestamp(root['submitted_at_utc']);
  final expiresAtUtc = _canonicalUtcTimestamp(root['expires_at_utc']);
  _requireLifetime(submittedAtUtc, expiresAtUtc);
  return OrganizationShareableJoinApplicationSubmitReceipt(
    organizationShareableJoinApplicationContractId: _applicationContractId,
    applicationId: applicationId,
    linkId: linkId,
    organizationWorkspaceId: _canonicalResponseUuid(
      root['organization_workspace_id'],
    ),
    submittedAtUtc: submittedAtUtc,
    expiresAtUtc: expiresAtUtc,
  );
}

OrganizationShareableJoinApplicationApproveReceipt
_parseApplicationApproveReceipt(
  Map<String, Object?> root,
  String expectedApplicationId,
  String expectedWorkspaceId,
) {
  _requireExactKeys(root, const [
    'organization_shareable_join_application_contract_id',
    'application_id',
    'organization_workspace_id',
    'organization_membership_id',
    'approved_at_utc',
  ]);
  _requireContract(
    root,
    'organization_shareable_join_application_contract_id',
    _applicationContractId,
  );
  final applicationId = _canonicalResponseUuid(root['application_id']);
  final workspaceId = _canonicalResponseUuid(root['organization_workspace_id']);
  if (applicationId != expectedApplicationId ||
      workspaceId != expectedWorkspaceId) {
    throw const FormatException('organization shareable join approve mismatch');
  }
  return OrganizationShareableJoinApplicationApproveReceipt(
    organizationShareableJoinApplicationContractId: _applicationContractId,
    applicationId: applicationId,
    organizationWorkspaceId: workspaceId,
    organizationMembershipId: _canonicalResponseUuid(
      root['organization_membership_id'],
    ),
    approvedAtUtc: _canonicalUtcTimestamp(root['approved_at_utc']),
  );
}

void _requireLifetime(DateTime start, DateTime end) {
  if (end.difference(start) != _lifetime) {
    throw const FormatException('invalid organization shareable join expiry');
  }
}

void _requireContract(Map<String, Object?> root, String key, String expected) {
  if (root[key] != expected) {
    throw const FormatException('invalid organization shareable join contract');
  }
}

OrganizationShareableJoinFailureCode _failure(
  int status,
  Map<String, Object?> root,
) {
  _requireExactKeys(root, const ['error']);
  final error = _object(root['error']);
  _requireExactKeys(error, const ['code']);
  final code = error['code'];
  if (code is! String || code.isEmpty || code.trim() != code) {
    throw const FormatException('invalid organization shareable join error');
  }

  return switch ((status, code)) {
    (400, 'invalid_json') => OrganizationShareableJoinFailureCode.invalidJson,
    (400, 'invalid_organization_shareable_join_request') =>
      OrganizationShareableJoinFailureCode.invalidRequest,
    (401, 'unauthenticated') =>
      OrganizationShareableJoinFailureCode.unauthorized,
    (403, 'organization_shareable_join_forbidden') =>
      OrganizationShareableJoinFailureCode.forbidden,
    (409, 'organization_shareable_join_conflict') =>
      OrganizationShareableJoinFailureCode.conflict,
    (413, 'payload_too_large') =>
      OrganizationShareableJoinFailureCode.payloadTooLarge,
    (503, 'organization_shareable_join_unavailable') =>
      OrganizationShareableJoinFailureCode.serviceUnavailable,
    _ => OrganizationShareableJoinFailureCode.invalidResponse,
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
    throw const FormatException('invalid organization shareable join headers');
  }
}

String _requiredHeader(http.Response response, String name) {
  for (final entry in response.headers.entries) {
    if (entry.key.toLowerCase() == name) return entry.value;
  }
  throw const FormatException('missing organization shareable join header');
}

Map<String, Object?> _object(Object? value) {
  if (value is! Map) {
    throw const FormatException(
      'expected organization shareable join JSON object',
    );
  }
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    if (entry.key is! String) {
      throw const FormatException(
        'invalid organization shareable join JSON key',
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
    throw const FormatException('invalid organization shareable join fields');
  }
}

String? _canonicalInputUuid(String value) =>
    _uuidPattern.hasMatch(value) ? value.toLowerCase() : null;

String _canonicalResponseUuid(Object? value) {
  if (value is! String ||
      !_uuidPattern.hasMatch(value) ||
      value.toLowerCase() != value) {
    throw const FormatException('invalid organization shareable join UUID');
  }
  return value;
}

String _organizationName(Object? value) {
  if (value is! String ||
      !value.codeUnits.any((codeUnit) => codeUnit != 0x20)) {
    throw const FormatException('invalid organization shareable join name');
  }
  return value;
}

DateTime _canonicalUtcTimestamp(Object? value) {
  if (value is! String || !_canonicalUtcPattern.hasMatch(value)) {
    throw const FormatException(
      'invalid organization shareable join timestamp',
    );
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null || !parsed.isUtc || parsed.toIso8601String() != value) {
    throw const FormatException(
      'invalid organization shareable join timestamp',
    );
  }
  return parsed;
}

OrganizationShareableJoinFailureCode _identityFailure(
  IdentityResult<IdentityAccessToken> result,
) => switch (result) {
  IdentityRejected<IdentityAccessToken>(:final failure) =>
    switch (failure.code) {
      IdentityFailureCode.notConfigured =>
        OrganizationShareableJoinFailureCode.notConfigured,
      IdentityFailureCode.networkUnavailable =>
        OrganizationShareableJoinFailureCode.networkUnavailable,
      _ => OrganizationShareableJoinFailureCode.unauthorized,
    },
  IdentitySuccess<IdentityAccessToken>() =>
    OrganizationShareableJoinFailureCode.unauthorized,
};

final _uuidPattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  caseSensitive: false,
);
final _canonicalUtcPattern = RegExp(
  r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$',
);
