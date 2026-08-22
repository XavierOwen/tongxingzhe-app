# ADR-0155：原始区域快照 HTTP 读取先认证再验证请求

- 状态：已接受
- 日期：2026-08-22
- Slice：6BJ
- Issue：[#205](https://github.com/XavierOwen/tongxingzhe-app/issues/205)
- 依赖：[#203](https://github.com/XavierOwen/tongxingzhe-app/issues/203)、6BI
- Requirement：`ANALYTICS-045`、`PRIVACY-037`、`TEST-039`、`MANUAL-029`

## 决定

6BJ 增加一个固定的 Backend HTTP 详情入口：

```text
GET /v1/projects/:projectId/management-original-region-report-snapshots/:snapshotId
```

handler 按以下顺序处理请求：

1. 解析 Bearer token，并验证 external `issuer + subject`；
2. 只有认证成功后，才验证 `projectId` 和 `snapshotId` UUID、query、GET body 的 `Content-Length`／`Transfer-Encoding` 声明以及专用 store 是否存在；
3. 只把 verified identity、显式 project UUID 和 snapshot UUID 传给 6BI 的 `ManagementOriginalRegionReportSnapshotStore`；
4. 等待 store Promise 完成后，再写 HTTP 响应。

缺少或无效身份始终先返回 `401 unauthenticated`。已认证请求的请求形状错误返回 `400`，不能通过 malformed path、query、GET body 或缺失 store 探测受保护资源状态。

## HTTP 合同

`completed` 只返回以下三个字段：

```json
{
  "access_event_id": "…",
  "snapshot_id": "…",
  "report": {}
}
```

响应状态和稳定错误码固定如下：

| 状态 | code |
| --- | --- |
| `401` | `unauthenticated` |
| `400` | `invalid_management_original_region_report_snapshot_request` |
| `403` | `management_original_region_report_snapshot_forbidden` |
| `404` | `management_original_region_report_snapshot_not_found` |
| `409` | `management_original_region_report_snapshot_untrusted` |
| `503` | `management_original_region_report_snapshot_unavailable` |

`404` 和 `409` 可以带 value-free 的 `access_event_id`。成功和错误响应都使用 JSON 与 `Cache-Control: no-store`。响应不得包含数据库消息、SQL、栈、external subject、授权关系、报告格、来源、贡献者、区域名称、坐标或 PII。

## 专用 store 与边界

HTTP 层只调用 6BI 的 `ManagementOriginalRegionReportSnapshotStore`。production composition 只注入 `PostgresManagementOriginalRegionReportSnapshotStore`；adapter 执行已有 6BI bridge 的一次固定 SQL。HTTP 层不调用 generic、current-city 或 interest store，不使用 `SessionContext`、`app_private` 或客户端 SQL，也不复制 0069 的授权、provenance、validator、撤权锁或 audit。

6BJ 不增加 migration、database check、fixture、PostgreSQL integration 或并发脚本。handler、route 和 composition 使用 synthetic identity 与 fake store 测试；这些测试不能替代 0069／0070 的 PostgreSQL 证据。Docker runner 仍运行既有 6BI 数据库套件，但不新增数据库步骤。

本决定不包含 snapshot directory、latest、分页、搜索、筛选、导出、缓存、离线、Flutter、Drift、UI、报告生成／发布／更正、删除、retention、warehouse、production JWT provider、真实账号或六平台真人运行时证据。

## 后果与验证

固定的认证顺序使 malformed 请求不能在身份验证前暴露路径或 store 状态；固定 wire、status 和 no-store 降低调用方对内部错误和受保护报告的误读风险。Promise gate 保证 response 不早于 store 完成。

只修改 HTTP 的开发者可以在仓库根目录运行：

```bash
cd backend/server
npm ci --ignore-scripts
npm run check
npm test
```

完整 Docker 套件仍可验证既有 0069／0070 数据库合同，但通过结果只证明 synthetic DB、bridge、ACL 和 parser；6BJ 的 HTTP 认证顺序、路由、wire 和 Promise gate 以 Backend 自动测试为证据。
