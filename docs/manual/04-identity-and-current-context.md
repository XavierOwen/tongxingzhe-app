# 第 4 章：登录身份如何成为可信的当前项目上下文

## 1. 这一章解决什么

Supabase 登录成功只证明“谁持有这个 session”。它不回答四个业务问题：同行者内部使用哪个用户标识、数据属于哪个空间、当前操作属于哪个推广项目，以及新草稿绑定哪个问卷版本。

如果 Flutter 自行把 Supabase subject 当成 `app_user_id`，或从 legacy Demo 读取团队和项目，客户端就能伪造归属。正式路径因此使用一条受控链：

```text
Supabase access token
        ↓ Backend 验证签名、issuer、audience、期限和 role
可信 (issuer, subject)
        ↓ PostgreSQL 原子引导
app_user_id → 个人空间 → 当前推广项目 → 当前问卷版本
        ↓ HTTPS 响应
Flutter AppSession
```

Flutter 只把 bearer token 交给自有 Backend。请求中没有 `app_user_id`、workspace、project、role 或 capability。

## 2. 为什么 issuer 和 subject 必须一起使用

`subject` 只在一个签发者的命名空间内唯一。两个 Supabase project 可以签发相同的 subject。数据库因此对 `(issuer, subject)` 建唯一约束，不对 subject 单独建全局唯一约束。subject 是不透明值，保存时不能改写大小写或裁剪字符。

`app_user_id` 由同行者生成。接触、成员关系、权限和审计以后都引用它。认证商 subject 只留在身份映射表中，所以更换认证商不会要求重写全部业务外键。

## 3. Backend 如何建立信任

