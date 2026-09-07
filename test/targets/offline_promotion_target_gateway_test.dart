import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tongxingzhe_app/app_session/session_context_gateway.dart';
import 'package:tongxingzhe_app/privacy/offline_pii_vault.dart';
import 'package:tongxingzhe_app/targets/offline_promotion_target_gateway.dart';
import 'package:tongxingzhe_app/targets/promotion_target.dart';

import '../support/fake_runtime_values.dart';

void main() {
  test('在线验权后的网络失败只降级到同一上下文的未过期密文', () async {
    final remote = _RemoteGateway();
    final vault = OfflinePiiVault(
      secureStore: _MemorySecureValueStore(),
      lockStore: _MemoryOfflinePiiLockStore(),
      clock: FixedClock(DateTime.utc(2026, 8, 6, 13)),
      installationId: 'installation-1',
    );
    final gateway = OfflinePromotionTargetGateway(
      remote: remote,
      vault: vault,
      currentScope: () =>
          (externalSubject: 'identity-subject-1', context: _context),
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
      currentScope: () =>
          (externalSubject: 'identity-subject-1', context: _context),
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

  test('撤权后重新在线验权可用较新授权恢复离线资料', () async {
    final remote = _RemoteGateway();
    final vault = _vault();
    final gateway = OfflinePromotionTargetGateway(
      remote: remote,
      vault: vault,
      currentScope: () =>
          (externalSubject: 'identity-subject-1', context: _context),
    );
    remote.listResult = PromotionTargetSuccess([
      _target,
    ], authorizedAtUtc: DateTime.utc(2026, 8, 6, 12));
    await gateway.loadAssigned();

    remote.listResult = const PromotionTargetRejected(
      PromotionTargetFailureCode.forbidden,
    );
    await gateway.loadAssigned();
    expect(await vault.read('identity-subject-1'), isA<OfflinePiiLocked>());

    remote.listResult = PromotionTargetSuccess([
      _target,
    ], authorizedAtUtc: DateTime.utc(2026, 8, 6, 13));
    final restored = await gateway.loadAssigned();

    expect(
      restored,
      isA<PromotionTargetSuccess<List<PromotionTargetProfile>>>(),
    );
    expect(await vault.read('identity-subject-1'), isA<OfflinePiiAvailable>());
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
      currentScope: () =>
          (externalSubject: 'identity-subject-1', context: _otherContext),
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
      currentScope: () =>
          (externalSubject: 'identity-subject-1', context: _context),
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

  test('同账号切换项目后旧 loadAssigned 成功不落盘也不回 UI', () async {
    final remote = _RemoteGateway();
    final secureStore = _MemorySecureValueStore();
    final vault = OfflinePiiVault(
      secureStore: secureStore,
      lockStore: _MemoryOfflinePiiLockStore(),
      clock: FixedClock(DateTime.utc(2026, 8, 6, 13)),
      installationId: 'installation-1',
    );
    var context = _context;
    final response =
        Completer<PromotionTargetResult<List<PromotionTargetProfile>>>();
    remote.listCompleter = response;
    final gateway = OfflinePromotionTargetGateway(
      remote: remote,
      vault: vault,
      currentScope: () =>
          (externalSubject: 'identity-subject-1', context: context),
    );

    final pending = gateway.loadAssigned();
    context = _otherContext;
    await vault.revoke(
      'identity-subject-1',
      OfflinePiiLockReason.contextChanged,
    );
    response.complete(
      PromotionTargetSuccess([
        _target,
      ], authorizedAtUtc: DateTime.utc(2026, 8, 6, 12)),
    );

    final result = await pending;
    expect(result, isA<PromotionTargetRejected>());
    expect(secureStore.values, isEmpty);
  });

  test('同账号项目切换 ABA 后旧 loadAssigned 成功仍视为 stale', () async {
    final remote = _RemoteGateway();
    final secureStore = _MemorySecureValueStore();
    final vault = OfflinePiiVault(
      secureStore: secureStore,
      lockStore: _MemoryOfflinePiiLockStore(),
      clock: FixedClock(DateTime.utc(2026, 8, 6, 13)),
      installationId: 'installation-1',
    );
    var context = _context;
    final response =
        Completer<PromotionTargetResult<List<PromotionTargetProfile>>>();
    remote.listCompleter = response;
    final gateway = OfflinePromotionTargetGateway(
      remote: remote,
      vault: vault,
      currentScope: () =>
          (externalSubject: 'identity-subject-1', context: context),
    );

    final pending = gateway.loadAssigned();
    context = _otherContext;
    await vault.revoke(
      'identity-subject-1',
      OfflinePiiLockReason.contextChanged,
    );
    context = _context;
    response.complete(
      PromotionTargetSuccess([
        _target,
      ], authorizedAtUtc: DateTime.utc(2026, 8, 6, 12)),
    );

    final result = await pending;
    expect(result, isA<PromotionTargetRejected>());
    expect(secureStore.values, isEmpty);
  });

  test('切换 scope 后旧 loadAssigned 的晚到 401/403 不撤销新 scope', () async {
    for (final code in [
      PromotionTargetFailureCode.unauthorized,
      PromotionTargetFailureCode.forbidden,
    ]) {
      final remote = _RemoteGateway();
      final lockStore = _MemoryOfflinePiiLockStore();
      final vault = OfflinePiiVault(
        secureStore: _MemorySecureValueStore(),
        lockStore: lockStore,
        clock: FixedClock(DateTime.utc(2026, 8, 6, 13)),
        installationId: 'installation-1',
      );
      var externalSubject = 'identity-subject-old';
      var context = _context;
      final response =
          Completer<PromotionTargetResult<List<PromotionTargetProfile>>>();
      remote.listCompleter = response;
      final gateway = OfflinePromotionTargetGateway(
        remote: remote,
        vault: vault,
        currentScope: () =>
            (externalSubject: externalSubject, context: context),
      );

      final pending = gateway.loadAssigned();
      externalSubject = 'identity-subject-new';
      context = _otherContext;
      response.complete(PromotionTargetRejected(code));

      final result = await pending;
      expect(
        (result as PromotionTargetRejected<List<PromotionTargetProfile>>).code,
        PromotionTargetFailureCode.unauthorized,
      );
      expect(lockStore.locks, isEmpty);
    }
  });

  test('网络失败时旧请求不读取切换后新 scope 的密文', () async {
    final remote = _RemoteGateway();
    final secureStore = _MemorySecureValueStore();
    final vault = OfflinePiiVault(
      secureStore: secureStore,
      lockStore: _MemoryOfflinePiiLockStore(),
      clock: FixedClock(DateTime.utc(2026, 8, 6, 13)),
      installationId: 'installation-1',
    );
    await vault.replace(
      externalSubject: 'identity-subject-1',
      context: _context,
      assignedTargets: [_target],
      authorizedAtUtc: DateTime.utc(2026, 8, 6, 12),
    );
    var context = _context;
    final response =
        Completer<PromotionTargetResult<List<PromotionTargetProfile>>>();
    remote.listCompleter = response;
    final gateway = OfflinePromotionTargetGateway(
      remote: remote,
      vault: vault,
      currentScope: () =>
          (externalSubject: 'identity-subject-1', context: context),
    );

    final pending = gateway.loadAssigned();
    context = _otherContext;
    await vault.revoke(
      'identity-subject-1',
      OfflinePiiLockReason.contextChanged,
    );
    await vault.replace(
      externalSubject: 'identity-subject-1',
      context: _otherContext,
      assignedTargets: [_target],
      authorizedAtUtc: DateTime.utc(2026, 8, 6, 12),
    );
    response.complete(
      const PromotionTargetRejected(
        PromotionTargetFailureCode.networkUnavailable,
      ),
    );

    final result = await pending;
    expect(
      (result as PromotionTargetRejected<List<PromotionTargetProfile>>).code,
      PromotionTargetFailureCode.unauthorized,
    );
  });

  test('revoke 在旧 loadAssigned 写入期间调用也不让晚到成功回 UI', () async {
    final remote = _RemoteGateway();
    final secureStore = _MemorySecureValueStore();
    final vault = OfflinePiiVault(
      secureStore: secureStore,
      lockStore: _MemoryOfflinePiiLockStore(),
      clock: FixedClock(DateTime.utc(2026, 8, 6, 13)),
      installationId: 'installation-1',
    );
    final response =
        Completer<PromotionTargetResult<List<PromotionTargetProfile>>>();
    final writeStarted = Completer<void>();
    final releaseWrite = Completer<void>();
    remote.listCompleter = response;
    secureStore.onNextWriteStarted = writeStarted;
    secureStore.releaseNextWrite = releaseWrite;
    final gateway = OfflinePromotionTargetGateway(
      remote: remote,
      vault: vault,
      currentScope: () =>
          (externalSubject: 'identity-subject-1', context: _context),
    );

    final pending = gateway.loadAssigned();
    response.complete(
      PromotionTargetSuccess([
        _target,
      ], authorizedAtUtc: DateTime.utc(2026, 8, 6, 12)),
    );
    await writeStarted.future;
    final revoke = vault.revoke(
      'identity-subject-1',
      OfflinePiiLockReason.contextChanged,
    );
    releaseWrite.complete();

    expect(
      (await pending as PromotionTargetRejected<List<PromotionTargetProfile>>)
          .code,
      PromotionTargetFailureCode.unauthorized,
    );
    await revoke;
    expect(await vault.read('identity-subject-1'), isA<OfflinePiiLocked>());
  });

  test('匿名化删除被再次 revoke 失效后，晚到 retention 不回成功', () async {
    final remote = _RemoteGateway();
    final secureStore = _MemorySecureValueStore();
    final lockStore = _MemoryOfflinePiiLockStore();
    final vault = OfflinePiiVault(
      secureStore: secureStore,
      lockStore: lockStore,
      clock: FixedClock(DateTime.utc(2026, 8, 6, 13)),
      installationId: 'installation-1',
    );
    final gateway = OfflinePromotionTargetGateway(
      remote: remote,
      vault: vault,
      currentScope: () =>
          (externalSubject: 'identity-subject-1', context: _context),
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
    final deleteStarted = Completer<void>();
    final releaseDelete = Completer<void>();
    secureStore.onNextDeleteStarted = deleteStarted;
    secureStore.releaseNextDelete = releaseDelete;

    final pending = gateway.applyRetentionAction(
      targetId: 'target-1',
      action: PromotionTargetRetentionAction.anonymize,
      reason: PromotionTargetRetentionReason.withdrawal,
      mutationId: 'withdrawal-1',
    );
    await deleteStarted.future;
    final secondRevoke = vault.revoke(
      'identity-subject-1',
      OfflinePiiLockReason.contextChanged,
    );
    releaseDelete.complete();

    expect(
      (await pending
              as PromotionTargetRejected<PromotionTargetRetentionOutcome>)
          .code,
      PromotionTargetFailureCode.unauthorized,
    );
    await secondRevoke;
    expect(await vault.read('identity-subject-1'), isA<OfflinePiiLocked>());
  });

  test('同 scope 的旧 load 遇到已完成匿名化后仍不回成功', () async {
    final remote = _RemoteGateway();
    final vault = _vault();
    final response =
        Completer<PromotionTargetResult<List<PromotionTargetProfile>>>();
    remote.listCompleter = response;
    remote.retentionResult = const PromotionTargetSuccess(
      PromotionTargetRetentionOutcome(
        targetId: 'target-1',
        status: PromotionTargetRetentionStatus.anonymized,
        duplicate: false,
        reviewDueAtUtc: null,
      ),
    );
    final gateway = OfflinePromotionTargetGateway(
      remote: remote,
      vault: vault,
      currentScope: () =>
          (externalSubject: 'identity-subject-1', context: _context),
    );

    final staleLoad = gateway.loadAssigned();
    final retention = gateway.applyRetentionAction(
      targetId: 'target-1',
      action: PromotionTargetRetentionAction.anonymize,
      reason: PromotionTargetRetentionReason.withdrawal,
      mutationId: 'withdrawal-1',
    );
    expect(
      await retention,
      isA<PromotionTargetSuccess<PromotionTargetRetentionOutcome>>(),
    );
    expect(await vault.read('identity-subject-1'), isA<OfflinePiiLocked>());

    response.complete(
      PromotionTargetSuccess([
        _target,
      ], authorizedAtUtc: DateTime.utc(2026, 8, 6, 12)),
    );
    expect(
      (await staleLoad as PromotionTargetRejected<List<PromotionTargetProfile>>)
          .code,
      PromotionTargetFailureCode.unauthorized,
    );
    expect(await vault.read('identity-subject-1'), isA<OfflinePiiLocked>());
  });

  test('currentScope 抛错时 direct gateway fail closed 且不调用 remote', () async {
    final remote = _RemoteGateway();
    final gateway = OfflinePromotionTargetGateway(
      remote: remote,
      vault: _vault(),
      currentScope: () => throw StateError('scope unavailable'),
    );

    final result = await gateway.loadAssigned();

    expect(
      (result as PromotionTargetRejected<List<PromotionTargetProfile>>).code,
      PromotionTargetFailureCode.unauthorized,
    );
    expect(remote.loadAssignedCalls, 0);
  });

  test('切换 scope 后晚到 retention anonymize 不撤销新 scope或回 stale 成功', () async {
    final remote = _RemoteGateway();
    final lockStore = _MemoryOfflinePiiLockStore();
    final vault = OfflinePiiVault(
      secureStore: _MemorySecureValueStore(),
      lockStore: lockStore,
      clock: FixedClock(DateTime.utc(2026, 8, 6, 13)),
      installationId: 'installation-1',
    );
    var externalSubject = 'identity-subject-old';
    var context = _context;
    final response =
        Completer<PromotionTargetResult<PromotionTargetRetentionOutcome>>();
    remote.retentionCompleter = response;
    final gateway = OfflinePromotionTargetGateway(
      remote: remote,
      vault: vault,
      currentScope: () => (externalSubject: externalSubject, context: context),
    );

    final pending = gateway.applyRetentionAction(
      targetId: 'target-1',
      action: PromotionTargetRetentionAction.anonymize,
      reason: PromotionTargetRetentionReason.withdrawal,
      mutationId: 'withdrawal-1',
    );
    externalSubject = 'identity-subject-new';
    context = _otherContext;
    response.complete(
      const PromotionTargetSuccess(
        PromotionTargetRetentionOutcome(
          targetId: 'target-1',
          status: PromotionTargetRetentionStatus.anonymized,
          duplicate: false,
          reviewDueAtUtc: null,
        ),
      ),
    );

    expect(await pending, isA<PromotionTargetRejected>());
    expect(lockStore.locks, isEmpty);
  });

  test('切换 scope 后晚到 retention 拒绝不撤销新 scope或回 stale 结果', () async {
    final remote = _RemoteGateway();
    final lockStore = _MemoryOfflinePiiLockStore();
    final vault = OfflinePiiVault(
      secureStore: _MemorySecureValueStore(),
      lockStore: lockStore,
      clock: FixedClock(DateTime.utc(2026, 8, 6, 13)),
      installationId: 'installation-1',
    );
    var externalSubject = 'identity-subject-old';
    var context = _context;
    final response =
        Completer<PromotionTargetResult<PromotionTargetRetentionOutcome>>();
    remote.retentionCompleter = response;
    final gateway = OfflinePromotionTargetGateway(
      remote: remote,
      vault: vault,
      currentScope: () => (externalSubject: externalSubject, context: context),
    );

    final pending = gateway.applyRetentionAction(
      targetId: 'target-1',
      action: PromotionTargetRetentionAction.anonymize,
      reason: PromotionTargetRetentionReason.withdrawal,
      mutationId: 'withdrawal-1',
    );
    externalSubject = 'identity-subject-new';
    context = _otherContext;
    response.complete(
      const PromotionTargetRejected(PromotionTargetFailureCode.forbidden),
    );

    final result = await pending;
    expect(
      (result as PromotionTargetRejected<PromotionTargetRetentionOutcome>).code,
      PromotionTargetFailureCode.unauthorized,
    );
    expect(lockStore.locks, isEmpty);
  });
}

OfflinePiiVault _vault() => OfflinePiiVault(
  secureStore: _MemorySecureValueStore(),
  lockStore: _MemoryOfflinePiiLockStore(),
  clock: FixedClock(DateTime.utc(2026, 8, 6, 13)),
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

const _otherContext = TrustedSessionContext(
  appUserId: _contextAppUserId,
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
);

const _contextAppUserId = '11111111-1111-4111-8111-111111111111';

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
  var loadAssignedCalls = 0;
  Completer<PromotionTargetResult<List<PromotionTargetProfile>>>? listCompleter;
  Completer<PromotionTargetResult<PromotionTargetRetentionOutcome>>?
  retentionCompleter;

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
  }) => retentionCompleter?.future ?? Future.value(retentionResult);

  @override
  Future<PromotionTargetResult<List<PromotionTargetProfile>>> loadAssigned() {
    loadAssignedCalls += 1;
    return listCompleter?.future ?? Future.value(listResult);
  }

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

final class _MemorySecureValueStore implements SecureValueStore {
  final values = <String, String>{};
  Completer<void>? onNextWriteStarted;
  Completer<void>? releaseNextWrite;
  Completer<void>? onNextDeleteStarted;
  Completer<void>? releaseNextDelete;

  @override
  Future<void> delete(String key) async {
    final started = onNextDeleteStarted;
    final release = releaseNextDelete;
    onNextDeleteStarted = null;
    releaseNextDelete = null;
    started?.complete();
    if (release != null) await release.future;
    values.remove(key);
  }

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    final started = onNextWriteStarted;
    final release = releaseNextWrite;
    onNextWriteStarted = null;
    releaseNextWrite = null;
    started?.complete();
    if (release != null) await release.future;
    values[key] = value;
  }
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
