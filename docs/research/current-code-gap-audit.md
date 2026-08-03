# 当前 Flutter／Drift 代码与目标模型差距审计

> **状态说明（2026-07-31）：**本文对 legacy v5 代码的事实审计仍有效，但其渐进迁移建议已被“无不可丢失真实 v5 数据”的确认更新；认证与首阶段数据库分别以 ADR-0096、ADR-0097 及 [正式 Spec](../PRODUCT_SPEC.md) 为准。本文不再单独充当实施计划。

审计日期：2026-07-21

审计范围：当前工作树中的手写 Flutter／Dart 代码、Drift schema 与迁移、现有测试；以 `CONTEXT.md` 和 ADR 0001–0095 为目标模型。

审计性质：只读分析，不代表已经实施目标架构。

## 1. 结论先行

### 事实

- 当前 App 是可以运行的单进程 Flutter Demo：界面直接调用一个 `AppController`，`AppController` 同时管理本地数据库、演示认证、权限、设置、接触 CRUD、统计和演示数据。入口只允许注入一个完整 Controller（`lib/main.dart:13-30`），Controller 默认自行创建 `LocalDatabase`（`lib/app/app_controller.dart:12-26`）。
- 当前 Drift schemaVersion 为 `5`，只有用户、旧接触记录、记录中的联系方式、键值设置和安全事件五张表（`lib/data/local_database.dart:6-125`）。目标模型中的空间、组织、项目、成员关系、能力、问卷版本、草稿、推广对象、项目关系、修订、作废、Outbox 和指标版本均没有对应表。
- `home_shell.dart` 把主导航、快速记录、列表、分析、管理、设置、图表与大量表单控件放在同一个约 2,840 行文件中；`AppController` 约 1,048 行。文件长度不是单独的问题，真正的问题是不同业务变化共享同一接口和同一可变状态。
- `dart analyze` 与 `flutter test --no-pub` 在本次审计中均通过；测试套件只有一个 Widget 测试，覆盖登录页、语言切换、演示登录和部分图表渲染（`test/widget_test.dart:9-58`）。

### 推论

- 这套代码可以作为验证 Flutter、Drift、本地持久化、响应式布局和双语界面的原型，但不是对 ADR 0001–0095 的局部欠缺实现；它与目标模型在数据所有权、隐私、版本历史和统计单位上存在结构性冲突。
- 直接把新字段继续加进 `DbConversationRecords`，会把“互动场次、推广对象、项目关系、问卷回答、个人反思和健康数据”继续压在同一行中，使权限、删除、同步和统计无法分别成立。
- 直接把旧字段批量解释成新模型也不安全。许多必需事实从未被记录，无法由 SQL 推断；伪造默认值会让迁移看似完整，却制造错误业务事实。

### 建议

- 不做一次性推倒重写，也不在旧表上继续堆兼容列。采用 **expand–contract（先扩展、后收缩）**：先冻结并测试 schema v5，在旁边创建新模型；新功能按可交付垂直切片写入新表；旧数据以明确的 legacy 来源只读呈现或经人工确认迁移；最后才停止旧读路径并删除旧表。
- 先建立几个真正有价值的深模块和测试接缝，再拆 UI 文件。首要接缝不是“每张表一个 Repository”，而是身份、当前项目上下文、接触日志、问卷、对象跟进、同步和指标计算这些完整行为。
- 第一条生产垂直切片应是：`假认证／内部用户 → 个人空间与项目 → 私有多草稿自动保存 → 匿名核心接触正式提交 → sync_outbox`。它同时验证 Flutter、SQL、离线与目标领域边界，又暂不引入最敏感的推广对象资料。

## 2. 审计口径：事实、推论与建议

本文使用以下标签：

- **事实**：可以从当前文件、执行结果或 ADR 直接观察。
- **推论**：由多个事实共同支持，但仍需在实现或真实数据上验证。
- **建议**：拟议的迁移与模块设计，不是已经确认的实现状态。

目标模型的关键基线包括：

- 接触记录默认匿名并独立于推广对象（`docs/adr/0001-contact-records-independent-of-promotion-targets.md:1-3`）。
- 核心事实与项目问卷分开，问卷和接触记录归属于明确项目（`docs/adr/0005-stable-core-with-versioned-configurable-questionnaires.md:1-3`；`docs/adr/0006-campaign-owns-questionnaire-and-contact-records.md:1-3`）。
- 用户身份与成员权限分离，授权基于能力而非全局数字等级（`docs/adr/0007-separate-user-identity-from-membership-roles.md:1-3`；`docs/adr/0010-capability-based-membership-permissions.md:1-3`）。
- 已提交接触采用追加修订和作废，不直接覆盖或物理删除（`docs/adr/0020-submitted-contact-records-use-append-only-revisions.md:1-3`；`docs/adr/0021-submitted-contacts-are-voided-not-silently-deleted.md:1-3`）。
- 本地 SQLite 先保存，`sync_outbox` 经 Backend API 同步，冲突不静默使用 Last Write Wins（`docs/adr/0022-offline-first-contact-recording-with-an-outbox.md:1-3`；`docs/adr/0024-sync-conflicts-never-use-silent-last-write-wins.md:1-3`）。
- 生产认证采用 Firebase Authentication，但业务授权和审计仍在应用 SQL 中（`docs/adr/0025-use-firebase-authentication-for-production-identity.md:1-5`）。
- 当前上下文和主导航分别为“空间 → 项目”以及“今日、接触、对象、分析”（`docs/adr/0078-a-visible-project-context-scopes-default-work.md:1-3`；`docs/adr/0089-primary-navigation-centers-today-contacts-targets-and-analysis.md:1-9`）。

## 3. 当前模块、接口与依赖方向

### 3.1 当前依赖图

```text
main.dart
├── 创建／持有 AppController
├── AuthScreen ───────────────┐
└── HomeShell ────────────────┼──> AppController
    ├── ConversationRecord ───┘      ├── LocalDatabase / Drift
    ├── LocationService              ├── AppUser / ConversationRecord
    ├── HeartRateService             ├── MD5 / Random / DateTime.now
    └── fl_chart                      └── ChangeNotifier / ThemeMode
```

依赖总体从 UI 指向 Controller，再指向 Drift；但 Controller 同时依赖 Flutter 表示层类型，因此“业务／数据层”并没有真正独立于 UI。

### 3.2 文件职责与当前接口

