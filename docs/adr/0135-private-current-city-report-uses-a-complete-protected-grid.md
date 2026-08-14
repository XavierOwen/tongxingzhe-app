# ADR-0135：私有 current 城市报告使用完整受保护网格

- 状态：已接受
- 日期：2026-08-14
- Slice：6AN
- Issue：#157
- Requirement：`REGION-007`–`REGION-013`、`ANALYTICS-023`、`PRIVACY-015`、`TEST-017`

## 背景

6AK、6AL 和 6AM 已分别固定跨版本映射、单条地点归属和报告截止点的 current 目标树。现有固定管理报告链只认识渠道维度和 16 格文档。向注册表插入区域定义并不能让旧执行、快照或导出函数安全理解新的网格。

## 决定

首个区域报告候选固定为 `contact_sessions_by_current_city_two_periods@1`。它只使用 current 视图、城市粒度、项目报告时区下最近两个完整 ISO 周和 `contact_sessions@1`，不接受客户端提供的树版本、区域集合、坐标、polygon 或其他筛选。

私有 executor 先用 6AM 从可信 `data_cutoff_utc` 取得目标树，再把显式版本和内容指纹传给 6AL。每条可报告归属只进入目标树中唯一的城市祖先。完整网格包含两期间和目标树中的全部城市，并按稳定区域 ID 排序。目标树出现嵌套城市、归属没有唯一城市祖先或证据漂移时失败关闭。

每个城市格以接触场次为真实单位，必须同时满足 `k=10`、至少三位贡献者和单人不超过一半。一个期间若只有一个格首先被隐藏，政策再按稳定顺序互补隐藏一个原本可显示的格。隐藏格只返回 `null`，报告不返回名称、边界、坐标、来源、接触、revision、贡献者或 PII。

新定义使用专用 canonicalizer 和私有执行合同。旧渠道 canonicalizer、16 格校验、快照、HTTP 和导出链继续拒绝它，直到后续工作单元增加显式 dispatcher、文档校验和 lineage。注册表中存在定义不表示生产入口已经支持该报告。

executor 由无登录、无成员的最小 reader role 拥有。该角色只读取执行所需的接触、来源索引、区域节点和 change watermark 列，并执行 6AM、6AL 与保护函数。runtime、`PUBLIC` 和区域维护身份不能执行 executor。

## 后果与边界

城市单一粒度避免在同一文档中发布父区域总数和子区域数。完整网格与互补隐藏减少省略格和单一未知格造成的相减风险，但不构成形式化不可重识别保证，也不能知道所有外部事实。

候选读取现有 current contact projection，并记录 source change watermark；它不是历史 `as-of` 重放。此决定不交付 original 视图、生产快照发布、runtime bridge、HTTP、Flutter、缓存、导出、区域治理、更正版或删除。
