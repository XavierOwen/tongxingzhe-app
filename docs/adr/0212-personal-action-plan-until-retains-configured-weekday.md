# ADR-0212：个人计划周期结束保留配置的周起始日

- 状态：已接受
- 日期：2026-11-16
- 范围：私有数据库修正；Issue [#669](https://github.com/XavierOwen/tongxingzhe-app/issues/669)
- Requirement：`PLAN-005`、`TEST-196`、`MANUAL-185`
- 关联：[ADR-0050](./0050-weekly-goals-use-a-fixed-plan-time-zone.md)、[ADR-0211](./0211-personal-action-plan-midnight-folds-use-first-occurrence.md)

`Pacific/Apia` 跳过了 2011-12-30（Friday），见 [IANA 数据](https://data.iana.org/time-zones/tzdb/australasia)。
真实 0162 中，周起始日为 Friday 的普通计划在 `2011-12-31T00:00Z` 保存后，周期 start 映射到当地 Saturday 午夜。
旧两参数 until 从这个 Saturday 日期加七天，得到 `2012-01-06T10:00Z`，但下一 Friday 周期已在 `2012-01-05T10:00Z` 开始，两个周期重叠一天。
不改时区或起始日、仅将目标 3 改为 4 的普通新 mutation，也把新版排到较晚的一天，下一 Friday 读取仍得到目标 3。
Apia Saturday 和 UTC Friday 对照均正确衔接。正常 writer 路径重复复现，并以正式 fixture 在 0162 先 RED。

旧 until 只有 UTC start 和时区，无法区分真正的 Saturday 与跳过 Friday 后映射成的 Saturday，必须补充已配置的周起始日。
0163 新增私有 `personal_action_plan_cycle_until_v2(timestamptz,text,integer)`，输入为同一时区和周起始日算出的 resolved cycle start。
从 resolved start 的当地日期回退到配置 weekday，再加七个日历日，交给 0162 的首次午夜 helper 解析。
这样，缺失 Friday 的当前 start 仍为实际存在的 Saturday 午夜，until 则回到下一个 Friday。
不能直接从任意 reference 的当地日期计算 until：Casey 回拨中间会退到前日，必须保留已经解析出的 cycle start。

迁移只替换两个实际调用点：document 传当前版本 weekday，save 传与内层 start 相同的 requested weekday 和时区。
原签名、OID、owner、ACL 及其他属性保留；旧两参数 until 和 0162 helper 不删除、不改写。
新 helper 使用 SQL、STABLE、PARALLEL SAFE、SECURITY INVOKER 和解析后的 RETURN，owner 与原 document 一致，只有 owner 可执行。
不新增业务表、版本字段、runtime grant、生产、Backend、HTTP、UI 或通知入口。

旧行和已存 pending effective 不回写，错误排到 Saturday 的旧 pending 仍可能延迟生效并阻止其间的新修改。
旧 mutation 精确重放不写行，但返回文档的派生 until 使用新计算，不能承诺旧 JSON 字节不变。
PLAN-005 的统计时区、周起始日和 requested 设置按下一周期生效的既有政策保留。
MANUAL-185／TEST-196 覆盖普通创建、目标修改、边界场次、重放、三种连接时区和历史 fold／gap／普通对照。
正式 runner 分别验证 fresh、真实 0162 升级、完整旧行与 catalog、checksum、既有回归和独立恢复；固定提交 PR CI 通过后合并，对应 main CI 通过后关票。
