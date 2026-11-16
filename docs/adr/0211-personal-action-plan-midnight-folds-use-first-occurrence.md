# ADR-0211：个人计划回拨午夜取第一次出现

- 状态：已接受
- 日期：2026-11-16
- 范围：私有数据库修正；Issue [#667](https://github.com/XavierOwen/tongxingzhe-app/issues/667)
- Requirement：`PLAN-005`、`TEST-195`、`MANUAL-184`
- 关联：[ADR-0050](./0050-weekly-goals-use-a-fixed-plan-time-zone.md)

真实 0161 基线中，`America/Havana` 以周日为周期起始日，参考时刻为 `2026-11-01T04:30Z`，即第一次当地 `00:30`。
原 cycle start 返回尚未到达的 `05:00Z`，普通首版 save 写出该 effective 时间后返回 SQL NULL。
同日第二次 `00:30`、UTC 和 Chicago 对照返回正常文档。
PostgreSQL 对回拨重叠时间默认采用切换后的 offset，见 [PG16 的歧义时间规则](https://www.postgresql.org/docs/16/datetime-invalid-input.html)。

0162 为个人计划的当地日期边界选取第一次出现的午夜。
新增私有 `personal_action_plan_local_midnight_v1(date,text)`：先求 PostgreSQL 原 nominal，再采样 nominal 本身及前后各连续 24 小时的 UTC offset。
根据这些 offset 构造 UTC 候选，只保留转回原时区后精确等于目标日期 `00:00` 的候选，取最早 UTC。
没有 exact 候选时回退原 nominal，保留 gap 行为。
cycle start 和两参数 cycle until 共同调用该 helper，使相邻周期使用同一个午夜边界。
cycle start 对当前当地日期所属周的起始日期及其后七天各求首次午夜，取不晚于 reference 的最大候选，使本票回拨情形的当前 UTC 周期满足 `start <= reference < until`。

PG16 已确认 Havana 的两次午夜分别为 `04:00Z` 与 `05:00Z`，本决定选择 `04:00Z`。
Casey 在 2010-03-05 的午夜则对应前日 `13:00Z` 与 `16:00Z`，选择 `13:00Z`。
两次午夜之间的 `15:30Z` 已回拨至前日 `23:30`，仍归入 `13:00Z` 开始的新周期，不能退回已经结束的旧周期。
[IANA Antarctica 数据](https://data.iana.org/time-zones/tzdb/antarctica)记录了 Casey 从 UTC+11 回拨至 UTC+8，因此实现不能假定回拨总是一小时。

迁移只改变两个已关闭 EXECUTE 的 cycle helper 函数体，保留其 OID、owner、ACL 和其他属性。
新 helper 使用 SQL、STABLE、PARALLEL SAFE、SECURITY INVOKER 和解析后的 RETURN，owner 与旧 helper 一致，PUBLIC／runtime 没有执行权。
save、read、document 和旧计划行不改写，版本、保存的 effective 时间及 PLAN-005 的下一周期生效政策保留。

旧版本若已经保存较晚的 effective 时间，新 helper 不会使它提前可见。
原参考时刻早于保存值时，历史读取和精确重放仍可能返回 SQL NULL；这些旧异常版本需要独立处理。
MANUAL-184／TEST-195 要求验证 Havana 两次午夜、Casey 三小时回拨、正常与 gap 对照、相邻周期边界，以及真实升级中的旧行和完整函数 catalog 保留。
fresh、升级、checksum、既有 fixtures 和独立恢复须分别留证，局部回归不等于完整 Docker 或固定提交 CI 已通过。
本票不增加 runtime、HTTP、UI 或通知入口；整日跳过（如 Pacific/Apia）的周期行为单列跟踪，不据此声称全部时区日期均已验证。
