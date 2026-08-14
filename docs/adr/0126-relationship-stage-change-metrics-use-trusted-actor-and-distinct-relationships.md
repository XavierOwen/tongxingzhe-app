# 阶段变更指标使用可信操作者与去重项目关系

状态：**已接受（2026-08-13）**。

关联：Issue #134、Slice 6AE-0；ADR-0061、ADR-0070、ADR-0122；
`TARGET-009`、`TARGET-016`、`ANALYTICS-007`、`ANALYTICS-015`、
`PRIVACY-012`、`TEST-005`、`TEST-008`。

## 决定

指标目录固定注册以下三个版本化指标：

| 指标 | 个人统计单位 | 计算合同 |
| --- | --- | --- |
| `relationship_stage_change_events@1` | 阶段变更事件 | 统计期间内合格 revision 的事件数 |
| `relationship_stage_change_direction_distribution@1` | 阶段变更事件 | 按固定 `upward`、`downward` 顺序计数；两格之和等于事件数 |
| `relationships_with_stage_change@1` | 去重“推广对象 × 推广项目”关系 | 统计期间内至少有一条合格事件的不同项目关系数 |

三个指标都使用 revision 的 `changed_at` 作为时间依据，`MetricTimeBasis` 固定为
`relationshipChangedAtUtc`。查询期间是 UTC 半开区间 `[from_utc, until_utc)`，包含左边界，
不包含右边界。`changed_at = until_utc` 的事件进入
下一期间；查询不能改用设备时区、录入时间、当前快照时刻或当前分配区间。

个人结果的 actor scope 固定为可信当前用户：Backend 从已验证外部身份取得 `app_user_id`，
并从可信上下文取得 workspace 与 project；数据库只计 `changed_by_app_user_id` 等于该用户的
revision。客户端不能提交、覆盖或在 query 中替换 actor、workspace 或 project。当前分配结束
不会移除该用户在结束前执行、且发生在目标 UTC 期间内的合格事件。

一个 revision 只有在 `old_stage` 非空、`old_stage <> new_stage` 且 `changed_fields` 包含
`stage` 时才形成事件。初始 `project_entry`、只改变 lifecycle 或备注的 revision、同阶段
revision 和无效输入均排除。
`new_stage > old_stage` 是 `upward`；`new_stage < old_stage` 是 `downward`。同一关系的
不同 revision 作为不同事件计数，但在 `relationships_with_stage_change@1` 中按
`(promotion_target_id, project_id)` 去重。同一 revision 的重复输入必须失败关闭。

未来管理分析若使用这组指标，`relationship_stage_change_events@1` 和方向事件分布的
`managementPrivacyUnit` 固定为不同的“对象 × 项目”关系。匿名阈值 `k=10` 必须由至少十个
不同关系满足，不能用同一关系的重复事件达到阈值；既有贡献者保护和互补隐藏继续适用。这个
决定不建立管理阶段变更报告或管理 API。

## 后果与边界

个人页面可以同时显示事件数、`upward`／`downward` 分布和去重关系数，并能解释为什么两个
数量可能不同。事件仍代表历史事实，不能被当前关系阶段快照或结束分配改写。历史某一时点的
关系状态重建、按历史分配区间归因、报告快照、更正版报告、导出、warehouse 和删除／保留流程
不属于本决定。

跨层对账使用不含 PII 的共享 fixture
[`relationship_stage_changes_v1.csv`](../../backend/database/fixtures/shared/relationship_stage_changes_v1.csv)。
fixture 必须覆盖本人／他人、其他项目、期间前后边界、结束当前分配、`project_entry`、
lifecycle-only、同阶段、上升、下降、同一关系多次变更和重复 revision。Dart 与 PostgreSQL
独立重算事件数、去重关系数和方向数，主场景预期为 `5` 个事件、`4` 个不同关系、`3` 个上升
和 `2` 个下降。结果必须一致；错误输入失败关闭。

本决定不新增生产 HTTP endpoint、Flutter 页面、Drift 表、关系历史同步、Outbox 或新的关系事实。
