# Supabase Auth 六平台 Spike

状态：**实现与自动 build 骨架完成；真实认证流程尚未通过，因此不能把 Supabase 写成最终 pass。**

记录日期：2026-07-31

适用需求：`AUTH-001`、`AUTH-004`、`AUTH-006`–`AUTH-008`、`TEST-002`、`TEST-006`

## 1. 要回答的问题

Supabase 是有条件首选，不是因为 SDK 能编译就自动合格。六个平台必须分别证明：

1. 邮箱＋密码注册；
2. App 内输入注册 OTP；
3. 登录；
4. token 强制刷新；
5. 登出；
6. 结束并重新打开进程后，从安全存储恢复 session；
7. App 内输入恢复 OTP，并设置新密码；
8. 错误能映射成 App 的稳定分类，不要求 UI 解析 Supabase 英文信息。

任一必需平台无法稳定满足这套合同，才构成 ADR-0096 所说的 provider failure，并触发 Cognito fallback。缺少测试 project／设备只表示“未验证”，不能伪装成 pass，也不能误判为 Supabase 本身失败。

## 2. 已落实的实现证据

- `IdentitySession` 是业务可见的窄接口；没有暴露 Supabase `User`、`Session` 或 `AuthException`；
- `SupabaseIdentitySession` 覆盖注册、注册 OTP、登录、恢复 OTP、改密码、刷新、登出、重启恢复和 bearer token；
- 正式配置只接受 `SUPABASE_URL` 与 publishable／legacy anon key，并拒绝 `sb_secret_` 与 legacy JWT `service_role`；
- Supabase 默认用 SharedPreferences 保存 session，本项目覆盖为 `flutter_secure_storage`，PKCE verifier 也使用同一安全边界；
- 正式入口缺少两项配置时显示 unavailable，不回退到 MD5；只配置一项或 URL／key 不安全时启动失败；
- test-only fake 位于 `test/`，不能进入 production build；
- `integration_test/supabase_auth_spike_test.dart` 是同一正式代码的设备合同探针，不是另一套教学 Demo。

Supabase 官方说明 Flutter 初始化使用 project URL 和 publishable／anon key，并支持自定义本地 session 存储：[Flutter initialization](https://supabase.com/docs/reference/dart/initializing)。邮箱确认／恢复可通过 `verifyOTP` 完成，但邮件模板需要输出 `Token`：[verify OTP](https://supabase.com/docs/reference/dart/auth-verifyotp)、[email templates](https://supabase.com/docs/guides/auth/auth-email-templates)。

## 3. 当前证据矩阵

| 平台 | App build | 安全存储实际读写 | 注册／OTP／恢复 | 登录／刷新／重启恢复／登出 | 当前结论 |
| --- | --- | --- | --- | --- | --- |
| Android | 本机 debug APK pass | 真机待测 | 待测 | 待测 | build only |
| iOS | 本机 device/no-codesign pass | 真机待测 | 待测 | 待测 | build only |
| Web | 本机 release build pass | HTTPS／localhost 浏览器待测 | 待测 | 待测 | build only |
| macOS | 本机 debug build pass | Keychain 待测 | 待测 | 待测 | build only |
| Windows | CI 待运行 | 安全存储待测 | 待测 | 待测 | 未验证 |
| Linux | CI 待运行 | libsecret＋keyring 待测 | 待测 | 待测 | 未验证 |

GitHub Actions 的 build 只能把第一列改为 pass；其余列必须有真实 Supabase test project 和对应运行环境。`flutter_secure_storage` 声明支持六平台，但 Web 需要 HTTPS／localhost，Linux 需要 libsecret 与可用 keyring，这些都是 runtime 条件，不能从 package metadata 推导为真机通过：[package requirements](https://pub.dev/packages/flutter_secure_storage)。

上述四个本机构建均在 2026-07-31 使用 Flutter 3.44.2 完成。Android 依赖目前会提示 `package_info_plus` 尚未迁移到未来的 Built-in Kotlin；本次 build 成功，但应在依赖发布兼容版本后升级并清除 warning。

## 4. 隔离测试 project 的设置

1. 只使用专门 staging／local project，不使用 production 用户池；
2. 开启 email＋password，关闭 auto-confirm；
3. 注册确认模板和密码恢复模板都显示 `{{ .Token }}`，使用户在 App 内输入 OTP；
4. 只创建 `example.test` 或团队控制域名的 synthetic 测试账号；
5. Flutter 只拿 publishable key；任何 secret/service-role key 只允许在隔离的服务器端测试辅助程序中使用，不能写入 JSON、Dart define、日志或 App；
6. 每个平台测试后删除 synthetic 用户和邮件。

## 5. 运行探针

把示例复制到 Git 忽略的 `secrets/`，不要直接修改并提交示例：

```bash
mkdir -p secrets
cp docs/spikes/supabase-auth-config.example.json \
  secrets/supabase-auth-android.json
```

设置设备与文件路径：

```bash
export AUTH_SPIKE_DEVICE='DEVICE_ID_FROM_FLUTTER_DEVICES'
export AUTH_SPIKE_CONFIG='secrets/supabase-auth-android.json'
./tool/run_supabase_auth_spike.sh
```

配置中的 `AUTH_SPIKE_MODE` 分五次运行：

| mode | 用途 | 需要的字段 |
| --- | --- | --- |
| `signup_request` | 发注册邮件 | email、password |
| `signup_confirm` | 输入刚收到的注册 OTP | email、otp |
| `session` | 登录、刷新、关闭 Adapter、恢复、登出 | 已确认账号的 email、password |
| `recovery_request` | 发恢复邮件 | email |
| `recovery_confirm` | 输入恢复 OTP、设置新密码、登出 | email、otp、new password |

每次运行只报告稳定 failure code 和 provider code，不输出 password、OTP 或 bearer token。实际结果应补回第 3 节，并附 GitHub run、设备／OS 版本、App commit、Supabase project 类型（local/staging）与日期。

## 6. 当前阻塞与决策

当前机器没有可用的 Supabase CLI 本地栈，Docker daemon 也未运行；仓库没有隔离 staging project 的 URL、publishable key、测试邮箱或六平台设备会话。因此真实网络、OTP 邮件、安全存储和重启恢复还不能诚实验收。

当前决策是：保留 Supabase 的条件首选和已编译 Adapter；Issue #2 继续保持 open。获得隔离测试环境后按矩阵逐项验证；如果某个必需平台在合理修复后仍失败，再记录失败证据并切 Cognito，而不是现在凭猜测切换。
