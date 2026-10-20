# ADR-0199：已有项目关系的历史归属与当前选择分别记录

- 状态：已接受
- 日期：2026-10-20
- Slice：7FA／private DB-only
- Issue：[#601](https://github.com/XavierOwen/tongxingzhe-app/issues/601)
- Requirement：`PII-009`、`PII-019`、`TEST-171`、`MANUAL-160`
- 关联：[ADR-0193](./0193-historical-pending-facts-and-current-source-candidates.md)、[ADR-0197](./0197-unknown-project-relationship-facts-stay-pending-until-assigned.md)、[ADR-0198](./0198-project-relationship-resolution-plans-list-metadata-candidates.md)

## 决定

0138 确认本代次全部项目关系 pending 的原来源，并逐个受影响的 `(source target, original project)` 槽明确选择 current 或一项已分配的 pending。它只接受所有槽已有原关系及真实 current revision，且没有未处理的接触类 pending；否则整批拒绝并保留原状态。没有来源明确的初始关系创建合同前，不制造 contact、conflict 或 project_entry。

`app_private.confirm_personal_merge_project_relationship_resolutions_v1` 接收可信 user／workspace／current project／request／generation、0137 的 known／pending／resolution 三指纹、完整 assignments 与完整 current choices，返回既有 end receipt 的数据库时间。

choices 每项精确含 project、source、candidate kind 和 pending ID。current 要求 pending ID 为 JSON null；pending 必须是该槽已分配的真实候选。UUID 大小写与顺序归一，遗漏、重复、额外槽或不可用候选拒绝。单候选也必须明确选择。

## 历史与当前

每项 pending 追加一个独立的真实来源分配 revision，raw 阶段、生命周期、备注、原因和时间都来自原 pending；同值事件不去重。其 old 值取确认前真实 current，`changed_fields` 精确为 `pending_source_assignment`，不把候选归属冒充已经生效的阶段变化。追加候选期间不逐项更新当前投影。

每槽最后追加一条当前选择 revision，old 值仍取确认前 current，new 值来自明确选择的原 current 或 pending。字段标记含 `pending_current_selection` 和真正变化的 stage／lifecycle／note，原因固定为 correction，时间取锁后数据库确认时间；没有业务变化时仍保留明确选择事件。当前投影一次指向最终 revision。

锁下先核对当前投影的阶段、生命周期和备注与真实 head 一致，矛盾时零写拒绝。原关系的创建 binding、全部旧 revision、其他来源和项目不改。每个新 revision 通过现有 INSERT binder 取得真实当前代次；parent 与 head binding 可以不同，不回填。没有普通 mutation／processed command，也不伪造普通 writer 接受了无变化更新。

三个 private 不可变表只保存请求与三指纹、pending／source／project／原 base／实际应用 revision、各槽原／最终 revision、原 parent binding 与明确选择。业务值和业务哈希不复制到 ledger。应用和当前 revision 是敏感业务历史，继续受原数据面保护，不因 metadata ledger 私有就改称匿名。

## 原子性与重放

只允许 READ COMMITTED，其他模式在授权、锁或请求读取前拒绝。按 actor／request、本人 user 的 FOR NO KEY UPDATE、global generation fence、两 target 的 created time／UUID、两 assignment UUID、关系 project／source UUID 取锁。所有等待后重读完整集合、三指纹、资格和两端 due，不补取反向 contact 锁。

完整 proof 逐项核对原 pending、真实历史内容与 binding、连续 revision 编号、原 current 和最终选择。只有 proof 成立才能通过扩展后的 0136 end guard；之后必须有精确 known-source end receipt 才能清除全部 payload，末尾再次核对数量与 proof。任何一步报错或被抑制均回滚历史、当前、metadata、end 和消费。

同 actor／request 的规范化映射、选择、指纹与上下文完全一致时，只经既有 end replay 的当前授权返回原时间。请求漂移 conflict，不重复追加历史；同代次和每个 pending 只能确认一次。

## 边界

仅新增 private 表、proof 与 confirmer，并必要扩展 0136 的 end／payload 两个 guard；原 expiry、0018 schema／initial trigger、普通 writer 和既有历史不改。runtime／PUBLIC 无权限，不接 Backend／HTTP／UI、scheduler 或生产 active merge。

缺关系初始化、接触与项目 pending 的混合确认、其他未知事实类型及完整拆分另行交付。synthetic fresh、升级、checksum 和独立恢复不能替代生产身份、真实 PII 或设备验收。
