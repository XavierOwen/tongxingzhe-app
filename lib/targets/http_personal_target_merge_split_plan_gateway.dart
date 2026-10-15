import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../foundation/backend_base_uri.dart';
import '../identity/identity_session.dart';
import 'personal_target_merge_split_plan.dart';
import 'promotion_target.dart';

const _backendBaseUrl = String.fromEnvironment('BACKEND_BASE_URL');

PersonalTargetMergeSplitPlanGateway
productionPersonalTargetMergeSplitPlanGateway(IdentitySession identitySession) {
  if (_backendBaseUrl.trim().isEmpty) {
    return const DeferredPersonalTargetMergeSplitPlanGateway();
  }
  return HttpPersonalTargetMergeSplitPlanGateway(
    baseUri: Uri.parse(_backendBaseUrl),
    identitySession: identitySession,
    client: http.Client(),
  );
}

final class DeferredPersonalTargetMergeSplitPlanGateway
    implements PersonalTargetMergeSplitPlanGateway {
  const DeferredPersonalTargetMergeSplitPlanGateway();

  @override
  Future<PersonalTargetMergeSplitPlanResult> read({
    required String expectedSubject,
    required String workspaceId,
    required String projectId,
    required String generationId,
    required bool Function() requestIsCurrent,
  }) async => const PersonalTargetMergeSplitPlanRejected(
    PersonalTargetMergeSplitPlanFailure.networkUnavailable,
  );

  @override
  Future<void> close() async {}
}

