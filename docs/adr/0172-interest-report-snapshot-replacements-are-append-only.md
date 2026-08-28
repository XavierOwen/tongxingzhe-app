# ADR-0172：interest 报告快照更正版取代关系采用独立追加合同

- 状态：已接受
- 日期：2026-08-28
- Slice：6CD
- Issue：[#257](https://github.com/XavierOwen/tongxingzhe-app/issues/257)
- 依赖：ADR-0141、ADR-0159、ADR-0170
- Requirement：`ANALYTICS-013`、`ANALYTICS-065`、`PRIVACY-056`、`TEST-059`、`MANUAL-049`

## 背景

0062 已把 interest 受保护报告保存为不可变 snapshot。它用独立 release attempt 记录项目、报告定义、时区 revision、期间、source watermark 和 previous pointer。后续补录、接触修订或作废可能产生更晚的 approved snapshot，但旧 snapshot 不能被改写。目录顺序也不能代表 current、latest 或 replacement。

渠道、current-city 和 original-region 已有各自的 replacement provenance。interest 必须核对自己的 0062 attempt，不能复用其他 report family 的关系或 validator。

## 决定

6CD 只登记两份已经通过 0062 的 interest approved snapshot 之间的直接 replacement。旧、新快照必须属于同一 project、report／version、query fingerprint、privacy policy、source scope、报告时区 revision、期间和 release lineage。新快照的 `data_cutoff_utc` 与发布时间必须更晚，source change sequence 不得回退。

每份 snapshot 的 `previous_snapshot_id` 必须与自己的 0062 release attempt 一致。replacement edge 是独立生命周期关系。它不改写既有发布指针，也不要求新快照的发布指针等于被取代快照。

关系在共享的 value-free request UUID ledger 中使用独立 interest replacement family。release 与 replacement 使用同一 request lock。同一 UUID 先被任一合同声明后，另一个合同失败关闭。

关闭的 lifecycle writer 只能通过 interest 专用 provenance seam 核对 0062 attempt，不能直接读取 attempt ledger。原因只允许 `late_accepted_data`、`contact_revision` 和 `contact_void`。

关系和最小 audit 追加不可变。每份旧快照最多一个直接 replacement，每份新快照最多一个 predecessor。自链接、循环、分叉、stale head、跨项目、跨 family 和时间倒序失败关闭。

事务取得 request、replacement lineage 和授权层级锁后，再次确认 `release_management_reports`、membership、项目状态与 approved provenance。相同 request UUID 和 canonical payload 精确幂等；载荷漂移失败关闭。生命周期只返回 snapshot ID、`active`／`superseded` 和直接 replacement ID。

## 后果与边界

这个决定只增加有证据的 interest 同版本数据更正链。它不改变 0062 发布、目录排序、读取、runtime、HTTP、Flutter 或导出，也不自动选择链头。

分析定义变化、跨 report version replacement 和 follow-up-consent replacement 不属于本切片。6CD 也不处理删除、retention、warehouse 或真人平台验收。Docker synthetic 通过只证明 PostgreSQL 中的关系、provenance、授权锁、不可变性和 ACL。

## 验证

完整 runner 自动发现 0082 migration、structural check、rollback fixture 和 concurrency script。它随后验证 checksum，并在独立 cluster 中完成 dump／restore。恢复库不重跑会提交 synthetic 行的并发脚本。

从仓库根目录运行：

```bash
./tool/run_postgres_tests_in_docker.sh
```

只调试 6CD 时，先确认 `DATABASE_URL` 指向专用测试库，再运行：

```bash
./tool/postgres_migrate.sh
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/checks/verify_management_interest_report_snapshot_replacements.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/fixtures/0082_management_interest_report_snapshot_replacements.sql
./tool/verify_management_interest_report_snapshot_replacements_concurrency.sh
```

这些命令只提供 synthetic DB-only replacement 证据。它们不证明 snapshot 生成、生产身份、runtime、HTTP、Flutter、目录、导出或真人平台环境。
