import 'local_database.dart';

/// 在 composition root 处打开本地数据库。
///
/// Feature 不自行调用 `LocalDatabase.defaults()`；测试可以在同一 seam 提供
/// 内存数据库或确定性的打开失败。
abstract interface class LocalDatabaseFactory {
  LocalDatabase open();
}

final class DriftLocalDatabaseFactory implements LocalDatabaseFactory {
  const DriftLocalDatabaseFactory();

  @override
  LocalDatabase open() => LocalDatabase.defaults();
}
