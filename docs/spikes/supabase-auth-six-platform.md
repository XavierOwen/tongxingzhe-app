# Supabase Auth 六平台 Spike

状态：**macOS 真实认证合同已通过；其余五个平台仍须实测，因此不能把 Supabase 写成六平台最终 pass。**

记录日期：2026-08-01

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
| Android | CI pass；本机 debug APK pass | 真机待测 | 待测 | 待测 | build only |
| iOS | CI pass；本机 device/no-codesign pass | 真机待测 | 待测 | 待测 | build only |
| Web | CI pass；本机 release build pass | HTTPS／localhost 浏览器待测 | 待测 | 待测 | build only |
| macOS | CI pass；Apple Development 签名 debug pass | Keychain 读写 pass | 注册、8 位 OTP、恢复、改密码 pass | 登录、强制刷新、跨进程恢复、登出 pass | runtime pass |
| Windows | CI pass | 安全存储待测 | 待测 | 待测 | build only |
| Linux | CI pass | libsecret＋keyring 待测 | 待测 | 待测 | build only |

GitHub Actions 的 build 只能把第一列改为 pass；其余列必须有真实 Supabase test project 和对应运行环境。`flutter_secure_storage` 声明支持六平台，但 Web 需要 HTTPS／localhost，Linux 需要 libsecret 与可用 keyring，这些都是 runtime 条件，不能从 package metadata 推导为真机通过：[package requirements](https://pub.dev/packages/flutter_secure_storage)。

六个平台均在 [GitHub Actions run 30666113687](https://github.com/XavierOwen/tongxingzhe-app/actions/runs/30666113687) 的独立 job 中 build 通过；上述四个本机构建也在 2026-07-31 使用 Flutter 3.44.2 完成。Android 依赖目前会提示 `package_info_plus` 尚未迁移到未来的 Built-in Kotlin；本次 build 成功，但应在依赖发布兼容版本后升级并清除 warning。

macOS 运行时证据于 2026-08-01 在 macOS 26.5.2、隔离 hosted Supabase project 和专用测试邮箱／SMTP 上取得。第一次实测暴露出 App Sandbox 缺少出站网络权限，以及 Keychain 缺少签名 entitlement；最小探针分别得到 `Operation not permitted` 和系统错误 `-34018`。修复 `com.apple.security.network.client`、`keychain-access-groups` 并使用 Apple Development 签名后，注册、注册 OTP、登录、刷新、Adapter 重建、密码恢复、修改后重新登录均通过。最后再用两个独立 App 进程执行 `session_start` 与 `session_restore`，证明恢复不只是同一进程内重建对象。

## 4. 隔离测试 project 的设置

1. 只使用专门 staging／local project，不使用 production 用户池；
2. 开启 email＋password，关闭 auto-confirm；
3. 注册确认模板和密码恢复模板都显示 `{{ .Token }}`，使用户在 App 内输入 OTP；
4. hosted project 使用能实际收信的专用测试邮箱或团队控制的别名；`example.test` 只适合不会真的投递邮件的 local／fixture；
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

配置中的 `AUTH_SPIKE_MODE` 按验证目的分阶段运行：

| mode | 用途 | 需要的字段 |
| --- | --- | --- |
| `signup_request` | 发注册邮件 | email、password |
| `signup_confirm` | 输入刚收到的注册 OTP | email、otp |
| `session` | 快速验证登录、刷新、同进程 Adapter 重建、恢复、登出 | 已确认账号的 email、password |
| `session_start` | 第一进程登录、刷新并保留安全 session 后退出 | 已确认账号的 email、password |
| `session_restore` | 第二进程只从安全存储恢复并登出 | email；password 不参与恢复 |
| `recovery_request` | 发恢复邮件 | email |
| `recovery_confirm` | 输入恢复 OTP、设置新密码、登出 | email、otp、new password |

每次运行只报告稳定 failure code 和 provider code，不输出 password、OTP 或 bearer token。实际结果应补回第 3 节，并附 GitHub run、设备／OS 版本、App commit、Supabase project 类型（local/staging）与日期。

## 6. 当前阻塞与决策

隔离 hosted Supabase project、测试邮箱和 macOS 签名环境已经就绪，macOS 合同通过。尚缺 Android、iOS、Web、Windows、Linux 的真实运行环境与逐平台安全存储、OTP、恢复证据；CI build 不能替代这些运行时结果。本地 Supabase CLI／Docker 栈仍不可用，但不再阻塞 hosted project 的设备验证。

当前决策是：保留 Supabase 的条件首选和已编译 Adapter；Issue #2 继续保持 open。继续按矩阵验证其余平台；如果某个必需平台在合理修复后仍失败，再记录失败证据并切 Cognito，而不是把 macOS 单平台成功扩张为六平台结论。
