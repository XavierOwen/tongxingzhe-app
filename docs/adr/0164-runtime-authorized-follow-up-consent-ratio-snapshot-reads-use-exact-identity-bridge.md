# ADR-0164：Backend runtime 通过 exact identity bridge 读取后续联系同意占比快照

- 状态：已接受
- 日期：2026-08-25
- Slice：6BS
- Issue：#223
- 依赖：#221、0076
- Requirement：`ANALYTICS-054`、`PRIVACY-046`、`TEST-048`、`MANUAL-038`
- 相关决定：ADR-0161、ADR-0162、ADR-0163

## 背景

6BR 已在 private PostgreSQL 中提供 0076 authorized read。它接受内部 `app_user_id`，重新检查管理分析能力和项目授权，验证 0075 consent-ratio provenance，并追加 value-free audit。Backend runtime 不能直接执行这个 private function。

后续 Backend consumer 需要一个固定入口，把已经验证的 external identity 映射为现有内部用户。该入口不能接收内部用户 ID、capability、`SessionContext`、任意筛选或 SQL，也不能复制 6BR 的授权和隐私逻辑。

## 决定

新增 0077 runtime bridge：

```text
app_data.read_authorized_management_follow_up_consent_report_snapshot_v1(
  trusted_issuer text,
  trusted_subject text,
  requested_project_id uuid,
  requested_snapshot_id uuid
) returns jsonb
```

bridge 只用 exact `issuer + subject` 匹配现有 active identity。输入长度检查可以使用 `btrim`，身份匹配不能 trim 或 normalize。未知、停用或删除中的 identity 失败关闭；函数不 bootstrap、创建账号或创建个人上下文。

函数使用 `SECURITY DEFINER`、`VOLATILE` 和固定 `search_path = pg_catalog`。owner 与 0076 private reader 一致。它只调用一次 `app_private.read_authorized_management_follow_up_consent_report_snapshot_v1(uuid, uuid, uuid)`。授权、provenance、strict validator、撤权锁和访问审计仍由 6BR 负责。

`tongxingzhe_runtime` 只拥有 bridge `EXECUTE`。它不能使用 `app_private`、执行 0076 private reader，或读取用户、identity、snapshot、attempt、claim 和 audit 表。`PUBLIC`、普通 app role 和其他报告 reader／writer 不能执行 bridge。

Backend adapter 只执行一次固定参数化 SQL，并传递 verified identity 与显式 project／snapshot UUID。strict parser 只接受 0076 固定 envelope 和 `contact_target_follow_up_consent_ratio_two_periods@1` protected report。它验证 exact keys、项目与快照绑定、相邻完整期间、两个 period result、ratio、三项 coverage、连续顺序、安全整数和 `suppressed = null`。

额外字段、其他报告 family、PII、contact、target、contributor、source 和隐藏前值均失败关闭。

adapter 只把 SQLSTATE `42501` 映射为 typed `forbidden`。其他数据库错误和 parser 错误保持内部失败，不返回数据库消息。

## 后果与边界

0076 继续是唯一的授权、0075 provenance、6BQ validator、撤权锁和 audit 来源。0077 只提供 exact identity 映射和 runtime 调用边界，不增加第二套审计，也不重算或修改报告。

本 Slice 增加 migration、structural check、rollback fixture、Backend typed store、strict parser 和真实 PostgreSQL integration。它不增加 HTTP route、Bearer／JWT 验证、目录、Flutter、Drift、导出、缓存、离线、同步、replacement、删除、retention、warehouse、生产身份或真人平台证据。

0076 已覆盖 private read／revoke 并发，因此不增加重复的并发脚本。

## 验证

```bash
cd backend/server
npm ci --ignore-scripts
npm run check
npm test
cd ../..
./tool/run_postgres_tests_in_docker.sh
```

Docker runner 自动发现 0077 migration、check 和 fixture，并显式运行 Backend integration。它继续运行 0076 read／revoke 并发、checksum 和 dump／restore。恢复库只重跑 check 和 rollback fixture，不重新执行 migration，也不重跑会提交 synthetic 行的并发脚本。

这些结果只证明 synthetic PostgreSQL bridge 和 Backend adapter 合同。它们不证明 HTTP、Flutter、生产 identity provider、真实账号或任何平台上的运行时行为。
