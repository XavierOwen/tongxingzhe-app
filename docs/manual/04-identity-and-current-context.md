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

组织进入删除恢复期时，governance lock 会冻结新 transfer claim，精确重放仍只读。期满清除按固定 family 和 request UUID 顺序锁定全部 creation／transfer requests。

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

两个值都必须是 UUID 字符串。接受大小写 RFC 形式，验证后统一为 lowercase。
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

### 3.7 Flutter 组织 owner transfer typed gateway（Issue #314，MANUAL-056，spec-only）

Issue #314 只固定 Flutter 业务层的 typed gateway 合同。它复用 Issue #309 的 HTTP transport 和 Issue #312 的 Backend route，不重新定义 0086 的 owner、membership、claim、audit、recovery 或 purge 规则。
本节不实现 Dart gateway、HTTP adapter、AppDependencies、AppStartupReady、UI 或生产接线。

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
输入 UUID 可以使用 RFC 形式的大小写字母。adapter 在取得 token 或发 HTTP 前把三者统一为 lowercase canonical value；非法 UUID 直接返回 `OrganizationOwnerTransferRejected(OrganizationOwnerTransferFailureCode.invalidRequest)`。

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
如果首个 response 恰好是 `401` 且 error code 为 `unauthenticated`，gateway 只强制刷新一次 token，并用完全相同的 canonical URL、body 和参数重试。第二个相同 `401` 返回 `unauthorized`，不得循环刷新。

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
receipt、failure 和原始 response 只存在于内存，不写 Drift、缓存、同步队列或日志。本票不定义 `AppDependencies`、App lifecycle、controller、ViewModel、Screen、导航或成功后的组织上下文切换。

后续实现使用 fake `IdentitySession` 和内存 `MockClient` 运行 focused tests：

```bash
flutter test test/organization_owner_transfer/http_organization_owner_transfer_gateway_test.dart
dart analyze
flutter test
dart run tool/check_markdown_links.dart
```

测试必须覆盖 path、body、headers、UUID canonicalization、非法输入的 no-token/no-request short-circuit、deferred no-network、identity failure、一次 `401` 刷新与相同 retry body、strict receipt／error parser、全部 stable mapping、脱敏、内存结果和可重复 `close()`。

本节是 spec-only。文档、Markdown link、no-slop 和 Dart analyzer 检查只证明文字或静态语法一致，不证明 Dart gateway、HTTP adapter、Backend、PostgreSQL、production identity、部署端点、真实组织、Drift、UI、删除恢复、Apple 或其他真人平台行为。

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
