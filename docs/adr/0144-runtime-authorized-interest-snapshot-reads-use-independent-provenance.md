# ADR-0144：管理兴趣快照 runtime 读取使用 exact identity bridge

- 状态：已接受
- 日期：2026-08-21
- Slice：6AY
- Issue：#183
- 依赖：#181、0063
- Requirement：`ANALYTICS-034`、`PRIVACY-026`、`TEST-028`、`MANUAL-018`

## 背景

6AX 已在 private PostgreSQL 中提供 0063 authorized read。它重新检查
`view_anonymous_analytics`、项目成员关系、0062 interest provenance 和 6AV 十格 validator，并在同一事务中写入
value-free read audit。0063 只接受内部 `app_user_id`，没有 runtime 权限。

0033 和 0059 已为 Backend 建立窄 bridge 模式。Backend 提供已验证的 external `issuer + subject`、显式 project UUID 和
snapshot UUID。数据库只映射现有 active identity，再调用一个 private read。runtime 不获得 `app_private` 使用权，也不直接读取
用户、identity、snapshot 或 audit 表。

6AY 将同一模式用于兴趣快照。它不复制 0063 的 private authorization，也不增加 HTTP、目录、导出或客户端查询能力。

## 决策

新增 0064 runtime bridge：

```text
app_data.read_authorized_management_interest_report_snapshot_v1(
  trusted_issuer text,
  trusted_subject text,
  requested_project_id uuid,
  requested_snapshot_id uuid
) returns jsonb
```

bridge 必须满足以下条件：

- 使用 exact `issuer + subject` 匹配 `app_data.external_identities`，目标 `app_user` 必须是 active。
- 不 trim、bootstrap、创建账号、创建个人上下文或读取 `SessionContext`。
- 使用 `SECURITY DEFINER` 和 `search_path = pg_catalog`。
- 只调用 `app_private.read_authorized_management_interest_report_snapshot_v1(uuid, uuid, uuid)`。
- runtime 只拥有 bridge `EXECUTE`。`PUBLIC`、普通 app role、interest reader、current-city writer 和区域角色没有 bridge 或 private read 权限。
- bridge owner 与 0063 private function owner 相同，且不能是 runtime、reader 或 release-writer。

Backend adapter 接收已有的 `VerifiedIdentity`，执行一次固定参数化 SQL：

```sql
SELECT app_data.read_authorized_management_interest_report_snapshot_v1(
  $1::text, $2::text, $3::uuid, $4::uuid
) AS access_result
```

adapter 使用 strict parser 检查：

- 0063 的固定 `access_contract_id`、root keys、requested/resolved snapshot、状态和 reason code；
- `completed` 的 6AX protected report、固定 `previous/current × interest_level 0..4` 十格、合法 count 和 `suppressed = null`；
- `not_found` 与 `untrusted_provenance` 不含 `protected_report`；
- project 与 snapshot 绑定、无额外 root/report key、无 PII、contact、contributor、来源或隐藏前值。

adapter 只把 SQLSTATE `42501` 映射为 typed `forbidden`。其他 SQLSTATE、数据库消息、SQL 和栈信息继续作为内部错误向上抛出。
HTTP wire mapping 不属于 6AY。bridge 或 adapter 不追加第二条 audit，也不把报告值写入日志。

## 影响

0063 继续是唯一的授权、provenance、validator、撤权锁和 audit 来源。0064 只提供身份映射和调用边界，因此不会产生第二套
授权语义。Backend runtime 可以得到已授权的受保护报告，但不能读取 private schema 或任意报告。

这项决策增加一个 DB migration、结构与 ACL check、synthetic fixture、Backend adapter 和真实 PostgreSQL integration。Docker runner
在源库自动发现 migration、check 和 fixture，显式运行第八条 Backend integration、既有 0063 read/revoke 并发，并验证 checksum。
dump/restore 后，恢复库只重跑全部 check 和 numbered fixture，不重新执行 migration，也不重跑会提交 synthetic 行的并发脚本。

这些测试只提供 DB-only synthetic 证据。它们不证明 HTTP、Flutter、目录、导出、生产 identity provider、真实账号或六平台运行时。

## 非范围

6AY 不包括：

- HTTP route、Bearer/JWT 验证、HTTP status 和 `Cache-Control`；
- 目录、分页、搜索、项目选择、导出、下载、分享、warehouse、retention、删除或更正；
- Flutter、Drift、缓存、离线、同步和 UI；
- 修改 0062、0063、6AV 或兴趣统计定义；
- 修改 generic channel 或 current-city bridge；
- 真实账号、真人平台、真机或 Apple Developer Program 证据。

## 验证

```bash
cd backend/server
npm ci --ignore-scripts
npm run check
npm test
cd ../..
./tool/run_postgres_tests_in_docker.sh
```

成功必须同时包含源库中的 0064 migration、check、fixture、interest runtime integration、0063 并发和 checksum，以及 dump/restore 后
恢复库中的全部 check 和 numbered fixture 证据。