| 文件／模块 | 当前事实 | 接口评价 |
|---|---|---|
| `lib/main.dart` | 负责数据库间接创建、Controller 生命周期、主题、语言、登录／首页分流（`lib/main.dart:22-74`） | `TongxingzheApp(controller:)` 是有用的测试注入点，但组合根仍只认识一个万能 Controller。 |
| `lib/app/app_controller.dart` | 公共可变字段包含语言、主题、城市、区域、团队、记录者、管理员模式和当前用户（`lib/app/app_controller.dart:30-43`）；公共方法再覆盖认证、设置、记录与统计（`lib/app/app_controller.dart:65-503`） | 一个调用者必须理解几乎整个 App 才能正确使用；接口过宽，变化局部性低。 |
| `lib/data/local_database.dart` | 同一文件定义所有 Drift 表和从 v1 到 v5 的升级逻辑（`lib/data/local_database.dart:6-203`） | schema 集中本身可读，但没有按行为组织的数据访问模块，也没有迁移测试。 |
| `lib/models/app_user.dart` | 用户模型同时含身份资料、密码摘要、全局角色等级、城市权限和团队（`lib/models/app_user.dart:1-46`） | 模型固化了已被 ADR 0007/0010 否决的权限结构。 |
| `lib/models/conversation_record.dart` | 一个对象同时承载场次、人物资料、联系方式、人口属性、关系阶段、兴趣、心率、定位、备注与校正（`lib/models/conversation_record.dart:35-96`） | 数据对象就是旧宽表的镜像，无法为不同隐私边界提供小而稳定的接口。 |
| `lib/screens/auth_screen.dart` | 表单直接调用 Controller 的本地登录、注册和密码重置；页面还公开五个演示账号快捷入口（`lib/screens/auth_screen.dart:233-318`、`338-383`） | 表示层与演示认证机制绑定，无法用同一 UI 安全切换 Firebase／假认证。 |
| `lib/screens/home_shell.dart` | 一个文件包含五个导航页面、表单、管理校正、统计计算和图表渲染；首页直接实例化定位和心率实现（`lib/screens/home_shell.dart:13-176`） | UI 既决定业务规则又执行统计，测试只能跨很大的 Widget 表面。 |
| `lib/services/location_service.dart` | 把权限与 Geolocator 调用包装成 `LocationSnapshot`（`lib/services/location_service.dart:3-56`） | 返回值简洁、可保留；但实现由 Widget 内部创建，当前无法替换为测试 Adapter。 |
| `lib/services/heart_rate_service.dart` | 返回结构化占位结果，尚未接设备（`lib/services/heart_rate_service.dart:1-15`） | 目标边界正确地暗示了“设备能力可替换”，但当前只有一个占位实现，且数据之后被放进共享接触表。 |
| `lib/l10n/app_strings.dart` | 中文／英文和固定选项集中保存，缺失项回退中文（`lib/l10n/app_strings.dart:1-13`） | 可复用，但问卷选项、稳定领域枚举和显示文本以后必须分层，不能继续把配置题目写死在这里。 |

### 3.3 依赖方向的核心问题

**事实：**

1. `AppController` 继承 `ChangeNotifier`，同时导入 `flutter/material.dart`、Drift、密码散列、数据库和两个业务模型（`lib/app/app_controller.dart:1-14`）。
2. `QuickRecordView` 在 State 内直接创建 `LocationService` 和 `HeartRateService`（`lib/screens/home_shell.dart:174-181`）。
3. Drift 行与 Dart 模型之间的双向映射、事务、权限、统计和种子数据都写在 Controller 内（`lib/app/app_controller.dart:604-919`）。
4. 图表不是消费已经定义好的指标结果，而是在 Widget `build` 中直接按记录循环计数；例如按小时、关系阶段和兴趣分布（`lib/screens/home_shell.dart:1538-1550`、`1997-2010`、`2106-2118`）。

**推论：**

- 修改数据库字段会同时触及 schema、Controller 映射、模型、表单、列表和图表；修改权限或统计口径也会影响同一个 Controller。这使需求演进需要同时理解大范围代码，正是“需求更新时难以灵活更新”的根因。
- 单纯把大文件切成许多小文件不会自动修复它；如果小文件仍共享同一个万能 Controller 和 `ConversationRecord`，只是把耦合隐藏起来。

**建议：**

- 表示层只能依赖应用行为的窄接口和不可变 View State；领域和统计模块不能导入 Flutter。
- Drift 是本地实现细节。不要为五十张表创建五十个浅 Repository；让 `ContactJournal`、`QuestionnaireCatalog`、`TargetFollowUp`、`MetricEngine` 等深模块在内部协调多张表和事务。
- 只有真实存在两个 Adapter 的外部依赖才建立 Port：Firebase 与测试假认证需要 `IdentityPort`；Backend HTTP 与内存合同测试 Adapter 需要 `SyncPort`。Drift DAO 可以先作为模块内部实现，不为抽象而抽象。

## 4. 两个集中化热点

### 4.1 `AppController`：状态容器、业务规则和数据访问混为一体

**事实：**

- `load()` 依序读用户、创建默认账号、读设置、读记录并自动补种子数据（`lib/app/app_controller.dart:65-71`）。启动本身会改变数据库，不是纯读取。
- Controller 自己执行登录失败计数、30 天锁定、注册、重置和改密（`lib/app/app_controller.dart:79-309`）。认证结果、授权和用户资料没有独立接缝。
- 当前记录读权限是“用户可以看该城市；城市管理员看全城；其他人只看自己记录”（`lib/app/app_controller.dart:604-616`）。这与“成员能力＋当前项目＋匿名管理分析”的目标完全不同。
- `addRecord` 和 `updateRecord` 先修改内存并通知 UI，再等待数据库写入（`lib/app/app_controller.dart:356-370`）。如果数据库写入失败，当前接口没有回滚内存、错误状态或重试语义。
- `updateRecord` 使用同一主键覆盖原行，`deleteRecord` 和 `clearRecords` 物理删除（`lib/app/app_controller.dart:362-385`）；这与追加修订和作废相冲突。
- 统计方法直接读取 `visibleRecords`；`contactRate()` 把“存在联系方式”的记录数除以记录总数（`lib/app/app_controller.dart:474-492`），而 ADR 0066 已明确删除这个口径（`docs/adr/0066-follow-up-consent-rate-is-optional-and-consent-based.md:1-3`）。
- Controller 负责数据库行映射、父子表事务和硬编码 30 条演示记录（`lib/app/app_controller.dart:637-919`）。

