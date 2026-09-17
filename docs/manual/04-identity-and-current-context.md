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

### 3.25 在 PostgreSQL 创建和预览可分享 link（Issue #358，MANUAL-072）

7AH／0092 只实现 3.24 的 link 子集。当前 owner 可以在数据库签发 link，任一 active exact identity 可以按已知 link UUID 读取最小预览。link 不建立 membership；0093 实现 application submit，0094 实现 owner approval。

0092 提供三个 SQL seam：

- `app_private.create_organization_shareable_join_link_v1(uuid, uuid, uuid)` 接收 trusted actor、link 和 organization workspace；
- `app_data.create_organization_shareable_join_link_for_identity_v1(text, text, uuid, uuid)` 把 exact active identity 映射到 private writer；
- `app_data.preview_organization_shareable_join_link_for_identity_v1(text, text, uuid)` 直接执行只读预览。

private schema 保存 link claim、value-free tombstone 和 append-only audit。claim 只有 link、workspace、可去关联 creator、issued 与 expiry；它不保存组织名称、external identity、token、owner 或成员资料。runtime 只能执行两个 `app_data` bridge，不能执行 private writer 或直接访问关系。

首次 create 依次取得 link request、creator user、governance 和 creator membership 锁。全部锁后重读 owner、账号、workspace recovery、membership、claim 与 tombstone，再读取一次 `clock_timestamp()`。claim、audit 和五字段 receipt 使用同一个 issued time，expiry 精确晚 168 小时。

同一 active creator、link 和 workspace 是精确重放，只返回原 receipt。它不重验 creator 后来的 owner 或 membership；creator 不 active、引用已去关联或 live claim 属于另一 creator 时 forbidden，同一 creator 改 workspace 或命中 tombstone 时 conflict。creator 去关联不撤销 link，其他 active 账号仍可在期限内预览。

preview 返回 contract、link、组织原名称和 expiry 四个字段。它在一次墙钟和同一查询快照内排除 unknown、expired、personal workspace、recovery workspace 和非 active identity。preview 不写 claim／audit，不取 advisory 或 row lock，也不能证明调用者随后有申请资格。

从仓库根目录运行完整验证：

```bash
./tool/run_postgres_tests_in_docker.sh
dart run tool/check_markdown_links.dart
git diff --check
```

完整 PostgreSQL runner 自动发现 0092 migration、结构检查、rollback fixture 和独立并发脚本，并验证 checksum 与 dump／restore。fixture 使用 synthetic 数据且回滚；并发脚本使用另一组 synthetic UUID 并提交到一次性容器。本地通过不证明 application／approval、Backend、HTTP、生产 identity、部署、客户端分享、Apple 或真人平台。

### 3.26 在 PostgreSQL 提交可分享加入申请（Issue #360，MANUAL-073）

7AI／0093 只实现 3.24 的 application submit 子集。active exact identity 持有已知、未过期 link UUID 时，可以提交一份独立有效 168 小时的申请；提交不建立 membership，也不代表 owner 已批准。

0093 提供两个 SQL seam：

- `app_private.submit_organization_shareable_join_application_v1(uuid, uuid, uuid)` 接收 trusted applicant、application 和 link；
- `app_data.submit_organization_shareable_join_application_for_identity_v1(text, text, uuid, uuid)` 把 exact active identity 映射到 private writer。

private schema 保存 approval-ready application claim、value-free tombstone 和 append-only audit。
claim 只含 application、link、workspace 和可去关联 applicant。它还保存 submitted、expiry 与成对 nullable approval 字段。
claim 不保存组织名称、external identity、profile、email、token 或 approver。0093 本身只授予 runtime submit bridge 的 `EXECUTE`。
0094 另授予 approval bridge 的 `EXECUTE`；runtime 仍不能执行 private writer 或读写三张关系。

首次 submit 依次取得 link request、application request、applicant user、governance 和 applicant membership 锁。全部锁后重读并物化 application、link、账号、workspace 和 membership 事实，再读取一次 `clock_timestamp()`。claim、submitted audit 和六字段 receipt 使用同一个 submitted time，application expiry 精确晚 168 小时。

同一 active、未去关联 applicant、application 和 link 是精确重放，只返回原 receipt。重放不重验 link 或 application expiry、recovery、current membership 或 approval。首次提交才拒绝 unknown／expired link、personal／recovery workspace 和 current member；link creator 后来的 owner、membership、active 或去关联状态不参与申请资格。

application tombstone、同 applicant／link 已保留另一 application ID、同 applicant/application 改 link 都返回 conflict。错误 applicant 或已去关联引用返回 forbidden。历史分类先于首次资格，所以后来的 link 过期、recovery 或入组不会把 alternate application ID 的 conflict 改成 forbidden。

从仓库根目录运行完整验证：

```bash
./tool/run_postgres_tests_in_docker.sh
dart run tool/check_markdown_links.dart
git diff --check
```

完整 runner 自动发现 0093 migration、结构检查、rollback fixture 和独立并发脚本，并验证 checksum 与 dump／restore。fixture 与并发脚本都只使用 synthetic 数据。本地通过不证明 0094 approval、Backend、HTTP、生产 identity、部署、Apple 或真人平台。

### 3.27 在 PostgreSQL 批准可分享加入申请（Issue #362，MANUAL-074）

7AJ／0094 只实现 3.24 的 owner approval 子集。当前 active owner 可以批准一份未过期的 pending application，使申请人成为普通 organization member。批准不授予 owner、project membership 或 capability。

0094 提供两个 SQL seam：

- `app_private.approve_organization_shareable_join_application_v1(uuid, uuid, uuid)` 接收 trusted actor、application 和 requested organization workspace；
- `app_data.approve_organization_shareable_join_application_for_identity_v1(text, text, uuid, uuid)` 把 exact active identity 映射到 private writer。

两个函数都返回 contract、application、workspace、organization membership 和 approved time。0094 不增加表、字段、trigger 或角色，复用 0093 的 approval-ready claim、guard 与 audit。runtime 只能执行 identity bridge。

函数在所有历史分类前确认 actor 是 requested organization 的 current active owner。首次 approval 依次锁 application request、按 UUID 排序去重的 approver／applicant user、requested governance 和 exact applicant membership。全部锁后重读并物化 application、账号、workspace、owner 和 membership 事实，再读取一次 `clock_timestamp()`。

首次成功原子建立一条普通 organization membership，以同一时间推进 claim、追加 `application_approved` audit 并返回五字段 receipt。pending application 必须未过期，workspace 必须不是 recovery，applicant 必须仍 active、未去关联且不是 current member。约束拒绝 future-overlap membership 时，外部仍只收到稳定 forbidden，事务不保留部分写入。

已批准精确重放只锁 application request、approver user 和 requested governance。它仍要求调用者是 requested organization 的 current active owner，但不重验 recovery、applicant 后来的状态或去关联、membership 是否结束或 application expiry。任何当前合格 owner 都能取得同一历史 receipt。

unknown application、tombstone、workspace drift 和错误或失效 owner 都返回 forbidden。approval 没有 conflict 结果，也不透露 application 是否属于另一 organization。

从仓库根目录运行完整验证：

```bash
./tool/run_postgres_tests_in_docker.sh
dart run tool/check_markdown_links.dart
git diff --check
```

完整 runner 自动发现 0094 migration、结构检查、rollback fixture 和独立并发脚本，并验证 checksum 与 dump／restore。fixture 与并发脚本都只使用 synthetic 数据。本地通过不证明 Backend、HTTP、生产 identity、部署、Apple 或真人平台。

### 3.28 通过 Backend 创建和预览可分享 link（Issue #364，MANUAL-075）

7AK 只把 0092 已有的 link create 与 preview bridge 接到 Backend：

- `POST /v1/organizations/:organizationWorkspaceId/shareable-join-links` 只接受 `{ "link_id": "uuid" }`；
- `GET /v1/organization-shareable-join-links/:linkId` 不接受 query 或 declared body。

