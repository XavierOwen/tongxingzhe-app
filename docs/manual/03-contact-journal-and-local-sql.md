# 第 3 章：匿名接触如何在 SQLite 中原子保存和统计

本章解释 Slice 1A 的本地数据地基。当前版本已经能保存并读取匿名接触，也能计算个人期间汇总。草稿界面、同步执行器和 Backend 仍在后续检查点中。

## 1. `ContactJournal` 为什么是一个深模块

页面不应分别写接触表、revision 表、答案表和 Outbox 表。任何页面遗漏一步，都会制造“界面说已保存，但同步命令不存在”一类不完整状态。

[`ContactJournal`](../../lib/features/contact_journal/contact_journal.dart) 提供三个公开行为：提交匿名接触、按 ID 读取当前接触、汇总一个人的期间接触。模块内部负责校验、ID、时间、四张表和数据库 transaction。调用者无需知道表的写入顺序。

构造函数接收真实 Drift 数据库、Clock 和 ID generator。测试使用内存 SQLite、固定时间和确定性 ID。这些替换点让失败场景可以重复出现，也不会把测试条件带入正式代码。

## 2. v6 的四张现代接触表

表结构定义在 [`contact_tables.dart`](../../lib/features/contact_journal/contact_tables.dart)。Drift 根据这些定义生成 SQLite schema 和类型安全的 Dart row。

| 表 | 保存的事实 | 不保存的内容 |
| --- | --- | --- |
| `db_contact_records` | 当前有效核心事实、归属、当前 revision | 姓名、电话、邮箱、私人备注 |
| `db_contact_revisions` | 每次提交或更正的完整核心快照 | 被覆盖后消失的历史 |
| `db_contact_answers` | 问题 ID、回答状态、答案类型和值 | 含义不明的任意 JSON |
| `db_sync_outbox` | 幂等命令、协议版本、状态和重试字段 | 身份令牌、日志用 PII |

`db_contact_records` 是当前投影，便于 Today 页面和个人分析直接查询。`db_contact_revisions` 是追加式历史。两者保留相同核心字段并非重复失误：投影负责读取速度，revision 负责审计和恢复历史解释。

## 3. 一次提交为何必须使用 transaction

一次合法提交按下列顺序执行：

1. 写入接触当前投影；
2. 写入 revision 1；
3. 写入本次问卷答案；
4. 写入唯一的 `contact.submit.v1` Outbox 命令；
5. 全部成功后返回本地保存回执。

SQLite transaction 具有原子性。第四步失败时，前三步也会回滚。测试会先占用一个 `command_id`，再故意重复使用该 ID。第二次提交在最后一步失败。随后使用相同 `contact_id` 重试仍能成功，这证明失败事务没有留下接触、revision 或答案残片。

这个测试使用红-绿流程。红色阶段先观察到错误行为或缺失接口。绿色阶段只加入足以满足该行为的实现。测试转绿后再整理重复代码。第 2 章说明完整流程和回归测试的作用。

## 4. 地点不是一个 nullable 字段

地点使用三个互斥类型：

| 状态 | 必须保存 | 禁止混同 |
| --- | --- | --- |
| 已解析 | 具体地点名称、最小规范区域 ID | 待解析、`N/A` |
| 待解析 | 合法经纬度、可选精度 | 已确定区域、`N/A` |
| `N/A` | 明确的不适用状态 | 定位失败、漏填 |

面对面接触不能选择 `N/A`。纯线上接触可以选择 `N/A`。混合渠道是否包含线下成分由表单明确询问，不能只凭渠道名称推断。

数据库也用 `CHECK` 约束保护这些组合。即使未来某个调用者绕过 Flutter 校验，SQLite 仍会拒绝无效地点。

## 5. 问卷状态和值为何分开

Slice 1A 先实现布尔题，但已经保存五种回答状态：已回答、未知、拒绝回答、不适用和未回答。只有“已回答”可以携带 `true` 或 `false`。其他状态必须没有布尔值。

因此，“不知道”不会被误算成“否”，`NULL` 也不会同时表示四种不同原因。同一 revision 对同一道题只能有一行答案。后续加入数字、日期和选择题时，每种类型使用受约束的值列。

## 6. 个人期间汇总 SQL

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

## 7. v5 如何升级到 v6

v6 使用 expand-contract。升级只新增现代表和索引，保留五张 legacy 表。旧宽表缺少可信的空间、项目、问卷和匿名语义，因此 migration 不把旧行猜成现代接触。

[`local_database_migration_test.dart`](../../test/data/local_database_migration_test.dart) 保存两类证据：当前 v6 快照可重建；v5 写入 synthetic 设置后升级到 v6，旧设置仍存在，现代表为空。机器可读快照位于 [`drift_schema_v6.json`](../../drift_schemas/drift_schema_v6.json)。

CI 会重新导出当前 schema 并与 v6 快照逐字比较。表、约束或索引变化后，如果开发者忘记更新 migration 和快照，检查会失败。

## 8. 当前边界

Slice 1A 只完成本地接触事实。`pending` Outbox 尚未领取、租赁或发送，个人汇总也没有接入正式页面。下一检查点将加入多草稿自动保存和提交表单，再接入 Today 与最近七日分析。
