# ADR-0188：组织删除与恢复使用固定期限和受控终结

- 状态：已接受
- 日期：2026-09-28
- Slice：7CT Spec
- Issue：[#486](https://github.com/XavierOwen/tongxingzhe-app/issues/486)
- Requirement：`ORG-041` 起、`TEST-138`、`MANUAL-128`
- 关联：[ADR-0036](./0036-delete-organizations-after-a-thirty-day-recovery-window.md)、[ADR-0037](./0037-delete-accounts-without-erasing-organization-owned-history.md)、[ADR-0151](./0151-management-report-retention-follows-organization-lifecycle.md)、[ADR-0175](./0175-organization-creation-is-atomic-with-first-active-owner.md)、[ADR-0182](./0182-organization-directory-is-membership-scoped.md)、[ADR-0186](./0186-explicit-ordinary-project-membership-assignment.md)

## 背景与取舍

ADR-0036 已确定三十天恢复期和期满完整清除，ADR-0151 已确定恢复期内现有报告的受控读取。现有组织 owner、成员关系、请求 claim 和普通目录各有独立边界；删除流程需要一致的时钟、授权和失败状态。

任一当前有效 owner 都可申请删除，也可在期限内恢复。首版不要求多个 owner 共同确认，因为共同确认会使失联 owner 阻止其他 owner 恢复；恢复窗口给误申请留出撤回机会。当前有效要求账号 active、组织成员关系和 owner assignment 均有效。owner 资格只授权删除治理，不授予报告内容或其他项目数据权限。恢复意图必须同时携带 workspace UUID 与当前 opaque `deletion_request_id`；锁后两者仍须指向同一个 `deletion_pending` cycle，避免上一轮迟到请求恢复下一轮删除。

首次成功申请以数据库确认的 UTC 时刻为 `effective_at_utc`，`purge_after_utc` 恰好晚 720 小时。恢复窗口是半开区间 `[effective_at_utc, purge_after_utc)`：截止时刻本身不能恢复。连续小时数不受组织时区、客户端时钟、夏令时或日历月长短影响；选择日历月或本地日期会使同一请求的实际期限随时区和月份变化。

## 生命周期与重放

状态合同包含 `active`、`deletion_pending`、`restored`、`purge_due`、`purging`、`purge_failed` 和 `purged`。首次申请使 `active` 进入 `deletion_pending`；期限内成功恢复记为 `restored`，并恢复正常治理资格。`restored` 是该次 lifecycle attempt 的终态，运行权限等同 `active`；以后再次申请删除必须使用新的 request 和恢复窗口，不能复用旧 claim 或 deadline。期限届满后进入 `purge_due`，受控清除期间为 `purging`；失败记为 `purge_failed`，完整清除后才可记为 `purged`。`purge_due`、`purging` 和 `purge_failed` 均关闭恢复与普通访问，失败不能回到可读状态。

申请与恢复各使用自己的 request claim family，恢复 claim 另绑定目标 `deletion_request_id`。同 family 的 request UUID 只有在 actor、组织、operation 和 deletion cycle 全部相同时才精确重放原意图和结果；任一 payload 漂移返回冲突。不同 UUID 的新申请不能替换或延长当前 `deletion_pending` 的 deadline。恢复不得改写首次申请的时间、期限或历史 claim；已有 live claim 的合格精确重放只读，不产生第二次状态变更、成功审计或期限延长。终结后只剩 value-free tombstone，不能据此重建含业务内容的历史回执。

## 恢复期的访问边界

`deletion_pending` 冻结新的普通组织治理和业务写入，包括 owner／成员治理、项目与接触写入、报告发布和 replacement。窗口内首次恢复 writer 及其 request claim／状态变更是恢复所必需的唯一新 lifecycle 写入例外；已有 live claim 的精确重放可只读返回原结果。仍具原有授权的成员可读取既有管理报告；为该读取所必需的 value-free access audit 是另一受控例外。报告导出、去身份化地点异常工作流及新的报告生成均不可用。恢复成功后，已有报告保持原状，不能产生报告 tombstone 或清除资格事实。

ADR-0182 的普通“我的组织目录”继续隐藏 `deletion_pending` 组织。独立的窄 recovery directory 只列出读取时 actor 仍是当前有效 owner 的可恢复组织，并返回 workspace UUID、当前 opaque `deletion_request_id`、原显示名、申请生效时间、截止时间和状态。cycle selector 只绑定一次恢复意图；它不是全局组织搜索，也不授予恢复资格的长期凭据、报告读取、成员、项目或导出权限。恢复提交时必须重新确认 selector、owner 与期限。

## 终结与证据

截止后只允许受控终结清除。清除须覆盖组织业务、成员与 owner 历史、各 report family、含业务内容的审计和组织拥有的历史贡献副本。个人空间原始记录不随组织清除。业务清除事务失败时必须完整回滚；回滚完成后，独立的最小生命周期事务才可记录 `purge_failed`，且不保存底层错误或业务内容。只有受控 finalizer 可以把 `purge_failed` 再次推进到 `purging`；它不能恢复组织。只有完成必要清除才能记录 `purged`。

终结清除后，每个已清除的 request claim 只留下最小 value-free tombstone：`claim_family`、`request_uuid` 和清除完成时间。它阻止该 family 内的 UUID 复用，不保存 workspace、actor、报告、资料或其他业务标识。完成时间只说明受控清除记录，不单独证明生产备份、灾备副本或物理介质已清除。请求锁和治理锁须沿用既有全局 family 顺序；后续数据库合同再固定删除与恢复 writer 的具体锁和重验步骤。

本 ADR 只固定执行合同。它不新增 migration、数据库状态机、Backend、Flutter、purge worker 或生产备份清除证据。[Issue #350](https://github.com/XavierOwen/tongxingzhe-app/issues/350) 的 readiness 检查不能代替这些实现及验证。