两条 route 首次执行和精确重放都返回 `200`。create receipt 只含 contract、link、organization workspace、issued time 和 expiry；preview receipt 只含 preview contract、link、组织原名称和 expiry。UUID 规范为小写，时间规范为 UTC 毫秒。所有成功和失败响应使用 JSON UTF-8 与 `Cache-Control: no-store`。

Backend 在 URL 归一化前匹配 raw pathname 和 method。错误 method、percent encoding、dot segment、重复或尾随 slash 直接返回 `404 not_found`。此时不验证 token、不读 body、不访问 store。

命中 route 后才按 Bearer、通用 exact identity、query／body declaration、path UUID、store 和 create body 的顺序处理。

create body 必须只有 `link_id`；空或非法 JSON 返回 `invalid_json`，超过共享 1 MiB 实际字节上限返回 `payload_too_large`。非法 selector 或 body 返回 `invalid_organization_shareable_join_request`。数据库 stable forbidden／conflict 分别映射为 `403`／`409`；invalid trusted identity、store 缺失、未知数据库错误或 row shape 漂移统一 `503 organization_shareable_join_unavailable`。

production composition 复用 generic JWT verifier 与单一 `pool.query`，只注入专用 link store。它不使用组织创建 eligibility verifier、Auth user lookup、`SessionContext` 或 `app_private`。handler 等待参数化 `app_data` bridge query settled 后才写成功响应。

从仓库根目录运行：

```bash
cd backend/server
npm test
npm run check
cd ../..
./tool/run_postgres_tests_in_docker.sh
dart run tool/check_markdown_links.dart
git diff --check
```

route、unit、composition 和 Docker integration 使用 synthetic identity／PostgreSQL fixture。本地通过不证明 application submit／approve、Flutter、deep link、生产 identity、部署、Apple 或真人平台。

### 3.29 通过 Backend 提交和批准可分享加入申请（Issue #366，MANUAL-076）

7AL 把 0093 submit 与 0094 approval 接到同一个 application-family Backend module：

- `POST /v1/organization-shareable-join-links/:linkId/applications` 只接受 `{ "application_id": "uuid" }`；
- `POST /v1/organizations/:organizationWorkspaceId/shareable-join-applications/:applicationId/approve` 只接受 `{}`。

两条 route 都不接受 query，首次执行和精确重放都返回 `200`。
submit receipt 只含 contract、application、link 和 organization workspace。
它还包含 submitted time 与 expiry。
approve receipt 只含 contract、application 与 requested workspace。
它还包含普通 membership 和 approved time，不含 link。

UUID 规范为小写，时间规范为 UTC 毫秒。
submit expiry 与 submitted time 精确相差 168 小时。

Backend 在 URL 归一化前匹配 raw pathname 和 method。错误 method、编码、dot segment 或 slash 形状返回 `404 not_found`。此时不认证、不读 body、不访问 store。命中后先处理 Bearer、generic exact identity、query、path UUID 和 store。之后才运行共享 body reader 和 exact body parser。

共享 body reader 位于 store error catch 外。空或非法 JSON 返回 `400 invalid_json`；实际字节超过 1 MiB 返回 `413 payload_too_large`。额外／缺失字段和非法 selector 返回 `400 invalid_organization_shareable_join_request`。forbidden／conflict 分别返回 `403`／`409`；invalid trusted identity、未知数据库错误、row shape 或 adapter 异常统一返回 `503 organization_shareable_join_unavailable`。

submit store 只调用一次 0093 exact-identity bridge；approve store 只调用一次 0094 bridge。Backend 不预读 application、workspace、owner 或 membership，也不调用 `app_private`。审批是否允许仍只由 0094 owner-first 锁后合同判断；不合格 actor 对 known、unknown 或 cross-workspace application 只能得到同一 forbidden。

从仓库根目录运行：

```bash
cd backend/server
npm test
npm run check
cd ../..
./tool/run_postgres_tests_in_docker.sh
dart run tool/check_markdown_links.dart
git diff --check
```

route、unit、composition 和 Docker integration 使用 synthetic identity 与 0093／0094 fixture。本地通过不证明申请列表、通知、Flutter、deep link、production identity、部署、Apple 或真人平台。

### 3.30 通过 Flutter typed gateway 调用四种可分享加入操作（Issue #368，MANUAL-077）

7AM 使用一个 `OrganizationShareableJoinGateway` 表示四种操作：

- owner 创建 link；
- applicant 预览 link；
- applicant 提交 application；
- owner 批准 application。

四种成功结果各有独立的 immutable receipt。它们不会合并成带 optional 字段的通用 envelope。gateway 只接受调用方提供的 opaque UUID，不生成编号，也不预读 owner、membership、link 或 application。

HTTP 实现调用 7AK／7AL 的固定 route。create、submit 与 approve 使用 JSON POST；preview 使用无 body GET。所有请求发送 JSON accept header，POST 额外发送 JSON UTF-8 content type。输入 UUID 先在本地校验并规范为 lowercase；非法输入不会取得 token 或发起网络请求。

成功和失败响应都必须是 JSON UTF-8 且 `Cache-Control: no-store`。成功结果要求 exact keys、固定 contract、request selector 绑定、lowercase UUID 与 UTC 毫秒。create link 和 submit application 各自验证精确 168 小时，不用设备当前时间重新判定服务端已经签发的历史 receipt。

Backend 的 stable code 映射为 typed failure。空或非法 JSON、过大 body、未认证、非法请求、forbidden、conflict 和 service unavailable 保持分开。未知 status／code、缺失或错误 header、额外字段、非法 UUID／时间、网络响应 shape 漂移都收敛为 invalid response；timeout 和 client network failure 使用 network unavailable。

一个请求只能交付给启动它的连续登录身份。gateway 在 token、HTTP、401 refresh 和最终交付前检查同一个 signed-in subject，并监听中途注销或换号。401 只刷新一次，重试保持完全相同的 URL 与 body。close、换号、同账号注销重登和迟到结果都不能把旧 receipt 交给新会话。

空 `BACKEND_BASE_URL` 返回 deferred gateway，不分配 HTTP client。非空配置必须是 pathless Backend base URI；非法配置同步失败。configured gateway 拥有并关闭自己的 client，但不关闭共享 `IdentitySession`。7AM 本身不把 gateway 接入 `AppDependencies`；首个 UI consumer 出现后的接线见 3.31。

从仓库根目录运行：

```bash
dart format --output=none --set-exit-if-changed \
  lib/organization_shareable_join \
  test/organization_shareable_join
flutter test \
  test/organization_shareable_join/http_organization_shareable_join_gateway_test.dart
flutter test
dart analyze
dart run tool/check_production_boundary.dart
dart run tool/check_markdown_links.dart
git diff --check
```

focused tests 使用 fake identity 和 mock HTTP client。完整 Flutter、analyzer 与六平台 CI build 仍不证明 App composition、Backend、PostgreSQL、production identity、部署、Apple 或真人平台。

### 3.31 从“我的组织”创建可分享加入链接（Issue #370，MANUAL-078）

7AN 提供 3.30 所等待的第一个 UI consumer，并在同一工作单元完成 production composition。用户在“我的组织”选择一个组织，打开“创建加入链接”窗口，明确提交后取得 link UUID。窗口不会读取 owner、成员或 capability，也不会把当前项目权限当成组织权限；Backend 仍按 3.24 的合同确认调用者是该组织的 current active owner。

组织目录中的每个当前成员组织都显示入口，因为目录回执只有组织 UUID 和原名称，没有 owner 角色。服务端返回 forbidden 时，界面只说明当前账号或请求不符合条件，不探查 owner 或组织状态。窗口固定使用被选择的 organization workspace，不切换当前项目，也不刷新组织目录。

