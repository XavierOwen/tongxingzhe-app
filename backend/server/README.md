# Backend 身份上下文、项目与接触同步

这个模块提供可信个人 session context、个人推广项目选择／创建、规范区域解析、问卷管理发布、问卷指标兼容审计、同步 command、change feed、独立的管理分析导航上下文，以及受保护管理报告的发布、目录和单份读取。所有受保护端点都先验证 Supabase access token。大部分业务使用可信个人上下文；管理报告使用独立的组织授权边界。同步协议处理已提交接触、追加更正、带原因作废、跨设备更正的自动合并与显式解决、未获回应尝试和账号私有草稿；设备专用草稿不会离开本机。

客户端不能提交 `app_user_id`、role 或 capability。上传会把 payload 的 workspace 和 project 与可信上下文交叉核对。拉取也会核对 query 范围，并只接受属于同一范围的不透明 cursor。响应不返回外部 subject、email 或 token。所有受保护入口共用严格的 bearer header 解析器，防止端点之间出现不同的认证规则。

cursor 不存在或不属于当前用户、空间和项目时，端点返回 `400 invalid_cursor`。未分类的数据库失败返回 `503 sync_unavailable`，不把内部 SQL 错误文字暴露给客户端。

## 规范区域解析合同

`POST /v1/regions/resolve` 接受 bearer token 与合法的 `latitude`、`longitude`。Backend 调用受限的 PostgreSQL 函数，只查询当前发布的区域树版本。

- 命中时返回 `200`、最小规范区域和从根到该节点的父链；
- 没有命中时返回 `202` 和 `pending`；
- 坐标无效返回 `400 invalid_coordinates`；
- 身份无效返回 `401 unauthenticated`；
- 数据库或服务不可用返回 `503 region_resolution_unavailable`。

响应不回显 token、外部 subject 或 email。Flutter 必须先原子安装返回的父链，再把地点改成已解析状态。任何失败都保留原坐标，不能改写成 `N/A`。

## 问卷管理合同

只有最新可信上下文含 `manage_analysis_definitions` 时，以下入口才可用：

| 方法与路径 | 行为 |
| --- | --- |
| `GET /v1/questionnaire-administration` | 列出当前版本、历史版本和草稿 |
| `POST /v1/questionnaire-drafts` | 建立空白草稿，或复制指定的已发布版本 |
| `GET /v1/questionnaire-drafts/:id` | 读取当前项目中的单个草稿 |
| `PUT /v1/questionnaire-drafts/:id` | 按预期 revision 保存受控定义 |
| `POST /v1/questionnaire-drafts/:id/publish` | 用 request ID 与发布说明建立新版本 |

Backend 不接受客户端提供的用户、空间或项目范围。每次请求都重新验证身份和上下文；发布前还会重读草稿、revision 与完整定义。PostgreSQL 再检查个人空间所有权并在项目锁内发布。网络重试不会产生重复版本，并发发布后仍只有一个 current 版本。

问卷指标使用同一 capability 和可信上下文，但走独立端点：

| 方法与路径 | 行为 |
| --- | --- |
| `GET /v1/questionnaire-metrics` | 列出稳定指标、结构化候选问题和追加式审计历史 |
| `POST /v1/questionnaire-metric-decisions` | 明确记录兼容或不兼容、理由和 request ID |
| `POST /v1/questionnaire-metric-decisions/:id/revoke` | 追加撤销事件并移除当前兼容成员 |

列表中的候选问题包含不可变定义、选项、时间范围、回答方式和当前样本数。Backend 不做文字相似匹配，也不接受任意公式或 SQL。PostgreSQL 保存当时的比较与影响快照；同一关系的并发确认或撤销只允许一个请求成为当前事实。

## 推广对象合同

`GET /v1/promotion-targets` 只返回当前分配给使用者的对象。`POST /v1/promotion-targets` 建立个人或机构对象，并在同一事务中把建立者设为初始跟进人。建立需要 `create_target` 和 `view_assigned_target_pii`；列表需要后一项能力。

