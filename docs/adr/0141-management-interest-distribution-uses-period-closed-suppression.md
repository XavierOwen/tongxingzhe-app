# ADR-0141：管理兴趣五档分布使用期间整体隐藏

- 状态：已接受
- 日期：2026-08-21
- Slice：6AV
- Requirement：`ANALYTICS-031`、`PRIVACY-023`、`TEST-025`

## 背景

管理分析已有渠道和 current-city 报告。这些报告可能公开同一期间的总数。若兴趣五档只逐格隐藏，查看者可以用一个已显示的
总数减去其他已显示的报告或档位，恢复一个不安全的兴趣档。因此，兴趣报告不能把“其他报告恰好隐藏”当作自己的隐私控制。

兴趣等级是 `0..4` 的有序答案。Slice 6AV 只需要固定分布数量，暂不定义中位数、比例、百分点差或总计。统计单位是 Backend
已接受的有效接触场次，贡献者是可信的 `app_user_id`。

## 决定

注册独立报告：

```text
report:             contact_sessions_by_interest_level_two_periods@1
metric:             interest_distribution@1
dimension:          interest_level
product view class: management (not a DB output field)
granularity:        iso_week_monday_v1
query fingerprint:  management-report:contact_sessions_by_interest_level_two_periods:v1
privacy policy:     management_interest_distribution_privacy_v1
source scope:       backend_accepted_active_contacts_current_revision
```

服务端从项目的 IANA 报告时区和可信 `data_cutoff_utc` 派生截止点之前最近两个相邻、已经结束的完整 ISO 周。期间使用当地周边界
转换后的 UTC 半开区间。客户端不能提交项目、时区、截止点、期间、兴趣等级、筛选或 SQL。

结果固定为 `previous/current × 0..4` 十个格。每个格只返回期间、等级、隐私状态和可选的整数 count。`displayed` 才能返回 count；
`suppressed` 的 count 永远为 `null`。没有 total cell，不返回中位数、比例、百分点差、算术指数或其他派生统计。

对每个期间的每个等级计算：

```text
N = 该期间该等级的有效接触场次数
P = 该期间该等级的不同可信贡献者数量
M = 该期间该等级的单一贡献者最大贡献数
```

单格只有在 `N >= 10`、`P >= 3` 且 `2 × M <= N` 时才可显示。若同一期间任一等级不满足条件，该期间的五格全部
`suppressed`，另一期间独立判断。期间闭包不读取、引用或假设渠道／current-city 报告的隐藏状态。

private policy／executor 只输出固定保护后的网格，不输出贡献者、接触、revision、原始答案、地点、推广对象、PII 或隐藏前值。
`PUBLIC`、runtime 和普通 app role 不能执行私有 policy／executor 或读取中间贡献。实现只交付 DB-only 合同和 synthetic fixture，
不提供 HTTP、runtime bridge、快照、发布 lineage、目录、Flutter、导出、缓存、离线、同步、warehouse 或真实平台证据。

## 未采用的方案

### 逐格隐藏并依赖总数隐藏

不采用。已有报告属于不同版本和来源合同，未来也可能一个报告显示总数而另一个报告隐藏。安全性不能依赖跨报告状态的偶然一致。

### 增加兴趣总计格

不采用。总计会扩大可相减关系，且 count-only 五档分布已经满足本 Slice 的需求。总计和比例需要各自新的威胁模型与互补隐藏设计。

### 把中位数或比例一起交付

不采用。中位数和比例改变可推导信息及测试边界。它们必须在独立版本中定义统计单位、空值语义、隐私政策和输出合同，不能从本
Slice 的 protected cells 在客户端临时计算。

## 后果

- 期间内只要一个等级不安全，五个等级都会隐藏。结果较保守，但跨报告相减不能恢复该期间的某个等级。
- 消费者必须把 `suppressed` 和 `null` 当作隐私状态，不得把它们显示成零，也不得用另一期间或其他报告补回。
- Dart policy 与 PostgreSQL executor 必须读取同一无 PII synthetic fixture，并覆盖边界、排除项、畸形输入和跨报告相减反例。
- 自动测试、Docker、dump／restore 只证明确定性的 DB-only 合同，不证明 HTTP、Flutter、真实用户、真人平台或形式化不可重识别。
