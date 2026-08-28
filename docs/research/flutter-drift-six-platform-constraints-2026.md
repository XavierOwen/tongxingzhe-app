# Flutter、Drift 六平台约束与 Firebase Authentication 边界

更新日期：2026-07-21

研究范围：Flutter 官方架构、导航与自适应建议；Drift 六平台执行器、Web 持久化、isolate、迁移测试与可读 SQL；Firebase Authentication 的 Flutter 平台支持与 Emulator。

证据边界：本文只使用 Flutter、Drift、Firebase/FlutterFire 的官方文档、官方包页面或官方源码。文中的“事实”“推论”“建议”刻意分开；建议不是上游产品承诺。

## 结论摘要

1. **Flutter UI 与 Drift 本地关系数据库可以维持一套六平台代码。** Flutter 官方 `go_router` 包和 Drift 都列出 Android、iOS、macOS、Windows、Linux、Web；Drift 在五个原生平台使用 `NativeDatabase`，Web 使用 `WasmDatabase`。平台差异应收敛在路由、数据库打开器和 Capability/Policy 等少量接口，而不应散落在页面里。
2. **Firebase Authentication 不能被写成“六个原生平台同等可用于生产”。** 当前 `firebase_auth` 官方包列出 Android、iOS、macOS、Web、Windows，不含 Linux；Firebase Flutter 官方页面又把 macOS/其他 Apple 平台和 Windows 标为 beta，并明确警告 Windows Firebase 只用于本地开发、不是生产用途。因此，“六平台都能编译”与“六平台都能用 Firebase Auth 正式登录”是两个不同命题。
3. **Web 离线数据库不是单一能力。** Drift 会在 `opfsShared`、`opfsLocks`、`sharedIndexedDb`、`unsafeIndexedDb`、`inMemory` 中择一。后两者意味着多标签页不安全或数据不持久，App 必须检测并把实际能力告诉用户；不能只因为初始化成功就宣称“离线数据可靠”。
4. **Web 的 Drift 最优存储与 OAuth 弹窗存在真实张力。** Drift 的 OPFS 路径可能需要 COOP/COEP 响应头，Drift 官方同时提醒这些响应头可能与 Google Auth 一类弹窗冲突。因此不能在设计阶段同时默认“强制 OPFS 最优模式”和“Firebase Web 弹窗登录一定正常”，必须用部署级集成测试决定策略。
5. **当前项目已经选对了底层方向，但缺少工程护栏。** 现有 `LocalDatabase.defaults()` 已通过 `driftDatabase(...)` 使用跨平台打开器并提供 Web worker/WASM；然而目前没有 schema 快照、迁移测试、可读 `.drift` 查询层、Firebase Auth 适配层或 URL 路由。后续应扩展现有正式代码，不另造一套教学 Demo。

## 一、六平台能力矩阵

这里的六个平台指 Android、iOS、macOS、Windows、Linux、Web。状态以 2026-07-21 可见的官方资料为准。

| 能力 | Android | iOS | macOS | Windows | Linux | Web |
| --- | --- | --- | --- | --- | --- | --- |
| Flutter + `go_router` | 支持 | 支持 | 支持 | 支持 | 支持 | 支持 |
| Drift 本地 SQLite | `NativeDatabase` | `NativeDatabase` | `NativeDatabase` | `NativeDatabase` | `NativeDatabase` | `WasmDatabase` |
| `firebase_auth` 包声明 | 支持 | 支持 | 支持 | 支持 | **未列出** | 支持 |
| Firebase 官方产品姿态 | 正式支持 | 正式支持 | **beta** | **beta；仅本地开发，非生产** | **无官方 Flutter 插件** | 正式支持 |

证据：

