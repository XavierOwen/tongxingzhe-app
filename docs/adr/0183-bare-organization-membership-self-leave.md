# ADR-0183：无下游关系成员可自助结束组织 membership

- 状态：已接受
- 日期：2026-09-07
- Slice：7W
- Issue：[#336](https://github.com/XavierOwen/tongxingzhe-app/issues/336)
- 依赖：[ADR-0033](./0033-organization-membership-does-not-imply-project-membership.md)、[ADR-0175](./0175-organization-creation-is-atomic-with-first-active-owner.md)、[ADR-0177](./0177-organization-owner-transfer-is-an-atomic-handoff.md)、[ADR-0180](./0180-organization-directed-account-invitation-contract.md)、0030、0085、0087、0088
- Requirement：`ORG-003`、`ORG-008`、`ORG-019`、`ORG-020`、`PII-003`、`TEST-073`、`MANUAL-063`

## 背景

0087 接受邀请只建立 organization membership。此时用户可能尚未参与项目，也未获得 owner 或对象分配。
0030 要求先结束 capability grants，再结束 project memberships，才能结束它们的 organization membership；关闭父行不是级联撤权。
对象分配只绑定 app user 与 target，不绑定 organization membership。完整组织退出还需要结束分配并按 PII-003 清除对应本地敏感缓存。

## 决定

首版只交付“无下游关系成员自助退出”，以硬拒绝保护尚未实现的依赖处理。
它不增加读取权限、owner relinquish 或替他人移除成员的能力。

### 资格与作用范围

0090 增加 `app_data.leave_organization_membership_for_identity_v1(text,text,uuid,uuid)`，依次接受 trusted issuer、subject、request、organization workspace。
bridge 原值精确解析 active app user，调用 private `app_private.leave_organization_membership_v1(uuid,uuid,uuid)`，参数依次为 actor、request、workspace。
identity 输入按原长度检查：issuer 最多 2048 字符、subject 最多 512 字符，NULL 或去除两端 U+0020 后为空时拒绝；不 normalize、bootstrap 或复用创建资格。

首次执行必须在锁后同时满足：

- actor 仍 active，workspace 是未删除 organization；
- 本人 membership 当前有效且 `inactive_from_utc IS NULL`；已排定未来结束也不能重写；
- 该 membership 没有 `inactive_from_utc IS NULL` 或结束时间晚于本次判断时间的 owner assignment；当前和未来所有权均拒绝，多 owner 也不例外；
- 该 membership 不存在任何 project membership 历史，包括已经结束的项目关系；
- 本人在该 workspace 下不存在 `ended_at IS NULL` 的 promotion target assignment，不因 target 已匿名化而放行。

过去已结束的 owner 历史不阻止退出。任一资格或依赖不符统一 forbidden，整个事务无 membership、claim 或 audit 写入。
成功只结束选中的 membership，其他账号、组织、项目、capability、owner、对象分配与当前项目保持原状。

### 锁与时间

首次执行遵守 `self-leave request lock → actor app-user FOR UPDATE → organization governance lock → organization-membership advisory lock`。
request 前缀固定 `organization-membership-self-leave-request:`；后两种锁复用既有 workspace 与 workspace／actor key。
全部锁取得后重读 claim、tombstone 与授权事实，以一次 `clock_timestamp()` 作为资格判断、membership end、claim、audit 和 receipt 的共同时间。
数据库不先截断精度。不能用 transaction 起点：事务可能先开始，再等另一个事务提交刚接受邀请的新 membership。

项目成员 writer 的既有 membership 锁与本操作串行化。现有正式 target writer 只允许 personal workspace，本切片不开放组织 target 写入。
未来组织 target 分配／重新激活必须另定与本操作共同使用的授权、锁及撤权合同，不能仅靠这里的一次不存在查询。

### Claim、重放与生命周期

family 为 `organization-membership-self-leave:v1`。claim 的单列主键是 request UUID；另存可去关联 actor、organization workspace、organization membership 与有限的 effective time。
只有 actor 使用 `ON DELETE SET NULL` FK，其余 UUID 是不阻断终结清除的 opaque references。guard 只允许 actor 非 null → null 一次，其他更新或删除拒绝。
value-free audit 只保存 event UUID、固定 contract、request、workspace、membership 与 effective time，不保存 actor、名称、身份、token、PII 或自由文本；audit 追加不可变。
tombstone 只含固定 family 与 request UUID，不可改删。相同 UUID 可以用于其他独立操作 family。

request lock 下先检查本 family tombstone 和 live claim。相同 request、actor 与 workspace 再锁定并重读 active actor，然后返回原 receipt，不重验当前 membership、owner 或组织恢复状态，也不追加 audit。
重新入组产生新 membership 后，旧 request 仍只重放先前退出；再次退出必须使用新 request UUID。
actor／workspace drift、已去关联 claim 或 tombstone 固定 idempotency conflict。无法解析或非 active identity 仍由 bridge 返回 forbidden。

恢复期冻结首次执行，live exact replay 保持只读。未来组织终结清除按 creation → directed invitation → owner transfer → membership self-leave 顺序，各 family 内按 UUID 取 request locks，再按既有 app-user／governance／membership 顺序取锁。
治理锁后重读 claim 集合；出现未锁定的新 request 必须回滚后按完整集合重试。先写 value-free tombstone，再清除 leave claim／audit 与组织业务数据。
账号终结删除同样先锁完整受影响 request 集合，在治理事务内去关联 actor；去关联不产生替代操作者。
这里仅追加未来清除的 family 合同，不实现删除、恢复或 purge writer，也不改写历史 claim。

### Result、HTTP 与 ACL

数据库与 HTTP receipt 固定四字段：

```json
{
  "membership_self_leave_contract_id": "organization-membership-self-leave:v1",
  "organization_workspace_id": "uuid",
  "organization_membership_id": "uuid",
  "effective_at_utc": "UTC timestamp"
}
```

private writer 与 bridge 都为 VOLATILE SECURITY DEFINER、固定 `search_path=pg_catalog`，owner 与既有 membership validator 相同。
显式撤销 PUBLIC／runtime 的默认权限；runtime 只获 bridge EXECUTE，无 private writer 或相关表权限。

| SQLSTATE 与 exact message | HTTP status 与 code |
| --- | --- |
| `22023 invalid organization membership self-leave identity` | `503 organization_membership_self_leave_unavailable` |
| `22023 invalid organization membership self-leave request` | `400 invalid_organization_membership_self_leave_request` |
| `42501 organization membership self-leave forbidden` | `403 organization_membership_self_leave_forbidden` |
| `22023 organization membership self-leave idempotency conflict` | `409 organization_membership_self_leave_conflict` |

只有 `POST /v1/organizations/:organizationWorkspaceId/membership-self-leave`，body 精确为 `{ "request_id": "uuid" }`。
按 canonical raw path → strict Bearer／generic identity → 无 query（含裸 `?`）→ path UUID → store 配置 → JSON body／实际 1 MiB 限制 → 一次参数化 bridge 调用处理；必须 await 后才响应。
客户端不提交 actor、membership、owner 或时间。composition 复用 generic verifier 与 pool，不增加连接、环境变量、Auth user lookup 或当前项目读取。
response parser 检查 exact keys、固定 contract、小写 canonical UUID、有限 UTC 时间和 requested workspace 一致；HTTP 时间沿用现有毫秒序列化。
200 同时表示首次成功或 exact replay，不增加 replay flag。全部响应 JSON UTF-8、no-store；错误仅固定 code，完整 transport 错误表见 Product Spec 7W。
未知 SQLSTATE／message、constraint、row shape、parser 或 adapter 错误一律 unavailable，不回传内部原文。

## 取舍与验证

不尝试在这一切片级联关闭项目或对象分配。只拒绝“当前项目成员”仍会留下历史／未来范围问题，因此首版拒绝任何 project membership 历史。
不直接结束多-owner成员的所有权；过去 owner 可在既有 handoff 完成后退出，未来 co-owner relinquish 单独定义。
这两个限制是 v1 的明确适用范围，不声称覆盖所有成员。

structural check、回滚 fixture、独立会话并发、Backend unit／真实本地 HTTP／composition／runtime integration 与 Docker rebuild／checksum／dump／restore 验证合同。
重点证明锁等待后时间、刚入组再退出、等待中失效、同／异 request、旧请求不影响重加入的新 membership、依赖拒绝和零部分写入。
不实现 Flutter gateway／UI、敏感缓存清除、邀请预览、成员目录、完整组织退出或生产配置；synthetic 与 CI 不是 production identity、真实 PII 清除或真人平台证明。
