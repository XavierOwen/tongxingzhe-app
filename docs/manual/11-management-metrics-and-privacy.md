# 第 11 章：管理指标如何构造完整网格并隐藏小样本

个人分析和管理分析处理不同的信任边界。个人页可以立即显示本人设备上的事实，并说明哪些接触尚未同步。管理分析只能使用后端已接受的数据，还必须先降低小群体披露风险。

当前实现已固定管理隐私政策、报告请求、完整周期间、私有执行管线、重叠发布判定和不可变快照。
项目报告时区历史、管理能力、可信发布 v2、管理项目选择、快照目录和窄 HTTPS 端点也已接入。
Flutter 可以只读浏览报告、显示固定元数据，并严格验证 canonical JSON v1 内存 artifact；服务端另有独立导出审计、私有区域威胁探针和已发布规范区域树。

Slice 6AE-0 固定个人阶段变更指标合同，6AE-1 增加固定个人读取，6AE-2 在个人页面显示结果；6AF 增加个人兴趣 `3–4` 占比的两期可比趋势。这些切片不交付管理阶段变更报告。Slice 6S 固定 PostgreSQL 地点来源合同；6U 接入 Flutter／Drift、Outbox 和 Backend；6V 用共享 synthetic fixture 对账四层。

当前仍没有生产成员管理、自动发布调度、生产区域报告、真实 GPS 或六平台真机证据。6AH 的服务端审计和 6AI 的内存 artifact 都不证明客户端已经下载、保存、分享或读取文件。

## 先确定统计单位

匿名阈值中的“十个”不是固定指十条数据库行。每个指标必须使用自己的真实统计单位：

- 接触场次和渠道使用有效接触记录；
- 触达人数使用实际参与人数；
- 当前关系阶段使用不同的“对象 × 项目”关系；
- 阶段变更不能用同一关系的重复事件凑足阈值。

本章实现的固定报表只处理 `contact_sessions` v1，所以统计单位是有效接触场次。草稿、接触尝试和已作废接触仍按指标目录排除。

## 阶段变更的个人历史合同

Slice 6AE-0 固定三个个人指标。它们不加入本章已有的管理报告网格，也不新增管理读取入口。

| 指标 | 个人值的单位 | 结果 |
| --- | --- | --- |
| `relationship_stage_change_events@1` | 一次合格阶段变更 revision | 期间内事件数 |
| `relationship_stage_change_direction_distribution@1` | 一次合格阶段变更 revision | `upward`、`downward` 两个固定方向数 |
| `relationships_with_stage_change@1` | 去重的“推广对象 × 推广项目”关系 | 期间内至少发生一次合格事件的关系数 |

三个指标只读取可信当前用户在可信 workspace／project 中执行的 revision。Backend 从已验证
身份取得 `app_user_id`，SQL 再用 `changed_by_app_user_id = trusted_app_user_id` 过滤；客户端
不能提交 actor、workspace 或 project 来改变范围。`MetricTimeBasis` 固定为
`relationshipChangedAtUtc`；`changed_at` 以 UTC 解释，期间固定为
`[from_utc, until_utc)`。`from_utc` 时刻的事件计入，`until_utc` 时刻的事件不计入。当前分配
结束后，结束前已发生的合格事件仍留在原期间。

合格事件满足 `old_stage IS NOT NULL AND old_stage <> new_stage`，且 `changed_fields` 包含
`stage`。初始 `project_entry`、只改 lifecycle 或备注、同阶段 revision 和重复 revision 不计入。
`new_stage > old_stage`
是 `upward`，`new_stage < old_stage` 是 `downward`。同一关系的不同 revision 分别增加事件
数和方向数；`relationships_with_stage_change@1` 使用 `count(distinct (promotion_target_id,
project_id))`，所以一条关系无论发生多少次都只计一次。

个人结果按事件数提供事实，不受管理匿名阈值限制。未来管理报告若采用事件数或方向数，
`managementPrivacyUnit` 固定为不同的“对象 × 项目”关系；`k=10` 必须有至少十个不同关系，
不能用同一关系的重复事件凑数。贡献者保护和互补隐藏仍按通用管理政策执行。本 Slice 不实现
管理阶段变更报告、历史 `as-of`、当前／历史分配归因、导出或 warehouse。

两层消费者读取同一个无 PII fixture：[`relationship_stage_changes_v1.csv`](../../backend/database/fixtures/shared/relationship_stage_changes_v1.csv)。
fixture 覆盖本人／他人、其他项目、UTC 期间前后边界、结束当前分配、`project_entry`、
lifecycle-only、同阶段、上升、下降、同一关系多次变更和重复 revision。Dart 与 PostgreSQL
独立重算事件数、方向数和去重关系数；主场景预期依次为 `event_count = 5`、
`distinct_relationship_count = 4`、`upward_count = 3`、`downward_count = 2`。同一 revision
重复输入或不可信 scope 必须失败关闭。

### Flutter 如何读取这份个人历史

个人“最近七日”页面通过独立的 typed gateway 读取固定端点。请求 wire 只有 `from_utc` 和
`until_utc`；页面当前项目 ID 不发送给 Backend，只用于确认响应属于仍在显示的项目。项目或期间
变化、同步完成、项目设置返回、App 恢复和手工重试都会发起新读取。旧请求即使稍后返回，也不能覆盖新项目或
新期间的状态。本地最近七日统计仍在载入或失败时，远端卡片仍使用同一 UTC 期间独立读取。

Backend 合同可接收一至六位小数，Flutter gateway 则把固定最近七日边界限制为毫秒精度，并发送
规范的三位小数 UTC `Z`。当前页面使用整秒自然日边界，因此不会丢失有效页面输入；未来若开放
任意微秒期间，必须先扩展客户端合同和测试，不能静默截断。

客户端必须完整校验响应，不能只取四个数字：contract、`relationshipChangedAtUtc`、项目、期间、
`data_cutoff_utc`、`authorized_at_utc` 和 value 的 exact keys 都要匹配。两个可信时刻必须相等，
且不得晚于客户端收到响应的时间。四个计数必须是非负安全整数；事件总数等于上升与下降之和，
去重关系数不大于事件数。任一检查失败，卡片显示稳定错误和重试入口，不显示部分结果。

卡片只在 personal workspace 出现。它把事件数、上升数、下降数和去重关系数连同单位读出，
并显示 UTC 半开期间与服务器数据截止。上升和下降是阶段数值方向，不是成功／失败评价。一次关系
可有多次事件，但去重关系数只加一。空期间显示四个零；它不表示服务未启用或数据未知。

这份结果不缓存到 Drift。网络失败只影响阶段变更卡片，不能遮蔽同页的本地接触指标、当前关系
阶段快照或后续联系同意占比。没有远端结果时，客户端也不能用这些相邻事实推算阶段变更历史。

## Slice 6AF：个人兴趣 3-4 占比的两期趋势

Slice 6AF（Issue #140）只在 personal workspace 比较 `interest_3_4_ratio@1`。它不比较五档
兴趣比例、兴趣 `0` 子集、后续联系同意占比或其他指标。这个结果是 `localOperational` 来源的
`personalFact`，只描述本人观察到的事实，不表示成功、失败、改进、退步或因果关系。

### 期间边界

刷新时只读取一次当前 UTC 时钟。把当天 UTC `00:00` 作为较晚期的 `until`，该期就是已经
完整结束的七个 UTC 自然日。较早期紧接其前：

```text
current   = [today_utc_midnight - 7 days, today_utc_midnight)
previous  = [today_utc_midnight - 14 days, today_utc_midnight - 7 days)
```

两个期间都是 `[from_utc, until_utc)` 半开区间，边界相邻且不重叠。`current` 表示最近一个
已经结束的期间，不表示正在进行的日期。实现不能使用设备时区、项目报告时区、旅行时区或任意
期间。

### 同一 Drift 读取和本地截止

两期事实在同一个 Drift transaction 中读取。事务使用同一身份、personal workspace 和项目范围，
只取得一次本地 `dataCutoffUtc`，并把它用于两期结果。两期的 cutoff 不相等时，比较器失败关闭。

候选集继续排除草稿、接触尝试、作废记录、旧 revision、期间外记录和其他项目。待同步记录只
作为同步覆盖说明，不能伪装成后端已接受的数据。项目切换、同步完成、App 恢复和手工重试都会
重新读取；旧项目或旧期间的迟到结果不能覆盖当前页面。

### 单期值和比较条件

每期显示整数分子、分母、按既有 half-up 合同生成的百分比和本地待同步接触数。分子是兴趣等级
`3` 或 `4` 的有效接触场次，分母是同一期的全部有效接触场次。分母为零时显示 `0 / 0` 和
“暂无可计算比例”，不显示伪造的 `0%`。

比较器必须确认两期的 metric ID／version、统计单位、公式、时间基准、UTC 时区、周期长度、
个人隐私状态、身份／workspace／project 范围和本地 `dataCutoffUtc` 一致。只有两期都有百分比
时才显示带正负号的 `current - previous` 百分点差：

```text
percentage_point_delta =
  current.percentage_basis_points - previous.percentage_basis_points
```

百分比基点的差值按百分比点格式化。任一期分母为零、结果不可比较或读取失败时，不显示差值，
但继续显示已有“今日”和“最近七日”个人事实。

### 范围和验证边界

本切片不协调后续联系同意占比的两个独立 HTTP GET，也不增加管理报告、管理隐私抑制、固定
报告导出、图表、排名、任意指标、任意期间、Backend、PostgreSQL、migration、Drift schema、
离线趋势缓存、历史 `as-of`、报告更正／删除、区域下钻或真机通知验收。

自动测试覆盖 UTC 边界、scope、排除项、half-up、正／负／零差、空分母、同一 transaction、共享
`dataCutoffUtc` 和不可比较结果。小屏、200% 字号、键盘路径、heading、屏幕阅读器语义和中英文
文案属于自动 Widget 测试；它们不等于真机通知验收。

## 为什么必须先建立完整网格

如果 SQL 只返回数据中实际出现的渠道，缺失行可能表示零，也可能表示查询遗漏。调用者无法区分这两种情况，也无法统一执行隐私政策。

`contact_sessions_by_channel_two_periods` v1 固定返回 previous 和 current 两期。每期都有一个总计和七个稳定渠道，因此结果始终有 16 格。没有贡献的渠道也会生成一格，但该格只返回 `suppressed`，不会返回精确零。

固定网格还限制查询自由度。客户端不能增加未知维度、任意日期范围、区域下钻或自定义 SQL。更开放的分析需要新的威胁模型，不能通过给当前函数增加可选参数实现。

## 三项显示底线

政策先按“期间 × 渠道 × 推广者”汇总有效接触数。对每个格子计算：

```text
N = 有效接触场次总数
P = 有贡献的不同推广者数量
M = 单一推广者的最大贡献数

可以显示 = N >= 10 且 P >= 3 且 2 × M <= N
```

最后一个条件使用整数比较。`M = 5, N = 10` 恰好为一半，可以显示；`M = 6, N = 10` 必须隐藏。整数比较不会在 50% 边界产生浮点舍入差异。

这三项条件必须同时满足。十条接触若只来自两位推广者，仍不能显示；三位推广者若一人贡献六条，也不能显示。

## 互补隐藏为什么还要处理总计

假设一个渠道因样本不足而隐藏，其他渠道和同期总计都显示。读取者可以用总计减去其他渠道，恢复隐藏渠道的精确值。

当前固定报表采用一条保守且确定的规则：只要同期任一渠道被隐藏，同期总计也隐藏。另一不重叠期间独立判断。以后增加比例或多层区域时，必须为每个加法关系重新设计互补隐藏，不能假设当前树状规则自动适用。

## 隐藏结果在类型上没有数值

[`SuppressedMetricValue`](../../lib/features/contact_metrics/metric_contract.dart) 不保存真实数量、贡献者数量或最大贡献值。`MetricResult` 只在 `privacyStatus = suppressed` 时接受这个类型；若调用者尝试把精确 `CountMetricValue` 标成隐藏，构造过程会拒绝。

个人兴趣页可以使用 [`RatioMetricValue`](../../lib/features/contact_metrics/metric_contract.dart) 保存穷尽五档比例，也可以使用 [`SubsetRatioMetricValue`](../../lib/features/contact_metrics/metric_contract.dart) 保存兴趣 `3–4` 或 `0` 的独立子集比例。两种值都保留可复算的整数分子、分母、缺失／排除计数和百分比基点，因为它们是本人自己的 `personalFact`。这不表示管理报告可以接收相同精确值。管理比例必须先完成真实统计单位阈值和互补隐藏；被隐藏的管理单元仍只能使用 `SuppressedMetricValue`，不能把精确比例包在另一种值类型中绕过隐藏。

对象当次反应五档比例也属于个人 `personalFact`，但统计单位是 contact-target link，分母只包含当前已填关联。`NULL` 只作为未填写覆盖，不进入五档比例。即使分母使用对象关联，个人页仍只显示接触场次同步覆盖；管理报告不能直接接收这项个人精确比例，未来若纳入管理分析，必须另行定义真实统计单位、阈值和互补隐藏。

个人本地结果继续带 `MetricSyncCoverage`。管理结果来自后端已接受事实，不伪造“仅本机”或“待同步”数量，因此同步覆盖为不适用。来源层明确标为 `backendOperational`。

[`ManagementContactSessionPrivacyPolicyV1`](../../lib/features/contact_metrics/management_privacy_policy.dart) 是纯政策模块。它不读取成员关系，也不授予查看权限。输入必须是服务端已经按固定报表定义聚合的可信贡献，不能接收客户端声明的推广者身份。

## Dart 与 PostgreSQL 如何对账

两端读取同一个 synthetic 文件：[`management_contact_sessions_v1.csv`](../../backend/database/fixtures/shared/management_contact_sessions_v1.csv)。文件包含以下场景：

- 所有渠道恰好达到十个单位、三位推广者和 50% 边界；
- 九个单位；
- 十个单位但只有两位推广者；
- 十个单位但一人贡献六个；
- 一个渠道隐藏后，同期总计执行互补隐藏。

Dart 测试验证 `MetricResult` 和固定顺序。PostgreSQL fixture 把相同贡献送入 [`protect_management_contact_session_grid_v1`](../../backend/database/migrations/0023_management_contact_session_privacy.sql)，核对相同的显示状态和值。

隐私政策 SQL 位于 `app_private` schema。`tongxingzhe_runtime` 没有 schema 使用权或政策函数执行权。可信发布 v2 在同一私有 schema 中组合这些政策；生产 Backend 只能通过 `0036` 的固定报告发布 bridge 和 `0033` 的单份读取 bridge 使用它，不能直接执行政策或动态报告。

## 固定报告请求为什么只有两个字段

第一版客户端只能提交以下 JSON：

```json
{
  "report_id": "contact_sessions_by_channel_two_periods",
  "report_version": 1
}
```

客户端不能提交项目 ID、时区、日期范围、维度、筛选或导出字段。项目和请求者来自已验证的 Backend 上下文。项目报告时区和数据截止时间也必须由服务端决定。若客户端可以指定这些字段，它就能制造许多重叠查询，并扩大通过比较结果恢复小样本的机会。

[`canonicalizeManagementReportRequest`](../../backend/server/src/management-report-contract.ts) 把有效输入映射为一份固定定义。定义包含 `contact_sessions` v1、渠道维度、周粒度、相邻两期、隐私政策版本和 `view_anonymous_analytics` capability。任何额外字段、未知报告或未知版本都返回稳定的拒绝结果。

PostgreSQL 在 [`0024_management_report_contract.sql`](../../backend/database/migrations/0024_management_report_contract.sql) 中保存同一份不可变定义。私有规范化函数返回稳定的 `query_fingerprint`：

```text
management-report:contact_sessions_by_channel_two_periods:v1
```

这个指纹用于审计和对账。它不是密码、token 或匿名化手段，也不授权任何查询。

审计信封只保存请求者内部 ID、项目 ID、报告 ID 与版本、查询指纹、UTC 请求时间和结果状态。它不保存报表格值、贡献者数量、最大贡献值或隐藏的精确值。可信发布 v2 使用同样的最小化原则，并另存当次授权关系、能力 grant、时区 revision 和底层快照关联。`0036` 只把已经验证的身份和幂等键交给该合同。`0032` 增加私有快照访问审计，`0033` 的生产读取端点复用该审计。

TypeScript 与 PostgreSQL 都读取 [`management_report_requests_v1.csv`](../../backend/database/fixtures/shared/management_report_requests_v1.csv)。fixture 包含有效请求、未知报告、未知版本，以及客户端伪造项目、时区、日期、维度、筛选和导出字段的负向场景。

## 两个完整周如何确定

固定报告定义包含 `iso_week_monday_v1` 边界版本。这个字段来自服务端注册表，不是客户端参数。可信发布 v2 从项目配置取得报告 IANA 时区，并用数据库固定的 UTC 截止点调用期间解析器。

解析器先在项目报告时区中找到不晚于截止点的最近一个周一 `00:00`，再向前取两个完整当地自然周。`previous` 是较早一周，`current` 是较晚一周。这里的 `current` 不表示正在进行、尚未结束的本周。两个区间都采用 `[start, until)` 半开形式，因此前一期的 `until` 必须等于后一期的 `start`，边界上的一条接触只会进入一期。

数据截止点和 `current.until` 是不同概念。截止点说明后端事实新鲜到何时；`current.until` 是最近一个已经完成的周边界。只取完整周可以避免把七天完整数据与三天的进行中数据直接比较。

不能先算一个 UTC 边界，再固定减去 `168` 小时。正确做法是分别把每个当地周一午夜转换为 UTC。共享 fixture [`management_report_periods_v1.csv`](../../backend/database/fixtures/shared/management_report_periods_v1.csv) 包含以下证据：

| 项目报告时区 | 场景 | 较早一周 | 较晚一周 |
| --- | --- | ---: | ---: |
| `UTC` | 普通周 | 168 小时 | 168 小时 |
| `Asia/Shanghai` | 无夏令时 | 168 小时 | 168 小时 |
| `America/Chicago` | 春季进入夏令时 | 167 小时 | 168 小时 |
| `America/Chicago` | 秋季退出夏令时 | 169 小时 | 168 小时 |

`CST` 等缩写不合格，因为它可能指不同地区。空值、未知时区和无限截止点也会被拒绝。TypeScript 的 [`resolveManagementReportPeriods`](../../backend/server/src/management-report-periods.ts) 与 PostgreSQL 的私有 `resolve_management_report_periods_v1` 读取同一 fixture，对账边界、相邻性和时长。

`0025_management_report_periods.sql` 只固定期间读取合同，本身不保存项目时区。`0029_project_reporting_time_zone.sql` 后续增加私有版本历史和生效规则。两个 migration 都不开放 runtime 执行权。

## 私有执行管线如何筛选事实

[`execute_management_contact_session_report_v1`](../../backend/database/migrations/0026_management_report_execution.sql) 只接受固定报告 ID／版本、可信项目 ID、可信项目报告时区和可信 UTC 数据截止点。前三个查询条件之外的维度、日期范围和筛选仍不存在。

函数按以下顺序处理：

1. 规范化固定报告定义，并确认项目仍有效；
2. 解析两个完整周；
3. 只读取同一项目、`lifecycle_status = active`、初次提交时间不晚于数据截止点、实际发生时间位于两个半开周期间的 `contacts`；
4. 在函数内部按“期间 × 渠道 × `app_user_id`”计数；
5. 立即把贡献送入完整网格与隐私政策，只返回保护后的 16 格。

`contact_attempts` 不在查询来源中。作废接触、右边界上的下一期接触、截止后才提交的接触和其他项目接触也不进入。`app_user_id` 只作为内部贡献者键，不会出现在结果中。输出格只有期间、渠道／总计、稳定顺序、可选数量和隐私状态；隐藏格的数量是 JSON `null`，不是先发送精确值再要求客户端隐藏。

这个函数读取接触的当前投影，所以它形成动态报告，不是“截至过去某一时刻”的历史投影。数据截止点限制初次提交事实并说明本次查询的新鲜度，但不会倒转后来发生的修订。后面的快照会冻结本次受保护输出和来源 change sequence；它仍不能把旧截止参数变成可重新执行的 `as-of` 查询。

`0026_management_report_execution.sql` 的 fixture 建立两个项目、三位 synthetic 推广者和两个完整周。每期十条合格语音通话按 `5 + 3 + 2` 分布，因此两个语音格显示 `10`；其他 14 格隐藏且值为 `null`。fixture 还混入上述排除记录，并检查整个 JSON 不含贡献者 ID、贡献者数量、最大贡献、触达人数、兴趣、地点或对象资料。

该执行函数仍位于 `app_private`。它没有成员授权、访问审计或 runtime 执行权，不是可以由 App 调用的管理 API。

## 为什么重叠报告还要检查历史格

固定请求不能阻止动态数据变化。假设一个完整周先显示十个语音通话，后来补录一条发生在该周的接触。下一次滚动报告会再次包含同一周，并显示十一个。读取者比较两份结果就能知道新增量是一个。若读取者还知道外部事实，风险会继续增加。

[`assess_management_report_pair_release_v1`](../../backend/database/migrations/0027_management_report_pair_release.sql) 比较两份已经受保护的固定报告。它用实际 `start_utc` 和 `until_utc` 匹配共享期间，不使用会随滚动报告改变的 `previous` 或 `current` 标签。

发布判定检查以下条件：

- 两份文档必须是同一报告版本、项目、时区、查询指纹和隐私政策；
- 每份文档必须有完整的 16 格，`suppressed` 格只能带 JSON `null`；
- 共享格的隐私状态不能改变；
- 两次均为 `displayed` 的共享格不能改变数量；
- 没有共享期间的报告对不能用这个判定证明安全，因此返回 `blocked`。

稳定的一期或两期重叠可以返回 `approved`。数量变化返回 `shared_displayed_value_changed`，抑制状态变化返回 `shared_cell_privacy_status_changed`。审计判定不包含类别值、变化前后的数量或贡献者资料。

这个函数只提供发布前判定。`0028_management_report_snapshots.sql` 在同一私有事务中读取可信快照并强制执行它。两个函数都位于 `app_private`，runtime role 无权执行。

`0027_management_report_pair_release.sql` 的 fixture 建立三个相邻周。稳定滚动报告共享一个周并通过；相同周期的重复报告共享两个周并通过。随后 fixture 加入两条补录，使一个共享格从 `10` 变成 `11`，另一个从 `suppressed` 变成 `displayed`，发布判定必须阻止。fixture 还验证互补隐藏、九个单位的稀疏格、无共享期间、伪造隐藏值、任意日期、区域维度和排除已知推广者等探针。

## 快照发布为什么必须是一个事务

[`release_management_report_snapshot_v1`](../../backend/database/migrations/0028_management_report_snapshots.sql) 不接受报告 JSON。它接受私有调用方提供的内部用户、项目、固定报告身份、可信项目报告时区、数据截止时间、请求时间和 UUID 幂等键，然后直接调用私有执行管线。这样调用者不能提交一份形状正确、但没有真正经过贡献者保护的伪造报告。这个 v1 仍接收时区文本，因此不能作为未来生产 HTTP 入口。

函数依次取得幂等请求锁和稳定 report lineage 锁。lineage 使用项目与逻辑报告身份，不因报告版本或时区改变而重新开始。取得锁以后，函数才读取最近的已发布快照。两个并发发布因此不能都把自己当作首次基线；后到的事务必须看见先提交的结果。

发布事务按以下顺序工作：

1. 相同幂等键和相同业务参数直接返回首次结果；重试时新的服务端时间不改变原审计，其他参数变化则拒绝复用；
2. 在同一 SQL statement snapshot 中生成受保护报告并读取该项目的 `change_feed.change_sequence` 水位；
3. 再次验证报告只有固定的 16 格，且每个隐藏格都是 JSON `null`；
4. 没有历史时建立唯一的 `approved_baseline`；已有历史时调用 6F 比较；
5. 只有 `approved_baseline` 或 `approved` 才写入 `management_report_snapshots`；
6. 每个正常完成的尝试都写入 `management_report_release_attempts`，但 `blocked` 尝试不保存候选报告文档。

快照表保存完整的受保护报告、报告和指标版本、查询指纹、隐私政策、实际 UTC 周边界、项目报告时区、数据截止时间、来源 change sequence、发布者和上一快照。发布尝试只保存请求上下文、比较／发布快照 ID、格数、结果和原因码。它没有候选 `cells`、`value_count`、贡献者数量、最大贡献或抑制前值。

报告版本、查询指纹或时区与既有 lineage 不一致时，结果是 `release_lineage_context_changed`，不是另一份首次基线。同一 cutoff 不能用新幂等键重复发布。无共享期间、共享显示值改变或隐私状态改变也只留下阻断审计。

两张表都用 trigger 拒绝普通 `UPDATE` 和 `DELETE`。这里的“不可变”表示产品操作不能静默覆盖历史，不表示资料可以永久绕过删除规则。未来账号或组织删除需要单独的窄权限清除流程；真正允许变化的更正版报告也需要新的威胁模型，不能通过关闭 6F 判定实现。

来源 change sequence 说明生成时看见了哪一批运营变更，但它不是完整历史投影。当前执行函数仍读取 contact 的当前 projection，所以现阶段能证明的是“已发布的受保护输出不会漂移”，不能声称数据库可以按旧水位重新算出同一报告。

当前 v1 把固定 `report_version` 和 `query_fingerprint` 作为计算合同身份。渠道接触场次报告不读取问卷兼容映射，也不读取区域视图，所以这两项在本报告中不适用。未来报告一旦依赖问卷或区域版本，必须把对应版本写入 protected document 并发布新报告版本，不能沿用当前身份。

历史 v1 发布和读取函数仍没有 runtime 权限。`0031` 的私有 v2 已把 `0030` 授权、`0029` 时区 revision 和历史 `6G` 发布函数接在同一事务中。`0036` 与 `0033` 的 HTTP gateway 都先验证认证 token，再由各自的窄 bridge 映射内部用户；runtime 始终没有 `app_private` 的通用执行权。

## 项目报告时区如何保存和生效

[`project_reporting_time_zone_versions`](../../backend/database/migrations/0029_project_reporting_time_zone.sql) 只为活动组织项目保存 IANA 时区。个人项目、归档项目和已删除 workspace 都不能建立管理报告时区。`CST` 等缩写、未知时区、`posix/*` 和 `right/*` 也会被拒绝。

