# 后续联系同意占比要求项目明确启用

状态：**已接受（2026-08-13）**。

关联：Issue #120、Slice 6AD-0；ADR-0066、ADR-0117、ADR-0119；
`TARGET-004`、`TARGET-010`、`ANALYTICS-003`、`ANALYTICS-007`、
`ANALYTICS-010`、`ANALYTICS-012`、`ANALYTICS-014`。

## 决定

`follow_up_consent_ratio@1` 是项目可选的个人分析指标。项目未启用时，结果状态为
`not_enabled`，不返回 `0 / 0`、百分比、缺失覆盖或排除数。`not_enabled` 表示没有配置
这项分析，不等于没有接触、没有回答、样本不足、权限失败或服务不可用。

项目启用后，统计单位是可信个人项目和 UTC 半开期间内，当前有效 contact revision 的
contact-target link。一个接触关联两个对象时计两个单位。旧 revision、草稿、接触尝试、
作废接触、其他项目和期间外事实在候选集之前排除；同名场次问卷答案不属于对象关联，
也不能形成统计单位。

分子是 `yes`，分母是 `yes + no`。`refused` 和 `not_applicable` 分开保存为覆盖。当前
对象关联把 `unknown` 同时用作新关联的默认值，所以它不能证明使用者主动选择了“未知”。
v1 将所有 `unknown` 映射为 `unanswered_count`，并把 `unknown_count` 固定为零。未来若要
区分主动的“无法判断”和从未回答，必须先新增可区分的录入与存储事实，再发布新指标版本；
不能从旧记录猜测。

整数百分比基点按 half-up 从 `yes / (yes + no)` 派生。项目已启用但分母为零时保留
`0 / 0` 和空百分比，不显示 `0%`。候选集之前的排除不累加到 `excluded_count`；v1 将其
固定为零，避免为了统计排除数而扫描草稿、尝试、其他项目或旧 revision。

## 后果与边界

Slice 6AD-0 只用共享 synthetic fixture 固定合同，不新增项目设置、生产指标、查询、
Drift schema、Backend 端点或 UI。后续实现必须先交付可信的项目启用事实，并为
`not_enabled` 使用独立结果类型，不能拿精确 `0 / 0`、隐私抑制或通用错误代替。

个人结果不得成为目标、排名或考核。未来管理展示仍需按 contact-target link 的真实统计
单位执行最小样本、贡献者和互补隐藏；本决定不注册管理报告。
