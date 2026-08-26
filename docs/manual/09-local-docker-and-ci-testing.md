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
    ├── Node 24 容器：编译并运行真实 Backend→PostgreSQL adapter 对账
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

PostgreSQL migration、bridge、索引、授权、fixture 或 Backend store 发生变化时，再执行 Docker 数据库套件：

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

只修改 6AI 的 Flutter 导出读取时，再加入导出 gateway 测试：

```bash
flutter test --no-pub \
  test/management_reports/http_management_report_export_gateway_test.dart \
  test/management_reports/http_management_report_gateway_test.dart
```

这组测试使用内存 HTTP 响应和 canonical UTF-8 golden bytes，不会在电脑上创建报告文件，也不需要
Docker。通过表示 Flutter 能严格验证服务端响应；它不表示浏览器已下载、原生平台已保存、系统分享
可用或用户已经打开文件。后续平台交付必须分别运行对应 adapter、平台 build 和必要的运行时验收。

只修改 6AJ 的 Web 下载 delivery 或两阶段 UI 时，运行：

```bash
flutter test --no-pub \
  test/management_reports/management_report_export_delivery_test.dart \
  test/features/management_reports/management_report_browser_view_model_test.dart \
  test/features/management_reports/management_report_browser_test.dart \
  test/l10n/app_strings_test.dart
flutter test --no-pub --platform chrome \
  test/management_reports/management_report_export_delivery_web_test.dart
flutter build web --release
```

这些命令不需要 Docker。第一条在内存中检查准备、下载请求、重试、迟到响应、非 Web unavailable、
双语文案和辅助功能；它不会在电脑上创建文件。第二条在 Headless Chrome 中拦截真实 Blob 和临时链接，
对账 bytes、MIME、文件名、链接移除和 object URL 延后回收，并把浏览器版本写入测试日志。测试会阻止
默认保存动作，因此只证明浏览器收到了正确的下载请求，不证明文件已保存。第三条编译真正的 Web
adapter，能发现条件导入或浏览器 API 的编译错误，但不会自动点击下载。

2026-08-14 的本地证据使用 `HeadlessChrome/150.0.0.0`：测试捕获文件名
`management-report.json`、MIME `application/json; charset=utf-8` 和 bytes
`[0, 1, 2, 127, 128, 255]`，并确认临时链接已移除、object URL 在 click 后回收。这个证据没有执行
浏览器保存动作，也不能替代其他浏览器或五个原生平台的验收。若要声称某个浏览器实际生成了文件，
还要在该浏览器中完成保存后的文件对账，并另行记录浏览器版本、文件名、MIME 和 bytes。

只修改 Slice 6AK 的规范区域跨版本映射合同时，不需要 Flutter、浏览器或真机。第一次使用 Docker 时，
确认 Docker Desktop 已启动，然后从仓库根目录运行：

```bash
./tool/run_postgres_tests_in_docker.sh
```

脚本会自动发现 0053 migration、结构与权限 check、可回滚 fixture 和确定性并发脚本；随后还会导出
测试数据库，在第二个 PostgreSQL 16 容器恢复并重复 check 与 fixture。看到
`0053_canonical_region_version_mappings`、`verify_canonical_region_version_mappings.sql` 和
`verify_canonical_region_version_mapping_concurrency.sh` 均执行成功，才表示这张数据库合同已通过。

