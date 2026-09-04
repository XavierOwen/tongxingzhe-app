# ADR-0179：组织 owner transfer Flutter typed gateway 合同

- 状态：已接受
- 日期：2026-09-04
- Slice：7L Spec
- Issue：[#314](https://github.com/XavierOwen/tongxingzhe-app/issues/314)
- 依赖：[ADR-0178](./0178-organization-owner-transfer-http-contract.md)、[#309](https://github.com/XavierOwen/tongxingzhe-app/issues/309)、[#312](https://github.com/XavierOwen/tongxingzhe-app/issues/312)、[#302](https://github.com/XavierOwen/tongxingzhe-app/issues/302)
- Requirement：`CTX-002`、`AUTHZ-001`、`AUTHZ-004`、`AUTHZ-006`、`ORG-009` 至 `ORG-012`、`CODE-005`、`TEST-066`、`MANUAL-056`

## 背景

ADR-0178 已固定 owner-transfer 的 HTTP route、请求形状、认证顺序、0086 五字段 receipt 和稳定错误。#312 已交付对应的 Backend handler、dedicated store、route、production composition 和 local synthetic integration。

Flutter 业务层仍需要一个独立的 typed gateway。它必须让调用方使用同一 request UUID 重试，同时不接触 Bearer token、数据库行、provider 错误或成员资料。组织创建 gateway（#302）提供 transport 形状的参考，但 owner transfer 的 path、target membership、failure union 和 receipt 都是独立合同。

本 ADR 是 Issue #314 的 spec-only 决定，不重新定义 0086、owner、membership、recovery 或 purge。

## 决定

### 公共 typed seam

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

公共类型名称固定为 `OrganizationOwnerTransferReceipt`、`OrganizationOwnerTransferFailureCode`、`OrganizationOwnerTransferResult`、`OrganizationOwnerTransferSuccess` 和 `OrganizationOwnerTransferRejected`。result 只有 `OrganizationOwnerTransferSuccess(receipt)` 与 `OrganizationOwnerTransferRejected(code)` 两种形状。

`OrganizationOwnerTransferReceipt` 是不可变值，只含 `ownerTransferContractId`、`organizationWorkspaceId`、`previousOwnerAssignmentId`、`organizationOwnerAssignmentId` 四个 `String` ID，以及 UTC `DateTime` 类型的 `effectiveAtUtc`。receipt 不增加 target、actor、成员资料、replay flag 或自由字段。

`OrganizationOwnerTransferFailureCode` 只有以下值：`notConfigured`、`unauthorized`、`invalidJson`、`payloadTooLarge`、`invalidRequest`、`forbidden`、`conflict`、`targetAlreadyOwner`、`serviceUnavailable`、`networkUnavailable` 和 `invalidResponse`。不增加业务性 `notFound`。

公开实现名称固定为 `DeferredOrganizationOwnerTransferGateway`、`HttpOrganizationOwnerTransferGateway` 和 `productionOrganizationOwnerTransferGateway(IdentitySession)`。它们是 owner-transfer 专用类型，不抽取通用 UUID、时间、router、错误或 domain gateway 抽象。

### 配置、IdentitySession 与 client ownership

`productionOrganizationOwnerTransferGateway(IdentitySession identitySession)` 读取 `BACKEND_BASE_URL`。值缺少、为空或只含空白时，返回不触网的 `DeferredOrganizationOwnerTransferGateway`；其调用结果是 `notConfigured`，`close()` 是 no-op。

非空配置必须先完成 `Uri.parse` 和现有 `validatePathlessBackendBaseUri`。URI 解析失败或 validator 拒绝时同步抛出配置异常，不降级为 deferred，也不创建 `HttpOrganizationOwnerTransferGateway` 或 `http.Client`。

`HttpOrganizationOwnerTransferGateway` 接管并关闭传入的 `http.Client`。production factory 创建并传入该 client；deferred gateway 不创建或关闭 client。任何 gateway 都不关闭 `IdentitySession`。响应和 receipt 只留在内存，不写 Drift、缓存、同步队列或日志。

实现复用既有 `IdentitySession`、pathless Backend base URI validator、已安装的 `http.Client` 和一次 `401` refresh 模式。不复用 organization-creation domain、7A eligibility、Auth lookup、`SessionContext` 或 creation gateway。

### 输入、route、headers 与 body

调用方提供 request、organization workspace 和 target membership UUID。输入必须是 `8-4-4-4-12` 十六进制 wire shape，字母可以大写或小写，不额外限制 version／variant nibble。gateway 先校验并 canonicalize 为 lowercase；非法 UUID 在取得 token 或发送 HTTP 前返回 `OrganizationOwnerTransferRejected(invalidRequest)`。gateway 不生成 request UUID，也不做 workspace、actor、membership、owner 或权限预查。

请求只发送无 query、无 fragment 的：

```text
POST /v1/organizations/:organizationWorkspaceId/owner-transfer
```

path 使用 canonical workspace UUID。headers 固定为 `Accept: application/json`、`Authorization: Bearer <token>` 和 `Content-Type: application/json; charset=utf-8`。不发送 `Idempotency-Key`、actor 或 workspace header/body 字段。body 只能含两个 canonical lowercase UUID：`request_id` 与 `target_organization_membership_id`。

### Identity failure 与一次 401

gateway 从同一个 `IdentitySession` 取得 Bearer token。identity failure 映射固定为：`IdentityFailureCode.notConfigured` 到 `notConfigured`，`IdentityFailureCode.networkUnavailable` 到 `networkUnavailable`，其他 `IdentityFailureCode` 到 `unauthorized`。

首次 response 只有在 headers 严格正确且 error envelope 精确为 `401 {"error":{"code":"unauthenticated"}}` 时，才强制 refresh 一次。retry 复用相同 method、canonical URL 和 body，`Authorization` 使用强制刷新取得的 token。第二个 `401` 返回 `unauthorized`，不得循环刷新；其他响应不触发 refresh。

### Response parser 与 typed failure

所有 response 先严格要求 `Content-Type: application/json; charset=utf-8` 和 `Cache-Control: no-store`。

成功 `200` 只接受 exact 五字段 root：固定 `organization-owner-transfer:v1`、三个 lowercase canonical UUID、与 path 相同的 `organizationWorkspaceId`，以及有效 UTC `YYYY-MM-DDTHH:mm:ss.SSSZ` 时间。adapter 将有效时间解析为 UTC `DateTime`；字段缺失、额外、错误类型或值不符合合同都返回 `invalidResponse`。

稳定错误映射固定如下：

| HTTP response | Flutter failure |
| --- | --- |
| `400 invalid_json` | `invalidJson` |
| `400 invalid_organization_owner_transfer_request` | `invalidRequest` |
| `401 unauthenticated` | `unauthorized` |
| `403 organization_owner_transfer_forbidden` | `forbidden` |
| `409 organization_owner_transfer_conflict` | `conflict` |
| `409 organization_owner_transfer_target_already_owner` | `targetAlreadyOwner` |
| `413 payload_too_large` | `payloadTooLarge` |
| `503 organization_owner_transfer_unavailable` | `serviceUnavailable` |
| network、timeout 或 `http.ClientException` | `networkUnavailable` |

缺少或错误 headers、非法 JSON、非 exact error envelope、unknown status／code、`404 not_found`、字段漂移、非法 UUID／时间和其他 parser／adapter 错误统一返回 `invalidResponse`。不得暴露 HTTP client、provider、数据库、身份或成员原文。

首次成功和 exact replay 在客户端都返回同一五字段 success。gateway 不判断 replay、owner、membership、组织状态或权限；这些语义由 Backend 和 0086 决定。

### 隐私、关闭与证据边界

返回值和原始 response 只存在于内存。gateway 不写 PII 到 Drift、缓存、同步队列或日志，也不把未知错误原文交给调用方。调用方负责在应用生命周期中调用 `close()`；HTTP gateway 关闭自己拥有的 client，deferred gateway 的 `close()` 不触网，任何 gateway 都不关闭 `IdentitySession`。

本 ADR 不定义 `AppDependencies`、`AppStartupReady`、`TongxingzheApp` lifecycle、controller、ViewModel、Screen、route、导航、l10n、上下文切换、Drift、缓存、离线队列、同步、UUID generator 或 durable retry。

它也不实现 Dart gateway、unit tests、Backend、HTTP route、PostgreSQL、0086 migration／bridge／writer、owner invariant、claim、audit、tombstone、membership、capability、recovery、deletion、purge、邀请或申请。

## 后果

Flutter 业务层获得了可重试且不泄露 transport/provider 细节的稳定 typed seam。独立 failure union 让 UI 或业务层处理配置、认证、请求、冲突、服务和网络状态，而不需要解释 HTTP status 或数据库错误。

代价是 adapter 必须严格维护 URL、headers、UUID、JSON、时间和错误 envelope 的解析合同；不能通过宽松解析或客户端预查弥补 Backend 状态。这个边界保留了 0086 的 no-enumeration、PII-free 和一次性身份刷新语义。

所有实现证据都是 synthetic 或 local。它们不证明 production identity、部署端点、真实组织、删除恢复、Apple 或其他真人平台运行时。

## 验证

`TEST-066` 要求后续 focused Flutter tests 使用 fake `IdentitySession` 和内存 `MockClient`，覆盖：

- 固定 interface、public type、path、body、headers 和无 `Idempotency-Key`；
- 三个 UUID 的 lowercase canonicalization，以及非法输入在 token／HTTP 前 short-circuit；
- 空 `BACKEND_BASE_URL` 的 deferred no-network、非空非法 URI／path validator 的同步配置失败和 client ownership／close；
- identity failure、一次精确 `401 unauthenticated` refresh、相同 retry URL／body 与第二次 `401`；
- strict JSON／`no-store`、五字段 immutable receipt、UTC `DateTime`、全部 stable mappings、unknown／404／parser／network／timeout 脱敏；
- 首次成功与 exact replay 的相同 typed success，以及 `IdentitySession` 不被关闭。

最小命令为：

```bash
flutter test --no-pub test/organization_owner_transfer/http_organization_owner_transfer_gateway_test.dart
dart analyze
flutter test --no-pub
dart run tool/check_markdown_links.dart
```

本 ADR、Product Spec、MANUAL-056、Markdown link、no-slop 和 Dart synthetic tests 只证明 Flutter transport、parser、内存和资源生命周期合同，不证明 Backend、PostgreSQL、production identity、部署、Drift、UI、删除恢复、Apple 或其他真人平台。
