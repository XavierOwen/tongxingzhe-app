# 第 11 章：管理指标如何构造完整网格并隐藏小样本

个人分析和管理分析处理不同的信任边界。个人页可以立即显示本人设备上的事实，并说明哪些接触尚未同步。管理分析只能使用后端已接受的数据，还必须先降低小群体披露风险。

当前实现完成管理隐私政策、固定报告请求合同、完整周期间解析、私有执行管线、重叠报告发布判定和跨层 fixture。它没有开放管理 HTTP 端点，也没有授予任何账号查看团队汇总的权限。组织成员关系、管理 capability 和项目报告时区配置完成后，才能把这些模块接入生产查询。

## 先确定统计单位

匿名阈值中的“十个”不是固定指十条数据库行。每个指标必须使用自己的真实统计单位：

- 接触场次和渠道使用有效接触记录；
- 触达人数使用实际参与人数；
- 当前关系阶段使用不同的“对象 × 项目”关系；
- 阶段变更不能用同一关系的重复事件凑足阈值。

本章实现的固定报表只处理 `contact_sessions` v1，所以统计单位是有效接触场次。草稿、接触尝试和已作废接触仍按指标目录排除。

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

SQL 函数位于 `app_private` schema。`tongxingzhe_runtime` 没有 schema 使用权或函数执行权。这个权限边界防止 Backend 在成员授权和报告时区尚未完成时，把测试基础误接成生产管理端点。

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

审计信封只保存请求者内部 ID、项目 ID、报告 ID 与版本、查询指纹、UTC 请求时间和结果状态。它不保存报表格值、贡献者数量、最大贡献值或隐藏的精确值。当前代码只固定信封结构。持久审计必须在未来授权后的执行事务中写入。

TypeScript 与 PostgreSQL 都读取 [`management_report_requests_v1.csv`](../../backend/database/fixtures/shared/management_report_requests_v1.csv)。fixture 包含有效请求、未知报告、未知版本，以及客户端伪造项目、时区、日期、维度、筛选和导出字段的负向场景。

## 两个完整周如何确定

固定报告定义包含 `iso_week_monday_v1` 边界版本。这个字段来自服务端注册表，不是客户端参数。未来的授权执行层必须从项目配置取得报告 IANA 时区，并用后端已经接受数据的 UTC 截止点调用期间解析器。

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

当前切片只固定读取合同。它没有决定项目时区保存在哪里、谁能修改、修改何时生效，也没有查询任何接触数据。PostgreSQL 函数仍在 `app_private`，runtime role 不能直接调用。

## 私有执行管线如何筛选事实

[`execute_management_contact_session_report_v1`](../../backend/database/migrations/0026_management_report_execution.sql) 只接受固定报告 ID／版本、可信项目 ID、可信项目报告时区和可信 UTC 数据截止点。前三个查询条件之外的维度、日期范围和筛选仍不存在。

函数按以下顺序处理：

1. 规范化固定报告定义，并确认项目仍有效；
2. 解析两个完整周；
3. 只读取同一项目、`lifecycle_status = active`、初次提交时间不晚于数据截止点、实际发生时间位于两个半开周期间的 `contacts`；
4. 在函数内部按“期间 × 渠道 × `app_user_id`”计数；
5. 立即把贡献送入完整网格与隐私政策，只返回保护后的 16 格。

`contact_attempts` 不在查询来源中。作废接触、右边界上的下一期接触、截止后才提交的接触和其他项目接触也不进入。`app_user_id` 只作为内部贡献者键，不会出现在结果中。输出格只有期间、渠道／总计、稳定顺序、可选数量和隐私状态；隐藏格的数量是 JSON `null`，不是先发送精确值再要求客户端隐藏。

这个函数读取接触的当前投影，所以它形成动态报告，不是“截至过去某一时刻”的历史快照。数据截止点限制初次提交事实并说明本次查询的新鲜度，但不会倒转后来发生的修订。正式快照必须在后续切片固定修订版本、时区、指标、隐私规则和生成时间，不能把当前函数的旧截止参数伪装成历史复现。

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

这个函数只提供发布前判定，不会保存之前发布的报告。未来管理端点必须读取可信的既有快照或发布历史，在同一授权流程中执行判定并持久记录结果。当前函数仍位于 `app_private`，runtime role 无权执行。

`0027_management_report_pair_release.sql` 的 fixture 建立三个相邻周。稳定滚动报告共享一个周并通过；相同周期的重复报告共享两个周并通过。随后 fixture 加入两条补录，使一个共享格从 `10` 变成 `11`，另一个从 `suppressed` 变成 `displayed`，发布判定必须阻止。fixture 还验证互补隐藏、九个单位的稀疏格、无共享期间、伪造隐藏值、任意日期、区域维度和排除已知推广者等探针。

## 在 Docker 中验证

先启动 Docker Desktop。然后在仓库根目录运行：

```bash
./tool/run_postgres_tests_in_docker.sh
```

脚本会建立临时 PostgreSQL 16 容器，执行全部 migration、权限检查和 fixture。它还会导出 `app_data`、`app_private` 与 migration 历史，再恢复到第二个空库重跑检查。脚本结束后自动删除容器。

只想验证 Dart 政策时运行：

```bash
flutter test --no-pub test/features/contact_metrics/management_privacy_policy_test.dart
```

只想验证 Backend 请求和期间合同时运行：

```bash
cd backend/server
npm ci
npm test
```

Docker 的安装、输出解释和失败容器保留方法见[第 9 章](09-local-docker-and-ci-testing.md)。

## 当前证据不能证明什么

这些条件减少直接披露和简单相减恢复的风险，不构成形式化的不可重识别保证。当前 fixture 覆盖固定报告的相邻完整周、补录变化、稀疏格、互补隐藏和已知推广者排除探针。它尚未覆盖父子区域报告、跨账号导出组合或真实外部资料攻击。

生产管理报表仍需完成：

- 组织和项目成员关系；
- 独立的管理分析 capability；
- 项目固定报告 IANA 时区的保存、修改、生效时间和历史；
- 授权后的固定报告端点、可信历史快照、发布历史、重叠判定强制执行和持久审计；
- 父子区域与重叠区域报告的重识别演练；
- 只接收抑制后结果的 API、缓存、图表和导出。

在这些前置条件完成前，不得删除个人指标 SQL 的 `app_user_id` 条件来制造团队汇总，也不得向 `tongxingzhe_runtime` 授予私有政策函数的执行权。