客户端不提交用户、空间、项目或对象 ID。PostgreSQL 生成对象 UUID，并用已验证使用者与 request ID 保护重试。当前对象资料只在线读取，不进入 Flutter 本地库、接触同步 command 或 warehouse。

接触同步可以携带零到多条 `target_links`。非空关联要求 `view_assigned_target_pii`，只接受当前分配、同空间的对象；payload 保存对象 ID、类型、可选当次反应和后续联系同意，不携带姓名、电话或邮箱。机构反应还要求明确确认回应者代表机构。PostgreSQL v3 包装函数把对象校验、可选阶段 0 项目关系和接触 revision 原子提交。

项目关系使用两个独立入口：

| 方法与路径 | 行为 |
| --- | --- |
| `PATCH /v1/promotion-targets/:id/relationship` | 按 `expected_revision` 追加阶段、生命周期和共享备注修订 |
| `PUT /v1/promotion-target-stage-aliases` | 配置当前项目五个阶段的可选显示名 |

关系更新需要 `manage_assigned_target_follow_up` 和 `view_assigned_target_pii`，PostgreSQL 还会重验当前分配。旧 revision 先按 base revision 比较字段：不同字段自动合并，同字段返回 `409 promotion_target_relationship_conflict`、服务器当前值、持久化的拟提交值和冲突 ID。再次提交 `resolved_conflict_id` 会追加明确解决 revision。相同 `mutation_id` 的相同重试不增加 revision 或冲突。别名配置另需 `manage_analysis_definitions`。服务只存 `0–4`，响应中的 `display_stage` 由阶段乘二得到。

个人与机构关系归 workspace，不归当前项目：

| 方法与路径 | 行为 |
| --- | --- |
| `GET /v1/promotion-target-institution-relationships` | 返回调用者仍同时获分配两端对象的当前及历史关系 |
| `POST /v1/promotion-target-institution-relationships` | 明确建立一种个人—机构关系 |
| `POST /v1/promotion-target-institution-relationships/:id/end` | 按 `expected_revision` 结束关系并保留历史 |

读取需要 `view_assigned_target_pii`；建立和结束另需 `manage_assigned_target_relations`。Backend 不接受 workspace、project、操作者、开始或结束时间。PostgreSQL 用可信服务器时间，检查一端是个人、另一端是机构、两端属于同一 workspace，且调用者当前同时获分配两端。相同 mutation 精确重放不会增加历史；改写重放、活动关系重复和并发失败返回 `409`。

## 私人行动计划合同

私人周计划只使用已验证 identity 对应的当前个人空间和项目：

| 方法与路径 | 行为 |
| --- | --- |
| `GET /v1/personal-action-plan` | 返回本人当前版本、待生效版本和本周期接触场次 |
| `PUT /v1/personal-action-plan` | 按 expected revision 追加新版本 |
| `GET /v1/personal-action-reminder` | 返回本人当前项目的可选每日当地提醒钟点 |
| `PUT /v1/personal-action-reminder` | 立即追加、修改或清除提醒钟点 |

客户端只能提交可选周目标、固定 IANA 统计时区、ISO 周起始日、expected revision 和 mutation ID，不能提交用户、workspace、项目、进度或生效时间。Backend 使用服务端时间。首次设置立即采用当前自然周；后续设置从新配置定义的下一周期生效。

读取和写入不要求管理 capability，也没有组织或管理员列表入口。PostgreSQL 只计算当前有效的已提交接触，按实际发生时间使用半开周期边界。版本冲突返回 `409 personal_action_plan_conflict`；已有待生效版本时返回 `409 personal_action_plan_pending_change`。

提醒时间和周目标可独立使用。提醒 API 只接受 `0` 至 `1439` 的当地分钟、expected revision 和 mutation ID。它不接受设备 ID、设备权限或 UTC 触发时刻。系统通知 opt-in 只保存在各设备本地，新设备不会因同步提醒时间而自动启用。

## 管理报告发布合同

`POST /v1/projects/:projectId/management-report-snapshots` 只接受项目 UUID 和精确的 `{ "release_request_id": "UUID" }`。Backend 固定发布 `contact_sessions_by_channel_two_periods` v1；客户端不能提交报告定义、时区、数据截止点、筛选、capability、内部用户、报告 JSON 或格值。

