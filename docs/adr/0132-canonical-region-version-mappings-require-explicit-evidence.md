# 规范区域跨版本映射只接受显式一对一证据

状态：**已接受（2026-08-14）**。

关联：Issue #151、Slice 6AK；ADR-0110 至 ADR-0115；`REGION-006` 至 `REGION-010`、
`ANALYTICS-012`、`PRIVACY-010`、`TEST-007`、`TEST-014`。

## 决定

没有原始坐标可按新边界重新解析时，旧规范区域节点只能凭一条私有、追加式的一对一映射证据进入指定的新树版本。映射同时绑定来源和目标的 `tree_version`、`region_id` 与冻结内容指纹。两棵树必须已发布，两个节点必须属于各自版本，版本必须不同。缺失证据、错误指纹、未知节点、草稿树、拆分、合并或冲突目标都失败关闭；系统不按名称、父链或几何相似度猜测。

登记与解析函数由无登录、无成员的 `tongxingzhe_region_mapping_writer` 拥有。区域发布身份只有函数执行权，没有映射表写入权；表级 trigger 只允许函数的不可伪造 owner 身份插入。登记保存稳定 mapping ID、request ID、固定 evidence contract、外部证据的 SHA-256 摘要和数据库记录时间，不保存自由文本、坐标、接触资料或 PII。同一 request 的完全相同重试幂等；载荷漂移、同一来源到多个目标的拆分，以及多个来源到同一目标的合并都被拒绝。映射事实不能更新、删除、清空或静默取代。

私有解析函数只在调用方提供的来源、目标版本和两个内容指纹与唯一登记事实精确一致时返回 `mapped`。它不组合映射链，也不向 runtime、Backend 或 Flutter 开放。目标树是否是某份报告在数据截止点的 current 版本，仍由未来报告合同另行确定。

## 后果

`original` 视图继续读取 contact revision 保存的原区域、树版本和内容指纹；6AK 不改写这些来源事实。有坐标的来源可以由未来切片按指定报告截止点重新解析，只有 `resolved_region_only` 需要显式映射。`pending_resolution`、`not_applicable` 和来源不完整记录没有可映射的区域 ID。

本决定只提供 future current projection 的证据前置条件。它不注册生产区域报告，也不交付完整网格、互补隐藏、授权、快照 lineage、HTTP、Flutter、缓存、导出、历史 as-of、更正版、删除或一对多／多对一映射。

## 验证

完整 PostgreSQL Docker 套件从空库运行 0053 migration、结构与权限 check、synthetic fixture 和双事务竞争测试，然后在第二个 PostgreSQL 16 cluster 恢复 dump 并重复验证。通过只证明数据库合同拒绝已枚举的伪造、冲突和双写；它不证明维护者的外部证据正确，也不证明真实区域等价。
