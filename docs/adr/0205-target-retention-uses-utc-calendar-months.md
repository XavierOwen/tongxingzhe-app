# ADR-0205：推广对象保留期按 UTC 日历计算

- 状态：已接受
- 日期：2026-11-13
- 范围：私有数据库修正；Issue [#641](https://github.com/XavierOwen/tongxingzhe-app/issues/641)
- Requirement：`PII-004`、`MANUAL-175`、`TEST-186`
- 关联：[ADR-0026](./0026-use-purpose-limited-retention-for-promotion-target-data.md)、[ADR-0043](./0043-promotion-target-merges-are-reversible.md)

保留期此前已采用日历月，但没有指定计算时区。正常创建对象并设置六个月策略后，仅改变 SQL 会话 TimeZone，就能使同一参考事实的绝对截止相差一小时。对象属于 workspace，并可关联多个项目，不能由当前项目的报告时区或某条连接的设置决定其保留期限。

当前截止和新续期事件统一按 UTC 日历加月，保留月末截断及闰年规则，不把月份换算为固定天数。参考时间仍取对象建立、当前有效接触和明确续期中的最新 instant，月数仍来自当前 workspace 策略。提前复核窗口固定为连续 720 小时。UTC 无夏令时，因此这些计算不依赖调用会话，也无需新增对象或 workspace 时区。

历史续期事件及其 `review_due_at` 不回填；精确重放仍返回原事件的截止。当前动态截止按新规则重算。已有预览继续按原规则检查当前截止是否漂移，漂移时要求重新预览，不改写旧收据。JSON 时间字符串原有的显示方式不在本票内统一。

0153 只替换共享截止、续期新截止和复核窗口三处算术。函数身份、权限、配置、锁序与其余实现保留；全部旧业务数据不变。PostgreSQL 16 的 [date_add](https://www.postgresql.org/docs/16/functions-datetime.html) 可显式指定日历运算时区，无需改变整个函数或连接的 TimeZone。

本票不部署生产，不新增表、权限、Backend、HTTP、UI 或 scheduler，不开放组织策略或产品 active merge。非 UTC 连接下尚未到期对象的动态截止可能改变；生产接入仍须按既有发布门槛评审。
