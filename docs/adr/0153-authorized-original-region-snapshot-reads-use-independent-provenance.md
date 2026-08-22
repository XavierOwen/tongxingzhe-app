# ADR-0153：授权原始区域快照读取使用独立 provenance

- 状态：已接受
- 日期：2026-08-22
- Slice：6BH
- Issue：#201
- Requirement：`ANALYTICS-043`、`PRIVACY-035`、`TEST-037`、`MANUAL-027`
- 相关决定：ADR-0149、ADR-0152

## 背景

6BD 固定原始区域城市保护报告，6BG 把合法候选保存到原始区域专属的不可变 release lineage。通用渠道、current-city 和 interest
读取合同各自只信任自己的 request claim 与 release provenance，不能证明一份 original-region snapshot 属于 6BG，也不能复核它的
source tree tuple。

## 决定

6BH 增加 private DB-only 的原始区域快照读取合同。调用方必须提交可信内部用户、显式项目和 snapshot UUID。数据库在每次读取时重新确认
active user、组织成员、项目成员、项目状态和 `view_anonymous_analytics`，不能把发布授权、管理项目选择或数据库角色当作查看授权。

读取只接受 0068 `original_region_management_report_snapshot_release` claim family 中的 `approved_baseline`／`approved` attempt。attempt、claim
和 snapshot 的 project、report／version、query fingerprint、release lineage、时区 revision、cutoff、previous／compared pointer、source
change watermark 与 `source_tree_version + source_content_fingerprint` 必须完全对齐。返回前再次执行 6BD document validator；读取不重算、
不重新归类、不改写 snapshot，也不自动选择 latest。

`completed` 返回既有 protected report。unknown 或 cross-project snapshot 统一返回 value-free `not_found`；同项目的 foreign family、legacy、
blocked、缺失或漂移 provenance 返回 `untrusted_provenance`。两种失败都不返回正文。每次已授权尝试在同一事务追加原始区域专用、不可变、
value-free 的访问审计。审计只保存最小授权与 lineage metadata，不保存 `protected_report`、cells、隐藏前值、来源记录、contact、contributor、
区域名称、坐标或 PII；`untrusted_provenance` 审计中的 source tree tuple 和 watermark 固定为 `NULL`。

读取和撤权复用 0030 的授权锁顺序。未授权、撤权、过期、release-only、无有效项目成员或 inactive project 调用失败关闭且不写审计。
private function 与审计归共享 snapshot 的可信 owner；`PUBLIC`、runtime、普通 app role、0066 report reader、0068 release writer 和其他 report
family 角色都不能执行读取或直接访问审计。

## 后果与边界

独立 provenance 防止同一物理 snapshot storage 造成跨 report family 混淆，也让 unknown／cross-project 与 same-project untrusted 保持不同、
但都不泄露报告正文。代价是每个 fixed report family 需要自己的窄 validator、provenance query 和 value-free audit，不能用一张宽泛 reader
按客户端字段决定信任范围。

本决定不增加 runtime bridge、Backend HTTP、目录／latest、Flutter、Drift、导出、缓存、离线、同步、replacement、删除、retention、warehouse、
生产身份或六平台真人运行时证据。后续 runtime 入口必须另行提供 exact identity bridge，不能直接向 runtime 开放本 private function。

## 验证

0069 migration、structural check、rollback fixture 和独立 read／revoke 并发脚本应覆盖：

- 合法 baseline／successor、重复读取、完整 original city grid、`suppressed = null` 和再次 6BD validator；
- claim／attempt／snapshot、时区 revision、cutoff、previous pointer、source watermark 与 source tree tuple 对齐；
- unknown／cross-project `not_found`，foreign／legacy／blocked／missing／drift provenance `untrusted_provenance`；
- active、撤权、过期、release-only、无成员、inactive project、value-free audit 和 UPDATE／DELETE 拒绝；
- 固定 owner、`SECURITY DEFINER`、search path、最小 ACL，以及 read-first／revoke-first 线性化；
- migration checksum、源库 dump／restore 和恢复库的 migration／check／fixture 重跑。

这些 synthetic PostgreSQL 结果只能证明已执行的 DB-only 合同；不能证明 runtime、HTTP、Flutter、目录、导出、生产身份、删除或真人平台运行时。
