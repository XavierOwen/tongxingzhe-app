---
status: accepted
---

# 历史待分配事实与当前来源候选分离

0127 允许同一接触的不同历史 revision 分别登记待分配关联，而当前 `(contact, source)` 只能保存一份关联。每项 pending 都保留原 contact、revision、项目和事件时间，当前投影另行明确选择。不得自动取最新、按业务值相等合并，或丢弃未选作当前候选的历史事实。

0129 先实现 metadata-only 处置预检，完整列出历史 pending 和已有当前来源关联。多候选槽要求明确选择；单候选也不构成写回资格。来源映射、当前 revision、原项目及当前 link binding 都进入新的 metadata 指纹，不能只依赖旧 known／pending 指纹。

0130 复用原 v3 writer，为每项 pending 追加原历史完整 snapshot 与明确来源，再为每个 contact 追加进入前 current 的普通事实、answers、非 pair 关联和显式来源候选。每次 base 都使用锁下真实 head，避免触发 stale revision 的三路合并。

metadata-only 回执分别指向原 revision、实际应用 revision 和最终 revision，proof 核对实际 answers、地点 provenance、command、feed、audit 与去标识 warehouse。全批证明在结束前、end guard 和消费后分别执行；每项删除另须与实际应用值和精确 end receipt 对应，避免逐项重复全批证明。

问卷版本固定在 contact 上，不由项目后来发布的新版本替换。协调器先核对历史及入口 current snapshot 的版本；否则原 writer 可能把兼容答案静默改标为 contact 版本。原事件时间保留，修订时间使用真实确认时间。原历史及 binding 不改，新 revision 的 binding 仍由普通 trigger 分配。

所有候选即使只有一项也须明确选择。完整 child 和 contact 集合在 generation fence 前预锁，新增 pending 整批拒绝重取。原关联若已失去资格或不满足普通 writer 校验，整批拒绝，不删关联或补造确认。0128 保留原受限合同，0129 保持只读；0130 只在私有数据库中增加历史／多项处置，不开放 runtime、Backend、HTTP、UI 或生产合并。
