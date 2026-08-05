# Backend 身份上下文与接触同步

这个模块提供 `GET /v1/session/context`、`POST /v1/sync/commands` 和 `GET /v1/sync/changes`。三个端点都先验证 Supabase access token，再取得内部用户和当前项目。

客户端不能提交 `app_user_id`、role 或 capability。上传会把 payload 的 workspace 和 project 与可信上下文交叉核对。拉取也会核对 query 范围，并只接受属于同一范围的不透明 cursor。响应不返回外部 subject、email 或 token。

cursor 不存在或不属于当前用户、空间和项目时，端点返回 `400 invalid_cursor`。未分类的数据库失败返回 `503 sync_unavailable`，不把内部 SQL 错误文字暴露给客户端。

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

测试使用临时 ES256 key 和 synthetic claims，不连接真实 Supabase 项目。身份 schema 见 [`0002_identity_context.sql`](../database/migrations/0002_identity_context.sql)。接触幂等写入和有序拉取见 [`0003_contact_sync.sql`](../database/migrations/0003_contact_sync.sql)。CI 使用 synthetic fixture 验证权限、重复 command、原子写入、cursor 和 dump／restore。

## 运行

先执行数据库 migration，再启动进程：

```bash
export DATABASE_URL='postgresql://backend_login:REPLACE_ME@HOST/DATABASE'
export AUTH_ISSUER='https://PROJECT.supabase.co/auth/v1'
npm run build
npm start
```

部署平台负责 TLS 终止和 secret 注入。日志不得记录 Authorization header、token、subject 或数据库连接地址。
