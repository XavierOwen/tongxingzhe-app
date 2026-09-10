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

失败分类保持稳定并失败关闭：JWT 无效、Auth 明确拒绝 token，或 user `id` 缺失、非法、为空或不匹配是 `unauthenticated`，且 JWT 无效时不调用 user lookup；JWT 有效且身份一致，但用户是匿名用户或邮箱尚未确认是 `forbidden`；配置、HTTPS、超时、网络、5xx、非 JSON、错误字段类型、非法确认时间或未知结构问题是 `unavailable`。Issue #298 记录后续 HTTP route 的合同，但本票只做 spec，不增加 route。

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
配套结构检查、回滚 fixture 和独立会话并发测试只证明 synthetic PostgreSQL 合同。Issue #298 固定组织创建 HTTP 合同，Issue #300 已增加 route、store、production composition 和 synthetic PostgreSQL integration，但未增加 Flutter UI。这些证据也不代表生产身份、真实账号删除或组织清除。

### 3.3 组织 owner 转让（Issue #304，spec-only）

组织 owner 转让只发生在已经存在的组织中。当前 owner 把 owner 身份交给同一组织的另一名有效成员。它不是组织创建，也不是邀请或加入组织。

首次转让开始前，数据库必须确认以下事实。确认必须在取得锁后再做一次。

- 发起人是当前组织 owner，且其 `app_user.status` 为 `active`。
- 目标使用已有的 `organization_membership_id`。该 membership 属于同一组织，且当前有效；对应账号也必须为 `active`。
- 目标不能已经是当前 owner。发起人与目标相同也返回“目标已经是 owner”的冲突。

首次执行时，发起人或目标账号只要是 `deletion_pending` 或 `deleted`，转让就被拒绝。组织进入删除恢复期后只读，也不能开始新转让；恢复失主的流程另行定义。

这条路径不复用 Slice 7A 的 organization-creation eligibility。7A 只回答已验证身份能否创建组织。owner 转让还需要当前 owner 授权、同组织成员关系和目标账号状态。

Backend 把外部身份和数据库写入分成两层。`app_data.transfer_organization_owner_for_identity_v1(text, text, uuid, uuid, uuid)` 先把精确的 `(issuer, subject)` 映射到现有 active `app_user_id`，再调用 `app_private.transfer_organization_owner_v1(uuid, uuid, uuid, uuid)`。只有 resolved actor 是可信事实；request、组织 workspace 和目标 membership UUID 都是不可信 selector，private writer 必须在锁后验证。HTTP body 不能提交 actor、邮箱或 internal user ID。

bridge 不 trim、bootstrap 或修复身份。null、空白、issuer 超过 2048 字符或 subject 超过 512 字符是 invalid identity。未知或非 active identity 使用同一个 forbidden。

两函数都是 `VOLATILE SECURITY DEFINER`，固定 `search_path = pg_catalog`。owner 与 membership validator 相同且不是 runtime。`PUBLIC` 不得执行两函数。runtime 只能执行 bridge，不能执行 private writer。runtime 也不能直接读写 identity、membership、owner、claim 或 audit 表。

转让使用独立的 claim 表和 `organization-owner-transfer-request:` lock 前缀。单列主键是 `request_id`；creation 和 transfer 分属不同 family，所以可以各自使用同一 UUID。

private claim 只保存 request UUID、可置空且 `ON DELETE SET NULL` 的 actor app-user UUID、organization workspace UUID、target membership UUID、旧／新 owner assignment UUID 和有限的 effective time。

除 actor 外的 UUID 不设 FK。claim 通常完全不可变。账号终结删除只能在同一治理 transaction 中把 actor 引用从非 null 置为 null。此后任何 resolved active actor 使用该 request 都返回 conflict。已删除或无法解析的 identity 仍返回 forbidden。

private writer 在 request lock 下先检查 live claim 和 transfer tombstone。request、组织、actor 和 target 完全相同时继续锁定 actor app-user row。它重读 `status = 'active'` 后返回 claim 中的原五字段 receipt。

精确重放不重新要求 actor 仍是 owner，也不因为 target 已经成为 owner而报错。它不新增 assignment 或 audit。它也不依赖 target 后来的 owner、membership 或账号状态。

参数漂移、tombstone 或已去关联 actor 都返回 idempotency conflict。只有没有 claim 和 tombstone 时，才检查首次 transfer 的 current owner、active target 和 target-not-owner 条件。

锁的顺序固定如下：

1. 取得 transfer request lock。
2. 按 UUID 顺序锁定 actor 和 target 的 app-user rows。
3. 取得 organization governance lock。
4. 按 UUID 顺序锁定相关 organization memberships。
5. 锁后重新读取 actor、target、workspace、claim 和 owner facts。

drift 和 tombstone 在第 1 步结束；精确重放再锁定并重读 actor app-user row 后结束。只有首次执行继续后续锁。不能反向取得这些锁。所有时间都使用同一个 `transaction_timestamp()`。private writer 先追加 target 的 owner assignment，再结束 actor 当前 assignment。assignment 历史只能追加和合法结束，不能改写或物理删除。事务末的 active-owner deferred check 必须看到至少一位 active owner。

同一 request 由 request lock 串行化。同组织的不同 request 由 governance lock 串行化。任何失败都不能留下部分 workspace、assignment、membership、claim 或 audit。

这是 handoff，不是 co-owner grant。多 owner 组织只结束发起人的当前 assignment，其他 current owners 保持不变。转让不改变 membership，不接受 invitation 或 application，不创建 project membership，也不授予或改变任何 project capability、管理报告能力或 PII 访问权。

未来数据库 result row 固定为五个字段：

```text
owner_transfer_contract_id = organization-owner-transfer:v1
organization_workspace_id
previous_owner_assignment_id
organization_owner_assignment_id
effective_at_utc
```

Backend 使用以下稳定错误和 code。未知 SQLSTATE、message、constraint、parser、result shape 或 adapter 错误统一为 `organization_owner_transfer_unavailable`，并且不返回数据库原文。

| 条件 | SQLSTATE 与固定 message | Backend code |
| --- | --- | --- |
| trusted identity 输入非法 | `22023 invalid organization owner transfer identity` | `organization_owner_transfer_unavailable` |
| request、workspace 或 target 输入非法 | `22023 invalid organization owner transfer request` | `invalid_organization_owner_transfer_request` |
| actor、target、组织状态或 owner 授权不允许 | `42501 organization owner transfer forbidden` | `organization_owner_transfer_forbidden` |
| request actor、workspace 或 target 漂移，或 request 已是 tombstone | `22023 organization owner transfer idempotency conflict` | `organization_owner_transfer_conflict` |
| target 已是 current owner，包括 actor 等于 target | `22023 organization owner transfer target already owner` | `organization_owner_transfer_target_already_owner` |

null request／workspace／target 是 invalid request。未知或非 organization workspace、未知／跨组织／非 active target membership、非 active target account、非 active member／非 current owner actor，以及组织恢复状态，都使用同一个 forbidden，不暴露对象是否存在。只有已验证为同组织 active target 且当前是 owner 时才使用 target-already-owner conflict。

转让 audit 只能追加且不可变。它的 exact allowlist 是 `organization_owner_transfer_audit_event_id`、`owner_transfer_contract_id`、`request_id`、`organization_workspace_id`、`previous_owner_assignment_id`、`organization_owner_assignment_id` 和 `effective_at_utc`。
target membership UUID 只保存在 private claim，不进入 audit；new assignment 是 canonical target lineage。
audit、失败响应和结构化日志都不保存 actor 或 target 的直接身份、display name、邮箱、external issuer／subject、token、Auth user object、provider metadata、SQL、数据库 message、stack 或自由文本。

组织进入删除恢复期时，governance lock 会冻结新 transfer claim，精确重放仍只读。期满清除按 [ADR-0183](../adr/0183-bare-organization-membership-self-leave.md) 的当前全局 family 和各 family 内 UUID 顺序锁定全部 requests，包含 creation／transfer。

取得 governance lock 后，它重读 recovery 状态和 claim 集合；集合不一致时回滚重试。清除先写只含 `claim_family = 'organization-owner-transfer:v1'` 与 request UUID 的 transfer tombstone，再按 FK 依赖删除 claim、audit 和组织业务记录。

transfer writer 只检查自己的 family，所以同一个 UUID 用于 creation 不会与 transfer 冲突。
删除、恢复与 purge writer 本身仍由后续工作单元实现。

Issue #304 仍记录 spec 合同。Issue #310 已交付 0086 DB-only 实现。
实现包括 transfer migration、表、trigger、函数、ACL、结构检查、回滚 fixture 和并发测试。
这些 synthetic PostgreSQL 证据不证明 Backend store、HTTP route、Flutter、Drift、生产 identity、真实删除或 Apple 行为。
账号或组织删除、purge、恢复失主、邀请、加入申请、membership 管理、capability 管理和 co-owner grant 另行定义。
Markdown 和文档检查只证明文字一致。

### 3.4 组织创建 HTTP route（Issue #298／#300）

Issue #298 固定 Backend 传输边界，Issue #300 实现 HTTP route、store adapter 和 production composition。入口为：

```text
POST /v1/organizations
```

其他 method 或未匹配 path 返回通用 `404 {"error":{"code":"not_found"}}`，不验证身份、读取 body 或调用 store。

请求必须先经过专用的 Slice 7A organization-creation eligibility verifier。Backend 在读取 body 或访问 store 前，先解析 Bearer token，验证 JWT，再以同一 token 读取 Auth user endpoint。缺失或无效 token 返回 `401 unauthenticated`；7A 资格为 `forbidden` 返回 `403 organization_creation_forbidden`；资格或 Auth provider 不可用返回 `503 organization_creation_unavailable`。认证失败不能触发 body parser 或 store。

body 是严格的 JSON object，只含 `request_id` 和 `display_name`：

```json
{
  "request_id": "uuid",
  "display_name": "string"
}
```

request UUID 必须在 body 中。它是组织创建命名空间的单列幂等键，不是 `Idempotency-Key` header，也不是 actor 与 UUID 的联合键。
任何 query 都在认证成功后、读取 body 前返回 `400 invalid_organization_creation_request`。
body 不能提供 issuer、subject、internal user、workspace、membership、owner、project、capability、时间或 audit；额外字段也必须拒绝。
空 body 或非法 JSON 返回 `400 invalid_json`；超过既有 body 上限返回 `413 payload_too_large`；其他 body 形状、字段缺失、无效 UUID 或非法 display name 返回 `400 invalid_organization_creation_request`。

Backend 不 trim `display_name`，不做 Unicode normalization、大小写折叠、唯一性检查或相似名称合并。它把原字符串传给 0084 bridge；数据库再由 bridge 调用 private writer，并按本章既定规则做 canonical `btrim` 和名称边界检查。

首次创建与相同 request、actor、canonical name 的精确重放都返回 `200`。成功响应不增加 replay 标记，且严格只含以下五个字段：

```json
{
  "creation_contract_id": "organization-creation:v1",
  "organization_workspace_id": "uuid",
  "organization_membership_id": "uuid",
  "organization_owner_assignment_id": "uuid",
  "created_at_utc": "2030-01-01T00:00:00.000Z"
}
```

Store 只执行一次参数化 `app_data.create_organization_for_identity_v1`，传入 verified exact issuer、subject、body 中的 request UUID 和 display name。handler 必须等待该 Promise settled，并确认数据库事务结果后才写 HTTP 响应。0084 的数据库错误映射为：

| 数据库错误 | HTTP 结果 |
| --- | --- |
| `22023 invalid organization creation identity` | `503 organization_creation_unavailable` |
| `22023 invalid organization creation request` | `400 invalid_organization_creation_request` |
| `42501 organization creation forbidden` | `403 organization_creation_forbidden` |
| `22023 organization creation idempotency conflict` | `409 organization_creation_conflict` |

`401 unauthenticated` 只来自 JWT／7A verifier。未列出的 SQLSTATE、数据库、adapter 或返回 parser 错误统一返回 `503 organization_creation_unavailable`。所有响应使用 `Content-Type: application/json; charset=utf-8` 和 `Cache-Control: no-store`；失败 body 只能是 `{ "error": { "code": "..." } }`。

