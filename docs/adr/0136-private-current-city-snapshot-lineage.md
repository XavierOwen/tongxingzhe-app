# ADR-0136：current 城市报告复用通用快照存储并保持区域 lineage 独立

- 状态：已接受
- 日期：2026-08-19
- Slice：6AO
- Issue：#159
- Requirement：`ANALYTICS-024`、`PRIVACY-016`、`TEST-018`；关联 `REGION-007` through `REGION-013`、`ANALYTICS-007`、`ANALYTICS-012`、`ANALYTICS-022`、`ANALYTICS-023`、`PRIVACY-001` through `PRIVACY-006`、`PRIVACY-010`、`PRIVACY-014`、`PRIVACY-015`

## 背景

6AN 已生成私有的 `contact_sessions_by_current_city_two_periods@1` 候选，包含两个完整期间的 8 格城市
网格。既有通用管理报告存储和渠道 v2 发布链以渠道维度和 16 格合同为前提。直接复用它的渠道 provenance
会把两个不同的报告形状和授权边界混在一起。

## 决定

6AO 复用通用不可变的受保护快照存储，但为 current 城市报告保留独立的区域 release attempt／provenance。
区域 validator 和 pair comparison 固定 report、metric、dimension、view、granularity、query fingerprint、privacy、
source scope、期间、source watermark、target context 和完整 cells；unavailable、额外字段、错误 identity、错误
target tuple、缺失／重复／乱序网格及期间错误失败关闭。`displayed` 遵守 6AN 的 `k=10` 保护，`suppressed` 必须
是 JSON `null`。
私有发布只接受 request ID、可信内部用户、项目和固定报告 definition/version。数据库在必要锁后重新验证
`release_management_reports`，在同一 release transaction 中派生可信项目报告时区 revision、`data_cutoff_utc`
和 6AM target context，再调用 6AN。调用方不能提交 capability、JSON、时区、截止点、城市列表或 target tuple。

首个通过 6AN 合同的文档建立唯一 baseline。后续成功发布只能推进 cutoff，链接前一 snapshot，并保持定义、
期间、完整网格、target tuple 和可信时区 revision 一致。相同 request 和固定上下文精确幂等，不新增 snapshot
或 attempt。value-free claim 使 current-city UUID 与渠道发布 UUID 互斥；trusted v2 与其委托的 v1 记录共享渠道
claim。

same／earlier cutoff、无共享期间、共享期间的城市值或隐私状态变化，以及任一上下文漂移，均返回
稳定 blocked reason。阻断尝试只保存不含 protected document、cells、来源、贡献者、隐藏前值和 PII 的最小 lineage
证据。snapshot 与 attempt 均追加不可变，不允许 UPDATE 或 DELETE。区域 provenance 不得解释为渠道 v2 provenance，
既有 channel v2/read/directory/export 也继续拒绝区域文档。

## 后果与边界

通用存储避免重复快照基础设施，独立 lineage 防止区域 8 格合同绕过渠道 16 格合同。发布能力、可信时区
revision 和 target tuple 由数据库重新确认，调用方不能通过请求参数改写它们。

本决定只交付 DB-only 的存储、授权重检、区域 lineage 和漂移失败关闭。它不交付 runtime bridge、HTTP、
Flutter、Drift、缓存、UI、目录、读取、导出、生产调度、能力授予／撤销、original、历史 `as-of`、更正版或
删除、retention 或 warehouse 流程。runtime、`PUBLIC` 和区域维护身份不能执行发布、读取区域 provenance 或
直接写区域 attempt／snapshot 表。

## 验证

`0057` migration、结构与权限 check、synthetic fixture、并发脚本、checksum 和 dump／restore 必须覆盖有效
与无效 6AN 文档、validator／pair 字段、unavailable、额外字段、错误 identity、完整网格、首个唯一 baseline、
前一 snapshot 链接、精确幂等、same／earlier cutoff、无共享期间、共享值变化、定义／期间／网格／target tuple／
时区 revision 漂移、value-free blocked attempt、snapshot／attempt 不可改删、角色读写边界、通用快照存储复用以及
与渠道 v2/read/directory/export 的隔离。blocked 记录不得含 protected document、cells、来源、贡献者、隐藏前值
或 PII。完整 Docker 套件只证明 DB-only synthetic 合同，不证明 HTTP、UI 或生产调度已完成。
