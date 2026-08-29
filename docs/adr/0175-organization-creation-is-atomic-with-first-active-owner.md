# ADR-0175：组织创建必须原子建立首位有效所有者

- 状态：已接受
- 日期：2026-08-29
- Slice：7B Spec
- Issue：[#280](https://github.com/XavierOwen/tongxingzhe-app/issues/280)
- 关联：ADR-0007、ADR-0010、ADR-0030、ADR-0033、ADR-0035 至 ADR-0037
- Requirement：`CTX-002`、`AUTHZ-001` 至 `AUTHZ-006`、`ORG-003`、`ORG-006` 至 `ORG-008`、`TEST-062`、`MANUAL-052`

## 背景

Slice 7A 只证明一次请求的外部身份满足组织创建资格。现有 `workspaces` 用可空的个人 owner 字段区分个人空间与组织空间，`organization_memberships` 只表达成员有效期。两者都不能表达组织 owner，也不能保证创建者、成员关系和 owner 同时存在。

把 owner 推导为项目 capability 会混淆组织治理和项目数据权限。把 owner 写成 membership 上的可变布尔值，则无法在保留成员关系的同时追加记录所有权授予与结束历史。

## 决定

组织 owner 使用独立、追加式的 temporal assignment 表达。每项 assignment 只引用一个 organization membership，不复制 workspace 归属。assignment 和 membership 都使用 `[active_from_utc, inactive_from_utc)`；起点和非空终点必须是有限 `timestamptz`，终点晚于起点。assignment 必须被 membership 有效期包含，同一 membership 不得有重叠 assignment。授予和结束只使用数据库当前时间，不安排未来所有权。owner 不自动创建 project membership，也不授予管理报告、去身份化异常、PII 或其他项目 capability。

除终结清除外，每个物理存在的 organization workspace 在任意治理 transaction 提交时都必须至少有一位当前 owner。当前 owner 要求 assignment 和 membership 有效，且对应 `app_user.status = 'active'`。DB 实现必须用 `DEFERRABLE INITIALLY DEFERRED` constraint triggers 在 transaction 结束时检查 workspace、membership、owner assignment 和 app user 状态变更。相关表不向 `PUBLIC`、runtime 或普通 app role 开放直接写入。migration 如发现已有组织无可证明的当前 owner，必须失败回滚，不猜测、指定或隔离 owner。

owner assignment 的普通治理只能追加和结束，不能改写其他字段或物理删除。转让必须在同一 transaction 中先建立新 owner，再结束旧 assignment。唯一 owner 的 assignment、membership 或账号不能单独结束。`deletion_pending` 账号不计作当前 owner，因此唯一 owner 的账号删除申请必须在改变账号状态前失败。多 owner 组织中的账号可进入恢复期；其 assignment 保留，在账号恢复 active 后重新生效。
账号终结删除必须在同一 governance transaction 中使用同一时间结束该用户的 active owner assignments 和 memberships，然后才清除账号。
账号在此前已是 `deletion_pending`，creation claim 集合不再增长。删除路径先按 UUID 取全部 claim request locks，再取 user row 和 organization governance locks。

组织删除恢复期不结束 owner 或 membership，也不清除 claim 或 creation audit。唯一 owner 不能在此期间进入账号删除恢复期。期满后，专用清除 transaction 可以物理删除 workspace 和所有组织业务记录；这是 owner 历史追加不可变的明确例外。constraint trigger 在提交时看到 workspace 已不存在，因此不要求为已清除组织保留 owner。最小删除审计除原有字段外，只增加原 request UUID 作为 value-free idempotency tombstone。

身份和写入分为两层。`app_data.create_organization_for_identity_v1(trusted_issuer text, trusted_subject text, requested_request_id uuid, requested_display_name text)` 是 runtime 唯一可执行的 bridge。它对 `issuer + subject` 做原值精确匹配，只接受已存在的 active internal user，不 trim、bootstrap 或修复 identity。它再调用 `app_private.create_organization_v1(trusted_app_user_id uuid, requested_request_id uuid, requested_display_name text)`。HTTP body 只能提供 request ID 和 display name；Backend 使用 Slice 7A 验证结果提供 issuer 和 subject。

bridge 要求 issuer 和 subject 非 null 且 `btrim` 后非空，并把原值 `char_length` 分别限制为 2048 和 512。`btrim` 只用于空白检查，不改变精确映射值。bridge 和 private writer 都是 `VOLATILE SECURITY DEFINER`，固定 `search_path = pg_catalog`，并与现有 private organization membership validator 共用一个非 runtime owner。`PUBLIC` 不得执行两者。runtime 只有 bridge `EXECUTE`，无 `app_private` 或 identity、owner、membership、claim、audit 表权限。

private writer 在一个 PostgreSQL transaction 中只读取一次 `transaction_timestamp()`，并显式写入 organization workspace、创建者 membership、首位 owner assignment、request claim 和 creation audit。任一检查或写入失败都使全部记录回滚。

display name 的 canonical 形式是 PostgreSQL `btrim` 只去掉两端 U+0020 后的原文本。
`char_length` 必须在 1 至 120 之间，且不得含 U+0000 到 U+001F 或 U+007F 到 U+009F。
canonical name 还必须有一个不属于 Unicode `White_Space` 的字符。
它不能只含 U+200B、U+200C、U+200D、U+2060 或 U+FEFF。
canonical name 原样存入 workspace 和 private claim。
服务不做 Unicode normalization、大小写折叠、唯一名称检查或相似名称合并。
组织身份只由不透明 workspace UUID 决定。

request UUID 在组织创建命名空间中是单列唯一键，不与 actor 组成联合键。
private claim 保存 request ID、可置空且 `ON DELETE SET NULL` 的 actor internal ID、canonical name、workspace／membership／owner assignment ID 和单一创建时间。
相同 request、actor 和 canonical name 精确重放返回原结果，不追加第二套事实或第二条成功 audit。
actor 或 canonical name 漂移返回 conflict。claim 的 immutable trigger 只允许账号终结删除将 actor 从非空改为 null，并拒绝其他更改。
此后该 request 对任何 actor 均冲突。组织终结清除先把 request UUID 写入最小删除审计作为 value-free tombstone，再清除 claim。
后续创建在同一 request lock 内检查 live claim 和 tombstone。任何已保留 UUID 均冲突，因此新意图必须使用新 UUID。

创建路径首先取 `hashtextextended('organization-creation-request:' || request_id::text, 0)` transaction advisory lock 并检查 claim 与 tombstone。
它然后用 `FOR UPDATE` 锁定 active actor row。初次请求生成 workspace UUID 后，它取
`hashtextextended('organization-governance:' || workspace_id::text, 0)` transaction advisory lock。
现有 membership 约束最后取 `organization-membership:<workspace>:<user>` lock。
未来带 request UUID 的路径先取 request lock。多用户／多组织治理再按 UUID 排序取 user row locks，
按 UUID 排序取 organization governance locks，然后遵循 organization membership、project membership、capability 的既有顺序。
owner 转让、membership 结束和账号删除不得使用相反顺序。

所有可改变当前 owner 集合的路径都在写入前取得所有受影响 organization governance locks。
这包括 owner 授予或结束、membership 写入或结束、app user 状态变更、账号删除和组织清除。
账号状态路径在 user row lock 后收集受影响组织，按 UUID 取 governance locks，然后重新读取 owner 集合。
deferred trigger 只检查 transaction 末状态，不替代这个并发 fence。

组织终结清除先读取不可变的 creation request UUID，取 request lock，再取 governance lock 和 workspace `FOR UPDATE` row lock。
它在取锁后重新确认 claim 归属和恢复期已结束；claim 缺失或漂移均失败关闭。
它在同一 transaction 中按依赖顺序清除 owner、membership、组织业务数据、claim、creation audit 和 workspace。
所有组织写入路径都在 governance lock 后重新检查 workspace 仍可治理，因此清除与新 owner 或 membership 写入不能交叉提交。

成功数据库结果只是一行：`creation_contract_id = 'organization-creation:v1'`、`organization_workspace_id` UUID、`organization_membership_id` UUID、`organization_owner_assignment_id` UUID 和 `created_at_utc` `timestamptz`。bridge 和 private writer 都返回这一 exact row，不返回 JSONB。未来 HTTP 成功响应只使用同名字段，时间转为 UTC ISO-8601。

数据库错误固定为四组 SQLSTATE 与 message：`22023 invalid organization creation identity`、`22023 invalid organization creation request`、`42501 organization creation forbidden` 和 `22023 organization creation idempotency conflict`。Backend 分别把它们映射为 `503 organization_creation_unavailable`、`400 invalid_organization_creation_request`、`403 organization_creation_forbidden` 和 `409 organization_creation_conflict`。第一组只表示 trusted identity 输入合同失配，不伪装成客户请求错误。`401 unauthenticated` 只来自 Backend JWT／Slice 7A verifier，不由数据库生成。其他 SQLSTATE、message、约束、parser 或未知错误都映射 `503 organization_creation_unavailable`。

未来 HTTP 的成功和失败响应都使用 `Content-Type: application/json; charset=utf-8` 和 `Cache-Control: no-store`。失败 envelope 只能是 `{ "error": { "code": "<stable-code>" } }`。

首次成功只追加一条 creation audit。
其 allowlist 是 event ID、`organization-creation:v1`、request ID、workspace／membership／owner assignment ID 和创建时间，不含直接 actor 引用。
audit、错误响应和结构化日志都不得保存 display name、邮箱、external issuer／subject、token、Auth user object、
provider metadata、自由文本、SQL、数据库消息、堆栈或原始错误。
失败 transaction 不写成功 audit。creation audit 在恢复期内保留，并在组织终结清除时与其他组织业务数据一同清除。

## 后果与边界

7B Spec 不新增 migration、SQL function、Backend store、HTTP route 或 Flutter UI。
后续数据库切片必须新增 owner assignment、request claim、audit、private writer 和 exact-identity bridge。
验证至少包括 structural check、rollback fixture 和并发测试。它还包括 checksum 和 dump／restore。

邀请、申请、owner 转让、成员退出、账号／组织删除、恢复、项目创建、capability bundle、配额和反滥用分别交付。synthetic PostgreSQL 或 Backend 测试不证明 production Supabase、部署端点、真实 PII 清除或真人平台运行时。

## 验证

当前验证只检查 Spec、ADR、学习文档、Markdown 链接和 diff。它不证明数据库原子性、并发锁、owner 不变量、生产身份、部署环境或真人平台。
