import 'package:tongxingzhe_app/app_session/session_context_gateway.dart';
import 'package:tongxingzhe_app/identity/identity_session.dart';

final class FakeSessionContextGateway implements SessionContextGateway {
  FakeSessionContextGateway({
    TrustedSessionContext? context,
    List<TrustedSessionContext>? availableContexts,
    Map<String, TrustedSessionContext>? selectedContexts,
    Map<String, TrustedSessionContext>? createdContexts,
    this.rejectWith,
  }) : context = context ?? syntheticSessionContext,
       availableContexts = availableContexts ?? const [syntheticSessionContext],
       selectedContexts = selectedContexts ?? const {},
       createdContexts = createdContexts ?? const {};

  TrustedSessionContext context;
  List<TrustedSessionContext> availableContexts;
  Map<String, TrustedSessionContext> selectedContexts;
  Map<String, TrustedSessionContext> createdContexts;
  SessionContextFailureCode? rejectWith;
  final List<IdentityAccessToken> receivedTokens = [];
  final List<String> selectedProjectIds = [];
  final List<String> createdProjectNames = [];
  bool isClosed = false;

  @override
  Future<void> close() async {
    isClosed = true;
  }

  @override
  Future<SessionContextResult> resolve(IdentityAccessToken accessToken) async {
    receivedTokens.add(accessToken);
    final failure = rejectWith;
    if (failure != null) {
      return SessionContextRejected(failure);
    }
    return SessionContextSuccess(context, availableContexts: availableContexts);
  }

  @override
  Future<SessionContextResult> selectProject(
    IdentityAccessToken accessToken,
    String projectId,
  ) async {
    receivedTokens.add(accessToken);
    selectedProjectIds.add(projectId);
    final failure = rejectWith;
    if (failure != null) {
      return SessionContextRejected(failure);
    }
    final selected = selectedContexts[projectId];
    if (selected == null) {
      return const SessionContextRejected(
        SessionContextFailureCode.serverRejected,
      );
    }
    context = selected;
    return SessionContextSuccess(
      selected,
      availableContexts: availableContexts,
    );
  }

  @override
  Future<SessionContextResult> createPersonalProject(
    IdentityAccessToken accessToken,
    String displayName,
  ) async {
    receivedTokens.add(accessToken);
    createdProjectNames.add(displayName);
    final failure = rejectWith;
    if (failure != null) {
      return SessionContextRejected(failure);
    }
    final created = createdContexts[displayName];
    if (created == null) {
      return const SessionContextRejected(
        SessionContextFailureCode.serverRejected,
      );
    }
    context = created;
    availableContexts = [...availableContexts, created];
    return SessionContextSuccess(created, availableContexts: availableContexts);
  }
}

const syntheticSessionContext = TrustedSessionContext(
  appUserId: '11111111-1111-4111-8111-111111111111',
  workspace: WorkspaceContext(
    id: '22222222-2222-4222-8222-222222222222',
    kind: WorkspaceKind.personal,
    name: '个人空间',
  ),
  project: ProjectContext(
    id: '33333333-3333-4333-8333-333333333333',
    name: '我的推广项目',
  ),
  questionnaireVersion: QuestionnaireVersionContext(
    id: '44444444-4444-4444-8444-444444444444',
    versionNumber: 1,
  ),
  capabilities: {'record_contact'},
);

const syntheticSecondSessionContext = TrustedSessionContext(
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
    versionNumber: 2,
  ),
  capabilities: {'record_contact'},
);
