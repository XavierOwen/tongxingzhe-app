# 可信报告发布绑定授权证据与时区 revision

状态：**已接受（2026-08-11）**。

关联：Slice 6J；ADR-0074、ADR-0099、ADR-0101、ADR-0102、ADR-0103；`AUTHZ-001`–`AUTHZ-006`、`ANALYTICS-007`–`ANALYTICS-014`、`PRIVACY-001`–`PRIVACY-011`。

可信管理报告发布 v2 只接收幂等请求 ID、内部用户、项目和固定报告 ID／版本。调用方不能提交 capability、时区、数据截止点、授权时间或授权 token。数据库依次取得组织／项目／发布能力锁、发布请求锁、项目报告时区锁和报告 lineage 锁。所有可能等待的锁取得后，数据库重新检查 `release_management_reports`，把这次检查的数据库时间同时作为授权参考时间和数据截止点，再选择当时有效的项目报告时区 revision。

授权关系 ID、能力 grant、参考时间、时区 revision、截止点和底层发布结果进入独立的不可变 v2 尝试记录。授权失败不写尝试或快照；lineage 检查失败只写类型化原因，不生成候选报告。通过检查后，v2 在同一事务中调用既有受保护快照发布函数。相同 v2 请求重试先重新授权，再返回首次最小结果；已被 v1 使用的请求 ID 不能补记为 v2 provenance。

报告 lineage 不因时区 revision 改变而重置。没有历史快照时可以建立基线；有历史时，最近快照必须具有 v2 provenance，且时区 revision 相同。旧 v1 快照、缺失 provenance、revision 变化和“改走后又改回同名 IANA 时区”都失败关闭。跨 revision 重新建立基线需要新的隐私判定，不能通过改变 lineage ID 绕过重叠报告保护。

本决定不开放 runtime、HTTP、Flutter、报告读取、生产授权管理或时区配置入口。v2 返回值只含报告身份、时区 revision、截止点、快照关联、结果状态和原因码，不含报告格、贡献者或授权关系 ID。
