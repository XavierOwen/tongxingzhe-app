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
    └── 临时 PostgreSQL 16 容器
        ├── tongxingzhe_test：空库重建、权限、fixture、并发
        └── tongxingzhe_restore：dump 后恢复验证

GitHub Actions
├── 重复 Flutter、Backend 和 PostgreSQL 检查
└── 分别在 Linux、macOS 和 Windows runner 构建六个平台
```

Flutter 的设备数据库是 Drift／SQLite。它随 `flutter test` 在测试进程中运行。PostgreSQL 是 Backend 的共享事务数据库。两者不是同一个数据库，也不能用一边的测试代替另一边。

### 2.1 Docker 中的三个基本名词

| 名词 | 含义 | 本项目中的例子 |
| --- | --- | --- |
| image（镜像） | 建立容器的只读模板 | `postgres:16` |
| container（容器） | 从镜像启动的隔离进程和文件系统 | `tongxingzhe-postgres-test-进程号` |
| database（数据库） | PostgreSQL 进程中的一个逻辑数据库 | `tongxingzhe_test` |

删除临时容器会删除其中的两个测试数据库。这是预期行为。测试只使用 synthetic 数据，脚本不挂载持久 volume，也不公开 PostgreSQL 端口。

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

若单个测试通过而完整测试失败，应按完整测试的失败处理。单个测试只能缩短开发反馈时间。

## 6. Docker PostgreSQL 套件怎样运行

### 6.1 最短用法

先启动 Docker，再从仓库根目录执行：

```bash
./tool/run_postgres_tests_in_docker.sh
```

脚本使用 `postgres:16`。首次运行时，Docker 会先下载镜像。下载时间取决于网络，后续运行会复用本机镜像。

### 6.2 脚本按什么顺序工作

脚本执行以下步骤：

1. 确认 Docker CLI 和 daemon 可用；
2. 建立名称含当前进程号的临时容器；
3. 等待 PostgreSQL 健康检查通过；
4. 把数据库目录和三个正式 runner 复制到容器；
5. 从空库执行全部 migration，再执行一次 checksum 重放；
6. 运行全部 schema／权限 check 和可回滚 synthetic fixture；
7. 用独立数据库会话检查问卷发布和指标兼容并发；
8. 修改 migration 的临时副本，确认 runner 拒绝 checksum 漂移；
9. 执行 `pg_dump`，恢复到第二个空库，再运行全部 check 和 fixture；
10. 成功后删除临时容器。

这组步骤同时验证新安装、重复部署、并发、最小权限和备份恢复。fixture 内使用 `BEGIN` 与 `ROLLBACK`，不会把合成业务资料留在测试库。

### 6.3 怎样读输出

正常输出会先显示 `已执行 0001_bootstrap` 到当前最高 migration。第二轮应显示 `无需重复执行`。

下面这行是成功证据，不是错误：

```text
checksum 漂移已按预期被拒绝。
```

最后应出现：

```text
PostgreSQL Docker 测试全部通过。
已删除临时 PostgreSQL 容器：tongxingzhe-postgres-test-...
```

### 6.4 失败时保留容器

默认情况下，脚本在成功或失败后都删除容器。需要检查失败现场时，运行：

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

不要把 production 数据库地址传给这个脚本。脚本始终在自己建立的容器内使用固定测试库名。

## 7. PostgreSQL 各类文件分别证明什么

| 文件或步骤 | 作用 | 失败通常表示 |
| --- | --- | --- |
| `migrations/*.sql` | 从上一 schema 迁移到下一 schema | SQL、约束、授权或依赖顺序错误 |
| `runner/*.sql` | 锁定、记录并校验 migration 历史 | 历史被改写或部署并发不安全 |
| `checks/verify_*.sql` | 检查表、函数、角色和权限形状 | schema 缺失或 runtime 权限过大 |
| `fixtures/NNNN_*.sql` | 用 synthetic 数据执行成功与拒绝路径 | 业务事务或不变量错误 |
| 并发脚本 | 用两个独立 `psql` 会话同时写入 | 锁、唯一约束或冲突合同错误 |
| dump／restore | 从备份重建 schema 后重复验证 | 备份范围、owner、授权或恢复路径错误 |

check 主要观察结构。fixture 会调用正式函数并核对结果。两者不能互相替代。

## 8. Drift v17 生成文件怎样检查

当前本地 schema 版本是 v17。数据库结构变化后先重新生成：

```bash
dart run build_runner build
dart run drift_dev schema dump \
  lib/data/local_database.dart \
  drift_schemas/drift_schema_v17.json
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

CI 会在临时目录重新生成 v17 snapshot 和 migration helper，并与仓库文件逐字比较。手工修改生成文件不能通过该检查。

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
| PostgreSQL rebuild, permissions, and restore | migration、check、fixture、并发、checksum 和恢复 |
| Backend identity, context, and sync | TypeScript check 和全部 Backend tests |
| Build Android／Web／Linux／iOS／macOS／Windows | 六个平台独立 build |

CI 的 PostgreSQL job 在 Linux runner 上启动 `postgres:16-alpine` service，并让 runner 上的 `psql` 通过端口 `5432` 访问。Docker 本地脚本使用 `postgres:16`，并在容器内运行 `psql`，因此不占用本机端口。两条路径执行相同的 migration、check、fixture 和并发脚本。

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
| restore check 失败 | dump schema 范围、role、函数授权和恢复 owner |
| Flutter 单测通过但完整测试失败 | 共享状态、生成文件或其他模块的回归 |
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
