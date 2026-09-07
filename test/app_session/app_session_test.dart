import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tongxingzhe_app/app_session/app_session.dart';
import 'package:tongxingzhe_app/app_session/session_context_gateway.dart';
import 'package:tongxingzhe_app/identity/identity_session.dart';
import 'package:tongxingzhe_app/privacy/offline_pii_vault.dart';

import '../support/fake_identity_session.dart';
import '../support/fake_runtime_values.dart';
import '../support/fake_session_context_gateway.dart';

void main() {
  test('ready 且 actor exact 时清除当前身份的组织离线 PII', () async {
    final identity = FakeIdentitySession(initial: _signedInIdentity());
    final secureStore = _MemorySecureValueStore();
    final vault = OfflinePiiVault(
      secureStore: secureStore,
      lockStore: _MemoryOfflinePiiLockStore(),
      clock: FixedClock(DateTime.utc(2026, 8, 6, 13)),
      installationId: 'installation-1',
    );
    final context = _withPii(_organizationContext);
    await vault.replace(
      externalSubject: 'external-subject-not-an-app-user-id',
      context: context,
      assignedTargets: const [],
      authorizedAtUtc: DateTime.utc(2026, 8, 6, 12),
    );
    final session = AppSession(
      identitySession: identity,
      contextGateway: FakeSessionContextGateway(context: context),
      offlinePiiVault: vault,
    );
    addTearDown(session.close);
    addTearDown(identity.close);
    await session.start();

    final result = await session.clearOrganizationOfflinePii(
      expectedAppUserId: context.appUserId,
      organizationWorkspaceId: context.workspace.id,
    );

    expect(result, OfflinePiiWorkspaceDeletionResult.deleted);
    expect(secureStore.values, isEmpty);
  });

  test('vault 为 null 时组织离线 PII 清理返回 notPresent', () async {
    final identity = FakeIdentitySession(initial: _signedInIdentity());
    final session = AppSession(
      identitySession: identity,
      contextGateway: FakeSessionContextGateway(),
    );
    addTearDown(session.close);
    addTearDown(identity.close);
    await session.start();

    expect(
      await session.clearOrganizationOfflinePii(
        expectedAppUserId: syntheticSessionContext.appUserId,
        organizationWorkspaceId: syntheticSessionContext.workspace.id,
      ),
      OfflinePiiWorkspaceDeletionResult.notPresent,
    );
  });

  test('actor mismatch、not ready 或 unavailable 时组织离线 PII 清理拒绝', () async {
    final identity = FakeIdentitySession(initial: _signedInIdentity());
    final secureStore = _MemorySecureValueStore();
    final vault = OfflinePiiVault(
      secureStore: secureStore,
      lockStore: _MemoryOfflinePiiLockStore(),
      clock: FixedClock(DateTime.utc(2026, 8, 6, 13)),
      installationId: 'installation-1',
    );
    final context = _withPii(_organizationContext);
    await vault.replace(
      externalSubject: 'external-subject-not-an-app-user-id',
      context: context,
      assignedTargets: const [],
      authorizedAtUtc: DateTime.utc(2026, 8, 6, 12),
    );
    final session = AppSession(
      identitySession: identity,
      contextGateway: FakeSessionContextGateway(context: context),
      offlinePiiVault: vault,
    );
    addTearDown(session.close);
    addTearDown(identity.close);

    expect(
      await session.clearOrganizationOfflinePii(
        expectedAppUserId: 'wrong-app-user-id',
        organizationWorkspaceId: context.workspace.id,
      ),
      OfflinePiiWorkspaceDeletionResult.unavailable,
    );
    await session.start();
    expect(
      await session.clearOrganizationOfflinePii(
        expectedAppUserId: 'wrong-app-user-id',
        organizationWorkspaceId: context.workspace.id,
      ),
      OfflinePiiWorkspaceDeletionResult.unavailable,
    );
    expect(secureStore.values, isNotEmpty);
  });

  test('组织离线 PII 清理期间会话变化返回 unavailable 且不清新账号', () async {
    final identity = FakeIdentitySession(initial: _signedInIdentity());
    final secureStore = _MemorySecureValueStore();
    final vault = OfflinePiiVault(
      secureStore: secureStore,
      lockStore: _MemoryOfflinePiiLockStore(),
      clock: FixedClock(DateTime.utc(2026, 8, 6, 13)),
      installationId: 'installation-1',
    );
    final context = _withPii(_organizationContext);
    await vault.replace(
      externalSubject: 'external-subject-not-an-app-user-id',
      context: context,
      assignedTargets: const [],
      authorizedAtUtc: DateTime.utc(2026, 8, 6, 12),
    );
    await vault.replace(
      externalSubject: 'test-subject',
      context: context,
      assignedTargets: const [],
      authorizedAtUtc: DateTime.utc(2026, 8, 6, 12),
    );
    final session = AppSession(
      identitySession: identity,
      contextGateway: FakeSessionContextGateway(context: context),
      offlinePiiVault: vault,
    );
    addTearDown(session.close);
    addTearDown(identity.close);
    await session.start();
    secureStore.deleteRequested = Completer<void>();
    secureStore.releaseDelete = Completer<void>();

    final cleanup = session.clearOrganizationOfflinePii(
      expectedAppUserId: context.appUserId,
      organizationWorkspaceId: context.workspace.id,
    );
    await secureStore.deleteRequested!.future;
    final signIn = identity.signIn(
      email: 'new-account@example.test',
      password: 'ignored',
    );
    secureStore.releaseDelete!.complete();

    expect(await cleanup, OfflinePiiWorkspaceDeletionResult.unavailable);
    await signIn;
    expect(await vault.read('test-subject'), isA<OfflinePiiAvailable>());
  });

  test('已登录身份通过 bearer token 取得可信内部上下文', () async {
    final identity = FakeIdentitySession(initial: _signedInIdentity());
    final gateway = FakeSessionContextGateway();
    final session = AppSession(
      identitySession: identity,
      contextGateway: gateway,
    );
    addTearDown(session.close);
    addTearDown(identity.close);

    await session.start();

    expect(session.current.stage, AppSessionStage.ready);
    expect(session.current.context, same(syntheticSessionContext));
    expect(session.current.canRecordContact, isTrue);
    expect(gateway.receivedTokens, hasLength(1));
    expect(gateway.receivedTokens.single.value, 'test-only-access-token');
  });

  test('未登录时不请求 access token 或内部上下文', () async {
    final identity = FakeIdentitySession();
    final gateway = FakeSessionContextGateway();
    final session = AppSession(
      identitySession: identity,
      contextGateway: gateway,
    );
    addTearDown(session.close);
    addTearDown(identity.close);

    await session.start();

    expect(session.current.stage, AppSessionStage.signedOut);
    expect(session.current.context, isNull);
    expect(gateway.receivedTokens, isEmpty);
  });

  test('Backend 拒绝上下文时不暴露部分 ID', () async {
    final identity = FakeIdentitySession(initial: _signedInIdentity());
    final gateway = FakeSessionContextGateway(
      rejectWith: SessionContextFailureCode.unauthorized,
    );
    final session = AppSession(
      identitySession: identity,
      contextGateway: gateway,
    );
    addTearDown(session.close);
    addTearDown(identity.close);

    await session.start();

    expect(session.current.stage, AppSessionStage.failed);
    expect(
      session.current.contextFailure,
      SessionContextFailureCode.unauthorized,
    );
    expect(session.current.context, isNull);
    expect(session.current.canRecordContact, isFalse);
  });

  test('Backend 明确拒绝上下文时锁定旧离线 PII', () async {
    final identity = FakeIdentitySession(initial: _signedInIdentity());
    final vault = OfflinePiiVault(
      secureStore: _MemorySecureValueStore(),
      lockStore: _MemoryOfflinePiiLockStore(),
      clock: FixedClock(DateTime.utc(2026, 8, 6, 13)),
      installationId: 'installation-1',
    );
    await vault.replace(
      externalSubject: 'external-subject-not-an-app-user-id',
      context: syntheticSessionContext,
      assignedTargets: const [],
      authorizedAtUtc: DateTime.utc(2026, 8, 6, 12),
    );
    final session = AppSession(
      identitySession: identity,
      contextGateway: FakeSessionContextGateway(
        rejectWith: SessionContextFailureCode.unauthorized,
      ),
      offlinePiiVault: vault,
    );
    addTearDown(session.close);
    addTearDown(identity.close);

    await session.start();
    final cached = await vault.read('external-subject-not-an-app-user-id');

    expect(session.current.stage, AppSessionStage.failed);
    expect(cached, isA<OfflinePiiLocked>());
    expect(
      (cached as OfflinePiiLocked).reason,
      OfflinePiiLockReason.unauthorized,
    );
  });

  test('只有网络失败时才用未过期 vault 恢复可信上下文', () async {
    final identity = FakeIdentitySession(initial: _signedInIdentity());
    final vault = OfflinePiiVault(
      secureStore: _MemorySecureValueStore(),
      lockStore: _MemoryOfflinePiiLockStore(),
      clock: FixedClock(DateTime.utc(2026, 8, 6, 13)),
      installationId: 'installation-1',
    );
    await vault.replace(
      externalSubject: 'external-subject-not-an-app-user-id',
      context: syntheticSessionContext,
      assignedTargets: const [],
      authorizedAtUtc: DateTime.utc(2026, 8, 6, 12),
    );
    final session = AppSession(
      identitySession: identity,
      contextGateway: FakeSessionContextGateway(
        rejectWith: SessionContextFailureCode.networkUnavailable,
      ),
      offlinePiiVault: vault,
    );
    addTearDown(session.close);
    addTearDown(identity.close);

    await session.start();

    expect(session.current.stage, AppSessionStage.ready);
    expect(
      session.current.context?.appUserId,
      syntheticSessionContext.appUserId,
    );
    expect(session.current.fromOfflineCache, isTrue);
  });

  for (final operation in ['resolve', 'select', 'create']) {
    test('$operation 确认同项目失去 PII 权限后重启也不能恢复旧快照', () async {
      final identity = FakeIdentitySession(initial: _signedInIdentity());
      final secureStore = _MemorySecureValueStore();
      final lockStore = _MemoryOfflinePiiLockStore();
      OfflinePiiVault openVault() => OfflinePiiVault(
        secureStore: secureStore,
        lockStore: lockStore,
        clock: FixedClock(DateTime.utc(2026, 8, 6, 13)),
        installationId: 'installation-1',
      );
      final vault = openVault();
      await vault.replace(
        externalSubject: 'external-subject-not-an-app-user-id',
        context: _withPii(syntheticSessionContext),
        assignedTargets: const [],
        authorizedAtUtc: DateTime.utc(2026, 8, 6, 12),
      );
      final gateway = FakeSessionContextGateway(
        context: operation == 'resolve'
            ? syntheticSessionContext
            : _withPii(syntheticSessionContext),
        selectedContexts: {
          syntheticSessionContext.project.id: syntheticSessionContext,
        },
        createdContexts: const {'同项目': syntheticSessionContext},
      );
      final session = AppSession(
        identitySession: identity,
        contextGateway: gateway,
        offlinePiiVault: vault,
      );
      addTearDown(session.close);
      addTearDown(identity.close);
      await session.start();
      if (operation == 'select') {
        await session.selectProject(syntheticSessionContext.project.id);
      } else if (operation == 'create') {
        await session.createPersonalProject('同项目');
      }

      expect(session.current.stage, AppSessionStage.ready);
      expect(session.current.context, same(syntheticSessionContext));
      final cached = await vault.read('external-subject-not-an-app-user-id');
      expect(cached, isA<OfflinePiiLocked>());
      expect(
        (cached as OfflinePiiLocked).reason,
        OfflinePiiLockReason.unauthorized,
      );
      expect(secureStore.values, isEmpty);
      await session.close();

      final restarted = AppSession(
        identitySession: identity,
        contextGateway: FakeSessionContextGateway(
          rejectWith: SessionContextFailureCode.networkUnavailable,
        ),
        offlinePiiVault: openVault(),
      );
      addTearDown(restarted.close);
      await restarted.start();
      expect(restarted.current.stage, AppSessionStage.failed);
      expect(restarted.current.fromOfflineCache, isFalse);
    });
  }

  test('同身份在线重新解析到另一个项目先锁定旧快照', () async {
    final identity = FakeIdentitySession(
      initial: IdentitySnapshot(
        stage: IdentityStage.signedIn,
        principal: const IdentityPrincipal(
          externalSubject: 'test-subject',
          email: 'synthetic@example.test',
        ),
        expiresAt: DateTime.utc(2029),
      ),
    );
    final vault = await _vaultWithEmptySnapshot();
    final original = _withPii(syntheticSessionContext);
    final next = _withPii(_secondProject);
    final gateway = FakeSessionContextGateway(context: original);
    final session = AppSession(
      identitySession: identity,
      contextGateway: gateway,
      offlinePiiVault: vault,
    );
    addTearDown(session.close);
    addTearDown(identity.close);
    await session.start();
    await vault.replace(
      externalSubject: 'test-subject',
      context: original,
      assignedTargets: const [],
      authorizedAtUtc: DateTime.utc(2026, 8, 6, 12),
    );
    gateway.context = next;
    final resolved = session.changes.firstWhere(
      (snapshot) => identical(snapshot.context, next),
    );
    await identity.signIn(email: 'synthetic@example.test', password: 'ignored');
    await resolved;
    final cached = await vault.read('test-subject');
    expect(cached, isA<OfflinePiiLocked>());
    expect(
      (cached as OfflinePiiLocked).reason,
      OfflinePiiLockReason.contextChanged,
    );
  });

  for (final sameProject in [false, true]) {
    test('全新会话在线解析时比较磁盘快照项目 sameProject=$sameProject', () async {
      final identity = FakeIdentitySession(initial: _signedInIdentity());
      final vault = await _vaultWithEmptySnapshot(
        context: _withPii(syntheticSessionContext),
      );
      final next = _withPii(
        sameProject ? syntheticSessionContext : _secondProject,
      );
      final session = AppSession(
        identitySession: identity,
        contextGateway: FakeSessionContextGateway(context: next),
        offlinePiiVault: vault,
      );
      addTearDown(session.close);
      addTearDown(identity.close);
      await session.start();

      expect(session.current.context, same(next));
      final cached = await vault.read('external-subject-not-an-app-user-id');
      if (sameProject) {
        expect(cached, isA<OfflinePiiAvailable>());
      } else {
        expect(cached, isA<OfflinePiiLocked>());
        expect(
          (cached as OfflinePiiLocked).reason,
          OfflinePiiLockReason.contextChanged,
        );
      }
    });
  }

  test('切换项目等待 PII 清除时注销不会发布旧成功上下文', () async {
    final identity = FakeIdentitySession(initial: _signedInIdentity());
    final secureStore = _MemorySecureValueStore();
    final vault = OfflinePiiVault(
      secureStore: secureStore,
      lockStore: _MemoryOfflinePiiLockStore(),
      clock: FixedClock(DateTime.utc(2026, 8, 6, 13)),
      installationId: 'installation-1',
    );
    final session = AppSession(
      identitySession: identity,
      contextGateway: FakeSessionContextGateway(
        context: _withPii(syntheticSessionContext),
        selectedContexts: {_secondProject.project.id: _withPii(_secondProject)},
      ),
      offlinePiiVault: vault,
    );
    addTearDown(session.close);
    addTearDown(identity.close);
    await session.start();
    secureStore.deleteRequested = Completer<void>();
    secureStore.releaseDelete = Completer<void>();
    final selection = session.selectProject(_secondProject.project.id);
    await secureStore.deleteRequested!.future;
    final published = <AppSessionSnapshot>[];
    final subscription = session.changes.listen(published.add);
    addTearDown(subscription.cancel);
    final signedOut = session.changes.firstWhere(
      (snapshot) => snapshot.stage == AppSessionStage.signedOut,
    );
    await identity.signOut();
    secureStore.releaseDelete!.complete();
    final result = await selection;
    await signedOut;
    expect(result, isA<SessionContextRejected>());
    expect(
      published.where((snapshot) => snapshot.stage == AppSessionStage.ready),
      isEmpty,
    );
    expect(session.current.stage, AppSessionStage.signedOut);
  });

  test('身份刷新因断网失败时可用本机已知 subject 恢复 vault', () async {
    final identity = FakeIdentitySession(initial: _signedInIdentity())
      ..rejectNextWith = const IdentityFailure(
        code: IdentityFailureCode.networkUnavailable,
      );
    final vault = OfflinePiiVault(
      secureStore: _MemorySecureValueStore(),
      lockStore: _MemoryOfflinePiiLockStore(),
      clock: FixedClock(DateTime.utc(2026, 8, 6, 13)),
      installationId: 'installation-1',
    );
    await vault.replace(
      externalSubject: 'external-subject-not-an-app-user-id',
      context: syntheticSessionContext,
      assignedTargets: const [],
      authorizedAtUtc: DateTime.utc(2026, 8, 6, 12),
    );
    final session = AppSession(
      identitySession: identity,
      contextGateway: FakeSessionContextGateway(),
      offlinePiiVault: vault,
    );
    addTearDown(session.close);
    addTearDown(identity.close);

    await session.start();

    expect(session.current.stage, AppSessionStage.ready);
    expect(session.current.fromOfflineCache, isTrue);
  });

  test('身份恢复成功但获取 access token 时断网也可恢复 vault', () async {
    final identity = FakeIdentitySession(initial: _signedInIdentity())
      ..rejectNextAccessTokenWith = const IdentityFailure(
        code: IdentityFailureCode.networkUnavailable,
      );
    final vault = OfflinePiiVault(
      secureStore: _MemorySecureValueStore(),
      lockStore: _MemoryOfflinePiiLockStore(),
      clock: FixedClock(DateTime.utc(2026, 8, 6, 13)),
      installationId: 'installation-1',
    );
    await vault.replace(
      externalSubject: 'external-subject-not-an-app-user-id',
      context: syntheticSessionContext,
      assignedTargets: const [],
      authorizedAtUtc: DateTime.utc(2026, 8, 6, 12),
    );
    final session = AppSession(
      identitySession: identity,
      contextGateway: FakeSessionContextGateway(),
      offlinePiiVault: vault,
    );
    addTearDown(session.close);
    addTearDown(identity.close);

    await session.start();

    expect(session.current.stage, AppSessionStage.ready);
    expect(session.current.fromOfflineCache, isTrue);
  });

  test('身份恢复确认会话已不存在时锁定旧离线 PII', () async {
    final identity = FakeIdentitySession(initial: _signedInIdentity())
      ..rejectNextWith = const IdentityFailure(
        code: IdentityFailureCode.sessionMissing,
      );
    final vault = await _vaultWithEmptySnapshot();
    final session = AppSession(
      identitySession: identity,
      contextGateway: FakeSessionContextGateway(),
      offlinePiiVault: vault,
    );
    addTearDown(session.close);
    addTearDown(identity.close);

    await session.start();
    final cached = await vault.read('external-subject-not-an-app-user-id');

    expect(session.current.stage, AppSessionStage.failed);
    expect(cached, isA<OfflinePiiLocked>());
    expect(
      (cached as OfflinePiiLocked).reason,
      OfflinePiiLockReason.unauthorized,
    );
  });

  test('获取 token 确认凭据失效时锁定旧离线 PII', () async {
    final identity = FakeIdentitySession(initial: _signedInIdentity())
      ..rejectNextAccessTokenWith = const IdentityFailure(
        code: IdentityFailureCode.invalidCredentials,
      );
    final vault = await _vaultWithEmptySnapshot();
    final session = AppSession(
      identitySession: identity,
      contextGateway: FakeSessionContextGateway(),
      offlinePiiVault: vault,
    );
    addTearDown(session.close);
    addTearDown(identity.close);

    await session.start();
    final cached = await vault.read('external-subject-not-an-app-user-id');

    expect(session.current.stage, AppSessionStage.failed);
    expect(cached, isA<OfflinePiiLocked>());
    expect(
      (cached as OfflinePiiLocked).reason,
      OfflinePiiLockReason.unauthorized,
    );
  });

  test('退出登录先锁定并清除该身份的离线 PII', () async {
    final identity = FakeIdentitySession(initial: _signedInIdentity());
    final vault = OfflinePiiVault(
      secureStore: _MemorySecureValueStore(),
      lockStore: _MemoryOfflinePiiLockStore(),
      clock: FixedClock(DateTime.utc(2026, 8, 6, 13)),
      installationId: 'installation-1',
    );
    await vault.replace(
      externalSubject: 'external-subject-not-an-app-user-id',
      context: syntheticSessionContext,
      assignedTargets: const [],
      authorizedAtUtc: DateTime.utc(2026, 8, 6, 12),
    );
    final session = AppSession(
      identitySession: identity,
      contextGateway: FakeSessionContextGateway(),
      offlinePiiVault: vault,
    );
    addTearDown(session.close);
    addTearDown(identity.close);
    await session.start();

    await identity.signOut();
    await Future<void>.delayed(Duration.zero);
    final cached = await vault.read('external-subject-not-an-app-user-id');

    expect(session.current.stage, AppSessionStage.signedOut);
    expect(cached, isA<OfflinePiiLocked>());
    expect((cached as OfflinePiiLocked).reason, OfflinePiiLockReason.signedOut);
  });

  test('上次清除失败后同一身份再次启动会重试删除且保持锁定', () async {
    final secureStore = _MemorySecureValueStore();
    final vault = OfflinePiiVault(
      secureStore: secureStore,
      lockStore: _MemoryOfflinePiiLockStore(),
      clock: FixedClock(DateTime.utc(2026, 8, 6, 13)),
      installationId: 'installation-1',
    );
    await vault.replace(
      externalSubject: 'external-subject-not-an-app-user-id',
      context: syntheticSessionContext,
      assignedTargets: const [],
      authorizedAtUtc: DateTime.utc(2026, 8, 6, 12),
    );
    secureStore.failDelete = true;
    await vault.revoke(
      'external-subject-not-an-app-user-id',
      OfflinePiiLockReason.signedOut,
    );
    expect(secureStore.values, isNotEmpty);

    secureStore.failDelete = false;
    final identity = FakeIdentitySession(initial: _signedInIdentity());
    final session = AppSession(
      identitySession: identity,
      contextGateway: FakeSessionContextGateway(
        rejectWith: SessionContextFailureCode.networkUnavailable,
      ),
      offlinePiiVault: vault,
    );
    addTearDown(session.close);
    addTearDown(identity.close);

    await session.start();

    expect(secureStore.values, isEmpty);
    expect(session.current.stage, AppSessionStage.failed);
    expect(
      await vault.read('external-subject-not-an-app-user-id'),
      isA<OfflinePiiLocked>(),
    );
  });

  test('同一安装切换身份时先清除上一身份的离线 PII', () async {
    final identity = FakeIdentitySession(initial: _signedInIdentity());
    final vault = OfflinePiiVault(
      secureStore: _MemorySecureValueStore(),
      lockStore: _MemoryOfflinePiiLockStore(),
      clock: FixedClock(DateTime.utc(2026, 8, 6, 13)),
      installationId: 'installation-1',
    );
    await vault.replace(
      externalSubject: 'external-subject-not-an-app-user-id',
      context: syntheticSessionContext,
      assignedTargets: const [],
      authorizedAtUtc: DateTime.utc(2026, 8, 6, 12),
    );
    final session = AppSession(
      identitySession: identity,
      contextGateway: FakeSessionContextGateway(),
      offlinePiiVault: vault,
    );
    addTearDown(session.close);
    addTearDown(identity.close);
    await session.start();

    await identity.signIn(email: 'second@example.test', password: 'ignored');
    await Future<void>.delayed(Duration.zero);
    final previous = await vault.read('external-subject-not-an-app-user-id');

    expect(previous, isA<OfflinePiiLocked>());
    expect(
      (previous as OfflinePiiLocked).reason,
      OfflinePiiLockReason.signedOut,
    );
  });

  for (final switchAccount in [false, true]) {
    test('身份变化在慢 PII 清除前撤下旧 ready 上下文 switchAccount=$switchAccount', () async {
      final identity = FakeIdentitySession(initial: _signedInIdentity());
      final secureStore = _MemorySecureValueStore();
      final session = AppSession(
        identitySession: identity,
        contextGateway: FakeSessionContextGateway(
          context: _withPii(syntheticSessionContext),
        ),
        offlinePiiVault: OfflinePiiVault(
          secureStore: secureStore,
          lockStore: _MemoryOfflinePiiLockStore(),
          clock: FixedClock(DateTime.utc(2026, 8, 6, 13)),
          installationId: 'installation-1',
        ),
      );
      addTearDown(session.close);
      addTearDown(identity.close);
      await session.start();
      expect(session.current.stage, AppSessionStage.ready);
      secureStore.deleteRequested = Completer<void>();
      secureStore.releaseDelete = Completer<void>();
      final published = <AppSessionSnapshot>[];
      final subscription = session.changes.listen(published.add);
      addTearDown(subscription.cancel);
      final settled = session.changes.firstWhere(
        (snapshot) => switchAccount
            ? snapshot.stage == AppSessionStage.ready &&
                  snapshot.identity?.principal?.externalSubject ==
                      'test-subject'
            : snapshot.stage == AppSessionStage.signedOut,
      );
      if (switchAccount) {
        await identity.signIn(email: 'next@example.test', password: 'ignored');
      } else {
        await identity.signOut();
      }
      await secureStore.deleteRequested!.future;
      try {
        expect(
          session.current.stage,
          switchAccount
              ? AppSessionStage.resolvingContext
              : AppSessionStage.signedOut,
        );
        expect(session.current.context, isNull);
        expect(published, isNotEmpty);
        expect(published.last.context, isNull);
      } finally {
        secureStore.releaseDelete!.complete();
        await settled;
      }
    });
  }

  for (final latestIsSignedIn in [false, true]) {
    test('旧身份清除完成不覆盖后来的会话 latestIsSignedIn=$latestIsSignedIn', () async {
      final identity = FakeIdentitySession(initial: _signedInIdentity());
      final secureStore = _MemorySecureValueStore();
      final session = AppSession(
        identitySession: identity,
        contextGateway: FakeSessionContextGateway(
          context: _withPii(syntheticSessionContext),
        ),
        offlinePiiVault: OfflinePiiVault(
          secureStore: secureStore,
          lockStore: _MemoryOfflinePiiLockStore(),
          clock: FixedClock(DateTime.utc(2026, 8, 6, 13)),
          installationId: 'installation-1',
        ),
      );
      addTearDown(session.close);
      addTearDown(identity.close);
      await session.start();
      secureStore.deleteRequested = Completer<void>();
      secureStore.releaseDelete = Completer<void>();
      if (latestIsSignedIn) {
        await identity.signOut();
      } else {
        await identity.signIn(email: 'next@example.test', password: 'ignored');
      }
      await secureStore.deleteRequested!.future;
      final latest = session.changes.firstWhere(
        (snapshot) => latestIsSignedIn
            ? snapshot.stage == AppSessionStage.ready
            : snapshot.stage == AppSessionStage.signedOut,
      );
      if (latestIsSignedIn) {
        await identity.signIn(email: 'next@example.test', password: 'ignored');
      } else {
        await identity.signOut();
      }
      await latest;
      secureStore.releaseDelete!.complete();
      await Future<void>.delayed(Duration.zero);
      expect(
        session.current.stage,
        latestIsSignedIn ? AppSessionStage.ready : AppSessionStage.signedOut,
      );
      expect(
        session.current.identity?.principal?.externalSubject,
        latestIsSignedIn ? 'test-subject' : null,
      );
    });
  }

  test('解析中的旧响应不能在注销后恢复上下文', () async {
    final identity = FakeIdentitySession(initial: _signedInIdentity());
    final gateway = _DelayedGateway();
    final session = AppSession(
      identitySession: identity,
      contextGateway: gateway,
    );
    addTearDown(session.close);
    addTearDown(identity.close);

    final start = session.start();
    await gateway.requested.future;
    await identity.signOut();
    gateway.complete(const SessionContextSuccess(syntheticSessionContext));
    await start;
    await Future<void>.delayed(Duration.zero);

    expect(session.current.stage, AppSessionStage.signedOut);
    expect(session.current.context, isNull);
  });

  test('本人选择项目后取得该项目的可信问卷上下文', () async {
    final identity = FakeIdentitySession(initial: _signedInIdentity());
    final gateway = FakeSessionContextGateway(
      availableContexts: const [syntheticSessionContext, _secondProject],
      selectedContexts: const {
        '55555555-5555-4555-8555-555555555555': _secondProject,
      },
    );
    final session = AppSession(
      identitySession: identity,
      contextGateway: gateway,
    );
    addTearDown(session.close);
    addTearDown(identity.close);
    await session.start();

    final result = await session.selectProject(_secondProject.project.id);

    expect(result, isA<SessionContextSuccess>());
    expect(session.current.context, same(_secondProject));
    expect(session.current.availableContexts, [
      syntheticSessionContext,
      _secondProject,
    ]);
    expect(gateway.selectedProjectIds, [_secondProject.project.id]);
  });

  test('切换项目成功后先锁定上一项目的离线 PII', () async {
    final identity = FakeIdentitySession(initial: _signedInIdentity());
    final vault = OfflinePiiVault(
      secureStore: _MemorySecureValueStore(),
      lockStore: _MemoryOfflinePiiLockStore(),
      clock: FixedClock(DateTime.utc(2026, 8, 6, 13)),
      installationId: 'installation-1',
    );
    await vault.replace(
      externalSubject: 'external-subject-not-an-app-user-id',
      context: syntheticSessionContext,
      assignedTargets: const [],
      authorizedAtUtc: DateTime.utc(2026, 8, 6, 12),
    );
    final session = AppSession(
      identitySession: identity,
      contextGateway: FakeSessionContextGateway(
        availableContexts: const [syntheticSessionContext, _secondProject],
        selectedContexts: const {
          '55555555-5555-4555-8555-555555555555': _secondProject,
        },
      ),
      offlinePiiVault: vault,
    );
    addTearDown(session.close);
    addTearDown(identity.close);
    await session.start();

    await session.selectProject(_secondProject.project.id);
    final cached = await vault.read('external-subject-not-an-app-user-id');

    expect(cached, isA<OfflinePiiLocked>());
    expect(
      (cached as OfflinePiiLocked).reason,
      OfflinePiiLockReason.contextChanged,
    );
  });

  test('本人创建个人项目后立即采用新项目上下文', () async {
    final identity = FakeIdentitySession(initial: _signedInIdentity());
    final gateway = FakeSessionContextGateway(
      createdContexts: const {'校园推广': _secondProject},
    );
    final session = AppSession(
      identitySession: identity,
      contextGateway: gateway,
    );
    addTearDown(session.close);
    addTearDown(identity.close);
    await session.start();

    final result = await session.createPersonalProject('校园推广');

    expect(result, isA<SessionContextSuccess>());
    expect(session.current.context, same(_secondProject));
    expect(gateway.createdProjectNames, ['校园推广']);
  });
}

