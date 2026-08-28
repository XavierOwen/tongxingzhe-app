import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../foundation/backend_base_uri.dart';
import '../../identity/identity_session.dart';
import 'relationship_stage_change_summary.dart';

const _backendBaseUrl = String.fromEnvironment('BACKEND_BASE_URL');
const _path = '/v1/personal/relationship-stage-change-summary';

PersonalRelationshipStageChangeSummaryGateway
productionPersonalRelationshipStageChangeSummaryGateway(
  IdentitySession identitySession,
) {
  if (_backendBaseUrl.trim().isEmpty) {
    return const DeferredPersonalRelationshipStageChangeSummaryGateway();
  }
  return HttpPersonalRelationshipStageChangeSummaryGateway(
    baseUri: Uri.parse(_backendBaseUrl),
    identitySession: identitySession,
    client: http.Client(),
  );
}

final class DeferredPersonalRelationshipStageChangeSummaryGateway
    implements PersonalRelationshipStageChangeSummaryGateway {
  const DeferredPersonalRelationshipStageChangeSummaryGateway();

  @override
  Future<PersonalRelationshipStageChangeSummaryGatewayResult> load({
    required String projectId,
    required DateTime fromUtc,
    required DateTime untilUtc,
  }) async => const PersonalRelationshipStageChangeSummaryGatewayRejected(
    PersonalRelationshipStageChangeSummaryFailureCode.notConfigured,
  );

  @override
  Future<void> close() async {}
}

/// Typed HTTP adapter for the personal stage-change aggregate.
///
/// The backend derives actor, workspace, and current project from the trusted
/// identity context. [projectId] is only a client-side scope expectation; it
/// is never sent as a query parameter.
final class HttpPersonalRelationshipStageChangeSummaryGateway
    implements PersonalRelationshipStageChangeSummaryGateway {
  factory HttpPersonalRelationshipStageChangeSummaryGateway({
    required Uri baseUri,
    required IdentitySession identitySession,
    required http.Client client,
    Duration timeout = const Duration(seconds: 15),
    DateTime Function() now = _utcNow,
  }) => HttpPersonalRelationshipStageChangeSummaryGateway._(
    baseUri: validatePathlessBackendBaseUri(baseUri),
    identitySession: identitySession,
    client: client,
    timeout: timeout,
    now: now,
  );

  const HttpPersonalRelationshipStageChangeSummaryGateway._({
    required this.baseUri,
    required this.identitySession,
    required this.client,
    required this.timeout,
    required this.now,
  });

  final Uri baseUri;
  final IdentitySession identitySession;
  final http.Client client;
  final Duration timeout;
  final DateTime Function() now;

  @override
  Future<PersonalRelationshipStageChangeSummaryGatewayResult> load({
    required String projectId,
    required DateTime fromUtc,
    required DateTime untilUtc,
  }) async {
    if (!_isUuid(projectId) || !_validPeriod(fromUtc, untilUtc)) {
      return const PersonalRelationshipStageChangeSummaryGatewayRejected(
        PersonalRelationshipStageChangeSummaryFailureCode.invalidRequest,
      );
    }
    final expectedProjectId = projectId.trim().toLowerCase();
    final expectedFrom = _canonicalUtc(fromUtc);
    final expectedUntil = _canonicalUtc(untilUtc);
    try {
      var access = await identitySession.accessToken();
      if (access is! IdentitySuccess<IdentityAccessToken>) {
        return PersonalRelationshipStageChangeSummaryGatewayRejected(
          _identityFailure(access),
        );
      }

      var response = await _send(
        access.value,
        fromUtc: expectedFrom,
        untilUtc: expectedUntil,
      ).timeout(timeout);
      if (response.statusCode == 401) {
        access = await identitySession.accessToken(forceRefresh: true);
        if (access is! IdentitySuccess<IdentityAccessToken>) {
          return PersonalRelationshipStageChangeSummaryGatewayRejected(
            _identityFailure(access),
          );
        }
        response = await _send(
          access.value,
          fromUtc: expectedFrom,
          untilUtc: expectedUntil,
        ).timeout(timeout);
      }

      final failure = _httpFailure(response.statusCode);
      if (failure != null) {
        return PersonalRelationshipStageChangeSummaryGatewayRejected(failure);
      }

      final envelope = _object(jsonDecode(response.body));
      _requireExactKeys(envelope, const ['result']);
      final summary = _parseResult(
        envelope['result'],
        expectedProjectId: expectedProjectId,
        expectedFrom: expectedFrom,
        expectedUntil: expectedUntil,
        retrievedAtUtc: now().toUtc(),
      );
      return PersonalRelationshipStageChangeSummaryGatewaySuccess(summary);
    } on TimeoutException {
      return const PersonalRelationshipStageChangeSummaryGatewayRejected(
        PersonalRelationshipStageChangeSummaryFailureCode.networkUnavailable,
      );
    } on http.ClientException {
      return const PersonalRelationshipStageChangeSummaryGatewayRejected(
        PersonalRelationshipStageChangeSummaryFailureCode.networkUnavailable,
      );
    } on FormatException {
      return const PersonalRelationshipStageChangeSummaryGatewayRejected(
        PersonalRelationshipStageChangeSummaryFailureCode.invalidResponse,
      );
    } on ArgumentError {
      return const PersonalRelationshipStageChangeSummaryGatewayRejected(
        PersonalRelationshipStageChangeSummaryFailureCode.invalidResponse,
      );
    } on StateError {
      return const PersonalRelationshipStageChangeSummaryGatewayRejected(
        PersonalRelationshipStageChangeSummaryFailureCode.invalidResponse,
      );
    }
  }

  Future<http.Response> _send(
    IdentityAccessToken token, {
    required String fromUtc,
    required String untilUtc,
  }) {
    final endpoint = baseUri
        .resolve(_path)
        .replace(queryParameters: {'from_utc': fromUtc, 'until_utc': untilUtc});
    return client.get(
      endpoint,
      headers: {
        'accept': 'application/json',
        'authorization': 'Bearer ${token.value}',
      },
    );
  }

  @override
  Future<void> close() async => client.close();
}

