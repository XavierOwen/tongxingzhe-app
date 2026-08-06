# 第 10 章：私人计划、当地提醒与每周周期

私人行动计划帮助使用者回顾自己的行动，不是组织考核。每个推广项目可以有一份只属于本人的计划。使用者可以不设周目标；启用后，App 只比较计划的接触场次数与当周有效接触场次数。

当前实现包含周目标、固定统计时区、周期起始日、版本历史、每日当地提醒、逐设备系统通知 opt-in、可选详细通知、本人 HTTP API 和“今日”页卡片。计划与提醒仍未加入离线缓存。Web、Linux 和 Windows 也不能在 App 关闭后可靠运行每日重复调度。

## 先分清三种时间

| 时间 | 用途 | 是否随旅行变化 |
| --- | --- | --- |
| 接触实际发生 UTC 时刻 | 决定一条接触属于哪个周期 | 不变 |
| 计划统计时区 | 把 UTC 时刻划入当地七天周期 | 固定到计划版本 |
| 设备当地提醒时间 | 决定某台设备几点提醒 | 会随设备所在地变化 |

统计时区使用 IANA 名称，例如 `America/Chicago` 或 `Asia/Shanghai`。`CST` 不是合格输入，因为它可能表示不同地区。旅行不会自动修改计划统计时区。

## 周期边界不能写成七乘二十四小时

使用者选择星期一至星期日中的任意一天作为周期起点。PostgreSQL 按以下顺序计算：

1. 把服务端参考时刻转换到计划统计时区；
2. 在当地日历中找到最近的周期起始日；
3. 取该当地日期的午夜作为起点；
4. 在当地日历中加七天，再转换回 UTC 作为终点。

这个顺序会正确处理夏令时。芝加哥春季切换所在周是 167 小时，秋季切换所在周是 169 小时。若直接对 UTC 时刻加 168 小时，周期终点会偏离当地午夜。

查询使用半开区间 `[cycle_start_utc, cycle_until_utc)`：起点计入，终点不计入。相邻周期因此不会重复计算同一条接触。

## 哪些事实计入周目标

计划进度查询只读取同时满足以下条件的接触：

- 创建者是当前用户；
- workspace 和项目与可信当前上下文一致；
- 当前生命周期是 `active`；
- 实际发生时间在周期半开区间内；
- 实际发生时间早于本次查询的 `as_of_utc`。

草稿、接触尝试、已作废接触、触达人数、兴趣、对象阶段和推广结果都不计入。延迟补录按实际发生时间归期；更正发生时间后，当前投影会进入更正后的周期。版本历史仍保留原值和操作者。

## 首次设置和后续修改为何不同

首次设置立即采用所选时区和起始日所在的当前自然周，因此使用者能看到本周已经记录的接触。此后修改周目标、统计时区或起始日时，新版本只从新设置定义的下一个周期边界生效。

每份计划有一个当前版本和至多一个待生效版本。待生效版本存在时，当前切片暂不接受第二次修改。这条限制避免多个未来版本产生难以解释的重叠；以后若产品需要编辑待生效版本，应通过新的追加式“取代”事件实现，不能改写旧版本。

## PostgreSQL 如何保护隐私和历史

[`0021_personal_action_plans.sql`](../../backend/database/migrations/0021_personal_action_plans.sql) 建立两张表：

- `personal_action_plans` 保存本人、workspace、项目和最新 revision；
- `personal_action_plan_versions` 保存目标、统计时区、起始日、生效时间和 mutation ID。

版本表的触发器拒绝 `UPDATE` 和 `DELETE`。Backend runtime role 没有两张表的直接读写权限，只能执行：

- `read_personal_action_plan`；
- `save_personal_action_plan`。

两个函数都要求 trusted app user、workspace 和项目组成当前个人空间。函数不提供按 workspace 或组织列出计划的入口。Backend HTTP 也只有本人当前上下文的 `GET` 和 `PUT /v1/personal-action-plan`，没有管理员汇总路由。

保存使用 expected revision 防止另一台设备静默覆盖，并用 mutation ID 安全重试。首次并发创建还取得同一用户项目 scope 的 transaction advisory lock。

## Flutter 如何连接页面与 Backend

[`PersonalActionPlanGateway`](../../lib/plans/personal_action_plan.dart) 是 Flutter 业务层看到的唯一远端接口。[`HttpPersonalActionPlanGateway`](../../lib/plans/http_personal_action_plan_gateway.dart) 只发送计划字段，不发送 app user、workspace 或项目 ID；Backend 从已验证 identity 和当前上下文取得这些可信值。

[`PersonalActionPlanPanel`](../../lib/features/plans/personal_action_plan_panel.dart) 放在“今日”页。它显示：

- 本周计划场次；
- 已记录场次；
- 剩余差额或已经达到计划；
- 固定统计时区和周期起始日；
- 待生效版本的 UTC 边界。

文案不要求解释未完成原因，不产生连续打卡、排名或管理员通知。没有周目标时，页面仍保留计划入口，但不伪造差额。

## 提醒时间与设备开关为何分开

