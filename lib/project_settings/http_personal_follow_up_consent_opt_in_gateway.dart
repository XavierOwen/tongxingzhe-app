import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../foundation/backend_base_uri.dart';
import '../identity/identity_session.dart';
import 'personal_follow_up_consent_opt_in.dart';

const _backendBaseUrl = String.fromEnvironment('BACKEND_BASE_URL');
const _path = '/v1/personal/follow-up-consent-ratio/opt-in';

PersonalFollowUpConsentOptInGateway
productionPersonalFollowUpConsentOptInGateway(
  IdentitySession identitySession,
  String Function() currentProjectId,
) {
  if (_backendBaseUrl.trim().isEmpty) {
    return const DeferredPersonalFollowUpConsentOptInGateway();
  }
  return HttpPersonalFollowUpConsentOptInGateway(
    baseUri: Uri.parse(_backendBaseUrl),
    identitySession: identitySession,
    client: http.Client(),
    currentProjectId: currentProjectId,
  );
}

final class DeferredPersonalFollowUpConsentOptInGateway
    implements PersonalFollowUpConsentOptInGateway {
  const DeferredPersonalFollowUpConsentOptInGateway();

  @override
  Future<PersonalFollowUpConsentOptInResult<PersonalFollowUpConsentOptInState>>
  load() async => const PersonalFollowUpConsentOptInRejected(
    PersonalFollowUpConsentOptInFailureCode.notConfigured,
  );

  @override
  Future<
    PersonalFollowUpConsentOptInResult<
      PersonalFollowUpConsentOptInConfiguration
    >
  >
  configure({
    required int expectedVersion,
    required bool enabled,
    required String requestId,
  }) async => const PersonalFollowUpConsentOptInRejected(
    PersonalFollowUpConsentOptInFailureCode.notConfigured,
  );

  @override
  Future<void> close() async {}
}

