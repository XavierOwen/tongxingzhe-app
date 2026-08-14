# 个人兴趣 3-4 占比趋势只比较两个完整 UTC 七日

状态：**已接受（2026-08-13）**。

关联：Issue #140、Slice 6AF；ADR-0117、ADR-0118、ADR-0128；
`ANALYTICS-003`、`ANALYTICS-004`、`ANALYTICS-005`、`ANALYTICS-007`、
`ANALYTICS-010`、`ANALYTICS-012`、`ANALYTICS-017`、`TEST-005`、`TEST-009`。

## 决定

个人趋势只比较 `interest_3_4_ratio@1`。它使用单次兴趣为 `3` 或 `4` 的有效接触场次作
分子，全部有效接触场次作分母。这个指标沿用 ADR-0118 的整数分子、分母和 half-up 百分比
基点；它是 `localOperational` 来源的 `personalFact`，不是管理报告指标。

## 两个固定期间

一次刷新只读取一次当前 UTC 时钟。较晚期的 `until` 是当天 UTC `00:00`，所以该期是已经完整
结束的七个 UTC 自然日。较早期紧接其前：

```text
current   = [today_utc_midnight - 7 days, today_utc_midnight)
previous  = [today_utc_midnight - 14 days, today_utc_midnight - 7 days)
```

两个期间都使用 `[from_utc, until_utc)` 半开边界，互不重叠。边界上的接触只属于后一个期间。
实现不能使用设备时区、项目报告时区、旅行时区、进行中的日期或任意期间。

## 一次 Drift 读取

两期事实必须在同一个 Drift transaction 中读取。事务使用同一身份、personal workspace 和
项目范围，并共享一次取得的本地 `dataCutoffUtc`。两期结果中的 `dataCutoffUtc` 必须相同；
刷新不能先读取一期、再重新取截止时间读取另一期。

候选集继续排除草稿、接触尝试、作废记录、旧 revision、期间外记录和其他项目。待同步记录只
进入同步覆盖说明，不能被写成后端已经接受的事实。

## 比例与百分点差

每期都显示整数 `numerator / denominator`、既有 half-up 百分比和本地待同步接触数。分母为零时
显示 `0 / 0` 和“暂无可计算比例”，不显示 `0%`。只有两期都有百分比时才显示有正负号的：

```text
percentage_point_delta =
  current.percentage_basis_points - previous.percentage_basis_points
```

百分点差的格式以基点转换为百分比点，并保留正号、负号或零。任一期为空时不显示差值。

比较器必须验证两期的 metric ID／version、统计单位、公式、时间基准、UTC 时区、周期长度、
个人隐私状态、身份／workspace／project 范围和 `dataCutoffUtc`。任何不一致都失败关闭，不
从两个不兼容的结果拼出趋势。

## 观察事实和范围

这项趋势只描述一个人看到的两个历史期间的比例差异。它不表示成功、失败、改进、退步或因果
关系，也不产生团队排名、目标或考核结论。趋势失败或不可比较时，页面继续显示已有“今日”和
“最近七日”个人事实。

本决定不读取后续联系同意占比的两个独立 HTTP GET，不增加管理报告、管理隐私抑制、固定报告
导出、图表、排名、任意指标、任意期间、Backend、PostgreSQL、migration、Drift schema、
离线趋势缓存、历史 `as-of`、报告更正／删除、区域下钻或真机通知验收。

## 后果与边界

趋势计算留在现有本地个人分析层。它不需要新的数据库表、同步合同或服务端查询。客户端需要
在项目切换、同步完成、App 恢复和手工重试时重新读取，并丢弃旧范围的迟到结果。自动测试应覆盖
UTC 边界、排除项、half-up、正／负／零差、空分母、同一 transaction 和共享截止时间；这组测试
不替代真实设备验收。
