import '../features/contact_journal/contact_models.dart';
import 'promotion_target.dart';

abstract interface class PersonalTargetMergeProjectionGateway {
  Future<PersonalTargetMergeProjectionResult> read({
    required String expectedSubject,
    required String workspaceId,
    required String projectId,
    required String generationId,
    required bool Function() requestIsCurrent,
  });

  Future<void> close();
}

sealed class PersonalTargetMergeProjectionResult {
  const PersonalTargetMergeProjectionResult();
}

final class PersonalTargetMergeProjectionReady
    extends PersonalTargetMergeProjectionResult {
  const PersonalTargetMergeProjectionReady(this.projection);

  final PersonalTargetMergeProjection projection;
}

final class PersonalTargetMergeProjectionRejected
    extends PersonalTargetMergeProjectionResult {
  const PersonalTargetMergeProjectionRejected(this.failure);

  final PersonalTargetMergeProjectionFailure failure;
}

enum PersonalTargetMergeProjectionFailure {
  unauthenticated,
  forbidden,
  invalidRequest,
  serviceUnavailable,
  networkUnavailable,
  invalidResponse,
  requestInvalidated,
}

final class PersonalTargetMergeProjection {
  PersonalTargetMergeProjection({
    required this.generationId,
    required this.workspaceId,
    required this.projectId,
    required this.targetType,
    required this.retainedTargetId,
    required this.displayNameSourceTargetId,
    required this.phoneSourceTargetId,
    required this.emailSourceTargetId,
    required this.displayName,
    required this.phone,
    required this.email,
    required this.reviewDueAtUtc,
    required List<PersonalTargetMergeProjectionSource> sources,
  }) : sources = List.unmodifiable(sources);

  final String generationId;
  final String workspaceId;
  final String projectId;
  final PromotionTargetType targetType;
  final String retainedTargetId;
  final String displayNameSourceTargetId;
  final String phoneSourceTargetId;
  final String emailSourceTargetId;
  final String displayName;
  final String? phone;
  final String? email;
  final DateTime reviewDueAtUtc;
  final List<PersonalTargetMergeProjectionSource> sources;
}

final class PersonalTargetMergeProjectionSource {
  PersonalTargetMergeProjectionSource({
    required this.targetId,
    required this.profile,
    required this.reviewDueAtUtc,
    required this.projectRelationship,
    required List<PersonalTargetMergeContactLink> contactLinks,
    required List<PersonalTargetMergeInstitutionRelationship>
    institutionRelationships,
  }) : contactLinks = List.unmodifiable(contactLinks),
       institutionRelationships = List.unmodifiable(institutionRelationships);

  final String targetId;
  final PersonalTargetMergeSourceProfile profile;
  final DateTime reviewDueAtUtc;
  final PersonalTargetMergeProjectRelationship? projectRelationship;
  final List<PersonalTargetMergeContactLink> contactLinks;
  final List<PersonalTargetMergeInstitutionRelationship>
  institutionRelationships;
}

final class PersonalTargetMergeProjectRelationship {
  PersonalTargetMergeProjectRelationship({
    required this.targetId,
    required this.projectId,
    required this.stage,
    required this.displayStage,
    required this.lifecycleStatus,
    required this.followUpNote,
    required this.revisionNumber,
    required this.updatedAtUtc,
    required List<PromotionTargetStageAlias> stageAliases,
  }) : stageAliases = List.unmodifiable(stageAliases);

  final String targetId;
  final String projectId;
  final int stage;
  final int displayStage;
  final PromotionTargetRelationshipLifecycle lifecycleStatus;
  final String? followUpNote;
  final int revisionNumber;
  final DateTime updatedAtUtc;
  final List<PromotionTargetStageAlias> stageAliases;
}

final class PersonalTargetMergeSourceProfile {
  const PersonalTargetMergeSourceProfile({
    required this.targetId,
    required this.targetType,
    required this.displayName,
    required this.phone,
    required this.email,
    required this.createdAtUtc,
  });

  final String targetId;
  final PromotionTargetType targetType;
  final String displayName;
  final String? phone;
  final String? email;
  final DateTime createdAtUtc;
}

final class PersonalTargetMergeContactLink {
  const PersonalTargetMergeContactLink({
    required this.contactId,
    required this.revisionNumber,
    required this.promotionTargetId,
    required this.responseLevel,
    required this.followUpConsent,
    required this.institutionRepresentativeConfirmed,
    required this.confirmedProjectEntry,
    required this.mergeGenerationId,
  });

  final String contactId;
  final int revisionNumber;
  final String promotionTargetId;
  final int? responseLevel;
  final ContactFollowUpConsent followUpConsent;
  final bool institutionRepresentativeConfirmed;
  final bool confirmedProjectEntry;
  final String? mergeGenerationId;
}

/// The projection carries current relationship facts, not revision history.
final class PersonalTargetMergeInstitutionRelationship {
  const PersonalTargetMergeInstitutionRelationship({
    required this.id,
    required this.personTargetId,
    required this.institutionTargetId,
    required this.kind,
    required this.roleDescription,
    required this.startedAtUtc,
    required this.endedAtUtc,
    required this.status,
    required this.revisionNumber,
  });

  final String id;
  final String personTargetId;
  final String institutionTargetId;
  final TargetInstitutionRelationshipKind kind;
  final String? roleDescription;
  final DateTime startedAtUtc;
  final DateTime? endedAtUtc;
  final TargetInstitutionRelationshipStatus status;
  final int revisionNumber;
}
