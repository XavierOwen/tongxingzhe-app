enum PromotionTargetType {
  person('person'),
  institution('institution');

  const PromotionTargetType(this.storageValue);

  final String storageValue;
}

enum PromotionTargetRelationshipLifecycle {
  active('active'),
  paused('paused'),
  ended('ended');

  const PromotionTargetRelationshipLifecycle(this.storageValue);

  final String storageValue;
}

enum PromotionTargetRelationshipReason {
  progressUpdate('progress_update'),
  contactLost('contact_lost'),
  timingChanged('timing_changed'),
  requirementsChanged('requirements_changed'),
  targetRequest('target_request'),
  projectChange('project_change'),
  correction('correction'),
  other('other');

  const PromotionTargetRelationshipReason(this.storageValue);

  final String storageValue;
}

enum PromotionTargetRetentionAction {
  renew('renew'),
  anonymize('anonymize');

  const PromotionTargetRetentionAction(this.storageValue);

  final String storageValue;
}

enum PromotionTargetRetentionReason {
  purposeConfirmed('purpose_confirmed'),
  withdrawal('withdrawal'),
  retentionExpired('retention_expired');

  const PromotionTargetRetentionReason(this.storageValue);

  final String storageValue;
}

enum PromotionTargetRetentionStatus {
  active('active'),
  anonymized('anonymized');

  const PromotionTargetRetentionStatus(this.storageValue);

  final String storageValue;
}

final class PromotionTargetRetentionTask {
  const PromotionTargetRetentionTask({
    required this.targetId,
    required this.reviewDueAtUtc,
  });

  final String targetId;
  final DateTime reviewDueAtUtc;
}

final class PromotionTargetRetentionOutcome {
  const PromotionTargetRetentionOutcome({
    required this.targetId,
    required this.status,
    required this.duplicate,
    required this.reviewDueAtUtc,
  });

  final String targetId;
  final PromotionTargetRetentionStatus status;
  final bool duplicate;
  final DateTime? reviewDueAtUtc;
}

enum TargetInstitutionRelationshipKind {
  employmentRepresentative('employment_representative'),
  ownershipGovernance('ownership_governance'),
  learningParticipation('learning_participation'),
  membershipAffiliation('membership_affiliation'),
  partnershipService('partnership_service'),
  other('other');

  const TargetInstitutionRelationshipKind(this.storageValue);

  final String storageValue;
}

enum TargetInstitutionRelationshipStatus {
  active('active'),
  ended('ended');

  const TargetInstitutionRelationshipStatus(this.storageValue);

  final String storageValue;
}

enum TargetInstitutionRelationshipEvent {
  created('created'),
  ended('ended');

  const TargetInstitutionRelationshipEvent(this.storageValue);

  final String storageValue;
}

final class TargetInstitutionRelationshipRevision {
  const TargetInstitutionRelationshipRevision({
    required this.revisionNumber,
    required this.event,
    required this.oldStatus,
    required this.newStatus,
    required this.endedAtUtc,
    required this.changedByAppUserId,
    required this.changedAtUtc,
  });

  final int revisionNumber;
  final TargetInstitutionRelationshipEvent event;
  final TargetInstitutionRelationshipStatus? oldStatus;
  final TargetInstitutionRelationshipStatus newStatus;
  final DateTime? endedAtUtc;
  final String changedByAppUserId;
  final DateTime changedAtUtc;
}

