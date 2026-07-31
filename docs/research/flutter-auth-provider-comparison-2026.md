# Flutter 六平台托管认证比较：Supabase、Auth0 与 AWS Cognito

更新日期：2026-07-31

状态：**选型研究完成；用户已确认建议，并由 [ADR-0096](../adr/0096-use-supabase-auth-with-cognito-fallback.md) 正式取代原 Firebase 决策。**

## 1. 结论

本项目建议采用以下顺序：

1. **Supabase Auth：有条件首选。**它最符合 Flutter／Dart 开发体验、SQL 学习目标、当前规模和用户偏好，也能在本地运行 Auth 与 PostgreSQL；但正式承诺六平台前，必须验证 Linux 的邮箱确认、找回密码与会话安全。
2. **AWS Cognito：验证失败时的后备。**Amplify Flutter 明确把 Authentication 标为 Android、iOS、Web、Windows、macOS、Linux 六平台可用，技术覆盖最完整；代价是 AWS 配置、测试环境和日常维护更复杂。
3. **Auth0：本项目不采用。**官方 Flutter 包不列 Linux；Windows 虽已支持登录，但没有内置 Credentials Manager，需要 App 自己保存和刷新凭据，不能满足本项目的严格六平台合同。

这里的“有条件”不是长期犹豫，而是一组很短的通过／失败测试。若 Supabase 在规定的六平台测试中通过，就正式采用；若 Linux 的必需流程无法安全完成，就切换 Cognito。

## 2. 比较前提

本项目的目标平台是：Android、iOS、Web、macOS、Windows、Linux。首版至少需要：

- 邮箱注册、登录、邮箱确认、退出和账号找回；
- App 重启后的会话恢复与令牌刷新；
- 原生平台安全保存会话；
- Backend 验证令牌，并把外部身份映射为内部 `app_user_id`；
- 本地／自动化测试不依赖真实生产账号；
- 身份提供商不负责业务角色、项目权限和审计，这些继续保存在应用 SQL 中；
- 将来更换认证商时，不重写联系人、项目、问卷、统计和同步模块。

社交登录、Magic Link、Passkey、短信和企业 SSO 都不是首版选型的必要条件。

## 3. 结果总表

| 判断项 | Supabase Auth | Auth0 | AWS Cognito |
| --- | --- | --- | --- |
| Flutter 包标示平台 | 六平台 | 五平台，不含 Linux | 六平台，Authentication 明确全绿 |
| Linux 基础认证 | 包可运行；仍需真实验证 | 无官方 Flutter 支持 | 官方支持 |
| Linux Deep Link | 官方 `supabase_flutter` 文档未列 Linux | 不适用 | Hosted UI／平台流程可用，但仍应实测 |
| Windows 会话保存 | 默认保存方式不够安全，需自定义安全存储 | 无 Credentials Manager，需自行实现 | Amplify Secure Storage 路径 |
| 本地认证环境 | 有 Supabase CLI、本地 Auth、Postgres、Mailpit | 未发现等价官方本地模拟器 | 未发现等价官方 Cognito 模拟器 |
| 与 SQL 学习的结合 | 很强，项目同时包含 PostgreSQL 与 migrations | 弱，纯身份平台 | 中等，身份与 SQL 基础设施分开 |
| 运维复杂度 | 低至中 | 中 | 高 |
| 本项目结论 | **有条件首选** | **排除** | **后备** |

“包标示支持”只说明代码入口存在，不等于所有登录方法、回跳、系统密钥库和安装包都已在每个平台达到生产质量，所以仍保留小范围设备测试。

## 4. 为什么首选 Supabase

### 4.1 与 Flutter 和 SQL 学习目标最一致

官方发布的 `supabase_flutter` 包列出 Android、iOS、Linux、macOS、Web、Windows 六个平台。Supabase 本地开发栈同时提供 Auth、PostgreSQL、迁移、seed 与 Mailpit，因此可以把“正式 App”“Flutter 学习”“真正 SQL”“认证集成测试”放在同一套工程中，而不另造一个教学 Demo。

