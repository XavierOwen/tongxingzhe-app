# 六平台能力证据矩阵

状态：**持续更新；截至 2026-08-06，只确认六平台 build 和 iOS／Web／macOS 认证运行时证据。离线 PII 尚无平台运行时通过结论。**

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
| Android | CI pass；本机 debug APK pass | 待测；安全存储待测 | 只有共享 migration 自动测试，平台持久化待测 | 共享自动测试通过；设备重启恢复待测 | 实现和启动探针已接线；真机读写、重启、到期和撤权待测 | 未验收 | build only |
| iOS | CI pass；签名真机安装 pass | pass；Keychain、OTP、刷新、跨进程恢复均有证据 | 只有共享 migration 自动测试，平台持久化待测 | 共享自动测试通过；设备重启恢复待测 | 实现和启动探针已接线；离线 PII 专用流程待测 | 未验收 | auth runtime pass |
| Web | CI／release build pass | pass；localhost 安全存储、OTP、刷新、跨浏览器进程恢复均有证据 | Web 持久化、刷新、崩溃和双标签待测 | 共享自动测试通过；浏览器持久化恢复待测 | 当前禁用；durable database 仍为 `runtimeProbeRequired`，不会装配 PII vault | 未验收 | auth runtime pass |
| macOS | CI pass；签名 debug pass | pass；Keychain、OTP、刷新、跨进程恢复均有证据 | 只有共享 migration 自动测试，平台持久化待测 | 共享自动测试通过；设备重启恢复待测 | 实现和启动探针已接线；离线 PII 专用流程待测 | 未验收 | auth runtime pass |
| Windows | CI pass | 待测；安全存储待测 | 只有共享 migration 自动测试，平台持久化待测 | 共享自动测试通过；设备重启恢复待测 | 实现和启动探针已接线；Credential Store 运行时待测 | 未验收 | build only |
| Linux | CI pass | 待测；libsecret／keyring 待测 | 只有共享 migration 自动测试，平台持久化待测 | 共享自动测试通过；设备重启恢复待测 | 实现和启动探针已接线；libsecret／keyring 运行时待测 | 未验收 | build only |

认证逐步证据和测试环境见 [Supabase Auth 六平台 Spike](./supabase-auth-six-platform.md)。离线对象资料的信任边界和残余风险见[威胁模型](../security/offline-pii-threat-model.md)。共享 Drift schema 和 migration 测试证明代码路径可重建旧库，但在每个平台完成关闭进程、重新打开和持久化探针前，不能把“测试通过”扩大为平台 runtime 通过。

## 公开发布前必须补齐

- Android、Windows、Linux 的注册、OTP、恢复、刷新、登出和跨进程安全 session 恢复；
- 六平台本地数据库初始化、migration、进程重启后的持久化和失败恢复；
- 六平台断网记录、Outbox 租约恢复、重复请求和同步恢复；
- 原生五平台的离线 PII 写入、跨进程只读恢复、到期、撤权和清除失败重试；
- Web durable database 探针和隔离策略；通过前保持离线 PII 禁用；
- 稳定主导航、关键宽度、键盘／鼠标／触摸和可访问状态；
- 每项证据的 App commit、设备或浏览器、OS、日期、测试数据类型和 pass／pending／failed 结论。

在这些项目完成前，内部 Alpha 只能使用测试资料，并按平台显示真实能力状态；“六平台共用代码”不能写成“六平台已经可发布”。