响应、日志和失败审计不得包含 token、Auth user object、邮箱、确认时间、provider metadata、issuer、subject、SQL、数据库 message、stack 或 display name。creation audit 仍只保存 0084 规定的 value-free 字段。owner 不自动生成 project membership、capability、管理报告或 PII 权限。

production composition 显式组合专用 7A verifier、Supabase Auth user lookup 和 creation store，并要求 `SUPABASE_PUBLISHABLE_KEY`。缺配置时启动失败关闭，不能只使用 generic JWT、JWT metadata、请求 body、本地缓存或 `SessionContext`。Issue #300 不增加 migration、owner lifecycle、Flutter、Drift 或 Apple 行为。

### 3.5 Flutter 组织创建 typed gateway 与 AppDependencies 生命周期（Issue #302、#306）

Issue #302 增加独立的 `OrganizationCreationGateway` 和 HTTP adapter。Issue #306 将它接入 `AppDependencies` 生命周期。调用方显式提供 canonical request UUID 与原始 display name；gateway 不生成 UUID，
不 trim 或 normalize 名称，也不读取 email、external subject、内部 user／workspace／project／capability 或 `SessionContext`。

HTTP adapter 只发送无 query 的 `POST /v1/organizations`，body 仍只有 `request_id` 和 `display_name`。它通过 `IdentitySession` 取得 Bearer token；
首次 `401 unauthenticated` 后只强制刷新并重试一次，且两次请求使用完全相同的 UUID 和 body。成功 parser 只接受固定 contract ID、三个 canonical UUID
与 canonical UTC 时间；所有响应都必须是 JSON 且带 `Cache-Control: no-store`。稳定 Backend error envelope、identity、timeout、network 和协议漂移只返回 typed failure，
不会把 response body、provider 或数据库错误交给调用方。

未配置 `BACKEND_BASE_URL` 时，production factory 返回不触网的 deferred gateway。`AppDependencies` 的 builder 接收启动时打开的同一个 `IdentitySession`，
`AppStartupReady` 暴露 builder 返回的同一个 gateway。`close()` 只负责关闭它拥有的 HTTP client；receipt 不写入 Drift、缓存或日志。
后续启动步骤失败、App 在启动完成前被移除或 `TongxingzheApp` 正常 dispose 时，已创建的 gateway 都只关闭一次。
本切片仍没有接入 controller、UI、Screen、route、导航、创建后的组织／项目上下文、Drift、request UUID 生成器或跨重启 durable retry。

先运行 focused gateway 与 composition tests，再运行全量 Flutter 回归：

```bash
flutter test test/organization_creation/http_organization_creation_gateway_test.dart
flutter test test/app/app_dependencies_test.dart test/app/tongxingzhe_app_test.dart
dart analyze
flutter test
dart run tool/check_markdown_links.dart
```

这些 fake identity 与 mock HTTP 测试只证明客户端 transport、strict parser 和资源生命周期，不证明 production Supabase、部署端点、真实组织创建或真人平台。

### 3.6 组织 owner transfer HTTP route（Issue #309，Backend 实现见 #312）

3.3 固定数据库 handoff 合同。本节记录 Issue #309 固定的 HTTP transport；Issue #312 已按该合同实现 Backend handler、store、route 和 composition。
客户端只选择目标 membership 和 request UUID。当前 owner 身份来自 Bearer token，不能由 body 提供。

公开入口只有：

```text
POST /v1/organizations/:organizationWorkspaceId/owner-transfer
```

router 先从 request target 取 `?` 前的 raw pathname，再匹配这一条含一个动态 segment 的 path。
它不能先使用 WHATWG URL 的 dot-segment normalization。错误 method、trailing slash、repeated slash、literal 或 percent-encoded dot segment、任何 percent-encoded path segment 或其他未匹配 path 都返回：

```json
{"error":{"code":"not_found"}}
```

这类 `404` 不解析 Bearer，不读取 body，也不调用 store。带 query 的合法 path 仍先命中 route，随后按固定顺序拒绝 query。

命中 route 后，handler 必须按以下顺序处理：

1. 严格解析 Bearer credential。
2. 调用现有 generic `IdentityVerifier`，只取得 verified exact `issuer` 和 `subject`。
3. 拒绝 query。
4. 验证 path 中的 `organizationWorkspaceId`，然后转为 canonical lowercase UUID。
5. 检查 dedicated transfer store 是否存在。
6. 用既有 reader 按实际 body bytes 读取 JSON。
7. 解析请求并调用一次 store。
8. 等待 Promise settled 后写 HTTP 响应。

缺少或无效 token、JWT claim 或 signature 失败返回 `401 unauthenticated`。
缺少 verifier、provider、配置或未知 verifier 异常返回 `503 organization_owner_transfer_unavailable`。
`IdentityVerificationError.category === "unauthenticated"` 映射 `401`；`category === "unavailable"` 或非 `IdentityVerificationError` 异常映射 `503`。
前两步完成前，handler 不读取 body、不检查 path UUID、不拒绝 query，也不调用 store。
缺少 store 在读取 body 前返回同一个 `503`。
route 已命中但动态 segment 不是合法 UUID 的请求，在认证后返回 `400 invalid_organization_owner_transfer_request`。

`IdentityVerifier` 只提供 exact external identity。owner transfer 不使用 7A 的 `OrganizationCreationIdentityVerifier`、Auth user lookup、邮箱资格或 `SessionContext`。
Issue #312 的 production composition 只注入 generic verifier 和 dedicated Postgres transfer store，不增加环境变量或组织创建资格。

body reader 按收到的实际 bytes 计数，不信任 `Content-Length`，也必须覆盖 chunked body。
最多 `1,048,576` bytes 可以继续解析。收到第 `1,048,577` byte 时返回 `413 payload_too_large`。
空 body 或非法 JSON 返回 `400 invalid_json`。本合同不增加 request `Content-Type` gate。

JSON root 必须严格只含以下两个字段：

```json
{
  "request_id": "uuid",
  "target_organization_membership_id": "uuid"
}
```

两个值都必须使用 `8-4-4-4-12` 十六进制 UUID wire shape。字母可以大写或小写，不额外限制 version／variant nibble；验证后统一为 lowercase。
缺失字段、额外字段、错误类型、null 或无效 UUID 返回 `400 invalid_organization_owner_transfer_request`。
客户端不能提交 actor、workspace、owner assignment、email、name、时间或 capability。
request UUID 仍在 body 中，不使用 `Idempotency-Key` header。

请求校验通过后，dedicated store 只执行一次参数化调用：

```sql
app_data.transfer_organization_owner_for_identity_v1(
  trusted_issuer,
  trusted_subject,
  requested_request_id,
  requested_organization_workspace_id,
  requested_target_organization_membership_id
)
```

store 传入 verifier 返回的 exact identity、canonical request UUID、canonical path workspace UUID 和 canonical target membership UUID。
它不能访问 `app_private`、creation store 或客户端 actor。handler 必须等数据库 Promise 完成后才写响应。

首次成功和 exact replay 都返回 `200`。成功 JSON root 只能含以下五个字段：

```json
{
  "owner_transfer_contract_id": "organization-owner-transfer:v1",
  "organization_workspace_id": "uuid",
  "previous_owner_assignment_id": "uuid",
  "organization_owner_assignment_id": "uuid",
  "effective_at_utc": "2030-01-01T00:00:00.000Z"
}
```

contract ID 必须精确匹配。三个 UUID 必须是 canonical lowercase，响应 workspace 必须等于 canonical path UUID。
`effective_at_utc` 必须是有效 RFC 3339 instant。store 可以返回数据库 `Date` 或带 offset、fraction 的文本，parser 统一输出毫秒精度的 `YYYY-MM-DDTHH:mm:ss.SSSZ`。
响应不能增加 replay flag、target 资料、成员资料、身份或 capability 字段。

错误 root 严格为 `{ "error": { "code": "stable_code" } }`，不得返回数据库原文：

| 条件 | HTTP 结果 |
| --- | --- |
| body 是空或非法 JSON | `400 invalid_json` |
| query、path 或 body 请求不合法 | `400 invalid_organization_owner_transfer_request` |
| body 超过 1 MiB | `413 payload_too_large` |
| generic verifier 缺失或异常、store 缺失、非法 trusted identity、未知错误 | `503 organization_owner_transfer_unavailable` |
| DB actor、target、workspace、恢复状态或 owner 授权不允许 | `403 organization_owner_transfer_forbidden` |
| request、actor、workspace 或 target drift，tombstone，或 actor 已去关联 | `409 organization_owner_transfer_conflict` |
| target 已经是 owner，包括 actor 与 target 相同 | `409 organization_owner_transfer_target_already_owner` |

未知、跨组织、非 organization、恢复期 workspace，或 inactive／deleted actor、target，都由 DB 映射为 `403`。
transport 不能提前查询这些对象，也不能把它们改写成 `404`，否则会暴露成员或组织是否存在。
未知 SQLSTATE、message、constraint、result shape、parser、provider 或 adapter 错误统一返回 `503`。

所有响应，包括 `404` 和错误响应，都使用精确的：

```text
Content-Type: application/json; charset=utf-8
Cache-Control: no-store
```

Issue #312 的 tests 覆盖 raw pathname、method、slash、认证顺序、generic verifier、缺少 store、实际 byte 上限和 strict request parser。
测试还覆盖 canonical UUID／timestamp、单次 bridge 调用、Promise gate、首次／精确 replay、稳定错误映射、non-enumeration、headers、composition 和错误脱敏。

Issue #309 只固定 transport spec，Issue #310 交付 0086 DB-only migration、函数、ACL 和测试证据，Issue #312 交付 local synthetic Backend／HTTP／PostgreSQL integration。
这些证据不证明 production identity、部署端点、Flutter、Drift、controller、UI、Apple 或其他真人平台运行时。

### 3.7 Flutter 组织 owner transfer typed gateway（Issue #314/#316，MANUAL-056，已交付）

Issue #314 固定 Flutter 业务层的 typed gateway 合同，#316 已交付 Dart gateway、HTTP adapter 和 focused tests。它复用 Issue #309 的 HTTP transport 和 Issue #312 的 Backend route。
这些切片不重新定义 0086 的 owner、membership、claim、audit、recovery 或 purge 规则。
本节说明 7L 的 gateway。`AppDependencies`、`AppStartupReady` 和 App lifecycle 接入见 3.8 的 7N。

公共接口固定为：

```dart
abstract interface class OrganizationOwnerTransferGateway {
  Future<OrganizationOwnerTransferResult> transfer({
    required String requestId,
    required String organizationWorkspaceId,
    required String targetOrganizationMembershipId,
  });

  Future<void> close();
}
```

公共类型名称固定为 `OrganizationOwnerTransferResult`、`OrganizationOwnerTransferReceipt`、`OrganizationOwnerTransferFailureCode`、`OrganizationOwnerTransferSuccess` 和 `OrganizationOwnerTransferRejected`。`HttpOrganizationOwnerTransferGateway` 是配置后的 HTTP 实现；`DeferredOrganizationOwnerTransferGateway` 是未配置时的不触网实现；生产工厂名称为 `productionOrganizationOwnerTransferGateway`。

调用方必须提供三个 UUID：request、organization workspace 和 target organization membership。gateway 不生成 request UUID，不预查组织、owner 或 membership，也不接受 actor、email、external subject、owner assignment 或 capability。
输入 UUID 必须使用 `8-4-4-4-12` 十六进制 wire shape。字母可以大写或小写，不额外限制 version／variant nibble。adapter 在取得 token 或发 HTTP 前把三者统一为 lowercase canonical value；非法 UUID 直接返回 `OrganizationOwnerTransferRejected(OrganizationOwnerTransferFailureCode.invalidRequest)`。

成功结果和失败结果是两个固定分支：

- `OrganizationOwnerTransferSuccess(receipt)` 的 `OrganizationOwnerTransferReceipt` 只有 `ownerTransferContractId`、`organizationWorkspaceId`、`previousOwnerAssignmentId` 和 `organizationOwnerAssignmentId` 四个 `String` 字段，以及 `effectiveAtUtc` 一个 UTC `DateTime` 字段。这些值不可变。
- `OrganizationOwnerTransferRejected(code)` 的 `OrganizationOwnerTransferFailureCode` 只有 `notConfigured`、`unauthorized`、`invalidJson`、`payloadTooLarge`、`invalidRequest`、`forbidden`、`conflict`、`targetAlreadyOwner`、`serviceUnavailable`、`networkUnavailable` 和 `invalidResponse`。不增加业务性的 `notFound`。

