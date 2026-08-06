# 同行者 App 零基础学习路线

> **状态：当前 legacy demo 的代码阅读指南。**它帮助理解现有 `AppController`、Drift 表和界面，不代表现代化目标架构。正式产品实施后，将由 [产品与技术 Spec](./PRODUCT_SPEC.md) 约束，并逐步由 `docs/manual/README.md` 入口下的正式代码开发说明书取代。

这份文档写给一个很有生活经验、但刚开始学编程的人。目标不是一天内变成职业工程师，而是先把这个项目的“地图”装进脑子里：知道先看哪里、看到代码时该问什么问题、哪些基础知识要边走边补。

你可以把这个 App 理解成一个小型办公室：

- 前台：登录、注册、忘记密码。
- 记录员：快速记录推广接触。
- 档案柜：本地 SQLite 数据库。
- 经理办公室：管理员校正和统计。
- 白板：图表页。
- 翻译员：中英文界面。
- 总管：`AppController`，负责把前面这些人串起来。

## 0. 先别急着读所有文件

Flutter 项目里有很多平台文件，例如 `ios/`、`android/`、`macos/`、`windows/`。这些是为了让同一套 Dart/Flutter 代码跑在不同设备上。初学时不要从它们开始。

第一周只看这几个地方：

1. `pubspec.yaml`
2. `lib/main.dart`
3. `lib/l10n/app_strings.dart`
4. `lib/screens/auth_screen.dart`
5. `lib/screens/home_shell.dart`
6. `lib/app/app_controller.dart`
7. `lib/models/conversation_record.dart`
8. `lib/models/app_user.dart`
9. `lib/data/local_database.dart`
10. `test/widget_test.dart`

暂时不要读 `lib/data/local_database.g.dart`。这个文件是 Drift 自动生成的，像机器打印出来的说明书，很长，不适合入门阅读。

如果你的目标是参与当前正式产品开发，不要沿着这份 legacy demo 路线直接改代码。先读[正式开发说明书入口](manual/README.md)，再按[本机、Docker 与 CI 测试指南](manual/09-local-docker-and-ci-testing.md)准备环境。后者从 image、container、database 三个基本概念开始，不要求你用过 Docker。

## 1. 第一天：先学会把项目跑起来

打开终端，进入项目目录：

```bash
cd "/Users/xavieredith/Documents/Github/同行者APP"
```

拉依赖：

```bash
flutter pub get
```

跑网页版本：

```bash
flutter run -d web-server --web-hostname 127.0.0.1 --web-port 54731
```

然后打开：

```text
http://127.0.0.1:54731
```

跑测试：

```bash
dart analyze
flutter test
```

当前正式分支还包含 Backend 与 PostgreSQL。第一次准备完整测试环境时，继续执行：

```bash
npm --prefix backend/server ci
docker info
./tool/run_postgres_tests_in_docker.sh
```

最后一条命令会自己建立并删除临时 PostgreSQL 容器，不连接 production，也不要求本机安装 PostgreSQL。若 `docker info` 报 daemon 不可用，先启动 Docker Desktop。完整解释和失败排查见[第 9 章测试指南](manual/09-local-docker-and-ci-testing.md)。

你现在只要记住三句话：

- `flutter pub get`：把别人写好的工具包拿回来。
- `flutter run`：把 App 跑起来。
- `flutter test`：让机器帮你检查有没有把东西弄坏。

## 2. 第二天：从 `pubspec.yaml` 看“配料表”

先打开 `pubspec.yaml`。

它像食品包装上的配料表，告诉 Flutter：

- 项目名字：`tongxingzhe_app`
- 版本号：`1.0.0+1`
- 用了哪些第三方包

几个重要依赖：

- `flutter_localizations`：让 App 支持中文、英文等本地化。
- `geolocator`：获取定位。
- `fl_chart`：画图表。
- `crypto`：做 MD5 演示登录。
- `drift`、`drift_flutter`：用 Dart 操作 SQLite 数据库。
- `path_provider`：帮 App 找到可以保存本地文件的位置。

基础知识插一句：

依赖包就是“别人已经做好的零件”。写 App 不是什么都从铁矿石开始炼，专业开发本来就是把可靠零件组装起来，再把自己的业务逻辑写好。

## 3. 第三天：从 `main.dart` 看 App 怎么启动

看 `lib/main.dart`。

