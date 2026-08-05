import '../app_session/session_context_gateway.dart';
import '../data/local_database.dart';
import '../foundation/runtime_values.dart';
import 'sync_engine.dart';
import 'sync_models.dart';
import 'sync_transport.dart';

/// Composition root 创建并拥有的 SyncEngine 工厂。
///
/// Transport 在整个 App 生命周期内复用。每个可信上下文得到新的 worker ID，
/// 防止旧 session 的迟到 ACK 被新 session 当成本执行器结果。
final class SyncEngineFactory {
  const SyncEngineFactory({
    required this.database,
    required this.clock,
    required this.idGenerator,
    required this.transport,
    required this.jitter,
  });

  final LocalDatabase database;
  final AppClock clock;
  final IdGenerator idGenerator;
  final SyncTransport transport;
  final SyncJitter jitter;

  SyncEngine create(TrustedSessionContext context) {
    return SyncEngine(
      database: database,
      clock: clock,
      workerId: idGenerator.next(),
      scope: SyncScope(
        appUserId: context.appUserId,
        workspaceId: context.workspace.id,
        projectId: context.project.id,
      ),
      transport: transport,
      jitter: jitter,
    );
  }

  Future<void> close() => transport.close();
}
