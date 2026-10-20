# ADR-0200：other 原因详情以固定占位值完成匿名化

- 状态：已接受
- 日期：2026-10-20
- Slice：7FB／DB 修复
- Issue：[#603](https://github.com/XavierOwen/tongxingzhe-app/issues/603)
- Requirement：`PII-004`、`PII-005`、`TARGET-009`、`TEST-172`、`MANUAL-161`
- 关联：[ADR-0199](./0199-existing-project-relationship-resolution-keeps-history-and-explicit-current.md)、[匿名化威胁模型](../security/promotion-target-anonymization-threat-model.md)

## 已复现的问题

0018 要求原因为 other 的关系 revision 必须有详情。普通 writer 可以合法产生这种历史；既有匿名化函数随后把详情改为 NULL，触发 CHECK，使整笔清除回滚。0138 保留原 pending 原因时会继承此旧问题，并非新 history marker 被清除白名单漏掉。

## 决定

0139 只替换共享 `app_data.anonymize_promotion_target_internal` 中 revision 的敏感文本清除子句。other 的详情改为既有固定占位值 `[已匿名化]`，其他原因的详情仍为 NULL；follow-up note 与 requested note 一律 NULL。占位值不含原文、哈希、用户标识或原文长度，结构化原因仍为 other。

这既移除原敏感文本，也保留原 CHECK 和原原因事实。普通 writer 对 other 详情的要求不变，不为隐私擦除放宽所有正常写入。冲突表没有对应的 other 必填 CHECK，其 proposed note／detail 继续置 NULL，不增加占位分支。

函数的 OID、owner、ACL、签名、search path、锁序、active-merge 门禁、身份授权和精确重放全部保持不变。迁移本身不改数据；只有既有受控匿名化路径在获授权时执行清除。没有新表、函数、FK、权限、Backend／HTTP／UI、scheduler 或生产部署。

## 验证与边界

普通 other 和真实 0138 已确认历史都须经原 retention API 成功匿名化；保留非敏感原因和历史标识，原详情与备注不可从 revision、payload、metadata 或重放恢复。non-other 仍为 NULL，缺 other 详情仍拒绝；清除故障整批回滚，其他上下文逐值保留。

真实 0138 baseline 升级后，先比较全部旧 rows 与 catalog，证明只有这一子句变化，再执行匿名化和重放。fresh、checksum、既有并发和独立恢复继续验证。

本片修复数据库清除，不证明备份擦除、本机离线密文、真实 PII 或生产执行。既有部署和人工设备门槛不变。
