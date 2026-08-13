# 第 9 章：在本机、Docker 与 CI 中运行测试

## 1. 这一章解决什么

本章是测试操作入口。它说明测试在哪里运行、每条命令证明什么，以及失败后先检查哪里。

读者不需要有 Docker 使用经验。仓库提供一个脚本来建立临时 PostgreSQL、运行测试和删除容器。脚本不连接 production，也不要求本机安装 `psql`。

测试为什么要分层，以及 Red-Green、回归测试和真实设备证据的含义，见[第 2 章](02-testing-and-change-workflow.md)。本章只处理准备环境和执行命令。

## 2. 先建立运行模型

本项目的测试分布在三个运行位置：

```text
开发电脑
├── Flutter 与 Dart：格式、静态分析、SQLite、Widget、同步和工具测试
├── Node.js：Backend TypeScript 检查和 HTTP／命令合同测试
└── Docker daemon
    ├── 源 PostgreSQL 16 容器：空库重建、权限、fixture、Backend 对账、并发和 dump
    ├── Node 24 容器：编译并运行真实 Backend→PostgreSQL 地点来源对账
    └── 恢复 PostgreSQL 16 容器：预置 cluster roles 后恢复和复验

GitHub Actions
├── 重复 Flutter、Backend 和 PostgreSQL 检查
└── 分别在 Linux、macOS 和 Windows runner 构建六个平台
```

Flutter 的设备数据库是 Drift／SQLite。它随 `flutter test` 在测试进程中运行。PostgreSQL 是 Backend 的共享事务数据库。两者不是同一个数据库，也不能用一边的测试代替另一边。

### 2.1 Docker 中的三个基本名词

| 名词 | 含义 | 本项目中的例子 |
| --- | --- | --- |
| image（镜像） | 建立容器的只读模板 | `postgres:16`、`node:24-bookworm` |
| container（容器） | 从镜像启动的隔离进程和文件系统 | 源 PostgreSQL、Node 24 一次性容器和 `-restore` PostgreSQL |
| database（数据库） | PostgreSQL 进程中的一个逻辑数据库 | `tongxingzhe_test` |

删除两个临时容器会删除其中的测试数据库。Node 24 容器也会在命令结束后删除。这是预期行为。测试只使用 synthetic 数据，脚本不挂载持久 volume，也不公开 PostgreSQL 端口。

### 2.2 PostgreSQL 容器与 Supabase 本地栈不是同一项

本章的自动 Docker 套件启动 `postgres:16`，并用一次性 `node:24-bookworm` 容器执行 Backend→PostgreSQL 对账。它验证 migration、SQL 权限、fixture、Backend bridge、并发和备份恢复，不启动 Supabase Auth、Mailpit 或其他 Supabase 服务。

普通 Flutter、Widget 和管理报告客户端改动不需要本地 Supabase 栈。只有改动或验证 Supabase 登录接线、注册确认邮件、密码恢复、会话回调、本地 Auth／JWKS 或 Mailpit 时，才需要 Supabase CLI 的本地 Docker 栈。当前仓库尚未把这套环境接入自动 runner；具体状态和替代验证见 [Supabase Auth 六平台 Spike](../spikes/supabase-auth-six-platform.md)。

若没有实际运行本地 Supabase 或隔离 staging，不得把 fake 身份测试、PostgreSQL Docker 通过或 App build 写成“Supabase 认证集成已通过”。这些证据只能分别证明客户端状态、数据库合同或平台可编译。

## 3. 第一次准备开发电脑

所有命令都从仓库根目录运行。先确认当前目录：

```bash
pwd
git status -sb
```

### 3.1 安装工具

本地工具版本应尽量接近 [CI 配置](../../.github/workflows/ci.yml)：

- Flutter `3.44.2`，Dart 随 Flutter 提供；
- Node.js `24` 和 npm；
- Git；
- Docker Desktop，或 Linux 上的 Docker Engine。

