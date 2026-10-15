import 'promotion_target.dart';

abstract interface class PersonalTargetMergeSplitPlanGateway {
  Future<PersonalTargetMergeSplitPlanResult> read({
    required String expectedSubject,
    required String workspaceId,
    required String projectId,
    required String generationId,
    required bool Function() requestIsCurrent,
  });

  Future<void> close();
}

sealed class PersonalTargetMergeSplitPlanResult {
  const PersonalTargetMergeSplitPlanResult();
}

final class PersonalTargetMergeSplitPlanReady
    extends PersonalTargetMergeSplitPlanResult {
  const PersonalTargetMergeSplitPlanReady(this.plan);

  final PersonalTargetMergeSplitPlan plan;
}

final class PersonalTargetMergeSplitPlanRejected
    extends PersonalTargetMergeSplitPlanResult {
  const PersonalTargetMergeSplitPlanRejected(this.failure);

  final PersonalTargetMergeSplitPlanFailure failure;
}

enum PersonalTargetMergeSplitPlanFailure {
  unauthenticated,
  forbidden,
  invalidRequest,
  serviceUnavailable,
  networkUnavailable,
  invalidResponse,
  requestInvalidated,
}

final class PersonalTargetMergeSplitPlan {
  PersonalTargetMergeSplitPlan({
    required this.generationId,
    required this.workspaceId,
    required this.projectId,
    required this.targetType,
    required List<String> memberTargetIds,
    required this.reviewDueAtUtc,
    required this.factCount,
    required this.factFingerprint,
    required List<PersonalTargetMergeSplitPlanFact> facts,
  }) : memberTargetIds = List.unmodifiable(memberTargetIds),
       facts = List.unmodifiable(facts);

  final String generationId;
  final String workspaceId;
  final String projectId;
  final PromotionTargetType targetType;
  final List<String> memberTargetIds;
  final DateTime reviewDueAtUtc;
  final int factCount;

  /// Opaque PostgreSQL confirmation fingerprint. It does not retain authorization.
  final String factFingerprint;
  final List<PersonalTargetMergeSplitPlanFact> facts;
}

final class PersonalTargetMergeSplitPlanFact {
  const PersonalTargetMergeSplitPlanFact({
    required this.sourceTargetId,
    required this.metadata,
  });

  final String sourceTargetId;
  final PersonalTargetMergeSplitPlanMetadata metadata;
}

sealed class PersonalTargetMergeSplitPlanMetadata {
  const PersonalTargetMergeSplitPlanMetadata();
}

final class PersonalTargetMergeSplitPlanContactLink
    extends PersonalTargetMergeSplitPlanMetadata {
  const PersonalTargetMergeSplitPlanContactLink({
    required this.contactId,
    required this.revisionNumber,
    required this.promotionTargetId,
  });

  final String contactId;
  final int revisionNumber;
  final String promotionTargetId;
}

final class PersonalTargetMergeSplitPlanProjectRelationship
    extends PersonalTargetMergeSplitPlanMetadata {
  const PersonalTargetMergeSplitPlanProjectRelationship({
    required this.promotionTargetId,
    required this.projectId,
    required this.currentRevision,
    required this.updatedAtUtc,
  });

  final String promotionTargetId;
  final String projectId;
  final int currentRevision;
  final DateTime updatedAtUtc;
}

final class PersonalTargetMergeSplitPlanProjectRevision
    extends PersonalTargetMergeSplitPlanMetadata {
  const PersonalTargetMergeSplitPlanProjectRevision({
    required this.promotionTargetId,
    required this.projectId,
    required this.revisionNumber,
  });

  final String promotionTargetId;
  final String projectId;
  final int revisionNumber;
}

enum PersonalTargetMergeSplitPlanInstitutionEndpoint { person, institution }

final class PersonalTargetMergeSplitPlanInstitutionRelationship
    extends PersonalTargetMergeSplitPlanMetadata {
  const PersonalTargetMergeSplitPlanInstitutionRelationship({
    required this.endpoint,
    required this.relationshipId,
    required this.personTargetId,
    required this.institutionTargetId,
    required this.currentRevision,
    required this.updatedAtUtc,
    required this.otherMergeGenerationId,
  });

  final PersonalTargetMergeSplitPlanInstitutionEndpoint endpoint;
  final String relationshipId;
  final String personTargetId;
  final String institutionTargetId;
  final int currentRevision;
  final DateTime updatedAtUtc;
  final String? otherMergeGenerationId;
}

final class PersonalTargetMergeSplitPlanInstitutionRevision
    extends PersonalTargetMergeSplitPlanMetadata {
  const PersonalTargetMergeSplitPlanInstitutionRevision({
    required this.endpoint,
    required this.relationshipId,
    required this.revisionNumber,
    required this.personTargetId,
    required this.institutionTargetId,
    required this.otherMergeGenerationId,
  });

  final PersonalTargetMergeSplitPlanInstitutionEndpoint endpoint;
  final String relationshipId;
  final int revisionNumber;
  final String personTargetId;
  final String institutionTargetId;
  final String? otherMergeGenerationId;
}