首次配置从服务端接受请求的时刻生效。系统不把配置倒写到本周周一，因为该版本在请求前并不存在。后续变更由当前旧时区结束自己的周期：系统把请求时刻转换到旧时区，计算下一个当地周一 `00:00`，再转换回 UTC。它不按固定 `168` 小时相加，所以芝加哥的春秋夏令时边界仍正确。

每个项目最多有一个待生效版本。读取函数用半开时间边界选择版本：生效时刻之前返回旧版本和 pending，新边界时刻返回新版本。未配置项目会失败，不会静默采用 UTC、设备时区或客户端值。

配置入口先取得变更请求锁，再取得项目时区锁。相同 UUID 和相同业务参数返回首次版本；重试产生的新服务端时间不会改变结果。两个并发请求使用同一期望版本时，只有一个可以追加下一版本。版本表另用 trigger 拒绝无效直接插入、`UPDATE` 和 `DELETE`。

`0031` 没有修改历史 `0028` migration，也没有给既有快照回填时区版本。它用独立的不可变尝试记录把新发布关联到准确 revision。既有 v1 快照只能证明自身保存的时区文本和 UTC 边界；v2 遇到这种 legacy lineage 会在生成候选报告前失败关闭。6G v1 继续保持私有且无 runtime 权限。

## 管理报告授权链如何工作

登录成功只说明“这次请求来自哪个外部身份”。Backend 还要把它映射为同行者内部用户，并逐层回答三个不同问题：这个人现在属于组织吗，是否被明确分配到这个项目，以及是否被明确授予本次操作所需的能力。任意一层缺失都必须拒绝。

[`0030_management_report_authorization.sql`](../../backend/database/migrations/0030_management_report_authorization.sql) 把这三层保存为独立、带有效期的事实：

1. `organization_memberships` 保存内部用户与组织 workspace 的关系；
2. `project_memberships` 保存该组织成员与一个具体项目的关系；
3. `management_report_capability_grants` 保存该项目成员的一项具体管理报告能力。

项目成员区间必须完全位于组织成员区间内，能力区间又必须完全位于项目成员区间内。所有区间都使用 `[active_from_utc, inactive_from_utc)`：开始时刻立即有效，结束时刻立即失效。结束记录后不能改写身份、延后结束、重新打开或普通删除。退出后重新加入会取得新的成员关系 ID，因此旧项目关系和旧能力不会自动复活。

第一版只有两个管理报告能力：

- `view_anonymous_analytics` 允许受保护读取入口查看匿名管理分析；
- `release_management_reports` 允许私有可信发布入口尝试建立正式报告。

两项能力互不包含。项目管理员角色、组织所有者角色、当前项目选择和登录账号都不是替代凭证。发布入口若以后还要在响应中返回报告内容，必须同时检查发布与查看能力。

私有 `resolve_management_report_authorization_v1` 不接收客户端时间或报告的数据截止时间。它依次取得组织、项目和能力 transaction lock，再使用数据库当前时间检查活动账号、未删除组织、活动项目和三层有效事实。它只返回内部 ID、能力和授权参考时间，不返回角色、报告格、个人资料或可重复使用的 token。

“在同一事务中消费”是安全要求，不是性能建议。解析器与成员／能力撤权使用相同的 transaction lock。若受保护操作先取得锁，撤权会等该操作提交；若撤权先提交，后来的解析会看见结束边界并失败。调用方若先解析、提交事务，再在另一个事务执行报告操作，就会重新制造检查与使用之间的空窗。

Flutter 不能读这些表，`tongxingzhe_runtime` 也不能执行解析器。`0036` 的窄发布 bridge 在同一 statement 中调用可信发布 v2 并消费发布授权；`0033` 的窄读取 bridge 在同一 statement 中消费查看授权。组织邀请、生产授予与撤销、角色组合、权限变更审计和一般组织业务上下文仍须由后续 Slice 实现。

## 可信发布 v2 如何组合三条私有合同

[`release_management_report_snapshot_v2`](../../backend/database/migrations/0031_trusted_management_report_release.sql) 只有五个参数：幂等请求 ID、内部用户、项目、固定报告 ID 和版本。调用方没有位置可以提交 capability、时区、数据截止点、授权时间或报告 JSON。

函数按固定顺序取得授权、请求、项目时区和报告 lineage 的 transaction lock。等待全部结束后，它再次检查 `release_management_reports`。第二次检查返回的数据库时间同时成为授权参考时间和数据截止点；函数再从不可变时区历史中选择当时有效的 revision。这样，发布在等待 lineage 或时区配置期间跨过能力结束边界时，不能继续使用较早的授权结果。

每次正常 v2 尝试把授权关系 ID、能力 grant、授权参考时间、时区 revision、截止点、比较快照、发布快照、状态和原因码写入 `management_report_release_v2_attempts`。这张表不保存候选报告、格值或贡献者。授权失败和未配置时区会回滚，不留下尝试；lineage 失败只写最小原因，不调用 6G 生成器。

没有历史快照时，v2 可以建立一次基线。有历史时，最近快照必须由 v2 建立，而且时区 revision 必须相同。IANA 文本相同也不够：项目从 UTC 改到其他时区再改回 UTC，revision 已改变，发布仍返回 `release_time_zone_revision_changed`。当前合同不自动建立跨时区新基线，因为那会让两套不同期间边界的报告绕过重叠保护。如何安全恢复发布需另行设计。

相同 v2 请求重试会先重新授权，再返回首次最小结果。已经被 v1 使用的 UUID 不可补记为 v2 provenance。发布能力也不自动授予查看能力；返回值只有报告身份、时区 revision、截止点、快照关联、状态和原因码，不含报告内容。

## Backend 如何发布固定报告

生产发布端点是：

```text
POST /v1/projects/:projectId/management-report-snapshots
```

路径只含显式项目 UUID，请求体只含 UUID 幂等键 `release_request_id`。端点不接受 query、报告 ID／版本、时区、数据截止点、范围、筛选、capability、内部用户或报告 JSON。Backend 固定发布 `contact_sessions_by_channel_two_periods` v1，因此客户端不能把该入口变成任意查询面。

Backend 必须先验证 Bearer token，才读取并解析 JSON body。[`0036_runtime_trusted_management_report_release.sql`](../../backend/database/migrations/0036_runtime_trusted_management_report_release.sql) 的 `SECURITY DEFINER` bridge 把可信 issuer 与 subject 映射到既有活动用户，然后以固定报告 ID／版本调用 6J。未知或停用身份不会 bootstrap 账号、workspace 或项目。runtime 只获得这一函数的 `EXECUTE`，不能进入 `app_private` 或直接读取发布尝试、快照、成员关系与接触事实。

production store 使用一次参数化 `pool.query`。PostgreSQL 完成该 statement 的隐式事务后，query promise 才解决；HTTP handler 随后才发送最小发布结果。若提交后网络中断，客户端以同一 `release_request_id` 重试；数据库先重新授权，再返回首次结果，不增加发布尝试或快照。

`approved_baseline`、`approved` 和 `blocked` 都是已经提交的业务结果。响应只含请求、项目、固定报告身份、查询指纹、可信时区 revision、数据截止、比较／发布快照 ID、状态和类型化原因。它不含 `protected_report`、`cells`、计数、贡献者或内部授权证据。调用者若要读取已发布快照，仍须拥有独立查看能力并调用单份读取端点。

缺少或无效 token 返回 `401`；无权返回 `403`；无效 path／body 返回 `400`；请求 UUID 跨项目冲突或项目未配置时区返回稳定 `409`。lineage、时区 revision 或重叠隐私阻断是已提交的 `blocked` 业务结果，使用 `200` 返回原因码。Backend 检测到返回合同漂移、数据库或 bridge 异常时返回 `503`。错误响应不回显 PostgreSQL 消息。服务器对所有响应设置 `Cache-Control: no-store`。

## 授权快照读取如何避免绕过发布来源

[`read_authorized_management_report_snapshot_v1`](../../backend/database/migrations/0032_authorized_management_report_snapshot_read.sql) 只有内部用户、项目和快照三个参数。它固定要求 `view_anonymous_analytics`，调用方不能选择 capability，也不能提交报告 JSON、授权时间、时区、截止时间或访问事件 ID。只有发布能力而没有查看能力的成员会以 `42501` 失败。

函数先用 6I 解析器取得并持有账号、组织成员、项目成员和查看能力锁，再按“快照 ID + 请求项目”查找不可变快照。快照还必须被一条状态为 `approved_baseline` 或 `approved` 的 6J v2 发布记录准确指向。直接由历史 v1 建立的快照、缺失 provenance 和伪造关联都不返回报告内容，也不会回退到其他快照。

成功响应中的 `protected_report` 逐字来自快照表，不重新执行动态报告。发布后新增、修订或作废接触不会改变这次读取的文档。已授权调用中的未知快照和跨项目快照都返回 `not_found / snapshot_not_available`，不让调用方用状态判断另一个项目是否存在该 ID。属于当前项目但来源不可信的快照返回 `untrusted_provenance / snapshot_provenance_untrusted`。

每次已授权调用都会生成新的访问事件。审计保存授权关系、固定查看能力 grant、请求和命中的快照、报告身份、数据库访问时间、状态和原因码，但不保存 `protected_report`、`cells`、贡献者、触达人数、兴趣度或抑制前数值。事件只可追加；插入 trigger 会重新核对授权区间、项目归属和精确 v2 provenance，普通 `UPDATE` 与 `DELETE` 都被拒绝。未授权调用不写访问事件，因为整个 statement 以 `42501` 失败。

读取与撤权使用同一组 transaction lock。读取先取得锁时，撤权等到报告和审计提交；撤权先取得锁时，读取等待后看见失效边界，以 `42501` 结束且不写审计。如果调用方在显式外层事务中取得报告后主动 `ROLLBACK`，访问事件也会回滚。因此 `0033` production store 把读取作为单条自动提交操作，并在数据库调用成功以后才把报告交给客户端。

`0032` 仍位于 `app_private`。`tongxingzhe_runtime` 和 `PUBLIC` 对函数与审计表都没有权限。唯一单份报告读取入口是 `0033` 位于 `app_data` 的四参数 bridge；`0034` 的独立导航上下文不能读取报告。当前仍没有一般 organization session、缓存、latest 查询或其他动态导出；6AH 只提供显式项目／快照的固定 canonical JSON v1 导出。不能把私有函数直接授予通用 runtime role。

## 如何发现并选择管理分析项目

管理分析不复用个人 `SessionContext`。个人上下文会被联系人、同步、问卷和私人计划使用；把组织报告项目混入其中，可能让这些业务误用尚未授权的组织范围。生产 Backend 因此使用两个独立操作：

```text
GET /v1/management-analysis/context
PUT /v1/management-analysis/context
```

GET 只列出当前活动账号、组织、组织成员、项目、项目成员和 `view_anonymous_analytics` grant 同时有效的项目。只有发布能力的项目不会出现。没有有效保存选择时，`current_context` 返回 `null`，即使列表只有一项也不自动选择。

PUT 只接受 `project_id`。数据库在同一事务中调用 6I 解析器，再保存 app user、组织、组织成员、项目、项目成员和查看 grant 的精确 ID。选择与撤权共享三层锁。若选择先取得锁，撤权等待选择提交；若撤权先提交，选择失败且不改写原记录。

列表每次都把保存证据与当前有效链逐项比较。旧 grant 撤销后，即使同一项目后来获得新 grant，旧选择也不会复活。响应只含组织和项目名称与 ID，并用 `authorization: must_reauthorize` 提醒调用方：这是导航偏好，不是授权 token。6L 读取仍按显式项目和快照重新授权。

## 如何列出可选择的可信快照

生产快照目录端点是：

```text
GET /v1/projects/:projectId/management-report-snapshots
```

路径必须带一个显式项目 UUID。端点不接受 body、query、客户端 limit、筛选、时区、报告定义或 capability。6M 的当前选择可以帮助客户端构造路径，但数据库不会把这个选择当成授权证据。

[`0035_management_report_snapshot_directory.sql`](../../backend/database/migrations/0035_management_report_snapshot_directory.sql) 在每次请求中重新检查完整 `view_anonymous_analytics` 授权链。目录只列有成功 6J v2 发布来源的快照；legacy v1、blocked 尝试、缺失或不匹配的来源都不进入结果。结果最多 20 项，并按数据截止时间、发布时间和快照 ID 降序排列。

每项只有快照 ID、固定报告 ID 与版本、项目报告时区、数据截止时间和发布时间。目录成功时在同一事务中追加访问审计。审计保存精确授权证据、项目、数据库访问时间、完成状态和返回数量，不保存快照 ID、报告元数据、报告格或隐藏值。空目录也返回 `200` 和空数组，并写一条返回数量为 0 的审计。

固定排序不代表第一项是“当前”或“最新有效”报告。该目录和读取路径不提供更正版取代关系。客户端选择一项后，仍须调用单份快照端点；该端点会再次授权并追加自己的访问审计。

## Backend 如何在提交审计后交付报告

生产端点是：

```text
GET /v1/projects/:projectId/management-report-snapshots/:snapshotId
```

路径只含项目和快照 UUID，不接受 body 或 query。调用者不能提交内部用户、capability、报告 ID、时区、截止时间或筛选。显式项目范围和 6M 导航选择都不是授权证据；数据库仍按 6I 的组织成员、项目成员和查看能力逐层检查。

Backend 先验证 Bearer token，得到可信 issuer 和 subject。[`0033_runtime_authorized_management_report_snapshot_read.sql`](../../backend/database/migrations/0033_runtime_authorized_management_report_snapshot_read.sql) 的 `SECURITY DEFINER` bridge 只把它们映射到既有活动内部用户，不调用个人上下文 bootstrap。未知身份不会创建 app user、workspace 或 project。bridge 随后调用 6K 三参数读取；runtime 只获得这个 bridge 的 `EXECUTE`，不能使用 `app_private` 或直接读快照和审计。

production adapter 使用一次参数化 `pool.query`。PostgreSQL 完成该 statement 的隐式事务后，query promise 才解决；HTTP handler 在 `await` 之后才写响应。提交后若网络中断，访问审计仍然保留。客户端重试会重新授权并追加另一条访问事件，不复用前一次 event ID。

HTTP 只把数据库结果缩成稳定合同：可信快照返回 `200`、access event ID、快照 ID 和受保护报告；未知与跨项目统一返回 `404`；同项目 legacy provenance 返回 `409`；无权返回 `403`。错误响应没有报告格、授权关系、外部 subject 或 PostgreSQL 错误文字。服务器对全部响应设置 `Cache-Control: no-store`。

## 固定匿名管理报告文件导出如何保持快照和审计边界

6AH 的生产端点是：

```text
GET /v1/projects/:projectId/management-report-snapshots/:snapshotId/export
```

路径只含显式项目和快照 UUID。请求不接受 body、query、报告定义、格式、时区、数据截止点、筛选或其他客户端字段；报告身份固定为 `contact_sessions_by_channel_two_periods@1`。项目或快照路径只是查找范围，不是授权证据。它不提供 latest、动态重算、任意指标或 CSV。

Backend 先验证 Bearer token，再在同一数据库授权边界中重新确认活动账号、组织／项目成员关系，以及 `view_anonymous_analytics` 和独立 `export_management_reports` capability。`release_management_reports` 不自动包含查看或导出权；`export_target_pii`、近期重新认证和推广对象资料权限也不由本 Slice 引入。未通过任一检查的请求不生成文件；未完成完整授权的调用不会写导出事件。

响应使用 UTF-8、`application/json` 和 `Cache-Control: no-store`。本合同中的 canonical 指固定 key 顺序、无多余空白和 UTC 毫秒时间格式，不表示 RFC 8785。顶层 exact keys 固定为 `export_contract_id`、`snapshot_id`、`released_at_utc` 和 `report`。结构示意如下；尖括号只是文档占位符，不会作为字符串写入真实文件：

```text
{
  "export_contract_id": "management_report_snapshot_export_v1",
  "snapshot_id": "<snapshot UUID>",
  "released_at_utc": "<UTC instant>",
  "report": <the fixed protected report object, including exactly 16 cell objects>
}
```

`report` 直接复用已经保存的受保护快照，包括固定定义、指标、来源、报告时区、数据截止、期间和 16 格 `cells`。格子按 `cell_order` 稳定排列；`displayed` 只能携带大于等于 10 的整数，`suppressed` 必须保持 JSON `null`。服务端只序列化已通过阈值、贡献者保护、完整网格和互补隐藏的值，不重新执行动态报告或隐私政策，也不接受客户端自定义字段。同一快照的后续数据变化不能改变其 canonical JSON v1 字节；合同不包含本地化标签、组织名称、贡献者、推广对象、地点、PII 或隐藏前值。

导出读取和普通快照读取是两个审计边界。每次通过身份验证并完成完整授权的导出请求都追加一个独立、不可变的导出事件，记录内部 actor、项目、快照、导出合同、请求时间、结果状态和 event ID，不记录报告格、贡献者、推广对象、地点或 PII。数据库先提交授权、生成和审计，再准备 HTTP 交付；网络中断后的重试重新授权并产生新的导出事件。事件只能证明服务端已完成授权、生成并准备交付，不证明客户端已经落盘、分享或读取文件。

固定匿名管理报告文件导出不等同于推广对象资料导出，也不声称形式化不可重识别。本节不交付 Flutter、浏览器或原生保存／分享、六平台真机验收、缓存、保留／删除策略、区域下钻、报告更正／取代或 Slice 7 的 PII 流程。

## Flutter 如何验证导出 artifact，而不伪造文件结果

6AI 在 [`ManagementReportGateway`](../../lib/management_reports/management_report_gateway.dart) 增加单份
快照导出读取。调用方只传当前显式管理项目和已经由目录返回的快照摘要。HTTP adapter 复用登录
session；第一次 `401` 后只强制刷新并重试一次，第二次 `401` 停止。

成功响应必须同时满足固定 `Content-Type`、`Content-Disposition`、`Cache-Control: no-store`、
`X-Content-Type-Options: nosniff`、导出事件 UUID 和准确 `Content-Length`。Flutter 随后严格解码 UTF-8，
核对 canonical key 顺序、无额外空白、UTC 毫秒时间、目录摘要、固定报告元数据、相邻期间和 16 格。
`displayed` 小于 10、超过 JSON safe integer、`suppressed` 非 `null`、额外地点／PII 字段或任何坐标漂移
都会拒绝整份响应。

成功的 `ManagementReportExportArtifact` 保留服务端原始 bytes；客户端不重新序列化，也不写入 Drift、
缓存或日志。这一结果只证明 Flutter 已取得并验证响应。浏览器下载、原生保存和系统分享需要独立的
capability adapter 和工作单元；取消、失败或成功的语义不能互相替代，也不能反向改变 6AH 导出审计。

6AJ 只接入 Web 浏览器下载。用户先选择“准备 JSON 文件”。Flutter 调用 6AI，并在当前页面内存中
保留验证后的 artifact。准备完成后，页面显示第二个动作“请求浏览器下载”。把这两步分开，可以让
真正的浏览器下载由一次新的用户操作触发，也避免把网络响应到达误当成下载许可。

Web delivery adapter 直接用 artifact 的原始 bytes、固定 MIME 和固定文件名创建 Blob，再通过临时
object URL 和 anchor 请求下载。anchor 在点击后移除，object URL 延后释放。delivery 失败可使用同一
artifact 重试，不会再次调用服务端导出端点。切换管理项目或快照、返回目录或关闭页面会清除 artifact。
非 Web build 使用 unavailable adapter，不会尝试写原生文件系统。

页面只能显示“已请求下载”。浏览器可能自动保存、询问用户或阻止请求，App 无法据此证明文件已经保存、
打开或保留。6AJ 也不证明原生保存、系统分享或其他浏览器可用，更不会改变 6AH 的服务端审计含义。

## Flutter 如何浏览受保护报告

“分析”页保留原有的个人最近七日事实，并增加“管理报告”视图。两个视图使用独立范围：个人视图继续读取个人 `SessionContext`，管理视图只读取 6M 的管理分析上下文。切换管理项目不会切换接触记录、问卷、私人计划或提醒所在的个人项目。

管理视图按以下顺序工作：

1. 调用 `GET /v1/management-analysis/context`。没有保存选择时，页面等待用户明确选择，不因列表只有一项而自动选择。
2. 用户选择项目后调用 `PUT /v1/management-analysis/context`。页面立即清除旧项目的目录和详情，再等待服务端确认。
3. 调用 6N 目录端点。空数组显示“没有可读取的管理报告”，不是错误。
4. 用户选择目录项后，把完整目录摘要交给 6L 读取。单份响应没有发布时间，所以 Flutter 不补造该值；它还会核对快照 ID、报告版本、时区和截止时间与目录项一致。
5. 页面只渲染服务端返回的 16 格。`displayed` 必须带非负整数；`suppressed` 必须带 `null`，页面显示“已隐藏”，不显示 `0`，也不运行客户端隐私算法。

[`HttpManagementReportGateway`](../../lib/management_reports/http_management_report_gateway.dart) 每次请求前取得身份 access token。遇到 `401` 时，它只强制刷新并重试一次。`403`、`404`、`409`、网络失败和无效合同分别进入稳定页面状态。响应只存在于当前 Widget 内存；当前实现没有 Drift 表、文件缓存、通知内容或报告值日志。

目录保留服务端顺序，但界面不把第一项称为“最新”“当前”或“有效”。6BM consumer 不读取 6BN 的 replacement relation，也不从目录顺序推断取代状态。用户离开详情后，键盘焦点回到刚才选择的目录项；选择另一项目后，旧项目的迟到响应会被 generation 检查丢弃。

紧凑宽度和大字号使用逐期间列表，每格有独立的期间、渠道和值／隐藏状态语义。宽屏和正常字号使用三列表格。两种布局显示相同的服务端结果，不在客户端重排或聚合报告值。

## 报告详情如何显示固定定义和隐私边界

Slice 6AG 只使用 6L 已经严格解析并交给 Widget 的字段，不增加新的 wire 字段，也不从
显示文字反推或重新计算指标。详情保留既有的报告时区、数据截止和发布时间，并在同一元数据区
显示以下稳定合同：

| 显示项目 | 固定显示内容 |
| --- | --- |
| 报告定义 | “报告定义”／“Report definition”标签，加稳定的 `contact_sessions_by_channel_two_periods@1` |
| 统计指标 | “接触场次”／“Contact sessions”，加 `contact_sessions@1` |
| 数据来源 | “后端已接受的接触”／“Backend-accepted contacts”，加 `(backend_accepted_contacts)` |
| 隐私规则 | “接触场次隐私规则 v1”／“Contact session privacy rules v1”，加 `(management_contact_session_privacy_v1)` |
| 隐私摘要 | 对 16 个固定格按 `privacy_status` 计数，分别显示 `displayed` 与 `suppressed` 格数 |

稳定 ID 和 version 不能被友好名称替代，因为它们用于复算、审计和发现合同漂移。摘要只数格子：
`displayed` 格必须已有非负 `value_count`，`suppressed` 格的值在服务端就是 JSON `null`，页面继续
显示“已隐藏”而不是 `0`，也不运行客户端隐私算法。中文和英文标签描述同一组字段。

这组字段描述的是已经经过服务端阈值、贡献者保护、完整结果网格和互补隐藏的匿名管理事实。规则
用于降低披露风险，但不构成形式化的不可重识别保证，也不能证明所有外部资料组合都安全。页面因此
不把它写成“绝对匿名”、个人绩效、排名或因果结论；6AG 本身也不新增导出、下载、图表、缓存、动态查询、
更正版或删除规则，6AH 的固定文件合同另见上一节。

## 在 Docker 中验证

先启动 Docker Desktop。然后在仓库根目录运行：

```bash
./tool/run_postgres_tests_in_docker.sh
```

脚本会建立临时 PostgreSQL 16 容器，执行全部 migration、权限检查和 fixture。独立会话检查还会证明三层授权的重叠写入各只有一个成功、授权消费与撤权按事务顺序完成、管理上下文选择与撤权线性化、并发滚动发布等待基线事务，以及相同期望版本只能追加一个报告时区版本。v2 发布与 runtime bridge 检查会让发布等待到能力自然到期，并验证“发布先取得时区锁”和“配置先取得时区锁”两种顺序；单份读取和快照目录检查都覆盖“读取先于撤权”和“撤权先于读取”。随后脚本导出 `app_data`、`app_private` 与 migration 历史，恢复到第二个空库重跑检查。脚本结束后自动删除容器。

并发脚本会提交 synthetic 数据，这些行会进入后面的 dump；普通 fixture 虽然回滚，却会在恢复库再运行一次。新增测试时，两类文件必须使用不同的 synthetic UUID 前缀。若第一次 fixture 通过、恢复后的同一 fixture 报重复主键，先检查命名空间是否与某个并发脚本重叠。

只想验证 Dart 政策时运行：

```bash
flutter test --no-pub test/features/contact_metrics/management_privacy_policy_test.dart
```

只想验证 Flutter 管理报告浏览时运行：

```bash
flutter test --no-pub \
  test/management_reports/http_management_report_gateway_test.dart \
  test/features/management_reports/management_report_browser_view_model_test.dart \
  test/features/management_reports/management_report_browser_test.dart \
  test/l10n/app_strings_test.dart
```

第一项固定身份 token、三条端点和严格 JSON 合同。第二项固定项目切换、迟到响应和重试状态。第三项固定 320 px、200% 字号、键盘焦点、屏幕阅读器语义、固定来源／定义／隐私元数据及 displayed／suppressed 摘要。第四项固定中英文文案的结构。所有测试使用 synthetic HTTP 响应，不证明真实账号拥有报告权限，也不替代服务端的 PostgreSQL 授权与审计测试。

只想验证 Backend 请求、期间和固定导出合同时运行：

```bash
cd backend/server
npm ci
npm test
```

这组 Node 测试还覆盖 canonical JSON v1 的 exact keys、16 格顺序、`suppressed = null`、稳定字节、严格数据库结果解析和不含值的错误响应。它们不替代 Docker 中的双 capability 授权、可信 provenance 或不可变导出审计检查。

Docker 的安装、输出解释和失败容器保留方法见[第 9 章](09-local-docker-and-ci-testing.md)。

## 区域报告为什么先做威胁探针

严格区域树规定每个节点只有一个规范父级，但这不等于每份报表的查询集合互不重叠。一个校园属于一座城市；若同一期同时发布校园数和城市总数，读取者可以把两者与其他已知子区域相减。区域树版本改变后，同一接触也可能从旧范围进入新范围。单格都通过 `k=10`，仍不能自动排除这些组合风险。

