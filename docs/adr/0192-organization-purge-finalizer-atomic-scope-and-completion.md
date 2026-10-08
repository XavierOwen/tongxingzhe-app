# ADR-0192：组织清除使用固定范围与原子完成记录

- 状态：已接受
- 日期：2026-10-07
- Slice：DB0109 / DB-only
- Issue：[#509](https://github.com/XavierOwen/tongxingzhe-app/issues/509)
- 关联：[ADR-0188](./0188-organization-deletion-and-recovery-execution-contract.md)、[ADR-0190](./0190-management-report-request-locks-precede-authorization-locks.md)、[ADR-0191](./0191-organization-purge-uses-exact-row-transaction-authorizations.md)

`app_private.finalize_organization_purge_v1(workspace UUID, expected deletion request UUID)` 由既有组织治理 owner 持有，使用 SECURITY DEFINER、固定 `pg_catalog` search path 和 READ COMMITTED。runtime 与 PUBLIC 没有 EXECUTE。首次执行只接受仍绑定该组织的当前未恢复删除 cycle，期限必须等于生效时间加 720 小时，并在全部必要锁取得后以数据库 `clock_timestamp()` 确认已届满。

finalizer 先收集固定 request family，依全局 family／UUID 顺序取得请求锁，再取得所选业务行涉及的用户、组织治理、成员层级、项目配置与报告 lineage 锁。治理锁后重新收集 request 与用户引用；出现新增引用即拒绝并要求调用者完整回滚后重试。它固定选择 86 个 relation 中能以 workspace、project、contact、target、questionnaire、snapshot 或成员键证明归属的行，独立验证非 FK 的来源一致性，并保留真实 FK 的边界检查。来自个人或其他组织的外部引用导致失败，不能扩大清除范围。

0108 的授权表保存当前事务、backend、workspace、relation OID 与完整主键。0109 先锁定所选行并冻结逐行授权，再依 child-first 顺序 DELETE；questionnaire compatibility 和 report snapshot 的自引用依叶至根删除。UPDATE 仍受原 guard 约束。`purging` 只存在于该清除事务内；owner invariant 延后检查后必须恢复为 IMMEDIATE。任何业务删除、ledger 写入或最终约束失败都使整个事务回滚。

同一事务为 21 个固定 UUID family 写入 `claim_family`、`request_uuid`、一个有限 UTC 完成时间，并补写七个旧组织 tombstone。完成后删除 workspace、当前 lifecycle 行及所有临时授权，只返回 `deletion_request_id` 与 `purge_completed_at_utc`。重试已完成 request 返回相同两个字段。value-free ledger 不保存 workspace 或 actor，因而该重试证明的是 request 已终结，不能重新证明调用者提供的 workspace 与已删除组织之间的旧绑定。

`processed_commands`、promotion target creation 与 questionnaire publication 的 text receipt 使用 actor＋text key。它们没有被扩大为 UUID tombstone family；只删除能以精确业务 payload、project／draft 或 `(actor, command)` 审计证据证明归属的回执。旧 workspace／project 已不可访问，同一 text key 可用于新的个人操作，另一 actor 的同名个人回执必须保留。

清除调用失败后，调用者必须先完整 ROLLBACK，再开启新事务调用 `app_private.record_organization_purge_failed_v1(workspace UUID, expected cycle UUID)`。该函数重新锁定并确认组织、当前 cycle、未恢复状态及期限，仅把当前状态置为 `purge_failed`；失效 selector 返回 false。它不保存错误文本或业务内容。后续 finalizer 可以对仍有效的失败 cycle 重试。

验证使用真实个人 writer 构建 contact／questionnaire／target 图后，在 fixture setup 中移植成 synthetic imported organization history；当前组织 runtime writer 并未因此开放。组织治理、报告五 family、release／replacement、读取／目录／导出、时区与 management opt-in 由既有真实组织 writer 生成。fixture 明确要求 86 个 relation 都有组织行，以全行快照证明清除与个人、另一组织、身份及共享定义的保留；独立核对 21 family 的全部完成 UUID。最终 workspace DELETE 的单一注入故障证明 children、状态、ledger 和授权全部回滚；独立连接再证明 outer ROLLBACK 后另起失败状态事务与正常重试。恢复、治理、request replay 与 report read 双向并发通过真实锁等待和提交后重验。旧数据库丰富图升级、checksum replay 与标准 dump／restore 属于数据库验证，不证明生产备份或灾备副本已清除。