`productionOrganizationOwnerTransferGateway` 读取 `BACKEND_BASE_URL`。空或只含空白时返回 `const DeferredOrganizationOwnerTransferGateway`，不创建 HTTP client，也不触网；非空值先解析并由 `validatePathlessBackendBaseUri` 验证无 path 的 Backend base URI。URI 解析或 validator 失败必须同步抛出，且不得创建或返回 gateway/client。验证通过后才创建 `HttpOrganizationOwnerTransferGateway`，并可注入测试用的 `http.Client`。

configured gateway 只发送无 query、无 fragment 的：

```text
POST /v1/organizations/:organizationWorkspaceId/owner-transfer
```

path 使用 canonical workspace UUID。JSON body 严格只有 `request_id` 和 `target_organization_membership_id`，两者也使用 canonical UUID。请求不发送 `Idempotency-Key`、actor 或重复的 workspace 字段。

每个请求严格只有三项相关 headers：

```text
Accept: application/json
Authorization: Bearer <token>
Content-Type: application/json; charset=utf-8
```

gateway 使用同一个 `IdentitySession` 取得 Bearer token。identity failure 的映射固定为：`notConfigured` 返回 `notConfigured`，`networkUnavailable` 返回 `networkUnavailable`，其他 identity failure 返回 `unauthorized`。
如果首个 response 恰好是 `401` 且 error code 为 `unauthenticated`，gateway 只强制刷新一次 token。重试使用相同 method、canonical URL 和 body，`Authorization` 使用强制刷新取得的 token。第二个相同 `401` 返回 `unauthorized`，不得循环刷新。

adapter 在解析任何 response 前都要求精确的：

```text
Content-Type: application/json; charset=utf-8
Cache-Control: no-store
```

`200` 只接受 exact 五字段 receipt、固定 contract ID、三个 lowercase UUID、与 path 相同的 workspace，以及 `YYYY-MM-DDTHH:mm:ss.SSSZ` UTC 时间。adapter 不判断 replay、owner、membership、组织状态或权限。

Backend stable error 映射为：`400 invalid_json` → `invalidJson`；`400 invalid_organization_owner_transfer_request` → `invalidRequest`；`401 unauthenticated` → `unauthorized`；`403 organization_owner_transfer_forbidden` → `forbidden`；`409 organization_owner_transfer_conflict` → `conflict`；`409 organization_owner_transfer_target_already_owner` → `targetAlreadyOwner`；`413 payload_too_large` → `payloadTooLarge`；`503 organization_owner_transfer_unavailable` → `serviceUnavailable`。
网络、timeout 和 `http.ClientException` 返回 `networkUnavailable`。

缺少或错误 response header、response JSON 无法解析、非 exact error envelope、unknown status 或 code、`404 not_found`、字段漂移、非法 UUID 或时间，以及其他 parser 或 adapter 错误，都返回 `invalidResponse`。failure 只保留 typed code，不把 response body、provider error、SQL、数据库 message、stack、token 或成员资料交给调用方。

`DeferredOrganizationOwnerTransferGateway` 的每次调用返回 `OrganizationOwnerTransferRejected(OrganizationOwnerTransferFailureCode.notConfigured)`。`HttpOrganizationOwnerTransferGateway` 拥有并关闭传入的 `http.Client`；production factory 创建该 client。`close()` 可重复调用且不得关闭 `IdentitySession`，deferred gateway 的 `close()` 是 no-op。
receipt、failure 和原始 response 只存在于内存，不写 Drift、缓存、同步队列或日志。7L 不定义 `AppDependencies`、App lifecycle、controller、ViewModel、Screen、导航或成功后的组织上下文切换。

后续实现使用 fake `IdentitySession` 和内存 `MockClient` 运行 focused tests：

```bash
flutter test test/organization_owner_transfer/http_organization_owner_transfer_gateway_test.dart
dart analyze
flutter test
dart run tool/check_markdown_links.dart
```

测试必须覆盖 path、body、headers、UUID canonicalization、非法输入的 no-token/no-request short-circuit、deferred no-network、identity failure、一次 `401` 刷新与相同 retry body、strict receipt／error parser、全部 stable mapping、脱敏、内存结果和可重复 `close()`。

本节的文档、Markdown link、no-slop 和 Dart analyzer 检查，以及 #316 的 Dart tests，只证明文字、静态语法、Flutter transport、strict parser 和内存边界，不证明 Backend、PostgreSQL、production identity、部署端点、真实组织、Drift、UI、删除恢复、Apple 或其他真人平台行为。

### 3.8 Flutter 组织 owner transfer composition（Issue #318，MANUAL-056，已交付）

Issue #318 将 #316 创建的 `OrganizationOwnerTransferGateway` 接入 `AppDependencies` composition root。builder 使用启动时打开的同一个 `IdentitySession`；`AppStartupReady.organizationOwnerTransferGateway` 暴露 builder 返回的同一个 gateway。没有注入 builder 时，composition root 使用不触网的 `DeferredOrganizationOwnerTransferGateway`。

如果 gateway 已创建而后续启动步骤失败，`AppDependencies.start()` 只关闭它一次。`TongxingzheApp` 在启动完成前被移除时，异步启动结果也只关闭该 gateway 一次；正常 `dispose()` 同样只关闭一次，重复 pump 不增加 close 次数。gateway 只由 composition root 持有和关闭，不传入 `_ReadyApp`、controller、UI、route 或 context switch。

本切片不改变 owner-transfer gateway、HTTP、Backend、PostgreSQL、identity、Drift 或组织状态合同，也不生成 request UUID、增加缓存、离线队列、同步或 durable retry。

运行以下本地检查：

```bash
flutter test test/app/app_dependencies_test.dart test/app/tongxingzhe_app_test.dart
dart analyze
flutter test
dart run tool/check_markdown_links.dart
```

这些 fake identity、fake gateway 和 widget tests 只证明本地 composition、deferred fallback 和资源生命周期，不证明 production identity、部署端点、真实 owner transfer、Backend、PostgreSQL、Drift、UI、Apple 或其他真人平台运行时。

### 3.9 组织定向账号邀请与接受（Issue #320，MANUAL-057，spec-only）

Issue #320 只固定已有内部账号的定向邀请合同。它落实 `ORG-001` 和 `ORG-002` 的私有组织边界，但不实现邀请功能。
用户看到的结果是：当前 active owner 可以邀请一个已有的 active 账号；只有这个指定账号可以在连续 168 小时内接受。
接受成功后只建立 organization membership，不自动成为 owner，不建立 project membership，也不授予任何 capability。
这不是邮箱邀请、可分享链接或公开加入入口。可分享链接只能创建待审批申请，另有独立合同。

#### 先确定谁可以做什么

首版只允许当前 active owner 创建邀请。实现不得猜测或新增成员管理 capability。目标是一个不可信的 opaque internal `app_user_id` selector。
数据库必须在锁后确认目标账号为 active、不是发起人，且尚未是该组织的 current member。目标组织由不可信的 workspace selector 指定，目标账号不需要预先属于该组织。
客户端不能提交 actor、email、external identity、Auth user object 或 raw invite token 作为业务事实，也不能通过目标 selector 枚举组织成员。
未注册账号和邮箱绑定邀请不在本节内。

创建和接受都先用 generic identity verifier 验证精确 `(issuer, subject)`，再由 identity bridge 解析当前 actor。
bridge 不 trim、normalize、bootstrap 或修复身份，也不复用 Slice 7A 的组织创建资格。只有解析出的 active internal account 是可信 actor。

#### 创建、接受和 168 小时期限

`invitation_id` 是单列 UUID，同时是邀请选择器、创建幂等键和 request-lock key。claim family 固定为
`organization-directed-account-invitation:v1`，request advisory-lock 前缀固定为
`organization-directed-account-invitation-request:`。

可以把一次邀请理解为以下步骤：

1. 当前 owner 提交新的 `invitation_id`、organization workspace selector 和目标账号 selector。数据库锁后重读 owner、目标账号、组织恢复状态和成员关系。
2. 首次创建把 claim、创建审计和邀请 receipt 放进同一个 transaction。`issued_at_utc` 使用一次数据库时间，`expires_at_utc` 恰好晚 168 小时，不受数据库 session time zone 或 DST 影响。
3. 目标账号用自己的精确 identity 接受。数据库锁后再次检查 claim、期限、目标账号和成员关系，然后在同一 transaction 中建立 organization membership、消费 claim 并追加接受审计。

pending 不是另存的状态。claim 尚未 accepted 且数据库当前时间早于 `expires_at_utc` 时，它就是 pending。系统不增加后台 sweeper 或 status history。
接受只建立 organization membership，不复活或改写已经结束的 membership，也不创建 project membership 或 capability。
目标账号若已通过其他路径入组，接受失败且不消费 invitation。

private 关系固定为 `app_private.organization_directed_account_invitation_request_claims`、`app_private.organization_directed_account_invitation_request_tombstones` 和 `app_private.organization_directed_account_invitation_audit_events`。
claim 只保存以下字段：invitation UUID、workspace UUID、可去关联的 inviter／target internal user UUID、`issued_at_utc`、`expires_at_utc`、可空的 `accepted_at_utc` 和 membership UUID。
claim 不保存邮箱或外部身份。pending claim 只追加一次接受结果；账号终结删除可以按统一规则去关联内部账号引用，除此和一次 pending-to-accepted 更新外，其他字段不能改写。

创建的精确重放必须由同一 active inviter identity 发起，并返回原 invitation receipt，不重复 claim 或审计。相同 inviter、workspace 和 target 才是精确重放；它不重新检查 inviter 的 owner／membership 或 target membership。identity 不再 active 或 claim 引用去关联时返回 forbidden；漂移或 invitation tombstone 返回 conflict。
接受的精确 target replay 必须仍由同一 active target identity 发起，并返回原 membership receipt，不重复建立 membership 或追加审计。它不重新检查 owner 或 target membership；identity 不再 active 或 target 引用去关联时返回 forbidden。只有尚未接受的 live claim 才重新检查 target、workspace、期限和当前成员关系。

创建 receipt 固定为 contract ID、invitation ID、workspace ID、issued time 和 expiry time。接受 receipt 固定为 contract ID、invitation ID、workspace ID、membership ID 和 accepted time。
未来 HTTP 的 UUID 使用 canonical lowercase，时间使用 UTC 毫秒精度。SQL row 保留完整的 `timestamptz` 精度，membership、claim、audit 和返回时间使用同一个未截断的 `transaction_timestamp()`。receipt 不含目标资料、邮箱或 replay flag。

#### 信任边界、锁和原子性

四个函数的名称、参数顺序和类型固定为：

- `app_data.create_organization_directed_account_invitation_for_identity_v1(text, text, uuid, uuid, uuid)`：issuer、subject、invitation、organization workspace、target app user；
- `app_private.create_organization_directed_account_invitation_v1(uuid, uuid, uuid, uuid)`：trusted actor、invitation、organization workspace、target app user；
- `app_data.accept_organization_directed_account_invitation_for_identity_v1(text, text, uuid)`：issuer、subject、invitation；
- `app_private.accept_organization_directed_account_invitation_v1(uuid, uuid)`：trusted actor、invitation。

返回类型固定为：

```text
create: text, uuid, uuid, timestamptz, timestamptz
accept: text, uuid, uuid, uuid, timestamptz
```

create row 依次是 contract ID、invitation ID、workspace ID、issued time、expiry time。
accept row 依次是 contract ID、invitation ID、workspace ID、membership ID、accepted time。
bridge 只调用对应 private writer。四个函数都是 `VOLATILE SECURITY DEFINER`，并固定 `search_path = pg_catalog`。
函数 owner 与现有 membership validator 相同，且不是 runtime。`PUBLIC` 不得执行这些函数；runtime 只能执行两个 bridge，不能直接写 claim、audit 或 membership。

锁序固定为：invitation request lock → 按 UUID 排序的受影响 app-user row locks → organization governance lock → organization membership lock。
锁后必须重读 claim、tombstone、账号状态、workspace recovery 状态和 membership，不能用锁前的检查结果写入。
同一 invitation request 由 request lock 串行化，同一组织的不同 request 由 governance lock 串行化。