首次提交使用 `secureUuidV4` 生成 canonical link UUID。发生 network unavailable、service unavailable、invalid response、conflict 或意外异常时，结果可能已经在服务端提交；窗口因此锁定同一组织和 UUID，只提供原请求重试。用户要停止重试时必须再次确认。其他稳定拒绝不生成新 UUID；再次提交仍使用当前窗口的同一意图。

成功回执显示 link UUID、数据库签发时间和过期时间。历史回执不证明调用者目前仍是 owner，也不保证 link 仍有效。用户必须显式点击复制；复制失败只重试 Clipboard，不重新调用 create。此仓库尚未固定 share URL、App route 或 universal-link 合同，所以 7AN 只复制 opaque UUID，不自行拼 URL，也不引入分享插件。

窗口捕获打开时的 trusted app-user ID，并监听 `AppSession`。账号失效、换号或注销后又登录同一账号，都会永久清除该窗口中的 UUID、回执和复制状态，并忽略迟到的网络或 Clipboard 结果。同一账号切换项目不改变组织级创建意图。

`AppDependencies.production()` 使用 `productionOrganizationShareableJoinGateway`。显式 builder 接收启动时打开的同一个 `IdentitySession`，`AppStartupReady` 和 UI 参数链传递同一个 gateway。缺少 builder 时使用不触网的 deferred gateway。后续启动失败、App 在启动完成前被移除和正常 dispose 三条路径都负责关闭已创建的 gateway；gateway 只关闭自有 HTTP client，不关闭 identity。

从仓库根目录运行：

```bash
flutter test --no-pub \
  test/features/organization_directory/organization_shareable_join_link_create_dialog_test.dart \
  test/features/organization_directory/organization_directory_dialog_test.dart \
  test/app/app_dependencies_test.dart \
  test/app/tongxingzhe_app_test.dart
dart format --output=none --set-exit-if-changed lib test
dart analyze
flutter test --no-pub
dart run tool/check_production_boundary.dart
dart run tool/check_markdown_links.dart
git diff --check
```

Widget tests 使用 fake session、内存 gateway 和 synthetic Clipboard。它们可以证明本地显示、重试、会话隔离和参数接线，不能证明 production identity、Backend 部署、数据库权限、真实剪贴板、Apple universal link 或六平台真人运行。7AN 不增加 link preview、application submit／approve UI、申请列表、通知、Drift、离线缓存、删除恢复或 purge writer。

### 3.32 预览可分享链接并提交入组申请（Issue #372，MANUAL-079）

7AO 复用 3.31 已接入 App 的同一个 `OrganizationShareableJoinGateway` 和 `AppSession`。申请入口位于“我的组织”顶部，与“接受邀请”并列；即使账号尚未加入任何组织也可以打开。入口不依赖当前项目，不读取组织目录来寻找目标，也不增加 router、deep link 或扫码。

用户输入收到的 link UUID。窗口先在本地 trim、lowercase 并验证 canonical UUID，再调用 `previewLink`。成功 preview 只显示组织原名称、link UUID 和数据库到期时间；它不暴露 workspace、owner、成员或 capability，也不是 membership 或当前有效性的持久证明。preview 失败不会写服务端，因此用户可以修改 link 后重新读取。

用户确认 preview 后才调用 `submitApplication`。首次提交使用 `secureUuidV4` 生成一个 canonical application UUID。首次请求发出后，link 与 application UUID 都锁定；后续重试不重新 preview，也不产生新 UUID。network unavailable、service unavailable、invalid response 和意外异常可能隐藏已经提交的结果，因此关闭前必须确认放弃。Backend 返回 conflict 时已经给出稳定拒绝；窗口不把它标成结果不确定，也不改换 UUID。

成功回执显示组织原名称、application UUID、link UUID、organization workspace UUID、数据库提交时间和过期时间。用户必须显式复制 application UUID，并通过可信渠道交给 owner。Clipboard 失败只重试复制，不重新 submit。提交申请不建立 membership，不刷新组织目录，不切换当前项目，也不授予项目权限；owner approval 仍是后续独立动作。

窗口捕获打开时的 trusted app-user ID。账号失效、换号或注销后又登录同一账号，都会永久清除该窗口的输入、preview、application UUID、receipt 和复制状态，并忽略迟到的 preview、submit 或 Clipboard 完成结果。同一账号切换项目不改变组织级申请意图。窗口不关闭共享 gateway。

从仓库根目录运行：

```bash
flutter test --no-pub \
  test/features/organization_directory/organization_shareable_join_application_submit_dialog_test.dart \
  test/features/organization_directory/organization_directory_dialog_test.dart
dart format --output=none --set-exit-if-changed lib test
dart analyze
flutter test --no-pub
dart run tool/check_production_boundary.dart
dart run tool/check_markdown_links.dart
git diff --check
```

Widget tests 使用 fake session、内存 gateway 和 synthetic Clipboard。它们可以证明本地交互、同意图重试、会话隔离和参数接线，不能证明 production identity、Backend 部署、数据库权限、真实剪贴板、Apple universal link 或六平台真人运行。7AO 不增加申请列表、通知、approve／reject／revoke UI、Drift、离线缓存、删除恢复或 purge writer。

### 3.33 在选定组织明确批准入组申请（Issue #374，MANUAL-080）

7AP 消费 3.30 已有的 `approveApplication`，沿用 3.31 组合的同一个 gateway 和 `AppSession`。用户在“我的组织”选择目标组织的“批准入组申请”，输入申请人提供的 application UUID，再进入本地核对页。非法 UUID 不发送请求；大小写和两端空白在本地规范化。

核对页显示选定组织和 application UUID，不读取申请人姓名、账号或 profile。这个编号只是 opaque selector，不能单独确认申请人身份。所有者应通过收到编号的原渠道核对申请人，再明确批准。组织目录只说明当前成员关系，Backend 仍在每次 approve 中确认 current active owner。

首次 approve 发出后，organization 和 application UUID 固定。network unavailable、service unavailable、invalid response 或意外异常可能隐藏已经提交的结果；此时只能在窗口内用原意图重试，关闭须确认放弃重试信息。稳定 typed 拒绝结束不确定状态；不重新生成编号，也不把 forbidden 细分为不存在、过期或申请人已加入。

成功留窗显示 application UUID、organization workspace UUID、organization membership UUID 和 UTC 批准时间。历史 receipt 可以来自精确重放，不证明申请人现在仍是成员。请让申请人重新读取“我的组织”确认当前资格。批准不建立 project membership、owner 或 capability，不切换当前项目、不刷新 owner 目录、不自动复制，也不关闭共享 gateway。

窗口绑定打开时的 trusted app-user ID。账号失效、换号或 ABA 永久清除输入、固定 UUID 和 receipt，并隔离迟到网络结果；同账号切换项目不改变组织级批准意图。

从仓库根目录运行：

```bash
flutter test --no-pub \
  test/features/organization_directory/organization_shareable_join_application_approve_dialog_test.dart \
  test/features/organization_directory/organization_directory_dialog_test.dart
dart analyze
flutter test --no-pub
dart run tool/check_production_boundary.dart
dart run tool/check_markdown_links.dart
git diff --check
```

Widget tests 使用 fake session 和内存 gateway，只证明本地显示、同意图重试、会话隔离和参数接线。它们不证明 production identity、Backend 部署、数据库权限、通知或真人平台运行。7AP 不增加申请列表、profile、reject／revoke、通知、router、平台链接、删除恢复或 purge writer。

### 3.34 将组织所有权交接给已知成员（Issue #375，MANUAL-081）

7AQ 把已有 `OrganizationOwnerTransferGateway` 从 App startup 经 Home、组织目录传到交接窗口。用户从目标组织行打开“转让所有权”，输入同组织的有效成员关系 UUID，再进入本地核对页。只有明确转让才发送请求；无 Backend 配置时仍使用 deferred gateway，不触网。