final class TargetInstitutionRelationship {
  const TargetInstitutionRelationship({
    required this.id,
    required this.personTargetId,
    required this.institutionTargetId,
    required this.kind,
    required this.roleDescription,
    required this.startedAtUtc,
    required this.endedAtUtc,
    required this.status,
    required this.revisionNumber,
    required this.history,
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
  final List<TargetInstitutionRelationshipRevision> history;
}

final class PromotionTargetStageAlias {
  const PromotionTargetStageAlias({
    required this.stage,
    required this.displayStage,
    required this.displayName,
  });

  final int stage;
  final int displayStage;
  final String? displayName;
}

final class PromotionTargetRelationshipRevision {
  const PromotionTargetRelationshipRevision({
    required this.revisionNumber,
    required this.oldStage,
    required this.newStage,
    required this.oldLifecycleStatus,
    required this.newLifecycleStatus,
    required this.followUpNote,
    required this.changedFields,
    required this.reasonCode,
    required this.reasonDetail,
    required this.changedByAppUserId,
    required this.changedAtUtc,
  });

  final int revisionNumber;
  final int? oldStage;
  final int newStage;
  final PromotionTargetRelationshipLifecycle? oldLifecycleStatus;
  final PromotionTargetRelationshipLifecycle newLifecycleStatus;
  final String? followUpNote;
  final List<String> changedFields;
  final String reasonCode;
  final String? reasonDetail;
  final String changedByAppUserId;
  final DateTime changedAtUtc;
}

final class PromotionTargetRelationship {
  const PromotionTargetRelationship({
    required this.targetId,
    required this.projectId,
    required this.stage,
    required this.displayStage,
    required this.lifecycleStatus,
    required this.followUpNote,
    required this.revisionNumber,
    required this.updatedAtUtc,
    required this.stageAliases,
    required this.history,
  });

  final String targetId;
  final String projectId;
  final int stage;
  final int displayStage;
  final PromotionTargetRelationshipLifecycle lifecycleStatus;
  final String? followUpNote;
  final int revisionNumber;
  final DateTime updatedAtUtc;
  final List<PromotionTargetStageAlias> stageAliases;
  final List<PromotionTargetRelationshipRevision> history;

  PromotionTargetStageAlias aliasFor(int value) => stageAliases.firstWhere(
    (alias) => alias.stage == value,
    orElse: () => PromotionTargetStageAlias(
      stage: value,
      displayStage: value * 2,
      displayName: null,
    ),
  );
}

final class PromotionTargetRelationshipProposal {
  const PromotionTargetRelationshipProposal({
    required this.expectedRevision,
    required this.stage,
    required this.displayStage,
    required this.lifecycleStatus,
    required this.followUpNote,
    required this.reason,
    required this.reasonDetail,
  });

  final int expectedRevision;
  final int stage;
  final int displayStage;
  final PromotionTargetRelationshipLifecycle lifecycleStatus;
  final String? followUpNote;
  final PromotionTargetRelationshipReason reason;
  final String? reasonDetail;
}

final class PromotionTargetProfile {
  const PromotionTargetProfile({
    required this.id,
    required this.type,
    required this.displayName,
    required this.phone,
    required this.email,
    required this.createdAtUtc,
    this.hasCurrentProjectRelationship = false,
    this.projectRelationship,
  });

  final String id;
  final PromotionTargetType type;
  final String displayName;
  final String? phone;
  final String? email;
  final DateTime createdAtUtc;
  final bool hasCurrentProjectRelationship;
  final PromotionTargetRelationship? projectRelationship;
}

enum PromotionTargetFailureCode {
  unauthorized,
  forbidden,
  conflict,
  invalidInput,
  networkUnavailable,
  serverRejected,
}

sealed class PromotionTargetResult<T> {
  const PromotionTargetResult();
}

final class PromotionTargetSuccess<T> extends PromotionTargetResult<T> {
  const PromotionTargetSuccess(
    this.value, {
    this.authorizedAtUtc,
    this.expiresAtUtc,
    this.fromOfflineCache = false,
  });

  final T value;
  final DateTime? authorizedAtUtc;
  final DateTime? expiresAtUtc;
  final bool fromOfflineCache;
}

final class PromotionTargetRejected<T> extends PromotionTargetResult<T> {
  const PromotionTargetRejected(this.code);

  final PromotionTargetFailureCode code;
}

final class PromotionTargetConflict<T> extends PromotionTargetResult<T> {
  const PromotionTargetConflict({
    required this.current,
    this.conflictId,
    this.conflictingFields = const [],
    this.proposed,
  });

  final T current;
  final String? conflictId;
  final List<String> conflictingFields;
  final PromotionTargetRelationshipProposal? proposed;
}

abstract interface class PromotionTargetGateway {
  Future<PromotionTargetResult<List<PromotionTargetProfile>>> loadAssigned();

  Future<PromotionTargetResult<PromotionTargetProfile>> create({
    required PromotionTargetType type,
    required String displayName,
    required String? phone,
    required String? email,
    required String requestId,
  });

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
  });

  Future<PromotionTargetResult<List<PromotionTargetStageAlias>>>
  configureStageAliases({required List<PromotionTargetStageAlias> aliases});

  Future<PromotionTargetResult<List<TargetInstitutionRelationship>>>
  loadInstitutionRelationships();

  Future<PromotionTargetResult<TargetInstitutionRelationship>>
  createInstitutionRelationship({
    required String personTargetId,
    required String institutionTargetId,
    required TargetInstitutionRelationshipKind kind,
    required String? roleDescription,
    required String mutationId,
  });

  Future<PromotionTargetResult<TargetInstitutionRelationship>>
  endInstitutionRelationship({
    required String relationshipId,
    required int expectedRevision,
    required String mutationId,
  });

  Future<void> close();
}

/// Online-only retention operations. Responses contain target IDs, never PII.
abstract interface class PromotionTargetRetentionGateway {
  Future<PromotionTargetResult<List<PromotionTargetRetentionTask>>>
  loadRetentionTasks();

  Future<PromotionTargetResult<PromotionTargetRetentionOutcome>>
  applyRetentionAction({
    required String targetId,
    required PromotionTargetRetentionAction action,
    required PromotionTargetRetentionReason reason,
    required String mutationId,
  });
}
