import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../foundation/backend_base_uri.dart';
import '../identity/identity_session.dart';
import 'organization_project_membership_assignment.dart';

const _backendBaseUrl = String.fromEnvironment('BACKEND_BASE_URL');
const _pathPrefix = '/v1/organizations/';
const _contractId = 'organization-project-membership-assignment:v1';

OrganizationProjectMembershipAssignmentGateway
productionOrganizationProjectMembershipAssignmentGateway(
  IdentitySession identitySession,
) {
  final configured = _backendBaseUrl.trim();
  if (configured.isEmpty) {
    return const DeferredOrganizationProjectMembershipAssignmentGateway();
  }

  // Validate before constructing the client. A bad build-time configuration
  // must fail synchronously without allocating an HTTP resource.
  final baseUri = validatePathlessBackendBaseUri(Uri.parse(configured));
  return HttpOrganizationProjectMembershipAssignmentGateway(
    baseUri: baseUri,
    identitySession: identitySession,
    client: http.Client(),
  );
}

/// Typed transport for the fixed organization project-membership-assignment route.
final class HttpOrganizationProjectMembershipAssignmentGateway
    implements OrganizationProjectMembershipAssignmentGateway {
  factory HttpOrganizationProjectMembershipAssignmentGateway({
    required Uri baseUri,
    required IdentitySession identitySession,
    required http.Client client,
    Duration timeout = const Duration(seconds: 15),
  }) => HttpOrganizationProjectMembershipAssignmentGateway._(
    baseUri: validatePathlessBackendBaseUri(baseUri),
    identitySession: identitySession,
    client: client,
    timeout: timeout,
  );

  HttpOrganizationProjectMembershipAssignmentGateway._({
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
  Future<OrganizationProjectMembershipAssignmentResult> assign({
    required String requestId,
    required String organizationWorkspaceId,
    required String projectId,
    required String targetOrganizationMembershipId,
  }) {
    final request = _canonicalInputUuid(requestId);
    final workspace = _canonicalInputUuid(organizationWorkspaceId);
    final project = _canonicalInputUuid(projectId);
    final target = _canonicalInputUuid(targetOrganizationMembershipId);
    if (request == null ||
        workspace == null ||
        project == null ||
        target == null) {
      return Future.value(
        const OrganizationProjectMembershipAssignmentRejected(
          OrganizationProjectMembershipAssignmentFailureCode.invalidRequest,
        ),
      );
    }

    final body = jsonEncode({
      'request_id': request,
      'target_organization_membership_id': target,
    });
    return _request(
      requestBody: body,
      organizationWorkspaceId: workspace,
      projectId: project,
      targetOrganizationMembershipId: target,
    );
  }

  Future<OrganizationProjectMembershipAssignmentResult> _request({
    required String requestBody,
    required String organizationWorkspaceId,
    required String projectId,
    required String targetOrganizationMembershipId,
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

    const unauthorized = OrganizationProjectMembershipAssignmentRejected(
      OrganizationProjectMembershipAssignmentFailureCode.unauthorized,
    );

    Future<OrganizationProjectMembershipAssignmentResult>
    performRequest() async {
      try {
        subject = identitySession.current.principal?.externalSubject;
        if (!isCurrent()) return unauthorized;

        // One project-membership-assignment intent belongs to one uninterrupted sign-in,
        // including a 401 retry. A final-only comparison would miss ABA.
        identitySubscription = identitySession.changes.listen(
          (snapshot) {
            if (!matches(snapshot)) identityChanged = true;
          },
          onError: (Object error, StackTrace stackTrace) =>
              identityChanged = true,
          onDone: () => identityChanged = true,
        );
        if (!isCurrent()) return unauthorized;
        var access = await identitySession.accessToken();
        if (!isCurrent()) return unauthorized;
        if (access is! IdentitySuccess<IdentityAccessToken>) {
          return OrganizationProjectMembershipAssignmentRejected(
            _identityFailure(access),
          );
        }

        var response = await _send(
          access.value,
          organizationWorkspaceId: organizationWorkspaceId,
          projectId: projectId,
          requestBody: requestBody,
        );
        if (!isCurrent()) return unauthorized;
        var root = _jsonObject(response);

        if (response.statusCode == 401) {
          final firstFailure = _failure(response.statusCode, root);
          if (firstFailure !=
              OrganizationProjectMembershipAssignmentFailureCode.unauthorized) {
            return const OrganizationProjectMembershipAssignmentRejected(
              OrganizationProjectMembershipAssignmentFailureCode
                  .invalidResponse,
            );
          }

          access = await identitySession.accessToken(forceRefresh: true);
          if (!isCurrent()) return unauthorized;
          if (access is! IdentitySuccess<IdentityAccessToken>) {
            return OrganizationProjectMembershipAssignmentRejected(
              _identityFailure(access),
            );
          }
          response = await _send(
            access.value,
            organizationWorkspaceId: organizationWorkspaceId,
            projectId: projectId,
            requestBody: requestBody,
          );
          if (!isCurrent()) return unauthorized;
          root = _jsonObject(response);
        }

        final result = response.statusCode == 200
            ? OrganizationProjectMembershipAssignmentSuccess(
                _parseReceipt(
                  root,
                  organizationWorkspaceId,
                  projectId,
                  targetOrganizationMembershipId,
                ),
              )
            : OrganizationProjectMembershipAssignmentRejected(
                _failure(response.statusCode, root),
              );
        return isCurrent() ? result : unauthorized;
      } on TimeoutException {
        if (fenceWasBroken()) return unauthorized;
        return const OrganizationProjectMembershipAssignmentRejected(
          OrganizationProjectMembershipAssignmentFailureCode.networkUnavailable,
        );
      } on http.ClientException {
        if (fenceWasBroken()) return unauthorized;
        return const OrganizationProjectMembershipAssignmentRejected(
          OrganizationProjectMembershipAssignmentFailureCode.networkUnavailable,
        );
      } on FormatException {
        if (fenceWasBroken()) return unauthorized;
        return const OrganizationProjectMembershipAssignmentRejected(
          OrganizationProjectMembershipAssignmentFailureCode.invalidResponse,
        );
      } on Object {
        if (fenceWasBroken()) return unauthorized;
        // Do not expose provider, HTTP client, identity, or database details.
        return const OrganizationProjectMembershipAssignmentRejected(
          OrganizationProjectMembershipAssignmentFailureCode.invalidResponse,
        );
      }
    }

    final result = await performRequest();
    try {
      // cancel() stops events before its cleanup Future completes. Awaiting it
      // would hide identity changes before delivery. ignore() keeps errors typed.
      identitySubscription?.cancel().ignore();
    } on Object {
      if (fenceWasBroken()) return unauthorized;
      return const OrganizationProjectMembershipAssignmentRejected(
        OrganizationProjectMembershipAssignmentFailureCode.invalidResponse,
      );
    }
    try {
      return isCurrent() ? result : unauthorized;
    } on Object {
      return const OrganizationProjectMembershipAssignmentRejected(
        OrganizationProjectMembershipAssignmentFailureCode.invalidResponse,
      );
    }
  }

  Future<http.Response> _send(
    IdentityAccessToken token, {
    required String organizationWorkspaceId,
    required String projectId,
    required String requestBody,
  }) => client
      .post(
        baseUri.resolve(
          '$_pathPrefix$organizationWorkspaceId/projects/$projectId/memberships',
        ),
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

OrganizationProjectMembershipAssignmentReceipt _parseReceipt(
  Map<String, Object?> root,
  String expectedWorkspaceId,
  String expectedProjectId,
  String expectedOrganizationMembershipId,
) {
  _requireExactKeys(root, const [
    'project_membership_assignment_contract_id',
    'organization_workspace_id',
    'project_id',
    'organization_membership_id',
    'project_membership_id',
    'active_from_utc',
    'inactive_from_utc',
  ]);
  if (root['project_membership_assignment_contract_id'] != _contractId) {
    throw const FormatException(
      'invalid project membership assignment contract',
    );
  }
  final workspaceId = _canonicalResponseUuid(root['organization_workspace_id']);
  final projectId = _canonicalResponseUuid(root['project_id']);
  final membershipId = _canonicalResponseUuid(
    root['organization_membership_id'],
  );
  if (workspaceId != expectedWorkspaceId ||
      projectId != expectedProjectId ||
      membershipId != expectedOrganizationMembershipId) {
    throw const FormatException(
      'project membership assignment selector mismatch',
    );
  }
  final activeFromUtc = _canonicalUtcTimestamp(root['active_from_utc']);
  final inactiveFromUtc = root['inactive_from_utc'] == null
      ? null
      : _canonicalUtcTimestamp(root['inactive_from_utc']);
  if (inactiveFromUtc != null && inactiveFromUtc.isBefore(activeFromUtc)) {
    throw const FormatException(
      'invalid project membership assignment interval',
    );
  }
  return OrganizationProjectMembershipAssignmentReceipt(
    projectMembershipAssignmentContractId: _contractId,
    organizationWorkspaceId: workspaceId,
    projectId: projectId,
    organizationMembershipId: membershipId,
    projectMembershipId: _canonicalResponseUuid(root['project_membership_id']),
    activeFromUtc: activeFromUtc,
    inactiveFromUtc: inactiveFromUtc,
  );
}

OrganizationProjectMembershipAssignmentFailureCode _failure(
  int status,
  Map<String, Object?> root,
) {
  _requireExactKeys(root, const ['error']);
  final error = _object(root['error']);
  _requireExactKeys(error, const ['code']);
  final code = error['code'];
  if (code is! String || code.isEmpty || code.trim() != code) {
    throw const FormatException(
      'invalid organization project membership assignment error',
    );
  }

  return switch ((status, code)) {
    (400, 'invalid_json') =>
      OrganizationProjectMembershipAssignmentFailureCode.invalidJson,
    (400, 'invalid_organization_project_membership_assignment_request') =>
      OrganizationProjectMembershipAssignmentFailureCode.invalidRequest,
    (401, 'unauthenticated') =>
      OrganizationProjectMembershipAssignmentFailureCode.unauthorized,
    (403, 'organization_project_membership_assignment_forbidden') =>
      OrganizationProjectMembershipAssignmentFailureCode.forbidden,
    (409, 'organization_project_membership_assignment_conflict') =>
      OrganizationProjectMembershipAssignmentFailureCode.conflict,
    (413, 'payload_too_large') =>
      OrganizationProjectMembershipAssignmentFailureCode.payloadTooLarge,
    (503, 'organization_project_membership_assignment_unavailable') =>
      OrganizationProjectMembershipAssignmentFailureCode.serviceUnavailable,
    _ => OrganizationProjectMembershipAssignmentFailureCode.invalidResponse,
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
      'invalid organization project membership assignment response headers',
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
    'missing organization project membership assignment response header',
  );
}

Map<String, Object?> _object(Object? value) {
  if (value is! Map) {
    throw const FormatException(
      'expected organization project membership assignment JSON object',
    );
  }
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    if (entry.key is! String) {
      throw const FormatException(
        'invalid organization project membership assignment JSON key',
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
      'invalid organization project membership assignment JSON fields',
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
    throw const FormatException(
      'invalid organization project membership assignment UUID',
    );
  }
  return value;
}

DateTime _canonicalUtcTimestamp(Object? value) {
  if (value is! String || !_canonicalUtcPattern.hasMatch(value)) {
    throw const FormatException(
      'invalid organization project membership assignment timestamp',
    );
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null || !parsed.isUtc || parsed.toIso8601String() != value) {
    throw const FormatException(
      'invalid organization project membership assignment timestamp',
    );
  }
  return parsed;
}

OrganizationProjectMembershipAssignmentFailureCode _identityFailure(
  IdentityResult<IdentityAccessToken> result,
) => switch (result) {
  IdentityRejected<IdentityAccessToken>(:final failure) =>
    switch (failure.code) {
      IdentityFailureCode.notConfigured =>
        OrganizationProjectMembershipAssignmentFailureCode.notConfigured,
      IdentityFailureCode.networkUnavailable =>
        OrganizationProjectMembershipAssignmentFailureCode.networkUnavailable,
      _ => OrganizationProjectMembershipAssignmentFailureCode.unauthorized,
    },
  IdentitySuccess<IdentityAccessToken>() =>
    OrganizationProjectMembershipAssignmentFailureCode.unauthorized,
};

final _uuidPattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  caseSensitive: false,
);
final _canonicalUtcPattern = RegExp(
  r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$',
);