/// Narrow adapter for the current personal project's opt-in endpoints.
///
/// The current project ID is a response-boundary assertion. It is never sent
/// to the Backend, which derives the current project from its trusted session
/// context. The provider is evaluated for every response so a project switch
/// cannot silently accept data for the previous project.
final class HttpPersonalFollowUpConsentOptInGateway
    implements PersonalFollowUpConsentOptInGateway {
  factory HttpPersonalFollowUpConsentOptInGateway({
    required Uri baseUri,
    required IdentitySession identitySession,
    required http.Client client,
    required String Function() currentProjectId,
    Duration timeout = const Duration(seconds: 15),
  }) {
    return HttpPersonalFollowUpConsentOptInGateway._(
      baseUri: validatePathlessBackendBaseUri(baseUri),
      identitySession: identitySession,
      client: client,
      currentProjectId: currentProjectId,
      timeout: timeout,
    );
  }

  const HttpPersonalFollowUpConsentOptInGateway._({
    required this.baseUri,
    required this.identitySession,
    required this.client,
    required this.currentProjectId,
    required this.timeout,
  });

  final Uri baseUri;
  final IdentitySession identitySession;
  final http.Client client;
  final String Function() currentProjectId;
  final Duration timeout;

  @override
  Future<PersonalFollowUpConsentOptInResult<PersonalFollowUpConsentOptInState>>
  load() => _request(
    send: (token) =>
        client.get(baseUri.resolve(_path), headers: _headers(token)),
    parse: (root) {
      _requireExactKeys(root, const ['state']);
      return _parseState(root['state'], _uuid(currentProjectId()));
    },
  );

  @override
  Future<
    PersonalFollowUpConsentOptInResult<
      PersonalFollowUpConsentOptInConfiguration
    >
  >
  configure({
    required int expectedVersion,
    required bool enabled,
    required String requestId,
  }) {
    if (!_validVersion(expectedVersion) || !_uuidOrNull(requestId)) {
      return Future.value(
        const PersonalFollowUpConsentOptInRejected(
          PersonalFollowUpConsentOptInFailureCode.invalidRequest,
        ),
      );
    }
    final normalizedRequestId = requestId.toLowerCase();
    return _request(
      send: (token) => client.put(
        baseUri.resolve(_path),
        headers: _headers(token, hasBody: true),
        body: jsonEncode({
          'expected_version': expectedVersion,
          'enabled': enabled,
          'request_id': normalizedRequestId,
        }),
      ),
      parse: (root) {
        _requireExactKeys(root, const ['configuration']);
        final configuration = _parseConfiguration(
          root['configuration'],
          _uuid(currentProjectId()),
        );
        if (configuration.expectedVersion != expectedVersion ||
            configuration.enabled != enabled ||
            configuration.requestId != normalizedRequestId) {
          throw const FormatException('configuration does not match request');
        }
        return configuration;
      },
    );
  }

  Future<PersonalFollowUpConsentOptInResult<T>> _request<T>({
    required Future<http.Response> Function(IdentityAccessToken token) send,
    required T Function(Map<String, Object?> root) parse,
  }) async {
    try {
      var access = await identitySession.accessToken();
      if (access is! IdentitySuccess<IdentityAccessToken>) {
        return PersonalFollowUpConsentOptInRejected(_identityFailure(access));
      }

      var response = await send(access.value).timeout(timeout);
      if (response.statusCode == 401) {
        access = await identitySession.accessToken(forceRefresh: true);
        if (access is! IdentitySuccess<IdentityAccessToken>) {
          return PersonalFollowUpConsentOptInRejected(_identityFailure(access));
        }
        response = await send(access.value).timeout(timeout);
      }
      if (response.statusCode == 401) {
        return const PersonalFollowUpConsentOptInRejected(
          PersonalFollowUpConsentOptInFailureCode.unauthorized,
        );
      }
      if (response.statusCode == 400) {
        return const PersonalFollowUpConsentOptInRejected(
          PersonalFollowUpConsentOptInFailureCode.invalidRequest,
        );
      }
      if (response.statusCode == 403) {
        return const PersonalFollowUpConsentOptInRejected(
          PersonalFollowUpConsentOptInFailureCode.forbidden,
        );
      }
      if (response.statusCode == 409) {
        return const PersonalFollowUpConsentOptInRejected(
          PersonalFollowUpConsentOptInFailureCode.conflict,
        );
      }
      if (response.statusCode == 408) {
        return const PersonalFollowUpConsentOptInRejected(
          PersonalFollowUpConsentOptInFailureCode.networkUnavailable,
        );
      }
      if (response.statusCode >= 500) {
        return const PersonalFollowUpConsentOptInRejected(
          PersonalFollowUpConsentOptInFailureCode.serviceUnavailable,
        );
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return const PersonalFollowUpConsentOptInRejected(
          PersonalFollowUpConsentOptInFailureCode.serverRejected,
        );
      }
      return PersonalFollowUpConsentOptInSuccess(
        parse(_object(jsonDecode(response.body))),
      );
    } on TimeoutException {
      return const PersonalFollowUpConsentOptInRejected(
        PersonalFollowUpConsentOptInFailureCode.networkUnavailable,
      );
    } on http.ClientException {
      return const PersonalFollowUpConsentOptInRejected(
        PersonalFollowUpConsentOptInFailureCode.networkUnavailable,
      );
    } on FormatException {
      return const PersonalFollowUpConsentOptInRejected(
        PersonalFollowUpConsentOptInFailureCode.invalidResponse,
      );
    } on StateError {
      return const PersonalFollowUpConsentOptInRejected(
        PersonalFollowUpConsentOptInFailureCode.invalidResponse,
      );
    }
  }

  Map<String, String> _headers(
    IdentityAccessToken token, {
    bool hasBody = false,
  }) => {
    'accept': 'application/json',
    'authorization': 'Bearer ${token.value}',
    if (hasBody) 'content-type': 'application/json; charset=utf-8',
  };

  @override
  Future<void> close() async => client.close();
}

PersonalFollowUpConsentOptInFailureCode _identityFailure(
  IdentityResult<IdentityAccessToken> result,
) => switch (result) {
  IdentityRejected<IdentityAccessToken>(:final failure) =>
    switch (failure.code) {
      IdentityFailureCode.notConfigured =>
        PersonalFollowUpConsentOptInFailureCode.notConfigured,
      IdentityFailureCode.networkUnavailable =>
        PersonalFollowUpConsentOptInFailureCode.networkUnavailable,
      _ => PersonalFollowUpConsentOptInFailureCode.unauthorized,
    },
  IdentitySuccess<IdentityAccessToken>() =>
    PersonalFollowUpConsentOptInFailureCode.unauthorized,
};

