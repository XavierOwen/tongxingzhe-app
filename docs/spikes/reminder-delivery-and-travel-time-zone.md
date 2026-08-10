# 提醒送达与旅行时区真机 Spike

本 Spike 对应 Issue #50。它验证 Android、iOS 和 macOS 的系统通知行为，并为 Slice 5 提供可复查证据。

## 先分清三类证据

| 事件 | 探针怎样取得 | 能证明什么 | 不能证明什么 |
| --- | --- | --- | --- |
| `scheduled` | 调度 API 成功返回 | App 在某时区安排了一个计划钟点 | 操作系统后来显示了通知 |
| `observed-active` | App 查询通知中心并找到测试 ID | 查询时通知仍在通知中心 | 首次显示时间和首次显示时区 |
| `interacted` | 用户点击通知或通过通知启动 App | 用户交互时间和交互时区 | 系统首次显示时间和时区 |

探针没有 `delivered` 事件。当前插件没有跨三个平台的后台送达回调。测试人员必须从设备时钟、通知横幅或通知中心直接观察首次显示，并把结果写入本页的证据矩阵。

代码审查还发现，当前重复调度把安排时区交给平台。Android 保存 `timeZoneName`，Apple 平台把时区写入日历触发器。这说明旅行后的首个提醒存在风险，但源代码审查不能代替真机结果。

## 准备设备

从仓库根目录运行：

```bash
flutter doctor -v
flutter devices
git status --short
git rev-parse --short HEAD
```

`flutter doctor -v` 显示 Flutter 和平台工具状态。`flutter devices` 列出可用设备及其 ID。`git status --short` 必须没有输出；否则 commit 不能代表实际运行代码。最后一条命令输出本次证据使用的 commit，例如 `214943d`。

Android 和 iOS 的终止场景必须使用真机。模拟器可以先检查页面和权限流程，但不能作为发布证据。设备必须解锁，并允许开发电脑安装调试 App。

Apple 设备还需要 Xcode 中的有效开发账号和匹配 bundle ID 的 Development 描述文件。只打开 iPhone Developer Mode 或只在钥匙串保存证书，仍不能安装测试 App。

这项测试不需要 Docker、Backend 或测试账号。Docker 只能验证 PostgreSQL 和服务端合同，不能模拟系统通知中心、设备时区或 App 进程状态。

## 启动探针

把 `<device-id>` 和 `<commit>` 替换为上一步的实际值：

```bash
flutter run \
  -t tool/reminder_delivery_probe.dart \
  -d <device-id> \
  --dart-define=REMINDER_PROBE_COMMIT=<commit>
```

macOS 的设备 ID 通常是 `macos`。iPhone 和 Android 的 ID 以 `flutter devices` 输出为准，不要照抄示例值。

探针先显示旅行目标 IANA 时区，再显示四个操作：安排提醒、检查通知中心、取消提醒和复制证据。通知标题和正文固定为通用文案。探针不连接服务端，也不读取项目、进度或推广对象资料。

测试通知的 payload 保存原安排 UTC、当地钟点、时区和通知 ID。App 被终止后，点击通知可以恢复 `scheduled` 事件。payload 不含账号、项目、进度或推广对象资料。

## 运行基础场景

每个场景开始前，先取消上一个测试提醒。随后重新安排提醒，并保存新的 `scheduled` 事件。

### 前台

1. 保持探针页面打开。
2. 点击“安排约 3 分钟后的每日测试提醒”。
3. 记录通知首次出现时的设备时间，并截图保留设备时钟和通知。
4. 点击通知，再复制证据 JSON。

前台结果应包含 `scheduled` 和 `interacted`。如果平台显示横幅，截图才是首次显示时间的证据。

### 后台

1. 安排提醒。
2. 返回主屏幕，不要从最近任务中移除 App。
3. 记录通知首次出现时的设备时间和截图。
4. 点击通知，再复制证据 JSON。

### 已终止

1. 安排提醒。
2. Android 先返回主屏幕，再按下列命令记录 PID、终止后台进程并复查：

   ```bash
   adb shell pidof com.tongxingzhe.app
   adb shell am kill com.tongxingzhe.app
   adb shell pidof com.tongxingzhe.app
   ```

3. 第一条命令应显示 PID，最后一条命令应没有输出。只从最近任务移除 App 不能证明进程已终止。
4. iOS 从 App 切换器移除 App。macOS 关闭窗口后，在“活动监视器”确认同行者进程消失。
5. 不要在 Android 设置中点“强行停止”，也不要运行 `adb shell am force-stop`。force-stop 会进入另一种系统状态，并阻止正常启动前的后台工作。
6. 记录通知首次出现时的设备时间和截图。
7. 点击通知启动 App，再复制证据 JSON。

终止场景重新打开后，JSON 应同时包含恢复的 `scheduled` 和新的 `interacted`。`interacted.launchedApp` 应为 `true`。该字段仍只表示通知启动了 App。

### 权限拒绝

先在系统设置中关闭同行者的通知权限，再启动探针并点击安排。页面应显示权限未授予，JSON 不应新增 `scheduled` 事件。

若要重新显示首次授权弹窗，可卸载调试 App 后重新安装。卸载会删除这台设备上的本机调试数据。

## 运行旅行时区场景

