# ADR-0165：后续联系同意占比快照 HTTP 读取先认证再验证请求

- 状态：已接受
- 日期：2026-08-26
- Slice：6BT
- Issue：#225
- 依赖：#223、0077
- Requirement：`ANALYTICS-055`、`TEST-049`、`MANUAL-039`
- 相关决定：ADR-0164

## 背景

6BS 已将 6BR 的 private snapshot reader 接到 Backend runtime。它提供 exact external identity bridge 和专用 store，但在 6BS 的范围内没有定义
HTTP route、Bearer verification 或 HTTP 错误 wire。客户端需要读取一份已经明确指定的后续联系同意占比快照，不能因此获得通用数据库查询、自动 latest 选择或
另一套授权逻辑。

## 决定

新增一个固定的只读详情入口：

```text
GET /v1/projects/:projectId/management-follow-up-consent-ratio-report-snapshots/:snapshotId
```

在该固定 path 命中后，handler 先解析并验证 Bearer identity；只有认证成功后，才检查 project／snapshot UUID、query、GET body 和 6BS 专用 store。
认证失败时，即使 path 参数、query、body 或 store 不合法，也返回 `401 unauthenticated`，不让未认证请求探测后续验证或组合状态。

GET 不接受 query 参数或 body。非零 `Content-Length` 或 `Transfer-Encoding` 等声明的 body 也属于无效请求。认证通过后，handler 只将 verified `issuer + subject`、
显式 project UUID 和 snapshot UUID 传给 `PostgresManagementFollowUpConsentRatioReportSnapshotStore`。它不调用 `SessionContext`、generic reader、其他
report-family store、`app_private` 或客户端 SQL。handler 等待 store Promise 完成后才写响应。

成功 HTTP wire 的 exact root keys 是 `access_event_id`、`snapshot_id` 和 `report`。`report` 逐字来自 6BS 已保护的
`contact_target_follow_up_consent_ratio_two_periods@1` snapshot；HTTP 层不重算比例、不恢复 `suppressed` 值，也不改写 snapshot。

HTTP 使用固定状态和错误 code：

| 状态 | code |
| --- | --- |
| `401` | `unauthenticated` |
| `400` | `invalid_management_follow_up_consent_ratio_report_snapshot_request` |
| `403` | `management_follow_up_consent_ratio_report_snapshot_forbidden` |
| `404` | `management_follow_up_consent_ratio_report_snapshot_not_found` |
| `409` | `management_follow_up_consent_ratio_report_snapshot_untrusted` |
| `503` | `management_follow_up_consent_ratio_report_snapshot_unavailable` |

`404`／`409` 可以带 store 提供的 value-free `access_event_id`，但错误不得包含报告格、授权关系、external subject、数据库消息、SQL、栈或 PII。所有
成功和错误响应使用 `Content-Type: application/json; charset=utf-8` 与 `Cache-Control: no-store`。

production composition 只注入 6BS 专用 store。6BT 不复制 6BR／6BS 的授权、provenance、validator、撤权锁或 audit，也不增加 PostgreSQL migration、
reader、directory、latest／current 选择、分页、筛选、Flutter、Drift、导出、缓存、离线、同步、replacement、删除、retention、warehouse 或
真人平台证据。

## 后果与证据边界

固定 path 和认证优先顺序让 HTTP transport contract 独立于既有数据库授权合同。专用 store 和三字段 wire 也使 report family、内部数据库 envelope 和
错误细节不会由通用路由混合。代价是客户端必须明确选择 project／snapshot，不能依赖一个自动发现或 latest API。

handler、real HTTP route 和 production composition 测试使用 synthetic identity 与 fake store；它们证明 method／path、认证顺序、请求形状、Promise gate、
错误映射、wire、错误脱敏和 `no-store`，不证明 production identity provider、已部署端点、真实账号、Flutter 消费或 Android、iOS、macOS、Windows、
Linux、Web 真人平台运行时。既有 6BS Docker suite 继续证明 0077／0076 的 PostgreSQL 合同，但不能替代 HTTP 测试。

## 验证

```bash
cd backend/server
npm ci --ignore-scripts
npm run check
npm test
```

如果同时回归 6BS PostgreSQL 合同，从仓库根目录运行：

```bash
cd ../..
./tool/run_postgres_tests_in_docker.sh
```
