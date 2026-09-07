// Public constructor arguments intentionally differ from private field names.
// ignore_for_file: prefer_initializing_formals

import '../app_session/session_context_gateway.dart';
import '../privacy/offline_pii_vault.dart';
import 'promotion_target.dart';

typedef CurrentOfflineTargetScope =
    ({String externalSubject, TrustedSessionContext context}) Function();

/// 只在明确的网络失败时使用未过期密文；服务器拒绝会先锁定并清除。
final class OfflinePromotionTargetGateway
    implements PromotionTargetGateway, PromotionTargetRetentionGateway {
  const OfflinePromotionTargetGateway({
    required PromotionTargetGateway remote,
    required OfflinePiiVault vault,
    required CurrentOfflineTargetScope currentScope,
  }) : _remote = remote,
       _vault = vault,
       _currentScope = currentScope;

  final PromotionTargetGateway _remote;
  final OfflinePiiVault _vault;
  final CurrentOfflineTargetScope _currentScope;

  @override
  Future<PromotionTargetResult<List<PromotionTargetProfile>>>
  loadAssigned() async {
    final scope = _captureScope();
    if (scope == null) return _unauthorized();
    final remote = await _remote.loadAssigned();
    switch (remote) {
      case PromotionTargetSuccess(:final value, :final authorizedAtUtc):
        if (!_isCurrent(scope)) return _unauthorized();
        if (authorizedAtUtc != null) {
          final saved = await _vault.replace(
            externalSubject: scope.externalSubject,
            context: scope.context,
            assignedTargets: value,
            authorizedAtUtc: authorizedAtUtc,
            expectedFence: scope.fence,
          );
          if (saved is! OfflinePiiSaved) return _unauthorized();
        }
        return _isCurrent(scope) ? remote : _unauthorized();
      case PromotionTargetRejected(:final code):
        if (code == PromotionTargetFailureCode.unauthorized ||
            code == PromotionTargetFailureCode.forbidden) {
          if (!_isCurrent(scope)) return _unauthorized();
          final deletion = _vault.revoke(
            scope.externalSubject,
            OfflinePiiLockReason.unauthorized,
            expectedFence: scope.fence,
          );
          final revocationFence = _vault.captureRequest(scope.externalSubject);
          final deleted = await deletion;
          return deleted == OfflinePiiDeletionResult.stale ||
                  !_vault.isRequestCurrent(revocationFence) ||
                  !_sameLiveScope(scope)
              ? _unauthorized()
              : remote;
        }
        if (code != PromotionTargetFailureCode.networkUnavailable) {
          return _isCurrent(scope) ? remote : _unauthorized();
        }
      case PromotionTargetConflict():
        return _isCurrent(scope) ? remote : _unauthorized();
    }

    if (!_isCurrent(scope)) return _unauthorized();
    final cached = await _vault.read(
      scope.externalSubject,
      expectedFence: scope.fence,
    );
    if (!_isCurrent(scope)) return _unauthorized();
    if (cached is! OfflinePiiAvailable ||
        !_sameContext(cached.snapshot.context, scope.context)) {
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
  loadRetentionTasks() async {
    final scope = _captureScope();
    if (scope == null) return _unauthorized();
    final remote = _remote;
    if (remote is! PromotionTargetRetentionGateway) {
      return const PromotionTargetRejected(
        PromotionTargetFailureCode.networkUnavailable,
      );
    }
    final result = await (remote as PromotionTargetRetentionGateway)
        .loadRetentionTasks();
    return _isCurrent(scope) ? result : _unauthorized();
  }

  @override
  Future<PromotionTargetResult<PromotionTargetRetentionOutcome>>
  applyRetentionAction({
    required String targetId,
    required PromotionTargetRetentionAction action,
    required PromotionTargetRetentionReason reason,
    required String mutationId,
  }) async {
    final scope = _captureScope();
    if (scope == null) return _unauthorized();
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
        if (!_isCurrent(scope)) return _unauthorized();
        final deletion = _vault.revoke(
          scope.externalSubject,
          OfflinePiiLockReason.targetAnonymized,
          expectedFence: scope.fence,
        );
        final revocationFence = _vault.captureRequest(scope.externalSubject);
        final deleted = await deletion;
        if (deleted == OfflinePiiDeletionResult.stale ||
            !_vault.isRequestCurrent(revocationFence) ||
            !_sameLiveScope(scope)) {
          return _unauthorized();
        }
      case PromotionTargetRejected(:final code)
          when code == PromotionTargetFailureCode.unauthorized ||
              code == PromotionTargetFailureCode.forbidden:
        if (!_isCurrent(scope)) return _unauthorized();
        final deletion = _vault.revoke(
          scope.externalSubject,
          OfflinePiiLockReason.unauthorized,
          expectedFence: scope.fence,
        );
        final revocationFence = _vault.captureRequest(scope.externalSubject);
        final deleted = await deletion;
        if (deleted == OfflinePiiDeletionResult.stale ||
            !_vault.isRequestCurrent(revocationFence) ||
            !_sameLiveScope(scope)) {
          return _unauthorized();
        }
      case PromotionTargetSuccess():
      case PromotionTargetRejected():
      case PromotionTargetConflict():
        if (!_isCurrent(scope)) return _unauthorized();
    }
    return result;
  }

  _OfflineTargetRequestScope? _captureScope() {
    try {
      final current = _currentScope();
      if (!_canViewOfflinePii(current.context)) return null;
      final request = _OfflineTargetRequestScope(
        externalSubject: current.externalSubject,
        context: current.context,
        fence: _vault.captureRequest(current.externalSubject),
      );
      return _isCurrent(request) ? request : null;
    } on Object {
      return null;
    }
  }

  bool _isCurrent(_OfflineTargetRequestScope request) =>
      _vault.isRequestCurrent(request.fence) && _sameLiveScope(request);

  bool _sameLiveScope(_OfflineTargetRequestScope request) {
    try {
      final current = _currentScope();
      return current.externalSubject == request.externalSubject &&
          _canViewOfflinePii(current.context) &&
          _sameContext(current.context, request.context);
    } on Object {
      return false;
    }
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

final class _OfflineTargetRequestScope {
  const _OfflineTargetRequestScope({
    required this.externalSubject,
    required this.context,
    required this.fence,
  });

  final String externalSubject;
  final TrustedSessionContext context;
  final OfflinePiiRequestFence fence;
}

PromotionTargetRejected<T> _unauthorized<T>() =>
    const PromotionTargetRejected(PromotionTargetFailureCode.unauthorized);

bool _canViewOfflinePii(TrustedSessionContext context) =>
    context.capabilities.contains('view_assigned_target_pii');

bool _sameContext(
  TrustedSessionContext cached,
  TrustedSessionContext current,
) =>
    cached.appUserId == current.appUserId &&
    cached.workspace.id == current.workspace.id &&
    cached.project.id == current.project.id;