官方资料：

- [`supabase_flutter` 平台与用法](https://pub.dev/packages/supabase_flutter)
- [Supabase 本地开发工作流](https://supabase.com/docs/guides/local-development/cli-workflows)
- [Supabase CLI 与本地 Mailpit](https://supabase.com/docs/guides/local-development/cli/getting-started)

### 4.2 Linux 风险是具体的，也有首版规避路径

Supabase 的 Flutter 包列 Linux，但其 Deep Link 说明只列 Android、iOS、Web、macOS 和 Windows。Magic Link、默认邮箱确认链接、默认找回密码链接和 OAuth 都会依赖回跳，因此不能据此承诺 Linux 上这些流程已经完整可用。

首版建议采用跨平台一致的输入式流程：

- 登录：邮箱＋密码；
- 邮箱确认：邮件发送六位 OTP，用户回到 App 输入；
- 找回密码：邮件发送 recovery OTP，用户在 App 输入后设置新密码；
- 暂不把 Magic Link 与社交 OAuth 列为首版必需功能。

Supabase 官方邮件模板支持以 `{{ .Token }}` 发送 OTP，Dart SDK 支持用邮箱、token 与 `email`／`recovery` 类型调用 `verifyOTP`。这条路不依赖 Linux Deep Link，但仍必须在真实 Linux 安装包上测试整个流程。

官方资料：

- [`supabase_flutter` Deep Link 支持范围](https://pub.dev/packages/supabase_flutter#deep-links)
- [邮件模板与 OTP](https://supabase.com/docs/guides/auth/auth-email-templates)
- [Dart `verifyOtp`](https://supabase.com/docs/reference/dart/auth-verifyotp)
- [邮箱 OTP 登录](https://supabase.com/docs/guides/auth/auth-email-passwordless)

### 4.3 默认会话保存不能直接照搬到生产

`supabase_flutter` 默认使用 Shared Preferences 保存会话；官方也给出了注入自定义 `LocalStorage`、改用 `flutter_secure_storage` 的示例。正式原生 App 应使用平台密钥库／安全存储；Web 则必须接受浏览器会话受 XSS 风险影响这一事实，并配套 CSP、依赖审计和最小令牌寿命策略。

这不是淘汰 Supabase 的理由，但它必须成为实现验收项，不能把默认配置误认为安全完成。

官方资料：

- [`supabase_flutter` Custom LocalStorage](https://pub.dev/packages/supabase_flutter#custom-localstorage)

### 4.4 成本适合当前阶段，但不是“永远免费”

截至 2026-07-31，Supabase Free 为每月 0 美元，含 50,000 MAU、500 MB 数据库与最多两个活跃项目；免费项目连续一周无活动会暂停。Pro 从每月 25 美元起，含 100,000 MAU，超出后按每 MAU 0.00325 美元计费。生产邮件还应配置自有 SMTP，不能依赖试用发送额度。

官方资料：

- [Supabase Pricing](https://supabase.com/pricing)
- [密码认证与生产邮件说明](https://supabase.com/docs/guides/auth/passwords)

Supabase 的价格已经包含 PostgreSQL。若最后只用 Supabase Auth、同时另付 Cloud SQL，会形成两套数据库基础设施。更合理的候选是“Supabase Auth＋同项目 PostgreSQL，业务仍经自有 Backend API”，但这是数据库托管决策，应在认证选择之后单独确认，不能因 Auth 选型自动决定。

## 5. 为什么 Cognito 是后备

AWS 官方发布的 `amplify_auth_cognito` 把 Authentication 在 Android、iOS、Web、Windows、macOS、Linux 六个平台全部标为支持；`amplify_secure_storage` 也是其依赖。这是三者中最强的严格六平台证据。

截至 2026-07-31，Cognito Lite 与 Essentials 对直接／社交登录用户提供每月 10,000 MAU 的长期免费额度。Essentials 超过免费额度后示例价格为每 MAU 0.015 美元；短信由 SNS、邮件由 SES 另行收费。

它没有成为首选的原因不是功能不足，而是项目适配成本：

- 需要维护 AWS 账号、区域、User Pool、App Client、IAM／Amplify 配置和独立测试资源；
- 没有与 Supabase CLI 相当的官方本地 Cognito 栈，单元测试仍用 fake，真实接线通常需要隔离的云端测试池；
- 它不会自然帮助本项目学习 PostgreSQL／SQL，数据库仍需另外选择；
- 对当前尚无真实用户的项目，这些复杂度暂时没有足够收益。

官方资料：

- [`amplify_auth_cognito` 六平台支持表](https://pub.dev/packages/amplify_auth_cognito)
- [Amplify Flutter Auth](https://docs.amplify.aws/flutter/frontend/auth/)
- [Cognito Pricing](https://aws.amazon.com/cognito/pricing/)
- [Amplify token 与设备凭据](https://docs.amplify.aws/flutter/build-a-backend/auth/concepts/tokens-and-credentials/)

## 6. 为什么排除 Auth0

Auth0 的官方 Flutter 包列 Android、iOS、macOS、Web 与 Windows，但不列 Linux。Windows 路径还明确没有 Credentials Manager，App 必须自行保存凭据。即使其 Universal Login 成熟、Free 额度截至 2026-07-31 达到 25,000 MAU，也无法弥补本项目“六平台同一正式代码”的硬缺口。

官方资料：

- [`auth0_flutter` 平台与 Windows 限制](https://pub.dev/packages/auth0_flutter)
- [Auth0 Flutter Windows Quickstart](https://auth0.com/docs/quickstart/native/flutter-windows)
- [Auth0 Pricing](https://auth0.com/pricing)

## 7. Supabase 通过／失败验证

在正式 ADR 和业务实现前，只做一个有边界的认证验证。六个平台逐项验证：

1. 邮箱＋密码注册和登录；
2. 输入式邮箱确认 OTP；
3. 输入式 recovery OTP 与修改密码；
4. App 重启后的会话恢复、过期刷新、退出和撤销；
5. Android、iOS、macOS、Windows、Linux 使用安全存储；Web 检查刷新、双标签与 XSS 防护边界；
6. Backend 使用受信任的 issuer／JWKS 验证 access token，并以 `(issuer, subject)` 映射内部 `app_user_id`；
7. 本地 Supabase CLI＋Mailpit 的集成测试，以及隔离 staging 项目的接线测试；
8. 生产构建中不能启用 fake auth，也不能包含 service-role secret。

通过标准：八项全部通过，且 Linux 不需要用户复制原始令牌或执行开发者操作。否则切换 Cognito，不继续为 Supabase 编写平台专用认证框架。

## 8. 与业务代码的边界

无论最终是 Supabase 还是 Cognito，业务代码只认识一个小接口，例如：

```dart
abstract interface class IdentitySession {
  Stream<SignedInIdentity?> watchIdentity();
  Future<void> signInWithEmailAndPassword(String email, String password);
  Future<String> accessToken();
  Future<void> signOut();
}
```

生产环境接 Supabase，普通自动化测试接 `FakeIdentitySession`。Backend 只把认证商返回的稳定 subject 当作“外部身份证号”，再在 SQL 中映射 `app_user_id`；组织角色、项目权限、管理员能力和审计永远不写进 Flutter 可自报字段，也不绑死在 Supabase 专有类型上。

这个边界就是认证部分的“测试接缝”：可以拔掉真实认证商，换上可控制成功、失败、过期和撤销的测试实现，而业务代码不需要改变。

## 9. 已确认的决定

用户已确认：

> 以 Supabase Auth 为首选，先完成上述有边界的六平台验证；首版使用邮箱＋密码及输入式邮箱 OTP，不承诺 Magic Link／社交登录；验证失败则改用 AWS Cognito。认证商只负责身份，业务授权和审计继续由应用 SQL 负责。

是否同时采用 Supabase PostgreSQL 取代原计划的 Cloud SQL，是下一项独立架构决定，不由本次认证决定自动带出。
