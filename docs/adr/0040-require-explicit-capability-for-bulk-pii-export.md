# 批量导出推广对象资料需要独立能力

## 决定

批量导出推广对象姓名和联系方式必须同时具有 `export_target_pii` 与原查看能力。组织 owner 和项目管理员不自动获得导出能力。组织空间的 capability grant 及可见对象范围需要另行定义。

个人空间 v1 只向当前可信账号的 active personal workspace 开放。owner 上下文派生 `export_target_pii` 和 `view_assigned_target_pii`，Backend 与 PostgreSQL 每次重验 exact identity、owner、workspace 和 capability。导出只包含同一事务内仍分配给当前账号的 active 对象。当前项目确认可信上下文，不缩小 workspace-wide 范围。

每次导出只接受已验签 JWT `amr` 中 15 分钟内的 `password` 方法，并允许最多 60 秒时钟偏差。token `iat`、refresh、session restore 和其他 AMR 不证明近期重新输入凭据。Flutter 只把密码交给 Supabase Auth，重新登录后必须仍是同一 external subject。

导出文件使用固定 `personal_promotion_target_pii_export_v1` canonical JSON，保留 PII 原值和显式 `null`。v1 不使用 CSV，因为 quoting 不阻止 spreadsheet formula injection，加前缀又会改变电话等权威值。如果将来需要电子表格直接打开，另行定义 typed XLSX 合同。

每个已准备交付的文件都在同一数据库事务中追加独立不可变审计。文件的 `export_event_id` 等于审计 event ID，结果固定为 `prepared`。审计只保存 actor、workspace、合同、认证方法与时间和计数，不保存对象标识、PII、文件或字段 hash。审计证明服务端已准备交付，不证明客户端已保存或分享。

## 后果

导出失败不返回部分资料，每次网络重试产生新的导出事件。客户端只在内存中保留 artifact 到明确的系统交付动作，不写入 Drift、离线 PII vault、Outbox、普通缓存或日志。