Slice 6Q 因此没有给现有生产端点增加区域参数，也没有注册第二份报告。它先建立一个[私有、fixture-first 的候选形状和威胁探针](../../backend/database/migrations/0037_management_region_privacy_probe.sql)。候选只用于自动测试，枚举以下边界：

- 父区域与子区域同时出现，以及两个非父子查询集合有成员交集；
- 同一历史期间在后续报告中的显示值或隐藏状态改变；
- 区域树版本改变后，同一成员进入另一范围；
- 不足十个统计单位、少于三位贡献者、单人超过一半，却被错误标为可显示；
- 总计、区域子格、互补类别或外部已知事实组合后留下可恢复的小残余；
- `current` 与 `original` 混用，或没有版本映射时猜测当前城市；
- 把待解析坐标或非线下 `N/A` 伪装成区域格。

探针返回的不是报表。结果只有探针版本、固定指纹、`approved`／`blocked` 状态和 allowlist 原因码。它没有坐标、贡献者、隐藏数量或生产授权证据。`tongxingzhe_runtime` 无权进入 `app_private` 或执行该函数；Backend 和 Flutter 也没有调用入口。

### `original` 与 `current` 的证据要求

`original` 视图使用接触事实保存的最小区域 ID 和区域树版本。它回答“记录当时归到哪里”。`current` 视图回答“按今天有效的规范区域应归到哪里”，所以必须有明确跨版本映射，或保留可以按当前边界重新解析的来源坐标。

现有 contact current projection 只保存 `region_id + tree_version`；`contact_region_assignments` 还是随 revision 更新的 current projection。Slice 6S 至 6V 为有来源的 revision 保存解析前坐标，Slice 6AK 又固定了私有的一对一跨版本映射证据，但仍没有生产区域报告读取路径。系统不能把旧区域 ID 猜成相似名称的新城市；有坐标时的重新解析、无坐标时的显式映射和目标树的报告截止点仍须分别处理。探针把缺失映射作为失败关闭条件，也不声称已交付两种生产视图。

`pending_resolution` 的含义不同：面对面接触已有坐标，但平台尚未给出规范区域。该记录保留坐标并排除在城市格之外。`not_applicable` 只适用于纯非线下接触，表示地点维度不适用。它不是解析失败、未知城市或零数量。

### 如何运行这组证据

Dart 和 PostgreSQL 读取同一个 [`management_region_privacy_v1.csv`](../../backend/database/fixtures/shared/management_region_privacy_v1.csv)。第一行场景提供完整基线，后续 `probe_patch` 只浅覆盖要攻击的顶层字段；因此新增场景不用复制整个候选，但不能依赖未写明的深层合并。Dart 测试检查结构错误、状态和原因码对账；完整 PostgreSQL Docker 套件检查 migration、fixture、权限、checksum 和 dump/restore：

```bash
flutter test test/features/contact_metrics/
./tool/run_postgres_tests_in_docker.sh
```

第一次使用 Docker 时，先按[第 9 章](09-local-docker-and-ci-testing.md)确认 Docker Desktop 已启动。测试通过只说明当前列出的 synthetic 攻击被稳定识别；它不能证明真实世界中不存在其他外部资料或跨账号组合方式。

## 已发布区域树如何冻结

区域隐私探针依赖一个稳定的区域版本。Slice 6R 给规范树版本增加 `draft` 和 `published` 生命周期。迁移会把已有 release 解释为已发布版本，并保留原节点、边界、接触区域 ID 和解析版本。旧 schema 没有 current 的实际选择时间；迁移基线会把实际选择时间保留为空，只记录迁移观察时间，不能把旧发布时间当作选择时间。新版本先作为草稿编辑，草稿可以增加或修改节点和边界。

私有函数 [`publish_canonical_region_tree_v1`](../../backend/database/migrations/0038_freeze_published_canonical_region_trees.sql) 只接受完整的 `tree_version` 和是否成为 `current` 的标志。它在一个事务中检查严格单父、无环、城市父链和至少一条可解析边界，再按 `C` 排序、固定浮点输出和规范 JSON 编码计算内容指纹。指纹覆盖节点父级、名称、`kind`、`attributes` 和边界，不随 session 的浮点输出设置变化。相同内容重算得到相同指纹，任一内容变化都会改变指纹。

发布成功后，属于该 `tree_version` 的节点和边界不能直接插入、修改或删除。release 的版本、发布时间和内容指纹不能改写。草稿编辑和发布共用一把事务锁；发布开始验证后，新编辑只能等待，并在发布提交后因版本已冻结而失败。`current` 是解析器读取的单值投影，不是对旧事实的覆盖。发布新 current 时，旧版本只失去投影位置，节点、边界和发布时间仍可读；数据库同时追加一条选择记录，保存顺序、前后版本、选择时间、记录时间、来源和内容指纹。唯一 current 约束、发布锁和重复版本的稳定 `55000` 冲突一起防止双 current、交叉指纹或半个发布。

运行时通过 6T 的窄函数 `resolve_canonical_region_with_provenance` 取得解析结果、发布内容指纹和固定解析器合同。该函数复用 [`resolve_canonical_region`](../../backend/database/migrations/0007_canonical_region_resolution.sql) 的匹配结果，只补充这两项来源证据。`tongxingzhe_runtime` 不能直接读取或写入区域表、release 选择历史，也不能执行私有发布函数。发布函数由无登录、无成员的专用数据库角色执行；trigger 检查这个函数身份，维护会话不能用 session 设置绕过冻结。区域维护身份应在发布前先完成 check、fixture 和并发验证。

### 如何验证冻结合同

没有 PostgreSQL 时，从仓库根目录运行完整 Docker 套件：

```bash
./tool/run_postgres_tests_in_docker.sh
```

第一次使用 Docker 时先启动 Docker Desktop。脚本不要求本机安装 `psql`，也不连接 production 数据库。

脚本会启动临时 PostgreSQL 16 容器，从空库运行 migration 两次，第二次检查历史 checksum。它按文件名运行所有 check、fixture 和并发脚本，所以会包含 [`verify_frozen_canonical_region_tree_releases.sql`](../../backend/database/checks/verify_frozen_canonical_region_tree_releases.sql)、[`0038_frozen_canonical_region_tree_releases.sql`](../../backend/database/fixtures/0038_frozen_canonical_region_tree_releases.sql) 和 [`verify_canonical_region_tree_release_concurrency.sh`](../../tool/verify_canonical_region_tree_release_concurrency.sh)。脚本还会导出 schema，在没有源 cluster roles 的第二个 PostgreSQL 容器中运行 [`postgres_prepare_restore_roles.sh`](../../tool/postgres_prepare_restore_roles.sh)，再恢复 archive 并重复 check 和 fixture。成功后脚本自动删除两个容器。

如果只需要在已经运行的测试库检查这一票，先运行 migration，再按以下顺序执行：

```bash
export DATABASE_URL='postgresql://postgres:postgres@127.0.0.1:5432/tongxingzhe_test'
./tool/postgres_migrate.sh
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/checks/verify_frozen_canonical_region_tree_releases.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/fixtures/0038_frozen_canonical_region_tree_releases.sql
./tool/verify_canonical_region_tree_release_concurrency.sh
```

这些文件只使用 synthetic 数据。并发脚本会提交自己的测试行，普通 fixture 会回滚；不要把测试库当作生产库，也不要把 Docker 通过写成真实维护者发布或六平台验收。

冻结版本是 6S 地点 provenance 的前置条件，不是 provenance 本身。Slice 6S 在 PostgreSQL 中追加保存解析来源和原始证据；6U 接入 Flutter／Drift、Outbox 和 Backend；6V 增加四层对账。生产区域报告还必须另行确定完整网格、互补隐藏、授权、快照 lineage 和自己的重识别 fixture。本节不增加区域报告 API、管理 UI、缓存或导出。

## Slice 6AK 如何固定跨版本区域映射证据

有些旧 contact revision 只保留当时的规范区域，没有可按新边界重新解析的坐标。Slice 6AK 为这种
`resolved_region_only` 来源建立私有的显式一对一映射注册表。它不是区域名称对照表，也不把 target tree
的 current 选择写成节点映射。来源和目标分别由 `tree_version + region_id + content_fingerprint`
标识；两个 release 都必须已经发布，节点必须真实属于相应版本，请求中的指纹必须等于 6R 冻结内容。

私有登记函数同时保存稳定 mapping ID、request ID、固定 evidence contract、64 字符小写十六进制
evidence digest 和数据库写入时间。digest 是外部审核材料的最小引用，不把自由说明、坐标、联系人或 PII
复制进数据库。完全相同的 request 重试返回原结果；同一 request 改载荷，或同一来源节点到同一目标
tree 的第二个目标，以及多个来源到同一 target 的合并，都会失败关闭。表级 trigger 拒绝直接插入、
更新、删除和清空；映射只能通过由无登录、无成员的 `tongxingzhe_region_mapping_writer` 拥有的
`SECURITY DEFINER` 函数追加。区域发布身份只有函数执行权，没有映射表写入权。

映射行保存在受保护的 `app_data`，登记和解析函数位于 `app_private`。runtime、PUBLIC 和普通管理
分析能力都不能直接读取映射表或执行这两个函数。

私有解析函数只接受显式来源、目标版本和两个内容指纹。全部事实精确一致时返回唯一 `mapped` 结果；
缺失记录返回稳定的未映射状态，错误指纹、草稿树、未知节点、同版本和冲突输入直接拒绝。v1 不表示
拆分、合并、retired 或 ambiguous；这些情况必须保持未映射，不能按名称、父链或坐标相似度猜测。
`pending_resolution`、`not_applicable` 和来源不完整记录没有来源区域 ID，不进入这张表。

完整 Docker 套件会自动运行
[`verify_canonical_region_version_mappings.sql`](../../backend/database/checks/verify_canonical_region_version_mappings.sql)、
[`0053_canonical_region_version_mappings.sql`](../../backend/database/fixtures/0053_canonical_region_version_mappings.sql)
和 [`verify_canonical_region_version_mapping_concurrency.sh`](../../tool/verify_canonical_region_version_mapping_concurrency.sh)。

它从空库迁移，检查 migration checksum、对象 owner、固定 `search_path`、runtime／PUBLIC 权限和追加不可变，
再让两个事务争用同一 source + target tree，证明至多一个目标提交。最后导出数据库，在没有源 cluster roles
的第二个 PostgreSQL 16 容器恢复并重复 check 与 fixture。

如果只在已经运行的测试数据库验证本切片，执行：

```bash
export DATABASE_URL='postgresql://postgres:postgres@127.0.0.1:5432/tongxingzhe_test'
./tool/postgres_migrate.sh
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/checks/verify_canonical_region_version_mappings.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/fixtures/0053_canonical_region_version_mappings.sql
./tool/verify_canonical_region_version_mapping_concurrency.sh
```

这些测试只使用 synthetic tree、节点、指纹和 evidence digest。通过表示数据库拒绝当前列出的伪造、
冲突和并发双写；它不证明维护者审核正确，不证明两个真实区域等价，也没有交付 production current
区域报告、完整隐私网格、授权、快照 lineage、HTTP、Flutter、缓存或导出。

## Slice 6AL 如何解析私有区域归属证据

Slice 6AL 为未来固定区域报告提供一个私有、只读的 typed resolver。调用方必须明确选择
`original` 或 `current`。`original` 的两个 target 参数必须为 `NULL`；`current` 视图才同时提供已发布
目标树的 `tree_version` 和精确 `content_fingerprint`。resolver 不读取 current 选择开关，也不替调用方
决定报告截止点的目标树。

`original` 只验证地点来源自己的 release、内容指纹、区域节点和城市父链，然后返回原始区域 tuple。
来源事实不完整或指纹不一致时，resolver 失败关闭。它不能用 `contact_region_assignments` 当前投影补造
历史来源。

`current` 对 `resolved_from_coordinates` 使用来源保存的原始坐标和指定目标树的边界。只接受唯一最深
候选；其他命中必须属于同一父链。零命中返回 `unmapped`。跨父链或同深度多候选返回 `ambiguous`，
不能用稳定排序把歧义变成一个结果。`resolved_region_only` 在来源和目标树相同时保留已验证来源，
跨版本时只调用 Slice 6AK 的显式一对一 mapping resolver，不组合映射链。

`pending_resolution`、`not_applicable` 和 `legacy_incomplete` 没有可报告区域 ID，返回不含区域 tuple
的稳定 `not_reportable` 状态。成功结果只带固定 contract、视图、状态、原因和区域 ID、树版本、内容
指纹。输出不含 source ID、contact、revision、贡献者、地点名、坐标或 PII。错误视图、缺少 current
目标、草稿目标、目标指纹漂移、未知目标节点或缺少城市父链均失败关闭。

这个 resolver 由无登录、无成员的 `tongxingzhe_region_attribution_reader` 拥有。`tongxingzhe_runtime`、`PUBLIC`、区域
发布者、mapping writer 和 provenance writer 都不能执行它或直接读取新增能力。本 Slice 不注册生产区域
报告，不选择 current tree，不实现历史 `as-of`、接触统计资格、完整区域网格、重叠查询、互补隐藏、授权、
快照 lineage、HTTP、Flutter、缓存或导出。

### 如何验证 6AL

没有 PostgreSQL 时，从仓库根目录运行完整 Docker 套件：

```bash
./tool/run_postgres_tests_in_docker.sh
```

脚本会从空库运行 0054 migration、结构与权限 check、synthetic fixture、checksum，并在没有源 cluster
roles 的第二个 PostgreSQL 16 容器恢复后重复 check 和 fixture。看到 0054 的 migration、check、fixture
都通过，且最后出现 `PostgreSQL Docker 测试全部通过。`，才表示数据库合同的本地证据齐全。

如果只检查已经运行的测试库，先确认 Docker Desktop 或 PostgreSQL 测试库已启动，再执行：

```bash
export DATABASE_URL='postgresql://postgres:postgres@127.0.0.1:5432/tongxingzhe_test'
./tool/postgres_migrate.sh
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/checks/verify_management_region_attribution.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/fixtures/0054_management_region_attribution.sql
```

手工检查只使用 synthetic 来源、区域树、坐标和指纹。它应覆盖 original 精确来源、current 坐标唯一／
零命中／同链嵌套／跨链歧义／同深度歧义、region-only 同版本／显式 mapping／缺失 mapping、错误指纹、
草稿或未知树，以及 pending、N/A 和不完整来源的 `not_reportable`。通过只证明当前列出的 SQL shape、
权限和失败关闭条件，不证明真实区域等价、维护者审核、报告截止点选择或 production 区域报告已经完成。

## Slice 6AM 按报告截止点固定区域目标树上下文

6AM 解决一个比区域聚合更早的问题：给定可信的 `data_cutoff_utc`，数据库能否证明当时哪一个已发布
区域树是 current。私有函数
`app_private.resolve_management_report_region_target_context_v1(timestamptz)` 提供只读的
`history-derived cutoff context`，不注册生产报告，也不读取接触
统计。返回值只包含固定 contract、状态、原因、cutoff、`target_tree_version`、
`target_content_fingerprint`、`selection_sequence`、`selection_source`、证据时间和
`tree_published_at_utc`。

### 6AM 如何选择历史上下文

resolver 只读两类事实：0038 的追加式 current selection history 和对应的已发布 release。它不读取 mutable
`is_current`，也不按最新 release、区域名称、父链或几何相似度猜测目标树。

一条 publication selection 只有同时满足以下条件，才能进入结果：

- `selected_at_utc <= data_cutoff_utc`；
- 对应 release 的生命周期是 `published`；
- `published_at_utc <= data_cutoff_utc`；
- selection 保存的内容指纹与 release 的精确指纹一致。

resolver 按选择时间和历史序号取得截止点以前的唯一选择。没有可用选择时，结果不含目标区域 tuple，
并返回稳定的 `selection_history_unavailable`。如果选中的历史指向草稿或缺失 release，或者发布时间、
选择时间或指纹不一致，resolver 以固定 `SQLSTATE 55000` 拒绝解析，不返回上下文。相同 cutoff 的重试
读取同一追加历史，不会因后来切换 current 而改变旧上下文。

### migration baseline 不是历史选择时间

0038 迁移会为迁移时已经是 current 的已发布树写入 `migration_baseline` 选择记录。旧 schema 没有真实的
`selected_at_utc`，所以该字段保持 `NULL`；`recorded_at_utc` 只表示数据库在迁移时观察到这条基线。
`recorded_at_utc` 是可以使用该观察证据的下界，不是树成为 current 的时间。报告 cutoff 早于该时间时，
resolver 必须返回 `selection_history_unavailable`，不能把观察时间回填成选择时间，也不能返回一个猜测的
target tree。

### publication 与 resolver 的共享锁

区域树发布函数和 6AM resolver 共用 `canonical-region-tree-publication:v1` 事务 advisory lock。发布函数在
锁内完成 draft 校验、内容指纹、release 冻结和 selection history 追加。resolver 在同一把锁内读取已提交
历史。resolver 没有写表动作，但仍使用 `VOLATILE SECURITY DEFINER`，因为它必须持有并遵守事务锁，保证
publication-first 与 resolver-first 两种并发顺序都得到可解释的线性化结果。

### 权限与 6AL 的边界

resolver 由无登录、无成员的最小 reader role 拥有，只获得 selection history 和 published release 所需的
`SELECT`。`PUBLIC`、`tongxingzhe_runtime`、区域发布者、mapping writer 和 provenance writer 不能执行
resolver。`PUBLIC`、runtime、mapping writer 和 provenance writer 也不能直接读取 selection history；
区域发布者只保留 0038 发布流程所需的既有 `SELECT`／`INSERT`。它没有 HTTP、Flutter、Drift 或 runtime bridge。

未来固定区域报告先调用 6AM，再把结果中的显式 `target_tree_version + target_content_fingerprint` 传给 6AL 的
`current` resolver。6AL 继续负责地点来源、坐标唯一性和 6AK 显式映射。6AL 不读取 current selection，
也不自行决定 cutoff。`original` 视图合同不变。

6AM 不交付完整区域报告、接触统计资格、区域网格、父子或重叠查询、`k=10`、贡献者保护、互补隐藏、
snapshot lineage、capability、项目目标树配置、任意历史 `as-of`、报告修订／删除、HTTP、Flutter、Drift、
缓存或导出。它只交付后续报告可以安全消费的目标树上下文。

### 如何验证 6AM

没有 PostgreSQL 时，从仓库根目录运行完整 Docker 套件：

```bash
./tool/run_postgres_tests_in_docker.sh
```

脚本会从空库运行 0055 migration、结构与权限 check、synthetic fixture、checksum、并发脚本，并在没有源
cluster roles 的第二个 PostgreSQL 16 容器恢复后重复执行。fixture 覆盖无历史、publication 在 cutoff 前／
等于／之后、两次切换、baseline 观察下界前／等于／之后、草稿、缺失 release、指纹或发布时间不一致、稳定
不可用状态和敏感字段不输出。并发脚本分别让 publication 和 resolver 先取共享锁。

如果只检查已经运行的测试库，先运行 migration，再按以下顺序执行：

```bash
export DATABASE_URL='postgresql://postgres:postgres@127.0.0.1:5432/tongxingzhe_test'
./tool/postgres_migrate.sh
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/checks/verify_management_report_region_target_context.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/fixtures/0055_management_report_region_target_context.sql
./tool/verify_management_report_region_target_context_concurrency.sh
```

手工通过只证明当前 SQL 返回合同、权限、历史边界和并发锁成立。它不证明真实区域对应关系、维护者审核或
生产区域报告已经验收。

## Slice 6AN 如何生成私有 current 城市报告候选

6AN 把 6AM 和 6AL 接到第一份固定区域聚合，但仍停在私有数据库边界。报告定义固定为
`contact_sessions_by_current_city_two_periods@1`：指标是接触场次，视图是 `current`，区域粒度是城市，
时间是项目报告时区下最近两个完整 ISO 周。调用方不能传区域树、城市列表、坐标、polygon 或其他筛选。

executor 先用可信 `data_cutoff_utc` 调用 6AM。只有 6AM 返回 `selected`，它才把明确的目标树版本和内容
指纹传给 6AL。6AL 返回的最小区域沿同一目标树父链归入唯一城市祖先。坐标零命中或歧义、缺失一对一
mapping、pending、`N/A` 和不完整来源不会进入城市格；当前 revision 缺少来源、同一父链出现多个城市或
冻结证据不一致时，整个候选失败关闭。

### 完整网格和互补隐藏

“完整网格”表示输出先枚举目标树中的全部城市，再与 `previous/current` 两个期间做笛卡尔积。即使某城市
没有接触，也会有一个 suppressed cell；不能用省略城市来暗示零或小样本。城市按 `region_id` 的 `C`
排序。该稳定 ID 只用于机器合同，6AN 不返回城市名称、边界或坐标。

每格的真实统计单位是一条合格接触场次。保护函数先检查：

1. 场次数至少为 `10`；
2. 至少有三位不同推广者；
3. 任一推广者的场次数不超过该格一半。

任一条件不满足时，值为 `null`。若一个期间恰好只有一个格因这些条件被隐藏，同时还有可显示格，函数再
按稳定城市顺序隐藏一个格。这样即使另有总量，也不会只剩一个未知数可由相减直接恢复。两格以上首先被
隐藏时不增加互补格。没有随机噪声；这些控制只降低披露风险，不构成形式化不可重识别保证。

候选文档记录 `source_change_sequence`。它说明这次读取观察到的项目 change feed 水位，不表示系统可以按
该水位重放历史。接触修订或作废后，current projection 可以改变以后生成的候选。正式固定与更正版仍需要
后续 snapshot lineage。

### 为什么旧渠道发布链仍拒绝新定义

现有 `canonicalize_management_report_request_v1`、16 格 validator、快照发布、HTTP 和导出只理解
`contact_sessions_by_channel_two_periods@1`。6AN 使用专用 canonicalizer 和 executor。私有注册表出现新的
definition，不表示旧 dispatcher 已支持区域文档。后续接入必须显式选择正确 executor、validator、pair
release 和 lineage；不能把区域 ID 塞进原有 channel cell。

6AN reader role 无登录、无成员，只读取执行所需列并调用 6AM、6AL 和保护函数。`PUBLIC`、runtime、区域
发布者、mapping writer 和 provenance writer 不能执行 executor。本切片没有 runtime bridge、HTTP、Flutter、
缓存、快照、目录或导出。

### 如何验证 6AN

零基础读者仍只需从仓库根目录运行：

```bash
./tool/run_postgres_tests_in_docker.sh
```

脚本会自动发现 0056 migration、结构与权限 check、synthetic fixture 和并发脚本。它还会检查 migration
checksum，并在没有源 cluster roles 的第二个 PostgreSQL 16 容器中先建立最小角色、恢复 dump，再重复
check 和 fixture。成功或失败退出时，脚本都会删除临时容器。

如果已有专用测试库，可以按以下顺序只检查 6AN。不要把命令指向 production：

```bash
export DATABASE_URL='postgresql://postgres:postgres@127.0.0.1:5432/tongxingzhe_test'
./tool/postgres_migrate.sh
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/checks/verify_management_current_city_report.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/fixtures/0056_management_current_city_report.sql
./tool/verify_management_current_city_report_concurrency.sh
```

这组结果证明固定请求、归属组合、完整网格、隐私状态、最小权限和两种 publication 锁顺序。它不证明真实
城市映射正确、外部资料攻击已被排除、生产快照已经发布或用户已在任何平台看到区域报告。

## Slice 6AO 如何固定 current 城市报告快照与发布 lineage

6AO 把 6AN 的私有 current 城市报告候选固定为受保护快照。它复用通用不可变快照存储
`app_private.management_report_snapshots`，但使用独立的区域 release attempt／provenance，不把两个完整期间的
城市网格塞进既有渠道 v2 的 provenance、16 格校验、读取、目录或导出链。

区域 validator／pair comparison 固定 report、metric、dimension、view、granularity、query fingerprint、privacy、
source scope、期间、source watermark、target context 和完整 cells。unavailable、额外字段、错误 identity、错误
target tuple、缺失／重复／乱序网格及期间错误失败关闭；`displayed` 必须达到 6AN 的 `k=10`，`suppressed` 必须
是 JSON `null`。

私有发布只接受 request ID、可信内部用户、项目和固定报告 definition/version。调用方不能提交 JSON、capability、
时区、截止点、城市列表或 target tree tuple。数据库在必要锁后重新验证 `release_management_reports`，派生可信
项目报告时区 revision、`data_cutoff_utc` 和 6AM target context，再调用 6AN executor。成功文档保存固定的 6AN
定义、两个完整期间、完整城市网格、保护状态、目标树 `version + content_fingerprint`、可信时区 revision、数据
截至时间和 source change watermark。

首个成功文档建立唯一 lineage baseline。后续发布只能推进 cutoff，链接前一 snapshot，并保持定义、期间、网格、
target tuple 和可信时区 revision 一致。相同 request 和固定上下文精确幂等，不新增 snapshot 或 attempt。
current-city 与渠道发布不能复用 request UUID；trusted v2 与其内部委托的 v1 记录仍视为同一渠道发布。

same／
earlier cutoff、无共享期间、共享期间的城市值或隐私状态变化，或定义、期间、网格、target tuple、时区 revision
任何漂移，都会返回稳定 blocked reason。blocked attempt 只记录不含 protected document、cells、来源、贡献者、
隐藏前值或 PII 的最小 attempt／provenance 证据，不能借失败记录泄漏结果。snapshot 与 attempt 均追加不可变，
不允许 UPDATE 或 DELETE。区域 provenance 独立于渠道 v2，也不授予读取、目录或导出权。

release writer 之外，runtime、`PUBLIC` 和区域维护身份不能执行发布、读取区域 provenance 或直接写区域 attempt／
snapshot 表。

这仍是 DB-only 合同：没有 HTTP、runtime bridge、Flutter、Drift、缓存、UI、读取、目录、导出、生产调度、能力
授予／撤销、original、历史 `as-of`、更正版、删除、retention 或 warehouse 流程。验证 6AO 时从仓库根目录运行：

```bash
./tool/run_postgres_tests_in_docker.sh
```

Docker runner 会自动发现 0057 migration、check、synthetic fixture 和并发脚本，并在 checksum 和 dump／restore
恢复库重跑。成功证据包括 validator／pair 字段、unavailable／额外字段／错误 identity、完整网格、唯一 baseline、
前一 snapshot 链接、精确幂等、same／earlier cutoff、无共享期间、value-free blocked attempt、不可改删和角色读写
边界。已有专用测试库可以按以下顺序检查；不要把 `DATABASE_URL` 指向 production：

