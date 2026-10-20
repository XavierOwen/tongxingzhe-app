# ADR-0194：账号恢复绑定当前删除代次并保留原关系

- 状态：已接受
- 日期：2026-10-20
- Slice：7EV／private DB-only
- Issue：[#593](https://github.com/XavierOwen/tongxingzhe-app/issues/593)
- Requirement：`ORG-005`、`ORG-050` 至 `ORG-055`、`TEST-166`、`MANUAL-155`
- 关联：[ADR-0037](./0037-delete-accounts-without-erasing-organization-owned-history.md)、[ADR-0175](./0175-organization-creation-is-atomic-with-first-active-owner.md)

## 决定

账号删除和组织删除拥有各自的恢复周期。本人首次申请删除账号时，只把账号从 active 变为 deletion_pending，不结束 membership、owner assignment、capability 或对象分配。恢复 active 后，原关系按原有效期重新参与授权；已经到期、被其他合法治理结束的关系不会复活。这样保留可撤回性，避免恢复时重新授予已经失去的权限。账号恢复也不撤回任何组织删除申请。

首次申请只接受可信内部 app_user_id 本人的意图。数据库在全部等待锁之后取一次 `clock_timestamp()`，写入 `effective_at_utc`；`purge_after_utc` 恰好晚连续 720 小时。恢复窗口为 `[effective_at_utc, purge_after_utc)`，不使用本地日历月、客户端时间或事务开始时间。到达截止点即不可恢复；本片只保留 pending 状态与期限事实，不执行期满清除。

申请使用独立 `account-deletion-request:v1` family，request UUID 同时是本次 opaque deletion cycle。恢复使用独立 `account-deletion-restore:v1` family，并显式绑定该 cycle。同一账号可在成功恢复后以新 UUID 再次申请；两类 family 的 UUID 独立，不复用组织 claims 或 tombstones。

申请重放只允许相同 actor、request 与当前尚未到期的 pending cycle。恢复重放只允许相同 actor、request 与当前 restored cycle，账号必须仍 active；它可在原期限之后返回已经完成的恢复 receipt。恢复后的旧申请、被新 cycle 取代的旧申请／恢复或 selector 漂移全部 conflict，不触碰当前状态。claim actor 已去关联或换 actor 同样 conflict。若请求没有先命中该 conflict，但账号／current／原申请 receipt 的来源不一致，则返回 unavailable，不能补造生命周期。

## 锁与权限

两个 private writer 仅允许 READ COMMITTED，在授权、锁和写入之前拒绝其他模式。锁序为本操作 request advisory lock、本人 app-user row、本人全部历史组织 membership 所涉及的 governance locks，组织 UUID 升序。申请与恢复分别使用 `account-deletion-request:<UUID>` 和 `account-deletion-restore-request:<UUID>` 锁键。同账号的不同 request 由 user row 串行化。

全部锁取得后重读 current 与 receipt。首次申请必须证明所有相关、仍物理存在的组织都有另一位 current active owner，包括正在组织恢复期的组织。治理锁后不再锁其他 owner 的 user row，避免两个 owner 各持本人 user lock 时形成反向等待。既有 deferred owner invariant 继续在提交时检查；其他 owner 在提交前自然到期导致失败时，整笔事务回滚。

`app_private.request_account_deletion_v1(uuid,uuid)` 返回 contract、deletion request、effective 和 deadline 四字段。`app_private.restore_account_v1(uuid,uuid,uuid)` 返回 restore contract、deletion request 和 restored time 三字段。两者均为 `VOLATILE SECURITY DEFINER`、固定 `search_path=pg_catalog`，owner 与既有组织 membership validator 相同。PUBLIC／runtime 没有执行权或直接表权限，不增加外部 identity bridge。

四张 typed private 表分别保存 current、申请 claim、恢复 claim 和 value-free audit。claim 追加不可变，只允许未来账号终结处理把 actor 从非空解除为 null；audit 不含 actor、外部身份、组织、业务正文或自由文本。状态、claim 和 audit 任一步失败均使本次全部写入回滚。没有账号恢复来源的既有 deletion_pending 行使迁移失败，不能以迁移时刻回填期限；既有 deleted 行原样保留且不可申请或恢复。

## 边界

本片不改变普通 writer、bootstrap、0085 owner trigger 或任何旧函数。pending 账号仍由现有 active-user 检查拒绝；这不证明所有旧业务入口与账号状态变化均已线性化。外部认证商的登录／账号删除、客户端敏感缓存、期满个人数据清除、组织作者不可反查去关联和终结 claim 清除另行交付。没有 Backend、runtime、HTTP、UI、scheduler 或生产部署。

Docker synthetic 的行为、并发、真实升级、checksum 和独立恢复只能证明私有 PostgreSQL 合同，不能记作完整账号删除、真实 PII、认证商或设备清除证据。