目标是 organization membership UUID，不是账号、入组申请或 owner assignment UUID。7AP 的批准回执可提供这个编号，但历史回执不保证成员现在仍有效，也不能仅凭编号识别人。用户应通过可信渠道核对接收方；窗口不新增成员搜索、profile 或资格预查。

转让是原子交接，不是增加 co-owner：目标成为 owner，调用者的当前 owner assignment 结束，其他 owner 不变。它不建立 project membership 或 capability，也不切换项目。Backend 在首次执行时确认 current active owner、同组织 active target 和 target-not-owner；“我的组织”仅是成员目录，不是这些权限的证明。

首次提交生成一个 request UUID。请求发出后，request、organization workspace 和 target membership 固定，所有重试都复用它们。网络、服务、无效响应或异常可能隐藏已提交的结果，此时关闭须确认放弃窗口内重试信息；稳定拒绝结束不确定状态，不替换意图。exact replay 只要求原 actor 仍 active，不要求其仍是 current owner，也不重复转让。窗口不根据本地 owner 推断阻挡重试。

成功留窗显示合同、组织、前后 owner assignment UUID 和 UTC 生效时间，并标明已提交的 target membership UUID。receipt 只记录那次交接，不能证明接收方现在仍是 owner。不刷新目录、不复制、不切项目，关闭窗口也不关闭共享 gateway；App 生命周期负责释放它。

窗口绑定打开时的 trusted app-user ID。会话失效、换号或 ABA 清除输入、固定意图和回执并拒绝迟到结果；同账号切项目不改变组织级交接意图。已在线 ready 的正常 token 续期只更新共享会话的身份元数据，不丢弃原意图、不新增 capability 或延长离线 PII 授权期；failed 和 offline 恢复仍须重新读取 Backend 上下文。

从仓库根目录运行：

```bash
flutter test --no-pub \
  test/features/organization_directory/organization_owner_transfer_dialog_test.dart \
  test/features/organization_directory/organization_directory_dialog_test.dart \
  test/app/tongxingzhe_app_test.dart
dart analyze
flutter test --no-pub
dart run tool/check_production_boundary.dart
dart run tool/check_markdown_links.dart
git diff --check
```

Widget 和 App tests 使用 fake identity、内存 gateway 与 synthetic receipt，只证明交互、固定意图、会话隔离和接线。它们不证明 production identity、部署端点、数据库实权、真实辅助技术或真人平台运行。7AQ 不增加成员目录、co-owner grant、恢复或手动改派、通知、router、Drift、离线重试、删除恢复或 purge writer。

### 3.35 保留组织创建请求的防重放墓碑（Issue #377，MANUAL-082）

0084 已交付创建请求的 live claim；0095 补齐 ADR-0175 的 terminal fence，不改写旧 migration。新 private tombstone 只保存 `organization-creation:v1` 和 request UUID，不保存 actor、组织、名称、时间或业务内容。UPDATE／DELETE 被 immutable guard 拒绝，PUBLIC 和 runtime 没有直接访问权。

已有 create writer 先取得 creation request advisory lock，再检查本 family tombstone、live claim 和 actor。命中墓碑返回既有 `22023 organization creation idempotency conflict`，首次创建和 live exact replay 都被拒绝；不同 family 相同 UUID 不影响创建。

替换 writer 保留函数 OID、owner、ACL 和参数，runtime 仍只调用原 exact-identity bridge。名称验证、active actor、原子首位 owner、五字段 receipt、精确重放和审计不变。

从仓库根目录运行完整隔离套件：

```bash
./tool/run_postgres_tests_in_docker.sh
dart run tool/check_markdown_links.dart
git diff --check
```

runner 自动发现 0095 migration、structural check、rollback fixture 和专用并发脚本。并发分别让墓碑事务先持 request lock、让 create 先持锁，再观察另一个会话真实等待；两种提交顺序之后，已保留的墓碑都阻止后续创建或重放。完整套件还检查旧 checksum、Backend 对账和独立恢复库的 check／fixture。

测试只向可丢弃 synthetic 数据库插入模拟墓碑，不删除 live claim、owner history、审计或组织业务行。通过证明防重放边界，不证明组织已实际清除。0095 不提供 deletion／restore／purge eligibility、runner、最小删除审计或 runtime 写入口；实际清除还必须固定完整生命周期、受控 immutable-delete exception 和全部 family 锁序，不能关闭约束或以局部删除冒充。

### 3.36 高字号软键盘下的组织输入窗口（Issue #379，MANUAL-083）

7AS 修复创建组织、创建定向邀请、接受定向邀请和提交分享链接申请四个既有窗口。Android 原生审批复核暴露同类输入裁切后，以 `320×568`、`200%` 字号、底部键盘 `307px` 和顶部安全区 `24px` 检查旧窗口，新增八条回归；修复前其中七条实际失败，中文创建组织原本通过。

固定标题、过长动作和默认留白共同压缩正文 viewport。键盘打开时只缩减外部／正文留白；三个固定标题移入已有正文滚动区，保留 heading、route semantics 和原 headlineSmall。创建组织继续用已有 scrollable AlertDialog。默认 M3 留白在非 IME 场景保持，不缩小字体或触控目标，不添加统一窗口框架。

创建动作复用“创建／Create”，接受邀请与申请的英文 preview 使用“View”。这些是当前字段对象的操作，不表示提交或加入；标题、编号标签、预览、明确确认和风险正文继续区分对象与动作。UUID、fixed request、会话 fence、未知结果退出、历史 receipt、显式复制和共享 gateway 生命周期均未改变。

```bash
flutter test --no-pub \
  test/features/organization_creation/organization_creation_dialog_test.dart \
  test/features/organization_directory/organization_invitation_create_dialog_test.dart \
  test/features/organization_directory/organization_invitation_accept_dialog_test.dart \
  test/features/organization_directory/organization_shareable_join_application_submit_dialog_test.dart
flutter analyze --no-pub
dart format --output=none --set-exit-if-changed lib test tool
```

Widget 检查证明完整输入可滚动露出、viewport 能容纳输入框、动作位于键盘以上，以及最小 48px 触控目标。原生 Android batch 使用 synthetic identity 与内存 gateway，观察中英文键盘输入及代表性预览／确认／回执；截图不能独立证明几何尺寸、真人辅助技术、实际账号或生产权限。

### 3.37 普通项目成员安排，不是管理权限提升（Issue #381，MANUAL-084）

7AT／[ADR-0186](../adr/0186-explicit-ordinary-project-membership-assignment.md) 具体化既有 owner 项目治理职责。组织加入只建立 organization membership；项目须逐一明确安排，新 project membership 默认推广者。项目管理员等更高能力仍须另有明确授予，owner 不因此自动成为项目管理员或看到个人资料。

首次安排的输入只有 request、organization、project 和 target organization-membership UUID。actor 由 exact identity bridge 解析；这些编号只选择对象，不证明 owner、成员或项目现在有效。writer 锁后重验 current active owner、同组织 active target 与 active project，不提供账号或成员搜索。owner 安排自己也须明确操作。

新 project membership 在单一锁后墙钟立即生效，结束点复制 parent bound，可为空，不延长父关系。结束历史不复活，当前或未来重叠区间整体拒绝。结束点原为空只能设置一次；插入时已非空则不能再改，有限 parent 下的 child 没有提前结束能力。完整撤权与改期不是这个合同。

首次写入遵循 request→sorted user rows→governance→sorted organization-membership locks→target project-membership lock→project status fence。最后一把锁复用 0073 的 `management-follow-up-consent-opt-in:<project>` key；仅复用状态串行化资源，不调用配置、不取得 release capability，也不新增 trigger 或 project row lock。

private writer 首先校验 exact READ COMMITTED；否则固定 0A000，未来 transport 统一 unavailable，函数内不改变事务模式。REPEATABLE READ 的旧事务快照不会被 advisory lock 刷新；锁后新 SQL 必须真的取得新快照。归档先提交则安排拒绝，安排先提交则 membership 先建立、项目随后归档。

