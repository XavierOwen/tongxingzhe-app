# 管理报告详情显示固定定义、来源和隐私摘要

状态：**已接受（2026-08-13）**。

关联：Issue #142、Slice 6AG；ADR-0099、ADR-0105、ADR-0106、ADR-0108、ADR-0109；
`ANALYTICS-018`、`TEST-010`。

## 决定

管理报告详情直接显示 6L 单份快照响应已经严格解析的固定字段，不增加 wire 字段，不执行动态
查询，也不在 Flutter 重新计算指标或隐私。详情继续显示报告时区、数据截止和目录中的发布时间，
并固定显示以下身份与来源：

| 显示项目 | 界面标签／友好名称 | 稳定值 |
| --- | --- | --- |
| 报告定义 | 报告定义／Report definition 标签 | `contact_sessions_by_channel_two_periods@1` |
| 统计指标 | 接触场次／Contact sessions | `contact_sessions@1` |
| 数据来源 | 后端已接受的接触／Backend-accepted contacts | `(backend_accepted_contacts)` |
| 隐私规则 | 接触场次隐私规则 v1／Contact session privacy rules v1 | `(management_contact_session_privacy_v1)` |

友好名称不能替代稳定 ID 或 version；两者同时显示，便于复算、审计和发现定义漂移。未知固定 ID
不会被客户端猜测成另一个指标，必须沿用已经通过 gateway 合同校验的原值。

## 16 格隐私摘要

详情按 16 个固定“期间 × 渠道”格的 `privacy_status` 计数，分别显示 `displayed` 和
`suppressed` 格数。`displayed` 格只能来自已经带非负 `value_count` 的响应；`suppressed` 格的
值在响应中为 JSON `null`，页面显示“已隐藏”而不是 `0`，也不把隐藏值补回、聚合或排序。摘要的
屏幕阅读器节点使用稳定的 `management-report-privacy-summary` key。

中文和英文使用对应文案，但表达同一组固定字段。320×568 宽度和 200% 字号使用逐格紧凑布局；
元数据、摘要和边界说明必须可读取且不产生布局溢出。既有逐格期间／渠道／状态语义和目录返回后
焦点恢复不改变。

## 匿名边界

报告显示的是已经经过服务端阈值、贡献者保护、完整结果网格和互补隐藏的匿名管理事实。中英文
边界文案必须说明这些规则用于降低披露风险，但**不构成形式化的不可重识别保证**，也不证明所有
外部资料组合都安全。页面不得把结果表述为绝对匿名、个人绩效、排名或因果结论。

## 范围与后果

本决定只约束已有固定报告详情的呈现、语义和测试。它不改变 PostgreSQL、Backend、权限、capability、
快照发布／读取审计或 wire contract，不增加导出、下载、图表、缓存、动态报告、历史 `as-of`、更正版
或删除规则，也不触及 PII 和 Slice 7。
