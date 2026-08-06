import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../identity/identity_session.dart';
import 'questionnaire_contract.dart';

const _backendBaseUrl = String.fromEnvironment('BACKEND_BASE_URL');

QuestionnaireRemoteSource? productionQuestionnaireRemoteSource(
  IdentitySession identitySession,
) {
  if (_backendBaseUrl.trim().isEmpty) {
    return null;
  }
  return HttpQuestionnaireRemoteSource(
    baseUri: Uri.parse(_backendBaseUrl),
    identitySession: identitySession,
    client: http.Client(),
  );
}

/// 只读取 Backend 已授权的不可变发布版本；失败时不删除本机缓存。
final class HttpQuestionnaireRemoteSource implements QuestionnaireRemoteSource {
  factory HttpQuestionnaireRemoteSource({
    required Uri baseUri,
    required IdentitySession identitySession,
    required http.Client client,
    Duration timeout = const Duration(seconds: 10),
  }) => HttpQuestionnaireRemoteSource._(
    _validatedBaseUri(baseUri),
    identitySession,
    client,
    timeout,
  );

  HttpQuestionnaireRemoteSource._(
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
  Future<QuestionnaireVersion?> fetchPublishedVersion(String versionId) async {
    try {
      var token = await _identitySession.accessToken();
      if (token is! IdentitySuccess<IdentityAccessToken>) {
        return null;
      }
      var response = await _get(versionId, token.value);
      if (response.statusCode == 401) {
        token = await _identitySession.accessToken(forceRefresh: true);
        if (token is! IdentitySuccess<IdentityAccessToken>) {
          return null;
        }
        response = await _get(versionId, token.value);
      }
      if (response.statusCode != 200) {
        return null;
      }
      final root = jsonDecode(response.body);
      if (root is! Map<String, Object?>) {
        throw const FormatException('questionnaire response must be an object');
      }
      final version = QuestionnaireContract.parseVersion(root['questionnaire']);
      if (version.id != versionId) {
        throw const FormatException('questionnaire response ID differs');
      }
      return version;
    } on TimeoutException {
      return null;
    } on http.ClientException {
      return null;
    } on FormatException {
      return null;
    } on StateError {
      return null;
    }
  }

  Future<http.Response> _get(String versionId, IdentityAccessToken token) {
    return _client
        .get(
          _baseUri.resolve(
            '/v1/questionnaire-versions/${Uri.encodeComponent(versionId)}',
          ),
          headers: {
            'accept': 'application/json',
            'authorization': 'Bearer ${token.value}',
          },
        )
        .timeout(_timeout);
  }

  @override
  Future<void> close() async => _client.close();
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
