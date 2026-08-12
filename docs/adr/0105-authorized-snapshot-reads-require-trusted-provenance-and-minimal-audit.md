# 授权快照读取只接受可信 provenance 并记录最小审计

状态：**已接受（2026-08-11）**。

关联：Slice 6K；ADR-0099、ADR-0103、ADR-0104；`AUTHZ-001`–`AUTHZ-006`、`ANALYTICS-007`–`ANALYTICS-014`、`PRIVACY-001`–`PRIVACY-011`。

受保护管理报告快照的私有读取入口只接收内部用户、项目和快照 ID。数据库固定要求 `view_anonymous_analytics`，并在读取报告的同一事务中解析账号、组织成员、项目成员和查看能力。`release_management_reports` 不包含查看能力，调用方也不能提交 capability、授权时间、报告 JSON、时区、截止时间或可复用授权 token。

成功读取必须同时满足两个条件：快照属于请求项目，并且一条成功的 Slice 6J v2 发布记录准确指向该快照。legacy v1、缺失或伪造 provenance 均不返回 `protected_report`。已授权调用中的未知快照和跨项目快照统一返回 `not_found`，避免用结果区分其他项目是否存在该 ID；provenance 不可信则返回独立的 `untrusted_provenance` 状态。

每次已授权调用都在同一事务中追加一条不可变访问事件。事件保存授权关系、能力 grant、请求和命中的快照、报告身份、数据库访问时间、状态与原因码，但不复制 `protected_report`、格值、贡献者或隐藏前数值。未授权调用以 `42501` 失败，不返回报告，也不写访问事件。读取与撤权使用同一组 transaction lock，因此读取先行时撤权等待，撤权先行时读取失败。

“报告与审计同一事务提交”是当前私有合同的一部分。若未来服务层把调用包在显式外层事务中，在收到报告后又主动回滚，数据库也会回滚访问事件。生产 runtime bridge 必须把读取作为单条自动提交操作，或在事务提交成功后才向客户端交付报告；不能把当前私有函数直接开放为通用 SQL 能力。

本决定不开放 runtime、HTTP、Flutter、缓存、导出、快照列表或 production session context。新增表和函数继续对 `tongxingzhe_runtime` 与 `PUBLIC` 保持零权限。