对于个人 session context，Backend 按 [Supabase JWT 说明](https://supabase.com/docs/guides/auth/jwts)使用 JWKS 公钥验证 access token。验证同时限制精确 issuer、`authenticated` audience、`authenticated` role、签名算法和过期时间。只有验证通过后，Backend 才调用 SQL：

```sql
SELECT *
FROM app_data.bootstrap_personal_context($1, $2);
```

`$1` 和 `$2` 来自已验证 claims。HTTP body 和 query string 都不能提供这两个值。Backend 使用参数化查询，不拼接 SQL。这个流程只建立个人上下文，不建立组织创建资格。

正式环境只接受 `ES256` 或 `RS256` asymmetric signing key。Supabase 的[签名密钥说明](https://supabase.com/docs/guides/auth/signing-keys)给出了 JWKS 地址、缓存和轮换边界。JWKS 只含公钥，Backend 不保存 Supabase JWT secret 或 service-role key。

### 3.1 组织创建资格为什么要二次验证

组织创建资格使用同一 JWT 验证作为第一步。JWT 通过后，专用 verifier 再用同一 access token 读取配置的 HTTPS Auth user endpoint。它不把 JWT 中的 `email`、`email_verified`、可修改的 `user_metadata` 或请求 body 当作邮箱确认依据。

可信证据分成两层：

| 阶段 | 可信证据 |
| --- | --- |
| JWT 验证 | 签名、issuer、audience、期限、subject 和 `authenticated` role |
| Auth user lookup | user `id` 与 JWT `subject` 精确相等、`is_anonymous === false`，以及带时区的有效 `email_confirmed_at` |

lookup 接口使用 provider-neutral 注入方式。Supabase adapter 只向配置的 HTTPS endpoint 发送 Bearer token、publishable key 和受控超时。它不接受 JWT secret 或 service-role key。

成功只返回短生命周期的组织创建资格类型。user adapter 在内部核对三项 Auth 证据，只向 verifier 返回固定资格决定；两层都不返回或保存邮箱、确认时间、完整 user object、JWT claims 或 provider metadata。

该 lookup 无副作用。它不写 `app_users`、session、audit 或 cache。它也不记录 token 或 provider 原文。

失败分类保持稳定并失败关闭：JWT 无效、Auth 明确拒绝 token，或 user `id` 缺失、非法、为空或不匹配是 `unauthenticated`，且 JWT 无效时不调用 user lookup；JWT 有效且身份一致，但用户是匿名用户或邮箱尚未确认是 `forbidden`；配置、HTTPS、超时、网络、5xx、非 JSON、错误字段类型、非法确认时间或未知结构问题是 `unavailable`。后续 HTTP route 可以把这些类别映射为稳定状态码，但本切片不增加 route。

### 3.2 资格通过后仍不能直接写组织表

Slice 7A 的成功结果只有 `issuer`、`subject` 和 request-scoped purpose。它不包含内部用户、组织、成员关系或 owner，也不授权 Backend 逐张表执行多次 `INSERT`。

7B 把身份映射和业务写入分开。runtime 只能执行 `app_data.create_organization_for_identity_v1`。
这个 bridge 原值精确匹配 Backend 提供的 verified `issuer + subject`，只接受既有 active internal user。
它不 trim、bootstrap 或修复 identity，并调用 runtime 无权直接执行的 `app_private.create_organization_v1`。
它拒绝 null 或 `btrim` 后空白的 issuer／subject，并把原值长度分别限制为 2048 和 512 个字符。
bridge 和 private writer 都使用固定非 runtime owner、`VOLATILE SECURITY DEFINER` 和 `search_path = pg_catalog`。
`PUBLIC` 无执行权；runtime 只能执行 bridge，而且不能读写相关表。
客户端以后只提交 UUID request ID 和 display name。客户端不能提交 issuer、subject、internal user、workspace、membership、owner、project、capability、时间或 audit 字段。

private writer 在一个 transaction 中使用同一次 `transaction_timestamp()` 完成五项写入：organization workspace、创建者 organization membership、首位 active owner assignment、request claim 和 creation audit。owner assignment 独立于项目 capability，并只引用同组织的 membership。assignment 的 `[active_from_utc, inactive_from_utc)` 范围必须在 membership 范围内，同一 membership 不得重叠。所有权只能用数据库时间立即授予或结束。创建 owner 不建立项目成员关系，也不授予管理报告、异常读取或 PII 权限。

数据库把 `btrim` 只移除两端 U+0020 后的原文本作为 canonical name。
它使用 `char_length` 检查 1 至 120 个字符，并拒绝 U+0000 到 U+001F 和 U+007F 到 U+009F。
名称必须至少有一个非 Unicode `White_Space` 字符，也不能只含 U+200B、U+200C、U+200D、U+2060 或 U+FEFF。
相同 request、actor 和 canonical name 重试返回原来的 workspace、membership、owner assignment 与创建时间。

actor 或 name 漂移返回 conflict。request UUID 在组织创建命名空间内单列唯一，不是 actor-scoped 联合键。
账号终结删除可以将 claim 的 actor 引用置空，但 claim 的其他字段不可改。
组织终结清除前，最小删除审计保留 request UUID 作为 value-free tombstone。因此旧 UUID 永不会被当作新创建。

创建路径的顺序是 request advisory lock、active actor row lock、新 workspace governance advisory lock，最后是现有 membership-specific lock。
后续多用户或多组织治理必须按 UUID 排序锁 user，再按 UUID 排序锁 organization，不得反向取锁。
所有 owner／membership 写入、账号状态变更和组织清除都必须先取同一 governance lock，再重新检查状态。

数据库在 transaction 结束时延迟检查：每个尚未终结清除的组织都必须有一位 active owner。
延迟 trigger 不代替 governance lock；后者阻止两位 owner 在并发 transaction 中同时失效。
组织删除恢复期仍保留 owner、membership、claim 和 audit。只有期满清除 transaction 可以连同 workspace 删除它们。
终结清除先取 creation request lock，再取 governance 和 workspace row locks，并在锁后重新确认 claim 和恢复期。

账号终结删除时，`deletion_pending` 已使 creation claim 集合停止增长。
删除路径先按 UUID 取 claim request locks，再取 user 和 organization locks。
它最后用同一数据库时间结束 owner assignments 和 memberships，然后清除账号。

两层数据库函数都返回同一 exact row，不返回 JSONB。成功只含 `organization-creation:v1`、workspace UUID、membership UUID、owner assignment UUID 和单一数据库创建时间。
数据库只使用四组固定错误：`22023 invalid organization creation identity`、`22023 invalid organization creation request`、`42501 organization creation forbidden` 和 `22023 organization creation idempotency conflict`。
Backend 将它们映射为 `503 organization_creation_unavailable`、`400 invalid_organization_creation_request`、`403 organization_creation_forbidden` 和 `409 organization_creation_conflict`。
`401 unauthenticated` 只来自 JWT／Slice 7A verifier。未知 SQLSTATE、message、约束、parser 和数据库错误都返回 unavailable，不透出原文。
未来 HTTP 响应都使用 `Content-Type: application/json; charset=utf-8` 和 `Cache-Control: no-store`。
失败 body 只使用固定 `{ "error": { "code": "..." } }`。

创建 audit 只保存 event／request ID、三个业务 ID、`organization-creation:v1` 和数据库时间，不保存直接 actor 引用。audit、错误响应和结构化日志也不保存组织名称、邮箱、external identity、token、Auth user object、provider metadata、SQL、数据库消息、堆栈或原始错误。该 audit 在组织删除恢复期内保留，并在期满清除时连同其他组织业务数据删除。

0084 migration 已实现组织创建 bridge、private writer、owner assignment、claim 和 audit。
0085 migration 为 workspace、membership、owner assignment 和 app user status 增加同一 governance lock fence。transaction 结束时执行延迟 active-owner 检查。
配套结构检查、回滚 fixture 和独立会话并发测试只证明 synthetic PostgreSQL 合同。仓库仍未增加组织创建 HTTP route 或 Flutter UI。这些证据也不代表生产身份、真实账号删除或组织清除。

## 4. PostgreSQL transaction 建立哪些事实

`0002_identity_context.sql` 创建五张最小表：

| 表 | 当前职责 |
| --- | --- |
| `app_users` | 保存稳定内部用户及账号状态 |
| `external_identities` | 保存 `(issuer, subject) → app_user_id` |
| `workspaces` | 保存每个用户唯一的活动个人空间 |
| `projects` | 保存个人空间的起始推广项目 |
| `questionnaire_versions` | 保存该项目当前的基础已发布版本 |

`bootstrap_personal_context` 是一个 `SECURITY DEFINER` 函数。普通 Backend runtime role 可以执行它，但不能直接插入、更新或删除上述表。函数使用 transaction advisory lock，让同一身份的并发首启共用一套个人上下文。

同一 `(issuer, subject)` 重复调用会返回相同 ID。相同 subject 配合不同 issuer 会得到不同内部用户。任一创建失败时，整个语句回滚，不返回半套上下文。

身份引导创建的基础问卷版本可以没有场景问题。它仍是一个正式、已发布、版本号为 1 的问卷版本。项目后来发布的问题由受权读取端点取得，并按精确版本缓存在本机；新草稿始终绑定可信当前上下文给出的版本。

## 5. Flutter AppSession 隐藏哪些细节

`AppSession` 对调用者只暴露一个 snapshot：未配置、未登录、正在解析上下文、可用或失败。可用状态同时包含内部用户、空间、项目、问卷版本和 capability。

模块内部完成以下工作：

- 从 `IdentitySession` 恢复登录状态；
- 取得短期 access token；
- 调用 `/v1/session/context`；
- 验证响应 ID、空间类型、版本号和 capability 结构；
- 在注销或身份变化时立即清除旧上下文；
- 丢弃注销后才返回的旧网络响应。

Widget 不读取 token，也不把 external subject 填进草稿。下一步正式草稿 UI 只从 `AppSession.current.context` 取得四个归属 ID。

## 6. 失败为何必须关闭操作入口

认证成功但上下文失败时，App 不能回退到 Demo 项目，也不能生成本地临时 `app_user_id`。这些做法会制造无法安全同步的孤立事实。

`AppSession` 因此保留稳定失败分类：认证失败、Backend 未配置、未授权、网络不可用、响应无效或服务端拒绝。失败 snapshot 不含任何部分上下文，`canRecordContact` 为 false。UI 后续应显示重试或重新登录操作。

组织创建资格也不能在 Auth user lookup 不可用时回退到 JWT metadata、请求 body、本地缓存或上一次资格结果。认证、授权和服务不可用必须保持不同类别；任何未知响应或错误都不返回 provider 原文，并关闭组织创建入口。

## 7. 可以怎样验证

Flutter 目标测试：

```bash
flutter test test/app_session
```

Backend 目标测试：

```bash
npm --prefix backend/server run check
npm --prefix backend/server run build
node --test \
  backend/server/dist/test/organization-creation-identity.test.js \
  backend/server/dist/test/identity.test.js
npm --prefix backend/server test
```

专用测试使用临时 ES256 key、synthetic user object 和 fake Auth lookup／HTTP transport。它们检查 user `id`、匿名状态、带时区的确认时间、请求 headers、失败分类、PII 和日志边界，并确认无效 JWT 不触发 lookup。上述测试不连接真实 Supabase，不证明生产身份、部署端点、组织创建 route、数据库写入或六平台运行时。

PostgreSQL 16 可用时，按[数据库说明](../../backend/database/README.md)重建空库，再运行 `verify_identity_context.sql` 和 `0002_identity_context.sql` fixture。fixture 只使用 synthetic issuer 和 subject，并在结尾回滚。

读完这一章，应能解释：为什么 subject 不是 `app_user_id`、谁可以决定当前项目，以及注销为何能阻止旧网络响应恢复上下文。