接受 transaction 使用同一 `transaction_timestamp()` 原子完成 membership、claim acceptance 和 audit。创建也必须让 claim 与成功审计一起提交。
任何错误都必须回滚，不得留下半个 membership、半个 claim、半条 audit 或其他部分事实。

#### 稳定错误和不枚举对象

数据库与 Backend 只使用以下稳定分类：

| 条件 | SQLSTATE 与固定 message | Backend code |
| --- | --- | --- |
| trusted identity 输入非法 | `22023 invalid organization invitation identity` | `organization_invitation_unavailable` |
| invitation 或 selector 输入非法 | `22023 invalid organization invitation request` | `invalid_organization_invitation_request` |
| 当前 actor、目标、组织状态或邀请状态不允许 | `42501 organization invitation forbidden` | `organization_invitation_forbidden` |
| request、actor、workspace 或 target 漂移，或 tombstone 已存在 | `22023 organization invitation idempotency conflict` | `organization_invitation_conflict` |
| 未知数据库、parser 或 adapter 错误 | 不返回原始错误 | `organization_invitation_unavailable` |

未知 invitation／target selector、未知或非 organization workspace、inactive／deleted 账号、已过期 invitation、已通过其他路径入组，及恢复期组织中的新操作都统一返回 forbidden。
已接受 invitation 只允许原 target 做 exact replay；其他调用不能借此枚举邀请状态。
系统不区分 `not_found`、`expired`、`wrong_target` 或 `already_member`，以免暴露对象是否存在。首版没有 revoke 操作，也不增加 `revoked` 状态。
未来 HTTP 的成功和失败响应必须使用精确 `Content-Type: application/json; charset=utf-8` 与 `Cache-Control: no-store`；错误 root 只能是 `{ "error": { "code": "<stable-code>" } }`。后续 transport slice 再固定 raw route、method、认证顺序、body byte limit 和既有 `401`、`400`、`413`、`404` 结果。

#### 审计、恢复和清除

邀请 audit 只能追加且不可变。allowlist 只有 event ID、contract ID、invitation ID、workspace ID、固定 event kind、接受后的 membership ID 和数据库时间。
audit、响应、错误和结构化日志不得保存 inviter／target user ID、邮箱、名称、external issuer／subject、access／refresh token、Auth user object、provider metadata、请求原文、SQL、数据库 message、stack 或自由文本。

组织进入删除恢复期后，冻结新邀请和首次接受。已经接受的邀请仍可由同一 active target identity 只读精确重放；target 引用去关联后统一 forbidden。账号终结删除也先收集并排序取得受影响 invitation request locks，再取得 app-user、governance 和 membership locks。治理锁后重读 claim 集合；若出现未锁定的新 invitation，则回滚并用完整集合重试。

最终清除按 [ADR-0183](../adr/0183-bare-organization-membership-self-leave.md) 的当前全局 family 顺序、再按每个 family 内 UUID 排序取得 request locks；7W 已在 owner transfer 后追加 membership self-leave。不能先拿 governance lock 再反向拿 request lock。随后才按既有顺序取得 app-user、governance 和 membership locks，并在治理锁后重读。
清除先保留只含 `claim_family` 和 invitation UUID 的 tombstone，再删除 claim、audit 和组织业务记录。删除、恢复和 purge writer 本身由后续工作单元实现。

本票不实现邮箱或未注册账号邀请、邮件投递、邀请 revoke、可分享链接、加入申请、审批或成员目录。
它也不实现 migration、SQL、Backend route／store、Flutter gateway、controller、UI、通知、project membership／capability、co-owner grant、owner transfer、组织上下文切换、Drift、缓存、离线、同步、账号／组织 deletion、recovery 或 purge writer。

验证只运行文档检查：

```bash
node /Users/xavieredith/.codex/skills/no-slop/slop-lint.mjs docs/manual/04-identity-and-current-context.md
dart run tool/check_markdown_links.dart
git diff --check
```

这些检查只证明文字、链接和补丁格式。Issue #320 不证明数据库 schema、事务原子性、并发锁、真实 identity、HTTP、邮件投递、UI、生产部署、Apple 或真人平台行为。

### 3.10 通过 HTTP 创建与接受定向账号邀请（Issue #326，MANUAL-058）

3.9 说明邀请的数据库合同；7P／#322 已用 0087 实现它。7R／#326 把两个操作接到 Backend。
它仍没有 App 页面、账号目录或邀请投递功能。目标账号 UUID 只是调用方明确提供的 selector，不是查询邮箱或搜索账号的权限。
HTTP 决定见 [ADR-0181](../adr/0181-organization-directed-account-invitation-http-contract.md)，实现见 [invitation module](../../backend/server/src/organization-directed-account-invitations.ts)。

#### 两个请求分别携带什么

创建者使用自己的 Bearer token。组织来自 path；body 只允许 invitation 与目标账号 UUID：

```http
POST /v1/organizations/00000000-0000-0000-0000-000000000001/directed-account-invitations
Authorization: Bearer <access_token>
Content-Type: application/json

{"invitation_id":"00000000-0000-0000-0000-000000000002","target_app_user_id":"00000000-0000-0000-0000-000000000003"}
```

接受者使用绑定目标账号自己的 Bearer token。invitation 来自 path，body 必须是空 JSON object：

```http
POST /v1/organization-directed-account-invitations/00000000-0000-0000-0000-000000000002/accept
Authorization: Bearer <access_token>
Content-Type: application/json

{}
```

`{}` 与没有 body 不同：前者表示没有额外业务参数；后者不是有效 JSON 请求，返回 `invalid_json`。
接受时不能再提交 workspace、target、actor、email 或 token 字段，数据库从 invitation claim 决定组织与目标账号。
UUID 可以用大写或小写十六进制，但形状必须是 `8-4-4-4-12`；Backend 校验后统一小写，不另行限制 UUID version 或 variant。
重试创建必须使用同一 invitation、组织和 target；接受重试只使用同一 invitation 和 exact target identity。HTTP 不生成新幂等键，也不维护重试队列。

#### 为什么先认证、后解析

[server](../../backend/server/src/server.ts) 先用 raw pathname 匹配 route，再交给 handler：

1. 错误 method、额外／重复／末尾 slash、dot segment 或任何 percent-encoded path 返回通用 404，不认证或读取 body。
2. 命中后严格解析 Bearer，再用 generic `IdentityVerifier` 验证身份。此处不调用 7A 组织创建资格或 Auth user endpoint。
3. 认证成功后拒绝 query（只有 `?` 也算），再验证 path UUID、检查专用 store。
4. 最后按实际 byte 数读取 JSON，验证精确字段，调用一次对应 store method，等待结果后响应。

因此无效 token 不能靠 malformed body 或未知 invitation 探测业务状态。missing verifier／store 也在 body 读取前失败关闭。
reader 支持 chunked，并按 UTF-8 的实际 byte 数计数，不按字符数或 `Content-Length` 声明判断。
1,048,576 bytes 仍可解析，超过这个边界返回 413。示例发送 JSON Content-Type，但 handler 不增加该请求 header 的门禁。

#### Store 与两个独立结果

`OrganizationDirectedAccountInvitationStore.create` 只接收已验证 identity、invitation、workspace 和 target。
`accept` 只接收已验证 identity 与 invitation。两个 method 各自只运行一次对应的 0087 参数化 identity bridge，不拆成多条业务 SQL。
它们不访问 `app_private`，不查询账号资料，也不使用 session context 或 creation／transfer store。
[main](../../backend/server/src/main.ts) 复用既有 pool query 和 generic verifier，注入一个 dedicated Postgres invitation store，不新增环境变量。

create 与 accept 分别返回 3.9 的五字段 receipt，不使用带可选字段的混合 envelope。
create 结果须绑定请求 invitation 与组织；accept 结果须绑定 path invitation，组织与 membership 由数据库返回。
Backend 检查精确字段、contract ID、UUID、日期与请求绑定。create 的 expiry 仍须精确晚于 issued 168 小时。
有效数据库 Date／RFC3339 instant 转成 UTC 毫秒时间，SQL 中的完整时间精度不变。未知或漂移结果不交给调用者。
首次和精确重放都返回 200，没有 replay flag。等待 pool query 完成只说明数据库调用已完成，不证明远端客户端收到或保存了 receipt。

#### 错误不能变成邀请状态查询

| 状态 | 稳定 code |
| --- | --- |
| 404 | `not_found`，只用于 route／method 不匹配 |
| 401 | `unauthenticated` |
| 400 | `invalid_json` 或 `invalid_organization_invitation_request` |
| 413 | `payload_too_large` |
| 403 | `organization_invitation_forbidden` |
| 409 | `organization_invitation_conflict` |
| 503 | `organization_invitation_unavailable` |

DB 错误只接受 3.9 的 exact SQLSTATE／message 配对。未知 invitation、target 或组织，以及过期、错误接受者、已有成员、恢复期或账号去关联，都不由 HTTP 预查。
数据库将这些业务拒绝收敛为 forbidden；只有 claim drift／tombstone 使用 conflict。不能添加 `expired`、`already_member` 或业务 `not_found`。
未知数据库、verifier、adapter 和 parser 错误统一 unavailable，不带原始 message、SQL、stack 或身份资料。
所有响应固定 `Content-Type: application/json; charset=utf-8` 和 `Cache-Control: no-store`，错误只含 `{"error":{"code":"stable_code"}}`。
响应、日志和失败审计仍遵守 3.9 的 value-free allowlist，不保存身份、token 或请求原文。

#### 可以复制的验证命令

```bash
npm --prefix backend/server run check
npm --prefix backend/server run build
node --test \
  backend/server/dist/test/organization-directed-account-invitations.test.js \
  backend/server/dist/test/organization-directed-account-invitations-route.test.js \
  backend/server/dist/test/organization-directed-account-invitations-composition.test.js
npm --prefix backend/server test
./tool/run_postgres_tests_in_docker.sh
dart run tool/check_markdown_links.dart
git diff --check
```

unit tests 验证 handler／store 合同；本地 HTTP tests 验证 raw route、认证顺序、bytes、headers、错误和 Promise gate。
composition tests 检查生产接线源码，不等于生产服务已部署。Docker runner 使用隔离 synthetic PostgreSQL，运行 create／accept runtime bridge integration、既有 0087 检查与 dump／restore。
7R 不新增 migration、权限、Flutter、UI、邮件、账号／成员／邀请目录、通知、分享链接、审批、revoke、capability、上下文切换、缓存、离线或删除 API。
上述检查不证明 production identity、部署端点、邮件送达、真实组织、Apple 或真人平台运行时。

### 3.11 Flutter 定向邀请 gateway 与资源生命周期（Issue #328，MANUAL-059）

7S 为 3.10 的两条 HTTP 入口提供 Flutter typed gateway，并把它接入 App 启动与关闭流程。
调用方只交明确的 UUID，得到 success 或稳定 failure；它不需要解释 token、HTTP response 或数据库错误。
这仍不是可点击的邀请功能：App 尚未提供账号目录、邀请投递、组织上下文或操作页面。

接口与不可变结果在 [organization_directed_account_invitation.dart](../../lib/organization_directed_account_invitation/organization_directed_account_invitation.dart)。
HTTP 实现在 [http_organization_directed_account_invitation_gateway.dart](../../lib/organization_directed_account_invitation/http_organization_directed_account_invitation_gateway.dart)。

#### 两个 method 与两个 receipt

`OrganizationDirectedAccountInvitationGateway.create` 接收调用方提供的 invitation、organization workspace 和 target app user UUID。
`accept` 只接收 invitation UUID；gateway 自动把它放入 acceptance path，并发送 `{}`，不能替用户选择接受者。
两者先验证 UUID 并转 lowercase，再取 token；非法输入直接返回 invalidRequest，不触网。
gateway 不生成 invitation UUID，也不查询目标账号、owner、membership 或邀请状态。

下面是简化调用示例，变量均由调用方提供，不表示当前 App 已有对应 UI。
两次调用分别来自 owner 与绑定 target 的身份会话；owner 不能替另一个账号接受邀请：

```dart
final created = await ownerGateway.create(
  invitationId: invitationId,
  organizationWorkspaceId: organizationWorkspaceId,
  targetAppUserId: targetAppUserId,
);
final accepted = await targetGateway.accept(invitationId: invitationId);
```

