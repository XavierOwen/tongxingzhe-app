// Public constructor arguments intentionally differ from private field names.
// ignore_for_file: prefer_initializing_formals

import '../app_session/session_context_gateway.dart';
import '../privacy/offline_pii_vault.dart';
import 'promotion_target.dart';

typedef OfflineIdentitySubject = String Function();
typedef CurrentTargetContext = TrustedSessionContext Function();

/// 只在明确的网络失败时使用未过期密文；服务器拒绝会先锁定并清除。
final class OfflinePromotionTargetGateway
    implements PromotionTargetGateway, PromotionTargetRetentionGateway {
  const OfflinePromotionTargetGateway({
    required PromotionTargetGateway remote,
    required OfflinePiiVault vault,
    required OfflineIdentitySubject externalSubject,
    required CurrentTargetContext currentContext,
  }) : _remote = remote,
       _vault = vault,
       _externalSubject = externalSubject,
       _currentContext = currentContext;

  final PromotionTargetGateway _remote;
  final OfflinePiiVault _vault;
  final OfflineIdentitySubject _externalSubject;
  final CurrentTargetContext _currentContext;

  @override
  Future<PromotionTargetResult<List<PromotionTargetProfile>>>
  loadAssigned() async {
    final remote = await _remote.loadAssigned();
    switch (remote) {
      case PromotionTargetSuccess(:final value, :final authorizedAtUtc):
        if (authorizedAtUtc != null) {
          await _vault.replace(
            externalSubject: _externalSubject(),
            context: _currentContext(),
            assignedTargets: value,
            authorizedAtUtc: authorizedAtUtc,
          );
        }
        return remote;
      case PromotionTargetRejected(:final code):
        if (code == PromotionTargetFailureCode.unauthorized ||
            code == PromotionTargetFailureCode.forbidden) {
          await _vault.revoke(
            _externalSubject(),
            OfflinePiiLockReason.unauthorized,
          );
          return remote;
        }
        if (code != PromotionTargetFailureCode.networkUnavailable) {
          return remote;
        }
      case PromotionTargetConflict():
        return remote;
    }

    final cached = await _vault.read(_externalSubject());
    if (cached is! OfflinePiiAvailable ||
        !_sameContext(cached.snapshot.context, _currentContext())) {
      return remote;
    }
    return PromotionTargetSuccess(
      cached.snapshot.assignedTargets,
      authorizedAtUtc: cached.snapshot.authorizedAtUtc,
      expiresAtUtc: cached.snapshot.expiresAtUtc,
      fromOfflineCache: true,
    );
  }

  @override
  Future<PromotionTargetResult<PromotionTargetProfile>> create({
    required PromotionTargetType type,
    required String displayName,
    required String? phone,
    required String? email,
    required String requestId,
  }) => _remote.create(
    type: type,
    displayName: displayName,
    phone: phone,
    email: email,
    requestId: requestId,
  );

  @override
  Future<PromotionTargetResult<List<PromotionTargetRetentionTask>>>
  loadRetentionTasks() {
    final remote = _remote;
    if (remote is! PromotionTargetRetentionGateway) {
      return Future.value(
        const PromotionTargetRejected(
          PromotionTargetFailureCode.networkUnavailable,
        ),
      );
    }
    return (remote as PromotionTargetRetentionGateway).loadRetentionTasks();
  }

  @override
  Future<PromotionTargetResult<PromotionTargetRetentionOutcome>>
  applyRetentionAction({
    required String targetId,
    required PromotionTargetRetentionAction action,
    required PromotionTargetRetentionReason reason,
    required String mutationId,
  }) async {
    final remote = _remote;
    if (remote is! PromotionTargetRetentionGateway) {
      return const PromotionTargetRejected(
        PromotionTargetFailureCode.networkUnavailable,
      );
    }
    final result = await (remote as PromotionTargetRetentionGateway)
        .applyRetentionAction(
          targetId: targetId,
          action: action,
          reason: reason,
          mutationId: mutationId,
        );
    switch (result) {
      case PromotionTargetSuccess(:final value)
          when value.status == PromotionTargetRetentionStatus.anonymized:
        await _vault.revoke(
          _externalSubject(),
          OfflinePiiLockReason.targetAnonymized,
        );
      case PromotionTargetRejected(:final code)
          when code == PromotionTargetFailureCode.unauthorized ||
              code == PromotionTargetFailureCode.forbidden:
        await _vault.revoke(
          _externalSubject(),
          OfflinePiiLockReason.unauthorized,
        );
      case PromotionTargetSuccess():
      case PromotionTargetRejected():
      case PromotionTargetConflict():
    }
    return result;
  }

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
  }) => _remote.updateRelationship(
    targetId: targetId,
    expectedRevision: expectedRevision,
    stage: stage,
    lifecycleStatus: lifecycleStatus,
    followUpNote: followUpNote,
    reason: reason,
    reasonDetail: reasonDetail,
    mutationId: mutationId,
    resolvedConflictId: resolvedConflictId,
  );

  @override
  Future<PromotionTargetResult<List<PromotionTargetStageAlias>>>
  configureStageAliases({required List<PromotionTargetStageAlias> aliases}) =>
      _remote.configureStageAliases(aliases: aliases);

  @override
  Future<PromotionTargetResult<List<TargetInstitutionRelationship>>>
  loadInstitutionRelationships() => _remote.loadInstitutionRelationships();

  @override
  Future<PromotionTargetResult<TargetInstitutionRelationship>>
  createInstitutionRelationship({
    required String personTargetId,
    required String institutionTargetId,
    required TargetInstitutionRelationshipKind kind,
    required String? roleDescription,
    required String mutationId,
  }) => _remote.createInstitutionRelationship(
    personTargetId: personTargetId,
    institutionTargetId: institutionTargetId,
    kind: kind,
    roleDescription: roleDescription,
    mutationId: mutationId,
  );

  @override
  Future<PromotionTargetResult<TargetInstitutionRelationship>>
  endInstitutionRelationship({
    required String relationshipId,
    required int expectedRevision,
    required String mutationId,
  }) => _remote.endInstitutionRelationship(
    relationshipId: relationshipId,
    expectedRevision: expectedRevision,
    mutationId: mutationId,
  );

  @override
  Future<void> close() => _remote.close();
}

bool _sameContext(
  TrustedSessionContext cached,
  TrustedSessionContext current,
) =>
    cached.appUserId == current.appUserId &&
    cached.workspace.id == current.workspace.id &&
    cached.project.id == current.project.id;
