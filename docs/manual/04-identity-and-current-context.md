# 第 4 章：登录身份如何成为可信的当前项目上下文

## 1. 这一章解决什么

Supabase 登录成功只证明“谁持有这个 session”。它不回答四个业务问题：同行者内部使用哪个用户标识、数据属于哪个空间、当前操作属于哪个推广项目，以及新草稿绑定哪个问卷版本。

如果 Flutter 自行把 Supabase subject 当成 `app_user_id`，或从 legacy Demo 读取团队和项目，客户端就能伪造归属。正式路径因此使用一条受控链：

```text
Supabase access token
        ↓ Backend 验证签名、issuer、audience、期限和 role
可信 (issuer, subject)
        ↓ PostgreSQL 原子引导
app_user_id → 个人空间 → 当前推广项目 → 当前问卷版本
        ↓ HTTPS 响应
Flutter AppSession
```

Flutter 只把 bearer token 交给自有 Backend。请求中没有 `app_user_id`、workspace、project、role 或 capability。

## 2. 为什么 issuer 和 subject 必须一起使用

`subject` 只在一个签发者的命名空间内唯一。两个 Supabase project 可以签发相同的 subject。数据库因此对 `(issuer, subject)` 建唯一约束，不对 subject 单独建全局唯一约束。subject 是不透明值，保存时不能改写大小写或裁剪字符。

`app_user_id` 由同行者生成。接触、成员关系、权限和审计以后都引用它。认证商 subject 只留在身份映射表中，所以更换认证商不会要求重写全部业务外键。

## 3. Backend 如何建立信任

Backend 按 [Supabase JWT 说明](https://supabase.com/docs/guides/auth/jwts)使用 JWKS 公钥验证 access token。验证同时限制精确 issuer、`authenticated` audience、`authenticated` role、签名算法和过期时间。只有验证通过后，Backend 才调用 SQL：

```sql
SELECT *
FROM app_data.bootstrap_personal_context($1, $2);
```

`$1` 和 `$2` 来自已验证 claims。HTTP body 和 query string 都不能提供这两个值。Backend 使用参数化查询，不拼接 SQL。

正式环境只接受 `ES256` 或 `RS256` asymmetric signing key。Supabase 的[签名密钥说明](https://supabase.com/docs/guides/auth/signing-keys)给出了 JWKS 地址、缓存和轮换边界。JWKS 只含公钥，Backend 不保存 Supabase JWT secret 或 service-role key。

## 4. PostgreSQL transaction 建立哪些事实

`0002_identity_context.sql` 创建五张最小表：

| 表 | 当前职责 |
| --- | --- |
| `app_users` | 保存稳定内部用户及账号状态 |
| `external_identities` | 保存 `(issuer, subject) → app_user_id` |
| `workspaces` | 保存每个用户唯一的活动个人空间 |
| `projects` | 保存个人空间的起始推广项目 |
| `questionnaire_versions` | 保存该项目当前的基础已发布版本 |

`bootstrap_personal_context` 是一个 `SECURITY DEFINER` 函数。普通 Backend runtime role 可以执行它，但不能直接插入、更新或删除上述表。函数使用 transaction advisory lock，让同一身份的并发首启共用一套个人上下文。

同一 `(issuer, subject)` 重复调用会返回相同 ID。相同 subject 配合不同 issuer 会得到不同内部用户。任一创建失败时，整个语句回滚，不返回半套上下文。

身份引导创建的基础问卷版本可以没有场景问题。它仍是一个正式、已发布、版本号为 1 的问卷版本。项目后来发布的问题由受权读取端点取得，并按精确版本缓存在本机；新草稿始终绑定可信当前上下文给出的版本。

## 5. Flutter AppSession 隐藏哪些细节

`AppSession` 对调用者只暴露一个 snapshot：未配置、未登录、正在解析上下文、可用或失败。可用状态同时包含内部用户、空间、项目、问卷版本和 capability。

模块内部完成以下工作：

- 从 `IdentitySession` 恢复登录状态；
- 取得短期 access token；
- 调用 `/v1/session/context`；
- 验证响应 ID、空间类型、版本号和 capability 结构；
- 在注销或身份变化时立即清除旧上下文；
- 丢弃注销后才返回的旧网络响应。

Widget 不读取 token，也不把 external subject 填进草稿。下一步正式草稿 UI 只从 `AppSession.current.context` 取得四个归属 ID。

## 6. 失败为何必须关闭操作入口

认证成功但上下文失败时，App 不能回退到 Demo 项目，也不能生成本地临时 `app_user_id`。这些做法会制造无法安全同步的孤立事实。

`AppSession` 因此保留稳定失败分类：认证失败、Backend 未配置、未授权、网络不可用、响应无效或服务端拒绝。失败 snapshot 不含任何部分上下文，`canRecordContact` 为 false。UI 后续应显示重试或重新登录操作。

## 7. 可以怎样验证

Flutter 目标测试：

```bash
flutter test test/app_session
```

Backend 目标测试：

```bash
npm --prefix backend/server test
```

PostgreSQL 16 可用时，按[数据库说明](../../backend/database/README.md)重建空库，再运行 `verify_identity_context.sql` 和 `0002_identity_context.sql` fixture。fixture 只使用 synthetic issuer 和 subject，并在结尾回滚。

读完这一章，应能解释：为什么 subject 不是 `app_user_id`、谁可以决定当前项目，以及注销为何能阻止旧网络响应恢复上下文。
