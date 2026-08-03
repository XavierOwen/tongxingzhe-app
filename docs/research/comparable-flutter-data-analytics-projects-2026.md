# 可比较的 Flutter 记录与分析项目调研

更新日期：2026-08-03

状态：**研究完成；用于同行者的架构与产品参考，不构成引入第三方代码或依赖的决定。**

## 1. 结论

GitHub 上确实有仍在维护、star 数量可观、同时涉及 Flutter、结构化记录与分析的公开项目；但目前没有找到一个项目同时成熟满足下列全部条件：

1. Android、iOS、Web、macOS、Windows、Linux 六个平台都是正式产品目标；
2. 六个平台主要共享同一套 Flutter 代码；
3. 本地以 SQLite／SQL 为事实来源，并支持可靠离线写入；
4. 存在适合多用户、权限、审计和冲突处理的同步链路；
5. 已有较成熟的统计分析与报表；
6. 架构仍足够清楚，适合用来学习 Flutter 与 SQL。

因此，同行者不应选择一个项目整套模仿，而应建立一组分工明确的参考：

- **Lotti**：最值得研究“计划与实际分离”、Drift／SQLite、持久化 Outbox 与个人分析；
- **Table Habit**：最值得研究自我问责、连续记录、解释性统计图和五原生平台体验；
- **Cashew**：最值得研究 Drift schema、数据库升级与财务统计功能，同时也是“大文件和反向依赖”的反面教材；
- **Sossoldi**：最适合阅读原始 SQL、migration、repository 和图表之间的连接，同时要反向学习如何避免动态拼 SQL；
- **Invoice Ninja**：最值得研究真实业务记录、筛选、报表、响应式 CRUD 与 Web／原生多端交付；
- **AppFlowy**：只作为大型 local-first 工程、模块边界和同步状态的参考，不作为同行者的技术栈模板。

如果按对同行者的直接价值，而不是按 star 数排序，本轮建议为：

> **Lotti > Table Habit > Cashew ≈ Sossoldi > Invoice Ninja > AppFlowy**

这不是“谁的代码质量绝对更高”的排名，而是“谁更能回答同行者当前问题”的排序。

## 2. 怎样判断“类似”和“仍在维护”

本轮先建立筛选口径，避免被 star 或 README 宣传语误导。

### 2.1 核心筛选条件

- 核心候选在快照时至少约一千 stars；
- repository 未 archived，且默认分支、正式 release 或其他可核实分支在最近约六个月有活动；
- 代码中确实存在结构化持久化、迁移、查询、同步或图表，而不只是在 README 中写“analytics”；
- 至少在“记录型产品”“SQL／SQLite”“分析”“多平台”“同步”中的两个方面与同行者高度相关。

### 2.2 三种容易混淆的平台证据

“仓库中有 `windows/` 或 `web/` 文件夹”只证明曾生成或保留过平台入口，不自动证明该平台达到生产质量。本报告区分：

1. **目录存在**：代码树有平台目录；
2. **可以构建**：CI 或维护文档实际执行该平台 build；
3. **正式支持**：README、release 或商店渠道把它列为可交付平台。

只有第 3 类才能作为成熟平台证据。第 1 类最多说明未来可能支持。

### 2.3 “大量数据”的证据边界

这些项目普遍没有发布可横向比较的“多少行、多少年、什么设备、查询耗时多少”的完整 benchmark。项目拥有很多实体、图表或 stars，不等于已经证明能在手机上流畅处理任意规模数据。

本轮能够确认的是：它们包含真实的长期记录、迁移、索引、分页、同步或统计逻辑；不能确认的是：它们已经达到 Snowflake 一类分析仓库的规模。同行者仍应让设备 SQLite 负责离线工作集，让后端 PostgreSQL 负责共享事务事实，让将来的 warehouse 负责大规模去身份化分析。

## 3. 快照总表

star 与活动时间是 2026-08-03 的 GitHub 快照，会继续变化。

