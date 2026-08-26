# Backend 身份上下文、项目与接触同步

这个模块提供可信个人 session context、个人推广项目选择／创建、规范区域解析、问卷管理发布、问卷指标兼容审计、同步 command、change feed、独立的管理分析导航上下文，以及受保护管理报告的发布、目录、current-city 目录和单份读取。所有受保护端点都先验证 Supabase access token。大部分业务使用可信个人上下文；管理报告使用独立的组织授权边界。同步协议处理已提交接触、追加更正、带原因作废、跨设备更正的自动合并与显式解决、未获回应尝试和账号私有草稿；设备专用草稿不会离开本机。

客户端不能提交 `app_user_id`、role 或 capability。上传会把 payload 的 workspace 和 project 与可信上下文交叉核对。拉取也会核对 query 范围，并只接受属于同一范围的不透明 cursor。响应不返回外部 subject、email 或 token。所有受保护入口共用严格的 bearer header 解析器，防止端点之间出现不同的认证规则。

## 个人当前关系阶段快照

| 方法与路径 | 行为 |
| --- | --- |
| `GET /v1/personal/current-relationship-stage` | 返回当前 personal project 中仍分配给当前使用者、对象 active 且项目关系 active 的 PII-free 对象×项目关系快照 |

这个端点不接受 query、body、workspace、user、project、`asOf` 或任意时间范围。Backend 从已验证身份解析当前 session context，PostgreSQL 再验证 personal workspace owner、active project、active assignment、active target 和 active relationship。`snapshot_as_of_utc` 是一次一致性读取判断当前状态的 UTC 时刻；`source_cutoff_utc` 表示该返回集合中最新关系更新时间，空集合使用同一 snapshot 时刻。两者都不表示可重建的历史 as-of，也不等同于接触期间的数据截止时间。

响应只包含稳定合同、project key、快照和授权时刻、`coverage.total/pending`（当前 bridge 的 pending 为 0）以及 target key、stage、revision、updated time。target key 是受限数据面的 UUID，不是匿名保证；响应不含姓名、电话、邮箱、关系备注或历史 revision。runtime role 只能执行窄 bridge，不能直接读取对象、分配或关系表。当前路由不扩展组织 workspace，也不调用对象 PII 目录或离线 PII vault。

cursor 不存在或不属于当前用户、空间和项目时，端点返回 `400 invalid_cursor`。未分类的数据库失败返回 `503 sync_unavailable`，不把内部 SQL 错误文字暴露给客户端。地点来源只有一个窄的永久拒绝例外，见下节。

## 个人阶段变更汇总

| 方法与路径 | 行为 |
| --- | --- |
| `GET /v1/personal/relationship-stage-change-summary?from_utc=...&until_utc=...` | 返回当前个人项目在 UTC 半开期间内的阶段变更事件、方向和去重关系数 |

请求必须只有一次 `from_utc` 和一次 `until_utc`，不带 body。时间只接受 UTC `Z`，可带一至六位
小数；Backend 规范化到毫秒，并要求 `from_utc < until_utc`。Backend 先验证 Bearer token，再
检查 query。客户端不能提交 actor、workspace、project、metric、筛选条件或 `as-of`。

成功响应固定为：

```json
{
  "result": {
    "contract_id": "personal_relationship_stage_change_summary_result_v1",
    "project_id": "uuid",
    "time_basis": "relationshipChangedAtUtc",
    "period": {
      "from_utc": "2030-01-01T00:00:00.000Z",
      "until_utc": "2030-01-08T00:00:00.000Z"
    },
    "data_cutoff_utc": "UTC timestamp",
    "authorized_at_utc": "UTC timestamp",
    "value": {
      "event_count": 5,
      "distinct_relationship_count": 4,
      "upward_count": 3,
      "downward_count": 2
    }
  }
}
```

空期间仍返回同一 `result` 形状和四个零。Backend 严格检查 exact keys、UUID、UTC 时间、非负
安全整数、`event_count = upward_count + downward_count` 以及
`distinct_relationship_count <= event_count`。

PostgreSQL 通过
`app_data.read_personal_relationship_stage_change_summary_v1(text,text,timestamptz,timestamptz)`
重新解析 issuer／subject 对应的 active app user。一次 bridge 调用在同一 PostgreSQL transaction
中锁定该用户的 `user_current_projects` 行，验证未删除的 personal workspace 与 active current
project，再用一个 statement snapshot 聚合 revision。锁与项目切换写入冲突，所以项目切换、归档
或删除并发时只能得到完整旧 snapshot、完整新 snapshot 或 `403`，不会混合两个项目。
`data_cutoff_utc` 和 `authorized_at_utc` 都来自外层 bridge 调用 statement 开始时的可信 UTC 时刻，不是
历史 as-of，也不是客户端收包时间。

候选 revision 必须属于可信 actor、workspace 和 current project，并满足 `old_stage IS NOT NULL`、
`old_stage <> new_stage`、`changed_fields` 含 `stage`、`reason_code <> 'project_entry'`。同一关系的
不同 revision 分别计事件，distinct 关系按对象×项目去重。查询不按当前 assignment、关系 lifecycle
或 target active 状态过滤；对象匿名化或 assignment 结束后，先前合格事件仍计入。匿名化产生的
lifecycle-only 与 note-only revision 不计入。响应只含计数，不含对象、revision、actor、原因、备注
或其他 PII。

缺失／无效 Bearer 返回 `401 unauthenticated`；query 或 body 形状错误返回 `400
invalid_personal_relationship_stage_change_summary_request`；inactive identity、无 current
project、已归档 project、删除 workspace 或数据库 `42501` 返回 `403
personal_relationship_stage_change_summary_forbidden`；bridge、数据库或合同解析失败返回 `503
personal_relationship_stage_change_summary_unavailable`。服务器为成功和错误响应都设置
`Cache-Control: no-store`。Slice 6AE-1 只交付这条服务端入口；Slice 6AE-2 另以严格 Flutter
gateway 在个人最近七日页面显示结果，但仍不新增 Drift 表、离线历史同步或 Outbox。

## 个人后续联系同意占比

| 方法与路径 | 行为 |
| --- | --- |
| `GET /v1/personal/follow-up-consent-ratio?from_utc=...&until_utc=...` | 返回当前 personal project 在 UTC 半开期间内的固定 `follow_up_consent_ratio@1` 结果 |
| `GET /v1/personal/follow-up-consent-ratio/opt-in` | 返回当前 personal project 的可信启用状态和最新配置元数据 |
| `PUT /v1/personal/follow-up-consent-ratio/opt-in` | 用预期版本、boolean 启用值和 UUID 请求 ID 追加启用或停用版本 |

这个端点必须且只能收到一次 `from_utc` 和一次 `until_utc`。两者使用 UTC `Z` 时刻，可带一至九位小数秒。Backend 会截取到毫秒精度，并要求规范后的 `from_utc < until_utc`。GET body、偏移时区、重复／缺失／额外 query、客户端 project、workspace、user 或 metric 都会被拒绝。token 验证先于 query 校验；项目只来自已验证身份的当前 personal context。

Store 把 verified issuer／subject、当前 project、固定 metric 和期间交给 `read_personal_follow_up_consent_ratio_v1`。PostgreSQL 会重新授权。未配置或当前停用时，`result` 只有合同、metric、project 和 `status: not_enabled`；它没有 `period` 或 `value`。启用后，`status: ready` 才带期间、`yes / (yes + no)`、各缺失状态和整数百分比基点。Backend 对两种结果执行 exact-key 和计数不变量检查，不接受返回合同漂移。

