# 组织删除与恢复接入准备度

> 状态：Issue #350 的代码证据与实施地图；不是 ADR、接口规范或权限决定。查验范围截至 migration 0091。

## 结论

组织删除与恢复目前**不可执行**。已接受的产品结果是“删除申请生效后进入三十天可撤销只读期，期满完整清除”；但数据库只有 `workspaces.deleted_at`，没有删除申请、截止时间、恢复、终结清除或失败关闭状态，Backend 和 Flutter 也没有对应入口。

现有组织治理写入口已经具备受控 identity bridge、request claim、审计和一致的治理锁。后续实现应沿用这些边界。不能只增加一个 `deleted_at` 更新接口：它既不能表达三十天状态机，也不能证明所有组织业务写入已冻结。

当前存在一个已确认的接入约束：管理报告在恢复期应允许已有授权者读取，但共享报告授权和各 report family 的访问审计校验都要求 `workspace.deleted_at IS NULL`。若未来用非空 `deleted_at` 表示恢复期，现有报告目录和详情读取会被拒绝。这是后续状态设计必须解决的问题，不是已有恢复功能的运行时故障。

## 已接受的生命周期结果

- [ADR-0036](../adr/0036-delete-organizations-after-a-thirty-day-recovery-window.md)规定：删除申请生效后进入三十天可撤销只读期；期满清除组织拥有的成员关系、项目、推广对象、接触记录和分析数据，只保留不含业务内容的最小删除审计。
- [ADR-0035](../adr/0035-organizations-must-always-have-an-active-owner.md)规定：组织始终要有有效 owner；唯一 owner 必须先转让所有权或明确删除组织。失主恢复需要身份核验和完整审计。
- [ADR-0175](../adr/0175-organization-creation-is-atomic-with-first-active-owner.md)已允许多位 owner，但每个仍物理存在的组织必须保有至少一位当前 active owner。组织恢复期不结束 owner／membership，也不清除 claim 或 creation audit；唯一 owner 在此期间不能申请账号删除。这些已接受的约束不等于已经决定谁能申请组织删除或恢复。
- [ADR-0151](../adr/0151-management-report-retention-follows-organization-lifecycle.md)规定：恢复期内，仍获授权的成员可读取已有报告；不得发布、登记 replacement 或生成导出。恢复保留报告原状；期满清除全部 report family 及含业务内容的依赖，清除不完整时失败关闭。
- [ADR-0182](../adr/0182-organization-directory-is-membership-scoped.md)明确普通“我的组织”目录不显示恢复期组织。报告可读不等于恢复期组织应重新出现在普通目录。

## 当前可执行边界

[0002](../../backend/database/migrations/0002_identity_context.sql)中的 `app_data.workspaces` 只有可空的 `deleted_at`。它不能区分申请已提交、恢复截止时间、已恢复、等待清除、清除失败或已完成清除。[0085](../../backend/database/migrations/0085_organization_owner_invariant.sql)则已提供 `organization-governance:<workspace>` 锁，并通过 deferred constraint trigger 要求软删除组织仍保有 active owner，只有物理清除的 workspace 才退出该不变量。

以下两表分别覆盖组织治理 API 和当前 workspace-scoped 业务写家族。全局 canonical region tree 不属于单个组织，本报告不盘点它；联系人写入触发的 region provenance 仍计入联系人家族。

### 组织治理入口