```bash
export DATABASE_URL='postgresql://postgres:postgres@127.0.0.1:5432/tongxingzhe_test'
./tool/postgres_migrate.sh
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/checks/verify_management_current_city_report_snapshot_lineage.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/fixtures/0057_management_current_city_report_snapshot_lineage.sql
./tool/verify_management_current_city_report_snapshot_lineage_concurrency.sh
```

这些检查只证明 synthetic DB-only 快照、授权重检、可信时区、target tuple 漂移失败关闭、独立 lineage、不可改删和
角色读写边界成立；不证明 HTTP、Flutter、UI、读取、目录、导出、retention、warehouse、真实区域证据、生产调度或
外部事实攻击已经验收。

## Slice 6AP 如何授权读取 current 城市报告快照

6AP 为 6AO 的 current 城市受保护快照增加一个私有 PostgreSQL 读取合同。它和 0032 的渠道 v2 读取合同分开，
因为 6AO 使用区域 release attempt／provenance。调用方必须同时给出用户 UUID、项目 UUID 和 snapshot UUID：

```text
app_private.read_authorized_management_current_city_report_snapshot_v1(
  requested_app_user_id,
  requested_project_id,
  requested_snapshot_id
)
```

函数先调用 0030 的授权解析器，重新检查用户、组织成员、项目成员、项目状态和
`view_anonymous_analytics`。授权解析器和撤权事务使用同一 advisory lock。若读取先取得锁，撤权会等待读取事务；若撤权
先取得锁，读取会在锁后重新看到失效 capability。这两个顺序都失败关闭，不用缓存中的旧授权。

读取成功还需要满足以下条件：

- snapshot 属于请求的 project；
- 0057 attempt 有 `current_city_management_report_snapshot_release` family claim，状态是 `approved` 或
  `approved_baseline`；
- `reason_codes` 是空数组；
- attempt 与 snapshot 的报告定义、query fingerprint、release lineage、`reporting_time_zone`、
  `data_cutoff_utc` 和 `previous_snapshot_id` 对齐；
- target tree version 和 content fingerprint 对齐；
- 数据库再次调用 current-city document validator。

成功返回受保护报告，并在同一事务追加一条 value-free、不可变访问事件。审计只保留授权 lineage、project／snapshot
ID、报告定义、截止点、target fingerprint、结果和 reason code，不保存 cells、贡献者、来源、城市名称或 PII。
未知 snapshot 和跨 project 请求返回 `not_found`。存在但未通过上述 provenance 的快照返回
`untrusted_provenance`。两者都不返回报告正文。legacy channel snapshot 也只能得到 `untrusted_provenance`。

runtime、`PUBLIC` 和区域维护身份不能读取审计表、执行读取函数或直接操作区域 attempt／snapshot。6AP 不增加 HTTP、
Flutter、Drift、缓存、目录、导出、区域名称、边界或任意查询。目录和发现流程如果以后需要，必须另建受限合同。

零基础读者可以把 Docker 理解为一次性测试环境。runner 启动隔离的 PostgreSQL 容器，运行 migration、结构 check、
synthetic fixture 和并发脚本，最后删除容器。它不会修改 production 数据库。先启动 Docker Desktop，再从仓库根目录运行：

```bash
./tool/run_postgres_tests_in_docker.sh
```

runner 会自动发现 0058 的 migration、check、fixture 和并发脚本，并在 checksum、dump／restore 和恢复库中重跑它们。
完整套件还会重跑既有授权读取、trusted release、directory 和 export 合同。通过表示合成 PostgreSQL 合同成立，
不表示 HTTP、Flutter、UI、生产区域证据或真实平台验收完成。

如果只调试已经运行的专用测试库，先确认 `DATABASE_URL` 不是 production，再按顺序运行：

```bash
export DATABASE_URL='postgresql://postgres:postgres@127.0.0.1:5432/tongxingzhe_test'
./tool/postgres_migrate.sh
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/checks/verify_authorized_management_current_city_report_snapshot_read.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/fixtures/0058_authorized_management_current_city_report_snapshot_read.sql
./tool/verify_authorized_management_current_city_report_snapshot_read_concurrency.sh
```

check、fixture 和并发脚本不能互相替代。fixture 覆盖 approved claim、空 reason、reporting time zone／cutoff／previous
snapshot 对齐、固定 protected grid、`suppressed = null`、legacy／unknown／cross-project／untrusted 失败关闭、撤权和
不可变审计。并发脚本覆盖 read-first 与 revoke-first 的锁线性化。

## Slice 6AQ 如何把 current 城市读取交给 Backend runtime

6AQ 在 6AP 和 Backend 之间增加一个 PostgreSQL runtime bridge。它接收 external identity 的 exact `issuer + subject`、
project UUID 和 snapshot UUID：

```text
app_data.read_authorized_management_current_city_report_snapshot_v1(
  trusted_issuer,
  trusted_subject,
  requested_project_id,
  requested_snapshot_id
)
```

bridge 只查 exact issuer／subject，并要求 identity 仍绑定 active app user。它不 trim 数据库中保存的 issuer 或 subject，
所以带空格的存储值不会被干净 token 错误命中。它随后只调用 0058 的 current-city private function，并原样返回 6AP
固定合同。completed 报告内的 project 必须匹配请求。它不调用 0032 渠道 read、generic reader、session context、
bootstrap、目录、导出或任意查询。

bridge 是 `SECURITY DEFINER`，固定 `search_path = pg_catalog`。runtime 只有 bridge `EXECUTE`，不能使用 `app_private`，
不能读取关键 private table、`app_users` 或 `external_identities`。bridge owner 与 0058 private function owner 相同，
且 owner 不是 runtime、区域维护或 release writer。adapter 只把 SQLSTATE `42501` 映射为稳定的 `forbidden`，不返回权限
细节、内部用户 ID 或表内容。其他数据库错误仍是内部异常；本 Slice 没有 HTTP／wire 入口，完整错误映射留给后续切片。

Backend adapter 对结果执行固定 allowlist 解析。它核对 root keys、请求 project／snapshot、固定 report／metric／query／
privacy／source、period 和 target context shape、两个期间的 city 配对网格、cell keys 与顺序。cell 只能返回安全整数的
`displayed` 或 `null` 的 `suppressed`。它拒绝 contact、source、contributor、城市名称、坐标、geometry 和其他额外字段。
解析失败关闭，不能把数据库 JSON 当作已验证的 wire response。

### 如何验证 6AQ

第一次使用 Docker 时，先启动 Docker Desktop。Docker 是一次性测试环境：runner 创建隔离的 PostgreSQL 容器，运行测试，
然后删除容器。测试使用 synthetic 数据，不连接 production，也不会修改生产数据库。仓库根目录运行：

```bash
./tool/run_postgres_tests_in_docker.sh
```

完整 runner 会显式运行 0059 migration、结构 check、可回滚 fixture、真实 Node 24 adapter integration、并发检查、migration
checksum 和 dump／restore 恢复库。adapter integration 在自己的 transaction 中建立数据并回滚，因此不会依赖 fixture 的
回滚状态。最终看到 `PostgreSQL Docker 测试全部通过。`，才表示这套本地 DB-only 证据齐全。

没有 Docker 时，可以在专用 PostgreSQL 测试库按顺序运行。先确认 `DATABASE_URL` 不是 production：

```bash
export DATABASE_URL='postgresql://postgres:postgres@127.0.0.1:5432/tongxingzhe_test'
./tool/postgres_migrate.sh
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/checks/verify_runtime_authorized_management_current_city_report_snapshot_read.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/fixtures/0059_runtime_authorized_management_current_city_report_snapshot_read.sql
cd backend/server
npm ci --ignore-scripts
npm run build
DATABASE_URL="$DATABASE_URL" \
CURRENT_CITY_RUNTIME_FIXTURE=../../backend/database/fixtures/0059_runtime_authorized_management_current_city_report_snapshot_read.sql \
node dist/test/management-current-city-report-snapshots.integration.js
```

fixture 证明数据库身份边界、0058 claim、project／snapshot 对齐、value-free audit 和 runtime ACL。adapter integration
证明真实 PostgreSQL 返回值经过 Backend parser 后仍满足固定合同。二者都不证明 HTTP handler、Flutter、目录、导出、
生产 identity provider、六平台 runtime 或真实区域证据已经完成。

## Slice 6AR 如何通过 Backend HTTP 读取 current 城市快照

6AR 在 6AQ adapter 外增加一个固定的只读 HTTP 入口：

```text
GET /v1/projects/:projectId/management-current-city-report-snapshots/:snapshotId
```

请求只带两个 UUID path 参数。它不接受 query、GET body、筛选、报告定义、时区、截止点或 SQL。Backend 先解析并验证
Bearer token，再检查 UUID、query、body 和 store。无 token 或无效 token 时，即使 path、query、body 或 store 不合法，
也先返回 `401`。认证不使用 `SessionContext`，只把 verified issuer、subject、project ID 和 snapshot ID 交给 6AQ
adapter。

成功响应沿用 6AP 的固定 protected report：

```json
{
  "access_event_id": "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
  "snapshot_id": "88888888-8888-4888-8888-888888888888",
  "report": {"...": "6AP protected report"}
}
```

handler 等待 adapter 的 PostgreSQL Promise 完成后才写响应。错误只返回稳定 code。`404` 和 `409` 可以带 value-free
`access_event_id`，不返回报告格、授权关系、external subject、数据库消息、SQL 或栈：

| 情况 | 状态和 code |
| --- | --- |
| token 缺失或无效 | `401 unauthenticated` |
| UUID、query 或 GET body 无效 | `400 invalid_management_current_city_report_snapshot_request` |
| 6AP 重新授权拒绝 | `403 management_current_city_report_snapshot_forbidden` |
| 快照不存在或跨项目 | `404 management_current_city_report_snapshot_not_found` |
| provenance 不可信 | `409 management_current_city_report_snapshot_untrusted` |
| verifier、adapter、数据库或未知 SQLSTATE 异常 | `503 management_current_city_report_snapshot_unavailable` |

server 对该 JSON 路由的成功和错误响应都设置 `Content-Type: application/json; charset=utf-8` 与
`Cache-Control: no-store`。生产 `main.ts` 只注入 `PostgresManagementCurrentCityReportSnapshotStore`，因此 route
不会退回渠道快照 reader、通用 reader、私有表或任意查询。

### 如何验证 6AR

这是 Backend HTTP 合同，不需要真实设备。先在 `backend/server` 安装 Node 依赖并运行静态检查和完整 Backend 测试：

```bash
cd backend/server
npm ci --ignore-scripts
npm run check
npm test
```

测试包含 handler 的认证顺序、UUID／query／body 拒绝、六类状态映射、未知 SQLSTATE 脱敏和 Promise gate；route 测试还会
发送带 `transfer-encoding` 的 GET body，检查固定 path、错误响应和 `no-store`。这些 synthetic HTTP 测试不证明真实身份
提供方、生产 PostgreSQL 权限或六平台运行时能力。

Docker runner 仍用于 0058／0059 的 PostgreSQL 证据，不替代 6AR 的 Node HTTP 测试。第一次使用 Docker 时，启动
Docker Desktop，然后在仓库根目录运行：

```bash
./tool/run_postgres_tests_in_docker.sh
```

runner 会创建隔离的 PostgreSQL 容器，运行 migration、结构 check、fixture、adapter integration、并发检查、checksum 和
dump／restore，再删除容器。它不连接 production，也不会证明 HTTP、Flutter、真实账号或设备验收。若只修改 6AR HTTP，
Backend `check` 与 `test` 是最小验证集；涉及 0058／0059 数据库代码时，再运行完整 Docker 套件。

## Slice 6AS 如何发现 current 城市快照目录

6AS 为 current 城市快照提供一个只返回元数据的目录。它使用 0060 的独立 DB 合同，不调用 0035 渠道目录、6AP 单份
读取、`SessionContext` 或客户端查询。

数据库提供两个固定函数：

```text
app_private.list_authorized_management_current_city_report_snapshots_v1(
  requested_app_user_id,
  requested_project_id
)

app_data.list_authorized_management_current_city_report_snapshots_v1(
  trusted_issuer,
  trusted_subject,
  requested_project_id
)
```

private 函数先在同一事务重新检查 `view_anonymous_analytics`、组织成员、项目成员、项目状态和 capability 有效时间。
它只列出 0057 current-city release family 中 `approved` 或 `approved_baseline` 且 `reason_codes = []` 的快照。attempt
必须和 snapshot 对齐 project、`contact_sessions_by_current_city_two_periods@1`、report version、query fingerprint、
release lineage、报告时区、数据截止、previous snapshot 和 target tree tuple。legacy channel、blocked／unavailable、
跨项目、claim 不匹配或 tuple 漂移的记录会被排除。

目录最多返回 20 项，顺序固定为 `data_cutoff_utc`、`released_at_utc`、`snapshot_id` 降序。每项只包含：

- `snapshot_id`
- `report_id`
- `report_version`
- `reporting_time_zone`
- `data_cutoff_utc`
- `released_at_utc`

根对象还包含 `access_contract_id`、`access_event_id`、`project_id` 和 `snapshots`。空目录仍是成功结果。数据库在同一
事务追加不可变、value-free 的目录访问审计，保存授权 lineage、项目、访问时刻、结果和返回数量，不保存 snapshot ID、
报告 metadata、报告格、来源、贡献者、城市名称、边界、坐标或 PII。目录第一项只是排序结果，不表示当前、最新有效或取代。

runtime bridge 使用 `SECURITY DEFINER` 和 `search_path = pg_catalog`。它只按 exact `issuer + subject` 映射现有 active
identity，再调用 0060 private 函数。runtime 只有 bridge `EXECUTE`，不能使用 `app_private`，不能读取目录／snapshot／
attempt／claim、app user 或 external identity 表，也不能执行 private 函数。区域发布、区域映射、接触来源、区域归属和
current-city release writer 角色同样没有 bridge 或目录审计权限。bridge owner 必须与 private function owner 相同，并且
不能属于这些 runtime 或写入角色。

HTTP 入口是：

```text
GET /v1/projects/:projectId/management-current-city-report-snapshots
```

它只接受显式项目 UUID，不接受 query、GET body、筛选、分页、报告 ID、时区、截止点、capability、内部用户 ID 或 SQL。
Backend 先验证 Bearer token，再检查 UUID、请求形状和 store。无 token 或 token 无效时，即使其他输入有问题，也先返回
`401 unauthenticated`。认证通过后只把 verified issuer、subject 和 project UUID 传给 0060 adapter，不读取
`SessionContext`。adapter 的 PostgreSQL Promise 完成后，handler 才发送响应。

成功响应示例：

```json
{
  "access_event_id": "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
  "project_id": "11111111-1111-4111-8111-111111111111",
  "snapshots": [
    {
      "snapshot_id": "88888888-8888-4888-8888-888888888888",
      "report_id": "contact_sessions_by_current_city_two_periods",
      "report_version": 1,
      "reporting_time_zone": "America/Chicago",
      "data_cutoff_utc": "2026-08-20T06:00:00.000Z",
      "released_at_utc": "2026-08-20T07:00:00.000Z"
    }
  ]
}
```

| 结果 | HTTP 合同 |
| --- | --- |
| token 缺失或验证失败 | `401 unauthenticated` |
| project UUID、query 或 GET body 无效 | `400 invalid_management_current_city_report_snapshot_directory_request` |
| 0060 重新授权拒绝 | `403 management_current_city_report_snapshot_directory_forbidden` |
| verifier、adapter、数据库、返回合同或未知 SQLSTATE 异常 | `503 management_current_city_report_snapshot_directory_unavailable` |

错误只返回稳定 code，不返回数据库消息、SQL、栈、external subject、报告格、城市名称、坐标或 PII。成功和错误响应都
使用 JSON `Content-Type` 与 `Cache-Control: no-store`。不可信 provenance 被过滤，不单独生成逐 snapshot 的 `404` 或
`409`，调用方仍须用 6AR detail route 读取一份显式 snapshot。

### 如何验证 6AS

#### 第一次使用 Docker

Docker 可以理解为一次性测试环境。runner 创建隔离的 PostgreSQL 容器，在其中运行 migration、结构 check、synthetic
fixture、并发脚本、adapter integration、checksum 和 dump／restore。它不连接 production。测试完成后，runner 删除容器。

先启动 Docker Desktop。然后从仓库根目录运行：

```bash
./tool/run_postgres_tests_in_docker.sh
```

看到 `PostgreSQL Docker 测试全部通过。`，表示 synthetic PostgreSQL 合同和恢复检查通过。它不表示真实账号、生产权限、
HTTP、Flutter、真实区域事实或六平台运行时已经验收。Docker 测试不能替代 `backend/server` 的 Node HTTP 测试。

#### 不使用 Docker 的专用测试库

只在专用测试库调试时，先确认 `DATABASE_URL` 不是 production，再从仓库根目录按顺序运行：

```bash
export DATABASE_URL='postgresql://postgres:postgres@127.0.0.1:5432/tongxingzhe_test'
./tool/postgres_migrate.sh
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/checks/verify_authorized_management_current_city_report_snapshot_directory.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/fixtures/0060_authorized_management_current_city_report_snapshot_directory.sql
./tool/verify_authorized_management_current_city_report_snapshot_directory_concurrency.sh
```

fixture、check 和并发脚本不能互相替代。fixture 覆盖 approved／approved_baseline、legacy channel、blocked／unavailable、
current-city claim、tuple 漂移、exact identity、停用／未知身份、跨项目、撤权、空目录、20 项上限、稳定排序、value-free
审计和不可改删。并发脚本覆盖目录读取先取得授权锁，以及撤权先取得授权锁。通过只证明 synthetic DB 合同成立。

#### Backend HTTP 测试

```bash
cd backend/server
npm ci --ignore-scripts
npm run check
npm test
```

HTTP 测试覆盖认证顺序、固定 collection route、query／GET body、401／400／403／503 映射、未知 SQLSTATE 脱敏、单次
bridge query、strict metadata parser、重复或乱序目录、Promise gate、`transfer-encoding` body 和 `no-store`。这些测试
使用 synthetic identity 和 store，不证明真实身份提供方或六平台设备能力。

## Slice 6AT：Flutter 如何通过 typed gateway 选择并读取 current 城市快照

这一节说明 6AT 的 Flutter transport 接缝。它不是给用户看的页面，而是一层把固定 HTTPS JSON 转成不可变 Dart 类型的
typed gateway。可以把 gateway 理解为“门口的翻译员”：它负责带上当前身份、发送固定请求、检查完整响应和分类失败；它不
决定页面布局，也不保存报告。

6AT 把两个已有的 Backend 合同接在一起：6AS 提供 metadata-only 目录，6AR 提供一份显式快照的 protected report。它们
使用独立的 current-city 类型和方法，不复用 legacy channel gateway。目录与 channel 是两个独立来源，目录第一项只是
固定排序中的第一项，不能称为 current、latest、最新有效或取代快照。

### 两个固定请求

```text
GET /v1/projects/:projectId/management-current-city-report-snapshots
GET /v1/projects/:projectId/management-current-city-report-snapshots/:snapshotId
```

请求只放显式 UUID path 参数。不要附加 query、GET body、筛选、分页、报告定义、时区或截止点。目录成功响应的根对象
只有 `access_event_id`、`project_id` 和 `snapshots`；每个目录项只有以下六个字段：

- `snapshot_id`
- `report_id`
- `report_version`
- `reporting_time_zone`
- `data_cutoff_utc`
- `released_at_utc`

目录最多有 20 项，服务端按 `data_cutoff_utc DESC`、`released_at_utc DESC`、`snapshot_id DESC` 排序。空目录仍是成功的
空列表。用户选择一项后，gateway 必须把该项的 `projectId` 和 `snapshotId` 原样传给第二个请求；不能自动选择第一项，
也不能把排序推断成“当前报告”。

详情成功响应只有 `access_event_id`、`snapshot_id` 和 `report`。`report` 是 6AP 的固定 current-city protected report，
其中 periods、target context 和完整 city grid 的字段、类型、顺序以及 `suppressed = null` 都要完整检查。客户端不重算
指标、不把隐藏值当作零、不把城市 ID 转成城市名称，也不接受来源、贡献者、坐标、geometry、contact 或其他 PII。多余、
缺失、类型错误或 project／snapshot 不匹配都应当失败关闭。

### 身份和失败为什么要放在 gateway

gateway 从 `IdentitySession` 取得 Bearer token。调用方不能传 token，页面和 ViewModel 也不能保存 token。一次读取的流程是：

1. gateway 取得当前身份的 token；没有 token 时返回未认证，不发送带有伪造身份的请求；
2. gateway 发送没有 query 和 body 的固定 HTTPS 请求；
3. 如果收到一次 `401`，刷新身份并只重试一次；不能无限刷新，也不能把 token、external subject 或响应正文写入日志；
4. 对第二次 `401`、`400`、`403`、`404`、`409`、`503`、网络失败、非 JSON、错误 `Content-Type`、错误 `no-store`、字段错误或
   严格解析失败，返回稳定的 typed failure，不返回部分目录或报告。

Backend 仍是授权、隐私和 provenance 的边界。Flutter 的 parser 只能证明“收到的 JSON 符合固定合同”，不能把 parser 通过
解释成“用户有权看到所有数据”。成功响应必须有 JSON `Content-Type` 和 `Cache-Control: no-store`；非成功响应按状态码
分类，不解析或显示响应正文。

### 第一次验证 gateway

gateway 的测试使用 synthetic HTTP、fake `IdentitySession` 和内存中的 `MockClient`。这意味着第一次验证不需要真实账号、
真实网络、Docker 或手机；它检查的是请求和响应合同。首次检出仓库或 `pubspec.lock` 改变后，从仓库根目录运行：

```bash
flutter pub get
dart analyze
flutter test --no-pub test/management_reports/
```

已有依赖没有变化时可以跳过 `flutter pub get`。看到测试通过，至少说明当前管理报告 gateway 测试目录中的固定 path、
Bearer 注入、一次 `401` 刷新、目录／详情 strict parser、错误映射、空目录、稳定排序、显式 snapshot 传递、timeout 和 close
通过；它不证明 Backend 数据库权限，也不证明真实 identity provider。

需要验证 PostgreSQL、migration、0060 directory 或 0059 bridge 时，另外按 [本章的 Docker 与 CI 测试说明](09-local-docker-and-ci-testing.md)
运行 `./tool/run_postgres_tests_in_docker.sh`。Docker 测试证明 Backend／数据库合同，不会替代上述 Flutter gateway 测试，
也不证明 UI、Drift、离线、导出、真实平台或真机行为。6AT 本身不交付页面、导航、缓存、同步、下载／导出、分页、搜索或
任何六平台 runtime 证据；完整边界以[产品规格](../PRODUCT_SPEC.md)的 Slice 6AT 合同为准。

## Slice 6AU：为什么 current 城市面板使用管理项目上下文

6AU 把 6AT 的 transport 接到管理报告页面。这里有两种容易混淆的“当前项目”：

- 个人 `TrustedSessionContext` 是本人记录接触、计划和个人分析所用的工作区项目；
- `ManagementAnalysisContext` 是 Backend 重新核对匿名管理分析权限后返回的组织和项目。

current 城市报告属于第二种。面板只能使用既有管理报告浏览器当前选中的 `ManagementAnalysisContext.projectId`，不能从个人
工作区、Widget 输入框、目录第一项或响应正文猜项目。这个限制既防止跨项目混淆，也让 Backend 每次读取时可以继续独立
复核 `view_anonymous_analytics`；页面是否显示入口不是授权证据。

### 用户明确选择报告类型和快照

打开“管理报告”时，原有渠道报告保持默认。用户选择“当前城市”后，Panel 才读取该管理项目的 current-city 目录。目录是
已经排序的元数据列表，不是“最新报告”列表，因此页面不会自动打开第一项，也不会给第一项加 current、latest 或最新有效
标签。用户选择一个 snapshot 后，Panel 把同一个 typed summary 交给 6AT gateway 读取详情。

详情只显示服务端已经保护的字段：报告和指标版本、来源范围、隐私规则、报告时区、数据截止点、两段期间、target context、
城市 ID，以及每期的 `displayed` 或 `suppressed` 状态。`displayed` 显示服务端返回的计数；`suppressed` 只显示“已隐藏”，
不显示 `0`，也不尝试用其他行或期间相减。城市 ID 不是城市名称，Panel 不做名称或 geometry 查询。

### 为什么切换时要丢弃迟到响应

网络请求返回的顺序不一定等于发出的顺序。用户可能在目录仍加载时切换项目、切回渠道报告或退出页面。ViewModel 为每一轮
操作保存 generation；项目、视图、重试或 dispose 改变 generation 后，旧请求即使稍后成功也不能写回页面。切换项目时先
清除旧目录、旧选择和旧报告，避免上一项目内容短暂出现在新项目标题下。

空目录是一次成功读取，不是错误。未配置、未认证、禁止、未找到、不可信、服务不可用、网络和协议失败使用稳定文案；页面
不显示服务器正文。错误区域使用 live region，键盘可以进入详情、返回目录并恢复到原快照。城市网格使用按需构建的纵向
列表，使 320×568 和 200% 字号不需要横向宽表。

### 本机如何验证

6AU 没有修改 PostgreSQL 或 Backend，因此验证 Panel 和状态机不需要先启动 Docker：

```bash
dart analyze
flutter test --no-pub test/features/management_reports/
flutter test --no-pub test/app/
flutter test --no-pub
dart run tool/check_production_boundary.dart
dart run tool/check_markdown_links.dart
```

定向测试检查目录、显式选择、逐阶段重试、迟到响应、项目切换、焦点、语义、小屏和大字号；全量测试检查个人分析和既有渠道
报告没有回归。CI 的 Android、iOS、macOS、Windows、Linux 和 Web build 只证明这些 target 可以编译，不证明真实账号、
真实 identity provider、设备键盘或屏幕阅读器行为。数据库合同需要复核时，仍按
[Docker 与 CI 测试说明](09-local-docker-and-ci-testing.md)运行 PostgreSQL runner；它不能替代 Flutter Widget 测试或真人设备证据。
完整边界以[产品规格](../PRODUCT_SPEC.md)的 Slice 6AU 合同为准。

## Slice 6AV：如何验证管理兴趣五档分布

6AV 是一个只在私有数据库边界验证的管理报告候选。固定报告 ID 是
`contact_sessions_by_interest_level_two_periods@1`，metric identity 是
`interest_distribution@1`。它统计 Backend 已接受的有效接触场次，使用可信的
`app_user_id` 作为贡献者，按项目 IANA 报告时区和可信 `data_cutoff_utc` 取最近两个已经结束的完整 ISO 周。

