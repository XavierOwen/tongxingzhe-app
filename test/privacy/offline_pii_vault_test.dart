import 'package:flutter_test/flutter_test.dart';
import 'package:tongxingzhe_app/app_session/session_context_gateway.dart';
import 'package:tongxingzhe_app/foundation/runtime_values.dart';
import 'package:tongxingzhe_app/privacy/offline_pii_vault.dart';
import 'package:tongxingzhe_app/targets/promotion_target.dart';

void main() {
  test('联网验权后只开放本次明确分配的对象', () async {
    final clock = _MutableClock(DateTime.utc(2026, 8, 6, 12));
    final vault = OfflinePiiVault(
      secureStore: _MemorySecureValueStore(),
      lockStore: _MemoryOfflinePiiLockStore(),
      clock: clock,
      installationId: 'installation-1',
    );

    final saved = await vault.replace(
      externalSubject: 'identity-subject-1',
      context: _context,
      assignedTargets: [_target('target-1', '王小明')],
      authorizedAtUtc: DateTime.utc(2026, 8, 6, 12),
    );
    clock.value = DateTime.utc(2026, 8, 9, 11, 59);
    final read = await vault.read('identity-subject-1');

    expect(saved, isA<OfflinePiiSaved>());
    expect(read, isA<OfflinePiiAvailable>());
    final snapshot = (read as OfflinePiiAvailable).snapshot;
    expect(snapshot.context.appUserId, _context.appUserId);
    expect(snapshot.context.workspace.id, _context.workspace.id);
    expect(snapshot.context.project.id, _context.project.id);
    expect(snapshot.assignedTargets.map((target) => target.id), ['target-1']);
    expect(snapshot.expiresAtUtc, DateTime.utc(2026, 8, 9, 12));
  });

  test('七十二小时整即锁定且不能靠再次读取恢复', () async {
    final clock = _MutableClock(DateTime.utc(2026, 8, 6, 12));
    final vault = OfflinePiiVault(
      secureStore: _MemorySecureValueStore(),
      lockStore: _MemoryOfflinePiiLockStore(),
      clock: clock,
      installationId: 'installation-1',
    );
    await vault.replace(
      externalSubject: 'identity-subject-1',
      context: _context,
      assignedTargets: [_target('target-1', '王小明')],
      authorizedAtUtc: DateTime.utc(2026, 8, 6, 12),
    );

    clock.value = DateTime.utc(2026, 8, 9, 12);
    final expired = await vault.read('identity-subject-1');
    clock.value = DateTime.utc(2026, 8, 6, 13);
    final afterClockReset = await vault.read('identity-subject-1');

    expect(expired, isA<OfflinePiiLocked>());
    expect((expired as OfflinePiiLocked).reason, OfflinePiiLockReason.expired);
    expect(afterClockReset, isA<OfflinePiiLocked>());
    expect(
      (afterClockReset as OfflinePiiLocked).reason,
      OfflinePiiLockReason.expired,
    );
  });

  test('观察到超过容差的时间回拨后保持锁定', () async {
    final clock = _MutableClock(DateTime.utc(2026, 8, 6, 12));
    final vault = OfflinePiiVault(
      secureStore: _MemorySecureValueStore(),
      lockStore: _MemoryOfflinePiiLockStore(),
      clock: clock,
      installationId: 'installation-1',
    );
    await vault.replace(
      externalSubject: 'identity-subject-1',
      context: _context,
      assignedTargets: [_target('target-1', '王小明')],
      authorizedAtUtc: DateTime.utc(2026, 8, 6, 12),
    );
    clock.value = DateTime.utc(2026, 8, 6, 18);
    expect(await vault.read('identity-subject-1'), isA<OfflinePiiAvailable>());

    clock.value = DateTime.utc(2026, 8, 6, 17, 54);
    final rolledBack = await vault.read('identity-subject-1');

    expect(rolledBack, isA<OfflinePiiLocked>());
    expect(
      (rolledBack as OfflinePiiLocked).reason,
      OfflinePiiLockReason.clockRollback,
    );
  });

  test('撤权先锁定，安全存储清除失败后可以重试但不能解锁', () async {
    final secureStore = _MemorySecureValueStore();
    final clock = _MutableClock(DateTime.utc(2026, 8, 6, 12));
    final vault = OfflinePiiVault(
      secureStore: secureStore,
      lockStore: _MemoryOfflinePiiLockStore(),
      clock: clock,
      installationId: 'installation-1',
    );
    await vault.replace(
      externalSubject: 'identity-subject-1',
      context: _context,
      assignedTargets: [_target('target-1', '王小明')],
      authorizedAtUtc: DateTime.utc(2026, 8, 6, 12),
    );

    secureStore.failDelete = true;
    final firstDelete = await vault.revoke(
      'identity-subject-1',
      OfflinePiiLockReason.unauthorized,
    );
    secureStore.failDelete = false;
    final retry = await vault.retryLockedDeletion('identity-subject-1');
    final read = await vault.read('identity-subject-1');

    expect(firstDelete, OfflinePiiDeletionResult.pending);
    expect(retry, OfflinePiiDeletionResult.deleted);
    expect(read, isA<OfflinePiiLocked>());
    expect(
      (read as OfflinePiiLocked).reason,
      OfflinePiiLockReason.unauthorized,
    );
  });

  test('加密快照保留项目关系和共享备注历史', () async {
    final vault = OfflinePiiVault(
      secureStore: _MemorySecureValueStore(),
      lockStore: _MemoryOfflinePiiLockStore(),
      clock: _MutableClock(DateTime.utc(2026, 8, 6, 12)),
      installationId: 'installation-1',
    );
    await vault.replace(
      externalSubject: 'identity-subject-1',
      context: _context,
      assignedTargets: [_targetWithRelationship()],
      authorizedAtUtc: DateTime.utc(2026, 8, 6, 12),
    );

    final read = await vault.read('identity-subject-1');

    final target =
        (read as OfflinePiiAvailable).snapshot.assignedTargets.single;
    expect(target.hasCurrentProjectRelationship, isTrue);
    expect(target.projectRelationship?.stage, 3);
    expect(target.projectRelationship?.followUpNote, '下周再次联系');
    expect(
      target.projectRelationship?.history.single.reasonCode,
      'progress_update',
    );
  });

  test('读取后无法持久化时间高水位时立即锁定', () async {
    final secureStore = _MemorySecureValueStore();
    final vault = OfflinePiiVault(
      secureStore: secureStore,
      lockStore: _MemoryOfflinePiiLockStore(),
      clock: _MutableClock(DateTime.utc(2026, 8, 6, 13)),
      installationId: 'installation-1',
    );
    await vault.replace(
      externalSubject: 'identity-subject-1',
      context: _context,
      assignedTargets: [_target('target-1', '王小明')],
      authorizedAtUtc: DateTime.utc(2026, 8, 6, 12),
    );

    secureStore.failWrite = true;
    final failedRead = await vault.read('identity-subject-1');
    secureStore.failWrite = false;
    final laterRead = await vault.read('identity-subject-1');

    expect(failedRead, isA<OfflinePiiLocked>());
    expect(
      (failedRead as OfflinePiiLocked).reason,
      OfflinePiiLockReason.storageFailure,
    );
    expect(laterRead, isA<OfflinePiiLocked>());
  });

  test('较旧的并发刷新不能在较新分配结果之后重新写回', () async {
    final secureStore = _MemorySecureValueStore()..delayFirstWrite = true;
    final vault = OfflinePiiVault(
      secureStore: secureStore,
      lockStore: _MemoryOfflinePiiLockStore(),
      clock: _MutableClock(DateTime.utc(2026, 8, 6, 14)),
      installationId: 'installation-1',
    );

    final older = vault.replace(
      externalSubject: 'identity-subject-1',
      context: _context,
      assignedTargets: [_target('target-old', '旧分配')],
      authorizedAtUtc: DateTime.utc(2026, 8, 6, 12),
    );
    await Future<void>.delayed(Duration.zero);
    final newer = vault.replace(
      externalSubject: 'identity-subject-1',
      context: _context,
      assignedTargets: [_target('target-new', '新分配')],
      authorizedAtUtc: DateTime.utc(2026, 8, 6, 13),
    );
    await Future.wait([older, newer]);

    final read = await vault.read('identity-subject-1');

    expect(
      (read as OfflinePiiAvailable).snapshot.assignedTargets.single.id,
      'target-new',
    );
  });

  test('并发撤权必须排在已开始的刷新之后且保持最终锁定', () async {
    final secureStore = _MemorySecureValueStore()..delayFirstWrite = true;
    final vault = OfflinePiiVault(
      secureStore: secureStore,
      lockStore: _MemoryOfflinePiiLockStore(),
      clock: _MutableClock(DateTime.utc(2026, 8, 6, 14)),
      installationId: 'installation-1',
    );

    final refresh = vault.replace(
      externalSubject: 'identity-subject-1',
      context: _context,
      assignedTargets: [_target('target-old', '即将撤权')],
      authorizedAtUtc: DateTime.utc(2026, 8, 6, 13),
    );
    await Future<void>.delayed(Duration.zero);
    final revocation = vault.revoke(
      'identity-subject-1',
      OfflinePiiLockReason.unauthorized,
    );
    await Future.wait([refresh, revocation]);

    final read = await vault.read('identity-subject-1');

    expect(read, isA<OfflinePiiLocked>());
    expect(
      (read as OfflinePiiLocked).reason,
      OfflinePiiLockReason.unauthorized,
    );
  });

  test('安全存储跨重装残留时由新的安装 ID 锁定', () async {
    final secureStore = _MemorySecureValueStore();
    final lockStore = _MemoryOfflinePiiLockStore();
    final clock = _MutableClock(DateTime.utc(2026, 8, 6, 14));
    final original = OfflinePiiVault(
      secureStore: secureStore,
      lockStore: lockStore,
      clock: clock,
      installationId: 'installation-1',
    );
    await original.replace(
      externalSubject: 'identity-subject-1',
      context: _context,
      assignedTargets: [_target('target-1', '王小明')],
      authorizedAtUtc: DateTime.utc(2026, 8, 6, 13),
    );

    final reinstalled = OfflinePiiVault(
      secureStore: secureStore,
      lockStore: lockStore,
      clock: clock,
      installationId: 'installation-2',
    );
    final read = await reinstalled.read('identity-subject-1');

    expect(read, isA<OfflinePiiLocked>());
    expect(
      (read as OfflinePiiLocked).reason,
      OfflinePiiLockReason.installationChanged,
    );
  });

  test('一台设备的在线验权不会给另一台设备建立离线资料', () async {
    final clock = _MutableClock(DateTime.utc(2026, 8, 6, 14));
    final firstDevice = OfflinePiiVault(
      secureStore: _MemorySecureValueStore(),
      lockStore: _MemoryOfflinePiiLockStore(),
      clock: clock,
      installationId: 'installation-device-1',
    );
    final secondDevice = OfflinePiiVault(
      secureStore: _MemorySecureValueStore(),
      lockStore: _MemoryOfflinePiiLockStore(),
      clock: clock,
      installationId: 'installation-device-2',
    );
    await firstDevice.replace(
      externalSubject: 'identity-subject-1',
      context: _context,
      assignedTargets: [_target('target-1', '王小明')],
      authorizedAtUtc: DateTime.utc(2026, 8, 6, 13),
    );

    final secondDeviceRead = await secondDevice.read('identity-subject-1');

    expect(secondDeviceRead, isA<OfflinePiiEmpty>());
  });

  test('损坏的安全存储内容不会在修复时重新变为可读', () async {
    final secureStore = _MemorySecureValueStore();
    final vault = OfflinePiiVault(
      secureStore: secureStore,
      lockStore: _MemoryOfflinePiiLockStore(),
      clock: _MutableClock(DateTime.utc(2026, 8, 6, 14)),
      installationId: 'installation-1',
    );
    await vault.replace(
      externalSubject: 'identity-subject-1',
      context: _context,
      assignedTargets: [_target('target-1', '王小明')],
      authorizedAtUtc: DateTime.utc(2026, 8, 6, 13),
    );
    secureStore.values.updateAll((_, _) => '{invalid');

    final read = await vault.read('identity-subject-1');

    expect(read, isA<OfflinePiiLocked>());
    expect((read as OfflinePiiLocked).reason, OfflinePiiLockReason.corrupt);
  });

  test('在线刷新无法读取旧密文时立即锁定旧资料', () async {
    final secureStore = _MemorySecureValueStore();
    final vault = OfflinePiiVault(
      secureStore: secureStore,
      lockStore: _MemoryOfflinePiiLockStore(),
      clock: _MutableClock(DateTime.utc(2026, 8, 6, 14)),
      installationId: 'installation-1',
    );
    await vault.replace(
      externalSubject: 'identity-subject-1',
      context: _context,
      assignedTargets: [_target('target-old', '旧资料')],
      authorizedAtUtc: DateTime.utc(2026, 8, 6, 12),
    );

    secureStore.failRead = true;
    final refresh = await vault.replace(
      externalSubject: 'identity-subject-1',
      context: _context,
      assignedTargets: [_target('target-new', '新资料')],
      authorizedAtUtc: DateTime.utc(2026, 8, 6, 13),
    );
    secureStore.failRead = false;
    final read = await vault.read('identity-subject-1');

    expect(refresh, isA<OfflinePiiSaveFailed>());
    expect(read, isA<OfflinePiiLocked>());
    expect(
      (read as OfflinePiiLocked).reason,
      OfflinePiiLockReason.storageFailure,
    );
  });

  test('离线读取遇到安全存储故障时锁定并删除旧资料', () async {
    final secureStore = _MemorySecureValueStore();
    final vault = OfflinePiiVault(
      secureStore: secureStore,
      lockStore: _MemoryOfflinePiiLockStore(),
      clock: _MutableClock(DateTime.utc(2026, 8, 6, 14)),
      installationId: 'installation-1',
    );
    await vault.replace(
      externalSubject: 'identity-subject-1',
      context: _context,
      assignedTargets: [_target('target-1', '王小明')],
      authorizedAtUtc: DateTime.utc(2026, 8, 6, 13),
    );

    secureStore.failRead = true;
    final failedRead = await vault.read('identity-subject-1');
    secureStore.failRead = false;
    final laterRead = await vault.read('identity-subject-1');

    expect(failedRead, isA<OfflinePiiLocked>());
    expect(
      (failedRead as OfflinePiiLocked).reason,
      OfflinePiiLockReason.storageFailure,
    );
    expect(laterRead, isA<OfflinePiiLocked>());
    expect(secureStore.values, isEmpty);
  });
}

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

