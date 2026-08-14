# 按报告截止点解析历史区域目标树上下文

状态：**已接受（2026-08-14）**。

关联：Issue #155、Slice 6AM；ADR-0110、ADR-0111、ADR-0132、ADR-0133；
`REGION-012`、`ANALYTICS-022`、`PRIVACY-014`、`MANUAL-013`、`TEST-016`。

## 决定

Slice 6AM 提供私有函数
`app_private.resolve_management_report_region_target_context_v1(timestamptz)`。
它接收可信的 `data_cutoff_utc`，从追加式区域树 current selection history 和已发布 release
派生一份 `history-derived cutoff context`。它不读取 mutable `is_current`，不按
最新 release、名称、父链或几何相似度猜测目标树。

只有同时满足以下条件的 publication selection 才能进入上下文：

- `selected_at_utc <= data_cutoff_utc`；
- 对应 release 已发布；
- release 的 `published_at_utc <= data_cutoff_utc`；
- selection 保存的内容指纹与 release 指纹完全一致。

resolver 返回固定合同、状态、原因、截止点、目标 `target_tree_version`、
`target_content_fingerprint`、`selection_sequence`、`selection_source`、证据时间和
`tree_published_at_utc`。返回值不含来源 ID、接触、坐标、贡献者、区域名称或 PII。
如果历史不存在或截止点早于可证明的选择时间，resolver 返回不含目标 tuple 的稳定不可用状态。
如果已经选中的历史指向草稿或缺失 release，或者指纹、选择时间和发布时间不一致，resolver 以固定
`SQLSTATE 55000` 拒绝整次解析，不返回上下文。

0038 的 migration baseline 只有观察事实。它把既有 current release 写入选择历史，
但 `selected_at_utc` 为 `NULL`，`recorded_at_utc` 只表示数据库在该时刻观察到这条
基线。因此，baseline 只能从 `recorded_at_utc` 这个观察下界开始使用。更早的
`data_cutoff_utc` 必须返回 `selection_history_unavailable`，不能把观察时间解释成
真实的 current 选择时间。

区域树发布函数和 6AM resolver 共用
`canonical-region-tree-publication:v1` 事务 advisory lock。发布函数在锁内验证、
冻结、指纹化并追加 selection history；resolver 在同一把锁内读取已提交历史。
resolver 虽然不写表，仍使用 `VOLATILE SECURITY DEFINER`，以保持明确的事务锁和
线性化语义。一个 resolver 事务不会看到未提交的 selection，也不会产生与发布
提交顺序矛盾的上下文。

6AL 仍是归属证据解析器。未来固定区域报告先调用 6AM，再把返回的显式
`target_tree_version + target_content_fingerprint` 传给 6AL 的 `current` 入口。6AL 不自行选择
树，`original` 合同也不改变。6AM 只固定目标上下文，不执行接触统计或区域聚合。

resolver 由最小权限的无登录 reader role 拥有。该角色只获得 selection history 和
published release 所需的最小读取权限。`PUBLIC`、`tongxingzhe_runtime`、
`tongxingzhe_region_publisher`、`tongxingzhe_region_mapping_writer` 和
`tongxingzhe_contact_provenance_writer` 都不能执行 resolver。`PUBLIC`、runtime、mapping writer 和 provenance
writer 也不能直接读取 selection history；publisher 只保留 0038 发布流程所需的既有 `SELECT`／`INSERT`。
本决定不新增 runtime bridge、HTTP 参数或 Flutter 入口。

## 后果与边界

既有 `is_current` 投影可以继续服务实时解析，但不能为历史报告提供目标树。
migration baseline 在迁移观察时间之前不能证明 current 选择。这个限制会让部分
较早的报告截止点不可判定，系统必须返回不可用，而不是选择一个看起来合理的树。

本 Slice 不注册生产区域报告，不实现完整区域网格、接触统计资格、父子或重叠
查询、`k=10`、贡献者保护、互补隐藏、snapshot lineage、capability、项目级目标树
配置、区域发布 UI、任意历史 `as-of`、报告修订／删除、HTTP、Flutter、Drift、缓存
或导出。它也不修改 6AL 的显式 target 参数合同。

## 验证

使用 synthetic 区域树、selection history 和 release 运行完整 PostgreSQL Docker
套件。`0055` migration、结构与权限 check、fixture、checksum、并发脚本和 dump／
restore 必须全部通过。fixture 至少覆盖无历史、cutoff 早于／等于／晚于 publication、
两次切换、baseline 观察下界前／等于／之后、草稿、缺失 release、指纹或发布时间
不一致、稳定不可用状态和敏感字段不出现在输出。

并发脚本分别让 publication 先拿锁和 resolver 先拿锁，确认两种顺序都只看到已提交
selection。恢复库不继承源 cluster roles，因此还要检查 reader owner、固定
`search_path`、`SECURITY DEFINER` 和 runtime／维护角色 ACL。
