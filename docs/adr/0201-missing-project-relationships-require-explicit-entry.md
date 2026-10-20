# ADR-0201：缺失项目关系须明确确认真实进入

- 状态：已接受
- 日期：2026-10-20
- Slice：7FC／private DB-only
- Issue：[#605](https://github.com/XavierOwen/tongxingzhe-app/issues/605)
- Requirement：`PII-020`、`TEST-173`、`MANUAL-162`
- 关联：[ADR-0198](./0198-project-relationship-resolution-plans-list-metadata-candidates.md)、[ADR-0199](./0199-existing-project-relationship-resolution-keeps-history-and-explicit-current.md)

## 决定

0138 v1 仍拒绝缺失原关系的槽。0140 新增私有 v2 wrapper，只在调用者明确确认来源现在进入原项目时初始化，再委托未修改的 v1 完成历史归属、当前选择、代次结束与 payload 消费。不复制旧 writer，也不改普通创建路径、表约束或初始 revision trigger。

v2 接收原三项 metadata 指纹、完整 assignments／current choices，以及 `project_entry_acknowledgements`。每项 acknowledgement 精确包含 project、source 和 pending UUID；规范化大小写与顺序，拒绝重复。其集合须精确覆盖原 0137 预检中没有 current 的槽，pending 必须等于该槽已分配并明确选择的候选。已有槽不得 acknowledgement；全已有时允许空集。

## 进入不是历史回填

每个 acknowledgement 是真实的新行政性项目进入动作。仅对仍属于本人有效 personal workspace 的 active 原项目，在锁后数据库时间以真实 actor 建立阶段 0、active、无备注、revision 1 的普通关系。现有 INSERT binder 和初始 trigger 产生真实 generation binding 与 project_entry，不补造 contact、consent 或过去的进入时间。

初始化之后重算内部 known／resolution 指纹，pending 指纹不变，再调用原 v1。全部原 pending 各自进入历史，原时间不改，同值不去重；最终值只取逐槽明确选择，不自动取最新。初始 project_entry 是新动作，不是重复应用某项 pending；阶段 0 初始事件不计作阶段变更。

## 事务与重放

沿用 actor／request → 本人 user NO KEY UPDATE → global generation fence → targets created／UUID → assignments UUID → 原有关系 project／source UUID 的锁序。所有等待后重读原计划、完整集合、三指纹、范围、两端 due 及待初始化项目资格；不增加 project、contact 或普通子请求锁。缺失槽由原 global fence 串行化。

两张不可变 private 表只保存请求、标识、原／内部 metadata 指纹和时间。origin 精确绑定所选 pending、初始 revision 1、真实 actor／时间／binding；proof 同时核对内部确认与 end。deferred inner-request FK 防止初始化或 provenance 脱离完整确认提交。输入、资格、数量、proof 或子步骤失败均回滚新增关系、初始 revision、历史、当前、metadata、end 与消费。

精确重放核对原上下文、三指纹和完整规范化 assignments／choices／acknowledgements，再以保存的内部指纹委托旧 v1 返回原时间。它不重新初始化、不重复历史，也不恢复后来编辑或匿名化的文本。READ COMMITTED 以外的事务在请求读取、授权或锁之前拒绝。

## 边界

同代次还有接触 pending 时仍整批拒绝。没有接触、同意、retention 续期、业务哈希或普通 writer 改动；旧 rows、函数及 catalog 不变，新增八条 FK 纳入严格清理 inventory。PUBLIC／runtime 无权限，不接 Backend／HTTP／UI、scheduler 或生产 active merge。

这是项目 pending 的显式进入与处置，不是接触／项目 mixed split、全部未知事实类型或完整拆分。synthetic fresh、真实版本升级、并发、checksum 和独立恢复不替代生产身份、真实 PII 或设备验收。
