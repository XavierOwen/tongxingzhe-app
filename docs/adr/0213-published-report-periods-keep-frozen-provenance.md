# ADR-0213：已发布报告沿用冻结的 UTC 周期

- 状态：已接受
- 日期：2026-11-16
- 范围：私有数据库修正；Issue [#672](https://github.com/XavierOwen/tongxingzhe-app/issues/672)
- Requirement：`ANALYTICS-001`、`ANALYTICS-004`、`TEST-197`、`MANUAL-186`
- 关联：[ADR-0101](./0101-management-weekly-reports-use-two-complete-iso-weeks.md)

在 PostgreSQL 16.14 正常发布的 Havana empty interest baseline，经真实 pg_dump／restore 到 16.16 后，详情从 completed 变为 untrusted_provenance，精确发布重放仍返回原回执。
原报告、回执和相关函数定义保持相同，没有联系人、回溯 first_submit 或伪造发布来源。
[tzdata 2026f](https://www.iana.org/time-zones/releases/2026f)改变了 Havana 的 2026 年末规则，三个周界从旧规则的 05Z 变为 04Z。
四类严格文档 validator 重新调用当前 resolver，因此会否定按原规则发布的 UTC 周期。

UTC periods 是已发布结果的一部分。完整文档与已保存 snapshot 逐值相同，且该 snapshot 具有本 family 的 approved、同值发布 provenance 时，校验沿用保存的 periods。
0164 只改变 current-city、interest、original-region 和 consent-ratio 四个 validator 的 periods 来源：先查自己的已冻结 snapshot／attempt，否则调用原 resolver。
查询匹配完整 protected_report、request、creator、project、report/version/fingerprint、lineage、时区、cutoff、previous snapshot 和各 family 的 source context。
文档 cutoff 只序列化到毫秒，查找使用该毫秒内的原 metadata 时间窗口，并保留 metadata 的微秒精度。
各函数 owner 只读取本来可读的 snapshot 和本 family ledger，不新增 helper、表、grant 或跨 family 权限。

其他文档形状、UUID、指标、隐私、source、版本、UTC 格式、时间次序等校验保留。
只匹配 periods 的文档、修改过的文档，以及缺少本 family approved 来源的文档，都不能借用冻结来源。
尚未发布的新文档仍按当前规则校验。reader 的当前身份／项目资格、claim、时区版本和其他 source proof 继续执行，冻结文档不是独立读取资格。

迁移不改 resolver、producer、release／read 接口、旧快照、回执或时区版本，只改四个原函数的 prosrc，保留 OID、owner、ACL 和其他属性。
新报告仍使用当前时区规则。旧新 UTC 周期不再对齐时，后续 lineage 比较沿用原失败关闭政策，不自动重设 baseline。
周一回拨的新计算版本属于独立的 [Issue #670](https://github.com/XavierOwen/tongxingzhe-app/issues/670)，不混入本次历史可读性修正。

TEST-197／MANUAL-186 以固定官方 PostgreSQL 16.14 镜像建立真实 0163、正常 empty 发布和旧读取，经实际 dump／restore 后由正式 runner 升级。
真实升级前后保留全部业务行及旧函数 catalog，只允许四个 validator body 按预期变化；原报告和回执逐值相同，读取只增加规定的 access audit，重放不新增发布事实。
fresh 回归另在同一回滚事务内对 resolver 注入明确错误，证明精确冻结文档无需重算，而未冻结文档仍走当前校验；该单元注入不作为真实升级 RED 的证据。
既有四 family fixtures、checksum、完整 Docker、独立恢复和固定提交 CI 分别验收，不把其中一项扩大为其他层已通过。
不开放生产、runtime、Backend、HTTP、UI 或通知入口。