[`0022_personal_action_reminders.sql`](../../backend/database/migrations/0022_personal_action_reminders.sql) 保存一个可选的每日当地分钟。`0` 表示 `00:00`，`1439` 表示 `23:59`。提醒可在没有周目标时单独使用。提醒版本只追加，并使用 expected revision 与 mutation ID 处理多设备更新和安全重试。

Backend 只同步提醒钟点。它不接收设备 ID、通知权限或 UTC 触发时刻。Flutter 的 [`DriftDeviceReminderPreferenceStore`](../../lib/reminders/drift_device_reminder_preference_store.dart) 把 opt-in 写入本机已有的非敏感设置表。设置键同时包含设备、用户、workspace 和项目。另一台设备或另一个项目没有对应行时，默认值是关闭。

用户在本设备打开开关后，App 才请求系统权限。权限拒绝或调度失败时，设置不会写成已启用。用户关闭开关时，App 先取消该项目的通知，再保存关闭状态。不同项目使用稳定且不同的通知 ID，不会互相覆盖。

系统通知默认只使用通用标题、通用行动文案和带类型标记的 `today` payload。调度接口不接收推广对象资料。

本设备已启用通知后，用户可以选择同时显示项目名与个人周进度。App 先读取本人当前计划，并显示最终标题和正文预览；用户再次确认后才替换系统调度并保存本机选择。没有周目标时，详细通知只说明未设置目标，不伪造 `0 / 0` 或差额。进度只读 `PersonalActionPlanSnapshot.current` 和服务端计算结果，不提前采用 pending 版本，也不按设备提醒时区重算。

详细选择保存在独立的 `personal-reminder-content-v1` 设置键。原 `personal-reminder-v1` 仍只保存系统通知开关。旧版 App 因此仍能读取开关，并会用同一通知 ID 把详细文案替换为通用文案。损坏或缺失的详细设置也按通用模式读取。

详细正文明确写“上次安排提醒时”。重复通知保存的是安排时的文字，不是实时计数器。App 回到前台时会重新读取提醒和计划，再更新通知。接触修订、作废、跨周或计划变更后，用户在 App 内看到的当前值仍以服务端页面为准。

## 当地提醒怎样处理旅行与平台差异

[`FlutterReminderNotificationScheduler`](../../lib/reminders/flutter_reminder_notification_scheduler.dart) 每次安排通知前读取设备当前 IANA 时区，再在该地区的当地日历中计算下一次钟点。App 恢复到前台时会重新核对已启用提醒。因此，从芝加哥到上海后，`19:00` 仍表示上海当地 `19:00`，不是原来的 UTC 时刻。

当前平台边界如下：

| 平台 | App 关闭后的每日重复通知 |
| --- | --- |
| Android | 已接 Adapter；使用不精确的 idle-safe 调度，不申请 exact alarm |
| iOS | 已接 Adapter；只在用户打开本设备开关后申请权限 |
| macOS | 已接 Adapter；只在用户打开本设备开关后申请权限 |
| Web | 浏览器没有后台 scheduled/repeating notification，明确降级 |
| Linux | 桌面通知协议没有 scheduler API，明确降级 |
| Windows | 当前插件不支持重复通知，明确降级 |

“已接 Adapter”不等于真机发布验收已经完成。Android 厂商后台限制、Apple 权限状态和时区旅行仍需真机矩阵验证。

[`ReminderNotificationPrivacyGuard`](../../lib/app/reminder_notification_privacy_guard.dart) 监听可信 App session。登出、启动时未登录或 session 失败后，它会取消带私人提醒 payload 的待发通知。当前项目的提醒或计划读取失去授权时，面板也会取消该项目的旧调度。App 长期关闭期间无法立即得知远端撤权；这是本地重复调度的残余限制。

## 怎样运行这条切片的测试

先运行快速测试：

```bash
flutter test --no-pub \
  test/features/plans/personal_action_plan_panel_test.dart \
  test/plans/http_personal_action_plan_gateway_test.dart \
  test/features/reminders/personal_action_reminder_panel_test.dart \
  test/app/reminder_notification_privacy_guard_test.dart \
  test/reminders

npm --prefix backend/server run build
node --test \
  backend/server/dist/test/personal-action-plans.test.js \
  backend/server/dist/test/personal-action-reminders.test.js
```

再运行真实 PostgreSQL 16 套件：

```bash
./tool/run_postgres_tests_in_docker.sh
```

没有用过 Docker 时，从[第 9 章](09-local-docker-and-ci-testing.md)第 2 节开始。脚本会自己建立临时数据库、运行 `0021` 和 `0022` 的 check 与 fixture、执行备份恢复，再删除容器。不要手工连接 production 验证这条功能。

## 当前边界

本章不能作为以下能力已完成的证据：

- 断网查看或修改计划；
- 多设备离线合并计划；
- 记录每次系统通知的实际触发时区；
- App 长期未打开时，旅行后的首个通知立即改用新时区；
- Web、Linux 或 Windows 的 App 关闭后重复提醒；
- 六个平台的系统通知真机权限与实际触发验收。

这些事项仍属于 Slice 5。实现时必须继续保持计划统计时区与设备提醒当地时间分离。
