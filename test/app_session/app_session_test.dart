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

Future<OfflinePiiVault> _vaultWithEmptySnapshot() async {
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

  @override
  Future<void> delete(String key) async {
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
