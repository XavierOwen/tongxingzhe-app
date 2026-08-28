import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../foundation/backend_base_uri.dart';
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
  Future<PromotionTargetResult<PromotionTargetRelationship>>
  updateRelationship({
    required String targetId,
    required int expectedRevision,
    required int stage,
    required PromotionTargetRelationshipLifecycle lifecycleStatus,
    required String? followUpNote,
    required PromotionTargetRelationshipReason reason,
    required String? reasonDetail,
    required String mutationId,
    required String? resolvedConflictId,
  }) async => const PromotionTargetRejected(
    PromotionTargetFailureCode.networkUnavailable,
  );

  @override
  Future<PromotionTargetResult<List<PromotionTargetStageAlias>>>
  configureStageAliases({
    required List<PromotionTargetStageAlias> aliases,
  }) async => const PromotionTargetRejected(
    PromotionTargetFailureCode.networkUnavailable,
  );

  @override
  Future<PromotionTargetResult<List<TargetInstitutionRelationship>>>
  loadInstitutionRelationships() async => const PromotionTargetRejected(
    PromotionTargetFailureCode.networkUnavailable,
  );

  @override
  Future<PromotionTargetResult<TargetInstitutionRelationship>>
  createInstitutionRelationship({
    required String personTargetId,
    required String institutionTargetId,
    required TargetInstitutionRelationshipKind kind,
    required String? roleDescription,
    required String mutationId,
  }) async => const PromotionTargetRejected(
    PromotionTargetFailureCode.networkUnavailable,
  );

  @override
  Future<PromotionTargetResult<TargetInstitutionRelationship>>
  endInstitutionRelationship({
    required String relationshipId,
    required int expectedRevision,
    required String mutationId,
  }) async => const PromotionTargetRejected(
    PromotionTargetFailureCode.networkUnavailable,
  );

  @override
  Future<void> close() async {}
}

