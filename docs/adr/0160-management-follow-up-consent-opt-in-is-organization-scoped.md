# ADR-0160：组织项目的后续联系同意占比使用独立 opt-in 配置

- 状态：已接受
- 日期：2026-08-25
- Slice：6BO
- Issue：[#215](https://github.com/XavierOwen/tongxingzhe-app/issues/215)
- 关联：ADR-0077、ADR-0103、ADR-0123、ADR-0124、ADR-0125
- Requirement：`ANALYTICS-050`、`PRIVACY-042`、`TEST-044`、`MANUAL-034`

## 背景

0048 保存个人项目的 `follow_up_consent_ratio@1` opt-in。该表的授权主体是个人空间所有者，不能表达组织成员、项目成员和管理报告 capability。
组织项目需要单独保存 opt-in，才能避免把个人配置或导航上下文当成管理授权。

6BO 只固定配置生命周期。它不执行比例候选，不读取 contact-target link，不生成管理报告，也不开放 runtime、HTTP 或 Flutter 入口。

## 决定

组织项目的 configure 和 private read 使用可信内部 `app_user_id`，并在同一事务中重新解析：活动账号、组织 workspace、组织 membership、项目 membership、项目和
`release_management_reports` capability。`view_anonymous_analytics` 只允许读取受保护分析，不允许修改此配置。6BO 不新增 capability。

调用方只提供可信内部 `app_user_id`，不能自行提交 workspace、membership、capability grant、授权 provenance 或报告数据来替代数据库解析。配置表属于独立的 `app_private` 合同，不复用 0048 的个人配置表。

每个配置版本追加保存项目、固定 metric ID、`enabled`、预期版本、版本号、request UUID、操作者、完整 membership／capability provenance 和数据库记录时间。
历史版本不可 UPDATE 或 DELETE。未配置和当前停用均返回 `not_enabled`；当前启用返回 `enabled`。记录时间是审计时间，不是指标生效边界，也不裁切历史期间。

配置写入先取得授权 resolver 使用的组织／项目／capability 锁，再取得 request lock 和与项目 status 变更触发器共享的 project lock。每次可能等待后都重新授权。
项目归档与 configure 共享 project lock，因此 archive↔configure 线性化；0030 resolver 本身不替代该归档锁。相同 request UUID 与完全相同 payload 精确幂等，payload 漂移、过期版本和并发冲突失败关闭。

配置结果只返回 metric、项目、状态、版本和时间等 value-free metadata。它不返回比例、报告格、contact、推广对象、贡献者、地点或 PII。

## 后果与边界

该决定让组织项目的 opt-in 与个人配置、查看 capability、发布 lineage 和未来比例候选保持独立。未来若要执行组织比例候选，必须另行验证此配置、统计单位和管理隐私政策。

6BO 是 PostgreSQL DB-only 合同。它不证明比例数学、披露风险控制、报告生成、runtime、HTTP、Flutter、生产身份、删除、retention 或任何平台真人运行时。

## 验证

实现必须增加 migration、structural check、可回滚 synthetic fixture 和并发脚本。测试覆盖组织／项目／capability 授权、个人项目拒绝、启用／停用、版本、精确幂等、
payload 漂移、撤权锁顺序、直接 UPDATE／DELETE、value-free 输出、个人配置隔离、checksum 和 dump／restore。

完整数据库套件从仓库根目录运行：

```bash
./tool/run_postgres_tests_in_docker.sh
```

这些检查只证明 synthetic PostgreSQL 配置合同。它们不能证明未来比例候选或管理报告已经可用。
