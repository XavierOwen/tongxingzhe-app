# ADR-0149：管理原始区域报告固定单一来源树

- 状态：已接受
- 日期：2026-08-21
- 切片：Slice 6BD
- Issue：#193
- 需求：`ANALYTICS-039`、`PRIVACY-031`、`TEST-033`、`MANUAL-023`
- 相关决定：ADR-0110、ADR-0111、ADR-0132、ADR-0133、ADR-0135

## 背景

`REGION-007`、`REGION-009` 和 `REGION-010` 同时要求保留原始解析结果、支持原始区域视图，并在没有可信证据时失败关闭。
6AN 已固定 current 城市报告，但它依赖 6AM 的 current target context；把 current 城市报告改名为 original，或把不同来源树的记录
拼在一起，都会丢失历史来源语义。下一份 review-sized 工作单元需要先固定一个可独立测试的数据库合同，不提前承诺快照、HTTP 或客户端。

## 决策

6BD 定义私有 PostgreSQL 报告 `contact_sessions_by_original_region_two_periods@1`。固定 identity 为：

```text
metric=contact_sessions@1
view_mode=original
dimension=original_region
region_granularity=city
```

它使用项目报告 IANA 时区、两个相邻完整 ISO 周和 `data_cutoff_utc`。cutoff 只限定本次纳入的已接受事实；它不是任意历史
`as-of`，不重建某个时刻的区域树，也不自动选择 current 或 latest release。

每个报告只绑定一个精确的 `source_tree_version + source_content_fingerprint`。每条可报告接触都必须使用保存的 original
release、指纹和区域节点，通过 6AL `original` 证据在同一来源树内找到唯一城市祖先；调用 6AL 时不提供 current target 参数。6BD 不使用
6AM target context、current selection、跨版本 mapping、坐标重新解析或名称／父链猜测。来源不完整、release 不可验证、指纹漂移、节点缺失、
没有唯一城市祖先或 `not_reportable` 的记录不进入可报告集合。一个候选中如果出现多个来源树 tuple，或没有可用来源树，executor 返回稳定
unavailable／失败关闭；它不选择其中一棵，也不跨树聚合。

输出是该来源树全部城市的稳定完整网格。每个期间和城市先执行 `k=10`、至少三位贡献者和任一贡献者不超过一半的保护，再按稳定城市顺序
执行互补隐藏。`displayed` 只保存安全整数，`suppressed` 固定为 JSON `null`。固定 metadata 可包含报告 identity、项目、时区、两个期间、
cutoff、来源树 tuple 和数据证据边界；报告不包含城市名称、边界、坐标、来源、接触、revision、贡献者或其他 PII。

数据库函数、检查和角色权限属于 private DB-only 合同。runtime、`PUBLIC`、普通 app role 和区域维护角色不能通过宽泛 ACL 绕过
private function；授权读取、审计、快照或发布能力由后续 Slice 单独决定。

## 后果与边界

单一来源树使报告可以明确回答“按接触原始解析时所在的城市看，两期接触场次如何分布”，也使树版本冲突成为可观察的 unavailable，
而不是被最新树或名称相似度掩盖。代价是不同来源树不能在同一份固定网格中合并，证据不足的记录不能通过 current 映射补齐。

6BD 不增加 snapshot／release lineage、authorized read、runtime bridge、HTTP、Flutter、Drift、缓存、离线、同步、导出、parent／overlap
处理、retention、warehouse、自动调度、真实身份、任意历史 `as-of` 或六平台真机验收。Docker 和 SQL fixture 只证明 synthetic PostgreSQL
合同，不能证明真实区域树内容、生产报告或平台运行时。

## 验证

实现应新增 0066 migration、结构／权限 check、synthetic fixture 和独立并发脚本。fixture 至少覆盖：原始来源 release／指纹／节点／唯一城市父链、
缺失或漂移证据、`not_reportable`、current／mapping／名称猜测被拒绝、单一来源树、混合来源树失败关闭、两完整期间、全部城市网格、
`k=10`／三位／半数边界、期间独立判断、互补隐藏、无敏感字段、最小 ACL、旧 6AN 回归和不可改删约束。完整 Docker runner 应在 checksum 和
dump／restore 后重跑 migration、check 和 fixture；restore 不重跑会提交 synthetic 行的并发脚本。

第一次使用 Docker 时，从仓库根目录运行：

```bash
./tool/run_postgres_tests_in_docker.sh
```

只调试专用测试库时，确认它不是 production，再运行：

```bash
export DATABASE_URL='postgresql://postgres:postgres@127.0.0.1:5432/tongxingzhe_test'
./tool/postgres_migrate.sh
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/checks/verify_management_original_region_report.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/fixtures/0066_management_original_region_report.sql
./tool/verify_management_original_region_report_concurrency.sh
```

这些命令的成功只说明合成 PostgreSQL 数据满足 6BD；它不说明 runtime、HTTP、Flutter、导出、生产身份、任意历史 `as-of` 或六平台真人运行时已经完成。
