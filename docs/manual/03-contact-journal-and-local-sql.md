# 第 3 章：接触草稿如何在 SQLite 中保存、提交和统计

本章解释 Slice 1 的本地数据模块。当前代码可以保存多份私有草稿、在本人设备间同步账号私有草稿、保留离线冲突副本，并把完整草稿原子提交为匿名接触。

## 1. `ContactJournal` 为什么是一个深模块

页面不应分别写草稿、接触、revision、答案和 Outbox 表。任何页面遗漏一步，都会产生不完整状态。

[`ContactJournal`](../../lib/features/contact_journal/contact_journal.dart) 隐藏表的写入顺序。调用者只表达以下行为：

- 保存或更新当前草稿快照；
- 列出本人尚未放弃的草稿；
- 放弃草稿，或在期限内撤销放弃；
- 把完整草稿正式提交；
- 读取已提交接触和个人期间汇总。

公开入口保留在 `contact_journal.dart`。草稿生命周期的实现放在 [`contact_draft_operations.dart`](../../lib/features/contact_journal/contact_draft_operations.dart)，并通过 Dart 的 `part` 属于同一个 library。这样可以缩短单个文件，同时让草稿代码继续访问模块私有实现；它没有增加第二套数据库接口。

模块接收真实 Drift 数据库、Clock 和 ID generator。测试使用真实 SQLite、固定时间和确定性 ID。测试可以稳定重现失败，不把测试条件带入正式代码。

## 2. v9 的十一张现代接触、同步与区域表

表结构定义在 [`contact_tables.dart`](../../lib/features/contact_journal/contact_tables.dart)。Drift 根据这些定义生成 SQLite schema 和类型安全的 Dart row。

| 表 | 保存的事实 | 不保存的内容 |
| --- | --- | --- |
| `db_contact_drafts` | 创建者、项目、问卷版本、未完成核心字段、同步模式、放弃期限 | 姓名、电话、邮箱 |
| `db_contact_draft_answers` | 草稿中的类型化问卷答案 | 已提交接触答案 |
| `db_contact_records` | 当前有效核心事实、归属、当前 revision | 草稿、PII、私人备注 |
| `db_contact_revisions` | 每次提交或更正的完整核心快照 | 被覆盖后消失的历史 |
| `db_contact_answers` | 问题 ID、回答状态、答案类型和值 | 含义不明的任意 JSON |
| `db_sync_outbox` | 命令、协议版本、状态和重试字段 | 身份令牌、日志用 PII |
| `db_sync_drainer_leases` | 跨执行器互斥的全局租约 | 远端锁、用户身份 |
| `db_sync_scopes` | 每个用户和项目的拉取 cursor、最后成功和失败 | command payload、token |
| `db_canonical_region_versions` | 带版本、唯一父级的规范区域节点和属性 | 项目私有层级、接触事实 |
| `db_contact_region_assignments` | 已提交接触到最小区域节点的真实外键 | 重复保存的上级区域路径 |
| `db_draft_region_assignments` | 草稿到最小区域节点的真实外键 | 未经解析的坐标 |

草稿答案与正式答案分表保存。统计 SQL 只查询 `db_contact_records`，因此草稿不会增加接触场次、触达人数或兴趣分布。

## 3. 空白页和草稿的区别

项目、空间和问卷版本是页面上下文。它们本身不代表用户已经开始记录。`saveDraft` 只有在出现下列内容之一时才创建 ID：

- 实际发生时间；
- 渠道或非空渠道明细；
- 地点；
- 触达人数；
- 单次兴趣；
- 问卷答案；
- 用户明确选择“仅本设备”。

这条规则防止仅打开页面就产生空草稿。创建后的每次保存会更新原草稿，不生成第二个 ID。创建时间保持不变，最后修改时间向前推进。

草稿列表按创建者过滤，并按最后修改时间排序。同一用户可以保留不同项目和问卷版本的草稿。默认 `account_private` 会通过私有同步命令送到本人的其他设备；用户可以改为 `device_only`，此时未提交内容不离开本机。两种模式都不让管理员看到草稿。

每次本地保存递增 `local_revision`，服务器接受后更新 `server_revision`。另一台设备的版本与本机尚未上传的修改同时出现时，SyncEngine 不采用“最后写入覆盖”。它安装服务器确认的原草稿，并把本机分叉保存为 `device_only` 的草稿冲突副本。冲突副本不能直接提交，使用者必须对照后手动合并需要的内容。

