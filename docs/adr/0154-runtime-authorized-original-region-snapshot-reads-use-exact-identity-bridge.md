# ADR-0154：Backend runtime 通过 exact identity bridge 读取原始区域快照

- 状态：已接受
- 日期：2026-08-22
- Slice：6BI
- Issue：#203
- 依赖：#201、0069
- Requirement：`ANALYTICS-044`、`PRIVACY-036`、`TEST-038`、`MANUAL-028`

## 背景

6BH 已在 private PostgreSQL 中提供 0069 authorized read。它接受内部 `app_user_id`，重新检查管理分析能力、项目授权和 0068 original-region
provenance，并追加 value-free audit。private function 不能直接给 Backend runtime 使用。

6BI 为后续 Backend consumer 提供窄 bridge。Backend 已经验证 external identity，但不应把内部用户 ID、capability、SessionContext 或任意 SQL
传给数据库。原始区域报告也必须保持自己的 6BD／6BG provenance 和 parser 边界，不能复用 channel、current-city 或 interest reader。

## 决定

新增 0070 runtime bridge：

```text
app_data.read_authorized_management_original_region_report_snapshot_v1(
  trusted_issuer text,
  trusted_subject text,
  requested_project_id uuid,
  requested_snapshot_id uuid
) returns jsonb
```

bridge 必须满足以下条件：

- 只用 exact `issuer + subject` 匹配现有且 active 的 identity。
- 不 trim、bootstrap、创建账号、创建个人上下文或读取 `SessionContext`。
- 使用 `SECURITY DEFINER` 和固定 `search_path = pg_catalog`。
- 只调用 `app_private.read_authorized_management_original_region_report_snapshot_v1(uuid, uuid, uuid)`。
- runtime 只有 bridge `EXECUTE`。它不能使用 `app_private` schema，也不能读取用户、identity、snapshot、attempt、claim 或 audit 表。
- bridge owner 与 0069 private reader owner 相同。`PUBLIC`、普通 app role、0066 reader、0068 writer 和其他 report-family 角色不能执行 bridge 或 private reader。

Backend adapter 接收已有 `VerifiedIdentity`，只执行一次固定参数化 SQL：

```sql
SELECT app_data.read_authorized_management_original_region_report_snapshot_v1(
  $1::text, $2::text, $3::uuid, $4::uuid
) AS access_result
```

strict parser 只接受 0069 的固定 envelope。`completed` 必须包含固定的 17 个 original-region report keys、同项目 ID、完整两期城市网格、连续
`cell_order`、安全整数和 `suppressed = null`。它还必须核对 selected source tree tuple、报告期间、截止点和 source change sequence。parser
拒绝额外字段、其他 report family、城市名称、坐标、来源记录、贡献者、contact、PII 和任何数据库错误文本。

parser 只验证两期使用相同、稳定排序的城市 ID 集合。城市 ID 是否完整属于所选 canonical tree 仍由 0069 调用的 6BD validator 权威判断；Backend 不复制区域树，也不把结构校验当成来源证明。

adapter 只把 SQLSTATE `42501` 映射为 typed `forbidden`。`not_found` 和 `untrusted_provenance` 不含 `protected_report`；其他 SQLSTATE 继续作为
内部错误向上抛出。bridge 和 adapter 不追加第二条 audit，也不把报告值写入日志。

## 后果与边界

0069 继续是唯一的授权、0068 provenance、6BD validator、撤权锁和 audit 来源。0070 只提供 exact identity 映射和调用边界，不复制授权语义。
它允许 Backend runtime 读取已授权的原始区域报告，同时保持 runtime 与 private schema 分离。

本 Slice 增加 0070 migration、structural check、rollback fixture、Backend typed store、strict parser 和真实 PostgreSQL integration。不增加 HTTP
route、Bearer／JWT 验证、目录／latest、导出、缓存、离线、Drift、同步、Flutter UI、replacement、删除、retention、warehouse、生产身份或六平台真人证据。
0069 已覆盖 private read 与撤权并发，因此本 Slice 不增加新的并发写入脚本。

Docker 和 integration 只提供 synthetic DB-only 证据。通过不能证明 HTTP、Flutter、生产 identity provider、真实账号或任何平台上的运行时行为。

## 验证

```bash
cd backend/server
npm ci --ignore-scripts
npm run check
npm test
cd ../..
./tool/run_postgres_tests_in_docker.sh
```

Docker runner 在源库自动发现 0070 migration、check 和 fixture，并运行原始区域 runtime integration、0069 read／revoke 并发和 checksum。
dump／restore 后，恢复库只重跑全部 check 和 numbered fixture，不重新执行 migration，也不重跑会提交 synthetic 行的并发脚本。