Docker 的系统安装步骤见 [Docker 官方安装入口](https://docs.docker.com/get-started/get-docker/)。Linux 使用者若要免 `sudo` 运行 Docker，应先阅读 [Docker 官方 Linux 安装后说明](https://docs.docker.com/engine/install/linux-postinstall/)。把用户加入 `docker` group 等同授予较高的本机权限，不应在共享机器上盲目执行。

### 3.2 验证工具可用

```bash
flutter --version
dart --version
node --version
npm --version
docker version
docker info
```

`docker version` 应同时显示 Client 和 Server。若 `docker info` 报 daemon 不可用，请先启动 Docker Desktop 或 Docker Engine。

### 3.3 安装仓库依赖

```bash
flutter pub get
npm --prefix backend/server ci
```

`npm ci` 按 lockfile 安装 Backend 依赖。依赖变化不明确时，不要用 `npm install` 顺手改写 lockfile。

## 4. 日常完整检查

普通 Flutter 或文档改动先执行这组命令：

```bash
dart format --output=none --set-exit-if-changed \
  lib test integration_test test_driver tool
dart analyze
flutter test --no-pub
dart run tool/check_production_boundary.dart
dart run tool/check_markdown_links.dart
```

Backend 发生变化时再执行：

```bash
npm --prefix backend/server run check
npm --prefix backend/server test
```

PostgreSQL migration、函数、授权、fixture 或 Backend store 发生变化时，再执行 Docker 数据库套件：

```bash
./tool/run_postgres_tests_in_docker.sh
```

`--no-pub` 表示测试使用已经解析的 Flutter 依赖。首次检出仓库或 `pubspec.lock` 变化后，应先运行 `flutter pub get`。

## 5. 怎样选择较小的目标测试

开发时先运行最接近改动的测试。目标测试通过后，提交前仍要运行完整检查。

| 改动范围 | 先运行 | 提交前增加 |
| --- | --- | --- |
| 一个 Dart 模块 | 对应的单个 `*_test.dart` | `dart analyze` 和全部 Flutter tests |
| Widget 或页面流程 | 对应 Widget test | 全部 Flutter tests |
| Drift schema 或 migration | 本地 migration test | Drift 生成文件比较和全部 Flutter tests |
| Backend TypeScript | Backend check 和相关 test | 全部 Backend tests |
| PostgreSQL | Docker 数据库套件 | PR 上的 PostgreSQL CI |
| Markdown | Markdown 链接检查 | 相关代码测试和 CI |
| 平台工程 | 当前平台 build | PR 上的六平台 build |

只运行一个 Flutter 测试文件：

```bash
flutter test --no-pub test/features/contact_revision/contact_revision_screen_test.dart
```

只运行 Drift 升级测试：

```bash
flutter test --no-pub test/data/local_database_migration_test.dart
```

只运行一个已编译的 Backend 测试文件：

```bash
npm --prefix backend/server run build
node --test backend/server/dist/test/sync-command.test.js
```

### 5.1 验证七十二小时离线对象资料

这项功能同时改动 Flutter、设备安全存储接缝和 Backend 响应。开发时可先运行以下目标测试：

```bash
flutter test --no-pub test/privacy
flutter test --no-pub test/app_session/app_session_test.dart
flutter test --no-pub test/targets/offline_promotion_target_gateway_test.dart
flutter test --no-pub \
  test/features/targets/promotion_target_directory_page_test.dart

npm --prefix backend/server run build
node --test backend/server/dist/test/promotion-targets.test.js
```

`test/privacy` 使用可控 fake 模拟安全存储成功、损坏、删除失败和并发。它也检查普通 Drift 锁不含对象 PII。这证明业务合同，但不证明某个平台的 Keychain、Credential Store 或 keyring 已在真实设备运行。

只修改七十二小时离线缓存时，目标开发循环不需要启动 Docker。若改动资料保留、匿名化、对象分配或服务端关系，必须运行第 6 节的 Docker 套件。

真实平台验收必须在目标设备上启动正式 App。启动探针需要完成写入、精确读回和删除，随后还要验证联网取得对象、结束进程、断网重启、只读显示、到期锁定与重新联网。只完成 `flutter build` 或上述 fake 测试时，应把平台结果写成 `build only` 或 `runtime pending`。

若单个测试通过而完整测试失败，应按完整测试的失败处理。单个测试只能缩短开发反馈时间。

### 5.2 验证资料保留与匿名化

这项功能同时改动 Flutter、Backend、PostgreSQL migration、权限和独立会话并发脚本。先运行快速测试：

```bash
flutter test --no-pub \
  test/targets/http_promotion_target_gateway_test.dart \
  test/targets/offline_promotion_target_gateway_test.dart \
  test/features/targets/promotion_target_directory_page_test.dart

npm --prefix backend/server run build
node --test backend/server/dist/test/promotion-targets.test.js
```

随后必须运行完整 Docker 套件：

```bash
./tool/run_postgres_tests_in_docker.sh
```

不要只在已有数据库上执行 `0020` fixture。完整脚本还会从空库应用 migration、检查 runtime 最小权限、启动两个独立会话争用同一对象、制造 checksum 漂移，并在恢复库重跑全部 check 和 fixture。第一次使用 Docker 时，继续按第 6.1 至 6.4 节操作；不需要先安装 PostgreSQL 或学习容器网络。

### 5.3 验证私人周计划

私人周计划同时包含 Widget、HTTP 合同、Backend trusted context 和 PostgreSQL 周期计算。开发时先运行短反馈测试：

```bash
flutter test --no-pub \
  test/plans/drift_personal_planning_cache_test.dart \
  test/features/plans/personal_action_plan_panel_test.dart \
  test/plans/http_personal_action_plan_gateway_test.dart

npm --prefix backend/server run build
node --test backend/server/dist/test/personal-action-plans.test.js
```

只运行这些测试不能证明时区边界和数据库权限。随后运行：

```bash
./tool/run_postgres_tests_in_docker.sh
```

看到 `fixture：0021_personal_action_plans.sql` 表示脚本正在检查私人计划。该 fixture 会验证美国夏令时切换周只有 167 小时、后续设置在下一周期生效、边界采用半开区间、mutation 可安全重放，以及另一位用户不能读取计划。Docker 脚本还会在恢复库再次运行相同 fixture。

### 5.4 验证 Flutter 管理报告浏览

管理报告浏览页只消费已经交付的管理项目、快照目录和单份读取端点。开发页面或 HTTP adapter 时，先运行：

```bash
flutter test --no-pub \
  test/management_reports/http_management_report_gateway_test.dart \
  test/features/management_reports/management_report_browser_view_model_test.dart \
  test/features/management_reports/management_report_browser_test.dart \
  test/app/app_dependencies_test.dart \
  test/app/tongxingzhe_app_test.dart
```

这组测试不需要启动 Docker。它用可控响应检查 Bearer token、`401` 单次刷新、严格报告合同、项目切换、迟到响应、320 px、200% 字号、键盘焦点和屏幕阅读器语义。

如果改动只在 Flutter 层，提交前运行第 4 节的完整 Flutter 检查即可。若同时改动 6M、6N、6L 的 Backend store、PostgreSQL bridge、权限、访问审计或 fixture，则还必须运行：

```bash
./tool/run_postgres_tests_in_docker.sh
```

第一次使用 Docker 时，从第 6.1 节开始操作。Docker 套件证明数据库授权、最小访问审计、撤权并发和恢复后合同；Flutter synthetic 测试证明客户端状态与显示规则。两类证据不能互相替代。

管理报告发布端点同时改动 Backend 和 PostgreSQL bridge。开发时先运行：

```bash
npm --prefix backend/server run build
node --test backend/server/dist/test/management-report-release.test.js

./tool/run_postgres_tests_in_docker.sh
```

Backend 测试检查认证优先、精确 JSON、稳定错误和单 statement store；Docker 套件检查真实身份映射、固定报告、发布能力、幂等、撤权／时区并发以及 dump／restore。两者都不证明生产成员已经获得发布能力，也不等同于运行了自动发布调度。

只读离线计划缓存复用现有 `db_app_settings`，没有修改 Drift schema，因此不需要生成新的 Drift snapshot。`drift_personal_planning_cache_test.dart` 在测试进程的内存 SQLite 中检查 scope 隔离、远端空值、损坏缓存、仅网络故障回退，以及 `401/403` 后清除。只修改这层缓存时不需要启动 Docker；改动 Backend 或 PostgreSQL 周期函数时仍必须运行 Docker 套件。

### 5.5 验证同步提醒和逐设备通知开关

提醒测试分四层。第一次接触项目时，可以按以下顺序运行：

```bash
flutter test --no-pub \
  test/app/private_session_data_guard_test.dart \
  test/plans/drift_personal_planning_cache_test.dart \
  test/reminders/http_personal_action_reminder_gateway_test.dart \
  test/reminders/drift_device_reminder_preference_store_test.dart \
  test/reminders/reminder_schedule_math_test.dart \
  test/features/reminders/personal_action_reminder_panel_test.dart

npm --prefix backend/server run build
node --test backend/server/dist/test/personal-action-reminders.test.js

./tool/run_postgres_tests_in_docker.sh
```

第一条命令不启动手机模拟器。它在测试进程中检查：新设备默认关闭、权限拒绝不写假成功、详细内容必须预览确认、旧版设置降级为通用通知、登出后取消私人提醒、不同项目通知不互相覆盖、旅行后按新设备时区计算，以及 Web／Linux／Windows 的明确降级。第二组命令检查 Backend 只使用可信当前上下文，客户端不能伪造用户、项目或设备字段。

最后一条命令才启动 Docker。没有用过 Docker 也不需要先创建数据库：脚本会下载 PostgreSQL 16 镜像、启动临时容器、从 `0001` 运行到当前最高 migration、执行全部 check 和 fixture、导出并恢复数据库，然后删除容器。看到以下两行表示提醒数据库合同正在执行：

```text
check：verify_personal_action_reminders.sql
fixture：0022_personal_action_reminders.sql
```

`0022` fixture 会创建、读取、清除和重放提醒，并验证越界分钟、旧 revision 和跨用户读取都被拒绝。它不测试手机锁屏。系统权限弹窗、App 被终止后的实际触发、旅行换时区和 Android 厂商后台限制仍需真机测试。

### 5.6 验证系统通知送达与旅行时区

系统通知真机测试不使用 Docker。Docker 容器运行 PostgreSQL，不能模拟 Android、iOS 或 macOS 的通知中心、设备时区和 App 终止状态。

仓库提供独立探针。它不连接 Backend，也不需要测试账号：

```bash
flutter devices
git status --short
git rev-parse --short HEAD
flutter run \
  -t tool/reminder_delivery_probe.dart \
  -d <device-id> \
  --dart-define=REMINDER_PROBE_COMMIT=<commit>
```

先取得设备 ID，并确认 `git status --short` 没有输出。随后取得 commit，再替换命令中的尖括号内容。探针拒绝缺失或无效的 commit。它只使用通用通知文案，分别记录安排、通知仍活跃的观察和用户交互，不把点击时间称为实际送达时间。

完整的权限、前台、后台、终止和旅行测试步骤见[提醒送达与旅行时区真机 Spike](../spikes/reminder-delivery-and-travel-time-zone.md)。没有真机时保留 `pending`，不能用 build 或单元测试替代。

## 6. Docker PostgreSQL 套件怎样运行

### 6.1 最短用法

先启动 Docker，再从仓库根目录执行：

```bash
./tool/run_postgres_tests_in_docker.sh
```

脚本默认使用 `postgres:16` 和 `node:24-bookworm`。首次运行时，Docker 会下载这两个镜像；Node 阶段还会从 npm registry 下载 `backend/server/package-lock.json` 指定的依赖。后续运行会复用本机镜像，但每个一次性 Node 容器仍会重新运行 `npm ci`，除非你在 Docker 环境外另行配置 npm cache。

Node 24 容器使用与 PostgreSQL 容器相同的 network namespace。它通过临时 `DATABASE_URL` 访问 `tongxingzhe_test`。脚本把 Backend 源码和共享 fixture 从只读仓库挂载复制到一个临时 work volume，再运行 `npm ci --ignore-scripts` 和编译。这个做法也适用于没有 `node_modules` 或 `dist` 的全新 checkout。Node 阶段不公开端口，也不连接 production。

### 6.2 脚本按什么顺序工作

脚本执行以下步骤：

1. 确认 Docker CLI 和 daemon 可用；
2. 建立名称含当前进程号的临时 PostgreSQL 容器；
3. 等待 PostgreSQL 健康检查通过；
4. 把数据库目录和全部正式并发脚本复制到容器；
5. 从空库执行全部 migration，再执行一次 checksum 重放；
6. 运行全部 schema／权限 check 和可回滚 synthetic fixture；
7. 建立一次性的 Node 24 容器，编译 Backend，并运行地点来源、当前关系阶段和后续联系同意占比三条 PostgreSQL adapter integration test；
8. 按文件名运行全部正式并发脚本，用独立数据库会话检查锁、撤权和唯一性合同；
9. 修改 migration 的临时副本，确认 runner 拒绝 checksum 漂移；
10. 执行 `pg_dump`，启动没有源 cluster roles 的第二个 PostgreSQL 容器；
11. 用 `postgres_prepare_restore_roles.sh` 建立 archive 所需的无登录角色，恢复后再运行全部 check 和 fixture；
12. 成功后删除两个 PostgreSQL 容器、Node 容器、临时 work volume 和本机临时 dump。

这组步骤同时验证新安装、重复部署、Backend→PostgreSQL 结果分类、并发、最小权限和备份恢复。fixture 内使用 `BEGIN` 与 `ROLLBACK`，不会把合成业务资料留在测试库。并发脚本会提交自己的 synthetic 行，这些行会随 dump 进入恢复库；它们不是 production 数据。

Node 阶段编译并运行 `backend/server/test/contact-location-evidence.integration.ts`、`backend/server/test/personal-current-relationship-stage.integration.ts` 和 `backend/server/test/personal-follow-up-consent-ratio.integration.ts`。第三条先以 runtime role 读取 `not_enabled`，再经正式配置入口启用并读取 `ready 0 / 0`。如果入口缺失、编译失败或真实 Backend 到 PostgreSQL 的任一断言失败，脚本会在这一步停止；设置 `KEEP_POSTGRES_TEST_CONTAINER=1` 后，PostgreSQL 容器会保留供检查。不能把前面的 SQL 通过单独记为 Backend 集成通过。

### 6.3 怎样读输出

正常输出会先显示 `已执行 0001_bootstrap` 到当前最高 migration。第二轮应显示 `无需重复执行`。

下面这行是成功证据，不是错误：

```text
checksum 漂移已按预期被拒绝。
```

地点来源四层阶段开始时还应看到：

```text
用真实 Backend adapter 对账 PostgreSQL（node:24-bookworm）。
```

该行只表示 Node 阶段开始。必须看到该阶段的 integration test 退出码为 0，且最后的总成功标志才算完整套件通过。

最后应出现：

```text
PostgreSQL Docker 测试全部通过。
已删除临时 PostgreSQL 容器：tongxingzhe-postgres-test-...
```

### 6.4 失败时保留容器

默认情况下，脚本在成功或失败后都删除 PostgreSQL 容器。Node 24 容器使用 `--rm`，其 stdout 是唯一的阶段日志，失败后不会保留容器。需要检查 PostgreSQL 失败现场时，运行：

```bash
KEEP_POSTGRES_TEST_CONTAINER=1 \
  ./tool/run_postgres_tests_in_docker.sh
```

脚本失败后会打印准确容器名和三条检查命令。把以下示例中的容器名替换为脚本实际输出：

```bash
docker logs tongxingzhe-postgres-test-12345
docker exec -it tongxingzhe-postgres-test-12345 \
  psql -U postgres -d tongxingzhe_test
```

如果 Node 阶段失败，先保存终端中从 `用真实 Backend adapter 对账 PostgreSQL` 开始的完整输出，再按错误涉及的命令重跑。`npm ci`、TypeScript 编译和 integration test 的断言都在终端输出；脚本不会把依赖或编译目录写回仓库。

进入 `psql` 后可先运行只读命令：

```sql
\dt app_data.*
SELECT version, applied_at_utc
FROM app_migrations.schema_migrations
ORDER BY version;
\q
```

完成检查后，只删除脚本打印的准确容器：

```bash
docker rm --force tongxingzhe-postgres-test-12345
```

不要用未核对的通配符或批量命令删除其他 Docker 容器。

### 6.5 使用其他 PostgreSQL 16 镜像

默认镜像适合本地脚本，因为它包含 Bash 和 PostgreSQL client。需要验证一个兼容镜像时，可以显式设置：

```bash
POSTGRES_TEST_IMAGE='postgres:16' \
  ./tool/run_postgres_tests_in_docker.sh
```

Node 24 镜像也可以显式设置，用于检查兼容的 Node 基础镜像：

```bash
BACKEND_POSTGRES_TEST_IMAGE='node:24-bookworm' \
  ./tool/run_postgres_tests_in_docker.sh
```

不要把 production 数据库地址传给这个脚本。脚本始终在自己建立的容器内使用固定测试库名。

### 6.6 重跑和清理

成功运行后直接再次执行同一个命令即可。每次运行使用新的进程号命名容器；脚本会先检查同名容器，避免覆盖别的测试现场。若上一次运行设置了 `KEEP_POSTGRES_TEST_CONTAINER=1`，先用脚本输出的准确名称查看并删除旧容器，再重跑：

```bash
docker rm --force tongxingzhe-postgres-test-12345
./tool/run_postgres_tests_in_docker.sh
```

不要删除未由脚本输出的容器，也不要把 production 数据库、个人 Docker volume 或真实 dump 传给这个 runner。

## 7. PostgreSQL 各类文件分别证明什么

| 文件或步骤 | 作用 | 失败通常表示 |
| --- | --- | --- |
| `migrations/*.sql` | 从上一 schema 迁移到下一 schema | SQL、约束、授权或依赖顺序错误 |
| `runner/*.sql` | 锁定、记录并校验 migration 历史 | 历史被改写或部署并发不安全 |
| `checks/verify_*.sql` | 检查表、函数、角色和权限形状 | schema 缺失或 runtime 权限过大 |
| `fixtures/NNNN_*.sql` | 用 synthetic 数据执行成功与拒绝路径 | 业务事务或不变量错误 |
| `backend/server/test/contact-location-evidence.integration.ts` | 用 Node 24、真实 Backend Store 和 PostgreSQL bridge 对账地点来源 | wire、Store、SQL 结果分类或隐私边界错误 |
| `backend/server/test/personal-current-relationship-stage.integration.ts` | 用 runtime role 对账当前关系阶段 Store 与窄 bridge | current snapshot 参数、结果解析或隐私边界错误 |
| `backend/server/test/personal-follow-up-consent-ratio.integration.ts` | 用 runtime role 对账未启用与启用后的个人比例结果 | identity／project 参数、开关状态或 union 解析错误 |
| 并发脚本 | 用两个独立 `psql` 会话同时写入 | 锁、唯一约束或冲突合同错误 |
| dump／restore | 从备份重建 schema 后重复验证 | 备份范围、owner、授权或恢复路径错误 |

check 主要观察结构。fixture 会调用正式函数并核对结果。两者不能互相替代。

### 7.1 用关系审计切片理解一次完整数据库测试

`0018_promotion_target_relationship_audit.sql` 是一个可直接对照的例子：

1. migration 给当前关系增加生命周期、备注和 revision，并建立只追加历史；
2. `verify_promotion_target_relationship_audit.sql` 检查表、函数、触发器和 runtime 最小权限；
3. 同名 `0018` fixture 建立 synthetic 对象，测试上升、阶段 4 下降、重放、冲突、别名、撤销分配和 warehouse 隔离；
4. Docker wrapper 先从空库运行它，再在 dump／restore 后的第二个数据库重跑；
5. GitHub Actions 使用同一 check 和 fixture，因此本地证据与远端 CI 证据可比较。

看到 `fixture：0018_promotion_target_relationship_audit.sql` 后失败，表示 migration 已经成功，失败点在行为验证。看到 `已执行 0018_promotion_target_relationship_audit` 前失败，则先检查 migration SQL。不要为绕过失败而删除旧 migration 或修改已经发布版本；修复尚未发布的新 migration，或为已发布 schema 追加更高版本。

`0019_person_institution_relationships.sql` 还示范了“串行 fixture 不足以证明并发安全”的情况。fixture 验证关系形状、权限、重放和结束历史；`verify_person_institution_relationship_concurrency.sh` 另开两个 `psql` 会话，同时建立同一对对象的同一种活动关系。成功输出必须说明只有一个请求成功，并且数据库只保留一条关系和一个初始 revision。Docker wrapper 已自动运行这个脚本；使用现有测试库时也可单独执行：

```bash
export DATABASE_URL='postgresql://postgres:postgres@127.0.0.1:5432/tongxingzhe_test'
./tool/verify_person_institution_relationship_concurrency.sh
```

`0020_promotion_target_retention.sql` 使用相同方法证明匿名化并发安全。fixture 先验证较短保留策略、到期前通用复核、明确续期、自动到期、撤回和接触事实保留。`verify_promotion_target_retention_concurrency.sh` 再让两个独立会话同时匿名化同一对象。成功时必须只有一个请求完成，并且数据库只留下匿名化对象、零个活动分配和一条匿名化审计。单独运行方法如下：

```bash
export DATABASE_URL='postgresql://postgres:postgres@127.0.0.1:5432/tongxingzhe_test'
./tool/verify_promotion_target_retention_concurrency.sh
```

`0021_personal_action_plans.sql` 展示另一类时间边界测试。计划保存固定 IANA 时区和 ISO 周起始日；SQL 先在当地日历中找周期边界，再转换为 UTC。这样夏令时切换周可以是 167 或 169 小时，而不是错误地固定成 168 小时。`verify_personal_action_plans.sql` 检查函数和最小权限，`0021` fixture 检查版本、重放、跨用户拒绝和下一周期生效。它不需要独立并发脚本，因为第一次创建用 scope advisory lock 串行化，fixture 与函数约束已覆盖本切片的写入合同。

`0022_personal_action_reminders.sql` 保存可选的每日当地分钟，不保存 UTC 触发时刻。`verify_personal_action_reminders.sql` 检查 runtime role 不能直接读表，也不能调用内部 document 函数。`0022` fixture 检查提醒可以独立于周目标使用、清除写成新版本、mutation 可重放、旧 revision 被拒绝，且另一位用户不能读取。设备 opt-in 不进入 PostgreSQL；它由 Flutter 测试覆盖。

### 7.2 用快照目录理解串行测试和并发测试的分工

`0035_management_report_snapshot_directory.sql` 同时有 check、fixture 和并发脚本。三者验证不同问题：

1. `verify_management_report_snapshot_directory.sql` 检查表、函数、触发器、固定 search path 和最小权限；
2. `0035_management_report_snapshot_directory.sql` fixture 建立 21 份可信 v2 快照和一份 legacy 快照，确认只返回排序后的前 20 项，并检查空目录、无权、未知身份和审计不可修改；
3. `verify_management_report_snapshot_directory_concurrency.sh` 开两个独立数据库会话，让目录访问与撤权竞争，确认锁顺序不会把已撤销权限误当成仍有效。

从仓库根目录运行完整套件即可覆盖三者：

```bash
./tool/run_postgres_tests_in_docker.sh
```

不需要手工建立数据库、用户或测试资料。脚本会启动两个隔离的 PostgreSQL 16 容器，自动执行 migration、check、fixture、并发和跨 cluster dump／restore，然后删除容器。输出中应依次看到：

```text
check：verify_management_report_snapshot_directory.sql
fixture：0035_management_report_snapshot_directory.sql
并发：verify_management_report_snapshot_directory_concurrency.sh
```

并发脚本不能直接在没有准备的空数据库中运行。只有在完整套件失败并保留了容器时，才按 6.4 节的方法进入该测试库单独调查。目录并发测试使用 `pg_locks` 等待实际锁，不用固定休眠猜测请求先后；若它偶尔失败，应先检查锁合同和 synthetic UUID 是否冲突，不要只增加等待秒数。

## 8. Drift v19 生成文件怎样检查

当前本地 schema 版本是 v19。数据库结构变化后先重新生成：

```bash
dart run build_runner build
dart run drift_dev schema dump \
  lib/data/local_database.dart \
  drift_schemas/drift_schema_v19.json
dart run drift_dev schema generate \
  drift_schemas \
  test/generated_migrations
```

随后运行：

```bash
dart format --output=none --set-exit-if-changed lib test
dart analyze
flutter test --no-pub test/data/local_database_migration_test.dart
```

CI 会在临时目录重新生成 v19 snapshot 和 migration helper，并与仓库文件逐字比较。手工修改生成文件不能通过该检查。

## 9. 六个平台 build 怎样运行

平台 build 证明工程能编译，不证明真实设备权限或外部服务可用。

| 平台 | CI 操作系统 | build 命令 |
| --- | --- | --- |
| Android | Linux | `flutter build apk --debug --no-pub` |
| Web | Linux | `flutter build web --release --no-pub` |
| Linux | Linux | `flutter build linux --debug --no-pub` |
| iOS | macOS | `flutter build ios --debug --no-codesign --no-pub` |
| macOS | macOS | `./tool/build_macos_unsigned.sh` |
| Windows | Windows | `flutter build windows --debug --no-pub` |

一台 Mac 不能本地完成 Windows 或 Linux build。一台 Windows 也不能构建 iOS。GitHub Actions 使用对应操作系统补齐六个平台。

## 10. GitHub Actions 与本机测试的对应关系

每个 PR 触发 [CI workflow](../../.github/workflows/ci.yml)。当前有九个 job：

| CI job | 重复的主要证据 |
| --- | --- |
| Flutter quality and tests | 格式、分析、全部 Flutter tests、边界、链接和 Drift 生成比较 |
| PostgreSQL rebuild, permissions, and restore | migration、check、fixture、Node 24 Backend→PostgreSQL 对账、并发、checksum 和恢复 |
| Backend identity, context, and sync | TypeScript check 和全部 Backend tests |
| Build Android／Web／Linux／iOS／macOS／Windows | 六个平台独立 build |

CI 的 PostgreSQL job 在 Linux runner 上执行同一个 Docker runner。默认会拉取 `postgres:16` 和 `node:24-bookworm`，在临时容器中运行 `psql`、Backend build 和三条 Backend integration；它不需要 runner 上的 PostgreSQL service，也不占用本机端口。两条路径执行相同的 migration、check、fixture、Backend 对账和并发脚本。

本机通过是提交前证据。远端 CI 通过是干净环境证据。合并前应同时检查两者，不能根据本机结果推断 GitHub 已通过。

## 11. 常见失败怎样定位

| 症状 | 先检查 |
| --- | --- |
| `docker: command not found` | Docker 是否已安装，终端是否重启 |
| `Cannot connect to the Docker daemon` | Docker Desktop／Engine 是否已启动，当前用户是否有权限 |
| 镜像下载失败 | 网络、代理和 Docker registry 访问 |
| `bash -n` 失败 | Docker runner 的 shell 语法 |
| migration 第一次失败 | 输出中的第一个 migration 文件和 PostgreSQL 错误码 |
| 第二次 migration 报 checksum 不同 | 已执行的 migration 是否被改写 |
| fixture 失败 | 最后打印的 fixture 文件和异常文本 |
| `contact-location-evidence.integration.js` 未找到 | 当前 checkout 是否包含对应 TypeScript source；没有它就不能声称四层对账通过 |
| Node 24 `npm ci` 或 build 失败 | npm registry、lockfile、Node 镜像和 Backend TypeScript 错误 |
| Backend 地点来源 integration 断言失败 | 先保留 Node 阶段完整 stdout，再分别检查 Store 映射、SQL fixture 和 privacy assertion |
| Backend 同意占比 integration 断言失败 | 检查 runtime identity／project 参数、0048 当前开关、0049 union 和 Store exact-key 解析 |
| restore check 失败 | dump schema 范围、role、函数授权和恢复 owner |
| Flutter 单测通过但完整测试失败 | 共享状态、生成文件或其他模块的回归 |
| 离线对象测试通过但真机不启用缓存 | 安全存储探针、本地数据库能力和六平台证据矩阵 |
| 某平台 build 失败 | 该平台 job 的第一条失败命令，不把它写成所有平台失败 |

先保存第一条稳定错误。后续清理错误常由第一条失败引起，不应同时修改多个层次。

## 12. 提交前复制清单

Flutter、Backend 和 PostgreSQL 都发生变化时，从仓库根目录依次执行：

```bash
flutter pub get
npm --prefix backend/server ci

dart format --output=none --set-exit-if-changed \
  lib test integration_test test_driver tool
dart analyze
flutter test --no-pub

npm --prefix backend/server run check
npm --prefix backend/server test

./tool/run_postgres_tests_in_docker.sh

dart run tool/check_production_boundary.dart
dart run tool/check_markdown_links.dart
```

文档只报告实际执行的结果。未运行的平台 build、真实设备流程或外部服务探针应标为未验证。