你会看到：

```dart
void main() {
  runApp(const TongxingzheApp());
}
```

这就是 App 的入口。手机点开 App 后，程序先从 `main()` 开始。

`TongxingzheApp` 负责三件事：

- 等待 `AppController.load()` 把数据库、用户、设置、假数据准备好。
- 根据语言选择中文或英文。
- 根据是否登录，决定显示 `AuthScreen` 还是 `HomeShell`。

基础知识：

- `Widget`：Flutter 里所有界面零件都叫 Widget。按钮是 Widget，文字是 Widget，整页也是 Widget。
- `StatefulWidget`：会变化的界面。例如登录后页面会变、主题会变、语言会变。
- `StatelessWidget`：不自己保存变化状态的界面。
- `FutureBuilder`：等待一个未来才完成的事情，比如加载数据库。

读这一文件时只问一个问题：

```text
App 启动后，第一步显示谁？
```

答案是：没登录显示 `AuthScreen`，登录后显示 `HomeShell`。

## 4. 第四天：看翻译文件 `app_strings.dart`

看 `lib/l10n/app_strings.dart`。

这个文件里有：

- 中文文字
- 英文文字
- 性别选项
- 身份选项
- 年龄段选项
- 关系等级
- 兴趣度等级

例如：

```dart
'appTitle': '同行者'
```

英文对应：

```dart
'appTitle': 'Outreach Companion'
```

设计思路：

界面文字不要散落在各个页面里。集中放在这里，后面改文案、加第三种语言会容易很多。

练习：

1. 找到 `newRecord`。
2. 把中文从“快速记录”改成“新增记录”。
3. 跑起来看看页面有没有变化。
4. 再改回来。

这类小练习最适合入门：风险小，反馈快。

## 5. 第五天：看登录页 `auth_screen.dart`

看 `lib/screens/auth_screen.dart`。

它负责：

- 登录
- 注册
- 忘记密码
- 点击 demo 账号快速登录

这里你会遇到几个常见 Flutter 写法：

- `TextEditingController`：读取输入框里的文字。
- `setState()`：告诉 Flutter“这里的数据变了，请刷新界面”。
- `TextField`：输入框。
- `FilledButton`、`TextButton`：按钮。
- `SnackBar`：底部提示条。
- `showDialog()`：弹窗。

读法建议：

先找 `build()`。Flutter 页面的界面几乎都从 `build()` 开始。

然后顺着看：

```text
build()
  -> _loginFields()
  -> _registerFields()
  -> _forgotFields()
  -> _submit()
```

重点理解：

- 用户点“登录”按钮后，代码会进入 `_submit()`。
- `_submit()` 会调用 `widget.controller.login(...)`。
- 真正判断密码对不对，不在页面里，而在 `AppController` 里。

设计思路：

页面只负责“收集用户输入”和“显示结果”。账号、密码、数据库这些业务逻辑交给 controller。这样页面不会越来越乱。

## 6. 第六天：看主页面 `home_shell.dart`

`lib/screens/home_shell.dart` 是目前最大的文件。不要从头到尾硬啃。按模块看。

它里面主要有这些页面：

- `HomeShell`：底部导航和整体框架。
- `QuickRecordView`：记录页。
- `RecordsView`：列表页。
- `AnalyticsView`：图表页。
- `AdminView`：管理员页。
- `SettingsView`：设置页。

建议阅读顺序：

1. 先看 `HomeShell`：理解底部导航怎么切换页面。
2. 再看 `QuickRecordView`：理解一条记录怎么创建。
3. 再看 `AnalyticsView`：理解图表怎么从数据统计出来。
4. 最后看 `AdminView` 和 `SettingsView`。

### 6.1 记录页怎么工作

`QuickRecordView` 里有很多输入状态，例如：

- `_personNameController`
- `_englishNameController`
- `_contactDrafts`
- `_areaName`
- `_gender`
- `_identity`
- `_relationshipLevel`
- `_interestLevel`

点“保存”后会进入 `_save()`。

`_save()` 会创建一个 `ConversationRecord`：

```dart
final record = ConversationRecord(...)
```

然后调用：

```dart
await widget.controller.addRecord(record);
```

这句话的意思是：把刚刚填写的记录交给总管 `AppController`，由它负责保存。

### 6.2 图表页怎么工作

`AnalyticsView` 会拿到：

