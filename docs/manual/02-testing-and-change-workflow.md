# 第 2 章：用测试和证据安全地修改代码

## 1. 这一章解决什么

写出一段“现在可以运行”的代码并不难，难的是回答下面这些问题：

1. 它真的满足需求，还是只在开发者脑中满足？
2. 修复一个错误时，是否意外破坏了别的功能？
3. 半年后需求变化，怎样知道旧规则仍然成立？
4. 云服务、浏览器、数据库和 App 同时参与时，失败究竟发生在哪一层？
5. build 成功、单元测试成功和真实设备成功，分别能证明什么？

这一章用本项目的 Supabase Auth Web 与 iOS 验证作为完整例子，解释测试驱动开发、回归测试、测试接缝、分层测试、证据式诊断、持续集成和完成标准。这里描述的不是额外教学 Demo；所有测试都围绕正式 `IdentitySession`、正式 Supabase Adapter 和正式 runner 展开。

操作步骤与逐平台结果保存在 [Supabase Auth 六平台 Spike](../spikes/supabase-auth-six-platform.md)。本章负责解释“为什么这样测试”和“以后如何复用这套方法”。

需要安装工具、运行本机测试或使用 Docker 重建 PostgreSQL 时，按[第 9 章](09-local-docker-and-ci-testing.md)操作。

## 2. 先分清几个容易混在一起的词

| 术语 | 它回答的问题 | 本项目中的例子 |
| --- | --- | --- |
| 测试接缝（test seam） | 从哪个稳定边界观察行为？ | `IdentitySession`、`tool/run_supabase_auth_spike.sh` |
| 单元测试（unit test） | 一个小而稳定的合同在可控输入下是否正确？ | HTTP 500 是否映射为 `providerRejected` |
| 集成测试（integration test） | 多个真实组件接在一起后是否工作？ | Flutter Adapter、Web 安全存储与 ChromeDriver 一起运行 |
| 端到端／真实环境探针 | 从用户入口到真实外部服务是否完整通过？ | hosted Supabase 发 OTP、确认账号、恢复密码 |
| 回归测试（regression test） | 已修复的旧错误会不会再次出现？ | 防止 Web runner 再次同时启动两个 Chrome |
| 静态分析（static analysis） | 不运行 App 时，类型、语法和 lint 是否有明显问题？ | `dart analyze` |
| 持续集成（CI） | 每次提交是否由干净机器自动重复必要检查？ | GitHub Actions 的六平台 build 与测试 job |
| Spike | 在正式大规模实现前，用有边界的实验回答高风险问题 | Supabase 是否能满足六平台认证合同 |

这些词不能互相替代。例如，CI 中 Web build 成功只证明代码能够编译，不证明 Gmail 收到了 OTP；真实 OTP 成功也不证明 Windows 安全存储可用。

## 3. 什么是 Red-Green，以及它和回归测试有什么区别

### 3.1 Red：先看到测试正确地失败

Red 是“红灯”。先写一个描述需求的测试，在修复代码之前运行它，并确认它因为目标行为缺失而失败。

这一步看似多余，其实在验证测试本身是否有感知能力。如果一个新测试在旧错误仍存在时就通过，它可能测错了入口、断言没有作用，或者只验证了常量等于自己。

本轮 Web runner 的公开合同是：

```text
使用者设置 AUTH_SPIKE_DEVICE=chrome
    ↓
runner 内部只启动一个 WebDriver 浏览器
    ↓
跨进程测试固定使用同一个 origin 和 Chrome profile
```

我们先修改 [runner 回归测试](../../test/tool/run_supabase_auth_spike_test.dart)，要求 Flutter 命令包含固定 `--web-port` 和持久 `--user-data-dir`。旧 runner 没有这些参数，所以测试明确失败；实际失败点是找不到 `--web-port`。这就是有效的 Red：它准确指出缺少的公开行为，而不是随机报错。

### 3.2 Green：只实现足以满足当前测试的改动

Green 是“绿灯”。给 [认证 runner](../../tool/run_supabase_auth_spike.sh) 加入固定 hostname、port 和 Chrome profile 后，同一个测试通过。

