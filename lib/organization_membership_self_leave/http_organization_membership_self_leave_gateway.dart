import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../foundation/backend_base_uri.dart';
import '../identity/identity_session.dart';
import 'organization_membership_self_leave.dart';

const _backendBaseUrl = String.fromEnvironment('BACKEND_BASE_URL');
const _pathPrefix = '/v1/organizations/';
const _pathSuffix = '/membership-self-leave';
const _contractId = 'organization-membership-self-leave:v1';

OrganizationMembershipSelfLeaveGateway
productionOrganizationMembershipSelfLeaveGateway(
  IdentitySession identitySession,
) {
  final configured = _backendBaseUrl.trim();
  if (configured.isEmpty) {
    return const DeferredOrganizationMembershipSelfLeaveGateway();
  }

  // Validate before constructing the client. A bad build-time configuration
  // must fail synchronously without allocating an HTTP resource.
  final baseUri = validatePathlessBackendBaseUri(Uri.parse(configured));
  return HttpOrganizationMembershipSelfLeaveGateway(
    baseUri: baseUri,
    identitySession: identitySession,
    client: http.Client(),
  );
}

/// Typed transport for the fixed organization membership self-leave route.
final class HttpOrganizationMembershipSelfLeaveGateway
    implements OrganizationMembershipSelfLeaveGateway {
  factory HttpOrganizationMembershipSelfLeaveGateway({
    required Uri baseUri,
    required IdentitySession identitySession,
    required http.Client client,
    Duration timeout = const Duration(seconds: 15),
  }) => HttpOrganizationMembershipSelfLeaveGateway._(
    baseUri: validatePathlessBackendBaseUri(baseUri),
    identitySession: identitySession,
    client: client,
    timeout: timeout,
  );

  HttpOrganizationMembershipSelfLeaveGateway._({
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
  Future<OrganizationMembershipSelfLeaveResult> leave({
    required String requestId,
    required String organizationWorkspaceId,
  }) {
    final request = _canonicalInputUuid(requestId);
    final workspace = _canonicalInputUuid(organizationWorkspaceId);
    if (request == null || workspace == null) {
      return Future.value(
        const OrganizationMembershipSelfLeaveRejected(
          OrganizationMembershipSelfLeaveFailureCode.invalidRequest,
        ),
      );
    }

    final body = jsonEncode({'request_id': request});
    return _request(requestBody: body, organizationWorkspaceId: workspace);
  }

  Future<OrganizationMembershipSelfLeaveResult> _request({
    required String requestBody,
    required String organizationWorkspaceId,
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

    const unauthorized = OrganizationMembershipSelfLeaveRejected(
      OrganizationMembershipSelfLeaveFailureCode.unauthorized,
    );

    Future<OrganizationMembershipSelfLeaveResult> performRequest() async {
      try {
        subject = identitySession.current.principal?.externalSubject;
        if (!isCurrent()) return unauthorized;

        // A leave intent belongs to one uninterrupted sign-in, including 401
        // retry. Comparing only the final subject would miss sign-out/sign-in ABA.
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
          return OrganizationMembershipSelfLeaveRejected(
            _identityFailure(access),
          );
        }

        var response = await _send(
          access.value,
          organizationWorkspaceId: organizationWorkspaceId,
          requestBody: requestBody,
        );
        if (!isCurrent()) return unauthorized;
        var root = _jsonObject(response);

        if (response.statusCode == 401) {
          final firstFailure = _failure(response.statusCode, root);
          if (firstFailure !=
              OrganizationMembershipSelfLeaveFailureCode.unauthorized) {
            return const OrganizationMembershipSelfLeaveRejected(
              OrganizationMembershipSelfLeaveFailureCode.invalidResponse,
            );
          }

          access = await identitySession.accessToken(forceRefresh: true);
          if (!isCurrent()) return unauthorized;
          if (access is! IdentitySuccess<IdentityAccessToken>) {
            return OrganizationMembershipSelfLeaveRejected(
              _identityFailure(access),
            );
          }
          response = await _send(
            access.value,
            organizationWorkspaceId: organizationWorkspaceId,
            requestBody: requestBody,
          );
          if (!isCurrent()) return unauthorized;
          root = _jsonObject(response);
        }

        final result = response.statusCode == 200
            ? OrganizationMembershipSelfLeaveSuccess(
                _parseReceipt(root, organizationWorkspaceId),
              )
            : OrganizationMembershipSelfLeaveRejected(
                _failure(response.statusCode, root),
              );
        return isCurrent() ? result : unauthorized;
      } on TimeoutException {
        if (fenceWasBroken()) return unauthorized;
        return const OrganizationMembershipSelfLeaveRejected(
          OrganizationMembershipSelfLeaveFailureCode.networkUnavailable,
        );
      } on http.ClientException {
        if (fenceWasBroken()) return unauthorized;
        return const OrganizationMembershipSelfLeaveRejected(
          OrganizationMembershipSelfLeaveFailureCode.networkUnavailable,
        );
      } on FormatException {
        if (fenceWasBroken()) return unauthorized;
        return const OrganizationMembershipSelfLeaveRejected(
          OrganizationMembershipSelfLeaveFailureCode.invalidResponse,
        );
      } on Object {
        if (fenceWasBroken()) return unauthorized;
        // Do not expose provider, HTTP client, identity, or database details.
        return const OrganizationMembershipSelfLeaveRejected(
          OrganizationMembershipSelfLeaveFailureCode.invalidResponse,
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
      return const OrganizationMembershipSelfLeaveRejected(
        OrganizationMembershipSelfLeaveFailureCode.invalidResponse,
      );
    }
    try {
      return isCurrent() ? result : unauthorized;
    } on Object {
      return const OrganizationMembershipSelfLeaveRejected(
        OrganizationMembershipSelfLeaveFailureCode.invalidResponse,
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

OrganizationMembershipSelfLeaveReceipt _parseReceipt(
  Map<String, Object?> root,
  String expectedWorkspaceId,
) {
  _requireExactKeys(root, const [
    'membership_self_leave_contract_id',
    'organization_workspace_id',
    'organization_membership_id',
    'effective_at_utc',
  ]);
  if (root['membership_self_leave_contract_id'] != _contractId) {
    throw const FormatException(
      'invalid organization membership self-leave contract',
    );
  }

  final workspaceId = _canonicalResponseUuid(root['organization_workspace_id']);
  if (workspaceId != expectedWorkspaceId) {
    throw const FormatException(
      'organization membership self-leave workspace mismatch',
    );
  }

  return OrganizationMembershipSelfLeaveReceipt(
    membershipSelfLeaveContractId: _contractId,
    organizationWorkspaceId: workspaceId,
    organizationMembershipId: _canonicalResponseUuid(
      root['organization_membership_id'],
    ),
    effectiveAtUtc: _canonicalUtcTimestamp(root['effective_at_utc']),
  );
}

OrganizationMembershipSelfLeaveFailureCode _failure(
  int status,
  Map<String, Object?> root,
) {
  _requireExactKeys(root, const ['error']);
  final error = _object(root['error']);
  _requireExactKeys(error, const ['code']);
  final code = error['code'];
  if (code is! String || code.isEmpty || code.trim() != code) {
    throw const FormatException(
      'invalid organization membership self-leave error',
    );
  }

  return switch ((status, code)) {
    (400, 'invalid_json') =>
      OrganizationMembershipSelfLeaveFailureCode.invalidJson,
    (400, 'invalid_organization_membership_self_leave_request') =>
      OrganizationMembershipSelfLeaveFailureCode.invalidRequest,
    (401, 'unauthenticated') =>
      OrganizationMembershipSelfLeaveFailureCode.unauthorized,
    (403, 'organization_membership_self_leave_forbidden') =>
      OrganizationMembershipSelfLeaveFailureCode.forbidden,
    (409, 'organization_membership_self_leave_conflict') =>
      OrganizationMembershipSelfLeaveFailureCode.conflict,
    (413, 'payload_too_large') =>
      OrganizationMembershipSelfLeaveFailureCode.payloadTooLarge,
    (503, 'organization_membership_self_leave_unavailable') =>
      OrganizationMembershipSelfLeaveFailureCode.serviceUnavailable,
    _ => OrganizationMembershipSelfLeaveFailureCode.invalidResponse,
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
      'invalid organization membership self-leave response headers',
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
    'missing organization membership self-leave response header',
  );
}

Map<String, Object?> _object(Object? value) {
  if (value is! Map) {
    throw const FormatException(
      'expected organization membership self-leave JSON object',
    );
  }
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    if (entry.key is! String) {
      throw const FormatException(
        'invalid organization membership self-leave JSON key',
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
      'invalid organization membership self-leave JSON fields',
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
      'invalid organization membership self-leave UUID',
    );
  }
  return value;
}

DateTime _canonicalUtcTimestamp(Object? value) {
  if (value is! String || !_canonicalUtcPattern.hasMatch(value)) {
    throw const FormatException(
      'invalid organization membership self-leave timestamp',
    );
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null || !parsed.isUtc || parsed.toIso8601String() != value) {
    throw const FormatException(
      'invalid organization membership self-leave timestamp',
    );
  }
  return parsed;
}

OrganizationMembershipSelfLeaveFailureCode _identityFailure(
  IdentityResult<IdentityAccessToken> result,
) => switch (result) {
  IdentityRejected<IdentityAccessToken>(:final failure) =>
    switch (failure.code) {
      IdentityFailureCode.notConfigured =>
        OrganizationMembershipSelfLeaveFailureCode.notConfigured,
      IdentityFailureCode.networkUnavailable =>
        OrganizationMembershipSelfLeaveFailureCode.networkUnavailable,
      _ => OrganizationMembershipSelfLeaveFailureCode.unauthorized,
    },
  IdentitySuccess<IdentityAccessToken>() =>
    OrganizationMembershipSelfLeaveFailureCode.unauthorized,
};

final _uuidPattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  caseSensitive: false,
);
final _canonicalUtcPattern = RegExp(
  r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$',
);
