# ADR-0161：组织项目后续联系同意占比候选只返回已保护结果

- 状态：已接受
- 日期：2026-08-25
- Slice：6BP
- Issue：[#217](https://github.com/XavierOwen/tongxingzhe-app/issues/217)
- 关联：ADR-0123、ADR-0141、ADR-0160
- Requirement：`ANALYTICS-051`、`PRIVACY-043`、`TEST-045`、`MANUAL-035`

## 背景

ADR-0123 固定了 `follow_up_consent_ratio@1` 的统计语义：统计单位是当前有效的
contact-target link，分子是 `yes`，分母是 `yes + no`。`unknown` 不能被猜成主动选择，
`refused` 与 `not_applicable` 需要单独保留。

ADR-0160 只为组织项目保存当前 opt-in。它没有读取 contact-target link，也没有生成比例候选。
后续发布流程需要一份可以审查的候选，但不能因为生成候选而开放报告读取或保存未保护的精确值。

## 决定

6BP 在 `app_private` 中提供一个 private release-candidate 合同。合同使用专用 closed role，
只供未来的管理报告发布流程调用。调用方提供可信内部 `app_user_id`、显式项目、可信项目报告
时区和数据库拥有的截止时间。数据库在授权锁和项目锁后重新确认活动账号、组织／项目 membership、
项目状态、`release_management_reports` capability 和 6BO 当前 opt-in。调用方不能提交 workspace、
membership、capability provenance 或统计数据来替代数据库事实。

候选的固定身份是 `contact_target_follow_up_consent_ratio_two_periods@1`，指标是
`follow_up_consent_ratio@1`，统计单位是 `contact_target_link`。候选只使用两个相邻且已经结束的
完整 ISO 周，并使用项目报告时区和数据库截止时间。6BO 配置的记录时间不裁切统计期间。

候选集只包括目标组织项目中当前有效 contact revision 的 contact-target link。同一 contact 的多个
link 分别计数；贡献者是 contact 的可信 `app_user_id`。草稿、接触尝试、作废接触、旧 revision、
其他项目和截止时间之外的事实在候选集之前排除。问卷答案、触达人数和推广对象资料不能形成统计单位。

`yes` 是分子，`yes + no` 是分母。`unknown` 计入 unanswered，`refused` 和 `not_applicable`
作为独立 coverage cell，`unknown_count` 和 `excluded_count` 固定为零。

每个期间独立执行以下保护规则：

- `yes` 与 `no` 各自必须有至少 `10` 个统计单位、至少 `3` 位不同贡献者，且任一贡献者的单位数不得超过该类总数的一半；
- 只有 `yes` 和 `no` 两类都通过保护时，候选才返回 numerator、denominator 和按 half-up 计算的 basis points；任一类不安全时，ratio 状态为 `suppressed`，所有 ratio 数值为 `null`；
- unanswered、refused 和 not_applicable 各自独立执行同样的三项保护；隐藏 cell 的值为 `null`，候选不返回可用于从 ratio、coverage、期间或总数相减的 contact-target-link 总量。

未配置或当前停用时，合同在读取 contact-target link 之前返回 `not_enabled`，不返回报告、ratio 或
coverage。`not_enabled` 表示指标没有启用，不表示空样本、零比例、样本不足或授权错误。已启用但
某个值没有通过保护时返回 `suppressed`，它表示该值不能披露，不等于 `not_enabled`。两个期间
独立保护，候选不返回趋势或差值。

候选输出只包含固定报告定义、项目、期间、状态和已经保护的数值。它不包含 contact ID、target ID、
contributor ID、membership、capability provenance、地点、原始回答、隐藏前值或 PII。候选与
`release_management_reports` capability、6BO disable、membership revoke 和 project archive
使用固定锁顺序并在线性化点重新授权；先提交的失效状态不能产生旧的精确值。

## 后果与边界

未来发布流程可以把候选作为受保护输入继续审查。候选本身不表示报告已经发布，也不建立 snapshot 或
release lineage。`suppressed = null` 只表示服务端没有交付该值，不能解释为零。三项保护降低直接
披露和简单相减恢复的风险，不构成形式化不可重识别保证。

6BP 是 PostgreSQL DB-only 合同。它不增加 snapshot、release lineage、authorized read、runtime
bridge、HTTP、Backend、Flutter、Drift、UI、目录、导出、缓存、离线、同步、删除、retention、
warehouse 或真人平台证据。它不修改个人 0048／0049 合同，也不声称生产数据已经通过验证。

## 验证

实现必须增加 0074 migration、structural check、可回滚 synthetic fixture、disable／archive／revoke
并发脚本、restore role 准备、checksum 和 dump／restore 验证。fixture 必须覆盖 yes/no 的安全边界、
coverage 独立保护、两个期间独立隐藏、not_enabled 与 suppressed、候选集排除、value-free 输出、
授权撤回和归档的两种锁顺序。

完整数据库套件从仓库根目录运行：

```bash
./tool/run_postgres_tests_in_docker.sh
```

这些检查只证明 synthetic PostgreSQL 的 private candidate 合同、隐私门槛和 ACL。它们不能证明
报告发布、生产身份、真实数据或任何平台的运行时行为。
