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

固定排序不代表第一项是“当前”或“最新有效”报告。当前模型还没有更正版取代关系。客户端选择一项后，仍须调用单份快照端点；该端点会再次授权并追加自己的访问审计。

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

目录保留服务端顺序，但界面不把第一项称为“最新”“当前”或“有效”。当前数据模型没有更正版取代关系。用户离开详情后，键盘焦点回到刚才选择的目录项；选择另一项目后，旧项目的迟到响应会被 generation 检查丢弃。

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

现有 contact current projection 只保存 `region_id + tree_version`；`contact_region_assignments` 还是随 revision 更新的 current projection。Slice 6S 至 6V 会为有来源的 revision 保存解析前坐标，但没有建立跨版本映射或生产区域报告读取路径。系统仍不能把旧区域 ID 猜成相似名称的新城市。探针把缺失映射作为失败关闭条件，也不声称已交付两种生产视图。

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

这些条件减少直接披露和简单相减恢复的风险，不构成形式化的不可重识别保证。当前 fixture 覆盖固定渠道报告的相邻完整周、补录变化、稀疏格和互补隐藏，也用候选区域形状演练父子范围、跨版本重叠、外部已知事实、待解析与 `N/A`。它没有交付生产区域报告，也未覆盖跨账号导出组合或真实外部资料攻击。6AH 的合同只证明服务端授权、生成并准备交付固定快照，不证明客户端落盘、分享或读取。

生产管理报表仍需完成：

- 组织邀请、项目分配、角色组合，以及生产成员和能力授予／撤销入口；
- 权限变更审计和一般组织业务上下文；
- 跨时区 revision 后重新建立基线或更正版的隐私判定；
- 可按历史 revision 水位重新执行的 `as-of` 投影、更正版取代关系和删除流程；
- 可验证的 current 跨版本映射，以及生产区域报告自己的完整网格、互补隐藏、授权和快照 lineage；
- 快照目录与单份读取以外的动态 API、缓存、图表，以及除 6AH 固定 canonical JSON v1 外的其他导出。

在这些前置条件完成前，不得删除个人指标 SQL 的 `app_user_id` 条件来制造团队汇总，也不得向 `tongxingzhe_runtime` 授予私有政策函数的执行权。