```dart
final records = controller.visibleRecords;
```

这里的 `visibleRecords` 很关键。它不是所有记录，而是“当前用户有权限看的记录”。

然后传给各种图表：

- `_DailyTrendChart`
- `_HourChart`
- `_AreaChart`
- `_IdentityChart`
- `_RelationshipChart`
- `_InterestChart`

基础知识：

图表不是数据库直接画出来的。通常过程是：

```text
原始记录 -> 分组统计 -> 图表数据 -> 画出来
```

例如“按区域”：

```text
IIT 有几条
Union 有几条
UIC 有几条
```

再变成柱状图。

## 7. 第七天：看模型 `models/`

模型就是“这个 App 世界里的名词”。

### 7.1 `conversation_record.dart`

`ConversationRecord` 表示一条推广记录。

重要字段：

- `createdAt`：记录时间。
- `collectorUserId`：谁记录的。
- `cityName`、`areaName`：城市和区域。
- `latitude`、`longitude`：经纬度。
- `gender`、`identity`、`ageRange`：基础问卷。
- `relationshipLevel`：关系等级。
- `interestLevel`：兴趣度。
- `contacts`：多条联系方式。
- `notes`：备注。
- `isLocationVerified`：定位是否被管理员核准。

这里还会看到：

- `toJson()`
- `fromJson()`
- `copyWith()`

基础知识：

- `toJson()`：把对象变成能保存/传输的 Map。
- `fromJson()`：把保存的数据变回对象。
- `copyWith()`：创建一个“差一点点不一样”的新对象。

### 7.2 `app_user.dart`

`AppUser` 表示登录用户。

重要字段：

- `username`
- `displayName`
- `email`
- `roleLevel`
- `cityNames`
- `passwordMd5`
- `lockedUntil`
- `lastSeenAt`

设计思路：

管理员和普通用户没有分成两张表，而是用 `roleLevel` 区分。这样更简单，也更接近实际开发。

## 8. 第八天：看总管 `app_controller.dart`

`lib/app/app_controller.dart` 是业务逻辑中心。

它负责：

- 加载数据库。
- 创建 demo 用户。
- 创建 demo 记录。
- 登录、注册、忘记密码、修改密码。
- 权限判断。
- 保存记录。
- 更新记录。
- 统计今日数量、联系方式率、正向兴趣数量等。
- 保存语言和主题设置。

可以把它想成饭店经理：

- 页面说“客人点了菜”。
- Controller 决定“这菜能不能做、谁来做、记到账上没有”。
- 数据库负责“把账本保存好”。

重点先看这些方法：

1. `load()`
2. `login()`
3. `loginDemoAccount()`
4. `addRecord()`
5. `visibleRecords`
6. `_canCurrentUserSeeRecord()`
7. `_ensureSeedData()`

基础知识：

- `ChangeNotifier`：一种通知机制。数据变了，调用 `notifyListeners()`，界面就会更新。
- `async` / `await`：等待比较慢的事情完成，比如读数据库。
- 私有方法：Dart 里以下划线开头的方法，例如 `_saveSettings()`，表示只在当前文件内部使用。

设计思路：

页面不要直接碰数据库。页面把事情交给 `AppController`，`AppController` 再去读写数据库。这样以后如果从本地 SQLite 换成云端 API，页面不用大改。

## 9. 第九天：看数据库 `local_database.dart`

`lib/data/local_database.dart` 定义 SQLite 表。

你可以把数据库想成 Excel 文件：

- 表：一个 sheet。
- 列：字段。
- 行：一条记录。

本项目核心表：

- `DbUsers`：登录用户。
- `DbConversationRecords`：推广记录主表。
- `DbRecordContacts`：联系方式子表。
- `DbAppSettings`：语言、主题、当前用户等设置。
- `DbSecurityEvents`：登录失败、锁定、密码重置等安全事件。

为什么联系方式单独一张表？

因为一个人可能有多条联系方式：微信、电话、邮箱。数据库里这种“一条记录对应多条子记录”的情况，通常拆成子表。

基础知识：

- 主键：每一行的身份证，例如 `recordId`。
- 外键思想：联系方式表里的 `recordId` 指向哪一条推广记录。
- 迁移 migration：App 已经安装在用户手机上后，数据库结构改了，不能简单删库重来，要用迁移一步步升级。

这个项目的数据库版本：