配置 GET 不接受 query 或 body。配置 PUT 只接受 `expected_version`、`enabled` 和 `request_id`。
`expected_version` 必须在 PostgreSQL `integer` 的非负范围 `0..2147483647` 内；
不能提交用户、workspace、project、metric、actor 或 capability。未配置时返回 `not_enabled` 和
null configuration；当前停用时仍返回 `not_enabled`，但保留 `enabled: false` 的最新配置。Backend
严格验证数据库中的 actor ID，却不会把它发送给客户端。写入成功统一返回 `200`，因为底层合同
不能区分首次执行与幂等重放。

缺失或无效 token 返回 `401 unauthenticated`。比例请求无效时返回
`400 invalid_personal_follow_up_consent_ratio_request`；配置请求无效时返回
`400 invalid_personal_follow_up_consent_opt_in_request`。数据库重新授权失败分别返回对应的 `403`；
配置版本或幂等冲突返回 `409 personal_follow_up_consent_opt_in_conflict`。adapter 缺失、数据库错误
或返回合同无效返回对应的 `503 unavailable`。所有响应使用 `Cache-Control: no-store`，错误不含
identity、接触事实或 PostgreSQL 消息。这些入口不提供自由指标、管理报告、导出或 Flutter 离线缓存。

## 接触地点来源与同步错误边界

接触同步的 wire payload 使用 snake_case `location_source`。只有 `resolved` 地点可以带 `captured_coordinates` 来源。`resolved` 没有来源表示 `region-only`；`pending_resolution` 把坐标保留在地点本身；`not_applicable` 不带来源或坐标。提交、更正和冲突解决共用这个 exact-key codec；作废命令不接收新地点，只复制已经接受的 revision。

PostgreSQL `0039_contact_location_provenance.sql` 在接触 revision 的同一 transaction 中追加来源证据。`0039` fixture 覆盖坐标解析、region-only、pending、N/A、历史不完整、修订、冲突、作废和 warehouse 清理。来源表留在 `app_data`；management report、匿名结果、错误响应和 warehouse 不读取精确地点事实。Backend 当前没有应用日志 sink。部署平台的访问日志不得记录请求体或响应体。

Backend Store 只把 PostgreSQL `SQLSTATE 23514` 与 `0039` 中已知的固定错误文字配对。已知地点来源形状错误返回 `rejected`、`invalid_location_source`；已知地点形状错误返回 `rejected`、`invalid_location`。HTTP 响应为 `422`，批量结果也保持永久拒绝，不进入自动重试。响应只包含稳定错误码，不包含坐标。

未知的 `23514`、其他 PostgreSQL 错误或查询结果合同错误仍向 HTTP 层抛出，并返回 `503 sync_unavailable`。代码不能把任意数据库约束失败都当作客户端永久错误。这个窄映射由 Backend Store 单元测试和 Docker 中的真实 PostgreSQL 对账入口共同检查；它不等于生产数据库或真实设备验收。

## 规范区域解析合同

`POST /v1/regions/resolve` 接受 bearer token 与合法的 `latitude`、`longitude`。Backend 调用 `resolve_canonical_region_with_provenance`，只查询当前已发布的区域树版本。runtime 只能执行该窄函数，不能直接读取 release 表。

- 命中时返回 `200`、最小规范区域、父链、64 位小写 SHA-256 内容指纹和固定合同 `canonical-region-resolution:v1`；
- 没有命中时返回 `202` 和 `pending`；
- 坐标无效返回 `400 invalid_coordinates`；
- 身份无效返回 `401 unauthenticated`；
- 数据库或服务不可用返回 `503 region_resolution_unavailable`。

响应不回显 token、外部 subject、email 或输入坐标。Flutter 必须先验证指纹和合同，再原子安装返回的父链，并把原始坐标绑定到已解析状态。任何失败都保留原坐标，不能改写成 `N/A`。

同步命令里的 `location_source` 是可选对象。只有 `resolved` 地点可带 `captured_coordinates` 来源；来源必须含原始坐标、可选非负精度、同一固定合同和发布指纹。resolved 没有来源表示兼容的 region-only 记录。pending 的坐标保存在 `location`，`not_applicable` 和空草稿地点不带来源。submit、revise、resolve-conflict 和 draft 共用 exact-key codec；void 不接受地点或来源。

Slice 6U 已把来源写入 Flutter Drift／Outbox 和 PostgreSQL 接触来源表。Slice 6V 用共享 synthetic fixture 对账四层，并在 Docker 中运行真实 Backend→PostgreSQL 集成。该证据不等于生产环境、真实 GPS 或六平台真机验收。

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

无效 token 返回 `401`，无效 path／body 返回 `400`，无权返回 `403`，请求 UUID 跨项目冲突或项目未配置时区返回 `409`。Backend 检测到返回合同漂移或数据库异常时返回 `503`。6J 的 lineage、时区 revision 和重叠隐私阻断仍是已提交的 `blocked` 业务结果，使用 `200` 返回。`approved_baseline`、`approved` 与 `blocked` 都不含报告格、贡献者或授权证据。

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

## current 城市快照 HTTP 读取合同

6AR 使用独立路由读取 6AP 的 current-city protected snapshot：

```text
GET /v1/projects/:projectId/management-current-city-report-snapshots/:snapshotId
```

请求只接受两个 UUID path 参数。它不接受 query、GET body、筛选、报告定义、时区、截止点或 SQL。handler 先解析并
验证 Bearer token，再检查 UUID、query、body 和 store。认证失败时，其他输入即使无效，也先返回 `401`。handler 不调用
`SessionContext`，只把 verified issuer、subject、project ID 和 snapshot ID 传给 6AQ adapter。

成功响应如下：

```json
{
  "access_event_id": "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
  "snapshot_id": "88888888-8888-4888-8888-888888888888",
  "report": {}
}
```

`report` 是 6AP 的固定 current-city protected report。adapter 的 PostgreSQL Promise 解决后，handler 才发送响应。
错误只返回稳定 code。`404` 和 `409` 可以带 value-free `access_event_id`，不返回报告格、授权关系、external subject、
数据库消息、SQL 或栈：

| 结果 | HTTP 合同 |
| --- | --- |
| token 缺失或无效 | `401 unauthenticated` |
| UUID、query 或 GET body 无效 | `400 invalid_management_current_city_report_snapshot_request` |
| 6AP 重新授权拒绝 | `403 management_current_city_report_snapshot_forbidden` |
| 快照不存在或跨项目 | `404 management_current_city_report_snapshot_not_found` |
| provenance 不可信 | `409 management_current_city_report_snapshot_untrusted` |
| verifier、adapter、数据库或未知 SQLSTATE 异常 | `503 management_current_city_report_snapshot_unavailable` |

server 对成功和错误响应都设置 `Content-Type: application/json; charset=utf-8` 与 `Cache-Control: no-store`。`main.ts`
只组合 `PostgresManagementCurrentCityReportSnapshotStore`，因此该 route 不调用渠道快照 reader、通用 reader、私有表或
任意查询。该 route 不提供目录、导出、离线缓存、同步或 Flutter 页面。

### 6AR 的本地测试