| 家族 | Runtime 可调用面 | 当前 active SQL 与锁序 | 恢复期接入含义 |
| --- | --- | --- | --- |
| 创建组织 | Backend [organization-creation.ts](../../backend/server/src/organization-creation.ts) 调用 `app_data.create_organization_for_identity_v1` | private writer 和 bridge 都在 [0084](../../backend/database/migrations/0084_organization_creation.sql)。顺序是 creation request → actor row → 新 organization governance → membership key | 恢复期不会创建既有组织；终结清除仍须纳入该组织的 creation claim 和 audit |
| owner 转让 | Backend [organization-owner-transfer.ts](../../backend/server/src/organization-owner-transfer.ts) 调用 [0086](../../backend/database/migrations/0086_organization_owner_transfer.sql)的 identity bridge | private writer 的最新定义是 [0088](../../backend/database/migrations/0088_organization_owner_transfer_authorization_time.sql)的 `CREATE OR REPLACE app_private.transfer_organization_owner_v1`，不是 0086 初版。顺序是 request → 排序 user rows → 排序 governance → 排序 membership；锁后用 `clock_timestamp()` 重授权 | 首次执行须冻结；若保留现有合同，成功 claim 的 exact replay 只能读取既有 receipt |
| 定向邀请创建／接受 | Backend [organization-directed-account-invitations.ts](../../backend/server/src/organization-directed-account-invitations.ts) 调用两个 identity bridge | private writers、bridges 和 ACL 均在 [0087](../../backend/database/migrations/0087_organization_directed_account_invitation.sql)。顺序是 request → 排序 user rows → governance → 排序 membership | 新邀请和首次接受须冻结；已接受 claim 的 exact target replay 当前先于 recovery 检查 |
| 成员自行退出 | Backend [organization-membership-self-leave.ts](../../backend/server/src/organization-membership-self-leave.ts) 调用 identity bridge | private writer 和 bridge 在 [0090](../../backend/database/migrations/0090_organization_membership_self_leave.sql)。顺序是 request → actor row → governance → membership key | 首次退出须冻结；终结清除须纳入 self-leave claim family |
| 我的组织目录 | Backend [organization-directory.ts](../../backend/server/src/organization-directory.ts) 调用 `app_data.list_organizations_for_identity_v1` | [0089](../../backend/database/migrations/0089_organization_directory.sql)是只读函数，无 advisory lock，并过滤 `deleted_at IS NULL` | 按 ADR-0182 保持排除恢复期组织；它不是恢复入口 |
| 邀请预览 | 同一 invitation Backend store 调用 preview bridge | [0091](../../backend/database/migrations/0091_organization_directed_account_invitation_preview.sql)是只读 observation，无 writer 或 advisory lock，并过滤 `deleted_at IS NULL` | 恢复期继续 forbidden；不能借预览暴露组织状态 |

这些 migration 都从 `PUBLIC, tongxingzhe_runtime` 撤销 private writer 权限。Runtime 只获得 `app_data.*_for_identity_v1` bridge 或 reader 的 `EXECUTE`；bridge 精确解析可信 issuer／subject 后再调用 private writer。新的删除申请和恢复入口应复用该权限形状，不能把 private lifecycle writer 直接授予 runtime。[postgres_migrate.sh](../../tool/postgres_migrate.sh)按文件名顺序执行，因此判断当前定义时必须考虑后续 `CREATE OR REPLACE`。

[server.ts](../../backend/server/src/server.ts)当前注册创建、转让、邀请、退组和目录路由；migration 0091 以前没有组织删除、恢复或终结清除函数。对应的 request claim、deadline、最小 lifecycle audit、受控 bridge、Backend store／route、Flutter gateway／UI、purge worker 和 lifecycle 测试也不存在。

### 组织业务写入口

“无组织写入口”表示当前 runtime 函数把范围限定为 personal workspace，或只存在未授予 runtime 的 private 函数；不表示底表中不可能存在 fixture、历史或管理员写入的数据。