```dart
int get schemaVersion => 5;
```

如果以后加字段，就要考虑是否把版本升到 6，并写迁移逻辑。

## 10. 第十天：看服务 `services/`

`lib/services/location_service.dart`：

- 负责获取定位。
- 处理定位权限。
- 如果拿不到位置，返回错误状态。

`lib/services/heart_rate_service.dart`：

- 当前是 demo 模拟。
- 未来真实移动端可以接 HealthKit 或 Google Fit。

设计思路：

和系统打交道的东西单独放在 `services/`，不要混在页面代码里。这样页面更干净，也方便以后替换实现。

## 11. 第十一天：看测试 `test/widget_test.dart`

测试文件不是摆设，它是机器帮你点 App。

现在测试会做这些事：

- 以手机尺寸打开 App。
- 确认中文标题是“同行者”。
- 切换英文，确认标题是 `Outreach Companion`。
- 输入 `admin1 / admin1` 登录。
- 进入图表页。
- 滚到按区域、按身份，检查没有布局异常。

基础知识：

- 手工测试：你自己点。
- 自动化测试：机器帮你点。

自动化测试的好处是：以后你改了代码，跑一次 `flutter test`，它能提醒你有没有把原来的功能弄坏。

## 12. 一条数据从输入到保存的完整路线

这是理解项目最重要的一条线：

```text
用户在记录页填写表单
  -> QuickRecordView._save()
  -> 创建 ConversationRecord
  -> AppController.addRecord()
  -> 写入 SQLite: db_conversation_records
  -> 联系方式写入 SQLite: db_record_contacts
  -> notifyListeners()
  -> 页面和图表刷新
```

如果你能把这条线讲清楚，就已经摸到这个项目的骨架了。

## 13. 权限设计怎么想

这个 App 不是所有人都能看所有数据。

大致规则：

- 普通用户：看自己记录的明细。
- 城市管理员：看自己城市的数据。
- 组织管理员：看所有城市。

代码里主要由 `AppUser.roleLevel` 和 `AppController.visibleRecords` 控制。

设计思路：

隐私相关的限制不要只靠界面隐藏按钮。真正的数据过滤必须在业务逻辑层做，也就是 controller 或后端做。界面隐藏只是用户体验，权限判断才是安全边界。

## 14. 初学者最容易误会的几个点

### 14.1 App 不是一个文件

真实 App 是很多文件合作。不要追求“一个文件看懂全部”。先看清职责分工。

### 14.2 页面代码长，不代表没有结构

`home_shell.dart` 很长，因为 demo 阶段把多个页面放在一个文件里。以后可以拆成：

- `quick_record_view.dart`
- `records_view.dart`
- `analytics_view.dart`
- `admin_view.dart`
- `settings_view.dart`

但初学阶段放一起也有好处：比较容易顺着读。

### 14.3 数据库不是神秘黑箱

数据库就是有规则的表格。SQLite 是本机小数据库，Snowflake 是云上的大仓库。思路相通：表、列、行、查询、权限、备份。

### 14.4 生成文件不要手改

`local_database.g.dart` 是机器生成的。你改 `local_database.dart`，然后用命令重新生成。不要直接手改 `.g.dart` 文件。

## 15. 建议的练习顺序

### 练习 1：改一个界面文字

文件：`lib/l10n/app_strings.dart`

把某个中文文案改一下，运行看看，再改回来。

### 练习 2：加一个身份选项

文件：`lib/l10n/app_strings.dart`

在 `identityOptions` 里加一个英文 key，再在中英文翻译里补对应文字。

思考：

- 旧数据怎么办？
- 图表是否会自动统计新身份？

### 练习 3：给记录页加一个简单字段

先不要真的动数据库。可以先加一个不保存的临时界面输入框，理解 `TextField` 和 `TextEditingController`。

### 练习 4：看懂登录失败锁定

文件：`lib/app/app_controller.dart`

找到：

```dart
static const _maxFailedLogins = 4;
static const _lockDuration = Duration(days: 30);
```

读 `login()`，看失败次数如何增加、如何锁定。

### 练习 5：看懂图表统计

文件：`lib/screens/home_shell.dart`

找 `_AreaChart`。看它如何把 records 变成 counts，再变成柱状图。

## 16. 如果要继续重构，先做这几件事

等你对项目熟悉后，可以考虑：