PersonalRelationshipStageChangeSummary _parseResult(
  Object? value, {
  required String expectedProjectId,
  required String expectedFrom,
  required String expectedUntil,
  required DateTime retrievedAtUtc,
}) {
  final root = _object(value);
  _requireExactKeys(root, const [
    'contract_id',
    'project_id',
    'time_basis',
    'period',
    'data_cutoff_utc',
    'authorized_at_utc',
    'value',
  ]);
  if (root['contract_id'] != personalRelationshipStageChangeSummaryContract ||
      root['time_basis'] != personalRelationshipStageChangeSummaryTimeBasis ||
      _uuid(root['project_id']) != expectedProjectId) {
    throw const FormatException('invalid relationship stage change identity');
  }

  final period = _object(root['period']);
  _requireExactKeys(period, const ['from_utc', 'until_utc']);
  final fromUtc = _utcTimestamp(period['from_utc']);
  final untilUtc = _utcTimestamp(period['until_utc']);
  if (_canonicalUtc(fromUtc) != expectedFrom ||
      _canonicalUtc(untilUtc) != expectedUntil) {
    throw const FormatException('relationship stage change period drifted');
  }

  final dataCutoffUtc = _utcTimestamp(root['data_cutoff_utc']);
  final authorizedAtUtc = _utcTimestamp(root['authorized_at_utc']);
  if (!retrievedAtUtc.isUtc ||
      dataCutoffUtc != authorizedAtUtc ||
      dataCutoffUtc.isAfter(retrievedAtUtc)) {
    throw const FormatException('invalid relationship stage change cutoff');
  }

  final metricValue = _object(root['value']);
  _requireExactKeys(metricValue, const [
    'event_count',
    'distinct_relationship_count',
    'upward_count',
    'downward_count',
  ]);
  final eventCount = _safeCount(metricValue['event_count']);
  final distinctRelationshipCount = _safeCount(
    metricValue['distinct_relationship_count'],
  );
  final upwardCount = _safeCount(metricValue['upward_count']);
  final downwardCount = _safeCount(metricValue['downward_count']);
  final directionTotal = BigInt.from(upwardCount) + BigInt.from(downwardCount);
  if (directionTotal > BigInt.from(_maximumSafeInteger) ||
      eventCount != directionTotal.toInt() ||
      distinctRelationshipCount > eventCount) {
    throw const FormatException('invalid relationship stage change value');
  }

  return PersonalRelationshipStageChangeSummary.fromCounts(
    projectId: expectedProjectId,
    fromUtc: fromUtc,
    untilUtc: untilUtc,
    dataCutoffUtc: dataCutoffUtc,
    authorizedAtUtc: authorizedAtUtc,
    retrievedAtUtc: retrievedAtUtc,
    eventCount: eventCount,
    distinctRelationshipCount: distinctRelationshipCount,
    upwardCount: upwardCount,
    downwardCount: downwardCount,
  );
}

