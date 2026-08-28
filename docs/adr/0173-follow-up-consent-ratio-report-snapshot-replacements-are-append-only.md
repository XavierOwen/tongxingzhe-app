# ADR-0173：后续联系同意占比报告快照更正版取代关系采用独立追加合同

- 状态：已接受
- 日期：2026-08-28
- Slice：6CE
- Issue：[#259](https://github.com/XavierOwen/tongxingzhe-app/issues/259)
- 关联：ADR-0160、ADR-0162、ADR-0172
- Requirement：`ANALYTICS-013`、`ANALYTICS-066`、`PRIVACY-057`、`TEST-060`、`MANUAL-050`

## 背景

0075 已把 6BP 生成的
`contact_target_follow_up_consent_ratio_two_periods@1` protected candidate 固定为不可变 snapshot。它保存自己的 request claim、approved attempt、报告时区 revision、期间、cutoff、previous pointer 和 source watermark。后续补录、接触修订或作废可能产生更晚的 approved snapshot，但旧 snapshot 不能被改写。

其他报告族已经有各自的 replacement provenance。follow-up consent ratio 必须继续使用 0075 的专用 provenance，不能复用 channel、interest、current-city 或 original-region replacement。6BO 只控制新候选是否生成；它不是既有 approved snapshot 更正关系的门禁。

## 决定

6CE 只登记两份已经通过 0075、结果为 `approved_baseline` 或 `approved` 的 consent-ratio snapshot 之间的直接 replacement。两份 snapshot 必须属于同一 project、report／version、query fingerprint、privacy policy、source scope、报告时区 revision、期间和 release lineage。新 snapshot 的 `data_cutoff_utc` 与发布时间必须晚于旧 snapshot，source change sequence 不得回退。

replacement 只能通过 0075 专用 provenance seam 核对 approved attempt，不能直接读取 attempt ledger。它不读取当前 6BO opt-in。停用 opt-in 后，既有 approved snapshot 仍可在满足 `release_management_reports`、membership、active project、项目状态和 provenance 条件时登记合格的更正关系。

replacement 使用共享的 value-free request UUID ledger 和独立 consent-ratio replacement family。replacement lineage lock 与 release lineage lock 分开。不同 request UUID 的普通 release 和 replacement 不互相串行；只有同一 UUID 的共享 request claim 互斥，先成功的合同使另一合同失败关闭。

登记原因只允许 `late_accepted_data`、`contact_revision` 和 `contact_void`。关系和最小 audit 追加不可变；每份旧 snapshot 最多一个直接 successor，每份新 snapshot 最多一个 predecessor。自链接、循环、分叉、stale head、跨 project、跨 family、same／earlier cutoff、时间倒序和 payload drift 失败关闭。

事务取得 request claim、replacement lineage 和授权锁后，必须再次确认 `release_management_reports`、membership、active project、项目状态、0075 provenance 和 protected-document validator。相同 request UUID 与相同 canonical payload 精确幂等，payload drift 不得复用旧结果。

生命周期只返回 snapshot ID、`active`／`superseded` 和直接 replacement ID。它不返回 ratio、coverage、hidden value、source、contributor、contact、授权关系或 PII。旧、新 snapshot 和既有 0075 release lineage 保持不变。

## 后果与边界

6CE 只增加同一 consent-ratio report version 内的更正链。它不生成或修改 snapshot，不改变 0074 candidate、0075 release、authorized read、runtime、Backend、HTTP、Flutter、目录、导出或缓存。它不实现分析定义或跨版本更正、删除、retention、warehouse、production identity 或真人平台验收。

6BO 停用只阻止新的候选或发布路径，不能撤销历史 approved snapshot 的 provenance。replacement 仍需要当前的发布 capability、membership、项目状态和锁后授权；它不把 6BO opt-in 当作统计结果或更正资格。

## 验证

0083 migration、structural check、rollback fixture 和独立并发脚本覆盖 0075 approved provenance、protected-document／snapshot binding、时区 revision、期间、cutoff、previous pointer 和 source watermark。

它们还覆盖原因 allowlist、active／superseded、精确幂等、payload drift、跨 project／family、倒序、自链接、stale head、分叉、循环、旧新 snapshot 字节不变、value-free lifecycle、锁后授权、竞争 replacement、replacement／revoke 两种锁顺序和 release／replacement request UUID 双向互斥。

structural check 确认 replacement lineage lock 与 release lineage lock 使用不同 namespace；并发脚本确认同一 UUID 的 claim 只能由一个合同占用。完整 Docker runner 另行验证 migration checksum 和独立 dump／restore；恢复库不重跑会提交 synthetic 行的并发脚本。

这些检查只证明 synthetic private PostgreSQL replacement contract、provenance、授权锁、不可变性、value-free 输出和 ACL。它们不证明 snapshot 生成、生产数据、部署身份、runtime、HTTP、Flutter、导出或真人平台运行时。
