# 个人阶段变更页面把远端历史与本地当前事实分开

状态：**已接受（2026-08-13）**。

关联：Issue #138、Slice 6AE-2；ADR-0122、ADR-0126、ADR-0127；
`ANALYTICS-010`、`ANALYTICS-011`、`ANALYTICS-015`、`ANALYTICS-016`、
`PRIVACY-008`、`UI-001`–`UI-007`、`TEST-006`。

## 决定

Flutter 在个人“最近七日”分析页增加独立的阶段变更卡片。卡片只调用 6AE-1 的固定
`GET /v1/personal/relationship-stage-change-summary`，请求只发送一次 `from_utc` 和一次
`until_utc`。当前项目仍由 PostgreSQL 从认证身份解析；客户端持有的项目 ID 只用于校验响应
scope 和废弃迟到结果，不能进入 query。

typed gateway 严格校验 `personal_relationship_stage_change_summary_result_v1`、
`relationshipChangedAtUtc`、回显期间、项目、`data_cutoff_utc == authorized_at_utc`，以及四个
非负安全整数。
`event_count` 必须等于 `upward_count + downward_count`，
`distinct_relationship_count` 不得大于事件数。响应有额外或缺失字段、未来时间、不规范 UTC、
scope 不匹配或不满足不变量时，客户端都把它视为无效响应，不显示部分结果。

卡片同时显示事件数、固定方向分布和去重对象×项目关系数。文案明确这些是按实际操作者归属的
个人事实：同一关系可以贡献多次事件，但只贡献一个去重关系；`upward` 和 `downward` 只描述
数值方向，不代表成功和失败。页面显示 Backend 的 `data_cutoff_utc`，不把客户端收包时间称为
数据截止。

这份历史汇总保持远端、只读和页面生命周期级。项目或期间改变、同步完成、项目设置返回、App
恢复或用户重试会重新读取；generation guard 丢弃旧 scope 的迟到响应。远端 loading 或失败只影响此卡片，
不能遮蔽本地接触分析、当前关系阶段或后续联系同意占比。本地最近七日统计仍在载入或失败时，
这张卡片也按共享 UTC 边界独立读取。

## 理由

当前关系阶段是带本地只读快照缓存的动态当前投影；阶段变更是按 `changed_at` 和可信操作者统计的
历史事件。把两者写入同一个 Drift 模型、同步覆盖或页面状态，会让当前分配、当前 lifecycle 和
本地新鲜度看似可以解释历史事件。独立 gateway 与卡片保留了这两个统计问题的边界。

客户端不能通过发送项目 ID 改变数据库授权范围，但仍需要用可信页面 context 检查响应项目，
以免缓存、代理或迟到响应把一个项目的个人事实显示到另一个项目。只有 personal workspace 构造
这张卡片；组织 workspace 不用个人入口试探权限。

## 后果与边界

本切片会增加 Flutter typed gateway、composition-root 注入、个人页卡片、中英文文案和自动测试。
它不增加 Drift 表、离线历史缓存、Outbox、逐事件列表、历史 as-of、任意期间选择、趋势、图表、
导出或管理阶段变更报告。阶段变更服务不可用时，页面不会用当前关系阶段分布或本地接触事实推算
替代值。
