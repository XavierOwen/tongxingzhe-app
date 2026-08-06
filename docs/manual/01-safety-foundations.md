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

保存的 v5 schema 只用于证明旧结构和升级起点，不代表现代领域模型。机器可读基线在 `drift_schemas/drift_schema_v5.json`，当前 v17 与升级过程见[第 3 章](03-contact-journal-and-local-sql.md)，完整盘点见 [Legacy Drift v5 盘点](../migrations/legacy-v5-inventory.md)。

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

macOS 的安全能力还受 App Sandbox 和代码签名控制。[`com.apple.security.network.client`](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.network.client) 表示 App 可以主动连接 Supabase；调试 VM 使用的 `network.server` 不能替代它。[`flutter_secure_storage` 的 macOS 配置](https://pub.dev/packages/flutter_secure_storage)要求 `keychain-access-groups`，让 session 使用受数据保护的 Keychain；该 entitlement 必须由 Apple Development／Distribution 签名授权。缺少前者时 HTTPS 会得到 `Operation not permitted`，缺少后者时 Keychain 会得到系统错误 `-34018`。

个人 Team ID 不写进共享 Xcode project。开发者把 `macos/Runner/Configs/LocalSigning.xcconfig.example` 复制为被 Git 忽略的 `LocalSigning.xcconfig`，再填写自己的 Team ID；正式运行因此使用签名和 Keychain。GitHub CI 没有开发者私钥，只执行 `CODE_SIGNING_ALLOWED=NO` 的无签名编译；它能证明代码可构建，却不能证明 Keychain 可运行。真实设备探针与静态 entitlement 测试分别覆盖这两个不同结论。

iOS 同样把 refresh token 放进 Keychain，因此 Runner 的 Debug／Profile 和 Release 都必须引用包含 `keychain-access-groups` 的 entitlement。共享工程只记录能力声明，由 Xcode 在本机选择开发 Team 和 provisioning profile；个人证书资料不提交。静态测试能防止 entitlement 文件或 Xcode 接线以后被误删，但只有 Apple Development 签名后的真机探针，才能证明系统确实允许 App 写入并在下一进程读取 Keychain。

真机启动还存在三个容易混淆的系统门槛：设备信任这台 Mac、Developer Mode 已启用、Developer App Certificate 已信任。前两项通过并不表示第三项自动通过。若 Xcode 报 `Developer App Certificate is not trusted`，应在 iPhone 的“设置 → 通用 → VPN 与设备管理”中信任对应开发者，再重新发起启动；已经失败的那次启动不会因事后信任而自动重试。测试时保持设备解锁、连接稳定，并把这类环境失败与 Supabase／业务失败分开记录。

本项目的原生认证探针必须给 `flutter test` 传入 `--no-uninstall`。Flutter 的 integration test 默认在结束时卸载 App；当它是设备上该开发者签名的最后一款 App 时，iOS 随后也不再保留这项开发者信任，下一阶段重新安装就会再次要求手工信任。`--no-uninstall` 不会跳过下一次构建或覆盖安装，只是不在每轮测试结束时删除 App。整套真机验证完成后，可以手工删除测试 App；此时以后再次安装需要重新信任属于预期安全行为。

“package 支持某平台”也不等于“运行时能力可用”。例如 Web 安全存储需要 HTTPS／localhost，Linux 需要 libsecret 和 keyring，定位还要权限。因此 `PlatformCapabilities` 记录当前设备的五种运行态：available、runtime probe required、denied、temporarily unavailable、unavailable。它不记录项目是否已取得该平台的发布证据。`PlatformPolicy` 在 probe 尚未成功、权限被拒绝或能力暂时失败时禁止敏感对象离线缓存，并按能力降级；Widget 不自行猜平台。跨平台 build、真实设备流程和发布结论另见 [六平台能力证据矩阵](../spikes/six-platform-capability-matrix.md)。

Web 自动化还需要明确“谁拥有浏览器”。`flutter drive` 已经会让 WebDriver 启动测试浏览器；如果同时把 App device 设成 `chrome`，受影响的 Flutter 版本还会额外启动一个普通 Chrome，使同一认证测试执行两遍。本项目的 runner 对使用者仍接受 `AUTH_SPIKE_DEVICE=chrome`，但内部使用 `web-server`，只让 ChromeDriver 启动浏览器。这里守住的是一个重要副作用边界：一次测试只能对应一次注册、发信或恢复请求。跨浏览器进程恢复还必须固定 localhost origin，并复用持久 Chrome profile；否则 port 或 profile 改变后得到的是另一份 Web 存储，失败不能归因于 Supabase session。

错误类型也不能只看 SDK 类名。Supabase SDK 的 `AuthRetryableFetchException` 既可能表示根本没有收到 HTTP response，也可能包装服务器的 5xx response。前者没有 HTTP status，映射为 `networkUnavailable`；后者带 status，映射为 `providerRejected`，并只暴露 `http_<status>` 这种安全 provider code。服务器 response body 不进入 UI、分析事件或稳定业务合同。

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
dart format --output=none --set-exit-if-changed \
  lib test integration_test test_driver tool
dart analyze
flutter test --no-pub
```

Drift v5／v6／v8 到当前 v17 的 migration 测试：

```bash
flutter test --no-pub test/data/local_database_migration_test.dart
```

Docker、Backend 和 CI 的完整操作步骤见[第 9 章](09-local-docker-and-ci-testing.md)。

macOS 网络和 Keychain entitlement 回归：

```bash
flutter test test/platform/macos_entitlements_test.dart
```

iOS Keychain entitlement 与 Xcode 接线回归：

```bash
flutter test test/platform/ios_entitlements_test.dart
```

读完这一章，应能回答：正式入口为什么拿不到 MD5、测试为什么能固定时间、Drift 与 SQLite 各是什么，以及为什么 PostgreSQL migration 不能在 Dashboard 里手工代替。