在仓库根目录运行 Backend 测试：

```bash
cd backend/server
npm ci --ignore-scripts
npm run check
npm test
```

HTTP 测试使用 synthetic identity 和 store。它覆盖认证顺序、UUID／query／GET body 拒绝、401／400／403／404／409／503
映射、未知 SQLSTATE 脱敏、Promise gate、固定 route 和 `no-store`。带 body 的 GET 使用 `transfer-encoding` 发送，避免只
测试请求头而没有测试 route 的真实 body 判定。

`./tool/run_postgres_tests_in_docker.sh` 仍用于 0058／0059 的 PostgreSQL migration、fixture、adapter integration、并发、
checksum 和 dump／restore。它不会替代 Node HTTP 测试，也不证明生产身份、Flutter 或真实平台运行时。第一次使用时先
启动 Docker Desktop，再在仓库根目录运行该脚本。测试 runner 使用隔离容器和 synthetic 数据，完成后删除容器。

## current 城市快照目录合同

6AS 使用独立的 current-city provenance 目录，不调用 0035 渠道目录、6AP 单份读取或 `SessionContext`：

```text
GET /v1/projects/:projectId/management-current-city-report-snapshots
```

path 只接受一个显式项目 UUID。请求不能有 query、GET body、筛选、分页、报告 ID、时区、截止点、capability、内部用户
ID 或客户端 SQL。Backend 先解析并验证 Bearer token，再检查项目 UUID、请求形状和 directory store。无 token 或无效 token
时，即使项目 UUID、query、body 或 store 不合法，也先返回 `401 unauthenticated`。认证通过后只把 verified issuer、subject
和 project ID 交给 `PostgresManagementCurrentCityReportSnapshotDirectoryStore`。

store 只执行一次参数化查询：

```sql
SELECT app_data.list_authorized_management_current_city_report_snapshots_v1(
  $1::text, $2::text, $3::uuid
) AS directory_result
```

PostgreSQL 在同一事务重新检查 `view_anonymous_analytics`，只列出 0057 current-city release family 中通过 validator 的
`approved`／`approved_baseline` 快照。attempt 必须与 snapshot 的 project、固定
`contact_sessions_by_current_city_two_periods@1`、query fingerprint、release lineage、报告时区、data cutoff、previous
snapshot 和 target tree tuple 一致，且 `reason_codes = []`。legacy channel、blocked／unavailable、跨项目、claim 不匹配或
tuple 漂移的记录被排除。返回最多 20 项，排序为 `data_cutoff_utc`、`released_at_utc`、`snapshot_id` 降序。

成功响应只含 `access_event_id`、`project_id` 和 `snapshots`。每项只含 `snapshot_id`、`report_id`、`report_version`、
`reporting_time_zone`、`data_cutoff_utc` 和 `released_at_utc`。parser 要求 root 和 item 使用 exact keys、固定报告 ID／版本、
唯一 snapshot UUID、RFC 3339 时间戳、发布时间不早于 cutoff、最多 20 项和稳定排序。响应不含报告格、来源、贡献者、城市
名称、边界、坐标或 PII。

| 结果 | HTTP 合同 |
| --- | --- |
| token 缺失或无效 | `401 unauthenticated` |
| project UUID、query 或 GET body 无效 | `400 invalid_management_current_city_report_snapshot_directory_request` |
| 0060 重新授权拒绝 | `403 management_current_city_report_snapshot_directory_forbidden` |
| verifier、adapter、数据库、返回合同或未知 SQLSTATE 异常 | `503 management_current_city_report_snapshot_directory_unavailable` |

handler 等待 adapter 的 PostgreSQL Promise 完成后才写响应。成功和错误响应都设置 JSON `Content-Type` 与
`Cache-Control: no-store`。`main.ts` 只组合 0060 的 current-city directory store，不退回 0035 generic directory、6AP
snapshot reader、私有表或任意查询。第一项只是排序结果，不表示“当前”“最新有效”或“取代”。

### 如何验证 6AS

先验证 Backend 静态检查和单元／HTTP／route 测试：

```bash
cd backend/server
npm ci --ignore-scripts
npm run check
npm test
```

测试必须覆盖认证优先于 UUID、query、GET body 和 store；固定 collection route；401／400／403／503 稳定映射；未知
SQLSTATE 脱敏；单次 bridge query；strict metadata parser；重复或乱序目录失败；Promise gate；`transfer-encoding` GET body；
`no-store`；以及 production composition 只注入 0060 store。

首次使用 Docker 时，启动 Docker Desktop，然后回到仓库根目录运行：

```bash
./tool/run_postgres_tests_in_docker.sh
```

runner 创建隔离 PostgreSQL 容器，运行 0060 migration、check、fixture、并发、checksum 和 dump／restore，完成后删除容器。
它不连接 production，也不能替代上面的 Node HTTP 测试。若只修改 HTTP 文件，`npm run check` 与 `npm test` 是最小验证集；
涉及 0060 数据库合同时，再运行 Docker 套件。

本 Slice 不增加 Flutter、Drift、导航上下文、分页、搜索、筛选、导出、下载、缓存、离线、同步、快照创建／刷新／更正／删除、
retention、warehouse、区域发布或六平台真机证据。

## 管理兴趣快照 runtime bridge 合同

6AY 只提供 Backend runtime 对 0063 private read 的受控调用。它不是 HTTP route，也不负责 Bearer token 验证。adapter 接收已有的
`VerifiedIdentity`、显式 project UUID 和 snapshot UUID。

production bridge 的固定调用形状是：

```sql
SELECT app_data.read_authorized_management_interest_report_snapshot_v1(
  $1::text, $2::text, $3::uuid, $4::uuid
) AS access_result
```

bridge 用 exact `issuer + subject` 映射现有且 active 的 identity。它不 trim、bootstrap、读取 `SessionContext` 或接受内部用户、capability、
时区、截止点、期间、筛选和 SQL。bridge 使用 `SECURITY DEFINER` 与 `search_path = pg_catalog`，只调用
`app_private.read_authorized_management_interest_report_snapshot_v1(uuid, uuid, uuid)`。

runtime 只有 bridge `EXECUTE`。它没有 `app_private` schema usage，也不能执行 0063 private function 或读取用户、identity、snapshot、
provenance 和 audit 表。bridge owner 与 0063 private function owner 相同。0063 继续负责授权、interest provenance、6AV validator、撤权锁
和 value-free audit；bridge 不复制这些逻辑，也不追加第二条 audit。

adapter 只执行一次固定参数化 SQL。strict parser 检查 root keys、contract ID、请求和解析出的 snapshot、状态、reason code，以及 6AX 的十格
protected report。它只接受固定 cell 顺序、合法 count 和 `suppressed = null`，拒绝额外字段、PII、其他 report family 和错误 project。它只把
`42501` 映射为 typed `forbidden`；其他数据库错误继续向上抛出，后续 HTTP slice 再定义 wire mapping。

### 6AY 的本地测试

先运行 Backend 的无数据库合同测试：

```bash
cd backend/server
npm ci --ignore-scripts
npm run check
npm test
```

再从仓库根目录运行 PostgreSQL Docker 套件：

```bash
./tool/run_postgres_tests_in_docker.sh
```

