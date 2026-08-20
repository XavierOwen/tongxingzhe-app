# ADR-0139：current 城市快照 HTTP 读取先认证再验证请求

- 状态：已接受
- 日期：2026-08-20
- Slice：6AR
- Requirement：`ANALYTICS-027`、`PRIVACY-019`、`TEST-021`

## 决定

Backend 使用独立的只读路由：

```text
GET /v1/projects/:projectId/management-current-city-report-snapshots/:snapshotId
```

handler 先解析 Bearer token 并完成 identity verification，再检查 project／snapshot UUID、query、GET body 和
current-city adapter 是否存在。无 token 或无效 token 时，不因其他输入无效而改变 `401 unauthenticated` 结果。认证
通过后，handler 只调用 6AQ 的 `ManagementCurrentCityReportSnapshotStore`，不使用 `SessionContext`、通用快照 reader、
目录、导出或客户端提供的查询条件。

adapter Promise 完成后才开始 HTTP 响应。成功响应序列化 6AP 已验证的 protected report。`403`、`404`、`409` 和 `503`
使用固定 code；未知 SQLSTATE、数据库消息、SQL、栈、external subject 和报告格不进入响应。所有响应保持 JSON
`Content-Type` 和 `Cache-Control: no-store`。

## 原因

current-city 读取已有 6AP 授权、provenance、时区／截止点、validator 和 value-free audit 合同。HTTP 层只应提供窄
wire seam，不重新解释报告或增加查询自由度。认证优先还可以让未认证调用不会通过错误的资源 ID、body、query 或
store 状态观察受保护端点的差异。

## 后果

- 客户端必须使用显式项目和快照 UUID；管理导航上下文不是读取授权输入。
- `401`、`400`、`403`、`404`、`409`、`503` 可以由 handler 单元测试稳定复现。
- route 测试必须覆盖带 `transfer-encoding` 的 GET body、Promise gate 和 no-store headers。
- 该 ADR 不交付 Flutter、目录、导出、离线缓存、同步、生产身份提供方或真实平台验收。