create 与 accept 分别返回 `CreateSuccess`／`CreateRejected` 和 `AcceptSuccess`／`AcceptRejected`，完整类型名都以 `OrganizationDirectedAccountInvitation` 开头。
两个 receipt 分别保存 3.9 的五个字段；ID 为 String，时间为 UTC DateTime，字段不可修改。
create parser 绑定 invitation 与 workspace，accept parser 绑定 invitation。两者都拒绝多余／缺少字段、错误 contract、非小写 UUID、无效日期和错误绑定。
日期必须是 canonical UTC 毫秒格式，不能让 DateTime 自动把不存在的日期改成下个月。
create 的 expires 必须精确晚于 issued 168 小时，但不会拿设备当前时间拒绝旧 receipt。
因为精确重放可以返回历史 receipt，判断过期、已接受或成员资格仍是 Backend／0087 的责任。

#### Token、重试和错误

gateway 使用同一个 `IdentitySession`，请求固定带 Accept JSON、Bearer 和 JSON utf-8 headers。
只有第一次响应同时通过 JSON／no-store 和精确 `401 unauthenticated` 检查，才强制刷新一次 token。
retry 复用相同 URL 与 body；第二次 401 返回 unauthorized，不能再次刷新。响应字段或 headers 不合法时直接 invalidResponse，不尝试“修复”数据。

两操作共用十个 failure code：notConfigured、unauthorized、invalidJson、payloadTooLarge、invalidRequest、forbidden、conflict、serviceUnavailable、networkUnavailable、invalidResponse。
其中 400／401／403／409／413／503 沿用 3.10 的固定映射；网络、timeout 和 HTTP client 异常映射 networkUnavailable。
未知 status／code、404、非法 JSON／headers／receipt 和其他异常为 invalidResponse，不向调用者暴露原文。
不存在 expired、wrongTarget、alreadyMember、业务 notFound 或 replay flag；这些字段会把邀请状态变成可探测信息。

#### 配置与关闭由谁负责

`productionOrganizationDirectedAccountInvitationGateway` 读取既有 `BACKEND_BASE_URL`。
空配置返回 deferred，两个 method 都给出 notConfigured，不创建或发送 HTTP 请求。
非空配置先通过 URI 解析和现有 pathless validator，再创建 client；非法配置同步失败，不静默降级。
HTTP gateway 接管传入 client，重复 close 只关闭一次；它不关闭 identity session，不写 Drift、缓存、同步队列或日志。

[AppDependencies](../../lib/app/app_dependencies.dart) 的 invitation builder 接收启动时同一个 identity session。
production 使用上述 factory，测试或调用方没有提供 builder 时使用 deferred。
`AppStartupReady.organizationDirectedAccountInvitationGateway` 保存 builder 返回的同一实例，不再创建第二个 gateway。

App 资源关闭分为三种路径：

1. gateway 创建后，后续启动步骤失败：AppDependencies 清理已创建的实例。
2. App 已被移除，启动结果才回来：TongxingzheApp 清理该结果中的实例。
3. App 正常启动后退出：dispose 关闭持有的实例。

每种路径都只关闭一次。gateway 仍只由 composition root 持有，不传给 `_ReadyApp`、controller、UI 或 context switch。

#### 验证与证据范围

```bash
flutter test --no-pub \
  test/organization_directed_account_invitation/http_organization_directed_account_invitation_gateway_test.dart \
  test/app/app_dependencies_test.dart \
  test/app/tongxingzhe_app_test.dart
flutter test --no-pub \
  --dart-define=BACKEND_BASE_URL=https://example.invalid/prefix \
  test/organization_directed_account_invitation/http_organization_directed_account_invitation_gateway_test.dart
dart format --output=none --set-exit-if-changed lib test
dart analyze
flutter test --no-pub
dart run tool/check_production_boundary.dart
dart run tool/check_markdown_links.dart
```

第二条命令只检查非法 build-time 配置，测试不连接 example.invalid。focused tests 使用 fake identity 与 MockClient，覆盖两个操作、headers、一次刷新、严格 parser、错误和 client ownership。
两个 App 测试文件检查同一 identity／gateway、缺省 deferred 和三类关闭路径。它们不模拟真实邀请投递，也不证明 UI、production identity、部署、Backend 授权、数据库事务或真人平台行为。
7S 不改变 0087／HTTP，也不新增目录、邮件、通知、审批、revoke、capability、离线、durable retry 或删除 API。

### 3.12 从当前项目菜单创建组织（Issue #330，MANUAL-060）

7T 把 3.5 的组织创建 gateway 接到正式 App：登录并载入项目后，打开顶部项目菜单，选择“创建组织”。
个人和组织当前上下文中的账号都能看到入口。界面不会因为你不是当前组织 owner 就隐藏它，因为这里创建的是一个新组织。
能看到入口不等于已获创建资格；Backend 仍按 7A 验证当前账号和邮箱状态。

[organization_creation_dialog.dart](../../lib/features/organization_creation/organization_creation_dialog.dart) 只接收组织名称。
它提示明显空值或过长输入，但不替数据库决定完整 Unicode 名称规则，也不把输入 trim 后再提交。
隐藏的 request UUID 来自 [secureUuidV4](../../lib/foundation/runtime_values.dart)，该函数复用现有 consent opt-in 的算法。
既有 `SecureIdGenerator` 仍产生原来的不透明非 UUID 字符串；不能把两种 ID 格式混用。

#### 为什么重试必须保留请求

一次有效提交把“请求 UUID＋原名称”组成当前意图，随后显示“正在创建组织”，禁止重复提交。
服务器可能已经成功创建，但响应在返回途中丢失。此时再生成一个 UUID，会被服务器视为另一次创建。
因此网络失败、服务不可用、无法验证响应或 conflict 后，表单冻结原名称和 ID，只允许重试原请求或明确放弃。

不确定性不能被后来的拒绝覆盖。例如第一次创建已提交但响应丢失，第二次账号状态变化而被拒绝，不能据此断定第一次没有创建。
这个意图仍保持冻结，直到收到成功 receipt 或用户确认放弃。
只有从未出现不确定结果的明确拒绝，才允许修改名称；改名后的首次提交使用新的意图 ID，同名重试仍用原 ID。
界面不自动重试，不把重新连网当成重新创建的命令。

普通取消直接关闭。对不确定结果选择关闭时，当前对话框先说明：组织可能已经存在，关闭后不能继续该次重试，再次创建可能产生另一个组织。
“保留并返回”回到原表单，“放弃并关闭”才丢弃本地意图。
这里的放弃只丢弃重试资料，不撤销已经发送的服务器请求。

意图只存在当前对话框内存，不写 Drift、偏好、日志或同步队列。
关闭 App 后不能恢复该请求；界面提前显示这个限制。本切片没有跨重启恢复、创建请求查询或组织目录。

#### 身份变化和成功反馈

对话框记录开窗时 Backend 已验证的 app user，并观察 `AppSession.changes`。
账号不再 ready 或换成另一位 app user 时，旧表单立即移除，不能继续提交，也不展示迟到的结果。
每次点击提交前还会再次检查会话。关闭对话框只释放自己的输入 controller 和 subscription，不关闭 AppSession 或 gateway。

十种 gateway failure 都映射为中英文提示，不显示身份服务、HTTP、数据库或异常原文。
成功 receipt 由 gateway 校验后返回；对话框关闭，App 提示“组织已创建，当前项目未切换”。

为什么不马上进入新组织？组织创建只返回 workspace、membership 和首位 owner，没有 project。
现有 `TrustedSessionContext` 必须有 project 和 questionnaire；owner 也不自动取得项目 membership 或 capability。
所以本切片既不切换 AppSession，也不假装刷新后就能看见新组织。组织项目、目录和上下文选择仍需后续工作。

[TongxingzheApp](../../lib/app/tongxingzhe_app.dart) 把已有 startup gateway 传给 `_ReadyApp`，再传给 [ProductionHomeShell](../../lib/screens/production_home_shell.dart)。
UI 使用同一个实例，不另建 HTTP client；启动失败、提前卸载和正常退出的资源清理由原 composition root 负责。

#### 验证与证据范围

```bash
flutter test --no-pub \
  test/features/organization_creation/organization_creation_dialog_test.dart \
  test/foundation/secure_uuid_v4_test.dart \
  test/organization_creation/http_organization_creation_gateway_test.dart \
  test/project_settings/http_personal_follow_up_consent_opt_in_gateway_test.dart \
  test/app/app_dependencies_test.dart \
  test/app/tongxingzhe_app_test.dart \
  test/features/home/production_home_shell_accessibility_test.dart
dart analyze
dart format --output=none --set-exit-if-changed lib test
flutter test --no-pub
dart run tool/check_production_boundary.dart
dart run tool/check_markdown_links.dart
```

Widget 检查覆盖原名称、UUID、重复点击、十种错误、不确定性保持、编辑后的新意图、取消确认、身份切换和迟到结果。
还需检查键盘／Escape／焦点返回、状态 live region、中英文、320×568 小屏与 200% 字号、宽屏和触控目标。
App 测试验证入口真实使用注入 gateway，成功后没有调用项目创建、目录刷新或上下文切换。
这些 fake identity／gateway 与 synthetic UI 检查不证明生产服务已部署、真实账号可用或真人平台已验收；六平台 build 也不能替代运行时证据。
本切片不修改 Backend／数据库，不提供邀请、组织项目、跨重启恢复或删除流程。

### 3.13 读取当前账号加入的组织（Issue #332，MANUAL-061）

组织创建成功后可能还没有项目。项目上下文必须包含 project 和 questionnaire，不能为了显示组织而造出一个项目或假上下文。
因此“我的组织目录”使用独立的只读接口。它回答“我目前加入哪些未删除组织”，不回答“我可以进入哪些项目”或“我是哪些组织的 owner”。

#### 从身份到目录

Backend 验证 generic Bearer token，然后只把 exact issuer／subject 传给 `app_data.list_organizations_for_identity_v1(text,text)`。
这里不检查邮箱创建资格，不 bootstrap 新账号，也不接受用户 ID、组织 ID 或项目 selector。
reader 拒绝 NULL、ASCII-space 空身份和原值超长。未知、去关联或非 active 用户统一 forbidden；已识别的 active 账号没有组织则返回零行。

0089 在一个查询快照内检验 active user、organization membership 的当前半开区间和 workspace 的未删除状态。
一个 `clock_timestamp()` 取样用于所有成员区间，不用客户端时间，也不把 transaction 启动时间当作稍后的读取时间。
`active_from_utc` 恰好等于取样时刻时属于有效区间，`inactive_from_utc` 恰好相等时已经无效。
个人 workspace、其他账号的组织和恢复期组织都排除。没有项目、问卷或管理能力不会排除有效组织成员。

返回只有组织 UUID 与数据库中的名称。名称按 `COLLATE "C"` 排序，UUID 作为同名时的稳定次序；不修改旧名称，不合并同名组织。
v1 完整读取，不设任意数量截断。若单账号目录规模确实影响读取延迟，再单独定义分页；不能先返回前若干条却让用户误以为这是全部。
函数使用既有 trusted owner、SECURITY DEFINER 与固定 search_path。迁移显式撤销 PUBLIC 函数权限；runtime 只执行 reader，不能 SELECT 身份、workspace 或 membership 底表。

这只是读取时的快照。用户看到组织后可能立即被移除，后续操作仍要重新授权；列表不是可复用的权限证明，也不是组织恢复页面。

#### GET 与创建 POST 如何共存

`GET /v1/organizations` 读取，既有 `POST /v1/organizations` 仍按 7A 资格创建。
GET 先匹配原始 canonical 路径，再认证，再拒绝 query（含裸 `?`）和声明 body，最后检查 store 并等待一次 reader。
`Content-Length` 缺省或精确 `0` 且无 `Transfer-Encoding` 才按无 body 处理；GET 不解析 JSON。
错误 method、编码、dot、重复／尾 slash 路径返回通用 404，不走认证或数据库。

