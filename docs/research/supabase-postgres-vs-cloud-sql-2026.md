# Supabase PostgreSQL 与 Google Cloud SQL for PostgreSQL 比较

- 研究日期：2026-07-31
- 适用项目：同行者 App
- 资料范围：只使用 Supabase、Google Cloud 与 PostgreSQL 官方资料
- 决策状态：用户已确认首阶段采用 Supabase PostgreSQL；见 [ADR-0097](../adr/0097-use-supabase-postgresql-for-the-initial-stage.md)

## 1. 结论先行

两者都是真正的 PostgreSQL，都能使用表、约束、事务、索引、JOIN、CTE、窗口函数、RLS、`pg_dump` 和版本化 `.sql` migration。它们不会改变 Flutter 客户端的 Drift／SQLite、`sync_outbox` 或离线优先设计。

真正的差别是托管边界：

- **Supabase PostgreSQL** 是 Supabase Backend-as-a-Service 的核心数据库，与 Supabase Auth、Data API、Realtime、本地 CLI 和 Dashboard 放在一个产品中。它的早期成本低、开发体验一体化，特别适合快速原型和 SQL 学习。
- **Cloud SQL for PostgreSQL** 是更聚焦的托管数据库服务，与 Cloud Run、IAM、VPC、Cloud Logging、Cloud Monitoring、备份、区域 HA 和跨区域 DR 紧密集成。它不替 App 生成业务 API，但更适合“自有 Cloud Run Backend API 是长期安全边界”的架构。

### 针对当前阶段的建议

当前 App 没有用户、没有不可丢失的真实数据，眼前目标是完成第一条正式垂直切片、学习 Flutter／SQL、验证 Supabase Auth 六平台接线，同时把基础设施成本保持在可控范围。**因此已确认当前阶段采用同一 Supabase project 中的 PostgreSQL 作为业务数据库。**这不是另造教学 Demo：仍然使用同一套正式代码、自有 Backend API、版本化 SQL migration、Drift／Outbox 和正式领域模型。

选择它的当前阶段理由是：

1. Auth、PostgreSQL、本地 CLI、测试邮件和 migration 在一个可复现环境中；
2. Pro 的最低生产候选约 $25/月，而 Supabase Pro＋Cloud SQL 至少是两套账单；
3. 当前没有真实数据，若验证发现跨云连接或运行保障不合适，迁移成本仍最低；
4. 业务 schema 只用标准 PostgreSQL，Backend 继续通过 `(issuer, subject)` 映射 `app_user_id`，不会把核心领域绑死在 `auth.users` 或 `auth.uid()`。

但这是一项**带生产复审门槛的当前阶段选择**。如果 Backend 最终长期固定在 Google Cloud Run，并出现私网、HA、SLA、PITR、跨云延迟或统一监控要求，则在第一批不可丢失真实数据产生前切换到 Cloud SQL。**只把数据库放在 Supabase、Backend 长期留在 Cloud Run，是可行但折中的组合：普通 Pro 会形成跨云公网 TLS 数据库连接。**

## 2. 一眼看懂的差异