**推论：**

- 目前 Controller 的“接口”不仅是方法签名，也包括调用顺序、所有公共字段、内存／数据库先后顺序和隐式自动播种。测试任何一项行为都容易带入其余行为。
- `notifyListeners()` 先于持久化使 UI 快速，但没有一个明确的乐观更新协议；未来加入 Outbox 后如果照搬，会出现“界面显示已保存、实际本地事务失败”的错误承诺。

**建议：**

- 保留一个很小的 `AppSessionState` 处理登录态、语言、主题和当前项目上下文；它不负责接触、问卷、对象或统计。
- 接触模块用一个原子接口返回持久化结果，例如 `autosaveDraft`、`submitDraft`、`reviseContact`、`voidContact`。只有本地 SQLite 事务成功后才发布“已保存”；Outbox 状态作为结果的一部分，不由 Widget 猜测。
- 把随机 ID 和当前时间从 `Random()`／`DateTime.now()` 改为注入的 `IdGenerator`／`Clock`，以便测试锁定、周期、延迟录入和冲突重放。

### 4.2 `home_shell.dart`：导航、表单、权限和计算混为一体

**事实：**

- 稳定主导航现在是“记录、列表、图表、管理、设置”五项，手机使用底栏、宽度 ≥900 使用 NavigationRail（`lib/screens/home_shell.dart:22-115`）。响应式容器已有雏形，但目的地与 ADR 0089 不符。
- 页面列表每次 `build` 重新创建，Body 只挂载当前 `pages[_selectedIndex]`（`lib/screens/home_shell.dart:26-41`、`68-114`）。快速记录内容只保存在 `_QuickRecordViewState` 的 TextEditingController 和普通字段中（`lib/screens/home_shell.dart:174-216`），数据库没有草稿表。
- 快速记录是一张平铺长表单，直接要求姓名、英文名、性别、身份、年龄、关系阶段、联系方式、兴趣、心率、地点和备注（`lib/screens/home_shell.dart:227-457`）。提交只验证城市，然后立即创建并保存旧 `ConversationRecord`（`lib/screens/home_shell.dart:504-571`）。
- 当前所谓 `_ContactDraft` 只是“一条联系方式输入行”的临时对象（`lib/screens/home_shell.dart:144-163`），不是目标模型中的“可自动保存、项目与问卷版本绑定的接触草稿”。同名会误导实现者。
- 记录列表可以搜索姓名、联系方式、备注等可识别内容，并直接物理删除（`lib/screens/home_shell.dart:641-665`、`754-775`）。
- 城市管理员可以打开完整记录并原地覆盖校正字段（`lib/screens/home_shell.dart:859-929`、`1293-1437`），而不是消费服务端返回的去身份化异常。

**推论：**

- 当前导航切换不能满足“不丢草稿”的保证；即使改成 `IndexedStack` 让 Widget 暂时存活，也仍不满足 App 崩溃、后台终止、多草稿和跨设备同步。因此草稿可靠性必须先落在 SQL 模块，不能靠导航控件修补。
- 管理页面和个人页面共享同一份 `visibleRecords`，使“UI 隐藏”承担了过多权限责任；接入后端后仍必须由 API 按能力返回不同数据形状。

**建议：**

- 先让四个目的地消费独立 Feature Module，再调整导航容器：`TodayFeature`、`ContactFeature`、`TargetFeature`、`AnalyticsFeature`。管理、问卷配置和成员权限从项目菜单进入，个人设置从个人菜单进入。
- 快速记录页只持有渲染状态；每次有意义输入调用草稿模块，界面展示模块返回的 `saving/saved/failed/conflict`，不自行维护“是否已保存”的真相。
- 图表 Widget 只接收 `MetricResult`（包含版本、统计单位、分子／分母、排除项、时区、截止时间和隐私状态），不能接收原始 `ConversationRecord` 后自行计算。

## 5. Drift schemaVersion 5 与迁移审计

### 5.1 当前五张表

| 表 | 当前字段语义 | 与目标模型的主要冲突 |
|---|---|---|
| `DbUsers` | 登录身份、个人资料、MD5、锁定状态、全局角色等级、城市列表和团队全部在一行（`lib/data/local_database.dart:6-29`） | Firebase 身份映射、内部用户、组织／项目成员关系与能力必须分表；不能从 `roleLevel` 推导。 |
| `DbConversationRecords` | 场次、人物 PII、人口属性、关系／兴趣、心率、定位、备注和校正都在一行（`lib/data/local_database.dart:32-68`） | 违反接触／对象、个人／共享、当前值／历史、核心／问卷的多个边界。 |
| `DbRecordContacts` | 记录 ID 下的联系方式渠道和值（`lib/data/local_database.dart:71-80`） | 名称容易被误读为“接触渠道”；它实际保存 PII，却不属于推广对象，也没有外键。 |
| `DbAppSettings` | 无用户或设备命名空间的任意键值（`lib/data/local_database.dart:82-88`） | 无法可靠表达逐用户、逐设备、逐项目的当前上下文、提醒和草稿同步模式。 |
| `DbSecurityEvents` | 本地用户 ID、事件类型和 JSON 详情（`lib/data/local_database.dart:90-99`） | 可作为审计概念原型，但缺少服务端接受状态、操作者能力、对象、mutation ID、不可篡改历史和同步。 |

### 5.2 完整性约束

**事实：**

- 除 `DbUsers.username` 唯一约束外，表定义没有外键、索引、Check 约束或复合唯一约束（`lib/data/local_database.dart:6-99`）。
- `DbRecordContacts.recordId` 只是普通文本，父记录删除依靠 Controller 手写事务（`lib/app/app_controller.dart:641-692`）。
- `relationshipLevel`、`interestLevel`、`attitudeLevel` 和多种字符串枚举没有数据库约束。`ConversationRecord` 的 JSON／`copyWith` 会夹取范围，但从 Drift 行读出时直接采用数据库值（`lib/models/conversation_record.dart:158-229`；`lib/app/app_controller.dart:764-799`）。
- `ConversationRecord.toJson()` 写入名为 `schemaVersion: 3` 的模型版本，而 Drift 数据库为 schemaVersion 5（`lib/models/conversation_record.dart:232-264`；`lib/data/local_database.dart:124-125`）。两者可能是不同版本域，并非必然错误，但当前命名和代码没有清楚表达这一点。

**建议：**

