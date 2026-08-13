import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../identity/identity_session.dart';
import 'current_relationship_stage.dart';
import 'metric_contract.dart';

const _backendBaseUrl = String.fromEnvironment('BACKEND_BASE_URL');
const _defaultPath = '/v1/personal/current-relationship-stage';

CurrentRelationshipStageGateway productionCurrentRelationshipStageGateway(
  IdentitySession identitySession,
) {
  if (_backendBaseUrl.trim().isEmpty) {
    return const DeferredCurrentRelationshipStageGateway();
  }
  return HttpCurrentRelationshipStageGateway(
    baseUri: Uri.parse(_backendBaseUrl),
    identitySession: identitySession,
    client: http.Client(),
  );
}

final class DeferredCurrentRelationshipStageGateway
    implements CurrentRelationshipStageGateway {
  const DeferredCurrentRelationshipStageGateway();

  @override
  Future<void> close() async {}

  @override
  Future<CurrentRelationshipStageGatewayResult> load({
    required CurrentRelationshipStageScope scope,
  }) async => const CurrentRelationshipStageGatewayRejected(
    CurrentRelationshipStageGatewayFailureCode.notConfigured,
  );
}

/// 只负责短期 bearer、协议解码和一次性认证刷新；它不保存 PII，也不把
/// 服务端返回的宽字段透传到领域模型。
final class HttpCurrentRelationshipStageGateway
    implements CurrentRelationshipStageGateway {
  factory HttpCurrentRelationshipStageGateway({
    required Uri baseUri,
    required IdentitySession identitySession,
    required http.Client client,
    Duration timeout = const Duration(seconds: 15),
    String path = _defaultPath,
    DateTime Function() now = _utcNow,
  }) => HttpCurrentRelationshipStageGateway._(
    baseUri: _validatedBaseUri(baseUri),
    identitySession: identitySession,
    client: client,
    timeout: timeout,
    path: _validatedPath(path),
    now: now,
  );

  const HttpCurrentRelationshipStageGateway._({
    required this._baseUri,
    required this._identitySession,
    required this._client,
    required this._timeout,
    required this._path,
    required this._now,
  });

  final Uri _baseUri;
  final IdentitySession _identitySession;
  final http.Client _client;
  final Duration _timeout;
  final String _path;
  final DateTime Function() _now;

  @override
  Future<CurrentRelationshipStageGatewayResult> load({
    required CurrentRelationshipStageScope scope,
  }) async {
    try {
      var access = await _identitySession.accessToken();
      if (access is! IdentitySuccess<IdentityAccessToken>) {
        return CurrentRelationshipStageGatewayRejected(
          _identityFailureCode(access),
        );
      }

      var response = await _send(access.value).timeout(_timeout);
      if (response.statusCode == 401) {
        // 401 只触发一次强制刷新；刷新失败或第二次 401 都停止。
        access = await _identitySession.accessToken(forceRefresh: true);
        if (access is! IdentitySuccess<IdentityAccessToken>) {
          return CurrentRelationshipStageGatewayRejected(
            _identityFailureCode(access),
          );
        }
        response = await _send(access.value).timeout(_timeout);
      }
      if (response.statusCode == 401) {
        return const CurrentRelationshipStageGatewayRejected(
          CurrentRelationshipStageGatewayFailureCode.unauthorized,
        );
      }
      if (response.statusCode == 403) {
        return const CurrentRelationshipStageGatewayRejected(
          CurrentRelationshipStageGatewayFailureCode.forbidden,
        );
      }
      if (response.statusCode >= 500 || response.statusCode == 408) {
        return const CurrentRelationshipStageGatewayRejected(
          CurrentRelationshipStageGatewayFailureCode.networkUnavailable,
        );
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return const CurrentRelationshipStageGatewayRejected(
          CurrentRelationshipStageGatewayFailureCode.serverRejected,
        );
      }

      final envelope = _object(jsonDecode(response.body));
      _requireExactKeys(envelope, const ['snapshot']);
      final root = _object(envelope['snapshot']);
      return CurrentRelationshipStageGatewaySuccess(
        _parseSnapshot(root, scope, receivedAtUtc: _now()),
      );
    } on TimeoutException {
      return const CurrentRelationshipStageGatewayRejected(
        CurrentRelationshipStageGatewayFailureCode.networkUnavailable,
      );
    } on http.ClientException {
      return const CurrentRelationshipStageGatewayRejected(
        CurrentRelationshipStageGatewayFailureCode.networkUnavailable,
      );
    } on FormatException {
      return const CurrentRelationshipStageGatewayRejected(
        CurrentRelationshipStageGatewayFailureCode.invalidResponse,
      );
    } on ArgumentError {
      return const CurrentRelationshipStageGatewayRejected(
        CurrentRelationshipStageGatewayFailureCode.invalidResponse,
      );
    } on StateError {
      return const CurrentRelationshipStageGatewayRejected(
        CurrentRelationshipStageGatewayFailureCode.invalidResponse,
      );
    }
  }

  Future<http.Response> _send(IdentityAccessToken access) => _client.get(
    _baseUri.resolve(_path),
    headers: {
      'accept': 'application/json',
      'authorization': 'Bearer ${access.value}',
    },
  );

  @override
  Future<void> close() async => _client.close();
}

