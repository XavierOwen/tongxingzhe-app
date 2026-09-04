# ADR-0180：组织定向账号邀请与接受合同

- 状态：已接受
- 日期：2026-09-04
- Slice：7O Spec
- Issue：[#320](https://github.com/XavierOwen/tongxingzhe-app/issues/320)
- 依赖：[ADR-0031](./0031-private-organizations-require-invitation-or-approved-request.md)、[ADR-0032](./0032-separate-bound-invitations-from-shareable-join-links.md)、[ADR-0033](./0033-organization-membership-does-not-imply-project-membership.md)、[ADR-0175](./0175-organization-creation-is-atomic-with-first-active-owner.md)、[ADR-0177](./0177-organization-owner-transfer-is-an-atomic-handoff.md)
- Requirement：`ORG-001` 至 `ORG-003`、`ORG-008`、`ORG-013` 至 `ORG-017`、`AUTHZ-001`、`AUTHZ-004`、`AUTHZ-006`、`CODE-005`、`TEST-067`、`MANUAL-057`

## 背景

ADR-0031 和 ADR-0032 已规定私有组织可以使用定向邀请，且定向邀请只能由绑定的接收者在连续 168 小时内接受。它们没有规定现有账号之间的可信身份解析、组织 owner 的创建权限、幂等 claim、接受原子性、锁序、稳定错误、审计或组织删除边界。

直接实现会让数据库、Backend 和 Flutter 对邀请是否已使用、接受者是否仍然有效，以及失败是否留下部分成员事实作出不同解释。本 ADR 只固定已有 active 账号的定向邀请与接受合同。

邮箱邀请、未注册账号、邮件投递、可分享链接、公开申请和审批继续使用各自的决定，不进入本 trust boundary。

## 决定

### 参与者与范围

邀请创建者必须是该组织当前的 active owner。这里的 owner 同时要求当前 owner assignment、有效的 organization membership 和 `app_user.status = 'active'`。本规则只使用 owner 事实，不复用 Slice 7A 的组织创建资格，也不新增或猜测成员管理 capability。

target 是不可信的 opaque internal app-user UUID selector。数据库在锁定后必须重新验证 target 是已存在的 active 账号、不是 inviter，且不是该组织的 current member。target 的 UUID 只用于选择，不表示客户端可以读取账号目录。未知 target selector、未知或非 organization workspace、非 active、已删除或正在删除的账号都统一失败关闭，不返回存在性差异。

target 必须在邀请创建和接受时仍是已有账号。target 如果只有已结束的历史 membership，接受时不得复活历史行，而是追加一条新的 organization membership；已有 active membership 则禁止接受。target 不会因此获得 owner assignment、project membership 或任何 capability。

创建和接受都由 exact `(issuer, subject)` identity bridge 解析当前 actor。bridge 必须按原值匹配，不得 trim、Unicode normalize、bootstrap、修复 identity 或使用 Auth user object。客户端不得提交 actor、email、external identity、Auth object 或 invite token 作为业务事实。

null、空白、issuer 超过 2048 个字符或 subject 超过 512 个字符属于 invalid identity。未知或非 active identity 属于 forbidden。

创建 actor 是 inviter。接受 actor 必须是 claim 绑定的 target；其他 active 账号不能通过提交另一个用户的标识接受邀请。target selector 和 workspace selector 都必须在数据库锁后检查，不能由客户端预查或由 Backend 枚举。

### Invitation claim 与生命周期

每个 invitation 使用独立的 claim family：`organization-directed-account-invitation:v1`。`invitation_id` 是单列 UUID，同时作为 invitation selector、创建幂等键和 request-lock key。组织创建、owner transfer 和 invitation 的 claim、tombstone 与 advisory lock namespace 分开；相同 UUID 可以分别出现在不同 family 中。invitation request lock 的 advisory key 前缀固定为 `organization-directed-account-invitation-request:`。

private 关系名固定为 `app_private.organization_directed_account_invitation_request_claims`、`app_private.organization_directed_account_invitation_request_tombstones` 和 `app_private.organization_directed_account_invitation_audit_events`。

private claim 的字段合同固定为：

- `invitation_id`：不可变的单列 UUID 主键；
- `organization_workspace_id`：目标 organization workspace UUID；
- `inviter_app_user_id`：可在账号终结删除时去关联的内部 inviter UUID；
- `target_app_user_id`：可在账号终结删除时去关联的内部 target UUID；
- `issued_at_utc`：数据库生成的创建时间；
- `expires_at_utc`：由同一数据库时间精确加 168 小时得到的时间；
- `accepted_at_utc`：未接受时为 NULL，接受时只设置一次；
- `accepted_organization_membership_id`：未接受时为 NULL，接受时保存新建 membership UUID。

`expires_at_utc` 必须恰好比 `issued_at_utc` 晚 168 小时，不受数据库 session time zone 或 DST 影响。`organization_workspace_id` 和 `accepted_organization_membership_id` 是由 writer 在治理锁内验证的 opaque references。它们不使用会阻断组织终结清除的 foreign key。`inviter_app_user_id` 和 `target_app_user_id` 只可在既有账号终结删除 governance transaction 中按 `ON DELETE SET NULL` 规则去关联，不得改绑到另一个账号。这个去关联不改变 invitation 的 target 意图，也不产生替代接受者。除这两项去关联和一次 pending-to-accepted 更新外，claim 不可改写。claim 不保存邮箱、姓名、external identity、token 或 provider metadata。

pending 状态由 `accepted_at_utc IS NULL` 且数据库当前时间早于 `expires_at_utc` 推导。两个 acceptance 字段必须同时为空或同时非空。不增加 status history、后台 sweeper 或 revoke 状态。数据库当前时间达到或超过 expiry 时，接受固定失败关闭，不写 claim，不追加 audit。首版没有 revoke 操作；撤销需要另一个决定。

创建首次成功时只写一条 pending claim 和一条创建成功 audit。request lock 下，writer 先检查已有 claim 和本 family tombstone。

相同 `invitation_id`、active inviter identity、workspace 和 target 的精确重放返回原 receipt。它不重复写 claim 或 audit，也不重新检查 inviter 的 owner／membership 或 target membership。inviter identity 不再映射 active 账号或 claim 引用去关联时返回 forbidden。inviter、workspace 或 target 漂移，或本 family tombstone 返回 idempotency conflict。

接受首先判断 claim 是否已经 accepted。已接受 claim 只有仍映射同一 active target 的 exact identity 可以直接返回原 membership receipt。

replay 不重新检查 owner 或 target membership，也不重复写入。target identity 不再映射 active 账号时返回 forbidden。
target 引用已经去关联时返回 forbidden。未接受 claim 必须匹配 target。
锁后再检查 claim、workspace recovery、expiry、target account status 和 current membership。
任一检查失败都不消费 invitation。target 已通过其他路径入组时返回 forbidden，不改变已有 membership。

接受成功只把 `accepted_at_utc` 与新建的 `accepted_organization_membership_id` 从 NULL 写成一次性值，并在同一 transaction 中追加一条接受成功 audit。相同 target 对同一已接受 invitation 的精确重放返回原 membership receipt，不重复建立 membership 或 audit。其他 actor 和已去关联 claim 统一返回 forbidden。claim drift 或 tombstone 使用 idempotency conflict，不泄露 invitation 状态。

### Membership 与原子性

接受 transaction 只使用一次 `transaction_timestamp()`。它必须原子地建立 organization membership、更新 claim 的接受字段和追加成功 audit。任何 identity、权限、状态、恢复期、expiry、membership 或约束失败都回滚全部三类事实，不留下 membership、claim 或 audit 的部分写入。

新 membership 使用既有 organization membership 的 temporal 与 append-only 规则。接受不改写或复活历史 membership，不建立 project membership，不授予 project capability，也不建立 owner assignment。组织级治理能力与项目级访问权继续分离。

### 锁序、恢复与清除

创建和接受的首次路径都遵守以下锁序：

`invitation request lock → 受影响 app-user row locks（按 UUID 排序）→ organization governance lock → organization membership lock`

受影响用户锁只锁定实际参与本次操作的 inviter、target 和已解析 actor，并按唯一 UUID 排序。拿到锁后，writer 必须重新读取 claim、tombstone、账号状态、workspace recovery 状态、target 归属和 current membership。

相同 invitation 的请求由 request lock 串行化。同一组织的不同 invitation 由 governance lock 串行化。任何后续 membership 或账号治理路径不得使用相反顺序。

exact replay 仍先取得 request lock，并在 actor 可解析时锁定对应 user row。它返回原 receipt 前不取得治理或 membership 写锁，也不写入 claim、membership 或 audit。

组织删除恢复期冻结新的 invitation claim 和首次接受。已存在的 claim 只能执行不写入事实的精确重放；已接受 invitation 只能由绑定 target 执行 exact replay。恢复期不结束 owner 或 membership，也不清除 claim 或 audit。

最终清除不在本 ADR 实现。清除先按固定 family 顺序取得 request locks。
每个 family 内按 invitation／request UUID 排序。不得先取得 governance lock 再反向取得 request lock。
family 顺序是 creation、directed invitation、owner transfer。随后按 UUID 排序取得 app-user row locks，再取得 governance lock 和 membership locks。
治理锁后必须重读 recovery 状态和 claim 集合。然后先写仅含 family 与 UUID 的 tombstone，再删除该 family 的 claim、audit 和组织业务数据。

清除不得因 claim 的历史内部引用而阻断，也不得把 invitation UUID 跨 family 视为冲突。

账号终结删除先收集并排序取得所有受影响 invitation request locks，再取得 app-user、governance 和 membership locks。治理锁后必须重读 claim 集合；如果出现未锁定的新 invitation，则回滚并按完整集合重试。随后才可按现有 governance 规则去关联 claim 中的 inviter/target 内部引用。去关联后的 invitation 不能被重新绑定或接受，公开路径统一 forbidden。它的存在、过期和原始 target 不得通过错误、日志或 audit 暴露。具体 deletion、recovery 和 purge writer 不属于本票。

### Receipt、错误与审计

创建 receipt 只含以下五个字段：

```json
{
  "organization_invitation_contract_id": "organization-directed-account-invitation:v1",
  "invitation_id": "uuid",
  "organization_workspace_id": "uuid",
  "issued_at_utc": "UTC ISO-8601 timestamp",
  "expires_at_utc": "UTC ISO-8601 timestamp"
}
```

接受 receipt 只含以下五个字段：

```json
{
  "organization_invitation_contract_id": "organization-directed-account-invitation:v1",
  "invitation_id": "uuid",
  "organization_workspace_id": "uuid",
  "organization_membership_id": "uuid",
  "accepted_at_utc": "UTC ISO-8601 timestamp"
}
```

所有 UUID 使用 canonical lowercase。时间使用 UTC、毫秒精度的 ISO-8601 表示。receipt 不含 target 资料、inviter 资料、owner assignment、capability、replay flag 或自由字段。创建和接受的 receipt 是两个独立的 typed 结果，不能用一个含糊 envelope 合并。

未来 HTTP response 使用精确 `Content-Type: application/json; charset=utf-8` 和 `Cache-Control: no-store`。错误 root 只能是 `{ "error": { "code": "<stable-code>" } }`。具体 route、method 和 transport 顺序由后续 slice 固定。

数据库错误与未来 Backend code 固定为：

| SQLSTATE 与固定 message | Backend code |
| --- | --- |
| `22023 invalid organization invitation identity` | `organization_invitation_unavailable` |
| `22023 invalid organization invitation request` | `invalid_organization_invitation_request` |
| `42501 organization invitation forbidden` | `organization_invitation_forbidden` |
| `22023 organization invitation idempotency conflict` | `organization_invitation_conflict` |

unknown SQLSTATE、message、constraint、parser 或内部异常统一映射为 `organization_invitation_unavailable`。invalid request 只表示请求字段或 UUID shape 不符合合同。

未知 invitation／target selector、未知或非 organization workspace、inactive、deleted、deletion_pending、expired、已接受但非 exact target、已有 current membership、deassociated claim 或 recovery 状态统一使用 forbidden。已识别且引用仍在的 claim actor/workspace/target drift 和 tombstone 使用 idempotency conflict。

错误不得返回数据库原文或用不同错误区分 invitation 是否存在。未来 HTTP route、认证状态、body parser、status、envelope 和 refresh 由后续 slice 固定，不改变本数据库错误 taxonomy。

invitation audit 使用追加式、不可变、value-free allowlist，只允许：

- `organization_invitation_audit_event_id`；
- `organization-directed-account-invitation:v1` contract ID；
- `invitation_id`；
- organization workspace UUID；
- 固定 event kind（`invitation_issued` 或 `invitation_accepted`）；
- 接受成功时的 `accepted_organization_membership_id`，创建事件为 NULL；
- 数据库生成的 UTC `occurred_at_utc`。

每次首次创建只追加一条 `invitation_issued` audit，每次首次接受只追加一条 `invitation_accepted` audit。audit 不保存 inviter 或 target internal user UUID、姓名、display name、email、external issuer/subject、access/refresh/invite token、Auth user/provider metadata、request/body/URL 原文、SQL、数据库 message、stack、target 资料或自由文本。失败操作不追加含邀请状态或身份的 audit。成功精确重放不追加第二条 audit。

### Trust boundary 与 ACL

实现必须提供四个 operation-specific trust seam：

- `app_data.create_organization_directed_account_invitation_for_identity_v1(text, text, uuid, uuid, uuid)`：trusted issuer、trusted subject、invitation、organization workspace、target app user；
- `app_private.create_organization_directed_account_invitation_v1(uuid, uuid, uuid, uuid)`：trusted actor、invitation、organization workspace、target app user；
- `app_data.accept_organization_directed_account_invitation_for_identity_v1(text, text, uuid)`：trusted issuer、trusted subject、invitation；
- `app_private.accept_organization_directed_account_invitation_v1(uuid, uuid)`：trusted actor、invitation。

参数名依次固定为 create bridge 的 `trusted_issuer`、`trusted_subject`、`invitation_id`、`organization_workspace_id`、`target_app_user_id`，create writer 的 `trusted_actor_app_user_id` 加后三个 UUID，accept bridge 的 `trusted_issuer`、`trusted_subject`、`invitation_id`，以及 accept writer 的 `trusted_actor_app_user_id`、`invitation_id`。

两个 create 函数返回 exact row：`organization_invitation_contract_id text`、`invitation_id uuid`、`organization_workspace_id uuid`、`issued_at_utc timestamptz`、`expires_at_utc timestamptz`。两个 accept 函数返回 exact row：`organization_invitation_contract_id text`、`invitation_id uuid`、`organization_workspace_id uuid`、`organization_membership_id uuid`、`accepted_at_utc timestamptz`。bridge 只调用对应的 private writer。private writer 只接收 bridge 解析出的内部 actor 和不可信 selector，并在锁后重验。migration 拆分可以由后续 DB slice 决定，但不得改变这些关系、函数、输入、输出和权限边界。

四个函数均为 `VOLATILE SECURITY DEFINER`，固定 `search_path = pg_catalog`，owner 与现有 `app_private.validate_organization_membership_v1()` 相同且不是 runtime。`PUBLIC` 不得执行任一 bridge 或 private writer。runtime 只获得两个 identity bridge 的 `EXECUTE`，不得执行 private writer，也不得直接写 invitation claim、audit 或 organization membership。普通 app role 不获得这些关系的直接 `INSERT`、`UPDATE`、`DELETE` 或 `TRUNCATE` 权限；既有安全的读取权限不因本 ADR 被扩大或撤销。新实现不以 RLS 代替 trust-boundary、governance lock 或 writer 校验。

## 后果与边界

本 ADR 把定向邀请限制为一个可审计的既有账号到私有组织的单次 membership 建立操作。它保留 ADR-0031 的私有组织边界、ADR-0032 的定向邀请与连续 168 小时有效期、ADR-0033 的 membership／project capability 分离，并沿用 ADR-0175 与 ADR-0177 的 active-owner、claim、governance lock、PII-free audit 和 purge fence 原则。

本 ADR 是 Issue #320 的 spec-only 决定。它不新增 migration、SQL function、Backend route/store、Flutter gateway、controller、UI、通知、邮件供应商、Drift、缓存、离线队列或同步。

它不实现邮箱邀请、未注册账号、分享链接、加入申请、审批、revoke、owner transfer、co-owner grant、member management、项目 capability、配额、反滥用、deletion、recovery 或 purge writer。

后续数据库切片必须继续保持四个 trust seam、claim family、锁序、原子接受、稳定错误、ACL、value-free audit 和 tombstone 边界。后续 HTTP 或 Flutter 切片不得把 email、Auth object、token、target profile 或内部 actor ID加入请求和 receipt。

## 验证

本 ADR 的验证只检查 Product Spec、相关 ADR、学习文档、Markdown links、no-slop 和 diff。它不证明数据库 claim、membership 原子性、并发锁、真实身份、HTTP、邮件投递、生产部署、组织清除、Apple 或真人平台运行时。
