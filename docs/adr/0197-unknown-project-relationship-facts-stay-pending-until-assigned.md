# ADR-0197：未知来源项目关系事实独立待分配

- 状态：已接受
- 日期：2026-10-20
- Slice：7EY／private DB-only
- Issue：[#598](https://github.com/XavierOwen/tongxingzhe-app/issues/598)
- Requirement：`PII-009`、`PII-013` 至 `PII-017`、`TEST-169`、`MANUAL-158`
- 关联：[ADR-0193](./0193-historical-pending-facts-and-current-source-candidates.md)、[ADR-0019](./0019-relationship-stages-can-move-in-both-directions.md)

## 决定

已知来源项目关系及其历史一直保留在原对象上，结束代次不需要搬移或复制。通过合并视图新增、没有明确原对象来源的项目关系事件则独立登记为 pending，不能伪装成普通关系、revision 或合并前事实。NULL generation binding 仍不表示来源未知。

首片只登记新事件，不实现分配、当前候选、历史应用或完整 split。每个 request 产生独立 pending，事件时间为锁后数据库墙钟；不回填合并前历史，不按值去重，不自动取最新或覆盖任一原对象已有关系。后续分配须另定执行合同，登记成功不是普通 writer 的写回资格。

private header 只保存 pending、actor、personal workspace、project、generation、target type、request 和数据库时间，不复制或散列业务值。第三张 private 表只记录到期 purge 的 pending、generation 和时间。

独立 typed payload 保存阶段 `0–4`、active／paused／ended、可空共享备注、既有 reason code／detail。备注最多 4000 字、detail 最多 1000 字，非空文本不能全空白，`other` 必须有 detail。

## 登记与读取

`app_private.stage_unassigned_personal_merge_project_relationship_v1` 接收可信内部 user／workspace／project、request、generation 与五项 typed 值。只接受 READ COMMITTED，先输入／隔离验证，再取独立 `personal-merge-unassigned-project-relationship:<actor>:<request>` 和既有 generation fence。通过 known-source split-plan 重验本人 personal scope、活动项目、两项 capability 和两端 active target／assignment／generation；最后取一次墙钟，要求两端 current retention deadline 均更晚。

首次成功原子建立 header／payload，返回固定 contract、pending UUID 和 staged time。live 精确重放仍需当前资格及未到期代次，返回原结果；context 或任一 typed 值漂移 conflict。代次结束、来源不完整或载荷已清除后，不补造载荷。普通关系、revision、feed 和 binding 不改；既有 fence epoch 变化属于锁协议，不是新业务事实。

`app_private.read_personal_merge_unassigned_project_relationship_plan_v1` 为 STABLE、单 statement snapshot 的真正只读预检，返回 known-source plan、pending metadata 数组、数量与 metadata fingerprint。每项只含 pending／project UUID、target type 和固定 UTC staged time。读取只核对 payload 是否完整，不返回或散列业务值；归属、项目、代次、类型或 purge 状态矛盾时失败关闭。它不取行锁或 fence，不写 audit、receipt、context 或 ledger，不保留确认资格。

## 结束与到期

新 BEFORE end guard 阻止仍有本类 pending 时的任何 known_source_split，也约束 0119 end、0128 单项和 0130 历史接触确认。旧 confirmer 此前的写入必须随整次事务回滚，不能完成一类却遗漏另一类。不改写旧函数绕过 guard。

retention_expired AFTER end trigger 在既有 pair expiry 事务内核对来源与完整数量，先写与真实 ended receipt、operation、reason、outcome 和时间一致的 purge 标识，再删除全部 typed payload。直接 UPDATE 永远拒绝，DELETE 仅允许精确 expiry receipt；缺载荷、来源矛盾、计数不符或任一步失败使整对 expiry 回滚。既有 batch 继续按原合同隔离可识别的单元失败，不阻断无关项。

header／purge 追加不可变。三表五函数保持 PUBLIC／runtime 封闭，由 known-source split-plan trusted owner 拥有；固定 `search_path=pg_catalog`、SECURITY DEFINER，writer／trigger 为 VOLATILE，reader 为 STABLE。七条即时 RESTRICT FK 纳入严格 inventory。旧迁移、函数 OID／owner／ACL／定义、普通 writer 和既有源事实不改。

## 边界

既有普通关系更新在阶段、生命周期和归一化备注都相同时拒绝追加 revision；换 request 或 reason 不构成事实变化。它也不创建不存在的关系，普通创建路径依赖实际 contact revision。后续历史处置必须明确保存同值事件和关系创建来源，不能把本片登记当作这些前提已经成立。

不创建普通关系／revision，不交付分配／消费、当前候选、其他 unknown 类型或混合事实完整确认。既有只读来源审查不因此获得产品 active merge、runtime、Backend／HTTP／UI、scheduler 或生产权限。synthetic fresh、升级、并发、checksum 和恢复只证明私有 PostgreSQL 合同，不证明真实 PII、设备同步、外部消费者或 #549 生产清理 SLA。