CurrentRelationshipStageSnapshot _parseSnapshot(
  Map<String, Object?> root,
  CurrentRelationshipStageScope expectedScope, {
  required DateTime receivedAtUtc,
}) {
  _requireExactKeys(root, const [
    'contract_id',
    'statistical_unit',
    'project_key',
    'snapshot_as_of_utc',
    'source_cutoff_utc',
    'authorized_at_utc',
    'coverage',
    'relationships',
  ]);
  if (root['contract_id'] != 'current_relationship_stage_distribution@1' ||
      root['statistical_unit'] != 'targetProjectRelationship') {
    throw const FormatException(
      'invalid_current_relationship_metric_reference',
    );
  }
  final projectKey = _nonEmptyString(root['project_key']);
  if (projectKey != expectedScope.projectId) {
    throw const FormatException('current_relationship_snapshot_scope_mismatch');
  }
  final snapshotAsOfUtc = _utcTimestamp(root['snapshot_as_of_utc']);
  final sourceCutoff = _utcTimestamp(root['source_cutoff_utc']);
  final authorizedAt = _utcTimestamp(root['authorized_at_utc']);
  if (!receivedAtUtc.isUtc ||
      sourceCutoff.isAfter(snapshotAsOfUtc) ||
      authorizedAt.isAfter(snapshotAsOfUtc)) {
    throw const FormatException('invalid_current_relationship_snapshot_time');
  }
  final coverage = _parseCoverage(root['coverage']);
  final relationshipValues = _list(root['relationships']);
  final rows = relationshipValues
      .map((value) => _parseRow(value, expectedScope))
      .toList(growable: false);

  return CurrentRelationshipStageSnapshot(
    scope: expectedScope,
    snapshotAsOfUtc: snapshotAsOfUtc,
    sourceDataCutoffUtc: sourceCutoff,
    authorizedAtUtc: authorizedAt,
    lastSuccessfulSyncAtUtc: receivedAtUtc,
    coverage: coverage,
    rows: rows,
    freshness: MetricSourceFreshness.fresh(
      sourceDataCutoffUtc: sourceCutoff,
      authorizedAtUtc: authorizedAt,
      lastSuccessfulSyncAtUtc: receivedAtUtc,
    ),
  );
}

CurrentRelationshipStageCoverage _parseCoverage(Object? value) {
  final root = _object(value);
  _requireExactKeys(root, const ['total', 'pending']);
  return CurrentRelationshipStageCoverage.known(
    totalCount: _nonNegativeInteger(root['total']),
    pendingCount: _nonNegativeInteger(root['pending']),
  );
}

CurrentRelationshipStageRow _parseRow(
  Object? value,
  CurrentRelationshipStageScope expectedScope,
) {
  final root = _object(value);
  _requireExactKeys(root, const [
    'target_key',
    'stage',
    'revision',
    'updated_at_utc',
  ]);
  return CurrentRelationshipStageRow(
    targetId: _nonEmptyString(root['target_key']),
    relationshipProjectId: expectedScope.projectId,
    assignedAppUserId: expectedScope.appUserId,
    stage: _nonNegativeInteger(root['stage']),
    currentRevision: _positiveInteger(root['revision']),
    updatedAtUtc: _utcTimestamp(root['updated_at_utc']),
  );
}

CurrentRelationshipStageGatewayFailureCode _identityFailureCode(
  IdentityResult<IdentityAccessToken> result,
) => switch (result) {
  IdentityRejected<IdentityAccessToken>(:final failure) =>
    switch (failure.code) {
      IdentityFailureCode.notConfigured =>
        CurrentRelationshipStageGatewayFailureCode.notConfigured,
      IdentityFailureCode.networkUnavailable =>
        CurrentRelationshipStageGatewayFailureCode.networkUnavailable,
      _ => CurrentRelationshipStageGatewayFailureCode.unauthorized,
    },
  IdentitySuccess<IdentityAccessToken>() =>
    CurrentRelationshipStageGatewayFailureCode.unauthorized,
};

Map<String, Object?> _object(Object? value) {
  if (value is! Map) throw const FormatException('expected_json_object');
  return value.map<String, Object?>((key, value) {
    if (key is! String) throw const FormatException('json_key_not_string');
    return MapEntry(key, value);
  });
}

List<Object?> _list(Object? value) {
  if (value is! List) throw const FormatException('expected_json_list');
  return List<Object?>.from(value);
}

String _nonEmptyString(Object? value) {
  if (value is! String || value.trim().isEmpty) {
    throw const FormatException('expected_non_empty_string');
  }
  return value.trim();
}

int _positiveInteger(Object? value) {
  if (value is! int || value < 1) {
    throw const FormatException('expected_positive_integer');
  }
  return value;
}

int _nonNegativeInteger(Object? value) {
  if (value is! int || value < 0) {
    throw const FormatException('expected_non_negative_integer');
  }
  return value;
}

DateTime _utcTimestamp(Object? value) {
  if (value is! String) throw const FormatException('expected_utc_timestamp');
  final parsed = DateTime.tryParse(value);
  if (parsed == null || !parsed.isUtc) {
    throw const FormatException('expected_utc_timestamp');
  }
  return parsed;
}

void _requireExactKeys(Map<String, Object?> root, List<String> keys) {
  final expected = keys.toSet();
  if (root.length != expected.length || !root.keys.every(expected.contains)) {
    throw const FormatException('unexpected_current_relationship_json_key');
  }
}

Uri _validatedBaseUri(Uri value) {
  if (value.scheme != 'https' && value.scheme != 'http' ||
      value.host.isEmpty ||
      value.path.isNotEmpty && value.path != '/') {
    throw ArgumentError('invalid_backend_base_uri');
  }
  return value;
}

String _validatedPath(String value) {
  final path = value.trim();
  if (path.isEmpty || !path.startsWith('/') || path.contains('..')) {
    throw ArgumentError('invalid_current_relationship_gateway_path');
  }
  return path;
}

DateTime _utcNow() => DateTime.now().toUtc();