membership、claim、audit 与 receipt 原子提交并使用同一时间。七字段历史 receipt 包括 contract、workspace、project、target parent、新 project membership、active_from 和可空 inactive_from。它不含 actor、资料、capability 或 replay flag。

精确重放只允许原 active actor 读取相同 request／selectors 的旧结果，不重新要求 current owner，也不恢复访问权。

其他 actor 或 actor 去关联统一 forbidden；同 actor 的 selectors drift 或本 family tombstone 为 conflict。audit 只存最小 opaque lineage 与时间，不存 actor／target user、名称、资料、identity、token、原始请求或数据库消息；value-free 不等于不可反查匿名数据。

恢复期冻结首次安排，只允许合格的只读 historical replay。assignment family 在六个既有治理 family 后追加；具体 deletion、restore、purge eligibility／runner 与受控 DELETE 例外仍另票交付，不关闭 immutable guard。

7AT 当前只交付文档，未实现上述 writer、bridge、数据库竞态或客户端。链接、no-slop、diff 与独立合同审查仅证明材料一致性；后续 DB 需实际验证归档双序等待、隔离模式拒绝零写入、parent／overlap、ACL、checksum 和 dump／restore，不把静态推演当作生产证明。

### 3.38 普通项目成员的数据库安排（Issue #383，MANUAL-085）

7AU 的 0096 migration 实现 [ADR-0186](../adr/0186-explicit-ordinary-project-membership-assignment.md)，不是新角色授予系统。current active owner 明确选择同组织有效 target membership 和 active project；一次成功只追加默认推广者 membership，不写管理 grant、owner、对象分配或 PII 权限。

runtime 只调用 `app_data.assign_organization_project_member_for_identity_v1(text,text,uuid,uuid,uuid,uuid)`。bridge 原值匹配既有 active identity，再调用 private writer；不 bootstrap、修复身份或允许表直读写。两函数均先要求 READ COMMITTED，其他模式固定 0A000，零 advisory lock／业务写入；不能在函数内刷新 REPEATABLE READ 旧快照。

首次写入按 request→sorted actor／target user rows→governance→sorted org hierarchy→target project hierarchy→0073 status fence 取锁。

状态 fence 只是既有串行化资源，不读取配置或授予 release capability。没有 project row lock 或新增状态 trigger；锁后新的 SQL 重读 active project，归档和安排因此有明确先后。

全部锁后只读取一次墙钟，用于资格判断、membership、claim、audit 和 receipt。child end 复制 parent bound，可为空；当前或未来同 user／project overlap 整体拒绝，结束历史不复活。有限结束点插入后不可提前改写，完整撤权仍须另票实现。

七字段 receipt 是原安排的历史结果，含 target parent 和新 membership，但不含 actor、资料或 capability。exact replay 只锁 request 和原 active actor row，不重验后来 owner、target、project 或 recovery。失去 owner 后仍可读自己的历史 receipt，不代表当前项目资格。

tombstone 在同一 request lock 下优先 conflict。claim 不可改绑，只有终结治理可把 actor 非空引用去关联为空；tombstone 与最小 audit 的更新／删除均由 immutable guard 拒绝。value-free UUID 仍可有关联 lineage，不是匿名保证，也未实现 purge 或受控删除例外。

从仓库根目录运行完整套件：

```bash
./tool/run_postgres_tests_in_docker.sh
```

`TEST-095` 包括 structural、rollback fixture 和十二种真实双会话竞态。空项目／历史成员的归档双序覆盖 actor 在 target UUID 前后两种顺序；request replay、其他 actor 和墓碑也检查锁等待。十种先观察精确 advisory key 与 PostgreSQL PID，再允许 holder commit，不以 sleep 推测先后。

parent 结束的两种竞态先经过 0085 target app-user row lock；测试观察精确 transactionid、holder／waiter PID 和 `pg_blocking_pids`。parent 先结束则安排拒绝且零事实；child 先建立则裸 parent 结束被包含约束拒绝，不偷偷结束 child。

局部 structural／fixture／并发通过不等于完整套件通过。完整 runner 另检查旧 checksum、全部 rebuild／fixtures、既有 Backend 对账与独立 dump／restore；恢复库只重跑 check／fixture，不重跑会提交 synthetic 行的并发。源库和恢复库都是合成 Docker，不证明生产身份、HTTP、客户端或真人平台。

### 3.39 普通项目成员的 Backend typed adapter（Issue #385，MANUAL-086）

7AV 只把 0096 identity bridge 的结果变成固定 Backend 类型，不开放 HTTP route。store 每次一条参数化 query，按 issuer、subject、request、organization、project、target parent 传参；identity 不 trim，不另读 owner、资料或 current context。

result parser 要求单行、固定 family 和 exact 七字段，并核对提交的 workspace、project、target parent。其他行数、extra／missing keys、actor／owner 字段、合同漂移或 selectors 不符统一 unavailable，不交付不可信 receipt。

四个 UUID 规范为 lowercase。active time 与非空 parent end 必须是有限 Date 或严格合法日历／时区字符串，规范到 UTC 毫秒；结束必须显式 null 或合法时间，undefined／缺失不是无限结束。

SQL 保留完整精度且验证正区间，node-postgres Date 与 wire receipt 只保留毫秒。例如 `.123456` 到 `.123789` 的正区间可投影为两个 `.123`。adapter 拒绝投影 end 早于 start，但允许相等，不重造微秒资格判断；历史 receipt 从来不是当前访问凭据。

只有 ADR-0186 五组固定 SQLSTATE／message 映射四个稳定 Backend code；未知错误、constraint 或 parser 失败统一本功能 unavailable。typed error 不携带数据库原文、cause、identity、token、SQL 或原始 stack，也不添加日志。

从仓库根目录运行：

```bash
cd backend/server
npm test
cd ../..
./tool/run_postgres_tests_in_docker.sh
```

`TEST-096` 的单元 fake 检查参数、row、时间和脱敏。真实 integration 通过 `ORGANIZATION_PROJECT_MEMBERSHIP_ASSIGNMENT_FIXTURE` 只复用 0096 seed 段，后续隔离事务仍由 SQL fixture 验证；在 rollback transaction 切换 runtime role，对账有限／空 parent first／replay、selectors conflict 和两条 claim／audit。

Docker runner 显式注入 fixture 并运行编译后的 integration，之后继续 checksum／并发／独立 dump／restore。unit 通过不能替代 runtime 对账，合成 Docker 也不证明 production composition、HTTP、生产身份或真人平台。

### 3.40 普通项目成员的 HTTP 接线（Issue #386，MANUAL-087）

7AW 使用 `POST /v1/organizations/:organizationWorkspaceId/projects/:projectId/memberships`。body 只有 `request_id` 和 `target_organization_membership_id` 两个 UUID；组织和项目来自路径。不提交 actor、target user、角色、权限或时间。

server 在 URL 归一化前匹配 raw path／POST，路径别名和错误 method 在认证前 404。命中后按 Bearer、generic identity、query presence、两个 path UUID、store、body 顺序处理；query 包括裸 `?`。无效 path 不读取 body，missing store 也先 unavailable。

共享 reader 按实际字节限制为 1 MiB，等于上限可接受，包括 chunked 请求。空／非法 JSON 400 invalid_json，超过上限 413 payload_too_large；不新增 Content-Type gate，因此缺失或 text/plain 不单独产生 415。exact body 不合格使用本操作 invalid request。

first 与 exact replay 都为 200，响应只含 ADR-0186 七字段，parent end 明确 null 或 UTC 毫秒。不添加 replay flag、当前成员或权限承诺；微秒投影相等与 SQL 完整精度的区别沿用 §3.39。

401 表示未认证，400 表示无效请求，403 表示统一资格拒绝，409 表示固定幂等冲突。verifier／store 缺失、identity／isolation 错误和未知失败为 503。本操作完整 code 见 [Product Spec](../PRODUCT_SPEC.md)；错误不带 SQL、stack、identity 或 provider 原文。所有响应 JSON UTF-8／no-store。

