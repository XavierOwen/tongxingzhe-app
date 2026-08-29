# ADR-0176：组织创建固定 HTTP 合同

- 状态：已接受
- 日期：2026-08-29
- Slice：7E Spec
- Issue：[#298](https://github.com/XavierOwen/tongxingzhe-app/issues/298)
- 关联：Slice 7A、0084、0085、[ADR-0175](./0175-organization-creation-is-atomic-with-first-active-owner.md)
- Requirement：`CTX-002`、`AUTHZ-001` 至 `AUTHZ-006`、`ORG-006` 至 `ORG-008`、`TEST-063`、`MANUAL-053`

## 背景

Slice 7A 已固定一次请求内的组织创建资格，但它不是组织写入。0084 已提供 exact external identity bridge 和原子组织创建 DB writer，0085 已提供 active-owner invariant；现有合同仍未固定 Backend 的公开入口、请求形状、认证顺序、幂等输入、成功 wire 和错误脱敏。客户端需要一个不暴露 Auth provider、内部 ID 或数据库错误的稳定协议。

## 决定

组织创建唯一公开入口是 `POST /v1/organizations`。该 path 不接受 query；认证成功后带 query 返回 `400 invalid_organization_creation_request`。其他 method 或未匹配 path 返回通用 `404 {"error":{"code":"not_found"}}`，不验证身份、读取 body 或调用 store。

命中固定 POST path 后，Backend 必须先严格解析 Bearer credential，再把 token 交给 Slice 7A 的 request-scoped `OrganizationCreationIdentityVerifier`。
verifier 先验证 JWT，再以同一 token 读取 Auth user endpoint。
整个身份和资格检查完成前，handler 不读取或解析 JSON body、不调用 store，也不写业务响应。
缺少或无效身份返回 `401 unauthenticated`；匿名或邮箱未确认返回 `403 organization_creation_forbidden`；provider、配置或未知资格状态不可用返回 `503 organization_creation_unavailable`。
Backend 不得使用 `SessionContext`、客户端 actor 或 body 字段替代 verifier 的 exact identity 与 eligibility。

认证成功且无 query 后，body 必须是严格的 JSON object，字段集合只能是：

```json
{
  "request_id": "uuid",
  "display_name": "string"
}
```

两个字段都必须存在，类型必须正确，不能有额外字段；`request_id` 必须是 UUID 字符串。它是 body 中唯一的幂等请求键，不使用 `Idempotency-Key` header、Backend cache 或 actor 与 UUID 的联合键。空 body 或非法 JSON 复用既有 `400 invalid_json`；超过既有 1 MiB body 上限复用 `413 payload_too_large`；非 object、缺失字段、额外字段、错误类型或无效 UUID 返回 `400 invalid_organization_creation_request`。

Backend 只把 7A 已验证的 exact `issuer`、`subject`、body 中的 `request_id` 和原始 `display_name` 传给 0084 的 `app_data.create_organization_for_identity_v1`。它不传入 Auth user object、内部 user／workspace／membership／owner ID、时间或审计值，也不绕过 bridge 调用 private writer。Backend 不 trim、Unicode normalize、大小写折叠、唯一性预检或合并 `display_name`；名称规则由既有 0084／0085 数据合同处理。固定调用完成并且 Promise settled 后，handler 才能写响应。

首次创建和同一 `request_id`、actor、canonical name 的精确重放都返回 `200`，响应不包含 replay 标记。成功 JSON root 的字段集合严格是以下五项，不包含组织名称、身份、内部附加字段或数据库 row 的其他列：

```json
{
  "creation_contract_id": "organization-creation:v1",
  "organization_workspace_id": "uuid",
  "organization_membership_id": "uuid",
  "organization_owner_assignment_id": "uuid",
  "created_at_utc": "UTC ISO-8601 timestamp"
}
```

0084 的四组数据库错误映射固定如下：

| SQLSTATE 与固定 message | HTTP 结果 |
| --- | --- |
| `22023 invalid organization creation identity` | `503 organization_creation_unavailable` |
| `22023 invalid organization creation request` | `400 invalid_organization_creation_request` |
| `42501 organization creation forbidden` | `403 organization_creation_forbidden` |
| `22023 organization creation idempotency conflict` | `409 organization_creation_conflict` |

任何未列出的 SQLSTATE、message、约束、parser、result shape、provider 或 adapter 错误都返回 `503 organization_creation_unavailable`。`401 unauthenticated` 只来自 Backend JWT／Slice 7A verifier，不由数据库生成。

所有成功和失败响应都使用 `Content-Type: application/json; charset=utf-8` 和 `Cache-Control: no-store`。失败 body 只能是 `{ "error": { "code": "<stable-code>" } }`。响应、结构化日志和失败审计不得保存 display name、邮箱、external issuer／subject、access token、Auth user object、provider metadata、SQL、数据库 message、stack、自由文本或原始错误；creation audit 继续遵守 0084 的 value-free allowlist。

## 后果与边界

7E 是 spec-only 工作单元。
本 ADR 不新增 TypeScript handler、Postgres adapter、真实 HTTP route 或 production composition。
它也不新增 migration、SQL function、Flutter、Drift 或 Apple 平台行为。
后续实现票必须覆盖 handler、adapter、真实 HTTP、production composition、synthetic PostgreSQL integration、四组错误映射、PII-free 日志和 promise-before-response。
这些 synthetic 证据不证明 production identity、部署端点或真人平台。

邀请、申请、owner 转让、membership／capability 管理、配额、反滥用和账号／组织删除不属于本合同，仍由其他工作单元定义。完整产品边界见 [`PRODUCT_SPEC.md`](../PRODUCT_SPEC.md) 的 Slice 7B／7E 条款。

## 验证

本 ADR 的 spec-only 验证只检查 Product Spec、ADR、学习文档、Markdown 链接和 diff；它不证明 HTTP runtime、数据库并发、生产身份、部署环境或真人平台。
