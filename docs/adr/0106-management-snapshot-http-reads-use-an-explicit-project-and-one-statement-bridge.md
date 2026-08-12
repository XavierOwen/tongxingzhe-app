# 管理快照 HTTP 读取使用显式项目和单 statement bridge

状态：**已接受（2026-08-11）**。

关联：Slice 6L；ADR-0078、ADR-0099、ADR-0103、ADR-0105；`ARCH-002`、`AUTHZ-001`–`AUTHZ-006`、`ANALYTICS-007`–`ANALYTICS-014`、`PRIVACY-001`–`PRIVACY-011`。

第一版生产读取端点是 `GET /v1/projects/:projectId/management-report-snapshots/:snapshotId`。它只接受显式项目和快照 UUID，不接受报告 JSON、capability、时区、截止时间、筛选或内部用户 ID。Backend 验证 Bearer token 后，把可信 issuer、subject 和两个 UUID 交给管理快照 store；它不使用个人 `SessionContext` 或其中的 capability 来授权组织报告。

数据库只向 `tongxingzhe_runtime` 开放一个位于 `app_data` 的四参数 `SECURITY DEFINER` bridge。bridge 使用固定 `pg_catalog` search path，把外部身份映射到已经存在且活动的内部用户，再调用 Slice 6K 的私有三参数读取。未知身份失败，不建立用户、个人空间或项目。runtime 继续不能使用 `app_private`，也不能直接读取快照、审计、成员关系或执行私有授权函数。

生产 store 通过一次 `pool.query` 执行 bridge，不建立可由上层控制的显式事务。PostgreSQL 完成隐式事务后 query promise 才解决；HTTP handler 等待该 promise，再序列化报告。这样客户端不会在访问事件仍可被外层回滚时收到报告。提交后网络中断可能让客户端没有收到报告，但访问事件已经存在；重试会形成另一条已授权访问事件。

成功只返回 access event ID、快照 ID 和数据库保存的受保护报告。未知与跨项目统一为 `404`，同项目不可信 provenance 为 `409`，无权为 `403`；错误响应不包含报告格、授权关系或 PostgreSQL 消息。所有响应使用 `Cache-Control: no-store`。

本决定不建立组织项目列表或 organization session context。组织项目发现与选择、成员治理、报告列表或 latest、发布端点、缓存、导出和 Flutter UI 分别进入后续工作单元。
