# 架构决策索引

本目录记录已经影响产品合同、数据边界或发布风险的决定。领域词语以 [`CONTEXT.md`](../../CONTEXT.md) 为准，完整需求和 Slice 以 [`PRODUCT_SPEC.md`](../PRODUCT_SPEC.md) 为准。

## 状态规则

- ADR-0001 至 ADR-0095 作为 `TXZ-SPEC-001` 的首批决策集，于 2026-07-31 一并接受；文件另有状态时以文件为准。
- ADR-0096、ADR-0097 于 2026-07-31 接受；ADR-0098、ADR-0099 于 2026-08-03 接受；ADR-0100 于 2026-08-05 接受；ADR-0101、ADR-0102 于 2026-08-10 接受；ADR-0103 至 ADR-0108 于 2026-08-11 接受；ADR-0109 至 ADR-0119 于 2026-08-12 接受；ADR-0120 至 ADR-0129 于 2026-08-13 接受；ADR-0130 于 2026-08-13 接受。
- 被取代的 ADR 保留原文和指向新 ADR 的状态，不再作为当前实现合同。
- 新 ADR 默认只需一个清楚的决定段落。只有背景、备选和后果能帮助未来维护者避免误读时，才增加这些章节。
- 可逆的 UI 细节、库选择和票内实现步骤留在 Spec 或 Issue，不为增加编号而创建 ADR。

## 当前状态与取代关系