- 新表从第一天加入 FK、必要索引、范围 Check、状态 Check 和业务复合唯一约束；同时让后端重复验证，不把 SQLite 约束当作唯一安全边界。
- 区分 `database_schema_version`、`payload_contract_version`、`questionnaire_version` 和 `metric_version`，不再用一个模糊的 `schemaVersion` 名称指代不同概念。
- 为 Outbox 和查询热路径设计索引：至少按 `sync_state/next_attempt_at`、`project_id/occurred_at_utc`、`creator_user_id/draft_updated_at`、`target_id/project_id`、`region_node_id` 等真实访问路径建立；最终索引应由查询计划和数据量验证。

### 5.3 v1 → v5 升级行为

**事实：**

- v2 给旧记录增加 `relationshipLevel`，默认把旧记录视为等级 1（`lib/data/local_database.dart:131-138`）。
- v3 给用户增加生日、性别、职业、联系方式 JSON，同时给记录增加区域和兴趣（`lib/data/local_database.dart:139-152`）。
- v4 用硬编码城市规则把 `unassigned` 改成 IIT、Campus、Downtown 或 General Area，并把旧 `attitude_level -2..2` 映射为 `interest_level 0..4`（`lib/data/local_database.dart:153-180`）。
- v5 尝试 `DROP COLUMN prayer_sentence`；运行时不支持时只把旧值清空，物理列仍保留（`lib/data/local_database.dart:181-200`）。
- 现有测试总是用 `NativeDatabase.memory()` 创建最新 schema，没有任何 v1/v2/v3/v4 文件升级到 v5 的测试（`test/widget_test.dart:16-21`）。

**推论：**

- v4 的区域与兴趣值中可能混有系统推断值，但表里没有“原始／推断／算法版本”标记。迁移到新统计时无法仅看当前数字分辨用户实际记录还是旧升级生成。
- v5 fallback 允许“Drift 声明的 v5”和“磁盘实际仍含废弃空列的 v5”并存。它不一定影响当前查询，却说明下一轮迁移必须用真实旧文件测试多种 SQLite Runtime，而不能只测试 `onCreate`。
- 现有迁移已做过不可逆的信息清空；新迁移不应继续用默认值填补未知业务事实。

**建议：**

1. 在任何 v6 迁移前，生成并纳入测试的 v1、v2、v3、v4、两种 v5 数据库夹具。
2. 每个夹具验证表／列、记录数、legacy 原始值、约束、迁移幂等行为和 App 可读性。
3. 新建 `legacy_import_source`／`legacy_record_map` 一类迁移溯源表；不要覆盖旧表以伪装迁移完成。
4. 将 schema 扩展拆成多个小版本，每个版本只随一个可验证垂直切片发布，避免一次性创建几十张尚无调用者的表。

## 6. 目标能力差距矩阵

| 领域 | 当前事实 | 缺口／冲突 | 严重性 |
|---|---|---|---|
| 认证 | 本地用户表保存 MD5；Controller 自己注册、锁定、重置并在 UI 显示临时密码（`lib/app/app_controller.dart:79-309`） | 无 Firebase SDK、Identity Adapter、Firebase UID → `app_user_id` 映射、令牌／会话处理或 Emulator 接线；正式构建与 Demo 构建未隔离。 | 阻断生产 |
| 授权与审计 | 全局 `roleLevel`、城市列表和 `teamName` 决定访问（`lib/models/app_user.dart:24-46`、`83-87`） | 无组织／项目成员关系、能力、所有者约束、对象分配；客户端可见性与本地安全事件不能代替后端授权。 | 阻断生产 |
| 空间／组织／项目 | 只有可编辑字符串 `cityName/areaName/teamName`（`lib/app/app_controller.dart:30-36`、`323-348`） | 无个人空间、组织、项目 ID、成员关系、当前项目上下文、邀请／申请、删除恢复期。每条记录也无 project FK。 | 核心缺失 |
| 区域 | `areasForCity` 是 Controller 中的硬编码平铺列表（`lib/app/app_controller.dart:1012-1035`） | 无全平台唯一父级树、节点 ID、属性、别名、解析版本、建议、当前／原始区域视图；`N/A` 与待解析未分开。 | 核心缺失 |
| 接触核心 | 旧记录有时间、位置和兴趣，但无渠道类别、触达人数、发生时区、录入时间、项目／问卷版本、状态（`lib/data/local_database.dart:32-68`） | 无接触尝试、场次／对象关联、延迟录入、草稿、提交状态、修订、作废。 | 核心缺失 |
| 草稿 | UI State 中只有当前表单；`_ContactDraft` 实为联系方式输入行（`lib/screens/home_shell.dart:144-216`） | 无多草稿、自动保存、项目／问卷绑定、仅本机／跨设备模式、冲突副本和恢复。 | 核心缺失 |
| 推广对象 | 姓名、联系方式、人口属性直接写在接触宽表和 child 表（`lib/data/local_database.dart:43-56`、`71-76`） | 无个人／机构对象、空间所有权、跟进者、保留期／匿名化、导入导出能力、重复合并／拆分、接触多对多关联。现状直接违反 ADR 0014。 | 高隐私风险 |
| 项目关系 | `relationshipLevel 1..4` 存在每条接触上（`lib/models/conversation_record.dart:83-88`、`376-384`） | 目标为 `target × project` 的 `0..4` 当前关系和追加阶段事件；无生命周期状态、操作者或原因。 | 数据语义冲突 |
| 问卷 | 性别、身份、年龄写死在本地化常量和长表单（`lib/l10n/app_strings.dart:15-41`；`lib/screens/home_shell.dart:358-400`） | 无八种题型、回答状态、显示规则、草稿／发布、不可变版本、兼容映射、回答类型表和后端验证。 | 核心缺失 |
| 私有文本／健康 | 公共 `notes` 和心率都在接触记录上，管理员可见（`lib/data/local_database.dart:45-59`；`lib/screens/home_shell.dart:1502-1519`） | 个人反思、跟进备注和个人生理信号没有分开的所有权、存储、同步或仓库排除路径。 | 高隐私风险 |
| 离线与同步 | SQLite 能本地写入，但没有 Outbox 或 API；pubspec 也没有 Firebase／网络同步依赖（`pubspec.yaml:30-58`） | 无 mutation ID、同步状态、重试、幂等、后台同步、服务端验权、字段级冲突、数据截止时间、敏感缓存撤销。 | 阻断多设备 |
| 本地敏感数据 | 默认 Drift 文件，没有应用层加密、设备密钥、72 小时授权租约或按分配清理逻辑（`lib/data/local_database.dart:110-122`） | 不能满足 ADR 0038/0039 的离线对象访问边界（`docs/adr/0038-cache-only-assigned-promotion-targets-for-offline-follow-up.md:1-3`；`docs/adr/0039-limit-offline-sensitive-access-to-seventy-two-hours.md:1-3`）。 | 高隐私风险 |
| 个人计划／今日 | 当前没有计划、目标或提醒表；导航也没有“今日” | 无私有提醒、可选周目标、固定统计时区、周期起始日、逐设备通知与非惩罚性反馈。 | 功能缺失 |
| 个人分析 | 本地记录写入后图表可刷新，是可用原型 | 无有效／作废过滤、版本指标、时区、触达人数、草稿／同步状态；关系阶段错误地按接触行计数。 | 口径不可信 |
| 管理分析 | 管理员直接看到 `visibleRecords` 精确值和完整记录（`lib/screens/home_shell.dart:899-975`） | 无阈值 10、三位贡献者、单人 ≤50%、互补隐藏、防差分、批准维度、服务端过滤；“匿名摘要”仍导出全部精确分组（`lib/app/app_controller.dart:398-455`）。 | 严重隐私冲突 |
| 指标系统 | 计算散落在 Controller 和 Widget | 无指标目录／版本、分子分母／排除项、跨 Flutter／后端／仓库 fixture 对账、报告快照或更正版。违反 ADR 0076（`docs/adr/0076-versioned-metric-catalog-keeps-analysis-layers-aligned.md:1-3`）。 | 核心缺失 |
| 导航 | 已有手机底栏与宽屏侧栏，但固定五目的地（`lib/screens/home_shell.dart:28-115`） | 无“今日／接触／对象／分析”、持续可见项目上下文、全局记录按钮、能力驱动菜单和深层链接。 | 结构冲突 |
| 六平台 | iOS、Android、Web、macOS、Windows、Linux 工程目录均存在；Web 配有 Drift worker/WASM（`lib/data/local_database.dart:113-121`） | 没有六平台测试／发布矩阵，也未验证安全存储、后台同步、通知、定位和文件能力的各平台 Adapter。 | 需验证 |
| 学习说明书 | 有手写说明文件，但 pubspec 未把 Markdown 声明为 App 资源（`pubspec.yaml:64-74`）；代码注释多为英文且覆盖不均 | 无 App 内说明书入口、代码片段提取、复制测试、文档／SQL／指标 CI 门禁；尚未达到 ADR 0053 的中文解释和同步维护要求（`docs/adr/0053-production-code-and-learning-materials-evolve-together.md:1-3`）。 | 交付缺失 |

