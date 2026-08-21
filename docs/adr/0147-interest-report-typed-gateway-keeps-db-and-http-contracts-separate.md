# ADR-0147：管理兴趣快照 typed gateway 保持 DB 与 HTTP 合同分离

- 状态：已接受
- 日期：2026-08-21
- 切片：Slice 6BB
- Issue：#189
- 需求：`ANALYTICS-037`、`PRIVACY-029`、`TEST-031`、`MANUAL-021`

## 背景

6BA 的 interest snapshot directory 通过数据库 private function 和 runtime bridge 提供 DB-only envelope。这个 envelope 为
授权和审计链保留 `access_contract_id`、`access_event_id`、`project_id`、`snapshots` 四个字段。6BA HTTP collection route
只需要给客户端目录结果，因此已经约定不转发内部 `access_contract_id`，HTTP 成功根对象只有 `access_event_id`、`project_id`
和 `snapshots` 三个字段。

6AZ 的显式详情使用另一条固定 HTTP GET，成功根对象只有 `access_event_id`、`snapshot_id` 和 `report`。Flutter 需要同时读取这两条
入口，但不能把 DB-only 字段、channel／current-city 类型或客户端推断混入 interest 合同。

## 决策

建立独立的 `InterestReportGateway`，提供有界目录读取、显式详情读取和 `close`。它使用固定的
`/v1/projects/:projectId/management-interest-report-snapshots` collection path 及其 `:snapshotId` detail path；只接受显式
UUID path 参数，不接受 query、GET body、筛选、分页或客户端提交的身份、时区、截止点和报告定义。

gateway 从 `IdentitySession` 取得 Bearer token。每次请求收到一次 `401` 时刷新并重试一次；第二次 `401`、其他 HTTP 错误、网络／
timeout、响应头错误或 JSON 不符合合同都映射为稳定 typed failure，不能循环刷新或返回部分结果。成功响应必须为 JSON 并带
`Cache-Control: no-store`。

目录 parser 严格要求 HTTP 三字段根对象和六字段摘要，最多接受 20 项并保留服务端的
`data_cutoff_utc DESC`、`released_at_utc DESC`、`snapshot_id DESC` 顺序。第一项不获得 current、latest、最新有效或取代语义；详情
只能使用用户明确选择的 project／snapshot。详情 parser 严格要求三字段根对象和 6AV 固定十格 interest report，包括固定 identity、
相邻期间、顺序、项目绑定、安全整数及 `suppressed = null`；额外字段、PII、错误顺序或错误绑定失败关闭。

## 后果

`access_contract_id` 保留在 DB-only 合同，不进入 HTTP 或 Dart，降低内部授权合同被误当成客户端资料的风险。目录和详情拥有自己的
不可变 Dart 类型，避免复用其他 report family 的 parser。解析结果只在内存中存在；6BB 不交付 UI、ViewModel、Widget、composition、
管理导航、Drift／SQLite、缓存、离线、同步、导出／下载、搜索、分页、报告创建／刷新／更正／删除或真实平台验收。

这也意味着 gateway 测试通过不能证明 Backend／数据库授权；6BA 的 Docker 和 6AZ 的 Backend 测试继续作为独立证据。目录首项不提供
任何“当前”或“最新”捷径，后续 consumer 必须明确让用户选择摘要，再读取对应详情。

## 验证

6BB 使用 synthetic HTTP、fake `IdentitySession` 和内存 `MockClient`，运行：

```bash
flutter pub get
dart analyze
flutter test --no-pub test/management_reports/
```

测试覆盖固定 path、三字段根对象、一次 `401`、20 项和稳定排序、空目录、显式 ID 传递、十格 strict parser、错误映射、PII／额外
字段拒绝、`no-store`、timeout、网络失败和 `close`。需要验证 DB／Backend 合同时，继续运行既有：

```bash
./tool/run_postgres_tests_in_docker.sh
```

6BB 不增加 PostgreSQL migration、fixture 或 Docker 合同；上述测试分别只证明 Flutter transport 和已有 DB／HTTP 合同，不证明生产
identity provider、真实账号、UI、Drift、缓存、离线、导出或六平台运行时。