Backend 验证 Bearer token 后，通过 [`0036_runtime_trusted_management_report_release.sql`](../database/migrations/0036_runtime_trusted_management_report_release.sql) 的唯一 bridge 调用 6J。runtime 只能执行 bridge，不能进入 `app_private`。production store 只执行一条参数化 `pool.query`；数据库提交发布尝试或幂等重放后，HTTP 才返回不含格值的最小结果。

无效 token 返回 `401`，无效 path／body 返回 `400`，无权返回 `403`，幂等／时区／合同冲突返回 `409`，数据库异常返回 `503`。`approved_baseline`、`approved` 与 `blocked` 成功结果都不含报告格、贡献者或授权证据。

## 管理报告快照读取合同

`GET /v1/projects/:projectId/management-report-snapshots/:snapshotId` 只接受两个 UUID path 参数。它不接受 body、query、报告 ID、时区、截止时间、筛选、capability 或内部用户 ID。这个显式项目范围不等于管理分析导航上下文，也不从当前选择推断项目。

Backend 验证 Bearer token 后，把 issuer、subject、project ID 和 snapshot ID 交给 [`0033_runtime_authorized_management_report_snapshot_read.sql`](../database/migrations/0033_runtime_authorized_management_report_snapshot_read.sql)。数据库只映射既有活动用户，再由 6K 重新检查组织成员、项目成员和 `view_anonymous_analytics`。个人 `SessionContext.capabilities` 不参与管理报告授权。

production store 只执行一条参数化 `pool.query`。PostgreSQL 提交这条 statement 的隐式事务后 promise 才解决；handler 随后才写 HTTP 响应。不要把 store query 放进可由上层稍后回滚的显式事务。若提交后网络中断，访问审计会保留；客户端重试会追加新的访问事件。

| 结果 | HTTP 合同 |
| --- | --- |
| 可信 v2 快照 | `200`，返回 `access_event_id`、`snapshot_id` 和受保护报告 |
| 未知或跨项目快照 | `404 management_report_snapshot_not_found` |
| 同项目 legacy／不可信 provenance | `409 management_report_snapshot_untrusted` |
| 无权 | `403 management_report_snapshot_forbidden` |
| token 缺失或无效 | `401 unauthenticated` |
| bridge、数据库或返回合同异常 | `503 management_report_snapshot_unavailable` |

所有响应使用 `Cache-Control: no-store`。错误不包含报告格、授权关系、external subject 或 PostgreSQL 消息。runtime 只能执行 `app_data` bridge，不能使用 `app_private`。

## 管理报告快照目录合同

`GET /v1/projects/:projectId/management-report-snapshots` 只接受一个显式项目 UUID。它不接受 body、query、筛选、分页、报告 ID、时区、capability 或内部用户 ID。6M 保存的管理分析选择只帮助导航，不是授权，也不会替代 path 中的项目。

Backend 先验证 Bearer token，再检查路径和请求形状。production store 只执行一条参数化 `pool.query`，调用 `app_data.list_authorized_management_report_snapshots_v1`。数据库映射既有活动用户，重新检查组织成员、项目成员和 `view_anonymous_analytics`，再返回至多 20 项可信 v2 快照元数据。结果按 `data_cutoff_utc`、`released_at_utc` 和 `snapshot_id` 降序排列。

成功响应包含 `access_event_id`、`project_id` 和 `snapshots`。每项只含 `snapshot_id`、`report_id`、`report_version`、`reporting_time_zone`、`data_cutoff_utc` 和 `released_at_utc`。空目录仍返回 `200` 并写入返回数量为 0 的访问审计。访问审计不保存快照 ID、报告元数据或报告格。

无权返回 `403 management_report_snapshot_directory_forbidden`；输入无效返回 `400 invalid_management_report_snapshot_directory_request`；数据库或返回合同异常返回 `503 management_report_snapshot_directory_unavailable`。token 缺失或无效始终先返回 `401 unauthenticated`。所有响应使用 `Cache-Control: no-store`。