runner 会自动发现 0064 migration、check 和 fixture，并显式运行兴趣快照 runtime integration。它还运行 0063 read/revoke 并发、checksum 和
dump／restore。恢复库只重跑 migration、check 和 fixture，不重跑会提交 synthetic 行的并发脚本。通过只证明 DB-only bridge、adapter parser 和
ACL，不证明 HTTP、Flutter、目录、导出、生产身份提供方或真实平台运行时。

## 管理兴趣快照 HTTP 读取合同

6AZ 把 6AY store 接到一个固定的 HTTP GET：

```text
GET /v1/projects/:projectId/management-interest-report-snapshots/:snapshotId
```

handler 先验证 Bearer token，再检查两个 UUID、query、GET body 和 store。认证失败时，其他输入即使无效，也先返回
`401 unauthenticated`。认证通过后，handler 只把 verified identity、显式 project UUID 和 snapshot UUID 传给 6AY store。
它不调用 `SessionContext`、通用 reader、current-city reader、private schema 或客户端 SQL。

成功响应包含 6AX protected report、`access_event_id` 和 `snapshot_id`。错误使用固定 code：
`400 invalid_management_interest_report_snapshot_request`、`403 management_interest_report_snapshot_forbidden`、
`404 management_interest_report_snapshot_not_found`、`409 management_interest_report_snapshot_untrusted` 和
`503 management_interest_report_snapshot_unavailable`。`404`／`409` 可以带 value-free `access_event_id`。所有响应使用
`Content-Type: application/json; charset=utf-8` 和 `Cache-Control: no-store`。错误不包含数据库消息、SQL、栈、external subject、授权关系、
报告格或 PII。

6AZ 不增加 PostgreSQL migration、check、fixture、并发脚本或新的 Docker 数据库合同。HTTP 测试使用 synthetic identity 和 fake 6AY store，
因此可以在没有数据库的情况下验证认证顺序、wire mapping、Promise gate 和 no-store。CI 仍运行既有 6AY PostgreSQL suite，以保持 runtime
bridge、ACL、parser 和 restore 证据。Docker 数据库测试不替代 HTTP 测试。

### 6AZ 的本地测试

从仓库根目录运行：

```bash
cd backend/server
npm ci --ignore-scripts
npm run check
npm test
```

测试覆盖 handler、固定 route、GET body／query 拒绝、401／400／403／404／409／503 映射、未知 SQLSTATE 脱敏、adapter Promise gate 和
production composition。涉及 6AY 数据库合同时，再运行：

```bash
cd ../..
./tool/run_postgres_tests_in_docker.sh
```

这条命令仍运行既有 6AY migration、check、fixture、integration、并发、checksum 和 dump／restore。6AZ 不新增数据库步骤，也不因此证明
Flutter、导出、缓存、离线、生产身份或真实平台运行时。

## 管理兴趣快照 metadata-only 目录合同

6BA 为 6AW interest snapshot 增加一个独立的 metadata-only directory。它不调用 0035 channel directory、0060 current-city directory、
6AX 单份读取或 6AY bridge。Backend 只把显式 project UUID 传给专用 interest directory store。

固定入口为：

```text
GET /v1/projects/:projectId/management-interest-report-snapshots
```

handler 先验证 Bearer token，再检查 project UUID、query、GET body 和 directory store。无 token 或无效 token 时，即使 project、query、body 或
store 不合法，也先返回 `401 unauthenticated`。认证通过后，handler 等待一次 directory adapter Promise，再发送响应。它不使用
`SessionContext`、通用 reader、current-city reader、6AX/6AY 单份读取、private schema 或客户端 SQL。

directory adapter 只调用一个固定的 runtime bridge：

```sql
SELECT app_data.list_authorized_management_interest_report_snapshots_v1(
  $1::text, $2::text, $3::uuid
) AS directory_result
```

PostgreSQL 重新确认 `view_anonymous_analytics` 和完整项目授权链，只列出 6AW interest release family 中 approved／approved_baseline、空
reason 且 project、report、version、query fingerprint、release lineage、报告时区、data cutoff、previous snapshot 和 source watermark
完全对齐的快照。channel、current-city、legacy、blocked、跨项目和 metadata drift 的记录被排除。结果最多 20 项，固定按
`data_cutoff_utc DESC`、`released_at_utc DESC`、`snapshot_id DESC` 排序。

响应根对象严格只含 `access_event_id`、`project_id` 和 `snapshots`。每个 item 严格只含 `snapshot_id`、`report_id`、`report_version`、
`reporting_time_zone`、`data_cutoff_utc` 和 `released_at_utc`。parser 拒绝额外字段、重复项、乱序项、非法 UUID／时间戳和超过 20 项。响应不含
protected report、cells、suppressed 前值、来源、贡献者或 PII。第一项只是排序结果，不表示 current、latest、最新有效或未被取代。

HTTP 错误使用稳定 code：

| 情况 | 状态和 code |
| --- | --- |
| token 缺失或验证失败 | `401 unauthenticated` |
| project UUID、query 或 GET body 无效 | `400 invalid_management_interest_report_snapshot_directory_request` |
| directory authorization forbidden | `403 management_interest_report_snapshot_directory_forbidden` |
| verifier、adapter、数据库、返回合同或未知 SQLSTATE 异常 | `503 management_interest_report_snapshot_directory_unavailable` |

被过滤的单个 snapshot 不产生 `404` 或 `409`。所有响应使用 `Content-Type: application/json; charset=utf-8` 和
`Cache-Control: no-store`。directory audit 与 6AX read audit 分离，追加且不可变，只保存最小授权 lineage、project、访问时间、结果和返回数量，
不保存 snapshot ID、metadata、protected report、cells、来源、贡献者或 PII。

### 6BA 的本地测试

先运行 Backend 的静态检查和无数据库合同测试：

```bash
cd backend/server
npm ci --ignore-scripts
npm run check
npm test
```

测试覆盖认证顺序、固定 collection route、GET body／query 拒绝、400／403／503 映射、未知 SQLSTATE 脱敏、一次 adapter Promise、strict
metadata parser、20 项上限、稳定排序和 `no-store`。production composition 必须注入专用 interest directory store。

涉及 0065 数据库合同时，从仓库根目录运行：

```bash
cd ../..
./tool/run_postgres_tests_in_docker.sh
```

runner 自动发现 0065 migration、check 和 fixture，并运行 interest directory integration、独立并发、checksum 和 dump／restore。恢复库重跑
migration、check 和 fixture，不重跑会提交 synthetic 行的并发脚本。integration 必须读取自己的 interest directory fixture，不得使用
`CURRENT_CITY_RUNTIME_FIXTURE`。上述证据只证明 DB、Backend 和 HTTP 合同，不证明 Flutter、导出、缓存、离线、生产身份或真实平台运行时。

## 原始区域快照 runtime bridge 合同

6BI 把 6BH 的 0069 private read 接到 Backend runtime。调用方必须先得到 Backend 验证的 `VerifiedIdentity`，并提供显式 project UUID 和 snapshot UUID。
它不是 HTTP route，也不负责 Bearer／JWT 验证。它不使用 `SessionContext`、通用 reader、current-city reader、interest reader 或客户端 SQL。

固定 bridge 调用形状为：

```sql
SELECT app_data.read_authorized_management_original_region_report_snapshot_v1(
  $1::text, $2::text, $3::uuid, $4::uuid
) AS access_result
```

