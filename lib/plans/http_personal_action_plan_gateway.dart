import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../foundation/backend_base_uri.dart';
import '../identity/identity_session.dart';
import 'personal_action_plan.dart';

const _backendBaseUrl = String.fromEnvironment('BACKEND_BASE_URL');

PersonalActionPlanGateway productionPersonalActionPlanGateway(
  IdentitySession identitySession,
) {
  if (_backendBaseUrl.trim().isEmpty) {
    return const DeferredPersonalActionPlanGateway();
  }
  return HttpPersonalActionPlanGateway(
    baseUri: Uri.parse(_backendBaseUrl),
    identitySession: identitySession,
    client: http.Client(),
  );
}

final class DeferredPersonalActionPlanGateway
    implements PersonalActionPlanGateway {
  const DeferredPersonalActionPlanGateway();

  @override
  Future<PersonalActionPlanResult<PersonalActionPlanSnapshot?>> load() async =>
      const PersonalActionPlanRejected(
        PersonalActionPlanFailureCode.notConfigured,
      );

  @override
  Future<PersonalActionPlanResult<PersonalActionPlanMutation>> save({
    required int expectedRevision,
    required int? weeklyContactTarget,
    required String statisticsTimeZone,
    required int weekStartIsoDay,
    required String mutationId,
    bool replaceOfflineChange = false,
  }) async => const PersonalActionPlanRejected(
    PersonalActionPlanFailureCode.notConfigured,
  );

  @override
  Future<bool> discardOfflineChange() async => true;

  @override
  Future<void> close() async {}
}

final class HttpPersonalActionPlanGateway implements PersonalActionPlanGateway {
  factory HttpPersonalActionPlanGateway({
    required Uri baseUri,
    required IdentitySession identitySession,
    required http.Client client,
    Duration timeout = const Duration(seconds: 15),
  }) => HttpPersonalActionPlanGateway._(
    baseUri: validateAbsoluteBaseUri(baseUri),
    identitySession: identitySession,
    client: client,
    timeout: timeout,
  );

  const HttpPersonalActionPlanGateway._({
    required this._baseUri,
    required this._identitySession,
    required this._client,
    required this._timeout,
  });

  final Uri _baseUri;
  final IdentitySession _identitySession;
  final http.Client _client;
  final Duration _timeout;

  @override
  Future<PersonalActionPlanResult<PersonalActionPlanSnapshot?>> load() =>
      _request(
        method: 'GET',
        parse: (root) => root['plan'] == null ? null : _parsePlan(root['plan']),
      );

  @override
  Future<PersonalActionPlanResult<PersonalActionPlanMutation>> save({
    required int expectedRevision,
    required int? weeklyContactTarget,
    required String statisticsTimeZone,
    required int weekStartIsoDay,
    required String mutationId,
    bool replaceOfflineChange = false,
  }) => _request(
    method: 'PUT',
    body: {
      'expected_revision': expectedRevision,
      'weekly_contact_target': weeklyContactTarget,
      'statistics_time_zone': statisticsTimeZone,
      'week_start_iso_day': weekStartIsoDay,
      'mutation_id': mutationId,
    },
    parse: (root) => PersonalActionPlanMutation(
      plan: _parsePlan(root['plan']),
      duplicate: _bool(root['duplicate']),
      acceptedRevision: _int(root['accepted_revision']),
    ),
  );

  Future<PersonalActionPlanResult<T>> _request<T>({
    required String method,
    required T Function(Map<String, Object?> root) parse,
    Map<String, Object?>? body,
  }) async {
    try {
      var access = await _identitySession.accessToken();
      if (access is! IdentitySuccess<IdentityAccessToken>) {
        return const PersonalActionPlanRejected(
          PersonalActionPlanFailureCode.unauthorized,
        );
      }
      var response = await _send(method, access.value, body);
      if (response.statusCode == 401) {
        access = await _identitySession.accessToken(forceRefresh: true);
        if (access is! IdentitySuccess<IdentityAccessToken>) {
          return const PersonalActionPlanRejected(
            PersonalActionPlanFailureCode.unauthorized,
          );
        }
        response = await _send(method, access.value, body);
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return PersonalActionPlanRejected(_failure(response));
      }
      return PersonalActionPlanSuccess(parse(_jsonObject(response.body)));
    } on TimeoutException {
      return const PersonalActionPlanRejected(
        PersonalActionPlanFailureCode.networkUnavailable,
      );
    } on http.ClientException {
      return const PersonalActionPlanRejected(
        PersonalActionPlanFailureCode.networkUnavailable,
      );
    } on FormatException {
      return const PersonalActionPlanRejected(
        PersonalActionPlanFailureCode.invalidResponse,
      );
    }
  }

