# 管理报告 HTTP 发布固定报告定义并使用单 statement bridge

状态：**已接受（2026-08-12）**。

关联：Slice 6P；ADR-0099、ADR-0103、ADR-0104、ADR-0106；`ARCH-002`、`AUTHZ-001` 至 `AUTHZ-006`、`ANALYTICS-007` 至 `ANALYTICS-014`、`PRIVACY-001` 至 `PRIVACY-011`。

第一版生产发布端点是 `POST /v1/projects/:projectId/management-report-snapshots`。路径只含显式项目 UUID，请求体只含 UUID 幂等键 `release_request_id`。Backend 固定发布 `contact_sessions_by_channel_two_periods` v1；客户端不能提交报告定义、capability、时区、数据截止点、范围、筛选、授权时间、报告 JSON 或格值。

Backend 先验证 Bearer token，再把可信 issuer、subject、幂等键和项目交给 store。数据库只向 `tongxingzhe_runtime` 开放一个位于 `app_data` 的四参数 `SECURITY DEFINER` bridge。bridge 映射已经存在且活动的内部用户，并以固定报告 ID 和版本调用 Slice 6J 的私有可信发布函数。未知身份失败，不建立账号、个人空间或项目；runtime 继续不能进入 `app_private` 或读取成员、能力、发布尝试、快照和业务事实。

production store 通过一次 `pool.query` 执行 bridge，不建立可由上层回滚的显式事务。PostgreSQL 完成 statement 的隐式事务后 promise 才解决，HTTP handler 随后才写响应。若提交后网络中断，客户端使用同一幂等键重试；6J 会在重新授权后返回首次结果，不增加发布尝试或快照。

成功业务结果只返回 6J 的最小发布合同：固定报告身份、查询指纹、可信时区 revision、数据截止点、比较与发布快照 ID、结果状态和类型化原因。它不返回受保护报告、格值、贡献者或内部授权证据。无权返回 `403`，输入或合同冲突返回稳定 `400`／`409`，系统失败返回 `503`；错误不暴露 PostgreSQL 消息。

本决定不增加自动调度、Flutter 发布按钮、成员或能力治理、时区配置入口、动态分析、区域下钻、其他报告类型、缓存、图表或导出。