| ADR | 状态 | Slice／Requirement | 说明 |
| --- | --- | --- | --- |
| [0022](./0022-offline-first-contact-recording-with-an-outbox.md) | 已接受，2026-07-31 | Slice 1–2；`ARCH-001`、`ARCH-007`、`TEST-001`、`TEST-003` | 离线事实和 Outbox 总原则；运行状态由 ADR-0098 细化 |
| [0025](./0025-use-firebase-authentication-for-production-identity.md) | 已被 ADR-0096 取代 | Slice 0；`AUTH-004`–`AUTH-008` | 保留认证决策历史 |
| [0067](./0067-anonymous-analytics-prevent-differencing-without-noise.md) | 已被 ADR-0099 取代 | Slice 6；`PRIVACY-001`–`PRIVACY-011` | 原“防相减”表述不再是当前保证 |
| [0096](./0096-use-supabase-auth-with-cognito-fallback.md) | 已接受，2026-07-31 | Slice 0／发布门槛；`AUTH-004`–`AUTH-008` | Supabase Auth 首选，Cognito 后备 |
| [0097](./0097-use-supabase-postgresql-for-the-initial-stage.md) | 已接受，2026-07-31 | Slice 0／发布门槛；`ARCH-003`–`ARCH-010` | 首阶段数据库与发布前复审 |
| [0098](./0098-persistent-outbox-uses-claim-lease-and-ack.md) | 已接受，2026-08-03 | Slice 1–2；`ARCH-001`、`ARCH-007`、`TEST-001`、`TEST-003` | Outbox 领取、租约、ACK、退避和健康状态 |
| [0099](./0099-management-analytics-use-bounded-query-surfaces.md) | 已接受，2026-08-03 | Slice 6；`ANALYTICS-007`–`ANALYTICS-014`、`PRIVACY-001`–`PRIVACY-011` | 固定报告形状和披露风险边界 |
| [0100](./0100-pull-cursor-advances-only-after-local-batch-apply.md) | 已接受，2026-08-05 | Slice 1–2；`ARCH-001`、`ARCH-007`、`TEST-003` | push ACK cursor 与 pull cursor 分离，整批落盘后才推进 |
| [0101](./0101-management-weekly-reports-use-two-complete-iso-weeks.md) | 已接受，2026-08-10 | Slice 6；`ANALYTICS-001`、`ANALYTICS-004`、`ANALYTICS-007`、`ANALYTICS-012` | 固定管理周报使用两个完整 ISO 周 |
| [0102](./0102-project-reporting-time-zone-changes-use-the-old-zone-boundary.md) | 已接受，2026-08-10 | Slice 6H；`ANALYTICS-001`、`ANALYTICS-004`、`ANALYTICS-012` | 报告时区变更由旧时区结束当前周期 |
| [0103](./0103-management-analysis-view-and-report-release-use-separate-capabilities.md) | 已接受，2026-08-11 | Slice 6I；`AUTHZ-001`–`AUTHZ-006`、`PRIVACY-001`–`PRIVACY-011` | 管理分析查看和报告发布使用独立项目能力 |
| [0104](./0104-trusted-report-release-binds-authorization-and-time-zone-revision.md) | 已接受，2026-08-11 | Slice 6J；`AUTHZ-001`–`AUTHZ-006`、`ANALYTICS-007`–`ANALYTICS-014`、`PRIVACY-001`–`PRIVACY-011` | 可信发布在全部锁后绑定授权与时区 revision，跨 revision 失败关闭 |
| [0105](./0105-authorized-snapshot-reads-require-trusted-provenance-and-minimal-audit.md) | 已接受，2026-08-11 | Slice 6K；`AUTHZ-001`–`AUTHZ-006`、`ANALYTICS-007`–`ANALYTICS-014`、`PRIVACY-001`–`PRIVACY-011` | 授权读取只接受可信 v2 快照，并在同一事务中追加不含报告格的访问审计 |
| [0106](./0106-management-snapshot-http-reads-use-an-explicit-project-and-one-statement-bridge.md) | 已接受，2026-08-11 | Slice 6L；`ARCH-002`、`AUTHZ-001`–`AUTHZ-006`、`ANALYTICS-007`–`ANALYTICS-014` | HTTPS 读取使用显式项目和唯一 runtime bridge，数据库提交后才交付报告 |
| [0107](./0107-management-navigation-context-binds-exact-authorization-evidence.md) | 已接受，2026-08-11 | Slice 6M；`AUTHZ-001`–`AUTHZ-006`、`CTX-001`–`CTX-006` | 管理分析导航与个人上下文分离，并绑定选择时的完整授权证据 |
| [0108](./0108-management-report-snapshot-directory-is-bounded-and-reauthorized.md) | 已接受，2026-08-11 | Slice 6N；`AUTHZ-001`–`AUTHZ-006`、`ANALYTICS-007`–`ANALYTICS-014`、`PRIVACY-001`–`PRIVACY-011` | 快照目录固定上限和排序，每次访问重新授权并追加最小审计 |
| [0109](./0109-management-report-http-release-fixes-the-report-and-uses-one-statement.md) | 已接受，2026-08-12 | Slice 6P；`ARCH-002`、`AUTHZ-001`–`AUTHZ-006`、`ANALYTICS-007`–`ANALYTICS-014` | HTTP 发布固定报告定义，并通过唯一 runtime bridge 在提交后返回最小结果 |
| [0110](./0110-region-analytics-requires-provenance-before-production-reports.md) | 已接受，2026-08-12 | Slice 6Q；`REGION-005`–`REGION-009`、`PRIVACY-002`–`PRIVACY-006`、`PRIVACY-010` | 区域分析先固定来源语义和重叠威胁探针；证据不足时不猜测当前区域 |
| [0111](./0111-freeze-published-canonical-region-tree-releases.md) | 已接受，2026-08-12 | Slice 6R；`REGION-005`–`REGION-009`、`ARCH-004`、`ARCH-006`、`ARCH-010`、`PRIVACY-010`、`TEST-003`、`TEST-005` | 草稿发布后冻结区域节点和边界；内容指纹稳定，current 切换保留追加式选择历史 |
| [0112](./0112-contact-location-provenance-is-append-only-revision-evidence.md) | 已接受，2026-08-12 | Slice 6S；`CONTACT-010`、`REGION-001`、`REGION-002`、`REGION-005`、`REGION-007`–`REGION-009`、`ARCH-004`、`ARCH-006`–`ARCH-008`、`ARCH-010`、`AUTHZ-004`、`AUTHZ-006`、`PRIVACY-007`、`PRIVACY-010`、`PRIVACY-011`、`MIGRATION-001`–`MIGRATION-005`、`TEST-003`、`TEST-005` | 接触地点来源按 revision 追加保存；明确 pending／N/A、resolved region-only、历史回填和精确坐标边界 |
| [0113](./0113-location-source-wire-contract-binds-resolution-provenance.md) | 已接受，2026-08-12 | Slice 6T；`REGION-001`、`REGION-002`、`REGION-005`、`REGION-007`–`REGION-009`、`ARCH-004`、`ARCH-006`–`ARCH-008`、`ARCH-010`、`PRIVACY-007`、`PRIVACY-010`、`PRIVACY-011`、`TEST-003`、`TEST-005` | 严格位置来源 wire 合同把原始坐标绑定到已发布区域树指纹；缺少可信证据时保留 pending |
| [0114](./0114-device-location-source-is-an-atomic-typed-fact.md) | 已接受，2026-08-12 | Slice 6U；`REGION-001`、`REGION-002`、`REGION-005`、`REGION-007`–`REGION-009`、`ARCH-001`、`ARCH-004`、`ARCH-006`–`ARCH-008`、`ARCH-010`、`PRIVACY-007`、`PRIVACY-010`、`PRIVACY-011`、`MIGRATION-001`–`MIGRATION-005`、`TEST-003`、`TEST-005` | Drift v18 类型化保存来源；地点和来源在设备存储、队列、pull 与冲突中原子替换 |
| [0115](./0115-location-source-four-layer-evidence.md) | 已接受，2026-08-12 | Slice 6V；`REGION-001`、`REGION-002`、`REGION-005`、`REGION-007`–`REGION-009`、`ARCH-004`、`ARCH-006`–`ARCH-008`、`PRIVACY-007`、`PRIVACY-010`、`PRIVACY-011`、`TEST-003`、`TEST-005` | 共享合成证据对账设备、Backend、PostgreSQL 和隐私边界；已知地点约束稳定永久拒绝 |
| [0116](./0116-personal-interest-median-uses-the-lower-observed-level.md) | 已接受，2026-08-12 | Slice 6W；`ANALYTICS-001`、`ANALYTICS-002`、`ANALYTICS-006`、`ANALYTICS-007`、`ANALYTICS-012` | 个人兴趣中位等级取较低的真实等级；空期间不虚构零级 |
| [0117](./0117-personal-interest-ratios-use-integer-basis-points.md) | 已接受，2026-08-12 | Slice 6X；`ANALYTICS-001`、`ANALYTICS-003`、`ANALYTICS-007`、`ANALYTICS-010`、`ANALYTICS-012` | 个人兴趣五档比例保存整数分数、透明缺失覆盖和确定性基点；空分母不虚构零百分比 |
| [0118](./0118-interest-subset-ratios-are-independent-metrics.md) | 已接受，2026-08-12 | Slice 6Y；`ANALYTICS-001`、`ANALYTICS-003`、`ANALYTICS-007`、`ANALYTICS-010`、`ANALYTICS-012` | 兴趣 3–4 与 0 是共享分母的独立子集比例，不放松五档穷尽比例合同 |
| [0119](./0119-target-response-distribution-counts-current-answered-links.md) | 已接受，2026-08-12 | Slice 6Z；`TARGET-004`、`TARGET-006`、`TARGET-007`、`TARGET-013`、`ANALYTICS-001`、`ANALYTICS-002`、`ANALYTICS-007`、`ANALYTICS-012` | 对象当次反应按当前 revision 已填写关联计数，NULL 只作未填写覆盖 |
| [0120](./0120-target-response-median-uses-answered-current-links.md) | 已接受，2026-08-13 | Slice 6AA；`TARGET-004`、`TARGET-006`、`TARGET-007`、`TARGET-013`、`ANALYTICS-001`、`ANALYTICS-002`、`ANALYTICS-007`、`ANALYTICS-012` | 对象当次反应中位等级只使用当前已填关联，偶数取较低真实等级 |
| [0121](./0121-target-response-level-ratios-use-answered-current-links.md) | 已接受，2026-08-13 | Slice 6AB；`TARGET-004`、`TARGET-006`、`TARGET-007`、`TARGET-013`、`ANALYTICS-001`、`ANALYTICS-002`、`ANALYTICS-003`、`ANALYTICS-007`、`ANALYTICS-010`、`ANALYTICS-012` | 对象当次反应五档比例只使用当前已填关联，整数基点按 half-up 计算，空分母不虚构百分比 |
| [0122](./0122-current-relationship-stage-distribution-is-a-scoped-current-snapshot.md) | 已接受，2026-08-13 | Slice 6AC-0、Slice 6AC；`PII-001`–`PII-005`、`ANALYTICS-007`、`ANALYTICS-010`–`ANALYTICS-012` | 个人当前关系阶段按当前分配的 active 对象 × 项目关系计数，并区分快照时刻、来源新鲜度与历史重建 |
| [0123](./0123-follow-up-consent-ratio-requires-project-opt-in.md) | 已接受，2026-08-13 | Slice 6AD-0；`TARGET-010`、`ANALYTICS-003`、`ANALYTICS-007`、`ANALYTICS-010`、`ANALYTICS-012`、`ANALYTICS-014` | 后续联系同意占比只在项目启用后存在；现有默认 unknown 按未回答覆盖处理 |
| [0124](./0124-follow-up-consent-opt-in-is-an-audited-current-switch.md) | 已接受，2026-08-13 | Slice 6AD-1；`AUTHZ-004`、`AUTHZ-006`、`ANALYTICS-003`、`ANALYTICS-014` | 项目启用使用追加式当前开关；停用不删除事实，读取时重新授权 |
| [0125](./0125-personal-consent-opt-in-http-binds-current-project.md) | 已接受，2026-08-13 | Slice 6AD-4；`TARGET-004`、`TARGET-010`、`ANALYTICS-003`、`ANALYTICS-014`、`TEST-005` | 个人配置 HTTP 绑定可信当前项目和固定指标；成功重放统一返回 200，内部操作者 ID 不出现在 wire |
| [0126](./0126-relationship-stage-change-metrics-use-trusted-actor-and-distinct-relationships.md) | 已接受，2026-08-13 | Slice 6AE-0；`TARGET-009`、`TARGET-016`、`ANALYTICS-007`、`ANALYTICS-015`、`PRIVACY-012`、`TEST-005`、`TEST-008` | 阶段变更指标按可信当前用户和 UTC 半开期间统计；事件数与去重对象×项目关系数分开，未来管理 `k=10` 使用后者 |
| [0127](./0127-personal-stage-change-summary-uses-current-project-bridge.md) | 已接受，2026-08-13 | Slice 6AE-1；Issue #136；`TARGET-016`、`ANALYTICS-015`、`PRIVACY-012`、`TEST-005`、`TEST-008` | 个人汇总由固定 HTTP 读取和单 statement PostgreSQL bridge 提供；数据库解析并锁定当前项目，保留匿名化前的合格历史，不提供 as-of |
| [0128](./0128-personal-stage-change-ui-keeps-remote-history-separate.md) | 已接受，2026-08-13 | Slice 6AE-2；Issue #138；`ANALYTICS-010`、`ANALYTICS-011`、`ANALYTICS-015`、`ANALYTICS-016`、`PRIVACY-008`、`UI-001`–`UI-007`、`TEST-006` | Flutter 以独立远端卡片显示阶段变更历史，严格校验当前项目与可信数据截止，不把它混入当前阶段快照或本地覆盖 |
| [0129](./0129-personal-interest-trend-uses-two-complete-utc-weeks.md) | 已接受，2026-08-13 | Slice 6AF；Issue #140；`ANALYTICS-003`、`ANALYTICS-004`、`ANALYTICS-005`、`ANALYTICS-007`、`ANALYTICS-010`、`ANALYTICS-012`、`ANALYTICS-017`、`TEST-005`、`TEST-009` | 个人只比较 `interest_3_4_ratio@1` 的两个完整 UTC 七日；同一 Drift transaction 和本地截止时间，只有两期可计算才显示 current−previous 百分点差 |
| [0130](./0130-management-report-details-show-definition-source-and-privacy.md) | 已接受，2026-08-13 | Slice 6AG；Issue #142；`ANALYTICS-018`、`TEST-010` | 管理报告详情显示既有报告／指标定义、来源、隐私规则、16 格 displayed／suppressed 摘要和非形式化匿名边界；不改变 wire、Backend 或隐私计算 |

