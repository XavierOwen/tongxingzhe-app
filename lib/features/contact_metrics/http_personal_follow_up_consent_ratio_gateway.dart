import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../identity/identity_session.dart';
import 'personal_follow_up_consent_ratio.dart';

const _backendBaseUrl = String.fromEnvironment('BACKEND_BASE_URL');
const _path = '/v1/personal/follow-up-consent-ratio';

PersonalFollowUpConsentRatioGateway
productionPersonalFollowUpConsentRatioGateway(IdentitySession identitySession) {
  if (_backendBaseUrl.trim().isEmpty) {
    return const DeferredPersonalFollowUpConsentRatioGateway();
  }
  return HttpPersonalFollowUpConsentRatioGateway(
    baseUri: Uri.parse(_backendBaseUrl),
    identitySession: identitySession,
    client: http.Client(),
  );
}

final class DeferredPersonalFollowUpConsentRatioGateway
    implements PersonalFollowUpConsentRatioGateway {
  const DeferredPersonalFollowUpConsentRatioGateway();

  @override
  Future<PersonalFollowUpConsentRatioGatewayResult> load({
    required String projectId,
    required DateTime fromUtc,
    required DateTime untilUtc,
  }) async => const PersonalFollowUpConsentRatioGatewayRejected(
    PersonalFollowUpConsentRatioFailureCode.notConfigured,
  );

  @override
  Future<void> close() async {}
}

