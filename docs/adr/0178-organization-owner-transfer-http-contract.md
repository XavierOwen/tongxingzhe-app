# ADR-0178：组织 owner transfer HTTP 合同

- 状态：已接受
- 日期：2026-09-04
- Slice：7J Spec
- Issue：[#309](https://github.com/XavierOwen/tongxingzhe-app/issues/309)
- 关联：[ADR-0176](./0176-organization-creation-http-contract.md)、[ADR-0177](./0177-organization-owner-transfer-is-an-atomic-handoff.md)、0085、0086
- Requirement：`AUTHZ-001`、`AUTHZ-004`、`AUTHZ-006`、`ORG-009` 至 `ORG-012`、`TEST-064`、`TEST-065`、`MANUAL-054`、`MANUAL-055`

## 背景

0086 已实现 ADR-0177 固定的数据库 owner transfer claim、writer、identity bridge、audit 和 active-owner invariant。
公开 HTTP transport 仍需要固定 route、认证顺序、请求边界、store seam、response wire、错误映射和 non-enumeration 规则。
本 ADR 与 ADR-0177 配合，不改变 0086 的数据库合同，也不引入新的 owner eligibility。

## 决定

### Route matching

唯一入口是 `POST /v1/organizations/:organizationWorkspaceId/owner-transfer`。
router 必须在 WHATWG URL normalization 前，从 request-target 取第一个 `?` 之前的 raw pathname。
它只匹配一个未编码的动态 workspace segment。
wrong method、trailing slash、repeated slash、literal 或 percent-encoded dot segment、任何 percent-encoded path segment 和未匹配 path 都返回通用 `404`。
这些请求不认证、不读取 body、不调用 store。
命中单一动态 segment 但 workspace UUID 无效的请求，在认证后返回 `400 invalid_organization_owner_transfer_request`。

### Authentication and processing order

命中 route 后，Backend 严格解析 Bearer credential，并只调用现有 generic `IdentityVerifier`。
verifier 返回 exact `issuer` 和 `subject`，不使用 Slice 7A 的 `OrganizationCreationIdentityVerifier`、Auth user lookup 或组织创建 eligibility。
缺少或无效 token、JWT claim 或 signature 失败返回 `401 unauthenticated`。
缺少 verifier、provider／configuration 错误或未知 verifier exception 返回 `503 organization_owner_transfer_unavailable`。
`IdentityVerificationError.category === "unauthenticated"` 映射 `401`；`category === "unavailable"` 或非 `IdentityVerificationError` 异常映射 `503`。

处理顺序固定为：

1. 解析 Bearer；
2. 调用 generic `IdentityVerifier`；
3. 拒绝 query；
4. 校验 path workspace UUID，并 canonicalize 为 lowercase；
5. 检查 dedicated transfer store；
6. 按实际 bytes 读取并解析 body；
7. 只调用一次 transfer store；
8. 等待 Promise settled；
9. 写出 response。

query（包括空 query）和 path UUID 无效都返回 `400 invalid_organization_owner_transfer_request`。
missing verifier 或 store 必须在读取 body 前返回 `503 organization_owner_transfer_unavailable`。

### Request and store seam

body reader 按实际 byte 数计数，不信任 `Content-Length`，并支持 chunked body。
1,048,576 bytes 可以继续解析，第 1,048,577 byte 返回 `413 payload_too_large`。
请求不增加 `Content-Type` gate。
空 body 或非法 JSON 返回 `400 invalid_json`。

JSON root 必须严格只含 `request_id` 和 `target_organization_membership_id` 两个字段。
两个字段都必须是 UUID 字符串。非 object、缺字段、额外字段、错误类型或无效 UUID 返回 `400 invalid_organization_owner_transfer_request`。
输入 UUID 可以是大小写 RFC 形式，验证后统一使用 lowercase canonical value。
客户端不能提交 actor、workspace、owner assignment、email、name、时间或 capability。

dedicated store 只接收 verified issuer、subject、canonical body request、canonical path workspace 和 canonical body target membership。
它只执行一次参数化的
`app_data.transfer_organization_owner_for_identity_v1(trusted_issuer text, trusted_subject text, requested_request_id uuid, requested_organization_workspace_id uuid, requested_target_organization_membership_id uuid)`。
它不得访问 `app_private`、`SessionContext`、creation store 或客户端 actor。
production composition 复用 generic identity verifier 并注入 dedicated Postgres transfer store，不新增环境变量或组织创建 eligibility。

### Response and errors

首次成功与 exact replay 都返回 `200`。成功 JSON root 只有以下五个字段：

```json
{
  "owner_transfer_contract_id": "organization-owner-transfer:v1",
  "organization_workspace_id": "uuid",
  "previous_owner_assignment_id": "uuid",
  "organization_owner_assignment_id": "uuid",
  "effective_at_utc": "YYYY-MM-DDTHH:mm:ss.SSSZ"
}
```

contract ID 固定。三个 UUID 必须是 lowercase canonical form，workspace 必须等于 canonical path。
Backend 接受数据库 Date 或带 offset／fraction 的 RFC 3339 instant，并输出 `YYYY-MM-DDTHH:mm:ss.SSSZ`。
不得增加 replay flag 或 target／member 资料。

结果映射固定如下：

| 条件 | HTTP 结果 |
| --- | --- |
| wrong method、非法 route、percent-encoded path segment 或未匹配 path | `404 {"error":{"code":"not_found"}}` |
| 缺少或无效 Bearer、JWT claim／signature 失败 | `401 unauthenticated` |
| query、path UUID 或 body shape 无效 | `400 invalid_organization_owner_transfer_request` |
| 空 body 或非法 JSON | `400 invalid_json` |
| body 超过 1,048,576 bytes | `413 payload_too_large` |
| DB forbidden | `403 organization_owner_transfer_forbidden` |
| drift、tombstone 或 deassociated actor | `409 organization_owner_transfer_conflict` |
| target 已是 current owner，包括 actor 等于 target | `409 organization_owner_transfer_target_already_owner` |
| invalid trusted identity、missing verifier／store 或未知错误 | `503 organization_owner_transfer_unavailable` |

未知或非 organization／recovery workspace，以及未知、跨组织、inactive 或 deleted actor／target，只由 0086 DB 收敛为 `403`。
HTTP 不得预先枚举这些状态为 `404`。
只有 DB 已验证同组织 active target 且 target 当前是 owner 时，才返回 target-already-owner conflict。

所有 response 使用精确 `Content-Type: application/json; charset=utf-8` 和 `Cache-Control: no-store`。
error root 精确为 `{"error":{"code":"stable_code"}}`，不得返回数据库原文、成员资料或其他自由字段。
response、结构化日志和失败审计继续遵守 ADR-0177 的 value-free PII allowlist。

replay、drift、tombstone 和 actor deassociation 由 0086 claim family 决定。
exact replay 返回原五字段 receipt，不要求 actor 仍为 current owner，也不因 target 后来成为 owner 而失败。
HTTP 不读取成员资料来决定 404，不在 store 外实现 actor、workspace 或 target 的存在性枚举。

## 后果与边界

本 ADR 是 Issue #309 的 spec-only transport 决策。#312／7K 已按本决策交付 Backend handler、dedicated store、real HTTP route、production composition 和 local synthetic tests。
它不实现 Flutter、Drift、recovery、deletion 或 purge。
它不修改 0086 migration、claim、audit、tombstone、ACL、owner invariant 或锁序，也不增加 request `Content-Type` gate、`Idempotency-Key`、SessionContext、缓存或 durable retry。

#312／7K 的 handler、store、real HTTP 和 composition tests 覆盖 raw route、认证分类、精确处理顺序、actual-byte inclusive 1 MiB／chunked boundary、strict parser 和 UUID canonicalization。
测试还覆盖一次 0086 bridge call、五字段 success／replay、RFC 3339 时间输出、全部 400／401／403／409／413／503 映射、unknown／recovery non-enumeration、JSON／no-store、PII-free response／logs 和 Promise gate。
这些 local synthetic Backend、HTTP 和 PostgreSQL integration 证据不证明 production identity、部署端点、Flutter、删除流程、Apple 或其他真人平台运行时。

邀请、申请、membership／capability 管理、owner recovery、账号或组织 deletion、project capability、配额和反滥用不属于本决定。

## 验证

本 ADR 的文档验证检查 Product Spec、ADR 索引、学习文档、Markdown links、no-slop 和 diff。
Issue #310 的 0086 数据库证据验证 writer、并发、runtime ACL、checksum 和 dump／restore；Issue #312 还验证 Backend unit／HTTP／composition 和通过 runtime bridge 的 PostgreSQL integration。
这些 local synthetic 证据不证明 production identity、部署环境、真实删除、Flutter、Apple 或其他真人平台。
