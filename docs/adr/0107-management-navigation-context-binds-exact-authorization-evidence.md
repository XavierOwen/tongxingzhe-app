# 管理分析导航上下文绑定完整授权证据

状态：**已接受（2026-08-11）**。

关联：Slice 6M；ADR-0078、ADR-0103、ADR-0106；`AUTHZ-001`–`AUTHZ-006`、`CTX-001`–`CTX-006`。

管理分析使用独立于个人 `SessionContext` 的导航上下文。Backend 只通过 `GET /v1/management-analysis/context` 发现当前具有 `view_anonymous_analytics` 的组织项目，并通过同路径的 `PUT` 明确选择一个项目。端点不接受用户、组织、成员、capability 或授权时间。

当前选择保存当次内部用户、组织、组织成员关系、项目、项目成员关系和查看能力 grant 的精确 ID。列表只有在这些证据仍对应当前有效授权链时才标记 current。退出后以新 membership 或 grant 重新加入不会复活旧选择；用户必须再次选择。没有有效选择时返回 `null`，即使只有一个可用项目也不自动选择。

选择函数在同一事务中调用 6I 私有解析器，并与撤权共享三层锁。runtime 只能执行两个窄 `app_data` 函数，不能直接读取选择表、成员表、grant 或 `app_private`。响应只含组织和项目 ID、名称，不含内部用户或授权证据。

导航上下文不是授权 token。6L 快照读取继续要求显式项目和快照 ID，并在每次请求中重新执行完整授权。一般组织 session、成员治理、快照列表、发布、Flutter UI、缓存和导出不属于本决定。