结果永远是 `previous/current × 0..4` 的十个格。它只返回 count，不返回中位数、比例、百分点差、算术指数或 total cell。
每个期间的每个等级检查 `N >= 10`、至少三位贡献者和 `2 × M <= N`。只要一个等级不安全，该期间五格全部标为
`suppressed`，count 全部是 `null`；另一期间独立判断。这个规则不依赖渠道报告或 current-city 报告是否隐藏同期总数。
因此，读者不能通过另一个报告减去兴趣报告以外的数值来恢复隐藏档位。

### 第一次使用 Docker

Docker 是一个临时测试环境。它不会连接 production，也不会把 synthetic 数据写入真实项目。第一次使用时按以下顺序操作：

1. 安装并打开 Docker Desktop，等待界面显示 Docker Engine 正在运行。
2. 打开 Terminal，进入仓库根目录。已有仓库时可以复制：

   ```bash
   cd "$(git rev-parse --show-toplevel)"
   ```

   如果命令提示当前目录不是 Git 仓库，先用 `cd` 进入你检出的同行者 APP 目录，再运行该命令。
3. 确认 Docker 可以响应：

   ```bash
   docker version
   ```

   输出应同时包含 Client 和 Server。只有 Client 时，Docker Desktop 尚未完成启动。
4. 从仓库根目录运行完整数据库套件：

   ```bash
   ./tool/run_postgres_tests_in_docker.sh
   ```

脚本会创建临时 PostgreSQL 容器，按 migration 顺序运行 0061 的结构检查和 synthetic fixture，并运行仓库已有的 checksum、
dump／restore 及适用的对账检查。成功时可以看到各阶段通过，最后脚本清理临时容器并返回退出码 `0`。输出文字会随 runner
版本变化，不能只看某一行；应确认没有未处理的 `ERROR`，并检查命令最后的退出码。

### 不使用 Docker 的两组本机检查

如果本机已有专用 PostgreSQL 测试库，可以单独运行 0061 的检查。先确认连接地址是本机测试库，不是 production：

```bash
export DATABASE_URL='postgresql://postgres:postgres@127.0.0.1:5432/tongxingzhe_test'
./tool/postgres_migrate.sh
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/checks/verify_management_interest_distribution_report.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/fixtures/0061_management_interest_distribution_report.sql
```

本机没有 `psql` 时不要修改 production 连接来绕过错误，改用上面的 Docker runner。专用测试库中已有旧数据时，优先建立新的
测试库或重新启动一次性容器；不要删除生产数据，也不要把 fixture 当成业务数据导入。

Dart 纯政策合同不依赖 Docker，可以从仓库根目录运行：

```bash
dart analyze
flutter test --no-pub test/features/contact_metrics/management_interest_distribution_policy_test.dart
```

这两组检查互相不能替代。Dart 检查政策输入和输出，PostgreSQL 检查真实 SQL 聚合、权限、migration 和 fixture。两端必须
读取同一组无 PII synthetic 场景，并对账十格的顺序、显示状态和值。

### 预期失败与排查

- `Cannot connect to the Docker daemon`：打开 Docker Desktop，等待 Docker Engine 就绪，再重新运行 `docker version`。
- 只有 Docker Client 输出：桌面程序仍在启动，或 Docker Engine 没有运行。先修复 Docker，再重跑测试。
- `psql: command not found`：本机没有 PostgreSQL 客户端。使用完整 Docker runner，不要把命令改为 production 数据库。
- migration checksum 失败：不要编辑已经执行的 migration。保存输出，检查是否使用了含旧数据的测试库，必要时改用干净测试容器。
- fixture 或结构检查失败：保留首次失败的完整输出。重复运行不能修复合同错误；先确认 migration 顺序、数据库地址和 Docker 日志。
- Flutter 测试失败：先运行 `dart analyze`，再只重跑失败的测试文件。Flutter 测试失败不等同于 PostgreSQL 权限失败。
- Docker 下载超时或磁盘不足：检查网络、Docker Desktop 的磁盘空间和容器状态。不要为了通过检查而删改 fixture 或降低隐私条件。

### 这些检查能证明什么

Dart policy 测试证明固定阈值、`10`／三位／`50%` 边界、期间整体闭包、两期间独立判断和畸形输入的确定性。PostgreSQL
fixture 与 Docker runner 证明 synthetic 数据上的 accepted active contact 过滤、时区／截止点、半开周边界、项目隔离、作废／
尝试／草稿排除、跨报告相减反例、private policy／executor、最小权限、checksum 和 dump／restore。

这些结果不证明 Backend HTTP、runtime bridge、快照、Flutter UI、缓存、离线同步、导出、真实账号、Apple Developer Program、
Android／iOS／macOS／Windows／Linux／Web 的真人运行，或屏幕阅读器行为。自动测试和 Docker 也不构成形式化“不可重识别”保证。
它们只证明当前列出的 synthetic 合同和失败关闭规则。

## Slice 6AW：如何验证管理兴趣报告快照与独立发布 lineage

6AW 把符合 6AV 完整受保护文档合同的管理兴趣文档固定为不可变私有 snapshot。它复用通用 snapshot storage，但使用兴趣专属
release attempt、request claim family 和 provenance；不能使用 channel 的 16 格发布链，也不能使用 current-city 的区域
provenance。兴趣 validator 固定 6AV 的 report、metric、dimension、统计单位、privacy policy、source scope、两个相邻完整
ISO 周和 `previous/current × interest_level 0..4` 十格顺序。每格只有 `displayed` 的安全整数 count 或 `suppressed` 与
JSON `null`，没有中位数、比例、total cell 或其他派生值。

发布只提交 request UUID、可信内部用户、项目和固定 report identity。数据库在锁内重新验证
`release_management_reports`，在同一 release transaction 中派生可信报告时区 revision 和 `data_cutoff_utc`，再执行 6AV
executor；调用方不能提交报告 JSON、时区、截止点、期间、兴趣等级、筛选或 SQL。首个合法文档建立唯一 baseline，后续
发布只能推进 cutoff，保持报告定义、period definition／boundary、十格顺序、query fingerprint、privacy policy、source scope 和时区 revision
一致，并链接前一 snapshot。相同 request 与固定上下文精确幂等，不新增 snapshot 或 attempt。

same／earlier cutoff、没有共享期间、共享期间内的兴趣格值或隐私状态变化，以及定义、期间、网格、query fingerprint、privacy
policy、source scope 或时区 revision 漂移，都会返回稳定 blocked reason。blocked attempt 只保存最小 value-free lineage 和
reason，不保存候选文档、cells、来源、贡献者、隐藏前值或 PII。snapshot、attempt 和 request claim 追加不可变，不允许
UPDATE 或 DELETE；兴趣 request UUID 与 channel、current-city request UUID 互斥，兴趣 provenance 不能冒充其他 family。

release writer 之外，runtime、`PUBLIC`、普通 app role 和区域维护角色不能执行兴趣发布、读取兴趣 provenance 或直接写兴趣
snapshot／attempt 表。虽然两个报告族复用 snapshot storage，report-family RLS 仍把专用 writer 限制在自己的固定 report 和
lineage 内；current-city writer 看不到也不能插入兴趣 snapshot。这个切片只证明 DB-only contract，不增加 authorized read、runtime bridge、HTTP、Flutter、Drift、缓存、
离线、同步、目录、导出、warehouse、retention、报告更正／取代或生产调度。

### 6AW 的验证步骤

第一次使用 Docker 时，安装并打开 Docker Desktop，等待 Docker Engine 就绪。Docker 可以理解为一次性测试环境：它创建
隔离的 PostgreSQL 容器，运行迁移和无 PII synthetic fixture，完成后清理容器，不连接 production。打开 Terminal 后进入仓库
根目录，确认 Docker 同时有 Client 和 Server：

```bash
cd "$(git rev-parse --show-toplevel)"
docker version
./tool/run_postgres_tests_in_docker.sh
```

runner 会发现 0062 migration、结构／权限 check、fixture、并发脚本、checksum 和 dump／restore，并在恢复库重跑。完整证据
应包括合法与拒绝的十格文档、唯一 baseline、精确幂等、稳定 rolling、`previous_snapshot_id`、same／earlier cutoff、无共享
期间、共享期间内格值／隐私变化、固定定义／period definition／boundary／网格／query／privacy／source／时区 revision 漂移、value-free blocked
attempt、独立 claim／provenance、不可改删和最小 ACL。旧 channel、current-city 和 6AV 回归也必须继续通过。

如果本机已有专用测试库，先确认 `DATABASE_URL` 不是 production，再按顺序运行：

```bash
export DATABASE_URL='postgresql://postgres:postgres@127.0.0.1:5432/tongxingzhe_test'
./tool/postgres_migrate.sh
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/checks/verify_management_interest_report_snapshot_lineage.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/fixtures/0062_management_interest_report_snapshot_lineage.sql
./tool/verify_management_interest_report_snapshot_lineage_concurrency.sh
```

check、fixture 和并发脚本不能互相替代。`Cannot connect to the Docker daemon` 时先打开 Docker Desktop；只有 Docker Client 时
等待 Server；没有 `psql` 时使用完整 runner；checksum 失败时不要编辑已执行 migration，改用干净测试容器；fixture 失败时保留
首次输出并检查 migration 顺序、分支和数据库地址。不要为了通过检查而降低隐私条件或把命令指向 production。

这些自动检查只证明当前 PostgreSQL 实现中的 DB-only snapshot、lineage、并发、失败关闭和 ACL。它们不证明 Backend HTTP、
runtime bridge、Flutter UI、Drift、缓存、离线同步、读取、目录、导出、生产发布、真实账号、Apple／Android／iOS／macOS／
Windows／Linux／Web 真人平台运行或真机证据，也不构成形式化不可重识别保证。

## Slice 6AX：如何授权读取单份管理兴趣快照

6AX 只处理 6AW 兴趣 snapshot 的 private DB-only 读取。调用者必须同时提供内部 `app_user_id`、显式 `project_id` 和
`snapshot_id`。数据库重新解析 `view_anonymous_analytics`，再检查 0062 的 interest request claim、approved release attempt、
空 `reason_codes` 以及 attempt 与 snapshot 的 project、report、version、query fingerprint、release lineage、报告时区、数据截止、
`source_change_sequence`（source watermark）、previous pointer 和 released snapshot 对齐。函数返回前再次执行 6AV interest document validator。

读取不接受客户端提交的 capability、授权时间、时区、截止点、期间、兴趣等级、筛选或 JSON。它不重算十格，也不把其他报告的值
拼接进兴趣报告。

### 返回状态

成功结果是 `completed`，并带有原始的 `previous/current × interest_level 0..4` 十格 protected report。`displayed` 仍是安全整数，
`suppressed` 永远是 JSON `null`。

以下结果不带报告正文：

- `not_found`：未知 snapshot 或 snapshot 属于其他 project；
- `untrusted_provenance`：snapshot 属于请求 project，但其来源是 channel、current-city、legacy、blocked、缺失或漂移的
  interest provenance。

这两个状态不用于向调用者确认其他项目是否存在指定 snapshot。错误也不能包含报告格、贡献者、contact、来源、隐藏前值或 PII。

### 授权、撤权和审计

每次已授权尝试都会在同一事务追加一条兴趣专用的不可变、value-free 访问事件。事件保存最小授权 lineage、请求 project／snapshot、
固定报告元数据、结果和 reason code，不复制 `protected_report`、cells 或 `value_count`。未授权、已撤权、过期、只有
`release_management_reports` 或缺少项目成员的调用失败关闭且不写 audit。

读取和撤权使用同一组 transaction lock。读取先取得锁时，撤权等待读取完成；撤权先取得锁时，读取重新看到失效的
`view_anonymous_analytics` 并失败。管理项目选择只能帮助导航，不能代替这次读取的重新授权。

`PUBLIC`、`tongxingzhe_runtime`、普通 app role、interest reader、current-city writer 和区域角色不能执行 private read 函数，
也不能读取 interest audit、attempt 或 provenance。6AX 不增加 runtime bridge、HTTP、目录、Flutter、Drift、缓存、离线、同步、
导出、warehouse、retention、报告更正、生产调度或六平台证据。

### 第一次使用 Docker

没有用过 Docker 的读者可以把它理解成一次性测试环境。它创建隔离的 PostgreSQL 容器，运行 migration 和 synthetic 数据，完成
后删除容器，不连接 production。

1. 打开 Docker Desktop，等待 Docker Engine 完成启动。
2. 打开 Terminal，进入仓库根目录：

   ```bash
   cd "$(git rev-parse --show-toplevel)"
   ```

3. 确认 Docker 同时显示 Client 和 Server：

   ```bash
   docker version
   ```

4. 运行完整套件：

   ```bash
   ./tool/run_postgres_tests_in_docker.sh
   ```

runner 按文件名自动发现 0063 migration、private read check、synthetic fixture 和
`verify_authorized_management_interest_report_snapshot_read_concurrency.sh`。它还运行 checksum、dump／restore，并在没有源
cluster roles 的恢复库重跑 migration、check 和 fixture。恢复库不重跑并发脚本，因为并发脚本会提交 synthetic 行；这样不会把
同一批并发写入重复导入恢复库。

### 专用测试库命令

如果本机已有专用 PostgreSQL 测试库，先确认 `DATABASE_URL` 不是 production。并发脚本会提交固定 `6d*` synthetic 行；每次运行请
使用新建的空测试库，重复运行前先重建该测试库，否则固定主键会按预期冲突。

```bash
export DATABASE_URL='postgresql://postgres:postgres@127.0.0.1:5432/tongxingzhe_test'
./tool/postgres_migrate.sh
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/checks/verify_authorized_management_interest_report_snapshot_read.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/fixtures/0063_authorized_management_interest_report_snapshot_read.sql
./tool/verify_authorized_management_interest_report_snapshot_read_concurrency.sh
```

check、fixture 和并发脚本不能互相替代。fixture 证明合法读取、三类失败状态、授权失效、value-free audit 和不可改删；并发脚本
证明 read-first 与 revoke-first 的锁线性化。完整 Docker 还要证明旧 channel、current-city、6AV 和 6AW 回归、checksum 和恢复库
ACL。通过只证明当前 PostgreSQL 的 DB-only 合同，不证明 runtime、HTTP、Flutter、导出、生产发布、真实账号、六平台运行或形式化
不可重识别保证。

## Slice 6AY：如何通过 Backend runtime 读取兴趣快照

6AY 只把 0063 private read 接到 Backend runtime。它不增加 HTTP route，也不负责 Bearer token 验证。调用方必须先得到 Backend 验证的
external `issuer + subject`，再提供显式 project UUID 和 snapshot UUID。

### bridge 的身份和权限边界

0064 bridge 使用 exact `issuer + subject` 匹配现有且 active 的 identity。它不 trim、bootstrap、创建账号、读取 `SessionContext` 或接受
内部 `app_user_id`、capability、时区、截止点、期间、筛选和 SQL。bridge 只调用：

```text
app_private.read_authorized_management_interest_report_snapshot_v1(
  requested_app_user_id,
  requested_project_id,
  requested_snapshot_id
)
```

bridge 使用 `SECURITY DEFINER` 和固定 `search_path = pg_catalog`。runtime 只有 bridge `EXECUTE`，没有 `app_private` schema usage，不能执行
0063 private function，也不能读取用户、identity、snapshot、provenance 或 audit 表。0063 继续负责 `view_anonymous_analytics`、0062
interest lineage、6AV validator、撤权锁和 value-free audit。bridge 不复制这些检查，也不追加第二条 audit。

### 一次固定 SQL 和 strict parser

Backend adapter 接收 `VerifiedIdentity`，只执行一次参数化查询：

```sql
SELECT app_data.read_authorized_management_interest_report_snapshot_v1(
  $1::text, $2::text, $3::uuid, $4::uuid
) AS access_result
```

adapter 必须严格检查 0063 的 root keys、access contract、请求和解析出的 snapshot、状态和 reason code。`completed` 只接受 6AX 的
`previous/current × interest_level 0..4` 十格、合法 count 和 `suppressed = null`。`not_found` 与 `untrusted_provenance` 不得含
`protected_report`。额外字段、错误 project、错误 snapshot、PII、contact、contributor、来源和隐藏前值都失败关闭。

adapter 只把 SQLSTATE `42501` 映射为 typed `forbidden`。未知 SQLSTATE、数据库消息、SQL、栈和 external subject 不进入 runtime 结果。
HTTP wire mapping 留给后续切片。

### Docker 证据

没有用过 Docker 时，可以把它理解成一次性测试环境。Docker Desktop 提供 Docker Engine。runner 启动隔离的 PostgreSQL 和 Node 容器，使用
synthetic 数据运行测试，最后删除容器。它不连接 production。

```bash
./tool/run_postgres_tests_in_docker.sh
```

runner 自动发现 0064 migration、check 和 fixture，并显式运行第八条 Backend integration。它还运行 0063 read/revoke 并发、checksum 和
dump／restore。恢复库只重跑 migration、check 和 fixture，不重跑会提交 synthetic 行的并发脚本。

若只使用专用测试库，先确认 `DATABASE_URL` 不是 production，再运行：

```bash
export DATABASE_URL='postgresql://postgres:postgres@127.0.0.1:5432/tongxingzhe_test'
./tool/postgres_migrate.sh
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/checks/verify_runtime_authorized_management_interest_report_snapshot_read.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/fixtures/0064_runtime_authorized_management_interest_report_snapshot_read.sql
cd backend/server
npm ci --ignore-scripts
npm run build
DATABASE_URL="$DATABASE_URL" \
INTEREST_RUNTIME_FIXTURE=../../backend/database/fixtures/0064_runtime_authorized_management_interest_report_snapshot_read.sql \
node dist/test/management-interest-report-snapshots.integration.js
```

fixture 证明数据库 identity、project／snapshot、0063 状态和 runtime ACL。integration 证明真实 Node adapter 的一次 bridge 调用和 strict JSON
对账。通过只证明 DB-only bridge 和 parser 合同，不证明 HTTP、Flutter、目录、导出、生产身份提供方、真实账号或六平台运行时。

## Slice 6AZ：如何通过 HTTP 读取管理兴趣快照

6AZ 只把 6AY store 接到一个固定的只读入口：

```text
GET /v1/projects/:projectId/management-interest-report-snapshots/:snapshotId
```

### 认证顺序和 6AY 复用

handler 先解析并验证 Bearer token，再检查 project／snapshot UUID、query、GET body 和 6AY store。无 token 或无效 token 时，其他输入即使无效，
也先返回 `401 unauthenticated`。认证通过后，handler 只把 verified issuer、subject、显式 project UUID 和 snapshot UUID 传给 6AY store。
它不调用 `SessionContext`、通用 reader、current-city reader、private schema，也不接受筛选、报告定义、时区、截止点或 SQL。

6AY 继续负责 `view_anonymous_analytics`、interest provenance、6AV validator、撤权锁和 value-free audit。6AZ 不复制这些逻辑，也不增加第二
条审计或改变 protected report。

### 固定 HTTP 合同

成功响应保留 6AX protected report：

```json
{
  "access_event_id": "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
  "snapshot_id": "88888888-8888-4888-8888-888888888888",
  "report": {}
}
```

错误只返回稳定 code：

| 情况 | 状态和 code |
| --- | --- |
| token 缺失或验证失败 | `401 unauthenticated` |
| UUID、query 或 GET body 无效 | `400 invalid_management_interest_report_snapshot_request` |
| 6AY authorization forbidden | `403 management_interest_report_snapshot_forbidden` |
| 快照不存在或跨项目 | `404 management_interest_report_snapshot_not_found` |
| interest provenance 不可信 | `409 management_interest_report_snapshot_untrusted` |
| verifier、adapter、数据库或未知 SQLSTATE 异常 | `503 management_interest_report_snapshot_unavailable` |

`404` 和 `409` 可以带不含报告值的 `access_event_id`。错误不包含数据库消息、SQL、栈、external subject、授权关系、报告格或 PII。成功和错误
响应都使用 `Content-Type: application/json; charset=utf-8` 与 `Cache-Control: no-store`。handler 等待 adapter Promise 完成后才写响应。

### 为什么没有新的数据库测试

6AZ 没有 PostgreSQL migration、check、fixture 或并发脚本。6AY 已经提供 runtime bridge、ACL、parser、审计、并发、checksum 和 restore 证据。
6AZ 的新增行为是 HTTP handler、route 和 composition，所以 HTTP 测试使用 synthetic identity 与 fake 6AY store。CI 仍运行既有 6AY Docker suite，
保持数据库合同回归。Docker 不替代 HTTP 测试。

没有用过 Docker 时，可以把 runner 理解为一次性测试环境。Docker Desktop 启动隔离的 PostgreSQL 和 Node 容器，使用 synthetic 数据，完成后删除
容器。它不连接 production。只修改 6AZ HTTP 文件时，从 `backend/server` 运行：

```bash
npm ci --ignore-scripts
npm run check
npm test
```

如果同时修改或核对 6AY 数据库合同，再从仓库根目录运行：

```bash
./tool/run_postgres_tests_in_docker.sh
```

这些测试只证明固定 HTTP wire contract 与既有 DB-only 6AY 合同，不证明 Flutter、导出、缓存、离线、生产身份、真实账号或真人平台运行时。

## Slice 6BA：如何发现管理兴趣快照目录

6BA 为 6AW interest snapshot 增加一个独立的 metadata-only directory。它不复用 0035 channel directory 或 0060 current-city directory，
也不替代 6AX 的单份读取授权和审计。

固定入口为：

```text
GET /v1/projects/:projectId/management-interest-report-snapshots
```

调用方必须提供显式 project UUID。handler 先验证 Bearer token，再检查 UUID、query、GET body 和 directory store。认证失败先返回
`401 unauthenticated`。认证通过后，Backend 只调用 interest directory adapter，不调用 `SessionContext`、通用 reader、6AX/6AY 单份读取、
current-city reader、private schema 或客户端查询。

### 目录只列出可信 interest provenance

数据库在同一事务重新检查 `view_anonymous_analytics`、组织成员、项目成员和项目状态。只有以下记录可以进入目录：

- 记录属于请求 project；
- report 固定为 `contact_sessions_by_interest_level_two_periods@1`；
- release lineage、query fingerprint、报告时区、data cutoff、previous snapshot 和 source watermark 与 release attempt 完全一致；
- interest release attempt 为 `approved` 或 `approved_baseline`，且 `reason_codes = []`；
- request claim 属于 interest release family。

channel、current-city、legacy、blocked、跨项目、claim 不匹配或 metadata drift 的记录直接排除。目录不把排除原因转换为逐 snapshot
的 `404` 或 `409`，因此调用方不能通过目录探测其他 report family 的 provenance。

### 固定 metadata 合同

数据库 bridge 返回的根对象只含：

```text
access_contract_id
access_event_id
project_id
snapshots
```

HTTP 成功正文不转发内部 `access_contract_id`，只含 `access_event_id`、`project_id` 和 `snapshots`。

每项只含：

```text
snapshot_id
report_id
report_version
reporting_time_zone
data_cutoff_utc
released_at_utc
```

目录最多返回 20 项，按 `data_cutoff_utc DESC`、`released_at_utc DESC`、`snapshot_id DESC` 排序。第一项只是固定排序中的第一项，不表示
current、latest、最新有效或未被取代。响应不含 protected report、cells、suppressed 前值、来源、贡献者、城市/区域信息或 PII。

目录访问 audit 与 6AX 单份读取 audit 分开保存。它只记录最小授权 lineage、project、访问时间、结果和返回数量，不记录 snapshot ID、metadata、
报告格或 PII。audit 追加且不可变；未认证或未授权请求不产生成功目录 audit。

### Docker 和 Backend 测试

没有使用过 Docker 时，可以把它理解成一次性测试环境。Docker Desktop 启动隔离的 PostgreSQL 和 Node 容器，runner 使用 synthetic 数据运行
测试，完成后删除容器。它不连接 production。

```bash
cd "$(git rev-parse --show-toplevel)"
./tool/run_postgres_tests_in_docker.sh
```

runner 自动发现 0065 migration、directory check 和 fixture，并运行 interest directory integration、独立并发、checksum 和 dump／restore。
恢复库重跑 migration、check 和 fixture，不重跑会提交 synthetic 行的并发脚本。6BA integration 必须读取自己的 interest directory fixture，
不得读取 current-city integration 使用的 `CURRENT_CITY_RUNTIME_FIXTURE`。

如果只修改或调试 Backend HTTP 文件，从 `backend/server` 运行：

```bash
npm ci --ignore-scripts
npm run check
npm test
```

这些 Backend 测试覆盖认证顺序、固定 collection route、query／GET body、稳定错误、strict metadata parser、Promise gate、错误脱敏和
`no-store`。Docker 只证明 PostgreSQL synthetic 合同；Backend 测试只证明 HTTP 和 adapter 合同。两者都不证明 Flutter、导出、缓存、离线、
生产身份、真实账号或六平台真人运行时。

## Slice 6BB：Flutter 如何读取管理兴趣快照目录与详情

6BB 是一层独立的 Flutter typed gateway。它把已经由 6BA／6AZ 保护和授权的 HTTPS JSON 变成不可变 Dart 类型，供后续 consumer
使用；它不是页面、ViewModel、Widget，也不负责选择管理项目、计算指标或保存报告。与 current-city 和 legacy channel 一样，interest
有自己的 gateway 类型，不要把三种 report family 混在一个 parser 或 repository 中。

### 两个固定请求和两个“三字段”边界

目录和详情使用以下固定入口：

```text
GET /v1/projects/:projectId/management-interest-report-snapshots
GET /v1/projects/:projectId/management-interest-report-snapshots/:snapshotId
```

两个请求只把显式 project／snapshot UUID 放在 path 中。不要附加 query、GET body、筛选、分页、报告定义、时区或截止点。

这里有一个容易混淆的 DB／HTTP 边界。6BA 的数据库 bridge 为 DB-only 合同，内部根对象有四个字段：

```text
access_contract_id
access_event_id
project_id
snapshots
```

HTTP 目录会把内部 `access_contract_id` 去掉，只发送三个字段：

```text
access_event_id
project_id
snapshots
```

