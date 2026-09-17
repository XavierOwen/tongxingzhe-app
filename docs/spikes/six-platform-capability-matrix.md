# 六平台能力证据矩阵

状态：**持续更新；截至 2026-09-17，保留六平台 build 和已有 iOS／Web／macOS／Windows 认证运行时证据，新增 Android 模拟器离线 PII 预检。离线 PII 尚无平台运行时通过结论。**

适用需求：`GOAL-006`、`AUTH-004`、`PLATFORM-001` 至 `PLATFORM-007`、`TEST-006`

## 证据层级

本矩阵把四个容易混淆的结论分开：

1. **实现存在**：仓库中已有 Adapter 或代码路径；
2. **build 通过**：目标平台可编译，但不证明设备服务可用；
3. **runtime 通过**：在记录过环境的真实进程或设备上完成指定流程；
4. **release evidence 完整**：登录、本地持久化、离线恢复、同步恢复和关键 UI 都通过发布门槛。

`PlatformCapabilities` 只表达当前设备本次运行的探针结果。它不能替代本矩阵，也不能因为操作系统理论支持某项功能就把 release evidence 标为通过。

## 当前矩阵

| 平台 | Build | Auth／session runtime | 本地数据库／migration runtime | 匿名离线／同步恢复 | 加密离线 PII | 现代响应式 UI | 当前结论 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Android | CI pass；本机 debug APK pass | 待测；Auth session 安全存储待测 | 共享 migration 自动测试；模拟器 PII 探针跨进程预检，业务持久化待测 | 共享自动测试通过；设备重启恢复待测 | 模拟器九项预检 `simulated`；真机、真实授权／撤权和实际期限验收待测 | 未验收 | build only；PII simulated preflight |
| iOS | CI pass；签名真机安装 pass | pass；Keychain、OTP、刷新、跨进程恢复均有证据 | 只有共享 migration 自动测试，平台持久化待测 | 共享自动测试通过；设备重启恢复待测 | 实现和启动探针已接线；离线 PII 专用流程待测 | 未验收 | auth runtime pass |
| Web | CI／release build pass | pass；localhost 安全存储、OTP、刷新、跨浏览器进程恢复均有证据 | Web 持久化、刷新、崩溃和双标签待测 | 共享自动测试通过；浏览器持久化恢复待测 | 当前禁用；durable database 仍为 `runtimeProbeRequired`，不会装配 PII vault | 未验收 | auth runtime pass |
| macOS | CI pass；签名 debug pass | pass；Keychain、OTP、刷新、跨进程恢复均有证据 | 只有共享 migration 自动测试，平台持久化待测 | 共享自动测试通过；设备重启恢复待测 | 实现和启动探针已接线；离线 PII 专用流程待测 | 未验收 | auth runtime pass |
| Windows | CI pass；Windows 11 25H2／Flutter 3.44.9 本机 debug pass | pass；Windows 安全存储、注册／恢复 OTP、刷新、改密码、跨独立进程 session 恢复和登出均有证据 | 只有共享 migration 自动测试，平台持久化待测 | 共享自动测试通过；设备重启恢复待测 | 实现和启动探针已接线；Windows 安全存储基础运行时 pass，离线 PII 专用流程待测 | 未验收 | auth runtime pass |
| Linux | CI pass | 待测；libsecret／keyring 待测 | 只有共享 migration 自动测试，平台持久化待测 | 共享自动测试通过；设备重启恢复待测 | 实现和启动探针已接线；libsecret／keyring 运行时待测 | 未验收 | build only |

认证逐步证据和测试环境见 [Supabase Auth 六平台 Spike](./supabase-auth-six-platform.md)。离线对象资料的信任边界和残余风险见[威胁模型](../security/offline-pii-threat-model.md)。共享 Drift schema 和 migration 测试证明代码路径可重建旧库，但在每个平台完成关闭进程、重新打开和持久化探针前，不能把“测试通过”扩大为平台 runtime 通过。