目录第一项只是在固定排序下最靠前。当前合同没有更正、取代或“最新有效”语义，因此调用方不得把第一项标为当前报告。目录也不替代单份快照端点的再次授权和访问审计。

## 管理分析导航上下文

管理项目发现和选择使用独立入口，不改变个人 `/v1/session/context`：

| 方法与路径 | 行为 |
| --- | --- |
| `GET /v1/management-analysis/context` | 返回当前可查看的组织项目和有效的保存选择 |
| `PUT /v1/management-analysis/context` | 只接受一个 `project_id` UUID，并明确保存选择 |

只有当前完整授权链含 `view_anonymous_analytics` 的项目会出现。没有有效选择时 `current_context` 是 `null`；唯一项目也不自动选择。选择保存当次组织成员、项目成员和查看 grant 的精确证据。任一证据失效后 current 变为 `null`，以新 membership 或 grant 重新加入也不会复活旧选择。

响应只含组织和项目的 ID、名称，并固定返回 `authorization: must_reauthorize`。它不含 app user、subject、membership、grant 或授权时间。这个上下文只帮助导航；读取快照仍必须调用显式项目的 6L 端点，并由数据库再次授权。

GET 不接受 query 或 body；PUT 不接受额外字段。无效 token 返回 `401`，未知身份或无权选择返回 `403`，输入无效返回 `400`，数据库或合同异常返回 `503`。所有响应使用 `Cache-Control: no-store`。

## 配置

Backend 需要以下环境变量：

| 变量 | 含义 |
| --- | --- |
| `DATABASE_URL` | Backend 专用 PostgreSQL login；该 login 必须继承 `tongxingzhe_runtime` |
| `AUTH_ISSUER` | Supabase Auth 的精确 issuer，例如 `https://PROJECT.supabase.co/auth/v1` |
| `AUTH_AUDIENCE` | access token audience；默认 `authenticated` |
| `AUTH_JWKS_URL` | 可选 JWKS 地址；默认由 issuer 加 `/.well-known/jwks.json` 得到 |
| `PORT` | HTTP 端口；默认 `8080` |