## 7. 当前统计实现的具体语义问题

### 7.1 已有可用部分

- 兴趣已经使用 `0..4`，UI 有各级柱状分布（`lib/screens/home_shell.dart:2106-2198`）。这可以保留为“图表渲染参考”，但计算必须移出 Widget。
- 按日、小时、区域和类别进行计数的代码展示了基础分组思路（`lib/screens/home_shell.dart:1538-1761`、`1763-1865`）。
- 个人数据写入本地后可以即时重算，符合 ADR 0075 的个人即时层方向，但没有同步状态和截止时间。

### 7.2 不可继续沿用的口径

1. `contactRate` 实际是“记录中存在联系方式的比例”，不是明确同意继续联系；ADR 0066 明确要求删除该默认指标（`lib/app/app_controller.dart:474-482`；`docs/adr/0066-follow-up-consent-rate-is-optional-and-consent-based.md:1-3`）。
2. `_RelationshipChart` 对每条接触的 `relationshipLevel` 计一次（`lib/screens/home_shell.dart:1997-2010`），目标应对去重的 `推广对象 × 项目` 当前关系计一次，阶段流转另按事件计算（`docs/adr/0061-interest-stage-and-transition-statistics-use-distinct-units.md:1-3`）。
3. `countToday` 使用设备当前本地日期，小时图使用 `createdAt.hour`（`lib/app/app_controller.dart:457-463`；`lib/screens/home_shell.dart:1545-1549`）。记录没有 UTC＋IANA 发生时区，也没有项目报告时区，无法满足 ADR 0062/0063（`docs/adr/0062-management-periods-use-the-project-reporting-time-zone.md:1-3`；`docs/adr/0063-hour-of-day-analysis-defaults-to-contact-local-time.md:1-3`）。
4. `averageAttitude()` 对有序兴趣等级直接算平均值且不带等距警示（`lib/app/app_controller.dart:484-493`）。即便当前 UI 未明显使用它，保留该接口仍会诱导错误调用；默认应展示分布、比例和中位等级（`docs/adr/0060-ordinal-scale-distributions-are-primary.md:1-3`）。
5. 所有管理结果都是 App 收到原始行后再计算，阈值完全不存在；目标要求后端在返回任何精确单元前执行阈值、互补隐藏和防差分（`docs/adr/0067-anonymous-analytics-prevent-differencing-without-noise.md:1-3`）。
6. 比例只显示百分比，没有统一显示分子、分母、未知、不适用和排除项（`lib/screens/home_shell.dart:2812-2817`），不符合透明描述性统计（`docs/adr/0068-core-reports-use-transparent-descriptive-statistics.md:1-3`）。
7. 无“有效记录”概念，所以补录、修订、作废、冲突或尚未同步都可能无法正确处理。正式报告也无数据截止、指标版本或快照（ADR 0074/0075）。

### 7.3 建议的统计测试接缝

定义一个不依赖 Flutter 的 `MetricEngine` 深模块：

```text
输入：MetricRequest + MetricVersion + 经过授权的数据视图
输出：MetricResult
      ├── unit / time basis / privacy status
      ├── numerator / denominator / exclusions
      ├── cells / median / percentage-point change
      └── data cutoff / calculation version
```

- 个人本地 Adapter 可读本地有效事实，并明确标注未同步状态。
- 管理 Adapter 只接收 Backend API 已执行隐私保护的 `MetricResult`；Flutter 不接收被抑制的原始精确值。
- 同一份虚构 fixture 在本地 Dart、后端事务 SQL 和仓库 SQL 上复算，满足 ADR 0076 的跨层对账要求。
- 图表 Widget 测试只验证 `MetricResult` 的显示、隐藏文案、口径说明和响应式布局，不再重复测试公式。

## 8. 可以保留和深化的部分

### 8.1 明确可保留