| 判断项 | Supabase PostgreSQL | Cloud SQL for PostgreSQL | 对同行者的意义 |
| --- | --- | --- | --- |
| 产品定位 | PostgreSQL＋Auth＋Data API＋Realtime＋Functions 的一体化平台 | 聚焦数据库基础设施的托管 PostgreSQL | App 已决定保留自有 API，因此不一定需要 Supabase Data API |
| Flutter 是否直连 | 技术上可以经 Data API＋RLS，但本项目不应这么做 | 不应直连 | 两者都应走 Backend API |
| 与自有 API | 标准连接串；跨云时需处理公网 TLS、IP、pooler | Cloud Run 有官方连接器、Unix socket、IAM 与 VPC 路径 | Cloud SQL 更自然 |
| Auth 集成 | 同项目有 `auth` schema 和 `auth.uid()` | Backend 验证 Supabase JWT，再映射内部用户 | 本项目应保持 provider-neutral，不直接绑 `auth.users` |
| RLS | Supabase Auth＋Data API 的一等能力 | 原生 PostgreSQL RLS | 本项目由 Backend 授权，RLS只作额外防线 |
| 离线 Drift／Outbox | 完全兼容 | 完全兼容 | 无差别 |
| SQL 可见性 | SQL Editor、CLI、migration、psql | Cloud SQL Studio、psql、自有 migration job | 都满足学习要求 |
| 可移植性 | 核心是标准 PG；使用 `auth.uid()`、PostgREST 等会增加锁定 | 核心是标准 PG；IAM、连接器属于外围锁定 | 核心 schema 均可保持可移植 |
| 本地开发 | Supabase CLI 可启动 Auth＋Postgres＋Mailpit 等完整栈 | 通常使用本地 PostgreSQL 容器；另接 Supabase Auth 测试环境 | Supabase 本地体验更省事 |
| 自动备份 | Free 无；Pro 每日且保留 7 天 | 标准备份可配置 1–365 天 | Cloud SQL 更可配置 |
| PITR | 7 天约 $100/月，且至少 Small compute | Enterprise 版日志保留 1–7 天；按使用量计存储 | Cloud SQL 早期成本更低 |
| 区域 HA | 官方 Pro 资料没有等价的自动多可用区写入故障切换承诺 | 区域 HA：跨两个 zone 同步复制并自动切换 | Cloud SQL 更成熟、边界更明确 |
| uptime SLA | 只有 Enterprise 列出 uptime SLA | Enterprise HA 99.95%；Enterprise Plus HA 99.99% | 正式可用性要求偏向 Cloud SQL |
| 读副本／异地 | 异步只读副本；Auth 仍走 primary | 区域／跨区域只读副本，跨区域可用于 DR | 两者都不能把异步副本等同零数据丢失 |
| 网络安全 | SSL enforcement、CIDR；PrivateLink 只对 Team／Enterprise 且要求 AWS VPC | Cloud SQL Connector／Auth Proxy、IAM、私有 IP、VPC | Cloud Run＋Cloud SQL 更少跨云暴露面 |
| 监控 | Dashboard、Reports、Logs；Pro 7 天日志，外送日志另收费 | Cloud Monitoring、Logging、System Insights、Query Insights、告警 | Cloud SQL 更适合统一运维 |
| 最低早期成本 | Free $0；生产候选 Pro $25/月 | 无长期免费层；shared-core＋10 GiB SSD 约 $9.37/月 | 但 Supabase Auth 生产本来仍可能需要 Pro |
| 正式 HA 成本 | 没有可直接对齐的 Pro HA 规格；PITR／副本另付 | 最小 dedicated HA 粗算约 $102/月 | Supabase 更便宜，Cloud SQL 高可靠合同更明确 |

## 3. 产品责任边界

### 3.1 Supabase

