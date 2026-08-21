# ADR-0140：current 城市快照目录使用独立 provenance

- 状态：已接受
- 日期：2026-08-20
- 切片：Slice 6AS
- Issue：#171
- 需求：`ANALYTICS-028`、`PRIVACY-020`、`TEST-022`

## 背景

6AR 已能按显式 `project_id + snapshot_id` 读取一份 current 城市快照。调用方还需要一个受限目录来发现同一项目中可读的
current 城市快照。现有 0035 目录只承认渠道 v2 provenance，不能把它当作区域快照目录。目录也不能把“第一项”或最新
截止点解释为当前有效报告。

目录读取必须重新检查 `view_anonymous_analytics`，并沿用 6AP 的 current-city release family claim、approved provenance、
report／version、query fingerprint、lineage、可信报告时区、截止点、previous snapshot 和 target tree tuple 对齐规则。
它只能返回导航所需的快照元数据，不能把报告格、城市名称或区域来源带到 Backend。

## 决策

Slice 6AS 增加独立的 current-city 目录 DB 合同：

```text
app_private.list_authorized_management_current_city_report_snapshots_v1(
  requested_app_user_id,
  requested_project_id
) -> jsonb

app_data.list_authorized_management_current_city_report_snapshots_v1(
  trusted_issuer,
  trusted_subject,
  requested_project_id
) -> jsonb
```

private 函数在同一事务中重新解析组织成员、项目成员、项目状态和
`view_anonymous_analytics`。它只列出 0057 current-city release family 中通过 0057 validator 的
`approved`／`approved_baseline` 快照，且 `reason_codes = []`。attempt 与 snapshot 的 project、report、version、query
fingerprint、release lineage、`reporting_time_zone`、`data_cutoff_utc`、`previous_snapshot_id` 和 target tree tuple 必须
一致。legacy channel snapshot、blocked／unavailable attempt、跨项目记录、tuple 漂移和其他 provenance 失败关闭，并从
目录中排除。

结果最多 20 项，按 `data_cutoff_utc DESC`、`released_at_utc DESC`、`snapshot_id DESC` 排序。每项只含
`snapshot_id`、`report_id`、`report_version`、`reporting_time_zone`、`data_cutoff_utc` 和 `released_at_utc`。根对象含固定
`access_contract_id`、`access_event_id`、`project_id` 和 `snapshots`。空目录仍是成功结果，并记录返回数量为 0 的访问审计。
目录访问审计追加且不可变，只保存授权 lineage、project、访问时刻、结果和返回数量，不保存 snapshot ID、报告元数据、
报告格、来源、贡献者、城市名称、坐标或 PII。

runtime bridge 使用 `SECURITY DEFINER` 和 `SET search_path = pg_catalog`，只做 exact `issuer + subject` 的 active
identity 映射，再调用上述 private 函数。runtime 只拥有 bridge 的 `EXECUTE`，没有 `app_private` schema usage、私有表、
identity／用户表或 private function 权限。bridge 不调用 0035 generic directory、6AP snapshot read、渠道 reader、
SessionContext、bootstrap、目录之外的查询或导出。bridge owner 由受控数据库 owner 持有，不是 runtime、区域维护或
release writer。

Backend 提供固定 HTTP 目录入口：

```text
GET /v1/projects/:projectId/management-current-city-report-snapshots
```

handler 先验证 Bearer token，再检查 project UUID、query、GET body 和 adapter。认证失败时，不因其他输入、store 状态或
provenance 结果改变 `401`。认证通过后只传递 verified issuer、subject 和显式 project UUID。成功响应保留 DB 目录的
`access_event_id`、`project_id` 和 metadata-only `snapshots`。handler 等待 adapter Promise 完成后再写响应，所有响应
使用 JSON `Content-Type` 与 `Cache-Control: no-store`。

HTTP 只接受无 query、无 GET body 的固定 path。输入错误返回
`400 invalid_management_current_city_report_snapshot_directory_request`，授权拒绝返回
`403 management_current_city_report_snapshot_directory_forbidden`，adapter、数据库、返回合同或未知 SQLSTATE 异常返回
`503 management_current_city_report_snapshot_directory_unavailable`。不可信或 legacy provenance 不进入列表，因此不另
建可观察的逐 snapshot `404`／`409` 响应。

## 后果

current 城市目录与渠道 v2 目录的 provenance、函数和审计边界分开。目录可以帮助客户端选择显式 snapshot，但不替代 6AP
的读取授权、访问审计或 6AR 的 detail route。固定上限和排序限制了返回规模，且不赋予第一项“当前”“最新”或“取代”语义。

## 非范围

本 ADR 不增加 Flutter／Drift 页面、导航上下文授权、分页、搜索、筛选、动态报告、导出、下载、缓存、离线、同步、快照
创建／刷新／更正／删除、retention、warehouse、区域发布、授权授予／撤销、六平台真机验收或生产 identity provider。

## 验证

从仓库根目录运行完整 PostgreSQL Docker 套件。套件必须包含 6AS migration、结构 check、synthetic fixture、独立并发
脚本、Backend adapter integration、checksum 和 dump／restore。

```bash
./tool/run_postgres_tests_in_docker.sh
```

HTTP 的最小验证在 `backend/server`：

```bash
npm run check
npm test
```

DB fixture 必须覆盖 approved／approved_baseline、legacy channel、blocked／unavailable、tuple 漂移、跨项目、未知／停用
identity、撤权、空目录、20 项上限、稳定排序、value-free audit、runtime ACL 和直接 private access 拒绝。HTTP 测试还要
覆盖认证顺序、固定 path、query／GET body、稳定错误、Promise gate、严格 metadata parser 和 `no-store`。
