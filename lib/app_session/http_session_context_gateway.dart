import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../identity/identity_session.dart';
import 'session_context_gateway.dart';

const _backendBaseUrl = String.fromEnvironment('BACKEND_BASE_URL');

SessionContextGateway productionSessionContextGateway() {
  if (_backendBaseUrl.trim().isEmpty) {
    return const UnavailableSessionContextGateway();
  }
  return HttpSessionContextGateway(
    baseUri: Uri.parse(_backendBaseUrl),
    client: http.Client(),
  );
}

final class HttpSessionContextGateway implements SessionContextGateway {
  factory HttpSessionContextGateway({
    required Uri baseUri,
    required http.Client client,
    Duration timeout = const Duration(seconds: 15),
  }) =>
      HttpSessionContextGateway._(_validatedBaseUri(baseUri), client, timeout);

  HttpSessionContextGateway._(this._baseUri, this._client, this._timeout);

  final Uri _baseUri;
  final http.Client _client;
  final Duration _timeout;

  @override
  Future<void> close() async => _client.close();

  @override
  Future<SessionContextResult> resolve(IdentityAccessToken accessToken) async {
    return _requestContext(
      accessToken: accessToken,
      request: () => _client.get(
        _baseUri.resolve('/v1/session/context'),
        headers: {
          'accept': 'application/json',
          'authorization': 'Bearer ${accessToken.value}',
        },
      ),
    );
  }

  @override
  Future<SessionContextResult> selectProject(
    IdentityAccessToken accessToken,
    String projectId,
  ) async {
    return _requestContext(
      accessToken: accessToken,
      request: () => _client.post(
        _baseUri.resolve('/v1/session/context/select'),
        headers: {
          'accept': 'application/json',
          'authorization': 'Bearer ${accessToken.value}',
          'content-type': 'application/json; charset=utf-8',
        },
        body: jsonEncode({'project_id': projectId}),
      ),
    );
  }

  @override
  Future<SessionContextResult> createPersonalProject(
    IdentityAccessToken accessToken,
    String displayName,
  ) async {
    return _requestContext(
      accessToken: accessToken,
      acceptedStatusCodes: const {201},
      request: () => _client.post(
        _baseUri.resolve('/v1/session/projects'),
        headers: {
          'accept': 'application/json',
          'authorization': 'Bearer ${accessToken.value}',
          'content-type': 'application/json; charset=utf-8',
        },
        body: jsonEncode({'display_name': displayName}),
      ),
    );
  }

  Future<SessionContextResult> _requestContext({
    required IdentityAccessToken accessToken,
    required Future<http.Response> Function() request,
    Set<int> acceptedStatusCodes = const {200},
  }) async {
    try {
      final response = await request().timeout(_timeout);

      if (response.statusCode == 401 || response.statusCode == 403) {
        return const SessionContextRejected(
          SessionContextFailureCode.unauthorized,
        );
      }
      if (!acceptedStatusCodes.contains(response.statusCode)) {
        return const SessionContextRejected(
          SessionContextFailureCode.serverRejected,
        );
      }

      return _parseContextResult(response.body);
    } on TimeoutException {
      return const SessionContextRejected(
        SessionContextFailureCode.networkUnavailable,
      );
    } on http.ClientException {
      return const SessionContextRejected(
        SessionContextFailureCode.networkUnavailable,
      );
    } on FormatException {
      return const SessionContextRejected(
        SessionContextFailureCode.invalidResponse,
      );
    }
  }
}

SessionContextSuccess _parseContextResult(String responseBody) {
  final root = _object(jsonDecode(responseBody), 'response');
  final current = _parseContext(root);
  final availableValue = root['available_contexts'];
  if (availableValue == null) {
    return SessionContextSuccess(current);
  }
  if (availableValue is! List<Object?>) {
    throw const FormatException('available_contexts must be a list');
  }
  return SessionContextSuccess(
    current,
    availableContexts: [
      for (final value in availableValue)
        _parseContext(_object(value, 'available context')),
    ],
  );
}

TrustedSessionContext _parseContext(Map<String, Object?> root) {
  final current = _object(root['current_context'], 'current_context');
  final workspace = _object(current['workspace'], 'workspace');
  final project = _object(current['project'], 'project');
  final questionnaire = _object(
    current['questionnaire_version'],
    'questionnaire_version',
  );
  final capabilitiesValue = root['capabilities'];
  if (capabilitiesValue is! List<Object?>) {
    throw const FormatException('capabilities must be a list');
  }

  return TrustedSessionContext(
    appUserId: _uuid(root['app_user_id'], 'app_user_id'),
    workspace: WorkspaceContext(
      id: _uuid(workspace['workspace_id'], 'workspace_id'),
      kind: _workspaceKind(workspace['kind']),
      name: _nonEmptyString(workspace['name'], 'workspace name'),
    ),
    project: ProjectContext(
      id: _uuid(project['project_id'], 'project_id'),
      name: _nonEmptyString(project['name'], 'project name'),
    ),
    questionnaireVersion: QuestionnaireVersionContext(
      id: _uuid(
        questionnaire['questionnaire_version_id'],
        'questionnaire_version_id',
      ),
      versionNumber: _positiveInteger(
        questionnaire['version_number'],
        'version_number',
      ),
    ),
    capabilities: Set.unmodifiable(
      capabilitiesValue.map((value) => _nonEmptyString(value, 'capability')),
    ),
  );
}

Map<String, Object?> _object(Object? value, String name) {
  if (value is! Map<String, Object?>) {
    throw FormatException('$name must be an object');
  }
  return value;
}

String _nonEmptyString(Object? value, String name) {
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('$name must be a non-empty string');
  }
  return value;
}

String _uuid(Object? value, String name) {
  final text = _nonEmptyString(value, name);
  final uuid = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    caseSensitive: false,
  );
  if (!uuid.hasMatch(text)) {
    throw FormatException('$name must be a UUID');
  }
  return text;
}

int _positiveInteger(Object? value, String name) {
  if (value is! int || value < 1) {
    throw FormatException('$name must be a positive integer');
  }
  return value;
}

WorkspaceKind _workspaceKind(Object? value) {
  return switch (value) {
    'personal' => WorkspaceKind.personal,
    'organization' => WorkspaceKind.organization,
    _ => throw const FormatException('workspace kind is invalid'),
  };
}

Uri _validatedBaseUri(Uri value) {
  if (!value.hasScheme || value.host.isEmpty) {
    throw const FormatException('BACKEND_BASE_URL must be an absolute URL');
  }
  final localHttp =
      value.scheme == 'http' &&
      const {'localhost', '127.0.0.1', '::1'}.contains(value.host);
  if (value.scheme != 'https' && !localHttp) {
    throw const FormatException(
      'BACKEND_BASE_URL must use HTTPS except on localhost',
    );
  }
  return value;
}