PersonalFollowUpConsentOptInState _parseState(
  Object? value,
  String expectedProjectId,
) {
  final root = _object(value);
  _requireExactKeys(root, const [
    'state_contract_id',
    'metric_id',
    'project_id',
    'status',
    'configuration',
  ]);
  final projectId = _uuid(root['project_id']);
  if (root['state_contract_id'] != personalFollowUpConsentOptInStateContract ||
      root['metric_id'] != personalFollowUpConsentOptInMetric ||
      projectId != expectedProjectId) {
    throw const FormatException('invalid opt-in state identity');
  }

  final configurationValue = root['configuration'];
  if (configurationValue == null) {
    if (root['status'] != 'not_enabled') {
      throw const FormatException('enabled state requires configuration');
    }
    return PersonalFollowUpConsentOptInState(
      stateContractId: personalFollowUpConsentOptInStateContract,
      metricId: personalFollowUpConsentOptInMetric,
      projectId: projectId,
      status: PersonalFollowUpConsentOptInStatus.notEnabled,
      configuration: null,
    );
  }

  final configuration = _parseConfiguration(
    configurationValue,
    expectedProjectId,
  );
  final status = switch (root['status']) {
    'enabled' when configuration.enabled =>
      PersonalFollowUpConsentOptInStatus.enabled,
    'not_enabled' when !configuration.enabled =>
      PersonalFollowUpConsentOptInStatus.notEnabled,
    _ => throw const FormatException('state and configuration disagree'),
  };
  return PersonalFollowUpConsentOptInState(
    stateContractId: personalFollowUpConsentOptInStateContract,
    metricId: personalFollowUpConsentOptInMetric,
    projectId: projectId,
    status: status,
    configuration: configuration,
  );
}

PersonalFollowUpConsentOptInConfiguration _parseConfiguration(
  Object? value,
  String expectedProjectId,
) {
  final root = _object(value);
  _requireExactKeys(root, const [
    'configuration_contract_id',
    'metric_id',
    'project_id',
    'version_number',
    'expected_version',
    'enabled',
    'request_id',
    'recorded_at_utc',
  ]);
  final projectId = _uuid(root['project_id']);
  final versionNumber = _integer(root['version_number'], positive: true);
  final expectedVersion = _integer(root['expected_version']);
  final requestId = _uuid(root['request_id']);
  final recordedAtUtc = _utcTimestamp(root['recorded_at_utc']);
  if (root['configuration_contract_id'] !=
          personalFollowUpConsentOptInConfigurationContract ||
      root['metric_id'] != personalFollowUpConsentOptInMetric ||
      projectId != expectedProjectId.toLowerCase() ||
      root['enabled'] is! bool ||
      versionNumber != expectedVersion + 1) {
    throw const FormatException('invalid opt-in configuration');
  }
  return PersonalFollowUpConsentOptInConfiguration(
    configurationContractId: personalFollowUpConsentOptInConfigurationContract,
    metricId: personalFollowUpConsentOptInMetric,
    projectId: projectId,
    versionNumber: versionNumber,
    expectedVersion: expectedVersion,
    enabled: root['enabled']! as bool,
    requestId: requestId,
    recordedAtUtc: recordedAtUtc,
  );
}

Map<String, Object?> _object(Object? value) {
  if (value is! Map) throw const FormatException('expected JSON object');
  return value.map<String, Object?>((key, value) {
    if (key is! String) throw const FormatException('JSON key is not text');
    return MapEntry(key, value);
  });
}

void _requireExactKeys(Map<String, Object?> value, List<String> keys) {
  final expected = keys.toSet();
  if (value.length != expected.length || !value.keys.every(expected.contains)) {
    throw const FormatException('unexpected opt-in response field');
  }
}

String _uuid(Object? value) {
  if (value is! String || !_uuidOrNull(value)) {
    throw const FormatException('expected UUID');
  }
  return value.toLowerCase();
}

bool _uuidOrNull(Object? value) =>
    value is String &&
    RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
      caseSensitive: false,
    ).hasMatch(value);

int _integer(Object? value, {bool positive = false}) {
  if (value is! int ||
      (positive ? value < 1 : value < 0) ||
      value > personalFollowUpConsentOptInMaxVersion) {
    throw const FormatException('invalid PostgreSQL integer version');
  }
  return value;
}

bool _validVersion(int value) =>
    value >= 0 && value <= personalFollowUpConsentOptInMaxVersion;

DateTime _utcTimestamp(Object? value) {
  final text = value is String ? value : null;
  final match = text == null
      ? null
      : RegExp(
          r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})\.(\d{6})Z$',
        ).firstMatch(text);
  if (match == null) {
    throw const FormatException('expected UTC timestamp');
  }
  final parsed = DateTime.tryParse(text!);
  final parts = [
    for (var index = 1; index <= 7; index++) int.parse(match.group(index)!),
  ];
  if (parsed == null ||
      !parsed.isUtc ||
      parsed.year != parts[0] ||
      parsed.month != parts[1] ||
      parsed.day != parts[2] ||
      parsed.hour != parts[3] ||
      parsed.minute != parts[4] ||
      parsed.second != parts[5] ||
      parsed.millisecond * 1000 + parsed.microsecond != parts[6]) {
    throw const FormatException('expected UTC timestamp');
  }
  return parsed;
}