main 将已有 generic verifier 和同一个 pool.query 注入 store；handler 等待单条 bridge statement settled 后才响应。不新增 transaction、连接池、隔离设置、owner checker、Auth lookup 或 SessionContext，避免在 HTTP 层破坏历史 replay。

从仓库根目录运行：

```bash
npm --prefix backend/server run check
npm --prefix backend/server test
```

`TEST-097` 的真实 Node HTTP server 使用 fake verifier／store；Promise gate 使用真实 adapter 与 fake query，composition 检查实际 source 接线。它们不替代 §3.39 的 runtime-role 对账，也不证明生产部署、真实身份、Flutter 或真人平台。

### 3.41 普通项目成员的 Flutter typed gateway（Issue #388，MANUAL-088）

7AX 的 assign API 接受 request、organization、project、target parent 四个 UUID，输出七字段 immutable 历史 receipt 或 typed rejection。本票不接 UI、startup、目录或 Drift；无 owner／资料／current context 预查。

四个输入在取得 token 前验证，可把 uppercase 规范为 lowercase，但不 trim。无效输入不读取身份或网络。HTTP 固定 POST 7AW 路径，body 只有 request_id 和 target_organization_membership_id，不提交 actor、角色、时间或 capability。

receipt 要求 JSON UTF-8／no-store、exact 七字段、固定 family、canonical UUID／UTC 毫秒与 submitted selectors。parent end 必须明确 null 或时间，不把 missing 当无结束。end 早于 start 拒绝；相等毫秒端点可来自合法 SQL 微秒区间，不重判完整精度资格，也不证明当前访问。

401 只强制刷新一次，并重发相同路径、body 与 request。gateway 观察同一次登录的身份流：注销、换号、ABA、流 error／done、close 或迟到结果均不能交付旧意图。正常同账号续 token 不破坏意图；已经发送的请求不承诺撤销数据库事实。

不等待 subscription cancel 返回的 cleanup Future，以免阻塞结果交付。cleanup error 不外泄，交付前再次检查当前身份。该做法沿用既有 owner-transfer gateway，不引入共享状态框架。typed result 不包含 token、provider、SQL、自由文本或 raw error。

HTTP stable code 必须与 status 配对；格式、header、unknown code、receipt 漂移统一 invalidResponse。timeout／network 为 networkUnavailable；unauthorized、forbidden 与 unavailable 不混为一类。deferred gateway 无网络，非法 Backend 配置在创建 client 前失败，close 只结束自己 client，不关闭共享 identity。

从仓库根目录运行：

```bash
flutter test --no-pub test/organization_project_membership_assignment
dart analyze
flutter test --no-pub
```

`TEST-098` 使用 fake IdentitySession／HTTP client，不连接生产或真实账号。focused／完整 Flutter、source review、analyzer、format、边界、links 与 CI 是各自证据，不证明 App 接线、当前成员权、生产部署或真人平台。

### 3.42 在组织窗口明确安排普通项目成员（Issue #390，MANUAL-089）

7AY 在组织目录的每个组织行增加安排入口，固定该组织，只接受已知 project 与 target organization-membership UUID。先本地校验与 review，不调用 gateway；明确“安排”才生成一次 request UUID。它不提供成员搜索、申请列表、角色选择或个人资料，也不把 owner 变成项目管理员。

输入可把 uppercase 规范为 lowercase，不 trim。确认页展示组织、项目和 target parent，并说明只建立默认推广者关系，不授管理／PII 权限、不安排对象、不改变当前项目。已加入组织不等于已加入项目；每个项目都须明确操作。

503、network 或不可信 response 的结果未知，重试固定同一 request 和 selectors。任何已提交意图均不能编辑；稳定失败只结束未知状态，仍可固定重试或直接关闭，不要求放弃确认。编辑只在首次提交前可用；新窗口才开始新的意图。注销、换号、ABA、身份流失效、失去可信 session 或迟到结果不能交付旧意图；同用户正常续 token 和当前项目切换不改写原意图。没有 owner 预查，因此失去 owner 后仍可重试自己的历史结果，首次资格由 SQL 判断。

成功页只展示七字段历史 receipt，UTC 毫秒及显式 null end，不宣称当前成员资格。关闭、Escape 或 back 在未知结果时先说明放弃本地重试，不承诺撤销已提交 SQL。窗口不关闭共享 gateway，关闭后不自动 reload 目录、select project 或修改 AppSession。

AppDependencies 复用同一个 IdentitySession 创建 production gateway，未配置为 deferred。ready、失败与迟到 startup 的三个释放路径都关闭自有 gateway；Home 与 Directory 注入同一实例，不新增缓存、Drift、同步或日志。

从仓库根目录运行：

```bash
flutter test --no-pub test/features/organization_directory
flutter test --no-pub test/app
flutter test --no-pub
dart analyze
dart format --output=none --set-exit-if-changed lib test tool
```

`TEST-099` 覆盖 review／explicit submit、fixed retry、稳定失败、session fences、历史 receipt、未知结果退出、directory entry 和 composition 生命周期。中英文 Android 原生 batch 使用 synthetic identity／gateway，检查 logical `320×568`、`200%` 字号及软键盘下的完整输入、可滚动确认／回执和 48px 动作；不缩字体或增加通用窗口框架。这些 widget／native／CI 证据不证明生产身份、部署、六平台真人辅助技术或当前权限。

另一次临时 Android 测试入口使用实际 typed gateway、Node HTTP 和独立 PID PostgreSQL observer。安排提交后合法转移 owner，再模拟 store 的 post-commit unknown failure，界面显示固定重试。
重试的六个 bridge 参数相同，原 request／membership 回执不变，membership／claim／audit 各一条。新窗口的新 request 被 former-owner gate 稳定 403 拒绝且零 claim。身份／AppSession context 仍为 synthetic fake，不是实际生产 composition 或真实 Auth；诊断入口不进入正式代码。

### 3.43 HTTP 200 之后，另一连接能看到哪些事实（Issue #392，MANUAL-090）

7AZ 把 7AW 的实际 Node HTTP server、真实 PostgreSQL adapter 和 runtime role 接起来，generic verifier 仍为 fake。测试只复用 0096 fixture 的 synthetic seed，提交 setup；业务 bridge 不包显式 transaction，每条 statement 在 query Promise 和 HTTP 200 前提交。

runtime 和 observer 使用两个不同 PostgreSQL PID。有限／空 parent 的首次 HTTP 200 后，observer 逐项对账 membership、claim、audit 的 selectors 与完整 SQL 时间，确认各一条；精确重放返回同一 wire body，计数不增加。wire 毫秒仍不替代 SQL 微秒。

同 request 改 selectors 为 409，overlap 和 non-owner 为 403，均无 claim／audit。raw alias、认证、JSON、extra key、actual-byte 超限和 verifier unavailable 也经过真实 HTTP，且 transport 拒绝不调用业务 query。整个测试只新增两条成员关系，既有 fixture seed 历史保留。

从仓库根目录运行：

```bash
./tool/run_postgres_tests_in_docker.sh
```

runner 显式执行编译后的 `organization-project-membership-assignment-http.integration.js`，随后继续全部 checksum、checks、fixtures、并发和独立 dump／restore。连接释放时销毁带 runtime role 的 client，不删除已提交事实或绕过 immutable guard；临时数据库由 runner 清理。

`TEST-100` 的本地实际 HTTP／Docker 和 CI 证明合成连接间的提交可见性，不证明真实 JWT、生产部署、Flutter、App composition 或真人平台。200 是历史操作结果，不是目标当前权限凭据。

7BD／Issue #400 修复这条 integration 暴露的旧 fixture 边界。0093／0094 曾用全库 before／after 总数判断副作用；并行 file 提交无关组织时，READ COMMITTED 下一条 SQL 看见它，造成假失败。现在用 live temporary views 统计本 fixture 的全部组织、用户、个人空间和动态 parent／project／grant，不降低并行或改事务模式。

