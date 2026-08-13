# 对象当次反应五档比例使用当前已填关联

状态：**已接受（2026-08-13）**。

关联：Issue #112、Slice 6AB；ADR-0117 至 ADR-0120；`TARGET-004`、
`TARGET-006`、`TARGET-007`、`TARGET-013`、`ANALYTICS-001`、
`ANALYTICS-002`、`ANALYTICS-003`、`ANALYTICS-007`、`ANALYTICS-010`、
`ANALYTICS-012`。

## 决定

`target_response_level_ratios@1` 固定返回 `0–4` 五档比例。统计单位是当前有效
contact revision 中的 contact-target link，不是接触场次、触达人数或去重对象。
候选集使用个人可信 scope、UTC 半开期间和当前 revision；旧 revision、草稿、接触
尝试和作废接触不进入候选集。

共同分母是 `answered contactTargetLink` 的数量，也就是 `response_level` 非 `NULL`
的当前关联。五个等级分子分别统计 `0–4`，分子之和必须等于共同分母。`NULL` 只增加
`unanswered_count`，不进入任何分子或分母，也不能改写为等级 `2`。

每档百分比保存为整数基点，不以浮点数作为权威值。分母大于零时，按 half-up 规则
从 `numerator / denominator` 计算基点：

```text
(numerator × 10000 + denominator ~/ 2) ~/ denominator
```

例如 `2 / 9` 返回 `2222` 基点。分母为零时保留 `0 / 0`，百分比为 `NULL`，页面显示
“暂无可计算比例”，不显示 `0%`。

本地 Drift 不新增查询。现有对象反应汇总已经返回五档数量和未填写覆盖；Flutter
从这些数量生成版本化 `RatioMetricValue`。PostgreSQL 另提供 `0046` 窄 bridge，
返回相同的五行合同并重新核对个人 scope。它不读取对象 PII，也不成为管理报告或
任意查询入口。

## 后果与边界

最近七日个人页每档同时显示数量、分子／分母和百分比，并保留未填写覆盖与中位等级。
即使指标单位是 contact-target link，个人结果的同步覆盖仍只描述接触场次；不能从
待同步场次推导已同步关联数。

本决定不新增或修改对象关联、反应、revision 或对象 PII 存储，不实现对象类型拆分、
关系阶段、后续联系同意占比、管理报表、排名、趋势、导出或 warehouse 新指标。
