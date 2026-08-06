import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../identity/identity_session.dart';
import 'promotion_target.dart';

const _backendBaseUrl = String.fromEnvironment('BACKEND_BASE_URL');

PromotionTargetGateway productionPromotionTargetGateway(
  IdentitySession identitySession,
) {
  if (_backendBaseUrl.trim().isEmpty) {
    return const DeferredPromotionTargetGateway();
  }
  return HttpPromotionTargetGateway(
    baseUri: Uri.parse(_backendBaseUrl),
    identitySession: identitySession,
    client: http.Client(),
  );
}

final class DeferredPromotionTargetGateway implements PromotionTargetGateway {
  const DeferredPromotionTargetGateway();

  @override
  Future<PromotionTargetResult<List<PromotionTargetProfile>>>
  loadAssigned() async => const PromotionTargetRejected(
    PromotionTargetFailureCode.networkUnavailable,
  );

  @override
  Future<PromotionTargetResult<PromotionTargetProfile>> create({
    required PromotionTargetType type,
    required String displayName,
    required String? phone,
    required String? email,
    required String requestId,
  }) async => const PromotionTargetRejected(
    PromotionTargetFailureCode.networkUnavailable,
  );

  @override
  Future<void> close() async {}
}

final class HttpPromotionTargetGateway implements PromotionTargetGateway {
  factory HttpPromotionTargetGateway({
    required Uri baseUri,
    required IdentitySession identitySession,
    required http.Client client,
    Duration timeout = const Duration(seconds: 15),
  }) => HttpPromotionTargetGateway._(
    baseUri: _validatedBaseUri(baseUri),
    identitySession: identitySession,
    client: client,
    timeout: timeout,
  );

  HttpPromotionTargetGateway._({
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
  Future<PromotionTargetResult<List<PromotionTargetProfile>>> loadAssigned() =>
      _request(
        method: 'GET',
        parse: (root) => _list(root['targets']).map(_parseProfile).toList(),
      );

  @override
  Future<PromotionTargetResult<PromotionTargetProfile>> create({
    required PromotionTargetType type,
    required String displayName,
    required String? phone,
    required String? email,
    required String requestId,
  }) => _request(
    method: 'POST',
    body: {
      'target_type': type.storageValue,
      'display_name': displayName,
      'phone': phone,
      'email': email,
      'request_id': requestId,
    },
    parse: (root) => _parseProfile(root['target']),
  );

  Future<PromotionTargetResult<T>> _request<T>({
    required String method,
    required T Function(Map<String, Object?> root) parse,
    Map<String, Object?>? body,
  }) async {
    try {
      var token = await _identitySession.accessToken();
      if (token is! IdentitySuccess<IdentityAccessToken>) {
        return const PromotionTargetRejected(
          PromotionTargetFailureCode.unauthorized,
        );
      }
      var response = await _send(method, token.value, body);
      if (response.statusCode == 401) {
        token = await _identitySession.accessToken(forceRefresh: true);
        if (token is! IdentitySuccess<IdentityAccessToken>) {
          return const PromotionTargetRejected(
            PromotionTargetFailureCode.unauthorized,
          );
        }
        response = await _send(method, token.value, body);
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return PromotionTargetRejected(_failure(response.statusCode));
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, Object?>) {
        throw const FormatException('target response must be an object');
      }
      return PromotionTargetSuccess(parse(decoded));
    } on TimeoutException {
      return const PromotionTargetRejected(
        PromotionTargetFailureCode.networkUnavailable,
      );
    } on http.ClientException {
      return const PromotionTargetRejected(
        PromotionTargetFailureCode.networkUnavailable,
      );
    } on FormatException {
      return const PromotionTargetRejected(
        PromotionTargetFailureCode.serverRejected,
      );
    }
  }

  Future<http.Response> _send(
    String method,
    IdentityAccessToken token,
    Map<String, Object?>? body,
  ) => _client
      .send(
        http.Request(method, _baseUri.resolve('/v1/promotion-targets'))
          ..headers.addAll({
            'authorization': 'Bearer ${token.value}',
            'accept': 'application/json',
            if (body != null) 'content-type': 'application/json',
          })
          ..body = body == null ? '' : jsonEncode(body),
      )
      .then(http.Response.fromStream)
      .timeout(_timeout);

  @override
  Future<void> close() async => _client.close();
}

PromotionTargetProfile _parseProfile(Object? value) {
  final root = _object(value);
  return PromotionTargetProfile(
    id: _string(root['target_id']),
    type: PromotionTargetType.values.firstWhere(
      (candidate) => candidate.storageValue == _string(root['target_type']),
    ),
    displayName: _string(root['display_name']),
    phone: _nullableString(root['phone']),
    email: _nullableString(root['email']),
    createdAtUtc: DateTime.parse(_string(root['created_at'])).toUtc(),
  );
}

PromotionTargetFailureCode _failure(int status) => switch (status) {
  400 => PromotionTargetFailureCode.invalidInput,
  401 => PromotionTargetFailureCode.unauthorized,
  403 => PromotionTargetFailureCode.forbidden,
  409 => PromotionTargetFailureCode.conflict,
  _ => PromotionTargetFailureCode.serverRejected,
};

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

Uri _validatedBaseUri(Uri value) {
  final localHttp =
      value.scheme == 'http' &&
      const {'localhost', '127.0.0.1', '::1'}.contains(value.host);
  if (!value.hasScheme || value.host.isEmpty) {
    throw const FormatException('BACKEND_BASE_URL must be an absolute URL');
  }
  if (value.scheme != 'https' && !localHttp) {
    throw const FormatException(
      'BACKEND_BASE_URL must use HTTPS except on localhost',
    );
  }
  return value;
}
