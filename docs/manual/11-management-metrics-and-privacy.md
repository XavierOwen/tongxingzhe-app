# 第 11 章：管理指标如何构造完整网格并隐藏小样本

个人分析和管理分析处理不同的信任边界。个人页可以立即显示本人设备上的事实，并说明哪些接触尚未同步。管理分析只能使用后端已接受的数据，还必须先降低小群体披露风险。

当前实现完成管理隐私政策、固定报告请求合同、完整周期间解析、私有执行管线、重叠报告发布判定、不可变受保护快照、项目报告时区版本历史、管理报告能力授权，以及组合这些合同的可信发布 v2。它仍没有生产成员管理入口、管理 HTTP／读取端点，也没有向 runtime role 授予查看或发布团队汇总的权限。

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

SQL 函数位于 `app_private` schema。`tongxingzhe_runtime` 没有 schema 使用权或函数执行权。可信发布 v2 已在同一私有 schema 中组合这些政策，但生产 HTTP 和读取入口尚未建立，Backend 仍不能把测试基础直接接成管理端点。

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

审计信封只保存请求者内部 ID、项目 ID、报告 ID 与版本、查询指纹、UTC 请求时间和结果状态。它不保存报表格值、贡献者数量、最大贡献值或隐藏的精确值。可信发布 v2 使用同样的最小化原则，并另存当次授权关系、能力 grant、时区 revision 和底层快照关联。它仍不是生产访问审计，因为当前没有 HTTP 读取或发布入口。

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

历史 v1 发布和读取函数仍没有 runtime 权限。`0031` 的私有 v2 已把 `0030` 授权、`0029` 时区 revision 和历史 `6G` 发布函数接在同一事务中。未来 HTTP gateway 仍必须先从认证 token 解析内部用户，再调用受控的服务层；不能获得 `app_private` 的通用执行权。

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

- `view_anonymous_analytics` 允许未来的受保护读取入口查看匿名管理分析；
- `release_management_reports` 允许私有可信发布入口尝试建立正式报告。

两项能力互不包含。项目管理员角色、组织所有者角色、当前项目选择和登录账号都不是替代凭证。发布入口若以后还要在响应中返回报告内容，必须同时检查发布与查看能力。

私有 `resolve_management_report_authorization_v1` 不接收客户端时间或报告的数据截止时间。它依次取得组织、项目和能力 transaction lock，再使用数据库当前时间检查活动账号、未删除组织、活动项目和三层有效事实。它只返回内部 ID、能力和授权参考时间，不返回角色、报告格、个人资料或可重复使用的 token。

“在同一事务中消费”是安全要求，不是性能建议。解析器与成员／能力撤权使用相同的 transaction lock。若受保护操作先取得锁，撤权会等该操作提交；若撤权先提交，后来的解析会看见结束边界并失败。调用方若先解析、提交事务，再在另一个事务执行报告操作，就会重新制造检查与使用之间的空窗。

Flutter 不能读这些表，`tongxingzhe_runtime` 也不能执行解析器。可信发布 v2 在同一事务中消费授权证据；组织邀请、生产授予与撤销、角色组合、权限变更审计和受保护报告端点仍须由后续 Slice 实现。

## 可信发布 v2 如何组合三条私有合同

[`release_management_report_snapshot_v2`](../../backend/database/migrations/0031_trusted_management_report_release.sql) 只有五个参数：幂等请求 ID、内部用户、项目、固定报告 ID 和版本。调用方没有位置可以提交 capability、时区、数据截止点、授权时间或报告 JSON。

函数按固定顺序取得授权、请求、项目时区和报告 lineage 的 transaction lock。等待全部结束后，它再次检查 `release_management_reports`。第二次检查返回的数据库时间同时成为授权参考时间和数据截止点；函数再从不可变时区历史中选择当时有效的 revision。这样，发布在等待 lineage 或时区配置期间跨过能力结束边界时，不能继续使用较早的授权结果。

每次正常 v2 尝试把授权关系 ID、能力 grant、授权参考时间、时区 revision、截止点、比较快照、发布快照、状态和原因码写入 `management_report_release_v2_attempts`。这张表不保存候选报告、格值或贡献者。授权失败和未配置时区会回滚，不留下尝试；lineage 失败只写最小原因，不调用 6G 生成器。

没有历史快照时，v2 可以建立一次基线。有历史时，最近快照必须由 v2 建立，而且时区 revision 必须相同。IANA 文本相同也不够：项目从 UTC 改到其他时区再改回 UTC，revision 已改变，发布仍返回 `release_time_zone_revision_changed`。当前合同不自动建立跨时区新基线，因为那会让两套不同期间边界的报告绕过重叠保护。如何安全恢复发布需另行设计。

相同 v2 请求重试会先重新授权，再返回首次最小结果。已经被 v1 使用的 UUID 不可补记为 v2 provenance。发布能力也不自动授予查看能力；返回值只有报告身份、时区 revision、截止点、快照关联、状态和原因码，不含报告内容。

## 在 Docker 中验证

先启动 Docker Desktop。然后在仓库根目录运行：

```bash
./tool/run_postgres_tests_in_docker.sh
```

脚本会建立临时 PostgreSQL 16 容器，执行全部 migration、权限检查和 fixture。独立会话检查还会证明三层授权的重叠写入各只有一个成功、授权消费与撤权按事务顺序完成、并发滚动发布等待基线事务，以及相同期望版本只能追加一个报告时区版本。v2 检查另会让发布等待到能力自然到期，并验证“发布先取得时区锁”和“配置先取得时区锁”两种顺序。随后脚本导出 `app_data`、`app_private` 与 migration 历史，恢复到第二个空库重跑检查。脚本结束后自动删除容器。

并发脚本会提交 synthetic 数据，这些行会进入后面的 dump；普通 fixture 虽然回滚，却会在恢复库再运行一次。新增测试时，两类文件必须使用不同的 synthetic UUID 前缀。若第一次 fixture 通过、恢复后的同一 fixture 报重复主键，先检查命名空间是否与某个并发脚本重叠。

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

- 组织邀请、项目分配、角色组合，以及生产成员和能力授予／撤销入口；
- 权限变更审计和可信的当前组织／项目上下文；
- 跨时区 revision 后重新建立基线或更正版的隐私判定；
- 授权后的固定报告端点和访问审计；
- 可按历史 revision 水位重新执行的 `as-of` 投影、更正版取代关系和删除流程；
- 父子区域与重叠区域报告的重识别演练；
- 只接收抑制后结果的 API、缓存、图表和导出。

在这些前置条件完成前，不得删除个人指标 SQL 的 `app_user_id` 条件来制造团队汇总，也不得向 `tongxingzhe_runtime` 授予私有政策函数的执行权。