- Flutter 团队发布的 [`go_router` 包页面](https://pub.dev/packages/go_router)列出六个平台，并说明其提供 URL 路由、deep link、redirect 与多 Navigator 的 `ShellRoute`。
- Drift 的[平台总览](https://drift.simonbinder.eu/platforms/)列明五个原生平台使用 `NativeDatabase`，Web 使用 `WasmDatabase`；[`drift_flutter` 官方包](https://pub.dev/packages/drift_flutter)也列出六个平台。
- [`firebase_auth` 官方包页面](https://pub.dev/packages/firebase_auth)列出 Android、iOS、macOS、Web、Windows，未列出 Linux。
- Firebase 的[Flutter 可用插件表](https://firebase.google.com/docs/flutter/setup#available-plugins)将 Authentication 在“Other Apple”和 Windows 标为 beta，并明确写明 Windows Firebase 不用于生产，只用于本地开发工作流。

### 对本项目的推论

- **可以承诺六平台共用领域模型、页面、Drift schema 与绝大多数测试。** 这不等于可以承诺六个原生客户端都用同一个 Firebase SDK 正式登录。
- 若“六个平台”包含六个原生/浏览器发行物，则正式身份能力至少需要一个明确的 `AuthCapability`：Android、iOS、Web 为可用；macOS 为 beta 风险；Windows 生产关闭；Linux 生产关闭。
- Windows/Linux 用户仍可使用正式 Web 版；但这只是可行的发行策略，不等于满足“Windows/Linux 原生 App 正式登录”。如果后者是硬需求，需要另立认证方案研究，不能假装 Firebase Flutter 已覆盖。
- macOS 虽有插件，但 beta 状态应成为发布风险，而不是被表格中的“支持”二字抹去。

### 建议

将“六平台”拆成两个可验证的产品合同：

1. **六平台代码与离线数据库合同**：全部平台编译；核心页面、领域规则、Drift 查询和 fake-auth 测试一致。
2. **生产发行合同**：第一阶段明确哪些平台开放真实登录；Windows/Linux 原生端在生产认证能力不足时不伪装可用，桌面用户先走 Web。以后上游支持变化时，只替换认证适配器与 Capability/Policy，不改业务模块。

## 二、Flutter 官方架构：哪些是事实，怎样用于本项目

### 2.1 官方事实

Flutter 的[应用架构指南](https://docs.flutter.dev/app-architecture/guide)把 separation of concerns 作为核心原则，并建议把应用分为：

- UI 层：`View` 与 `ViewModel`；
- Data 层：`Repository` 与 `Service`；
- 可选 Domain 层：在逻辑需要合并多个 Repository、非常复杂，或被多个 ViewModel 复用时加入 use-case/interactor。

该指南同时明确：

- View 负责呈现和把用户事件交给 ViewModel，不应容纳业务逻辑；布局、动画、简单显示判断和简单路由可以留在 View。
- 一个 View 是一组组成某个功能的 widgets，不是“每个 widget 一个 ViewModel”；官方建议 View 与 ViewModel 一对一。
- Repository 是某类模型数据的 source of truth，承担缓存、错误、重试、刷新等数据逻辑。
- Repository 不应互相依赖；需要组合多个 Repository 的逻辑应放在 ViewModel 或按需加入的 Domain use-case。
- Service 包裹 REST、平台 API、本地文件等外部数据源，本身不持有业务状态。
- 官方称这些是可适配的 guidelines，不是不可改变的铁律。

### 2.2 对本项目的推论

研究时的 `lib/app/app_controller.dart` 与 `lib/screens/home_shell.dart` 分别承担了过多全局数据/业务职责和页面职责；这些 legacy 文件后来已删除，原始内容由 Git 历史保留。官方指南并不要求机械地为每个方法新增一层，而是要求边界清楚、接口可测。因此适合本项目的目标不是“类越多越现代”，而是：

- 每个用户功能有自己的 View + ViewModel；
- Drift、HTTP、位置、认证等外部能力进入 Service/adapter；
- Repository 维护对应数据的 source of truth；
- 只有“提交一次接触并同时写入草稿、正式事实、关联、outbox”等跨 Repository 事务，才使用明确的 use-case；
- 不再由一个全局 Controller 直接知道所有表、统计、认证、导航和设置细节。

### 2.3 建议的最小依赖方向

```text
View
  -> ViewModel
      -> 单一 Repository
      -> 必要时调用 UseCase（组合多个 Repository）
          -> Repository interface
              -> Drift / HTTP / Firebase adapter
```

这不是要求每个箭头都对应一个目录。它定义的是依赖方向和测试替换点：页面不直接调用 SQL、Firebase 或平台插件；领域规则也不 import Flutter widget。

## 三、导航与自适应：URL、Shell 与 Capability/Policy

### 3.1 官方事实

Flutter 的[导航与路由指南](https://docs.flutter.dev/ui/navigation)不建议大多数 App 使用旧式 named routes。对于 Web URL、deep link 或多个 Navigator 等较复杂需求，官方建议使用 `go_router` 一类 Router 包；Router 还能与浏览器 History API 协作，使前进/后退按钮与 URL 一致。

Flutter 团队发布的 [`go_router`](https://pub.dev/packages/go_router)支持：

- URL path/query 参数；
- 子路由；
- 根据认证等应用状态 redirect；
- `ShellRoute` 下的多个 Navigator，可维持底部导航或侧栏；
- Android、iOS、macOS、Windows、Linux、Web。

Flutter 的[自适应与响应式指南](https://docs.flutter.dev/ui/adaptive-responsive)区分：responsive 是布局装进现有空间，adaptive 是在现有空间中仍然好用。其[Capabilities & policies 指南](https://docs.flutter.dev/ui/adaptive-responsive/capabilities)进一步区分：

- Capability：代码/设备**能做什么**，例如 API 是否存在、OS 限制、硬件能力；
- Policy：产品**应该怎么做**，例如商店规则、设计偏好、服务端 feature flag。

官方不建议在 UI 中到处用 `Platform.isAndroid`、`kIsWeb` 推断布局或能力；应把真正的分支原因命名成方法，并通过 mock Capability/Policy 测试。

### 3.2 对本项目的推论

- 已确认的四个主入口“今日 / 接触 / 对象 / 分析”适合放在一个持久 shell 中；宽屏显示 NavigationRail、窄屏显示 NavigationBar。研究时的 `lib/screens/home_shell.dart` 已按宽度切换 rail/bar；该原则已进入正式 shell，旧文件由 Git 历史保留。
- 选择哪个页面不应继续只存一个内存 index。Web 刷新、分享说明书章节、打开某条接触记录、浏览器前进/后退都需要稳定 URL。
- 认证、当前 workspace/project 和权限变化可通过 router redirect 控制；但授权判断仍应来自应用 SQL/后端，不把 Firebase 登录状态误当成业务权限。
- `supportsReliableLocalPersistence`、`supportsProductionAuth`、`shouldUseNavigationRail`、`shouldWarnAboutMultipleTabs` 比 `isWeb`、`isWindows` 更能表达真实原因，也更容易测试。

### 3.3 建议

- 使用 `MaterialApp.router` + `go_router`；主导航使用 shell route，详情、编辑、说明书章节有稳定路径。
- 路由只负责导航与 redirect，不承载接触计数、匿名阈值等业务规则。
- 建立小而可 mock 的 Capability/Policy 接口；Web Drift 实际存储结果、Firebase 平台状态、窗口宽度是其输入，不在各页面重复判断平台名称。

## 四、Drift 六平台执行器与当前项目

### 4.1 官方事实

Drift 的[平台总览](https://drift.simonbinder.eu/platforms/)说明，其核心 API 是跨平台纯 Dart，平台相关数据库实现通过 `QueryExecutor` 接入：

- Android、iOS、macOS、Windows、Linux：`NativeDatabase`；
- Web：`WasmDatabase`；
- 旧 `WebDatabase` 已弃用，推荐 `WasmDatabase`；
- 共享代码只需改变“如何打开数据库”，表、查询与 Repository 的使用方式可以相同。

[`drift_flutter`](https://pub.dev/packages/drift_flutter)提供统一的 `driftDatabase(...)` 打开器：原生平台把数据库放在 application documents 目录，Web 走 Drift Web 实现。

### 4.2 当前项目事实

- [`pubspec.yaml`](../../pubspec.yaml)当前声明 `drift: ^2.34.0`、`drift_flutter: ^0.3.0`、`drift_dev: ^2.34.0`；lockfile 当前解析为 2.34.0 / 0.3.0 / 2.34.0。
- [`LocalDatabase.defaults()`](../../lib/data/local_database.dart)已经使用 `driftDatabase(name: ..., web: DriftWebOptions(...))`，并保留可注入 executor 的构造函数。这是正确的跨平台/测试 seam。
- [`web/`](../../web/)已有 `sqlite3.wasm` 与 `drift_worker.js`；`drift_worker.js.deps`显示 worker 是使用当前 Drift 2.34.0 依赖编译的。仅凭该文件尚不能证明 WASM 二进制一定与 lockfile 匹配，发布流程仍应自动校验/重新生成资产。

### 4.3 对本项目的推论与建议

- 不需要为了六平台另写六套数据库。`LocalDatabase(QueryExecutor)` 应继续作为底层注入点；平台打开逻辑收敛在一个 database factory。
- Repository/DAO 不应知道 `kIsWeb`；它只接收同一个 generated database API。
- Web worker、WASM 和响应头属于部署资产，必须有构建/烟雾测试，不能只靠开发机上“能运行”。
- 当前依赖版本无需因为本研究立即升级；升级应单独验证迁移、worker/WASM 配对和六平台构建。

## 五、原生平台后台 isolate：性能边界不是后台同步承诺

### 5.1 官方事实

Drift 的[原生平台说明](https://drift.simonbinder.eu/platforms/vm/)指出，SQLite C API 同步执行，若直接在 UI isolate 运行 I/O 或复杂 SQL，可能掉帧；`NativeDatabase.createInBackground` 会把数据库托管到后台 isolate，而数据库的调用方式不变。

Drift 的[isolate 指南](https://drift.simonbinder.eu/isolates/)说明：

- transaction、批量写入、自动更新查询、custom/verified SQL 都能在 Drift 后台 isolate 上使用；
- isolate 通信有开销，降低 UI 卡顿不等于总吞吐一定更快；
- 多 client isolate 可以连接同一 Drift server isolate；
- 由原生平台在 App 关闭时拉起的后台 `FlutterEngine` 是更复杂的独立情形，官方明确提醒其通信与生命周期仍有固有限制。

当前项目使用的 `drift_flutter 0.3.0` [官方源码](https://github.com/simolus3/drift/blob/3e2ae3cbbe7563f3db36821fde2a816647c447d0/drift_flutter/lib/src/native.dart)中，原生 `driftDatabase(...)` 默认建立 background connection；`shareAcrossIsolates` 则是另一个默认关闭的选项，用于同一 Flutter engine 内需要跨 isolate 共享时。

### 5.2 对本项目的推论

- 当前 `driftDatabase(...)` 已经避免把普通原生 SQLite 工作直接压在 UI isolate，不能再把“增加一个 isolate”当作首要现代化任务。
- **数据库后台 isolate 不等于 App 被系统挂起/杀死后仍会自动同步。** 定时同步、推送唤醒、后台引擎各平台能力不同，应由独立 SyncScheduler capability 管理。
- 第一阶段可以保证“前台打开 App 时可靠 drain outbox”；是否增加 OS 后台同步要逐平台研究和测试，不能由 Drift isolate 文档推导出来。
- 在没有真实性能数据前，不建议启用多 reader pool；单一后台数据库 isolate 足以覆盖大多数应用，复杂化 WAL/并发只会提高迁移和调试成本。

## 六、Drift Web：OPFS、IndexedDB、多标签页与内存降级

### 6.1 官方事实

Drift 的[Web 平台指南](https://drift.simonbinder.eu/platforms/web/)要求：

- 浏览器加载匹配当前包版本的 `sqlite3.wasm` 和 Drift worker；WASM 必须以 `application/wasm` MIME type 提供；
- `WasmDatabase.open` 会探测浏览器能力并返回 `chosenImplementation` 与 `missingFeatures`；
- 当前存储策略按偏好顺序为：

| 策略 | 官方含义 | 需要 App 关注的约束 |
| --- | --- | --- |
| `opfsShared` | OPFS + shared worker | 当前官方文档称只有 Firefox 实现所需 worker 组合 |
| `opfsLocks` | OPFS，不依赖 shared worker | 需要 COOP/COEP 响应头 |
| `sharedIndexedDb` | IndexedDB 分块存储 + shared worker | 可由 shared worker 协调多标签页 |
| `unsafeIndexedDb` | IndexedDB，但没有跨标签页同步 | **同一数据库被多个标签页访问不安全** |
| `inMemory` | 无持久化 API 时退回内存数据库 | 关闭/刷新后不能承诺数据保留 |

官方还指出：

- Firefox 隐私窗口可能降级到 IndexedDB 或内存；
- Android Chrome 缺少 shared worker 时，在没有所需 headers 的情况下可能发生多标签页 data race 与持久化问题；
- 如果最终选择 `unsafeIndexedDb` 或 `inMemory`，应用应考虑警告用户升级浏览器或换用原生 App；
- Web 不支持 WAL 数据库导入；不能把原生 WAL 行为直接假定到 Web。

### 6.2 COOP/COEP 与 Firebase Web 登录的交叉约束

Drift 的同一份[Web 指南](https://drift.simonbinder.eu/platforms/web/#additional-headers)说明，OPFS 的某些最优路径需要：

- `Cross-Origin-Opener-Policy: same-origin`；
- `Cross-Origin-Embedder-Policy: require-corp` 或 `credentialless`。

它同时明确提醒这些 headers 与某些打开 popup 的包不兼容，并以 Google Auth 为例；如果 headers 破坏 App，应关闭它们并接受较慢的 fallback。

**对本项目的推论：** Firebase Web 的 federated sign-in 可能使用 popup/redirect，所以 Drift 的最优 OPFS 配置与登录方式必须作为一个整体测试。不能分别验证数据库和认证后就假定组合一定成立。

### 6.3 建议的 Web 产品策略

1. 在 database factory 中接收/记录 `WasmDatabaseResult`，转换成领域无关的 `LocalPersistenceCapability`。
2. `opfsShared` / `opfsLocks` / `sharedIndexedDb` 可正常进入离线工作流；`unsafeIndexedDb` 显示“不要多开标签页”的明确警告；`inMemory` 不允许把未同步草稿标记为安全保留。
3. 为以下组合做真实浏览器测试，而不只跑 widget test：Chrome desktop、Safari、Firefox、Android Chrome；普通与隐私窗口；单标签与双标签；在线、离线、刷新、崩溃恢复。
4. 分别测试 COOP/COEP 开关下的 Firebase email/password 与 federated popup/redirect 登录，再决定生产 headers 与登录方式。
5. 同一时间只把一个 tab 作为 outbox drainer；即使 query streams 可跨标签同步，也不能让两个 tab 无协调地重复推送同一操作。

## 七、Schema 快照、迁移测试与 v5 边界

### 7.1 官方事实

Drift 的[迁移指南](https://drift.simonbinder.eu/migrations/)推荐使用 `dart run drift_dev make-migrations` 生成增量迁移辅助代码与测试；官方明确警告手写迁移容易出错并可能丢失数据。

Drift 的[schema export 指南](https://drift.simonbinder.eu/migrations/exports/)建议：

- 初始 schema 保存一次；
- 每次增加 `schemaVersion` 都保存新的 schema 快照；
- 工具用历史快照生成 step-by-step migration 与测试代码。

Drift 的[迁移测试指南](https://drift.simonbinder.eu/migrations/tests/)说明，生成的 `SchemaVerifier` 可以：

- 从指定旧版本创建数据库；
- 执行真实升级逻辑；
- 语义比较升级后的 SQLite schema 与目标 schema；
- 通过旧版 data classes/companions 在升级前插入数据，再验证资料完整性。

### 7.2 当前项目事实与推论

当前数据库为 schema v5，并在 [`local_database.dart`](../../lib/data/local_database.dart)手写 `onUpgrade`；仓库尚未保存 Drift schema 快照与迁移测试。

这意味着“直接开始 v6 重构”存在两种不同风险：

- schema 结构是否正确；
- v5 真实数据能否无损映射到新的项目、对象、接触、修订与 outbox 模型。

前者可由 Drift 生成工具自动验证；后者必须用项目自己的 fixture 与不变量测试，工具不会替我们决定旧字段的业务含义。

### 7.3 建议

1. 在任何 v6 schema 修改前，先从当前代码/现有 SQLite 文件导出并提交 `drift_schema_v5.json`，把它当作迁移起点。
2. 配置 `make-migrations`；每个 schema version 都提交快照、step 文件和生成的测试骨架。
3. 至少测试：空 v5、典型 v5、有多个联系人、边界 interest 值、已 void/历史兼容记录、PII 字段、升级中断/重试。
4. schema 验证和数据语义验证分开命名；“表创建成功”不等于“兴趣、阶段、对象和隐私归属迁对了”。
5. 旧数据是否真实且不可丢失仍是产品事实问题。在确认前保留两条方案：无真实数据时导出备份后新建；有真实数据时提供可预览、可回滚的迁移流程。

## 八、可读 `.drift` SQL：学习价值与代码边界

### 8.1 官方事实

Drift 的[Verified SQL 指南](https://drift.simonbinder.eu/sql_api/)说明，`.drift` 文件中的 SQL 会在 build 时由 analyzer 检查，并生成 type-safe Dart 方法，同时保留 reactive query 等 Drift 能力。

Drift 的[`.drift` 文件指南](https://drift.simonbinder.eu/sql_api/drift_files/)说明：

- 可以用 SQL 定义 table/view/index/trigger 与命名的 `SELECT`、`INSERT`、`UPDATE`、`DELETE`；
- `.drift` 可以 import 另一个 `.drift`，也可以 import 定义了 Dart tables 的 Dart 文件；
- 因此项目可以保留 Dart table 定义，同时把 JOIN、统计、报表查询写成真正可读、可检查的 SQL；
- 生成方法仍可参与 transaction 与自动更新查询。

### 8.2 对本项目的建议

- **不要为了“学 SQL”把所有简单 CRUD 改成大段 raw SQL。** 表的稳定约束和简单写入可继续用 Drift Dart API；真正能展示 SQL 思维的 JOIN、聚合、窗口/分桶、匿名阈值前置统计放进按领域拆分的 `.drift` 文件。
- 优先建立例如 contact journal、follow-up、personal analytics、management analytics 等查询模块，而不是一个 `queries.drift` 大文件。
- 每个重要 SQL 同时配：中文注释、输入/输出含义、统计口径、空值与 answer-state 处理、fixture 测试、说明书中的可复制示例。
- 区分 SQLite SQL 与未来服务端 PostgreSQL/仓库 SQL。概念可以相同，方言、时间函数、并发与权限模型不能假定相同。
- SQL 生成的 Dart 方法属于数据层；ViewModel 消费领域结果，不直接拼 SQL 字符串。

## 九、Firebase Authentication：支持矩阵、Emulator 与测试边界

### 9.1 官方事实

Firebase 的[Flutter Authentication 入门](https://firebase.google.com/docs/auth/flutter/start)提供 `firebase_auth` 插件和 `FirebaseAuth.instance.useAuthEmulator(host, 9099)`；登录状态可通过 `authStateChanges()` 等 stream 观察。

Firebase 的[Flutter 平台设置页](https://firebase.google.com/docs/flutter/setup#available-plugins)与 [`firebase_auth` 包页面](https://pub.dev/packages/firebase_auth)共同给出本文第一节的平台边界：

- Android、iOS、Web：官方 Flutter 主路径；
- macOS/Other Apple：beta；
- Windows：包存在且为 beta，但官方明确禁止将 Windows Firebase 视为生产用途；
- Linux：`firebase_auth` 未列为支持平台。

Firebase 的[Auth Emulator 指南](https://firebase.google.com/docs/emulator-suite/connect_auth)说明：

- 推荐尽可能使用 `demo-` project，避免误连真实资源、产生数据修改或计费；
- Emulator 可通过 UI 或 REST 非交互方式创建/清理测试用户；
- Emulator 发出的 ID token 未签名，只应被其他 emulator 或已明确连接 emulator 的 Admin SDK 接受，生产服务会拒绝；
- Emulator 不发送真实 email/SMS，而是在终端或 REST 接口提供测试链接/验证码；
- Emulator 不复刻生产 rate limiting、anti-abuse 与全部第三方身份安全流程。

官方通用 Emulator 页面明确展示 Android、Apple/Swift、Web 的连接方式；Flutter 入门页提供统一的 Dart `useAuthEmulator` 调用。它没有给出一张“六个平台的 Emulator 生产等价保证表”。因此 Windows/macOS 的实际 FlutterFire emulator 组合应做本地验证，Linux 则首先缺少官方插件。

### 9.2 对本项目的推论

- Firebase Authentication 只应证明外部身份 `subject/uid`，不应承载 workspace membership、项目角色、Capability 权限或审计；这些仍进入应用 SQL。
- ViewModel 不应直接依赖 `FirebaseAuth.instance`。一个小型 `IdentityProvider`/`AuthGateway` 接口可以分别接 Firebase、fake 和未来替代实现，并把供应商 uid 映射到内部 `app_user_id`。
- fake auth 与 Emulator 不是二选一：fake 适合快速、确定、六平台统一的 unit/widget test；Emulator 适合验证 Firebase 初始化、token、登录流与后端验签的 integration test。
- Emulator 通过不代表生产安全功能通过。至少还需要真实 staging 环境验证 token 签名、过期/刷新、禁用用户、provider redirect、rate-limit/anti-abuse 相关失败路径。

### 9.3 建议的测试分层

| 层级 | 身份实现 | 验证什么 | 不验证什么 |
| --- | --- | --- | --- |
| Unit / ViewModel | in-memory fake | 登录/登出状态转换、路由 redirect、错误 UI、权限输入 | Firebase SDK、token、网络 |
| Widget | fake + fake Capability/Policy | 六平台共同 UI 与平台降级呈现 | 真实 provider |
| Integration | Firebase Auth Emulator（优先 demo project） | 初始化、email/password、测试用户、token 送后端、登出/刷新 | 生产签名、真实 email/SMS、anti-abuse |
| Staging smoke | 独立真实 Firebase project | 签名 token、redirect、provider、过期/撤销与实际平台配置 | 大规模负载 |

[Firebase Auth Emulator 官方示例](https://firebase.google.com/docs/emulator-suite/connect_auth#instrument_your_app_to_talk_to_the_emulator)中，Android Emulator 连接宿主机使用 `10.0.2.2`，而不是机械复用 desktop 的 `localhost`；host 选择也应通过平台 capability/config 注入。

## 十、建议固定为实现前的测试 seams

以下 seams 能同时服务现代化、灵活改需求、Flutter/SQL 学习和六平台测试：

1. **`QueryExecutor` / database factory seam**：生产选择 native/Web executor，测试使用内存 executor；所有 schema 与 SQL 测试不依赖页面。
2. **Repository seam**：按领域提供 source of truth；离线缓存、outbox、重试留在 Repository/同步模块，不进入 Widget。
3. **Use-case seam**：只用于跨 Repository 或高复杂度规则，如“提交接触”事务；用领域 fixture 测不变量。
4. **Identity seam**：Firebase / fake / emulator 配置可替换；业务只看到稳定内部用户标识和 session state。
5. **Capability/Policy seam**：把 Web 实际存储、生产认证支持、位置、通知、窗口布局等转换为“能做什么/应该怎么做”。
6. **Router seam**：认证/上下文 redirect 与 URL/deep link 可测试；页面不自行改变全局 index。
7. **Metric query seam**：重要统计保留在可读 `.drift` SQL 与服务端 SQL，固定输入、数学口径和期望输出。

对应的最低测试集合：

- 每个 ViewModel 的状态与 command unit tests；
- Repository/DAO 的内存 SQLite integration tests；
- v5 → 新 schema 的结构与数据完整性 migration tests；
- 每个关键统计 SQL 的 fixture/golden-number tests；
- fake auth 的六平台 widget tests；
- Firebase Emulator + 后端的 integration tests；
- Web 的真实浏览器存储模式、双标签、离线、刷新、COOP/COEP + 登录组合测试；
- Android/iOS/macOS/Windows/Linux/Web 的构建 smoke test，其中 Firebase 生产能力按矩阵 gate。

## 十一、研究没有证明的事项

为了避免把推论写成事实，本研究**没有**证明：

- Windows 或 Linux 原生 App 能以 Firebase Auth 作为正式生产认证；现有官方资料反而否定或缺少这一承诺。
- Web 在所有浏览器/隐私模式都能持久保存 Drift 数据。
- 打开 COOP/COEP 后 Firebase 的所有 provider popup/redirect 都可用。
- Drift 的后台 isolate 能让被系统杀死的 App 持续同步。
- schema 验证通过就代表旧 v5 数据业务语义迁移正确。
- 六个平台上的位置、通知、后台任务、加密和生物识别能力相同；这些需要各自的 Capability 研究。

这些不是“以后再说”的小问题，而是应被接口、测试和发布策略显式承认的边界。

## 官方来源索引

### Flutter

- [Guide to app architecture](https://docs.flutter.dev/app-architecture/guide)
- [Navigation and routing](https://docs.flutter.dev/ui/navigation)
- [`go_router` package](https://pub.dev/packages/go_router)
- [Adaptive and responsive design](https://docs.flutter.dev/ui/adaptive-responsive)
- [Capabilities & policies](https://docs.flutter.dev/ui/adaptive-responsive/capabilities)

### Drift

- [Supported platforms](https://drift.simonbinder.eu/platforms/)
- [Native Drift and background isolates](https://drift.simonbinder.eu/platforms/vm/)
- [Isolates](https://drift.simonbinder.eu/isolates/)
- [Web platform guide](https://drift.simonbinder.eu/platforms/web/)
- [Migrations](https://drift.simonbinder.eu/migrations/)
- [Exporting schemas](https://drift.simonbinder.eu/migrations/exports/)
- [Testing migrations](https://drift.simonbinder.eu/migrations/tests/)
- [Verified SQL](https://drift.simonbinder.eu/sql_api/)
- [Drift files](https://drift.simonbinder.eu/sql_api/drift_files/)
- [`drift_flutter` package](https://pub.dev/packages/drift_flutter)

### Firebase / FlutterFire

- [Get started with Firebase in Flutter / available plugins](https://firebase.google.com/docs/flutter/setup#available-plugins)
- [Get started with Firebase Authentication on Flutter](https://firebase.google.com/docs/auth/flutter/start)
- [`firebase_auth` package](https://pub.dev/packages/firebase_auth)
- [Connect to the Authentication Emulator](https://firebase.google.com/docs/emulator-suite/connect_auth)