Supabase 官方说明每个项目都有完整的专用 PostgreSQL，而不是某种只能通过 SDK 使用的数据库抽象。Auth、Storage、Realtime 与 Data API 都建立在这个 PostgreSQL 之上。[Supabase Database overview](https://supabase.com/docs/guides/database/overview)

Supabase 负责基础设施、操作系统、数据库服务、平台监控，并在相应付费计划中负责备份。项目方仍必须负责：

- 应用架构和业务实现；
- 数据与 schema 的正确性；
- 账户、数据库、表和 API key 的访问控制；
- RLS 与安全策略；
- SQL、索引、连接、容量和性能；
- migration 和生产变更流程。

官方特别指出，“一个设计不好的数据库，无论托管在哪里都会运行不良”。[Supabase Shared Responsibility Model](https://supabase.com/docs/guides/deployment/shared-responsibility-model)

### 3.2 Cloud SQL

Google 负责底层硬件、固件、kernel、OS、存储、网络、数据库软件和补丁，默认进行静态加密，并提供监控、HA、备份与 DR 能力。客户仍负责选择版本、区域、规格和 flags，设计 schema，管理用户与权限，配置连接、HA／DR、容量和 SQL 性能。[Cloud SQL Shared responsibility](https://docs.cloud.google.com/sql/docs/shared-responsibility)

所以 Cloud SQL 不是“需要自己维护 PostgreSQL 服务器”；它只是不会把 Auth、移动 SDK 和自动 Data API 与数据库绑成一个产品。

## 4. Flutter、Drift 和 Outbox 不受数据库托管商影响

本项目的正确数据路径在两种选择下都一样：

```text
Flutter
  → Drift / SQLite
  → 本地事务写 contact + revision + answers + sync_outbox
  → HTTPS Backend API
  → PostgreSQL 服务端事务
```

因此：

- 离线新增、重试、幂等、冲突副本和 cursor pull 都不依赖 Supabase 或 Google SDK；
- Flutter 不持有 PostgreSQL 密码；
- 未来更换数据库托管商时，Flutter 协议不必跟着变化；
- 服务端仍在一个 PostgreSQL transaction 中写入业务事实、revision、audit、change feed 与 `warehouse_outbox`。

这也是“测试接缝”的具体价值：数据库连接藏在 Backend adapter 后面，业务规则和 Flutter UI 不认识托管商类型。

## 5. 自有 Backend API 与数据库连接

### 5.1 Supabase PostgreSQL

Supabase 提供四类常见连接：

- direct connection：适合 migration、`pg_dump` 和长驻 Backend；默认直接端点使用 IPv6；
- Supavisor session mode：适合需要 IPv4 的持久 Backend；
- Supavisor transaction mode：适合 serverless／短连接流量；
- paid project 的 dedicated pooler：适合较高性能的 transaction pooling。

transaction mode **不支持 prepared statements**。如果 Cloud Run Backend 使用它，Node PostgreSQL driver 必须禁用命名 prepared statement；“查询 SQL 文件有名字”不等于使用 PostgreSQL server-side prepared statement，两者应区分。[Supabase connection methods](https://supabase.com/docs/guides/database/connecting-to-postgres)

Supabase 项目当前部署在 AWS 区域。若 Backend 继续在 Google Cloud Run：

1. 普通 Pro 方案会通过公网 TLS 连接 Supabase；
2. 可启用 SSL enforcement，并应使用 `verify-full` 验证 CA 和 hostname；
3. 可用 CIDR network restrictions，但 Cloud Run 若要稳定 allowlist，通常还要配置固定出口 IP；
4. Supabase PrivateLink 只对 Team／Enterprise 开放，并要求同区域 AWS VPC，不能直接把 GCP Cloud Run 变成 AWS 私网客户端。

来源：[SSL enforcement](https://supabase.com/docs/guides/platform/ssl-enforcement)、[Network restrictions](https://supabase.com/docs/guides/platform/network-restrictions)、[PrivateLink](https://supabase.com/docs/guides/platform/privatelink)

这条跨云路径并非不可用，但需要把额外延迟、出口流量、DNS／pooler、固定 IP 和两个云的故障面纳入运行设计。

### 5.2 Cloud SQL

Cloud Run 对 Cloud SQL 有官方连接路径：

- Cloud SQL Connector 或内置 Auth Proxy；
- Unix domain socket；
- private IP＋Direct VPC egress；
- Cloud Run service account 的 `roles/cloudsql.client`；
- 可选 automatic IAM database authentication；
- 连接自动加密，数据库密码可放 Secret Manager，或改用短期 IAM token。

来源：[Connect from Cloud Run](https://docs.cloud.google.com/sql/docs/postgres/connect-run)、[IAM database authentication](https://docs.cloud.google.com/sql/docs/postgres/iam-authentication)、[Private IP](https://docs.cloud.google.com/sql/docs/postgres/private-ip)

Cloud Run 的每个实例最多可以建立 100 条 Cloud SQL 连接；实例扩容会放大总连接数。因此无论选择哪一家，都要使用小连接池、限制每实例连接数，并为 Cloud Run 设置合理的最大实例数。[Cloud Run to Cloud SQL connection limits](https://docs.cloud.google.com/sql/docs/postgres/connect-run)

Cloud SQL 的 Managed Connection Pooling 目前要求 Enterprise Plus；早期使用普通应用内连接池即可。[Managed Connection Pooling](https://docs.cloud.google.com/sql/docs/postgres/managed-connection-pooling)

## 6. Supabase Auth、内部用户与 RLS

### 6.1 Supabase 数据库的一体化能力

Supabase Auth 把用户数据放在同一数据库的 `auth` schema 中。通过 Data API 访问时，SDK 自动携带 JWT，policy 可以使用 `auth.uid()` 和 `auth.jwt()`。[Auth architecture](https://supabase.com/docs/guides/auth/architecture)、[Securing data](https://supabase.com/docs/guides/database/secure-data)

这对“Flutter 直接调用 Supabase Data API”的产品很有吸引力，但同行者已经选择更严格的边界：Flutter 只调用自有 Backend API。因此不建议让核心业务 schema 直接引用 `auth.users`，也不建议把所有权限逻辑写死为 `auth.uid()`。

无论业务 PostgreSQL 托管在哪里，都保持：

```text
(auth_issuer, auth_subject) → app_user_id
```

这样 Supabase Auth 验证失败而切换 Cognito 时，业务主键、审计记录和成员关系不需要整体重写。

### 6.2 两边都有 PostgreSQL RLS

RLS 是 PostgreSQL 原生功能，不是 Supabase 私有功能。启用 RLS 后，普通角色对每行的 `SELECT`／`INSERT`／`UPDATE`／`DELETE` 必须通过 policy；若没有 policy，默认拒绝。表 owner、superuser 和 `BYPASSRLS` 角色可能绕过它。[PostgreSQL Row Security Policies](https://www.postgresql.org/docs/current/ddl-rowsecurity.html)

因此：

- Supabase 的优势是 JWT helper 和 Data API 自动注入上下文；
- Cloud SQL 也可以使用 RLS，但需要 Backend 在事务内安全设置用户／tenant context，或使用不同数据库角色；
- Supabase `service_role` 会绕过 RLS；Backend 若总用 service role，RLS 就不能替代业务授权；
- 本项目应以 Backend 的 capability 检查与带 scope 的 SQL 为主，RLS 只作为 defense-in-depth；
- 两边都应建立权限受限的 runtime role，migration／管理 role 与运行时 role 分离。

## 7. SQL 可见性、学习价值与 migration

两者都能完整学习 PostgreSQL 与 SQL。

### Supabase

- Dashboard SQL Editor 与 Table Editor；
- `psql`、DBeaver 和标准连接串；
- `supabase/migrations/*.sql`；
- `supabase db reset` 从 migration＋seed 重建；
- 本地 CLI 同时运行 PostgreSQL、Auth、Mailpit 等服务；
- `db diff` 可以从本地变更生成可审阅 SQL。

Supabase 官方警告：一旦采用 migration，生产 schema 不应再直接从 Dashboard 修改，否则会产生 schema drift；所有远端变更应先形成版本化 migration。[Database migrations](https://supabase.com/docs/guides/deployment/database-migrations)、[Local development workflow](https://supabase.com/docs/guides/local-development/cli-workflows)

### Cloud SQL

- Cloud SQL Studio 可以在 Google Cloud Console 中运行 SQL；
- `psql` 与普通 PostgreSQL driver；
- 项目自有的有序 `.sql` migrations；
- migration 由一次性受控 Cloud Run Job／CI job 执行；
- Query Insights 与 execution plan 辅助理解慢 SQL。

来源：[Cloud SQL Studio](https://docs.cloud.google.com/sql/docs/postgres/manage-data-using-studio)、[Query Insights](https://docs.cloud.google.com/sql/docs/postgres/using-query-insights)

所以“选择 Cloud SQL 会失去 SQL 学习机会”是错误的。Supabase 的优势是学习环境更集成，而不是 SQL 更真实。

## 8. 迁移、可移植性与扩展

### 8.1 共同基础

只要核心业务采用：

- 标准 PostgreSQL 类型和约束；
- 普通 function／trigger／view；
- 两家都支持的扩展；
- 有序 `.sql` migrations；
- `pg_dump`／`pg_restore` 可验证备份；
- 连接与 Auth helper 隔离在 adapter；

那么 Supabase 与 Cloud SQL 之间可通过标准 PostgreSQL 工具迁移。

### 8.2 不能假装“零锁定”

Supabase 托管实例没有真正 superuser；`auth`、`storage`、Realtime、PostgREST grants、`auth.uid()`、`pg_net` 和平台管理 schema 都会增加迁移成本。[Supabase unsupported superuser operations](https://supabase.com/docs/guides/database/postgres/roles-superuser)、[Supabase extensions](https://supabase.com/docs/guides/database/extensions)

Cloud SQL 同样没有真正 PostgreSQL superuser；不能运行任意自定义 background worker，只能安装官方支持的扩展，部分 flags 不开放。[Cloud SQL features and restrictions](https://docs.cloud.google.com/sql/docs/postgres/features)、[Cloud SQL extensions](https://docs.cloud.google.com/sql/docs/postgres/extensions)

项目需要 PostGIS 处理区域／地点时，两边都提供官方支持，但仍应把扩展版本列入 migration 验证矩阵。

## 9. 备份、PITR、HA、区域与 DR

### 9.1 Supabase

截至研究日期：

- Free 不包含自动备份，闲置一周会暂停；
- Pro 每日备份，保留 7 天；
- Team 每日备份，保留 14 天；
- PITR 是独立 add-on，7／14／28 天分别约 $100／$200／$400 每月；
- PITR 至少要求 Small compute；
- restore 期间项目不可访问；
- 删除项目会永久删除关联数据与备份，因此仍应保留独立 `pg_dump`／离站备份演练。

来源：[Supabase backups](https://supabase.com/docs/guides/platform/backups)、[Supabase pricing](https://supabase.com/pricing)

每个项目有一个 primary region。当前指定区域基于 AWS，包括 Ohio、North Virginia 等；官方列表没有 Iowa／Chicago 区域。[Supabase regions](https://supabase.com/docs/guides/platform/regions)

Supabase Read Replica：

- 是异步、只读副本，存在 replication lag；
- 至少要求 Pro、Small compute、PostgreSQL 15；
- Auth 请求仍由 primary 处理；
- 官方材料没有把它描述成 Pro 方案下的自动 writable failover；
- 因此不能把“有读副本”写成“已经具备区域 HA”。

来源：[Supabase Read Replicas](https://supabase.com/docs/guides/platform/read-replicas)、[Getting started with Read Replicas](https://supabase.com/docs/guides/platform/read-replicas/getting-started)

Supabase 定价表只为 Enterprise 列出 uptime SLA，Free、Pro、Team 都未包含 uptime SLA。[Supabase plan comparison](https://supabase.com/pricing)

### 9.2 Cloud SQL

Cloud SQL standard backup：

- 自动备份可保留 1–365 天；
- Enterprise 默认 7 天，Enterprise Plus 默认 15 天；
- on-demand backup 可保留到手动删除；
- 可设置备份地点，默认可以落在邻近 multi-region；
- Enhanced Backup 支持更长保留、独立 backup project 和 retention lock，但属于更高级需求。

Cloud SQL PITR：

- Enterprise 可保留 1–7 天 transaction logs，默认 7 天；
- Enterprise Plus 可保留 1–35 天，默认 14 天；
- 可从 live、unavailable 或 deleted instance 恢复到新实例；
- 费用主要随使用的备份／日志存储增长，而不是固定 $100 add-on。

来源：[Cloud SQL backup options](https://docs.cloud.google.com/sql/docs/postgres/backup-recovery/backup-options)、[Configure PITR](https://docs.cloud.google.com/sql/docs/postgres/backup-recovery/configure-pitr)

Cloud SQL 区域 HA 在同一 region 的两个 zone 之间同步复制，事务在两边持久化后才报告 commit；primary／zone 故障后自动切换，官方提示典型不可用时间约 60 秒。HA 成本约为 standalone 的两倍。[Cloud SQL high availability](https://docs.cloud.google.com/sql/docs/postgres/high-availability)

SLA：

- Enterprise edition＋HA：99.95%；
- Enterprise Plus＋HA：99.99%；
- shared-core、single-zone 和单节点 read pool 不在 SLA 内。

来源：[Cloud SQL SLA](https://cloud.google.com/sql/sla)

Cloud SQL 还可以创建跨区域异步 read replica，用于区域迁移或 DR；由于复制是异步的，区域灾难时仍可能丢失尚未复制的最近事务，不能宣称 RPO 为零。[Cross-region replicas](https://docs.cloud.google.com/sql/docs/postgres/replication/cross-region-replicas)

Cloud SQL 提供 `us-central1`（Iowa）；如果第一批用户主要在 Chicago／美国中西部，Iowa 在地理上通常比 Supabase 当前的 Ohio／Virginia 更接近，但最终应以真实端到端延迟测试为准。[Cloud SQL regions](https://docs.cloud.google.com/sql/docs/postgres/region-availability-overview)

## 10. 监控和运行诊断

### Supabase

- Dashboard Database Reports、Log Explorer、Query Performance；
- `pg_stat_statements`；
- Pro 7 天 API／database log retention；
- Pro 有 metrics endpoint；
- Log Drain 另收每条 drain 每月 $60，加事件和流量费；
- 平台 audit logs 从 Team 开始。

来源：[Supabase pricing](https://supabase.com/pricing)、[Supabase Postgres logs](https://supabase.com/docs/guides/troubleshooting/how-to-interpret-and-explore-the-postgres-logs-OuCIOj)

### Cloud SQL

- Cloud Monitoring 指标与告警；
- Cloud Logging 与 audit logging；
- System Insights 显示 CPU、内存、磁盘、连接、吞吐和事件；
- Query Insights 可按应用、route、user／host 等维度追踪慢查询；
- Recommender 提供 sizing／idle 建议。

来源：[System Insights](https://docs.cloud.google.com/sql/docs/postgres/use-system-insights)、[Query Insights](https://docs.cloud.google.com/sql/docs/postgres/using-query-insights)、[Shared responsibility](https://docs.cloud.google.com/sql/docs/shared-responsibility)

若 Backend 已运行在 Cloud Run，Cloud SQL 的 API、应用日志、trace 和数据库指标可以留在同一个 GCP observability 体系中。

## 11. 截至 2026-07-31 的成本快照

以下是公开 list price 的粗算，不是最终报价；未含税、Cloud Run、Secret Manager、SMTP、网络出口、监控超额、未来 warehouse 和人工运维。统一用每月 730 小时计算。

### 11.1 Supabase

| 场景 | 约月费 | 主要包含／缺少 |
| --- | ---: | --- |
| 本地开发 | $0 | Supabase CLI 本地栈，不可暴露为生产服务 |
| Free cloud demo | $0 | 500 MB、shared CPU、无自动备份、闲置会暂停 |
| Pro＋Micro | $25 | $25 plan 含 $10 compute credit，8 GB disk、7 天每日备份、7 天 logs、无 uptime SLA |
| Pro＋Small | $30 | $25＋$15 compute－$10 credit；2 GB RAM |
| Pro＋Small＋7 天 PITR | 约 $130 | 上项＋$100 PITR |
| dedicated IPv4 | 另加约 $4 | 每个 primary／replica 分别计费 |

官方价格：[Supabase pricing](https://supabase.com/pricing)、[IPv4 usage](https://supabase.com/docs/guides/platform/manage-your-usage/ipv4)

### 11.2 Cloud SQL（Iowa `us-central1`，Enterprise edition）

官方公开单价：

- `db-f1-micro`：$0.0105／小时；
- dedicated：$0.0413／vCPU-hour＋$0.007／GiB-memory-hour；
- standalone SSD：约 $0.000232877／GiB-hour；
- HA CPU、memory 和 storage 约为 standalone 的两倍；
- backup used：约 $0.000109589／GiB-hour；
- data disk 最低 10 GiB；
- 没有长期免费层，新客户只有一次性的 $300 credits。

来源：[Cloud SQL pricing](https://cloud.google.com/sql/pricing)、[Cloud SQL instance API minimum disk](https://docs.cloud.google.com/sql/docs/postgres/admin-api/rest/v1/instances)、[Cloud SQL instance settings](https://docs.cloud.google.com/sql/docs/postgres/instance-settings)

| 场景 | 计算 | 约月费 |
| --- | --- | ---: |
| shared-core dev／staging | `0.0105×730 + 10×0.000232877×730` | $9.37＋backup／network |
| 最小 dedicated standalone | `(1×0.0413 + 3.75×0.007)×730 + 10 GiB SSD` | $51.01＋backup／network |
| 最小 dedicated HA | 上项 CPU／memory／storage 约双倍 | $102.02＋backup／network |

shared-core 很便宜，但官方明确排除在 SLA 之外，不应把它写成正式高可用生产配置。

### 11.3 整体账单，而不只看数据库

正式 Supabase Auth 若使用 Pro，再加 Cloud SQL：

- 低成本 staging：约 `$25 + $9.37 = $34.37/月`，另加 Cloud Run 等；
- 最小 dedicated standalone：约 `$25 + $51.01 = $76.01/月`；
- 最小 dedicated HA：约 `$25 + $102.02 = $127.02/月`。

若 Auth 和业务数据库都使用同一个 Supabase Pro project，最低生产候选为约 $25/月。因此 Supabase 的成本优势是真实的；Cloud SQL 多付的钱主要换取同云连接、IAM／VPC、可配置备份、PITR、明确 HA 和 SLA 路径，而不是换取“更真实的 SQL”。

## 12. 未来去标识化分析仓库

两种数据库都能提供 logical replication／CDC，但**原始 CDC 不会自动满足隐私要求**。

Supabase Pipelines 截至研究日期仍是 Public Alpha，当前正式 managed destination 是 BigQuery；Snowflake、ClickHouse 和 DuckLake 仍为 early access，而且 Pipelines 不支持用户自定义转换。[Supabase database replication](https://supabase.com/docs/guides/database/replication)、[Supabase Pipelines](https://supabase.com/docs/guides/database/replication/pipelines)

Google Datastream 可以从 PostgreSQL／Cloud SQL 持续复制到 BigQuery 或 Cloud Storage，但它同样只是 CDC 工具，不会理解同行者的匿名阈值、精细位置限制或管理分析规则。[Google Datastream](https://docs.cloud.google.com/datastream/docs)

因此两种方案都保留相同出口：

```text
业务 transaction
  → warehouse_outbox（只含已经去标识化、版本化的分析事实）
  → 独立 exporter / worker
  → 未来 Snowflake-like warehouse
```

初期不要把 `auth.users`、原始 contact、精细 GPS、备注或潜在 PII 整库复制到 warehouse。以后即使采用 CDC，也只发布去标识化 outbox／analytics schema，并用 synthetic fixtures 在 SQLite、PostgreSQL 和 warehouse 三层对账。

## 13. 当前阶段的实施边界

采用 Supabase PostgreSQL 不改变已经确认的安全与可替换原则：

1. Supabase Auth 只提供 issuer／subject／token；
2. Backend 以 `(issuer, subject)` 映射 `app_user_id`，核心业务表不直接依赖 `auth.users`；
3. Flutter 只调用自有 HTTPS API，不使用 Supabase Data API 直接读写业务表；
4. Backend 使用权限受限的专用数据库角色，不在普通业务流量中使用可绕过 RLS 的 `service_role`；
5. migration 是仓库内唯一 schema source of truth；
6. 核心 SQL 只用标准 PostgreSQL 和两边共有扩展；
7. `sync_outbox` 与 `warehouse_outbox` 都是应用自己定义的稳定合同；
8. Pro 正式试运行前启用 SSL enforcement、`verify-full`、网络限制和独立备份演练；
9. transaction pooler 路径必须测试连接上限、重连、token／secret rotation，并禁用不兼容的 prepared statements；
10. 在产生第一批不可丢失真实数据前完成一次 `pg_dump` 到 stock PostgreSQL／Cloud SQL staging 的恢复演练。

## 14. 切换到 Cloud SQL 的明确触发条件

当前选择 Supabase PostgreSQL 不等于承诺永远不迁移。出现以下任一条件，就重新打开数据库 ADR；出现第 1–4 项时，默认切换 Cloud SQL：

1. **Cloud Run 被确认是长期 Backend 运行位置**，并且不愿长期承担跨云公网数据库连接；
2. 正式合同需要可核验的 99.95%／99.99% uptime SLA；
3. 需要区域级自动写入故障切换，而不是异步只读副本；
4. 需要 GCP private IP／IAM database authentication／统一 VPC 安全边界；
5. 需要 7 天 PITR，但 Supabase 的约 $100/月 add-on 使总成本高于合适的 Cloud SQL 规格；
6. 跨云延迟、断连或出口流量的实测超过发布预算；
7. Cloud Monitoring／Logging／Trace 与数据库统一告警成为运维硬要求；
8. Supabase 特有 extension、Data API 或 RLS helper 开始渗入核心 schema，使可移植性检查失败。

切换不应等到系统变慢或发生事故以后才准备。当前阶段就保留 Cloud SQL 可恢复性测试；一旦触发条件成立，使用普通 PostgreSQL migration 与 `pg_dump`／restore 在正式数据规模仍小的时候完成迁移。

推荐确认文本：

> 当前阶段业务 PostgreSQL 与 Supabase Auth 使用同一 Supabase project，但 Flutter 仍只访问自有 Backend API；核心 schema、身份映射、权限、Outbox 和 warehouse 出口保持 provider-neutral。正式公开生产前依据 Cloud Run、私网、HA、SLA、PITR、跨云延迟和监控需求复审；满足切换条件时采用 Cloud SQL，且在出现不可丢失真实数据前完成可恢复性演练。