final class HttpPersonalTargetMergeSplitPlanGateway
    implements PersonalTargetMergeSplitPlanGateway {
  factory HttpPersonalTargetMergeSplitPlanGateway({
    required Uri baseUri,
    required IdentitySession identitySession,
    required http.Client client,
    Duration timeout = const Duration(seconds: 15),
  }) => HttpPersonalTargetMergeSplitPlanGateway._(
    validateBackendBaseUri(baseUri),
    identitySession,
    client,
    timeout,
  );

  HttpPersonalTargetMergeSplitPlanGateway._(
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
  Future<PersonalTargetMergeSplitPlanResult> read({
    required String expectedSubject,
    required String workspaceId,
    required String projectId,
    required String generationId,
    required bool Function() requestIsCurrent,
  }) async {
    if (_closed || !requestIsCurrent()) {
      return _rejected(PersonalTargetMergeSplitPlanFailure.requestInvalidated);
    }
    bool matchesIdentity(IdentitySnapshot snapshot) =>
        snapshot.stage == IdentityStage.signedIn &&
        snapshot.principal?.externalSubject == expectedSubject;
    if (!matchesIdentity(_identitySession.current)) {
      return _rejected(PersonalTargetMergeSplitPlanFailure.unauthenticated);
    }
    if (!_isUuid(workspaceId) ||
        !_isUuid(projectId) ||
        !_isUuid(generationId)) {
      return _rejected(PersonalTargetMergeSplitPlanFailure.invalidRequest);
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
    PersonalTargetMergeSplitPlanResult result;
    try {
      result = await _read(workspaceId, projectId, generationId, isCurrent);
    } on FormatException {
      result = _rejected(PersonalTargetMergeSplitPlanFailure.invalidResponse);
    } on TimeoutException {
      result = _rejected(
        PersonalTargetMergeSplitPlanFailure.networkUnavailable,
      );
    } on http.ClientException {
      result = _rejected(
        PersonalTargetMergeSplitPlanFailure.networkUnavailable,
      );
    } on Exception {
      result = _rejected(
        PersonalTargetMergeSplitPlanFailure.networkUnavailable,
      );
    } finally {
      await subscription.cancel();
    }
    return isCurrent()
        ? result
        : _rejected(PersonalTargetMergeSplitPlanFailure.requestInvalidated);
  }

  Future<PersonalTargetMergeSplitPlanResult> _read(
    String workspaceId,
    String projectId,
    String generationId,
    bool Function() isCurrent,
  ) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      if (!isCurrent()) {
        return _rejected(
          PersonalTargetMergeSplitPlanFailure.requestInvalidated,
        );
      }
      final token = await _identitySession
          .accessToken(forceRefresh: attempt == 1)
          .timeout(_timeout);
      if (!isCurrent()) {
        return _rejected(
          PersonalTargetMergeSplitPlanFailure.requestInvalidated,
        );
      }
      if (token is! IdentitySuccess<IdentityAccessToken>) {
        return _rejected(
          token is IdentityRejected<IdentityAccessToken> &&
                  token.failure.code == IdentityFailureCode.networkUnavailable
              ? PersonalTargetMergeSplitPlanFailure.networkUnavailable
              : PersonalTargetMergeSplitPlanFailure.unauthenticated,
        );
      }
      final response = await _client
          .send(
            http.Request(
                'GET',
                _baseUri.resolve(
                  '/v1/projects/$projectId/promotion-target-merges/$generationId/split-plan',
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
          PersonalTargetMergeSplitPlanFailure.requestInvalidated,
        );
      }
      if (response.statusCode == 401 && attempt == 0) continue;
      if (response.statusCode != 200) {
        return _rejected(switch (response.statusCode) {
          400 => PersonalTargetMergeSplitPlanFailure.invalidRequest,
          401 => PersonalTargetMergeSplitPlanFailure.unauthenticated,
          403 => PersonalTargetMergeSplitPlanFailure.forbidden,
          503 => PersonalTargetMergeSplitPlanFailure.serviceUnavailable,
          _ => PersonalTargetMergeSplitPlanFailure.invalidResponse,
        });
      }
      if (response.headers['cache-control'] != 'no-store' ||
          response.headers['content-type'] !=
              'application/json; charset=utf-8') {
        throw _invalidResponse();
      }
      final root = _object(jsonDecode(utf8.decode(response.bodyBytes)));
      _keys(root, const ['split_plan']);
      final plan = _plan(
        root['split_plan'],
        workspaceId,
        projectId,
        generationId,
      );
      return isCurrent()
          ? PersonalTargetMergeSplitPlanReady(plan)
          : _rejected(PersonalTargetMergeSplitPlanFailure.requestInvalidated);
    }
    return _rejected(PersonalTargetMergeSplitPlanFailure.unauthenticated);
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _client.close();
  }
}

PersonalTargetMergeSplitPlan _plan(
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
    'member_target_ids',
    'review_due_at_utc',
    'fact_count',
    'fact_fingerprint',
    'facts',
  ]);
  if (!_sameUuid(root['workspace_id'], workspaceId) ||
      !_sameUuid(root['project_id'], projectId) ||
      !_sameUuid(root['generation_id'], generationId)) {
    throw _invalidResponse();
  }
  final targetType = switch (root['target_type']) {
    'person' => PromotionTargetType.person,
    'institution' => PromotionTargetType.institution,
    _ => throw _invalidResponse(),
  };
  final members = _list(root['member_target_ids']).map(_uuidString).toList();
  if (members.length != 2 ||
      members[0].toLowerCase().compareTo(members[1].toLowerCase()) >= 0) {
    throw _invalidResponse();
  }
  final fingerprint = root['fact_fingerprint'];
  if (fingerprint is! String || !_matches(_fingerprint, fingerprint)) {
    throw _invalidResponse();
  }
  final factCount = _integer(root['fact_count'], minimum: 0);
  final factValues = _list(root['facts']);
  if (factCount != factValues.length) throw _invalidResponse();
  final seen = <Record>{};
  final facts = <PersonalTargetMergeSplitPlanFact>[];
  for (final value in factValues) {
    final fact = _object(value);
    _keys(fact, const ['source_target_id', 'metadata']);
    final sourceId = _uuidString(fact['source_target_id']);
    if (!members.any((member) => _sameUuid(sourceId, member))) {
      throw _invalidResponse();
    }
    final (metadata, key) = _metadata(
      fact['metadata'],
      sourceId,
      targetType,
      members,
    );
    if (!seen.add(key)) throw _invalidResponse();
    facts.add(
      PersonalTargetMergeSplitPlanFact(
        sourceTargetId: sourceId,
        metadata: metadata,
      ),
    );
  }
  return PersonalTargetMergeSplitPlan(
    generationId: _uuidString(root['generation_id']),
    workspaceId: _uuidString(root['workspace_id']),
    projectId: _uuidString(root['project_id']),
    targetType: targetType,
    memberTargetIds: members,
    reviewDueAtUtc: _timestamp(root['review_due_at_utc']),
    factCount: factCount,
    factFingerprint: fingerprint,
    facts: facts,
  );
}