| 家族 | 实际可调用面与最新定义 | 当前锁／workspace 门禁 | 恢复期准备度 |
| --- | --- | --- | --- |
| sync draft／contact／revision／void／attempt；target link 中的 consent／follow-up facts | Backend [sync-store.ts](../../backend/server/src/sync-store.ts)选择 [0017](../../backend/database/migrations/0017_contact_target_links.sql)的 submit／revise／resolve／void／draft-upsert v3、[0008](../../backend/database/migrations/0008_contact_attempts.sql)的 attempt 和 [0005](../../backend/database/migrations/0005_regions_and_private_draft_sync.sql)的 draft-delete。v3 委托 [0011](../../backend/database/migrations/0011_questionnaire_execution.sql) v2。它们都是 runtime `app_data` 函数；旧 overload／v2 的来源 grant 也未被 0017 撤销 | command request lock 后取 draft 或 contact lock／row lock；授权要求 active **personal** owner、active project 和 `deleted_at IS NULL`，不取 organization-governance | 当前不能写组织数据。后续若开放组织同步，必须先接生命周期门禁；不能只检查 Backend 当前选择的 v3 |
| 推广对象 PII、分配、阶段／共享 follow-up note、机构关系 | Runtime 直接执行 [0016](../../backend/database/migrations/0016_promotion_target_directory.sql)的 `create_promotion_target`、[0018](../../backend/database/migrations/0018_promotion_target_relationship_audit.sql)的 relationship／alias writers、[0019](../../backend/database/migrations/0019_person_institution_relationships.sql)的 institution writers | 复用 `promotion_target_context_authorized`，只允许 active personal owner；另取 request、target、relationship 等局部锁，不取 organization-governance | 当前无组织写入口。未来开放前统一接生命周期门禁，不把 PII writer 遗漏在治理路由之外 |
| 问卷 draft／publish 与 metric compatibility | Runtime 直接执行 [0013](../../backend/database/migrations/0013_questionnaire_publishing.sql)和 [0015](../../backend/database/migrations/0015_questionnaire_metric_compatibility.sql)的 `app_data` writers | `questionnaire_management_authorized`只接受 personal workspace；publish 取 project 锁，compatibility 取 metric 锁，不取 organization-governance | 当前无组织 questionnaire writer。恢复期冻结矩阵不应虚构该能力；未来组织问卷另接门禁 |
| project、membership、capability、reporting time zone | 组织 project 创建／状态、project membership 和 capability grant 没有 runtime writer；[0030](../../backend/database/migrations/0030_management_report_authorization.sql)只有底表 validator／授权 resolver。[0029](../../backend/database/migrations/0029_project_reporting_time_zone.sql)只有 private `configure_project_reporting_time_zone_v1`，未授予 runtime | capability validator 取 organization-membership → project-membership → capability 锁；time-zone writer 取 request → project-time-zone 锁并只检查 active organization workspace。两者都不取 organization-governance | 不能把“无公开 API”当作冻结。private 初始化／运维路径也要在 lifecycle 锁后拒绝恢复期新写入 |
| follow-up consent 配置 | Personal metric 的 [0048](../../backend/database/migrations/0048_project_follow_up_consent_opt_in.sql) bridge 可由 runtime 调用，但只允许 personal owner。Organization management 配置只存在 [0073](../../backend/database/migrations/0073_management_follow_up_consent_opt_in.sql) private writer，没有 runtime bridge／Backend route | personal 路径取 request → project opt-in 锁；management 路径取 report authorization → request → project opt-in 锁并重授权。均不取 organization-governance | Organization private writer 已用 `deleted_at IS NULL` 间接拒绝，但仍缺少与 lifecycle writer 串行化的治理锁 |
| 管理分析当前上下文 | [0034](../../backend/database/migrations/0034_management_analysis_contexts.sql)的 runtime `app_data.select_management_analysis_context_v1` 由 Backend [management-analysis-contexts.ts](../../backend/server/src/management-analysis-contexts.ts)调用；它更新按 app user 保存的导航偏好，不是组织业务正文 | 通过共享 report authorization 取得 membership／capability 锁，写入后再次列目录；不取 organization-governance，并要求 `deleted_at IS NULL` | 它目前不能支持恢复期报告导航。后续需明确是允许该读取辅助写入，还是使用不持久化的恢复期 selector |
| report release | Channel 的 runtime bridge 是 [0036](../../backend/database/migrations/0036_runtime_trusted_management_report_release.sql)，调用 [0031](../../backend/database/migrations/0031_trusted_management_report_release.sql)的 private `release_management_report_snapshot_v2`。Current-city／interest／original-region／follow-up-consent-ratio 只存在 [0057](../../backend/database/migrations/0057_management_current_city_report_snapshot_lineage.sql)、[0062](../../backend/database/migrations/0062_management_interest_report_snapshot_lineage.sql)、[0068](../../backend/database/migrations/0068_management_original_region_report_snapshot_lineage.sql)、[0075](../../backend/database/migrations/0075_management_follow_up_consent_ratio_snapshot_lineage.sql)的 private release writers，没有 runtime bridge | 共享 authorization 取 organization-membership → project-membership → capability 锁；channel 再取 release request → project-time-zone → lineage 锁。没有 organization-governance | 恢复期必须禁止所有 family 新发布。仅靠 `deleted_at` 检查会留下与 lifecycle 状态切换并发的窗口 |
| replacement／export | 五个 family 的 replacement writers 在 [0067](../../backend/database/migrations/0067_management_report_snapshot_replacements.sql)、[0072](../../backend/database/migrations/0072_management_original_region_report_snapshot_replacements.sql)、[0080](../../backend/database/migrations/0080_management_current_city_report_snapshot_replacements.sql)、[0082](../../backend/database/migrations/0082_management_interest_report_snapshot_replacements.sql)、[0083](../../backend/database/migrations/0083_management_follow_up_consent_ratio_snapshot_replacements.sql)，均为 private，无 runtime bridge。只有 channel export 通过 [0052](../../backend/database/migrations/0052_management_report_snapshot_export.sql) `app_data` bridge 开放给 runtime | replacement 取 authorization → request → lineage 锁；export 取 view／export capability 锁并写 audit。都不取 organization-governance | 恢复期禁止 replacement 和新 export；现有 ACL 差异要求同时覆盖 runtime 与 private 路径 |
| deidentified location anomaly | [0081](../../backend/database/migrations/0081_authorized_management_deidentified_location_anomaly_read.sql)只有 private directory／detail readers 和 provenance-triggered ID capture，没有 runtime bridge、Backend route或 resolve／mutation writer | reader 取 authorization 锁，detail 另取 contact 锁，并追加 access audit；要求 `deleted_at IS NULL`，不取 organization-governance | 它不是 ADR-0151 的已有报告读取例外。恢复期应失败关闭，除非后续另有明确产品决定 |

