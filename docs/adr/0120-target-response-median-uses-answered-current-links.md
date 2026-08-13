# 对象当次反应中位等级只使用当前已填关联

状态：**已接受（2026-08-13）**。

关联：Issue #108、Slice 6AA；ADR-0060、ADR-0061、ADR-0068、ADR-0070、
ADR-0076、ADR-0116、ADR-0119；`TARGET-004`、`TARGET-006`、
`TARGET-007`、`TARGET-013`、`ANALYTICS-001`、`ANALYTICS-002`、
`ANALYTICS-007`、`ANALYTICS-012`。

## 决定

`target_response_ordinal_summary` v1 从
`target_response_distribution` v1 的五档数量生成已填关联总数和
下中位等级。它使用相同的 contact-target link 候选集、个人可信
scope、UTC 半开期间和当前有效 contact revision。

样本不为空时，累计数量首次达到 `(answered + 1) ~/ 2` 的真实等级就是
中位等级。偶数样本取两个中间观察值中较低的一个，不平均等级。
没有已填关联时中位等级为 `null`。

`response_level IS NULL` 不进入已填分母，也不映射为等级 `2`。未填
数量继续由 `target_response_distribution` v1 的 `unanswered_count` 表示。

## 后果与边界

个人页必须同时显示五档数量、已填分母、未填覆盖和中位等级。
中位等级不是关系阶段、绩效评分或对象长期状态。本决定不新增关联
存储、对象类型拆分、管理报表或算术平均指标。