(PersonalTargetMergeSplitPlanMetadata, Record) _metadata(
  Object? value,
  String sourceId,
  PromotionTargetType targetType,
  List<String> members,
) {
  final fields = _list(value);
  if (fields.isEmpty) throw _invalidResponse();
  switch (fields[0]) {
    case 'contact_link':
      _length(fields, 4);
      final contactId = fields[1];
      if (contactId is! String || !_sameUuid(fields[3], sourceId)) {
        throw _invalidResponse();
      }
      final revision = _integer(fields[2], minimum: 1);
      final targetId = _uuidString(fields[3]);
      return (
        PersonalTargetMergeSplitPlanContactLink(
          contactId: contactId,
          revisionNumber: revision,
          promotionTargetId: targetId,
        ),
        ('contact_link', contactId, revision, targetId.toLowerCase()),
      );
    case 'project_relationship':
      _length(fields, 5);
      if (!_sameUuid(fields[1], sourceId)) throw _invalidResponse();
      final targetId = _uuidString(fields[1]);
      final projectId = _uuidString(fields[2]);
      return (
        PersonalTargetMergeSplitPlanProjectRelationship(
          promotionTargetId: targetId,
          projectId: projectId,
          currentRevision: _integer(fields[3], minimum: 1),
          updatedAtUtc: _timestamp(fields[4]),
        ),
        (
          'project_relationship',
          targetId.toLowerCase(),
          projectId.toLowerCase(),
        ),
      );
    case 'project_revision':
      _length(fields, 4);
      if (!_sameUuid(fields[1], sourceId)) throw _invalidResponse();
      final targetId = _uuidString(fields[1]);
      final projectId = _uuidString(fields[2]);
      final revision = _integer(fields[3], minimum: 1);
      return (
        PersonalTargetMergeSplitPlanProjectRevision(
          promotionTargetId: targetId,
          projectId: projectId,
          revisionNumber: revision,
        ),
        (
          'project_revision',
          targetId.toLowerCase(),
          projectId.toLowerCase(),
          revision,
        ),
      );
    case 'institution_relationship_person':
    case 'institution_relationship_institution':
    case 'institution_revision_person':
    case 'institution_revision_institution':
      final variant = fields[0] as String;
      final isRelationship = variant.startsWith('institution_relationship_');
      _length(fields, isRelationship ? 7 : 6);
      final endpoint = variant.endsWith('_person')
          ? PersonalTargetMergeSplitPlanInstitutionEndpoint.person
          : PersonalTargetMergeSplitPlanInstitutionEndpoint.institution;
      if ((endpoint ==
              PersonalTargetMergeSplitPlanInstitutionEndpoint.person) !=
          (targetType == PromotionTargetType.person)) {
        throw _invalidResponse();
      }
      final relationshipId = _uuidString(fields[1]);
      final personId = _uuidString(fields[isRelationship ? 2 : 3]);
      final institutionId = _uuidString(fields[isRelationship ? 3 : 4]);
      final otherEndpointId =
          endpoint == PersonalTargetMergeSplitPlanInstitutionEndpoint.person
          ? institutionId
          : personId;
      if (members.any((member) => _sameUuid(otherEndpointId, member)) ||
          !_sameUuid(
            endpoint == PersonalTargetMergeSplitPlanInstitutionEndpoint.person
                ? personId
                : institutionId,
            sourceId,
          )) {
        throw _invalidResponse();
      }
      final revision = _integer(fields[isRelationship ? 4 : 2], minimum: 1);
      final otherId = fields[isRelationship ? 6 : 5];
      final otherGenerationId = otherId == null ? null : _uuidString(otherId);
      if (isRelationship) {
        return (
          PersonalTargetMergeSplitPlanInstitutionRelationship(
            endpoint: endpoint,
            relationshipId: relationshipId,
            personTargetId: personId,
            institutionTargetId: institutionId,
            currentRevision: revision,
            updatedAtUtc: _timestamp(fields[5]),
            otherMergeGenerationId: otherGenerationId,
          ),
          (variant, relationshipId.toLowerCase()),
        );
      }
      return (
        PersonalTargetMergeSplitPlanInstitutionRevision(
          endpoint: endpoint,
          relationshipId: relationshipId,
          revisionNumber: revision,
          personTargetId: personId,
          institutionTargetId: institutionId,
          otherMergeGenerationId: otherGenerationId,
        ),
        (variant, relationshipId.toLowerCase(), revision),
      );
    default:
      throw _invalidResponse();
  }
}

PersonalTargetMergeSplitPlanRejected _rejected(
  PersonalTargetMergeSplitPlanFailure failure,
) => PersonalTargetMergeSplitPlanRejected(failure);

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

void _length(List<Object?> value, int expected) {
  if (value.length != expected) throw _invalidResponse();
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

int _integer(Object? value, {required int minimum}) {
  if (value is! int || value < minimum || value > 9007199254740991) {
    throw _invalidResponse();
  }
  return value;
}

DateTime _timestamp(Object? value) {
  if (value is! String || !_matches(_timestampPattern, value)) {
    throw _invalidResponse();
  }
  final parsed = DateTime.parse(value);
  final canonical =
      '${parsed.toIso8601String().replaceFirst('Z', '').padRight(26, '0')}Z';
  if (parsed.year == 0 || canonical != value) {
    throw _invalidResponse();
  }
  return parsed;
}

FormatException _invalidResponse() =>
    const FormatException('invalid personal target merge split plan response');

final _uuid = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  caseSensitive: false,
);
final _fingerprint = RegExp(r'^[0-9a-f]{64}$');
final _timestampPattern = RegExp(
  r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{6}Z$',
);