表中通过函数执行的 organization writer 大多依赖 `deleted_at IS NULL`，但没有一个取得 0085 的 organization-governance 锁；capability grant validator 甚至不重查 workspace lifecycle。若 lifecycle writer 只在 governance lock 下改变状态，旧 writer 可能在状态切换前通过检查，并在恢复期开始后提交。实现只读期时必须为这些 private／runtime 路径定义统一锁序，并在最后一个可能等待的锁后重读 lifecycle；仅在入口前查询状态不足以关闭竞态。

## 恢复期报告读取冲突

当前五个已发布 report family 是 channel、current-city、interest、original-region 和 follow-up-consent-ratio。它们的目录与详情通过 runtime `app_data` bridge 调用 private reader，并在读取时写入 access event。

- 最新共享授权函数是 [0081](../../backend/database/migrations/0081_authorized_management_deidentified_location_anomaly_read.sql)重定义的 `app_private.resolve_management_report_authorization_v1`。它同时检查 active account、organization membership、project membership 和 capability，并要求 `workspace.deleted_at IS NULL`。
- channel 的详情访问审计校验见 [0032](../../backend/database/migrations/0032_authorized_management_report_snapshot_read.sql)，目录校验见 [0035](../../backend/database/migrations/0035_management_report_snapshot_directory.sql)。两者都再次要求 `deleted_at IS NULL`。
- 其他四个 family 在 [0058](../../backend/database/migrations/0058_authorized_management_current_city_report_snapshot_read.sql)、[0063](../../backend/database/migrations/0063_authorized_management_interest_report_snapshot_read.sql)、[0069](../../backend/database/migrations/0069_authorized_management_original_region_report_snapshot_read.sql)、[0076](../../backend/database/migrations/0076_authorized_management_follow_up_consent_ratio_snapshot_read.sql)及其目录 migration 0060／0065／0071／0078 中重复同一条件。
- [0034](../../backend/database/migrations/0034_management_analysis_contexts.sql)的管理分析上下文也排除 `deleted_at` 非空的 workspace。即使详情 reader 放行，普通 UI 仍缺少发现恢复期组织及其项目的路径。
- [0052](../../backend/database/migrations/0052_management_report_snapshot_export.sql)的导出授权也依赖共享 resolver。不能把 resolver 对所有 capability 一次性放宽，否则可能把恢复期禁止的 export、release 或 replacement 一并放开。

