# ADR-0181：组织定向账号邀请与接受 HTTP 合同

- 状态：已接受
- 日期：2026-09-06
- Slice：7R
- Issue：[#326](https://github.com/XavierOwen/tongxingzhe-app/issues/326)
- 依赖：[ADR-0180](./0180-organization-directed-account-invitation-contract.md)、[ADR-0178](./0178-organization-owner-transfer-http-contract.md)、0087
- Requirement：`ORG-013` 至 `ORG-017`、`AUTHZ-001`、`AUTHZ-004`、`AUTHZ-006`、`TEST-068`、`MANUAL-058`

0087 已实现定向账号邀请的数据库授权、claim、原子接受和幂等。HTTP 使用两个独立操作，复用既有 generic identity verifier 和 JSON body reader，不重做数据库授权。接受入口用 invitation selector 定位资源；组织与目标账号只能由 claim 决定。

## Route 与请求

| 操作 | 唯一入口 | 精确 JSON body |
| --- | --- | --- |
| 创建 | `POST /v1/organizations/:organizationWorkspaceId/directed-account-invitations` | `{"invitation_id":"uuid","target_app_user_id":"uuid"}` |
| 接受 | `POST /v1/organization-directed-account-invitations/:invitationId/accept` | `{}` |

router 在 WHATWG URL normalization 前取第一个 `?` 之前的 raw pathname。每条 route 只允许一个未编码的动态 segment。
wrong method、trailing／repeated slash、literal 或 encoded dot segment、任何含 `%` 的 path segment、extra 或未匹配 path 返回通用 `404 not_found`。
这些请求不认证、不读 body、不调用 store。单个动态 segment 不是合法 UUID 时仍算命中，认证后才返回 invalid request。

两操作顺序相同：

1. 严格解析 Bearer credential；
2. generic `IdentityVerifier` 验证 exact issuer／subject；
3. 拒绝所有 query，包括仅有 `?` 的空 query；
4. 验证 path UUID，并转为 lowercase；
5. 检查 dedicated invitation store；
6. 按实际 byte 数读取 JSON body，再校验精确字段；
7. 只调用对应的一个 store method；
8. 等待 Promise 完成后写出 response。

缺少或无效 Bearer 返回 `401 unauthenticated`。verifier 的 `unauthenticated` category 返回 401，`unavailable` 或未知异常返回 503。
missing verifier／store 在读取 body 前返回 `503 organization_invitation_unavailable`。
不调用 7A creation eligibility、Auth user lookup、`SessionContext` 或客户端账号预查。

body reader 复用实际 byte 数的 inclusive 1 MiB 边界：1,048,576 bytes 可以解析，第 1,048,577 byte 返回 `413 payload_too_large`。
它支持 chunked body，不信任 `Content-Length`，不增加请求 `Content-Type` gate。空 body 和非法 JSON 返回 `400 invalid_json`。
非 object、缺字段、额外字段、错误类型或无效 UUID 返回 `400 invalid_organization_invitation_request`。
接受必须发送空 object `{}`，不能省略 body，也不能加入 invitation、workspace、target、actor、email 或 token 字段。
UUID 只要求 `8-4-4-4-12` 十六进制形状，不增加 version／variant 限制；大小写均可输入，传入 store 前统一 lowercase。

## Store、receipt 与错误

`OrganizationDirectedAccountInvitationStore` 保留 `create(identity, invitationId, organizationWorkspaceId, targetAppUserId)` 和 `accept(identity, invitationId)` 两个方法。
两者分别只执行一次参数化的 0087 create／accept identity bridge；函数签名、SQLSTATE、锁、ACL 与 claim family 沿用 ADR-0180。
store 不访问 `app_private`，不拆成多个写入，也不使用 creation／owner-transfer store。
production composition 复用既有 generic identity verifier 与 pool query，注入 dedicated Postgres store；不增加环境变量。

首次与 exact replay 均返回 `200`。两个成功 root 仍是 ADR-0180 的独立五字段 receipt：

- create：`organization_invitation_contract_id`、`invitation_id`、`organization_workspace_id`、`issued_at_utc`、`expires_at_utc`；
- accept：`organization_invitation_contract_id`、`invitation_id`、`organization_workspace_id`、`organization_membership_id`、`accepted_at_utc`。

contract ID 固定为 `organization-directed-account-invitation:v1`。create receipt 必须绑定请求 invitation 与 path workspace，accept receipt 必须绑定 path invitation。
所有 UUID 输出 lowercase。数据库 Date 或有效有限的 RFC3339 instant 输出为 `YYYY-MM-DDTHH:mm:ss.SSSZ`；create expiry 与 issued 仍相差连续 168 小时。
额外字段、错误类型、无效日期、绑定漂移或其他 parser 错误失败关闭。SQL 仍保存完整时间精度，不因 HTTP 毫秒序列化改变事实时间。

| 条件 | HTTP 结果 |
| --- | --- |
| 错误 method／route | `404 not_found` |
| 缺少或无效 Bearer／JWT | `401 unauthenticated` |
| query、path、body shape／UUID，或 DB invalid request | `400 invalid_organization_invitation_request` |
| 空 body／非法 JSON | `400 invalid_json` |
| body 超过 1,048,576 bytes | `413 payload_too_large` |
| DB forbidden | `403 organization_invitation_forbidden` |
| DB claim drift／tombstone | `409 organization_invitation_conflict` |
| invalid trusted identity、missing verifier／store、未知错误 | `503 organization_invitation_unavailable` |

DB 映射只接受 ADR-0180 的 exact SQLSTATE 与 message 配对。未知 SQLSTATE、message、约束、result、adapter 或 verifier 异常统一 503，不返回原文。
未知 invitation／target／workspace、错误接受者、expiry、current membership、inactive／deleted／deletion_pending、recovery 与账号去关联都由 DB 收敛为 forbidden。
HTTP 不预查这些状态，不新增 `expired`、`already_member` 或业务 `not_found`。replay 和 conflict 的先后次序仍由 0087 决定。

所有 response 使用精确 `Content-Type: application/json; charset=utf-8` 和 `Cache-Control: no-store`。
错误 root 精确为 `{"error":{"code":"stable_code"}}`。响应、结构化日志和失败审计遵守 ADR-0180 的 value-free allowlist；不记录请求原文、身份、token、SQL 或数据库错误。

## 验证与边界

7R 在同一工作单元固定并实现上述 HTTP 合同。handler／store、真实本地 HTTP、production composition 和 runtime bridge integration 检查顺序、边界、strict receipt、错误、幂等与 Promise gate。
既有 Docker suite 继续验证 0087 授权、原子性、锁、ACL 和 restore；7R 不增加 migration、SQL writer 或权限。
本地 synthetic HTTP、PostgreSQL 与 CI 不证明 production identity、部署服务、邮件投递、真实组织、Apple 或真人平台运行时。

本决定不包含 Flutter、UI、邮件／未注册账号邀请、账号／成员／邀请目录、通知、分享链接、申请审批、revoke、owner／capability、上下文切换、Drift、缓存、离线或 durable retry。
删除、恢复和 purge API 仍属于独立工作单元。