Green 阶段强调最小实现。它不顺便重写所有脚本、不提前设计尚未要求的浏览器框架，也不把 Supabase 类型泄漏进业务模块。小改动更容易判断因果：测试从红变绿，主要变量就是刚刚加入的行为。

### 3.3 Review／Refactor：行为稳定后再整理

行业常把完整节奏称为 **Red-Green-Refactor**：先失败、再通过、最后在不改变行为的前提下改善结构。为了降低一次改动的范围，本项目把工作组织为多个很小的 Red-Green vertical slice，等行为完整后再进入独立的 review／refactor 阶段：

- 删除临时诊断输出；
- 合并重复代码；
- 改善名称和中文注释；
- 检查测试是否绑死私有实现；
- 重新运行完整测试，而不只运行刚才的目标测试。

重构不是“再加几个功能”。如果行为合同发生变化，应重新开启下一轮 Red-Green。

### 3.4 回归测试描述用途，不描述写法

回归测试的目的，是把已经发生过的错误变成一个长期自动检查。它可以用 TDD 的 Red-Green 方法写成，也可能在已有测试中补充断言。

所以“红绿回归测试”不是一种与单元测试并列的独立类别。更准确的说法是：**我们用 Red-Green 流程建立了一条回归测试。**

本轮保留下来的两条回归测试分别防止：

1. Web runner 再次双开普通 Chrome 与 HeadlessChrome，导致注册或发信执行两遍；
2. Supabase 返回带 HTTP status 的 5xx 时，被 App 错误翻译成“设备断网”。

## 4. 好测试从公开接缝观察行为

测试接缝像插座。正式运行插入真实 Supabase，局部测试可以插入可控制的 HTTP 边界；调用者看到的仍然是同一个公开合同。

本项目认证区域约定两个接缝：

- `IdentitySession`：业务层只看登录阶段、内部稳定 failure code 和 token 能力；
- `tool/run_supabase_auth_spike.sh`：开发者只设置设备和受忽略的配置文件，由 runner 负责正确启动平台探针。

测试不直接调用 `_mapFailure` 这样的私有函数，也不只断言某个内部 helper 被调用一次。私有实现可以重构；只要公开结果没变，测试就不应该无故失败。

### 4.1 Arrange-Act-Assert

很多测试使用 **Arrange-Act-Assert（准备、行动、断言）** 结构：

```dart
// 教学化简示例，不是另一套生产实现。
// Arrange：准备一个会返回 HTTP 500 的外部边界。
final identity = identityWithSyntheticHttpStatus(500);

// Act：仍通过公开 IdentitySession 发起注册。
final result = await identity.signUp(
  email: 'learner@example.test',
  password: 'synthetic-password',
);

// Assert：业务只看到稳定、安全的错误合同。
expect(result.failure.code, IdentityFailureCode.providerRejected);
expect(result.failure.providerCode, 'http_500');
```

BDD 文档有时把同一结构写成 **Given-When-Then（给定、当、那么）**。名字不同，核心都是把输入、动作和可观察结果分开，使测试像一条可读规格。

### 4.2 只在系统边界使用 mock／fake

Mock 或 fake 是可控制的替身。适合替换的是外部认证、网络、时间、随机数、设备能力等系统边界；不应把自己拥有的每个内部类都 mock 掉。

HTTP 500 测试使用 synthetic response，是因为它要稳定制造认证商错误，而且不能每次都故意破坏真实 Supabase。真实 OTP 流程则不使用假邮件，因为它的问题正是 SMTP、模板、Supabase 与 Flutter 是否真的接通。这两类测试互补，不能彼此冒充。

## 5. 为什么要分层测试

越接近真实用户，测试覆盖的组件越多，但速度更慢、失败原因也更多。越靠近小模块，测试越快、越容易制造边界条件，但不能证明真实云服务已经接好。