bridge 用 exact `issuer + subject` 匹配现有且 active 的 identity。它不 trim、bootstrap、创建账号或个人上下文，也不接受内部用户 ID、capability、时区、
截止点、期间、source tree tuple、筛选和 SQL。bridge 使用 `SECURITY DEFINER` 与固定 `search_path = pg_catalog`，只调用
`app_private.read_authorized_management_original_region_report_snapshot_v1(uuid, uuid, uuid)`。runtime 只有 bridge `EXECUTE`，没有
`app_private` schema usage，不能读取用户、identity、snapshot、release attempt、request claim 或 audit 表。

adapter 只执行一次固定参数化 SQL。strict parser 检查 0069 的固定 root keys、请求和解析出的 snapshot、状态、reason code、project／snapshot 绑定，
以及 original-region report 的 17 个固定 keys。`completed` 还必须通过 selected source tree tuple、两个完整期间、连续 `cell_order`、安全整数和
`suppressed = null` 检查。parser 拒绝额外字段、其他 report family、城市名称、坐标、来源记录、贡献者、contact 和 PII；`not_found` 与
`untrusted_provenance` 不含 `protected_report`。它只把 SQLSTATE `42501` 映射为 typed `forbidden`，其他数据库错误继续作为内部错误向上抛出。

6BI 不增加 HTTP route、目录、latest、导出、Flutter、Drift、缓存、离线、同步、删除或 retention。0070 bridge 不复制 0069 的授权、6BD validator、
0068 provenance、撤权锁或 audit，也不追加第二条 audit。0069 已覆盖 private read 与 revoke 并发，本 Slice 不增加新的提交型并发脚本。

### 6BI 的本地测试

先运行 Backend 的静态检查和无数据库合同测试：

```bash
cd backend/server
npm ci --ignore-scripts
npm run check
npm test
```

再从仓库根目录运行 PostgreSQL Docker 套件：

```bash
cd ../..
./tool/run_postgres_tests_in_docker.sh
```

runner 自动发现 0070 migration、structural check 和 rollback fixture，并显式运行原始区域 runtime integration。它还运行 0069 read／revoke 并发、
checksum 和 dump／restore。恢复库只重跑 migration、check 和 fixture，不重跑会提交 synthetic 行的并发脚本。

如果只调试专用测试库，先确认 `DATABASE_URL` 不是 production，再运行 migration、0070 check 和 fixture。fixture 使用 synthetic identity 和快照，
不会连接真实 identity provider：

```bash
export DATABASE_URL='postgresql://postgres:postgres@127.0.0.1:5432/tongxingzhe_test'
./tool/postgres_migrate.sh
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/checks/verify_runtime_authorized_management_original_region_report_snapshot_read.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/fixtures/0070_runtime_authorized_management_original_region_report_snapshot_read.sql
```

通过只证明 DB-only bridge、Backend adapter parser 和最小 ACL。它不证明 HTTP、Flutter、目录、导出、生产身份或六平台真人运行时。

## 原始区域快照 HTTP 读取合同

6BJ 增加固定的 HTTP 详情入口：

```text
GET /v1/projects/:projectId/management-original-region-report-snapshots/:snapshotId
```

handler 先解析并验证 Bearer identity，再检查两个 UUID、query、GET body 的 `Content-Length`／`Transfer-Encoding` 声明和专用 store。缺少或无效
token 时，即使 path、query、body 或 store 不合法，也先返回 `401 unauthenticated`。认证通过后，handler 只向 6BI 的
`ManagementOriginalRegionReportSnapshotStore` 传递 verified identity、显式 project UUID 和 snapshot UUID，并等待它的 Promise 完成后才写响应。
它不使用 `SessionContext`、generic／current-city／interest store、`app_private` 或客户端 SQL。

成功响应固定为：

```json
{
  "access_event_id": "…",
  "snapshot_id": "…",
  "report": {}
}
```

错误状态和 code 固定为：

| 状态 | code |
| --- | --- |
| `400` | `invalid_management_original_region_report_snapshot_request` |
| `403` | `management_original_region_report_snapshot_forbidden` |
| `404` | `management_original_region_report_snapshot_not_found` |
| `409` | `management_original_region_report_snapshot_untrusted` |
| `503` | `management_original_region_report_snapshot_unavailable` |

`401` 使用 `unauthenticated`。`404`／`409` 可以带 value-free `access_event_id`。所有成功和错误响应使用
`Content-Type: application/json; charset=utf-8` 与 `Cache-Control: no-store`；不返回数据库消息、SQL、栈、external subject、授权关系、报告格、来源、贡献者、区域名称、坐标或 PII。

production composition 只注入 `PostgresManagementOriginalRegionReportSnapshotStore`，复用 6BI 的一次固定 bridge SQL。HTTP 层不复制 6BH／6BI 的授权、provenance、validator、撤权锁或 audit，也不增加 migration、database check、fixture、PostgreSQL integration 或并发脚本。HTTP 证据由 handler、route 和 composition 自动测试提供；既有 0069／0070 Docker 套件继续验证数据库合同，不替代这些 HTTP 测试。

### 6BJ 的本地测试

从仓库根目录进入 Backend 目录，安装依赖并运行检查：

```bash
cd backend/server
npm ci --ignore-scripts
npm run check
npm test
```

这些测试使用 synthetic identity 和 fake store，覆盖固定 method／path、认证先于 malformed UUID／query／GET body／store、六类状态映射、错误脱敏、Promise gate 和 `no-store`。不需要真实账号或 JWT provider。

如需同时确认既有数据库合同，再从仓库根目录运行：

```bash
cd ../..
./tool/run_postgres_tests_in_docker.sh
```

Docker 结果只证明 synthetic 0069／0070 PostgreSQL bridge、parser、授权和 ACL；它不证明 6BJ HTTP、Flutter、目录、导出、缓存、离线、生产身份或六平台真人运行时。

## 原始区域快照 metadata-only 目录合同

6BK 增加固定 collection route：

```text
GET /v1/projects/:projectId/management-original-region-report-snapshots
```

handler 先验证 Bearer identity，再检查 project UUID、query、GET body 的 `Content-Length`／`Transfer-Encoding` 声明和专用 directory store。认证失败先返回
`401 unauthenticated`。认证通过后只把 verified identity 和显式 project UUID 传给 original-region directory adapter，并等待 Promise 完成后写响应。
它不调用 6BJ detail store、generic、current-city、interest store、`SessionContext` 或 `app_private`。

成功 HTTP 根对象只有 `access_event_id`、`project_id` 和 `snapshots`。每项只有 `snapshot_id`、`report_id`、`report_version`、
`reporting_time_zone`、`data_cutoff_utc` 和 `released_at_utc`。最多 20 项，按 cutoff、release time 和 snapshot ID 固定降序；第一项不表示 current、
latest 或未被取代。空目录返回 `200` 和空数组。数据库内部 envelope 的 `access_contract_id` 不进入 HTTP。

错误固定为 `400 invalid_management_original_region_report_snapshot_directory_request`、`403 management_original_region_report_snapshot_directory_forbidden`
和 `503 management_original_region_report_snapshot_directory_unavailable`。所有结果使用 JSON 与 `Cache-Control: no-store`，不返回 protected report、cells、
source tuple、来源、贡献者、区域名称、坐标、PII、数据库消息、SQL 或栈。

### 6BK 的本地测试

从仓库根目录运行 Backend 检查：

