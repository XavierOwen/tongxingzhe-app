# 个人同意占比开关入口绑定当前项目

状态：**已接受（2026-08-13）**。

关联：Issue #128、Slice 6AD-4；ADR-0123、ADR-0124；
`TARGET-004`、`TARGET-010`、`ANALYTICS-003`、`ANALYTICS-014`、`TEST-005`。

## 决定

Backend 用同一路径的 `GET` 和 `PUT` 公开个人项目的后续联系同意占比开关。调用方不能
提交用户、空间、项目、指标、操作者或 capability。Backend 先验证 bearer token，再从可信
personal session context 取得当前项目。PostgreSQL bridge 仍按 verified issuer／subject 和项目
重新授权，不能把 session context 当成数据库授权。

`PUT` 只接受预期版本、boolean 启用值和 UUID 请求 ID。所有成功写入返回 `200`。数据库结果
没有说明本次调用是首次执行还是幂等重放，因此 Backend 不根据版本号猜测 `201`。`GET` 返回
未配置、启用或停用状态；停用状态保留最新的 disabled 配置元数据。HTTP 会验证数据库返回的
内部操作者 ID，但不向客户端发送它。

## 后果与边界

无效请求、无权、版本或幂等冲突，以及系统失败使用不同的稳定错误码。结果不缓存，错误不包含
身份或数据库消息。设置页可先读取当前版本，再提交变更；重复提交同一请求不会建立新版本。

本决定不增加 Flutter 设置页、离线配置、组织项目、管理能力或任意指标配置，也不改变开关的
当前语义。若未来需要组织项目开关或历史生效边界，必须新增授权与版本合同。
