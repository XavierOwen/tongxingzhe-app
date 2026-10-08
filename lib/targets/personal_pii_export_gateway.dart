import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../foundation/backend_base_uri.dart';
import '../identity/identity_session.dart';

const _backendBaseUrl = String.fromEnvironment('BACKEND_BASE_URL');

PersonalPiiExportGateway productionPersonalPiiExportGateway(
  IdentitySession identitySession,
) {
  if (_backendBaseUrl.trim().isEmpty) {
    return const DeferredPersonalPiiExportGateway();
  }
  return HttpPersonalPiiExportGateway(
    baseUri: Uri.parse(_backendBaseUrl),
    identitySession: identitySession,
    client: http.Client(),
  );
}

abstract interface class PersonalPiiExportGateway {
  Future<PersonalPiiExportResult> export({
    required bool Function() requestIsCurrent,
  });

  Future<void> close();
}

final class DeferredPersonalPiiExportGateway
    implements PersonalPiiExportGateway {
  const DeferredPersonalPiiExportGateway();

  @override
  Future<PersonalPiiExportResult> export({
    required bool Function() requestIsCurrent,
  }) async => const PersonalPiiExportRejected(
    PersonalPiiExportFailure.networkUnavailable,
  );

  @override
  Future<void> close() async {}
}

sealed class PersonalPiiExportResult {
  const PersonalPiiExportResult();
}

final class PersonalPiiExportReady extends PersonalPiiExportResult {
  const PersonalPiiExportReady(this.artifact);

  final PersonalPiiExportArtifact artifact;
}

final class PersonalPiiExportRejected extends PersonalPiiExportResult {
  const PersonalPiiExportRejected(this.failure);

  final PersonalPiiExportFailure failure;
}

enum PersonalPiiExportFailure {
  unauthenticated,
  reauthenticationRequired,
  exportForbidden,
  serviceUnavailable,
  networkUnavailable,
  invalidResponse,
}

final class PersonalPiiExportArtifact {
  PersonalPiiExportArtifact({required List<int> bytes})
    : bytes = List<int>.unmodifiable(bytes);

  final List<int> bytes;
  String get fileName => _fileName;
  String get contentType => _contentType;
}

final class HttpPersonalPiiExportGateway implements PersonalPiiExportGateway {
  factory HttpPersonalPiiExportGateway({
    required Uri baseUri,
    required IdentitySession identitySession,
    required http.Client client,
    Duration timeout = const Duration(seconds: 15),
  }) => HttpPersonalPiiExportGateway._(
    baseUri: validateBackendBaseUri(baseUri),
    identitySession: identitySession,
    client: client,
    timeout: timeout,
  );