```bash
cd backend/server
npm ci --ignore-scripts
npm run check
npm test
```

这些测试覆盖 strict parser、20 项上限、稳定排序、认证先于请求验证、Promise gate、固定 wire、错误脱敏、`no-store` 和 production composition。
要同时验证 0071 PostgreSQL 合同，再回到仓库根目录运行：

```bash
cd ../..
./tool/run_postgres_tests_in_docker.sh
```

Docker runner 自动发现 0071 migration、check 和 fixture，并运行专用 integration、并发、checksum 和 dump／restore。通过只证明 synthetic PostgreSQL、
runtime bridge 和 Backend HTTP 合同；它不证明 Flutter、导出、缓存、离线、生产身份或六平台真人运行时。

## 后续联系同意占比快照 runtime bridge 合同

6BS 增加 `PostgresManagementFollowUpConsentRatioReportSnapshotStore`。它接收已有 `VerifiedIdentity`、显式 project UUID 和 snapshot UUID，只执行一次固定 SQL：

```sql
SELECT app_data.read_authorized_management_follow_up_consent_report_snapshot_v1(
  $1::text, $2::text, $3::uuid, $4::uuid
) AS access_result
```

0077 bridge exact 匹配现有 active identity，再调用 0076 private reader。runtime 只有 bridge `EXECUTE`，不能执行 private reader 或读取 identity、snapshot、provenance 和 audit 表。授权、0075 provenance、6BQ validator、撤权锁和 value-free audit 仍由 0076 负责。

strict parser 只接受固定六字段 access envelope。`completed` 还必须包含 `contact_target_follow_up_consent_ratio_two_periods@1` 的 17 个顶层字段、相邻完整期间、两个 period result、ratio、三项 coverage、连续顺序、安全整数和 `suppressed = null`。额外字段、其他 report family、PII、contact、target、contributor、source 或隐藏前值都会使读取失败。`not_found` 和 `untrusted_provenance` 不得包含正文。

adapter 只将 SQLSTATE `42501` 映射为 typed `forbidden`。未知数据库错误和 parser 错误保持内部失败，不泄露数据库消息。6BS 本身不定义 HTTP route；
6BT 后续以独立的 HTTP handler 定义认证顺序、wire mapping 和 `Cache-Control`，不改变 6BS runtime／数据库边界。

### 6BS 的本地测试

```bash
cd backend/server
npm ci --ignore-scripts
npm run check
npm test
cd ../..
./tool/run_postgres_tests_in_docker.sh
```

前三条 Backend 命令验证 typed store 和 strict parser。Docker runner 还执行 0077 migration、check、fixture 和真实 PostgreSQL integration。

它也运行既有 0076 read／revoke 并发、checksum 和 dump／restore。通过只证明 synthetic runtime bridge 与 Backend adapter；6BS 当时不包含 HTTP，
后续 6BT 单独提供 HTTP 证据。上述结果不证明 Flutter、生产 identity provider、真实账号或真人平台。

## 后续联系同意占比快照 HTTP 读取

6BT 将 6BS 的专用 snapshot store 接到一个固定的只读详情入口：

```text
GET /v1/projects/:projectId/management-follow-up-consent-ratio-report-snapshots/:snapshotId
```

handler 在该固定 route 命中后先验证 Bearer identity，再检查 project／snapshot UUID、query、GET body 和专用 store。认证失败时，即使 UUID、
query、body 或 store 不合法，也先返回 `401 unauthenticated`。认证通过后只向
`PostgresManagementFollowUpConsentRatioReportSnapshotStore` 传递 verified `issuer + subject`、显式 project UUID 和 snapshot UUID；不调用
`SessionContext`、generic reader、其他 report-family store、`app_private` 或客户端 SQL。

GET 不接受 query 参数或 body。非零 `Content-Length` 或 `Transfer-Encoding` 等声明存在 body 时，同样返回 `400`。handler 等待 store 的 PostgreSQL
Promise 完成后才写响应，因此已提交的 value-free audit 不会因过早发送 HTTP 响应而失去顺序保证。

成功响应只有三个字段：

```json
{
  "access_event_id": "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
  "snapshot_id": "88888888-8888-4888-8888-888888888888",
  "report": {}
}
```

错误使用稳定 code：

| 状态 | code |
| --- | --- |
| `401` | `unauthenticated` |
| `400` | `invalid_management_follow_up_consent_ratio_report_snapshot_request` |
| `403` | `management_follow_up_consent_ratio_report_snapshot_forbidden` |
| `404` | `management_follow_up_consent_ratio_report_snapshot_not_found` |
| `409` | `management_follow_up_consent_ratio_report_snapshot_untrusted` |
| `503` | `management_follow_up_consent_ratio_report_snapshot_unavailable` |

`404`／`409` 可以带 6BS store 返回的 value-free `access_event_id`，但错误不得包含报告、数据库消息、SQL、栈、external subject、授权关系或
PII。所有成功和错误响应使用 `Content-Type: application/json; charset=utf-8` 与 `Cache-Control: no-store`。

6BT 的 production composition 只注入 6BS 专用 store。HTTP 层不复制 6BR／6BS 的授权、provenance、validator、撤权锁或 audit，也不增加
PostgreSQL migration、reader、directory、latest／current 选择、分页、筛选、Flutter、Drift、导出、缓存、离线、同步、replacement、删除、
retention、warehouse 或真人平台证据。新增 handler、route、real HTTP 和 composition 测试使用 synthetic identity 与 fake store；它们只证明
Backend HTTP transport contract，不证明 production identity provider、部署端点、真实账号或客户端消费。

### 6BT 的本地测试

```bash
cd backend/server
npm ci --ignore-scripts
npm run check
npm test
```

这些测试覆盖固定 method／path、认证先于 UUID／query／GET body／store、Promise gate、三字段 success wire、`401`／`400`／`403`／`404`／`409`／`503`、
错误脱敏和 `no-store`。若要同时执行既有 PostgreSQL 合同，从仓库根目录运行：

```bash
cd ../..
./tool/run_postgres_tests_in_docker.sh
```

Docker runner 仍验证 0077 bridge、0076 reader、授权、provenance、parser、audit、并发、checksum 和 restore；它不替代 6BT HTTP 测试。

## 后续联系同意占比快照目录 runtime bridge 合同

6BV 增加 `PostgresManagementFollowUpConsentRatioSnapshotDirectoryStore`。store 接收 Backend 已验证的 `VerifiedIdentity` 和显式 project UUID，只执行一次固定 SQL：

```sql
SELECT app_data.list_authorized_management_follow_up_consent_snapshots_v1(
  $1::text, $2::text, $3::uuid
) AS directory_result
```

0079 bridge 精确匹配已有 active external `issuer + subject`，再调用 0078 private directory。它不 trim、不 bootstrap、不创建 identity，也不接受内部用户 ID、
capability、时区、截止点、筛选或 SQL。runtime 只有 bridge `EXECUTE`，不能使用 `app_private` schema 或直接读取 identity、snapshot、attempt、claim、directory
和 audit 表。0078 继续负责组织／项目授权、0075 provenance、撤权锁、目录排序和 value-free audit。