const _secondProject = TrustedSessionContext(
  appUserId: '11111111-1111-4111-8111-111111111111',
  workspace: WorkspaceContext(
    id: '22222222-2222-4222-8222-222222222222',
    kind: WorkspaceKind.personal,
    name: '个人空间',
  ),
  project: ProjectContext(
    id: '55555555-5555-4555-8555-555555555555',
    name: '校园推广',
  ),
  questionnaireVersion: QuestionnaireVersionContext(
    id: '66666666-6666-4666-8666-666666666666',
    versionNumber: 1,
  ),
  capabilities: {'record_contact'},
);

const _organizationContext = TrustedSessionContext(
  appUserId: '11111111-1111-4111-8111-111111111111',
  workspace: WorkspaceContext(
    id: '66666666-6666-4666-8666-666666666666',
    kind: WorkspaceKind.organization,
    name: '同行组织',
  ),
  project: ProjectContext(
    id: '77777777-7777-4777-8777-777777777777',
    name: '组织推广项目',
  ),
  questionnaireVersion: QuestionnaireVersionContext(
    id: '88888888-8888-4888-8888-888888888888',
    versionNumber: 1,
  ),
  capabilities: {'record_contact', 'view_assigned_target_pii'},
);

TrustedSessionContext _withPii(TrustedSessionContext context) =>
    TrustedSessionContext(
      appUserId: context.appUserId,
      workspace: context.workspace,
      project: context.project,
      questionnaireVersion: context.questionnaireVersion,
      capabilities: {...context.capabilities, 'view_assigned_target_pii'},
    );