六平台离线 PII 的人工证据由 [Issue #161](https://github.com/XavierOwen/tongxingzhe-app/issues/161) 统一跟踪。原生五平台必须验证真实安全存储、跨进程、七十二小时、撤权和删除失败。Web 当前应证明禁用和失败关闭，不能登记 PII runtime pass。

2026-08-20 在 `1b370d9` 复查 macOS：51 项离线 PII 定向自动测试和 unsigned build 通过；Development 构建因 Xcode 没有登录开发账号和匹配的 Mac App Development profile 而停止。本次没有运行 Keychain PII 流程，因此 macOS 离线 PII 仍为待测。

### 2026-09-17 Android 模拟器离线 PII 预检

使用现有独立入口 [`offline_pii_runtime_probe.dart`](../../tool/offline_pii_runtime_probe.dart)，不连接 Backend，也不使用真实账号或对象。代码版本为 `f98d07452b598e364d055c2d41940b13d82f8252`，轮次为 `probe-20260917-android-01`；环境为 Android 16／API 36、ARM64 AVD、Flutter 3.44.2、debug APK，签名证据分类为 `simulator`。

生产 `OfflinePiiVault`、平台安全存储 Adapter 和本地 Drift 数据库实际运行。三个独立 OS 进程的 PID 分别为 2206、6765、7245；每次 `am force-stop` 后确认旧进程不存在，再启动新进程，不使用 hot restart。第 2、3 进程开启飞行模式且 active default network 为 `NONE`；第 1 进程的写入不宣称在断网下执行。

三个导出文件保留探针原始 allowlist JSON，11 条事件覆盖九种 scenario；所有事件为 `pass`／`simulated`：

- [第 1 进程](./evidence/offline-pii-android-emulator-20260917/session-1.json)：平台门禁、synthetic 快照写入与读回。
- [第 2 进程](./evidence/offline-pii-android-emulator-20260917/session-2.json)：平台门禁、跨进程恢复不续期、到期前一分钟、七十二小时整锁定、模拟撤权删除、注入一次删除失败后持久锁定。
- [第 3 进程](./evidence/offline-pii-android-emulator-20260917/session-3.json)：平台门禁、跨进程重试删除后仍锁定、清理五个 synthetic scope。

首次写入与恢复的授权时间均为 `2026-09-17T16:38:34.299228Z`，到期时间均为 `2026-09-20T16:38:34.299228Z`。期限边界通过回填 synthetic 授权时间检查，没有修改系统时钟，也没有实际等待七十二小时。撤权由探针模拟，删除失败由 Adapter 包装层注入，不是服务器撤权或系统安全存储故障证明。

本次只证明上述模拟器代码路径和指定时间字段，不声称逐字段验证全部 PII 正文、硬件 Keystore 防护、系统备份／重装行为、真实 Auth、生产服务或真人可访问性。清理不调用全量安全存储删除；普通 Drift 保留不含 PII 的 fail-closed 锁。#161 的真机／正式签名验收与父 Issue #6 均保持未完成。

## 公开发布前必须补齐

- Android、Linux 的注册、OTP、恢复、刷新、登出和跨进程安全 session 恢复；
- 六平台本地数据库初始化、migration、进程重启后的持久化和失败恢复；
- 六平台断网记录、Outbox 租约恢复、重复请求和同步恢复；
- 原生五平台的离线 PII 写入、跨进程只读恢复、到期、撤权和清除失败重试；
- Web durable database 探针和隔离策略；通过前保持离线 PII 禁用；
- 稳定主导航、关键宽度、键盘／鼠标／触摸和可访问状态；
- 每项证据的 App commit、设备或浏览器、OS、日期、测试数据类型和 pass／pending／failed 结论。

在这些项目完成前，内部 Alpha 只能使用测试资料，并按平台显示真实能力状态；“六平台共用代码”不能写成“六平台已经可发布”。