1. 把 `home_shell.dart` 拆成多个页面文件。
2. 把图表组件拆到 `lib/screens/analytics/`。
3. 把数据库读写再封装一层 repository。
4. 把 demo 登录改成真实后端 API。
5. 把 SQLite 加密。
6. 增加同步队列表 `sync_outbox`。
7. 增加更多测试：登录失败、普通用户权限、管理员校正、图表统计。

不要一开始就重构。先能读懂，再小步调整。

## 17. Git 是什么

Git 是代码的时间机器。

它能帮你：

- 记录每次改了什么。
- 回到以前的版本。
- 对比两个版本差异。
- 把代码上传到 GitHub。
- 多个人协作时合并改动。

你可以把 Git 想成“带历史记录的文件夹”，但它比普通文件夹聪明得多。

## 18. GitHub 是什么

GitHub 是放 Git 仓库的网站。

Git 在你电脑本地也能用；GitHub 是把本地仓库同步到云端，方便备份、展示和协作。

关系是：

```text
Git: 工具
GitHub: 网站
repository: 一个项目仓库
commit: 一次存档
push: 上传到 GitHub
pull: 从 GitHub 拉下来
```

## 19. 最常用的 Git 命令

进入项目：

```bash
cd "/Users/xavieredith/Documents/Github/同行者APP"
```

查看当前状态：

```bash
git status
```

把文件加入本次提交：

```bash
git add .
```

提交一次存档：

```bash
git commit -m "Add beginner learning guide"
```

查看历史：

```bash
git log --oneline
```

上传到 GitHub：

```bash
git push
```

如果是第一次上传，通常要先设置远程地址：

```bash
git remote add origin https://github.com/YOUR_USERNAME/tongxingzhe-app.git
git branch -M main
git push -u origin main
```

把 `YOUR_USERNAME` 换成你的 GitHub 用户名。

## 20. 每次提交前先做完整检查

```bash
dart analyze
flutter test --no-pub
npm --prefix backend/server run check
npm --prefix backend/server test
./tool/run_postgres_tests_in_docker.sh
git status
```

含义：

- `dart analyze`：检查代码有没有明显问题。
- `flutter test --no-pub`：跑 Flutter 自动化测试。
- 两条 `npm` 命令：检查 Backend TypeScript 和 HTTP 合同。
- Docker 脚本：在临时 PostgreSQL 16 中检查 migration、权限、fixture 和备份恢复。
- `git status`：看看你准备提交什么。

只改界面时可以先跑相关 Widget test 缩短反馈时间，但提交前仍按[正式测试清单](manual/09-local-docker-and-ci-testing.md#12-提交前复制清单)选择完整范围。没有运行的检查应写成“未验证”，不能凭本机其他测试推断通过。

尤其注意不要提交真实数据：

- `.sqlite`
- `.db`
- `.csv`
- `.xlsx`
- 真实手机号、微信、邮箱
- 真实截图
- `.env`
- 密钥文件

项目里的 `.gitignore` 已经挡住很多风险，但提交前自己看一眼永远是好习惯。

## 21. 一条靠谱的学习路线

建议按这个节奏：

第一周：

- 会运行 App。
- 会改文字。
- 会看 `main.dart`、`app_strings.dart`、`auth_screen.dart`。

第二周：

- 看懂 `QuickRecordView._save()`。
- 看懂 `ConversationRecord`。
- 知道一条记录怎么保存。

第三周：

- 看懂 `AppController.login()`。
- 看懂 `visibleRecords` 权限过滤。
- 看懂 demo 数据怎么生成。

第四周：

- 看懂 `local_database.dart`。
- 知道 SQLite 表和 Dart model 的关系。
- 能解释为什么联系方式要拆子表。

第五周：

- 看懂图表统计。
- 能新增一个简单统计卡片。
- 能写或修改一个 widget test。

第六周：

- 学 Git。
- 学 GitHub。
- 学会开分支、提交、推送。

## 22. 最后给初学者的一句话

不要幻想“读完所有代码才开始动手”。正确顺序是：

```text
读一点 -> 改一点 -> 跑一下 -> 错一下 -> 查一下 -> 再改一点
```

会写程序的人不是不犯错，而是知道怎么把错误缩小、定位、修掉。这个项目已经有清晰的入口、测试、本地数据库和文档，很适合拿来边学边拆。