PromotionTargetProfile _target(String id, String name) =>
    PromotionTargetProfile(
      id: id,
      type: PromotionTargetType.person,
      displayName: name,
      phone: '+1 555 0100',
      email: 'assigned@example.test',
      createdAtUtc: DateTime.utc(2026, 8, 1),
    );

PromotionTargetProfile _targetWithRelationship() => PromotionTargetProfile(
  id: 'target-with-relationship',
  type: PromotionTargetType.person,
  displayName: '李小华',
  phone: null,
  email: 'li@example.test',
  createdAtUtc: DateTime.utc(2026, 8, 1),
  hasCurrentProjectRelationship: true,
  projectRelationship: PromotionTargetRelationship(
    targetId: 'target-with-relationship',
    projectId: _context.project.id,
    stage: 3,
    displayStage: 6,
    lifecycleStatus: PromotionTargetRelationshipLifecycle.active,
    followUpNote: '下周再次联系',
    revisionNumber: 1,
    updatedAtUtc: DateTime.utc(2026, 8, 6, 12),
    stageAliases: const [
      PromotionTargetStageAlias(stage: 3, displayStage: 6, displayName: '明确推进'),
    ],
    history: [
      PromotionTargetRelationshipRevision(
        revisionNumber: 1,
        oldStage: null,
        newStage: 3,
        oldLifecycleStatus: null,
        newLifecycleStatus: PromotionTargetRelationshipLifecycle.active,
        followUpNote: '下周再次联系',
        changedFields: const ['stage', 'follow_up_note'],
        reasonCode: 'progress_update',
        reasonDetail: null,
        changedByAppUserId: _context.appUserId,
        changedAtUtc: DateTime.utc(2026, 8, 6, 12),
      ),
    ],
  ),
);

final class _MutableClock implements AppClock {
  _MutableClock(this.value);

  DateTime value;

  @override
  DateTime now() => value;
}

final class _MemorySecureValueStore implements SecureValueStore {
  final values = <String, String>{};
  var failDelete = false;
  var failRead = false;
  var failWrite = false;
  var delayFirstWrite = false;
  var writeCount = 0;

  @override
  Future<void> delete(String key) async {
    if (failDelete) throw StateError('synthetic delete failure');
    values.remove(key);
  }

  @override
  Future<String?> read(String key) async {
    if (failRead) throw StateError('synthetic read failure');
    return values[key];
  }

  @override
  Future<void> write(String key, String value) async {
    if (failWrite) throw StateError('synthetic write failure');
    writeCount += 1;
    if (delayFirstWrite && writeCount == 1) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
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