同一 application integration 留下四种受控回归：各 fixture 的成功与失败断言前，精确 advisory key、fixture／holder PID 和 blocking PID 证实等待，再合法提交无关 membership／owner／project／capability。旧计数四处 RED，新计数四处 GREEN；原本域零副作用、claim 内容、receipt 和 runtime ACL 检查继续保留。不改生产 writer 或旧 migration。

### 3.44 批准入组与安排项目是两次独立写入（Issue #395，MANUAL-091）

7BA 使用 actual Node HTTP、真实 link／application／assignment adapters、runtime role 和 fake verifier，依次建立分享链接、提交申请、owner 明确批准，再明确安排到项目。每个业务 bridge 都是单 statement 隐式提交，不同 PID 的 observer 只在 HTTP 响应后读已提交事实。

申请人 organization membership 依次为 `0→0→1→1`，project membership 为 `0→0→0→1`。批准 receipt 的 membership UUID 必须等于随后 assignment 的 target parent；只有安排项目那一步建立默认推广者 child，所有步骤都不新增 management capability。

observer 分别对账 link claim／audit、application claim／submitted／approved audit 和 assignment claim／audit。精确重放三次已成功操作不增加记录；non-owner 安排和已安排后的 overlap 为 403，drift 为 409，未知／cross-organization approval 统一拒绝。SQL 时间用数据库文本／等值比较，不拿 node-postgres 毫秒 Date 去等同 SQL 微秒。

从仓库根目录运行：

```bash
./tool/run_postgres_tests_in_docker.sh
```

runner 显式执行 `organization-join-project-assignment-http.integration.js`，不替代既有各 family 的并发、checksum 或恢复检查。每次只提交随机 synthetic setup 和合法业务事实；连接销毁后由 runner 删除专用临时库，不关闭 guard 或 DELETE 已提交行。

`TEST-101` 证明本地跨操作合同，不实现自动项目加入、角色提升、申请列表、通知或新政策。fake verifier、Docker、CI 和 SQL 事实都不是生产身份、部署、Flutter 或真人平台证明。

### 3.45 为什么有效的 finite member 不能接收 owner（Issue #396，MANUAL-092）

active 是“现在处于区间内”，不等于没有结束点。0097 修复当前 0088 transfer writer：首次 target 必须 active 且结束点为 null。0084 新 owner assignment 的结束点固定 null；若 parent 有未来结束点，child 会超出 parent，旧 writer 因包含约束失败并被 Backend 映射成 unavailable，重试也不能完成。

修复只在原锁后 target guard 增加 finite-end 拒绝，返回既有 42501／HTTP 403 forbidden。request、claim、audit 和旧 owner 均不变化。不能把 parent 的未来结束点复制给 owner：那会另行引入 owner 到期、最后所有者失效和 validator 政策，本次不实现。

exact replay 的提前返回位置保持。原 active actor 后来失去 owner，target membership 已结束或账号状态改变，仍可读同一历史五字段回执；这不是当前权限凭据。授权用 0088 的锁后墙钟，immutable handoff 时间仍用原 transaction timestamp；锁序、grant-before-close、bridge 和 ACL 没有改变。

从仓库根目录运行：

```bash
./tool/run_postgres_tests_in_docker.sh
```

`TEST-102` 先以旧 writer 运行新 finite fixture 得到实际 containment failure，再在 0097 后检查 exact forbidden／零写入和 unended 成功。新 fixture 合法提交随机 setup 和两次跨事务 handoff；先保留 successor owner，再结束原 target assignment／parent，最后新事务 exact replay 并回滚临时账号状态，对账 receipt 不变和 owner／claim／audit 无增长。不绕过 guard 或 DELETE。

已有 Backend runtime-role integration 另验证 finite target 为稳定 403 后仍可合法转给 unended target。完整套件继续旧 checksum、全部 checks／fixtures／并发和独立 dump／restore；local synthetic 与 CI 不证明生产身份、部署、未来到期政策或真实删除。

### 3.46 为什么锁后 active 仍可能不能完成 handoff（Issue #402，MANUAL-093）

owner transfer 有两个时间。0088 在全部锁后用墙钟确认当前授权；写入时间仍是请求 transaction 的不可变开始时间。锁等待期间，target parent 可能才开始有效，或 actor 经另一合法 handoff 才成为 owner。它们在授权时 active，不表示能承载较早的 grant／close。

0098 在同一共享 FIRST writer 的锁后、实际写入前增加两项检查：target parent start≤effective time，actor owner start<effective time。
既有 target-already-owner conflict 先返回，不因无须执行的 close 检查改变稳定错误。target 起点相等可以包含新 grant；actor 起点相等会产生零长结束区间，必须拒绝。失败使用既有 42501／HTTP403 forbidden，保持旧 owner、claim 和 audit，不给底层未知错误增加 mapper。

授权仍用当前墙钟；不能改回 transaction time，否则可能接受等待期间已结束的权限。包含、append-only、无结束点 target、锁序、grant-before-close 和 ACL 均保持。exact replay 仍提前返回原历史 receipt，不重做 FIRST 区间资格，也不授予当前访问。

从仓库根目录运行：

```bash
./tool/run_postgres_tests_in_docker.sh
```

`TEST-103` 用 actual runtime role 的 implicit bridge、真实 typed store／handler 与 synthetic verifier。不同 physical PID、精确 request advisory key 和 blocking PID 先证实等待；第一 case 在另一合法 transaction 建立 parent 并提交，第二 case 在等待中合法提交另一次 handoff。数据库明确确认新 start 晚于等待请求的 transaction time，再释放 holder；不依赖固定未来窗口或 sleep 决定先后。

两个旧 writer case 分别触发包含／append-only 错误并映射503；新 guard 为403，scoped owner／claim／audit 完整 snapshot 不变，相同 actor／target／request 的 fresh transaction 控制200。

新边界 fixture 检查相等起点；既有0086 conflict、0097历史 replay fixture 在0098后继续运行。完整 Docker 保留旧 checksum、全部 checks／fixtures／并发和独立 dump／restore；本地 synthetic 和 CI 不证明真实 Auth、生产部署、真人平台或真实删除。

### 3.47 从待审批目录选择记录，再明确批准（Issue #412，MANUAL-094）

7BI 的[目录合同](../adr/0187-organization-shareable-join-application-directory-is-owner-scoped.md)沿用 current-owner 审批边界。用户从“我的组织”的固定组织打开“待审批记录”，读取最早20项并可以显式刷新。目录不是完整队列，也不证明申请人身份；原手工输入 UUID 的批准入口仍保留。

pending 只表示未批准且数据库读取时未过期。申请人可能后来失去账号资格、去关联或通过其他路径入组；这些记录不会被目录暗中删除。link 已过期或 creator 不再是 owner，也不改变已提交 application 的独立期限。选中后仍须通过原渠道核对申请人，进入既有本地确认页，再明确批准。

#### 一次查询怎样避免资格和记录来自不同读取

`list_org_join_applications_for_identity_v1` 在一个 SQL query snapshot 中匹配 exact identity、active user、未删除组织及当前 membership/owner，同时取该组织的 pending claims。materialized observation 只读取一次数据库墙钟。合法 owner 没有记录时返回空数组；不合格 actor 固定 forbidden，不先查询 owner 再独立读取 claims。

读取不写 claim、membership 或 audit，不取新治理锁，不给 runtime 底表权限。它只说明读取快照，不能保留下一次批准资格；0094 继续在原锁后重新授权并原子写入普通组织成员。列表不建立项目成员或管理能力。

返回四项 root：固定 directory contract、组织 UUID、读取 UTC 时间和 applications。每项只有 application/link UUID 与 submitted/expiry。SQL JSON 时间为 UTC 六位小数，HTTP 为三位毫秒；未截断 SQL 仍严格排除到期记录。两个时间截断到同一毫秒不表示 SQL 违反期限，也不保证收到响应时还能批准。

