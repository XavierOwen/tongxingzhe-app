# ADR-0145：管理兴趣快照 HTTP 读取先认证再验证请求

- 状态：已接受
- 日期：2026-08-21
- Slice：6AZ
- Issue：#185
- 依赖：#183、6AY
- Requirement：`ANALYTICS-035`、`PRIVACY-027`、`TEST-029`、`MANUAL-019`

## 决定

Backend 使用一个固定的只读路由：

```text
GET /v1/projects/:projectId/management-interest-report-snapshots/:snapshotId
```

handler 按以下顺序处理请求：

1. 解析 Bearer token。
2. 完成 identity verification。
3. 检查 project 和 snapshot UUID、query、GET body 以及 6AY store 是否存在。
4. 把 verified identity、显式 project UUID 和 snapshot UUID 传给 6AY store。
5. 等待 adapter Promise 完成，再写 HTTP 响应。

未认证请求先返回 `401 unauthenticated`。认证通过后，输入错误返回
`400 invalid_management_interest_report_snapshot_request`。handler 不使用
`SessionContext`，不读取 private schema，也不接受筛选、报告定义、时区、截止点或客户端 SQL。

## HTTP 合同

成功响应保留 6AY 返回的 6AX protected report：

```json
{
  "access_event_id": "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
  "snapshot_id": "88888888-8888-4888-8888-888888888888",
  "report": {}
}
```

状态映射如下：

| 情况 | 状态和 code |
| --- | --- |
| token 缺失或验证失败 | `401 unauthenticated` |
| UUID、query 或 GET body 无效 | `400 invalid_management_interest_report_snapshot_request` |
| 6AY authorization forbidden | `403 management_interest_report_snapshot_forbidden` |
| 快照不存在或跨项目 | `404 management_interest_report_snapshot_not_found` |
| interest provenance 不可信 | `409 management_interest_report_snapshot_untrusted` |
| verifier、adapter、数据库或未知 SQLSTATE 异常 | `503 management_interest_report_snapshot_unavailable` |

`404` 和 `409` 可以返回不含报告值的 `access_event_id`。错误不返回数据库消息、SQL、栈、external subject、授权关系、报告格或 PII。
成功和错误响应都使用 JSON `Content-Type` 和 `Cache-Control: no-store`。

## 边界

6AZ 只调用 6AY 的 `ManagementInterestReportSnapshotStore`。它不复制 6AX 的授权、provenance、validator、锁或审计逻辑，
不调用通用报告 reader、current-city reader、`SessionContext` 或 private function。

本 Slice 不增加 PostgreSQL migration、check、fixture、并发脚本或新的 Docker 数据库合同。CI 仍运行已有 6AY PostgreSQL suite，
6AZ 的新增证据来自 Backend handler、route 和 production composition 测试。Docker 不是 HTTP 测试替代品。

本 Slice 不包括目录、分页、搜索、Flutter、Drift、导出、下载、缓存、离线、同步、快照创建／刷新／更正／删除、生产 identity provider、
真实账号或任何平台真机证据。

## 后果

- HTTP 层有固定的认证顺序和错误合同。
- 6AY 继续是唯一的 interest snapshot authorization 和 parser boundary。
- `no-store` 防止浏览器和中间层缓存受保护报告。
- HTTP 测试可以在 synthetic store 上独立验证，不需要新增数据库 fixture。
