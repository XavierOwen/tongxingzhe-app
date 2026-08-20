# ADR-0137：授权读取 current 城市快照使用独立 provenance

- 状态：已接受
- 日期：2026-08-20
- 切片：Slice 6AP
- Issue：#165
- 需求：`ANALYTICS-025`、`PRIVACY-017`、`TEST-019`

## 背景

Slice 6AO 把 current 城市报告候选固定为受保护快照。它使用独立的区域 release attempt 和 provenance，因而不能使用
渠道 v2 的授权读取函数。若把 current 城市快照当作普通渠道快照读取，区域 lineage 会被错误地解释为渠道 provenance。

读取还必须在授权撤销与快照查找之间保持明确的事务顺序，并留下不含报告格和 PII 的访问证据。

## 决策

0058 增加私有函数
`app_private.read_authorized_management_current_city_report_snapshot_v1(user_id, project_id, snapshot_id)`。
函数只接受显式的用户、项目和快照 UUID。它调用 0030 的授权解析器，重新检查
`view_anonymous_analytics`、组织成员关系、项目成员关系和项目状态。授权解析器使用共享 advisory lock，因此撤销与读取
按照数据库取得锁的顺序线性化。

完成读取必须同时满足以下条件：

- snapshot 属于请求的 project，且其报告是 `contact_sessions_by_current_city_two_periods@1`；
- 0057 release attempt 已通过 current-city 的 release family claim，状态是 `approved` 或 `approved_baseline`；
- attempt 的 `reason_codes` 是空 JSON 数组；
- attempt 与 snapshot 的报告 ID、版本、query fingerprint、release lineage、reporting time zone、`data_cutoff_utc`
  和 `previous_snapshot_id` 一致；
- attempt 和受保护文档的 target tree version 与 content fingerprint 一致；
- 数据库再次调用 0057 的 current-city document validator。

读取成功后，函数在同一事务追加一条 value-free、不可变的访问事件，再返回受保护报告。访问事件只保存授权 lineage、快照
ID、报告定义、截止点、target fingerprint、结果和稳定 reason code。未知快照、跨项目快照和 provenance 不可信的快照
不会返回报告正文。它们只留下最小的 `not_found` 或 `untrusted_provenance` 事件。

0058 不授予 runtime、PUBLIC 或区域维护角色对审计表、发布 attempt、snapshot 或读取函数的权限。它也不增加 HTTP、
Flutter、Drift、目录、导出、区域名称、几何数据或任意查询接口。

## 后果

current 城市读取有自己的 provenance 边界，不会误用 0032 的渠道 v2 合同。审计可以证明一次读取尝试及其授权依据，
但不能从审计事件恢复报告格。调用方必须已经知道要读取的 project 和 snapshot UUID；目录和发现流程仍属于未来切片。

## 验证

从仓库根目录运行完整 PostgreSQL Docker 套件：

```bash
./tool/run_postgres_tests_in_docker.sh
```

该套件会执行 0058 migration、结构检查、synthetic fixture、并发检查、checksum 和 dump/restore。专用测试库的顺序
见 `docs/manual/11-management-metrics-and-privacy.md` 的 Slice 6AP 小节。
