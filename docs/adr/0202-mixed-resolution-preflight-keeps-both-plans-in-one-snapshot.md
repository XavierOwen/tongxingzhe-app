# ADR-0202：混合只读预检保留同一快照中的两份计划

- 状态：已接受
- 日期：2026-10-20
- Slice：7FD／private DB-only
- Issue：[#607](https://github.com/XavierOwen/tongxingzhe-app/issues/607)
- Requirement：`PII-021`、`TEST-174`、`MANUAL-163`
- 关联：[ADR-0193](./0193-historical-pending-facts-and-current-source-candidates.md)、[ADR-0198](./0198-project-relationship-resolution-plans-list-metadata-candidates.md)、[ADR-0201](./0201-missing-project-relationships-require-explicit-entry.md)

## 决定

0141 新增私有 `plan_personal_merge_mixed_resolutions_v1`，只为实际同时存在两类 pending 的代次提供共同只读预检。输入可信 user／workspace／current project／generation、共同 known 指纹、各类 pending 指纹及完整拟议来源映射；两个映射数组都须非空。单类请求继续使用原预检，不在这里增加回退模式。

函数在同一 outer command snapshot 内调用未改动的 STABLE 0129 和 0137，并核对两份完整 known-source JSON 一致。元素形状、完整集合、来源、授权、current 指针和陈旧指纹仍由各自原函数检查，不复制验证或候选算法。

结果精确四键：`contract_id` 为 `personal_merge_mixed_resolution_plan_v1`；`contact_resolution_plan` 和 `project_relationship_resolution_plan` 分别保留原生计划；`resolution_fingerprint` 是前三键 JSONB 的 PostgreSQL text／UTF-8 SHA-256。nested 候选不展平、不去重、不另排顺序，contact TEXT ID 原样保留；无当前项目关系仍只是原计划里的 metadata，不因此初始化。

## 快照不是写回资格

STABLE 读取可在 READ ONLY transaction 中执行，不取业务行锁或 generation fence，不写 request、audit、context 或事实。并发 writer 可以提交；一个已经建立的 command snapshot 仍可返回完整旧结果，下一 command 须重新核对范围和三指纹。复合指纹只绑定这份 metadata 结果，不保存授权、due、选择或 mixed 确认资格。

0141 只新增一个 owner-only SECURITY DEFINER／pg_catalog 函数，owner 沿用 0137；无新表、FK、权限或旧 catalog 变更。不读、返回或散列业务值，所有原 pending 载荷和五类已知来源事实保持不变。

## 边界

这不是混合 writer，不执行来源分配、当前选择、项目进入、end 或 payload 消费。现有两类 confirmer 会各自终结且锁序不同，不能因获得此结果就顺序嵌套；完整混合确认仍须独立的共同最终 manifest、完整预锁与单次终结合同。

PUBLIC／runtime、Backend／HTTP／UI、scheduler 和生产 active merge 均不开放。synthetic 读取、升级、并发、checksum 和恢复不证明完整 mixed split、生产身份、真实 PII、部署或设备验收。
