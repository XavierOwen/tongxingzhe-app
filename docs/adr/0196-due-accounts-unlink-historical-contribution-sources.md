# ADR-0196：期满账号解除历史贡献的来源引用

- 状态：已接受
- 日期：2026-10-20
- Slice：7EX／private DB-only
- Issue：[#597](https://github.com/XavierOwen/tongxingzhe-app/issues/597)
- Requirement：`ORG-005`、`ORG-056` 至 `ORG-059`、`TEST-168`、`MANUAL-157`
- 关联：[ADR-0037](./0037-delete-accounts-without-erasing-organization-owned-history.md)、[ADR-0194](./0194-account-deletion-recovery-is-cycle-bound-and-preserves-relationships.md)、[ADR-0195](./0195-personal-history-contributions-copy-only-core-facts.md)

## 决定

账号恢复期满后，组织拥有的历史贡献核心副本保留，私有 preview／confirmation 不再直接指向该账号或其个人原记录。此片只完成这一步，不删除账号、个人数据或外部身份，不撤销成员关系，也不把原生组织接触作者替换成虚构的匿名用户。现有管理报告和真实 contributor 归并不变。

`app_private.unlink_due_account_history_contributions_v1(user UUID, expected deletion cycle UUID)` 只接受可信内部调用。数据库必须证明本人仍为 deletion_pending，0133 current 仍是指定 pending cycle，原申请 actor、effective time 和 deadline 完全一致，且最后等待锁后的墙钟已到或超过 deadline。期限前返回 not due，旧 cycle 返回 conflict，缺失或矛盾的生命周期来源返回 unavailable。半开恢复窗结束的截止点本身可以执行此步骤。

选择范围包含 actor 为本人或 source 仍属于本人个人空间的 preview／confirmation，即使 actor 已经解除引用也不能漏掉 source。两表按 preview UUID 形成完整关联集；actor 与 source ownership 不一致、来源不是本人个人事实、preview／confirmation／copy 的目标或确认来源相矛盾时整笔拒绝，不能通过清空引用掩盖来源错误。已经只解除一侧引用的合法行可继续解除另一侧。

成功只把两表的 `actor_app_user_id` 和 `source_contact_id` 置为 null。原 preview／confirmation 的其他 metadata、核心副本的全部五项事实、个人接触与所有修订、组织及成员事实逐值保留。无需改动 0134 的 guard：它已经允许这两列非空到 null，禁止重绑及其他修改。去关联后的组织副本仍由原组织终结清除合同负责。

## 锁与完成凭据

只接受 READ COMMITTED，其他模式在读取、授权和锁之前拒绝。首先取得 `account-history-contribution-unlink:<cycle UUID>`，再把预收集的 confirmation request UUID 按升序锁定，锁键仍为 `personal-history-contribution-confirmation:<request UUID>`；随后锁本人 user row，最后按组织 UUID 升序锁 governance。本人使用 `FOR NO KEY UPDATE`，冻结状态和删除，同时兼容旧个人接触 writer 的作者 FK 检查。

user／governance 之后不能补取 request lock。全部锁到齐后重新收集范围；新 request 或未预锁组织出现时零写返回 retry required。组织 purge 先完成而使范围缩小可以继续；既有组织内新增的未确认 preview 也可以纳入，因为它没有 request lock。此规则保持与 0134 confirmation 和组织 purge 的 request→user→governance 相对顺序。

两表更新与一条 value-free completion 原子提交。completion 只保存 cycle UUID 和完成时间，无账号、source、组织、项目、计数或正文引用，不建立新的自然人反查映射。空范围也可记录本步骤完成。精确重放要求仍是本人的当前 due pending cycle，且没有新的可归属 provenance；返回原 completion，不改变时间或业务事实。已有 completion 却残留引用或完成时间不可信时 unavailable，不把部分清除当作成功。

新增一表、一函数，均由既有 membership validator 的 trusted owner 拥有。函数为 `VOLATILE SECURITY DEFINER`、固定 `search_path=pg_catalog`；PUBLIC／runtime 无执行权或表权限。completion 不可 UPDATE／DELETE，也没有指向账号、来源或组织的 FK。所有旧函数、OID、owner、ACL、约束和组织 purge inventory 保持原样。

## 边界

这只解除历史贡献副本的直接来源关系，不证明时间等核心事实无法被外部信息重识别。原生组织接触和共享跟进仍有其他作者引用，不能把本步骤报告为“已删除成员”匿名化、个人账号 purge 或 ORG-005 完成。

不增加 runtime、Backend、HTTP、UI、scheduler 或生产部署，不处理外部 Auth、本地缓存、个人空间删除、全部作者去关联或最终成员撤销。fresh、真实 0134 升级、行为、并发、checksum 与独立恢复仅证明 synthetic private PostgreSQL 合同。