因此 Flutter directory parser 必须严格要求这三个 HTTP 字段，不能因为数据库函数返回过四个字段就把第四个字段加入 wire 或 Dart
模型。每个目录项只有 `snapshot_id`、`report_id`、`report_version`、`reporting_time_zone`、`data_cutoff_utc` 和
`released_at_utc` 六个字段。目录最多 20 项，顺序由 Backend 固定为 `data_cutoff_utc DESC`、`released_at_utc DESC`、
`snapshot_id DESC`。空目录是成功的空列表；第一项只是排序后的第一项，不是 current、latest、最新有效或未被取代的报告。

详情 HTTP 根对象也只有三个字段：

```text
access_event_id
snapshot_id
report
```

调用方必须把用户明确选择的目录摘要、同一个 `projectId` 和其中的 `snapshotId` 传给详情请求。不能自动取第一项，也不能由目录
顺序猜测 current／latest。详情中的 `report` 是 6AV 的固定十格 count-only interest report：`previous/current × interest_level
0..4` 必须完整且顺序固定，显示格是安全整数，隐藏格的 `value_count` 必须是 JSON `null`。parser 还要核对固定报告／指标
identity、项目绑定、两个期间、IANA 时区和 canonical UTC；额外字段、缺失字段、重复或乱序格、错误 project／snapshot、source、
contributor、contact、location、geometry 和 PII 都必须失败关闭。

### 身份、一次 401 和内存边界

gateway 从 `IdentitySession` 取得 Bearer token。Widget、ViewModel 或方法调用参数不能提供 token。每次请求按以下顺序处理：

1. 取得当前 token；没有 token 就返回未认证，不发送伪造身份的请求；
2. 发送没有 query 和 body 的固定 HTTPS 请求；
3. 如果收到一次 `401`，刷新身份并只重试一次；第二次 `401` 直接失败，不循环刷新；
4. 将 `400`、`403`、`404`、`409`、`503`、网络／timeout、非 JSON、错误 `Content-Type`、错误 `no-store` 或 parser 失败映射为稳定
   typed failure，不返回部分目录或报告。

token、external subject、响应正文和数据库错误不能写入日志。成功响应必须是 JSON 并带 `Cache-Control: no-store`。解析后的对象只
在当前调用期间留在内存；6BB 不写 Drift／SQLite、文件或 secure storage，不做缓存、离线、同步、导出或下载。gateway `close` 后
不能继续发起请求。

### 第一次验证 Flutter gateway

这组测试不需要真实账号、真实网络、Docker 或手机。它使用 synthetic HTTP、fake `IdentitySession` 和内存 `MockClient`，只验证
transport 合同：

```bash
cd "$(git rev-parse --show-toplevel)"
flutter pub get
dart analyze
flutter test --no-pub test/management_reports/
```

测试应覆盖固定 path、无 query／GET body、Bearer 注入、一次 `401` 刷新、三字段目录 parser、三字段详情 parser、六字段摘要、20
项和服务端排序、空目录、首项没有 current／latest 语义、显式 project／snapshot、十格报告、PII／额外字段拒绝、错误映射、
`no-store`、timeout、网络失败和 `close`。测试通过只说明 Dart gateway 能拒绝不符合合同的响应；它不证明数据库授权、Backend
production identity、UI、键盘或屏幕阅读器、Drift、缓存、离线、导出、真实账号或 Android、iOS、macOS、Windows、Linux、Web
运行时。

需要验证 6BA 的 PostgreSQL directory、6AZ 的 Backend HTTP 或其既有 Docker 合同时，另从仓库根目录运行：

```bash
./tool/run_postgres_tests_in_docker.sh
```

Docker runner 继续自动发现并运行既有 6BA migration／check／fixture／并发／integration、6AZ Backend 测试以及 checksum 和
dump／restore；6BB 不新增数据库 migration 或数据库 fixture。恢复库仍只重跑 migration、check 和 fixture，不重跑会提交
synthetic 行的并发脚本。Docker 证据说明 DB／Backend 合同，Flutter 命令说明 Dart transport 合同，二者都不能互相替代，也不能
声称生产身份或六平台真机证据。

6BB 的边界明确不包括 UI、ViewModel、Widget、composition／AppDependencies 接线、管理导航、Drift、缓存、离线、同步、导出／下载、
搜索、分页、报告创建／刷新／更正／删除或真实平台验收。这些工作必须在后续切片中单独定义和验证。

## Slice 6BC：在 Flutter 中选择并阅读管理兴趣报告

6BC 把 6BB gateway 接到用户可见的管理报告浏览器。这一层不改变服务端报告，只负责明确选择、内存状态、
受保护结果显示和可访问交互。

### 先选报告类型，再读目录

管理报告浏览器有三个互斥的 report family：

```text
渠道报告（默认）
当前城市
兴趣报告
```

“互斥”表示同一时刻只有一个视图。不要用多个布尔开关表示这三种状态，否则可能出现同时选中两种报告的无效组合。
打开浏览器时仍显示渠道报告。只有用户明确选择“兴趣报告”后，interest gateway 才读取目录。

请求中的 project ID 只能来自当前 `ManagementAnalysisContext`。这个 context 是服务端重新授权后的管理范围。它不是个人项目菜单中的
`TrustedSessionContext`。没有管理 context 时，界面不发 interest 请求，也不用个人项目作为替代。

### 目录顺序不是“最新”指令

interest 目录最多 20 项，并保留服务端的固定排序。空目录是成功结果。有目录项时，界面不自动打开第一项，也不把第一项称为
current、latest、最新有效或 as-of。用户需要通过点击、Enter、Space 或辅助技术明确选择一个当前目录成员。ViewModel 随后把同一
project 和 summary 交给详情 gateway。

详情显示报告定义、指标、项目、时区、数据截止、期间、来源和隐私元数据，然后显示十格：

```text
previous × interest level 0..4
current  × interest level 0..4
```

`displayed` 格只显示服务端返回的计数。`suppressed` 格显示“已隐藏 / Hidden”，不显示为 `0`。UI 不把十格求和，也不计算比例、
平均等级、中位数或趋势。

### 为什么需要 generation

网络响应可能乱序到达。例如，项目 A 的目录尚未返回时，用户已经切换到项目 B。如果不做隔离，A 的迟到响应可能覆盖 B 的界面。
ViewModel 为每次目录、详情、项目切换、返回目录、重试和 dispose 递增 generation。响应只有在 generation 和项目仍匹配时才能更新状态。

返回目录后，焦点回到刚才选择的快照项。详情载入完成后，焦点进入返回按钮。错误文案使用 live region，但不包含响应正文、SQL、token 或内部用户 ID。

### 从零开始运行 Flutter consumer 测试

在仓库根目录打开终端。第一次运行先下载 Flutter 依赖：

```bash
cd "$(git rev-parse --show-toplevel)"
flutter pub get
```

先运行 6BC 的窄测试，便于快速找到界面或状态机问题：

```bash
flutter test --no-pub test/features/management_reports/interest_report_panel_view_model_test.dart
flutter test --no-pub test/features/management_reports/interest_report_panel_test.dart
flutter test --no-pub test/features/management_reports/management_report_browser_test.dart
flutter test --no-pub test/app/app_dependencies_test.dart
flutter test --no-pub test/app/tongxingzhe_app_test.dart
```

然后运行整个 Flutter 和文档门槛：

```bash
dart format --output=none --set-exit-if-changed lib test
dart analyze
flutter test --no-pub
dart run tool/check_production_boundary.dart
dart run tool/check_markdown_links.dart
git diff --check
```

Widget 测试使用 synthetic gateway，并在 320×568 和 200% 字号下检查溢出。它还要验证 Tab／Shift-Tab、Enter／Space、Escape／返回、焦点恢复、
heading 和 live region。App 测试检查 gateway 的构造、传递、启动失败清理和应用销毁。

6BC 不改变 Backend 或 PostgreSQL，因此不新增 Docker fixture。CI 仍会运行既有数据库套件和六平台 build smoke，但本地 Flutter 测试只证明 consumer、
composition、状态隔离和可访问性模拟路径。它不证明生产身份、真实账号、Drift、缓存、离线、导出或 Android、iOS、macOS、Windows、Linux、Web 真机运行时。

6BC 的非范围还包括共享 report-family DTO／泛型 panel 重构、报告创建／刷新／更正／删除、retention、warehouse、分页、搜索、筛选、as-of／latest 查询、下载和分享。

## Slice 6BD：验证原始区域城市固定报告

6BD 是 6AN current 城市报告的另一份数据库合同。它回答的是“按接触保存的原始区域解析结果，两个完整期间的有效接触场次如何分布到原始来源树中的城市”，
而不是“按现在选中的区域树重新归类”。它固定报告 `contact_sessions_by_original_region_two_periods@1`、
`metric=contact_sessions@1`、`view_mode=original`、`dimension=original_region` 和城市粒度。

### 单一来源树和原始城市

一份报告只能绑定一个精确的：

```text
source_tree_version + source_content_fingerprint
```

每条可报告接触都必须使用保存的 original release、指纹和区域节点，并沿同一来源树找到唯一城市父级。6BD 不读取 6AM current target context，
不使用 current selection，不做跨版本 mapping，不重新解析坐标，也不按名称或父链猜测。缺失 release、错误指纹、找不到节点、没有唯一城市父级、
`pending_resolution`、`not_applicable` 或其他不完整来源会由 original attribution 标记为 `not_reportable`；6BD executor 随即以 `55000` 失败关闭，
不会把该记录补成另一个城市，也不会返回部分报告。

如果候选数据混有多个来源树 tuple，或没有可用的单一来源树，报告返回稳定 unavailable／失败关闭。系统不能挑选最新树、丢掉冲突项后继续跨树相加，
也不能用不同来源树的城市格做相减。报告网格包含选定来源树的全部城市，使用稳定的城市区域 ID；不返回城市名称、边界、坐标或来源明细。

### 期间、截止点和隐私

报告使用项目报告 IANA 时区和两个相邻完整 ISO 周。`data_cutoff_utc` 只限定本次纳入的已接受事实，是报告的证据边界，不是任意历史 `as-of` 查询，
不重建截止时刻的区域树，也不自动选择 current 或 latest release。每个期间和城市格独立执行：至少 10 个有效接触、至少 3 位可信贡献者、任一贡献者不超过该格的一半。
通过后再按稳定城市顺序执行互补隐藏。`displayed` 只显示安全整数；`suppressed` 永远显示为隐藏状态，底层值为 JSON `null`。

响应只携带固定报告 identity、项目、时区、两个期间、cutoff、单一来源树 tuple 和已保护的完整城市网格。它不得包含接触、revision、贡献者、来源、
坐标、边界、城市名称或其他 PII。6BD 只提供 private PostgreSQL 合同，不包含 snapshot、release lineage、authorized read、审计、runtime、HTTP、
Flutter、Drift、缓存、离线、同步、导出、parent／overlap、retention、warehouse、自动调度或六平台真机验收。

### 从零开始运行 Docker 数据库测试

没有用过 Docker 时，可以按下面步骤操作：

1. 安装并启动 Docker Desktop。看到 Docker Desktop 正常运行后，再打开终端。
2. 在仓库根目录执行命令。runner 会创建临时 PostgreSQL 和 Node 容器，使用 synthetic 测试数据，完成后清理容器；它不会连接 production。
3. 运行完整套件：

```bash
cd "$(git rev-parse --show-toplevel)"
./tool/run_postgres_tests_in_docker.sh
```

runner 会自动发现 0066 migration、结构／权限 check、fixture 和独立并发检查，并运行 migration checksum 与 dump／restore。恢复库会再次运行 migration、
check 和 fixture，但不会重跑会提交 synthetic 行的并发脚本。成功时应看到仓库约定的 `PostgreSQL Docker 测试全部通过。`。

Docker 通过只证明 synthetic PostgreSQL 合同成立。它不证明真实区域树内容、生产数据、任意历史 `as-of`、Backend runtime、HTTP、Flutter、导出或六平台真人运行时。

### 只调试专用测试库

只有在 Docker runner 已能工作或需要定位单项 SQL 失败时，才使用专用测试库。先确认 `DATABASE_URL` 指向空的本机测试库，不要指向 production；
并发脚本会提交 synthetic 行，所以重复运行前应重建测试库或使用新的空库：

```bash
export DATABASE_URL='postgresql://postgres:postgres@127.0.0.1:5432/tongxingzhe_test'
./tool/postgres_migrate.sh
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/checks/verify_management_original_region_report.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/fixtures/0066_management_original_region_report.sql
./tool/verify_management_original_region_report_concurrency.sh
```

check、fixture 和并发脚本不能互相替代。它们应覆盖原始 release／指纹／节点／唯一城市父链、`not_reportable`、混合来源树失败关闭、current／mapping／
名称猜测排除、完整城市网格、`k=10`／三位／半数边界、期间独立判断、互补隐藏、无敏感输出和最小 private ACL。dump／restore 后的通过只说明
迁移和固定检查可重复，不增加 runtime、HTTP、Flutter、导出、生产身份、任意 `as-of` 或真人平台证据。

## Slice 6BH：只读取可信的原始区域快照

6BH 不创建报告，也不决定哪份快照是最新。调用方必须给出内部用户、项目和 snapshot UUID。数据库先重新检查
`view_anonymous_analytics`，然后把快照与 6BG 保存的 original-region request claim 和 approved attempt 对账。项目、报告 identity、lineage、
报告时区 revision、cutoff、previous pointer、source watermark 或 `source_tree_version + source_content_fingerprint` 任一不一致，都不能返回报告正文。
通过这些检查后，数据库还会再次运行 6BD document validator。

读取结果只有三种：

- `completed` 表示授权和 provenance 都可信，返回已经保护的报告；
- `not_found` 表示该 ID 未知或属于其他项目，不泄露跨项目存在性；
- `untrusted_provenance` 表示同项目快照存在，但它属于其他报告族、legacy、blocked，或证据缺失／漂移。

每次已经通过授权门槛的尝试都会追加一条 original-region 专用 audit。它只保存访问合同、项目、snapshot、release request、固定报告元数据、
时区、cutoff、source tree tuple、watermark、状态和 reason，不保存报告正文、cells、隐藏前值、来源记录、contact、contributor、区域名称、坐标或 PII。
只有 `completed` audit 可以保存已经验证的 source tree tuple 和 watermark；`untrusted_provenance` 会把它们固定为 `NULL`。audit 不能更新或删除。
撤权和读取使用同一授权锁，因此读取先提交可以完成，撤权先提交后读取必须失败关闭。

### 从零开始验证 6BH 数据库合同

先安装并启动 Docker Desktop。你不需要单独安装 PostgreSQL，也不需要真实账号。打开终端，进入仓库根目录并运行：

```bash
cd "$(git rev-parse --show-toplevel)"
./tool/run_postgres_tests_in_docker.sh
```

runner 会建立临时容器和 synthetic 数据，自动发现 0069 migration、结构 check、rollback fixture 和并发脚本，随后验证历史 migration checksum，
再把源库 dump 恢复到独立 PostgreSQL。恢复库会重跑 migration、check 和 fixture，但不会重跑会提交 synthetic 行的并发脚本。测试结束后容器自动清理，
不会连接 production。成功只证明 private PostgreSQL 合同、权限、撤权顺序和恢复路径成立；它不证明 runtime bridge、HTTP、Flutter、目录、导出、
production identity 或真人平台运行时。

需要定位单项失败时，先准备新的本机测试库，并确认 `DATABASE_URL` 绝不指向 production：

```bash
export DATABASE_URL='postgresql://postgres:postgres@127.0.0.1:5432/tongxingzhe_test'
./tool/postgres_migrate.sh
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/checks/verify_authorized_management_original_region_report_snapshot_read.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/fixtures/0069_authorized_management_original_region_report_snapshot_read.sql
./tool/verify_authorized_management_original_region_report_snapshot_read_concurrency.sh
```

check 检查对象形状、owner、`SECURITY DEFINER`、固定 search path 和最小 ACL；fixture 检查正常、未知、不可信、再次验证、audit 和不可变性；
并发脚本使用两个连接检查 read-first 和 revoke-first。并发脚本会提交 synthetic 行，重复运行前应重建空库。这三层证据不能互相替代。

## Slice 6BI：通过 Backend runtime 读取原始区域快照

6BI 把 6BH 的 0069 private read 接到 Backend runtime。Backend 先验证 external `issuer + subject`，再把 verified identity、显式 project UUID 和
snapshot UUID 交给 0070 bridge。bridge 只映射现有且 active 的 identity，不 trim、bootstrap、读取 `SessionContext`，也不接受内部用户 ID、capability、
时区、截止点、source tree tuple、筛选或 SQL。runtime 只有 bridge `EXECUTE`，不能使用 `app_private` schema。

### bridge 的一次固定调用

Backend adapter 只执行一次固定参数化 SQL：

```sql
SELECT app_data.read_authorized_management_original_region_report_snapshot_v1(
  $1::text, $2::text, $3::uuid, $4::uuid
) AS access_result
```

0070 bridge 使用 `SECURITY DEFINER` 和固定 `search_path = pg_catalog`，只调用
`app_private.read_authorized_management_original_region_report_snapshot_v1(uuid, uuid, uuid)`。它不复制 0069 的授权、0068 provenance、6BD
validator、撤权锁或 audit。`PUBLIC`、普通 app role、0066 reader、0068 writer 和其他 report-family 角色不能执行 bridge 或 private reader。

### strict parser 保护什么

parser 只接受 0069 的固定 envelope。`completed` 必须包含 original-region report 的 17 个固定 keys：报告 identity、metric、维度、视图、粒度、
query fingerprint、privacy policy、source scope、project、periods、data cutoff、source change sequence、source tree context、状态和 cells。
它还必须确认请求与返回的 project／snapshot 绑定，selected source tree tuple 与报告一致，两个期间完整，cells 的 `cell_order` 连续，显示值是安全整数，
隐藏格的 `value_count` 是 `null`。parser 拒绝额外字段、其他 report family、城市名称、坐标、来源记录、贡献者、contact 和 PII。

`not_found` 和 `untrusted_provenance` 没有 `protected_report`。adapter 只把 SQLSTATE `42501` 映射为 typed `forbidden`，未知 SQLSTATE 仍按内部错误处理。
bridge 和 adapter 不追加第二条 audit，也不把报告值写入日志。

### 第一次验证 6BI

没有用过 Docker 时，可以把它看成一次性测试环境。Docker Desktop 启动隔离的 PostgreSQL 和 Node 容器，runner 使用 synthetic 数据运行测试，结束后删除容器。
它不连接 production，也不会修改真实项目。

1. 打开 Docker Desktop，等待 Docker Engine 显示已运行。
2. 打开终端，进入仓库根目录。
3. 运行完整测试：

   ```bash
   cd "$(git rev-parse --show-toplevel)"
   ./tool/run_postgres_tests_in_docker.sh
   ```

runner 自动发现 0070 migration、structural check 和 rollback fixture，并运行原始区域 runtime integration。它还运行 0069 read／revoke 并发、checksum 和
dump／restore。恢复库先准备 cluster roles，再重跑 migration、check 和 fixture，不重跑会提交 synthetic 行的并发脚本。

完整通过只证明 synthetic PostgreSQL 的 0070 bridge、Backend adapter、strict parser 和最小 ACL。它不证明 HTTP、Flutter、目录、导出、生产 identity provider、
真实账号或六平台真人运行时。

### 只调试专用测试库

只有需要定位单项 SQL 失败时，才使用专用测试库。先确认 `DATABASE_URL` 指向新的空库，绝不能指向 production。以下命令会写入 synthetic 数据：

```bash
export DATABASE_URL='postgresql://postgres:postgres@127.0.0.1:5432/tongxingzhe_test'
./tool/postgres_migrate.sh
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/checks/verify_runtime_authorized_management_original_region_report_snapshot_read.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/fixtures/0070_runtime_authorized_management_original_region_report_snapshot_read.sql
```

然后运行 Backend 检查和测试：

```bash
cd backend/server
npm ci --ignore-scripts
npm run check
npm test
```

重复运行前重建空测试库，因为 fixture 会使用固定 synthetic identity 和 snapshot。0070 不新增提交型并发脚本，0069 已覆盖 private read 与撤权的锁顺序。
check、fixture、Backend test 和 Docker suite 不能互相替代。通过只证明 DB-only bridge、adapter parser 和 ACL。

## Slice 6BJ：通过 HTTP 读取原始区域快照

6BJ 把 6BI 的 `ManagementOriginalRegionReportSnapshotStore` 接到固定的 HTTP 详情路径：

```text
GET /v1/projects/:projectId/management-original-region-report-snapshots/:snapshotId
```

### 请求顺序

handler 必须先处理 Bearer identity。它先解析 token，再验证 external `issuer + subject`；只有这一步成功后，才验证 `projectId` 和 `snapshotId` 的 UUID、query、GET body 的 `Content-Length`／`Transfer-Encoding` 声明以及专用 store。没有 token 或 token 无效时，即使 path、query、body 或 store 有问题，也先返回 `401 unauthenticated`。这能避免攻击者用 malformed 请求探测资源或后端组合状态。

认证通过后，handler 只向 6BI 的专用 store 传递 verified identity、显式 project UUID 和 snapshot UUID。它不从 `SessionContext`、客户端参数或其他 report family 推断项目，也不调用 generic、current-city 或 interest store。store Promise 完成前不能写 HTTP 响应；这就是 Promise gate。

### 固定响应

`completed` 的 JSON 根对象只有三个字段：

```json
{
  "access_event_id": "…",
  "snapshot_id": "…",
  "report": {}
}
```

固定状态如下：

| HTTP 状态 | code |
| --- | --- |
| `401` | `unauthenticated` |
| `400` | `invalid_management_original_region_report_snapshot_request` |
| `403` | `management_original_region_report_snapshot_forbidden` |
| `404` | `management_original_region_report_snapshot_not_found` |
| `409` | `management_original_region_report_snapshot_untrusted` |
| `503` | `management_original_region_report_snapshot_unavailable` |

`404` 和 `409` 可以带 value-free `access_event_id`，但不能带报告正文或内部字段。成功和错误响应都使用 JSON 与 `Cache-Control: no-store`。响应不能包含数据库消息、SQL、栈、external subject、授权关系、报告格、来源、贡献者、区域名称、坐标或 PII。production composition 只注入 `PostgresManagementOriginalRegionReportSnapshotStore`；HTTP 层不访问 `app_private`，不复制 6BH／6BI 的授权、provenance、validator、撤权锁或 audit。

### 如何测试以及测试证明什么

6BJ 不增加 migration、database check、fixture、PostgreSQL integration 或并发脚本。先从仓库根目录运行 Backend 的 synthetic HTTP 测试：

```bash
cd backend/server
npm ci --ignore-scripts
npm run check
npm test
```

这些测试覆盖固定 GET path、wrong method、两种 GET body 声明、认证先于请求验证、所有状态映射、错误脱敏、三字段成功 wire、JSON、`no-store`、Promise gate 和 production wiring。它们使用 fake store 与 synthetic identity，不需要真实账号或生产 JWT provider。

需要检查既有 0069／0070 数据库合同时，再回到仓库根目录运行：

```bash
cd ../..
./tool/run_postgres_tests_in_docker.sh
```

Docker runner 的结果只证明 synthetic PostgreSQL 的 private read、runtime bridge、strict parser、授权和 ACL。它不证明 6BJ HTTP 已在 production 身份提供方、Flutter、目录、导出、缓存、离线或六个平台真人环境中运行。HTTP 自动测试与 Docker 数据库测试是两层证据，不能互相替代。

## Slice 6BK：发现原始区域快照目录

6BJ 详情路径需要一个明确的 snapshot ID。6BK 提供取得这个 ID 的专用 collection route：

```text
GET /v1/projects/:projectId/management-original-region-report-snapshots
```

这不是 latest API。目录最多返回 20 项，固定按 `data_cutoff_utc`、`released_at_utc` 和 `snapshot_id` 降序。第一项只是在这次排序中靠前，调用方不能把它标成
current、latest、最新有效或未被取代。用户应明确选择一个目录项，再把该 project 和 snapshot ID 交给 6BJ。

数据库每次调用重新确认 active identity、组织／项目成员、项目状态和 `view_anonymous_analytics`。它只接受 6BG original-region release family 中
provenance 完整的 approved snapshot，并复核 report identity、query、lineage、报告时区 revision、cutoff、previous pointer、source watermark 和
source tree tuple。generic、channel、current-city、interest、legacy、blocked、跨项目或漂移快照不进入目录。

### 返回内容与隐私边界

成功 HTTP 根对象只有三个字段：

```json
{
  "access_event_id": "…",
  "project_id": "…",
  "snapshots": []
}
```

每项只有 snapshot ID、固定 report ID／version、报告时区、cutoff 和 release time。目录不返回 protected report、cells、隐藏前值、source tuple、来源、
贡献者、contact、区域名称、坐标或 PII。数据库内部 envelope 另有 `access_contract_id`；该内部字段不能进入 HTTP 或未来客户端类型。

空目录返回 `200` 和空数组，并追加一条返回数量为 0 的成功 audit。audit 只保存授权 lineage、project、访问时间、完成状态和返回数量。它不保存 snapshot ID、
报告 metadata、source tuple 或报告内容。未认证或未授权请求不伪造成功 audit。

### 请求顺序与失败

handler 先验证 Bearer identity，再检查 project UUID、query、GET body 的 `Content-Length`／`Transfer-Encoding` 声明和专用 store。缺少或无效 token 时，
即使请求形状或 store 有问题，也先返回 `401 unauthenticated`。认证通过后只调用 original-region directory store，并等待 Promise 完成后写响应。

输入无效返回 `400 invalid_management_original_region_report_snapshot_directory_request`；授权失败返回
`403 management_original_region_report_snapshot_directory_forbidden`；数据库、parser 或未知错误返回
`503 management_original_region_report_snapshot_directory_unavailable`。所有结果使用 JSON 与 `Cache-Control: no-store`。

### 如何验证

只检查 Backend 时，从仓库根目录运行：

```bash
cd backend/server
npm ci --ignore-scripts
npm run check
npm test
```

检查数据库、并发和恢复时，回到仓库根目录运行：

```bash
cd ../..
./tool/run_postgres_tests_in_docker.sh
```

Docker runner 自动发现 0071 migration、check、fixture 和 concurrency，并显式运行专用 PostgreSQL integration。恢复库重跑 migration、check 和 rollback
fixture，不重跑会提交 synthetic 行的并发脚本。完整通过只证明 synthetic provenance、授权撤回、20 项排序、value-free audit、runtime ACL、strict parser 和
HTTP 合同。它不证明 Flutter、导出、缓存、离线、production identity 或六平台真人运行时。

## Slice 6BL：在 Flutter 中严格读取原始区域目录与详情