strict parser 只接受四项 root envelope：`access_contract_id`、`access_event_id`、`project_id` 和 `snapshots`。每项只接受六个 metadata key：
`snapshot_id`、`report_id`、`report_version`、`reporting_time_zone`、`data_cutoff_utc` 和 `released_at_utc`。parser 检查 exact keys、consent-ratio report ID、
project 绑定、合法 UUID、规范 UTC 时间、最多 20 项、无重复和固定降序。额外字段、缺失字段、错误 contract、非 consent-ratio report、无效值和乱序结果失败关闭。
只有 SQLSTATE `42501` 映射为 typed `forbidden`；未知 SQLSTATE、数据库错误和 parser 错误不伪装成无权。

### 6BV 的本地测试

```bash
cd backend/server
npm ci --ignore-scripts
npm run check
npm test
cd ../..
./tool/run_postgres_tests_in_docker.sh
```

Backend 单元测试覆盖一次固定 SQL、参数传递、空目录、重复读取、严格 envelope／item parser、重复／超限／乱序和错误映射。Docker runner 自动发现
0079 migration、structural check 和 rollback fixture，运行 6BV PostgreSQL integration，并继续执行 0078 directory／revoke concurrency、checksum 和 dump／restore。
这些测试使用 synthetic identity 和 synthetic 数据，只证明 bridge、0078 delegation、adapter、parser 和 ACL。它们不证明 HTTP、Flutter、导出、缓存、离线、生产身份或六平台真人运行时。

## 后续联系同意占比快照目录 HTTP 合同

6BW 把 6BV 的 `PostgresManagementFollowUpConsentRatioSnapshotDirectoryStore` 接到一个固定的只读 collection route：

```text
GET /v1/projects/:projectId/management-follow-up-consent-ratio-report-snapshots
```

固定 path 命中后，handler 先验证 Bearer identity，再检查 project UUID、query、GET body 和该 dedicated store。GET 不接受 query 或 body；非零
`Content-Length`、`Transfer-Encoding` 等 body 声明返回 malformed request。认证失败始终先返回 `401 unauthenticated`，即使 path、query、body 或 store
不合法也不先暴露其他状态。认证通过后，handler 只把 verified identity 和显式 project UUID 传给 6BV store，并等待 store Promise 完成后才写响应。

成功 `200` 的 HTTP wire 只有 `access_event_id`、`project_id` 和 `snapshots`。每项只有六个 metadata 字段：`snapshot_id`、`report_id`、`report_version`、
`reporting_time_zone`、`data_cutoff_utc` 和 `released_at_utc`。授权 project 没有可列出的快照时仍返回 `200` 和空数组。第一项只是固定排序的第一项，
不表示 current、latest 或未被取代。

| 结果 | HTTP 合同 |
| --- | --- |
| token 缺失或验证失败 | `401 unauthenticated` |
| project UUID、query 或 GET body 无效 | `400 invalid_management_follow_up_consent_ratio_snapshot_directory_request` |
| 6BV directory authorization forbidden | `403 management_follow_up_consent_ratio_snapshot_directory_forbidden` |
| verifier、store、parser、数据库或未知错误 | `503 management_follow_up_consent_ratio_snapshot_directory_unavailable` |

collection 业务结果不使用详情读取的 `404` 或 `409`。它不把 unknown、cross-project 或 filtered snapshot 变成详情错误；其他 method 或未匹配 path 仍可由通用 server 返回
`404`。所有响应使用
`Content-Type: application/json; charset=utf-8` 和 `Cache-Control: no-store`，也不返回 protected report、period、ratio、coverage、source、contributor、
target、contact、external subject、数据库消息、SQL、栈或 PII。production composition 只注入该专用 store，不调用 `SessionContext`、generic 或 detail store。

### 6BW 的本地测试

```bash
cd backend/server
npm ci --ignore-scripts
npm run check
npm test
cd ../..
```

测试覆盖固定 GET path、auth-before-validation、query／GET body 拒绝、缺失或无效 Bearer、空目录、三字段 success wire、Promise gate、`403`／`503` 映射、
无业务 `404`／`409`、wrong method 的通用 `404` 和所有响应的 `no-store`。这些 synthetic HTTP 测试只证明 Backend transport contract 和 production wiring，不证明 PostgreSQL 授权、Flutter、
缓存、离线、部署服务、production identity 或 Android、iOS、macOS、Windows、Linux、Web 真人平台运行时。

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

测试使用临时 ES256 key 和 synthetic claims，不连接真实 Supabase 项目。身份 schema 见 [`0002_identity_context.sql`](../database/migrations/0002_identity_context.sql)，项目上下文见 [`0004_personal_project_contexts.sql`](../database/migrations/0004_personal_project_contexts.sql)，区域与私有草稿见 [`0005_regions_and_private_draft_sync.sql`](../database/migrations/0005_regions_and_private_draft_sync.sql)，个人指标见 [`0006_personal_contact_metrics.sql`](../database/migrations/0006_personal_contact_metrics.sql)，区域解析见 [`0007_canonical_region_resolution.sql`](../database/migrations/0007_canonical_region_resolution.sql)，独立接触尝试见 [`0008_contact_attempts.sql`](../database/migrations/0008_contact_attempts.sql)，接触更正与作废见 [`0009_contact_revisions.sql`](../database/migrations/0009_contact_revisions.sql)，修订冲突见 [`0010_contact_revision_conflicts.sql`](../database/migrations/0010_contact_revision_conflicts.sql)，版本化问卷执行见 [`0011_questionnaire_execution.sql`](../database/migrations/0011_questionnaire_execution.sql)，动态显示规则见 [`0012_questionnaire_visibility.sql`](../database/migrations/0012_questionnaire_visibility.sql)，管理草稿与不可变发布见 [`0013_questionnaire_publishing.sql`](../database/migrations/0013_questionnaire_publishing.sql)，旧草稿升级来源见 [`0014_questionnaire_draft_upgrades.sql`](../database/migrations/0014_questionnaire_draft_upgrades.sql)，问卷指标兼容见 [`0015_questionnaire_metric_compatibility.sql`](../database/migrations/0015_questionnaire_metric_compatibility.sql)，地点来源证据见 [`0039_contact_location_provenance.sql`](../database/migrations/0039_contact_location_provenance.sql) 和 [`0040_canonical_region_resolution_provenance.sql`](../database/migrations/0040_canonical_region_resolution_provenance.sql)，个人兴趣有序汇总见 [`0041_personal_interest_ordinal_summary.sql`](../database/migrations/0041_personal_interest_ordinal_summary.sql)，个人兴趣五档比例见 [`0042_personal_interest_level_ratios.sql`](../database/migrations/0042_personal_interest_level_ratios.sql)，个人兴趣 `3–4` 与 `0` 子集比例见 [`0043_personal_interest_subset_ratios.sql`](../database/migrations/0043_personal_interest_subset_ratios.sql)。CI 使用 synthetic fixture 验证权限、重放、并发、跨项目、同步、问卷、区域、cursor、地点来源证据、兴趣中位等级、五档比例、子集比例和 dump／restore。

对象反应分布的 PostgreSQL 入口见 [`0044_personal_target_response_distribution.sql`](../database/migrations/0044_personal_target_response_distribution.sql)。完整 Docker CI 使用 synthetic fixture 检查五档数量、已填写分母、未填写覆盖、current revision、个人 scope、UTC 半开边界、对象匿名化后事实保留和 dump／restore。

