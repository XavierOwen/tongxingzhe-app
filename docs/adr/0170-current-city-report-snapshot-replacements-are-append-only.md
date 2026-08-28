# ADR-0170：current-city 报告快照更正版取代关系采用独立追加合同

- 状态：已接受
- 日期：2026-08-26
- Slice：6CB
- Issue：[#242](https://github.com/XavierOwen/tongxingzhe-app/issues/242)
- 依赖：ADR-0136、ADR-0150、ADR-0159
- Requirement：`ANALYTICS-013`、`ANALYTICS-063`、`PRIVACY-054`、`TEST-057`、`MANUAL-047`

## 背景

0057 已把 current-city 受保护报告保存为不可变 snapshot，并用独立 release attempt 记录项目、报告定义、时区 revision、期间、source watermark 和目标区域树证据。后续补录、接触修订或作废可能产生更晚的 approved snapshot，但旧 snapshot 不能被改写，目录顺序也不能被解释为 current、latest 或 replacement。

6BE 的渠道 replacement 和 6BN 的 original-region replacement 都依赖各自的发布 provenance。current-city 不能复用它们的关系表或 validator；它必须重新核对 0057 的 target tree tuple 和 selection evidence。

## 决定

6CB 只登记两份已经通过 0057 的 current-city approved snapshot 之间的直接 replacement。它不生成 snapshot。
旧、新快照必须属于同一 project、report／version、query fingerprint、privacy policy 和 source scope。报告时区 revision、期间和 release lineage 也必须相同。
它们还必须保持精确相同的 target tree version、content fingerprint 和 selection evidence。新快照的 `data_cutoff_utc` 与发布时间必须更晚，source change sequence 不得回退。

每份 snapshot 的 `previous_snapshot_id` 必须与它自己的 0057 release attempt 精确一致。6CB 的 replacement edge 是独立生命周期关系。它不要求新快照的既有发布指针等于被取代快照，也不改写该指针。

关系在管理报告共享的 value-free request UUID ledger 中使用独立的 current-city replacement family claim。release 与 replacement 使用同一 request lock。因此，同一 UUID 无论先由哪一方声明，另一方都失败关闭。

登记复用既有关闭的 lifecycle writer role。该 role 只能通过 current-city 专用 provenance seam 核对 0057 attempt，不能直接读取 attempt ledger。6CB 不改变该 role 的既有 family ACL；current-city provenance 和 lifecycle seam 不暴露任何 report family 的正文。

登记原因只允许 `late_accepted_data`、`contact_revision` 和 `contact_void`。关系和最小 audit 追加不可变；每份旧快照最多一个直接 replacement，每份新快照最多一个 predecessor。自链接、循环、分叉、stale head、跨项目、跨 family、target context 漂移和时间倒序均失败关闭。

事务取得 request、replacement lineage 和授权层级锁后，必须再次确认 `release_management_reports`、membership、项目状态与 approved provenance。相同 request UUID 和 canonical payload 精确幂等；载荷漂移失败关闭。生命周期查询只返回 snapshot ID、`active`／`superseded` 和直接 replacement ID，不返回报告格、区域来源、贡献者、接触、坐标或 PII。

## 后果与边界

这个决定只给 current-city 增加有证据的同版本数据更正链。它不改变 0057 发布、现有目录排序、读取、HTTP、导出或 Flutter，也不自动选择链头。interest 和 follow-up-consent report family 仍需各自的 replacement 合同。

分析定义变化或跨 report version replacement 不属于本切片。6CB 也不处理删除、tombstone、retention、备份清除、parent／overlap 查询、warehouse 或真人平台验收。Docker synthetic 通过只能证明 PostgreSQL 中的关系、provenance、授权锁、不可变性和 ACL，不能证明生产身份、报告生成或六平台运行时。

## 验证

完整 runner 在源库自动发现 0080 migration、structural check、rollback fixture 和 replacement concurrency script，并验证 checksum。dump／restore 后，恢复库只重跑全部 check 和 numbered fixture，不重新执行 migration，也不重跑会提交行的并发脚本。

从仓库根目录运行：

```bash
./tool/run_postgres_tests_in_docker.sh
```

只调试 6CB 时，先确认 `DATABASE_URL` 指向专用测试库，再运行：

```bash
./tool/postgres_migrate.sh
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/checks/verify_management_current_city_report_snapshot_replacements.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/fixtures/0080_management_current_city_report_snapshot_replacements.sql
./tool/verify_management_current_city_report_snapshot_replacements_concurrency.sh
```

这些命令只提供 synthetic DB-only replacement 证据。它们不证明新 snapshot 已生成，也不证明 runtime、HTTP、Flutter、目录、导出、删除、retention、生产身份或真人平台环境。
