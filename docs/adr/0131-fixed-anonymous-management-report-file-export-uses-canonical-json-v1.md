# 固定匿名管理报告文件导出使用 canonical JSON v1 与独立导出审计

状态：**已接受（2026-08-14）**。

关联：Issue #145、Slice 6AH；ADR-0103、ADR-0105、ADR-0108、ADR-0130；
`AUTHZ-007`、`ANALYTICS-019`、`PRIVACY-013`、`TEST-011`。

## 决定

固定匿名管理报告文件导出只针对一份已经发布且具有可信 v2 来源的固定快照，使用显式项目和快照 ID 的窄 GET 返回 `management_report_snapshot_export_v1`。顶层合同固定为 `export_contract_id`、`snapshot_id`、`released_at_utc` 和 `report`；`report` 复用 6L 的固定定义、来源、时区、截止点、期间和 16 格 `cells`，`displayed` 使用大于等于 10 的整数，`suppressed` 保持 JSON `null`。请求不接受报告、格式、时区、截止点、筛选或其他查询参数，也不执行动态重算。

导出请求必须在同一数据库授权边界内同时具备 `view_anonymous_analytics` 与独立 `export_management_reports` capability；`release_management_reports` 不包含查看或导出权。服务端每次重新验证账号、组织／项目成员关系和两项 capability，并从已保存的受保护快照生成稳定的 UTF-8 JSON；客户端尚未落盘、分享或读取不属于本决定的事实。

每次通过身份验证并完成完整授权的导出请求追加独立、不可变的管理报告导出审计。审计记录最小授权和结果元数据，证明服务端已授权生成并准备交付，不保存报告格、贡献者、推广对象、地点、PII 或隐藏前值，也不把导出伪装为普通快照读取。网络中断后的重试形成新的导出事件。该决定不扩展 Flutter、CSV、六平台保存／分享、区域报告、任意查询、缓存、报告保留或 Slice 7 删除流程，也不宣称形式化不可重识别。

## 选择与边界

选择 canonical JSON v1 是为了先固定机器可读的跨服务合同，并复用已经通过隐私保护的不可变快照。这里的 canonical 指本合同固定的 key 顺序、无多余空白和 UTC 毫秒时间格式，不表示实现 RFC 8785。CSV、客户端文件能力和人类可读版式需要另行评估。推广对象资料导出仍由 `export_target_pii` 和 Slice 7 的 PII 边界约束，不能与匿名报告文件导出混用。
