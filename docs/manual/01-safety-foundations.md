# 第 1 章：先让正式代码安全、可替换、可验证

## 1. 这一章解决什么

旧 Demo 可以展示界面，但它把数据库创建、演示账号、MD5 密码、自动 seed 和大部分业务集中在启动流程与 `AppController`。如果直接在这上面继续堆功能，会出现三个问题：

1. 正式运行也可能写入演示资料；
2. 测试无法稳定控制“现在几点”“下一个 ID 是什么”“数据库打开失败怎么办”；
3. 将来从 Supabase 切换认证商，或从本地 SQLite 同步到 PostgreSQL 时，UI 和业务代码会一起被迫重写。

Slice 0 先建立安全地基。它还没有实现现代“接触”业务，而是让每个后续切片有可验证的落点。

## 2. Composition root：全 App 的装配点

`AppDependencies` 是正式 App 唯一的 composition root，也就是“把真正实现装配起来的地方”。它决定正式运行使用哪一个数据库、时钟、ID 生成器和外部身份实现。

```dart
factory AppDependencies.production() {
  return AppDependencies(
    databaseFactory: const DriftLocalDatabaseFactory(),
    clock: const SystemClock(),
    idGenerator: SecureIdGenerator(),
  );
}
```

这段代码没有提供 `LegacyDemoAccess`，所以普通 `flutter run` 不会得到 MD5 比对、默认账号或自动 seed 的能力。旧原型必须显式运行另一个入口：

```bash
flutter run -t lib/main_demo.dart
```

关键不变量是：**正式入口不是靠一个容易漏设的布尔值关闭 Demo，而是根本没有装配 Demo Adapter。**

## 3. “测试接缝”到底是什么

接缝（seam）像插座：正式运行插真实实现，测试插一个可控制的实现。它不是要求把每一行代码都抽象成 interface。

例如正式时钟返回真实时间：

```dart
final class SystemClock implements AppClock {
  const SystemClock();

  @override
  DateTime now() => DateTime.now();
}
```

测试时钟永远返回指定时刻：

```dart
final class FixedClock implements AppClock {
  const FixedClock(this.value);

  final DateTime value;

  @override
  DateTime now() => value;
}
```

于是“今日接触数”“锁定到期”“统计周期”这些测试不会因为执行时间不同而偶尔失败。ID、数据库工厂、Identity 和平台能力采用同样原则。

只有这些真实边界值得保留接缝：

- production 与测试确实要换实现；
- 六个平台能力不同；
- 外部认证、网络、数据库可能以复杂方式失败；
- 测试必须稳定制造超时、拒绝、过期或部分失败。

普通的内部计算如果只有一种实现，就保持普通函数，避免为了“看起来架构化”制造很多浅层文件。

## 4. 启动失败为什么是结果，不是裸异常

数据库初始化可能失败。如果 UI 直接读取第三方异常文字，换一个 SQLite 版本就可能破坏界面和测试。`AppDependencies.start()` 因此返回两种稳定结果：

```text
AppStartupReady(controller)
AppStartupFailed(failure.code)
```

UI 只根据稳定 code 显示可恢复状态；原始 `cause` 和 `stackTrace` 留给诊断，不直接暴露给使用者。这里的“错误结果接缝”把外部实现的混乱失败语义翻译成 App 自己的有限语言。

## 5. SQLite、Drift 与真正的 SQL

SQLite 是设备内数据库；Drift 是 Dart 里的数据库工具。Drift 帮我们获得类型检查、migration 辅助和查询结果映射，但底层仍是 SQLite 和 SQL。

当前保存的 v5 schema 只用于证明旧结构和升级路径，不代表现代领域模型。机器可读快照在 `drift_schemas/drift_schema_v5.json`，完整盘点见 [Legacy Drift v5 盘点](../migrations/legacy-v5-inventory.md)。

测试大致做三件事：

```text
v5 JSON schema
    ↓ 建立一个临时旧库
运行当前 Drift migration
    ↓
核对表、列和约束
```

临时测试库不包含真实用户资料。将来每次正式 schema 变化都要保存上一版 fixture，证明“从零创建”和“从旧版升级”都得到相同有效结构。

## 6. PostgreSQL migration 为什么单独存在

SQLite 服务于离线设备；PostgreSQL 服务于 Backend 的共享事务事实。两者承担不同工作，不能把 SQLite 文件上传后当云数据库，也不能让 Flutter 直连 PostgreSQL。

PostgreSQL schema 由仓库内按编号排序的 `.sql` 文件定义。例如：

```text
0001_bootstrap.sql
0002_identity.sql
0003_contact_journal.sql
```

迁移器记录已经执行的版本和文件 checksum。同一文件执行过以后若被改写，检查应失败，而不是把历史悄悄改掉。新需求必须新增 migration；上线后的 migration 不回写，错误用 forward-fix 修复。

正式 Backend 只获得最小权限 runtime role。建表、改 schema 和读取 migration 历史使用部署身份；Flutter 中永远没有 PostgreSQL 密码或 Supabase `service_role` secret。

## 7. 为什么不“每一行都写注释”

本项目的手写业务代码以中文注释为主，但注释重点是读代码本身看不出的内容：

- 参数从哪里来、单位是什么、`null` 表示什么；
- 函数有哪些副作用和权限要求；
- 事务必须同时成功的事实；
- 统计分母、时区、缺失值和隐私抑制；
- 为什么选择某个降级或失败语义。

对每个括号、赋值或明显变量机械复述，会让真正重要的规则被淹没，也容易在代码变化后留下错误说明。生成的 Drift 文件更不能手工逐行注释；应解释生成命令、输入和验证方式。

## 8. Identity 与平台能力为什么也是接缝

`IdentitySession` 把 Supabase 的 `User`、`Session` 和 `AuthException` 留在 Adapter 内。业务代码只看到 external subject、可选 email、过期时间和稳定 failure code。external subject 仍然不是内部用户 ID；Backend 验证 token 后才把它映射为自己的 `app_user_id`，并用 SQL membership／capability 决定权限。

Supabase 的默认 Flutter 存储是 SharedPreferences，不适合直接保存 native refresh token。本项目用 `flutter_secure_storage` 覆盖 session 和 PKCE verifier；正式配置还会拒绝 secret/service-role key。没有配置时返回明确 unavailable，不回退到旧密码表。

“package 支持某平台”也不等于“运行时能力可用”。例如 Web 安全存储需要 HTTPS／localhost，Linux 需要 libsecret 和 keyring，定位还要权限。因此 `PlatformCapabilities` 有三种状态：available、runtime probe required、unavailable。`PlatformPolicy` 在 probe 尚未成功时禁止敏感对象离线缓存，并降级为前台同步；Widget 不自行猜平台。

真实认证流程与 build 证据见 [Supabase Auth 六平台 Spike](../spikes/supabase-auth-six-platform.md)。

## 9. 本章可自行验证的命令

正式安全入口：

```bash
flutter run
```

显式 legacy Demo：

```bash
flutter run -t lib/main_demo.dart
```

格式、静态分析与测试：

```bash
dart format --output=none --set-exit-if-changed lib test
dart analyze
flutter test
```

Drift v5 migration 测试：

```bash
flutter test test/data/local_database_migration_test.dart
```

读完这一章，应能回答：正式入口为什么拿不到 MD5、测试为什么能固定时间、Drift 与 SQLite 各是什么，以及为什么 PostgreSQL migration 不能在 Dashboard 里手工代替。
