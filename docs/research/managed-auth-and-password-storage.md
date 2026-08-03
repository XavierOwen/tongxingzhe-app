# 托管认证与密码存储：项目研究结论

更新日期：2026-07-20

## 结论

本项目建议在正式环境采用托管认证（Managed Authentication），由认证供应商处理注册、登录、邮箱验证、密码重置、会话/令牌、MFA、第三方登录和安全升级；本项目后端只保存供应商的稳定用户标识，并继续用自己的 SQL 表管理用户资料、组织成员关系、项目角色、能力权限和审计记录。

托管认证不是“把整个业务交给第三方”。它只负责证明“你是谁”（authentication）；“你在某个组织或项目里能做什么”（authorization）仍由本项目控制。

## 是否增加开销

会增加依赖和潜在费用，但小规模阶段通常可以为零：

- [Auth0 官方价格](https://auth0.com/pricing)提供免费层，当前标示最多 25,000 MAU（月活用户）。
- [AWS Cognito 官方价格](https://aws.amazon.com/cognito/pricing/)当前对直接注册或社交登录提供每月 10,000 MAU 免费额度；SAML/OIDC、短信、机器到机器和高级安全功能另计。
- [Firebase 官方价格](https://firebase.google.com/pricing)当前对多数 Identity Platform 登录方式提供 50,000 MAU 免费额度；手机登录按短信收费。
- [Supabase 官方价格](https://supabase.com/pricing)当前免费层含 50,000 MAU；Pro 从每月 25 美元起，并包含 100,000 MAU，超额再计费。

真正容易形成账单的通常不是普通邮箱登录，而是短信验证码、企业 SSO、高级 MFA/安全功能、超过免费额度的 MAU，以及配套后端、邮件和网络资源。价格会变化，选型时应重新核对，并设置预算告警。

对本项目而言值得采用：它将密码重置、令牌轮换、账号枚举防护、暴力尝试限制等高风险而非核心的工作交给专业服务。代价是供应商依赖、网络依赖和迁移成本，因此业务表不得使用供应商内部数据结构作主键；应通过一个认证适配层映射 `external_auth_subject -> app_user_id`，保留迁移空间。离线状态允许继续使用已登录会话和本地数据，但新登录和令牌刷新仍需要网络。

## MySQL 的密码函数是什么性质

这里有两个容易混淆的密码体系：

1. **MySQL 数据库账号认证**：用于后端服务或管理员连接 MySQL。现代 MySQL 通过认证插件和 `CREATE USER` / `ALTER USER ... IDENTIFIED BY` 管理凭据；[MySQL 8.4 官方文档](https://dev.mysql.com/doc/refman/8.4/en/assigning-passwords.html)说明服务器会按账户的认证插件处理密码。
2. **App 用户认证**：用于普通用户登录 Flutter App。它属于应用后端/认证服务，不能把 Flutter 客户端直接连接 MySQL，也不应使用 MySQL 数据库账号来代表每位 App 用户。

用户印象中的很可能是旧 `PASSWORD()` 函数。它原本用于 MySQL 自己的账户认证值，不是通用的 App 密码存储方案；[MySQL 5.7 官方文档](https://dev.mysql.com/doc/refman/5.7/en/set-password.html)明确说明 `SET PASSWORD ... = PASSWORD(...)` 在 5.7 已弃用，并在 8.0 移除。MySQL 的 `MD5()`、`SHA1()`、`SHA2()` 即使仍可用于一般摘要，也不适合直接保存用户密码。

[OWASP Password Storage Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Password_Storage_Cheat_Sheet.html)指出，SHA-256 等快速哈希允许攻击者高速猜测密码；如果必须自建密码认证，应在后端使用带唯一 salt 和可调成本的专用算法，首选 Argon2id（或按约束选择 scrypt、bcrypt、PBKDF2），并同时实现限速、重置流程、会话安全和 MFA。不要在 SQL 中写 `SHA2(password, 256)`，也不要在 Flutter 端自行哈希后把结果当作密码发送。

## 对本项目的落地建议

- 正式产品：采用托管认证，第一版优先邮箱登录或 magic link/passkey，暂不启用会产生短信费用的手机验证码。
- 本地学习：可以保留只在 demo/test build flavor 中运行的认证练习，但不得与正式账号库或真实个人资料混用。
- SQL 学习不受影响：SQLite/Drift 学习本地模型与 outbox；后端 SQL 学习组织、成员、权限和业务事务；仓库 SQL 学习匿名分析。认证供应商只替代最危险的“自己存密码”部分。
- 供应商选择应单独比较 Flutter SDK、后端技术栈、多组织支持、数据导出/迁移能力、地区合规和预计 MAU；不能仅凭免费额度决定。