这套测试不连接 production，不需要 Supabase 账号，也不使用真实区域或接触资料。通过只证明 synthetic
已发布树、精确内容指纹、幂等、冲突拒绝、追加不可变和最小权限；它不证明现实区域对应关系正确，
也不表示 production current 区域报告、HTTP、Flutter 或六平台运行时已经交付。完整原理和单项命令见
[第 11 章](11-management-metrics-and-privacy.md#slice-6ak-如何固定跨版本区域映射证据)。

只修改 Slice 6AL 的私有管理区域归属 resolver 时，不需要 Flutter、浏览器、Supabase 账号或真机。第一次
使用 Docker 时，确认 Docker Desktop 已启动，然后从仓库根目录运行：

```bash
./tool/run_postgres_tests_in_docker.sh
```

脚本会自动发现 0054 migration、结构与权限 check、synthetic fixture 和 dump／restore。通过必须同时
证明 reader role 的最小权限、`original` 与显式 `current` 目标树、坐标唯一／零命中／歧义状态、6AK
region-only mapping、`not_reportable` 和无敏感输出。脚本通过不表示报告截止点已经选定，也不表示生产区域
报告、完整网格、互补隐藏、授权、HTTP、Flutter 或真机运行时已经交付。

0054 使用无登录、无成员的 `tongxingzhe_region_attribution_reader` 作为 resolver owner。schema dump 不
包含 PostgreSQL cluster roles；恢复库会先由 `tool/postgres_prepare_restore_roles.sh` 幂等创建该 reader，
再恢复函数 owner 和权限。这样可以发现只在源数据库角色存在时才暴露的 owner／ACL 错误。

如果只需要在已经运行的测试库检查 0054，先运行 migration，再按以下顺序执行：

```bash
export DATABASE_URL='postgresql://postgres:postgres@127.0.0.1:5432/tongxingzhe_test'
./tool/postgres_migrate.sh
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/checks/verify_management_region_attribution.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/fixtures/0054_management_region_attribution.sql
```

这些命令只使用 synthetic 来源、树、边界、坐标和指纹。它们不读取 current selection，不选择报告截止点，
也不连接 production。手工通过只能证明当前 SQL 合同和权限矩阵，不证明维护者外部证据、真实区域等价或
生产区域报告已经验收。

第一次使用 Docker 时，从第 6.1 节开始操作。Docker 套件证明数据库授权、最小访问审计、撤权并发和恢复后合同；Flutter synthetic 测试证明客户端状态与显示规则。两类证据不能互相替代。

只修改 Slice 6AM 的报告截止区域目标树上下文时，不需要 Flutter、Backend、浏览器、Supabase 账号或真机。
第一次使用 Docker 时，先启动 Docker Desktop，再从仓库根目录运行：

```bash
./tool/run_postgres_tests_in_docker.sh
```

脚本会自动运行 0055 migration、结构与权限 check、synthetic fixture、checksum、并发脚本和 dump／restore。
它验证历史 selection 是否按可信 cutoff 固定、migration baseline 的观察下界、publication 与 resolver 的共享
事务锁、reader 最小权限和恢复库 owner／ACL。看到 `0055_management_report_region_target_context`、
`verify_management_report_region_target_context.sql`、`verify_management_report_region_target_context_concurrency.sh`
均通过，才表示本切片的数据库证据齐全。通过不表示生产区域报告、区域聚合、6AL 以外的客户端入口或真实区域
维护审核已经完成。完整原理见[管理指标与隐私章节](11-management-metrics-and-privacy.md#slice-6am-按报告截止点固定区域目标树上下文)。

如果只检查已经运行的测试库，先确认 `DATABASE_URL` 指向专用 synthetic 数据库，再按顺序执行：

```bash
export DATABASE_URL='postgresql://postgres:postgres@127.0.0.1:5432/tongxingzhe_test'
./tool/postgres_migrate.sh
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/checks/verify_management_report_region_target_context.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/fixtures/0055_management_report_region_target_context.sql
./tool/verify_management_report_region_target_context_concurrency.sh
```

这些命令只使用 synthetic selection history 和已发布树。手工通过表示当前 resolver 的返回合同、权限和锁语义
成立，不表示真实报告已经生成。并发脚本会提交自己的测试行，普通 fixture 会回滚；不要把测试库当作生产库。

只修改 Slice 6AN 的私有 current 城市报告合同时，也使用同一个 Docker 入口：

```bash
./tool/run_postgres_tests_in_docker.sh
```

不需要先创建容器、数据库或 PostgreSQL 用户。runner 会自动发现 0056 migration、check、fixture 和
`verify_management_current_city_report_concurrency.sh`，并在恢复库重复 check 与 fixture。6AN 新增的无登录
reader role 也由恢复准备脚本建立；若忘记这一步，源容器可能通过，但跨 cluster restore 会因 owner 不存在而失败。

只在已有专用测试库调试 6AN 时，按顺序运行：

```bash
export DATABASE_URL='postgresql://postgres:postgres@127.0.0.1:5432/tongxingzhe_test'
./tool/postgres_migrate.sh
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/checks/verify_management_current_city_report.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/fixtures/0056_management_current_city_report.sql
./tool/verify_management_current_city_report_concurrency.sh
```

check 检查固定定义、函数形状、最小列权限和旧渠道发布隔离；fixture 检查两期完整城市网格、归属状态、三项
primary 阈值和互补隐藏；并发脚本检查区域树 publication 和报告执行的两种锁顺序。三者不能互相替代。
通过仍只表示 DB-only synthetic 合同成立，不表示生产快照、HTTP、Flutter、导出、真实区域或外部事实攻击已验收。

### 6AO：验证 current 城市报告快照与发布 lineage

6AO 在 6AN 候选之上增加私有的受保护快照和独立区域发布 lineage。它复用通用不可变 snapshot storage，
但不复用渠道 v2 的 provenance、16 格校验、读取、目录或导出。数据库会重新验证 `release_management_reports`，
派生可信项目报告时区 revision、`data_cutoff_utc` 和 6AM target context；target tuple、时区 revision、定义、
期间或网格上下文漂移时失败关闭。

validator／pair comparison 固定 report、metric、dimension、view、granularity、
query fingerprint、privacy、source scope、期间、watermark、target context 和完整 cells；unavailable、额外字段、
错误 identity、错误 tuple、缺失／重复／乱序网格和期间错误都失败关闭。被阻断的尝试只保存不含 protected document、
cells、来源、贡献者、隐藏前值和 PII 的最小 evidence。

首次成功发布建立唯一 baseline，后续成功发布链接前一 snapshot。相同 request 和固定上下文精确幂等，不新增
snapshot 或 attempt。same／earlier cutoff、无共享期间、共享值／隐私变化和其他上下文漂移都返回稳定 blocked reason。
snapshot 与 attempt 只追加，不能 UPDATE 或 DELETE。runtime、`PUBLIC` 和区域维护身份不能执行发布、读取区域
provenance 或直接写区域表。retention 和 warehouse 不属于本 Slice。

零基础读者可以把 Docker 理解成一次性测试环境：它会启动隔离的 PostgreSQL 容器，运行迁移和 synthetic 数据，
结束后清理容器，不会修改生产数据库。先安装并启动 Docker Desktop，再从仓库根目录运行：

```bash
./tool/run_postgres_tests_in_docker.sh
```

runner 会自动发现 0057 migration、结构与权限 check、fixture 和
`verify_management_current_city_report_snapshot_lineage_concurrency.sh`，并执行 migration checksum、dump／restore
和恢复库重跑。成功证据应同时覆盖：有效和无效 6AN 文档、首个唯一 baseline、前一 snapshot 链接、精确幂等、
same／earlier cutoff、无共享期间、共享期间／城市值变化、target tuple／时区 revision 漂移失败关闭、
`release_management_reports` 重检、通用快照存储复用、独立区域 attempt／provenance、value-free blocked attempt、
snapshot／attempt 不可改删、角色读写边界，以及旧渠道 v2/read/directory/export 继续拒绝区域文档。
最后一项由 runner 自动重跑既有 trusted release、authorized read、directory 和 export 的 check／fixture 证明，
不是由 0057 fixture 单独替代旧合同测试。

如果只调试已经运行的专用测试库，不要把命令指向 production，按以下顺序运行：

```bash
export DATABASE_URL='postgresql://postgres:postgres@127.0.0.1:5432/tongxingzhe_test'
./tool/postgres_migrate.sh
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/checks/verify_management_current_city_report_snapshot_lineage.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/fixtures/0057_management_current_city_report_snapshot_lineage.sql
./tool/verify_management_current_city_report_snapshot_lineage_concurrency.sh
```

check、fixture 和并发脚本不能互相替代。通过只表示 DB-only synthetic 快照和 lineage 合同成立，不表示 HTTP、
Flutter、UI、读取、目录、导出、retention、warehouse、真实区域证据、生产调度或外部事实攻击已经验收。

### 6AW：验证管理兴趣报告快照与独立发布 lineage

6AW 在 6AV 的十格 count-only 兴趣合同之上增加私有的不可变快照和独立 release lineage。它复用通用 snapshot
storage，但不复用 channel 的 16 格 claim／provenance，也不复用 current-city 的区域 provenance。validator 固定
`previous/current × interest_level 0..4` 十格、6AV 的报告定义和隐私状态；`displayed` 只能是受保护整数，
`suppressed` 必须是 JSON `null`。

对没有用过 Docker 的读者，Docker 可以理解成一次性测试环境：它启动一个隔离的 PostgreSQL 容器，向容器内运行
migration 和 synthetic fixture，结束后删除容器。它不会连接 production，也不会把 fixture 写入真实项目。第一次运行：

1. 安装 Docker Desktop 并打开它。等待 Docker Engine 完全启动。
2. 打开 Terminal，进入同行者 APP 的仓库根目录：

   ```bash
   cd "$(git rev-parse --show-toplevel)"
   ```

   如果提示当前目录不是 Git 仓库，先用 `cd` 进入你 pull 下来的项目目录。
3. 确认 Docker 同时有 Client 和 Server：

   ```bash
   docker version
   ```

   只有 Client 没有 Server 时，Docker Desktop 仍未就绪；不要继续运行数据库测试。
4. 从仓库根目录运行完整套件：

   ```bash
   ./tool/run_postgres_tests_in_docker.sh
   ```

runner 会按完整 migration 顺序运行，并自动发现 0062 的兴趣 snapshot lineage 结构／权限 check、synthetic fixture 和并发脚本，并执行
checksum、dump／restore 以及恢复库重跑。预期证据包括：合法与拒绝的 6AV 文档、唯一 baseline、相同 request 的精确
幂等、稳定滚动和 `previous_snapshot_id`、same／earlier cutoff、无共享期间、共享期间内的兴趣格值／隐私变化、定义／period definition／boundary／网格／
query／privacy／source／时区 revision 漂移的稳定 blocked reason、value-free blocked attempt、通用 snapshot storage
复用、独立 request claim／provenance、snapshot／attempt／claim 不可改删和最小 ACL。runner 还应证明旧 channel、
current-city 与 6AV 合同没有回归。成功时命令退出码为 `0`；不要只看某一行输出而忽略末尾的 exit code。

如果已有专用 PostgreSQL 测试库，也可以单独调试。先确认地址是本机测试库，不是 production：

```bash
export DATABASE_URL='postgresql://postgres:postgres@127.0.0.1:5432/tongxingzhe_test'
./tool/postgres_migrate.sh
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/checks/verify_management_interest_report_snapshot_lineage.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/fixtures/0062_management_interest_report_snapshot_lineage.sql
./tool/verify_management_interest_report_snapshot_lineage_concurrency.sh
```

check、fixture 和并发脚本不能互相替代。已有测试库含有旧数据时，应建立新的专用库或重新运行一次性 Docker 容器，
不要删除 production 数据，也不要把 synthetic fixture 当作业务数据。

常见问题：

- `Cannot connect to the Docker daemon`：打开 Docker Desktop，等待 Engine 就绪，再运行 `docker version`。
- `psql: command not found`：本机没有 PostgreSQL 客户端，使用 Docker runner，不要改用 production 连接。
- checksum 失败：不要编辑已执行的 migration；保留输出并改用干净测试容器核对。
- fixture 或 check 失败：保留首次失败输出，先检查 migration 顺序、分支和数据库地址，不要为了通过而降低隐私条件。
- Docker 下载超时或磁盘不足：检查网络、Docker Desktop 磁盘空间和容器状态。

这些检查只证明 DB-only synthetic 快照、claim／provenance 隔离、lineage 不变量、并发行为和 ACL 在当前 PostgreSQL
实现中成立。它们不证明 Backend HTTP、runtime bridge、Flutter、Drift、读取、目录、导出、生产发布调度、真实账号、
Apple／Android／iOS／macOS／Windows／Linux／Web 真人平台运行或真机证据，也不构成形式化不可重识别保证。

### 6AX：验证授权兴趣快照读取

6AX 只在 private PostgreSQL 中读取一份明确指定的 6AW 兴趣快照。它重新验证
`view_anonymous_analytics`，检查 0062 interest request claim、approved release attempt、空 `reason_codes` 和完整
snapshot lineage（包括 `source_change_sequence` source watermark），再运行 6AV interest document validator。它不增加 runtime bridge、HTTP、目录、Flutter、导出或真人平台
验收。

第一次使用 Docker 时：

1. 打开 Docker Desktop，等待 Docker Engine 完成启动。
2. 打开 Terminal，进入仓库根目录：

   ```bash
   cd "$(git rev-parse --show-toplevel)"
   ```

3. 确认 Docker 同时显示 Client 和 Server：

   ```bash
   docker version
   ```

4. 运行完整 PostgreSQL 套件：

   ```bash
   ./tool/run_postgres_tests_in_docker.sh
   ```

runner 按文件名自动发现 0063 migration、private read check、synthetic fixture 和
`verify_authorized_management_interest_report_snapshot_read_concurrency.sh`。它还执行 checksum、dump／restore，并在没有源
cluster roles 的恢复库重跑 migration、check 和 fixture。恢复库不重跑并发脚本，因为并发脚本会提交 synthetic 行；重跑它会把
同一批并发写入再次导入恢复库。

通过时应同时看到以下证据：

- 合法读取和重复读取保持完整的 `previous/current × interest_level 0..4` 十格；
- unknown／cross-project 返回 `not_found`，没有正文；
- same-project channel、current-city、legacy、blocked 或缺失／漂移 provenance 返回 `untrusted_provenance`，没有正文；
- active、撤权、过期、release-only 和无项目成员请求失败关闭且不写 audit；
- audit 不含 `protected_report`、cells、`value_count`、贡献者、contact、来源或 PII，且 UPDATE／DELETE 被拒绝；
- read-first 与 revoke-first 并发结果符合授权锁；旧 channel、current-city、6AV 和 6AW 检查继续通过。

如果只调试已有专用 PostgreSQL 测试库，先确认它不是 production。并发脚本会提交固定 `6d*` synthetic 行；每次运行请使用
新建的空测试库，重复运行前先重建该测试库，否则固定主键会按预期冲突。

```bash
export DATABASE_URL='postgresql://postgres:postgres@127.0.0.1:5432/tongxingzhe_test'
./tool/postgres_migrate.sh
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/checks/verify_authorized_management_interest_report_snapshot_read.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/fixtures/0063_authorized_management_interest_report_snapshot_read.sql
./tool/verify_authorized_management_interest_report_snapshot_read_concurrency.sh
```

这些命令只使用 synthetic 数据。check、fixture 和并发脚本不能互相替代。Docker 通过只证明当前 PostgreSQL 的 private
authorization、interest provenance、失败关闭、value-free audit、并发和 ACL；它不证明 runtime、HTTP、Flutter、导出、生产
发布、真实账号、六平台运行或形式化不可重识别保证。

### 6AY：验证管理兴趣快照 runtime bridge

6AY 把 0063 private read 接到 Backend runtime。它不增加 HTTP route。调用方必须已经得到 Backend 验证的 external `issuer + subject`，
并提供显式 project UUID 和 snapshot UUID。

bridge 只用 exact `issuer + subject` 匹配现有且 active 的 identity。它不 trim、bootstrap、创建账号、读取 `SessionContext` 或接受内部用户、
capability、时区、截止点、期间、筛选和 SQL。bridge 使用 `SECURITY DEFINER` 和 `search_path = pg_catalog`，只调用
`app_private.read_authorized_management_interest_report_snapshot_v1(uuid, uuid, uuid)`。runtime 只有 bridge `EXECUTE`，没有
`app_private` schema usage，也不能读取用户、identity、snapshot、provenance 或 audit 表。

Backend adapter 只执行一次固定参数化 SQL。strict parser 检查 0063 的固定 root keys、状态、reason code、project／snapshot 绑定和 6AX 十格
protected report。它只接受固定 cell 顺序、合法 count 和 `suppressed = null`，拒绝额外字段、PII、其他 report family 和错误 project。它只把
`42501` 映射为 typed `forbidden`。HTTP status mapping 不属于本切片。

没有用过 Docker 时，先把它看成一次性测试环境。Docker Desktop 提供 Docker Engine。runner 启动隔离的 PostgreSQL 和 Node 容器，使用
synthetic 数据运行测试，最后删除容器。它不连接 production。

1. 打开 Docker Desktop，等待 Engine 完成启动。
2. 在仓库根目录运行：

   ```bash
   ./tool/run_postgres_tests_in_docker.sh
   ```

runner 自动发现 0064 migration、check 和 fixture，并显式运行第八条 Backend integration：
`management-interest-report-snapshots.integration.ts`。它还运行 0063 read/revoke 并发、checksum 和 dump／restore。
恢复库只重跑 migration、check 和 fixture，不重跑会提交 synthetic 行的并发脚本。

如果只调试专用测试库，先确认 `DATABASE_URL` 不是 production。并发脚本会提交 synthetic 行，所以每次运行都使用新的空库：

```bash
export DATABASE_URL='postgresql://postgres:postgres@127.0.0.1:5432/tongxingzhe_test'
./tool/postgres_migrate.sh
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/checks/verify_runtime_authorized_management_interest_report_snapshot_read.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/fixtures/0064_runtime_authorized_management_interest_report_snapshot_read.sql
cd backend/server
npm ci --ignore-scripts
npm run build
DATABASE_URL="$DATABASE_URL" \
INTEREST_RUNTIME_FIXTURE=../../backend/database/fixtures/0064_runtime_authorized_management_interest_report_snapshot_read.sql \
node dist/test/management-interest-report-snapshots.integration.js
```

fixture 证明数据库 identity、project／snapshot、0063 状态和 runtime ACL。integration 证明真实 Node adapter 的一次 bridge 调用和 strict JSON
对账。通过只证明 DB-only runtime bridge 合同，不证明 HTTP、Flutter、目录、导出、生产身份提供方、真实账号或六平台运行时。

### 6AZ：验证管理兴趣快照 HTTP 读取

6AZ 只把 6AY store 接到一个固定的只读 HTTP GET：

```text
GET /v1/projects/:projectId/management-interest-report-snapshots/:snapshotId
```

handler 先验证 Bearer token，再检查两个 UUID、query、GET body 和 store。认证失败时，其他输入即使无效，也先返回 `401`。认证通过后，
handler 只调用 6AY store，不使用 `SessionContext`、通用 reader、current-city reader、private schema 或客户端 SQL。

成功响应保留 6AX protected report，并返回 `access_event_id` 和 `snapshot_id`。`403`、`404`、`409` 和 `503` 使用固定错误 code；`404` 和
`409` 可以带不含报告值的 `access_event_id`。所有响应使用 JSON 和 `Cache-Control: no-store`。HTTP 层不重新执行 6AX／6AY 授权，
也不修改报告数据。

#### 为什么 6AZ 不新增数据库测试

6AY 已经验证 PostgreSQL bridge、ACL、parser、审计、并发、checksum 和 restore。6AZ 只增加 HTTP handler、route 和 production composition。
它使用已有的 6AY store 接口，不增加 migration、check、fixture 或新的数据库状态。因此，HTTP 测试可以用 synthetic identity 和 fake store
独立运行，避免重复建立数据库合同。

没有用过 Docker 时，仍可以运行完整套件。Docker 是一次性测试环境：runner 启动隔离的 PostgreSQL 和 Node 容器，使用 synthetic 数据，
完成后删除容器。它不连接 production。

1. 打开 Docker Desktop，等待 Docker Engine 就绪。
2. 在仓库根目录运行：

   ```bash
   ./tool/run_postgres_tests_in_docker.sh
   ```

CI 仍运行既有 6AY PostgreSQL suite。它继续自动发现 0064 migration、check 和 fixture，运行 interest runtime integration、既有并发、checksum
和 dump／restore。6AZ 不会让 runner 多出一个数据库步骤。

如果只修改 6AZ HTTP 文件，最小验证集是不启动 Docker 的 Backend 检查和测试：

```bash
cd backend/server
npm ci --ignore-scripts
npm run check
npm test
```

这些命令证明认证顺序、固定 route、wire mapping、错误脱敏、Promise gate 和 `no-store`。Docker 证据仍只证明既有 DB-only 6AY 合同，
不证明 Flutter、导出、缓存、离线、生产身份、真实账号或真人平台运行时。

### 6BA：验证管理兴趣快照 metadata-only 目录

6BA 为 6AW interest snapshot 增加独立的 metadata-only directory。它不复用 0035 channel directory 或 0060 current-city directory。
数据库重新验证 `view_anonymous_analytics`，只列出 approved interest provenance。目录最多返回 20 项，按
`data_cutoff_utc`、`released_at_utc` 和 `snapshot_id` 降序排列。第一项只是排序结果，不表示 current、latest、最新有效或未被取代。

目录的固定 HTTP 入口是：

```text
GET /v1/projects/:projectId/management-interest-report-snapshots
```

目录响应只含 `access_event_id`、`project_id` 和 metadata-only `snapshots`。每项只含 snapshot ID、固定 report ID／version、报告时区、
data cutoff 和发布时间。响应不含报告格、suppressed 前值、来源、贡献者或 PII。数据库目录 audit 也不保存 snapshot ID 或 metadata。

#### 用 Docker 运行完整测试

如果没有使用过 Docker，可以把它理解成一次性测试环境。Docker Desktop 提供 Docker Engine。测试 runner 启动隔离的 PostgreSQL 和 Node
容器，使用 synthetic 数据运行 migration、check、fixture、integration 和并发测试，然后删除容器。它不连接 production，也不会修改 production
数据。

1. 打开 Docker Desktop，等待 Engine 完成启动。
2. 在仓库根目录确认当前目录：

   ```bash
   cd "$(git rev-parse --show-toplevel)"
   ```

3. 确认 Docker 同时显示 Client 和 Server：

   ```bash
   docker version
   ```

4. 运行完整套件：

   ```bash
   ./tool/run_postgres_tests_in_docker.sh
   ```

runner 会按 migration 文件名发现 0065 migration、directory check 和 fixture，并运行独立的 interest directory concurrency script、Backend
directory integration、checksum 和 dump／restore。恢复库重跑 migration、check 和 fixture，不重跑会提交 synthetic 行的并发脚本。
6BA 的 integration 必须读取自己的 interest directory fixture，不能读取 current-city integration 使用的
`CURRENT_CITY_RUNTIME_FIXTURE`。

#### 只调试专用 PostgreSQL 测试库

先确认 `DATABASE_URL` 不是 production。并发脚本会提交 synthetic 行，所以每次运行都使用新的空测试库。重复运行前先重建测试库，否则固定
主键冲突是预期结果。

```bash
export DATABASE_URL='postgresql://postgres:postgres@127.0.0.1:5432/tongxingzhe_test'
./tool/postgres_migrate.sh
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/checks/verify_authorized_management_interest_report_snapshot_directory.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/fixtures/0065_authorized_management_interest_report_snapshot_directory.sql
./tool/verify_authorized_management_interest_report_snapshot_directory_concurrency.sh
```

这些步骤分别检查 function signature、owner、`SECURITY DEFINER`、固定 search path、最小 ACL、approved interest provenance、撤权、跨项目、
空目录、20 项上限、稳定排序、value-free audit、audit 不可变和 runtime 不能直接调用 private function。check、fixture 和并发脚本不能互相
替代。

#### Backend directory integration 和 HTTP 测试

Backend adapter integration 应在自己的 transaction 中建立 synthetic identity、项目和快照，结束时回滚。它必须严格解析固定 root/item keys，
拒绝额外字段、重复项、乱序项、非法时间戳和超过 20 项。若单独运行编译后的 integration，使用该测试声明的 interest directory fixture 变量，
不要传入 current-city fixture。

从 `backend/server` 运行无数据库的 Backend 测试：

```bash
cd backend/server
npm ci --ignore-scripts
npm run check
npm test
```

测试覆盖认证先于 project UUID、query、GET body 和 store，固定 collection route、400／403／503 映射、错误脱敏、Promise gate、strict
metadata parser 和 `no-store`。这些测试证明 HTTP 和 adapter 合同。Docker 测试证明 PostgreSQL 合同；两者都不证明 Flutter、导出、缓存、离线、
生产身份、真实账号或六平台运行时。

管理报告发布端点同时改动 Backend 和 PostgreSQL bridge。开发时先运行：

```bash
npm --prefix backend/server run build
node --test backend/server/dist/test/management-report-release.test.js

./tool/run_postgres_tests_in_docker.sh
```

Backend 测试检查认证优先、精确 JSON、稳定错误和单 statement store；Docker 套件检查真实身份映射、固定报告、发布能力、幂等、撤权／时区并发以及 dump／restore。两者都不证明生产成员已经获得发布能力，也不等同于运行了自动发布调度。

只读离线计划缓存复用现有 `db_app_settings`，没有修改 Drift schema，因此不需要生成新的 Drift snapshot。`drift_personal_planning_cache_test.dart` 在测试进程的内存 SQLite 中检查 scope 隔离、远端空值、损坏缓存、仅网络故障回退，以及 `401/403` 后清除。只修改这层缓存时不需要启动 Docker；改动 Backend 或 PostgreSQL 周期函数时仍必须运行 Docker 套件。

### 6BE：验证渠道管理报告快照 replacement ledger

6BE 只在 private PostgreSQL 中登记已有 6J trusted-v2 渠道快照之间的直接 replacement 关系。它不生成新快照，不修改快照内容，也不改变目录、授权读取、HTTP、导出或 Flutter。
两份快照必须属于同一项目、report、version、query fingerprint、reporting time zone 和 release lineage。新快照的 cutoff 和发布时间必须晚于旧快照。
登记原因只允许 `late_accepted_data`、`contact_revision` 和 `contact_void`。分析定义修正和跨版本取代留给后续独立合同。
登记会在等待请求、项目和 lineage 锁后重新确认 `release_management_reports` 与 trusted-v2 provenance。

生命周期查询对可信渠道快照只返回快照 ID、`active`／`superseded` 状态和直接 replacement ID；未知或不可信来源返回 value-free `not_found`。
它不返回报告正文、cells、隐藏前值、来源、贡献者、地点、授权关系或 PII。
每份旧快照最多一个直接 replacement，每份新快照最多一个 predecessor。关系可以向前形成链，但不能自链接、循环或分叉。关系和最小审计追加不可变，不能 UPDATE 或 DELETE。
该切片不处理物理删除、tombstone、恢复期或 retention。current-city、interest 和 original-region 快照不复用本合同。

#### 第一次用 Docker 运行 6BE

Docker 是一次性测试环境。runner 会启动隔离的 PostgreSQL 和 Node 容器，使用 synthetic 数据，结束后清理容器。它不连接 production，也不会修改真实项目。

1. 打开 Docker Desktop，等待 Docker Engine 完成启动。
2. 在 Terminal 中进入仓库根目录：

   ```bash
   cd "$(git rev-parse --show-toplevel)"
   ```

3. 确认 Docker 同时有 Client 和 Server：

   ```bash
   docker version
   ```

   如果只显示 Client，没有 Server，先启动 Docker Desktop 或 Docker Engine。
4. 运行完整套件：

   ```bash
   ./tool/run_postgres_tests_in_docker.sh
   ```

runner 会按 migration 顺序发现 0067 migration、structural check、fixture 和 replacement concurrency script。
它还会运行 checksum、dump／restore，并在恢复库重跑 migration、check 和 fixture。恢复库不重跑并发脚本，因为并发脚本会提交 synthetic 行。

成功输出应覆盖：两份合法同项目 channel trusted-v2 快照、三项登记原因 allowlist、链式 replacement、`active`／`superseded` 查询、同 request 精确幂等、载荷漂移、
跨项目和跨 report family 拒绝、legacy／blocked／未知 provenance、stale head、自链接、分叉、循环、倒序时间、旧快照字节不变、value-free 结果、
追加不可变、最小 ACL、竞争登记和撤权锁顺序。命令退出码必须为 `0`。

#### 只调试专用 PostgreSQL 测试库

先确认 `DATABASE_URL` 指向专用测试库，不要指向 production。并发脚本会写入 synthetic 行，因此每次运行使用新的空测试库。

```bash
export DATABASE_URL='postgresql://postgres:postgres@127.0.0.1:5432/tongxingzhe_test'
./tool/postgres_migrate.sh
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/checks/verify_management_report_snapshot_replacements.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/fixtures/0067_management_report_snapshot_replacements.sql
./tool/verify_management_report_snapshot_replacements_concurrency.sh
```

check、fixture 和并发脚本不能互相替代。不要为了通过测试降低 provenance、授权、链或隐私条件。
Docker 通过只证明当前 PostgreSQL 中的 replacement ledger、授权锁、value-free 结果、不可变约束和 ACL。
它不证明新报告已经生成，不证明目录、读取、HTTP、导出、Flutter、生产身份、删除或 retention，也不证明 Android、iOS、macOS、Windows、Linux 或 Web 真人平台运行时。

### 6BN：验证原始区域快照更正版取代 lineage

6BN 与 6BE 使用不同的 replacement 合同。6BN 只登记两份已经通过 6BG 的 original-region approved snapshot 之间的直接 replacement，不生成新
snapshot，也不复用 6BE 的渠道 replacement ledger。两份快照必须属于同一 project、report／version、query fingerprint、privacy、source scope、
报告时区 revision、期间、release lineage 和精确的 `source_tree_version + source_content_fingerprint`。新快照的 cutoff 和发布时间都必须更晚。replacement
在管理报告共享的 value-free request UUID ledger 中使用独立 family claim；它与 release 共用 request lock，因此同一 UUID 无论先用于哪一方都不能被另一方复用。

登记原因只允许 `late_accepted_data`、`contact_revision` 和 `contact_void`。关系和最小 audit 追加且不可变；每份旧快照最多有一个直接 replacement，
每份新快照最多有一个 predecessor。请求与 lineage 锁取得后，数据库会再次确认发布记录和 provenance。相同 request UUID 与 canonical payload 精确幂等，
载荷漂移失败关闭。生命周期结果只返回 snapshot ID、`active`／`superseded` 和直接 replacement ID，不返回报告格、source、贡献者、地点、隐藏前值或 PII。

本切片只证明 DB-only、value-free 的关系合同。它不处理 current-city、interest 或其他 report family，不做分析定义／跨版本更正，不生成 snapshot，
也不增加 runtime、HTTP、Flutter、目录、导出、缓存、离线、分享、删除、tombstone、retention、备份清除、parent／overlap、warehouse 或真人平台验收。

#### 第一次运行 Docker

没有用过 Docker 也可以按以下步骤操作。Docker Desktop 提供一个临时 PostgreSQL 测试环境；runner 使用 synthetic 数据，不连接 production，结束时清理容器。

1. 打开 Docker Desktop，等待 Docker Engine 显示正在运行。
2. 打开 Terminal，进入仓库根目录：

   ```bash
   cd "$(git rev-parse --show-toplevel)"
   ```

3. 确认 Docker 同时有 Client 和 Server：

   ```bash
   docker version
   ```

   如果只显示 Client，没有 Server，先启动 Docker Desktop，再重复此命令。
4. 运行完整 PostgreSQL 测试：

   ```bash
   ./tool/run_postgres_tests_in_docker.sh
   ```

runner 会按 migration 顺序发现 0072 migration、structural check、rollback fixture 和 replacement concurrency script，然后运行 checksum 与 dump／restore。
恢复库会重跑 migration、check 和 fixture；不会重跑会提交 synthetic 行的并发脚本。完整通过只表示 synthetic PostgreSQL 的 6BN 合同通过。

成功输出应覆盖合法同项目 original-region 快照、独立 replacement family claim、release／replacement UUID 双向互斥、专用 provenance、同 source-tree tuple、后续 cutoff／发布时间、原因 allowlist、
`active`／`superseded` 生命周期、精确幂等、载荷漂移、跨项目／跨 family／legacy／blocked／drift、时间倒序、自链接、分叉、循环、stale head、
旧快照不变、value-free 结果、锁后授权、最小 ACL、并发、checksum 和 restore。命令退出码必须为 `0`。

#### 只调试 6BN

并发脚本会提交 synthetic 行。先确认 `DATABASE_URL` 指向专用测试库，不要指向 production；若要重复运行，请使用新的空测试库。

```bash
export DATABASE_URL='postgresql://postgres:postgres@127.0.0.1:5432/tongxingzhe_test'
./tool/postgres_migrate.sh
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/checks/verify_management_original_region_report_snapshot_replacements.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/fixtures/0072_management_original_region_report_snapshot_replacements.sql
./tool/verify_management_original_region_report_snapshot_replacements_concurrency.sh
```

check、fixture 和并发脚本不能互相替代。Docker 通过不证明新 snapshot 已生成，不证明目录、runtime、HTTP、Flutter、导出、缓存、离线、删除、retention、
生产身份或 Android、iOS、macOS、Windows、Linux、Web 真人平台运行时。

### 6BO：验证组织项目后续联系同意占比 opt-in 配置

6BO 只验证组织项目的配置生命周期。它不执行后续联系同意比例候选。个人项目的 0048 配置表与组织配置表必须分开。

配置 caller 是可信内部 `app_user_id`。数据库必须重新确认活动账号、组织／项目 membership、项目状态和 `release_management_reports` capability。
`view_anonymous_analytics` 不能修改配置。每次等待 request、项目配置或授权锁后，数据库都必须再次授权。项目 status 变更触发器与 configure 共享 project lock，
因此 archive↔configure 线性化；0030 resolver 不替代归档锁。

版本记录 `enabled`、预期版本、版本号、request UUID、授权 provenance 和数据库时间。历史不可 UPDATE／DELETE。相同 request UUID 的相同 payload 精确幂等。
载荷漂移、过期版本、撤权和并发双写失败关闭。未配置和停用返回 `not_enabled`，不返回 `0 / 0` 或覆盖数。

#### 第一次运行 Docker

1. 打开 Docker Desktop，等待 Docker Engine 显示正在运行。
2. 从仓库根目录确认 Docker：
   ```bash
   docker version
   ```
3. 运行完整 PostgreSQL 套件：
   ```bash
   ./tool/run_postgres_tests_in_docker.sh
   ```
4. 确认输出包含 0073 migration、6BO check、6BO fixture、6BO concurrency、checksum、restore check 和 restore fixture，并确认退出码为 `0`。

#### 只调试 6BO

并发脚本会提交 synthetic 行。先确认 `DATABASE_URL` 指向专用测试库，不要指向 production。实现 6BO 后运行：

```bash
export DATABASE_URL='postgresql://postgres:postgres@127.0.0.1:5432/tongxingzhe_test'
./tool/postgres_migrate.sh
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/checks/verify_management_follow_up_consent_opt_in.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/fixtures/0073_management_follow_up_consent_opt_in.sql
./tool/verify_management_follow_up_consent_opt_in_concurrency.sh
```

check 观察 migration、函数和 ACL 结构。fixture 调用正式函数并验证组织／个人隔离、授权、版本、幂等、停用和 value-free 结果。并发脚本用两个 PostgreSQL
会话验证配置双写与撤权锁。dump／restore 会重跑 migration、check 和 fixture，不重跑会提交 synthetic 行的并发脚本。

这组证据只证明 synthetic PostgreSQL 的 opt-in 配置合同。它不证明后续联系同意比例已经计算，不证明报告隐私抑制、runtime、HTTP、Flutter、缓存、离线、
删除、retention、生产身份或 Android、iOS、macOS、Windows、Linux、Web 真人平台运行时。

### 6BP：验证组织项目后续联系同意占比候选

6BP 的 0074 migration 生成 private release-candidate。它只供未来 release workflow 使用，不生成 snapshot 或正式报告。
候选固定 `contact_target_follow_up_consent_ratio_two_periods@1`、`follow_up_consent_ratio@1` 和 `contact_target_link`。
候选使用两个相邻且已经结束的完整 ISO 周。数据库在读取 link 前重新确认组织／项目 membership、项目状态、`release_management_reports` capability 和 6BO opt-in。

`yes` 是分子，`yes + no` 是分母。`unknown` 计入 unanswered，`refused` 与 `not_applicable` 是独立 coverage cell。
yes、no 和每个 coverage cell 都必须满足 `N >= 10`、至少三位 contributor、贡献者不超过该 cell 总数一半。
只有 yes/no 都通过保护时才返回比例数值。任何未通过保护的值都返回 `suppressed` 和 `null`。未配置或停用时，executor 在读取 link 前返回 `not_enabled`，不返回 report、ratio 或 coverage。
`not_enabled` 表示没有当前 opt-in；`suppressed` 表示已启用但该值没有通过保护。两者都不表示零。

#### 第一次运行 Docker

1. 打开 Docker Desktop，等待 Docker Engine 显示正在运行。
2. 从仓库根目录确认 Docker：
   ```bash
   docker version
   ```
3. 运行完整 PostgreSQL 套件：
   ```bash
   ./tool/run_postgres_tests_in_docker.sh
   ```
4. 确认输出包含 0074 migration、6BP check、6BP fixture、6BP concurrency、checksum、restore check 和 restore fixture，并确认退出码为 `0`。

runner 会在源库建立专用 closed role，再运行 migration、structural check、rollback fixture、并发脚本和 checksum 检查。dump／restore 阶段先准备独立 cluster roles，
再用 `pg_restore` 重建恢复库，并只重跑 check 和 fixture。恢复库不重新执行 migration，也不重跑会提交 synthetic 行的并发脚本；同一 PostgreSQL cluster 的已有角色不能替代这项恢复验证。

#### 只调试 6BP

并发脚本会提交 synthetic 行。先确认 `DATABASE_URL` 指向专用测试库，不要指向 production。运行：

```bash
export DATABASE_URL='postgresql://postgres:postgres@127.0.0.1:5432/tongxingzhe_test'
./tool/postgres_migrate.sh
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/checks/verify_management_follow_up_consent_ratio.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/fixtures/0074_management_follow_up_consent_ratio.sql
./tool/verify_management_follow_up_consent_ratio_concurrency.sh
```

check 验证 contract、`SECURITY DEFINER`、固定 search path、专用 role 和最小 ACL。fixture 验证统计单位、候选集排除、yes/no 成对保护、coverage 独立保护、`not_enabled`／`suppressed` 和 value-free 输出。
并发脚本验证 candidate 与 disable、capability revoke、membership revoke、project archive 的锁线性化。

这些命令只证明 synthetic PostgreSQL 的 private candidate 合同。它们不证明 snapshot、release、authorized read、runtime、HTTP、Backend、Flutter、Drift、UI、导出、缓存、离线、生产身份或
Android、iOS、macOS、Windows、Linux、Web 真人平台运行时，也不构成形式化不可重识别保证。

### 6BQ：验证后续联系同意占比快照发布

6BQ 的 0075 migration 把 6BP 已保护的 completed candidate 固定为不可变 snapshot。它不开放读取。专用 release writer、attempt、request claim family 和 RLS policy 把该 lineage 与渠道、区域和兴趣报告分开。

发布事务重新确认 `release_management_reports`、membership、项目状态、报告时区 revision 和 6BO opt-in，再调用 0074 executor。数据库从 `change_feed` 取得 source watermark。调用方不能提交 candidate JSON、cutoff、时区或 watermark。首份 completed candidate 建立 baseline；后续成功发布链接 predecessor。`not_enabled` 不创建 snapshot；blocked attempt 不保存 ratio、coverage 或其他候选内容。

#### 从零开始运行 Docker

1. 打开 Docker Desktop，等待 Docker Engine 运行。
2. 在仓库根目录运行 `docker version`，确认 client 和 server 都有输出。
3. 运行完整套件：
   ```bash
   ./tool/run_postgres_tests_in_docker.sh
   ```
4. 确认输出包含 0075 migration、6BQ check、6BQ fixture、6BQ concurrency、checksum、restore check 和 restore fixture，且退出码是 `0`。

runner 自动建立一次性 PostgreSQL 16 容器。fixture 在 transaction 结束时回滚；并发脚本使用另一组 synthetic UUID 并提交，以观察真实的会话竞争。dump／restore 阶段先准备 closed roles，再通过 `pg_restore` 重建独立恢复库。恢复库只重跑 check 和 fixture，不重新执行 migration，也不重跑并发脚本。

#### 只调试 6BQ

以下命令会修改指定数据库。先确认它是可以丢弃的测试库，不是 production：

```bash
export DATABASE_URL='postgresql://postgres:postgres@127.0.0.1:5432/tongxingzhe_test'
./tool/postgres_migrate.sh
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/checks/verify_management_follow_up_consent_ratio_snapshot_lineage.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/fixtures/0075_management_follow_up_consent_ratio_snapshot_lineage.sql
./tool/verify_management_follow_up_consent_ratio_snapshot_lineage_concurrency.sh
```

check 观察函数、owner、RLS 和 ACL。fixture 验证 validator、baseline、successor、幂等、blocked 和不可变性。并发脚本验证同 request、同 lineage，以及 release 与停用、撤权、归档的锁顺序。这些 synthetic DB-only 证据不证明 authorized read、runtime、HTTP、Backend、Flutter、生产身份或六平台真人运行时。

### 6BR：验证后续联系同意占比快照授权读取

6BR 的 0076 migration 只读取一份明确指定的 6BQ snapshot。调用方提供内部用户、project UUID 和 snapshot UUID；数据库重新检查 `view_anonymous_analytics`，再复核 0075 claim、approved attempt、snapshot、时区 revision、cutoff、previous pointer 和 source watermark。它不会重新计算 ratio，也不会恢复 suppressed 值。

读取成功返回既有 protected report。unknown 或 cross-project UUID 返回 `not_found`；同项目但 provenance 不可信的 snapshot 返回 `untrusted_provenance`。两种失败均不返回正文。每次已授权调用写入不含 report、ratio、coverage、contact、target、contributor、原始回答或 PII 的 value-free audit。

#### 从零开始运行 Docker

1. 打开 Docker Desktop，等待 Docker Engine 运行。
2. 在仓库根目录运行 `docker version`。client 和 server 都有输出才表示 Docker 可以执行容器。
3. 运行完整套件：
   ```bash
   ./tool/run_postgres_tests_in_docker.sh
   ```
4. 确认输出包含 0076 migration、6BR check、6BR fixture、6BR concurrency、checksum、restore check 和 restore fixture，且退出码是 `0`。

runner 自动建立一次性 PostgreSQL 16 容器。fixture 在 transaction 结束时回滚；并发脚本使用独立 synthetic UUID 并提交，以观察真实的 read／revoke 竞争。dump／restore 阶段先准备既有 closed roles，再通过 `pg_restore` 重建恢复库。恢复库只重跑 check 和 fixture，不重新执行 migration，也不重跑会提交行的并发脚本。

#### 只调试 6BR

以下命令会修改指定数据库。先确认它是可丢弃的测试库，不是 production：

```bash
export DATABASE_URL='postgresql://postgres:postgres@127.0.0.1:5432/tongxingzhe_test'
./tool/postgres_migrate.sh
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/checks/verify_authorized_management_follow_up_consent_ratio_snapshot_read.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/fixtures/0076_authorized_management_follow_up_consent_ratio_snapshot_read.sql
./tool/verify_authorized_management_follow_up_consent_ratio_snapshot_read_concurrency.sh
```

check 观察函数、owner、固定 search path 和 ACL。fixture 验证合法 baseline／successor、重复读取、`not_found`、`untrusted_provenance`、再次 validator、授权负例、value-free audit 和不可变性。并发脚本验证 read-first 与 revoke-first 的锁线性化。

这些 synthetic DB-only 证据只证明本地 PostgreSQL 合同。它们不证明 runtime identity bridge、HTTP、Backend、目录、Flutter、导出、生产身份或 Android、iOS、macOS、Windows、Linux、Web 真人平台运行时，也不构成形式化不可重识别保证。

### 6BS：验证后续联系同意占比快照 runtime bridge

6BS 把 0076 private read 接到 Backend runtime。调用方必须先由 Backend 验证 external identity，再把 exact `issuer + subject`、显式 project UUID 和 snapshot UUID 交给 0077 bridge。bridge 不 trim identity、不创建账号，也不自动选择 snapshot。

runtime 只有 bridge `EXECUTE`。授权、0075 provenance、6BQ validator、撤权锁和 value-free audit 仍由 0076 负责。Backend adapter 只执行一次固定参数化 SQL，并 strict parse 固定 consent-ratio report；它不能重算 ratio 或恢复 suppressed 值。

#### 从零开始运行 6BS

1. 打开 Docker Desktop，等待 Docker Engine 运行。
2. 在仓库根目录运行 `docker version`。client 和 server 都有输出后再继续。
3. 运行 Backend 合同测试：
   ```bash
   cd backend/server
   npm ci --ignore-scripts
   npm run check
   npm test
   cd ../..
   ```
4. 运行完整 PostgreSQL 套件：
   ```bash
   ./tool/run_postgres_tests_in_docker.sh
   ```
5. 确认输出包含 0077 migration、6BS check、6BS fixture、新 Backend integration、0076 read／revoke concurrency、checksum、restore check 和 restore fixture，且退出码为 `0`。

runner 自动建立一次性 PostgreSQL 16 容器。0077 fixture 在 transaction 结束时回滚。0076 并发脚本使用独立 namespace 并提交，用于验证 private read 与撤权的真实锁顺序。dump／restore 阶段先准备既有 roles，再通过 `pg_restore` 重建恢复库；恢复库只重跑 check 和 fixture，不重新执行 migration，也不重跑并发脚本。

#### 只调试 6BS

以下命令会修改指定数据库。先确认它是可丢弃的测试库：

```bash
export DATABASE_URL='postgresql://postgres:postgres@127.0.0.1:5432/tongxingzhe_test'
./tool/postgres_migrate.sh
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/checks/verify_runtime_authorized_management_follow_up_consent_ratio_snapshot_read.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/fixtures/0077_runtime_authorized_management_follow_up_consent_ratio_snapshot_read.sql
```

check 验证函数签名、owner、固定 search path、exact identity body 和最小 ACL。
fixture 验证 active／unknown／inactive／release-only identity、空白变体、`completed`／`not_found`／`untrusted_provenance`、重复 value-free audit 和 runtime 直接访问拒绝。
Backend unit 验证一次 SQL、strict parser、PII 拒绝和只映射 SQLSTATE `42501`。PostgreSQL integration 以真实 runtime role 调用 bridge。

这些 synthetic 证据只证明 6BS runtime bridge 与 Backend adapter；6BS 当时不包含 HTTP，后续 6BT 单独提供 HTTP 证据。它们不证明 Flutter、生产 identity provider、
真实账号或 Android、iOS、macOS、Windows、Linux、Web 真人平台运行时，也不构成形式化不可重识别保证。

### 6BT：验证后续联系同意占比快照 HTTP 读取

6BT 只把 6BS 的专用 store 接到固定的 HTTP 详情路径：

```text
GET /v1/projects/:projectId/management-follow-up-consent-ratio-report-snapshots/:snapshotId
```

这里的“先认证”是安全顺序要求。固定 path 命中后，handler 先解析并验证 Bearer identity；只有认证成功后，才检查两个 UUID、query、GET body 的
非零 `Content-Length`／`Transfer-Encoding` 声明和 6BS 专用 store。没有 token 或 token 无效时，即使 UUID、query、body 或 store 有问题，也先返回
`401 unauthenticated`。认证通过后，handler 只把 verified `issuer + subject`、显式 project UUID 和 snapshot UUID 传给
`PostgresManagementFollowUpConsentRatioReportSnapshotStore`，并等待 store Promise 完成后再写响应。

GET 不接受 query 参数或 body。成功响应固定只有 `access_event_id`、`snapshot_id` 和 `report` 三个字段；`report` 保留 6BR／6BS 已保护的
consent-ratio report，HTTP 层不重算 ratio、不恢复 `suppressed` 值，也不修改 snapshot。

错误 code 固定为：

| HTTP 状态 | code |
| --- | --- |
| `401` | `unauthenticated` |
| `400` | `invalid_management_follow_up_consent_ratio_report_snapshot_request` |
| `403` | `management_follow_up_consent_ratio_report_snapshot_forbidden` |
| `404` | `management_follow_up_consent_ratio_report_snapshot_not_found` |
| `409` | `management_follow_up_consent_ratio_report_snapshot_untrusted` |
| `503` | `management_follow_up_consent_ratio_report_snapshot_unavailable` |

`404`／`409` 可以带 6BS store 返回的 value-free `access_event_id`，但错误不得包含报告格、授权关系、external subject、数据库消息、SQL、栈或
PII。所有成功和错误响应都使用 `Content-Type: application/json; charset=utf-8` 与 `Cache-Control: no-store`。

#### 第一次用 Docker 的读者要知道什么

6BT 的 HTTP、route 和 composition 测试不需要 Docker。Docker 是另一个隔离的测试环境：它启动临时 PostgreSQL 和 Node 容器，使用 synthetic
数据，完成后删除容器；它不会连接 production。若电脑上没有 Docker，请先安装并打开 Docker Desktop，等待 Docker Engine 显示运行。只验证
HTTP 时，从仓库根目录运行：

```bash
cd backend/server
npm ci --ignore-scripts
npm run check
npm test
```

这些测试使用 synthetic identity 和 fake store，覆盖固定 method／path、认证先于 malformed UUID／query／GET body／store、三字段 success wire、
`401`／`400`／`403`／`404`／`409`／`503`、错误脱敏、Promise gate 和 `no-store`。不需要真实账号或 JWT provider。

6BT 不增加 migration、database check、fixture、PostgreSQL integration 或并发脚本。若要连同既有 6BS 数据库合同一起检查，回到仓库根目录运行：

```bash
cd ../..
./tool/run_postgres_tests_in_docker.sh
```

Docker runner 仍验证 0077 bridge、0076 reader、授权、provenance、strict parser、audit、并发、checksum 和 restore；它不替代 6BT HTTP 测试。
这些 synthetic HTTP 和 Docker 结果不证明 production identity、已部署端点、Flutter、真实账号或 Android、iOS、macOS、Windows、Linux、Web 真人平台运行时。

### 6BU：验证后续联系同意占比快照目录

6BU 是 SQL-only 合同。0078 migration 为一个显式 project 增加 private directory 函数：

```text
app_private.list_authorized_management_follow_up_consent_snapshots_v1(uuid, uuid)
```

函数每次调用重新确认 active user、组织／项目 membership、active project 和 `view_anonymous_analytics`。目录读取与授权撤回沿既有 lock order，避免撤权竞态绕过授权。
它只接受 0075 consent-ratio family 的 `approved_baseline`／`approved` exact provenance；foreign project、foreign family、legacy、blocked、missing 或 drifted provenance
必须失败关闭或被排除。

成功结果的 root envelope 固定为 `access_contract_id`、`access_event_id`、`project_id` 和 `snapshots` 四项。
`snapshots` 最多 20 项，每项只有 `snapshot_id`、`report_id`、`report_version`、`reporting_time_zone`、`data_cutoff_utc` 和 `released_at_utc`。
数据库按 `data_cutoff_utc DESC`、`released_at_utc DESC`、`snapshot_id DESC` 排序。第一项只是排序结果，不表示 current、latest 或未被取代。没有合格快照的已授权
project 返回空数组，并写数量为 0 的成功 audit。

目录 audit 使用专用追加式、不可变、value-free 结构，只记录授权和访问 metadata。它不记录 snapshot ID、报告内容、period、ratio、coverage、source、contributor、
target、contact 或 PII。`PUBLIC`、runtime、普通 app role 和其他 report reader／writer 不能执行 private function 或读取 audit。

#### 从零开始运行 6BU

1. 打开 Docker Desktop，等待 Docker Engine 显示运行。
2. 在仓库根目录运行 `docker version`。Client 和 Server 都有输出后再继续。
3. 运行完整 PostgreSQL 套件：

   ```bash
   ./tool/run_postgres_tests_in_docker.sh
   ```

4. 确认输出包含 0078 migration、structural check、rollback fixture、directory／revoke concurrency、checksum、restore check 和 restore fixture，且退出码为 `0`。

runner 自动建立一次性 PostgreSQL 16 容器。源库执行 0078 migration、check、fixture 和并发脚本；fixture 在 transaction 结束时回滚，并发脚本使用独立 committed namespace。
恢复阶段先准备缺失的 PostgreSQL roles，再使用 dump 重建独立恢复库。恢复库重跑 check 和 fixture，不重跑会提交 synthetic 行的并发脚本。

这些测试只使用 synthetic 数据。通过结果只证明 PostgreSQL 的 provenance、授权、目录上限与排序、value-free audit、锁顺序、ACL、checksum 和恢复合同。
它不证明 runtime identity、Backend、HTTP、Flutter、部署服务、production data、缓存、离线或 Android、iOS、macOS、Windows、Linux、Web 真人平台运行时。
前序 6BS／6BT 已定义 runtime、Backend 和 HTTP；6BU 不修改这些边界。

#### 只调试 6BU

以下命令会修改指定数据库。先确认它是可丢弃的测试库，不是 production：

```bash
export DATABASE_URL='postgresql://postgres:postgres@127.0.0.1:5432/tongxingzhe_test'
./tool/postgres_migrate.sh
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/checks/verify_authorized_management_follow_up_consent_ratio_snapshot_directory.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/fixtures/0078_authorized_management_follow_up_consent_ratio_snapshot_directory.sql
./tool/verify_authorized_management_follow_up_consent_ratio_snapshot_directory_concurrency.sh
```

check 验证 canonical function、owner、固定 search path、`SECURITY DEFINER`、最小 ACL 和无 `PUBLIC` execute。fixture 验证 20 项上限、固定排序、baseline／successor、
空目录、重复读取、exact provenance、负例、zero-count audit、value-free audit 和不可变性。并发脚本验证 directory-first 与 revoke-first 的线性化。

### 6BF：理解管理报告删除与保留边界

6BF 是产品和测试合同，不是数据库清理功能。没有用过 Docker 的读者先记住：Docker runner 会在一次性容器中验证当前仓库已有的 PostgreSQL 行为。
本切片没有新增 migration、check、fixture 或并发脚本，所以重新运行 Docker 不能证明管理报告已经删除。

五个容易混淆的动作有不同结果：

- 授权撤回立即阻止该成员读取、发布和导出，但不删除报告。
- 账号删除期满后，组织报告继续保留；自然人归属改为不可反查的“已删除成员”。
- 更正版取代只登记新旧快照的 lineage，旧快照仍存在。
- 组织删除申请后的三十天是只读恢复期。仍获授权的成员可以读取已有报告，但不能发布、登记 replacement 或导出。
- 组织删除期满后，未来 Slice 7 删除全部 report family 和含业务内容的依赖，只保留最小组织删除审计。

管理报告没有按创建时间计算的独立 TTL。三十天是组织或账号删除的恢复期，不是报告年龄。组织在期限内恢复时，既有报告保持原状，
系统不写 tombstone 或清除资格。

清除失败时必须失败关闭。组织和报告保持不可访问，不能因为一部分表已处理就返回成功。logical tombstone 只能证明读取门禁，
purge eligibility 只能证明可以开始清理；两者都不能证明报告正文或 PII 已从底层存储清除。

备份也有独立边界。Docker 的 dump／restore 检查验证 schema、角色和 synthetic fixture 可以恢复。它不验证 production 备份期限或灾备副本清除。
真实恢复副本必须先重放已完成的组织删除事实，再对外提供服务，防止已删除组织的数据复活。

本切片的本地检查只需要文档命令：

```bash
git diff --check
dart run tool/check_markdown_links.dart
```

如果同时修改了数据库行为，仍要另外运行完整套件：

```bash
./tool/run_postgres_tests_in_docker.sh
```

看到 Docker 成功只能记录“既有 PostgreSQL 合同仍通过”。不能记录 logical gate、物理清除、production 备份清除或真人平台删除已经通过。
未来 Slice 7 的实现必须分别验证恢复期、按时恢复、重复请求、账号删除、全部 report family、replacement 链、失败重试、最小删除审计和恢复副本。

### 6BG：验证原始区域报告 snapshot/release lineage

6BG 在 6BD 的 original-region 报告候选之上增加不可变 snapshot 和独立发布 lineage。它不是读取功能，也不是删除功能。
6BD executor 负责生成一次受保护候选；6BG 负责在数据库内确认发布能力、固定报告时区 revision、source tree tuple、cutoff 和 source watermark，
再保存 baseline 或后续 successor。channel、current-city 和 interest 使用自己的 release family，不能把它们的 snapshot 或 request UUID 当作 6BG 的来源。

6BG 的 blocked attempt 只保存固定原因和最小 lineage metadata。它不能保存候选报告、cells、隐藏前值、来源、contact、contributor、区域名称、坐标或 PII。
因此，查询 attempt 表时看不到“被拒绝候选的报告值”是预期行为。这个 slice 也不增加 authorized read、runtime bridge、HTTP、Flutter、目录、导出、
缓存、离线、同步、parent／overlap 下钻、任意历史 `as-of`、replacement、删除或 retention。

#### 第一次用 Docker 运行 6BG

Docker 是一次性测试环境。runner 会建立隔离的 PostgreSQL 和 Node 容器，使用 synthetic 数据，完成后删除容器。它不连接 production，也不会修改真实项目。

从仓库根目录运行完整套件：

```bash
cd "$(git rev-parse --show-toplevel)"
./tool/run_postgres_tests_in_docker.sh
```

runner 会自动发现 0068 migration、structural check、fixture 和 original-region snapshot lineage concurrency script。它会先从空库运行 migration，
然后运行 check、可回滚 fixture、并发脚本、checksum drift 检查和 dump／restore。restore 流程先运行
`tool/postgres_prepare_restore_roles.sh`，因为 PostgreSQL schema dump 不包含 cluster roles；新的 original-region snapshot release writer
必须在恢复 cluster 中重新建立，并保持 `NOLOGIN`、无成员和最小 ACL。

恢复库会重跑 migration、check 和 fixture，但不重跑并发脚本。并发脚本会提交 synthetic 行，若在恢复库再次运行，会把源库已经保存的测试行与新 fixture 混在一起。
fixture 和并发脚本必须使用互不重复的 `6bg*` 与 `6bgc*` 命名空间，断言按 workspace、project 和 release lineage 过滤。

成功输出只能记录以下层级：0068 migration 已应用；structural check、rollback fixture 和 concurrency 已通过；checksum 未漂移；dump／restore 后 restore role、check 和 fixture 通过。
这些结果证明 synthetic PostgreSQL 的 snapshot/release、授权、request claim、lineage、幂等、并发、不可变性、value-free blocked attempt 和 ACL 合同。
它们不证明报告已可读取，不证明 runtime、HTTP、Flutter、导出、生产身份、组织删除、物理清除、生产备份或六平台真人运行时已经完成。

#### 只调试 6BG 专用 PostgreSQL 测试库

先确认 `DATABASE_URL` 指向新的专用测试库，不要指向 production。并发脚本会提交 synthetic 行，所以每次从空库开始：

```bash
export DATABASE_URL='postgresql://postgres:postgres@127.0.0.1:5432/tongxingzhe_test'
./tool/postgres_migrate.sh
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/checks/verify_management_original_region_report_snapshot_lineage.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/fixtures/0068_management_original_region_report_snapshot_lineage.sql
./tool/verify_management_original_region_report_snapshot_lineage_concurrency.sh
```

check、fixture 和并发脚本不能互相替代。它们应分别检查固定 original document validator、专用 writer role／RLS、request claim family、baseline、后续 cutoff、
previous／compared snapshot、source tree tuple、source watermark、授权仍有效时的幂等、blocked value-free 结果、竞争 successor、撤权锁顺序和 direct mutation rejection。
若只运行 check 和 fixture，没有并发证据；若只运行并发脚本，也没有完整的 restore 或结构证据。

### 6BH：验证授权原始区域快照读取

6BH 只在 private PostgreSQL 中读取一份明确指定的 6BG snapshot。调用方提供内部用户、project UUID 和 snapshot UUID；数据库重新检查
`view_anonymous_analytics`，再核对 0068 original-region request claim、approved attempt、snapshot、报告时区 revision、cutoff、previous pointer、
source watermark 和 source tree tuple。返回前再次运行 6BD validator。它不会重算区域归属，也不会自动选择 latest。

结果分三类：

- `completed`：provenance 完整可信，返回既有 protected report；
- `not_found`：snapshot 未知或属于其他项目，不返回正文，也不暴露其他项目是否存在该 ID；
- `untrusted_provenance`：snapshot 在同一项目存在，但属于其他 report family、legacy、blocked，或 provenance 缺失／漂移，不返回正文。

每次已授权尝试都会写一条原始区域专用、不可变、value-free audit。audit 不保存 `protected_report`、cells、隐藏前值、来源记录、contact、
contributor、区域名称、坐标或 PII。`untrusted_provenance` audit 的 source tree tuple 和 watermark 固定为 `NULL`。未授权、撤权、过期、
只有发布能力、无项目成员或 inactive project 会在写 audit 前失败。

#### 第一次用 Docker 运行 6BH

先启动 Docker Desktop。你不需要手工安装 PostgreSQL、创建数据库或准备账号。runner 使用 synthetic 数据建立临时 PostgreSQL 和 Node 容器，
完成后自动删除；它不连接 production，也不会修改真实项目。从仓库根目录运行：

```bash
cd "$(git rev-parse --show-toplevel)"
./tool/run_postgres_tests_in_docker.sh
```

runner 会自动发现 0069 migration、structural check、rollback fixture 和 read／revoke concurrency script。之后它检查历史 migration checksum，
把源库 dump 恢复到没有源 cluster state 的独立 PostgreSQL，再在恢复库重跑 migration、check 和 fixture。恢复库不重跑并发脚本，因为并发脚本
会提交 synthetic 行；重复提交会混淆恢复证据。fixture 使用 `6bh*`；并发脚本的文本键使用 `6bhc*`，UUID 使用独立且符合十六进制格式的 `6fc*` namespace。

成功输出只能说明：0069 已应用；结构、行为、撤权顺序和最小 ACL 在 synthetic PostgreSQL 中通过；历史 migration 未漂移；dump／restore 后合同仍成立。
它不能证明 runtime bridge、HTTP、Flutter、目录、导出、production identity、删除、备份清除或真人平台运行时已经完成。

#### 只调试 6BH 专用 PostgreSQL 测试库

先确认 `DATABASE_URL` 指向新的专用测试库，绝不能指向 production。并发脚本会提交 synthetic 行，所以重复执行前应重建空库：

```bash
export DATABASE_URL='postgresql://postgres:postgres@127.0.0.1:5432/tongxingzhe_test'
./tool/postgres_migrate.sh
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/checks/verify_authorized_management_original_region_report_snapshot_read.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/fixtures/0069_authorized_management_original_region_report_snapshot_read.sql
./tool/verify_authorized_management_original_region_report_snapshot_read_concurrency.sh
```

check 证明对象形状、owner、`SECURITY DEFINER`、固定 search path 和 ACL。fixture 证明合法／不可信／未知结果、再次 validator、value-free audit 和不可变性。
并发脚本用两个独立数据库会话证明 read-first 与 revoke-first 的锁顺序。三者不能互相替代，完整 Docker 还负责 checksum 与 restore。

### 6BI：验证原始区域快照 runtime bridge

6BI 把 6BH 的 0069 private read 接到 Backend runtime。它只接受 Backend 已验证的 exact external `issuer + subject`、显式 project UUID 和 snapshot UUID。
它不接受内部用户 ID、capability、`SessionContext`、时区、截止点、source tree tuple、筛选或 SQL。0070 bridge 只调用 0069 private function，runtime
只有 bridge `EXECUTE`。

Backend adapter 只执行一次固定参数化 SQL。strict parser 检查固定 envelope、请求和解析出的 snapshot、状态、reason code、项目绑定，以及
original-region report 的 17 个固定 keys。`completed` 还必须有 selected source tree tuple、两个完整期间、连续 `cell_order`、安全整数和
`suppressed = null`。parser 拒绝额外字段、其他 report family、城市名称、坐标、来源记录、贡献者、contact 和 PII。它只把 SQLSTATE `42501` 映射为
typed `forbidden`。`not_found` 和 `untrusted_provenance` 不含报告正文。

#### 第一次用 Docker 运行 6BI

Docker 是一次性测试环境。Docker Desktop 提供 Docker Engine。runner 启动隔离的 PostgreSQL 和 Node 容器，使用 synthetic 数据运行测试，完成后删除容器。
它不连接 production，也不会修改真实项目。

1. 打开 Docker Desktop，等待 Engine 完成启动。
2. 在仓库根目录运行：

   ```bash
   cd "$(git rev-parse --show-toplevel)"
   ./tool/run_postgres_tests_in_docker.sh
   ```

runner 自动发现 0070 migration、structural check 和 rollback fixture，并显式运行原始区域 runtime integration。它还运行 0069 read／revoke 并发、checksum
和 dump／restore。恢复库先准备 restore roles，再重跑 migration、check 和 fixture，不重跑会提交 synthetic 行的并发脚本。

成功输出只能说明 0070 bridge、Backend adapter、strict parser 和 ACL 在 synthetic PostgreSQL 中通过。0069 的 read／revoke 并发仍是 private read 的证据。
这些结果不证明 HTTP、Flutter、目录、导出、生产 identity provider、真实账号或六平台真人运行时。

#### 只调试 6BI 专用 PostgreSQL 测试库

只有 Docker runner 已能工作，或需要定位单项失败时，才使用专用测试库。先确认 `DATABASE_URL` 指向新的空测试库，绝不能指向 production：

```bash
export DATABASE_URL='postgresql://postgres:postgres@127.0.0.1:5432/tongxingzhe_test'
./tool/postgres_migrate.sh
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/checks/verify_runtime_authorized_management_original_region_report_snapshot_read.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/fixtures/0070_runtime_authorized_management_original_region_report_snapshot_read.sql
```

然后运行 Backend 的静态检查和测试：

```bash
cd backend/server
npm ci --ignore-scripts
npm run check
npm test
```

这些命令使用 synthetic identity 和 snapshot，不需要真实账号。check、fixture、Backend test 和 Docker suite 不能互相替代。0070 没有新的提交型并发脚本，
因为 0069 已覆盖 read／revoke 锁顺序。通过只证明 DB-only bridge、adapter parser 和最小 ACL。

### 6BJ：验证原始区域快照 HTTP 读取

6BJ 把 6BI 的专用 store 接到一个固定的 HTTP GET：

```text
GET /v1/projects/:projectId/management-original-region-report-snapshots/:snapshotId
```

这里的“先认证”是一个安全顺序要求。handler 先解析并验证 Bearer identity；只有认证成功后，才检查两个 UUID、query、GET body 的
`Content-Length`／`Transfer-Encoding` 声明和专用 store。没有 token 或 token 无效时，即使 path、query、body 或 store 不合法，也先返回
`401 unauthenticated`。认证通过后，handler 只把 verified identity、显式 project UUID 和 snapshot UUID 传给 6BI
`ManagementOriginalRegionReportSnapshotStore`，并等待 store Promise 完成后再写响应。

成功响应固定只有三个字段：

```json
{
  "access_event_id": "…",
  "snapshot_id": "…",
  "report": {}
}
```

错误 code 固定为：`400 invalid_management_original_region_report_snapshot_request`、`403 management_original_region_report_snapshot_forbidden`、
`404 management_original_region_report_snapshot_not_found`、`409 management_original_region_report_snapshot_untrusted` 和
`503 management_original_region_report_snapshot_unavailable`。认证错误使用 `401 unauthenticated`；`404`／`409` 可以带 value-free
`access_event_id`。所有成功和错误响应都使用 JSON 与 `Cache-Control: no-store`，不返回数据库消息、SQL、栈、external subject、授权关系、报告格、来源、贡献者、区域名称、坐标或 PII。

HTTP 层不调用 generic、current-city 或 interest store，不使用 `SessionContext`、`app_private` 或客户端 SQL。production composition 只注入
6BI 的 Postgres store。6BJ 没有新的 migration、database check、fixture、PostgreSQL integration 或并发脚本。

#### 第一次用 Docker 的读者要知道什么

本节的 HTTP 测试不需要 Docker。Docker 是另一个隔离的测试环境：它启动临时 PostgreSQL 和 Node 容器，使用 synthetic 数据，完成后删除容器；它不会连接 production。若电脑上没有 Docker，请先安装并打开 Docker Desktop，等待 Docker Engine 显示运行。

只验证 6BJ HTTP 时，从仓库根目录运行：

```bash
cd backend/server
npm ci --ignore-scripts
npm run check
npm test
```

这些命令使用 synthetic identity 和 fake store，检查固定 method／path、认证先于 malformed UUID／query／GET body／store、所有状态映射、错误脱敏、
Promise gate、production composition 和 `no-store`。不需要真实账号、真实 JWT provider 或数据库。

若要连同既有数据库合同一起检查，回到仓库根目录运行：

```bash
cd ../..
./tool/run_postgres_tests_in_docker.sh
```

runner 会自动运行既有 0069／0070 migration、check、fixture、integration、checksum 和 dump／restore。6BJ 不新增 Docker 数据库步骤，也不让 Docker
结果替代 HTTP 测试。完整通过只能证明 synthetic PostgreSQL 的 private read、runtime bridge、parser 和 ACL；它不证明 6BJ HTTP、Flutter、导出、缓存、离线、production identity 或六平台真人运行时。

### 6BK：验证原始区域快照 metadata-only 目录

6BK 为 6BG original-region snapshot 增加专用目录。目录只返回选择 6BJ 详情所需的最小 metadata，最多 20 项，并按 cutoff、release time 和 snapshot ID
固定降序。第一项不表示 current、latest 或未被取代。数据库每次重新检查 identity、项目成员和 `view_anonymous_analytics`，再复核 original-region
release provenance。其他报告族、legacy、blocked、跨项目或漂移快照不会进入目录。

#### 第一次运行 Docker

Docker 在这里是一台临时测试电脑。脚本会下载 PostgreSQL 16 镜像，启动隔离容器，从 `0001` 运行到 `0071`，执行 checks、fixtures、并发和 Backend
integration，再导出并恢复数据库。脚本结束后会删除容器。它不连接 production，也不会修改 production 数据。

1. 安装并打开 Docker Desktop。
2. 等待 Docker Desktop 显示 Engine 正在运行。
3. 打开终端，进入仓库根目录。
4. 运行：

```bash
./tool/run_postgres_tests_in_docker.sh
```

第一次运行通常较慢，因为 Docker 要下载镜像。以后只要镜像仍在本机，启动会更快。脚本成功时会完成 migration checksum、并发、Backend integration 和
dump／restore；失败时先读最后一个带 `check:`、`fixture:`、`concurrency:` 或 `Backend integration:` 的名称，这就是最小调试入口。

runner 自动发现 0071 migration、structural check 和 rollback fixture。它显式运行 original-region directory integration，并自动发现独立并发脚本。
fixture 使用 rollback 数据；并发脚本使用另一组已提交 synthetic ID。dump 会保留并发行，所以恢复库只重跑 migration、check 和 fixture，不重跑并发脚本。

#### 只调试 6BK

若已有专用本地 PostgreSQL 测试库，先确认它不是 production，再运行：

```bash
export DATABASE_URL='postgresql://postgres:postgres@127.0.0.1:5432/tongxingzhe_test'
./tool/postgres_migrate.sh
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/checks/verify_authorized_management_original_region_report_snapshot_directory.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/fixtures/0071_authorized_management_original_region_report_snapshot_directory.sql
./tool/verify_authorized_management_original_region_report_snapshot_directory_concurrency.sh
```

再运行 Backend 检查：

```bash
cd backend/server
npm ci --ignore-scripts
npm run check
npm test
```

SQL fixture 覆盖可信 20／21 项、空目录、其他报告族、provenance 漂移、未知或停用 identity、撤权、value-free audit 和最小 ACL。并发脚本验证读取先取得
授权锁和撤权先取得授权锁。Backend 测试覆盖 strict parser、固定 HTTP collection route、认证顺序、Promise gate、错误脱敏、JSON、`no-store` 和
production wiring。

这些结果只证明 synthetic PostgreSQL、runtime bridge 和 Backend HTTP 合同。它们不证明 Flutter 已消费目录，不证明导出、缓存、离线或 production
identity，也不证明 Android、iOS、macOS、Windows、Linux 或 Web 真人环境已经运行。

### 6BL：验证 Flutter original-region typed gateway

6BL 不增加数据库 migration 或 Backend route。它在 Dart 测试进程中用 fake `IdentitySession` 和内存 `MockClient` 模拟 6BK 目录与 6BJ 详情响应。
运行这些测试不需要 Android Studio、模拟器、手机或 Docker。

第一次运行时，在仓库根目录依次执行：

```bash
flutter pub get
dart analyze
flutter test --no-pub test/management_reports/http_original_region_report_gateway_test.dart
```

`flutter pub get` 下载 Dart 依赖。`dart analyze` 检查类型和静态错误。最后一条命令只运行 6BL 的 focused 测试。它会检查两个固定 GET path、Bearer、一次
`401` 刷新、JSON／`no-store`、三字段目录和详情 root、六字段摘要、20 项上限、固定排序、17-key report、source tree tuple、两期城市网格、隐私状态和
稳定失败。测试不会连接真实 Backend，也不会写 Drift、缓存或文件。

focused 测试通过后，再运行完整 Flutter 回归：

```bash
flutter test --no-pub
```

若需要确认 6BJ／6BK 的既有数据库和 Backend 合同没有回归，再运行：

```bash
./tool/run_postgres_tests_in_docker.sh
```

Docker 在本切片中只重跑既有 0071 及以前的合同。它不会测试 6BL 的 Dart parser；focused Flutter 测试也不会证明数据库授权、provenance、audit 或 ACL。
两组测试分别证明不同边界。任何通过结果都不证明 UI、离线、导出、production identity 或六平台真人运行时。

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

### 5.7 验证个人阶段变更汇总读取

Slice 6AE-1 改动 Backend HTTP、PostgreSQL bridge、索引和测试。Slice 6AE-2 在不增加 Drift 或
离线历史同步的前提下增加 Flutter typed gateway 和个人页面。先运行无数据库的 Backend 检查：

```bash
npm --prefix backend/server run check
npm --prefix backend/server test
```

这些测试必须覆盖 Bearer 验证先于 query shape、重复／额外 query、UTC `Z` 规范化、GET body、
`Cache-Control: no-store`、稳定的 `401`／`400`／`403`／`503`，以及成功 envelope 的 exact keys、
安全整数、不变量和零 PII。Store 必须只把可信 issuer／subject 和期间交给 bridge，不能接受
客户端 actor、workspace 或 project。

然后运行真实 PostgreSQL 套件：

```bash
./tool/run_postgres_tests_in_docker.sh
```

完整套件会从空库应用 `0051_personal_relationship_stage_change_summary.sql`，运行
`verify_personal_relationship_stage_change_summary.sql` 和 `0050_personal_relationship_stage_change_events.sql`，
再在 Node 24 容器中运行阶段变更 adapter integration。检查必须证明 runtime 只有 bridge `EXECUTE`、
`PUBLIC` 无执行权、`search_path` 固定、关闭顺序扫描后的 `EXPLAIN` 能使用 actor／project／
changed-at 部分索引，且
重复 revision 失败关闭。integration 必须对账 `5` 个事件、`4` 个不同关系、`3` 个上升、`2` 个下降
和空期间四个零。SQL fixture 另证实已结束 assignment 和匿名化对象的此前合格事件仍计入；函数
定义检查必须确认没有 target status、assignment 或 lifecycle 过滤，且 lifecycle-only／note-only
不计入。该 `EXPLAIN` 是索引可用性的结构检查，不预测生产数据分布下的成本计划；生产仍要执行
正常 `ANALYZE` 并监测查询计划。

Docker runner 还会执行已注册的并发脚本、checksum 检查和 dump／restore。0051 check 证明当前项目
指针锁先于 snapshot aggregate。只能在看到 Node integration、恢复库 check 和最后的总成功标志后，记录为 Backend→PostgreSQL 通过。这个
结果不代表生产 Supabase 身份、真实用户资料或任何 Flutter／真机功能已验收。

Flutter 测试不在 Docker 中运行。它们使用本机 Flutter SDK，验证 typed gateway、页面状态、
scope 隔离和可访问性；Docker 仍只负责真实 PostgreSQL 与 Backend adapter 边界。从仓库根目录运行：

```bash
flutter test --no-pub test/features/contact_metrics/relationship_stage_change_summary_test.dart
flutter test --no-pub test/features/contact_metrics/http_relationship_stage_change_summary_gateway_test.dart
flutter test --no-pub test/features/contact_metrics/relationship_stage_change_summary_panel_test.dart
flutter test --no-pub test/app/app_dependencies_test.dart test/app/tongxingzhe_app_test.dart
```

第一组检查四个计数、UTC 期间和可信时刻不变量。第二组检查请求只有 `from_utc`／`until_utc`、
Bearer 更新、HTTP 错误分类和 exact-key 解析。第三组检查 loading、成功、全零、失败、重试、
项目／期间变化、同步完成、项目设置返回、App 恢复、迟到响应、320 px、200% 字号、键盘路径和
屏幕阅读器语义。最后一组确认正式
composition root 注入并关闭 gateway，且只有 personal workspace 发起读取。

若 Flutter 测试通过但 Docker 失败，只能说明客户端合同内部一致，不能说明它与真实 PostgreSQL
bridge 对账成功。反过来，Docker 通过也不能代替 Flutter 页面和可访问性测试。两组都通过后，
才可以记录本地客户端合同与 Backend→PostgreSQL 分层证据齐全；它不是 Flutter→实际 Backend 的
端到端验收。生产 Supabase 身份和真机结果仍须单独验证。

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
7. 建立一次性的 Node 24 容器，编译 Backend，并运行九条 PostgreSQL adapter integration test：地点来源、当前关系阶段、同意占比开关、同意占比读取、个人阶段变更汇总、current-city 快照读取、current-city 快照目录、兴趣快照 runtime 读取和兴趣快照目录；
8. 按文件名运行全部正式并发脚本，用独立数据库会话检查锁、撤权和唯一性合同；
9. 修改 migration 的临时副本，确认 runner 拒绝 checksum 漂移；
10. 执行 `pg_dump`，启动没有源 cluster roles 的第二个 PostgreSQL 容器；
11. 用 `postgres_prepare_restore_roles.sh` 建立 archive 所需的无登录角色，恢复后再运行全部 check 和 fixture；
12. 成功后删除两个 PostgreSQL 容器、Node 容器、临时 work volume 和本机临时 dump。

这组步骤同时验证新安装、重复部署、Backend→PostgreSQL 结果分类、并发、最小权限和备份恢复。fixture 内使用 `BEGIN` 与 `ROLLBACK`，不会把合成业务资料留在测试库。并发脚本会提交自己的 synthetic 行，这些行会随 dump 进入恢复库；它们不是 production 数据。

Node 阶段编译并运行 `backend/server/test/contact-location-evidence.integration.ts`、
`backend/server/test/personal-current-relationship-stage.integration.ts`、
`backend/server/test/personal-follow-up-consent-opt-in.integration.ts`、
`backend/server/test/personal-follow-up-consent-ratio.integration.ts`、
`backend/server/test/personal-relationship-stage-change-summary.integration.ts`、
`backend/server/test/management-current-city-report-snapshots.integration.ts`、
`backend/server/test/management-current-city-report-snapshot-directory.integration.ts`、
`backend/server/test/management-interest-report-snapshots.integration.ts` 和
`backend/server/test/management-interest-report-snapshot-directory.integration.ts`。开关测试用
runtime role 验证未配置、启用、幂等重放、冲突、停用和回滚；比例测试再对账 `not_enabled` 与
启用后的 `ready 0 / 0`；阶段变更 integration 对账 `5 / 4 / 3 / 2` 和空期间，SQL fixture 与独立
并发脚本分别覆盖匿名化历史和当前项目锁。
如果入口缺失、编译失败或真实 Backend 到 PostgreSQL 的任一断言失败，脚本会在这一步停止；设置
`KEEP_POSTGRES_TEST_CONTAINER=1` 后，PostgreSQL 容器会保留供检查。不能把前面的 SQL 通过单独
记为 Backend 集成通过。

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
| `backend/server/test/personal-follow-up-consent-opt-in.integration.ts` | 用 runtime role 对账项目开关 Store 与 0048 bridge | 固定范围、版本、幂等、停用元数据或错误映射错误 |
| `backend/server/test/personal-follow-up-consent-ratio.integration.ts` | 用 runtime role 对账未启用与启用后的个人比例结果 | identity／project 参数、开关状态或 union 解析错误 |
| `checks/verify_personal_relationship_stage_change_summary.sql` | 检查 0051 bridge 的函数形状、权限、PII-free keys 和索引计划 | runtime 权限过大、合同漂移或历史全表扫描 |
| `fixtures/0050_personal_relationship_stage_change_events.sql` | 对账阶段变更候选集、排除项、方向和重复 revision 失败关闭 | actor、项目、期间或历史保留边界错误 |
| `backend/server/test/personal-relationship-stage-change-summary.integration.ts` | 用 runtime role 对账 Backend Store 与 0051 bridge 的计数、空期间和 PII 边界；SQL fixture 与并发脚本另证实匿名化历史和锁边界 | Backend 参数、结果解析或隐私边界错误 |
| `backend/server/test/management-current-city-report-snapshots.integration.ts` | 用 runtime role 对账 0059 current-city bridge、project／snapshot 绑定和 strict report parser | identity、protected report 或 parser 合同错误 |
| `backend/server/test/management-current-city-report-snapshot-directory.integration.ts` | 用 runtime role 对账 0060 current-city 目录 bridge、排序和 metadata parser | 目录 provenance、排序或 runtime ACL 错误 |
| `backend/server/test/management-interest-report-snapshots.integration.ts` | 用 runtime role 对账 0064 exact identity bridge、一次固定 SQL、0063 状态和十格 strict parser | identity、bridge ACL、结果 envelope 或兴趣报告合同错误 |
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

CI 的 PostgreSQL job 在 Linux runner 上执行同一个 Docker runner。默认会拉取 `postgres:16` 和 `node:24-bookworm`，在临时容器中运行 `psql`、Backend build 和九条 Backend integration；它不需要 runner 上的 PostgreSQL service，也不占用本机端口。两条路径执行相同的 migration、check、fixture、Backend 对账和并发脚本。

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
| Backend 同意占比开关 integration 断言失败 | 检查 current project、固定 metric、0048 版本／幂等合同与 disabled metadata |
| Backend 阶段变更汇总 integration 断言失败 | 检查 0051 的 current pointer `FOR UPDATE`、actor／project／changed-at 索引、匿名化历史和 `5 / 4 / 3 / 2` 对账 |
| `verify_personal_relationship_stage_change_summary.sql` 失败 | 检查 runtime 是否只有 bridge `EXECUTE`、`search_path`、exact keys 和 `EXPLAIN` 是否走部分索引 |
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