| 层次 | 速度与稳定性 | 能证明 | 不能单独证明 |
| --- | --- | --- | --- |
| 格式与静态分析 | 很快、稳定 | 代码可解析、类型与 lint 基本正确 | 业务结果、真实网络 |
| 单元／合同测试 | 快、可重复 | failure mapping、配置拒绝规则等局部合同 | SMTP、设备权限 |
| runner 集成测试 | 快、可重复 | shell 入口组装了正确的 Flutter 参数 | Chrome 与 hosted Supabase 一定成功 |
| 真实 Web／设备探针 | 较慢、依赖环境 | Flutter、平台存储、网络、Supabase 的完整路径 | 其他未运行平台 |
| 六平台 build CI | 较慢、自动化 | 各平台代码能在干净环境构建 | 真机 Keychain、keyring、邮件到达 |

正确策略不是只保留一种测试，而是让每层回答自己的问题。若真实探针失败，先用较小的测试缩小范围；若局部测试全绿但真实探针仍失败，就检查平台权限、外部服务和测试执行框架。

## 6. 本轮 Web 与 iOS 认证为什么按这些步骤测试

### 6.1 `signup_request`：把“请求成功”和“邮件送达”分开

第一步调用真实注册接口，并要求 Adapter 返回 `awaitingEmailConfirmation`。这证明 Supabase 接受了请求，但只有测试邮箱实际收到 OTP，才能证明自定义 SMTP 与模板也工作。

旧 runner 在这里暴露了一个重要问题：普通 Chrome 的 `/signup` 返回 200 并送达 OTP，但同一轮 `flutter drive` 又启动 HeadlessChrome，对同一邮箱重复注册。第二次请求触发 PostgreSQL email 唯一约束并返回 500。

因此，事实不是“SMTP 失败”，而是：

```text
第一次普通 Chrome 请求 → 200 → OTP 送达
第二次 HeadlessChrome 请求 → 重复邮箱 → 500
```

Supabase 日志、浏览器类型、时间戳和 PostgreSQL `23505` 共同支持“双重执行”解释。仅凭 App 显示的 `networkUnavailable` 会得出错误结论，所以诊断必须比较多层证据。

### 6.2 runner 回归测试：一次外部副作用只能执行一次

注册、发信、支付、删除或数据库 migration 都有外部副作用。一次自动化测试若运行两遍，不只是浪费时间，还会制造重复数据或错误邮件。

runner 因此保留使用者熟悉的 `AUTH_SPIKE_DEVICE=chrome`，但内部把 Flutter App device 设为 `web-server`，只让 ChromeDriver 拥有浏览器。回归测试通过公开 shell 入口捕获 Flutter 参数，防止以后有人把内部 device 改回 `chrome`。

### 6.3 HTTP 500 mapping：服务器失败不能冒充设备断网

Supabase SDK 的 `AuthRetryableFetchException` 可能表示两种不同事实：

- 没有收到任何 HTTP response：更接近 DNS、连接或设备网络问题；
- 收到带 status 的 5xx response：网络已经到达认证商，但服务器未能完成请求。

Adapter 现在按是否存在 HTTP status 区分：前者是 `networkUnavailable`，后者是 `providerRejected`，并只暴露安全的 `http_<status>`。response body 可能包含内部细节，不能进入 UI 或分析事件。

### 6.4 `signup_confirm`：收到邮件不等于账号已确认

收到 OTP 只证明发信路径。`signup_confirm` 还要把 OTP 交回 Supabase，要求结果进入 `signedIn`，再成功登出。这才证明 App 内输入 OTP 的正式产品路径成立。

### 6.5 `recovery_request` 与 `recovery_confirm`：恢复是两段合同

恢复请求要求结果为 `recoveryCodeSent`，测试邮箱还必须收到一封新的恢复邮件。注册 OTP 和恢复 OTP 语义不同，不能混用。

恢复确认随后验证三件事：

1. 新的 recovery OTP 能建立 `changingRecoveredPassword` session；
2. 新密码更新后回到 `signedIn`；
3. App 可以正常登出，不把恢复 session 留在测试环境。

### 6.6 新密码 `session`：防止“接口表面成功”

密码更新接口返回成功，仍可能存在状态未持久化或后续登录异常。我们用修改后的新密码重新运行 `session`，验证登录、强制刷新 token、重建 Identity Adapter 后恢复，以及登出。

这一步说明新密码在新的测试会话里确实可用，而不只是更新函数返回了成功状态。

### 6.7 `session_start` 与 `session_restore`：关闭浏览器后还能不能恢复

