import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../foundation/backend_base_uri.dart';
import '../identity/identity_session.dart';
import 'personal_target_merge_directory.dart';
import 'promotion_target.dart';

const _backendBaseUrl = String.fromEnvironment('BACKEND_BASE_URL');

PersonalTargetMergeDirectoryGateway
productionPersonalTargetMergeDirectoryGateway(IdentitySession identitySession) {
  if (_backendBaseUrl.trim().isEmpty) {
    return const DeferredPersonalTargetMergeDirectoryGateway();
  }
  return HttpPersonalTargetMergeDirectoryGateway(
    baseUri: Uri.parse(_backendBaseUrl),
    identitySession: identitySession,
    client: http.Client(),
  );
}

final class DeferredPersonalTargetMergeDirectoryGateway
    implements PersonalTargetMergeDirectoryGateway {
  const DeferredPersonalTargetMergeDirectoryGateway();

  @override
  Future<PersonalTargetMergeDirectoryResult> read({
    required String expectedSubject,
    required String workspaceId,
    required String projectId,
    String? afterGenerationId,
    required bool Function() requestIsCurrent,
  }) async => const PersonalTargetMergeDirectoryRejected(
    PersonalTargetMergeDirectoryFailure.networkUnavailable,
  );

  @override
  Future<void> close() async {}
}

final class HttpPersonalTargetMergeDirectoryGateway
    implements PersonalTargetMergeDirectoryGateway {
  factory HttpPersonalTargetMergeDirectoryGateway({
    required Uri baseUri,
    required IdentitySession identitySession,
    required http.Client client,
    Duration timeout = const Duration(seconds: 15),
  }) => HttpPersonalTargetMergeDirectoryGateway._(
    validateBackendBaseUri(baseUri),
    identitySession,
    client,
    timeout,
  );

  HttpPersonalTargetMergeDirectoryGateway._(
    this._baseUri,
    this._identitySession,
    this._client,
    this._timeout,
  );

  final Uri _baseUri;
  final IdentitySession _identitySession;
  final http.Client _client;
  final Duration _timeout;
  bool _closed = false;

  @override
  Future<PersonalTargetMergeDirectoryResult> read({
    required String expectedSubject,
    required String workspaceId,
    required String projectId,
    String? afterGenerationId,
    required bool Function() requestIsCurrent,
  }) async {
    if (_closed || !requestIsCurrent()) {
      return _rejected(PersonalTargetMergeDirectoryFailure.requestInvalidated);
    }
    bool matchesIdentity(IdentitySnapshot snapshot) =>
        snapshot.stage == IdentityStage.signedIn &&
        snapshot.principal?.externalSubject == expectedSubject;
    if (!matchesIdentity(_identitySession.current)) {
      return _rejected(PersonalTargetMergeDirectoryFailure.unauthenticated);
    }
    if (!_isUuid(workspaceId) ||
        !_isUuid(projectId) ||
        afterGenerationId != null && !_isUuid(afterGenerationId)) {
      return _rejected(PersonalTargetMergeDirectoryFailure.invalidRequest);
    }

    var identityChanged = false;
    bool isCurrent() =>
        !_closed &&
        !identityChanged &&
        requestIsCurrent() &&
        matchesIdentity(_identitySession.current);
    final subscription = _identitySession.changes.listen(
      (snapshot) {
        if (!matchesIdentity(snapshot)) identityChanged = true;
      },
      onError: (Object error, StackTrace stackTrace) => identityChanged = true,
      onDone: () => identityChanged = true,
    );
    PersonalTargetMergeDirectoryResult result;
    try {
      result = await _read(
        workspaceId,
        projectId,
        afterGenerationId,
        isCurrent,
      );
    } on FormatException {
      result = _rejected(PersonalTargetMergeDirectoryFailure.invalidResponse);
    } on TimeoutException {
      result = _rejected(
        PersonalTargetMergeDirectoryFailure.networkUnavailable,
      );
    } on http.ClientException {
      result = _rejected(
        PersonalTargetMergeDirectoryFailure.networkUnavailable,
      );
    } on Exception {
      result = _rejected(
        PersonalTargetMergeDirectoryFailure.networkUnavailable,
      );
    } finally {
      await subscription.cancel();
    }
    return isCurrent()
        ? result
        : _rejected(PersonalTargetMergeDirectoryFailure.requestInvalidated);
  }

  Future<PersonalTargetMergeDirectoryResult> _read(
    String workspaceId,
    String projectId,
    String? afterGenerationId,
    bool Function() isCurrent,
  ) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      if (!isCurrent()) {
        return _rejected(
          PersonalTargetMergeDirectoryFailure.requestInvalidated,
        );
      }
      final token = await _identitySession
          .accessToken(forceRefresh: attempt == 1)
          .timeout(_timeout);
      if (!isCurrent()) {
        return _rejected(
          PersonalTargetMergeDirectoryFailure.requestInvalidated,
        );
      }
      if (token is! IdentitySuccess<IdentityAccessToken>) {
        return _rejected(
          token is IdentityRejected<IdentityAccessToken> &&
                  token.failure.code == IdentityFailureCode.networkUnavailable
              ? PersonalTargetMergeDirectoryFailure.networkUnavailable
              : PersonalTargetMergeDirectoryFailure.unauthenticated,
        );
      }
      final response = await _client
          .send(
            http.Request(
                'GET',
                _baseUri
                    .resolve('/v1/projects/$projectId/promotion-target-merges')
                    .replace(
                      queryParameters: afterGenerationId == null
                          ? null
                          : {'after': afterGenerationId},
                    ),
              )
              ..headers.addAll({
                'authorization': 'Bearer ${token.value.value}',
                'accept': 'application/json',
              }),
          )
          .then(http.Response.fromStream)
          .timeout(_timeout);
      if (!isCurrent()) {
        return _rejected(
          PersonalTargetMergeDirectoryFailure.requestInvalidated,
        );
      }
      if (response.statusCode == 401 && attempt == 0) continue;
      if (response.statusCode != 200) {
        return _rejected(switch (response.statusCode) {
          400 => PersonalTargetMergeDirectoryFailure.invalidRequest,
          401 => PersonalTargetMergeDirectoryFailure.unauthenticated,
          403 => PersonalTargetMergeDirectoryFailure.forbidden,
          503 => PersonalTargetMergeDirectoryFailure.serviceUnavailable,
          _ => PersonalTargetMergeDirectoryFailure.invalidResponse,
        });
      }
      if (response.headers['cache-control'] != 'no-store' ||
          response.headers['content-type'] !=
              'application/json; charset=utf-8') {
        throw _invalidResponse();
      }
      final root = _object(jsonDecode(utf8.decode(response.bodyBytes)));
      _keys(root, const ['directory']);
      final directory = _directory(
        root['directory'],
        workspaceId,
        projectId,
        afterGenerationId,
      );
      return isCurrent()
          ? PersonalTargetMergeDirectoryReady(directory)
          : _rejected(PersonalTargetMergeDirectoryFailure.requestInvalidated);
    }
    return _rejected(PersonalTargetMergeDirectoryFailure.unauthenticated);
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _client.close();
  }
}