对象反应中位等级入口见 [`0045_personal_target_response_ordinal_summary.sql`](../database/migrations/0045_personal_target_response_ordinal_summary.sql)。它只使用已填的当前关联，偶数样本取较低真实等级，空分母返回 `NULL`。

对象反应五档比例入口见 [`0046_personal_target_response_level_ratios.sql`](../database/migrations/0046_personal_target_response_level_ratios.sql)。它返回 `target_response_level_ratios@1` 的五行结果，分母只包含当前已填的 contact-target link，`NULL` 关联只计入 `unanswered_count`，百分比基点按 half-up 规则计算。PostgreSQL bridge 重新核对个人 workspace、活动项目、current revision 和 UTC 半开区间，不读取对象 PII；个人 Flutter 页复用已有 Drift 五档汇总，不增加新的 Drift 查询。该入口不是管理报告或任意查询端点。

推广对象目录见 [`0016_promotion_target_directory.sql`](../database/migrations/0016_promotion_target_directory.sql)。对应 fixture 另外验证对象分配、PII 隔离、访问审计和恢复库权限。

接触对象关联见 [`0017_contact_target_links.sql`](../database/migrations/0017_contact_target_links.sql)。对应 fixture 验证零到多关联、阶段 0 确认、跨空间与未分配拒绝、机构代表约束、幂等重放、revision 历史、冲突比较和 warehouse PII 隔离。

Node 24 Docker 阶段会在已迁移的 PostgreSQL 上运行十三条 integration。它们覆盖地点来源、当前关系阶段、个人同意占比开关／读取、个人阶段变更汇总、current-city 快照读取／目录、兴趣快照读取／目录、original-region 快照读取／目录，以及后续联系同意占比快照 runtime 读取／目录读取。

地点来源测试和 Flutter 读取同一份 `contact_location_source_v1.csv`。其余测试分别对账窄 bridge、严格 parser、开关的版本／幂等合同、比例的 `not_enabled`／`ready` union，以及阶段变更汇总的 `5 / 4 / 3 / 2` 和空期间。SQL fixture 另证实匿名化历史，独立并发脚本证实项目锁边界。`npm test` 仍是无数据库的合同测试；它不能替代该阶段，也不能证明真机或生产环境。

个人阶段变更汇总的数据库入口和固定权限见
[`0051_personal_relationship_stage_change_summary.sql`](../database/migrations/0051_personal_relationship_stage_change_summary.sql)。
Backend Store 只传递已验证 issuer／subject 和规范化 UTC 期间，不传递 project ID。共享
[`relationship_stage_changes_v1.csv`](../database/fixtures/shared/relationship_stage_changes_v1.csv)
覆盖本人／他人、其他项目、期间边界、结束分配、匿名化保留边界、排除项、上升／下降、重复关系和
重复 revision。

数据库 check 用 `EXPLAIN` 固定 actor、project、changed-at 部分索引，避免无界历史扫描。
Slice 6AE-1 不包含 Flutter、Drift、页面或历史同步；6AE-2 只增加 Flutter gateway 和页面，
仍不增加 Drift 或历史同步。

项目关系审计见 [`0018_promotion_target_relationship_audit.sql`](../database/migrations/0018_promotion_target_relationship_audit.sql)。对应 fixture 验证双向阶段、独立生命周期、共享备注历史、结构化下降原因、mutation 重放、显式冲突、分配撤销、显示别名和 warehouse 文本隔离。

个人与机构历史关系见 [`0019_person_institution_relationships.sql`](../database/migrations/0019_person_institution_relationships.sql)。对应 fixture 和独立会话脚本验证六类性质、两端授权、同空间与异类型约束、不同性质并存、同种活动关系唯一、结束历史、重放、并发和 warehouse 隔离。

对象资料保留与匿名化见 [`0020_promotion_target_retention.sql`](../database/migrations/0020_promotion_target_retention.sql)。对应 fixture 和独立会话脚本验证十二个月上限、较短策略、通用复核任务、明确续期、到期清理、撤回、不可逆文本清除、接触事实保留、重放和并发。

私人周计划见 [`0021_personal_action_plans.sql`](../database/migrations/0021_personal_action_plans.sql)。对应 fixture 验证固定 IANA 时区、任意周起始日、夏令时周期、下一周期版本、重放、revision 冲突、跨用户拒绝和恢复库权限。

私人每日提醒见 [`0022_personal_action_reminders.sql`](../database/migrations/0022_personal_action_reminders.sql)。对应 fixture 验证提醒可独立创建、当地分钟边界、清除、幂等重放、revision 冲突、跨用户拒绝和恢复库权限。

管理报告快照的生产 bridge 见 [`0033_runtime_authorized_management_report_snapshot_read.sql`](../database/migrations/0033_runtime_authorized_management_report_snapshot_read.sql)。对应 fixture 验证既有身份映射、未知身份不 bootstrap、view/release 能力分离、跨项目隐藏、legacy provenance 和逐次访问审计。

管理分析导航上下文见 [`0034_management_analysis_contexts.sql`](../database/migrations/0034_management_analysis_contexts.sql)。对应 fixture 与独立会话脚本验证项目发现、完整选择证据、撤权失效、重新授予不复活、view/release 分离、未知身份不 bootstrap，以及选择与撤权的两种并发顺序。

管理报告快照目录见 [`0035_management_report_snapshot_directory.sql`](../database/migrations/0035_management_report_snapshot_directory.sql)。对应 fixture 与独立会话脚本验证可信 v2 来源、20 项上限、稳定降序、空目录审计、最小 runtime 权限，以及目录访问与撤权的两种并发顺序。

current 城市快照目录见 [`0060_authorized_management_current_city_report_snapshot_directory.sql`](../database/migrations/0060_authorized_management_current_city_report_snapshot_directory.sql)。对应 fixture、adapter、HTTP 和独立会话脚本验证 0057 current-city provenance、approved claim、20 项上限、稳定降序、空目录审计、strict metadata parser、最小 runtime 权限，以及目录访问与撤权的两种并发顺序。

管理兴趣快照 runtime bridge 见 [`0064_runtime_authorized_management_interest_report_snapshot_read.sql`](../database/migrations/0064_runtime_authorized_management_interest_report_snapshot_read.sql)。对应 fixture、adapter 和 integration 验证 exact identity、0063 private call、strict parser、最小 runtime 权限及 DB-only 证据边界；它不增加 HTTP route。

后续联系同意占比快照 runtime bridge 见 [`0077_runtime_authorized_management_follow_up_consent_ratio_snapshot_read.sql`](../database/migrations/0077_runtime_authorized_management_follow_up_consent_ratio_snapshot_read.sql)。对应 fixture、adapter 和 integration 验证 exact identity、0076 private call、strict consent-ratio parser、最小 runtime 权限及 synthetic 证据边界；6BS 当时不增加 HTTP route，当前 HTTP 详情由 6BT 的独立 handler 定义。

后续联系同意占比快照目录 runtime bridge 见 [`0079_runtime_authorized_management_follow_up_consent_ratio_snapshot_directory.sql`](../database/migrations/0079_runtime_authorized_management_follow_up_consent_ratio_snapshot_directory.sql)。对应 fixture、adapter 和 integration 验证 exact identity、0078 private directory delegation、四项 root envelope、六项 metadata、strict parser、最小 runtime 权限及 synthetic 证据边界；6BV 不增加 HTTP route，目录详情仍由后续独立 HTTP 合同定义。

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
