import '../identity/identity_session.dart';

enum WorkspaceKind { personal, organization }

final class WorkspaceContext {
  const WorkspaceContext({
    required this.id,
    required this.kind,
    required this.name,
  });

  final String id;
  final WorkspaceKind kind;
  final String name;
}

final class ProjectContext {
  const ProjectContext({required this.id, required this.name});

  final String id;
  final String name;
}

final class QuestionnaireVersionContext {
  const QuestionnaireVersionContext({
    required this.id,
    required this.versionNumber,
  });

  final String id;
  final int versionNumber;
}

/// Backend 已按 token 重新验证的内部操作上下文。
///
/// Flutter 不从 external subject、email 或 legacy Demo 数据推导这些 ID。
final class TrustedSessionContext {
  const TrustedSessionContext({
    required this.appUserId,
    required this.workspace,
    required this.project,
    required this.questionnaireVersion,
    required this.capabilities,
  });

  final String appUserId;
  final WorkspaceContext workspace;
  final ProjectContext project;
  final QuestionnaireVersionContext questionnaireVersion;
  final Set<String> capabilities;
}

enum SessionContextFailureCode {
  notConfigured,
  unauthorized,
  networkUnavailable,
  invalidResponse,
  serverRejected,
}

sealed class SessionContextResult {
  const SessionContextResult();
}

final class SessionContextSuccess extends SessionContextResult {
  const SessionContextSuccess(
    this.context, {
    this.availableContexts = const [],
  });

  final TrustedSessionContext context;
  final List<TrustedSessionContext> availableContexts;
}

final class SessionContextRejected extends SessionContextResult {
  const SessionContextRejected(this.code);

  final SessionContextFailureCode code;
}

/// 只有这个 Adapter 可以把 bearer token 送到自有 Backend。
abstract interface class SessionContextGateway {
  Future<SessionContextResult> resolve(IdentityAccessToken accessToken);

  Future<SessionContextResult> selectProject(
    IdentityAccessToken accessToken,
    String projectId,
  );

  Future<SessionContextResult> createPersonalProject(
    IdentityAccessToken accessToken,
    String displayName,
  );

  Future<void> close();
}

final class UnavailableSessionContextGateway implements SessionContextGateway {
  const UnavailableSessionContextGateway();

  @override
  Future<void> close() async {}

  @override
  Future<SessionContextResult> resolve(IdentityAccessToken accessToken) async =>
      const SessionContextRejected(SessionContextFailureCode.notConfigured);

  @override
  Future<SessionContextResult> selectProject(
    IdentityAccessToken accessToken,
    String projectId,
  ) async =>
      const SessionContextRejected(SessionContextFailureCode.notConfigured);

  @override
  Future<SessionContextResult> createPersonalProject(
    IdentityAccessToken accessToken,
    String displayName,
  ) async =>
      const SessionContextRejected(SessionContextFailureCode.notConfigured);
}