final class HttpPromotionTargetGateway
    implements PromotionTargetGateway, PromotionTargetRetentionGateway {
  factory HttpPromotionTargetGateway({
    required Uri baseUri,
    required IdentitySession identitySession,
    required http.Client client,
    Duration timeout = const Duration(seconds: 15),
  }) => HttpPromotionTargetGateway._(
    baseUri: validateBackendBaseUri(baseUri),
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
        capturesAuthorizationTime: true,
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

  @override
  Future<PromotionTargetResult<List<PromotionTargetRetentionTask>>>
  loadRetentionTasks() => _request(
    method: 'GET',
    path: '/v1/promotion-target-retention-tasks',
    parse: (root) => _list(root['tasks']).map(_parseRetentionTask).toList(),
  );

  @override
  Future<PromotionTargetResult<PromotionTargetRetentionOutcome>>
  applyRetentionAction({
    required String targetId,
    required PromotionTargetRetentionAction action,
    required PromotionTargetRetentionReason reason,
    required String mutationId,
  }) => _request(
    method: 'POST',
    path: '/v1/promotion-targets/${Uri.encodeComponent(targetId)}/retention',
    body: {
      'action': action.storageValue,
      'reason': reason.storageValue,
      'mutation_id': mutationId,
    },
    parse: _parseRetentionOutcome,
  );

  @override
  Future<PromotionTargetResult<PromotionTargetRelationship>>
  updateRelationship({
    required String targetId,
    required int expectedRevision,
    required int stage,
    required PromotionTargetRelationshipLifecycle lifecycleStatus,
    required String? followUpNote,
    required PromotionTargetRelationshipReason reason,
    required String? reasonDetail,
    required String mutationId,
    required String? resolvedConflictId,
  }) => _request(
    method: 'PATCH',
    path: '/v1/promotion-targets/${Uri.encodeComponent(targetId)}/relationship',
    body: {
      'expected_revision': expectedRevision,
      'stage': stage,
      'lifecycle_status': lifecycleStatus.storageValue,
      'follow_up_note': followUpNote,
      'reason_code': reason.storageValue,
      'reason_detail': reasonDetail,
      'mutation_id': mutationId,
      'resolved_conflict_id': resolvedConflictId,
    },
    parse: (root) => _parseRelationship(root['relationship']),
    parseConflict: (root) => PromotionTargetConflict(
      current: _parseRelationship(root['current']),
      conflictId: _string(root['conflict_id']),
      conflictingFields: _list(
        root['conflicting_fields'],
      ).map(_string).toList(),
      proposed: _parseProposal(root['proposed']),
    ),
  );

  @override
  Future<PromotionTargetResult<List<PromotionTargetStageAlias>>>
  configureStageAliases({required List<PromotionTargetStageAlias> aliases}) =>
      _request(
        method: 'PUT',
        path: '/v1/promotion-target-stage-aliases',
        body: {
          'aliases': aliases
              .map(
                (alias) => {
                  'stage': alias.stage,
                  'display_name': alias.displayName,
                },
              )
              .toList(),
        },
        parse: (root) => _list(root['aliases']).map(_parseStageAlias).toList(),
      );

  @override
  Future<PromotionTargetResult<List<TargetInstitutionRelationship>>>
  loadInstitutionRelationships() => _request(
    method: 'GET',
    path: '/v1/promotion-target-institution-relationships',
    parse: (root) => _list(
      root['relationships'],
    ).map(_parseInstitutionRelationship).toList(),
  );

  @override
  Future<PromotionTargetResult<TargetInstitutionRelationship>>
  createInstitutionRelationship({
    required String personTargetId,
    required String institutionTargetId,
    required TargetInstitutionRelationshipKind kind,
    required String? roleDescription,
    required String mutationId,
  }) => _request(
    method: 'POST',
    path: '/v1/promotion-target-institution-relationships',
    body: {
      'person_target_id': personTargetId,
      'institution_target_id': institutionTargetId,
      'relationship_kind': kind.storageValue,
      'role_description': roleDescription,
      'mutation_id': mutationId,
    },
    parse: (root) => _parseInstitutionRelationship(root['relationship']),
  );

  @override
  Future<PromotionTargetResult<TargetInstitutionRelationship>>
  endInstitutionRelationship({
    required String relationshipId,
    required int expectedRevision,
    required String mutationId,
  }) => _request(
    method: 'POST',
    path:
        '/v1/promotion-target-institution-relationships/'
        '${Uri.encodeComponent(relationshipId)}/end',
    body: {'expected_revision': expectedRevision, 'mutation_id': mutationId},
    parse: (root) => _parseInstitutionRelationship(root['relationship']),
  );

  Future<PromotionTargetResult<T>> _request<T>({
    required String method,
    required T Function(Map<String, Object?> root) parse,
    String path = '/v1/promotion-targets',
    Map<String, Object?>? body,
    PromotionTargetResult<T> Function(Map<String, Object?> root)? parseConflict,
    bool capturesAuthorizationTime = false,
  }) async {
    try {
      var token = await _identitySession.accessToken();
      if (token is! IdentitySuccess<IdentityAccessToken>) {
        return const PromotionTargetRejected(
          PromotionTargetFailureCode.unauthorized,
        );
      }
      var response = await _send(method, path, token.value, body);
      if (response.statusCode == 401) {
        token = await _identitySession.accessToken(forceRefresh: true);
        if (token is! IdentitySuccess<IdentityAccessToken>) {
          return const PromotionTargetRejected(
            PromotionTargetFailureCode.unauthorized,
          );
        }
        response = await _send(method, path, token.value, body);
      }
      if (response.statusCode == 409 && parseConflict != null) {
        final decoded = jsonDecode(response.body);
        if (decoded is! Map<String, Object?>) {
          throw const FormatException('target conflict must be an object');
        }
        return parseConflict(decoded);
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return PromotionTargetRejected(_failure(response.statusCode));
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, Object?>) {
        throw const FormatException('target response must be an object');
      }
      return PromotionTargetSuccess(
        parse(decoded),
        authorizedAtUtc: capturesAuthorizationTime
            ? DateTime.parse(_string(decoded['authorized_at'])).toUtc()
            : null,
      );
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
    String path,
    IdentityAccessToken token,
    Map<String, Object?>? body,
  ) => _client
      .send(
        http.Request(method, _baseUri.resolve(path))
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
    hasCurrentProjectRelationship: _bool(
      root['has_current_project_relationship'] ?? false,
    ),
    projectRelationship: root['project_relationship'] == null
        ? null
        : _parseRelationship(root['project_relationship']),
  );
}

PromotionTargetRetentionTask _parseRetentionTask(Object? value) {
  final root = _object(value);
  return PromotionTargetRetentionTask(
    targetId: _string(root['target_id']),
    reviewDueAtUtc: DateTime.parse(_string(root['review_due_at'])).toUtc(),
  );
}

PromotionTargetRetentionOutcome _parseRetentionOutcome(
  Map<String, Object?> root,
) => PromotionTargetRetentionOutcome(
  targetId: _string(root['target_id']),
  status: PromotionTargetRetentionStatus.values.firstWhere(
    (candidate) => candidate.storageValue == _string(root['status']),
  ),
  duplicate: _bool(root['duplicate']),
  reviewDueAtUtc: root['review_due_at'] == null
      ? null
      : DateTime.parse(_string(root['review_due_at'])).toUtc(),
);

PromotionTargetRelationship _parseRelationship(Object? value) {
  final root = _object(value);
  return PromotionTargetRelationship(
    targetId: _string(root['target_id']),
    projectId: _string(root['project_id']),
    stage: _integer(root['stage'], minimum: 0, maximum: 4),
    displayStage: _integer(root['display_stage'], minimum: 0, maximum: 8),
    lifecycleStatus: PromotionTargetRelationshipLifecycle.values.firstWhere(
      (candidate) =>
          candidate.storageValue == _string(root['lifecycle_status']),
    ),
    followUpNote: _nullableString(root['follow_up_note']),
    revisionNumber: _integer(root['revision_number'], minimum: 1),
    updatedAtUtc: DateTime.parse(_string(root['updated_at'])).toUtc(),
    stageAliases: _list(root['stage_aliases']).map(_parseStageAlias).toList(),
    history: _list(root['history']).map(_parseRevision).toList(),
  );
}

PromotionTargetStageAlias _parseStageAlias(Object? value) {
  final root = _object(value);
  return PromotionTargetStageAlias(
    stage: _integer(root['stage'], minimum: 0, maximum: 4),
    displayStage: _integer(root['display_stage'], minimum: 0, maximum: 8),
    displayName: _nullableString(root['display_name']),
  );
}

PromotionTargetRelationshipRevision _parseRevision(Object? value) {
  final root = _object(value);
  return PromotionTargetRelationshipRevision(
    revisionNumber: _integer(root['revision_number'], minimum: 1),
    oldStage: _nullableInteger(root['old_stage'], minimum: 0, maximum: 4),
    newStage: _integer(root['new_stage'], minimum: 0, maximum: 4),
    oldLifecycleStatus: root['old_lifecycle_status'] == null
        ? null
        : PromotionTargetRelationshipLifecycle.values.firstWhere(
            (candidate) =>
                candidate.storageValue == _string(root['old_lifecycle_status']),
          ),
    newLifecycleStatus: PromotionTargetRelationshipLifecycle.values.firstWhere(
      (candidate) =>
          candidate.storageValue == _string(root['new_lifecycle_status']),
    ),
    followUpNote: _nullableString(root['follow_up_note']),
    changedFields: _list(root['changed_fields']).map(_string).toList(),
    reasonCode: _string(root['reason_code']),
    reasonDetail: _nullableString(root['reason_detail']),
    changedByAppUserId: _string(root['changed_by_app_user_id']),
    changedAtUtc: DateTime.parse(_string(root['changed_at'])).toUtc(),
  );
}

PromotionTargetRelationshipProposal _parseProposal(Object? value) {
  final root = _object(value);
  return PromotionTargetRelationshipProposal(
    expectedRevision: _integer(root['expected_revision'], minimum: 1),
    stage: _integer(root['stage'], minimum: 0, maximum: 4),
    displayStage: _integer(root['display_stage'], minimum: 0, maximum: 8),
    lifecycleStatus: PromotionTargetRelationshipLifecycle.values.firstWhere(
      (candidate) =>
          candidate.storageValue == _string(root['lifecycle_status']),
    ),
    followUpNote: _nullableString(root['follow_up_note']),
    reason: PromotionTargetRelationshipReason.values.firstWhere(
      (candidate) => candidate.storageValue == _string(root['reason_code']),
    ),
    reasonDetail: _nullableString(root['reason_detail']),
  );
}

TargetInstitutionRelationship _parseInstitutionRelationship(Object? value) {
  final root = _object(value);
  return TargetInstitutionRelationship(
    id: _string(root['relationship_id']),
    personTargetId: _string(root['person_target_id']),
    institutionTargetId: _string(root['institution_target_id']),
    kind: TargetInstitutionRelationshipKind.values.firstWhere(
      (candidate) =>
          candidate.storageValue == _string(root['relationship_kind']),
    ),
    roleDescription: _nullableString(root['role_description']),
    startedAtUtc: DateTime.parse(_string(root['started_at'])).toUtc(),
    endedAtUtc: root['ended_at'] == null
        ? null
        : DateTime.parse(_string(root['ended_at'])).toUtc(),
    status: TargetInstitutionRelationshipStatus.values.firstWhere(
      (candidate) => candidate.storageValue == _string(root['status']),
    ),
    revisionNumber: _integer(root['revision_number'], minimum: 1),
    history: _list(
      root['history'],
    ).map(_parseInstitutionRelationshipRevision).toList(),
  );
}

TargetInstitutionRelationshipRevision _parseInstitutionRelationshipRevision(
  Object? value,
) {
  final root = _object(value);
  return TargetInstitutionRelationshipRevision(
    revisionNumber: _integer(root['revision_number'], minimum: 1),
    event: TargetInstitutionRelationshipEvent.values.firstWhere(
      (candidate) => candidate.storageValue == _string(root['event_type']),
    ),
    oldStatus: root['old_status'] == null
        ? null
        : TargetInstitutionRelationshipStatus.values.firstWhere(
            (candidate) =>
                candidate.storageValue == _string(root['old_status']),
          ),
    newStatus: TargetInstitutionRelationshipStatus.values.firstWhere(
      (candidate) => candidate.storageValue == _string(root['new_status']),
    ),
    endedAtUtc: root['ended_at'] == null
        ? null
        : DateTime.parse(_string(root['ended_at'])).toUtc(),
    changedByAppUserId: _string(root['changed_by_app_user_id']),
    changedAtUtc: DateTime.parse(_string(root['changed_at'])).toUtc(),
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

bool _bool(Object? value) {
  if (value is! bool) throw const FormatException('expected boolean');
  return value;
}

int _integer(Object? value, {required int minimum, int? maximum}) {
  if (value is! int ||
      value < minimum ||
      (maximum != null && value > maximum)) {
    throw const FormatException('expected bounded integer');
  }
  return value;
}

int? _nullableInteger(Object? value, {required int minimum, int? maximum}) =>
    value == null ? null : _integer(value, minimum: minimum, maximum: maximum);

String? _nullableString(Object? value) => value == null ? null : _string(value);