6BL 增加独立的 `OriginalRegionReportGateway`。它只消费 6BK collection route 和 6BJ detail route：

```text
GET /v1/projects/:projectId/management-original-region-report-snapshots
GET /v1/projects/:projectId/management-original-region-report-snapshots/:snapshotId
```

调用方先读取目录，再明确选择同一目录中的 summary，最后用相同 project 和 snapshot 读取详情。gateway 不自动读取第一项，也不把第一项解释为 current、latest、
最新有效或未被取代。

### 三层合同不能混用

数据库目录 envelope 有 `access_contract_id`、`access_event_id`、`project_id` 和 `snapshots` 四项。HTTP 和 Dart 目录只有后三项。内部
`access_contract_id` 若出现在客户端响应中，strict parser 会拒绝。每个目录 summary 只有 snapshot ID、report ID／version、报告时区、cutoff 和 release time。

详情根对象只有 `access_event_id`、`snapshot_id` 和 `report`。report 固定 17 个 keys，包括 original view、city granularity、项目、两个期间、cutoff、
source watermark、selected source tree context、完成状态和 cells。previous／current 必须拥有相同、稳定排序的城市集合，`cell_order` 从 0 连续递增。
`displayed` 只能保存不小于 10 的安全整数；`suppressed` 的值只能是 `null`，不能解释为零。

### 身份、失败和内存边界

token 只来自 `IdentitySession`。每次请求先取得 token；第一次 `401` 只刷新并重试一次，第二次 `401` 停止。成功响应必须是 JSON 并带
`Cache-Control: no-store`。请求、身份、授权、not-found、untrusted、服务不可用、网络、timeout 和响应合同错误使用稳定 typed failure，不返回部分结果。

parser 会递归拒绝来源记录、贡献者、contact、location、geometry、区域名称、坐标、PII 和额外字段。解析结果只保存在内存，不写 Drift、缓存、离线存储、
同步队列或导出。6BL 不包含 Widget、ViewModel、管理上下文接线或六平台真人验收。

### 如何验证

从仓库根目录运行：

```bash
flutter pub get
dart analyze
flutter test --no-pub test/management_reports/http_original_region_report_gateway_test.dart
flutter test --no-pub
```

这些测试使用 fake identity 和 synthetic HTTP，只证明 Dart transport、strict parser、typed failure 和内存边界。6BJ／6BK 的 Backend、数据库授权、
provenance、audit、ACL 和 restore 仍由各自自动测试证明。Dart 测试不证明 UI、缓存、离线、导出、production identity 或真人平台运行时。

## Slice 6BM：在 Flutter 中查看原始区域报告

6BM 把 6BL 的 typed gateway 接入管理报告浏览器。进入页面时仍先显示渠道报告。只有使用者明确选择“原始区域”，应用才读取当前管理项目的目录。
项目来自已经重新授权的 `ManagementAnalysisContext`，不是个人项目，也不是 Widget 自由输入。

页面有六种主要状态：未启用、目录加载、目录、详情加载、详情和失败。空目录属于成功状态。目录保留服务端顺序，但不会自动打开第一项，也不会把第一项称为
current、latest 或未被取代。使用者必须明确选择一个 summary，应用才读取该快照详情。

详情显示报告定义、时区、截止时间、发布时间、两个完整期间和 source-tree context。城市行只显示稳定 city ID。它不显示城市名称、边界或坐标。
`displayed` 格显示服务端给出的安全整数；`suppressed` 格只显示“已隐藏 / Hidden”，不显示零。Flutter 不重新排序、聚合、归类或计算总计、比例、差值和趋势。

项目、报告类型或目录状态改变时，ViewModel 会递增 generation。旧请求随后完成也不能恢复旧项目或旧快照。返回目录后，键盘焦点回到刚才选择的 summary；
详情和错误状态分别把焦点放到返回与重试控件。标题使用 heading 语义，状态区域使用 live region。

### 不使用 Docker 的 focused 验证

第一次运行 Flutter 测试时，先在仓库根目录下载依赖：

```bash
flutter pub get
```

然后运行 6BM 的三个直接测试入口：

```bash
flutter test --no-pub test/features/management_reports/original_region_report_panel_view_model_test.dart
flutter test --no-pub test/features/management_reports/original_region_report_panel_test.dart
flutter test --no-pub test/features/management_reports/management_report_browser_test.dart
flutter test --no-pub test/app/app_dependencies_test.dart test/app/tongxingzhe_app_test.dart
```

第一条检查目录、详情、重试和迟到响应状态。第二条检查双语文案、保护后城市格、320×568、200% 字号、键盘焦点和语义树。第三条检查四个互斥报告类型、
渠道默认值和管理项目来源。最后一条检查 gateway 的构造、传递和关闭。

6BM 没有 migration、数据库函数或 Backend route，因此 focused UI 验证不需要 Docker、Android Studio、模拟器或手机。完整回归仍运行：

```bash
dart analyze
flutter test --no-pub
```

CI 还会运行既有 Backend、PostgreSQL 和六平台构建。它们可以发现集成回归，但不会把 Flutter 模拟测试变成生产授权或真人平台证据。6BM 不证明真实账号、
Backend／数据库授权、真实屏幕阅读器、缓存、离线、导出或文件保存。

## Slice 6BN：登记原始区域快照更正版取代

6BN 只登记两份已经通过 6BG 的 original-region approved snapshot 之间的直接 replacement。它不生成 snapshot，也不把 6BE 的渠道 replacement
ledger 复用到 original-region。两份快照必须属于同一 project、report／version、query fingerprint、privacy、source scope、报告时区 revision、期间、
release lineage 和精确的 `source_tree_version + source_content_fingerprint`。新快照的 `data_cutoff_utc` 和发布时间都必须晚于旧快照。

数据库在管理报告共享的 value-free request UUID ledger 中使用独立 replacement family claim，并使用 original-region 专用 provenance 和最小 ACL。release
与 replacement 使用同一个 request lock；同一 UUID 无论先由哪一个合同占用，另一个合同都会失败关闭。登记原因只允许 `late_accepted_data`、`contact_revision` 和 `contact_void`。
关系和最小 audit 追加且不可变；每份旧快照最多一个直接 replacement，每份新快照最多一个 predecessor。自链接、循环、分叉、stale head、跨项目、
跨 report family、source-tree 漂移和时间倒序都失败关闭。请求与 lineage 锁取得后，数据库会再次确认发布记录和批准 provenance；相同 request UUID 与
canonical payload 精确幂等，载荷漂移失败关闭。

replacement 生命周期查询是 value-free 的，只返回 snapshot ID、`active`／`superseded` 和直接 replacement ID。它不返回报告格、来源、贡献者、地点、
隐藏前值或 PII。该关系不改变旧快照和新快照，不改变目录排序，也不能用于推断 current 或 latest。

### 6BN 的范围

这是 DB-only 合同。它不处理 channel、current-city、interest 或其他 report family，不做分析定义／跨版本更正，不生成 snapshot，也不增加 runtime、
HTTP、Flutter、目录、导出、缓存、离线、分享、删除、tombstone、retention、备份清除、parent／overlap、warehouse 或真人平台验收。Docker synthetic
通过只能证明 PostgreSQL 中的 replacement relation、授权锁、不可变性、value-free 结果和 ACL。

### 6BN 的验证命令

从仓库根目录运行完整 PostgreSQL 合同：

```bash
./tool/run_postgres_tests_in_docker.sh
```

runner 会发现 0072 migration、structural check、rollback fixture 和 replacement concurrency script，并在 checksum、dump／restore 后重跑 migration、check
和 fixture。恢复库不重跑会提交 synthetic 行的并发脚本。若只调试 6BN，先确认 `DATABASE_URL` 是专用测试库，再运行：

```bash
./tool/postgres_migrate.sh
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/checks/verify_management_original_region_report_snapshot_replacements.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/fixtures/0072_management_original_region_report_snapshot_replacements.sql
./tool/verify_management_original_region_report_snapshot_replacements_concurrency.sh
```

这些命令覆盖 synthetic DB-only 证据，不证明 snapshot 生成、其他 report family、分析定义／跨版本更正、runtime、HTTP、Flutter、目录、导出、删除、
retention、生产身份或 Android、iOS、macOS、Windows、Linux、Web 真人平台运行时。

## Slice 6CB：登记 current-city 快照更正版取代

6CB 只登记两份已经通过 0057 的 current-city approved snapshot 之间的直接 replacement。它不生成 snapshot，也不修改旧、新 snapshot。两份快照必须同 project、report／version、query fingerprint、privacy policy、source scope、报告时区 revision、期间、release lineage 和完整 target context；新快照的 cutoff 与发布时间必须更晚，source watermark 不得回退。

数据库在管理报告共享的 value-free request UUID ledger 中使用独立 current-city replacement family。release 与 replacement 共用 request lock；同一 UUID 在两个合同中双向互斥。既有关闭的 lifecycle writer 只能通过 current-city 专用 provenance seam 核对 0057 approved attempt，不能直接读取 attempt ledger，也不能借此读取 protected report。

原因只允许 `late_accepted_data`、`contact_revision` 和 `contact_void`。关系和最小 audit 追加不可变；每份旧快照最多一个直接 replacement，每份新快照最多一个 predecessor。自链接、循环、分叉、stale head、跨项目／family、target context 漂移和时间倒序都失败关闭。请求、lineage 和授权锁取得后再次确认 `release_management_reports`。相同 request 与 canonical payload 精确幂等；载荷漂移失败关闭。

生命周期查询只返回 snapshot ID、`active`／`superseded` 和直接 replacement ID，不返回报告格、区域来源、贡献者、接触、坐标、隐藏前值或 PII。关系不改变目录排序；客户端不能据此把第一项称为 current 或 latest。

### 6CB 的范围

这是 DB-only、value-free 合同。它不处理 channel、interest、original-region 或 follow-up-consent，不做分析定义／跨版本更正，不生成 snapshot，也不增加 runtime、HTTP、Flutter、目录、导出、缓存、离线、分享、删除、tombstone、retention、备份清除、parent／overlap、warehouse 或真人平台验收。

### 6CB 的验证命令

从仓库根目录运行完整 PostgreSQL 合同：

```bash
./tool/run_postgres_tests_in_docker.sh
```

runner 会发现 0080 migration、structural check、rollback fixture 和 replacement concurrency script，并在 checksum、dump／restore 后重跑 migration、check 和 fixture。恢复库不重跑会提交 synthetic 行的并发脚本。

只调试 6CB 时，先确认 `DATABASE_URL` 是专用测试库，再运行：

```bash
./tool/postgres_migrate.sh
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/checks/verify_management_current_city_report_snapshot_replacements.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/fixtures/0080_management_current_city_report_snapshot_replacements.sql
./tool/verify_management_current_city_report_snapshot_replacements_concurrency.sh
```

这些命令只证明 synthetic DB-only current-city replacement，不证明新 snapshot 生成、其他 report family、分析定义／跨版本更正、runtime、HTTP、Flutter、目录、导出、删除、retention、生产身份或六平台真人运行时。

## Slice 6BP：验证组织项目后续联系同意占比候选

6BP 在 6BO 当前 opt-in 为 enabled 时生成 private release-candidate。它不是 snapshot，也不是已经发布的报告。
固定报告定义是 `contact_target_follow_up_consent_ratio_two_periods@1`，指标是 `follow_up_consent_ratio@1`，统计单位是 `contact_target_link`。
候选只使用两个相邻且已经结束的完整 ISO 周、项目报告时区和数据库拥有的 cutoff。配置记录时间不裁切统计期间。

调用方只提交可信内部 actor、显式项目、可信项目报告时区和数据库 cutoff。数据库在授权锁和项目锁后重新确认活动账号、组织／项目 membership、项目状态、
`release_management_reports` capability 和 6BO 当前 opt-in。`view_anonymous_analytics` 不能执行候选。专用 closed role 只能用于未来 release workflow。

候选只读取目标组织项目中当前有效 contact revision 的 contact-target link。同一 contact 的多个 link 分别计数，contributor 是 contact 的可信 `app_user_id`。
草稿、接触尝试、作废接触、旧 revision、其他项目和 cutoff 之外的事实在候选集之前排除。问卷答案、reach count 和推广对象资料不能形成统计单位。

`yes` 是分子，`yes + no` 是分母。`unknown` 计入 unanswered，`refused` 与 `not_applicable` 作为独立 coverage cell，`unknown_count` 与 `excluded_count` 固定为零。
每个期间的 yes、no 和每个 coverage cell 都独立执行 `N >= 10`、至少三位 contributor、贡献者不超过该 cell 总数一半。
只有 yes/no 都通过保护时，候选才返回 numerator、denominator 和 half-up basis points。任一类不安全时，ratio 为 `suppressed`，所有 ratio 数值为 `null`。
两个期间独立保护，不返回趋势或差值。未配置或停用时，在读取 link 前返回 `not_enabled`，不返回 report、ratio 或 coverage。
`not_enabled` 表示没有当前 opt-in；`suppressed` 表示已启用但该值没有通过保护。两者都不表示零。

### 从零开始运行 Docker

没有用过 Docker 时，先安装并打开 Docker Desktop。等待 Docker Engine 运行，再从仓库根目录执行：

```bash
docker version
./tool/run_postgres_tests_in_docker.sh
```

runner 会在源库建立专用 closed role，自动发现 0074 migration、structural check、rollback fixture 和并发脚本，并运行 checksum 检查。
dump／restore 阶段通过 `pg_restore` 重建独立恢复库，再重跑 check 和 fixture；恢复库不重新执行 migration，也不重跑会提交 synthetic 行的并发脚本。

### 只调试 6BP

并发脚本会提交 synthetic 行。先确认 `DATABASE_URL` 指向专用测试库，再运行：

```bash
export DATABASE_URL='postgresql://postgres:postgres@127.0.0.1:5432/tongxingzhe_test'
./tool/postgres_migrate.sh
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/checks/verify_management_follow_up_consent_ratio.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/fixtures/0074_management_follow_up_consent_ratio.sql
./tool/verify_management_follow_up_consent_ratio_concurrency.sh
```

check 验证 private function、`SECURITY DEFINER`、固定 search path、专用 role、列级 ACL 和无 `PUBLIC` execute。
fixture 验证统计单位、排除边界、yes/no 成对保护、coverage 独立保护、`not_enabled`／`suppressed` 和 value-free 输出。
并发脚本验证 candidate 与 disable、capability revoke、membership revoke、project archive 的锁线性化。

这些检查只证明 synthetic PostgreSQL 的 private candidate、隐私门槛、并发、ACL 和 restore 合同。它们不证明 snapshot、release、authorized read、runtime、HTTP、Backend、Flutter、
Drift、UI、目录、导出、缓存、离线、生产身份或 Android、iOS、macOS、Windows、Linux、Web 真人平台运行时，也不构成形式化不可重识别保证。

## Slice 6BQ：固定后续联系同意占比快照

6BP candidate 是已保护的计算结果，但还不是发布历史。6BQ 为它增加独立 snapshot lineage。第一次成功发布得到 baseline；下一次只有在 cutoff 前进且固定定义、时区 revision 和 source watermark 合法时，才会得到链接 predecessor 的 successor。

每个共享期间比较四个受保护单元：一个 yes/no ratio，以及 unanswered、refused、not-applicable 三个 coverage cell。`displayed` 数值已经通过服务端保护；`suppressed` 必须保持 `null`。不要在客户端、SQL 调试记录或 blocked attempt 中补算隐藏值。

`not_enabled` 表示当前项目没有启用该指标。发布函数不把它保存为空 snapshot，而是返回 value-free blocked metadata。same／earlier cutoff、没有共享期间、共享显示值或 privacy status 变化、时区 revision 漂移和 source watermark 回退也不能生成 snapshot。

### 运行数据库证据

没有用过 Docker 时，先打开 Docker Desktop，然后在仓库根目录运行：

```bash
docker version
./tool/run_postgres_tests_in_docker.sh
```

完整 runner 自动运行 0075 migration、structural check、rollback fixture、独立并发脚本、checksum 和 dump／restore。只调试可丢弃测试库时运行：

```bash
export DATABASE_URL='postgresql://postgres:postgres@127.0.0.1:5432/tongxingzhe_test'
./tool/postgres_migrate.sh
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/checks/verify_management_follow_up_consent_ratio_snapshot_lineage.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/fixtures/0075_management_follow_up_consent_ratio_snapshot_lineage.sql
./tool/verify_management_follow_up_consent_ratio_snapshot_lineage_concurrency.sh
```

fixture 会回滚，独立并发脚本会提交另一组 synthetic 行。恢复库通过 `pg_restore` 重建，只重跑 check 和 fixture。通过这些测试只说明当前 private PostgreSQL 合同成立，不说明读取、HTTP、客户端、生产身份或真人平台已经验收。

## Slice 6BR：只读取可信的后续联系同意占比快照

6BR 不生成报告，也不决定哪份快照是最新。调用方必须给出内部用户、project UUID 和 snapshot UUID。数据库先重新检查 active user、组织／项目 membership、active project 和 `view_anonymous_analytics`，然后只查找请求项目中的精确 snapshot。

可信读取必须同时对齐 0075 consent-ratio request claim、approved／approved_baseline attempt 和 snapshot。
固定 report identity、query fingerprint 或 release lineage 不一致时，不能返回正文。
时区 revision、cutoff、previous pointer 或 source watermark 不一致时，也不能返回正文。
函数返回前再次运行 6BQ strict validator；suppressed ratio／coverage 仍为 JSON `null`，读取不能补算隐藏值。

已授权调用有三种稳定结果：

- `completed`：返回原有 protected report；
- `not_found`：用于 unknown 或 cross-project UUID，不暴露其他项目是否存在该 snapshot；
- `untrusted_provenance`：用于同项目的 foreign family、legacy、blocked、缺失或漂移 provenance。

每次已授权调用写入一条新的 value-free audit。audit 记录最小授权链、snapshot identity、固定 report metadata 和结果状态，不保存 `protected_report`、period results、ratio、coverage、contact、target、contributor、原始回答、隐藏前值或 PII。撤权、过期、release-only、无有效成员或 inactive project 的调用在授权阶段失败，且不写 audit。

### 从零开始验证 6BR 数据库合同

先打开 Docker Desktop。在仓库根目录运行：

```bash
docker version
./tool/run_postgres_tests_in_docker.sh
```

`docker version` 的 client 和 server 都有输出后，完整 runner 才能启动一次性 PostgreSQL 16 容器。runner 自动执行 0076 migration、structural check、rollback fixture、read／revoke 并发脚本、checksum 和 dump／restore。

只调试可丢弃测试库时运行：

```bash
export DATABASE_URL='postgresql://postgres:postgres@127.0.0.1:5432/tongxingzhe_test'
./tool/postgres_migrate.sh
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/checks/verify_authorized_management_follow_up_consent_ratio_snapshot_read.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/fixtures/0076_authorized_management_follow_up_consent_ratio_snapshot_read.sql
./tool/verify_authorized_management_follow_up_consent_ratio_snapshot_read_concurrency.sh
```

fixture 会回滚；并发脚本使用独立 namespace 并提交 synthetic 行。恢复库只重跑 check 和 fixture，不重新执行 migration，也不重跑并发脚本。通过这些测试只证明 synthetic PostgreSQL 的授权、provenance、validator、audit、撤权锁和 restore 合同，不证明 runtime、HTTP、Backend、目录、Flutter、导出、生产身份或真人平台已经验收。

## Slice 6BS：用 exact identity 接入同意占比快照读取

6BS 不改变 6BR 的授权或报告合同。它只把 Backend 已验证的 external identity 映射为现有 active 用户，再用显式 project 和 snapshot UUID 调用 0076 private reader。`issuer + subject` 必须精确匹配；trim 不能把不同身份变成相同身份，unknown 或 inactive identity 失败关闭，bridge 不创建账号或个人上下文。

runtime 只拥有 0077 bridge 的 `EXECUTE`。它不能使用 `app_private`、执行 0076 reader，或读取用户、identity、snapshot、attempt、claim 和 audit 表。0076 仍负责 `view_anonymous_analytics`、0075 provenance、6BQ validator、撤权锁和每次已授权调用的 value-free audit。

Backend store 只执行一次固定四参数 SQL。strict parser 必须核对 access envelope、project／snapshot、固定 17-key report、相邻完整期间、两个 period result、ratio、三项 coverage、连续顺序和安全整数。`suppressed` 的 ratio／coverage 数值必须保持 JSON `null`。其他 report family、额外字段、contact、target、contributor、source、PII 或隐藏前值会使解析失败。

### 从零开始验证 6BS

先打开 Docker Desktop。在仓库根目录确认 Docker 可用：

```bash
docker version
```

再运行 Backend 合同测试和完整数据库套件：

```bash
cd backend/server
npm ci --ignore-scripts
npm run check
npm test
cd ../..
./tool/run_postgres_tests_in_docker.sh
```

Backend 测试验证固定 SQL、strict parser 和 typed `42501`。Docker runner 自动发现 0077 migration、check 和 fixture，显式运行真实 PostgreSQL integration，并继续执行 0076 read／revoke 并发、checksum 和 dump／restore。

只调试可丢弃测试库时运行：

```bash
export DATABASE_URL='postgresql://postgres:postgres@127.0.0.1:5432/tongxingzhe_test'
./tool/postgres_migrate.sh
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/checks/verify_runtime_authorized_management_follow_up_consent_ratio_snapshot_read.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/fixtures/0077_runtime_authorized_management_follow_up_consent_ratio_snapshot_read.sql
```

0077 fixture 使用 rollback namespace。0076 并发脚本使用另一组 committed namespace。恢复库只重跑 check 和 fixture，不重新执行 migration，也不重跑并发脚本。通过这些测试只证明 synthetic exact-identity bridge 和 Backend adapter；6BS 当时不包含 HTTP，HTTP 证据由后续 6BT 单独提供；它不证明 Flutter、生产身份、真实账号或真人平台已经验收。

## Slice 6BT：通过 HTTP 读取后续联系同意占比快照

6BT 把 6BS 的专用 snapshot store 接到一个固定的只读详情路径：

```text
GET /v1/projects/:projectId/management-follow-up-consent-ratio-report-snapshots/:snapshotId
```

### 请求顺序

固定 path 命中后，handler 必须先处理 Bearer identity：先解析并验证 token，再检查 project／snapshot UUID、query、GET body 的
非零 `Content-Length`／`Transfer-Encoding` 声明以及 6BS 专用 store。没有 token 或 token 无效时，即使 UUID、query、body 或 store 有问题，也先返回
`401 unauthenticated`。认证通过后，handler 只向 `PostgresManagementFollowUpConsentRatioReportSnapshotStore` 传递 verified `issuer + subject`、
显式 project UUID 和 snapshot UUID。它不调用 `SessionContext`、generic reader、其他 report-family store、`app_private` 或客户端 SQL。

GET 不接受 query 参数或 body。非零 `Content-Length` 或 `Transfer-Encoding` 等 body 声明，就必须失败关闭；handler 不读取客户端查询来选择
报告、时区、期间或 snapshot。store Promise 完成前不能写 HTTP 响应，这就是 Promise gate，也保证已授权读取的 value-free audit 在数据库提交后才进入
响应流程。

### 固定响应

成功响应的 JSON 根对象只有三个字段：

```json
{
  "access_event_id": "…",
  "snapshot_id": "…",
  "report": {}
}
```

`report` 逐字保留 6BR／6BS 已保护的 `contact_target_follow_up_consent_ratio_two_periods@1` 报告；HTTP 层不重算 ratio、不恢复
`suppressed` 值，也不修改 6BQ snapshot。

固定状态和 code 如下：

| HTTP 状态 | code |
| --- | --- |
| `401` | `unauthenticated` |
| `400` | `invalid_management_follow_up_consent_ratio_report_snapshot_request` |
| `403` | `management_follow_up_consent_ratio_report_snapshot_forbidden` |
| `404` | `management_follow_up_consent_ratio_report_snapshot_not_found` |
| `409` | `management_follow_up_consent_ratio_report_snapshot_untrusted` |
| `503` | `management_follow_up_consent_ratio_report_snapshot_unavailable` |

`404` 和 `409` 可以带 6BS store 返回的 value-free `access_event_id`，但错误不能带报告正文、报告格、授权关系、external subject、数据库消息、SQL、
栈或 PII。成功和错误响应都使用 `Content-Type: application/json; charset=utf-8` 与 `Cache-Control: no-store`。

### 如何测试以及测试证明什么

6BT 不增加 PostgreSQL migration、reader、directory、latest／current 选择、分页、筛选、Flutter、Drift、导出、缓存、离线、同步、replacement、
删除、retention、warehouse 或并发脚本。它的新增证据是 Backend handler、fixed route、real HTTP route 和 production composition 测试；这些
测试使用 synthetic identity 与 fake store，因此不需要真实账号、JWT provider 或数据库。

从仓库根目录运行：

```bash
cd backend/server
npm ci --ignore-scripts
npm run check
npm test
```

这些测试覆盖固定 method／path、认证先于 UUID／query／GET body／store、缺失或无效 token 的 `401`、malformed request 的 `400`、6BS store 的
`403`／`404`／`409`／`503` 映射、verified identity 与显式资源 ID 传播、单次专用 store 调用、Promise gate、三字段 success wire、错误脱敏和
`no-store`。它们只证明 Backend HTTP transport contract。

若要同时检查既有 6BS PostgreSQL 合同，回到仓库根目录运行：

```bash
cd ../..
./tool/run_postgres_tests_in_docker.sh
```

Docker runner 仍验证 0077 bridge、0076 reader、授权、provenance、strict parser、audit、撤权并发、checksum 和 restore。Docker 结果不替代
6BT HTTP 测试，也不证明已部署端点、production identity provider、客户端消费或 Android、iOS、macOS、Windows、Linux、Web 真人平台运行时。

## Slice 6BU：发现后续联系同意占比快照目录

6BU 为一个显式 project 提供受授权的 snapshot directory。它只增加 private PostgreSQL 合同，不把 directory 接到 runtime、Backend 或 HTTP。
canonical 函数名是：

```text
app_private.list_authorized_management_follow_up_consent_snapshots_v1(uuid, uuid)
```

函数每次调用都重新确认 active user、组织／项目 membership、active project 和 `view_anonymous_analytics`。目录读取与撤权沿既有 authorization／revoke lock order。
0075 consent-ratio family 的 `approved_baseline`／`approved` exact provenance 才能进入目录。foreign project、foreign report family、legacy、blocked、missing 和
drifted provenance 失败关闭或被排除。

### 固定的目录结果

成功结果的 root envelope 只有四项：

