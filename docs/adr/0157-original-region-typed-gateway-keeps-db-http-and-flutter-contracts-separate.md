# ADR-0157：原始区域 typed gateway 分离 DB、HTTP 与 Flutter 合同

- 状态：已接受
- 日期：2026-08-25
- Slice：6BL
- Issue：[#209](https://github.com/XavierOwen/tongxingzhe-app/issues/209)
- 依赖：[#205](https://github.com/XavierOwen/tongxingzhe-app/issues/205)、[#207](https://github.com/XavierOwen/tongxingzhe-app/issues/207)
- Requirement：`ANALYTICS-047`、`PRIVACY-039`、`TEST-041`、`MANUAL-031`

## 决定

6BL 建立独立 `OriginalRegionReportGateway`。它读取 6BK 的固定 collection path 和 6BJ 的显式 detail path，不复用 channel、current-city 或
interest 类型。调用方只提供 canonical project UUID 和目录中明确选择的 summary；gateway 不自动选择首项，也不推断 current、latest 或 replacement 状态。

6BK 的数据库 envelope 有四项，包含内部 `access_contract_id`。HTTP 目录和 Dart 类型只接受 `access_event_id`、`project_id`、`snapshots` 三项。
目录项只有六个 metadata 字段，最多 20 项，无重复，并保持服务端 cutoff、release time 和 snapshot ID 降序。6BJ 详情只接受
`access_event_id`、`snapshot_id`、`report` 三项。

详情 parser 固定 original-region report 的 17 个 keys。它核对 project／snapshot／summary、original view、city granularity、两个相邻完整期间、
selected source tree tuple、previous／current 相同城市集合与顺序、连续 `cell_order`、安全整数和 `suppressed = null`。额外字段、其他报告族、来源记录、
贡献者、contact、location、geometry、区域名称、坐标或 PII 失败关闭。

gateway 每次从 `IdentitySession` 取得 Bearer token。一次 `401` 最多刷新并重试一次。成功必须为 JSON 并带 `Cache-Control: no-store`；HTTP、identity、
timeout、network、响应头或 parser 错误映射为稳定 typed failure。解析结果只留在内存，`close` 关闭 HTTP client。

## 边界与验证

6BL 使用 synthetic HTTP、fake `IdentitySession` 和内存 `MockClient` 验证两个固定 path、token、一次 `401`、strict parser、目录边界、详情绑定、
source tree、城市网格、隐私状态、响应头、错误映射、不可变集合和 `close`。

本决定不修改 Backend 或 PostgreSQL，也不增加 Widget、ViewModel、composition、Drift、缓存、离线、同步、导出、下载、分享、生产 identity、真实账号或
六平台真人运行时证据。Dart 测试不能替代 6BJ／6BK 的 HTTP、数据库授权、审计、ACL 或 provenance 证据。
