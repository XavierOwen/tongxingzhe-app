import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../foundation/backend_base_uri.dart';
import '../identity/identity_session.dart';
import 'personal_action_reminder.dart';

const _backendBaseUrl = String.fromEnvironment('BACKEND_BASE_URL');

PersonalActionReminderGateway productionPersonalActionReminderGateway(
  IdentitySession identitySession,
) {
  if (_backendBaseUrl.trim().isEmpty) {
    return const DeferredPersonalActionReminderGateway();
  }
  return HttpPersonalActionReminderGateway(
    baseUri: Uri.parse(_backendBaseUrl),
    identitySession: identitySession,
    client: http.Client(),
  );
}

final class DeferredPersonalActionReminderGateway
    implements PersonalActionReminderGateway {
  const DeferredPersonalActionReminderGateway();

  @override
  Future<PersonalActionReminderResult<PersonalActionReminder?>> load() async =>
      const PersonalActionReminderRejected(
        PersonalActionReminderFailureCode.notConfigured,
      );

  @override
  Future<PersonalActionReminderResult<PersonalActionReminderMutation>> save({
    required int expectedRevision,
    required LocalReminderTime? localTime,
    required String mutationId,
  }) async => const PersonalActionReminderRejected(
    PersonalActionReminderFailureCode.notConfigured,
  );

  @override
  Future<void> close() async {}
}

final class HttpPersonalActionReminderGateway
    implements PersonalActionReminderGateway {
  factory HttpPersonalActionReminderGateway({
    required Uri baseUri,
    required IdentitySession identitySession,
    required http.Client client,
    Duration timeout = const Duration(seconds: 15),
  }) => HttpPersonalActionReminderGateway._(
    baseUri: validateAbsoluteBaseUri(baseUri),
    identitySession: identitySession,
    client: client,
    timeout: timeout,
  );

  const HttpPersonalActionReminderGateway._({
    required this.baseUri,
    required this.identitySession,
    required this.client,
    required this.timeout,
  });

  final Uri baseUri;
  final IdentitySession identitySession;
  final http.Client client;
  final Duration timeout;

  @override
  Future<PersonalActionReminderResult<PersonalActionReminder?>> load() =>
      _request(
        method: 'GET',
        parse: (root) =>
            root['reminder'] == null ? null : _parseReminder(root['reminder']),
      );

  @override
  Future<PersonalActionReminderResult<PersonalActionReminderMutation>> save({
    required int expectedRevision,
    required LocalReminderTime? localTime,
    required String mutationId,
  }) => _request(
    method: 'PUT',
    body: {
      'expected_revision': expectedRevision,
      'local_minute_of_day': localTime?.minuteOfDay,
      'mutation_id': mutationId,
    },
    parse: (root) => PersonalActionReminderMutation(
      reminder: _parseReminder(root['reminder']),
      duplicate: _bool(root['duplicate']),
      acceptedRevision: _positiveInt(root['accepted_revision']),
    ),
  );

  Future<PersonalActionReminderResult<T>> _request<T>({
    required String method,
    required T Function(Map<String, Object?> root) parse,
    Map<String, Object?>? body,
  }) async {
    try {
      var access = await identitySession.accessToken();
      if (access is! IdentitySuccess<IdentityAccessToken>) {
        return const PersonalActionReminderRejected(
          PersonalActionReminderFailureCode.unauthorized,
        );
      }
      var response = await _send(method, access.value, body);
      if (response.statusCode == 401) {
        access = await identitySession.accessToken(forceRefresh: true);
        if (access is! IdentitySuccess<IdentityAccessToken>) {
          return const PersonalActionReminderRejected(
            PersonalActionReminderFailureCode.unauthorized,
          );
        }
        response = await _send(method, access.value, body);
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return PersonalActionReminderRejected(_failure(response));
      }
      return PersonalActionReminderSuccess(parse(_jsonObject(response.body)));
    } on TimeoutException {
      return const PersonalActionReminderRejected(
        PersonalActionReminderFailureCode.networkUnavailable,
      );
    } on http.ClientException {
      return const PersonalActionReminderRejected(
        PersonalActionReminderFailureCode.networkUnavailable,
      );
    } on FormatException {
      return const PersonalActionReminderRejected(
        PersonalActionReminderFailureCode.invalidResponse,
      );
    }
  }

  Future<http.Response> _send(
    String method,
    IdentityAccessToken token,
    Map<String, Object?>? body,
  ) {
    final uri = baseUri.resolve('/v1/personal-action-reminder');
    final headers = {
      'authorization': 'Bearer ${token.value}',
      'accept': 'application/json',
      if (body != null) 'content-type': 'application/json',
    };
    return (method == 'GET'
            ? client.get(uri, headers: headers)
            : client.put(uri, headers: headers, body: jsonEncode(body)))
        .timeout(timeout);
  }

  PersonalActionReminderFailureCode _failure(http.Response response) {
    if (response.statusCode == 401 || response.statusCode == 403) {
      return PersonalActionReminderFailureCode.unauthorized;
    }
    try {
      final code = _string(
        _object(_jsonObject(response.body)['error']),
        'code',
      );
      return switch (code) {
        'invalid_personal_action_reminder' =>
          PersonalActionReminderFailureCode.invalidRequest,
        'personal_action_reminder_conflict' =>
          PersonalActionReminderFailureCode.conflict,
        _ => PersonalActionReminderFailureCode.serverRejected,
      };
    } on FormatException {
      return PersonalActionReminderFailureCode.serverRejected;
    }
  }

  @override
  Future<void> close() async => client.close();
}

PersonalActionReminder _parseReminder(Object? value) {
  final root = _object(value);
  final minute = root['local_minute_of_day'];
  return PersonalActionReminder(
    reminderId: _string(root, 'reminder_id'),
    revision: _positiveInt(root['revision']),
    localTime: minute == null
        ? null
        : LocalReminderTime.fromMinuteOfDay(_boundedInt(minute, 0, 1439)),
    updatedAtUtc: _timestamp(root['updated_at_utc']),
  );
}

Map<String, Object?> _jsonObject(String source) => _object(jsonDecode(source));

Map<String, Object?> _object(Object? value) {
  if (value is! Map<String, Object?>) {
    throw const FormatException('invalid personal action reminder response');
  }
  return value;
}

String _string(Map<String, Object?> root, String key) {
  final value = root[key];
  if (value is! String || value.isEmpty) {
    throw const FormatException('invalid personal action reminder string');
  }
  return value;
}

bool _bool(Object? value) {
  if (value is! bool) {
    throw const FormatException('invalid personal action reminder boolean');
  }
  return value;
}

int _positiveInt(Object? value) => _boundedInt(value, 1, 0x7fffffff);

int _boundedInt(Object? value, int minimum, int maximum) {
  if (value is! int || value < minimum || value > maximum) {
    throw const FormatException(
      'personal action reminder integer out of range',
    );
  }
  return value;
}

DateTime _timestamp(Object? value) {
  if (value is! String || !value.endsWith('Z')) {
    throw const FormatException('invalid personal action reminder timestamp');
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null || !parsed.isUtc) {
    throw const FormatException(
      'personal action reminder timestamp must be UTC',
    );
  }
  return parsed;
}