同一个浏览器页面里重建 Dart Adapter，只证明对象重建；它没有证明浏览器进程结束后安全存储仍存在。

真正的跨进程测试拆成两次独立运行：

```text
session_start
  登录 → 刷新 → 保存 session → 退出浏览器但不登出

session_restore
  启动新的浏览器进程 → 不使用密码 → 从安全存储恢复 → 登出
```

Web 存储受 origin 限制，Chrome profile 也决定存储位置。因此两次运行必须同时固定：

- hostname：`127.0.0.1`
- port：默认 `57320`
- profile：默认 `.dart_tool/supabase-auth-web-profile/`

只固定 profile 而改变 port，仍然是不同 origin；只固定 port 而每次创建临时 profile，也仍然看不到上一进程的存储。

本轮先让 `session_start` 在固定 origin 上通过并结束第一个浏览器进程，再单独启动 `session_restore`。第二个进程没有调用登录，也没有使用配置中的密码；它从安全存储恢复 session、读取 token，随后成功登出。因此 Web 跨进程恢复已取得真实证据，不是把同一进程内的 Adapter 重建误写成 pass。

### 6.8 iOS entitlement：先证明工程接线，再证明真机授权

`flutter_secure_storage` 在 iOS 上最终依赖系统 Keychain。仅仅把 Dart package 加入 `pubspec.yaml`，或让 iOS App 编译成功，都不能证明 Runner 声明了 Keychain Sharing。

本轮先写一个静态平台测试，检查两个公开的工程事实：

1. Debug／Profile 与 Release 各有对应 entitlement 文件，并包含 `keychain-access-groups`；
2. Runner 的三种 build configuration 引用了正确文件。

旧工程运行该测试时，两个文件不存在、三个 Xcode 引用计数为零，因此得到三个预期 Red。补齐最小 entitlement 与 Xcode 接线后，同一组断言转为 Green。这个测试会长期保留，以后即使升级 Flutter 或重整 Xcode 工程，也会在能力声明被误删时立即报警。

不过，静态 Green 仍不能证明签名、provisioning profile 或设备策略允许 Keychain。于是下一层必须在 Apple Development 签名的 iPhone 上运行真实 `session`。这不是重复测试，而是两层分别回答不同问题：

```text
静态平台测试 → 工程是否声明并引用 Keychain capability
真机合同探针 → iOS 是否真的授权写入、读取和跨进程恢复
```

### 6.9 iOS `session_start` 与 `session_restore`：第二进程不使用密码

iOS 的快速 `session` 已经验证登录、刷新、Keychain 读取、Adapter 重建与登出，但 Adapter 重建仍发生在同一个 App 进程内。为了排除“只是内存里还有 session”，本轮又拆成两个独立启动：

```text
第一个真机进程：session_start → 登录、刷新、写入 Keychain、不登出
第二个真机进程：session_restore → 不使用密码、读取 Keychain、登出
```

第二个进程成功恢复并读取 token，随后登出，证明 session 的确跨进程保存在 iPhone Keychain。启动前出现的开发者证书未信任属于设备环境失败：完成系统要求的重启和显式信任后，必须重新发起一次新的启动；原来被拒绝的请求不会自行恢复。它不能记为 Supabase 失败，也不能因为最终通过而从记录中删除。

### 6.10 原生 runner 为什么必须保留测试 App

本轮最初的每个 iOS mode 都会重新要求信任同一开发者证书。失败日志始终停在安装／启动阶段，Dart 测试显示 `No tests ran`；手工信任后重新运行则通过。这说明认证请求、OTP 与 Supabase 不是触发条件。

继续检查公开命令后发现，`flutter test` 的 integration test 参数 `uninstall` 默认为 true，测试设备结束时会停止并卸载 App。该 App 又是手机上由这位开发者签名的唯一 App；删除后设备不再保留这项信任，下一阶段重新安装便再次询问。

修复仍按 Red-Green 进行：runner 回归测试通过公开 shell 入口捕获原生 Flutter 参数，先要求出现 `--no-uninstall`。旧命令缺少它，测试准确变红；原生分支加入参数后，同一测试转绿。Web 使用 `flutter drive`，不经过这个分支，所以没有被顺带改变。

