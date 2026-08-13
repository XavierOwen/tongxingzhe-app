# 地点来源四层证据使用同一条可重跑对账路径

状态：**已接受；本地四层合成证据已验证（2026-08-12）**。

关联：Issue #96、Slice 6V；ADR-0112、ADR-0113、ADR-0114；`CONTACT-010`、
`REGION-001`、`REGION-002`、`REGION-005`、`REGION-007` 至 `REGION-009`、
`PRIVACY-007`、`PRIVACY-010`、`PRIVACY-011`、`TEST-003`、`TEST-005`。

## 决定

地点来源只有在一条可重跑的对账路径同时经过以下边界后，才算完成四层证据：

```text
Flutter command → Backend Store → PostgreSQL revision/provenance → warehouse/privacy boundary
```

路径使用固定的 synthetic fixture。共享 CSV 覆盖 `resolved_from_coordinates`、
`resolved_region_only`、`pending_coordinates` 和 `not_applicable`；数据库 fixture
另行覆盖历史 `legacy_incomplete`。集成路径还覆盖 submit、revise、
resolve-conflict 和 void。地点与来源在 revision、冲突合并和作废复制中必须保持为
一个事实组。

Backend Store 对 0039 trigger 的客户端地点错误只允许窄映射：只有 PostgreSQL
`SQLSTATE 23514` 与已登记固定错误文字同时匹配时，才返回 `rejected`。source 形状
错误使用 `invalid_location_source`，location 形状错误使用 `invalid_location`；HTTP
状态为 `422`，批量结果保持 permanent failure。未知 `23514`、其他数据库错误和
结果合同错误继续向上抛出，HTTP 层返回 `503 sync_unavailable`。映射不能按整个
SQLSTATE 类别放宽，否则新的约束或权限故障会被错误标成用户输入。

错误响应、同步健康、管理报表、匿名输出和 warehouse 不得包含精确坐标。Backend 当前没有应用日志 sink。部署平台的访问日志不得记录请求体或响应体。
有权的个人同步 conflict／pull 可以取得自己的精确地点事实；这是同步授权边界，
不是管理或匿名输出。PostgreSQL provenance 表仍是私有 `app_data` append-only 表，
runtime role 不直接读取它；warehouse trigger 在分析边界移除地点和来源字段。

## 运行证据

- `backend/database/fixtures/0039_contact_location_provenance.sql` 证明 SQL shape、
  revision seam、冲突原子性、append-only、warehouse scrub、历史回填和 runtime
  权限。
- `backend/database/fixtures/shared/contact_location_source_v1.csv` 是 Flutter、
  Backend 和 PostgreSQL 断言共用的四种当前状态及错误输入。
- Backend Store 和 HTTP tests 证明固定错误映射、`422` permanent 结果、未知数据库
  错误上抛以及响应不回显坐标。
- Docker runner 在 PostgreSQL fixture 后使用 `node:24-bookworm`，编译并运行
  `backend/server/test/contact-location-evidence.integration.ts`。该测试调用真实
  Backend→PostgreSQL 路径，并核对上述状态、匿名管理报告和隐私边界。

只有 Node 24 阶段编译并执行 integration source，且以零退出码完成时，
才能声称本地四层合成证据已经闭合。SQL Docker 套件、Backend 单元测试、
Flutter 测试和平台 build 各自回答不同问题，不能互相替代。

## 后果与边界

这项决定让错误分类和地点来源证据在 SQL、Backend 和文档中使用同一组名称，也让
失败重试不会把永久地点错误伪装成暂时服务故障。它不证明 Supabase Auth、生产密钥、
真实用户资料、真实设备 GPS、六个平台运行或生产部署已经通过。所有 Docker fixture
和 integration 数据都必须是 synthetic，并在临时数据库中运行。
