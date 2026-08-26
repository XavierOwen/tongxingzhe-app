# ADR-0163：授权后续联系同意占比快照读取使用独立 provenance

- 状态：已接受
- 日期：2026-08-25
- Slice：6BR
- Issue：#221
- Requirement：`ANALYTICS-053`、`PRIVACY-045`、`TEST-047`、`MANUAL-037`
- 相关决定：ADR-0160、ADR-0161、ADR-0162

## 背景

6BP 生成已保护的后续联系同意占比候选，6BQ 将合法候选固定到独立且不可变的 release lineage。现有渠道、current-city、interest 和 original-region reader 各自只信任自己的 request claim 与 release provenance，不能证明一份 snapshot 来自 6BQ。

## 决定

6BR 增加 private DB-only 的后续联系同意占比快照读取合同。调用方必须提交可信内部用户、显式 project 和 snapshot UUID。数据库在每次读取时重新确认 active user、组织成员、项目成员、active project 和 `view_anonymous_analytics`。发布授权、管理项目选择和数据库角色不能代替查看授权。

读取只接受 0075 `follow_up_consent_ratio_management_report_snapshot_release` claim family 中的 `approved_baseline`／`approved` attempt。
attempt、claim 和 snapshot 的 actor、project、report／version、query fingerprint 和 release lineage 必须完全对齐。
时区 revision、cutoff、previous／compared pointer 和 source change watermark 也必须对齐。
返回前再次执行 6BQ strict protected-document validator；读取不重算比例、不恢复隐藏值、不改写 snapshot，也不自动选择 latest。

`completed` 返回既有 protected report，`suppressed` ratio／coverage 仍为 JSON `null`。unknown 或 cross-project snapshot 统一返回 value-free `not_found`；同项目的 foreign family、legacy、blocked、缺失或漂移 provenance 返回 `untrusted_provenance`。两种失败均不返回正文。

每次已授权调用在同一事务追加 consent-ratio 专用、不可变、value-free 的访问审计。审计只保存最小授权链、snapshot identity、固定 report metadata 和结果状态，不保存 `protected_report`、period results、ratio、coverage、contact、target、contributor、原始回答、隐藏前值或 PII。未授权、撤权、过期、release-only、无有效项目成员或 inactive project 的调用失败关闭且不写审计。

读取和撤权复用 0030 的授权锁顺序。private function 与审计归共享 snapshot 的可信 owner；不新增 reader role，也不向 runtime、`PUBLIC`、普通 app role、release writer 或其他 report-family 角色开放读取或审计。

## 后果与边界

独立 provenance 防止共享 snapshot storage 造成 report-family 混淆，也保留 unknown／cross-project 与 same-project untrusted 的不同结果，而不泄露报告正文。代价是该 fixed report family 需要自己的窄 provenance query、validator replay 和 value-free audit，不能由客户端字段驱动一个通用 reader。

本决定不增加 runtime bridge、Backend HTTP、目录、Flutter、Drift、导出、缓存、离线、同步、replacement、删除、retention、warehouse、生产身份或六平台真人运行时证据。后续 runtime 入口必须另行提供 exact identity bridge，不能直接向 runtime 开放本 private function。

## 验证

0076 migration、structural check、rollback fixture 和独立 read／revoke 并发脚本应覆盖：

- 合法 baseline／successor、重复读取、完整 protected document、`suppressed = null` 和再次 6BQ validator；
- claim／attempt／snapshot、时区 revision、cutoff、previous pointer 和 source watermark 对齐；
- unknown／cross-project `not_found`，foreign／legacy／blocked／missing／drift provenance `untrusted_provenance`；
- active、撤权、过期、release-only、无成员、inactive project、value-free audit 和 UPDATE／DELETE 拒绝；
- 固定 owner、`SECURITY DEFINER`、search path、最小 ACL，以及 read-first／revoke-first 线性化；
- migration checksum、源库 dump／restore 和恢复库的 check／fixture 重跑。

这些 synthetic PostgreSQL 结果只证明已执行的 DB-only 合同；不能证明 runtime、HTTP、Flutter、目录、导出、生产身份、删除或真人平台运行时。