200 的 root 只有 `organization_directory_contract_id: "organization-directory:v1"` 和 `organizations`。
数组每项只有 `organization_workspace_id` 与 `organization_name`，空数组是正常成功。
store 拒绝非 canonical UUID、非法名称、错误字段／类型和重复 UUID；它不会静默丢弃坏行或输出部分目录。
名字仅按已保存数据的最低有效性检查，不套用后来新增的创建规则，也不在客户端修剪。

无效 query／声明 body 返回 400 invalid request；未认证返回 401 unauthenticated；数据库身份不可用返回 403 forbidden；缺配置、parser、数据库或未知异常返回 503 unavailable。
完整 wire code 见 [Product Spec 7U](../PRODUCT_SPEC.md#slice-7u当前账号的只读组织目录)。响应固定 JSON UTF-8、no-store，不输出 token、身份或异常原文，也不记录目录内容。

#### 验证与证据范围

```bash
npm --prefix backend/server run check
npm --prefix backend/server run build
node --test \
  backend/server/dist/test/organization-directory.test.js \
  backend/server/dist/test/organization-directory-route.test.js \
  backend/server/dist/test/organization-directory-composition.test.js
npm --prefix backend/server test
bash tool/run_postgres_tests_in_docker.sh
dart run tool/check_markdown_links.dart
```

Docker runner 运行 0089 migration、结构 check、回滚 fixture 和 runtime integration，并继续验证既有 migrations、权限、checksum 与独立 dump／restore。
fixture 需覆盖项目为空仍可见、有效账号空列表、时间边界、身份原值、跨账号、恢复期、同名顺序和直接 SELECT 被拒绝。
HTTP 检查覆盖认证先后、声明 body、无 query、await、精确结果和错误脱敏，并确认 POST 未受影响。
这些 synthetic 证据不证明生产身份、部署端点、真实组织或真人平台；本切片还没有 Flutter gateway／列表、项目创建／切换、成员治理或恢复流程。

### 3.14 在当前项目菜单查看我的组织（Issue #333，MANUAL-062）

7V 把上一节的 GET 接到正式 App。用户打开“我的组织”时读取一次，之后由“刷新”重新读取。
它是账号范围的只读列表，不是项目切换器：只显示组织名与完整 UUID，没有进入项目、邀请或成员管理按钮。
UUID 用于区分同名组织，可选中文字，但不是访问凭证。查看列表后，原当前项目保持不变。

#### Gateway 怎样保持读取合同

`OrganizationDirectoryGateway.list()` 返回成功的不可修改列表，或七种脱敏 typed failure。
`OrganizationDirectoryEntry` 只有组织 workspace ID 与原名称；它不带 owner、membership、project、能力或原 response。
HTTP 只发无 query／body 的 GET，传 Accept JSON 和 Bearer，不发送 Content-Type 或幂等键。
200 parser 先验证 JSON UTF-8 和 no-store，再检查固定两字段 root 与每项两字段、contract ID、小写 UUID、非 ASCII-space 空名称和重复 UUID。
任何一项坏数据都使整个目录失败，不留下部分列表；旧名称不 trim、不按新建规则重验，顺序与同名组织原样保留。

只有完整合法的 `401 unauthenticated` 才允许一次 token refresh，并向同一 URL 重发 GET。
第二次 401 为 unauthorized，不能递归刷新。其他 HTTP status／code 只接受 7U allowlist；网络故障与响应无法验证保持不同错误类别。
目录错误没有 creation／invitation 的写入幂等问题，不需要 request UUID、uncertainty 状态或 durable retry。

空 Backend URL 返回 deferred 的 notConfigured，不发送网络请求。非法非空 URL 在分配 client 前同步失败。
HTTP gateway 只关闭自己的 client 一次，不关闭 IdentitySession；目录不写 Drift、偏好、日志、同步或缓存。

#### 开窗和账号变化

对话框记录开窗时的 ready appUserId。刷新前先清除上次结果，再发送新 GET；失败是失败，不保留旧权限快照，也不显示成“没有组织”。
AppSession 不再 ready 或换成另一个账号时，立即清空并禁用读取。晚到的结果不显示；本次开窗失效后，即使账号恢复，也需要关闭后重新打开。
同一账号的项目变化不作为目录筛选条件。读取期间可以关闭窗口，关闭只停止本地展示，不宣称撤销已经发出的请求。

同一个 startup gateway 经 AppStartupReady、`_ReadyApp` 传到 ProductionHomeShell。
composition root 处理后续启动失败、启动完成前移除 App 和正常 dispose 三种关闭路径；对话框只取消自己的订阅，不接管共享资源。
创建组织成功后，下次打开目录会读取新结果；不因此自动切换项目、创建项目或发起项目目录刷新。

#### 验证与证据范围

```bash
flutter test --no-pub \
  test/organization_directory/http_organization_directory_gateway_test.dart \
  test/features/organization_directory/organization_directory_dialog_test.dart \
  test/app/app_dependencies_test.dart \
  test/app/tongxingzhe_app_test.dart
dart analyze
dart format --output=none --set-exit-if-changed lib test
flutter test --no-pub
dart run tool/check_production_boundary.dart
dart run tool/check_markdown_links.dart
```

focused tests 检查 strict wire、七类失败、401、配置、单次 close、菜单与同一 gateway、空列表／刷新、身份切换和迟到结果。
UI 还需核对中英文、keyboard／Escape／焦点返回、状态 live region、48 dp 控件、长名称／UUID、320×568／200% 字号及暗色宽屏。
这里的 MockClient、fake identity／gateway、synthetic widget 和视觉检查不证明真实身份、服务部署或真人平台已验收；六平台 build 也不能替代运行时。
本切片不修改数据库或 Backend，不提供组织项目、成员管理、邀请 UI、恢复期或删除操作。

### 3.15 无下游关系成员自助退出（Issue #336，MANUAL-063）

7W 先服务一种简单情况：用户接受邀请后，还没有组织项目成员记录，也没有组织对象分配，希望离开该组织。
数据库只结束这条组织 membership，不删除账号、组织或历史事实，不切换当前项目。
它不是完整退出 UI，也没有实现 PII-003 的本地敏感缓存清除。

#### 为什么有依赖时整体拒绝

当前或未来 owner 必须先完成相应所有权处理；即使组织有多个 owner，这个入口也不替其放弃所有权。
过去已经结束的 owner 历史可以保留。membership 若已有未来结束时间，也不能再修改一次。
只要该 membership 存在任何项目成员历史，或本人有本组织 `ended_at IS NULL` 的对象分配，就统一返回 forbidden。
这样不会把仅关闭父 membership 误当成已经结束项目 capability、对象分配或清除了缓存。
未来完整退出需按 capability → project membership → organization membership 处理，并独立结束对象分配和清除缓存。

当前正式对象 writer 仅接受 personal workspace；7W 不开放组织对象写入。未来组织分配和重新激活必须与退出共享明确的授权与锁协议。
旧的 management-analysis context 绑定 exact membership lineage；结束旧 membership 后不会因重新入组而复活。

#### 请求、重放与数据库时间

Backend 接受 `POST /v1/organizations/:organizationWorkspaceId/membership-self-leave`，body 只有 `request_id` UUID。
账号来自经过验证的 exact identity，不接受 body 里的 actor、membership、owner、项目或时间。
缺配置和未知内部错误为 unavailable；身份／资格／依赖失败与输入错误分开，完整 status／code 见 [Product Spec 7W](../PRODUCT_SPEC.md#slice-7w无下游关系成员自助退出)。

数据库依次锁定 request、actor、组织治理和 membership，锁后才取一次当前时间。
同一时间用于重新判断资格、结束 membership、保存 claim／audit 和返回 receipt。不能使用事务开始时间，因为事务可能正在等待另一次入组完成。
两个并发请求不会各自结束一次；同 request 精确重放，另一新 request 在 membership 已结束后 forbidden。
并发测试让另一事务在退出事务开始后实际插入 membership，模拟接受邀请的数据库产物；它不把这个 INSERT 证明写成完整邀请 HTTP 流程证明。

网络丢失成功响应时，用同一 request 和组织重试即可取得原四字段 receipt。
重新加入后，旧 request 仍只返回旧退出结果，不能结束新 membership；新的退出意图必须用新 request。
不同 actor／workspace、去关联 claim 或同 family tombstone 为 conflict。恢复期禁止首次操作，但已有 live claim 可以只读重放。

claim 的 actor 只能在账号终结删除中去关联一次；audit 不含 actor、组织名称或身份。
未来组织 purge 先按创建、邀请、owner transfer、self-leave family 锁定完整 request 集合，再保留只有 family／request UUID 的 tombstone 后清除业务记录。
7W 只固定这些边界，不执行账号或组织删除。见 [ADR-0183](../adr/0183-bare-organization-membership-self-leave.md)。

#### 在隔离测试库验证

最直接的入口会建立并自动清理 synthetic PostgreSQL 容器，不使用真实用户：

```bash
./tool/run_postgres_tests_in_docker.sh
```

只调试这一切片时，先确认 `DATABASE_URL` 指向可丢弃的测试库，然后从仓库根目录运行：

```bash
./tool/postgres_migrate.sh
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/checks/verify_organization_membership_self_leave.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/fixtures/0090_organization_membership_self_leave.sql
./tool/verify_organization_membership_self_leave_concurrency.sh
npm --prefix backend/server run check
npm --prefix backend/server test
dart run tool/check_markdown_links.dart
```

fixture 会回滚；并发脚本会在测试库提交独立 synthetic namespace，所以不能向真实数据库执行。
runtime 只能执行 exact identity bridge，不可读写 membership、owner、claim 或 audit 表，也不可调用 private writer。
Docker 还检查 Backend integration、checksum 和独立 dump／restore；恢复库重跑 check／fixture，不重跑已提交型并发脚本。
通过只证明本地数据库与 transport 合同，不证明 Flutter、真人退出、生产身份、服务部署、敏感缓存清除或 Apple 行为。

### 3.16 成员退出客户端网关（Issue #338，MANUAL-064）

7X 接通上一节的 Flutter transport 与 App 资源生命周期，但没有退出按钮或确认对话框。
gateway 的调用者只提供 request UUID 与组织 workspace UUID；账号由同一个 IdentitySession 提供，不从表单接受。
无效输入在取得 token 或联网前拒绝。合法 UUID 规范为小写，POST body 只含 request_id，不增加 query 或其他幂等 header。

成功返回不可变四字段 receipt；十种 typed failure 保留 notConfigured、unauthorized、invalidJson、payloadTooLarge、invalidRequest、forbidden、conflict、serviceUnavailable、networkUnavailable、invalidResponse 的区别。
响应必须有 JSON UTF-8 与 no-store，200 还检查 exact keys、固定合同、小写 UUID、请求组织一致和合法 UTC 毫秒时间。
失败只映射 Backend 的 exact status／code，不输出 provider、网络或数据库原文。

只有合法的 `401 unauthenticated` 才刷新 token 一次，URL、request UUID 与 JSON body 都保持不变；第二次 401 停止。
网络断开与响应无法验证不同，不自动生成新 request 或重试业务失败。
同一 request 返回的是先前操作的 receipt，不是当前成员状态。重新入组后要再次退出，调用者必须创建新的请求意图并提供新 UUID。

空配置使用无网络 deferred；非法非空配置在分配 HTTP client 前失败。有效配置复用既有 pathless URI validator。
gateway 只关闭自己的 client 一次，不关闭 IdentitySession，也不持久化 receipt。
AppDependencies 缺省 builder 使用 deferred，production 注入 factory；AppStartupReady 持有同一 gateway。
后续启动失败、完成前移除 App、正常 dispose 均关闭一次。没有向 controller／UI 发起请求，也不刷新组织目录或切换项目。

```bash
flutter test --no-pub \
  test/organization_membership_self_leave/http_organization_membership_self_leave_gateway_test.dart \
  test/app/app_dependencies_test.dart \
  test/app/tongxingzhe_app_test.dart
dart analyze
dart format --output=none --set-exit-if-changed lib test
flutter test --no-pub
dart run tool/check_production_boundary.dart
dart run tool/check_markdown_links.dart
```

MockClient、fake identity 与 App tests 验证 transport、配置和资源生命周期；不重复运行未改变的 DB 实验。
本切片没有 UI、跨重启恢复、权限级联或 PII cache 清除，不能据此宣称完整用户退出或生产／真人平台已验收。

### 3.17 在我的组织确认退出（Issue #342，MANUAL-065）

7Z 在组织目录的每个条目加入退出入口。用户先选择组织，再看名称、完整标识、资格限制和缓存影响；仅打开确认页或取消不会发退出请求。
“没有项目历史”指本次将结束的 membership；不是把用户以前所有 membership 的历史混在一起。其余资格仍按 [ADR-0183](../adr/0183-bare-organization-membership-self-leave.md) 由数据库判断。

#### 为什么先清缓存

如果先发 HTTP，再等成功响应清缓存，网络中断会留下一个难判断的状态：服务端可能已经退出，设备却还保存旧资料。
所以这里先按所选组织清除本地敏感缓存，确认清除完成后再发退出请求。代价是服务端随后拒绝时缓存也不会恢复；确认页会提前说明。
个人空间和其他组织快照不会被一并清除，也不因这次操作解除已有锁。

Vault 每个登录主体只有一份加密快照。条件清除在同一队列内读取它并比较 workspace；匹配才先写 `organizationLeaveRequested` 锁再删除。
没有快照或快照属于其他 workspace 是 `notPresent`。不能读取或判断归属是 `unavailable`，删除失败是 `pending`；后两种都停止 HTTP 并显示重试提示。
清除前同步增加旧请求代次，因此在清除前启动的迟到刷新不能恢复资料。不新增多 workspace 表、持久退出请求或 tombstone。

`AppSession.isCurrentUser` 不只看界面保存的 app user，还核对实时登录主体。清除前后复核账号与会话代次，HTTP 前再同步检查。
网关在 token 等待、HTTP 和一次 401 刷新期间继续绑定原始登录；切账号以及注销再回到同一账号都不能让旧意图继续发请求。
Widget 从不读取 token 或 external subject。当前正式组织上下文及组织对象 writer 尚未开放；未来开放时，仍需另行处理退出期间新发起的组织 PII 请求，不把旧请求 fence 当永久撤权。

#### 重试和回执

第一次确认生成 UUID-v4。结果不确定时，只在本窗口保留同一 UUID 与所选组织；用户点重试才再次提交，不自动重发。
关闭不确定结果要再次确认；关闭 App 后不恢复这次请求。重新打开先读当前目录，再由用户决定是否建立新的退出意图。
成功回执只证明这一次请求，不能证明用户现在仍未入组。父窗口重新读取目录；若用户已重新加入，组织仍会显示，不按旧回执删掉它。
清除失败、服务端拒绝、会话失效和网络不确定分别显示提示，不把它们写成退出成功；当前项目不变。

```bash
flutter test --no-pub test/features/organization_directory \
  test/organization_membership_self_leave \
  test/privacy/offline_pii_vault_test.dart \
  test/app_session/app_session_test.dart \
  test/app/tongxingzhe_app_test.dart
dart analyze
dart format --output=none --set-exit-if-changed lib test integration_test test_driver tool
flutter test --no-pub
dart run tool/check_production_boundary.dart
dart run tool/check_markdown_links.dart
```

这次没有改动 DB 或 Backend，不重复跑未改变的数据库实验。可控 Future、fake identity／存储和 Widget 证明本地顺序、拒绝与清除合同；CI build 证明可编译。
这些证据不证明真实设备安全存储删除、真实用户退出、生产配置或完整组织退出。

### 3.18 预览并确认接受组织邀请（Issue #344，MANUAL-066）

7AA 在“我的组织”提供“接受邀请”。用户输入已有 invitation UUID，先在线核对组织原名称与 UTC 有效期，再点“确认加入”。
邀请编号只是定位邀请的标识，不是任何持有者都能使用的通行证。只有绑定的 active 收件人可读；组织目录仍只列出当前已加入的组织。
这项入组前读取经过用户明确授权，范围见 [ADR-0184](../adr/0184-bound-recipient-organization-invitation-preview.md)。

#### 预览不保留加入资格

`0091_organization_directed_account_invitation_preview.sql` 只增加一个 runtime identity bridge。
它按一次墙钟时间和同一查询快照检查身份、邀请、组织和当前成员关系，不加写锁、不写 claim、成员关系或审计。
错误收件人、已过期、已接受、去关联、恢复期或已经入组等不可见状态都返回同一个 forbidden，不透露邀请是否存在。
函数名 `preview_organization_directed_invitation_for_identity_v1` 省略 `account`，防止 PostgreSQL 的 63-byte 标识符上限截掉版本后缀。

Backend 仅开放 `GET /v1/organization-directed-account-invitations/:invitationId`。认证先于请求形状与 store 检查，拒绝 query 和非空 body。
成功 JSON 只有 preview contract ID、invitation ID、组织原名称和 UTC 毫秒有效期；不附带收件人、邀者、workspace 或权限，响应使用 `no-store`。
点击确认时仍由既有接受函数重新授权。预览之后邀请可能过期、组织可能进入恢复期，所以不能把预览成功当作加入成功。
加入只建立组织成员关系，不自动加入项目或取得 capability；既有离线敏感缓存锁不解除。

#### 接受结果不确定时为什么不重新预览

网络中断时，第一次接受可能已经提交。此时预览会拒绝已接受邀请，但相同 invitation ID 的接受仍可返回原回执。
因此同一窗口的重试直接调用 accept，不再要求 preview 成功；不自动重试，也不建立新的 UUID。
用户修改编号会清除旧预览；关闭不确定结果要再次确认，并提示重开“我的组织”核对。请求意图不跨重启保存。
回执是历史操作证据，父窗口在线重读当前目录，不凭旧回执添加组织，不切换当前项目。

账号失效时，`AppSession` 先发布非 ready 状态，再等待旧缓存删除，防止慢存储延长旧账号内容的可见时间。
每次异步操作按会话代次复核；旧清除完成不能覆盖新登录。网关在 token 等待、HTTP 和一次 401 刷新期间也绑定同一次登录。
界面不读取凭据，预览、编号和回执只保留在窗口内存；不写日志、Drift、Outbox 或偏好，不自动写剪贴板。

```bash
flutter test --no-pub test/organization_directed_account_invitation \
  test/features/organization_directory test/app test/app_session
npm --prefix backend/server run check
npm --prefix backend/server test
tool/run_postgres_tests_in_docker.sh
flutter test --no-pub
dart analyze
dart format --output=none --set-exit-if-changed lib test integration_test test_driver tool
dart run tool/check_production_boundary.dart
dart run tool/check_markdown_links.dart
```

Docker 使用隔离的 synthetic 数据库，执行 migration、结构／回滚 fixture、既有并发与 runtime adapter、checksum 和 dump／restore；恢复库不重跑提交型并发脚本。
Widget 覆盖中英文、320×568／200% 字号、暗色宽屏、键盘／焦点、live region 和 48 dp 操作目标。这些证据不证明生产身份、部署端点、真实组织或 Apple／真机行为。

### 3.19 组织写入请求不能借用新登录（Issue #346，MANUAL-067）

用户 A 点了创建组织，请求正在等待 token；这时设备切换到用户 B。如果网关直接使用后来取得的 B token，服务端看到的是 B 的合法请求，却无法知道这其实来自 A 的旧操作。
所以“服务端按 token 验权”和“客户端请求仍属于发起时的登录”是两层不同的保护。UI 在切号后隐藏结果，只解决显示问题，不能阻止网关继续提交。

7AB 复用 invitation 网关已有的检查方式，修复 organization creation 和 owner transfer，不建立新的通用网络层。
每次有效调用保存起始 subject，监听整个操作期间的 identity changes，并在 token、HTTP 和一次 401 刷新后重新核对。
即使最终又登录同一账号，中间的注销也使旧请求失效；正常同一登录内的 token 更新仍可继续。
stream 失败或结束、current 状态改变、close 和迟到异常都不能交付旧成功；失效沿用各模块的 `unauthorized`，不返回 token 或账号资料。

creation 的 close 现在只关闭 client 一次；owner transfer 保留原幂等 close。两者均不关闭共享 identity。
本次请求的监听在交付前停止，但不等待其异步清理；最后身份检查后没有额外清理等待窗口。清理失败不会向调用方抛出原始异常。
close 发生在 token 等待期间时，HTTP 不再发出；发生在 HTTP 之后时，迟到结果被丢弃。不能把这描述为撤销已经发送或已经提交的服务端写入。
已有 request UUID、body、单次合法 401 重试、输入校验和 failure enum 不变；身份失效优先于迟到的网络或解析错误。此优先级已显式补入 [ADR-0179](../adr/0179-organization-owner-transfer-flutter-gateway-contract.md)。owner transfer 本次仍没有新增操作页面。

```bash
flutter test --no-pub test/organization_creation test/organization_owner_transfer \
  test/features/organization_creation test/app
flutter test --no-pub
dart analyze
dart format --output=none --set-exit-if-changed lib test integration_test test_driver tool
dart run tool/check_production_boundary.dart
dart run tool/check_markdown_links.dart
```

可控 Future 先复现跨号 token、401 刷新、迟到成功和 close，再验证修复；既有正常请求、parser 和 App 生命周期测试继续通过。
本切片未改 Backend 或 SQL，不重复本地数据库实验。synthetic identity／HTTP 与 CI build 不证明生产身份、真实账号切换、平台网络取消或数据库回滚。

### 3.20 监听清理不能重新打开交付窗口（Issue #348，MANUAL-068）

`subscription.cancel()` 会停止后续事件，但返回的 Future 可能还在等待资源清理。如果先选定 success，再等待这个 Future，等待期间就没有监听可以记录注销／重登；清理报错也可能直接覆盖原来的 typed result。

7AC 将 3.19 节的修复用于 invitation 的 create／preview／accept 共用请求方法，以及 membership self-leave。
操作先在监听有效时完成 token、HTTP、单次 401 和解析，再同步发起取消，最后检查原登录和 gateway 是否仍有效；最后检查之后没有 await。
清理 Future 可以稍后完成，但不阻塞结果，其异步错误不外泄。同步清理异常被稳定错误类型吸收；已知身份失效优先返回 `unauthorized`，self-leave 的迟到失败也不能带回旧状态。
这不是取消服务端请求，也不是回滚数据库。已经交付后才发生的 close，不会追溯撤回调用方已经收到的回执。

```bash
flutter test --no-pub test/organization_directed_account_invitation \
  test/organization_membership_self_leave
flutter test --no-pub
dart analyze
dart format --output=none --set-exit-if-changed lib test integration_test test_driver tool
dart run tool/check_production_boundary.dart
dart run tool/check_markdown_links.dart
```

回归用可控的取消 Future 验证未完成清理不阻塞交付、清理错误不逸出，以及清理启动时换号或 close 后的最终检查。原有 token／HTTP／401、输入和 strict parser 测试继续执行。
本票未修改 UI、Backend、SQL 或依赖，不重复本地数据库实验；synthetic stream／HTTP 和 CI 仍不证明生产身份、网络取消或真人平台行为。

### 3.21 删除与恢复的接入准备（Issue #350）

[组织生命周期接入清单](../research/organization-lifecycle-readiness.md)按现有 SQL 和领域合同列出后续实施边界，不代表删除／恢复已经实现。
当前 `status`、`deleted_at`、治理锁与 owner invariant 不能组成完整的三十天恢复流程；恢复期应继续允许的报告读取，也不能因冻结写入而一起切断。
清单区分已确认结果、现有入口和待确认授权，后续先补成对的申请／恢复合同，再实现数据库及适配层。本次只检查文档与源码依据，不运行新的数据库实验，也不接受新的产品规则。
账号删除 ADR 中的历史 Firebase 名称已加上当前认证决策的修订指向；这不表示任何认证商的账号删除接口已经交付。

### 3.22 按已知账号编号创建邀请（Issue #351，MANUAL-069）

此入口服务手头已有收件人内部账号 UUID 的组织所有者。账号编号不是邮箱，也不是认证商 subject；本页不查找账号、不列成员。收件人可按 3.23 节复制自己的编号。

1. 打开“我的组织”，在目标组织行选择“创建邀请”。组织目录只证明当前成员关系，不能证明当前 owner 权限；服务端会重新检查。
2. 核对固定的组织，填写收件人内部账号 UUID，再提交。非法格式不发请求；首次有效提交才生成 invitation UUID。
3. 若结果不确定，只在当前窗口重试同一组组织、target 和 invitation UUID。即使下一次收到 403，也不能据此断言之前没有创建成功。关闭前须明确放弃本页重试信息；放弃不是撤销邀请。
4. 成功后核对服务端回执中的 invitation UUID 与 UTC 签发／过期时间。点击复制只复制 invitation UUID；复制失败重试不会再次创建邀请。
5. 把邀请编号手工交给指定收件人。App 没有自动发邮件或通知；只有绑定收件人可在线预览并接受，创建回执本身不保证当前可接受。

请求、回执和输入仅保存在窗口内存。会话失效、换号、同账号注销重登或离开窗口都会清除它们并丢弃迟到结果；页面不关闭共享服务、不切换当前项目、不产生项目权限。
复制由用户触发，且触发前检查原会话。已经写入系统剪贴板的内容不随本页销毁而自动删除，也不会在以后登录时被本页读取。
状态提示、放弃确认和回执沿用现有 Material 3 对话框，支持滚动、小屏大字号、键盘关闭和 live region。保持 owner、组织成员与邀请收件人的含义分离，不把统一 forbidden 改成账号枚举提示。
状态变化后，等待新布局完成再把提示滚回可见区域；同步滚动可能被新布局的滚动锚定抵消。该回调核对页面与请求代次，离开页面或开始新请求后不执行旧滚动。

相关验证：

```sh
flutter test test/features/organization_directory/organization_invitation_create_dialog_test.dart test/features/organization_directory/organization_directory_dialog_test.dart test/features/organization_directory/organization_invitation_accept_dialog_test.dart
flutter test
dart analyze
dart format --output=none --set-exit-if-changed lib test tool integration_test test_driver
dart run tool/check_production_boundary.dart
dart run tool/check_markdown_links.dart
```

本票复用原 HTTP／SQL 合同，没有新增本地数据库实验。Widget、synthetic Clipboard 与渲染结果不能代替生产身份、真人投递或六平台真实运行证据。

### 3.23 查看并复制本人的内部账号编号（Issue #354，MANUAL-070）

“我的组织”直接使用当前 ready `AppSession` 的 trusted context。该 context 已从 Backend 响应中校验 `app_user_id` 为 UUID，因此页面不需要新请求、缓存或身份推导。

页面把“本人账号编号”放在组织列表之前。即使列表为空或加载失败，用户仍可查看和选择完整编号。复制按钮只写入该编号，不读取剪贴板。写入成功或失败都会更新 live region；失败后可以再次选择复制，不会发送邀请或网络请求。

编号有三种不同用途：

- 本人账号编号标识当前 App 账号，可交给邀请者作为 target selector；
- 组织编号标识目标组织，由组织目录返回；
- invitation 编号标识一份七天有效的定向邀请，由邀请者交给绑定收件人。

本人账号编号不证明 owner、membership 或 capability，也不能读取其他账号。登录失效、换号或同账号注销重登会使原目录失效，并立即隐藏旧编号和复制操作。已经写入系统剪贴板的内容无法由页面追溯删除。

相关验证：

```sh
flutter test test/features/organization_directory/organization_directory_dialog_test.dart test/features/organization_directory/organization_invitation_create_dialog_test.dart
flutter test
dart analyze
dart format --output=none --set-exit-if-changed lib test tool integration_test test_driver
dart run tool/check_production_boundary.dart
dart run tool/check_markdown_links.dart
```

Widget 测试可以验证显示、会话隔离、平台通道调用和错误提示。它不证明真实设备剪贴板、生产身份、部署或实际邀请投递。

### 3.24 可分享加入链接与 owner 审批（Issue #356，MANUAL-071，spec-only）

7AG 固定“可分享 link → authenticated application → current owner approval”的合同，但不实现操作入口。它与定向邀请不同：链接不绑定收件人，持有者只能看到最小预览并提交待审批申请，不能直接入组。

当前没有组织级成员管理 capability。首版因此只允许组织的 current active owner 创建 link 和批准 application。组织目录、项目管理员和报告 capability 都不能替代 owner 授权。申请人必须是 active exact identity，且首次提交时尚非该组织 current member。

#### 后续手工流程怎样保持最小权限

后续实现应按以下顺序让参与者明确发起每项操作：

1. owner 选择一个已知 organization workspace，并为新 link 提供 opaque UUID。数据库在锁后重验 owner；首次成功返回 link、workspace、签发时间和到期时间。
2. owner 把 link 交给申请人。link 从锁后数据库签发时间起连续有效 168 小时，不是成员凭证，也不包含 owner 或成员资料。
3. active 账号用已知 link 在线预览。成功结果只有 preview contract、link、组织原名称和到期时间；预览不写 claim 或 audit，也不保留申请资格。
4. 非 current member 用自己的登录提交 application UUID。数据库从 exact identity 绑定申请人；一个 actor 对同一 link 永久只保留首个 application ID。
5. 申请人把 application ID 手工交给 owner。首版没有 pending list、profile、email、通知或自动投递。
6. 任一 current active owner 用已知 organization 与 application UUID 批准。首次成功原子建立一条 organization membership，并返回 membership ID 与批准时间。

批准不建立 project membership、owner assignment 或 capability，也不切换当前项目。申请人应重新读取“我的组织”确认当前成员快照；历史 approval receipt 不是持续成员资格证明。

#### 两个 168 小时期限与重试

link 和 application 使用两个独立 family：

| 对象 | Claim family | 期限起点 |
| --- | --- | --- |
| Link | `organization-shareable-join-link:v1` | link 在全部锁后取得的数据库签发时间 |
| Application | `organization-shareable-join-application:v1` | application 在全部锁后取得的数据库提交时间 |

两种 expiry 都精确晚 168 小时，不受 session time zone 或 DST 影响。application 提交后不再依赖 link 的到期时间；link 随后到期不会缩短 application 自己的期限。到期时刻及之后的新预览、提交或首次批准统一 forbidden。

link 创建重试必须保留同一 link、creator 和 workspace。精确重放返回原 receipt，不重新要求 creator 仍是 owner。creator 不再 active、已去关联或 live claim 属于另一 creator 时 forbidden；只有同一 active creator 改变 workspace 时 conflict。creator 后来失去 owner、结束 membership 或被去关联，不影响尚有效 link 供其他合格账号使用。

application 提交重试必须保留同一 application、applicant 和 link。精确重放返回原 submission receipt，不重验 link expiry、current membership、approval 或恢复状态。live claim 属于另一 applicant、applicant 不再 active 或已去关联时 forbidden；只有同一 active applicant 改变 link 时 conflict。

同一 applicant／link 更换 application ID 也固定 conflict，不能借新 UUID 生成第二份申请。

审批会先验证调用者是 requested workspace 的 current active owner，再分类 live application 的 workspace。unknown application、workspace mismatch、错误或非 owner actor 全部 forbidden，不能借 application UUID 探查其他组织。

application tombstone 也始终 forbidden，因为只含 family 和 request UUID 的 value-free tombstone 无法绑定 requested workspace。

首次批准还要确认 applicant 仍为 active；底层 membership validator 的原始错误收敛为 shareable-join forbidden。已批准 application 的重放仍先重验调用者当前是 requested workspace 的 active owner。任何当时合格的 owner 都可取得同一 approval receipt。

application claim 不保存原 approver，也不成为后续授权。重放不重建 membership 或 audit，也不依赖 applicant 后来的去关联、账号或 membership 状态。

四种 typed result 彼此独立：

| 操作 | 字段数 | 业务字段 |
| --- | ---: | --- |
| 创建 link | 5 | contract、link、workspace、issued、expires |
| 预览 link | 4 | contract、link、organization name、expires |
| 提交 application | 6 | contract、application、link、workspace、submitted、expires |
| 批准 application | 5 | contract、application、workspace、membership、approved |

提交和批准共用 `organization_shareable_join_application_contract_id = 'organization-shareable-join-application:v1'`。claim 中批准生成的 membership 列是 `approved_organization_membership_id`，批准结果对外列是 `organization_membership_id`。

结果不含 actor、profile、email、owner、capability、replay flag 或自由字段。未来 HTTP UUID 使用 canonical lowercase，时间使用 UTC 毫秒格式；成功和失败均为严格 JSON UTF-8 并带 `Cache-Control: no-store`。

#### 失败、锁和删除边界

数据库只固定四类错误：

| 条件 | SQLSTATE 与固定 message | Backend code |
| --- | --- | --- |
| trusted identity 输入非法 | `22023 invalid organization shareable join identity` | `organization_shareable_join_unavailable` |
| typed request 参数非法 | `22023 invalid organization shareable join request` | `invalid_organization_shareable_join_request` |
| 身份、授权、状态、对象或期限不允许 | `42501 organization shareable join forbidden` | `organization_shareable_join_forbidden` |
| 同身份的幂等 payload 漂移、同 actor／link 换 application 或 create／submit tombstone | `22023 organization shareable join idempotency conflict` | `organization_shareable_join_conflict` |

unknown、expired、current member、错误 actor、非 owner、恢复期或已由其他路径入组都不产生更细错误。create 只把同一 active creator 的 workspace drift 分为 conflict；submit 只把同一 active applicant 的 link drift 和同 applicant／link 换 application ID 分为 conflict。两者的错误 actor 都 forbidden。

approve 的 unknown application、workspace mismatch 和 application tombstone 都 forbidden。这样已知 UUID 不能充当 link、application、账号或组织状态查询。未知 SQLSTATE、message、constraint、result 或 parser 错误统一 unavailable，不返回数据库原文。

三条首次写入锁序固定为：

```text
create:  link request → creator user → governance → creator membership
submit:  link request → application request → applicant user → governance → applicant membership
approve: application request → approver/applicant users（UUID 排序）→ governance → applicant membership
```

每条路径在全部锁后重读 claim、tombstone、账号、workspace、membership 和 owner，再取一次 `clock_timestamp()` 判断资格和 expiry。submit 始终先取 link family lock；approve 使用独立 application 事实，不反向取得 link lock。批准的 membership、application approval、audit 和 receipt 在一个 transaction 中使用同一时间，失败全部回滚。

只读精确重放也有固定的缩减锁序：

```text
create replay:   link request → creator user
submit replay:   link request → application request → applicant user
approved replay: application request → current approver user → requested organization governance
```

每条重放在取得全部列出的锁后重读资格与 claim。approved replay 在 governance lock 后重验 current owner，不锁 applicant 或 membership。这两个对象后来可能已去关联或结束，不能阻止历史重放。重放不能先取 governance 再取 user row，也不能省略 governance 而留下 owner TOCTOU。

audit 只保存固定 contract、event kind、link／application／workspace、可选 membership 和数据库时间。它不保存 creator、applicant、approver、组织名称、profile、email、external identity、token、请求原文、SQL、数据库错误或自由文本。`PUBLIC` 不得执行四个 `app_data` 函数或三个 private writer，也不得直接写关系。runtime 只有四个 `app_data` 函数的最小 `EXECUTE`，不能访问 `app_private`。preview 由它的 `app_data` 函数直接执行只读查询，不增加 private preview。

组织恢复期冻结预览和首次 create／submit／approve，只允许符合各自身份或 owner 条件的只读精确重放。这些重放沿用上述缩减锁序和锁后重读。终结清除在既有 creation、directed invitation、owner transfer 和 membership self-leave 后，依次锁 shareable link 与 join application family；每个 family 内按 UUID 排序。清除先写只含 family／request UUID 的 tombstone，再删 claim、audit 和组织业务数据。

账号终结删除按同一全局 family 顺序锁定受影响 request，再去关联 link creator 和 application applicant。creator 去关联不撤销 link；pending application 的 applicant 去关联后不能批准。7AG 不实现账号或组织删除、恢复和 purge writer，完整合同见 [ADR-0185](../adr/0185-organization-shareable-join-application-contract.md)。

#### 文档验证与证据范围

```bash
node /Users/xavieredith/.codex/skills/no-slop/slop-lint.mjs \
   docs/adr/0185-organization-shareable-join-application-contract.md \
  docs/manual/04-identity-and-current-context.md
dart run tool/check_markdown_links.dart
git diff --check
```

这些检查只证明 Product Spec、ADR 和学习文档的合同一致。它们不证明 migration、数据库原子性、并发锁、Backend、HTTP、Flutter、deep link、生产 identity、部署、Apple 或真人平台行为。

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