```text
旧流程：构建 → 安装 → 测试 → 卸载最后一款开发 App → 信任消失
新流程：构建 → 覆盖安装 → 测试 → 保留 App → 下一 mode 继续受信任
```

保留 App 不是正式发布策略，只是多阶段真机探针的测试夹具生命周期。它不会让失败的旧启动自动恢复，也不会把构建 pass 冒充运行时 pass。整套 synthetic 测试完成后应手工删除 App；之后再次安装而需要重新信任是预期结果。

### 6.11 邮件 API 成功为什么仍不能写成“送达成功”

iOS 第一次 `signup_request` 对原测试邮箱返回 HTTP 200，导出的 Supabase 日志也全部是 success，但收件箱没有 OTP。这些日志没有收件服务器的最终投递回执，因此只能证明 Auth 接受请求；学校邮箱过滤、地址别名规则、垃圾邮件隔离、SMTP 后续退信等解释仍然并存。

换成受控工作邮箱后，App 再次得到注册成功状态，收件箱实际收到 OTP，随后 `signup_confirm` 也通过。这一组对照足以让 iOS 注册合同继续验证，却仍不足以断言原邮箱究竟在哪一层拦截。测试记录因此分别写“API 200”和“邮件实际送达”，不把二者合成一个模糊的 success。

### 6.12 失败与恢复测试：不能只证明顺利路径

自动保存、定位和正式提交都依赖可能失败的边界。只测试成功路径，会漏掉更重要的问题：失败后页面是否误报“已保存”、输入是否丢失、使用者能否重试。

接触表单先通过 `ContactEntryStore`、`DeviceTimeZoneProvider` 和 `ContactLocationCapture` 制造确定性失败。测试观察公开页面状态，确认失败不会清除输入，再把同一边界改为成功并执行重试。这个过程仍是 Red-Green，但合同包含两个阶段：

```text
第一次操作失败 → 显示可恢复状态，原输入仍在
同一页面重试成功 → 保存或提交完成，没有重复事实
```

这种测试有时称为 failure-recovery test。它不是要求程序永不失败，而是要求失败可见、状态可信、恢复路径可执行。

### 6.13 跨数据库合同测试：同一业务口径、两份可执行 SQL

本机 Drift/SQLite 与云端 PostgreSQL 使用不同 SQL 方言，不能把同一段 SQL 原样复制到两端。但“哪些行属于当前用户和项目”“时间窗怎样闭合”“场次和触达人数各是什么单位”必须一致。

项目因此让两端读取同一份 synthetic CSV。Drift 测试和 PostgreSQL fixture 分别执行正式查询，再核对场次、触达人数、兴趣分布、渠道分布和最近发生时间。共用的是输入与预期业务结果，不是数据库实现。

这属于 contract test（合同测试）：两个实现只要满足同一公开合同，就允许各自使用最合适的查询。它能发现某一端忘记 project 条件、把闭区间写成半开区间，或把 `COUNT(*)` 和 `SUM(reach_count)` 混用。

### 6.14 数据库 migration 为什么要做旧版本升级测试

空库能按 v17 建成，只证明新安装可用，不能证明 v16 或更早版本的用户能安全升级。迁移测试先用保存的旧 schema 建库并写入 synthetic 数据，再运行正式 migration，核对原内容、默认值、索引、外键和新约束。

本项目遇到过两类典型 Red。第一类是新增列已经存在，但 SQLite 仍保留旧 `CHECK` 约束。仅执行 `ALTER TABLE ... ADD COLUMN` 无法更新整张表的约束，必须用 Drift `TableMigration` 重建表。第二类发生在跨多个版本升级时：重建步骤使用当前表定义，如果旧版本缺少当前列，就必须把该列放进 `newColumns`；否则复制数据时会引用不存在的源列。迁移测试检查的是“旧数据经过升级后的数据库”，不是只比较当前 Dart 类或新建表。

## 7. 本轮测试证据表