Native Drift 读取日期时可能使用设备本地时区表示同一瞬间。`ContactJournal` 在返回草稿前统一调用 `toUtc()`。这样，调用者不会把时区表现差异误当成时间变化。

## 4. 草稿为何允许不完整

草稿保存填写过程，所以时间、渠道、地点、触达人数和兴趣都可以暂缺。已经存在的值仍受类型和数据库 `CHECK` 约束保护。例如，触达人数不能小于一，兴趣只能是 `0–4`，经纬度必须在有效范围内。

草稿列表的完成度使用五组稳定核心事实：

1. UTC 发生时间和 IANA 时区；
2. 渠道，以及“其他直接渠道”所需的明细；
3. 合法地点；
4. 正数触达人数；
5. `0–4` 单次兴趣。

完成度不是已填列数。面对面渠道配 `N/A` 地点不算地点完成，其他直接渠道缺少明细也不算渠道完成。正式提交会再次运行完整校验。

## 5. 自动保存为何需要 transaction

一份草稿包含主表行和零到多条问卷答案。创建或更新时，`ContactJournal` 在一个 SQLite transaction 内保存两部分。更新使用当前表单快照替换旧答案。

如果答案写入失败，主表变化也会回滚。UI 只有在 `saveDraft` 返回后才能显示“已保存”。正式表单在输入停止 350 毫秒后保存，在页面返回或 App 进入后台时立即排空待保存编辑。

文件型 SQLite 测试会执行以下步骤：

1. 保存同一用户在两个项目中的草稿；
2. 关闭数据库，模拟 App 退出；
3. 重新打开同一文件；
4. 核对两份草稿仍存在；
5. 核对另一用户的草稿不在本人的列表中。

这个测试证明数据库持久化路径成立。它不能替代每个平台的进程重启测试。

## 6. 放弃和短时撤销如何工作

已有内容的草稿不会立即物理删除。`abandonDraft` 写入放弃时间和十秒撤销期限，然后从正常列表隐藏草稿。`undoAbandonDraft` 在期限内清除这两个字段并恢复草稿。

撤销期限保存在 SQLite，不只存在于 Snackbar 内存。App 在期限内中断时，恢复逻辑仍有事实可读。期限过后，草稿保持隐藏。后续清理任务可以删除过期行，但不得影响撤销窗口。

## 7. 正式提交为何必须原子转换

一次合法草稿提交按下列顺序执行：

1. 读取创建者拥有的活动草稿及其答案；
2. 执行完整接触校验；
3. 写入接触当前投影；
4. 写入 revision 1；
5. 写入正式问卷答案；
6. 写入唯一的 `contact.submit.v1` Outbox 命令；
7. 删除草稿答案和草稿主表行；
8. transaction 成功后返回本地保存回执。

第六步失败时，SQLite 会回滚第三步到第七步。测试先占用一个 `command_id`，再故意重复该 ID。提交失败后，正式接触不存在，原草稿仍在。更换命令 ID 后重试可以成功。

这就是原子性：接触事实、revision、答案、同步命令和草稿状态只有两种结果，全部成功或全部不变。

## 8. 红-绿回归测试在这里做了什么

每个新行为先写公开接口测试。测试第一次运行时因接口缺失或行为不完整而失败，这一步叫红色阶段。随后只加入满足该行为的实现，测试通过后进入绿色阶段。

本章对应的测试依次覆盖：

- 空白页不创建草稿；
- 首次有意义输入创建草稿；
- 自动保存更新原 ID；
- 全部核心字段和答案可恢复；
- 文件库关闭后重开仍有多份私有草稿；
- 完整草稿可原子提交；
- Outbox 失败时保留草稿并回滚正式表；
- 放弃、期限内撤销和过期拒绝；
- 不完整草稿不进入个人统计。

测试只经过 `ContactJournal` 公开接口。测试不直接查询私有表来证明业务结果，因此表名或内部写入顺序变化时，行为测试仍然有效。第 2 章解释完整的红-绿流程和回归测试。

## 9. 地点不是一个 nullable 字段

正式接触地点使用三个互斥类型：

| 状态 | 必须保存 | 禁止混同 |
| --- | --- | --- |
| 已解析 | 具体地点名称、最小规范区域 ID | 待解析、`N/A` |
| 待解析 | 合法经纬度、可选精度 | 已确定区域、`N/A` |
| `N/A` | 明确的不适用状态 | 定位失败、漏填 |

