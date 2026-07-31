import '../app/app_dependencies.dart';
import '../data/local_database_factory.dart';
import '../foundation/runtime_values.dart';
import '../identity/identity_session.dart';
import '../platform/platform_capabilities.dart';
import 'md5_legacy_demo_access.dart';

/// legacy demo 的独立 composition root。
///
/// 正式 `main.dart` 不导入本文件。开发者必须通过 `main_demo.dart` 明确选择
/// 旧原型，避免一次普通 production 启动自动写入演示账号和记录。
abstract final class LegacyDemoDependencies {
  static AppDependencies create({
    LocalDatabaseFactory databaseFactory = const DriftLocalDatabaseFactory(),
    AppClock clock = const SystemClock(),
    IdGenerator? idGenerator,
  }) {
    return AppDependencies(
      databaseFactory: databaseFactory,
      clock: clock,
      idGenerator: idGenerator ?? SecureIdGenerator(),
      identitySessionFactory: const UnavailableIdentitySessionFactory(),
      platformCapabilitiesProvider: const FlutterPlatformCapabilitiesProvider(),
      legacyDemoAccess: Md5LegacyDemoAccess(),
    );
  }
}
