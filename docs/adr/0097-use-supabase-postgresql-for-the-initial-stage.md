# 首阶段业务数据库采用 Supabase PostgreSQL

状态：**已接受（2026-07-31）**。

当前开发和首阶段验证使用与 Supabase Auth 同一 Supabase project 中的 PostgreSQL 作为业务数据库。这一选择利用统一的 Auth、PostgreSQL、本地 CLI、测试邮件和 SQL migration 环境，减少尚无真实用户时的基础设施数量与固定成本。

该决定不改变 App 的安全和可替换边界：

- Flutter 继续使用 Drift／SQLite 和 `sync_outbox`，只调用自有 HTTPS Backend API，不持有 PostgreSQL 凭据，不直接读写 Supabase 业务表；
- Backend 负责幂等、权限、revision、审计、冲突、隐私阈值和 `warehouse_outbox`；
- 外部身份始终通过 `(issuer, subject) → app_user_id` 映射，核心业务表不直接依赖 `auth.users` 或 `auth.uid()`；
- schema 的权威来源是仓库内经过审查的有序 `.sql` migration，核心模型只使用标准 PostgreSQL 和双方都可接受的扩展；
- 正常运行流量使用最小权限数据库角色；可绕过 RLS 的 `service_role` 不进入 Flutter，也不代替 Backend 业务授权；
- 数据库托管商不进入 Flutter 领域接口、同步协议或仓库分析合同。

## 正式公开生产前的必要复审

在出现第一批不可丢失的真实数据前，必须依实测和当时的官方产品条件重新比较 Supabase PostgreSQL 与 Google Cloud SQL for PostgreSQL，至少检查：

1. Backend 是否长期运行在 Cloud Run，以及跨云连接的延迟、断连、出站流量和故障面；
2. 是否需要 GCP 私网、IAM database authentication 或统一 VPC 安全边界；
3. 是否需要区域级自动写入故障切换和可核验的 uptime SLA；
4. 备份、PITR、RPO、RTO、恢复演练和离站备份是否达到发布要求；
5. 连接池、可观测性、运行成本和数据驻留是否仍合适。

若这些条件成为硬要求，而当时的 Supabase 方案无法满足，则重新打开本 ADR，在真实数据规模仍小时改用 Cloud SQL。此复审是正式发布门禁，不是可选的未来优化。

## Consequences

当前可以用一套可复现环境学习和实施 Auth、PostgreSQL 与 SQL migration，不额外维护与正式 App 脱节的 Demo。如果 Backend 继续部署在 Cloud Run，团队必须明确承担 GCP 到 Supabase 的跨云公网 TLS 连接及其运维成本；选择 Supabase 不等于这一风险已被消除。

Cloud SQL 不被永久排除；它从“当前默认托管商”改为“正式公开生产前的重要备选与复审对象”。标准 PostgreSQL migration、定期 `pg_dump`／restore 演练与稳定 Backend 合同是保留这一退出路径的必要成本。

详细依据见 [Supabase PostgreSQL 与 Google Cloud SQL for PostgreSQL 比较](../research/supabase-postgres-vs-cloud-sql-2026.md)。