## 按主题查找

| 主题 | ADR 范围 | 主要 Slice／Requirement |
| --- | --- | --- |
| 接触、工作空间、身份与权限 | [0001](./0001-contact-records-independent-of-promotion-targets.md)–[0010](./0010-capability-based-membership-permissions.md)，另见 [0103](./0103-management-analysis-view-and-report-release-use-separate-capabilities.md) | Slice 1、4、6、7；`CONTACT`、`AUTHZ`、`CTX` |
| 区域、对象、隐私资料与修订 | [0011](./0011-shared-hierarchical-regions-with-eventual-resolution.md)–[0021](./0021-submitted-contacts-are-voided-not-silently-deleted.md) | Slice 1、2、4；`REGION`、`TARGET`、`CONTACT` |
| 离线、同步、认证与平台 | [0022](./0022-offline-first-contact-recording-with-an-outbox.md)–[0029](./0029-use-one-capability-adaptive-flutter-application.md)，另见 [0096](./0096-use-supabase-auth-with-cognito-fallback.md)、[0098](./0098-persistent-outbox-uses-claim-lease-and-ack.md)、[0100](./0100-pull-cursor-advances-only-after-local-batch-apply.md) | Slice 0–2；`ARCH`、`AUTH`、`PLATFORM`、`TEST-003` |
| 组织、保留、导入导出与合并 | [0030](./0030-allow-verified-users-to-create-organizations.md)–[0043](./0043-promotion-target-merges-are-reversible.md) | Slice 4、7；`ORG`、`TARGET`、`AUTHZ` |
| 私人计划、通知与周期 | [0044](./0044-personal-action-plans-are-private-and-user-controlled.md)–[0052](./0052-late-entered-contacts-count-in-their-occurrence-period.md) | Slice 5；`PLAN`、`PLATFORM` |
| 说明书与发布检查 | [0053](./0053-production-code-and-learning-materials-evolve-together.md)–[0059](./0059-documentation-and-statistics-checks-block-releases.md) | 全部 Slice；`MANUAL`、Definition of Done |
| 指标、报告与隐私 | [0060](./0060-ordinal-scale-distributions-are-primary.md)–[0077](./0077-core-metrics-ship-with-code-and-project-metrics-use-safe-configuration.md)，另见 [0099](./0099-management-analytics-use-bounded-query-surfaces.md)、[0101](./0101-management-weekly-reports-use-two-complete-iso-weeks.md)–[0130](./0130-management-report-details-show-definition-source-and-privacy.md) | Slice 6；`ANALYTICS`、`PRIVACY`、`AUTHZ`、`REGION`、`ARCH`、`TEST-005`、`TEST-010` |
| 当前上下文、问卷、草稿与导航 | [0078](./0078-a-visible-project-context-scopes-default-work.md)–[0090](./0090-contact-entry-prioritizes-core-facts-with-progressive-disclosure.md) | Slice 1、3、5；`CTX`、`QUESTION`、`DRAFT`、`UI` |
| 尝试、渠道、触达和机构关系 | [0091](./0091-unsuccessful-direct-outreach-is-a-contact-attempt.md)–[0095](./0095-person-to-institution-relationships-use-six-stable-kinds.md) | Slice 1、2、4；`CONTACT`、`TARGET` |
| 基础设施 | [0097](./0097-use-supabase-postgresql-for-the-initial-stage.md) | Slice 0／发布门槛；`ARCH-003`–`ARCH-010` |

文件名中的编号只表示记录顺序，不表示优先级。实现时先读取相关 ADR 的正文，再用当前 Spec 和 GitHub Issue 确认范围与验收条件。