正式环境只接受 JWKS 提供的 `ES256` 或 `RS256` 公钥。项目必须先启用 [Supabase asymmetric signing key](https://supabase.com/docs/guides/auth/signing-keys)。Backend 不需要 JWT secret、publishable key 或 service-role key。

## 本地检查

```bash
cd backend/server
npm ci
npm test
npm run check
```

测试使用临时 ES256 key 和 synthetic claims，不连接真实 Supabase 项目。身份 schema 见 [`0002_identity_context.sql`](../database/migrations/0002_identity_context.sql)，项目上下文见 [`0004_personal_project_contexts.sql`](../database/migrations/0004_personal_project_contexts.sql)，区域与私有草稿见 [`0005_regions_and_private_draft_sync.sql`](../database/migrations/0005_regions_and_private_draft_sync.sql)，个人指标见 [`0006_personal_contact_metrics.sql`](../database/migrations/0006_personal_contact_metrics.sql)，区域解析见 [`0007_canonical_region_resolution.sql`](../database/migrations/0007_canonical_region_resolution.sql)，独立接触尝试见 [`0008_contact_attempts.sql`](../database/migrations/0008_contact_attempts.sql)，接触更正与作废见 [`0009_contact_revisions.sql`](../database/migrations/0009_contact_revisions.sql)，修订冲突见 [`0010_contact_revision_conflicts.sql`](../database/migrations/0010_contact_revision_conflicts.sql)，版本化问卷执行见 [`0011_questionnaire_execution.sql`](../database/migrations/0011_questionnaire_execution.sql)，动态显示规则见 [`0012_questionnaire_visibility.sql`](../database/migrations/0012_questionnaire_visibility.sql)，管理草稿与不可变发布见 [`0013_questionnaire_publishing.sql`](../database/migrations/0013_questionnaire_publishing.sql)，旧草稿升级来源见 [`0014_questionnaire_draft_upgrades.sql`](../database/migrations/0014_questionnaire_draft_upgrades.sql)，问卷指标兼容见 [`0015_questionnaire_metric_compatibility.sql`](../database/migrations/0015_questionnaire_metric_compatibility.sql)。CI 使用 synthetic fixture 验证权限、重放、并发、跨项目、同步、问卷、区域、cursor 和 dump／restore。

推广对象目录见 [`0016_promotion_target_directory.sql`](../database/migrations/0016_promotion_target_directory.sql)。对应 fixture 另外验证对象分配、PII 隔离、访问审计和恢复库权限。

接触对象关联见 [`0017_contact_target_links.sql`](../database/migrations/0017_contact_target_links.sql)。对应 fixture 验证零到多关联、阶段 0 确认、跨空间与未分配拒绝、机构代表约束、幂等重放、revision 历史、冲突比较和 warehouse PII 隔离。

项目关系审计见 [`0018_promotion_target_relationship_audit.sql`](../database/migrations/0018_promotion_target_relationship_audit.sql)。对应 fixture 验证双向阶段、独立生命周期、共享备注历史、结构化下降原因、mutation 重放、显式冲突、分配撤销、显示别名和 warehouse 文本隔离。

个人与机构历史关系见 [`0019_person_institution_relationships.sql`](../database/migrations/0019_person_institution_relationships.sql)。对应 fixture 和独立会话脚本验证六类性质、两端授权、同空间与异类型约束、不同性质并存、同种活动关系唯一、结束历史、重放、并发和 warehouse 隔离。

对象资料保留与匿名化见 [`0020_promotion_target_retention.sql`](../database/migrations/0020_promotion_target_retention.sql)。对应 fixture 和独立会话脚本验证十二个月上限、较短策略、通用复核任务、明确续期、到期清理、撤回、不可逆文本清除、接触事实保留、重放和并发。

私人周计划见 [`0021_personal_action_plans.sql`](../database/migrations/0021_personal_action_plans.sql)。对应 fixture 验证固定 IANA 时区、任意周起始日、夏令时周期、下一周期版本、重放、revision 冲突、跨用户拒绝和恢复库权限。

私人每日提醒见 [`0022_personal_action_reminders.sql`](../database/migrations/0022_personal_action_reminders.sql)。对应 fixture 验证提醒可独立创建、当地分钟边界、清除、幂等重放、revision 冲突、跨用户拒绝和恢复库权限。

管理报告快照的生产 bridge 见 [`0033_runtime_authorized_management_report_snapshot_read.sql`](../database/migrations/0033_runtime_authorized_management_report_snapshot_read.sql)。对应 fixture 验证既有身份映射、未知身份不 bootstrap、view/release 能力分离、跨项目隐藏、legacy provenance 和逐次访问审计。

管理分析导航上下文见 [`0034_management_analysis_contexts.sql`](../database/migrations/0034_management_analysis_contexts.sql)。对应 fixture 与独立会话脚本验证项目发现、完整选择证据、撤权失效、重新授予不复活、view/release 分离、未知身份不 bootstrap，以及选择与撤权的两种并发顺序。

管理报告快照目录见 [`0035_management_report_snapshot_directory.sql`](../database/migrations/0035_management_report_snapshot_directory.sql)。对应 fixture 与独立会话脚本验证可信 v2 来源、20 项上限、稳定降序、空目录审计、最小 runtime 权限，以及目录访问与撤权的两种并发顺序。

管理报告生产发布见 [`0036_runtime_trusted_management_report_release.sql`](../database/migrations/0036_runtime_trusted_management_report_release.sql)。对应 fixture 与独立会话脚本验证既有身份映射、固定报告定义、发布与查看能力分离、幂等重放、冲突失败关闭、最小返回值，以及发布与撤权／时区配置的事务顺序。

## 运行

先执行数据库 migration，再启动进程：

```bash
export DATABASE_URL='postgresql://backend_login:REPLACE_ME@HOST/DATABASE'
export AUTH_ISSUER='https://PROJECT.supabase.co/auth/v1'
npm run build
npm start
```

部署平台负责 TLS 终止和 secret 注入。日志不得记录 Authorization header、token、subject 或数据库连接地址。