| 测试 | 为什么测试 | 通过标准 | 当前结果 |
| --- | --- | --- | --- |
| Web `signup_request` | 验证注册接口、SMTP 与模板起点 | 接口接受请求，邮箱收到 OTP | pass；同时发现旧 runner 双重执行 |
| runner 单浏览器回归 | 防止带副作用的测试执行两遍 | Flutter 使用 `web-server`，只有 WebDriver 启动 Chrome | Red 后 Green，自动测试保留 |
| synthetic HTTP 500 | 区分服务器失败和设备断网 | 500 映射 `providerRejected/http_500` | Red 后 Green，自动测试保留 |
| Web `signup_confirm` | 证明 App 内 OTP 确认可用 | `signedIn` 后成功登出 | pass |
| Web `recovery_request` | 证明恢复邮件请求可用 | `recoveryCodeSent` 且邮箱收到新 OTP | pass |
| Web `recovery_confirm` | 证明恢复 OTP 与改密码可用 | 改密码后 `signedIn`，再登出 | pass |
| Web 新密码 `session` | 证明新密码可再次登录 | 登录、刷新、Adapter 恢复、登出全部成功 | pass |
| runner 持久存储回归 | 保证跨进程前后使用同一 origin/profile | 固定 hostname、port、profile 参数 | Red 后 Green，自动测试保留 |
| Web `session_start` | 在第一浏览器进程留下有效 session | 登录、刷新后退出且不登出 | pass |
| Web `session_restore` | 从第二浏览器进程恢复，不偷用密码 | restore、token 读取、登出成功 | pass |
| iOS entitlement 静态回归 | 防止 Keychain capability 或 Xcode 接线被误删 | 两个 entitlement 与三种 configuration 均正确 | Red 后 Green，3 tests pass |
| iOS `signup_request` | 验证真机注册、SMTP 与收件起点 | 接口接受，受控工作邮箱实际收到 OTP | pass；原测试邮箱仅有 API 200，未证明送达 |
| iOS `signup_confirm` | 证明真机 App 内注册 OTP 可用 | `signedIn` 后成功登出 | pass |
| iOS `recovery_request` | 证明真机恢复邮件请求与送达 | `recoveryCodeSent` 且收到新 OTP | pass |
| iOS `recovery_confirm` | 证明恢复 OTP 与改密码可用 | 改密码后 `signedIn`，再登出 | pass |
| iOS 新密码 `session` | 证明真机 HTTPS、Keychain 与基本 session 生命周期 | 登录、刷新、Adapter 恢复、登出全部成功 | pass |
| iOS `session_start` | 第一真机进程留下 Keychain session | 登录、刷新后退出且不登出 | pass |
| iOS `session_restore` | 第二真机进程不使用密码恢复 | restore、token 读取、登出成功 | pass |
| 原生 runner 保留 App | 避免每个 mode 后卸载最后一款开发 App 并丢失信任 | 原生命令包含 `--no-uninstall` | Red 后 Green，自动测试保留 |
| push/pull cursor 分离 | 防止上传 ACK 跳过较早的其他设备变化 | push 不推进 pull cursor；batch 落盘后才推进 | Red 后 Green，ADR-0100 与回归测试保留 |
| 同 ID 快照冲突 | 防止将不同内容静默当成幂等重放 | 保留本地事实，batch 与 cursor 回滚 | Red 后 Green，自动测试保留 |
| 无效 cursor 错误分类 | 避免将客户端错误无限重试为 `503` | PostgreSQL `22023` 稳定转为 `400 invalid_cursor` | Red 后 Green，Backend 自动测试保留 |
| Router 直达与返回 | 证明 URL、主导航和草稿保存共用同一页栈 | `/analysis` 直达，导航改 URL，返回前保存草稿 | Red 后 Green，parser 与 Widget 测试保留 |
| 项目创建 HTTP 合同 | 防止 Backend `201 Created` 被 Flutter 当成失败 | adapter 接受 201 并解析可信上下文 | Red 后 Green，HTTP adapter 测试保留 |
| 接触表单失败与恢复 | 防止保存、定位或提交失败后丢失输入 | 显示可恢复状态，重试后不重复事实 | Red 后 Green，Widget 测试保留 |
| 接触更正与作废 | 防止覆盖历史、错算发生期间或让作废事实继续计数 | 完整追加历史，原因必填，作废退出指标 | Red 后 Green，本地、Widget 与 PostgreSQL 测试保留 |
| revision 历史重放 | 防止本机已到较新 revision 时拒绝服务端较早的已知历史 | 逐条核对已有快照，完整 batch 幂等落地并推进 cursor | Red 后 Green，同步回归测试保留 |
| 跨设备接触更正 | 防止不同字段丢失，或同字段静默覆盖 | 不同事实组自动合并；同一事实组保留双方快照并由本人解决 | Red 后 Green，Flutter、Backend 与 PostgreSQL 测试保留 |
| v5／v6／v8 至 v16→v17 migration | 证明旧数据升级后保留内容并采用新约束 | 旧接触、草稿、答案和问卷定义保留；新规则、升级来源和对象关联不猜测回填 | Red 后 Green，Drift migration 测试保留 |
| 问卷三端合同 | 防止 Flutter、Backend 和 PostgreSQL 对题型、状态或显示规则产生不同解释 | 八题型、五状态、显示操作符、隐藏必填题、权限、离线草稿和服务端复验通过 | Red 后 Green，共享 fixture 与三端测试保留 |
| 隐藏答案变更 | 防止前置答案改变时静默丢失旧值 | 取消不修改答案；确认后记录跳过原因；撤销恢复整次变更 | Red 后 Green，ViewModel 与 Widget 测试保留 |
| 问卷管理与发布 | 防止草稿覆盖、静默定义变化、重复版本或两个 current 版本 | revision 冲突、差异、模拟、幂等、不可变与双会话并发检查通过 | Red 后 Green，Flutter、Backend 与 PostgreSQL 测试保留 |
| Drift/PostgreSQL 指标合同 | 防止两套 SQL 的 scope、区间或单位漂移 | 两端读取同一 synthetic CSV 并得到同一业务结果 | pass，共享 fixture 与两端测试保留 |
| `dart analyze` | 发现类型和静态问题 | 0 issue | pass |
| 全部 Flutter tests | 检查已有合同未被破坏 | 全部通过 | pass；数量以当次命令输出为准 |
| Backend tests | 检查 JWT、可信上下文、项目、问卷、上传、拉取和错误分类 | TypeScript 检查与全部测试通过 | pass；数量以当次命令输出为准 |
| PostgreSQL 16 重建与恢复 | 证明 migration、最小权限、区域、私有草稿、修订冲突、问卷、指标和备份可用 | 空库、checksum 重跑、fixture、`pg_dump`、`pg_restore` 全部通过 | pass |
| 六平台 build | 发现平台插件、编译和工程接线问题 | Android、Web、Linux、iOS、macOS 和 Windows 在对应 runner 构建 | 以当前 PR 的九项 CI 为准 |
| production boundary | 防止 test-only fake 进入正式代码 | 边界检查通过 | pass |
| Markdown links | 防止说明书入口和链接失效 | 全部文档链接通过 | pass；数量以当次命令输出为准 |