1. 记录设备原时区，例如 `America/Chicago`。
2. 在探针中填写比原时区向西至少一小时的目标时区，例如芝加哥选择 `America/Denver`，上海选择 `Asia/Bangkok`。
3. 安排提醒，并复制包含 `scheduled` 的 JSON。记录 `scheduledForUtc` 和 `expectedInComparisonZoneUtc`。
4. 立即把设备时区改为 JSON 中的 `comparisonTimeZone`。
5. 不要重新打开 App，也不要重新安排提醒。
6. 分别在 `scheduledForUtc` 和 `expectedInComparisonZoneUtc` 前后各 15 分钟观察通知，并记录设备当地时间。Android 使用与产品相同的不精确调度，因此不要只观察计划分钟。
7. 点击通知，复制最终 JSON，并恢复设备原时区。

如果通知在 `scheduledForUtc` 附近出现，但设备当地钟点不等于 `scheduledLocalTime`，则旅行首个提醒仍绑定旧时区。如果通知在 `expectedInComparisonZoneUtc` 附近出现，并且当地钟点相同，则符合当地钟点合同。两个窗口都没有出现时，只能记录本次未观察到，不能推断通知永远不会出现。

## 提交证据

每条证据必须包含设备型号、OS 版本、commit、场景、人工观察时间、截图位置和探针 JSON。隐去设备名称中的个人姓名。

状态只使用 `pass`、`failed` 或 `pending`：

| 平台 | 设备与 OS | 前台 | 后台 | 已终止 | 权限拒绝 | 旅行换时区 | 证据 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Android | Android Studio Medium Phone AVD，Android 16 API 36（模拟器） | pending | pending | pending | pending | pending | 见 2026-08-10 诊断记录；模拟器不计发布证据 |
| iOS | iPhone 14 Pro，iOS 26.5.2（签名阻塞） | pending | pending | pending | pending | pending | 见 2026-08-10 诊断记录 |
| macOS | Apple silicon Mac，macOS 26.5.2（ad-hoc 诊断） | pending | pending | pending | pending | pending | 见 2026-08-10 诊断记录；缺少 Development 描述文件 |

`pass` 表示观察结果符合当前合同，并且有截图和 JSON。`failed` 表示有可复现的合同偏差。没有设备或没有完成场景时保留 `pending`。

### 2026-08-10 诊断记录

以下记录说明本次实际运行结果。它们没有满足 `pass` 的设备、签名和附件条件，因此证据矩阵仍为 `pending`。

#### Android 模拟器

运行环境为 Medium Phone AVD、Android 16 API 36、系统构建 `BP22.250325.006`。探针对应 commit `eb8a09f`。

- 首次授权后，探针安排 `08:56` 通知。系统在 `08:56:27` 记录通知发布，探针随后记录 `observed-active`，并在 `08:58:04` 记录 `interacted`。
- 后台场景安排 `08:59` 通知。通知在 `09:00:34` 仍处于活跃状态，点击事件记录于 `09:00:55`，`launchedApp` 为 `false`。
- 终止场景在 `09:01:51` 记录终止前 PID `3911`，终止后 PID 无输出。通知在 `09:05:52` 处于活跃状态。点击后恢复的 JSON 包含原 `scheduled` 事件和 `launchedApp: true` 的 `interacted` 事件。
- 权限拒绝后，页面显示“系统没有授予通知权限”，JSON 的 `events` 为空。
- 旅行换时区未执行。模拟器结果不能替代 Android 真机终止和旅行证据。

通知截图只保存在本次本机临时目录，尚未形成可提交附件。系统发布日志也不能单独证明用户首次看到通知的时间。

#### iOS 真机

Flutter 识别到已连接的 iPhone 14 Pro，系统版本为 iOS 26.5.2。设备已打开 Developer Mode。

指定真机的第一次 Xcode 构建在描述文件评估阶段触发 `EXC_BAD_ACCESS`。改用通用 iOS 目标后，Xcode 给出稳定错误：当前团队没有已登录账号，`com.tongxingzhe.app` 也没有可用的 iOS Development 描述文件。本次没有安装探针，全部 iOS 场景保持 `pending`。

#### macOS 本机

本机系统为 macOS 26.5.2。常规 Development 构建因缺少可用的 Mac Development 签名和描述文件而停止。

为检查运行路径，本次另建 ad-hoc 签名诊断包。该包通过本机代码签名校验，但没有 `TeamIdentifier`，不能作为发布证据。诊断包对应 commit `41b28c9`。

- 首次安排的通知计划于 `09:16` 显示。用户点击后，探针在 `09:16:02` 记录 `interacted`，`launchedApp` 为 `false`。系统同时显示“应用无法启动”。
- LaunchServices 当时登记了多份相同 bundle ID 的旧调试包，其中三份未通过代码签名校验。取消这些失效登记后，后台复测在 `09:23:07` 再次记录 `interacted`。系统提示是否消失仍需人工确认。
- 前台、后台、终止、权限拒绝和旅行场景都没有取得 Development 签名下的完整截图与 JSON，因此全部保持 `pending`。

本次 macOS 运行还暴露了一个探针缺陷。Darwin 插件在初始化时延后权限请求会返回 `false`，旧代码将它误判为初始化失败。commit `41b28c9` 只在 iOS 和 macOS 接受这个预期返回值，并保留 Android 的失败关闭行为。回归测试覆盖该路径。

## Spike 的退出条件

三个平台取得证据后，再选择下一项实现：

- 若平台能提供可靠送达事件，设计最小本机历史，并明确保留期限。
- 若只有部分平台可观察送达，ADR-0049 必须写明平台差异，不能伪造统一历史。
- 若重复任务在旅行后仍绑定旧时区，单独设计原生调度或系统时区变化后的重排。

本 Spike 不交付离线修改、生产历史表或六平台发布验收。