/// 只传 UTC 期间；Backend 从可信个人 session context 取得项目和固定指标。
final class HttpPersonalFollowUpConsentRatioGateway
    implements PersonalFollowUpConsentRatioGateway {
  factory HttpPersonalFollowUpConsentRatioGateway({
    required Uri baseUri,
    required IdentitySession identitySession,
    required http.Client client,
    Duration timeout = const Duration(seconds: 15),
    DateTime Function() now = _utcNow,
  }) => HttpPersonalFollowUpConsentRatioGateway._(
    baseUri: _validatedBaseUri(baseUri),
    identitySession: identitySession,
    client: client,
    timeout: timeout,
    now: now,
  );

  const HttpPersonalFollowUpConsentRatioGateway._({
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
  Future<PersonalFollowUpConsentRatioGatewayResult> load({
    required String projectId,
    required DateTime fromUtc,
    required DateTime untilUtc,
  }) async {
    if (!_isUuid(projectId) || !_validPeriod(fromUtc, untilUtc)) {
      return const PersonalFollowUpConsentRatioGatewayRejected(
        PersonalFollowUpConsentRatioFailureCode.invalidRequest,
      );
    }
    final expectedProjectId = projectId.toLowerCase();
    final expectedFrom = _canonicalUtc(fromUtc);
    final expectedUntil = _canonicalUtc(untilUtc);
    try {
      var access = await identitySession.accessToken();
      if (access is! IdentitySuccess<IdentityAccessToken>) {
        return PersonalFollowUpConsentRatioGatewayRejected(
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
          return PersonalFollowUpConsentRatioGatewayRejected(
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
        return PersonalFollowUpConsentRatioGatewayRejected(failure);
      }
      final envelope = _object(jsonDecode(response.body));
      _requireExactKeys(envelope, const ['result']);
      final value = _parseResult(
        envelope['result'],
        expectedProjectId: expectedProjectId,
        expectedFrom: expectedFrom,
        expectedUntil: expectedUntil,
        retrievedAtUtc: now().toUtc(),
      );
      return PersonalFollowUpConsentRatioGatewaySuccess(value);
    } on TimeoutException {
      return const PersonalFollowUpConsentRatioGatewayRejected(
        PersonalFollowUpConsentRatioFailureCode.networkUnavailable,
      );
    } on http.ClientException {
      return const PersonalFollowUpConsentRatioGatewayRejected(
        PersonalFollowUpConsentRatioFailureCode.networkUnavailable,
      );
    } on FormatException {
      return const PersonalFollowUpConsentRatioGatewayRejected(
        PersonalFollowUpConsentRatioFailureCode.invalidResponse,
      );
    } on ArgumentError {
      return const PersonalFollowUpConsentRatioGatewayRejected(
        PersonalFollowUpConsentRatioFailureCode.invalidResponse,
      );
    } on StateError {
      return const PersonalFollowUpConsentRatioGatewayRejected(
        PersonalFollowUpConsentRatioFailureCode.invalidResponse,
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

PersonalFollowUpConsentRatioResult _parseResult(
  Object? value, {
  required String expectedProjectId,
  required String expectedFrom,
  required String expectedUntil,
  required DateTime retrievedAtUtc,
}) {
  final root = _object(value);
  const commonKeys = ['contract_id', 'metric_id', 'project_id', 'status'];
  if (root['contract_id'] != personalFollowUpConsentRatioContract ||
      root['metric_id'] != personalFollowUpConsentRatioMetricId ||
      _uuid(root['project_id']) != expectedProjectId) {
    throw const FormatException('invalid consent ratio identity');
  }
  if (root['status'] == 'not_enabled') {
    _requireExactKeys(root, commonKeys);
    return PersonalFollowUpConsentRatioNotEnabled(projectId: expectedProjectId);
  }
  if (root['status'] != 'ready') {
    throw const FormatException('invalid consent ratio status');
  }
  _requireExactKeys(root, const [...commonKeys, 'period', 'value']);

  final period = _object(root['period']);
  _requireExactKeys(period, const ['from_utc', 'until_utc']);
  final from = _utcTimestamp(period['from_utc']);
  final until = _utcTimestamp(period['until_utc']);
  if (_canonicalUtc(from) != expectedFrom ||
      _canonicalUtc(until) != expectedUntil) {
    throw const FormatException('consent ratio period drifted');
  }

  final metricValue = _object(root['value']);
  _requireExactKeys(metricValue, const [
    'yes_count',
    'no_count',
    'numerator',
    'unknown_count',
    'refused_count',
    'not_applicable_count',
    'unanswered_count',
    'excluded_count',
    'denominator',
    'percentage_basis_points',
  ]);
  final percentageBasisPoints = metricValue['percentage_basis_points'];
  if (percentageBasisPoints != null &&
      (percentageBasisPoints is! int ||
          percentageBasisPoints < 0 ||
          percentageBasisPoints > 10000)) {
    throw const FormatException('invalid consent ratio basis points');
  }
  final yesCount = _safeCount(metricValue['yes_count']);
  final noCount = _safeCount(metricValue['no_count']);
  final expectedBasisPoints = _expectedBasisPoints(yesCount, noCount);
  if (percentageBasisPoints != expectedBasisPoints) {
    throw const FormatException('inconsistent consent ratio basis points');
  }
  final metric = consentRatioMetricResult(
    fromUtc: from,
    untilUtc: until,
    retrievedAtUtc: retrievedAtUtc,
    yesCount: yesCount,
    noCount: noCount,
    numerator: _safeCount(metricValue['numerator']),
    unknownCount: _safeCount(metricValue['unknown_count']),
    refusedCount: _safeCount(metricValue['refused_count']),
    notApplicableCount: _safeCount(metricValue['not_applicable_count']),
    unansweredCount: _safeCount(metricValue['unanswered_count']),
    excludedCount: _safeCount(metricValue['excluded_count']),
    denominator: _safeCount(metricValue['denominator']),
    percentageBasisPoints: percentageBasisPoints as int?,
  );
  return PersonalFollowUpConsentRatioReady(
    projectId: expectedProjectId,
    metric: metric,
  );
}

PersonalFollowUpConsentRatioFailureCode _identityFailure(
  IdentityResult<IdentityAccessToken> result,
) => switch (result) {
  IdentityRejected<IdentityAccessToken>(:final failure) =>
    switch (failure.code) {
      IdentityFailureCode.notConfigured =>
        PersonalFollowUpConsentRatioFailureCode.notConfigured,
      IdentityFailureCode.networkUnavailable =>
        PersonalFollowUpConsentRatioFailureCode.networkUnavailable,
      _ => PersonalFollowUpConsentRatioFailureCode.unauthorized,
    },
  IdentitySuccess<IdentityAccessToken>() =>
    PersonalFollowUpConsentRatioFailureCode.unauthorized,
};

PersonalFollowUpConsentRatioFailureCode? _httpFailure(int statusCode) =>
    switch (statusCode) {
      >= 200 && < 300 => null,
      400 => PersonalFollowUpConsentRatioFailureCode.invalidRequest,
      401 => PersonalFollowUpConsentRatioFailureCode.unauthorized,
      403 => PersonalFollowUpConsentRatioFailureCode.forbidden,
      408 => PersonalFollowUpConsentRatioFailureCode.networkUnavailable,
      >= 500 => PersonalFollowUpConsentRatioFailureCode.serviceUnavailable,
      _ => PersonalFollowUpConsentRatioFailureCode.serverRejected,
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
    throw const FormatException('unexpected consent ratio response field');
  }
}

int _safeCount(Object? value) {
  if (value is! int || value < 0 || value > _maximumSafeInteger) {
    throw const FormatException('invalid consent ratio count');
  }
  return value;
}

int? _expectedBasisPoints(int yesCount, int noCount) {
  final denominator = BigInt.from(yesCount) + BigInt.from(noCount);
  if (denominator == BigInt.zero) return null;
  return ((BigInt.from(yesCount) * BigInt.from(20000) + denominator) ~/
          (denominator * BigInt.from(2)))
      .toInt();
}

String _uuid(Object? value) {
  if (value is! String || !_isUuid(value)) {
    throw const FormatException('expected UUID');
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

Uri _validatedBaseUri(Uri value) {
  final localHttp =
      value.scheme == 'http' &&
      const {'localhost', '127.0.0.1', '::1'}.contains(value.host);
  if ((value.scheme != 'https' && !localHttp) ||
      value.host.isEmpty ||
      value.path.isNotEmpty && value.path != '/') {
    throw ArgumentError('invalid backend base URI');
  }
  return value;
}

DateTime _utcNow() => DateTime.now().toUtc();

final _uuidPattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  caseSensitive: false,
);
final _canonicalUtcPattern = RegExp(
  r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$',
);
const _maximumSafeInteger = 9007199254740991;
