# ADR-0146：管理兴趣快照目录使用独立 provenance

- 状态：已接受
- 日期：2026-08-21
- 切片：Slice 6BA
- Issue：#187
- 需求：`ANALYTICS-036`、`PRIVACY-028`、`TEST-030`、`MANUAL-020`

## 背景

6AZ 已能按显式 `project_id + snapshot_id` 读取一份 6AW 管理兴趣快照。调用方还需要一个受限目录来发现同一项目中可读的
interest snapshot。已有 0035 channel directory 和 0060 current-city directory 使用不同的 release family、provenance 和审计合同，
不能作为兴趣目录。

目录只帮助调用方选择显式 snapshot ID。它不能替代 6AX 的读取授权和审计，也不能把排序第一项解释为 current、latest、最新有效或未被取代。

## 决策

Slice 6BA 增加独立的 interest directory 合同：

```text
app_private.list_authorized_management_interest_report_snapshots_v1(
  requested_app_user_id,
  requested_project_id
) -> jsonb

app_data.list_authorized_management_interest_report_snapshots_v1(
  trusted_issuer,
  trusted_subject,
  requested_project_id
) -> jsonb
```

private function 在同一事务中重新解析组织成员、项目成员、项目状态和 `view_anonymous_analytics`。它只列出 6AW interest release family
中 `approved`／`approved_baseline` 且 `reason_codes = []` 的快照。attempt 与 snapshot 必须在 project、report、version、query fingerprint、
release lineage、`reporting_time_zone`、`data_cutoff_utc`、previous snapshot 和 source watermark 上完全一致。channel、current-city、legacy、
blocked、跨项目、claim 不匹配和 lineage／metadata 漂移的记录被排除。

结果最多 20 项，按 `data_cutoff_utc DESC`、`released_at_utc DESC`、`snapshot_id DESC` 排序。数据库 envelope 固定包含
`access_contract_id`、`access_event_id`、`project_id` 和 `snapshots`；HTTP 成功正文不转发内部 `access_contract_id`。每项只包含
`snapshot_id`、`report_id`、`report_version`、`reporting_time_zone`、`data_cutoff_utc` 和 `released_at_utc`。空目录仍返回成功结果。

目录访问审计独立于 6AX 单份读取审计。它只保存最小授权 lineage、显式 project、访问时间、结果和返回数量，不保存 snapshot ID、目录 metadata、
protected report、cells、来源、贡献者或 PII。审计追加且不可变，不允许 UPDATE 或 DELETE。未认证或未授权请求不产生成功目录审计。

runtime bridge 使用 `SECURITY DEFINER` 和固定 `search_path = pg_catalog`，只做 exact `issuer + subject` 的 active identity 映射，再调用
private function。runtime 只拥有 bridge 的 `EXECUTE`，没有 `app_private` schema usage、directory／snapshot／attempt／claim 表权限，也不能
执行 private function。bridge owner 由受控数据库 owner 持有，不能是 runtime、普通 app role、区域维护或 release-writer。

Backend 提供固定 HTTP collection route：

```text
GET /v1/projects/:projectId/management-interest-report-snapshots
```

handler 先验证 Bearer token，再检查 project UUID、query、GET body 和 directory store。认证失败时，不因其他输入无效而改变 `401`。认证通过后，
handler 只调用专用 interest directory adapter，不使用 `SessionContext`、6AX/6AY 单份读取、generic channel reader、current-city reader、
private schema 或客户端查询。adapter Promise 完成后才发送响应。

HTTP 错误只使用稳定的 `400`、`403` 和 `503` code。被过滤的单个 snapshot 不产生可观察的 `404` 或 `409`。所有响应使用 JSON 和
`Cache-Control: no-store`。Backend parser 只接受固定 root/item keys、最多 20 项、唯一 ID、合法 RFC 3339 时间戳和固定降序；报告正文和敏感字段
失败关闭。

## 后果

兴趣目录和 channel/current-city 目录的 provenance、函数、审计和 ACL 保持分离。目录可以为后续调用方提供 snapshot ID，但不会放宽 6AX 的再次授权，
也不会将不同报告 family 的 metadata 混入同一结果。

固定上限和排序限制返回规模。排序只定义稳定顺序，不定义业务上的 current、latest 或取代关系。metadata-only 响应不能用于重算、相减或恢复隐藏值。

## 非范围

本 ADR 不增加 Flutter、Dart gateway、管理 consumer、导航上下文、分页、搜索、筛选、导出、下载、缓存、离线、同步、动态报告、快照创建／刷新／更正／
删除、retention、warehouse、生产调度、capability 授予／撤销、真实身份提供商、真实账号、六平台真机或 Apple Developer Program 验收。

## 验证

从仓库根目录运行完整 PostgreSQL Docker 套件：

```bash
./tool/run_postgres_tests_in_docker.sh
```

套件必须在源库包含 6BA migration、结构与 ACL check、synthetic fixture、独立并发脚本、Backend directory integration 和 checksum。
dump／restore 后，恢复库只重跑全部 check 和 numbered fixture，不重新执行 migration，也不重跑会提交 synthetic 行的并发脚本。

fixture 必须覆盖 approved／approved_baseline、空目录、20 项上限、固定排序、exact／unknown／inactive identity、撤权、跨项目、channel/current-city/
legacy、blocked、claim 或 metadata drift、value-free audit、审计不可变和直接 private access 拒绝。并发测试覆盖 directory-first 和
revoke-first。

Backend unit、route 和 composition 测试必须覆盖认证顺序、固定 collection path、query／GET body、strict metadata parser、稳定错误、错误脱敏、
Promise gate 和 `no-store`。这些 DB、HTTP 和 Backend 测试只证明各自合同，不证明 Flutter、导出、缓存、离线、生产身份或真人平台运行时。
