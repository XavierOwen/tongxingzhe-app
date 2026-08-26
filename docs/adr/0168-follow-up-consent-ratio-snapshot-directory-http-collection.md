# ADR-0168：通过固定 HTTP GET 列出后续联系同意占比快照目录

- 状态：已接受
- 日期：2026-08-26
- Slice：6BW
- Issue：#231
- 依赖：#229、PR #230、0079
- Requirement：`ANALYTICS-058`、`PRIVACY-049`、`TEST-052`、`MANUAL-042`
- 相关决定：ADR-0165、ADR-0166、ADR-0167

## 背景

6BV 已把 6BU 的 consent-ratio snapshot directory 接到 Backend runtime。调用方可以用 exact external identity 和显式 project UUID 获得 metadata，
但还没有固定的 HTTP collection route。客户端需要先发现可选 snapshot，再把明确的 snapshot UUID 交给 6BT 的详情 route。

该入口必须保持 collection 与详情的边界。它不能自动选择 current、latest 或第一项，不能暴露 protected report，也不能复制 6BU／6BV 的数据库授权。

## 决定

新增固定的只读 collection route：

```text
GET /v1/projects/:projectId/management-follow-up-consent-ratio-report-snapshots
```

固定 path 命中后，handler 先验证 Bearer identity，再验证 project UUID、query、GET body 和
`PostgresManagementFollowUpConsentRatioSnapshotDirectoryStore`。GET 不接受 query 参数或 body；非零 `Content-Length`、`Transfer-Encoding` 等 body
声明属于无效请求。没有 token 或 token 验证失败时，handler 先返回 `401 unauthenticated`，不使用 malformed request 或缺失 store 探测资源状态。

认证成功后，handler 只把 verified identity 和显式 project UUID 交给 6BV 专用 store，并等待 store Promise 完成后才写响应。它不调用
`SessionContext`、generic directory、6BT detail store、`app_private` 或客户端 SQL。

成功 HTTP `200` 的 exact root keys 是：

```text
access_event_id
project_id
snapshots
```

每个 item 只含 6BV 已定义的六个 metadata keys：`snapshot_id`、`report_id`、`report_version`、`reporting_time_zone`、`data_cutoff_utc` 和
`released_at_utc`。空目录仍返回 `200` 和空数组。第一项只是 6BV 固定排序中的第一项，不表示 current、latest 或未被取代。

HTTP 使用固定状态和错误 code：

| 状态 | code |
| --- | --- |
| token 缺失或验证失败 | `unauthenticated` |
| project UUID、query 或 GET body 无效 | `invalid_management_follow_up_consent_ratio_snapshot_directory_request` |
| 6BV directory authorization forbidden | `management_follow_up_consent_ratio_snapshot_directory_forbidden` |
| verifier、store、parser、数据库或未知错误 | `management_follow_up_consent_ratio_snapshot_directory_unavailable` |

collection 业务结果不使用详情读取的 `404` 或 `409`。unknown、cross-project、filtered 或不可信的单份 snapshot 不在 collection wire 中产生详情错误；其他 method 或未匹配
path 仍可由通用 server 返回 `404`。
所有响应使用 `Content-Type: application/json; charset=utf-8` 和 `Cache-Control: no-store`。错误响应不得包含 protected report、period、ratio、coverage、
source、contributor、target、contact、external subject、授权关系、数据库消息、SQL、栈或 PII。

production composition 只注入该 dedicated store。6BW 不修改 0078／0079 的数据库授权、provenance、撤权锁、排序、audit 或 runtime bridge，不增加
PostgreSQL migration、check、fixture、integration、并发、Flutter、Drift、缓存、离线、导出、分页、筛选或自动 latest／current 语义。

## 后果与证据边界

固定 collection path 给客户端一个稳定的 metadata discovery 入口，同时保留显式 project／snapshot 选择和 6BT 详情授权边界。代价是客户端不能把
返回顺序解释为 current 或 latest，也不能从 collection route 得到报告正文。

Backend unit、real HTTP route 和 production composition tests 使用 synthetic identity 与 fake store。它们证明固定 method／path、认证顺序、请求形状、
专用 store、Promise gate、状态映射、三字段 wire、错误脱敏和 `no-store`。这些测试不证明 PostgreSQL 授权、部署端点、production identity、真实账号、
Flutter 消费、缓存、离线或 Android、iOS、macOS、Windows、Linux、Web 真人平台运行时。

## 验证

```bash
cd backend/server
npm ci --ignore-scripts
npm run check
npm test
```

6BW 不增加 PostgreSQL 测试步骤。需要回归前序数据库合同时，从仓库根目录运行：

```bash
cd ../..
./tool/run_postgres_tests_in_docker.sh
```
