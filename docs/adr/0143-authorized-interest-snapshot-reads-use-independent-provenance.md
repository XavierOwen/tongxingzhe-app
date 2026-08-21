# ADR-0143：授权兴趣快照读取使用独立 provenance

- 状态：已接受
- 日期：2026-08-21
- Slice：6AX
- Issue：#181
- Requirement：`ANALYTICS-033`、`PRIVACY-025`、`TEST-027`、`MANUAL-017`

## 背景

6AV 固定管理兴趣五档分布。6AW 把符合 6AV 合同的十格文档保存为不可变 snapshot，并使用兴趣专属 release attempt、request
claim 和 provenance。现有 0032 读取函数只信任渠道 v2 release attempt。它不能把 0062 的兴趣 provenance 当作可信来源。

读取还必须在返回正文前重新确认查看能力、项目范围、release lineage 和十格文档。撤权与读取需要共享数据库锁，否则一个已撤销
的 `view_anonymous_analytics` 可能在读取期间继续生效。

## 决策

0063 增加 private 函数：

```text
app_private.read_authorized_management_interest_report_snapshot_v1(
  requested_app_user_id uuid,
  requested_project_id uuid,
  requested_snapshot_id uuid
)
```

函数只接受三个显式 UUID。它在同一事务中调用既有授权解析器，重新确认活动账号、组织成员、项目成员、项目状态和
`view_anonymous_analytics`。授权解析器与撤权事务使用同一 advisory lock。函数不会接受 capability、授权时间、时区、截止点或
报告 JSON。

完成读取必须同时满足以下条件：

- snapshot 属于请求的 project；
- snapshot 的报告是 `contact_sessions_by_interest_level_two_periods@1`，并保持 6AV 的 metric、dimension、统计单位、query
  fingerprint、privacy policy、source scope 和十格顺序；
- 0062 attempt 由 `interest_management_report_snapshot_release` claim 指向，状态是 `approved_baseline` 或 `approved`；
- attempt 的 `reason_codes` 为空；
- attempt 与 snapshot 的 project、report、version、query fingerprint、release lineage、报告时区、`data_cutoff_utc`、
  `source_change_sequence`（source watermark）、previous pointer 和 released snapshot 对齐；
- 数据库再次执行 6AV interest document validator。

成功读取返回固定 envelope 和原始 protected report。`suppressed` 仍为 JSON `null`。函数不重算十格，也不从 channel、current-city
或其他报告补值。

已授权但找不到请求范围内 snapshot 时返回 `not_found`。这包括未知 snapshot 和跨 project snapshot，并且不返回正文。请求范围内
存在 snapshot、但它属于 channel、current-city、legacy、blocked、缺失或漂移 provenance 时返回 `untrusted_provenance`，也不返回正文。

每次已授权尝试都在同一事务追加兴趣专用的不可变、value-free 访问审计。审计只保留最小授权 lineage、请求 project／snapshot、
固定报告元数据、结果和 reason code。它不复制 protected report、cells、`value_count`、贡献者、contact、来源或 PII。未授权调用
以 `42501` 失败，不写访问审计。

读取函数和审计表继续对 `PUBLIC`、runtime、普通 app role、interest reader、current-city writer 和区域角色关闭。0063 不开放
runtime bridge、HTTP、目录、Flutter、Drift、缓存、离线、同步、导出、warehouse、retention 或生产发布入口。

## 后果

兴趣读取不会误用渠道 v2 或 current-city provenance。`not_found` 隐藏未知和跨项目存在性，`untrusted_provenance` 让同项目的错误
来源可审计而不泄漏正文。专用审计表避免把不同报告族的访问字段混在一起。

读取和撤权按取得共享授权锁的先后线性化：读取先取得锁时，撤权等待这次已授权读取完成；撤权先取得锁时，读取重新看到失效能力并
失败关闭。访问审计与返回正文在同一私有事务中提交。服务层尚未接入，因此本 ADR 不定义 HTTP 提交后的交付语义。

## 验证

从仓库根目录运行完整 Docker 套件：

```bash
./tool/run_postgres_tests_in_docker.sh
```

runner 按文件名自动发现 0063 migration、结构／权限 check、synthetic fixture 和 read/revoke 并发脚本。它还运行 checksum、
dump／restore，并在没有源 cluster roles 的恢复库重跑 migration、check 和 fixture。恢复库不重跑会提交 synthetic 行的并发脚本，
避免将相同并发写入重复导入恢复库。

专用测试库的顺序是：

```bash
export DATABASE_URL='postgresql://postgres:postgres@127.0.0.1:5432/tongxingzhe_test'
./tool/postgres_migrate.sh
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/checks/verify_authorized_management_interest_report_snapshot_read.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/fixtures/0063_authorized_management_interest_report_snapshot_read.sql
./tool/verify_authorized_management_interest_report_snapshot_read_concurrency.sh
```

fixture 覆盖合法与重复读取、`not_found`、`untrusted_provenance`、0062 lineage 对齐、授权失效、value-free audit 和不可改删。
并发脚本覆盖 read-first 与 revoke-first。通过只证明当前 PostgreSQL 的 DB-only 合同，不证明 runtime、HTTP、Flutter、导出、真实
账号、六平台运行或形式化不可重识别保证。