1. **Flutter 单代码库与六平台工程骨架。** 当前工程已经包含六个平台目录；继续遵守“一套能力适配 App”，不要拆成管理员 App 与推广者 App。
2. **Material 3 主题与宽度适配模式。** `ThemeData(useMaterial3: true)` 已存在（`lib/main.dart:74-107`）；NavigationBar／NavigationRail 的容器切换可以保留，只替换目的地和状态管理。
3. **双语回退机制。** `AppStrings.t()` 的中文回退简洁（`lib/l10n/app_strings.dart:1-13`）；后续可迁到标准 ARB，但不必为了现代化立即重写所有文案。
4. **Drift 与本地 SQLite。** `LocalDatabase(super.executor)` 允许传入不同执行器（`lib/data/local_database.dart:110-122`），既满足学习 SQL，也支持内存集成测试。
5. **数据库行与 Dart 对象显式映射的思想。** 当前 UI 没有直接依赖 Drift 生成类型，映射集中在 Controller（`lib/app/app_controller.dart:714-833`）。应把映射移入相应深模块，而不是取消这层。
6. **父子表事务。** 旧接触和联系方式在一个 Drift transaction 中写入（`lib/app/app_controller.dart:641-681`）。新模块应继续用事务保证草稿、正式事实、修订和 Outbox 原子写入。
7. **结构化设备结果。** `LocationSnapshot`／`HeartRateSnapshot` 比直接在 Widget 处理插件异常更易测试；应通过构造参数注入实现。
8. **图表绘制与小屏横向滚动经验。** `_horizontalChartViewport` 和现有 fl_chart 样式可以在计算移出后复用（`lib/screens/home_shell.dart:2723-2734`）。
9. **旧 JSON 兼容解析。** `ConversationRecord.fromJson` 已示范兼容旧 contacts、attitude 和 follow-up 字段（`lib/models/conversation_record.dart:266-364`）；可以抽出为一次性的 legacy importer 测试资料，不应继续作为新领域模型构造器。

### 8.2 需要保留“接缝”而非保留当前实现

- **根级依赖注入：** 保留 `TongxingzheApp(controller:)` 的测试便利，但把它发展为明确的 App dependencies／composition root。
- **认证：** 保留“认证可以替换”的位置，不保留 MD5 逻辑。测试 Adapter 不保存密码，Firebase Adapter 只返回外部身份，内部绑定由业务 SQL 处理。
- **定位：** 保留快照接口，生产 Adapter 调 Geolocator，测试 Adapter 返回确定结果。
- **时钟和 ID：** 当前没有接缝，必须新增；否则无法可靠测试 72 小时授权、周周期、补录和幂等 mutation。
- **图表：** 保留视觉 Widget，替换其输入，从原始记录改为版本化指标结果。

## 9. 旧数据迁移：哪些事实不可推断

迁移原则：**不知道就是不知道。** 新 schema 应能表达“legacy 未记录／无法判定”，而不是用默认值制造新事实。

| 旧字段／数据 | 可以安全保留的内容 | 无法可靠推断 | 建议处理 |
|---|---|---|---|
| `DbUsers.userId`、用户名 | legacy 本地标识和显示资料 | Firebase UID、已验证邮箱、正式 `app_user_id` | 登录后明确绑定或新建内部用户；保留 legacy ID 映射，不把本地 ID 当 Firebase 身份。 |
| `passwordMd5`、锁定／重置字段 | 最多作为 Demo 识别证据 | 不能迁移成安全密码或 Firebase 凭据 | 正式迁移中丢弃密码摘要；要求 Firebase 注册／受控账号迁移。 |
| `roleLevel`、`cityNamesJson`、`teamName` | 原始数值和字符串 | 组织、项目、成员关系、能力、所有者、当前上下文 | 管理者明确建立新成员关系；不做 `90 => owner` 等静默映射。 |
| `recordId` | legacy 来源主键 | 全局唯一性、mutation ID、修订链 | 新建稳定 ID，保留 source ID 唯一映射；不要把微秒时间字符串假定为跨设备唯一。 |
| `createdAt` | 原始时间值 | 实际发生时间还是录入时间、UTC 时刻、IANA 时区 | 保存为 `legacy_timestamp`；只有用户确认或有外部证据时才成为正式发生时间。 |
| `collectorUserId`、`recorderName` | 原始记录者线索 | 已认证操作者、成员资格、姓名是否被改过 | 仅在 legacy 用户绑定经确认后关联；否则使用不可反查的 legacy actor。 |
| `cityName`、`areaName` | 原始地点文字 | 规范区域节点、唯一父级、解析版本；v4 的 area 还可能是系统硬编码生成 | 保存 raw label＋坐标；通过区域解析／人工复核生成新关联，并记录解析版本与来源。 |
| 经纬度、精度、地点文字 | 原始位置观测和校正后值 | 面对面还是线上、地点 `N/A` 还是未填、最小区域 | 保留原始／校正坐标；未知地点状态不得自动设为 `N/A`。 |
| `personName`、`englishName`、`DbRecordContacts` | 可能的 PII 原文 | 是否同一对象、是否同意保存／联系、对象所属空间、对象类型、跟进者、与项目关系 | 隔离到受控 legacy PII 迁移队列；必须经权限与人工确认才能创建推广对象，不能自动合并。 |
| `gender`、`identity`、`ageRange` | 旧表单当时保存的字面值 | 是否实际询问、默认值还是回答、题目版本、回答状态、语义兼容 | 若保留，建立冻结的“legacy questionnaire”解释并标注来源；默认不与新问卷合并统计。 |
| `interestLevel` | 当前数值 `0..4` | 用户原始记录还是 v4 从 attitude 推断、当时量表定义是否与新“单次兴趣”完全一致 | 保存数值和 `legacy/unknown provenance`；未经兼容审查不进入新核心趋势。 |
| `attitudeLevel` | legacy `-2..2` 原值 | 与 `interestLevel` 谁是权威；新记录又把它写成 `interest - 2`（`lib/screens/home_shell.dart:538-540`） | 只作迁移证据，不作为新指标或第二套兴趣事实。 |
| `relationshipLevel 1..4` | 一次旧记录上的数字 | 新 `target × project` 的当前 `0..4` 阶段、阶段变更时间、原因、是否上升／下降 | 不自动创建项目关系或阶段事件；最多保留为 legacy session observation。 |
| `contacts.isNotEmpty` | 当时记录内存在 PII | 后续联系同意 | 绝不推断同意；ADR 0066 要求明确结构化同意。 |
| `notes` | 原始自由文本 | 哪部分是个人反思、哪部分是共享跟进，是否含 PII | 默认仅迁入记录者私有的受限 legacy note／隔离区；不得进入分析或自动共享给跟进者。 |
| `averageHeartRate` | 原始数值 | 是否取得有效授权、是否应属于组织记录 | 仅当记录者绑定可靠且用户同意时迁入私有个人信号；否则按隐私政策清除或隔离。 |
| `corrected*`、`correctedAt` | 原值与当前校正值 | 校正者、原因、能力、完整修订历史 | 生成一条“legacy migration correction”并注明缺失 actor/reason；不能伪造完整审计链。 |
| 自动 seed 的 `demo-*` 记录 | 演示用途线索 | 是否有人将演示记录修改后当作真实资料 | 正式迁移前单独列出并由用户确认删除／排除；不能只靠数量自动带入。 |
| `DbSecurityEvents` | 本地事件时间、类型、详情 | 服务端接受、不可篡改性、正式身份、完整审计 | 可归档为 legacy local log，不作为正式授权或合规审计证据。 |

