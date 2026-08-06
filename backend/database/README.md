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
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/checks/verify_region_resolution.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/fixtures/0007_canonical_region_resolution.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/checks/verify_contact_attempts.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/fixtures/0008_contact_attempts.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/checks/verify_contact_revisions.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/fixtures/0009_contact_revisions.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/checks/verify_contact_revision_conflicts.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/fixtures/0010_contact_revision_conflicts.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/checks/verify_questionnaire_execution.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/fixtures/0011_questionnaire_execution.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/checks/verify_questionnaire_visibility.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/fixtures/0012_questionnaire_visibility.sql
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

`0001_bootstrap.sql` 固定隔离 schema、runtime role 和迁移机制。`0002` 加入可信身份上下文，`0003` 加入匿名接触、幂等写入和按 cursor 拉取合同，`0004` 加入个人项目创建与选择，`0005` 加入版本化区域树和私有草稿同步，`0006` 加入与 Drift 共用 fixture 的个人接触指标，`0007` 加入平台发布版本、规范区域边界和坐标解析函数。后续表继续随垂直切片加入。

`0007_canonical_region_resolution.sql` 使用 PostgreSQL 内置 `polygon` 保存平台发布的 synthetic 或正式边界。解析函数只读取当前发布版本，并返回命中的最小节点及其完整父链。runtime role 可以执行函数，但不能直接读取发布表或边界表。没有边界命中时返回空结果，调用方必须保留原坐标为待解析状态。

`0006_personal_contact_metrics.sql` fixture 使用 psql 的 `\copy` 读取 [`personal_contact_metrics_v1.csv`](fixtures/shared/personal_contact_metrics_v1.csv)。请从仓库根目录运行上述命令；Flutter/Drift 测试也读取同一文件，以防两套指标样例悄悄漂移。

`0008_contact_attempts.sql` 保存未获回应的直接联络。尝试不含触达人数、兴趣或问卷答案，也不写入 warehouse outbox。后来发生的接触通过可选来源 ID 关联原尝试，两条事实都保留。

`0009_contact_revisions.sql` 保存追加式接触更正和作废。更正与作废都需要原因和当前 base revision。runtime role 只能执行受控包装函数，不能执行私有 helper 或直接读取历史表。更正会更新当前投影并重新归期；作废保留历史，但退出有效接触指标。

`0010_contact_revision_conflicts.sql` 对过期更正做三路比较。两台设备修改不同事实组时，服务器追加自动合并的 revision；修改同一事实组时，服务器保留基础、当前和本机建议快照。runtime role 只能按可信用户与项目读取单个比较结果，解决操作会追加新 revision，不覆盖历史。

`0011_questionnaire_execution.sql` 加入八种受控题型、五种回答状态、已发布定义读取和 v2 写入入口。客户端可以离线预验，但 PostgreSQL 仍会按可信项目与精确问卷版本复验每个答案。

`0012_questionnaire_visibility.sql` 给问题定义加入受限显示规则，并给答案加入 `rule_skipped` 原因。服务端按问题顺序重算可见性：可见必填题不能遗漏，隐藏题不能夹带旧值，也不能伪造普通“不适用”。
