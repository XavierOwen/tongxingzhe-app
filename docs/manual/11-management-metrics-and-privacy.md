# 第 11 章：管理指标如何构造完整网格并隐藏小样本

个人分析和管理分析处理不同的信任边界。个人页可以立即显示本人设备上的事实，并说明哪些接触尚未同步。管理分析只能使用后端已接受的数据，还必须先降低小群体披露风险。

当前实现完成管理隐私政策的基础模块和跨层 fixture。它没有开放管理 HTTP 端点，也没有授予任何账号查看团队汇总的权限。组织成员关系、管理 capability 和项目报告时区完成后，才能把该政策接入生产查询。

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

Docker 的安装、输出解释和失败容器保留方法见[第 9 章](09-local-docker-and-ci-testing.md)。

## 当前证据不能证明什么

这些条件减少直接披露和简单相减恢复的风险，不构成形式化的不可重识别保证。当前 fixture 尚未覆盖父子区域、重叠区域、任意相邻范围、跨账号导出组合或外部资料攻击。

生产管理报表仍需完成：

- 组织和项目成员关系；
- 独立的管理分析 capability；
- 项目固定报告 IANA 时区；
- 服务端固定报告注册、请求 canonicalization 和审计；
- 区域与时间重叠的重识别演练；
- 只接收抑制后结果的 API、缓存、图表和导出。

在这些前置条件完成前，不得删除个人指标 SQL 的 `app_user_id` 条件来制造团队汇总，也不得向 `tongxingzhe_runtime` 授予私有政策函数的执行权。
