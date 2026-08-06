import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../identity/identity_session.dart';
import 'questionnaire_administration.dart';
import 'questionnaire_contract.dart';

const _backendBaseUrl = String.fromEnvironment('BACKEND_BASE_URL');

QuestionnaireAdministrationGateway productionQuestionnaireAdministration(
  IdentitySession identitySession,
) {
  if (_backendBaseUrl.trim().isEmpty) {
    return const DeferredQuestionnaireAdministrationGateway();
  }
  return HttpQuestionnaireAdministrationGateway(
    baseUri: Uri.parse(_backendBaseUrl),
    identitySession: identitySession,
    client: http.Client(),
  );
}

final class DeferredQuestionnaireAdministrationGateway
    implements QuestionnaireAdministrationGateway {
  const DeferredQuestionnaireAdministrationGateway();

  @override
  Future<QuestionnaireAdministrationResult<QuestionnaireAdministrationSnapshot>>
  load() async => const QuestionnaireAdministrationRejected(
    QuestionnaireAdministrationFailureCode.networkUnavailable,
  );

  @override
  Future<QuestionnaireAdministrationResult<QuestionnaireDesignDraft>>
  createDraft({String? sourceVersionId}) async =>
      const QuestionnaireAdministrationRejected(
        QuestionnaireAdministrationFailureCode.networkUnavailable,
      );

  @override
  Future<QuestionnaireAdministrationResult<QuestionnaireDesignDraft>>
  saveDraft({
    required QuestionnaireDesignDraft draft,
    required QuestionnaireVersion definition,
  }) async => const QuestionnaireAdministrationRejected(
    QuestionnaireAdministrationFailureCode.networkUnavailable,
  );

  @override
  Future<QuestionnaireAdministrationResult<QuestionnairePublication>> publish({
    required QuestionnaireDesignDraft draft,
    required String requestId,
    required String publicationNote,
  }) async => const QuestionnaireAdministrationRejected(
    QuestionnaireAdministrationFailureCode.networkUnavailable,
  );

  @override
  Future<QuestionnaireVersion?> readPublishedVersion(String versionId) async =>
      null;

  @override
  Future<void> close() async {}
}

final class HttpQuestionnaireAdministrationGateway
    implements QuestionnaireAdministrationGateway {
  factory HttpQuestionnaireAdministrationGateway({
    required Uri baseUri,
    required IdentitySession identitySession,
    required http.Client client,
    Duration timeout = const Duration(seconds: 10),
  }) => HttpQuestionnaireAdministrationGateway._(
    _validatedBaseUri(baseUri),
    identitySession,
    client,
    timeout,
  );

  const HttpQuestionnaireAdministrationGateway._(
    this._baseUri,
    this._identitySession,
    this._client,
    this._timeout,
  );

  final Uri _baseUri;
  final IdentitySession _identitySession;
  final http.Client _client;
  final Duration _timeout;

  @override
  Future<QuestionnaireAdministrationResult<QuestionnaireAdministrationSnapshot>>
  load() => _request(
    method: 'GET',
    path: '/v1/questionnaire-administration',
    parse: _parseSnapshot,
  );

  @override
  Future<QuestionnaireAdministrationResult<QuestionnaireDesignDraft>>
  createDraft({String? sourceVersionId}) => _request(
    method: 'POST',
    path: '/v1/questionnaire-drafts',
    body: {'source_version_id': sourceVersionId},
    parse: (root) => _parseDraft(root['draft']),
  );

  @override
  Future<QuestionnaireAdministrationResult<QuestionnaireDesignDraft>>
  saveDraft({
    required QuestionnaireDesignDraft draft,
    required QuestionnaireVersion definition,
  }) => _request(
    method: 'PUT',
    path: '/v1/questionnaire-drafts/${Uri.encodeComponent(draft.id)}',
    body: {
      'expected_revision': draft.revision,
      'definition': {
        'questions': QuestionnaireContract.versionToJson(
          definition,
        )['questions'],
      },
    },
    parse: (root) => _parseDraft(root['draft']),
  );

  @override
  Future<QuestionnaireAdministrationResult<QuestionnairePublication>> publish({
    required QuestionnaireDesignDraft draft,
    required String requestId,
    required String publicationNote,
  }) => _request(
    method: 'POST',
    path: '/v1/questionnaire-drafts/${Uri.encodeComponent(draft.id)}/publish',
    body: {
      'expected_revision': draft.revision,
      'request_id': requestId,
      'publication_note': publicationNote,
    },
    parse: (root) => _parsePublication(root['publication']),
  );

  @override
  Future<QuestionnaireVersion?> readPublishedVersion(String versionId) async {
    final result = await _request(
      method: 'GET',
      path: '/v1/questionnaire-versions/${Uri.encodeComponent(versionId)}',
      parse: (root) =>
          QuestionnaireContract.parseVersion(root['questionnaire']),
    );
    return switch (result) {
      QuestionnaireAdministrationSuccess(:final value) => value,
      QuestionnaireAdministrationRejected() => null,
    };
  }

  Future<QuestionnaireAdministrationResult<T>> _request<T>({
    required String method,
    required String path,
    required T Function(Map<String, Object?> root) parse,
    Map<String, Object?>? body,
  }) async {
    try {
      var token = await _identitySession.accessToken();
      if (token is! IdentitySuccess<IdentityAccessToken>) {
        return const QuestionnaireAdministrationRejected(
          QuestionnaireAdministrationFailureCode.unauthorized,
        );
      }
      var response = await _send(method, path, token.value, body);
      if (response.statusCode == 401) {
        token = await _identitySession.accessToken(forceRefresh: true);
        if (token is! IdentitySuccess<IdentityAccessToken>) {
          return const QuestionnaireAdministrationRejected(
            QuestionnaireAdministrationFailureCode.unauthorized,
          );
        }
        response = await _send(method, path, token.value, body);
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return QuestionnaireAdministrationRejected(
          _failureCode(response.statusCode, response.body),
        );
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, Object?>) {
        throw const FormatException('administration response must be object');
      }
      return QuestionnaireAdministrationSuccess(parse(decoded));
    } on TimeoutException {
      return const QuestionnaireAdministrationRejected(
        QuestionnaireAdministrationFailureCode.networkUnavailable,
      );
    } on http.ClientException {
      return const QuestionnaireAdministrationRejected(
        QuestionnaireAdministrationFailureCode.networkUnavailable,
      );
    } on FormatException {
      return const QuestionnaireAdministrationRejected(
        QuestionnaireAdministrationFailureCode.serverRejected,
      );
    } on StateError {
      return const QuestionnaireAdministrationRejected(
        QuestionnaireAdministrationFailureCode.serverRejected,
      );
    }
  }

  Future<http.Response> _send(
    String method,
    String path,
    IdentityAccessToken token,
    Map<String, Object?>? body,
  ) {
    final uri = _baseUri.resolve(path);
    final headers = {
      'accept': 'application/json',
      'authorization': 'Bearer ${token.value}',
      if (body != null) 'content-type': 'application/json',
    };
    final encodedBody = body == null ? null : jsonEncode(body);
    final future = switch (method) {
      'GET' => _client.get(uri, headers: headers),
      'POST' => _client.post(uri, headers: headers, body: encodedBody),
      'PUT' => _client.put(uri, headers: headers, body: encodedBody),
      _ => throw StateError('unsupported administration method'),
    };
    return future.timeout(_timeout);
  }

  @override
  Future<void> close() async => _client.close();
}

