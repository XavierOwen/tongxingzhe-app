---
status: proposed
---

# 历史待分配事实与当前来源候选分离

0127 允许同一接触的不同历史 revision 分别登记待分配关联，而当前 `(contact, source)` 只能保存一份关联。推荐把每项 pending 作为具有原 contact、revision、项目和事件时间的独立历史事实保留，把当前投影的候选选择另行确认。不得自动取最新、按业务值相等合并，或把未选作当前投影的历史事实丢弃。

0129 先实现 metadata-only 处置预检，完整列出历史 pending 和已有当前来源关联。多候选槽要求明确选择；单候选也不构成写回资格。来源映射、当前 revision、原项目及当前 link binding 都进入新的 metadata 指纹，不能只依赖旧 known／pending 指纹。

后续 writer 须逐项建立真实来源应用证据，并用新增 revision 保留原事件时间、项目与全部事实，再显式确认当前投影。历史应用与最终投影的具体 revision 编排仍需验证旧问卷、answers、feed、audit、warehouse outbox 和精确重放，故本决策保留 proposed 状态。0129 不执行这些写入，不修改原 writer，也不放宽 0128 的受限确认合同。
