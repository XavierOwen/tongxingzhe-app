# ADR-0187：组织待审批申请目录只向当前所有者开放

- 状态：已接受
- 日期：2026-09-17
- Slice：7BI
- Issue：[#412](https://github.com/XavierOwen/tongxingzhe-app/issues/412)
- Requirements：`ORG-035` 至 `ORG-037`、`TEST-104`、`MANUAL-094`
- 依赖：[ADR-0185](./0185-organization-shareable-join-application-contract.md)、[ADR-0182](./0182-organization-directory-is-membership-scoped.md)

## 决定与原因

组织所有者需要发现本组织的申请编号，现有审批窗口却只接受原渠道提供的 UUID。目录沿用审批的 current-owner 边界，只提供申请来源与时间，不把申请人资料或批准资格带到客户端。普通成员目录、成员管理 capability 与完整队列另需合同。

### 可见范围与 pending

每次读取以 Backend 已验证的 exact issuer/subject 映射既有 active identity/user，并确认 requested workspace 是未删除组织，actor 的组织 membership 与 owner assignment 在读取时刻同时有效。组织目录不能代替 owner 授权。未知、非组织、删除恢复期、非 active 或非 current owner 均统一 forbidden。

pending 严格沿用 ADR-0185：两项 approval 字段为空，且数据库 observation time 严格早于 application expiry。目录不额外过滤 inactive、去关联或已入组 applicant；不重验 link 的期限、creator 或当前资格。link UUID 只标识申请来源。首次批准仍由 0094 在全部锁后重新检查 applicant、membership、expiry、recovery 与 owner。

目录固定按 `submitted_at_utc ASC, application_id ASC` 返回最早 20 项，无 cursor、total 或完整队列承诺。未能批准的 pending 也可能占据位置直到到期；现有按已知 UUID 手工批准的入口保留。LIMIT 只限制响应条数，不证明扫描工作量有界。

### 一次一致读取与 SQL seam

只新增 `app_data.list_org_join_applications_for_identity_v1(text, text, uuid)`，参数依次为 `trusted_issuer`、`trusted_subject`、`requested_organization_workspace_id`。不增加 private reader、表、writer、request family、audit 或治理 fence。

identity 原值精确匹配，不 trim、normalize、bootstrap 或修复。null、btrim 后为空、issuer 超过 2048 字符或 subject 超过 512 字符使用 invalid identity；btrim 只作空值检查。null workspace UUID 使用 invalid request。

owner/user/workspace 授权与 claim 读取须在同一 SQL query snapshot 中完成，以 materialized observation 只调用一次 `clock_timestamp()`。不得先独立查 owner 再查 claims。合法 owner 没有 pending 时仍返回一个空数组 row；未授权时没有结果并统一 forbidden。此读取快照不保留响应送达时或未来批准的资格。

函数使用 `VOLATILE SECURITY DEFINER`、固定 `search_path = pg_catalog`，owner 与 `validate_organization_membership_v1()` 相同且不是 runtime。PUBLIC 不可执行；runtime 仅获新 bridge EXECUTE，不扩大 identity、user、workspace、membership、owner 或 private claim/audit 的表权限。

SQL 返回一个 exact typed row：

| 字段 | 类型与含义 |
| --- | --- |
| `organization_shareable_join_application_directory_contract_id` | text，固定 `organization-shareable-join-application-directory:v1` |
| `organization_workspace_id` | requested uuid |
| `observed_at_utc` | 单次 observation 的完整 timestamptz |
| `applications` | jsonb array，最多 20 项 |

每项只有 `application_id`、`link_id`、`submitted_at_utc`、`expires_at_utc`。UUID 是 canonical lowercase；SQL JSON 时间显式使用 UTC 六位小数，保留 PostgreSQL 精度。expiry 仍精确晚于提交时间 168 小时。没有 applicant、profile、姓名、邮箱、membership、approval、角色或自由字段。

SQL 稳定错误为：

| SQLSTATE/message | 既有 Backend family code |
| --- | --- |
| `22023 invalid organization shareable join application directory identity` | `organization_shareable_join_unavailable` |
| `22023 invalid organization shareable join application directory request` | `invalid_organization_shareable_join_request` |
| `42501 organization shareable join application directory forbidden` | `organization_shareable_join_forbidden` |

其他 SQLSTATE/message、constraint、shape、parser 或内部异常保持 unavailable。不返回存在性、申请人状态或数据库原文。

### Backend 与 Flutter

固定 GET 为 `/v1/organizations/:organizationWorkspaceId/shareable-join-applications`。沿用 raw method/path 匹配与 generic auth-first 处理，不接受 query 或 declared GET body，不读取 body。错误 method、encoding、dot segment、重复或尾随 slash 在认证前返回 not_found。store 每次只执行一条参数化 identity bridge query，不预查 owner 或使用 SessionContext；响应等待 store settled。

成功 HTTP root 与 SQL row 对应四字段，时间规范为 UTC 三位毫秒，所有成功与失败响应使用 JSON UTF-8 和 no-store。SQL pending 使用未截断的严格时间比较；HTTP 截断后 expiry 与 observed 可能同为一个毫秒，客户端不得据相等值拒绝合法结果，也不能用本机时间裁切队列或保证可批准。

Backend 在既有 application store 增加 `listPending`。Flutter 在同一 `OrganizationShareableJoinGateway` 增加 `listPendingApplications`，复用既有请求、header、稳定 family error、一次 401 refresh、ABA/close fence、deferred 与资源所有权。不建立第二个 session/gateway 或新 composition。

strict parser 检查 fixed root/item、contract、requested workspace、UUID、UTC、168 小时、20 项上限与无重复。Backend 在 SQL 原始微秒精度检查 submitted/UUID 升序；Flutter 只检查提交毫秒非递减并保留服务器顺序。同一毫秒内可能有不同微秒，客户端不能重建真实的时间并列或再要求 UUID 升序。结果为不可修改的内存类型，不进 Drift、离线、缓存或同步。

“我的组织”的单个组织行可明确打开目录，开窗读取一次，之后显式刷新。loading、空目录、失败与读取时间均可辨识，文案明确最早 20 项而非完整队列。选中只预填既有审批窗口，仍须原渠道核对申请人、本地 review 和明确批准。原固定意图重试、历史 receipt 与服务端判权不变；不自动批准、复制、切项目或关闭借用 gateway。

账号失效、换号或 ABA 清空目录和选择，迟到读取或子窗口完成不能复活旧状态；同账号切项目不改变固定组织。中英文、键盘/焦点、heading/live region、触控目标、小屏高字号与安全区沿用现有 Material 组织窗口。

## 边界与验证

本决定不新增完整分页、账号/成员搜索、申请人资料、reject/revoke、通知、非 owner 权限、项目退出、删除/恢复/purge 或新入组政策。目录不写 claim、membership、owner 或 audit，不创建项目/capability，也不改变 0092/0093/0094 的业务事实。

验证须分别提供 SQL 结构/ACL、可重复 fixture 与零副作用、runtime-role/真实本地 HTTP、strict Dart gateway、Widget 会话/布局、完整 Docker/checksum/restore 与精确 head CI。原生 Android 的合成身份/入口复核不等于生产 JWT、生产 composition 端到端、部署或六平台真人验收。
