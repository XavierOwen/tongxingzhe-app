import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tongxingzhe_app/app_session/app_session.dart';
import 'package:tongxingzhe_app/app_session/session_context_gateway.dart';
import 'package:tongxingzhe_app/identity/identity_session.dart';

import '../support/fake_identity_session.dart';
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
