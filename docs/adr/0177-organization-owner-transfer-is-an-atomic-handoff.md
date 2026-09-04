# ADR-0177：组织 owner transfer 是原子交接

- 状态：已接受
- 日期：2026-08-29
- Slice：7G Spec
- Issue：[#304](https://github.com/XavierOwen/tongxingzhe-app/issues/304)
- 关联：ADR-0035、[ADR-0175](./0175-organization-creation-is-atomic-with-first-active-owner.md)、[ADR-0176](./0176-organization-creation-http-contract.md)、[ADR-0178](./0178-organization-owner-transfer-http-contract.md)、Slice 7A、0084、0085、0086
- Requirement：`AUTHZ-001`、`AUTHZ-004`、`AUTHZ-006`、`ORG-003` 至 `ORG-005`、`ORG-008` 至 `ORG-012`、`TEST-064`、`MANUAL-054`

## 背景

ADR-0175 和 0085 已固定 organization owner 的 temporal assignment、active-owner invariant、governance lock 与 grant-before-close 基础。它们没有固定 owner transfer 的 actor 授权、target 选择、幂等 claim、稳定错误或删除边界。Slice 7A 的组织创建 eligibility 也不是 owner transfer 的授权依据。

## 决定

owner transfer 是当前 organization owner 到同组织另一名有效成员的原子 handoff，不是新增 co-owner。

0086 runtime bridge 固定为 `app_data.transfer_organization_owner_for_identity_v1(text, text, uuid, uuid, uuid)`。它依次接收 trusted issuer、trusted subject、request、organization workspace 和 target membership。

bridge 调用 `app_private.transfer_organization_owner_v1(uuid, uuid, uuid, uuid)`。0086 private writer 依次接收 resolved actor、request、workspace 和 target membership。

只有 resolved actor identity 是可信事实。workspace 与 target UUID 是不可信 selector，writer 必须锁后验证。客户端不能提交 actor、email、internal user ID、owner assignment ID 或时间。

### Actor 与 target

身份 bridge 必须使用 trusted `(issuer, subject)` 的原值精确匹配解析 actor。它不得 trim、normalize、bootstrap 或使用 Auth user object。Bearer authentication 或 Slice 7A 的组织创建邮箱 eligibility 都不代表 transfer 授权。首次执行时，actor 必须在锁定后仍是 active app user、该组织的 active membership 和当前 owner。actor 不能通过提交另一个用户的标识代替自身。

bridge 复用 0084 的 identity 输入边界：null、空白、issuer 超过 2048 字符或 subject 超过 512 字符返回 invalid identity；未知或非 active identity 返回 forbidden。两函数都是 `VOLATILE SECURITY DEFINER`，固定 `search_path = pg_catalog`，owner 与 `app_private.validate_organization_membership_v1()` 相同且不是 runtime。`PUBLIC` 不得执行两者；runtime 只有 bridge `EXECUTE`，无 private writer 或 identity、membership、owner、claim、audit 表权限。

target 只接受同组织现有 membership UUID。首次执行锁定后，target membership 必须仍有效，对应 app user 必须为 `active`，且 target 不得已经是当前 owner。target 已是 owner，包括 target 与 actor 相同，返回专用 conflict，不创建 assignment。target 不会因此获得 project membership 或 capability。

### Claim、重放与 drift

`request_id` 使用 transfer 专用 claim 表与 `organization-owner-transfer-request:` advisory-lock 前缀。它是单列主键，不与 actor 组成联合键。creation 与 transfer 的 claim、lock 和 tombstone 都按 family 分开，因此同一 UUID 可以分别用于两种操作。

private claim 只有 `request_id`、可置空且 `ON DELETE SET NULL` 的 `actor_app_user_id`、`organization_workspace_id`、`target_organization_membership_id`、`previous_owner_assignment_id`、`organization_owner_assignment_id` 和有限的 `effective_at_utc`。除 actor 外的 UUID 不设 FK，避免 purge 被历史引用阻断。claim 的 immutable guard 只允许账号终结删除在同一治理 transaction 中将 actor 从非 null 置为 null；其他字段不可变，target membership 不去关联。去关联后，任何 resolved active actor 使用该 request 都冲突。已删除或无法解析的 identity 仍由 bridge 返回 forbidden。

writer 在 request lock 下先读取 live claim 与本 family tombstone。exact request、workspace、actor、target 继续锁定 actor app-user row。它重读 `status = 'active'` 后返回 claim 保存的原五字段 receipt。

exact replay 不重新要求 actor 仍是 current owner，也不因首次成功后 target 已是 owner 而失败。它不追加 assignment 或 audit。它也不依赖 target 后来的 owner、membership 或账号状态。

drift、tombstone 或已去关联 actor 返回 idempotency conflict。只有没有 claim／tombstone 的请求才继续首次 transfer 的 current-owner、target-active 和 target-not-owner 校验。

组织删除恢复期在 governance lock 下冻结新 transfer claim。live exact replay 只读返回既有 receipt。

终结清除按 `(claim_family, request_id)` 排序取得该组织全部 creation 与 transfer request locks。family 顺序固定为 creation 后 transfer。随后按既有顺序取得 app-user、governance 与 membership locks。取得 governance lock 后必须重读 recovery 状态和 claim 集合。集合与已锁定请求不一致时回滚重试。

清除先写只含 `claim_family = 'organization-owner-transfer:v1'` 和 `request_id` 的 tombstone，再按 FK 依赖删除 claim、audit 与组织业务记录。transfer writer 只检查本 family。因此 creation 与 transfer 的相同 UUID 不冲突。

账号 `deletion_pending` 或 `deleted` 的 actor、target 不得开始新 transfer；actor 终结删除按上述唯一例外解除 claim 引用。既有 sole-owner deletion、multi-owner account recovery 和 final account deletion 规则继续适用。

### 锁序与原子 handoff

transfer 使用以下固定顺序：

`request lock → app-user row locks（按 UUID 排序）→ organization governance locks（按 UUID 排序）→ organization-membership locks（按 UUID 排序）`

drift／tombstone 在 request lock 下结束。exact replay 再锁定并重读 actor app-user row 后结束。

首次执行取得其余锁后，writer 必须重读 claim、tombstone、workspace、actor、target membership、app-user status 和当前 owner facts。不同 request 的同组织 transfer 由 governance lock 串行化。同一 request 由 request lock 串行化。

membership end、account deletion 和 organization purge 不得使用相反顺序。

writer 在同一 transaction 中只使用一个数据库 `transaction_timestamp()`。它先追加 target 的 owner assignment，再结束 actor 的当前 assignment。这个语句顺序只保证 transaction 末的 owner invariant，不向外暴露 co-owner 状态。sole owner handoff 结束后必须仍有至少一名 active owner；multi-owner handoff 只结束 actor 的 assignment，其他 owner 保持不变。assignment history 只能追加和合法结束，不能删除或改写。

### Result、错误与审计

private writer 返回一行 exact result，未来 Backend 只序列化以下五个字段：

```json
{
  "owner_transfer_contract_id": "organization-owner-transfer:v1",
  "organization_workspace_id": "uuid",
  "previous_owner_assignment_id": "uuid",
  "organization_owner_assignment_id": "uuid",
  "effective_at_utc": "UTC ISO-8601 timestamp"
}
```

数据库错误和未来 Backend code 固定如下：

| SQLSTATE 与固定 message | Backend code |
| --- | --- |
| `22023 invalid organization owner transfer identity` | `organization_owner_transfer_unavailable` |
| `22023 invalid organization owner transfer request` | `invalid_organization_owner_transfer_request` |
| `42501 organization owner transfer forbidden` | `organization_owner_transfer_forbidden` |
| `22023 organization owner transfer idempotency conflict` | `organization_owner_transfer_conflict` |
| `22023 organization owner transfer target already owner` | `organization_owner_transfer_target_already_owner` |

未知 SQLSTATE、message、constraint、parser、result shape 或 adapter 错误统一返回 `organization_owner_transfer_unavailable`。HTTP route、status 和 envelope 由 [ADR-0178](./0178-organization-owner-transfer-http-contract.md) 与 Issue #309 固定；本 ADR 只禁止客户端提交 actor、email 或 internal user ID。

null request／workspace／target 是 invalid request。未知或非 organization workspace、未知／跨组织／非 active target membership、非 active target account、非 active member／非 current owner actor，以及组织恢复状态，统一返回 forbidden，不区分不存在、跨组织或已失效。只有已验证为同组织 active target 且当前是 owner 时才返回 target-already-owner conflict。

transfer audit 使用追加式、不可变、value-free allowlist。
它只记录 `organization_owner_transfer_audit_event_id`、`owner_transfer_contract_id`、`request_id`、`organization_workspace_id`、`previous_owner_assignment_id`、`organization_owner_assignment_id` 和 `effective_at_utc`。
target membership UUID 只在 private claim 中保存，不进入 audit；new assignment 是 canonical target lineage。
它不得记录姓名、邮箱、external identity、token、provider metadata、SQL、数据库 message、stack 或自由文本。

## 后果与边界

Issue #304 和本 ADR 是 spec-only 决策。Issue #310 已按本 ADR 交付 0086 migration、claim、tombstone、audit、private writer、identity bridge 及对应验证。
本 ADR 不定义 Backend route、production composition、Flutter 或 Drift 实现。HTTP transport 由 [ADR-0178](./0178-organization-owner-transfer-http-contract.md) 单独固定。
0086 的实现必须继续满足 exact identity、锁序、active-owner deferred check、claim replay／drift、稳定错误、ACL、append-only audit 和 recovery／purge fence。

邀请、申请、member management、co-owner grant、owner recovery／manual reassignment、账号或组织 deletion 实现、project membership、capability、配额和反滥用不属于本决定。synthetic PostgreSQL 或 Backend 证据不等同于 production identity、部署端点、真实删除或 Apple 平台证据。

## 验证

本 ADR 的文档验证只检查 Product Spec、ADR、学习文档、Markdown links 和 diff。Issue #310 另行提供 0086 的数据库 writer、并发、runtime ACL、checksum 和 dump／restore 证据；这些证据仍不证明生产身份、部署环境、真实删除或真人平台。
