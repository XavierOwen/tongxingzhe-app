import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tongxingzhe_app/data/local_database.dart';

import '../generated_migrations/schema.dart';

void main() {
  test('保存的 schema v5 与当前 LocalDatabase 结构一致', () async {
    final verifier = SchemaVerifier(GeneratedHelper());
    final connection = await verifier.startAt(5);
    final database = LocalDatabase(connection);
    addTearDown(database.close);

    await verifier.migrateAndValidate(database, 5);
  });
}
