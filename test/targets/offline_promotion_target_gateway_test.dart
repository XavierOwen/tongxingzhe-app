import 'package:flutter_test/flutter_test.dart';
import 'package:tongxingzhe_app/app_session/session_context_gateway.dart';
import 'package:tongxingzhe_app/foundation/runtime_values.dart';
import 'package:tongxingzhe_app/privacy/offline_pii_vault.dart';
import 'package:tongxingzhe_app/targets/offline_promotion_target_gateway.dart';
import 'package:tongxingzhe_app/targets/promotion_target.dart';

void main() {
  test('在线验权后的网络失败只降级到同一上下文的未过期密文', () async {
    final remote = _RemoteGateway();
    final vault = OfflinePiiVault(
      secureStore: _MemorySecureValueStore(),
      lockStore: _MemoryOfflinePiiLockStore(),
      clock: _FixedClock(DateTime.utc(2026, 8, 6, 13)),
      installationId: 'installation-1',
    );
    final gateway = OfflinePromotionTargetGateway(
      remote: remote,
      vault: vault,
      externalSubject: () => 'identity-subject-1',
      currentContext: () => _context,
    );
    remote.listResult = PromotionTargetSuccess([
      _target,
    ], authorizedAtUtc: DateTime.utc(2026, 8, 6, 12));
    expect(await gateway.loadAssigned(), isA<PromotionTargetSuccess>());

    remote.listResult = const PromotionTargetRejected(
      PromotionTargetFailureCode.networkUnavailable,
    );
    final fallback = await gateway.loadAssigned();

    expect(
      fallback,
      isA<PromotionTargetSuccess<List<PromotionTargetProfile>>>(),
    );
    final success =
        fallback as PromotionTargetSuccess<List<PromotionTargetProfile>>;
    expect(success.value.single.displayName, '王小明');
    expect(success.authorizedAtUtc, DateTime.utc(2026, 8, 6, 12));
    expect(success.expiresAtUtc, DateTime.utc(2026, 8, 9, 12));
    expect(success.fromOfflineCache, isTrue);
  });

  test('服务器明确拒绝时锁定密文且不降级到旧资料', () async {
    final remote = _RemoteGateway();
    final vault = _vault();
    final gateway = OfflinePromotionTargetGateway(
      remote: remote,
      vault: vault,
      externalSubject: () => 'identity-subject-1',
      currentContext: () => _context,
    );
    remote.listResult = PromotionTargetSuccess([
      _target,
    ], authorizedAtUtc: DateTime.utc(2026, 8, 6, 12));
    await gateway.loadAssigned();

    remote.listResult = const PromotionTargetRejected(
      PromotionTargetFailureCode.forbidden,
    );
    final rejected = await gateway.loadAssigned();
    final cached = await vault.read('identity-subject-1');

    expect(
      (rejected as PromotionTargetRejected<List<PromotionTargetProfile>>).code,
      PromotionTargetFailureCode.forbidden,
    );
    expect(cached, isA<OfflinePiiLocked>());
    expect(
      (cached as OfflinePiiLocked).reason,
      OfflinePiiLockReason.unauthorized,
    );
  });

  test('网络失败时不读取其他项目或工作区的密文', () async {
    final remote = _RemoteGateway();
    final vault = _vault();
    await vault.replace(
      externalSubject: 'identity-subject-1',
      context: _context,
      assignedTargets: [_target],
      authorizedAtUtc: DateTime.utc(2026, 8, 6, 12),
    );
    final gateway = OfflinePromotionTargetGateway(
      remote: remote,
      vault: vault,
      externalSubject: () => 'identity-subject-1',
      currentContext: () => const TrustedSessionContext(
        appUserId: '11111111-1111-4111-8111-111111111111',
        workspace: WorkspaceContext(
          id: '22222222-2222-4222-8222-222222222222',
          kind: WorkspaceKind.personal,
          name: '个人空间',
        ),
        project: ProjectContext(
          id: '99999999-9999-4999-8999-999999999999',
          name: '另一个推广项目',
        ),
        questionnaireVersion: QuestionnaireVersionContext(
          id: '88888888-8888-4888-8888-888888888888',
          versionNumber: 1,
        ),
        capabilities: {'view_assigned_target_pii'},
      ),
    );

    final result = await gateway.loadAssigned();

    expect(
      (result as PromotionTargetRejected<List<PromotionTargetProfile>>).code,
      PromotionTargetFailureCode.networkUnavailable,
    );
  });

  test('匿名化成功后立即清除本地密文且不再离线回退', () async {
    final remote = _RemoteGateway();
    final vault = _vault();
    final gateway = OfflinePromotionTargetGateway(
      remote: remote,
      vault: vault,
      externalSubject: () => 'identity-subject-1',
      currentContext: () => _context,
    );
    remote.listResult = PromotionTargetSuccess([
      _target,
    ], authorizedAtUtc: DateTime.utc(2026, 8, 6, 12));
    await gateway.loadAssigned();

    remote.retentionResult = const PromotionTargetSuccess(
      PromotionTargetRetentionOutcome(
        targetId: 'target-1',
        status: PromotionTargetRetentionStatus.anonymized,
        duplicate: false,
        reviewDueAtUtc: null,
      ),
    );
    final result = await gateway.applyRetentionAction(
      targetId: 'target-1',
      action: PromotionTargetRetentionAction.anonymize,
      reason: PromotionTargetRetentionReason.withdrawal,
      mutationId: 'withdrawal-1',
    );

    expect(
      result,
      isA<PromotionTargetSuccess<PromotionTargetRetentionOutcome>>(),
    );
    expect(await vault.read('identity-subject-1'), isA<OfflinePiiLocked>());
    remote.listResult = const PromotionTargetRejected(
      PromotionTargetFailureCode.networkUnavailable,
    );
    expect(
      await gateway.loadAssigned(),
      isA<PromotionTargetRejected<List<PromotionTargetProfile>>>(),
    );
  });
}