## 10. 当前测试覆盖与应保留的测试接缝

### 10.1 本次验证结果

```text
dart analyze
→ No issues found!

flutter test --no-pub
→ 1 test passed
```

唯一测试使用 `LocalDatabase(NativeDatabase.memory())` 注入 Controller（`test/widget_test.dart:16-21`），验证：

- 启动停在登录页；
- 中英切换；
- `admin1/admin1` 演示登录；
- 进入图表并滚动看到按日、区域和身份图表（`test/widget_test.dart:25-57`）。

### 10.2 没有覆盖的高风险行为

- v1/v2/v3/v4/v5 磁盘数据库升级；
- 登录失败、锁定、重置、退出后的缓存和生产／Demo 构建隔离；
- 任意权限边界，尤其项目能力、对象分配和管理员去身份化；
- 接触草稿、自动保存、提交事务、修订、作废、延迟录入；
- Outbox 幂等、重试、字段冲突、跨设备草稿冲突；
- 问卷八题型、显示规则、五回答状态、发布和版本兼容；
- 推广对象 PII、匿名化、保留期、合并／拆分和 72 小时离线授权；
- 指标单位、时区、分母、缺失、隐私阈值、贡献者保护和互补隐藏；
- Web 与五个原生平台的数据库、通知、定位、安全存储和布局；
- 说明书 bundle、代码片段提取、复制和 SQL 对账。

### 10.3 适合保留或新增的测试接缝

| 接缝 | 现在的基础 | 应如何深化 |
|---|---|---|
| App composition root | `TongxingzheApp(controller:)` | 注入 `AppDependencies`，测试可组合假身份、内存 Backend、Clock、ID 和临时 Drift。 |
| Drift executor | `LocalDatabase(super.executor)` | 保留 `NativeDatabase.memory()` 用于模块集成测试；另用真实旧文件测试 migrations，不只测 onCreate。 |
| 身份 | 无正式接缝 | `IdentityPort` 至少有 Firebase、Fake、Firebase Emulator 三种 Adapter；共同运行合同测试。 |
| 后端同步 | 完全缺失 | `SyncPort` 有 HTTP Adapter 和内存合同 Adapter；测试 mutation 幂等、重放、错误分类和权限拒绝。 |
| 时间／ID | 直接 `DateTime.now()`、`Random()` | 注入 Clock／ID，覆盖时区边界、72 小时、周起始、报告截止和重复 mutation。 |
| 位置／设备 | 已有 Snapshot | 构造注入 Adapter；测试权限拒绝、超时、无坐标、`N/A` 与待解析状态。 |
| 接触行为 | 当前直接 Controller CRUD | 以 `ContactJournal` 接口为测试面，断言可观察结果和 SQL 状态，不越过接口检查内部对象。 |
| 问卷 | 无 | 同一规则 fixture 同时测试 Flutter evaluator 和后端 validator；隐藏答案、必填和五状态必须对账。 |
| 指标 | 计算在 Widget | 共享 fixture 对账 Dart／事务 SQL／仓库 SQL；Widget 只测 MetricResult 展示。 |
| 响应式 UI | 当前 Widget 测试只用 390×844 | 对手机、平板／桌面关键宽度做 Widget／Golden；每个平台再做少量启动 smoke，不复制全部业务测试。 |

当前 Widget 测试适合保留为“App 可以启动并完成基本导航”的 smoke test，但导航改为四目的地后应按新术语重写。不要把它扩成包揽所有业务的巨型端到端测试。

## 11. 建议的 expand–contract 与垂直切片顺序

### 阶段 0：冻结旧行为，建立迁移护栏

**目标：** 在不改变用户数据的前提下，先让后续改造可验证。

1. 保存 v1–v5 真实数据库夹具，补齐升级测试和 v5 数据快照统计。
2. 把自动演示账号／演示数据限制在明确 Demo/Test 配置；生产配置绝不调用 `_ensureDefaultUsersExist`、`_ensureSeedData` 或 MD5。
3. 加入 Clock、ID 和错误结果类型；记录本地事务失败而不是只抛异常。
4. 建立 legacy 数据盘点页或只读导出，列出真实、演示、无法识别来源的记录数量。
5. CI 先固定 `dart analyze`、现有测试、Drift 生成文件一致性和迁移测试。

**Contract 暂不发生：** 不删表、不改旧字段语义、不批量回填新事实。

### 阶段 1：先切出深模块，保持现有 UI 行为

**建议模块及依赖：**

```text
Flutter Features
  ├── AppSession（登录态、语言、主题、当前项目）
  ├── ContactJournal（草稿、提交、修订、作废）
  ├── QuestionnaireCatalog（定义、版本、规则、答案）
  ├── TargetFollowUp（对象、分配、项目关系、备注）
  ├── PersonalPlan（提醒、周目标）
  └── Analytics（指标请求与结果）
          ↓
Domain / application rules（不依赖 Flutter、Drift、Firebase）
          ↓
Local Drift implementation + Firebase / Backend adapters
```

先移动现有行为并以测试保护，不在同一 PR 同时重做 UI 和领域语义。`AppController` 逐步收缩为组合这些模块的 Session 状态，最终不再执行 SQL、认证或指标公式。

### 阶段 2：扩展身份、空间、项目和规范上下文

新建而非改写旧 `DbUsers`：

