import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tongxingzhe_app/app/app_dependencies.dart';
import 'package:tongxingzhe_app/data/local_database.dart';
import 'package:tongxingzhe_app/data/local_database_factory.dart';
import 'package:tongxingzhe_app/foundation/runtime_values.dart';
import 'package:tongxingzhe_app/legacy_demo/legacy_demo_dependencies.dart';

import '../support/fake_identity_session.dart';
import '../support/fake_platform_capabilities.dart';

void main() {
  test('正式启动不会创建 legacy 演示账号或记录', () async {
    final database = LocalDatabase(NativeDatabase.memory());
    final dependencies = AppDependencies(
      databaseFactory: _SingleDatabaseFactory(database),
      clock: _FixedClock(DateTime.utc(2030, 1, 2, 3, 4)),
      idGenerator: _SequenceIdGenerator(),
      identitySessionFactory: FakeIdentitySessionFactory(FakeIdentitySession()),
      platformCapabilitiesProvider: const FakePlatformCapabilitiesProvider(),
    );

    final startup = await dependencies.start();

    expect(startup, isA<AppStartupReady>());
    final controller = (startup as AppStartupReady).controller;
    addTearDown(controller.dispose);
    expect(controller.users, isEmpty);
    expect(controller.records, isEmpty);

    final login = await controller.login('admin1', 'admin1');
    expect(login.success, isFalse);
    expect(login.messageKey, 'authUnavailableInProduction');
  });

  test('数据库无法打开时返回稳定的启动失败结果', () async {
    final identity = FakeIdentitySession();
    final dependencies = AppDependencies(
      databaseFactory: const _ThrowingDatabaseFactory(),
      clock: _FixedClock(DateTime.utc(2030, 1, 2, 3, 4)),
      idGenerator: _SequenceIdGenerator(),
      identitySessionFactory: FakeIdentitySessionFactory(identity),
      platformCapabilitiesProvider: const FakePlatformCapabilitiesProvider(),
    );

    final startup = await dependencies.start();

    expect(startup, isA<AppStartupFailed>());
    final failure = (startup as AppStartupFailed).failure;
    expect(failure.code, 'local_database_initialization_failed');
    expect(failure.cause, isA<StateError>());
    expect(identity.isClosed, isTrue);
  });

  test('平台能力探测失败时释放身份并返回稳定结果', () async {
    final identity = FakeIdentitySession();
    final dependencies = AppDependencies(
      databaseFactory: const _ThrowingDatabaseFactory(),
      clock: _FixedClock(DateTime.utc(2030, 1, 2, 3, 4)),
      idGenerator: _SequenceIdGenerator(),
      identitySessionFactory: FakeIdentitySessionFactory(identity),
      platformCapabilitiesProvider: FakePlatformCapabilitiesProvider(
        failure: StateError('synthetic capability failure'),
      ),
    );

    final startup = await dependencies.start();

    expect(startup, isA<AppStartupFailed>());
    expect(
      (startup as AppStartupFailed).failure.code,
      'platform_capability_detection_failed',
    );
    expect(identity.isClosed, isTrue);
  });

  test('legacy demo 只能通过独立 composition root 显式启用', () async {
    final database = LocalDatabase(NativeDatabase.memory());
    final dependencies = LegacyDemoDependencies.create(
      databaseFactory: _SingleDatabaseFactory(database),
      clock: _FixedClock(DateTime.utc(2030, 1, 2, 3, 4)),
      idGenerator: _SequenceIdGenerator(),
    );

    final startup = await dependencies.start();

    expect(startup, isA<AppStartupReady>());
    final controller = (startup as AppStartupReady).controller;
    addTearDown(controller.dispose);
    expect(controller.users, hasLength(5));
    expect(controller.records, hasLength(30));

    final login = await controller.loginDemoAccount('admin1');
    expect(login.success, isTrue);
  });
}

final class _SingleDatabaseFactory implements LocalDatabaseFactory {
  _SingleDatabaseFactory(this.database);

  final LocalDatabase database;

  @override
  LocalDatabase open() => database;
}

final class _FixedClock implements AppClock {
  const _FixedClock(this.value);

  final DateTime value;

  @override
  DateTime now() => value;
}

final class _ThrowingDatabaseFactory implements LocalDatabaseFactory {
  const _ThrowingDatabaseFactory();

  @override
  LocalDatabase open() => throw StateError('synthetic database failure');
}

final class _SequenceIdGenerator implements IdGenerator {
  var _next = 0;

  @override
  String next() => 'test-${_next++}';
}