OfflinePiiVault _vault() => OfflinePiiVault(
  secureStore: _MemorySecureValueStore(),
  lockStore: _MemoryOfflinePiiLockStore(),
  clock: _FixedClock(DateTime.utc(2026, 8, 6, 13)),
  installationId: 'installation-1',
);

const _context = TrustedSessionContext(
  appUserId: '11111111-1111-4111-8111-111111111111',
  workspace: WorkspaceContext(
    id: '22222222-2222-4222-8222-222222222222',
    kind: WorkspaceKind.personal,
    name: '个人空间',
  ),
  project: ProjectContext(
    id: '33333333-3333-4333-8333-333333333333',
    name: '校园推广',
  ),
  questionnaireVersion: QuestionnaireVersionContext(
    id: '44444444-4444-4444-8444-444444444444',
    versionNumber: 1,
  ),
  capabilities: {'view_assigned_target_pii'},
);

final _target = PromotionTargetProfile(
  id: 'target-1',
  type: PromotionTargetType.person,
  displayName: '王小明',
  phone: '+1 555 0100',
  email: null,
  createdAtUtc: DateTime.utc(2026, 8, 1),
);

final class _RemoteGateway
    implements PromotionTargetGateway, PromotionTargetRetentionGateway {
  PromotionTargetResult<List<PromotionTargetProfile>> listResult =
      const PromotionTargetRejected(
        PromotionTargetFailureCode.networkUnavailable,
      );
  PromotionTargetResult<PromotionTargetRetentionOutcome> retentionResult =
      const PromotionTargetRejected(
        PromotionTargetFailureCode.networkUnavailable,
      );

  @override
  Future<PromotionTargetResult<List<PromotionTargetRetentionTask>>>
  loadRetentionTasks() async => const PromotionTargetSuccess([]);

  @override
  Future<PromotionTargetResult<PromotionTargetRetentionOutcome>>
  applyRetentionAction({
    required String targetId,
    required PromotionTargetRetentionAction action,
    required PromotionTargetRetentionReason reason,
    required String mutationId,
  }) async => retentionResult;

  @override
  Future<PromotionTargetResult<List<PromotionTargetProfile>>>
  loadAssigned() async => listResult;

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

final class _FixedClock implements AppClock {
  const _FixedClock(this.value);

  final DateTime value;

  @override
  DateTime now() => value;
}

final class _MemorySecureValueStore implements SecureValueStore {
  final values = <String, String>{};

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

final class _MemoryOfflinePiiLockStore implements OfflinePiiLockStore {
  final locks = <String, OfflinePiiLock>{};

  @override
  Future<void> clear(String scopeKey) async => locks.remove(scopeKey);

  @override
  Future<OfflinePiiLock?> read(String scopeKey) async => locks[scopeKey];

  @override
  Future<void> write(String scopeKey, OfflinePiiLock lock) async {
    locks[scopeKey] = lock;
  }
}