IdentitySnapshot _signedInIdentity() {
  return IdentitySnapshot(
    stage: IdentityStage.signedIn,
    principal: const IdentityPrincipal(
      externalSubject: 'external-subject-not-an-app-user-id',
      email: 'synthetic@example.test',
    ),
    expiresAt: DateTime.utc(2030, 1, 2, 4, 4),
  );
}

Future<OfflinePiiVault> _vaultWithEmptySnapshot({
  TrustedSessionContext context = syntheticSessionContext,
}) async {
  final vault = OfflinePiiVault(
    secureStore: _MemorySecureValueStore(),
    lockStore: _MemoryOfflinePiiLockStore(),
    clock: FixedClock(DateTime.utc(2026, 8, 6, 13)),
    installationId: 'installation-1',
  );
  await vault.replace(
    externalSubject: 'external-subject-not-an-app-user-id',
    context: context,
    assignedTargets: const [],
    authorizedAtUtc: DateTime.utc(2026, 8, 6, 12),
  );
  return vault;
}

final class _DelayedGateway implements SessionContextGateway {
  final requested = Completer<void>();
  final _result = Completer<SessionContextResult>();

  void complete(SessionContextResult result) => _result.complete(result);

  @override
  Future<void> close() async {}

  @override
  Future<SessionContextResult> resolve(IdentityAccessToken accessToken) {
    requested.complete();
    return _result.future;
  }

  @override
  Future<SessionContextResult> selectProject(
    IdentityAccessToken accessToken,
    String projectId,
  ) async =>
      const SessionContextRejected(SessionContextFailureCode.serverRejected);

  @override
  Future<SessionContextResult> createPersonalProject(
    IdentityAccessToken accessToken,
    String displayName,
  ) async =>
      const SessionContextRejected(SessionContextFailureCode.serverRejected);
}

final class _MemorySecureValueStore implements SecureValueStore {
  final values = <String, String>{};
  var failDelete = false;
  Completer<void>? deleteRequested;
  Completer<void>? releaseDelete;

  @override
  Future<void> delete(String key) async {
    final requested = deleteRequested;
    if (requested != null && !requested.isCompleted) requested.complete();
    await releaseDelete?.future;
    if (failDelete) throw StateError('synthetic delete failure');
    values.remove(key);
  }

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
