# ADR-0169：后续联系同意占比 typed gateway 分离 DB、HTTP 与 Flutter 合同

- 状态：已接受
- 日期：2026-08-26
- Slice：6BX
- Issue：[#233](https://github.com/XavierOwen/tongxingzhe-app/issues/233)
- 依赖：[#231](https://github.com/XavierOwen/tongxingzhe-app/issues/231)、[#225](https://github.com/XavierOwen/tongxingzhe-app/issues/225)、[#229](https://github.com/XavierOwen/tongxingzhe-app/issues/229)
- Requirement：`ANALYTICS-059`、`PRIVACY-050`、`TEST-053`、`MANUAL-043`
- 相关决定：ADR-0165、ADR-0168

## 背景

6BW 为 6BU／6BV 的 consent-ratio snapshot directory 提供固定 HTTP collection route，6BT 为一份用户明确选择的 snapshot 提供固定 HTTP detail route。
Flutter 需要消费这两个入口，但不能把 PostgreSQL 的内部 envelope、授权 lineage 或受保护报告的未公开字段带入客户端边界。

collection 与 detail 还必须保持两个不同的选择语义。collection 只返回最多 20 项 metadata；它的第一项不是 current 或 latest。detail 只读取调用方明确
从目录中选择的 project 和 snapshot，不能在客户端重算比例、补回隐藏值或重新选择快照。

## 决定

6BX 建立独立的 `FollowUpConsentRatioReportGateway`。它提供目录读取、显式详情读取和 `close`，结果使用不可修改的内存类型。它不复用 channel、interest、
current-city 或 original-region gateway，也不连接 Drift、文件、secure storage、outbox、缓存或后台同步。

gateway 的目录请求固定为：

```text
GET /v1/projects/:projectId/management-follow-up-consent-ratio-report-snapshots
```

详情请求固定为：

```text
GET /v1/projects/:projectId/management-follow-up-consent-ratio-report-snapshots/:snapshotId
```

两个请求都只发送 GET、显式 project UUID 和必要的 snapshot UUID，不发送 query 或 body。gateway 从 `IdentitySession` 取得 Bearer token。第一次收到 `401` 时，
它强制刷新并只重试一次。其他 HTTP 状态、identity、timeout、network、响应头、JSON 和 parser 错误映射为稳定 typed failure；关闭后的 gateway 也失败关闭。

目录 parser 只接受 HTTP 三字段 root：`access_event_id`、`project_id` 和 `snapshots`。每项只接受六个 metadata 字段，最多 20 项，允许空数组，拒绝重复、
错误 project、无效 UUID、错误报告身份、非 UTC 时间和服务端固定降序之外的顺序。DB-only 的四字段 envelope（包括 `access_contract_id`）不进入 Dart 类型。

详情 parser 只接受 HTTP 三字段 root：`access_event_id`、`snapshot_id` 和 `report`。它严格解析 6BT 已保护的
`contact_target_follow_up_consent_ratio_two_periods@1`，检查 project／snapshot／summary 绑定、两个完整期间、ratio 算术、coverage 顺序、非负安全整数和
`suppressed = null`。额外字段、PII 形状、contact、target、contributor、source、隐藏前值、错误绑定、错误期间或不安全整数均失败关闭。

成功响应必须是 JSON 并带 `Cache-Control: no-store`。gateway 只把已解析的 metadata、用户明确选择的 summary 和已保护 detail 交给调用方，不修改服务端结果。

## 取舍

客户端解析而不是直接转发 JSON，可以在 Dart 边界拒绝 key 漂移、项目错绑、顺序变化、数值溢出和隐私字段泄漏。代价是每个固定 report family 都需要自己的
类型与 parser；这个重复是有意的，因为各 report family 的字段、来源和隐私规则不同。

collection 与 detail 共用一个 gateway 生命周期，但保留独立方法和类型。这样调用方可以在用户选择 summary 后发起 detail 请求，同时不能把目录第一项变成隐含的
latest 语义。

## 边界与验证

6BX 只增加 Dart interface、HTTP adapter、strict parser 和 synthetic Flutter tests。fake `IdentitySession` 与内存 `MockClient` 验证固定 path、请求形状、Bearer、
一次 `401` 刷新、目录／详情 wire、空目录、20 项上限、固定排序、详情数学与隐私边界、错误映射、`no-store`、不可修改集合和 `close`。

这些测试只证明 Flutter transport、parser 和内存边界。它们不证明 6BT／6BW 的 Backend authorization、PostgreSQL provenance、部署端点、production identity、UI、
Drift、缓存、离线、导出或 Android、iOS、macOS、Windows、Linux、Web 真人平台运行时。6BX 不增加数据库 migration、Backend route、runtime bridge、分页、筛选、
current／latest 选择或生产验收。

## 验证命令

```bash
flutter pub get
dart analyze
flutter test --no-pub test/management_reports/http_follow_up_consent_ratio_report_gateway_test.dart
flutter test --no-pub
```

6BX 没有新的 PostgreSQL 测试步骤。需要回归前序数据库合同时，从仓库根目录运行：

```bash
./tool/run_postgres_tests_in_docker.sh
```

Docker 命令只回归已有数据库合同，不证明 Flutter gateway 或真实平台运行时。
