import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../features/contact_journal/contact_models.dart';
import '../foundation/backend_base_uri.dart';
import '../identity/identity_session.dart';
import 'personal_target_merge_projection.dart';
import 'promotion_target.dart';

const _backendBaseUrl = String.fromEnvironment('BACKEND_BASE_URL');

PersonalTargetMergeProjectionGateway
productionPersonalTargetMergeProjectionGateway(
  IdentitySession identitySession,
) {
  if (_backendBaseUrl.trim().isEmpty) {
    return const DeferredPersonalTargetMergeProjectionGateway();
  }
  return HttpPersonalTargetMergeProjectionGateway(
    baseUri: Uri.parse(_backendBaseUrl),
    identitySession: identitySession,
    client: http.Client(),
  );
}

final class DeferredPersonalTargetMergeProjectionGateway
    implements PersonalTargetMergeProjectionGateway {
  const DeferredPersonalTargetMergeProjectionGateway();

  @override
  Future<PersonalTargetMergeProjectionResult> read({
    required String expectedSubject,
    required String workspaceId,
    required String projectId,
    required String generationId,
    required bool Function() requestIsCurrent,
  }) async => const PersonalTargetMergeProjectionRejected(
    PersonalTargetMergeProjectionFailure.networkUnavailable,
  );

  @override
  Future<void> close() async {}
}

