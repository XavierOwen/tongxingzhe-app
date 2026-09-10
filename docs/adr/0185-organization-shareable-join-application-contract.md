# ADR-0185：可分享加入链接与入组申请审批合同

- 状态：已接受
- 日期：2026-09-10
- Slice：7AG Spec
- Issue：[#356](https://github.com/XavierOwen/tongxingzhe-app/issues/356)
- 依赖：[ADR-0031](./0031-private-organizations-require-invitation-or-approved-request.md)、[ADR-0032](./0032-separate-bound-invitations-from-shareable-join-links.md)、[ADR-0175](./0175-organization-creation-is-atomic-with-first-active-owner.md)、[ADR-0177](./0177-organization-owner-transfer-is-an-atomic-handoff.md)、[ADR-0180](./0180-organization-directed-account-invitation-contract.md)、[ADR-0183](./0183-bare-organization-membership-self-leave.md)、[ADR-0184](./0184-bound-recipient-organization-invitation-preview.md)
- Requirement：`ORG-001` 至 `ORG-004`、`ORG-008`、`ORG-024` 至 `ORG-029`、`AUTHZ-001`、`AUTHZ-004`、`AUTHZ-006`、`CODE-005`、`TEST-081`、`MANUAL-071`

## 背景

ADR-0031 与 ADR-0032 允许可分享加入链接创建待审批申请，但没有固定链接、申请、审批、期限或并发合同。定向邀请的接收者在接受时直接入组，不能用它表示可转发链接的多申请人和 owner 审批。

仓库当前没有组织级成员管理 capability。本决定因此使用 current active owner 作为首版创建与审批授权，不从项目报告 capability 或组织目录延伸出新权限。

## 决定

### 参与者与范围

可分享 link 只能由组织的 current active owner 创建。owner 资格同时要求 active app user、有效 organization membership 和 current owner assignment。创建不复用 Slice 7A 的组织创建资格，也不接受客户端提交 actor、owner assignment 或 capability。

任一 active 账号可以用已知 `link_id` 预览仍有效的 link。预览只返回 link ID、组织原名称和到期时间，不返回 workspace、创建者、成员、owner 或 capability。它是私有组织目录之外的已知 UUID 例外，不提供搜索、列表或可复用的授权证据。

只有 active 且尚非该组织 current member 的 exact authenticated actor 能首次提交申请。current member 的新申请统一 forbidden。链接不绑定收件人；同一条链接可由多个合格账号各提交一份申请。持有链接不建立 membership，也不允许一个账号替另一个账号申请。

审批者必须在锁后仍是请求组织的 current active owner。审批只接受已知 organization workspace UUID 与 application UUID。首次审批只为申请人追加一条 organization membership，不建立 project membership、owner assignment 或 capability。

### Link claim 与预览

link claim family 固定为 `organization-shareable-join-link:v1`。`link_id` 是 opaque selector、创建幂等键和 request-lock key。request advisory-lock 前缀固定为 `organization-shareable-join-link-request:`。它与 creation、directed invitation、owner transfer、membership self-leave 及 application family 分开；相同 UUID 可在不同 family 中使用。

private 关系名固定为 `app_private.organization_shareable_join_link_request_claims`、`app_private.organization_shareable_join_link_request_tombstones` 和 `app_private.organization_shareable_join_link_audit_events`。link claim 只保存：

- 不可变的 `link_id` 单列主键；
- `organization_workspace_id`；
- 账号终结删除时可去关联的 `creator_app_user_id`；
- 数据库生成的 `issued_at_utc` 和精确晚 168 小时的 `expires_at_utc`。

workspace UUID 是 writer 在治理锁内验证的 opaque reference，不使用会阻断组织终结清除的 foreign key。claim 不保存组织名称、邮箱、external identity、token 或权限。除了账号终结治理可把 creator 从非空改为空，claim 不得更新或删除。

创建首次成功在取得全部锁后读取一次 `clock_timestamp()`。`expires_at_utc` 精确比该时间晚 168 小时，不受 session time zone 或 DST 影响。

相同 link、active creator 和 workspace 返回原创建 receipt。该重放不重验 creator 的 current owner 或 membership，也不追加 claim 或 audit。

creator identity 不再 active、creator 已去关联或 live claim 属于另一 creator 时返回 forbidden。只有同一 active creator 重用 link ID 但改变 workspace 时返回 idempotency conflict；link tombstone 也返回 conflict。

creator 后来失去 owner、结束 membership 或被去关联，都不撤销尚有效的 link。预览和首次提交只检查 link、workspace、当前 actor 与当次操作资格，不重新授权 creator。数据库当前时间达到或超过 expiry 后，预览和新申请统一 forbidden。预览使用一次墙钟和同一查询快照，不取写锁，不写 claim、application 或 audit。

### Application claim、重放与生命周期

application claim family 固定为 `organization-shareable-join-application:v1`。`application_id` 是 opaque selector、提交幂等键和 application request-lock key。request advisory-lock 前缀固定为 `organization-shareable-join-application-request:`。

private 关系名固定为 `app_private.organization_shareable_join_application_request_claims`、`app_private.organization_shareable_join_application_request_tombstones` 和 `app_private.organization_shareable_join_application_audit_events`。application claim 只保存：

- 不可变的 `application_id` 单列主键；
- `link_id` 与 `organization_workspace_id`；
- 账号终结删除时可去关联的 `applicant_app_user_id`；
- 数据库生成的 `submitted_at_utc` 和精确晚 168 小时的 `expires_at_utc`；
- 待审批时为空、首次批准时同时设置的 `approved_at_utc` 与 `approved_organization_membership_id`。

`link_id`、workspace 和 membership UUID 是 opaque references，不使用会阻断组织清除的 foreign key。applicant 使用 `ON DELETE SET NULL` 规则，不得改绑到另一账号。claim guard 只允许 applicant 一次去关联和一次 pending-to-approved 转换，其他字段不可改写。两个 approval 字段必须同时为空或同时非空。claim 不保存 approver、profile、邮箱、external identity 或自由文本。

待审批申请由 approval 字段为空且数据库当前时间早于 application expiry 推导。不增加 status history、expiry sweeper、reject 或 revoke。申请在全部锁后使用一次 `clock_timestamp()` 作为 submitted time，并从该时刻独立有效 168 小时。link 后来过期不使已提交 application 提前失效，批准不回头检查 link 或取得 link request lock。

同一 active applicant、link 和 application ID 精确重放返回原 submission receipt。它不重验 link expiry、组织恢复状态、current membership 或 approval，也不追加 audit。applicant identity 不再 active 或引用已去关联时返回 forbidden。

live claim 属于另一 applicant、applicant identity 不再 active 或引用已去关联时都返回 forbidden。同一 active applicant 重用 application ID 但改变 link 时返回 idempotency conflict。application tombstone 和同一 applicant／link 已保留另一 application ID 也返回 conflict。

只有没有 application claim／tombstone 且没有该 applicant／link 历史的请求，才进入 link 期限、恢复状态和 current-member 校验。

### 审批与原子 membership

批准先在锁后验证 active exact actor 是 `requested_organization_workspace_id` 的 current owner，再对 live application 的 workspace 做可观测分类。unknown application、live claim workspace mismatch、错误或非 owner actor 都返回 forbidden。application tombstone 也始终 forbidden；value-free tombstone 不保存 workspace，不能把它当作可授权的冲突回执。

首次批准还必须在全部锁后重新确认 application 仍为 pending，墙钟早于 application expiry，申请人引用未去关联且账号 active，并且尚无该组织的 current membership。组织恢复期、过期 application、去关联或非 active applicant，以及申请人已通过其他路径入组，都统一 forbidden 且不消费 application。底层 membership validator 的原始错误也收敛为 shareable-join forbidden，不向外暴露内部分类。

批准 transaction 使用一次锁后 `clock_timestamp()`。它原子地追加 organization membership、设置 application 的 approval 字段并追加批准 audit。membership、claim、audit 和 receipt 使用同一个未截断时间。任一失败都回滚全部三类事实，不留部分 membership、approval 或 audit。

已批准 application 的精确重放先验证请求 actor 在 requested workspace 中仍是 current active owner。验证成功后，它返回 claim 保存的原 approval receipt。任一当时合格的 owner 都可以执行该重放。claim 不保存原 approver，也不把原 approver 当作新授权。

重放不重验 applicant 后来的账号、去关联状态、membership 或 application expiry，不重建 membership，不追加 audit。live claim workspace mismatch 和 application tombstone 都返回 forbidden。

同一 application 的并发批准由 application request lock 串行化。同一 applicant 对同一组织的不同 application 由 governance 与 membership lock 串行化；首个批准建立 membership 后，其他待批申请因 current membership 而 forbidden，不改写这些申请。

### 锁序、恢复与清除

首次写入使用以下固定锁序：

- 创建 link：link request lock → creator app-user row → organization governance lock → creator organization-membership lock；
- 提交 application：link request lock → application request lock → applicant app-user row → organization governance lock → applicant organization-membership lock；
- 批准 application：application request lock → approver 与 applicant app-user rows（按唯一 UUID 排序）→ organization governance lock → applicant organization-membership lock。

每条路径取得全部必要锁后必须重读 claim、tombstone、账号、workspace recovery、membership 和 owner 事实。link 与 application 锁同时需要时始终先取 link 锁。approve 只使用 application 已保存的独立申请事实，不回头取 link 锁。后续 membership、账号或组织治理不得反向取锁。

只读精确重放使用缩减锁序，且在取得全部列出的锁后重读资格与 claim：

- create replay：link request lock → creator app-user row；
- submit replay：link request lock → application request lock → applicant app-user row；
- approved replay：application request lock → current approver app-user row → requested organization governance lock。

approved replay 只在最后一把锁后确认调用者仍是 current active owner。它不锁 applicant 或 membership，因为两者此时可能已去关联或结束。它不得先取 governance 再取 user row，也不得省略 governance 而保留 owner TOCTOU。

组织进入删除恢复期后，预览、新 link、新 application 和首次 approval 都 forbidden。已有 live claim 的精确创建或提交重放保持只读；已批准 application 只能由重放时仍合格的 current owner 只读重放。恢复期重放沿用上述缩减锁序和锁后重读。恢复期不结束 link 或 application claim，也不清除 audit。

组织终结清除按以下全局 family 顺序取得该组织的全部 request locks，每个 family 内再按 request UUID 排序：

`organization creation → directed invitation → owner transfer → membership self-leave → shareable join link → shareable join application`

清除随后按 UUID 排序取得受影响 app-user rows，再取 governance 和 membership locks。治理锁后必须重读 recovery 和两个新 family 的 claim 集合；集合变化时回滚并按完整集合重试。它先为每个 claim 写入只含固定 family 与 request UUID 的 value-free tombstone，再按依赖顺序清除 claim、audit 和组织业务数据。具体 deletion、recovery 和 purge writer 不属于本决定。

账号终结删除先按上述 family 和各 family 内 UUID 顺序取得完整的受影响 link／application request locks，再取 app-user、governance 和 membership locks。治理锁后重读 claim 集合；出现未锁定的新 claim 时回滚重试。它只去关联 creator 和 applicant 引用，不改绑、删除或缩短 link／application。creator 去关联不影响 link 供其他合格账号使用；pending application 的 applicant 去关联后不能批准。

### Receipt、错误与审计

四种 SQL result 与未来 HTTP receipt 使用独立的 exact typed row：

| 操作 | Contract ID | 字段 |
| --- | --- | --- |
| 创建 link | `organization-shareable-join-link:v1` | `organization_shareable_join_link_contract_id`、`link_id`、`organization_workspace_id`、`issued_at_utc`、`expires_at_utc` |
| 预览 link | `organization-shareable-join-link-preview:v1` | `organization_shareable_join_link_preview_contract_id`、`link_id`、`organization_name`、`expires_at_utc` |
| 提交 application | `organization-shareable-join-application:v1` | `organization_shareable_join_application_contract_id`、`application_id`、`link_id`、`organization_workspace_id`、`submitted_at_utc`、`expires_at_utc` |
| 批准 application | `organization-shareable-join-application:v1` | `organization_shareable_join_application_contract_id`、`application_id`、`organization_workspace_id`、`organization_membership_id`、`approved_at_utc` |

未来 HTTP UUID 使用 canonical lowercase，时间使用 UTC 毫秒 ISO-8601。SQL row 保留 `timestamptz` 完整精度。receipt 不含 creator、applicant、approver、profile、email、owner assignment、capability、replay flag 或自由字段。四种结果不使用含可选字段的混合 envelope。

未来 HTTP 成功和失败响应都使用精确 `Content-Type: application/json; charset=utf-8` 和 `Cache-Control: no-store`。错误 root 只能是 `{ "error": { "code": "<stable-code>" } }`。route、method、status、body 顺序和 parser 由后续 transport slice 固定。

数据库错误与未来 Backend code 固定为：

| SQLSTATE 与固定 message | Backend code |
| --- | --- |
| `22023 invalid organization shareable join identity` | `organization_shareable_join_unavailable` |
| `22023 invalid organization shareable join request` | `invalid_organization_shareable_join_request` |
| `42501 organization shareable join forbidden` | `organization_shareable_join_forbidden` |
| `22023 organization shareable join idempotency conflict` | `organization_shareable_join_conflict` |

unknown SQLSTATE、message、constraint、parser、result shape 或内部异常统一映射为 `organization_shareable_join_unavailable`。identity 输入为 null、去除两端 U+0020 后为空、issuer 超过 2048 字符或 subject 超过 512 字符时使用 invalid identity。typed UUID 参数为 null 时使用 invalid request。非法 UUID 文本由未来 transport 在进入 SQL 前处理。

未知 link／application／workspace、非 organization workspace、非 active actor、非 owner、current member 的新申请、过期、恢复期、申请人去关联或已由其他路径入组都统一 forbidden。错误不区分 `not_found`、`expired`、`already_member` 或 `recovery`。

create 的 live claim creator 不同时 forbidden；只有同一 active creator 的 workspace drift 是 idempotency conflict。submit 的 live claim applicant 不同时 forbidden；只有同一 active applicant 的 link drift 是 conflict。

同 applicant／link 更换 application ID 和 create／submit family tombstone 也使用 conflict。approve 的 unknown application、live claim workspace mismatch 或 application tombstone 始终 forbidden。错误不返回数据库原文。

link audit 只允许 event ID、link contract ID、link ID、workspace UUID、固定 `link_created` kind、issued time 和 expiry。

application audit 只允许 event ID、application contract ID、application ID、link ID、workspace UUID、固定 `application_submitted` 或 `application_approved` kind、批准时可有的 membership UUID，以及对应数据库时间。

两类 audit 都追加且不可变。它们不保存 creator、applicant、approver、组织名称、profile、email、external issuer／subject、token、Auth object、provider metadata、请求或 URL 原文、SQL、数据库 message、stack 或自由文本。失败操作不写成功 audit；精确重放不写第二条 audit。

### Trust boundary 与 ACL

实现必须提供四个 operation-specific exact-identity `app_data` 函数。三个 writer 各调用一个 private writer；preview 沿用 0091 的最小 read-only seam，直接 `RETURN QUERY`，不增加 private preview 函数：

- `app_data.create_organization_shareable_join_link_for_identity_v1(text, text, uuid, uuid)` 调用 `app_private.create_organization_shareable_join_link_v1(uuid, uuid, uuid)`；
- `app_data.preview_organization_shareable_join_link_for_identity_v1(text, text, uuid)` 直接读取最小预览；
- `app_data.submit_organization_shareable_join_application_for_identity_v1(text, text, uuid, uuid)` 调用 `app_private.submit_organization_shareable_join_application_v1(uuid, uuid, uuid)`；
- `app_data.approve_organization_shareable_join_application_for_identity_v1(text, text, uuid, uuid)` 调用 `app_private.approve_organization_shareable_join_application_v1(uuid, uuid, uuid)`。

每个 `app_data` 函数的前两个参数是 `trusted_issuer`、`trusted_subject`。create 的 UUID 依次是 `requested_link_id`、`requested_organization_workspace_id`；preview 只有 `requested_link_id`；submit 的 UUID 依次是 `requested_application_id`、`requested_link_id`；approve 的 UUID 依次是 `requested_application_id`、`requested_organization_workspace_id`。private writer 把两个 identity 参数替换为 bridge 解析的 `trusted_actor_app_user_id`，并保持各 UUID 顺序。identity 函数只使用 issuer 和 subject 原值精确匹配已有 active 账号，不 trim、normalize、bootstrap、修复 identity 或使用 Auth user object。

七个函数均为 `VOLATILE SECURITY DEFINER`，固定 `search_path = pg_catalog`。owner 与 `app_private.validate_organization_membership_v1()` 一致且不是 runtime。approve identity 函数名恰为 63 个 ASCII 字节，不得增长或依赖 PostgreSQL 静默截断。`PUBLIC` 不得执行任一函数。

runtime 只有四个 `app_data` 函数的 `EXECUTE`，不能使用 `app_private`、执行 private writer，或直接读写 identity、user、workspace、membership、owner、claim、tombstone 与 audit 关系。普通 app role 不获得这些关系的 `INSERT`、`UPDATE`、`DELETE` 或 `TRUNCATE`。RLS 不代替 trust boundary、request lock、governance lock 或锁后校验。

create、submit 与 approve 的 bridge 和 private writer 分别返回对应的 exact typed row。preview 函数只返回四字段 preview row。submit 与 approve 共用 `organization_shareable_join_application_contract_id = 'organization-shareable-join-application:v1'`，但字段形状保持不同。未来 migration 可拆分为多个交付，但不得改变函数的参与者、参数顺序、result、最小权限或数据边界。

## 后果与边界

本决定把可分享入口限定为“有界预览、认证申请、owner 审批”。它保留私有组织、独立 membership、current-owner 治理、request family、并发 fence、value-free audit 和终结清除原则。

7AG 是 spec-only 决定。它不新增 migration、SQL function、Backend route／store、Flutter gateway／UI、平台 deep link、申请列表、账号搜索、profile、reject、revoke、rotation、通知、项目权限或自动 context switch。它也不实现 deletion、recovery 或 purge writer。

## 验证

当前验证只检查 Product Spec、ADR、学习文档、Markdown links、no-slop 和 diff。它不证明数据库 claim、两个 168 小时生命周期、原子 membership、并发锁、真实 identity、HTTP、平台链接、生产部署、账号／组织清除、Apple 或真人平台行为。
