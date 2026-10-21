# ADR-0204：混合显式进入先锁完整集合再确认

- 状态：已接受
- 日期：2026-10-21
- Slice：7FF／private DB-only
- Issue：[#613](https://github.com/XavierOwen/tongxingzhe-app/issues/613)
- Requirement：`PII-023`、`TEST-176`、`MANUAL-165`
- 关联：[ADR-0201](./0201-missing-project-relationships-require-explicit-entry.md)、[ADR-0202](./0202-mixed-resolution-preflight-keeps-both-plans-in-one-snapshot.md)、[ADR-0203](./0203-mixed-resolution-confirmation-uses-one-final-manifest.md)

## 决定

0143 为两类 pending 同时存在的代次增加私有 v2 入口，在明确确认项目进入后委托原 0142 混合确认。原 0142、两类应用与证明、结束和载荷守卫不改；旧单类入口不因此获得混合确认能力。

每个进入确认精确包含项目、来源和项目 pending UUID。规范化后，它须精确覆盖原项目计划的 missing 槽，pending 必须已分配给该槽并明确选作 current。已有槽不得多给确认，全部已有时接受空数组。接触历史、进入前 current 的非配对链接及其他缺失槽仍拒绝，不从接触推造行政进入。

将 0140 的初始化段精确提取为一个私有 helper，立即供旧单类和新混合入口共用。其余旧函数体及 OID、owner、ACL、config 保留。初始化使用真实操作者和锁后数据库时间，只建立阶段 0、active、无备注的 revision 1。原 trigger 产生真实 project_entry 和 generation binding，不回填原 pending 的发生时间，不补造接触、同意或续期。

## 完整预锁与内部计划

新入口先锁 request 与本人 active user 行，再按 C 顺序预锁全部 child commands、contact advisory 和接触行。随后取得 generation fence，按创建时间／UUID 锁全部 pair 和历史／current 非配对对象，再锁活动分配及完整集合中已有的项目关系。缺失槽只由该 fence 串行化，不能先取 fence 再补 child 或 contact 锁。

等待后重检两类完整 pending、接触 current heads、原共同计划、权限、两端期限、明确选择与确认覆盖。除已明确确认的项目 missing 槽外，整个关系集合必须已存在。任一集合增长或快照漂移均拒绝重取，不在锁后补取反向锁。

初始化后重新计算共同 known、两份原生 resolution 和混合指纹，两类 pending 指纹不变。以内部指纹调用原 0142；它对已有关系的检查自然成立，仍应用两类事实、采用共同最终清单、结束一次并原子消费两类载荷。不把初始化前的清单或一类中间清单当作最终回执。

## 来源证明与重放

新增外层请求和 entry origins 两张不可变私有表，只保存标识、原／内部 metadata 指纹、时间及初始 revision。外层请求以 deferred FK 绑定内层共同回执，防止只初始化后提交；origins 绑定原项目 pending 和实际初始 revision。插入时核对实际数量和精确 metadata，不另存或散列业务值。

完整证明连接原确认集合、真实 revision 1、所选 pending、内层两类及共同回执和单一 end。它核对项目、来源、操作者、初始化时间和 binding，确认初始事件确为阶段 0、active、无备注的 project_entry。初始化、metadata、内层应用、证明、结束或任一载荷消费失败时，所有变更共同回滚。

精确重放核对原上下文与四项指纹，并还原两类完整映射、当前选择和进入确认，再用保存的内部指纹委托 0142 terminal replay。不重跑 live plan 或事实证明，不重新初始化，不恢复后来普通编辑或匿名化的数据。

## 边界

仅接受 READ COMMITTED；其他隔离模式在读取请求、授权或锁前拒绝，包括终态重放。所有新对象归原可信 owner，PUBLIC／runtime 无权限。普通 writer、表约束、初始 trigger 和原业务历史不改。

不开放生产、Backend／HTTP／UI 或 scheduler，不处理其他未知事实类型，不称完整拆分。synthetic fresh、真实版本升级、并发、checksum 与独立恢复不替代生产身份、真实 PII、部署或设备验收。
