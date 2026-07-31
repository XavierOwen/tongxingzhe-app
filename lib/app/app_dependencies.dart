import '../data/local_database.dart';
import '../data/local_database_factory.dart';
import '../foundation/runtime_values.dart';
import '../identity/identity_session.dart';
import '../identity/supabase/supabase_identity_session.dart';
import '../platform/platform_capabilities.dart';
import 'app_controller.dart';
import 'legacy_demo_access.dart';

/// App 唯一的 composition root。
///
/// 它集中决定正式数据库、时钟和 ID 实现，并把数据库打开／Controller 加载
/// 转成调用者可处理的结果，避免启动异常被 FutureBuilder 当成成功。
final class AppDependencies {
  const AppDependencies({
    required this.databaseFactory,
    required this.clock,
    required this.idGenerator,
    required this.identitySessionFactory,
    required this.platformCapabilitiesProvider,
    this.legacyDemoAccess,
  });

  factory AppDependencies.production() {
    return AppDependencies(
      databaseFactory: const DriftLocalDatabaseFactory(),
      clock: const SystemClock(),
      idGenerator: SecureIdGenerator(),
      identitySessionFactory: productionIdentitySessionFactory(),
      platformCapabilitiesProvider: const FlutterPlatformCapabilitiesProvider(),
    );
  }

  final LocalDatabaseFactory databaseFactory;
  final AppClock clock;
  final IdGenerator idGenerator;
  final IdentitySessionFactory identitySessionFactory;
  final PlatformCapabilitiesProvider platformCapabilitiesProvider;

  /// 临时兼容 legacy demo；正式 composition root 永远不提供此 Adapter。
  final LegacyDemoAccess? legacyDemoAccess;

  Future<AppStartupResult> start() async {
    LocalDatabase? database;
    IdentitySession? identitySession;
    try {
      identitySession = await identitySessionFactory.open();
    } catch (error, stackTrace) {
      return AppStartupFailed(
        AppStartupFailure(
          code: error is SupabaseConfigurationException
              ? 'identity_configuration_invalid'
              : 'identity_initialization_failed',
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }

    PlatformCapabilities platformCapabilities;
    try {
      platformCapabilities = await platformCapabilitiesProvider.load();
    } catch (error, stackTrace) {
      await identitySession.close();
      return AppStartupFailed(
        AppStartupFailure(
          code: 'platform_capability_detection_failed',
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }

    try {
      database = databaseFactory.open();
      final controller = AppController(
        database: database,
        clock: clock,
        idGenerator: idGenerator,
        legacyDemoAccess: legacyDemoAccess,
      );
      await controller.load();
      return AppStartupReady(
        controller: controller,
        identitySession: identitySession,
        platformCapabilities: platformCapabilities,
        platformPolicy: PlatformPolicy.from(platformCapabilities),
      );
    } catch (error, stackTrace) {
      await database?.close();
      await identitySession.close();
      return AppStartupFailed(
        AppStartupFailure(
          code: 'local_database_initialization_failed',
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }
}

sealed class AppStartupResult {
  const AppStartupResult();
}

final class AppStartupReady extends AppStartupResult {
  const AppStartupReady({
    required this.controller,
    required this.identitySession,
    required this.platformCapabilities,
    required this.platformPolicy,
  });

  final AppController controller;
  final IdentitySession identitySession;
  final PlatformCapabilities platformCapabilities;
  final PlatformPolicy platformPolicy;
}

final class AppStartupFailed extends AppStartupResult {
  const AppStartupFailed(this.failure);

  final AppStartupFailure failure;
}

/// 启动失败的稳定外部表示。
///
/// [cause] 和 [stackTrace] 只供诊断；UI 和测试依据稳定 [code] 决定表现，
/// 不解析第三方数据库异常文字。
final class AppStartupFailure {
  const AppStartupFailure({
    required this.code,
    required this.cause,
    required this.stackTrace,
  });

  final String code;
  final Object cause;
  final StackTrace stackTrace;
}
