# Supabase Auth 六平台 Spike

第一次接触测试流程的读者，可先阅读说明书的 [用测试和证据安全地修改代码](../manual/02-testing-and-change-workflow.md)。其中逐项解释本 Spike 为什么拆分注册、OTP、恢复、session 和跨进程恢复，以及 Red–Green、回归测试、测试接缝与 CI 分别是什么。

状态：**macOS、Web 与 iOS 的真实认证合同已通过；Android、Windows、Linux 仍须实测。因此不能把 Supabase 写成六平台最终 pass。**

记录日期：2026-08-03

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
| iOS | CI pass；本机 device/no-codesign pass；Apple Development 签名真机安装 pass | Keychain 写入与跨进程读取 pass | 注册请求、OTP 邮件送达／确认、恢复 OTP、改密码 pass | 登录、强制刷新、Adapter 重建、跨进程恢复、登出 pass | runtime pass |
| Web | CI pass；本机 release build pass | localhost 写入、Adapter 重建读取、关闭并重启浏览器后读取 pass | 注册请求、OTP 邮件送达、OTP 确认、恢复 OTP 与改密码 pass | 登录、强制刷新、跨浏览器进程恢复、登出 pass | runtime pass |
| macOS | CI pass；Apple Development 签名 debug pass | Keychain 读写 pass | 注册、8 位 OTP、恢复、改密码 pass | 登录、强制刷新、跨进程恢复、登出 pass | runtime pass |
| Windows | CI pass | 安全存储待测 | 待测 | 待测 | build only |
| Linux | CI pass | libsecret＋keyring 待测 | 待测 | 待测 | build only |

