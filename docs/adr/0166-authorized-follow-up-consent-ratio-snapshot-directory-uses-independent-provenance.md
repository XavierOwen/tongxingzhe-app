# ADR-0166：后续联系同意占比快照目录使用独立 provenance

- 状态：已接受
- 日期：2026-08-26
- Slice：6BU
- Issue：#227
- 依赖：#219、#221、#223、#225、0075
- Requirement：`ANALYTICS-056`、`PRIVACY-047`、`TEST-050`、`MANUAL-040`
- 相关决定：ADR-0162、ADR-0163、ADR-0164、ADR-0165

## 背景

6BQ 已把后续联系同意占比的 protected candidate 固定为 0075 lineage 中的不可变 snapshot。6BR 只按显式 project 和 snapshot UUID 读取一份快照，6BS 与 6BT
分别定义 runtime bridge 和 HTTP 详情。后续调用方需要一个受授权、受限的目录来发现可用快照，但目录不能成为通用的 latest 查询，也不能暴露报告值。

目录必须识别 0075 consent-ratio family 的可信 release provenance。复用 channel、current-city、interest 或 original-region provenance 会让不同 report family 的
授权边界混在一起。目录还必须在每次调用重新验证权限，并与撤权使用同一锁顺序。

## 决定

新增 0078 private PostgreSQL 函数：

```text
app_private.list_authorized_management_follow_up_consent_snapshots_v1(uuid, uuid)
```

这是 canonical 名称。它保持在 PostgreSQL 63 字节标识符限制内，避免长名称被截断。函数只接受可信内部用户和显式 project UUID，并在既有 authorization／revoke
锁顺序内重新确认 active user、组织／项目 membership、active project 和 `view_anonymous_analytics`。权限撤回、membership 变化、project archive、过期或其他
授权竞态必须失败关闭。

函数只纳入 0075 consent-ratio family 的 `approved_baseline`／`approved` exact provenance。project、report／version、query fingerprint、privacy、source scope、
报告时区 revision、期间、release lineage、cutoff、previous pointer 或 source watermark 不一致的记录不进入目录。unknown、cross-project、cross-family、legacy、
blocked、missing 和 drifted provenance 都失败关闭或被排除，不能绕过授权读取。

成功返回的 root envelope 只有四个 key：`access_contract_id`、`access_event_id`、`project_id` 和 `snapshots`。`snapshots` 是最多 20 项的 metadata-only 列表；
每项只有六个 key：`snapshot_id`、`report_id`、`report_version`、`reporting_time_zone`、`data_cutoff_utc` 和 `released_at_utc`。数据库固定按
`data_cutoff_utc DESC`、`released_at_utc DESC`、`snapshot_id DESC` 排序。第一项只是确定性排序的第一项，不表示 current、latest 或未被取代；本合同不提供
latest、current、分页或筛选参数。

已授权 project 没有合格快照时，函数返回空数组并追加数量为 0 的成功 audit。目录 audit 使用专用、追加式、不可变、value-free 合同，只记录授权和访问
metadata。audit 不记录 snapshot ID、report、period、ratio、coverage、source、contributor、target、contact 或 PII。未授权、撤权、过期、无成员、inactive
project、unknown ID、cross-project 或权限不足的调用不写成功 audit。

私有函数、目录表和 audit 表只由受限 owner／授权闭合角色使用。`PUBLIC`、`tongxingzhe_runtime`、普通 app role、其他 report reader／writer 不能执行该函数或
直接读取 audit。6BU 不修改前序 6BS／6BT 已定义的 `app_data` identity bridge、runtime、Backend adapter 和 HTTP route，也不增加 Flutter、导出、缓存、离线或同步合同。

## 后果与证据边界

调用方可以得到一个固定大小、固定排序的候选目录，再明确选择 snapshot UUID。目录不会为客户端推断 latest，也不会因目录读取而取得 protected report。代价是
调用方必须保存并提交显式 project／snapshot 选择，不能使用 current 或 latest 的隐含语义。

0078 structural check、rollback fixture、directory／revoke concurrency、checksum 和独立 dump／restore 只证明 synthetic PostgreSQL 的 function、provenance、
authorization、audit、锁和恢复合同。它们不证明 runtime identity、Backend、HTTP、Flutter、部署服务、production data、离线缓存或 Android、iOS、macOS、Windows、
Linux、Web 真人平台运行时，也不构成形式化不可重识别保证。

## 验证

从仓库根目录运行完整数据库套件：

```bash
./tool/run_postgres_tests_in_docker.sh
```

只调试 6BU 时，先确认 `DATABASE_URL` 指向可丢弃的测试库：

```bash
export DATABASE_URL='postgresql://postgres:postgres@127.0.0.1:5432/tongxingzhe_test'
./tool/postgres_migrate.sh
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/checks/verify_authorized_management_follow_up_consent_ratio_snapshot_directory.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/fixtures/0078_authorized_management_follow_up_consent_ratio_snapshot_directory.sql
./tool/verify_authorized_management_follow_up_consent_ratio_snapshot_directory_concurrency.sh
```

fixture 使用 rollback transaction；并发脚本使用独立 committed namespace。恢复阶段先准备缺失的 PostgreSQL roles，再重跑 check 和 fixture，不重跑会提交 synthetic
行的并发脚本。
