import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../foundation/backend_base_uri.dart';
import '../identity/identity_session.dart';
import 'organization_deletion_recovery.dart';

const _backendBaseUrl = String.fromEnvironment('BACKEND_BASE_URL');
const _directoryPath = '/v1/organizations/deletion-recovery';
const _deletionContractId = 'organization-deletion-request:v1';
const _restorationContractId = 'organization-deletion-restore:v1';
const _directoryContractId = 'organization-deletion-recovery-directory:v1';
const _eligibilityContractId = 'organization-deletion-eligibility:v1';
final _uuidPattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  caseSensitive: false,
);
final _utcMicrosecondPattern = RegExp(
  r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{6}Z$',
);

OrganizationDeletionRecoveryGateway
productionOrganizationDeletionRecoveryGateway(IdentitySession identitySession) {
  final configured = _backendBaseUrl.trim();
  if (configured.isEmpty) {
    return const DeferredOrganizationDeletionRecoveryGateway();
  }
  final baseUri = validatePathlessBackendBaseUri(Uri.parse(configured));
  return HttpOrganizationDeletionRecoveryGateway(
    baseUri: baseUri,
    identitySession: identitySession,
    client: http.Client(),
  );
}

final class HttpOrganizationDeletionRecoveryGateway
    implements OrganizationDeletionRecoveryGateway {
  factory HttpOrganizationDeletionRecoveryGateway({
    required Uri baseUri,
    required IdentitySession identitySession,
    required http.Client client,
    Duration timeout = const Duration(seconds: 15),
  }) => HttpOrganizationDeletionRecoveryGateway._(
    baseUri: validatePathlessBackendBaseUri(baseUri),
    identitySession: identitySession,
    client: client,
    timeout: timeout,
  );

  HttpOrganizationDeletionRecoveryGateway._({
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
  Future<OrganizationDeletionRecoveryResult<List<String>>>
  listDeletionEligibleOrganizations() => _request(
    method: 'GET',
    url: baseUri.resolve('/v1/organizations/deletion-eligibility'),
    body: null,
    parseSuccess: _parseEligibility,
    expectedErrors: const {
      'invalid_organization_deletion_eligibility_request':
          OrganizationDeletionRecoveryFailureCode.invalidRequest,
      'organization_deletion_eligibility_forbidden':
          OrganizationDeletionRecoveryFailureCode.forbidden,
      'organization_deletion_eligibility_unavailable':
          OrganizationDeletionRecoveryFailureCode.serviceUnavailable,
    },
  );

  @override
  Future<
    OrganizationDeletionRecoveryResult<OrganizationDeletionRecoveryDirectory>
  >
  listRecoverableOrganizations() => _request(
    method: 'GET',
    url: baseUri.resolve(_directoryPath),
    body: null,
    parseSuccess: (root) => _parseDirectory(root),
    expectedErrors: const {
      'invalid_organization_deletion_recovery_directory_request':
          OrganizationDeletionRecoveryFailureCode.invalidRequest,
      'organization_deletion_recovery_directory_forbidden':
          OrganizationDeletionRecoveryFailureCode.forbidden,
      'organization_deletion_recovery_directory_unavailable':
          OrganizationDeletionRecoveryFailureCode.serviceUnavailable,
    },
  );

  @override
  Future<OrganizationDeletionRecoveryResult<OrganizationDeletionRequestReceipt>>
  requestDeletion({
    required String requestId,
    required String organizationWorkspaceId,
  }) {
    final request = _inputUuid(requestId);
    final workspace = _inputUuid(organizationWorkspaceId);
    if (request == null || workspace == null) {
      return Future.value(_invalid<OrganizationDeletionRequestReceipt>());
    }
    return _request<OrganizationDeletionRequestReceipt>(
      method: 'POST',
      url: baseUri.resolve('/v1/organizations/$workspace/deletion-requests'),
      body: jsonEncode({'request_id': request}),
      parseSuccess: (root) => _parseDeletionReceipt(root, workspace, request),
      expectedErrors: const {
        'invalid_organization_deletion_request':
            OrganizationDeletionRecoveryFailureCode.invalidRequest,
        'organization_deletion_forbidden':
            OrganizationDeletionRecoveryFailureCode.forbidden,
        'organization_deletion_conflict':
            OrganizationDeletionRecoveryFailureCode.conflict,
        'organization_deletion_unavailable':
            OrganizationDeletionRecoveryFailureCode.serviceUnavailable,
      },
    );
  }

  @override
  Future<OrganizationDeletionRecoveryResult<OrganizationRestorationReceipt>>
  restore({
    required String requestId,
    required String organizationWorkspaceId,
    required String deletionRequestId,
  }) {
    final request = _inputUuid(requestId);
    final workspace = _inputUuid(organizationWorkspaceId);
    final deletion = _inputUuid(deletionRequestId);
    if (request == null || workspace == null || deletion == null) {
      return Future.value(_invalid<OrganizationRestorationReceipt>());
    }
    return _request<OrganizationRestorationReceipt>(
      method: 'POST',
      url: baseUri.resolve('/v1/organizations/$workspace/restorations'),
      body: jsonEncode({
        'request_id': request,
        'deletion_request_id': deletion,
      }),
      parseSuccess: (root) =>
          _parseRestorationReceipt(root, workspace, deletion),
      expectedErrors: const {
        'invalid_organization_restoration_request':
            OrganizationDeletionRecoveryFailureCode.invalidRequest,
        'organization_restoration_forbidden':
            OrganizationDeletionRecoveryFailureCode.forbidden,
        'organization_restoration_conflict':
            OrganizationDeletionRecoveryFailureCode.conflict,
        'organization_restoration_unavailable':
            OrganizationDeletionRecoveryFailureCode.serviceUnavailable,
      },
    );
  }

  Future<OrganizationDeletionRecoveryResult<T>> _request<T>({
    required String method,
    required Uri url,
    required String? body,
    required T Function(Map<String, Object?>) parseSuccess,
    required Map<String, OrganizationDeletionRecoveryFailureCode>
    expectedErrors,
  }) async {
    StreamSubscription<IdentitySnapshot>? subscription;
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

    const unauthorized = OrganizationDeletionRecoveryRejected<Object?>(
      OrganizationDeletionRecoveryFailureCode.unauthorized,
    );
    try {
      subject = identitySession.current.principal?.externalSubject;
      if (!isCurrent()) return _rejected<T>(unauthorized.code);
      subscription = identitySession.changes.listen(
        (snapshot) {
          if (!matches(snapshot)) identityChanged = true;
        },
        onError: (Object error, StackTrace stackTrace) =>
            identityChanged = true,
        onDone: () => identityChanged = true,
      );
      if (!isCurrent()) return _rejected<T>(unauthorized.code);
      var access = await identitySession.accessToken();
      if (!isCurrent()) return _rejected<T>(unauthorized.code);
      if (access is! IdentitySuccess<IdentityAccessToken>) {
        return _rejected<T>(_identityFailure(access));
      }
      var response = await _send(method, url, body, access.value);
      if (!isCurrent()) return _rejected<T>(unauthorized.code);
      var root = _jsonObject(response);
      if (response.statusCode == 401) {
        if (_failure(response.statusCode, root, expectedErrors) !=
            OrganizationDeletionRecoveryFailureCode.unauthorized) {
          return _rejected<T>(
            OrganizationDeletionRecoveryFailureCode.invalidResponse,
          );
        }
        access = await identitySession.accessToken(forceRefresh: true);
        if (!isCurrent()) return _rejected<T>(unauthorized.code);
        if (access is! IdentitySuccess<IdentityAccessToken>) {
          return _rejected<T>(_identityFailure(access));
        }
        response = await _send(method, url, body, access.value);
        if (!isCurrent()) return _rejected<T>(unauthorized.code);
        root = _jsonObject(response);
      }
      final result = response.statusCode == 200
          ? OrganizationDeletionRecoverySuccess<T>(parseSuccess(root))
          : _rejected<T>(_failure(response.statusCode, root, expectedErrors));
      return isCurrent() ? result : _rejected<T>(unauthorized.code);
    } on TimeoutException {
      return _rejected<T>(
        fenceWasBroken()
            ? unauthorized.code
            : OrganizationDeletionRecoveryFailureCode.networkUnavailable,
      );
    } on http.ClientException {
      return _rejected<T>(
        fenceWasBroken()
            ? unauthorized.code
            : OrganizationDeletionRecoveryFailureCode.networkUnavailable,
      );
    } on FormatException {
      return _rejected<T>(
        fenceWasBroken()
            ? unauthorized.code
            : OrganizationDeletionRecoveryFailureCode.invalidResponse,
      );
    } on Object {
      return _rejected<T>(
        fenceWasBroken()
            ? unauthorized.code
            : OrganizationDeletionRecoveryFailureCode.invalidResponse,
      );
    } finally {
      subscription?.cancel().ignore();
    }
  }

  Future<http.Response> _send(
    String method,
    Uri url,
    String? body,
    IdentityAccessToken token,
  ) {
    final headers = {
      'accept': 'application/json',
      'authorization': 'Bearer ${token.value}',
      if (body != null) 'content-type': 'application/json; charset=utf-8',
    };
    final request = http.Request(method, url)..headers.addAll(headers);
    if (body != null) request.body = body;
    return client.send(request).then(http.Response.fromStream).timeout(timeout);
  }

  OrganizationDeletionRecoveryResult<T> _invalid<T>() =>
      _rejected<T>(OrganizationDeletionRecoveryFailureCode.invalidRequest);

  OrganizationDeletionRecoveryRejected<T> _rejected<T>(
    OrganizationDeletionRecoveryFailureCode code,
  ) => OrganizationDeletionRecoveryRejected<T>(code);

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    client.close();
  }
}

List<String> _parseEligibility(Map<String, Object?> root) {
  _requireExactKeys(root, const [
    'organization_deletion_eligibility_contract_id',
    'organization_workspace_ids',
  ]);
  final values = root['organization_workspace_ids'];
  if (root['organization_deletion_eligibility_contract_id'] !=
          _eligibilityContractId ||
      values is! List) {
    throw const FormatException();
  }
  final ids = values.map(_responseUuid).toList(growable: false);
  if (ids.toSet().length != ids.length) throw const FormatException();
  return List.unmodifiable(ids);
}

OrganizationDeletionRecoveryDirectory _parseDirectory(
  Map<String, Object?> root,
) {
  _requireExactKeys(root, const [
    'organization_deletion_recovery_directory_contract_id',
    'items',
  ]);
  if (root['organization_deletion_recovery_directory_contract_id'] !=
          _directoryContractId ||
      root['items'] is! List) {
    throw const FormatException();
  }
  final items = (root['items'] as List)
      .map((value) {
        final item = _object(value);
        _requireExactKeys(item, const [
          'organization_workspace_id',
          'deletion_request_id',
          'display_name',
          'observed_at_utc',
          'effective_at_utc',
          'purge_after_utc',
          'status',
        ]);
        final workspace = _responseUuid(item['organization_workspace_id']);
        final deletion = _responseUuid(item['deletion_request_id']);
        final observed = _timestamp(item['observed_at_utc']);
        final effective = _timestamp(item['effective_at_utc']);
        final purge = _timestamp(item['purge_after_utc']);
        final name = item['display_name'];
        if (item['status'] != 'deletion_pending' ||
            name is! String ||
            name.trim().isEmpty ||
            observed == null ||
            effective == null ||
            purge == null ||
            effective.$2 >= purge.$2 ||
            observed.$2 < effective.$2 ||
            observed.$2 >= purge.$2) {
          throw const FormatException();
        }
        return OrganizationDeletionRecoveryItem(
          organizationWorkspaceId: workspace,
          deletionRequestId: deletion,
          displayName: name,
          observedAtUtc: observed.$1,
          effectiveAtUtc: effective.$1,
          purgeAfterUtc: purge.$1,
        );
      })
      .toList(growable: false);
  final seen = <String>{};
  String? observed;
  for (final item in items) {
    if (!seen.add(item.organizationWorkspaceId) ||
        (observed != null && observed != item.observedAtUtc)) {
      throw const FormatException();
    }
    observed = item.observedAtUtc;
  }
  return OrganizationDeletionRecoveryDirectory(items: items);
}

OrganizationDeletionRequestReceipt _parseDeletionReceipt(
  Map<String, Object?> root,
  String workspace,
  String request,
) {
  _requireExactKeys(root, const [
    'organization_deletion_contract_id',
    'organization_workspace_id',
    'deletion_request_id',
    'effective_at_utc',
    'purge_after_utc',
  ]);
  final effective = _timestamp(root['effective_at_utc']);
  final purge = _timestamp(root['purge_after_utc']);
  if (root['organization_deletion_contract_id'] != _deletionContractId ||
      _responseUuid(root['organization_workspace_id']) != workspace ||
      _responseUuid(root['deletion_request_id']) != request ||
      effective == null ||
      purge == null ||
      effective.$2 >= purge.$2) {
    throw const FormatException();
  }
  return OrganizationDeletionRequestReceipt(
    organizationWorkspaceId: workspace,
    deletionRequestId: request,
    effectiveAtUtc: effective.$1,
    purgeAfterUtc: purge.$1,
  );
}

OrganizationRestorationReceipt _parseRestorationReceipt(
  Map<String, Object?> root,
  String workspace,
  String deletion,
) {
  _requireExactKeys(root, const [
    'organization_deletion_restore_contract_id',
    'organization_workspace_id',
    'deletion_request_id',
    'restored_at_utc',
  ]);
  final restored = _timestamp(root['restored_at_utc']);
  if (root['organization_deletion_restore_contract_id'] !=
          _restorationContractId ||
      _responseUuid(root['organization_workspace_id']) != workspace ||
      _responseUuid(root['deletion_request_id']) != deletion ||
      restored == null) {
    throw const FormatException();
  }
  return OrganizationRestorationReceipt(
    organizationWorkspaceId: workspace,
    deletionRequestId: deletion,
    restoredAtUtc: restored.$1,
  );
}

OrganizationDeletionRecoveryFailureCode _failure(
  int status,
  Map<String, Object?> root,
  Map<String, OrganizationDeletionRecoveryFailureCode> expectedErrors,
) {
  _requireExactKeys(root, const ['error']);
  final error = _object(root['error']);
  _requireExactKeys(error, const ['code']);
  final code = error['code'];
  if (code is! String || code.trim() != code || code.isEmpty) {
    throw const FormatException();
  }
  if (status == 401 && code == 'unauthenticated') {
    return OrganizationDeletionRecoveryFailureCode.unauthorized;
  }
  if (expectedErrors.containsKey(code) &&
      ((status == 400 &&
              expectedErrors[code] ==
                  OrganizationDeletionRecoveryFailureCode.invalidRequest) ||
          (status == 403 &&
              expectedErrors[code] ==
                  OrganizationDeletionRecoveryFailureCode.forbidden) ||
          (status == 409 &&
              expectedErrors[code] ==
                  OrganizationDeletionRecoveryFailureCode.conflict) ||
          (status == 503 &&
              expectedErrors[code] ==
                  OrganizationDeletionRecoveryFailureCode
                      .serviceUnavailable))) {
    return expectedErrors[code]!;
  }
  throw const FormatException();
}

Map<String, Object?> _jsonObject(http.Response response) {
  final contentType = _header(
    response,
    'content-type',
  ).split(';').map((value) => value.trim().toLowerCase()).toList();
  if (contentType.length != 2 ||
      contentType[0] != 'application/json' ||
      contentType[1] != 'charset=utf-8' ||
      _header(response, 'cache-control').trim() != 'no-store') {
    throw const FormatException();
  }
  return _object(jsonDecode(response.body));
}

String _header(http.Response response, String name) => response.headers.entries
    .firstWhere(
      (entry) => entry.key.toLowerCase() == name,
      orElse: () => throw const FormatException(),
    )
    .value;

Map<String, Object?> _object(Object? value) {
  if (value is! Map) throw const FormatException();
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    if (entry.key is! String) throw const FormatException();
    result[entry.key as String] = entry.value;
  }
  return result;
}