final class HttpPersonalTargetMergeProjectionGateway
    implements PersonalTargetMergeProjectionGateway {
  factory HttpPersonalTargetMergeProjectionGateway({
    required Uri baseUri,
    required IdentitySession identitySession,
    required http.Client client,
    Duration timeout = const Duration(seconds: 15),
  }) => HttpPersonalTargetMergeProjectionGateway._(
    validateBackendBaseUri(baseUri),
    identitySession,
    client,
    timeout,
  );

  HttpPersonalTargetMergeProjectionGateway._(
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
  Future<PersonalTargetMergeProjectionResult> read({
    required String expectedSubject,
    required String workspaceId,
    required String projectId,
    required String generationId,
    required bool Function() requestIsCurrent,
  }) async {
    if (_closed || !requestIsCurrent()) {
      return _rejected(PersonalTargetMergeProjectionFailure.requestInvalidated);
    }
    bool matchesIdentity(IdentitySnapshot snapshot) =>
        snapshot.stage == IdentityStage.signedIn &&
        snapshot.principal?.externalSubject == expectedSubject;
    if (!matchesIdentity(_identitySession.current)) {
      return _rejected(PersonalTargetMergeProjectionFailure.unauthenticated);
    }
    if (!_uuid.hasMatch(workspaceId) ||
        !_uuid.hasMatch(projectId) ||
        !_uuid.hasMatch(generationId)) {
      return _rejected(PersonalTargetMergeProjectionFailure.invalidRequest);
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
    PersonalTargetMergeProjectionResult result;
    try {
      result = await _read(workspaceId, projectId, generationId, isCurrent);
    } on FormatException {
      result = _rejected(PersonalTargetMergeProjectionFailure.invalidResponse);
    } on TimeoutException {
      result = _rejected(
        PersonalTargetMergeProjectionFailure.networkUnavailable,
      );
    } on http.ClientException {
      result = _rejected(
        PersonalTargetMergeProjectionFailure.networkUnavailable,
      );
    } on Exception {
      result = _rejected(
        PersonalTargetMergeProjectionFailure.networkUnavailable,
      );
    } finally {
      await subscription.cancel();
    }
    return isCurrent()
        ? result
        : _rejected(PersonalTargetMergeProjectionFailure.requestInvalidated);
  }

  Future<PersonalTargetMergeProjectionResult> _read(
    String workspaceId,
    String projectId,
    String generationId,
    bool Function() isCurrent,
  ) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      if (!isCurrent()) {
        return _rejected(
          PersonalTargetMergeProjectionFailure.requestInvalidated,
        );
      }
      final token = await _identitySession
          .accessToken(forceRefresh: attempt == 1)
          .timeout(_timeout);
      if (!isCurrent()) {
        return _rejected(
          PersonalTargetMergeProjectionFailure.requestInvalidated,
        );
      }
      if (token is! IdentitySuccess<IdentityAccessToken>) {
        return _rejected(
          token is IdentityRejected<IdentityAccessToken> &&
                  token.failure.code == IdentityFailureCode.networkUnavailable
              ? PersonalTargetMergeProjectionFailure.networkUnavailable
              : PersonalTargetMergeProjectionFailure.unauthenticated,
        );
      }
      final response = await _client
          .send(
            http.Request(
                'GET',
                _baseUri.resolve(
                  '/v1/projects/$projectId/promotion-target-merges/$generationId',
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
          PersonalTargetMergeProjectionFailure.requestInvalidated,
        );
      }
      if (response.statusCode == 401 && attempt == 0) continue;
      if (response.statusCode != 200) {
        return _rejected(switch (response.statusCode) {
          400 => PersonalTargetMergeProjectionFailure.invalidRequest,
          401 => PersonalTargetMergeProjectionFailure.unauthenticated,
          403 => PersonalTargetMergeProjectionFailure.forbidden,
          503 => PersonalTargetMergeProjectionFailure.serviceUnavailable,
          _ => PersonalTargetMergeProjectionFailure.invalidResponse,
        });
      }
      if (response.headers['cache-control'] != 'no-store' ||
          response.headers['content-type'] !=
              'application/json; charset=utf-8') {
        throw _invalidResponse();
      }
      final root = _object(jsonDecode(utf8.decode(response.bodyBytes)));
      _keys(root, const ['projection']);
      final projection = _projection(
        root['projection'],
        workspaceId,
        projectId,
        generationId,
      );
      return isCurrent()
          ? PersonalTargetMergeProjectionReady(projection)
          : _rejected(PersonalTargetMergeProjectionFailure.requestInvalidated);
    }
    return _rejected(PersonalTargetMergeProjectionFailure.unauthenticated);
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _client.close();
  }
}

PersonalTargetMergeProjection _projection(
  Object? value,
  String workspaceId,
  String projectId,
  String generationId,
) {
  final root = _object(value);
  _keys(root, const [
    'generation_id',
    'workspace_id',
    'project_id',
    'target_type',
    'retained_target_id',
    'display_name',
    'phone',
    'email',
    'display_name_source_target_id',
    'phone_source_target_id',
    'email_source_target_id',
    'review_due_at_utc',
    'sources',
  ]);
  if (!_sameUuid(root['workspace_id'], workspaceId) ||
      !_sameUuid(root['project_id'], projectId) ||
      !_sameUuid(root['generation_id'], generationId)) {
    throw _invalidResponse();
  }
  final type = _enum(
    PromotionTargetType.values,
    root['target_type'],
    (value) => value.storageValue,
  );
  final sourceValues = _list(root['sources']);
  if (sourceValues.length != 2) throw _invalidResponse();
  final sources = sourceValues
      .map((value) => _source(value, type, projectId))
      .toList();
  if (sources[0].targetId.toLowerCase().compareTo(
        sources[1].targetId.toLowerCase(),
      ) >=
      0) {
    throw _invalidResponse();
  }
  PersonalTargetMergeProjectionSource selected(Object? id) {
    final targetId = _uuidString(id);
    for (final source in sources) {
      if (_sameUuid(source.targetId, targetId)) return source;
    }
    throw _invalidResponse();
  }

  selected(root['retained_target_id']);
  if (root['display_name'] !=
          selected(root['display_name_source_target_id']).profile.displayName ||
      root['phone'] != selected(root['phone_source_target_id']).profile.phone ||
      root['email'] != selected(root['email_source_target_id']).profile.email) {
    throw _invalidResponse();
  }
  final sourceDues =
      sourceValues
          .map((value) => _dueString(_object(value)['review_due_at_utc']))
          .toList()
        ..sort();
  if (_dueString(root['review_due_at_utc']) != sourceDues.first) {
    throw _invalidResponse();
  }
  return PersonalTargetMergeProjection(
    generationId: _uuidString(root['generation_id']),
    workspaceId: _uuidString(root['workspace_id']),
    projectId: _uuidString(root['project_id']),
    targetType: type,
    retainedTargetId: _uuidString(root['retained_target_id']),
    displayNameSourceTargetId: _uuidString(
      root['display_name_source_target_id'],
    ),
    phoneSourceTargetId: _uuidString(root['phone_source_target_id']),
    emailSourceTargetId: _uuidString(root['email_source_target_id']),
    displayName: _text(root['display_name'], 200),
    phone: _nullableText(root['phone'], 80),
    email: _nullableText(root['email'], 320),
    reviewDueAtUtc: _timestamp(root['review_due_at_utc']),
    sources: sources,
  );
}

PersonalTargetMergeProjectionSource _source(
  Object? value,
  PromotionTargetType type,
  String projectId,
) {
  final root = _object(value);
  _keys(root, const [
    'target_id',
    'profile',
    'review_due_at_utc',
    'project_relationship',
    'contact_links',
    'institution_relationships',
  ]);
  final targetId = _uuidString(root['target_id']);
  final profile = _object(root['profile']);
  _keys(profile, const [
    'target_id',
    'target_type',
    'display_name',
    'phone',
    'email',
    'created_at',
  ]);
  if (!_sameUuid(profile['target_id'], targetId) ||
      profile['target_type'] != type.storageValue) {
    throw _invalidResponse();
  }
  _dueString(root['review_due_at_utc']);
  return PersonalTargetMergeProjectionSource(
    targetId: targetId,
    profile: PersonalTargetMergeSourceProfile(
      targetId: _uuidString(profile['target_id']),
      targetType: type,
      displayName: _text(profile['display_name'], 200),
      phone: _nullableText(profile['phone'], 80),
      email: _nullableText(profile['email'], 320),
      createdAtUtc: _timestamp(profile['created_at']),
    ),
    reviewDueAtUtc: _timestamp(root['review_due_at_utc']),
    projectRelationship: root['project_relationship'] == null
        ? null
        : _relationship(root['project_relationship'], targetId, projectId),
    contactLinks: _list(
      root['contact_links'],
    ).map((value) => _contactLink(value, targetId)).toList(),
    institutionRelationships: _list(
      root['institution_relationships'],
    ).map((value) => _institution(value, targetId, type)).toList(),
  );
}

PersonalTargetMergeProjectRelationship _relationship(
  Object? value,
  String targetId,
  String projectId,
) {
  final root = _object(value);
  _keys(root, const [
    'target_id',
    'project_id',
    'stage',
    'display_stage',
    'lifecycle_status',
    'follow_up_note',
    'revision_number',
    'updated_at',
    'stage_aliases',
    'history',
  ]);
  final stage = _integer(root['stage'], minimum: 0, maximum: 4);
  final aliases = _list(root['stage_aliases']);
  if (!_sameUuid(root['target_id'], targetId) ||
      !_sameUuid(root['project_id'], projectId) ||
      root['display_stage'] != stage * 2 ||
      _list(root['history']).isNotEmpty ||
      aliases.length != 5) {
    throw _invalidResponse();
  }
  final parsedAliases = <PromotionTargetStageAlias>[];
  for (var stage = 0; stage < 5; stage++) {
    final alias = _object(aliases[stage]);
    _keys(alias, const ['stage', 'display_stage', 'display_name']);
    if (alias['stage'] != stage || alias['display_stage'] != stage * 2) {
      throw _invalidResponse();
    }
    parsedAliases.add(
      PromotionTargetStageAlias(
        stage: stage,
        displayStage: stage * 2,
        displayName: _nullableText(alias['display_name'], 80),
      ),
    );
  }
  return PersonalTargetMergeProjectRelationship(
    targetId: _uuidString(root['target_id']),
    projectId: _uuidString(root['project_id']),
    stage: stage,
    displayStage: stage * 2,
    lifecycleStatus: _enum(
      PromotionTargetRelationshipLifecycle.values,
      root['lifecycle_status'],
      (value) => value.storageValue,
    ),
    followUpNote: _nullableText(root['follow_up_note'], 4000),
    revisionNumber: _integer(root['revision_number'], minimum: 1),
    updatedAtUtc: _timestamp(root['updated_at']),
    stageAliases: parsedAliases,
  );
}

PersonalTargetMergeContactLink _contactLink(Object? value, String targetId) {
  final root = _object(value);
  _keys(root, const [
    'contact_id',
    'revision_number',
    'promotion_target_id',
    'response_level',
    'follow_up_consent',
    'institution_representative_confirmed',
    'confirmed_project_entry',
    'merge_generation_id',
  ]);
  if (!_sameUuid(root['promotion_target_id'], targetId) ||
      root['contact_id'] is! String) {
    throw _invalidResponse();
  }
  return PersonalTargetMergeContactLink(
    contactId: root['contact_id'] as String,
    promotionTargetId: _uuidString(root['promotion_target_id']),
    revisionNumber: _integer(root['revision_number'], minimum: 1),
    responseLevel: root['response_level'] == null
        ? null
        : _integer(root['response_level'], minimum: 0, maximum: 4),
    followUpConsent: _enum(
      ContactFollowUpConsent.values,
      root['follow_up_consent'],
      (value) => value.storageValue,
    ),
    institutionRepresentativeConfirmed: _boolean(
      root['institution_representative_confirmed'],
    ),
    confirmedProjectEntry: _boolean(root['confirmed_project_entry']),
    mergeGenerationId: root['merge_generation_id'] == null
        ? null
        : _uuidString(root['merge_generation_id']),
  );
}

PersonalTargetMergeInstitutionRelationship _institution(
  Object? value,
  String targetId,
  PromotionTargetType type,
) {
  final root = _object(value);
  _keys(root, const [
    'relationship_id',
    'person_target_id',
    'institution_target_id',
    'relationship_kind',
    'role_description',
    'started_at',
    'ended_at',
    'status',
    'revision_number',
  ]);
  final personId = _uuidString(root['person_target_id']);
  final institutionId = _uuidString(root['institution_target_id']);
  final startedAt = _timestamp(root['started_at']);
  final endedAt = root['ended_at'] == null
      ? null
      : _timestamp(root['ended_at']);
  final kind = _enum(
    TargetInstitutionRelationshipKind.values,
    root['relationship_kind'],
    (value) => value.storageValue,
  );
  final role = _nullableText(root['role_description'], 500);
  if (_sameUuid(personId, institutionId) ||
      !_sameUuid(
        type == PromotionTargetType.person ? personId : institutionId,
        targetId,
      ) ||
      root['status'] != (endedAt == null ? 'active' : 'ended') ||
      endedAt != null && endedAt.isBefore(startedAt) ||
      kind == TargetInstitutionRelationshipKind.other && role == null) {
    throw _invalidResponse();
  }
  return PersonalTargetMergeInstitutionRelationship(
    id: _uuidString(root['relationship_id']),
    personTargetId: personId,
    institutionTargetId: institutionId,
    kind: kind,
    roleDescription: role,
    startedAtUtc: startedAt,
    endedAtUtc: endedAt,
    status: _enum(
      TargetInstitutionRelationshipStatus.values,
      root['status'],
      (value) => value.storageValue,
    ),
    revisionNumber: _integer(root['revision_number'], minimum: 1),
  );
}

PersonalTargetMergeProjectionRejected _rejected(
  PersonalTargetMergeProjectionFailure failure,
) => PersonalTargetMergeProjectionRejected(failure);

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

String _uuidString(Object? value) {
  if (value is! String || !_uuid.hasMatch(value)) throw _invalidResponse();
  return value;
}

bool _sameUuid(Object? left, String right) =>
    _uuidString(left).toLowerCase() == right.toLowerCase();

String _text(Object? value, int maximum) {
  if (value is! String) throw _invalidResponse();
  final length = value.replaceAll(RegExp(r'^ +| +$'), '').runes.length;
  if (length < 1 || length > maximum) throw _invalidResponse();
  return value;
}

String? _nullableText(Object? value, int maximum) =>
    value == null ? null : _text(value, maximum);

int _integer(Object? value, {required int minimum, int? maximum}) {
  if (value is! int ||
      value < minimum ||
      value > 9007199254740991 ||
      maximum != null && value > maximum) {
    throw _invalidResponse();
  }
  return value;
}

bool _boolean(Object? value) {
  if (value is! bool) throw _invalidResponse();
  return value;
}

T _enum<T>(List<T> values, Object? value, String Function(T) storageValue) {
  for (final candidate in values) {
    if (storageValue(candidate) == value) return candidate;
  }
  throw _invalidResponse();
}

String _dueString(Object? value) {
  if (value is! String || !_due.hasMatch(value)) throw _invalidResponse();
  _timestamp(value);
  return value;
}

DateTime _timestamp(Object? value) {
  if (value is! String) throw _invalidResponse();
  final match = _timestampPattern.firstMatch(value);
  if (match == null) throw _invalidResponse();
  final parts = [for (var i = 1; i <= 6; i++) int.parse(match.group(i)!)];
  final local = DateTime.utc(
    parts[0],
    parts[1],
    parts[2],
    parts[3],
    parts[4],
    parts[5],
  );
  if (parts[0] == 0 ||
      local.year != parts[0] ||
      local.month != parts[1] ||
      local.day != parts[2] ||
      local.hour != parts[3] ||
      local.minute != parts[4] ||
      local.second != parts[5]) {
    throw _invalidResponse();
  }
  final offset = match.group(8)!;
  if (offset != 'Z' &&
      (int.parse(offset.substring(1, 3)) > 23 ||
          int.parse(offset.substring(4, 6)) > 59)) {
    throw _invalidResponse();
  }
  return DateTime.parse(value).toUtc();
}

FormatException _invalidResponse() =>
    const FormatException('invalid personal target merge projection response');

final _uuid = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  caseSensitive: false,
);
final _due = RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{6}Z$');
final _timestampPattern = RegExp(
  r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.(\d{1,6}))?(Z|[+-]\d{2}:\d{2})$',
);
