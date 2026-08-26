# ADR-0162：后续联系同意占比快照使用独立发布 lineage

- 状态：已接受
- 日期：2026-08-25
- Slice：6BQ
- Issue：[#219](https://github.com/XavierOwen/tongxingzhe-app/issues/219)
- 关联：ADR-0123、ADR-0142、ADR-0160、ADR-0161
- Requirement：`ANALYTICS-052`、`PRIVACY-044`、`TEST-046`、`MANUAL-036`

## 背景

6BO 固定组织项目的当前 opt-in，6BP 生成已经过保护的
`contact_target_follow_up_consent_ratio_two_periods@1` private release-candidate。候选不是正式报告，也没有 snapshot identity、predecessor 或不可变发布历史。

既有渠道、current-city、interest 和 original-region 报告各有独立的 release provenance。复用其中一条 lineage 会混淆报告形状、request UUID family 和审计边界。6BP 候选也没有 `source_change_sequence`，而共享 snapshot storage 要求保存可信 source watermark。

## 决定

6BQ 复用通用不可变 snapshot storage，但建立后续联系同意占比专用的 closed release-writer role、release attempt、request-claim family、RLS policy 和 release lineage。发布事务从 `change_feed` 读取 source watermark；调用方不能提交 watermark、cutoff、时区、候选 JSON、统计值或授权 provenance。

固定 identity 是 `contact_target_follow_up_consent_ratio_two_periods@1`、`follow_up_consent_ratio@1`、统计单位 `contact_target_link`、dimension `consent_state`、period boundary `iso_week_monday_v1`、privacy policy `management_follow_up_consent_ratio_privacy_v1`、source scope `backend_accepted_active_contact_target_links_current_revision` 和 query fingerprint `management-report:contact_target_follow_up_consent_ratio_two_periods:v1`。

发布入口只接受 request UUID、可信内部 actor、显式 project 和固定 report identity。事务取得授权、request、项目时区和 lineage 锁后，重新确认活动账号、组织／项目 membership、项目状态、`release_management_reports` capability 和 6BO 当前 opt-in，再调用 6BP executor。每次可能等待后都重新授权。

validator 只接受 6BP 的 completed protected document。它固定 report／metric identity、统计单位、dimension、period boundary、privacy policy、query fingerprint 和 source scope。它也固定两个期间和字段 allowlist。

每个期间比较一个 ratio 和三个 coverage cell。`displayed` 只允许安全整数；`suppressed` 必须保存 JSON `null`。validator 不接受 contact、target、contributor、原始回答、隐藏前值、总量、趋势或差值。

首个 completed 候选建立唯一 `approved_baseline`。后续成功发布必须推进 cutoff，保持固定报告定义、期间定义、项目时区 revision、source scope 和 source watermark 单调，并链接当前 predecessor。相同 request 和 canonical context 精确幂等，不新增 snapshot 或 attempt。

`not_enabled` 不形成 snapshot，只能写入不含候选内容的最小 blocked attempt。same／earlier cutoff、无共享期间、共享 ratio／coverage 显示值或 privacy status 变化、定义／期间／时区 revision／source scope 漂移和 watermark 回退也返回稳定 blocked reason。blocked attempt 保存授权审计 provenance，但不保存 `protected_report`、period result、contact、target、contributor、原始回答、隐藏前值或来源 PII。

snapshot、attempt 和 request claim 追加不可变。专用 writer 只能访问固定 report 和 lineage；runtime、`PUBLIC`、普通 app role、候选 reader 和其他 report-family writer 不能执行发布或借道读写该 lineage。

## 后果与边界

后续读取切片可以引用一份明确且不可变的受保护报告，而不重新计算候选。独立 lineage 防止比例文档借用其他 report family 的 provenance。value-free blocked attempt 降低失败路径泄露风险，但不构成形式化不可重识别保证。

6BQ 是 PostgreSQL DB-only 发布合同。它不增加 authorized read、runtime bridge、HTTP、Backend、Flutter、Drift、UI、目录、导出、缓存、离线、同步、replacement、删除、retention、warehouse、调度、生产身份或真人平台证据。

## 验证

0075 migration、structural check、rollback fixture 和独立并发脚本覆盖 strict protected-document validator，以及 baseline、successor 和 predecessor。它们还覆盖 suppressed 安全发布、not-enabled 和其他 value-free blocked、精确幂等、跨 family claim、固定上下文漂移、不可改删、RLS、最小 ACL 和锁顺序。完整 Docker runner 另行验证 checksum 与 dump／restore。

这些 synthetic 检查只证明 private PostgreSQL 合同，不能证明 authorized read、生产数据、真实身份或六平台运行时。
