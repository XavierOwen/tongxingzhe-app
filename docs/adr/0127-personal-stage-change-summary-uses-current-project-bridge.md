# 个人阶段变更汇总使用当前项目的可信单 statement bridge

状态：**已接受（2026-08-13）**。

关联：Issue #136、Slice 6AE-1；ADR-0122、ADR-0125、ADR-0126；
`TARGET-016`、`ANALYTICS-015`、`PRIVACY-012`、`TEST-005`、`TEST-008`。

## 决定

个人阶段变更汇总只提供固定的读取入口：

```text
GET /v1/personal/relationship-stage-change-summary?from_utc=...&until_utc=...
```

Backend 先验证 Bearer token，再检查请求形状。请求必须只有一次 `from_utc` 和一次
`until_utc`，不带 body。时间必须是 UTC `Z`，可带一至六位小数；Backend 规范化到毫秒，
并要求 `from_utc < until_utc`。客户端不能提交 actor、workspace、project、metric、筛选条件
或历史 as-of。

成功响应只有一个 `result` envelope：

```json
{
  "result": {
    "contract_id": "personal_relationship_stage_change_summary_result_v1",
    "project_id": "uuid",
    "time_basis": "relationshipChangedAtUtc",
    "period": {
      "from_utc": "2030-01-01T00:00:00.000Z",
      "until_utc": "2030-01-08T00:00:00.000Z"
    },
    "data_cutoff_utc": "UTC timestamp",
    "authorized_at_utc": "UTC timestamp",
    "value": {
      "event_count": 5,
      "distinct_relationship_count": 4,
      "upward_count": 3,
      "downward_count": 2
    }
  }
}
```

`value` 只有四个非负安全整数。`event_count` 等于 `upward_count + downward_count`，
`distinct_relationship_count` 不大于 `event_count`。空期间仍返回同样的 envelope 和四个零。
Backend 拒绝额外或缺失键、非安全整数、错误时间、非法 project UUID、未来元数据和不满足这些
不变量的数据库结果。project 是否等于已锁定的当前项目由同一数据库 bridge 构造并在 fixture 中
验证；HTTP 和 Store 不另接收一个可能过期或可伪造的 project 值作比较。

PostgreSQL 的生产入口是
`app_data.read_personal_relationship_stage_change_summary_v1(text,text,timestamptz,timestamptz)`。
它是 `SECURITY DEFINER` 函数，固定 `search_path = pg_catalog, app_data`。runtime role 只有
该函数的 `EXECUTE` 权限；`PUBLIC`、runtime 和其他调用者不能直接读取 revision、对象、分配、
身份或当前项目来源表。

一次 bridge 调用在同一 PostgreSQL transaction 中完成授权和聚合准备。最终聚合使用一个
statement snapshot：

1. 用 issuer／subject 重新解析 active app user。
2. 对该用户的 `user_current_projects` 行加 `FOR UPDATE`，与项目切换写入形成冲突边界。
3. 验证 personal workspace 未删除，current project 属于该 workspace 且仍为 active。
4. 以一个 PostgreSQL statement snapshot 聚合 `changed_at` 位于 `[from_utc, until_utc)` 的 revision。

聚合只保留可信 actor、current workspace 和 current project，并要求 `old_stage IS NOT NULL`、
`old_stage <> new_stage`、`changed_fields` 含 `stage`、`reason_code <> 'project_entry'`。
`new_stage > old_stage` 计入 `upward`，反之计入 `downward`。同一关系的不同 revision 分别
计为事件，但 distinct 关系按对象×项目只计一次。查询不按当前 assignment、relationship
lifecycle 或 target `status = 'active'` 过滤。对象被匿名化或 assignment 已结束时，先前合格
的事件仍保留；匿名化产生的 lifecycle-only 或 note-only revision 不计入。

`data_cutoff_utc` 与 `authorized_at_utc` 都是外层 PostgreSQL bridge 调用 statement 开始时的可信
UTC 时刻。它们
表示本次读取的授权与数据截止，不是历史 as-of，也不是客户端收到响应的时间。项目切换、归档
或删除与读取并发时，锁保证结果只能是完整的旧项目 snapshot，或授权失败／完整的新项目
snapshot，不会混合两个项目。

阶段变更 revision 使用 `(changed_by_app_user_id, project_id, changed_at)` 的部分索引。check
脚本关闭顺序扫描后用 `EXPLAIN` 证明谓词可使用该索引；这是结构性检查，不是生产数据分布下的
成本计划预测。生产仍需正常 `ANALYZE` 与查询计划监测。

共享
[`relationship_stage_changes_v1.csv`](../../backend/database/fixtures/shared/relationship_stage_changes_v1.csv)
仍是跨层 synthetic 对账资料，主场景预期为 `5 / 4 / 3 / 2`；重复 revision
必须失败关闭。Docker fixture 还切换 current project，并验证结束 assignment 与匿名化 target 的
此前合格事件仍计入，空期间返回四个零，结果不含 PII。

## 错误合同

| 情况 | HTTP 响应 |
| --- | --- |
| 缺失或无效 Bearer，先于 query 判断 | `401 {"error":{"code":"unauthenticated"}}` |
| query 重复、缺失、额外、非 UTC、非法期间或 GET body | `400 invalid_personal_relationship_stage_change_summary_request` |
| inactive identity、无 current project、project 归档、workspace 删除或数据库 `42501` | `403 personal_relationship_stage_change_summary_forbidden` |
| bridge 缺失、数据库错误或返回合同解析失败 | `503 personal_relationship_stage_change_summary_unavailable` |

所有成功和错误响应都带 `Cache-Control: no-store`。响应不得包含 SQL 文本、对象或关系 ID、
revision、actor、reason、备注、姓名、联系方式、PII 或逐事件明细。

## 后果与边界

这项决定只交付 Backend HTTP、PostgreSQL bridge、索引、检查和 Docker 对账。它不新增 Flutter
gateway、页面、Drift 表、关系历史同步、Outbox、管理阶段变更报告、匿名阈值执行、历史
as-of、assignment-period 归因、区域、导出、更正版报告、warehouse 或删除／保留流程。
