# ADR-0167：后续联系同意占比快照目录使用 exact identity bridge

- 状态：已接受
- 日期：2026-08-26
- Slice：6BV
- Issue：#229
- 依赖：#227、PR #228、0078
- Requirement：`ANALYTICS-057`、`PRIVACY-048`、`TEST-051`、`MANUAL-041`
- 相关决定：ADR-0164、ADR-0165、ADR-0166

## 背景

6BU 已在 private PostgreSQL 中提供受授权的后续联系同意占比 snapshot directory。它返回固定的四项 root envelope 和最多 20 项六字段 metadata。
后续 Backend 需要用已验证的 external identity 访问这个目录，但不能直接执行 0078 private function，也不能取得 private schema 的表权限。

6BS 只读取单份 snapshot，不能替代目录 bridge。directory bridge 还必须把显式 project UUID 传给 0078，避免按当前项目、latest 或客户端筛选隐式扩大范围。

## 决定

新增 0079 `app_data` bridge：

```text
app_data.list_authorized_management_follow_up_consent_snapshots_v1(text,text,uuid)
```

bridge 接受 Backend 已验证的 exact external `issuer + subject` 和显式 project UUID。它只映射已有且 active 的 identity，再调用 0078 private directory。
它不 trim identity，不 bootstrap，不创建 identity，也不接受内部用户 ID、capability、时区、截止点、筛选或 SQL。

bridge 使用 `SECURITY DEFINER`、`VOLATILE` 和固定 `search_path = pg_catalog`，owner 与 0078 private directory owner 对齐。`tongxingzhe_runtime` 只有 bridge
`EXECUTE`，没有 `app_private` schema usage，也不能直接读取 identity、snapshot、attempt、claim、directory 或 audit 表。`PUBLIC`、普通 app role 和其他
report reader／writer 不能调用 bridge。

0079 只委托给：

```text
app_private.list_authorized_management_follow_up_consent_snapshots_v1(uuid,uuid)
```

0078 继续负责 active user、组织／项目 membership、active project、`view_anonymous_analytics`、0075 exact provenance、撤权锁、目录排序和 value-free audit。
0079 不复制这些授权或审计规则，也不修改 0078 provenance、audit 或排序。

Backend 为目录提供独立 store。store 只执行一条固定参数化 SQL：

```sql
SELECT app_data.list_authorized_management_follow_up_consent_snapshots_v1(
  $1::text, $2::text, $3::uuid
) AS directory_result
```

strict parser 只接受 0078 的四项 root envelope：`access_contract_id`、`access_event_id`、`project_id` 和 `snapshots`。每个目录项只接受
`snapshot_id`、`report_id`、`report_version`、`reporting_time_zone`、`data_cutoff_utc` 和 `released_at_utc`。parser 检查 exact keys、project 绑定、
合法 UUID、UTC 时间、最多 20 项、无重复和 `data_cutoff_utc`／`released_at_utc`／`snapshot_id` 固定降序。它拒绝额外字段、错误 contract、非 consent-ratio
report、无效 UUID 或时间以及错误排序。

store 只把 SQLSTATE `42501` 映射为 typed `forbidden`。未知 SQLSTATE、数据库错误和 parser 错误不能被伪装成授权失败。

## 不在范围内

本决定不增加 HTTP route、Bearer 认证顺序、HTTP wire error mapping、Flutter、Drift、UI、缓存、离线、导出、分页、筛选、current／latest 选择或生产身份。
它不修改 0078 的 provenance、授权、撤权锁、audit 和排序，也不声称生产部署或 Android、iOS、macOS、Windows、Linux、Web 真人平台已经验证。

## 后果与证据边界

Backend 可以用固定项目和 exact identity 发现可选快照，再把明确的 snapshot UUID 交给后续详情流程。目录第一项仍不表示 current、latest 或未被取代。
strict parser 会把数据库合同漂移拦在 Backend 边界内；代价是新字段或新 report family 必须先更新 canonical contract 和测试。

0079 structural check、rollback fixture、Backend unit／integration、checksum 和 dump／restore 只证明 synthetic bridge、adapter、parser 和 ACL 合同。
它们不证明 HTTP、部署服务、production identity、真实账号、客户端消费、缓存、离线或六平台真人平台运行时，也不构成形式化不可重识别保证。

## 验证

从仓库根目录运行完整套件：

```bash
./tool/run_postgres_tests_in_docker.sh
```

只调试 6BV 时，先确认 `DATABASE_URL` 指向可丢弃的测试库，再运行 Backend 合同测试和 Docker 套件。恢复阶段先准备缺失的 PostgreSQL roles，重跑 check 和
fixture；不重跑会提交 synthetic 行的并发脚本。
