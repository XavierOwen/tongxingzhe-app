# ADR-0186：普通项目成员的明确安排合同

- 状态：已接受
- 日期：2026-09-16
- Slice：7AT Spec
- Issue：[#381](https://github.com/XavierOwen/tongxingzhe-app/issues/381)
- Requirements：`ORG-030` 至 `ORG-034`、`MANUAL-084`、`TEST-094`
- 依赖：[ADR-0033](./0033-organization-membership-does-not-imply-project-membership.md)、[ADR-0034](./0034-project-members-default-to-promoter-capabilities.md)、[ADR-0175](./0175-organization-creation-is-atomic-with-first-active-owner.md)、[ADR-0185](./0185-organization-shareable-join-application-contract.md)

## 背景

组织所有者负责成员和项目治理。ADR-0033 要求项目逐一明确分配，ADR-0034 把默认推广者加入与管理权限提升分开。0030 已有独立 project membership、父区间包含和重叠约束，但没有供真实身份使用的普通项目成员安排 writer。

本决定只具体化已有 owner 治理职责。它不定义角色分配 capability，不从报告能力取得组织治理权，也不授予 owner 数据访问权。

## 决定

### 参与者与一次性安排

首次安排只允许 requested organization 的 current active owner。actor 来自 trusted exact `(issuer, subject)`，锁后仍须是 active app user、有效 organization member 和 current owner。target 是同组织已有、锁后有效的 `organization_membership_id`，其 app user 仍 active。project 必须属于同一未删除 organization workspace，且锁后 status 为 active。

workspace、project 和 target membership 都是不可信的 opaque UUID selectors。客户端不能提交 actor、target app user、角色、capability、时间或资料；没有账号、项目或成员搜索。owner 可以明确安排自己，但所有权本身不自动产生项目成员关系。

成功只追加一条默认推广者 project membership。它不新建 organization membership、owner assignment、管理 capability 或推广对象分配；不改变 owner 的项目／PII 权限，也不升级 target 的职责。

首次写入在全部必要锁后只读取一次 `clock_timestamp()`。新 membership 的 active_from 使用该时刻，inactive_from 复制 target parent 当前的结束点，可为空。区间必须被 parent 包含；起点和非空终点有限。这里不接受客户端时间，也不安排未来起点或延长 parent。

已结束历史不得改写或复活。同一 target app user／project 的当前或未来区间若与新 `[now, parent_end)` 重叠，整体 forbidden；不消费 request、不变更原 membership。

结束点原为空时只能设置一次；插入时已经非空则不能再次修改。因此有限 parent 下的新 child 不能提前结束。本票不提供完整撤权或改期。

### Request、claim 与重放

独立 family 固定为 `organization-project-membership-assignment:v1`，request advisory prefix 为 `organization-project-membership-assignment-request:`。request UUID 是单列主键，不与 actor 组成联合键；其他治理 family 的同一 UUID 不冲突。

private 表固定为：

- `app_private.organization_project_membership_assignment_request_claims`；
- `app_private.organization_project_membership_assignment_request_tombstones`；
- `app_private.organization_project_membership_assignment_audit_events`。

claim 只保存 request、可去关联的 actor app-user UUID、organization workspace、project、target organization membership、新 project membership、active_from 和可空 inactive_from。

actor 使用 `ON DELETE SET NULL`；其他 UUID 是治理锁内验证的 opaque references，不设阻断终结清除的 foreign key。除账号终结治理把 actor 从非空改为空外，claim 不得 UPDATE／DELETE，不可改绑。

tombstone 只有固定 claim_family 和 request UUID 两列，不保存 actor、workspace、project、target、时间或业务内容，禁止 UPDATE／DELETE。

writer 在同一 request lock 下先检查 tombstone，再读取 live claim。tombstone 始终 idempotency conflict。live claim 属于其他 actor 或 actor 已去关联时统一 forbidden。同一 active actor 重用 request 但改变 workspace、project 或 target membership 时返回 idempotency conflict。

同一 active actor、request、workspace、project、target 精确重放返回原七字段历史 receipt，不重复建立 membership 或 audit。

replay 只取得 request 和 actor app-user row locks，并重读 actor active 与 claim；不重新要求 current owner，不重新检查 target、project、parent 或恢复状态，也不取得写入 hierarchy／project fence。历史 receipt 不是当前资格或访问凭据。

### 锁序与项目状态

首次写入使用固定顺序：

`request → actor／target app-user rows（UUID 去重排序）→ organization governance → actor／target organization-membership locks（按 user UUID 去重排序）→ target project-membership lock → project status fence`

hierarchy key 沿用 `organization-membership:<workspace>:<user>` 和 `project-membership:<project>:<user>`。project status fence 复用 0073 status trigger 已必取的 `management-follow-up-consent-opt-in:<project>` transaction advisory key。这里只复用串行化资源，不调用 opt-in configure/read，不读取配置，不授予 release capability，也不新增 status trigger。

不对 project 使用额外 `FOR UPDATE`／`FOR SHARE` row lock；status UPDATE 在进入 trigger 前已取得 row lock，反向取锁会形成 row／hierarchy 互等。INSERT 的 FK 校验沿用既有 schema。fence 后使用新的 SQL 重读项目状态，不保留取锁前的值。

private writer 在取锁和读取事实前检查 `current_setting('transaction_isolation') = 'read committed'`，首次写入与 replay 均适用。其他隔离模式失败关闭；不尝试在函数内修改事务模式。REPEATABLE READ 的事务快照可能在等待归档提交前建立，不能把新的 SQL 误当成新的快照。本要求只限两个新 seam，不改变既有 writer。

取得全部锁后，writer 重读 claim、tombstone、active actor／target、workspace、owner、target parent、project 和 overlap，并使用同一次墙钟生成 membership、claim、audit 与 receipt。任一失败回滚全部事实。

纯 status UPDATE 与安排由同一 fence 线性化。归档先提交则首次安排拒绝；安排先提交则先建立 membership，随后归档。已有 project／capability 撤权继续使用 org→project→capability hierarchy。若同一事务还做组织／账号治理，必须在 status UPDATE 前遵守既有 user→governance→hierarchy 全局顺序；本 writer 不修复任意反序的 superuser 组合。

### 身份 seam、结果与 ACL

operation-specific seam 固定为：

- `app_data.assign_organization_project_member_for_identity_v1(text, text, uuid, uuid, uuid, uuid)`：`trusted_issuer`、`trusted_subject`、`requested_request_id`、`requested_organization_workspace_id`、`requested_project_id`、`requested_target_organization_membership_id`；
- `app_private.assign_organization_project_member_v1(uuid, uuid, uuid, uuid, uuid)`：`trusted_actor_app_user_id` 加上述四个 requested UUID。

bridge 原值精确匹配既有 active identity，不 trim、normalize、bootstrap、修复或使用 Auth object。identity 为 null、btrim 后空、issuer 超过 2048 字符或 subject 超过 512 字符时属于 invalid identity；btrim 仅检查空白，不改变映射。未知或非 active identity 为 forbidden。

两函数返回同一 exact typed row：

| 字段 | SQL 类型／固定值 |
| --- | --- |
| `project_membership_assignment_contract_id` | text：`organization-project-membership-assignment:v1` |
| `organization_workspace_id` | uuid |
| `project_id` | uuid |
| `organization_membership_id` | uuid，提交的 target parent |
| `project_membership_id` | uuid，新追加 membership |
| `active_from_utc` | timestamptz，锁后单一墙钟 |
| `inactive_from_utc` | 可空 timestamptz，沿用 parent bound |

不返回 actor、target app user、owner assignment、资料、capability、replay flag 或自由字段。SQL 保留时间完整精度；未来 HTTP 使用 canonical lowercase UUID、UTC 毫秒 ISO-8601、JSON 和 no-store，但 route／method／transport 顺序由后续切片固定。

两函数使用 `VOLATILE SECURITY DEFINER`、固定 `search_path = pg_catalog`，owner 与 `app_private.validate_organization_membership_v1()` 相同且不是 runtime。PUBLIC 不得执行；runtime 只有 identity bridge 的 EXECUTE，没有 private schema、writer 或 identity／user／workspace／membership／owner／claim／tombstone／audit 直接读写权。guard 和新表不开放 runtime／PUBLIC 权限，不扩大既有表 ACL。

### 稳定错误与最小审计

| SQLSTATE 与固定 message | 未来 Backend code |
| --- | --- |
| `22023 invalid organization project membership assignment identity` | `organization_project_membership_assignment_unavailable` |
| `22023 invalid organization project membership assignment request` | `invalid_organization_project_membership_assignment_request` |
| `42501 organization project membership assignment forbidden` | `organization_project_membership_assignment_forbidden` |
| `22023 organization project membership assignment idempotency conflict` | `organization_project_membership_assignment_conflict` |
| `0A000 organization project membership assignment requires read committed` | `organization_project_membership_assignment_unavailable` |

requested UUID 为 null 时 invalid request。未知、跨组织、非 active、非 owner、project archived、parent 结束、overlap 和恢复期都统一 forbidden，不暴露存在性或内部约束分类。

未知 SQLSTATE、message、constraint、parser 或内部异常统一 unavailable。非法 UUID 文本由未来 transport 检查，不改变 typed SQL 签名。

成功 audit 只有 event UUID、固定 contract ID、request UUID、workspace UUID、project UUID、新 project-membership UUID、active_from 和可空 inactive_from，追加且不可变。target parent 只保存在 claim 和 receipt；新 membership 是 audit 的 target lineage。

audit 不保存 actor／target app user、组织或项目名称、资料、external identity、token、Auth/provider metadata、请求／URL 原文、SQL、数据库消息、stack 或自由文本。失败不写成功 audit，exact replay 不写第二条 audit。

value-free 只表示不保存资料和业务内容值，不把可关联 UUID 宣称为不可反查的匿名数据。claim、membership 与 audit 的受控 lineage 仍服从组织清除边界。

### 恢复与终结清除边界

组织恢复期冻结首次安排，但允许 live exact replay 只读返回历史 receipt；恢复期不结束 parent 或 project membership，也不清除 claim／audit。

本 family 在 ADR-0185 六个既有 family 后追加到全局 request-lock 顺序：creation → directed invitation → owner transfer → membership self-leave → shareable join link → join application → project membership assignment。

每个 family 内 UUID 排序；随后 user rows、governance、membership hierarchy 和必要 project fence。不反向取得 request locks。

未来组织清除在治理锁后重读完整 claim 集合和恢复资格，集合变化时回滚重试；先留 family／request tombstone，再按依赖移除 claim、audit 与组织业务数据。账号终结治理依同一全局顺序取得受影响 request locks，重读集合后才允许 actor 去关联，不能改绑到新账号。

具体 deletion、restore、eligibility、purge writer、清除运行器和受控 DELETE guard 例外不在本决定；不以关闭 guard 或授予 runtime 表权限实现清除。

## 后果与验证

7AT 只交付 Spec、ADR、术语和既有学习章节。它不实现 migration、writer、Backend／HTTP、Flutter、成员目录、项目创建、管理角色或 capability 提升、对象分配、完整撤权、通知、缓存、离线或同步。

文档验证检查既有权限方向、签名／字段、锁序、重放、时间、错误、ACL、审计与清除边界的一致性，以及 Markdown links、no-slop 和 diff。

后续 DB 切片须提供 structural check、rollback fixture、不支持隔离模式的失败关闭、真实等待的归档／安排双序和 hierarchy 竞态、checksum 及 dump／restore；静态推演和文档检查不证明数据库、生产身份或平台运行。
