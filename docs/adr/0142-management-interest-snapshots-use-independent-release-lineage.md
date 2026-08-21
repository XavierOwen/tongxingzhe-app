# ADR-0142：管理兴趣报告快照使用独立发布 lineage

- 状态：已接受
- 日期：2026-08-21
- Slice：6AW
- Issue：#179
- Requirement：`ANALYTICS-032`、`PRIVACY-024`、`TEST-026`、`MANUAL-016`

## 背景

6AV 已固定管理兴趣五档分布的私有候选：两个相邻完整 ISO 周、
`previous/current × interest_level 0..4` 的十格 count-only 网格，以及期间整体的隐私隐藏。
既有渠道发布链以渠道维度和 16 格合同为前提，current-city 发布链也有自己的区域 target context 和
provenance。若把兴趣文档接入其中任一链路，报告形状、claim family 和审计边界就会被混在一起。

## 决定

6AW 复用通用不可变的受保护 snapshot storage，但为兴趣报告建立独立的 release attempt、request claim
family 和 provenance。兴趣 validator 与 pair comparison 固定 6AV 的 report、metric、dimension、统计单位、
period boundary、query fingerprint、privacy policy、source scope、两个期间和十格顺序。只接受符合
6AV 完整受保护文档合同的文档；私有 release 在固定事务内调用 6AV executor 生成候选；`displayed` 只允许安全整数 count，`suppressed` 必须是 JSON `null`。它不增加
中位数、比例、总计格或其他派生值。

私有 release 在数据库锁内重新验证 `release_management_reports`，由数据库派生可信项目报告时区 revision
和 `data_cutoff_utc`，再由 6AV executor 生成候选。调用方只提交 request、user、project 和固定 report identity；不能提交报告 JSON、
时区、截止点、期间、兴趣等级、
筛选或 SQL。首个合法文档建立唯一 baseline；后续成功发布只能推进 cutoff，保持报告定义、period definition／boundary、十格顺序和
时区 revision 一致，并链接前一 snapshot。相同 request 和固定上下文精确幂等，不新增 snapshot 或 attempt。

same／earlier cutoff、没有共享期间、共享期间内的兴趣格值或隐私状态变化，以及定义、period definition／boundary、网格、query fingerprint、
privacy policy、source scope 或时区 revision 漂移，均返回稳定的 blocked reason。blocked attempt 只保存最小
lineage evidence 和 reason，不保存候选文档、cells、来源、贡献者、隐藏前值或 PII。snapshot、attempt 和
request claim 均追加不可变，不允许 UPDATE 或 DELETE。

兴趣 release request UUID 和 channel、current-city request UUID 互斥；兴趣 provenance 也不能冒充它们的
provenance。release writer 之外，runtime、`PUBLIC`、普通 app role 和区域维护角色不能执行兴趣发布、读取
兴趣 provenance 或直接写兴趣 snapshot／attempt 表。通用 snapshot storage 对专用 release writer 启用
report-family RLS：current-city writer 只能访问自己的固定 report 与 lineage，兴趣 writer 也只能访问兴趣行；
表 owner 保留已有内部维护与受控读取路径。

## 后果与边界

独立 lineage 使十格兴趣合同不会绕过渠道 16 格合同或 current-city 区域合同；复用 snapshot storage 则避免
重复实现不可变文档基础设施。blocked attempt 的 value-free 约束降低失败路径泄露候选值的风险，但不构成形式化
不可重识别保证。

本决定只交付 DB-only 的 validator、snapshot、release lineage、幂等、并发和失败关闭合同。它不交付 HTTP、
runtime bridge、Flutter、Drift、缓存、离线、同步、目录、读取、导出、warehouse、retention、报告更正／取代、
生产调度、真人账号、真机或六平台运行时证据。完整 Docker、checksum、dump／restore 和 synthetic fixture 只证明
当前数据库合同与 ACL 边界。

## 验证

0062 migration、结构与权限 check、synthetic fixture 和并发脚本应覆盖：合法十格与所有固定身份字段；
unavailable、额外字段、错误固定 identity／metadata、缺失／重复／乱序网格；唯一 baseline、精确幂等、稳定滚动、
same／earlier cutoff、无共享期间、共享值／隐私变化和定义／期间／网格／时区 revision 漂移；期间整体隐藏、
跨报告相减反例、跨 family claim 冲突、snapshot／attempt／claim 不可改删、value-free blocked attempt、
最小 ACL、checksum、并发及 dump／restore。旧 channel、current-city 和 6AV 测试仍必须通过。