“当前结果”是特定日期、设备、浏览器和 staging project 的证据，不是永久真理。依赖升级、浏览器版本变化或认证设置变化后，应重新运行相关探针。

## 8. 标准化的安全改动流程

以后修改 Flutter、SQL、认证或统计逻辑，默认按下面的顺序工作。

### 第一步：先写清合同

说明使用者需要什么、输入与输出是什么、哪些事实必须保持不变。产品语义写进 Spec／领域语言；重要架构取舍写 ADR；不要先从 Widget 或数据库列名猜需求。

### 第二步：选择公开测试接缝

找调用者真正依赖的入口，例如 `IdentitySession`、接触日志服务、指标计算接口或 migration runner。测试公开结果，不测试私有 helper 和文件数量。

### 第三步：切一个 vertical slice

Vertical slice（垂直切片）是一次贯穿必要层次、但范围很小的完整行为。例如“用户能请求恢复邮件”，而不是先写完所有 Auth UI、再写完所有 Adapter、最后才一起测试。

这种先穿通一条窄路径的做法也常叫 tracer bullet（曳光弹）：它先证明方向和连接点正确，再逐条扩展能力。

### 第四步：执行 Red-Green

1. 加一个通过公开接缝观察行为的测试；
2. 在旧实现上运行，确认因目标能力缺失而失败；
3. 做最小实现；
4. 重跑同一测试，确认转绿；
5. 再开始下一条行为，不一次想象出几十个测试。

