import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tongxingzhe_app/app/app_dependencies.dart';
import 'package:tongxingzhe_app/app/tongxingzhe_app.dart';
import 'package:tongxingzhe_app/data/local_database.dart';
import 'package:tongxingzhe_app/data/local_database_factory.dart';
import 'package:tongxingzhe_app/foundation/runtime_values.dart';

import '../support/fake_identity_session.dart';
import '../support/fake_platform_capabilities.dart';

void main() {
  testWidgets('正式入口不显示 legacy 登录、注册或演示账号', (tester) async {
    final database = LocalDatabase(NativeDatabase.memory());
    final dependencies = AppDependencies(
      databaseFactory: _SingleDatabaseFactory(database),
      clock: _FixedClock(DateTime.utc(2030, 1, 2, 3, 4)),
      idGenerator: _SequenceIdGenerator(),
      identitySessionFactory: FakeIdentitySessionFactory(FakeIdentitySession()),
      platformCapabilitiesProvider: const FakePlatformCapabilitiesProvider(),
    );

    await tester.pumpWidget(TongxingzheApp(dependencies: dependencies));
    await tester.pumpAndSettle();
    addTearDown(database.close);

    expect(find.text('正式认证尚未配置'), findsOneWidget);
    expect(find.text('admin1'), findsNothing);
    expect(find.text('注册'), findsNothing);
    expect(find.text('忘记密码'), findsNothing);
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

final class _SequenceIdGenerator implements IdGenerator {
  var _next = 0;

  @override
  String next() => 'test-${_next++}';
}