| 项目 | Stars | 最近可核实活动 | 正式／实际平台证据 | 数据与分析 | 对同行者的定位 |
| --- | ---: | --- | --- | --- | --- |
| [Lotti](https://github.com/matthiasn/lotti) | 1,157 | 默认分支 2026-08-03；release 2026-07-26 | Android、iOS、macOS、Windows、Linux；无 Web | Drift／SQLite、持久化 Outbox、习惯／时间／健康分析 | **同步与事实模型第一参考** |
| [Table Habit](https://github.com/FriesI23/mhabit) | 1,445 | commit 与 release 均为 2026-08-02 | Android、iOS、macOS、Windows、Linux；无 Web | sqflite、手写 SQL、WebDAV、成长与频率图 | **领域与自我问责第一参考** |
| [Cashew](https://github.com/jameskokoska/Cashew) | 4,522 | 默认分支 2026-03-09；最新 GitHub release 为 2024-07-01 | Android、iOS、Web | Drift schema v46、迁移快照、交互图表、预算分析 | **Drift／统计功能参考** |
| [Sossoldi](https://github.com/RIP-Comm/sossoldi) | 1,384 | 默认分支 2026-07-26；无 GitHub release | 六个平台目录齐全；README 正式表述集中在五原生平台 | sqflite、原始 SQL、migration、Riverpod、图表 | **可读 SQL 参考，成熟度待观察** |
| [Invoice Ninja Admin Portal](https://github.com/invoiceninja/admin-portal) | 1,748 | 默认分支与 release 为 2026-05-14 | 五原生平台有分发说明；CI 明确构建 Web | 远端 API、复杂业务实体、dashboard 与大量 reports | **业务记录与报表参考** |
| [AppFlowy](https://github.com/AppFlowy-IO/AppFlowy) | 74,848 | 默认分支 2026-06-26；release 2026-07-24 | Flutter 目录含六平台；官方稳定交付重点是移动与桌面 | Flutter＋Rust、local-first、协同数据库；统计不是主轴 | **大型工程参考** |

维护证据：

- [Lotti 最新核实 commit](https://github.com/matthiasn/lotti/commit/9063bcb447f3c4effb52d8b8eee1fc13ee676b13)与[最新 release](https://github.com/matthiasn/lotti/releases/tag/0.9.1071%2B4261)
- [Table Habit 最新核实 commit](https://github.com/FriesI23/mhabit/commit/c86a99107b25b3e93b66523efdd9750cb6f7e147)与[最新 release](https://github.com/FriesI23/mhabit/releases/tag/v1.26.5%2B178)
- [Cashew 最新核实 commit](https://github.com/jameskokoska/Cashew/commit/9cfbe50c16d95429891d44faf5f2c77a3abdb93b)与[最新 GitHub release](https://github.com/jameskokoska/Cashew/releases/tag/5.3.4%2B396)
- [Sossoldi 最新核实 commit](https://github.com/RIP-Comm/sossoldi/commit/ee9b2a6cd5314e1044b7e63ab6ab1234abcdda7b)
- [Invoice Ninja 最新核实 commit](https://github.com/invoiceninja/admin-portal/commit/806269400fce6a9845ce183fcf8e4828c29f5d65)与[最新 release](https://github.com/invoiceninja/admin-portal/releases/tag/v5.0.194)
- [AppFlowy 最新核实默认分支 commit](https://github.com/AppFlowy-IO/AppFlowy/commit/5cf3a365dec0d59f64bad1ee4bb1050471a39b93)与[最新 release](https://github.com/AppFlowy-IO/AppFlowy/releases/tag/0.13.0)

## 4. Lotti：最接近同行者整体问题的参考

### 4.1 为什么它最接近

Lotti 把“想要做什么”和“实际发生了什么”保存为不同事实；任务和计划描述意图，时间记录、日记、习惯与测量描述实际发生的生活。这与同行者“提醒不要混日子，但事实记录不等于考核”的产品方向高度相近。

它的正式说明明确列出五个原生平台，以 Flutter／Dart 开发，本地 SQLite 保存任务、日记、时间、习惯与健康数据。它没有 Web 平台，因此仍不能作为同行者六平台完成度的证明。

一手资料：

- [Lotti README：事实模型、平台、同步和分析](https://github.com/matthiasn/lotti/blob/main/README.md)
- [Lotti pubspec：Drift、SQLite、Riverpod、fl_chart、Matrix](https://github.com/matthiasn/lotti/blob/main/pubspec.yaml)
- [Lotti 架构说明](https://github.com/matthiasn/lotti/blob/main/docs/ARCHITECTURE.md)

### 4.2 最值得学习：持久化 Outbox

Lotti 的 Outbox 不是“断网后再试一次”的内存列表，而是 SQLite 中的持久队列。其源码包含：

- 写入 Outbox 表；
- 在事务内原子 claim 下一条或一批记录；
- `pending`、`sending`、`sent`、`error` 状态；
- lease 过期后重新认领，处理 App 中断或设备重启；
- priority，避免大批补传挡住用户刚写的新记录；
- ACK 后批量标记 sent；
- retry、deduplication、sequence gap 与 backfill；
- 独立的 Outbox 监控界面和健康统计。

一手资料：

- [Outbox claim、lease 与 mark-sent](https://github.com/matthiasn/lotti/blob/main/lib/database/sync_db_outbox.dart)
- [Outbox、索引与 sequence log 表](https://github.com/matthiasn/lotti/blob/main/lib/database/sync_db_tables.dart)
- [Outbox priority 与可观测性 ADR](https://github.com/matthiasn/lotti/blob/main/docs/adr/0013-outbox-priority-queue.md)

这些概念非常适合同行者的 `sync_outbox`。特别值得学习的是：一次本地提交先成为不可丢失的事实，再由独立队列负责传输；同步失败不应撤销用户已经完成的本地记录。

### 4.3 不能照搬什么

- 它没有 Web；
- 它是个人设备之间的 Matrix／Synapse 端到端加密同步，不是组织权限、审计、匿名管理汇总所需的中心 Backend；
- vector clock、加密协商和 backfill 的复杂度明显高于同行者第一阶段；
- README 明确说明本地 SQLite 当前没有 App 层静态加密；
- GPL-3.0 与同行者当前 MIT 许可不同，不能把源码直接复制进来后仍简单宣称整个项目只有 MIT 义务。

**结论：学习 Outbox 的状态机和故障恢复，不采用 Matrix 作为同行者的默认 Backend。**

## 5. Table Habit：最接近自我问责与连续记录

### 5.1 优点

Table Habit 是 local-first 的微习惯记录器，使用 SQLite／sqflite、手写 SQL、Provider 与 `fl_chart`，正式支持 Android、iOS、macOS、Windows、Linux，并为这些平台给出实际分发渠道。

它不只显示 streak，而是区分“做”和“不做”的评分模型，提供成长曲线、频率图、分数图与热力图。这很适合同行者学习如何把“事实回顾”做成温和的自我提醒，而不是排行榜或人员绩效。

一手资料：

- [Table Habit README：平台、SQLite、WebDAV 与统计](https://github.com/FriesI23/mhabit/blob/main/README.md)
- [pubspec：sqflite 与 fl_chart](https://github.com/FriesI23/mhabit/blob/main/pubspec.yaml)
- [SQL trigger 与 dirty tracking](https://github.com/FriesI23/mhabit/blob/main/lib/storage/db/sql.dart)
- [记录表读写与 JOIN](https://github.com/FriesI23/mhabit/blob/main/lib/storage/db/handlers/record.dart)
- [WebDAV 同步任务](https://github.com/FriesI23/mhabit/blob/main/lib/models/_app_sync_tasks/webdav_app_sync_task.dart)

### 5.2 值得学习

- 快速记录与长期趋势之间的产品闭环；
- 统计图不仅给结果，也让用户理解“分数为何变化”；
- 原始 SQL 仍然可读，适合作为教学材料；
- 数据库 handler、同步 task、provider 与 UI 比较容易分别定位；
- 数据库和 WebDAV 同步拥有较丰富的自动测试。

### 5.3 局限

- 没有 Web，且 `sqflite` 路径不能直接解决同行者的 Flutter Web 持久化；
- WebDAV 按习惯／组对象同步，不提供同行者所需的组织授权、幂等服务端事务、审计和匿名分析；
- 它是个人习惯产品，不包含推广对象、项目、问卷、区域树或多用户权限；
- dirty counter 与 WebDAV ETag 可以启发同步设计，但不能替代同行者的 Outbox 和服务端变更流。

**结论：优先学习产品闭环、统计解释和同步状态 UI，不复制其 WebDAV 架构。**

## 6. Cashew：Drift 与统计功能很强，代码边界不宜照搬

### 6.1 优点

Cashew 是 Android、iOS、Web 财务记录 App，使用 Drift 的 SQL 层和 `fl_chart`。其源码保留到 schema v46 的数据库结构和多版 Drift schema snapshot，包含交易、钱包、预算、目标、分类、删除日志和更新时间等真实长期数据问题。

它在产品上提供时间区间、类别、预算历史、目标进度、交互图表、CSV／Google Sheets 导入和跨设备同步，适合研究“记录如何变成可操作的分析”。

一手资料：

- [Cashew README](https://github.com/jameskokoska/Cashew/blob/main/README.md)
- [pubspec：Drift 与 fl_chart](https://github.com/jameskokoska/Cashew/blob/main/budget/pubspec.yaml)
- [数据库与查询实现](https://github.com/jameskokoska/Cashew/blob/main/budget/lib/database/tables.dart)
- [Drift schema snapshots](https://github.com/jameskokoska/Cashew/tree/main/budget/drift_schemas)
- [Google Drive 同步实现](https://github.com/jameskokoska/Cashew/blob/main/budget/lib/struct/syncClient.dart)

### 6.2 最值得学习

- Drift schema 版本、snapshot 和 migration 的长期演进意识；
- 日期区间、分类、预算和目标等分析交互；
- Web 与移动端使用同一数据模型的实际经验；
- 导入、删除记录和多设备变化都需要进入数据设计，而不是只做 UI。

### 6.3 明显问题

本轮核实的 `budget/lib/database/tables.dart` 约 7,667 行，并从数据库文件反向 import 多个页面、Widget、Firebase 和全局状态模块；测试目录中只有极少量 Dart 测试。它证明 Drift 能支撑丰富功能，却不是理想的“深模块”示范。

此外：

- 只有 Android、iOS、Web，没有桌面平台目录；
- GitHub 最新 release 仍停在 2024-07，默认分支虽在 2026-03 有提交，发布节奏仍需谨慎看待；
- Google Drive 每设备同步文件和变化日志不是中心服务端 Outbox；
- README 表示当前不接受代码贡献；
- GPL-3.0 不适合作为 MIT 项目的直接代码来源。

**结论：学习 Drift 的能力与产品分析，不学习 7,000 多行数据库文件和全局耦合。**

## 7. Sossoldi：适合读 SQL，也适合学习 SQL 安全边界

### 7.1 优点

Sossoldi 是 Flutter 个人财务／净值记录器，仓库包含 Android、iOS、Linux、macOS、Web、Windows 六个平台目录，使用 sqflite、Riverpod 与 `fl_chart`。代码把 migration、database service、repository 和图表拆成可定位的目录。

它的 migration 直接展示 `CREATE TABLE`，repository 直接展示 `JOIN`、`SUM`、`GROUP BY` 与 `strftime`，对初学者理解“Flutter 如何调用真正 SQL，再把结果交给图表”很有价值。

一手资料：

- [Sossoldi README](https://github.com/RIP-Comm/sossoldi/blob/main/README.md)
- [pubspec：sqflite、Riverpod 与 fl_chart](https://github.com/RIP-Comm/sossoldi/blob/main/pubspec.yaml)
- [数据库 migration 与 repositories](https://github.com/RIP-Comm/sossoldi/tree/main/lib/services/database)
- [初始 SQL schema](https://github.com/RIP-Comm/sossoldi/blob/main/lib/services/database/migrations/0001_initial_schema.dart)
- [交易查询与统计 SQL](https://github.com/RIP-Comm/sossoldi/blob/main/lib/services/database/repositories/transactions_repository.dart)

### 7.2 应反向学习的问题

部分筛选条件把日期、label、类型和账户 ID 动态拼进 SQL 字符串，而不是始终使用 `?` 参数绑定。即使某个调用路径当前对输入有约束，这种写法仍更难证明安全，也更容易在引号、日期或特殊字符出现时算错。

此外：

- README 仍称稳定版本正在开发，GitHub 没有 release；
- 平台目录齐全不等于 Web 等六端已经同等发布；
- 数据库和图表测试数量有限；
- 没有可核实的行级 Outbox／服务端同步；
- 第一阶段产品与 schema 仍可能快速变化。

**结论：把它当成可读 SQL 课堂，同时用同行者的参数绑定与查询测试修正其弱点。**

## 8. Invoice Ninja：真实业务记录、报表和六端交付参考

### 8.1 优点

Invoice Ninja 管理客户、产品、项目、发票、付款、费用、报价、任务、交易和供应商等大量业务实体。README 给出 Android、iOS、Windows、macOS、Linux 的实际分发入口，仓库包含 Web，并且 CI 明确运行 `flutter build web`。

它的 dashboard 与 reports 覆盖利润损失、发票、付款、费用、任务等多种场景，适合同行者研究：

- 多实体筛选与搜索；
- date range、grouping、previous period 与图表；
- 手机和桌面上的复杂表单／列表；
- 远端 API 数据如何形成 dashboard 和 report view model。

一手资料：

- [Invoice Ninja README 与架构目录](https://github.com/invoiceninja/admin-portal/blob/master/README.md)
- [Web build CI](https://github.com/invoiceninja/admin-portal/blob/master/.github/workflows/build.yml)
- [Reports UI](https://github.com/invoiceninja/admin-portal/tree/master/lib/ui/reports)
- [Dashboard selectors](https://github.com/invoiceninja/admin-portal/blob/master/lib/redux/dashboard/dashboard_selectors.dart)
- [本地 persistence repository](https://github.com/invoiceninja/admin-portal/blob/master/lib/data/repositories/persistence_repository.dart)

### 8.2 局限

- 客户端主轴是远端 API、Redux 和 built_value，不是 Drift／SQLite；
- 本地 persistence 主要序列化 Redux state 为 JSON 文件或 Web 存储，不是可审计的 SQL 事实库；
- 很多 dashboard 聚合在内存 selector 中完成，不适合作为同行者 SQL 学习主线；
- Redux 结构较老且全局状态庞大；
- `LICENSE.txt` 是自定义 Attribution Assurance License，GitHub API 也没有识别为标准 SPDX 许可，复用源码前必须单独审阅。

**结论：学习业务交互、筛选与报表，不把它当作离线 SQL／同步模板。**

## 9. AppFlowy：大型 local-first 工程参考，不是同行者模板

### 9.1 优点

AppFlowy 的 Flutter 前端目录包含六个平台入口，正式产品覆盖移动端和桌面端。它有大量数据库、同步、migration 与集成测试，适合观察大型产品如何把文档、grid、kanban、calendar、协作和云端状态拆成模块。

一手资料：

- [AppFlowy README：正式平台与技术栈](https://github.com/AppFlowy-IO/AppFlowy/blob/main/README.md)
- [Flutter 前端目录](https://github.com/AppFlowy-IO/AppFlowy/tree/main/frontend/appflowy_flutter)
- [Flutter pubspec](https://github.com/AppFlowy-IO/AppFlowy/blob/main/frontend/appflowy_flutter/pubspec.yaml)

### 9.2 局限

- 核心持久化和协作能力大量位于 Rust 层，SQLite 通过 Rust crate、Diesel 与 FFI 使用，不是适合初学者的 Dart／Drift 主线；
- CRDT、协作数据库、自托管和 Rust bridge 的复杂度远超同行者当前阶段；
- database/grid 是用户可编辑内容类型，不等于统计分析系统；
- `web/` 目录存在，但官方稳定交付证据重点仍在桌面和移动端，不能据此宣称 Flutter Web 已与其他端同等成熟；
- AGPL-3.0 使其更适合学习架构思想，而不是直接复制实现。

**结论：学习模块边界、同步状态与大型测试组织，不引入 Rust／CRDT 复杂度。**

## 10. 三个专项补充标杆

### 10.1 Open Food Facts Smooth App：大规模结构化外部数据与小型 Outbox

[Smooth App](https://github.com/openfoodfacts/smooth-app) 约 1,396 stars，持续活跃，使用 sqflite、Hive 和 Open Food Facts API。它有本地 product／list／operation DAO，也存在“先保存 transient operation，服务端接受后再删除”的模式。

值得学习：API client 与 App 分仓边界、离线 cache、贡献操作、数据质量展示。不能照搬：正式产品仍以 Android／iOS 为主，README 明确桌面只用于开发；它不是长期个人行为分析产品。

一手资料：

- [Smooth App README 与平台边界](https://github.com/openfoodfacts/smooth-app/blob/develop/README.md)
- [pubspec：sqflite 与 Hive](https://github.com/openfoodfacts/smooth-app/blob/develop/packages/smooth_app/pubspec.yaml)
- [Transient operation DAO](https://github.com/openfoodfacts/smooth-app/blob/develop/packages/smooth_app/lib/database/dao_transient_operation.dart)

### 10.2 LocalSend：跨平台打包与权限，不是数据分析参考

[LocalSend](https://github.com/localsend/localsend) 约 86,664 stars，Flutter 代码有移动、桌面和 Web 入口，但官方兼容／下载表重点列 Android、iOS、macOS、Windows、Linux。它非常适合研究网络权限、文件选择、系统托盘、分享扩展、不同安装包和平台 CI。

它没有与同行者可比的结构化记录、SQL 统计或业务同步，因此只应进入“平台工程”参考清单，不能因为 star 很高就提升为业务参考。

一手资料：[LocalSend README 与构建说明](https://github.com/localsend/localsend/blob/main/README.md)。

### 10.3 Ente：大规模加密同步与安全边界

[Ente](https://github.com/ente-io/ente) 约 28,123 stars，monorepo 包含 iOS、Android、Web、Linux、macOS、Windows 客户端以及 Go server。Flutter 主要用于移动 App；desktop 是 Electron／TypeScript，Web 也不是同一套 Flutter UI。

它适合研究端到端加密、上传队列、增量同步、后台任务和“本地／远端同步服务分开”的边界；不适合证明“Flutter 一套代码覆盖六平台”，也没有同行者所需的统计分析主线。

一手资料：

- [Ente README 与 monorepo 平台说明](https://github.com/ente-io/ente/blob/main/README.md)
- [Flutter Photos pubspec](https://github.com/ente-io/ente/blob/main/mobile/apps/photos/pubspec.yaml)
- [加密架构](https://github.com/ente-io/ente/blob/main/architecture/README.md)

## 11. 同行者应具体采用什么

### 11.1 采用“参考组合”，不采用 fork

建议把学习目标分成六条：

| 同行者问题 | 第一参考 | 采用的思想 | 明确不采用 |
| --- | --- | --- | --- |
| 自我问责与事实记录 | Lotti、Table Habit | 意图／事实分离、快速记录、趋势回顾 | 排行榜、把提醒变成人员考核 |
| 本地 SQL 与 migration | Cashew、Sossoldi | Drift schema snapshot、可读 SQL、版本升级 | 7,000 行数据库文件、动态拼用户输入 |
| 可靠同步 | Lotti、Smooth App | 本地事务＋持久 Outbox、claim／lease／ACK／retry | Matrix 全套、WebDAV 代替业务 Backend |
| 业务对象与报表 | Invoice Ninja | 筛选、date range、报表配置、响应式 CRUD | JSON state 充当事实数据库 |
| 大型模块组织 | AppFlowy、Lotti | feature-first、repository、state、UI 分层 | 为“看起来高级”提前加入 Rust／CRDT |
| 六平台交付 | Invoice Ninja、LocalSend | CI、能力矩阵、平台专用薄适配 | 用平台目录存在冒充正式支持 |

### 11.2 本地数据层

同行者继续使用 Drift／SQLite，但应结合候选项目的优点并修正其缺点：

- 表、migration、查询和 repository 分开；
- 每个 feature 只通过小而稳定的数据库接口访问数据；
- 重要聚合保留可读 SQL，不把统计全部改写成 Dart 循环；
- SQL 使用参数绑定，列名／排序字段只能来自受控白名单；
- 保存 Drift schema snapshot，并测试每一条升级路径；
- 统计查询用固定 fixture 测试分子、分母、缺失值、时区和匿名阈值；
- 禁止形成 Cashew 式跨页面 import 的巨型数据库文件。

### 11.3 同步层

采用 Lotti Outbox 的核心状态机，但保持同行者自己的安全边界：

```text
本地提交事务
  ├─ 写接触／修订／回答等正式事实
  └─ 写 sync_outbox
          ↓ claim + lease
      Backend HTTPS API
          ↓ token、capability、idempotency、transaction、audit
        ACK／conflict
          ↓
      本地标记已同步或需要处理
```

需要保留：持久化、原子 claim、lease、重试、幂等键、ACK 后完成、可见失败状态和诊断信息。

不需要第一阶段照搬：Matrix、端到端设备协商、CRDT、vector clock 全家桶和 WebDAV 文件同步。同行者是带组织权限与审计的共享业务系统，Backend 必须成为受信任的事务边界。

### 11.4 分析层

候选项目最常见的问题是把“统计”直接写进 Widget 或全局 selector。同行者应固定为：

```text
指标定义 → SQL 查询／后端聚合 → 结果模型 → 展示 ViewModel → 图表
```

每个指标还应明确：观察单位、时间范围、时区、分子、分母、排除项、数据截至时间、算法版本和隐私抑制。个人自我分析可在本地记录后即时更新；管理分析只使用后端接受的去身份化事实，并继续遵守至少 10 条有效接触记录等保护规则。

### 11.5 六平台

不再以“package 页面列了六个平台”或“仓库存在六个平台目录”作为完成标准。同行者每个平台都需要分别证明：

- build；
- 安全存储；
- 本地数据库与 migration；
- 离线写入与恢复；
- 同步；
- 认证 session 恢复；
- 响应式核心 UI；
- 平台受限能力的等价操作路径。

这也解释了为什么当前 Mac 上无法运行 Windows／Linux 真机，不等于可以把它们标为通过；应在相应 runner、虚拟机或设备上留下真实证据。

## 12. 不应照搬的做法

从候选项目中可以归纳出五条明确的反面约束：

1. **不要把功能丰富误认为模块清楚。**一个 7,000 多行文件仍然可以做出漂亮 App，但会让需求变化越来越危险。
2. **不要动态拼接用户输入到 SQL。**可读 SQL与参数绑定并不冲突。
3. **不要用备份同步冒充事务同步。**上传整库、JSON 或 WebDAV 对象无法自动提供组织权限、审计和幂等语义。
4. **不要用 Flutter 平台目录冒充正式支持。**必须有构建、运行与发布证据。
5. **不要因大项目很先进就复制其复杂度。**Rust、CRDT、E2EE 与 Matrix 都解决真实问题，但同行者第一阶段并不自动拥有那些问题。

## 13. 许可证边界

同行者当前使用 MIT License。公开源码只表示可以查看，不表示可以不看许可证直接复制。

| 项目 | 许可 | 对同行者的含义 |
| --- | --- | --- |
| Lotti | GPL-3.0 | 可学习思想；直接复制可能带来 GPL 义务 |
| Table Habit | Apache-2.0 | 条款相对宽松，但复制仍需保留许可／NOTICE 等义务 |
| Cashew | GPL-3.0 | 可学习 Drift 与产品设计；不作为直接源码来源 |
| Sossoldi | MIT | 相对容易复用，仍需保留版权与许可声明 |
| Invoice Ninja | 自定义 Attribution Assurance License | 需要逐条审阅署名与分发条件 |
| AppFlowy | AGPL-3.0 | 网络使用和分发可能触发强 copyleft 义务 |
| Smooth App、LocalSend | Apache-2.0 | 可研究实现，复用仍须履行许可证条件 |
| Ente | AGPL-3.0 | 主要学习安全／同步思想，不直接搬代码 |

本报告不是法律意见。对同行者最稳妥的做法是：记录参考来源，理解公开接口和设计取舍，再用本项目自己的命名、测试和 MIT 代码重新实现；需要复制实质代码时，先单独做许可证审查。

## 14. 最终建议

下一阶段不需要把任何候选 fork 进仓库。建议按以下顺序把研究转成自己的设计：

1. 用 Lotti 验证并细化同行者 `sync_outbox` 的 claim、lease、ACK、retry 和可观测性合同；
2. 用 Table Habit 校准“今日／个人分析”的温和自我问责体验；
3. 用 Cashew 和 Sossoldi 对照设计 Drift schema、migration 和可读统计 SQL，但强制 feature 边界与查询测试；
4. 用 Invoice Ninja 检查推广对象、项目、接触、问卷与报表的筛选／响应式交互；
5. 用 LocalSend／现有六平台认证 Spike 的方法建立平台验收矩阵；
6. 只有在真实冲突和协作需求证明必要时，才重新评估 AppFlowy／Ente 级别的复杂同步技术。

最重要的学习不是找到一个“完美源码”，而是辨认每个项目究竟解决了什么问题。同行者可以借它们的光，但仍要长成自己的骨架：Flutter 负责跨端体验，SQL 保存可核实的事实，Outbox 跨过不可靠的网络，统计则把事实转成理解，而不是转成人的排名。