Backend 检查完整微秒的提交时间及真实并列时的 UUID 顺序。Flutter 保留服务器顺序，只检查提交毫秒非递减；同一显示毫秒可能来自不同微秒，不能据此重建 UUID 并列排序。

#### 客户端复用已有资源和审批意图

Backend 的 `listPending` 只执行一条参数化 identity bridge query。GET 不接受 query 或声明 body，命中 raw route 后先认证，所有响应 JSON UTF-8/no-store。Flutter `listPendingApplications` 复用同一个 gateway、一次401刷新与 ABA/close fence；目录只在内存，不进本地缓存或离线队列。

选择记录只预填既有7AP窗口，不自动发送approve。该窗口的固定重试与历史 receipt 不变。目录、子窗口与 App 借用同一gateway，不额外打开identity或关闭共享资源。登录失效、换号或 ABA 清空旧状态；同账号切项目不会改变固定组织。

#### 验证与证据边界

SQL fixture 检查空目录、21项截断、同时间UUID排序、expiry/approved、原pending语义、owner/parent半开区间、读取零副作用与最小ACL。前后业务快照只覆盖本fixture，不采用会被其他runtime提交污染的全库基准；同session反复运行必须清掉自己的TEMP对象。

Backend检查strict root/item、selector、UTC、认证顺序、GET body拒绝和Promise gate；Dart检查一次401、身份/close隔离；Widget检查明确选择、刷新、原审批路径、中英文、小屏高字号和语义。运行正式Backend、Flutter及完整PostgreSQL runner，完整Docker仍包含checksum与独立restore。原生Android复核使用合成身份或临时入口时，不得写成生产JWT、生产入口端到端、部署或六平台真人验收。

### 3.48 读取定向邀请的历史接受回执（Issue #413，MANUAL-095）

7BK 沿用 [ADR-0180 的定向邀请接受合同](../adr/0180-organization-directed-account-invitation-contract.md)。绑定收件人先输入邀请 UUID，在线预览组织与期限，再明确接受。成功后窗口不立即关闭，而显示原合同、邀请 UUID、组织 UUID、组织 membership UUID 与接受 UTC。

这是历史接受记录。精确重放可能返回多年前的原 receipt，成员关系可能已经结束；回执不保证现在仍在组织，不自动加入项目或授予项目能力。不会为显示回执新增成员 reader 或读取账号资料。

关闭、系统 Back 或 Escape 返回同一类型化 receipt，原父目录随后只重新读取一次。“我的组织”以该次读取为准；历史成功和当前空目录可以同时成立。窗口内不自动复制、不切项目、不再预览或重复接受，借用的 AppSession 和 gateway 仍由 App 管理。

unknown 结果仍只能重试原邀请或经过确认停止重试。重试得到 known success 后清除 uncertain，显示历史 receipt。登录失效、换号或快速 ABA 隐藏内容并隔离迟到结果；共享 AppSession 关闭事件流时也清空回执，不能返回旧成功。同账号换项目不改变已捕获的邀请。接受后焦点移到“关闭”，使 Escape 仍可用。

`TEST-105` 覆盖五字段、历史 replay、各关闭路径的父目录重读次数、unknown 解消、会话与迟到结果、中英文320×568/200%字号、IME、语义和48dp操作。运行定向Widget、analyze、production boundary、链接与精确head CI。原生Android使用合成身份时，只证明该设备上的窗口显示与操作，不证明生产JWT、部署或六平台真人验收。

### 3.49 从批准历史回执主动安排已知项目（Issue #415，MANUAL-096）

7BJ 连接既有批准窗口和 [ADR-0186 的普通项目成员安排](../adr/0186-explicit-ordinary-project-membership-assignment.md)。批准收到已知成功回执后，所有者可以选择“安排这个成员的项目”。组织和目标 organization membership UUID 固定为该回执的值，目标只读；用户仍须输入已核对的 project UUID，再核对并单独明确安排。打开窗口和核对不会发送 assign。

历史批准不证明成员现在仍有效，也不保留所有者或项目资格。安排 writer 仍按原锁顺序独立重验，只建立默认推广者项目成员，不授管理 capability 或对象分配。批准和安排使用各自的操作意图；新安排沿用原独立 request、unknown 固定重试和退出确认，不复用申请 UUID 作为 assignment request。原手工输入目标成员／项目的入口保留。

手工批准和待审批目录两条路径都借用原 App-owned assignment gateway 及 AppSession。子窗关闭后保留批准历史回执，焦点返回父窗，不自动重读组织目录、复制、切项目或持久化。登录失效、换号、ABA 或共享会话事件流结束清空父子旧内容，迟到成功和子窗关闭不能恢复旧账号结果；同账号换项目不改变固定组织和目标。窗口不关闭借用资源。

`TEST-106` 覆盖两条接线、固定目标、零自动操作、独立提交与固定重试、原手工入口、关闭／会话边界和中英文小屏／200%／IME／48dp。运行关联Widget、analyze、format、production boundary、文档链接与精确head CI。Android临时合成入口只证明该设备上的显示和操作，不证明生产JWT、生产入口端到端、部署或六平台真人验收。

### 3.50 借用会话事件流结束时退役旧窗口（Issue #417，MANUAL-097）

`AppSession.close()` 先标记关闭并推进 generation，停止身份监听，关闭自己管理的 context gateway，最后结束 `changes` 事件流；它不发送一个新的 invalid snapshot。只监听 onData 的窗口因此可能仍显示旧组织或历史成功回执。7BL 为剩余七个组织窗口补上 onDone，复用各自已有的失效路径，不改变 AppSession、gateway 或业务授权。

覆盖组织创建、我的组织目录、定向邀请创建、分享链接创建、加入申请提交、负责人交接及退出组织。流结束清除旧目录、选择和回执，推进原窗口的 generation；迟到成功不能重新显示旧账号内容，关闭时也不能返回旧成功或让旧父目录重读。邀请接受、批准、待审批目录和项目安排已具有对应处理，本次不重复改动。

会话退役不证明服务器上的操作失败。已有 unknown、固定重试和停止重试确认仍按原规则处理；同账号换项目语义不变。窗口只是借用 AppSession 和 gateway，不替 App 关闭它们。

`TEST-107` 使用真实借用会话 close，而非手工发送 invalid snapshot，验证可见状态、请求中／迟到结果及父目录边界。运行关联Widget、analyze、format、production boundary、链接及精确head CI；临时合成 Android 抽查目录与邀请回执的真实 stream-close。该证据不证明生产身份、部署或六平台真人验收。

### 3.51 真实 App/Home 怎样连接两条批准后安排路径（Issue #422，MANUAL-100）

7BJ 的窗口测试已覆盖手工批准和待审批选择。7BO 再实际挂载 `TongxingzheApp`，从 Home 菜单进入“我的组织”，经过原目录和批准窗口打开项目安排；不以单独挂载子窗口替代 App 接线。两路逐层借用同一 App-owned gateway 与 AppSession。

本地核对和打开子窗都不写入。用户明确批准后才收到历史组织成员回执，再手工输入已核对的项目 UUID、核对并单独明确安排。目标组织和成员固定为原回执，安排生成自己的 UUIDv4 request，不复用 application UUID。子窗关闭保留同一个批准 State 和全部原回执值，不自动读取目录、切 context 或安排项目。

`TEST-110` 记录真实 UI 触发的调用与参数，并验证资源所有权：关闭借用窗口不关闭 gateway，移除 App 才各关闭一次。复用原 fake 的可配置结果，默认仍是 notConfigured；不修改生产行为、业务授权或接口。运行整份 App 测试、analyze、format、production boundary、链接和精确 head CI。这是生产 UI 接线的 synthetic 证据，不证明真实 Auth、RPC、数据库、当前成员资格或真人平台验收。

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
