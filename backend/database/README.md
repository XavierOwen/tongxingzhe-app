# PostgreSQL schema 与 migration

这里是共享事务数据库 schema 的唯一权威来源。Supabase Dashboard 可以用于观察，不得手工创建或修改正式业务表。

## 目录

- `migrations/`：只追加、按文件名排序的正式 SQL；已经执行的文件不得改写；
- `runner/`：迁移历史、锁与 checksum 检查；
- `checks/`：环境和权限不变量；
- `fixtures/`：只含 synthetic 数据的可回滚验证资料。

## 本地空库重建

先创建一个专用 PostgreSQL 测试库，再显式传入连接地址：

```bash
export DATABASE_URL='postgresql://postgres:postgres@127.0.0.1:5432/tongxingzhe_test'
./tool/postgres_migrate.sh
./tool/postgres_migrate.sh
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/checks/verify_bootstrap.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/fixtures/0001_runtime_probe.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/checks/verify_identity_context.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/fixtures/0002_identity_context.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/checks/verify_contact_sync.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/fixtures/0003_contact_sync.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/checks/verify_personal_project_contexts.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/fixtures/0004_personal_project_contexts.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/checks/verify_regions_and_private_drafts.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/fixtures/0005_regions_and_private_drafts.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/checks/verify_personal_contact_metrics.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/fixtures/0006_personal_contact_metrics.sql
```

第二次执行不是重复建库，而是验证已经记录的 checksum。若历史文件被修改，脚本会拒绝继续。

## 权限模型

`tongxingzhe_runtime` 是 `NOLOGIN` group role。实际 Backend login role 由部署环境管理，并只被授予这个 group role；Flutter 不知道 login role 或数据库密码。

业务表进入 `app_data`。Supabase 默认 Data API 角色 `anon`／`authenticated` 没有获得这个 schema 的权限。`app_migrations` 只供部署身份读取。

## 写下一条 migration

1. 复制下一个递增编号，例如 `0003_contact_journal.sql`；
2. SQL 不写 `BEGIN`／`COMMIT`，runner 会把 migration、锁和历史记录放在同一事务；
3. 明确写约束、索引、授权与中文不变量注释；
4. 增加 synthetic fixture、预期查询结果和失败检查；
5. 从空库运行全链，再从上一正式 fixture 运行升级链；
6. migration 一旦进入共享环境，只能新增 forward-fix，不能改旧文件。

`0001_bootstrap.sql` 固定隔离 schema、runtime role 和迁移机制。`0002` 加入可信身份上下文，`0003` 加入匿名接触、幂等写入和按 cursor 拉取合同，`0004` 加入个人项目创建与选择，`0005` 加入版本化区域树和私有草稿同步，`0006` 加入与 Drift 共用 fixture 的个人接触指标。后续表继续随垂直切片加入。

`0006_personal_contact_metrics.sql` fixture 使用 psql 的 `\copy` 读取 [`personal_contact_metrics_v1.csv`](fixtures/shared/personal_contact_metrics_v1.csv)。请从仓库根目录运行上述命令；Flutter/Drift 测试也读取同一文件，以防两套指标样例悄悄漂移。