  HttpPersonalPiiExportGateway._({
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
  Future<PersonalPiiExportResult> export({
    required bool Function() requestIsCurrent,
  }) async {
    StreamSubscription<IdentitySnapshot>? identitySubscription;
    final subject = _identitySession.current.principal?.externalSubject;
    var identityChanged = false;
    bool matchesIdentity(IdentitySnapshot snapshot) =>
        subject != null &&
        snapshot.stage == IdentityStage.signedIn &&
        snapshot.principal?.externalSubject == subject;
    bool isCurrent() =>
        !identityChanged &&
        requestIsCurrent() &&
        matchesIdentity(_identitySession.current);
    try {
      if (!isCurrent()) {
        return const PersonalPiiExportRejected(
          PersonalPiiExportFailure.unauthenticated,
        );
      }
      identitySubscription = _identitySession.changes.listen(
        (snapshot) {
          if (!matchesIdentity(snapshot)) identityChanged = true;
        },
        onError: (Object error, StackTrace stackTrace) =>
            identityChanged = true,
        onDone: () => identityChanged = true,
      );
      if (!isCurrent()) {
        return const PersonalPiiExportRejected(
          PersonalPiiExportFailure.unauthenticated,
        );
      }
      final token = await _identitySession.accessToken();
      if (!isCurrent()) {
        return const PersonalPiiExportRejected(
          PersonalPiiExportFailure.unauthenticated,
        );
      }
      if (token is! IdentitySuccess<IdentityAccessToken>) {
        return const PersonalPiiExportRejected(
          PersonalPiiExportFailure.unauthenticated,
        );
      }
      final response = await _client
          .send(
            http.Request('GET', _baseUri.resolve(_path))
              ..headers.addAll({
                'authorization': 'Bearer ${token.value.value}',
                'accept': 'application/json',
              }),
          )
          .then(http.Response.fromStream)
          .timeout(_timeout);
      if (!isCurrent()) {
        return const PersonalPiiExportRejected(
          PersonalPiiExportFailure.unauthenticated,
        );
      }

      if (response.statusCode == 401) {
        return const PersonalPiiExportRejected(
          PersonalPiiExportFailure.unauthenticated,
        );
      }
      if (response.statusCode == 403) {
        return PersonalPiiExportRejected(_forbiddenFailure(response.bodyBytes));
      }
      if (response.statusCode == 503) {
        return const PersonalPiiExportRejected(
          PersonalPiiExportFailure.serviceUnavailable,
        );
      }
      if (response.statusCode != 200) {
        return const PersonalPiiExportRejected(
          PersonalPiiExportFailure.invalidResponse,
        );
      }
      _validateSuccess(response);
      return PersonalPiiExportReady(
        PersonalPiiExportArtifact(bytes: response.bodyBytes),
      );
    } on TimeoutException {
      return const PersonalPiiExportRejected(
        PersonalPiiExportFailure.networkUnavailable,
      );
    } on http.ClientException {
      return const PersonalPiiExportRejected(
        PersonalPiiExportFailure.networkUnavailable,
      );
    } on FormatException {
      return const PersonalPiiExportRejected(
        PersonalPiiExportFailure.invalidResponse,
      );
    } on Exception {
      return const PersonalPiiExportRejected(
        PersonalPiiExportFailure.networkUnavailable,
      );
    } finally {
      await identitySubscription?.cancel();
    }
  }

  @override
  Future<void> close() async => _client.close();
}

void _validateSuccess(http.Response response) {
  final headers = response.headers;
  if (_header(headers, 'content-type') != _contentType ||
      _header(headers, 'content-disposition') != _contentDisposition ||
      _header(headers, 'cache-control') != 'no-store' ||
      _header(headers, 'x-content-type-options') != 'nosniff' ||
      !RegExp(
        r'^(?:0|[1-9]\d*)$',
      ).hasMatch(_header(headers, 'content-length').trim()) ||
      int.tryParse(_header(headers, 'content-length').trim()) !=
          response.bodyBytes.length) {
    throw const FormatException('invalid export response');
  }

  final body = utf8.decode(response.bodyBytes);
  final decoded = jsonDecode(body);
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('invalid export response');
  }
  _requireOrderedKeys(decoded, const [
    'export_contract_id',
    'export_event_id',
    'exported_at_utc',
    'targets',
  ]);
  if (decoded['export_contract_id'] != _contractId ||
      !_uuid.hasMatch(_string(decoded['export_event_id'])) ||
      !_isCanonicalUtcTimestamp(decoded['exported_at_utc']) ||
      decoded['targets'] is! List) {
    throw const FormatException('invalid export response');
  }
  for (final value in decoded['targets'] as List<Object?>) {
    if (value is! Map<String, dynamic>) {
      throw const FormatException('invalid export response');
    }
    _requireOrderedKeys(value, const [
      'target_type',
      'display_name',
      'phone',
      'email',
    ]);
    if (!const {'person', 'institution'}.contains(value['target_type']) ||
        value['display_name'] is! String ||
        !_nullableString(value['phone']) ||
        !_nullableString(value['email'])) {
      throw const FormatException('invalid export response');
    }
  }
  if (jsonEncode(decoded) != body) {
    throw const FormatException('invalid export response');
  }
}

PersonalPiiExportFailure _forbiddenFailure(List<int> bodyBytes) {
  try {
    final body = jsonDecode(utf8.decode(bodyBytes));
    if (body is Map<String, dynamic> &&
        body['error'] is Map<String, dynamic> &&
        (body['error'] as Map<String, dynamic>)['code'] ==
            'reauthentication_required') {
      return PersonalPiiExportFailure.reauthenticationRequired;
    }
  } on FormatException {
    // The status still safely maps to the generic forbidden result.
  }
  return PersonalPiiExportFailure.exportForbidden;
}

String _header(Map<String, String> headers, String name) => headers[name] ?? '';

bool _nullableString(Object? value) => value == null || value is String;

String _string(Object? value) => value is String ? value : '';

bool _isCanonicalUtcTimestamp(Object? value) {
  if (value is! String ||
      !RegExp(
        r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$',
      ).hasMatch(value)) {
    return false;
  }
  final parsed = DateTime.tryParse(value);
  return parsed != null && parsed.toIso8601String() == value;
}

void _requireOrderedKeys(Map<String, dynamic> value, List<String> expected) {
  final actual = value.keys.toList();
  if (actual.length != expected.length) {
    throw const FormatException('invalid export response');
  }
  for (var i = 0; i < actual.length; i++) {
    if (actual[i] != expected[i]) {
      throw const FormatException('invalid export response');
    }
  }
}

const _path = '/v1/promotion-targets/export';
const _contractId = 'personal_promotion_target_pii_export_v1';
const _contentType = 'application/json; charset=utf-8';
const _fileName = 'personal-promotion-target-pii-v1.json';
const _contentDisposition = 'attachment; filename="$_fileName"';
final _uuid = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  caseSensitive: false,
);
