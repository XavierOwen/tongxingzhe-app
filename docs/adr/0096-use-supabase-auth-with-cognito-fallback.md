# 正式身份认证以 Supabase Auth 为首选并以 Cognito 为后备

状态：**已接受（2026-07-31）**，取代 ADR-0025。

正式身份认证采用 Supabase Auth，但以有明确通过／失败标准的六平台验证为发布前提。首版使用邮箱＋密码以及在 App 内输入的邮箱确认／账号恢复 OTP，不承诺 Magic Link 或社交登录；若 Android、iOS、Web、macOS、Windows、Linux 中任何平台的必需认证、会话恢复或安全存储无法可靠通过，系统改用 AWS Cognito，不为 Supabase 编写长期的平台专用认证框架。Auth0 因缺少官方 Flutter Linux 支持而不采用。

认证商只证明外部身份。Flutter 业务模块依赖 `IdentitySession` 而不依赖 Supabase 类型；Backend 验证受信任 issuer／JWKS 后，以 `(issuer, subject)` 映射内部 `app_user_id`，组织成员关系、项目权限、能力授权和审计继续由应用 SQL 负责。本地单元与组件测试使用无法进入正式构建的 fake，Supabase 接线使用本地 CLI＋Mailpit 和隔离 staging；原生平台必须使用安全会话存储，客户端不得包含 service-role secret。

## Consequences

选择 Supabase Auth 本身不自动决定运行时 PostgreSQL 的托管位置。该数据库决策已在 [ADR-0097](./0097-use-supabase-postgresql-for-the-initial-stage.md) 中独立确认：首阶段使用 Supabase PostgreSQL，正式公开生产前必须重新复审 Cloud SQL。