- `app_users`、`external_auth_identities`；
- `workspaces`、`organizations`、`projects`；
- `organization_memberships`、`project_memberships`、`membership_capabilities`；
- 当前项目的逐用户／逐设备选择；
- 规范区域节点、父级、属性、别名、版本和解析结果。

先用隔离 Fake Identity 交付，Firebase Adapter 与 Emulator 接线作为同一接口的第二实现。所有后端受保护操作重复验权；UI 只按能力改善体验。

### 阶段 3：第一条生产垂直切片——匿名接触

从个人空间和一个项目开始，完整走通：

1. 顶部显示当前“空间 → 项目”和当前空／基础问卷版本；
2. 用户输入实际发生 UTC＋IANA 时区、稳定渠道、地点状态／最小区域、触达人数、单次兴趣；
3. 第一次有意义输入创建私有草稿，后续改动事务性自动保存；
4. 正式提交在同一 SQLite transaction 中写入 contact session、初始 revision／event 和唯一 Outbox mutation；
5. UI 立即显示本地事实及 `仅本机／同步中／失败`；
6. 接触页可读旧 legacy 记录，但新写只进入新表。

这一步不创建推广对象，也不迁移旧 PII。它验证“接触独立、默认匿名、离线优先”的最小完整闭环。

### 阶段 4：Backend 同步、修订、作废和冲突

- 定义版本化 mutation envelope、幂等 ID、基线版本和字段变更集；
- Backend API 校验身份、项目能力、问卷版本和核心字段；
- 实现 Outbox 重试、服务端接受时间、冲突副本和失败分类；
- 接触修改只追加 revision，错误事实用 void event；
- 不同字段自动合并，同字段产生用户可见冲突；
- 保持旧客户端兼容窗口，服务端在 Contract 前同时理解旧／新 payload。

### 阶段 5：版本化问卷垂直切片

- 问卷草稿、预览、差异、发布和不可变版本；
- 八种受控题型、五回答状态和一层 AND／OR 显示规则；
- 本地 evaluator 与后端 validator 共用同一 fixture；
- 接触草稿绑定版本，升级只复制已审计语义兼容答案；
- 回答使用类型化表和状态，不把全部值压成一个无约束 JSON；
- 固定 demographic 字段转为 legacy questionnaire，不再写入新接触核心表。

### 阶段 6：推广对象与跟进垂直切片

在身份、能力和同步已经可靠之后再引入 PII：

- 个人／机构对象、空间所有权；
- 当前跟进者和访问审计；
- 接触 ↔ 对象多对多关联及可选对象当次反应；
- `target × project` 项目关系、`0..4` 当前阶段和阶段变更历史；
- 人—机构多对多历史关系及六种性质；
- 明确后续联系同意、共享跟进备注、保留期／匿名化；
- 分配对象的加密离线缓存和 72 小时授权租约；
- 导入、导出、重复提示、可逆合并最后分别交付，不与基本对象 CRUD 混在一个切片。

### 阶段 7：今日、个人计划和四目的地导航

当“接触”和“对象”已有真实模块后，再完整落地导航：

- 今日：私有提醒、可选周目标、近期行动和同步异常；
- 接触：草稿、正式记录、补录、修订、作废；
- 对象：仅本人可跟进对象和事项；
- 分析：个人默认，能力允许时进入管理汇总。

这样不会先交付四个空壳页面。NavigationBar／Rail 的现有响应式代码可继续使用，所有主页面共享同一个上下文选择模块和全局“记录接触”动作。

### 阶段 8：指标目录、个人分析和隐私管理分析

1. 先发布平台核心指标目录和共享 fixture；
2. 本地个人分析只读取本人的有效事实，显示同步状态、时间口径和排除项；
3. Backend 实现阈值 10、三位贡献者、单人 ≤50%、互补隐藏和防差分；
4. App 只接收隐私处理后的管理 MetricResult；
5. 建立数据截止时间、新鲜度层级、报告快照和更正版；
6. 最后接去身份化仓库，不让 Snowflake 阻塞事务和本地体验。

### 阶段 9：legacy 转换与 Contract

只有在以下条件同时满足后才收缩旧模型：

- 新写路径至少经过一个稳定发布周期；
- 旧客户端兼容窗口结束或服务端仍能安全接收；
- 每一类旧字段已有“安全迁移／人工确认／保留为 legacy／删除”决定；
- 数量、哈希、抽样复核和统计对账通过；
- 用户可以看到哪些字段未被迁移以及原因；
- 回滚不需要恢复已经物理删除的旧表。

Contract 顺序应是：停止旧写 → 观察只读兼容 → 导出／归档 legacy → 删除旧 UI 入口 → 最后删除 `DbConversationRecords`、`DbRecordContacts`、旧密码和全局 role 字段。不要在 expand 阶段使用双写制造两个权威来源；若过渡必须双写，应以新事务＋Outbox 为唯一权威并有逐条一致性检查。

## 12. 建议的实施验收门槛

每个垂直切片至少同时交付：

- 一个清楚的模块接口及中文接口说明；
- 对应 Drift migration 和真实旧库升级测试；
- 领域行为／权限／错误模式测试；
- 一条成功路径和一条离线／失败路径 Widget 测试；
- SQL 示例及分子、分母、排除项说明；
- 与代码片段自动提取关联的开发说明书章节；
- `dart analyze`、全测试、`git diff --check` 和生成文件一致性通过。

涉及 PII、权限、同步或统计的切片还必须分别通过：

- 无权访问的后端拒绝测试，而不只是 Widget 隐藏；
- 日志／通知／仓库不含 PII 的负向测试；
- mutation 重放和同字段冲突测试；
- 阈值、贡献者保护、互补隐藏和跨层指标 fixture 对账。

## 13. 最终判断

当前代码最值得保留的不是旧数据模型，而是已经验证过的 Flutter＋Drift 技术方向、六平台工程骨架、Material 3、双语、内存数据库注入、显式行映射、事务写入和部分响应式／图表实现。最需要停止扩张的是万能 `AppController`、万能 `ConversationRecord`、Widget 内统计、平铺固定问卷以及全局 `roleLevel` 权限。

因此，现代化的正确单位不是“把 2,800 行 UI 拆成若干文件”，而是让每一项业务能力成为一个有小接口、深实现、可通过同一接口测试的模块；让 Flutter 负责呈现，让 Drift／SQL 明确保存事实与历史，让 Backend 负责云端授权和隐私，让指标目录负责统计解释。这样需求变化时，变化会落在正确的局部，而不是再次扩散到整个 App。
