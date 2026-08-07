# 第 10 章：私人计划、当地提醒与每周周期

私人行动计划帮助使用者回顾自己的行动，不是组织考核。每个推广项目可以有一份只属于本人的计划。使用者可以不设周目标；启用后，App 只比较计划的接触场次数与当周有效接触场次数。

当前实现包含周目标、固定统计时区、周期起始日、版本历史、每日当地提醒、逐设备系统通知 opt-in、可选详细通知、本人 HTTP API、“今日”页卡片和只读离线副本。离线状态不能修改计划或同步提醒时间。Web、Linux 和 Windows 也不能在 App 关闭后可靠运行每日重复调度。

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

## 只读离线副本怎样工作

[`DriftPersonalPlanningCache`](../../lib/plans/personal_planning_cache.dart) 使用 App 已有的 Drift／SQLite 设置表保存计划和提醒快照。它不是第二套授权，也不是同步队列。每条 key 同时包含内部 app user、workspace 和项目 ID。一次请求开始时会捕获这个可信 scope；远端结果返回时若 scope 已改变，结果不会写入缓存。

只有远端明确返回 `networkUnavailable`，并且 `AppSession` 仍对同一 scope 保持 `ready`，gateway 才读取缓存。普通服务器拒绝、响应结构错误、配置缺失和 revision 冲突都不会回退。HTTP `401` 和 `403` 都视为授权失效，并清除该 scope 的计划与提醒缓存。登出、账号切换或会话授权失效会清除全部计划缓存。

远端成功返回“没有计划”或“没有提醒”也是一个有效快照。缓存会保存这个空值，因此断网后不会复活已经清除的旧数据。损坏、字段多余、字段缺失或非 UTC 的缓存会被删除，并按“无可用缓存”处理。

离线卡片显示“离线副本”和上次同步 UTC 时间。计划与同步提醒时间保持只读；本设备的系统通知开关和通知内容偏好仍可修改，因为它们本来就是逐设备设置。若计划快照已经跨过 `cycle_until_utc`，界面会把它标成上一周期，不再称为本周计划。详细系统通知遇到过期周期时会降级为通用文案。

这份缓存不包含推广对象资料，也不进入七十二小时的 `OfflinePiiVault`。它仍必须经过 `AppSession` 的可信 scope 门；不能因为数据不属于对象 PII 就绕过授权。

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

[`PrivateSessionDataGuard`](../../lib/app/private_session_data_guard.dart) 监听可信 App session。登出、启动时未登录、账号切换或明确授权失败后，它会取消待发的私人提醒并清除计划缓存。单纯网络中断不会取消仍有效的提醒，也不会删除只读缓存。当前项目的提醒或计划读取失去授权时，gateway 会清缓存，面板也会取消该项目的旧调度。App 长期关闭期间无法立即得知远端撤权；这是本地重复调度的残余限制。

## 紧凑屏幕和辅助技术怎样使用这些卡片

手机外壳以 900 逻辑像素为分界。低于该宽度时，[`CompactProductionHomeScaffold`](../../lib/screens/production_home_shell.dart) 使用底部四项导航；宽屏继续使用 NavigationRail。紧凑外壳保留完整 workspace 和项目名称作为语义标签。视觉标题可以在空间不足时显示省略号，但屏幕阅读器读到的上下文不截断。

提醒和计划卡片不使用固定高度。宽度不足或文字达到大字号时，图标与 heading 留在第一行，修改动作移到下一行。详细通知预览和计划编辑对话框的正文可以纵向滚动，因此 200% 文字不会把底部动作挤出可达区域。

键盘焦点遵循页面视觉顺序：

1. AppBar 项目操作；
2. 当前页面中的提醒和计划操作；
3. “记录接触”浮动按钮；
4. 底部“今日、接触、对象、分析”导航。

详细通知预览先聚焦“取消”，再聚焦“确认”。计划编辑依次经过周目标开关、条件目标输入、统计时区、周期起始日、取消和保存。对话框内的 Tab 与 Shift+Tab 闭环。Escape 只取消；关闭时间选择器或两个自定义对话框后，焦点返回原触发控件。关闭周目标后，已经隐藏的目标输入不再进入焦点路径。

语义层把“每日行动提醒”和“私人周计划”标成 heading。开关继续使用 Material 的单一合并语义节点。计划数、已记录数和差额各有一个节点，不重复朗读。载入与保存进度有具体名称，异步错误和表单校验错误使用 live region。离线说明同时包含“离线副本”、上次同步时间和只读状态，不依赖灰色或禁用外观传达含义。

Widget 测试固定检查 `320 × 568`、`360 × 640` 和 `320 × 568` 配合 200% 文字三种状态。测试会发送真实 Tab、Shift+Tab、Enter、Space 和 Escape 键盘事件，并读取 Flutter semantics tree。这些测试在本机 Flutter 测试渲染器中运行，不需要模拟器、真机或 Docker。它们能证明 Widget 合同，不能代替 VoiceOver、TalkBack、NVDA 和六平台真机验收。

## 怎样运行这条切片的测试

先运行快速测试：

```bash
flutter test --no-pub \
  test/plans/drift_personal_planning_cache_test.dart \
  test/features/plans/personal_action_plan_panel_test.dart \
  test/features/plans/personal_action_plan_panel_accessibility_test.dart \
  test/plans/http_personal_action_plan_gateway_test.dart \
  test/features/reminders/personal_action_reminder_panel_test.dart \
  test/features/reminders/personal_action_reminder_panel_accessibility_test.dart \
  test/features/home/production_home_shell_accessibility_test.dart \
  test/app/private_session_data_guard_test.dart \
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

离线缓存本身使用测试进程中的 Drift／SQLite，不需要 Docker。Docker 套件验证的是 Backend 的 PostgreSQL schema、权限、周期计算、提醒版本和备份恢复。两组测试不能互相代替。

## 当前边界

本章不能作为以下能力已完成的证据：

- 断网修改计划或同步提醒时间；
- 多设备离线合并计划；
- 记录每次系统通知的实际触发时区；
- App 长期未打开时，旅行后的首个通知立即改用新时区；
- Web、Linux 或 Windows 的 App 关闭后重复提醒；
- 六个平台的系统通知真机权限与实际触发验收。

这些事项仍属于 Slice 5。实现时必须继续保持计划统计时区与设备提醒当地时间分离。
