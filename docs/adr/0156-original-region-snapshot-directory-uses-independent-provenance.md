# ADR-0156：原始区域快照目录使用独立 provenance

- 状态：已接受
- 日期：2026-08-25
- Slice：6BK
- Issue：[#207](https://github.com/XavierOwen/tongxingzhe-app/issues/207)
- 依赖：[#199](https://github.com/XavierOwen/tongxingzhe-app/issues/199)、[#201](https://github.com/XavierOwen/tongxingzhe-app/issues/201)、[#203](https://github.com/XavierOwen/tongxingzhe-app/issues/203)、[#205](https://github.com/XavierOwen/tongxingzhe-app/issues/205)
- Requirement：`ANALYTICS-046`、`PRIVACY-038`、`TEST-040`、`MANUAL-030`

## 决定

6BK 为 6BG 原始区域快照增加专用的 metadata-only 目录。目录按显式 project UUID 返回最多 20 项，固定按 `data_cutoff_utc DESC`、`released_at_utc DESC`、`snapshot_id DESC` 排序。第一项只表示排序结果，不表示 current、latest、最新有效或未被取代。

数据库每次调用重新验证 active identity、组织成员、项目成员、项目状态和 `view_anonymous_analytics`。
它只接受 original-region release family 中 provenance 完整的 `approved_baseline` 或 `approved` 快照。
数据库再次核对 project、report identity、query fingerprint、release lineage、时区 revision、cutoff、previous pointer、source watermark 和 source tree tuple。
generic、channel、current-city、interest、legacy、blocked、跨项目或漂移 provenance 不进入目录。

## 固定合同

private function 和 runtime bridge 分别为：

```text
app_private.list_authorized_management_original_region_report_snapshots_v1(uuid, uuid)
app_data.list_authorized_management_original_region_report_snapshots_v1(text, text, uuid)
```

runtime bridge 只映射完全匹配且 active 的 external `issuer + subject`。它不 trim、不 bootstrap，也不接受内部用户 ID、capability、时区、cutoff、source tuple、筛选或 SQL。`tongxingzhe_runtime` 只有 bridge `EXECUTE`，不能使用 `app_private` 或读取 private 表。

HTTP collection route 固定为：

```text
GET /v1/projects/:projectId/management-original-region-report-snapshots
```

handler 先认证，再检查 project UUID、query、GET body 和专用 store。成功 HTTP 根对象只有 `access_event_id`、`project_id` 和 `snapshots`。每项只有 `snapshot_id`、`report_id`、`report_version`、`reporting_time_zone`、`data_cutoff_utc` 和 `released_at_utc`。数据库内部 envelope 另有 `access_contract_id`，该字段不进入 HTTP。

## 隐私与审计

目录不返回 `protected_report`、cells、隐藏前值、source tree tuple、来源、贡献者、contact、区域名称、坐标或 PII。每次成功调用追加一条 original-region directory 专用 audit。审计只保存授权 lineage、project、访问时间、完成状态和 0 至 20 的返回数量；不保存 snapshot ID、报告 metadata、source tuple 或报告内容。audit 追加不可变，普通角色不能直接插入、修改或删除。

空目录是成功结果，返回 `200` 和空数组，并记录返回数量 0。认证失败、授权失败、数据库错误或返回合同错误不会伪造成功 audit。所有 HTTP 响应使用 JSON 与 `Cache-Control: no-store`。

## 边界与验证

本决定不增加 Flutter gateway、UI、导出、缓存、离线、Drift、分页、搜索、筛选、自动 latest、snapshot 发布、更正、删除、retention、production identity 或六平台真人运行时证据。

0071 structural check、rollback fixture、并发脚本和 PostgreSQL integration 验证 provenance、授权撤回、20 项上限、稳定排序、value-free audit 和最小 ACL。
Backend unit、route 和 composition 测试验证 strict parser、认证顺序和固定 wire。
它们也检查错误映射、Promise gate 和 production wiring。
Docker dump/restore 不重跑会提交 synthetic 行的并发脚本。
通过结果只证明 synthetic PostgreSQL、runtime bridge 和 Backend HTTP 合同。