因此，接入门禁必须按操作分类，而不能把“读”简化为 SQL `SELECT`：报告目录和详情读取会追加 access audit，这是允许读取所需的受控副作用；发布、replacement、导出和其他业务写入仍须拒绝。ADR-0151 要求终结清除含业务标识的读取、目录和导出审计，所以这些 access event 不能被误当成最终可保留的最小删除审计。

普通组织目录继续隐藏恢复期组织时，还需独立、窄化的恢复入口或恢复期报告导航。它应只返回执行已确认操作所需的数据，不能把 owner、成员、项目或 capability 状态扩展进现有目录合同。

## 建议的后续切片

以下顺序是实施建议，不是已接受合同。任何 runtime 删除入口都应等到写冻结和报告读取例外同时就绪后再开放。

1. **冻结产品决定。** 明确谁可申请、谁可恢复、三十天的时间基准、重复请求语义、恢复期可见性和稳定错误；形成 ADR 与 Product Spec 合同。
2. **只建内部生命周期核心。** 增加可区分状态的 schema、数据库生成的生效／截止时间、request claim、不可变且不含业务内容的 lifecycle audit，以及 request → actor → governance → row／membership 的锁后重验。先不授予 runtime。
3. **建立操作矩阵并接入门禁。** 逐类验证所有 workspace writer；冻结首次治理和业务写入，保留已完成 claim 的只读 replay。只对既有报告目录／详情及其 access audit 放行，不放行生成、发布、replacement、导出或 anomaly 工作流。
4. **交付 request／restore transport。** 增加 exact identity bridge、Backend store／route、固定 receipt 和错误映射；补恢复期组织与报告的窄化发现路径。DB 与 HTTP 并发测试通过后再接 Flutter。
5. **交付终结清除。** 按稳定 family／request UUID 顺序收集并加锁，治理锁后重读 lifecycle 和 claim 集合；在单一受控流程中清除全部依赖。出现未覆盖依赖或删除失败时保持不可访问，不把 tombstone 当成物理清除证据。
6. **分层证明。** 覆盖申请、恢复、期满、边界时刻、重复／漂移请求、并发治理写、五个 report family、失败回滚、最小审计、dump／restore。生产备份重放、RPO／RTO 和删除数据不再出现，需要单独的部署证据。

## 待决定问题

- 删除申请与期限内恢复是否允许当前任一有效 owner 发起？现有模型允许多 owner；是否需要共同确认，以及失主恢复和平台介入的权限，不能由实现自行猜测。
- “三十天”是连续 720 小时，还是某时区的三十个日历日？起点应是数据库确认生效的时间，而不是客户端时间；精确定义仍待决定。
- 普通目录隐藏恢复期组织时，谁能看见恢复提示、通过什么 selector 找回组织及可读报告？该入口是否只服务可恢复主体，仍待权限决定。
- 恢复、重复申请、已过截止时间、清除进行中和清除失败分别返回什么稳定结果？这些状态不能继续压在一个 `deleted_at` 上。
- 生产备份保留、删除事实重放、RPO 和 RTO 由部署评审决定。本地 Docker、fixture、dump／restore 只能证明 synthetic 数据库行为。

## 证据边界

本报告基于仓库中的 ADR、migration、Backend route／store 和静态 ACL 查验。未连接生产数据库，未执行 lifecycle SQL，也未证明部署、真实身份、物理清除或备份清除。旧版 [current-code-gap-audit.md](./current-code-gap-audit.md)仅作历史记录，不作为当前事实依据。
