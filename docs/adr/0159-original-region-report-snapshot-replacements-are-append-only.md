# ADR-0159：原始区域报告快照更正版取代关系采用独立追加合同

- 状态：已接受
- 日期：2026-08-25
- Slice：6BN
- Issue：[#213](https://github.com/XavierOwen/tongxingzhe-app/issues/213)
- 依赖：[#207](https://github.com/XavierOwen/tongxingzhe-app/issues/207)、[#212](https://github.com/XavierOwen/tongxingzhe-app/issues/212)
- Requirement：`ANALYTICS-049`、`PRIVACY-041`、`TEST-043`、`MANUAL-033`

## 背景

6BG 已为 original-region 报告保存 approved snapshot 和独立 release lineage。后续接纳的数据可能需要发布更晚的 snapshot，但这不应改写旧
snapshot，也不能把渠道报告的 replacement ledger 当作所有 report family 的通用关系。6BK 的目录排序只表达返回顺序，不表达 current、latest 或
replacement。需要一个只登记既有快照之间关系的窄合同。

## 决定

6BN 只登记已经通过 6BG 的 original-region approved snapshot 之间的直接 replacement，不生成 snapshot。旧快照和新快照必须属于同一 project、
report／version、query fingerprint、privacy、source scope、报告时区 revision、期间、release lineage，以及精确的
`source_tree_version + source_content_fingerprint`。新快照的 `data_cutoff_utc` 和发布时间都必须晚于旧快照。

该关系在管理报告共享的 value-free request UUID ledger 中使用独立 replacement family claim，并使用 original-region 专用 provenance 和最小 ACL，
不复用 6BE 的渠道 replacement ledger。release 与 replacement 使用相同 request lock，因此同一 UUID 在两个合同中的先后顺序都失败关闭。登记原因只允许
`late_accepted_data`、`contact_revision` 和 `contact_void`。关系和最小 audit 采用追加式不可变记录；每份旧快照最多一个直接 replacement，每份新
快照最多一个 predecessor。自链接、循环、分叉、stale head、跨项目、跨 report family、source-tree 漂移和时间倒序均失败关闭。

事务取得 request 和 lineage 锁后，必须再次确认 `release_management_reports` 与批准 provenance。相同 request UUID 与 canonical payload
精确幂等；同一 UUID 的载荷漂移失败关闭。生命周期查询只返回 snapshot ID、`active`／`superseded` 和直接 replacement ID。它不返回报告格、来源、
贡献者、地点、隐藏前值或 PII。

## 后果与边界

这个决定把 original-region replacement 关系与渠道、current-city、interest report family 分开。它不改变快照内容、目录排序或既有读取路径，也不
提供跨版本或分析定义更正。后续消费者必须显式读取 replacement 关系，不能从目录顺序猜测 latest。

6BN 是 DB-only、value-free 合同：不生成 snapshot，不增加 runtime、HTTP、Flutter、目录、导出、缓存、离线或分享，不处理删除、tombstone、
retention、备份清除、parent／overlap 查询、warehouse 或真人平台验收。Docker synthetic 通过只能证明 PostgreSQL 中的关系、授权、不可变性和
ACL；不能证明生产身份、报告生成、其他 report family 或任何平台运行时。

## 验证

完整 runner 会在源库发现 0072 migration、structural check、rollback fixture 和 replacement concurrency script，并验证 checksum。
dump／restore 后，恢复库只重跑全部 check 和 numbered fixture，不重新执行 migration，也不重跑会提交行的并发脚本。

从仓库根目录可运行：

```bash
./tool/run_postgres_tests_in_docker.sh
```

如需只调试 6BN，先确认 `DATABASE_URL` 指向专用测试库，再运行：

```bash
./tool/postgres_migrate.sh
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/checks/verify_management_original_region_report_snapshot_replacements.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/fixtures/0072_management_original_region_report_snapshot_replacements.sql
./tool/verify_management_original_region_report_snapshot_replacements_concurrency.sh
```

这些命令的证据范围仅是 synthetic PostgreSQL 的 DB-only replacement contract。它们不证明新 snapshot 已生成，不证明 runtime、HTTP、Flutter、
目录、导出、缓存、离线、删除、retention、生产身份或六平台真人环境。