  Future<http.Response> _send(
    String method,
    IdentityAccessToken token,
    Map<String, Object?>? body,
  ) {
    final uri = _baseUri.resolve('/v1/personal-action-plan');
    final headers = {
      'authorization': 'Bearer ${token.value}',
      'accept': 'application/json',
      if (body != null) 'content-type': 'application/json',
    };
    return (method == 'GET'
            ? _client.get(uri, headers: headers)
            : _client.put(uri, headers: headers, body: jsonEncode(body)))
        .timeout(_timeout);
  }

  PersonalActionPlanFailureCode _failure(http.Response response) {
    if (response.statusCode == 401 || response.statusCode == 403) {
      return PersonalActionPlanFailureCode.unauthorized;
    }
    try {
      final code = _string(
        _object(_jsonObject(response.body)['error']),
        'code',
      );
      return switch (code) {
        'invalid_personal_action_plan' =>
          PersonalActionPlanFailureCode.invalidRequest,
        'personal_action_plan_conflict' =>
          PersonalActionPlanFailureCode.conflict,
        'personal_action_plan_pending_change' =>
          PersonalActionPlanFailureCode.pendingChange,
        _ => PersonalActionPlanFailureCode.serverRejected,
      };
    } on FormatException {
      return PersonalActionPlanFailureCode.serverRejected;
    }
  }

  @override
  Future<bool> discardOfflineChange() async => true;

  @override
  Future<void> close() async => _client.close();
}

PersonalActionPlanSnapshot _parsePlan(Object? value) {
  final root = _object(value);
  final pending = root['pending'];
  return PersonalActionPlanSnapshot(
    planId: _string(root, 'plan_id'),
    revision: _positiveInt(root['revision']),
    current: _parseVersion(root['current']),
    pending: pending == null ? null : _parseVersion(pending),
    progress: _parseProgress(root['progress']),
  );
}

PersonalActionPlanVersion _parseVersion(Object? value) {
  final root = _object(value);
  final target = root['weekly_contact_target'];
  return PersonalActionPlanVersion(
    revision: _positiveInt(root['revision']),
    weeklyContactTarget: target == null ? null : _boundedInt(target, 1, 999),
    statisticsTimeZone: _string(root, 'statistics_time_zone'),
    weekStartIsoDay: _boundedInt(root['week_start_iso_day'], 1, 7),
    effectiveFromUtc: _timestamp(root['effective_from_utc']),
  );
}

PersonalActionPlanProgress _parseProgress(Object? value) {
  final root = _object(value);
  final remaining = root['remaining_contact_sessions'];
  return PersonalActionPlanProgress(
    cycleStartUtc: _timestamp(root['cycle_start_utc']),
    cycleUntilUtc: _timestamp(root['cycle_until_utc']),
    recordedContactSessions: _nonNegativeInt(root['recorded_contact_sessions']),
    remainingContactSessions: remaining == null
        ? null
        : _nonNegativeInt(remaining),
    asOfUtc: _timestamp(root['as_of_utc']),
  );
}

Map<String, Object?> _jsonObject(String source) {
  final decoded = jsonDecode(source);
  return _object(decoded);
}

Map<String, Object?> _object(Object? value) {
  if (value is! Map<String, Object?>) {
    throw const FormatException('invalid personal action plan response');
  }
  return value;
}

String _string(Map<String, Object?> root, String key) {
  final value = root[key];
  if (value is! String || value.isEmpty) {
    throw const FormatException('invalid personal action plan string');
  }
  return value;
}

bool _bool(Object? value) {
  if (value is! bool) {
    throw const FormatException('invalid personal action plan boolean');
  }
  return value;
}

int _int(Object? value) {
  if (value is! int) {
    throw const FormatException('invalid personal action plan integer');
  }
  return value;
}

int _positiveInt(Object? value) => _boundedInt(value, 1, 0x7fffffff);

int _nonNegativeInt(Object? value) => _boundedInt(value, 0, 0x7fffffff);

int _boundedInt(Object? value, int minimum, int maximum) {
  final result = _int(value);
  if (result < minimum || result > maximum) {
    throw const FormatException('personal action plan integer out of range');
  }
  return result;
}

DateTime _timestamp(Object? value) {
  if (value is! String || !value.endsWith('Z')) {
    throw const FormatException('invalid personal action plan timestamp');
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null || !parsed.isUtc) {
    throw const FormatException('personal action plan timestamp must be UTC');
  }
  return parsed;
}
