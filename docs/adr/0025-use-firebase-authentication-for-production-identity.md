# 正式身份认证采用 Firebase Authentication

状态：**已被 [ADR-0096](./0096-use-supabase-auth-with-cognito-fallback.md) 取代（2026-07-31）**。Firebase Authentication 无法满足本项目的六平台正式 Flutter 认证合同，不得按本 ADR 实施；本文仅作为决策历史保留。

正式环境采用 Firebase Authentication 处理注册、登录、账号恢复、会话与身份令牌；App 自己的 SQL 数据库继续负责用户资料、组织成员关系、项目角色、能力权限和审计。系统通过认证适配层把 Firebase 身份标识映射到内部 `app_user_id`，业务表不直接依赖 Firebase 的内部数据结构，以保留未来迁移能力。

本地 Demo 与单元、组件测试使用仅在非生产构建中可用的隔离假认证，不保存真实密码，也不复用正式账号；需要验证 Firebase 接线的集成测试使用 Firebase Authentication Emulator。现有 MD5 演示认证不得进入正式构建。
