# Backend 身份上下文、项目与接触同步

这个模块提供可信 session context、个人推广项目选择／创建、规范区域解析、问卷管理发布、同步 command 和 change feed。所有端点都先验证 Supabase access token，再取得内部用户和允许访问的项目。同步协议处理已提交接触、追加更正、带原因作废、跨设备更正的自动合并与显式解决、未获回应尝试和账号私有草稿；设备专用草稿不会离开本机。

客户端不能提交 `app_user_id`、role 或 capability。上传会把 payload 的 workspace 和 project 与可信上下文交叉核对。拉取也会核对 query 范围，并只接受属于同一范围的不透明 cursor。响应不返回外部 subject、email 或 token。三个 HTTP 入口共用严格的 bearer header 解析器，防止端点之间出现不同的认证规则。

cursor 不存在或不属于当前用户、空间和项目时，端点返回 `400 invalid_cursor`。未分类的数据库失败返回 `503 sync_unavailable`，不把内部 SQL 错误文字暴露给客户端。

## 规范区域解析合同

`POST /v1/regions/resolve` 接受 bearer token 与合法的 `latitude`、`longitude`。Backend 调用受限的 PostgreSQL 函数，只查询当前发布的区域树版本。

- 命中时返回 `200`、最小规范区域和从根到该节点的父链；
- 没有命中时返回 `202` 和 `pending`；
- 坐标无效返回 `400 invalid_coordinates`；
- 身份无效返回 `401 unauthenticated`；
- 数据库或服务不可用返回 `503 region_resolution_unavailable`。

响应不回显 token、外部 subject 或 email。Flutter 必须先原子安装返回的父链，再把地点改成已解析状态。任何失败都保留原坐标，不能改写成 `N/A`。

## 问卷管理合同

只有最新可信上下文含 `manage_analysis_definitions` 时，以下入口才可用：

| 方法与路径 | 行为 |
| --- | --- |
| `GET /v1/questionnaire-administration` | 列出当前版本、历史版本和草稿 |
| `POST /v1/questionnaire-drafts` | 建立空白草稿，或复制指定的已发布版本 |
| `GET /v1/questionnaire-drafts/:id` | 读取当前项目中的单个草稿 |
| `PUT /v1/questionnaire-drafts/:id` | 按预期 revision 保存受控定义 |
| `POST /v1/questionnaire-drafts/:id/publish` | 用 request ID 与发布说明建立新版本 |

Backend 不接受客户端提供的用户、空间或项目范围。每次请求都重新验证身份和上下文；发布前还会重读草稿、revision 与完整定义。PostgreSQL 再检查个人空间所有权并在项目锁内发布。网络重试不会产生重复版本，并发发布后仍只有一个 current 版本。

## 配置

Backend 需要以下环境变量：

| 变量 | 含义 |
| --- | --- |
| `DATABASE_URL` | Backend 专用 PostgreSQL login；该 login 必须继承 `tongxingzhe_runtime` |
| `AUTH_ISSUER` | Supabase Auth 的精确 issuer，例如 `https://PROJECT.supabase.co/auth/v1` |
| `AUTH_AUDIENCE` | access token audience；默认 `authenticated` |
| `AUTH_JWKS_URL` | 可选 JWKS 地址；默认由 issuer 加 `/.well-known/jwks.json` 得到 |
| `PORT` | HTTP 端口；默认 `8080` |

正式环境只接受 JWKS 提供的 `ES256` 或 `RS256` 公钥。项目必须先启用 [Supabase asymmetric signing key](https://supabase.com/docs/guides/auth/signing-keys)。Backend 不需要 JWT secret、publishable key 或 service-role key。

## 本地检查

```bash
cd backend/server
npm ci
npm test
npm run check
```

测试使用临时 ES256 key 和 synthetic claims，不连接真实 Supabase 项目。身份 schema 见 [`0002_identity_context.sql`](../database/migrations/0002_identity_context.sql)，项目上下文见 [`0004_personal_project_contexts.sql`](../database/migrations/0004_personal_project_contexts.sql)，区域与私有草稿见 [`0005_regions_and_private_draft_sync.sql`](../database/migrations/0005_regions_and_private_draft_sync.sql)，个人指标见 [`0006_personal_contact_metrics.sql`](../database/migrations/0006_personal_contact_metrics.sql)，区域解析见 [`0007_canonical_region_resolution.sql`](../database/migrations/0007_canonical_region_resolution.sql)，独立接触尝试见 [`0008_contact_attempts.sql`](../database/migrations/0008_contact_attempts.sql)，接触更正与作废见 [`0009_contact_revisions.sql`](../database/migrations/0009_contact_revisions.sql)，修订冲突见 [`0010_contact_revision_conflicts.sql`](../database/migrations/0010_contact_revision_conflicts.sql)，版本化问卷执行见 [`0011_questionnaire_execution.sql`](../database/migrations/0011_questionnaire_execution.sql)，动态显示规则见 [`0012_questionnaire_visibility.sql`](../database/migrations/0012_questionnaire_visibility.sql)，管理草稿与不可变发布见 [`0013_questionnaire_publishing.sql`](../database/migrations/0013_questionnaire_publishing.sql)。CI 使用 synthetic fixture 验证权限、重复 command、跨设备自动合并、同字段冲突与解决重放、作废指标排除、尝试字段边界、草稿 revision、问卷题型与显示规则、事务发布、跨用户隔离、区域解析、cursor 和 dump／restore。

## 运行

先执行数据库 migration，再启动进程：

```bash
export DATABASE_URL='postgresql://backend_login:REPLACE_ME@HOST/DATABASE'
export AUTH_ISSUER='https://PROJECT.supabase.co/auth/v1'
npm run build
npm start
```

部署平台负责 TLS 终止和 secret 注入。日志不得记录 Authorization header、token、subject 或数据库连接地址。
