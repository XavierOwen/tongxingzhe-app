import '../app_session/app_session.dart';
import '../app_session/http_session_context_gateway.dart';
import '../app_session/session_context_gateway.dart';
import '../data/local_database.dart';
import '../data/local_database_factory.dart';
import '../device/device_identity_store.dart';
import '../features/contact_journal/contact_journal.dart';
import '../foundation/runtime_values.dart';
import '../identity/identity_session.dart';
import '../identity/supabase/supabase_identity_session.dart';
import '../platform/platform_capabilities.dart';
import '../services/location_service.dart';
import '../sync/http_sync_transport.dart';
import '../sync/sync_engine_factory.dart';
import '../sync/sync_transport.dart';
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
    required this.sessionContextGateway,
    required this.platformCapabilitiesProvider,
    this.locationCapture = const LocationService(),
    this.syncTransportBuilder,
    this.legacyDemoAccess,
  });

  factory AppDependencies.production() {
    return AppDependencies(
      databaseFactory: const DriftLocalDatabaseFactory(),
      clock: const SystemClock(),
      idGenerator: SecureIdGenerator(),
      identitySessionFactory: productionIdentitySessionFactory(),
      sessionContextGateway: productionSessionContextGateway(),
      platformCapabilitiesProvider: const FlutterPlatformCapabilitiesProvider(),
      syncTransportBuilder: productionSyncTransport,
    );
  }

  final LocalDatabaseFactory databaseFactory;
  final AppClock clock;
  final IdGenerator idGenerator;
  final IdentitySessionFactory identitySessionFactory;
  final SessionContextGateway sessionContextGateway;
  final PlatformCapabilitiesProvider platformCapabilitiesProvider;
  final ContactLocationCapture locationCapture;
  final SyncTransport? Function(IdentitySession)? syncTransportBuilder;

  /// 临时兼容 legacy demo；正式 composition root 永远不提供此 Adapter。
  final LegacyDemoAccess? legacyDemoAccess;

  Future<AppStartupResult> start() async {
    LocalDatabase? database;
    IdentitySession? identitySession;
    AppSession? appSession;
    SyncEngineFactory? syncEngineFactory;
    try {
      identitySession = await identitySessionFactory.open();
    } catch (error, stackTrace) {
      await sessionContextGateway.close();
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
      await sessionContextGateway.close();
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
      final contactJournal = ContactJournal(
        database: database,
        clock: clock,
        idGenerator: idGenerator,
      );
      await controller.load();
      final deviceId = await DeviceIdentityStore(
        database,
        idGenerator,
      ).loadOrCreate();
      final syncTransport = syncTransportBuilder?.call(identitySession);
      if (syncTransport != null) {
        syncEngineFactory = SyncEngineFactory(
          database: database,
          clock: clock,
          idGenerator: idGenerator,
          transport: syncTransport,
          jitter: SecureSyncJitter(),
        );
      }
      appSession = AppSession(
        identitySession: identitySession,
        contextGateway: sessionContextGateway,
      );
      await appSession.start();
      return AppStartupReady(
        controller: controller,
        contactJournal: contactJournal,
        deviceId: deviceId,
        syncEngineFactory: syncEngineFactory,
        identitySession: identitySession,
        appSession: appSession,
        platformCapabilities: platformCapabilities,
        platformPolicy: PlatformPolicy.from(platformCapabilities),
        locationCapture: locationCapture,
      );
    } catch (error, stackTrace) {
      await database?.close();
      await syncEngineFactory?.close();
      await appSession?.close();
      if (appSession == null) {
        await sessionContextGateway.close();
      }
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
    required this.contactJournal,
    required this.deviceId,
    required this.syncEngineFactory,
    required this.identitySession,
    required this.appSession,
    required this.platformCapabilities,
    required this.platformPolicy,
    required this.locationCapture,
  });

  final AppController controller;
  final ContactJournal contactJournal;
  final String deviceId;
  final SyncEngineFactory? syncEngineFactory;
  final IdentitySession identitySession;
  final AppSession appSession;
  final PlatformCapabilities platformCapabilities;
  final PlatformPolicy platformPolicy;
  final ContactLocationCapture locationCapture;
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
