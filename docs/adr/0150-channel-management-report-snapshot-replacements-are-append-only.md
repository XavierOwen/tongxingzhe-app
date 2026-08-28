# ADR-0150：渠道管理报告快照取代登记采用追加不可变关系

- 状态：已接受
- 日期：2026-08-21
- 切片：Slice 6BE
- Issue：#195
- 需求：`ANALYTICS-040`、`PRIVACY-032`、`TEST-034`、`MANUAL-024`
- 相关决定：ADR-0104、ADR-0105、ADR-0108、ADR-0149

## 背景

6J 的 trusted-v2 发布会保存不可变的渠道管理报告快照。后续补录、接触修订或作废需要明确指出哪一份旧快照已被哪一份新快照取代。
如果直接修改快照，读取、导出和审计就无法复现当时看到的内容。如果把所有快照的排序结果称为“最新”，目录也会在没有取代证据时改变语义。

6BE 只增加一个私有数据库生命周期登记合同。它登记已有快照之间的关系，不负责生成报告或改变任何读取路径。

## 决策

6BE 只接受两份已经通过 6J trusted-v2 provenance 的渠道快照。两份快照必须属于同一项目、同一 report ID、version、query fingerprint、
reporting time zone 和 release lineage。新快照的 `data_cutoff_utc` 与发布时间必须晚于旧快照。调用方不能提交报告 JSON、cells、时区、截止点、
来源证据或 capability 来替代数据库重新验证。

登记原因只允许 `late_accepted_data`、`contact_revision` 和 `contact_void`。分析定义修正和跨版本取代需要后续独立合同，不能借本切片的同 report／version／query／时区／lineage
约束登记。

数据库登记一条从旧快照到新快照的直接 replacement 关系。旧快照和新快照本身不改写。每份旧快照最多只有一个直接替代者，每份新快照最多替代一份旧快照。
关系可以继续向前形成严格有向链，但不能自链接、分叉或循环。只有当前链头可以被取代，已经被取代的旧快照不能再次作为链头。登记合同只引用已存在的快照，
不生成 snapshot、release attempt 或新的报告正文。

登记使用既有 `release_management_reports` 授权链。事务取得会等待的请求、项目和 replacement lineage 锁后，必须重新确认授权和两份快照的 trusted-v2 provenance。
撤权先提交时，登记必须失败关闭；登记先取得锁时，撤权等待该事务完成。相同 request UUID 和完全相同的 canonical payload 精确幂等，payload 漂移、跨项目、
current-city、interest、legacy、blocked、未知来源或 stale head 均失败关闭。

生命周期查询对可信渠道快照只返回快照 ID、`active`／`superseded` 状态和直接 replacement snapshot ID；未知或不可信来源返回 value-free `not_found`。
查询不返回报告正文、cells、隐藏前值、来源、贡献者、地点、授权关系或 PII。
关系和最小审计证据均为追加不可变记录，不允许 UPDATE 或 DELETE。`PUBLIC`、`tongxingzhe_runtime`、普通 app role、reader 和其他 report-family writer
不能直接读写关系表或执行登记函数，除非后续切片另行定义窄的授权读取合同。

## 后果与边界

取代关系使报告历史保持可复现，也使“当前链头”成为有证据的生命周期状态。目录顺序、既有授权读取、HTTP、导出和 Flutter consumer 不因 6BE 改变。
调用方仍必须明确选择 snapshot；6BE 不把链头自动变成目录中的 latest。

6BE 不生成新快照，不修改 6J 发布函数，不接入 runtime bridge、HTTP、Flutter、Drift、缓存、离线、同步、目录、读取、导出、warehouse 或生产调度。
它不决定或执行物理删除、tombstone、账号／组织删除、恢复期或 retention 期限。current-city、interest 和 original-region report family 不能复用本合同，
必须先有各自的 trusted provenance 和独立生命周期决定。Docker 与 SQL fixture 只证明 synthetic PostgreSQL 合同，不证明生产数据或真人平台运行时。

## 验证

实现应新增 0067 migration、结构／权限 check、rollback fixture 和独立并发脚本。fixture 至少覆盖：两份合法同项目 channel trusted-v2 快照、链式取代、生命周期查询、
相同 request 精确幂等、payload 漂移、跨项目和跨 report family 拒绝、legacy／blocked／未知 provenance、stale head、自链接、分叉、循环、时间倒序、旧快照字节不变、
value-free 结果、追加不可变和最小 ACL。并发脚本应覆盖同一旧快照的竞争取代，以及 replacement-first／revoke-first 的两种锁顺序。

从仓库根目录运行完整 Docker 套件：

```bash
./tool/run_postgres_tests_in_docker.sh
```

只调试专用 PostgreSQL 测试库时，确认它不是 production，再运行：

```bash
export DATABASE_URL='postgresql://postgres:postgres@127.0.0.1:5432/tongxingzhe_test'
./tool/postgres_migrate.sh
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/checks/verify_management_report_snapshot_replacements.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/fixtures/0067_management_report_snapshot_replacements.sql
./tool/verify_management_report_snapshot_replacements_concurrency.sh
```

Docker runner 应在源库运行 migration、check、fixture、并发脚本并验证 checksum。独立 dump／restore 后，恢复库只重跑全部 check 和
numbered fixture，不重新执行 migration，也不重跑会提交 synthetic 行的并发脚本。
通过只证明 DB-only synthetic replacement ledger、锁线性化、授权、不可变约束和 ACL；它不证明报告生成、HTTP、Flutter、导出、retention、删除规则、生产身份或六平台真人运行时。