PersonalTargetMergeDirectory _directory(
  Object? value,
  String workspaceId,
  String projectId,
  String? afterGenerationId,
) {
  final root = _object(value);
  _keys(root, const ['workspace_id', 'project_id', 'items', 'next_cursor']);
  if (!_sameUuid(root['workspace_id'], workspaceId) ||
      !_sameUuid(root['project_id'], projectId)) {
    throw _invalidResponse();
  }
  final values = _list(root['items']);
  if (values.length > personalTargetMergeDirectoryPageSize) {
    throw _invalidResponse();
  }
  final items = <PersonalTargetMergeDirectoryItem>[];
  var previous = afterGenerationId?.toLowerCase();
  for (final value in values) {
    final item = _object(value);
    _keys(item, const [
      'generation_id',
      'target_type',
      'retained_target_id',
      'member_target_ids',
      'review_due_at_utc',
    ]);
    final generationId = _uuidString(item['generation_id']);
    if (previous != null &&
        generationId.toLowerCase().compareTo(previous) <= 0) {
      throw _invalidResponse();
    }
    previous = generationId.toLowerCase();
    final type = switch (item['target_type']) {
      'person' => PromotionTargetType.person,
      'institution' => PromotionTargetType.institution,
      _ => throw _invalidResponse(),
    };
    final members = _list(item['member_target_ids']).map(_uuidString).toList();
    final retainedId = _uuidString(item['retained_target_id']);
    if (members.length != 2 ||
        members[0].toLowerCase().compareTo(members[1].toLowerCase()) >= 0 ||
        !members.any((member) => _sameUuid(member, retainedId))) {
      throw _invalidResponse();
    }
    items.add(
      PersonalTargetMergeDirectoryItem(
        generationId: generationId,
        targetType: type,
        retainedTargetId: retainedId,
        memberTargetIds: members,
        reviewDueAtUtc: _timestamp(item['review_due_at_utc']),
      ),
    );
  }
  final nextCursor = root['next_cursor'] == null
      ? null
      : _uuidString(root['next_cursor']);
  if (nextCursor != null &&
      (items.length != personalTargetMergeDirectoryPageSize ||
          !_sameUuid(nextCursor, items.last.generationId))) {
    throw _invalidResponse();
  }
  return PersonalTargetMergeDirectory(
    workspaceId: _uuidString(root['workspace_id']),
    projectId: _uuidString(root['project_id']),
    items: items,
    nextCursor: nextCursor,
  );
}

PersonalTargetMergeDirectoryRejected _rejected(
  PersonalTargetMergeDirectoryFailure failure,
) => PersonalTargetMergeDirectoryRejected(failure);

Map<String, Object?> _object(Object? value) {
  if (value is! Map<String, Object?>) throw _invalidResponse();
  return value;
}

List<Object?> _list(Object? value) {
  if (value is! List<Object?>) throw _invalidResponse();
  return value;
}

void _keys(Map<String, Object?> value, List<String> expected) {
  if (value.length != expected.length ||
      expected.any((key) => !value.containsKey(key))) {
    throw _invalidResponse();
  }
}

bool _matches(RegExp pattern, String value) =>
    pattern.firstMatch(value)?.group(0) == value;
bool _isUuid(String value) => _matches(_uuid, value);
String _uuidString(Object? value) {
  if (value is! String || !_isUuid(value)) throw _invalidResponse();
  return value;
}

bool _sameUuid(Object? left, String right) =>
    _uuidString(left).toLowerCase() == right.toLowerCase();
DateTime _timestamp(Object? value) {
  if (value is! String || !_matches(_timestampPattern, value)) {
    throw _invalidResponse();
  }
  final parsed = DateTime.parse(value);
  final canonical =
      '${parsed.toIso8601String().replaceFirst('Z', '').padRight(26, '0')}Z';
  if (parsed.year == 0 || canonical != value) throw _invalidResponse();
  return parsed;
}

FormatException _invalidResponse() =>
    const FormatException('invalid personal target merge directory response');
final _uuid = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  caseSensitive: false,
);
final _timestampPattern = RegExp(
  r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{6}Z$',
);