void _requireExactKeys(Map<String, Object?> value, List<String> expected) {
  final set = expected.toSet();
  if (value.length != set.length || !value.keys.every(set.contains)) {
    throw const FormatException();
  }
}

String? _inputUuid(String value) =>
    _uuidPattern.hasMatch(value) ? value.toLowerCase() : null;

String _responseUuid(Object? value) {
  if (value is! String ||
      !_uuidPattern.hasMatch(value) ||
      value != value.toLowerCase()) {
    throw const FormatException();
  }
  return value;
}

(String, BigInt)? _timestamp(Object? value) {
  if (value is! String || !_utcMicrosecondPattern.hasMatch(value)) return null;
  final y = int.parse(value.substring(0, 4));
  final m = int.parse(value.substring(5, 7));
  final d = int.parse(value.substring(8, 10));
  final hour = int.parse(value.substring(11, 13));
  final minute = int.parse(value.substring(14, 16));
  final second = int.parse(value.substring(17, 19));
  final micros = int.parse(value.substring(20, 26));
  if (y < 1 || m < 1 || m > 12 || hour > 23 || minute > 59 || second > 59) {
    return null;
  }
  final date = DateTime.utc(y, m, d, hour, minute, second);
  if (date.year != y || date.month != m || date.day != d) return null;
  return (
    value,
    BigInt.from(date.millisecondsSinceEpoch ~/ 1000) * BigInt.from(1000000) +
        BigInt.from(micros),
  );
}

OrganizationDeletionRecoveryFailureCode _identityFailure(
  IdentityResult<IdentityAccessToken> result,
) => switch (result) {
  IdentityRejected<IdentityAccessToken>(:final failure) =>
    switch (failure.code) {
      IdentityFailureCode.notConfigured =>
        OrganizationDeletionRecoveryFailureCode.notConfigured,
      IdentityFailureCode.networkUnavailable =>
        OrganizationDeletionRecoveryFailureCode.networkUnavailable,
      _ => OrganizationDeletionRecoveryFailureCode.unauthorized,
    },
  IdentitySuccess<IdentityAccessToken>() =>
    OrganizationDeletionRecoveryFailureCode.unauthorized,
};