QuestionnaireAdministrationSnapshot _parseSnapshot(Map<String, Object?> root) =>
    QuestionnaireAdministrationSnapshot(
      currentVersionId: _string(root['current_version_id']),
      versions: _list(root['versions']).map(_parseSummary),
      drafts: _list(root['drafts']).map(_parseDraft),
    );

QuestionnaireDesignDraft _parseDraft(Object? value) {
  final root = _object(value);
  final draftId = _string(root['draft_id']);
  final projectId = _string(root['project_id']);
  final revision = _positiveInt(root['revision']);
  final definition = _object(root['definition']);
  return QuestionnaireDesignDraft(
    id: draftId,
    projectId: projectId,
    sourceVersionId: _nullableString(root['source_version_id']),
    revision: revision,
    updatedAtUtc: DateTime.parse(_string(root['updated_at'])).toUtc(),
    definition: QuestionnaireContract.parseVersion({
      'questionnaire_version_id': draftId,
      'project_id': projectId,
      'version_number': revision,
      'status': 'published',
      'questions': definition['questions'],
    }),
  );
}

QuestionnairePublishedVersionSummary _parseSummary(Object? value) {
  final root = _object(value);
  return QuestionnairePublishedVersionSummary(
    id: _string(root['questionnaire_version_id']),
    versionNumber: _positiveInt(root['version_number']),
    isCurrent: _bool(root['is_current']),
    publishedAtUtc: DateTime.parse(_string(root['published_at'])).toUtc(),
    publishedByAppUserId: _nullableString(root['published_by_app_user_id']),
    publicationNote: _nullableString(root['publication_note']),
  );
}

QuestionnairePublication _parsePublication(Object? value) {
  final root = _object(value);
  return QuestionnairePublication(
    summary: _parseSummary(root['summary']),
    version: QuestionnaireContract.parseVersion(root['questionnaire']),
  );
}

QuestionnaireAdministrationFailureCode _failureCode(int status, String body) {
  String? code;
  try {
    final root = jsonDecode(body);
    if (root is Map<String, Object?> && root['error'] is Map<String, Object?>) {
      code = (root['error']! as Map<String, Object?>)['code'] as String?;
    }
  } on FormatException {
    code = null;
  }
  if (status == 401) return QuestionnaireAdministrationFailureCode.unauthorized;
  if (status == 403) return QuestionnaireAdministrationFailureCode.forbidden;
  if (status == 404) return QuestionnaireAdministrationFailureCode.notFound;
  if (status == 409) {
    return QuestionnaireAdministrationFailureCode.revisionConflict;
  }
  if (status == 400 &&
      (code == 'invalid_questionnaire_definition' ||
          code == 'questionnaire_questions_required')) {
    return QuestionnaireAdministrationFailureCode.invalidDefinition;
  }
  return QuestionnaireAdministrationFailureCode.serverRejected;
}

Map<String, Object?> _object(Object? value) {
  if (value is! Map<String, Object?>) {
    throw const FormatException('expected object');
  }
  return value;
}

List<Object?> _list(Object? value) {
  if (value is! List<Object?>) throw const FormatException('expected list');
  return value;
}

String _string(Object? value) {
  if (value is! String || value.trim().isEmpty) {
    throw const FormatException('expected non-empty string');
  }
  return value;
}

String? _nullableString(Object? value) => value == null ? null : _string(value);

int _positiveInt(Object? value) {
  if (value is! int || value < 1) {
    throw const FormatException('expected positive integer');
  }
  return value;
}

bool _bool(Object? value) {
  if (value is! bool) throw const FormatException('expected boolean');
  return value;
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