### 第五步：真实边界需要集成证据

本地 fake 可以制造断网和 500，但不能证明真实 SMTP、Keychain 或浏览器存储。高风险外部边界需要隔离 staging、虚构数据和对应平台的真实探针。测试账号与 production 分离，secret 不提交、不打印。

### 第六步：证据式诊断

出现失败时按下面的顺序，而不是立刻猜一个修复：

1. 保存可重复的症状和最小输入；
2. 区分 App、SDK、网络、云服务、数据库和测试执行框架；
3. 列出多个可能解释；
4. 找能区分这些解释的日志或最小实验；
5. 修正最小根因；
6. 给旧错误留下回归测试；
7. 删除临时 debug 输出和测试资料。

本轮若只相信 App 的“断网”分类，就会错误修改网络权限；比较 Supabase Auth 日志、PostgreSQL code、浏览器 user agent 和时间戳，才发现双浏览器请求。

### 第七步：Review／Refactor

目标测试转绿后，单独审查：名称是否表达领域含义、模块是否过浅、注释是否说明原因、错误是否泄密、测试是否耦合实现、重复代码是否值得合并。重构后必须保持同一合同测试全绿。

### 第八步：运行完整质量门禁

目标测试只说明这一个切片成立。提交前还要运行格式、静态分析、全部测试、production boundary、Markdown／snippet／SQL 检查；数据库变化还要执行 migration 与 fixture 对账。

CI 是把这些命令放到干净环境自动重复。CI 通过不能替代人工审查或真机探针，但能防止“只在我的电脑上可以”。

### 第九步：同步文档与决策记录

代码、测试、说明书和必要的 ADR 必须一起变化。说明书写清原因、证据和限制；不要只贴一段代码，也不要把一次环境结果扩张为所有平台结论。

### 第十步：形成可审查的提交

提交只包含这一切片相关文件，保留失败与通过的验证记录，接受 code review。若涉及数据库，使用新增 migration 和 forward-fix；不回写已经执行过的 migration。若涉及高风险发布，还要事先定义回滚或降级路径。

## 9. Definition of Done：什么时候才叫完成

Definition of Done（完成定义）是团队对“完成”的共同门槛，不等于开发者说“我写完了”。本项目一个普通实现切片至少需要：

- 需求与领域语言没有歧义；
- 关键行为通过约定的公开接缝测试；
- 新测试曾在旧行为上正确失败，而不是一开始就无意义地通过；
- 目标测试和完整测试都通过；
- secret、真实 PII、测试 fake 没有进入 production；
- 相关说明书、中文注释和必要 ADR 已同步；
- 已知未验证范围明确写成 pending，而不是 pass；
- 改动经过 diff review，临时 debug 资料已清理；
- CI 与相应真实平台探针达到该切片要求。

对于 Supabase 六平台 Spike，只有某个平台的 build、安全存储、注册／OTP／恢复、登录／刷新／跨进程恢复／登出都取得真实证据，才可把该平台写成 runtime pass。

## 10. 本章可自行验证的命令

只运行 runner 回归测试：

```bash
flutter test --no-pub test/tool/run_supabase_auth_spike_test.dart
```

只运行 Identity 合同测试：

```bash
flutter test --no-pub test/identity/identity_session_test.dart
```

运行静态分析和全部 Flutter tests：

```bash
dart analyze
flutter test --no-pub
```

检查 production 边界与说明书链接：

```bash
dart run tool/check_production_boundary.dart
dart run tool/check_markdown_links.dart
```

真实 Supabase 探针必须使用受 Git 忽略的 staging 配置；完整分阶段命令见 [六平台 Spike](../spikes/supabase-auth-six-platform.md)。

读完这一章，应能解释：为什么测试要先红后绿、回归测试防止什么、mock 与真实探针为什么都需要、build pass 为什么不等于 runtime pass，以及一次需求更新如何沿着合同、测试、代码、文档和 CI 安全落地。