面对面接触不能选择 `N/A`。纯线上接触可以选择 `N/A`。数据库也用 `CHECK` 约束保护地点内部组合。

取得坐标后，[`ContactRegionResolver`](../../lib/regions/contact_region_resolver.dart) 请求自有 Backend 匹配平台发布的当前区域树。命中时，客户端先通过 [`RegionCatalog`](../../lib/regions/region_catalog.dart) 原子安装从根到最小节点的父链，并确认父链中存在城市，然后才保存已解析地点。断网、身份失效、响应不一致、父链无效或没有边界命中时，解析器返回原来的待解析坐标。它不会删除坐标，也不会把失败伪装成 `N/A`。

本地数据库只保存规范节点和接触／草稿的最小节点外键，不复制 PostgreSQL 的边界多边形。边界由平台统一发布和查询；Flutter 收到经过 Backend 限定的父链后，仍在自己的写入边界重新验证树结构。

## 10. 问卷状态和值为何分开

当前版本先实现布尔题，并保存五种回答状态：已回答、未知、拒绝回答、不适用和未回答。只有“已回答”可以携带 `true` 或 `false`。其他状态必须没有布尔值。

因此，“不知道”不会被误算成“否”。`NULL` 也不会同时表示四种原因。同一草稿或 revision 对同一道题只能有一行答案。

## 11. 个人期间汇总 SQL

正式查询位于 [`contact_queries.drift`](../../lib/features/contact_journal/contact_queries.drift)。Drift 在构建时检查表名、列名、参数类型和返回类型。查询使用 UTC 半开区间 `[fromUtc, untilUtc)`。相邻两周共用一个边界时，同一接触不会被计算两次。

以下代码是教学用简化示例。正式查询还返回五档兴趣分布和未完成同步的接触数。

```sql
-- 简化示例，不是正式查询的手工副本。
SELECT
  COUNT(*) AS contact_session_count,
  COALESCE(SUM(reach_count), 0) AS reach_count
FROM db_contact_records
WHERE app_user_id = :app_user_id
  AND workspace_id = :workspace_id
  AND project_id = :project_id
  AND occurred_at_utc >= :from_utc
  AND occurred_at_utc < :until_utc
  AND lifecycle_status = 'active';
```

设时间窗内有效接触集合为 `C`：

- 接触场次是 `|C|`；
- 触达人数是每条接触 `reach_count` 的总和；
- 兴趣等级 `k` 的数量是满足 `interest_level = k` 的接触数，其中 `k ∈ {0,1,2,3,4}`；
- 五档数量之和应等于接触场次。

兴趣是有序等级。核心分析先返回五档分布，不计算平均值。若以后显示兴趣算术指数，页面必须说明它额外假设相邻等级距离相等。

## 12. v5、v6 和 v8 如何升级到 v9

v6 使用 expand-contract 新增已提交接触、revision、答案和 Outbox 表。v7 新增草稿和草稿答案表。v8 新增同步执行租约和按可信范围保存的 cursor。v9 新增草稿同步版本、Outbox 可信范围和三张区域表。升级不删除五张 legacy 表，也不从旧宽表猜测现代接触或区域归属。

v9 的新列参与 `CHECK` 约束，不能只运行 SQLite `ADD COLUMN`。migration 使用 Drift `TableMigration` 重建受影响的表并复制旧数据。它先检查列是否已经存在，因此从 v5 或 v6 跨多版升级时，不会因较早步骤按当前定义建表而重复添加同名列。

[`local_database_migration_test.dart`](../../test/data/local_database_migration_test.dart) 保存四类证据：

- 当前 v9 快照可以独立重建；
- v8 的 synthetic 草稿升级后仍存在，并得到初始本机和服务器 revision；
- v6 的 synthetic 已提交接触升级后仍存在；
- v5 的 synthetic 设置升级后仍存在，无法证明的现代区域表保持为空。

机器可读快照位于 [`drift_schema_v9.json`](../../drift_schemas/drift_schema_v9.json)。CI 会重新导出当前 schema 并逐字比较，也会重新生成所有 migration 测试辅助代码。

## 13. 当前边界

v9 完成草稿、正式接触、跨设备私有草稿、冲突副本、版本化区域外键、本机同步状态和远端 cursor 的本地数据行为。本地数据库应用层加密仍属后续切片。同步状态机和 Backend SQL 见 [第 6 章](06-persistent-sync-and-backend-sql.md)。
