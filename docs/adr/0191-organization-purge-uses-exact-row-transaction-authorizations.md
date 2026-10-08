# ADR-0191：组织清除使用完整主键的事务级 DELETE 授权

- 状态：已接受
- 日期：2026-10-07
- Slice：7DJ / DB-only
- Issue：[#516](https://github.com/XavierOwen/tongxingzhe-app/issues/516)
- 关联：[ADR-0188](./0188-organization-deletion-and-recovery-execution-contract.md)、[ADR-0190](./0190-management-report-request-locks-precede-authorization-locks.md)、[ADR-0151](./0151-management-report-retention-follows-organization-lifecycle.md)

组织清除需要删除追加不可变的组织历史与管理报告依赖。0108 只提供私有 DELETE proof 和终结 UUID ledger，保留原有 UPDATE、身份 unlink 例外及个人记录 guard。它不选择组织或业务行、不改变生命周期、不执行清除、不记录失败。

`organization_purge_delete_authorizations` 由既有 `validate_organization_membership_v1()` owner 持有，只保存当前事务 ID、backend PID、组织 workspace、relation OID 与完整行主键。表不引用 workspace，避免阻止删除 workspace。closed report writer 与 runtime 没有写入权。

`organization_purge_row_delete_authorized_v1(oid,jsonb)` 从真实 PostgreSQL catalog 取得 relation 的完整主键，拒绝无主键、缺失或 null 键；只在当前事务、当前 backend、同 relation 与完整主键一致时返回 true。任意列子集、predicate、GUC 或临时开关不能授权。workspace 字段是 trusted finalizer 的授权分组；checker 不从外键推导行的组织归属。固定组织范围、异常拒绝与 child-first 顺序属于 finalizer。

固定的 28 个 guard 只在 DELETE、当前执行者具有 checker EXECUTE 且 exact-row proof 成立时返回 OLD。其余 body、owner、ACL、SECURITY INVOKER／DEFINER 与 search path 保持原状。无 helper 权限的 invoker 沿原 guard 报错；runtime 不获得 checker 权限。七组旧 organization tombstone 与新的 completion tombstone 即使存在授权行也拒绝，个人 draft／plan／reminder／opt-in guard 继续关闭。

`organization_purge_request_tombstones` 只保存明确 allowlist 中的 claim family、UUID 与有限 UTC 完成时间，复合主键并追加不可变。七组原有组织 writer 继续读取原 tombstone。删除、恢复、管理报告 release／replacement（包括可信直接 legacy v1 及 v2 同 UUID 委托）、报告时区与 management opt-in writer 在已有 request lock 后检查新的 completion ledger，复用各自的 22023 幂等冲突合同。九组共享 release／replacement family 的 UUID 互斥；渠道 replacement 使用既有独立 namespace。

后续 finalizer 在同一可信事务中选择固定范围、取得 request／治理锁、临时写入逐行授权、执行删除、写入 completion ledger，并在返回前清空授权。失败由事务回滚授权与业务变更，回滚后另行记录最小失败状态。0108 的 schema／ACL、synthetic rollback fixture、old-live-data upgrade、checksum replay 与 dump／restore 只能证明此 foundation，不证明生产清除或备份清除。