PersonalRelationshipStageChangeSummaryFailureCode _identityFailure(
  IdentityResult<IdentityAccessToken> result,
) => switch (result) {
  IdentityRejected<IdentityAccessToken>(:final failure) =>
    switch (failure.code) {
      IdentityFailureCode.notConfigured =>
        PersonalRelationshipStageChangeSummaryFailureCode.notConfigured,
      IdentityFailureCode.networkUnavailable =>
        PersonalRelationshipStageChangeSummaryFailureCode.networkUnavailable,
      _ => PersonalRelationshipStageChangeSummaryFailureCode.unauthorized,
    },
  IdentitySuccess<IdentityAccessToken>() =>
    PersonalRelationshipStageChangeSummaryFailureCode.unauthorized,
};

PersonalRelationshipStageChangeSummaryFailureCode? _httpFailure(
  int statusCode,
) => switch (statusCode) {
  >= 200 && < 300 => null,
  400 => PersonalRelationshipStageChangeSummaryFailureCode.invalidRequest,
  401 => PersonalRelationshipStageChangeSummaryFailureCode.unauthorized,
  403 => PersonalRelationshipStageChangeSummaryFailureCode.forbidden,
  408 => PersonalRelationshipStageChangeSummaryFailureCode.networkUnavailable,
  >= 500 =>
    PersonalRelationshipStageChangeSummaryFailureCode.serviceUnavailable,
  _ => PersonalRelationshipStageChangeSummaryFailureCode.serverRejected,
};

Map<String, Object?> _object(Object? value) {
  if (value is! Map) throw const FormatException('expected JSON object');
  return value.map<String, Object?>((key, value) {
    if (key is! String) throw const FormatException('JSON key is not text');
    return MapEntry(key, value);
  });
}

void _requireExactKeys(Map<String, Object?> value, List<String> expected) {
  final keys = expected.toSet();
  if (value.length != keys.length || !value.keys.every(keys.contains)) {
    throw const FormatException('unexpected relationship stage change field');
  }
}

int _safeCount(Object? value) {
  if (value is! int || value < 0 || value > _maximumSafeInteger) {
    throw const FormatException('invalid relationship stage change count');
  }
  return value;
}

String _uuid(Object? value) {
  if (value is! String || !_isUuid(value)) {
    throw const FormatException('expected relationship stage change UUID');
  }
  return value.toLowerCase();
}

bool _isUuid(String value) => _uuidPattern.hasMatch(value);

bool _validPeriod(DateTime fromUtc, DateTime untilUtc) =>
    fromUtc.isUtc &&
    untilUtc.isUtc &&
    fromUtc.microsecond == 0 &&
    untilUtc.microsecond == 0 &&
    fromUtc.isBefore(untilUtc);

DateTime _utcTimestamp(Object? value) {
  if (value is! String || !_canonicalUtcPattern.hasMatch(value)) {
    throw const FormatException('expected canonical UTC timestamp');
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null || !parsed.isUtc || parsed.microsecond != 0) {
    throw const FormatException('expected canonical UTC timestamp');
  }
  return parsed;
}

String _canonicalUtc(DateTime value) => value.toIso8601String();

DateTime _utcNow() => DateTime.now().toUtc();

final _uuidPattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  caseSensitive: false,
);
final _canonicalUtcPattern = RegExp(
  r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$',
);
const _maximumSafeInteger = 9007199254740991;
