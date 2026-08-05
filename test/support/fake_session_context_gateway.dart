import 'package:tongxingzhe_app/app_session/session_context_gateway.dart';
import 'package:tongxingzhe_app/identity/identity_session.dart';

final class FakeSessionContextGateway implements SessionContextGateway {
  FakeSessionContextGateway({TrustedSessionContext? context, this.rejectWith})
    : context = context ?? syntheticSessionContext;

  TrustedSessionContext context;
  SessionContextFailureCode? rejectWith;
  final List<IdentityAccessToken> receivedTokens = [];
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
    return SessionContextSuccess(context);
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