GitHub Actions 的 build 只能把第一列改为 pass；其余列必须有真实 Supabase test project 和对应运行环境。`flutter_secure_storage` 声明支持六平台，但 Web 需要 HTTPS／localhost，Linux 需要 libsecret 与可用 keyring，这些都是 runtime 条件，不能从 package metadata 推导为真机通过：[package requirements](https://pub.dev/packages/flutter_secure_storage)。

六个平台均在 [GitHub Actions run 30666113687](https://github.com/XavierOwen/tongxingzhe-app/actions/runs/30666113687) 的独立 job 中 build 通过；上述四个本机构建也在 2026-07-31 使用 Flutter 3.44.2 完成。Android 依赖目前会提示 `package_info_plus` 尚未迁移到未来的 Built-in Kotlin；本次 build 成功，但应在依赖发布兼容版本后升级并清除 warning。

macOS 运行时证据于 2026-08-01 在 macOS 26.5.2、隔离 hosted Supabase project 和专用测试邮箱／SMTP 上取得。第一次实测暴露出 App Sandbox 缺少出站网络权限，以及 Keychain 缺少签名 entitlement；最小探针分别得到 `Operation not permitted` 和系统错误 `-34018`。修复 `com.apple.security.network.client`、`keychain-access-groups` 并使用 Apple Development 签名后，注册、注册 OTP、登录、刷新、Adapter 重建、密码恢复、修改后重新登录均通过。最后再用两个独立 App 进程执行 `session_start` 与 `session_restore`，证明恢复不只是同一进程内重建对象。

Web 的部分运行时证据于 2026-08-01 在 Chrome 149.0.7827.200、ChromeDriver 149.0.7827.155 与 localhost 上取得。使用修改后的新密码，`session` 探针完成登录、token 强制刷新、安全存储读取、Adapter 重建恢复与登出。该结果不包含 Web 注册／OTP／密码恢复，也不证明关闭并重新启动浏览器后仍能恢复，所以只记为 `runtime partial`。

2026-08-03 的 Web `signup_request` 又补充了注册邮件证据：普通 Chrome 对 `/auth/v1/signup` 的请求返回 200，测试邮箱实际收到 OTP。同一次旧版 harness 还启动了 HeadlessChrome，并对同一邮箱重复提交注册；第二个请求触发 PostgreSQL `23505`（`users_email_partial_key` 唯一约束）后返回 500。该 500 是测试启动方式造成的一次测试执行两遍，不是 SMTP 投递失败，也不是第一次注册失败。runner 现保留用户侧的 `AUTH_SPIKE_DEVICE=chrome`，内部改用 `web-server`，只让 ChromeDriver 启动浏览器，并用回归测试锁定这条边界。修复后的单浏览器 `signup_confirm` 使用收到的 OTP 得到 `signedIn`，随后成功登出，证明 Web 注册 OTP 合同通过。后续 `recovery_request` 得到 `recoveryCodeSent`，测试邮箱收到新的恢复 OTP；`recovery_confirm` 进入 `changingRecoveredPassword`，新密码更新后回到 `signedIn` 并成功登出。再以修改后的新密码运行 `session`，登录、token 强制刷新、Adapter 重建恢复与登出均成功，证明 Web 密码恢复不只是更新接口表面返回成功。最后，`session_start` 在固定 `http://127.0.0.1:57320` 与持久 Chrome profile 中登录、刷新并退出第一个浏览器进程；第二次独立运行的 `session_restore` 不使用密码，从 Web 安全存储恢复 session、读取 token 并登出，证明恢复不只是同一页面或同一 Dart 对象内重建。认证 SDK 返回带 HTTP 状态的 5xx 时，Adapter 也会映射为 `providerRejected` 与安全的 `http_<status>`，不再把服务器错误误报为设备断网。

iOS 的第一轮真机证据于 2026-08-03 在 iPhone 14 Pro、iOS 26.5.2 和同一隔离 hosted Supabase project 上取得。静态检查先发现 Runner 没有供 `flutter_secure_storage` 使用的 Keychain Sharing entitlement；新增测试在旧配置上因两个 entitlement 文件缺失、Xcode 三种 build configuration 未引用它们而得到预期 Red。随后为 Debug／Profile 与 Release 分别增加 `keychain-access-groups`，并把 Xcode 配置接线，原来的三个断言全部转为 Green。这个静态测试只能证明工程声明存在，不能证明真机 Keychain 已获签名授权，因此仍继续执行真实设备探针。

第一次签名安装后的启动被 iOS 拒绝，系统明确报告 Developer App Certificate 尚未信任；完成设备重启和显式信任后，新的启动请求成功。这里需要区分三件事：信任这台 Mac、启用 Developer Mode、信任开发者证书分别解决配对、开发能力和签名 App 启动，不可互相替代。随后 `session` 在真机完成登录、token 强制刷新、Keychain 读取、Adapter 重建恢复与登出。再以两个独立 App 进程运行 `session_start` 与 `session_restore`：第一进程登录并留下 session，第二进程不使用密码，从 iPhone Keychain 恢复 token 后登出。因此 iOS 的签名安装、HTTPS、Keychain 写入／跨进程读取和 session 生命周期可以记为 pass；注册与恢复合同随后继续逐项验证。

分阶段 OTP 测试随后发现，每次成功运行后开发者信任都会消失。反馈回路表明这些失败均发生在 Dart VM 启动之前并显示 `No tests ran`，所以没有重复提交 OTP 或请求 Supabase。根因是 `flutter test` 对 integration test 默认启用卸载：测试结束时删除设备上的最后一款开发 App，下一 mode 覆盖安装前便需要重新建立信任。runner 的公开命令回归测试先因缺少 `--no-uninstall` 得到预期 Red；原生分支加入该参数后转为 Green。它仍然为每个 mode 构建并覆盖安装当前测试 App，只在阶段结束后保留 App，从而保持开发者信任；Web 分支不变。整套验证结束后再手工删除 synthetic App。

iOS 第一次注册请求对原测试邮箱得到 `/auth/v1/signup` 200，但未收到邮件；提供的 22 条日志全部标为 success，且没有收件服务器的最终投递回执，所以证据只支持“Supabase 接受请求”，不能证明学校邮箱、别名规则或 SMTP 中哪一层拦截。改用受控工作邮箱后，真机 `signup_request` 成功且实际收到 OTP；`signup_confirm` 随后进入 `signedIn` 并登出。`recovery_request` 又实际送达新的恢复 OTP，`recovery_confirm` 建立恢复 session、更新新密码、回到 `signedIn` 并登出。最后把新密码放入独立 `session` 运行，登录、两次刷新、Adapter 重建恢复与登出全部通过，也证明 `--no-uninstall` 后下一次覆盖安装不再丢失开发者信任。期间一次 Xcode“推荐工程设置”模态窗口导致启动等待超时；关闭而不接受自动工程改写后重跑通过，未进入 Dart 的轮次不计为认证失败。

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

Web 探针由 Flutter 官方的 `flutter drive` 路径运行，需要与本机 Chrome 主版本匹配的 ChromeDriver：[Flutter Web integration testing](https://docs.flutter.dev/testing/integration-tests#test-in-a-web-browser)。以 Apple Silicon 上的 Chrome 149 为例，可以把 driver 安装到已被 Git 忽略的 `.dart_tool/`：

```bash
driver_path="$(npx --yes @puppeteer/browsers install chromedriver@149 \
  --platform mac_arm \
  --path .dart_tool/chromedriver-cache \
  --format '{{path}}')"
export PATH="$(dirname "${driver_path}"):${PATH}"
export AUTH_SPIKE_DEVICE='chrome'
export AUTH_SPIKE_CONFIG='secrets/supabase-auth-macos.json'
./tool/run_supabase_auth_spike.sh
```

用户仍然设置 `AUTH_SPIKE_DEVICE=chrome`；runner 内部故意把 App device 设为 `web-server`，由 ChromeDriver 成为唯一的浏览器拥有者。不要把内部 device 改回 `chrome`：在受影响的 Flutter 版本中，这会同时启动 App Chrome 与 WebDriver 的 HeadlessChrome，使带注册、恢复等外部副作用的测试执行两遍。

为了让 `session_start` 与下一次独立运行的 `session_restore` 真正看到同一份 Web 安全存储，runner 默认固定使用 `http://127.0.0.1:57320`，并把 Chrome profile 放在 Git 已忽略的 `.dart_tool/supabase-auth-web-profile/`。如端口冲突，可用 `AUTH_SPIKE_WEB_PORT` 覆盖；如需隔离多组测试，可用 `AUTH_SPIKE_WEB_PROFILE_DIR` 覆盖。前后两次运行必须使用同一 hostname、port 与 profile。`session_start` 后 profile 会暂存 staging session，正常的 `session_restore` 会在验证后登出；不要把 production 凭据用于该探针。

其他 CPU／Chrome 版本需要替换 `--platform` 和 `chromedriver@<major>`；不要用版本不匹配的 driver 将 harness 失败误记为 Supabase 失败。

配置中的 `AUTH_SPIKE_MODE` 按验证目的分阶段运行：

| mode | 用途 | 需要的字段 |
| --- | --- | --- |
| `signup_request` | 发注册邮件 | 合成地址、password、`AUTH_SPIKE_SIGNUP_CONFIRM_NEW_SYNTHETIC_ACCOUNT="true"` |
| `signup_confirm` | 输入刚收到的注册 OTP | email、otp |
| `session` | 快速验证登录、刷新、同进程 Adapter 重建、恢复、登出 | 已确认账号的 email、password |
| `session_start` | 第一进程登录、刷新并保留安全 session 后退出 | 已确认账号的 email、password |
| `session_restore` | 第二进程只从安全存储恢复并登出 | email；password 不参与恢复 |
| `recovery_request` | 发恢复邮件 | email |
| `recovery_confirm` | 输入恢复 OTP、设置新密码、登出 | email、otp、new password |

每次运行只报告稳定 failure code 和 provider code，不输出 password、OTP 或 bearer token。实际结果应补回第 3 节，并附 GitHub run、设备／OS 版本、App commit、Supabase project 类型（local/staging）与日期。

### `signup_request` 的发送前安全检查

`signup_request` 是唯一会建立新账号的模式。runner 在启动 Flutter 前读取 JSON 配置，不联系 Supabase。

它要求两个条件：

1. `AUTH_SPIKE_SIGNUP_CONFIRM_NEW_SYNTHETIC_ACCOUNT` 必须是字符串 `"true"`；它只确认本次地址是新的合成测试账号。`session`、`recovery_request` 和其他模式不读取这个字段。
2. `AUTH_SPIKE_EMAIL` 必须匹配 `^auth-spike-[a-z0-9][a-z0-9._+-]*@[a-z0-9][a-z0-9.-]*\.[a-z0-9]+$`，例如 `auth-spike-run-20260813@example.test`。普通个人地址和本示例中的 `synthetic-test-account@example.test` 会被拒绝。`+tag` 是地址的字面部分，不会按 Gmail 别名规则合并。

测试 hosted project 时，把 `example.test` 换成团队控制且能实际收信的测试域名。每次注册都应使用新的地址和新的受忽略配置；不要把确认字段复制到个人账号配置中。runner 使用 Flutter SDK 自带的 `dart` 命令，不需要额外安装 Python。

这两项检查通过后，runner 检查命令、端口、路径并建立本机目录，再占用 `(SUPABASE_URL, AUTH_SPIKE_EMAIL)`。占用记录先刷新到磁盘，然后才能探测本机 driver 端口或启动 Flutter。后续 driver 失败、构建失败、进程中止、超时、5xx 或未知网络结果都不会释放该地址。正常重跑必须改用新的合成邮箱；确认字段不能覆盖占用记录。

两个并发 runner 会争用同一个操作系统文件锁。同一项目和邮箱最多只有一个 runner 能启动 Flutter。项目 URL 的 scheme 和 host 不区分大小写，默认端口和末尾 `/` 不产生新项目。邮箱在生成摘要前会移除首尾空白并转为 ASCII 小写；runner 入口仍只接受规范的小写合成地址。

ledger 是加锁的 append-only JSONL 文件。它只保存版本、UTC 占用时间和 project/email 的 SHA-256 摘要。完整记录追加后会先 flush，再允许 Flutter 启动。中途截断的记录会让后续运行失败关闭，不会被覆盖或静默修复。ledger 不保存原邮箱、项目 URL、password、OTP、publishable key 或 token。默认位置如下：

| 系统 | 默认 ledger |
| --- | --- |
| macOS | `~/Library/Application Support/tongxingzhe/auth-spike/spent-signup-emails-v1.json` |
| Linux | `$XDG_STATE_HOME/tongxingzhe/auth-spike/spent-signup-emails-v1.json`；未设置时使用 `~/.local/state/...` |
| Windows | `%LOCALAPPDATA%\tongxingzhe\auth-spike\spent-signup-emails-v1.json` |

自动测试可以用绝对路径 `AUTH_SPIKE_LEDGER_PATH` 隔离 ledger。Windows Git Bash 也接受 `/c/...` 形式的盘符绝对路径。改变该路径会建立新的保护域，不表示原地址可以复用。普通手工探针应使用默认位置，使同一电脑的多个 checkout 共用记录。

若 ledger 损坏、版本未知或不可写，runner 会失败关闭并保留原文件。不要为了重跑而删除或清空它。先保留备份并停止使用旧地址，再让维护者检查记录。删除远端 synthetic 用户也不会释放本机占用。

这套 ledger 只防止更新后、同一用户状态目录内、经此 runner 发起的重复尝试。它不能发现旧版本、其他电脑、其他系统用户、手工请求或另一 ledger 路径的历史。第一次使用新版本前，如果某个地址可能已经请求过，必须先换新地址。

Hosted Supabase Auth 可能对已确认账号返回与新账号相似的注册响应，客户端不能据此判断地址是否已经存在。runner 不调用 Admin API，也不保存 service-role key；“注册请求被接受”和“本机 ledger 首次占用”都不等于“地址此前不存在”。

## 6. 当前阻塞与决策

隔离 hosted Supabase project、测试邮箱和 Apple Development 签名环境已经就绪，macOS、Web 与 iOS 合同通过。Android、Windows、Linux 尚缺真实运行时验证；CI build 不能替代这些结果。本地 Supabase CLI／Docker 栈仍不可用，但不再阻塞 hosted project 的设备验证。

当前决策是：保留 Supabase 的条件首选和已编译 Adapter。Slice 0 只要求认证接缝、自动测试和证据矩阵诚实区分 pass／pending；Android、Windows、Linux 的真实运行时验证作为独立公开发布门槛并行推进，不再阻塞匿名领域切片。如果某个必需平台在合理修复后仍失败，再记录失败证据并按 ADR-0096 评估 Cognito，而不是把三个已通过平台扩张为六平台结论。整体能力状态见 [六平台能力证据矩阵](./six-platform-capability-matrix.md)。