```json
{
  "access_contract_id": "…",
  "access_event_id": "…",
  "project_id": "…",
  "snapshots": []
}
```

`snapshots` 最多 20 项。每项只保留六个 metadata 字段：
`snapshot_id`、`report_id`、`report_version`、`reporting_time_zone`、`data_cutoff_utc` 和 `released_at_utc`。
数据库固定按 `data_cutoff_utc DESC`、`released_at_utc DESC`、`snapshot_id DESC` 排序。第一项只是固定排序的第一项，不表示 current、latest 或未被取代。
合同不接受 latest、current、分页或筛选参数。已授权 project 没有合格 snapshot 时返回空数组，并追加数量为 0 的成功 audit。

### 目录隐私和授权

目录 audit 使用专用、追加式、不可变、value-free 合同，只记录授权和访问 metadata。audit 不记录 snapshot ID、report、period、ratio、coverage、source、contributor、
target、contact 或 PII。未授权、撤权、过期、无成员、inactive project、unknown ID、跨 project 和权限不足的调用失败关闭，且不写成功 audit。
`PUBLIC`、`tongxingzhe_runtime`、普通 app role 和其他 report reader／writer 不能执行 private function 或读取 audit。

### 如何测试以及测试证明什么

从仓库根目录运行完整 Docker 套件：

```bash
./tool/run_postgres_tests_in_docker.sh
```

runner 自动发现 0078 migration、structural check、rollback fixture 和 directory／revoke concurrency，并执行 checksum 与独立 dump／restore。恢复阶段先准备缺失的
PostgreSQL roles，再重跑 check 和 fixture；不重跑会提交 synthetic 行的并发脚本。只调试可丢弃测试库时运行：

```bash
export DATABASE_URL='postgresql://postgres:postgres@127.0.0.1:5432/tongxingzhe_test'
./tool/postgres_migrate.sh
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/checks/verify_authorized_management_follow_up_consent_ratio_snapshot_directory.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/fixtures/0078_authorized_management_follow_up_consent_ratio_snapshot_directory.sql
./tool/verify_authorized_management_follow_up_consent_ratio_snapshot_directory_concurrency.sh
```

fixture 使用 rollback transaction；并发脚本使用独立 committed namespace。check、fixture 和并发测试通过，只证明 synthetic PostgreSQL 的 provenance、授权、20 项
目录、固定排序、锁、ACL、value-free audit、checksum 和 restore 合同。它不证明 runtime identity、Backend、HTTP、Flutter、部署服务、production data、缓存、离线或
Android、iOS、macOS、Windows、Linux、Web 真人平台运行时。前序 6BS／6BT 已定义 runtime、Backend 和 HTTP；6BU 不修改这些边界。

## Slice 6BV：通过 exact identity bridge 读取后续联系同意占比快照目录

6BV 在 6BU 的 SQL-only directory 之上增加 0079 `app_data` bridge。Backend 先验证 external identity，再把 exact `issuer + subject` 和显式 project UUID 交给 bridge。
bridge 只映射已有且 active 的 identity，不 trim、不 bootstrap、不创建 identity，也不接受内部用户 ID、capability、时区、截止点、筛选或 SQL。它只调用：

```text
app_private.list_authorized_management_follow_up_consent_snapshots_v1(uuid, uuid)
```

bridge 使用 `SECURITY DEFINER`、`VOLATILE` 和固定 `search_path = pg_catalog`。`tongxingzhe_runtime` 只有 bridge `EXECUTE`，不能使用 `app_private` schema，也不能直接
读取 identity、snapshot、attempt、claim、directory 或 audit 表。0078 继续负责 active user、组织／项目 membership、active project、`view_anonymous_analytics`、
0075 exact provenance、撤权锁、固定排序和 value-free audit。

Backend 为目录使用独立 store。store 只执行一次固定参数化 SQL：

```sql
SELECT app_data.list_authorized_management_follow_up_consent_snapshots_v1(
  $1::text, $2::text, $3::uuid
) AS directory_result
```

strict parser 只接受四项 root envelope：`access_contract_id`、`access_event_id`、`project_id` 和 `snapshots`。每个 item 只接受六项 metadata：`snapshot_id`、
`report_id`、`report_version`、`reporting_time_zone`、`data_cutoff_utc` 和 `released_at_utc`。parser 检查 exact keys、consent-ratio report ID、project 绑定、合法
UUID、规范 UTC 时间、最多 20 项、无重复和 `data_cutoff_utc`／`released_at_utc`／`snapshot_id` 固定降序。额外字段、缺失字段、错误 contract、非 consent-ratio report、
无效值和乱序结果失败关闭。只有 SQLSTATE `42501` 映射为 typed `forbidden`，其他 SQLSTATE、数据库错误和 parser 错误保持 unavailable。

### 如何验证 6BV

第一次使用 Docker 时，先启动 Docker Desktop，再从仓库根目录运行：

```bash
docker version
./tool/run_postgres_tests_in_docker.sh
```

完整 runner 自动发现 0079 migration、structural check 和 rollback fixture，运行 6BV Backend integration，继续运行 0078 directory／revoke concurrency，并执行
checksum 和独立 dump／restore。恢复阶段先准备缺失的 PostgreSQL roles，再重跑 check 和 fixture；不重跑会提交 synthetic 行的并发脚本。

如果只调试 6BV，先确认 `DATABASE_URL` 指向可丢弃测试库：

```bash
export DATABASE_URL='postgresql://postgres:postgres@127.0.0.1:5432/tongxingzhe_test'
./tool/postgres_migrate.sh
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/checks/verify_runtime_authorized_management_follow_up_consent_ratio_snapshot_directory.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/fixtures/0079_runtime_authorized_management_follow_up_consent_ratio_snapshot_directory.sql
cd backend/server
npm ci --ignore-scripts
npm run check
npm test
cd ../..
```

这些测试证明 exact identity、0078 delegation、固定目录 envelope、strict parser、最小 ACL 和 `42501` 映射。它们不证明 HTTP、Flutter、Drift、导出、缓存、离线、生产
身份、部署服务或 Android、iOS、macOS、Windows、Linux、Web 真人平台运行时。6BV 不增加 HTTP route、客户端消费、分页、筛选或 current／latest 语义。

## Slice 6BW：通过固定 HTTP GET 列出后续联系同意占比快照目录

6BW 把 6BV 的 consent-ratio snapshot directory 接到固定的 HTTP collection route：

```text
GET /v1/projects/:projectId/management-follow-up-consent-ratio-report-snapshots
```

collection route 只发现可选 snapshot metadata。它不读取 protected report，也不自动选择 current、latest 或第一项。调用方必须明确选择 snapshot，
再使用 6BT 的详情 route。

### 请求顺序和固定 wire

固定 path 命中后，handler 先验证 Bearer identity，再验证 project UUID、query、GET body 和 dedicated directory store。GET 不接受 query 或 body。
非零 `Content-Length` 或 `Transfer-Encoding` 声明也视为 body。缺少或无效 token 时先返回 `401 unauthenticated`，即使 project UUID、query、body 或 store
有问题也不先返回其他状态。

认证成功后，handler 只把 verified identity 和显式 project UUID 传给 6BV 的专用 store，并等待 Promise 完成后才写响应。成功返回 `200`，根对象只有：

```json
{
  "access_event_id": "…",
  "project_id": "…",
  "snapshots": []
}
```

每个 item 只有 `snapshot_id`、`report_id`、`report_version`、`reporting_time_zone`、`data_cutoff_utc` 和 `released_at_utc`。空目录也返回 `200` 和空数组。
第一项只是固定排序结果的第一项，不表示 current、latest 或未被取代。

HTTP 错误固定为：

| 情况 | HTTP 结果 |
| --- | --- |
| token 缺失或验证失败 | `401 unauthenticated` |
| project UUID、query 或 GET body 无效 | `400 invalid_management_follow_up_consent_ratio_snapshot_directory_request` |
| 6BV directory authorization forbidden | `403 management_follow_up_consent_ratio_snapshot_directory_forbidden` |
| verifier、store、parser、数据库或未知错误 | `503 management_follow_up_consent_ratio_snapshot_directory_unavailable` |

该 collection 的业务结果不返回详情读取的 `404` 或 `409`。unknown、cross-project、filtered 或不可信的单份 snapshot 不在目录响应中产生详情错误；其他 method 或未匹配 path
仍可由通用 server 返回 `404`。所有状态使用
`Content-Type: application/json; charset=utf-8` 和 `Cache-Control: no-store`。错误响应不返回数据库消息、SQL、stack、external subject、授权关系、
protected report、period、ratio、coverage、source、contributor、target、contact 或 PII。

### 如何验证 6BW

6BW 没有新的 PostgreSQL migration、fixture、check 或 Docker 数据库步骤。第一次使用 Docker 时仍可启动 Docker Desktop，并在仓库根目录运行：

```bash
docker version
./tool/run_postgres_tests_in_docker.sh
```

该 Docker 命令只回归前序 6BV、6BU 及其他数据库合同。它不能证明 6BW HTTP route。

运行 6BW 的 Backend 测试：

```bash
cd backend/server
npm ci --ignore-scripts
npm run check
npm test
cd ../..
```

测试覆盖固定 method／path、认证先于 UUID／query／GET body／store、body 声明、专用 store、空目录、三字段 success wire、Promise gate、`401`／`400`／`403`／`503`、
无业务 `404`／`409`、wrong method 的通用 `404`、错误脱敏、production composition 和所有响应的 `no-store`。测试还确认 HTTP 层不调用 `SessionContext`、generic 或详情 store，不执行
`app_private` 或客户端 SQL。

这些 synthetic HTTP 测试只证明 Backend transport contract 和 composition wiring。它们不证明 PostgreSQL 授权、Flutter、Drift、缓存、离线、导出、部署服务、
production identity、真实账号或 Android、iOS、macOS、Windows、Linux、Web 真人平台运行时。

## Slice 6BX：Flutter typed gateway 的合同和隐私边界

6BX 让 Flutter 读取 6BW 的 consent-ratio metadata 目录和 6BT 的一份明确快照。它只增加 Dart interface、HTTP adapter、strict parser 和内存结果。
它不增加新的 Backend route、PostgreSQL 查询、runtime bridge、UI、ViewModel、Drift、缓存、离线、同步、导出或分页。

### 两个入口和两个选择步骤

目录入口是：

```text
GET /v1/projects/:projectId/management-follow-up-consent-ratio-report-snapshots
```

详情入口是：

```text
GET /v1/projects/:projectId/management-follow-up-consent-ratio-report-snapshots/:snapshotId
```

gateway 只发送 GET。它不发送 query 或 body。目录调用使用显式 project UUID。详情调用还使用用户从目录明确选择的 snapshot UUID。
目录第一项只是服务端固定排序中的第一项，不能叫作 current、latest 或“推荐”。

### Dart 解析和隐私边界

数据库目录有四项 root，其中的 `access_contract_id` 是 private metadata。HTTP／Dart 目录只接受三项 root：`access_event_id`、`project_id` 和 `snapshots`。
每项只接受六项 metadata，最多 20 项，可以是空数组。详情只接受三项 root：`access_event_id`、`snapshot_id` 和 `report`。

详情 parser 只接受 `contact_target_follow_up_consent_ratio_two_periods@1`。它检查 project／snapshot／summary 绑定、两个完整期间、ratio 算术、coverage 顺序、
非负安全整数和 `suppressed = null`。多余字段、错误 key、PII 形状、contact、target、contributor、source、隐藏前值、错误期间或不安全整数均失败关闭。
gateway 不重算、不补回、不改写服务端的 ratio、coverage 或隐藏状态。

gateway 通过 `IdentitySession` 取得 Bearer token。首次收到 `401` 时只强制刷新并重试一次。成功响应必须是 JSON，并带 `Cache-Control: no-store`。
identity、HTTP、timeout、network、响应头、JSON、parser 和 closed 错误都映射为稳定 typed failure。结果只在内存中保存，并通过不可修改集合暴露。

HTTP 状态在 Dart 中固定映射为：`400 → invalidRequest`、`401 → unauthorized`、`403 → forbidden`、`404 → notFound`、`409 → untrusted`、
`503 → serviceUnavailable`。其他非成功状态进入 `serverRejected`。失败结果不携带响应正文、数据库消息、授权详情或 PII。

### 如何验证 6BX

在仓库根目录运行：

```bash
flutter pub get
dart analyze
flutter test --no-pub test/management_reports/http_follow_up_consent_ratio_report_gateway_test.dart
flutter test --no-pub
```

focused 测试使用 fake `IdentitySession` 和内存 `MockClient`，检查两个固定 path、Bearer、一次 `401` 刷新、无 query／body、JSON／`no-store`、三字段 root、
六字段 metadata、空目录、20 项边界、固定降序、显式 summary、两个期间、ratio、coverage、`suppressed = null`、安全整数、错误映射、不可修改集合和 `close`。
这些测试证明 Flutter transport、strict parser 和内存边界，不证明 6BT／6BW 的 Backend authorization、数据库 provenance、生产身份或真实平台运行时。

6BX 没有新的 Docker 数据库步骤。需要回归前序数据库合同时，先启动 Docker Desktop，再从仓库根目录运行：

```bash
docker version
./tool/run_postgres_tests_in_docker.sh
```

Docker runner 只回归已有 PostgreSQL、runtime bridge 和 Backend 合同。它不运行 Dart gateway 测试，也不证明部署端点、UI、缓存、离线、导出或 Android、
iOS、macOS、Windows、Linux、Web 真人平台行为。

## Slice 6BY：把 typed gateway 接入 AppDependencies 生命周期

6BY 只处理 Flutter composition 和资源所有权。它把已经存在的
`FollowUpConsentRatioReportGateway` 接到 `AppDependencies`，供后续 UI slice 使用；当前 slice 不把 gateway 传入 UI。

### 同一个身份和一个 gateway 实例

启动流程先打开一个 `IdentitySession`。如果配置了
`followUpConsentRatioReportGatewayBuilder`，`AppDependencies` 把这个已经打开的对象原样传给 builder，不创建第二个身份会话。builder 返回的 gateway
通过 `AppStartupReady.followUpConsentRatioReportGateway` 暴露给后续 composition。个人同意占比 gateway 和其他管理报告 gateway 仍由各自的 builder 创建，不能混用。

没有配置 builder 时，composition 使用 `DeferredFollowUpConsentRatioReportGateway`。它的读取方法返回 `notConfigured`，不发网络请求。这个 fallback 让未配置
Backend 的启动结果保持可处理，同时不把“未配置”伪装成空报告。

### 启动失败和 app dispose

gateway 建立后，启动还可能在其他步骤失败。此时 `AppDependencies.start()` 必须在失败清理中关闭已拥有的 gateway 一次。启动成功后，
`TongxingzheApp` 拥有 ready result；widget 被移除时，它关闭 gateway 一次。gateway 的 `close` 必须幂等，避免清理路径重复释放 HTTP 资源。

当前 slice 不把 gateway 传给 `_ReadyApp`、`ProductionHomeShell`、管理报告 browser、ViewModel、widget、导航或其他 UI。后续 UI slice 需要定义明确的消费、状态和
错误边界后，才能使用 `AppStartupReady` 暴露的实例。

### 如何验证 6BY

在仓库根目录运行：

```bash
flutter pub get
dart analyze
flutter test --no-pub \
  test/app/app_dependencies_test.dart \
  test/app/tongxingzhe_app_test.dart
flutter test --no-pub
```

focused 测试使用 fake identity、fake gateway 和 fake 数据库。它们通过 `AppDependencies.start()` 检查 builder 收到的 identity 与 ready result 相同，检查
deferred fallback 没有网络请求，并在后续启动失败和 `TongxingzheApp` dispose 时检查只关闭一次。全量 Flutter 测试检查既有 Dart 行为没有回归。

这些测试只证明 composition、deferred fallback 和资源生命周期。它们不证明 HTTP 请求、strict parser、Backend authorization、PostgreSQL、UI 消费、缓存、离线、
导出、部署端点、production identity 或 Android、iOS、macOS、Windows、Linux、Web 真人平台运行时。6BY 不新增数据库步骤；如需回归前序数据库合同，按[第 9 章](09-local-docker-and-ci-testing.md)运行 Docker runner。

## Slice 6BZ：在 Flutter 中显示后续联系同意占比独立面板

6BZ 在 6BY 已装配的 `FollowUpConsentRatioReportGateway` 上增加一个独立 panel。panel 接收 `AppStrings`、typed gateway 和可空的已授权 `projectId`。
当 `projectId` 为空时，panel 显示 inactive，不调用 gateway。项目存在时，panel 只为这个项目读取一次目录，并先显示 loading。

### 目录和详情

目录只显示 gateway 返回的 snapshot summary，并保持服务端顺序。空目录显示本地化的 empty 状态。panel 不自动打开第一项，也不选择 current、latest 或 replacement。
用户明确选择一个 summary 后，panel 才读取该 summary 的详情。详情显示固定 report／metric identity、项目、source scope、privacy policy、报告时区、data cutoff、
发布时间、previous 和 current 两个相邻完整期间、ratio 以及 unanswered／refused／not_applicable coverage。

panel 只显示 typed gateway 已接受的值。percentage basis points 只转换为文字格式，不重新计算 ratio。panel 不计算总数、趋势、百分点差或互补值，不排序或补值。
每个 ratio 和 coverage cell 都独立处理 privacy status。`displayed` ratio 显示服务端提供的 yes、no、numerator、denominator 和 basis points。
`suppressed` ratio 只显示本地化的 hidden 文本，不显示数值、零或隐藏前值。`suppressed` coverage 也只显示 hidden 文本。

### 状态、键盘和大字号

panel 有 inactive、loading directory、directory、loading detail 和可恢复 failure 状态。project change、返回目录、retry 和 dispose 会使旧 generation 失效。
迟到的 directory 或 detail 响应不能修改当前项目或当前视图。

目录、详情、返回和 retry 操作必须支持 Tab traversal、Escape、focus return、heading、label 和 live-region announcement。所有状态必须在 `320×568` viewport 和
`200%` text scale 下可读且不溢出。failure 只显示本地化错误和 retry，不显示 response body、数据库消息、授权详情、内部 ID 或 PII。

### 如何验证 6BZ

在仓库根目录运行：

```bash
flutter pub get
dart analyze
flutter test --no-pub \
  test/features/management_reports/follow_up_consent_ratio_report_panel_view_model_test.dart \
  test/features/management_reports/follow_up_consent_ratio_report_panel_test.dart
flutter test --no-pub
```

focused tests 使用 fake `FollowUpConsentRatioReportGateway`。ViewModel tests 检查 inactive、目录与详情 loading、空目录、exact summary、retry、failure、project change、
late response、return 和 dispose。Widget tests 检查两个期间、三项 coverage、displayed／suppressed 混合 cell、suppressed 不显示零或隐藏前值、键盘、focus return、
heading、label、live region、English localization、`320×568` 和 `200%` text scale。

这些 Flutter tests 只证明 panel 状态、typed rendering、可访问性、响应式布局和内存内 failure handling。它们不证明 gateway parser、HTTP transport、Backend authorization、
PostgreSQL、部署服务、production identity、持久化、offline 或 Android、iOS、macOS、Windows、Linux、Web 真人平台运行时。6BZ 不把第五个 report-family choice 加入
`ManagementReportBrowser`，不修改 `_ReadyApp`、`ProductionHomeShell`、`AppDependencies`、导航或 gateway passing route，也不新增数据库步骤。需要回归前序数据库合同
时，按[第 9 章](09-local-docker-and-ci-testing.md)运行 Docker runner。

## Slice 6CA：把后续联系同意占比接入管理报告浏览器

6CA 把 6BZ 的 panel 接入 `ManagementReportBrowser`。浏览器保留 channel、current-city、interest、original-region 四个既有 family，新增第五个互斥的
follow-up consent ratio family。channel 仍是默认选择。默认状态和其他四个 family 不请求这个 gateway。

### 明确选择和当前项目

用户明确选择第五个 family 后，浏览器才创建并显示 6BZ panel。鼠标、触摸、Enter 和 Space 都可以完成选择。第五个 family 使用本地化的中文和 English 标签，
并与其他 family 保持单一选择。选择不会自动打开目录第一项，也不会自动请求详情。panel 只使用当前已重新授权的
`ManagementAnalysisContext.projectId`。它不回退到个人项目、旧项目或 gateway 内置项目。

6BY 已在 composition root 创建 `FollowUpConsentRatioReportGateway`。这个实例沿
`AppStartupReady → _ReadyApp → ProductionHomeShell → ManagementReportBrowser` 原样传递。下游 browser 和 panel 只借用它，不替换、不拥有、不关闭它。
gateway 的 ownership 和 close 仍由 6BY 的 composition root 负责。

### 项目和 family 切换

切换项目时，浏览器使用新的 `ManagementAnalysisContext.projectId` 重建 panel。旧项目的 directory 或 detail 响应不能写回新项目。
切换到其他 family 时，6BZ panel 被移除；旧响应不能把它重新显示。既有四个 family 的行为保持不变。

### 如何验证 6CA

在仓库根目录运行：

```bash
flutter pub get
dart analyze
flutter test --no-pub \
  test/features/management_reports/management_report_browser_test.dart \
  test/app/app_dependencies_test.dart \
  test/app/tongxingzhe_app_test.dart
flutter test --no-pub
```

Browser 和 app composition tests 使用 fake gateway。它们检查 channel 默认且不发请求、明确选择第五个 family、当前项目传递、无自动 detail、键盘 focus、
project／family 切换、迟到响应隔离、同一 gateway 实例和 close ownership。它们还检查中英文标签、既有 family 不回归、`320×568` viewport 和 `200%` text scale。

6CA 不修改 `AppDependencies` 的 gateway 构造、identity、ownership 或 close 逻辑，也不修改 6BZ panel、typed gateway、HTTP、Backend、PostgreSQL、runtime、缓存、
offline、同步、导出或导航。这个 slice 不新增 Docker 步骤。若要回归前序数据库合同，先启动 Docker Desktop，再按[第 9 章](09-local-docker-and-ci-testing.md)的命令运行
Docker runner。Flutter fake tests 不证明 gateway parser、Backend authorization、数据库、部署端点、production identity 或 Android、iOS、macOS、Windows、Linux、Web 真人平台运行时。

## Slice 6S 如何固定地点来源合同

Issue #92 的 Slice 6S 只处理共享 PostgreSQL 的来源合同、历史回填和
fixture-first 证据。每个已接受 `contact_id + revision_number` 最多保存一条
追加式来源记录；可信追加与 revision 在同一 transaction 中提交，来源记录之后
不能 `UPDATE` 或 `DELETE`。这张表不是 `contact_region_assignments` 的替代
current projection，也没有来源读取 API。

来源记录必须把三种地点状态分开：

- `resolved` 保存最小区域、已发布 `tree_version`、6R 内容指纹和城市父链。它
  还要明确是有原始坐标，还是只有历史区域版本的 `region-only`；
- `pending_resolution` 保存合法经纬度和可选精度，不保存区域或区域树；
- `not_applicable` 表示纯非线下接触，不保存坐标或区域。

旧 revision 无法完整解释时标记 `incomplete`／`unknown`。服务端记录时间不能
冒充设备采集时间，不能 reverse-geocode，不能把旧区域猜成当前城市。6S 只从
每个不可变 revision 自己的 `snapshot.location` 和可选 `snapshot.locationSource`
回填：pending 复制自己的坐标；resolved 复制自己的区域、树版本和 6R fingerprint，
有合法 source 时保留采集坐标，没有时保留 `region-only`；矛盾或畸形 source
保持 `incomplete`／`unknown`。回填不能从单一 current assignment 伪造历史。

精确坐标是敏感接触事实。来源表留在受限 `app_data`，不进入管理报告、
错误响应或 warehouse。Backend 当前没有应用日志 sink；部署平台的访问日志不得记录
请求体或响应体。数据库会在 `warehouse_outbox` 写入边界移除 location
和 source，防止修订、冲突解决或作废复制完整 snapshot 时泄漏坐标；
`tongxingzhe_runtime`、区域发布者和管理分析 capability
都不会因此获得来源读取权。作废保留来源历史，账号／空间删除与保留期继续遵循
既有政策。该 slice 只覆盖已提交 contact revisions；当前没有地点字段的
`contact_attempts` 另行处理。

### 如何验证 6S PostgreSQL 合同

完整 Docker 套件会在空库、checksum 重放、可回滚 fixture、独立并发会话和没有
源 cluster roles 的 restore 集群中检查 0039 来源表。除完整套件外，可在已经运行
的测试库执行：

```bash
export DATABASE_URL='postgresql://postgres:postgres@127.0.0.1:5432/tongxingzhe_test'
./tool/postgres_migrate.sh
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/checks/verify_contact_location_provenance.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/fixtures/0039_contact_location_provenance.sql
./tool/verify_contact_location_provenance_concurrency.sh
```

这些检查只证明来源 shape、权限、历史回填和并发不变量；它们不证明 Flutter／
Backend 生产写入、区域 current 映射或区域报告不可重识别。

## 当前证据不能证明什么

这些条件减少直接披露和简单相减恢复的风险，不构成形式化的不可重识别保证。当前 fixture 覆盖固定渠道报告的相邻完整周、补录变化、稀疏格和互补隐藏，也用候选区域形状演练父子范围、跨版本重叠、外部已知事实、待解析与 `N/A`。6AO 只增加私有 DB-only current 城市快照和区域 lineage 合同；它没有交付生产区域报告，也未覆盖跨账号导出组合或真实外部资料攻击。6AH 的合同只证明服务端授权、生成并准备交付固定快照，不证明客户端落盘、分享或读取。

生产管理报表仍需完成：

- 组织邀请、项目分配、角色组合，以及生产成员和能力授予／撤销入口；
- 权限变更审计和一般组织业务上下文；
- 跨时区 revision 后重新建立基线或更正版的隐私判定；
- 可按历史 revision 水位重新执行的 `as-of` 投影、其他 report family 的更正版取代关系和删除流程；
- 把显式映射或来源坐标重解析安全接入指定报告截止点的 current 视图，并把 6AO 的 DB-only lineage 继续接入生产区域报告的授权、HTTP、UI、读取、导出和调度边界；
- 快照目录与单份读取以外的动态 API、缓存、图表，以及除 6AH 固定 canonical JSON v1 外的其他导出。

在这些前置条件完成前，不得删除个人指标 SQL 的 `app_user_id` 条件来制造团队汇总，也不得向 `tongxingzhe_runtime` 授予私有政策函数的执行权。
