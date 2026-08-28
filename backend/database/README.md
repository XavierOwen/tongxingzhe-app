# PostgreSQL schema 与 migration

这里是共享事务数据库 schema 的唯一权威来源。Supabase Dashboard 可以用于观察，不得手工创建或修改正式业务表。

## 目录

- `migrations/`：只追加、按文件名排序的正式 SQL；已经执行的文件不得改写；
- `runner/`：迁移历史、锁与 checksum 检查；
- `checks/`：环境和权限不变量；
- `fixtures/`：只含 synthetic 数据的可回滚验证资料；`fixtures/shared/` 保存 Flutter、Backend 和 PostgreSQL 共用的输入。

## Docker 中运行完整数据库测试

没有安装 PostgreSQL 或 `psql` 时，先启动 Docker，再从仓库根目录运行：

```bash
./tool/run_postgres_tests_in_docker.sh
```

脚本建立隔离的 PostgreSQL 16 容器，运行 migration、check、fixture、Backend→PostgreSQL 对账、并发和 dump／restore，最后自动删除容器。Backend 对账阶段使用 Node 24 容器和仓库锁定的 npm 依赖；它不连接 production，也不使用真实用户资料。第一次使用 Docker、需要保留失败容器或理解输出时，阅读[本机、Docker 与 CI 测试指南](../../docs/manual/09-local-docker-and-ci-testing.md)。

Node 阶段要求十三条 Backend integration 入口存在：地点来源、当前关系阶段、个人阶段变更汇总、个人同意占比读取、个人同意占比开关、current-city
快照读取、current-city 快照目录、兴趣快照 runtime 读取、兴趣快照目录、original-region 快照读取、original-region 快照目录、后续联系同意占比快照读取和后续联系同意占比快照目录读取。
脚本先在 Node 24 中运行 `npm ci --ignore-scripts` 和 `npm run build`，再执行编译产物。6BU 是 SQL-only，不增加 Backend integration；6BV 增加一条目录 integration。
开关测试覆盖未配置、启用、幂等重放、冲突和停用；比例测试再读取 `not_enabled` 和启用后的
`ready 0 / 0`；阶段变更 integration 对账 `5 / 4 / 3 / 2` 和空期间。SQL fixture 另证实匿名化
历史，独立并发脚本证实 current-project 锁。
入口缺失、编译失败或断言失败都会使整套测试失败；不能把此前 SQL fixture 的通过单独写成
Backend adapter 集成通过。

## 6BO：组织项目 opt-in 配置边界

6BO 的组织项目 `follow_up_consent_ratio@1` opt-in 与个人 0048 配置分开。实现后的 `0073` migration 只应增加 private 配置表、private configure/read
合同、结构检查、可回滚 fixture 和独立并发脚本。函数使用可信内部 `app_user_id`，并在组织／项目 membership 与 `release_management_reports` capability
的授权锁后重新检查权限。项目 status 变更触发器与配置共享 project lock，归档与 configure 因此线性化；0030 resolver 不替代归档锁。`view_anonymous_analytics`
不能写配置。

该配置使用追加式版本、预期版本和 request UUID。相同 payload 精确幂等，载荷漂移、过期版本、撤权和并发冲突失败关闭。结果只包含 value-free 配置 metadata，
不包含比例、报告格、contact、推广对象、贡献者或 PII。`not_enabled` 不表示 `0 / 0`，配置时间也不改变统计期间。

6BO 不增加 runtime bridge、HTTP、Backend integration、Flutter 或统计候选。实现后，完整 Docker runner 会自动发现 0073 migration、check、fixture 和并发脚本，
并在 dump／restore 中重跑 migration、check 和 fixture。通过只能证明 synthetic PostgreSQL 配置合同，不能证明比例数学或披露风险控制。

schema dump 不包含 PostgreSQL cluster roles。恢复到新 cluster 前，部署身份必须先运行 `tool/postgres_prepare_restore_roles.sh`，幂等建立 `tongxingzhe_runtime`，以及无登录、无成员的 `tongxingzhe_region_publisher`、`tongxingzhe_contact_provenance_writer`、`tongxingzhe_region_mapping_writer`、`tongxingzhe_region_attribution_reader`、`tongxingzhe_management_region_report_reader`、`tongxingzhe_management_original_region_report_reader`、`tongxingzhe_management_interest_report_reader`、`tongxingzhe_management_current_city_snapshot_release_writer`、`tongxingzhe_management_interest_snapshot_release_writer`、`tongxingzhe_management_original_region_snapshot_release_writer`、`tongxingzhe_management_report_snapshot_lifecycle_writer`、`tongxingzhe_management_follow_up_consent_config_writer`、`tongxingzhe_management_follow_up_consent_ratio_reader`、`tongxingzhe_management_consent_ratio_snapshot_release_writer` 和 `tongxingzhe_management_deidentified_anomaly_reader`。Docker 套件会另启一个没有源角色的 PostgreSQL 容器，先准备角色再恢复，避免同 cluster 测试掩盖 owner／ACL 依赖。

## 6BP：组织项目后续联系同意占比候选边界

6BP 的 0074 migration 提供 `contact_target_follow_up_consent_ratio_two_periods@1` private release-candidate。它不复用个人 0048／0049 合同，也不把 6BO opt-in 当成比例结果。
候选只供未来 release workflow 使用，调用方提供可信内部 actor、显式项目、项目报告时区和数据库 cutoff。数据库在授权锁和项目锁后重新确认活动账号、组织／项目 membership、
项目状态、`release_management_reports` capability 和 6BO 当前 opt-in。`view_anonymous_analytics` 不能执行候选。

统计单位是当前有效 contact revision 的 contact-target link。同一 contact 的多个 link 分别计数，contributor 固定为 contact 的可信 `app_user_id`。候选使用两个相邻且已经结束的完整 ISO 周。
`yes` 是分子，`yes + no` 是分母；`unknown` 计入 unanswered，`refused` 与 `not_applicable` 是独立 coverage。`unknown_count` 与 `excluded_count` 固定为零。
`yes`、`no` 和每个 coverage cell 都执行 `N >= 10`、
至少三位 contributor、贡献者不超过该 cell 总数一半。只有 yes/no 都安全时才返回比例数值，否则返回 `suppressed` 和 `null` 数值。未启用或停用在读 link 前返回 `not_enabled`，
不返回 report、ratio 或 coverage。

实现应增加 `backend/database/migrations/0074_management_follow_up_consent_ratio.sql`、`backend/database/checks/verify_management_follow_up_consent_ratio.sql`、
`backend/database/fixtures/0074_management_follow_up_consent_ratio.sql`、
`verify_management_follow_up_consent_ratio_concurrency.sh`、专用 closed role、ACL check 和 restore role 准备。完整 runner 会在源库自动发现并运行 0074 migration、check、fixture 和并发脚本，
再检查 checksum。dump／restore 阶段通过 `pg_restore` 重建独立恢复库，然后只重跑 check 和 fixture；它不重新执行 migration，也不重跑会提交 synthetic 行的并发脚本。

从仓库根目录运行完整套件：

```bash
./tool/run_postgres_tests_in_docker.sh
```

只调试 6BP 时，先确认 `DATABASE_URL` 指向专用测试库，再运行：

```bash
export DATABASE_URL='postgresql://postgres:postgres@127.0.0.1:5432/tongxingzhe_test'
./tool/postgres_migrate.sh
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/checks/verify_management_follow_up_consent_ratio.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/fixtures/0074_management_follow_up_consent_ratio.sql
./tool/verify_management_follow_up_consent_ratio_concurrency.sh
```

这些检查只证明 synthetic PostgreSQL 的 candidate、隐私门槛、并发、ACL 和 restore 合同。它们不证明 snapshot、release、authorized read、runtime、HTTP、Backend、Flutter、生产身份、
真实数据或 Android、iOS、macOS、Windows、Linux、Web 真人平台运行时，也不构成形式化不可重识别保证。

## 6BQ：组织项目后续联系同意占比快照发布边界

6BQ 的 0075 migration 只把 6BP completed protected candidate 固定为不可变 snapshot。它使用独立 closed release writer、attempt、request claim family、RLS policy 和 consent-ratio lineage，不复用其他 report family 的 provenance。

发布函数只接受 request UUID、可信内部 actor、显式 project 和固定 report identity。数据库在锁内重新授权，派生项目报告时区与 cutoff，从 `change_feed` 读取 source watermark，再调用 0074 executor。首份 completed candidate 建立 baseline；后续发布必须推进 cutoff，并链接当前 predecessor。`suppressed` 保持 JSON `null`。`not_enabled` 和所有发布阻断只写不含候选内容的 value-free attempt。

完整 Docker runner 自动发现 0075 migration、check、fixture 和并发脚本，并继续执行 checksum 与 dump／restore。只调试专用测试库时运行：

```bash
export DATABASE_URL='postgresql://postgres:postgres@127.0.0.1:5432/tongxingzhe_test'
./tool/postgres_migrate.sh
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/checks/verify_management_follow_up_consent_ratio_snapshot_lineage.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/fixtures/0075_management_follow_up_consent_ratio_snapshot_lineage.sql
./tool/verify_management_follow_up_consent_ratio_snapshot_lineage_concurrency.sh
```

fixture 会回滚；并发脚本会提交独立 synthetic namespace。dump／restore 使用 `pg_restore` 重建恢复库，只重跑 check 与 fixture，不重新执行 migration，也不重跑并发脚本。这些检查不证明 authorized read、runtime、HTTP、Backend、Flutter、生产身份或真人平台运行时。

## 6BR：组织项目后续联系同意占比快照授权读取边界

6BR 的 0076 migration 在 6BQ lineage 之上增加 private DB-only 读取。函数只接受可信内部用户、显式 project 和 snapshot UUID，并在同一事务重新解析 `view_anonymous_analytics`。调用方不能提交报告 JSON、ratio、coverage、时区、cutoff、watermark、capability、筛选或 SQL。

可信读取必须同时满足：0075 request claim 属于 consent-ratio family；release attempt 是 `approved`／`approved_baseline` 且 reason 为空。
attempt 与 snapshot 的 actor、project、report／version、query fingerprint 和 lineage 必须对齐；时区 revision、cutoff、previous／compared pointer 和 source watermark 也必须对齐。
函数返回前再次运行 6BQ validator，不重算或改写报告。

`completed` 返回既有 protected report，suppressed ratio／coverage 继续是 JSON `null`。unknown／cross-project 返回 `not_found`；同项目 foreign、legacy、blocked、缺失或漂移 provenance 返回 `untrusted_provenance`。后两种结果不返回正文。每次已授权调用追加 consent-ratio 专用、不可变、value-free audit；未授权、撤权、过期、release-only、无成员和 inactive project 请求失败关闭且不写 audit。

private function 与 audit 归共享 snapshot 的可信 owner。`PUBLIC`、runtime、普通 app role、6BP reader、6BQ release writer 和其他 report-family 角色不能执行读取或直接访问审计。6BR 不增加 runtime bridge、HTTP、Backend、目录、Flutter、Drift、导出、缓存、离线、同步、删除、retention、warehouse 或生产身份。

完整 Docker runner 自动发现 0076 migration、structural check、rollback fixture 和 read／revoke 并发脚本，并执行 checksum 与 dump／restore。恢复库只重跑 check 和 fixture，不重跑会提交 synthetic 行的并发脚本。只调试可丢弃测试库时运行：

```bash
export DATABASE_URL='postgresql://postgres:postgres@127.0.0.1:5432/tongxingzhe_test'
./tool/postgres_migrate.sh
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/checks/verify_authorized_management_follow_up_consent_ratio_snapshot_read.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/fixtures/0076_authorized_management_follow_up_consent_ratio_snapshot_read.sql
./tool/verify_authorized_management_follow_up_consent_ratio_snapshot_read_concurrency.sh
```

fixture 使用 `6b76*` rollback namespace；并发脚本使用独立 `6b76c*` committed namespace。完整通过只证明 synthetic PostgreSQL 的授权、provenance、validator、value-free audit、撤权锁、checksum、restore 和 ACL 合同，不证明 runtime、HTTP、Backend、目录、Flutter、导出、生产身份或真人平台运行时。

## 6BS：后续联系同意占比快照 runtime bridge 边界

0077 在 0076 private reader 之上增加一个窄 `app_data` bridge。函数只接受 Backend 已验证的 exact external `issuer + subject`、显式 project 和 snapshot UUID。它只映射既有 active identity；输入长度检查不能改变匹配，未知或 inactive identity 失败关闭，函数不 bootstrap 或创建账号。

bridge 使用 `SECURITY DEFINER`、`VOLATILE` 和固定 `search_path = pg_catalog`，owner 与 0076 private reader 一致。它只调用 0076，不复制授权、0075 provenance、6BQ validator、撤权锁或 audit。`tongxingzhe_runtime` 只有 bridge `EXECUTE`，不能使用 `app_private` 或读取 identity、用户、snapshot、attempt、claim 和 audit 表。

完整 Docker runner 自动发现 0077 migration、check 和 rollback fixture，并显式运行 Backend PostgreSQL integration。它继续运行 0076 read／revoke 并发、checksum 与 dump／restore。只调试可丢弃测试库时运行：

```bash
export DATABASE_URL='postgresql://postgres:postgres@127.0.0.1:5432/tongxingzhe_test'
./tool/postgres_migrate.sh
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/checks/verify_runtime_authorized_management_follow_up_consent_ratio_snapshot_read.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/fixtures/0077_runtime_authorized_management_follow_up_consent_ratio_snapshot_read.sql
```

fixture 使用独立 `6bs*` rollback namespace。恢复库只重跑 check 和 fixture，不重跑会提交 synthetic 行的并发脚本。通过只证明 synthetic exact-identity bridge、runtime ACL 和 0076 委托合同，不证明 HTTP、Flutter、生产身份或真人平台运行时。

## 6BU：组织项目后续联系同意占比快照目录边界

0078 migration 为一个显式 project 增加 private snapshot directory。canonical 函数名是
`app_private.list_authorized_management_follow_up_consent_snapshots_v1(uuid, uuid)`。调用时重新确认 active user、组织／项目 membership、active project
和 `view_anonymous_analytics`，并沿既有 authorization／revoke lock order。它只接受 0075 consent-ratio family 的
`approved_baseline`／`approved` exact provenance。foreign project、foreign report family、legacy、blocked、missing 和 drifted provenance 都失败关闭。

返回 envelope 固定为 `access_contract_id`、`access_event_id`、`project_id` 和 `snapshots` 四项。
`snapshots` 最多 20 项，每项固定为 `snapshot_id`、`report_id`、`report_version`、`reporting_time_zone`、`data_cutoff_utc` 和 `released_at_utc`。
数据库按 `data_cutoff_utc DESC`、`released_at_utc DESC`、`snapshot_id DESC` 固定排序。第一项只是排序结果，不表示 current、latest 或未被取代。
没有合格快照的已授权 project 返回空数组，并记录数量为 0 的成功 audit。

目录 audit 使用专用追加式、不可变、value-free 合同，只保留授权和访问 metadata。它不记录 snapshot ID、报告内容、period、ratio、coverage、source、contributor、target、contact 或 PII。
撤权、过期、无成员、inactive project、unknown ID、跨 project 和权限不足都失败关闭。`PUBLIC`、runtime、普通 app role、其他 report reader 或 writer 不能执行 private function 或读取 audit。

6BU 不修改前序 6BS／6BT 已定义的 `app_data` identity bridge、runtime、Backend adapter 和 HTTP route，也不增加 Flutter、导出、缓存、离线或同步。
完整 Docker runner 自动发现 0078 migration、check、rollback fixture 和目录／撤权并发脚本，执行 checksum，并在独立恢复库中重跑 check 与 fixture；恢复库不重跑提交型并发脚本。
这些 synthetic PostgreSQL 结果只证明数据库授权、provenance、目录、audit、并发和恢复合同，不证明 production identity、部署服务或六平台真人运行时。

只调试 6BU 时，先确认 `DATABASE_URL` 指向可丢弃测试库，再运行：

```bash
export DATABASE_URL='postgresql://postgres:postgres@127.0.0.1:5432/tongxingzhe_test'
./tool/postgres_migrate.sh
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/checks/verify_authorized_management_follow_up_consent_ratio_snapshot_directory.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/fixtures/0078_authorized_management_follow_up_consent_ratio_snapshot_directory.sql
./tool/verify_authorized_management_follow_up_consent_ratio_snapshot_directory_concurrency.sh
```

fixture 在 transaction 结束时回滚；并发脚本使用独立 synthetic namespace 并提交，避免恢复测试中的既有行发生冲突。

## 6BV：通过 exact identity bridge 读取后续联系同意占比快照目录

0079 migration 为 6BU 的 private directory 增加窄 `app_data` bridge：

```text
app_data.list_authorized_management_follow_up_consent_snapshots_v1(text,text,uuid)
```

bridge 接收 Backend 已验证的 exact external `issuer + subject` 和显式 project UUID。它只映射已有且 active 的 identity，不 trim、不 bootstrap、不创建 identity，
并只调用 0078 的 `app_private.list_authorized_management_follow_up_consent_snapshots_v1(uuid, uuid)`。`tongxingzhe_runtime` 只有 bridge `EXECUTE`，不能使用
`app_private` schema，也不能直接读取 identity、snapshot、attempt、claim、directory 或 audit 表。bridge 使用 `SECURITY DEFINER`、`VOLATILE` 和固定
`search_path = pg_catalog`，owner 与 0078 private directory 对齐。

Backend 使用独立的 directory store，只执行一条固定参数化 SQL。strict parser 只接受四项 root envelope 和六项 metadata item，检查 project 绑定、UUID、UTC 时间、
最多 20 项、无重复和固定排序；额外字段、错误 contract、非 consent-ratio report 或无效值失败关闭。只有 SQLSTATE `42501` 映射为 typed `forbidden`，其他数据库或
parser 错误保持内部失败。

从仓库根目录运行完整套件：

```bash
./tool/run_postgres_tests_in_docker.sh
```

runner 自动发现 0079 migration、structural check 和 rollback fixture，并运行 6BV Backend integration。它继续运行 0078 directory／revoke concurrency、checksum
和 dump／restore。恢复阶段先准备缺失的 PostgreSQL roles，再重跑 check 和 fixture；不重跑会提交 synthetic 行的并发脚本。

只调试 6BV 时，先确认 `DATABASE_URL` 指向可丢弃测试库，再运行：

```bash
export DATABASE_URL='postgresql://postgres:postgres@127.0.0.1:5432/tongxingzhe_test'
./tool/postgres_migrate.sh
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/checks/verify_runtime_authorized_management_follow_up_consent_ratio_snapshot_directory.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/fixtures/0079_runtime_authorized_management_follow_up_consent_ratio_snapshot_directory.sql
cd backend/server
npm ci --ignore-scripts
npm run check
npm test
cd ../..
```

这些 synthetic 测试只证明 0079 bridge、0078 委托、Backend adapter、strict parser、ACL、checksum 和 restore 合同。它们不证明 HTTP、Flutter、Drift、导出、缓存、离线、
部署服务、production identity 或 Android、iOS、macOS、Windows、Linux、Web 真人平台运行时。6BV 不增加 HTTP route，也不修改 0078 provenance、授权、撤权锁、audit 或排序。

## 使用已有 PostgreSQL 测试库

先创建一个专用 PostgreSQL 测试库，再显式传入连接地址：

```bash
export DATABASE_URL='postgresql://postgres:postgres@127.0.0.1:5432/tongxingzhe_test'
./tool/postgres_migrate.sh
# 第二次运行用于验证历史 checksum；不是重复输入。
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
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/checks/verify_questionnaire_publishing.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/fixtures/0013_questionnaire_publishing.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/checks/verify_questionnaire_draft_upgrades.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/fixtures/0014_questionnaire_draft_upgrades.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/checks/verify_questionnaire_metric_compatibility.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/fixtures/0015_questionnaire_metric_compatibility.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/checks/verify_promotion_target_directory.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/fixtures/0016_promotion_target_directory.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/checks/verify_contact_target_links.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/fixtures/0017_contact_target_links.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/checks/verify_promotion_target_relationship_audit.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/fixtures/0018_promotion_target_relationship_audit.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/checks/verify_person_institution_relationships.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/fixtures/0019_person_institution_relationships.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/checks/verify_promotion_target_retention.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/fixtures/0020_promotion_target_retention.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/checks/verify_personal_action_plans.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/fixtures/0021_personal_action_plans.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/checks/verify_personal_action_reminders.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/fixtures/0022_personal_action_reminders.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/checks/verify_management_contact_session_privacy.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/fixtures/0023_management_contact_session_privacy.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/checks/verify_management_report_contract.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/fixtures/0024_management_report_contract.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/checks/verify_management_report_periods.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/fixtures/0025_management_report_periods.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/checks/verify_management_report_execution.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/fixtures/0026_management_report_execution.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/checks/verify_management_report_pair_release.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/fixtures/0027_management_report_pair_release.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/checks/verify_management_report_snapshots.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/fixtures/0028_management_report_snapshots.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/checks/verify_project_reporting_time_zone.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/fixtures/0029_project_reporting_time_zone.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/checks/verify_management_report_authorization.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/fixtures/0030_management_report_authorization.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/checks/verify_frozen_canonical_region_tree_releases.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/fixtures/0038_frozen_canonical_region_tree_releases.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/checks/verify_contact_location_provenance.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/fixtures/0039_contact_location_provenance.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/checks/verify_canonical_region_resolution_provenance.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/fixtures/0040_canonical_region_resolution_provenance.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/checks/verify_personal_interest_ordinal_summary.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/fixtures/0041_personal_interest_ordinal_summary.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/checks/verify_personal_interest_level_ratios.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/fixtures/0042_personal_interest_level_ratios.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/checks/verify_personal_interest_subset_ratios.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/fixtures/0043_personal_interest_subset_ratios.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/checks/verify_personal_target_response_distribution.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/fixtures/0044_personal_target_response_distribution.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/checks/verify_personal_target_response_ordinal_summary.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/fixtures/0045_personal_target_response_ordinal_summary.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/checks/verify_personal_target_response_level_ratios.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/fixtures/0046_personal_target_response_level_ratios.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/checks/verify_personal_current_relationship_stage_snapshot.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/fixtures/0047_personal_current_relationship_stage_snapshot.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/checks/verify_project_follow_up_consent_opt_in.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/fixtures/0048_project_follow_up_consent_opt_in.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/checks/verify_personal_follow_up_consent_ratio.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/fixtures/0049_personal_follow_up_consent_ratio.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/fixtures/0050_personal_relationship_stage_change_events.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/checks/verify_personal_relationship_stage_change_summary.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/fixtures/0051_personal_relationship_stage_change_summary.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/checks/verify_management_report_snapshot_export.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/fixtures/0052_management_report_snapshot_export.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/checks/verify_canonical_region_version_mappings.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/fixtures/0053_canonical_region_version_mappings.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/checks/verify_management_region_attribution.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/fixtures/0054_management_region_attribution.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/checks/verify_management_report_region_target_context.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/fixtures/0055_management_report_region_target_context.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/checks/verify_management_current_city_report.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/fixtures/0056_management_current_city_report.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/checks/verify_management_current_city_report_snapshot_lineage.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/fixtures/0057_management_current_city_report_snapshot_lineage.sql
./tool/verify_questionnaire_publish_concurrency.sh
./tool/verify_questionnaire_metric_concurrency.sh
./tool/verify_person_institution_relationship_concurrency.sh
./tool/verify_promotion_target_retention_concurrency.sh
./tool/verify_management_report_authorization_concurrency.sh
./tool/verify_management_report_release_concurrency.sh
./tool/verify_project_reporting_time_zone_concurrency.sh
./tool/verify_canonical_region_tree_release_concurrency.sh
./tool/verify_contact_location_provenance_concurrency.sh
./tool/verify_personal_relationship_stage_change_summary_concurrency.sh
./tool/verify_management_report_snapshot_export_concurrency.sh
./tool/verify_canonical_region_version_mapping_concurrency.sh
./tool/verify_management_report_region_target_context_concurrency.sh
./tool/verify_management_current_city_report_concurrency.sh
./tool/verify_management_current_city_report_snapshot_lineage_concurrency.sh
```

第二次执行不是重复建库，而是验证已经记录的 checksum。若历史文件被修改，脚本会拒绝继续。

## 权限模型

`tongxingzhe_runtime` 是 `NOLOGIN` group role。实际 Backend login role 由部署环境管理，并只被授予这个 group role；Flutter 不知道 login role 或数据库密码。

业务表进入 `app_data`。Supabase 默认 Data API 角色 `anon`／`authenticated` 没有获得这个 schema 的权限。`app_private` 保存尚未暴露给 runtime 的内部政策函数，`app_migrations` 只供部署身份读取。

## 写下一条 migration

1. 复制下一个递增编号，例如 `0003_contact_journal.sql`；
2. SQL 不写 `BEGIN`／`COMMIT`，runner 会把 migration、锁和历史记录放在同一事务；
3. 明确写约束、索引、授权与中文不变量注释；
4. 增加 synthetic fixture、预期查询结果和失败检查；
5. 从空库运行全链，再从上一正式 fixture 运行升级链；
6. migration 一旦进入共享环境，只能新增 forward-fix，不能改旧文件。

`0001_bootstrap.sql` 固定隔离 schema、runtime role 和迁移机制。`0002` 加入可信身份上下文，`0003` 加入匿名接触、幂等写入和按 cursor 拉取合同，`0004` 加入个人项目创建与选择，`0005` 加入版本化区域树和私有草稿同步，`0006` 加入与 Drift 共用 fixture 的个人接触指标，`0007` 加入平台发布版本、规范区域边界和坐标解析函数。后续表继续随垂直切片加入。

`0007_canonical_region_resolution.sql` 使用 PostgreSQL 内置 `polygon` 保存平台发布的 synthetic 或正式边界。解析函数只读取当前发布版本，并返回命中的最小节点及其完整父链。runtime role 可以执行函数，但不能直接读取发布表或边界表。没有边界命中时返回空结果，调用方必须保留原坐标为待解析状态。

`0006_personal_contact_metrics.sql` fixture 使用 psql 的 `\copy` 读取 [`personal_contact_metrics_v1.csv`](fixtures/shared/personal_contact_metrics_v1.csv)。请从仓库根目录运行上述命令；Flutter/Drift 测试也读取同一文件，并把结果映射到 v1 指标目录，以防 SQL 筛选、统计单位或结果元数据悄悄漂移。

`0008_contact_attempts.sql` 保存未获回应的直接联络。尝试不含触达人数、兴趣或问卷答案，也不写入 warehouse outbox。后来发生的接触通过可选来源 ID 关联原尝试，两条事实都保留。

`0009_contact_revisions.sql` 保存追加式接触更正和作废。更正与作废都需要原因和当前 base revision。runtime role 只能执行受控包装函数，不能执行私有 helper 或直接读取历史表。更正会更新当前投影并重新归期；作废保留历史，但退出有效接触指标。

`0010_contact_revision_conflicts.sql` 对过期更正做三路比较。两台设备修改不同事实组时，服务器追加自动合并的 revision；修改同一事实组时，服务器保留基础、当前和本机建议快照。runtime role 只能按可信用户与项目读取单个比较结果，解决操作会追加新 revision，不覆盖历史。

`0011_questionnaire_execution.sql` 加入八种受控题型、五种回答状态、已发布定义读取和 v2 写入入口。客户端可以离线预验，但 PostgreSQL 仍会按可信项目与精确问卷版本复验每个答案。

`0012_questionnaire_visibility.sql` 给问题定义加入受限显示规则，并给答案加入 `rule_skipped` 原因。服务端按问题顺序重算可见性：可见必填题不能遗漏，隐藏题不能夹带旧值，也不能伪造普通“不适用”。

`0013_questionnaire_publishing.sql` 保存管理草稿、发布者、发布说明和幂等请求。发布函数取得项目级 transaction lock，严格验证 JSON 定义，并在同一 transaction 中建立新版本、写入问题和选项、切换唯一 current 版本。管理端已发布定义受触发器保护，不能追加、修改或删除；回退只能复制旧版本并发布新版本。

`0014_questionnaire_draft_upgrades.sql` 给私有草稿保存升级来源，要求新旧草稿属于同一用户、空间和项目，并绑定不同问卷版本。来源草稿可以作废，新草稿及审计来源保持不变。

`0015_questionnaire_metric_compatibility.sql` 保存稳定问卷指标、当前版本成员和追加式兼容审计。确认前生成问题定义和样本影响快照；撤销追加事件并删除当前候选成员。runtime role 只能调用受控函数，不能直接读写指标表。

`0016_promotion_target_directory.sql` 保存 workspace 级个人或机构对象、当前跟进分配和不重复 PII 的幂等与访问审计。建立函数在同一事务中产生对象 UUID、初始分配和审计；列表函数只返回当前分配对象。runtime role 不能直接读写资料或审计表。

`0017_contact_target_links.sql` 给每个接触 revision 保存零到多条对象关联快照，以及对象在当前项目中的独立关系阶段。关联只保存对象 ID、类型、可选当次反应和后续联系同意，不复制 PII，也不改变场次、触达人数或整体兴趣。新关联、阶段 0 确认、接触写入和 Outbox 在同一 transaction 中完成；修订、冲突解决和拉取都保留逐版本历史。Warehouse payload 只保留对象类型、当次反应和同意状态，不包含对象 ID。

[`follow_up_consent_ratio_v1.csv`](./fixtures/shared/follow_up_consent_ratio_v1.csv) 是后续联系同意占比的共享合同。它固定项目启用、当前有效 contact-target link、`yes / (yes + no)`、默认 `unknown` 作为未回答、half-up 基点和候选集排除边界。`0048` 保存可信启用事实，`0049` 的个人比例 bridge 直接消费这份 fixture；管理隐私报告仍须另行交付。

`0018_promotion_target_relationship_audit.sql` 把项目关系扩展为当前投影和追加 revision 历史。阶段仍固定为 `0–4`，生命周期独立保存；阶段、生命周期和共享跟进备注的每次修改都保留操作者、时间、原因和 mutation ID。旧 revision 通过 base snapshot 做字段级三方比较：不同字段自动合并，同字段把拟提交内容写入受保护冲突表，等待当前跟进者明确解决。阶段下降要求结构化原因。项目别名只覆盖显示名，双倍刻度只在响应中派生。runtime role 不能直接读取备注、冲突或历史表。

`0019_person_institution_relationships.sql` 保存 workspace 内明确建立的个人与机构关系。六类性质固定；同一对对象可同时有不同性质，但同一种活动关系只允许一条。建立和结束都追加 revision 并使用 mutation ID。列表和写入都要求调用者仍同时获分配两端对象；关系本身不增加分配、成员资格、接触关联或 warehouse 事实。

`0020_promotion_target_retention.sql` 保存一至十二个月的 workspace 保留策略和不含 PII 的续期／匿名化审计。期限基准取对象建立、最近有效接触和最近明确续期中的最新时间。到期目录读取先匿名化；明确撤回立即匿名化。一个 transaction 会清除对象 PII 和历史敏感文本、结束活动分配与关系，同时保留接触和去标识统计。

`0021_personal_action_plans.sql` 保存每位用户、每个项目的一份私人计划和追加式版本。首次设置采用当前自然周；后续目标、IANA 统计时区或周期起始日修改从下一周期生效。进度只计算当前有效、已提交且实际发生在周期内的接触。runtime role 只能用可信当前上下文读取或修改本人计划，不能直接读表，也没有管理员列表函数。

`0022_personal_action_reminders.sql` 独立保存每位用户、每个项目的可选每日当地提醒钟点。版本只追加，提醒可在没有周目标时单独使用。服务端不会保存或开启设备通知权限；每台设备的 opt-in 只留在本机。runtime role 同样只能通过可信当前上下文读写本人提醒。

`0023_management_contact_session_privacy.sql` 建立固定双期间渠道网格的私有隐私政策。函数执行 `k=10`、至少三位推广者、单人不超过一半和总计互补隐藏；隐藏结果不返回精确值。runtime role 没有 `app_private` 使用权或函数执行权；`0031` 只在私有事务中组合授权和发布，`0036` 再通过固定报告 bridge 调用它。

`0024_management_report_contract.sql` 注册 `contact_sessions_by_channel_two_periods` v1，并只接受报告 ID 与版本。项目、时区、日期范围、维度、筛选和导出字段不能来自客户端。TypeScript 与 PostgreSQL 读取同一请求 fixture，对账规范查询指纹和失败结果。审计信封不含报表值。注册表和函数仍在 `app_private`，runtime role 没有读取或执行权。

`0025_management_report_periods.sql` 给固定报告定义增加 `iso_week_monday_v1` 边界，并用项目可信 IANA 时区解析数据截止点之前最近两个完整周。函数按当地日历分别换算三个周一午夜，所以夏令时切换周可以是 167 或 169 小时。TypeScript 与 PostgreSQL 读取同一期间 fixture。该 migration 不保存项目时区，也不开放 runtime 执行权。

`0026_management_report_execution.sql` 在一个私有函数中组合固定定义、完整期间、项目内有效接触和隐私网格。函数只读取截止点前已提交的当前活动接触；接触尝试、作废、期间外和其他项目记录不进入。按推广者形成的贡献只存在于函数内部，最终 JSON 固定为 16 个保护后格子。该函数仍无 runtime 执行权，也不提供历史快照。

`0027_management_report_pair_release.sql` 比较同一项目两份固定报告中实际 UTC 边界相同的期间。共享格的显示数量或隐私状态发生变化时返回 `blocked`，无共享期间也失败关闭。判定只返回版本、指纹、截止时间和原因码，不返回格值。该函数不保存旧报告、查询历史或授权结果，runtime role 仍不能执行。

`0028_management_report_snapshots.sql` 在一个私有事务中生成受保护报告、取得稳定 lineage 锁、比较最近已发布快照并追加发布历史。首次报告建立唯一基线；后续只有 6F 判定通过才保存候选 protected document。被阻止的尝试只保存原因码和请求元数据。快照另存项目 change sequence 水位；这冻结输出，但不提供历史 `as-of` 重算。版本或时区改变不能重置 lineage。runtime role 仍不能读取私有表或执行发布和读取函数。

`0029_project_reporting_time_zone.sql` 为组织项目保存追加式报告 IANA 时区版本。首次配置立即生效；后续配置由旧时区的下一个 ISO 周一边界生效。函数使用期望版本和 UUID 幂等键，并拒绝第二个待生效版本、个人项目、归档项目和无效时区。读取函数按可信 UTC 时间返回当前和待生效版本，未配置时不回退 UTC。该 migration 不改写 6G 发布函数，也不向 runtime 开放私有配置。

`0030_management_report_authorization.sql` 保存互相独立的组织成员关系、项目成员关系和项目管理报告能力。私有解析器只在活动账号、组织、项目和三级授权事实同时有效时返回最小证据。查看固定使用 `view_anonymous_analytics`，发布固定使用 `release_management_reports`，二者互不包含。解析器取得三层 transaction lock 后使用可信数据库时间，并与关系撤权共享这些锁；证据只能在同一数据库事务内消费。当前没有生产授予、撤销、HTTP 或 Flutter 入口，runtime role 不能直接访问新表或私有函数。

`0031_trusted_management_report_release.sql` 提供无时区、无截止时间参数的私有发布 v2。函数在组织／项目／发布能力、请求、项目时区和报告 lineage 锁全部取得后重新授权，以该数据库时间选择准确的时区 revision 并调用既有受保护快照发布。独立不可变表保存最小授权和 revision provenance；旧 v1 快照、缺失 provenance 或 revision 变化都在生成候选报告前失败关闭。runtime role 仍不能执行发布或读取证据。

`0032_authorized_management_report_snapshot_read.sql` 提供只有内部用户、项目和快照 ID 的私有读取入口。函数固定检查 `view_anonymous_analytics`，只返回属于请求项目且由成功 v2 发布记录准确指向的不可变 `protected_report`。每次已授权尝试在同一事务中追加不含报告格值的不可变访问事件；未知与跨项目快照统一为 `not_found`，legacy provenance 失败关闭。runtime 与 PUBLIC 不能读取新表或执行新函数。

`0033_runtime_authorized_management_report_snapshot_read.sql` 是生产 Backend 唯一可执行的管理快照 bridge。它只接收已验证 token 的 issuer、subject、显式项目和快照 ID，映射既有活动内部用户后调用 `0032`。未知身份不会 bootstrap 个人上下文。函数采用 `SECURITY DEFINER` 和固定 search path；runtime 只有这个 bridge 的执行权，仍不能使用 `app_private` 或直接读快照与审计。

`0034_management_analysis_contexts.sql` 提供独立于个人 session 的管理分析项目发现与选择。列表只返回当前完整授权链含 `view_anonymous_analytics` 的组织项目。选择在同一事务中消费 `0030` 解析器，并保存组织成员、项目成员和 grant 的精确证据；撤权或以新关系重新加入后旧选择不会复活。runtime 只能执行两个窄函数，不能直接读取选择或授权表。

`0035_management_report_snapshot_directory.sql` 提供按显式项目列出可信 v2 管理报告快照的只读目录。数据库在同一事务中重新检查完整 `view_anonymous_analytics` 授权链，只返回至多 20 项固定元数据，并按数据截止时间、发布时间和快照 ID 降序排列。每次成功访问都追加一条不可变目录审计；审计保存精确授权证据和返回数量，但不保存快照 ID、报告元数据或格值。runtime 只能执行一个窄 bridge。目录不判断“当前”或“最新有效”，也不提供筛选、分页或任意历史查询。

`0036_runtime_trusted_management_report_release.sql` 是生产 Backend 唯一可执行的管理报告发布 bridge。它只接收已验证 token 的 issuer、subject、显式项目和请求幂等 UUID，并固定发布 `contact_sessions_by_channel_two_periods` v1。未知或停用身份不会 bootstrap 个人上下文。runtime 只能执行这个 `SECURITY DEFINER` 函数，仍不能进入 `app_private`、读取发布记录或接触事实。bridge 在同一 statement 中调用 `0031`，因此发布继续使用相同的授权、时区和 lineage 锁。

`0037_management_region_privacy_probe.sql` 增加私有、fixture-first 的区域隐私威胁探针。它只接受固定 synthetic 候选形状，用类型化原因识别父子、其他查询集合或跨版本重叠、历史格变化、错误显示的小样本、互补恢复、外部已知事实、缺失原始来源或当前区域映射，以及把待解析或 `N/A` 当成区域格。输出没有坐标、贡献者或隐藏值。该 migration 不注册生产区域报告，也不向 runtime 或 Backend 开放函数。

`0038_freeze_published_canonical_region_trees.sql` 给规范区域树增加 `draft`／`published` 生命周期和发布冻结。历史 release 迁移为 `published`，新草稿只能由 `app_private.publish_canonical_region_tree_v1(text, boolean)` 在同一事务中验证严格单父、无环、城市父链和边界后发布。函数按固定排序和规范编码生成内容指纹；发布后节点、父级、名称、`kind`、`attributes`、边界、版本、发布时间和指纹都不能直接改写。成为 `current` 只改变唯一当前投影，并追加选择历史，不覆盖旧版本。`tongxingzhe_runtime` 仍只能执行区域解析函数，不能读取区域表、选择历史或发布函数。

`0039_contact_location_provenance.sql` 为已接受接触 revision 建立追加式地点来源合同。每个 `contact_id + revision_number` 最多一条来源记录；`resolved` 必须引用已发布区域树、城市父链和 0038 内容指纹，且可明确区分有原始坐标与 `region-only`。`pending_resolution` 只保存合法坐标，`not_applicable` 不保存坐标或区域；历史无法解释的行保持 `incomplete`／`unknown`。来源记录不能 `UPDATE`／`DELETE`，也不能由 `contact_region_assignments` 当前投影伪造历史。回填只读取每个 revision 自己的 `snapshot.location` 和可选 `snapshot.locationSource`，不改写既有 contact、revision 或 assignment。三路修订把 location 与 source 作为同一事实组，避免旧坐标与新区域误配。精确坐标留在受限 `app_data`；warehouse outbox 的边界 trigger 会移除 location 和 source，防止修订或作废路径把它们送入分析层。`tongxingzhe_runtime` 没有来源表、sequence 或维护函数直接权限。该 migration 只固定 PostgreSQL 合同、历史回填和 fixture-first 证据，不表示 Flutter／Drift、Backend HTTP 或生产写入 bridge 已接入。

`0040_canonical_region_resolution_provenance.sql` 提供 `resolve_canonical_region_with_provenance` 窄函数。它复用 0007 的当前树匹配，只在对应 release 已发布且内容指纹是 64 位小写 SHA-256 时返回结果，并补充固定解析器合同。runtime 只有函数执行权，仍不能直接读取 release 或边界表；发布身份和 PUBLIC 也不能执行该入口。该 migration 不写接触来源，不改变旧 resolver 的兼容合同。

`0041_personal_interest_ordinal_summary.sql` 提供个人兴趣有序汇总的窄函数。它只读取可信个人 scope 和 UTC 半开期间内的当前有效接触，返回 `0–4` 五档数量、接触场次总数和下中位等级。偶数样本取两个中间观察值中较低的真实等级；空期间返回 `NULL`。runtime 可以执行函数，但不能直接读取接触表。Drift 与 PostgreSQL fixture 读取同一份 `personal_contact_metrics_v1.csv`，并分别覆盖奇数、偶数、空期间、右边界、其他用户和其他项目。

`0042_personal_interest_level_ratios.sql` 提供 `read_personal_interest_level_ratios` 窄函数。它复用个人 workspace／项目授权、当前有效接触和 UTC 半开期间，稳定返回五行 `0–4` 比例；每行同时给出整数 `numerator`／共同 `denominator`、四种缺失计数、比例定义排除数和 `percentage_basis_points`。当前核心兴趣的 `NOT NULL` 与 `0–4` 约束使四种缺失计数和比例定义排除数为零；作废、草稿和尝试属于生命周期边界，不计入 `excluded_count`。正分母使用 numeric 中间值执行整数 half-up，空分母保留 `0/0` 且百分比为 `NULL`。对应 fixture 复用 `personal_contact_metrics_v1.csv`，另覆盖作废、右边界、其他项目、其他用户、非法期间和 `2/3 → 6667` 基点舍入。

`0043_personal_interest_subset_ratios.sql` 提供 `read_personal_interest_subset_ratios` 窄函数。它从同一份 scoped、当前有效接触集合一次计算共同分母，固定按顺序返回 `interest_3_4_ratio` 与 `interest_0_ratio` 两行；两者的分子分别是兴趣 `3/4` 和 `0` 的接触场次，允许分子之和小于分母，因此不能包装成 0042 的五档 exhaustive 比例。每行仍返回整数分子／共同分母、四种缺失计数、候选内排除数和 half-up 基点；当前核心兴趣约束使这些覆盖字段为零，空分母返回 `0/0` 与 `NULL`。对应 fixture 复用 `personal_contact_metrics_v1.csv`，另覆盖仅 `1–2`、全 `0`、全 `3–4`、五档混合、空期间、边界、作废、跨用户／项目和 `2/3 → 6667`。

`0044_personal_target_response_distribution.sql` 提供个人项目对象反应的窄分布 bridge。统计单位是当前有效 contact revision 中的对象关联；`response_level` 为 `NULL` 的关联不进入 0–4 五档分母，而在固定五行结果中以共享的 `unanswered_count` 单独返回。函数按可信用户、personal workspace、active project 和 UTC 半开期间重新授权，只读取 contact/link 事实，不连接 target PII、分配或关系状态，因此对象匿名化后历史响应仍可统计。空期间仍返回 0–4 五行，`denominator=0`、`unanswered_count=0`。对应 fixture 还覆盖多关联、current revision、作废排除、起止边界、跨项目／用户 scope 以及 retention anonymization。

`0045_personal_target_response_ordinal_summary.sql` 从同一组当前已填对象关联返回五档数量、已填总数、未填覆盖和下中位等级。偶数样本取较低的真实等级；全部未填或空期间返回五档零、已填总数零和 `NULL` 中位。函数复用 0044 的个人 scope、current revision、作废排除和 UTC 半开边界，不读取对象 PII。

`0046_personal_target_response_level_ratios.sql` 提供对象当次反应的 `target_response_level_ratios@1` 五档比例 bridge。它复用个人 scope、当前有效 contact revision 和 UTC 半开区间；`response_level` 非 `NULL` 的 contact-target link 组成共同 answered 分母，`NULL` 只返回 `unanswered_count`。五档每行返回整数分子、共同分母和按 half-up 计算的百分比基点，空分母保留 `0/0` 与 `NULL` 百分比。fixture 覆盖 `2/9` 舍入、全 `NULL`、空期间、current revision、作废、边界、跨项目／用户 scope、非法期间和权限；bridge 不读取对象 PII。

`0047_personal_current_relationship_stage_snapshot.sql` 提供个人当前关系阶段的窄快照 bridge。它在一次 statement 中重新验证 personal workspace owner、active project、当前查看者的 active assignment、active target 和 active relationship；按对象 × 项目去重后返回 `0–4` 阶段、当前 revision 和更新时间。paused、ended、匿名化对象、结束分配、其他用户和其他项目均不进入结果。空范围仍返回一个 UTC 快照 envelope。runtime 只有函数执行权，不能直接读取对象、分配或关系来源表。

`0047` fixture 与 Flutter 合同测试共同消费 `current_relationship_stage_v1.csv`。主场景五档各保留一个 active 关系；重复对象 × 项目场景必须整体失败，不能任选 revision 或重复计数。数据库检查还固定函数形状、`SECURITY DEFINER` search path、权限、PII-free JSON keys、稳定排序和 pending coverage 为零。

`0048_project_follow_up_consent_opt_in.sql` 为 `follow_up_consent_ratio@1` 保存个人项目的追加式启用版本。配置和读取函数都从可信 issuer／subject 重新解析活动个人空间所有者和活动项目；runtime 只有这两个窄函数的执行权，不能直接访问版本表。首次配置使用预期版本零，后续变更必须提供当前版本；UUID 请求 ID 使同内容重试稳定返回原版本，过期版本、内容不同的重放和并发竞争失败关闭。当前启用后可以回看已有期间；停用或从未配置只返回 `not_enabled`，不会删除接触事实或伪造比例、覆盖和排除数。

`0049_personal_follow_up_consent_ratio.sql` 提供个人后续联系同意占比的 PostgreSQL bridge。公开函数的签名是
`app_data.read_personal_follow_up_consent_ratio_v1(text,text,uuid,text,timestamptz,timestamptz)`：前两个参数是 Backend 从已验证 JWT 取得的可信 issuer／subject，第三个参数是项目，第四个参数必须是 `follow_up_consent_ratio@1`，最后两个参数是 UTC 半开期间。函数先重新核对活动账号、个人空间所有者和活动项目，再读取 0048 的当前开关。没有配置或当前停用时立即返回四个键 `contract_id`、`metric_id`、`project_id`、`status`，其中 `contract_id` 固定为 `personal_follow_up_consent_ratio_result_v1`，`status` 为 `not_enabled`；这个结果不含 `period`、`value`、覆盖或排除字段，也不读取接触事实。

当前开关启用时，结果仍使用上述三个身份键和 `status: "ready"`，并增加 UTC 半开 `period` 与嵌套 `value`。`value` 保存 `yes_count`、`no_count`、`numerator`、`unknown_count`、`refused_count`、`not_applicable_count`、`unanswered_count`、`excluded_count`、`denominator` 和 `percentage_basis_points`；`numerator` 与 `yes_count` 相同。分母是 `yes + no`，`unknown_count` 与 `excluded_count` 固定为零；分母为零时返回 `0 / 0` 和 `NULL` 基点。统计只使用活动接触的 current revision contact-target link；旧 revision、作废、草稿、尝试、问卷同名答案、其他项目和期间外记录在候选集前排除。

`0049` fixture 直接用 psql `\copy` 读取 [`follow_up_consent_ratio_v1.csv`](./fixtures/shared/follow_up_consent_ratio_v1.csv)，再把共享行映射为 PostgreSQL 的 contact、revision 和 contact-target link，逐场景对账结果。它必须覆盖主场景 `2 / 3 = 6667`、多对象关联、`unknown`／拒答／不适用覆盖、无 `yes`／`no` 的空分母、current revision、作废、错误统计单位、其他 scope、左含右不含的 UTC 边界，以及未启用分支的四键结果。该 migration 只交付 PostgreSQL bridge、权限、fixture 和检查；不包含 Flutter／Drift、Backend HTTP、项目设置、离线缓存、管理报告或 warehouse。

`0050_personal_relationship_stage_change_events.sql` 用共享 [`relationship_stage_changes_v1.csv`](./fixtures/shared/relationship_stage_changes_v1.csv) 独立重算阶段变更候选集。它固定可信 actor、workspace、project、UTC 半开边界、`project_entry`、lifecycle-only、note-only、同阶段、上升、下降和结束分配边界；0051 的 bridge 另外固定匿名化后仍保留历史，因为查询不按 target status 过滤。主场景必须得到 `5` 个事件、`4` 个不同对象×项目关系、`3` 个上升和 `2` 个下降；重复 revision 场景必须整体失败关闭，不能用 `DISTINCT` 掩盖错误输入。

`0051_personal_relationship_stage_change_summary.sql` 提供生产读取 bridge
`app_data.read_personal_relationship_stage_change_summary_v1(text,text,timestamptz,timestamptz)`。
函数使用 `SECURITY DEFINER` 和固定 `search_path = pg_catalog, app_data`。runtime role 只有
`EXECUTE`，没有 revision、target、assignment、identity 或 current-project 源表的 `SELECT`；
`PUBLIC` 也没有函数执行权。

bridge 接收 Backend 从已验证身份取得的 issuer／subject 和 UTC 期间，不接收 project ID。一次
bridge 调用在同一 PostgreSQL transaction 中把 issuer／subject 解析为 active app user，对
`app_data.user_current_projects` 的当前行加 `FOR UPDATE`，再验证未删除的 personal workspace、
属于该 workspace 的 active current project，最后用一个 PostgreSQL statement snapshot 聚合
历史 revision。项目切换、归档或删除与读取并发时，锁只允许完整旧项目结果、完整新项目结果或
`42501` 失败，不会混合两个 project。

统计只读取 revision，并将 revision join 到 target 的 workspace。它按可信 actor、current
workspace／project 和 `changed_at >= from_utc AND changed_at < until_utc` 过滤，并要求 `old_stage IS NOT NULL`、
`old_stage <> new_stage`、`changed_fields` 包含 `stage`、`reason_code <> 'project_entry'`。
它不按当前 assignment、relationship lifecycle 或 target `status = 'active'` 过滤，所以对象
匿名化或 assignment 结束不会删除此前合格事件；匿名化产生的 lifecycle-only／note-only revision
不计入。结果只有固定计数和 statement 时刻的 `data_cutoff_utc`／`authorized_at_utc`，不提供
历史 as-of 或逐事件明细。

`promotion_target_relationship_stage_change_actor_project_time` 是该候选集的部分
索引，覆盖 actor、project 和 changed-at。`verify_personal_relationship_stage_change_summary.sql`
检查函数形状、`SECURITY DEFINER`、search path、runtime 最小权限、PII-free keys、不变量和
关闭顺序扫描后用 `EXPLAIN` 验证结构性索引路径。这个检查证明查询谓词可使用该部分索引，不预测
生产数据分布下的成本计划；部署后仍需正常 `ANALYZE` 和查询计划监测。完整 Docker runner 还要
运行对应 Backend adapter integration、已注册并发脚本和 dump／restore；单独通过 SQL fixture
不能声称 HTTP 或 Backend 集成已通过。

`0052_management_report_snapshot_export.sql` 为可信 v2 管理报告快照增加固定 canonical JSON v1
导出。唯一 runtime bridge 只接受已验证身份、显式项目和快照 ID，并在同一数据库边界重新检查
`view_anonymous_analytics` 与 `export_management_reports`。响应只从已保存快照生成稳定 UTF-8 bytes；
`displayed` 保留受保护整数，`suppressed` 固定为 `null`。每次已授权生成都会追加不含报告格、贡献者、
地点或 PII 的不可变导出事件。服务端审计只证明已授权并准备交付，不证明客户端已经保存或打开文件。

`0053_canonical_region_version_mappings.sql` 保存已发布规范区域树之间的显式一对一映射证据。每条
映射绑定来源和目标的 tree version、region ID、冻结内容指纹、固定 evidence contract 和 SHA-256
evidence digest。独立的无登录 mapping writer 拥有私有登记与解析函数；区域发布身份只有函数执行权，
没有表写入权。精确 request 重试幂等，载荷漂移、拆分和合并失败关闭。映射只可追加，不能更新、删除或
清空；私有解析不组合链，也
不按名称、父链或几何相似度猜测。runtime 和 PUBLIC 无表或函数权限；本 migration 不注册生产区域
报告，也不改写 contact location provenance。

`0054_management_region_attribution.sql` 提供私有、只读的管理区域归属 evidence resolver。调用方必须
明确选择 `original` 或 `current`；`original` 的两个 target 参数必须为 `NULL`，`current` 才提供已发布
目标树版本和精确内容指纹。`original` 只接受已验证来源 release、指纹、节点和城市父链；`current` 对坐标
只接受指定树中的唯一最深同链命中，对 `resolved_region_only` 只接受同版本来源或 0053 显式一对一 mapping。
零命中、跨链或同深度多命中、错误指纹和缺失映射均失败关闭或返回稳定状态；`pending_resolution`、
`not_applicable` 和不完整来源返回 `not_reportable`。输出不含 source ID、contact、revision、贡献者、
地点名、坐标或 PII，也不读取 current selection 或自动选择报告截止点。无登录 reader role 只拥有 resolver
所需的受保护读取能力；runtime、PUBLIC、区域发布者、mapping writer 和 provenance writer 没有新增执行权或表权。
该 migration 不注册生产区域报告。

`0055_management_report_region_target_context.sql` 提供 6AM 的历史派生 cutoff resolver
`app_private.resolve_management_report_region_target_context_v1(timestamptz)`。它只读取追加式
current selection history 和已发布 release，用可信 `data_cutoff_utc` 选择 `selected_at_utc <= cutoff` 的
唯一历史上下文，并返回树版本、精确指纹、selection sequence、selection source、证据时间和发布时间。
目标 release 必须在 cutoff 前发布。0038 migration baseline 的 `selected_at_utc` 为 `NULL`，只能从
`recorded_at_utc` 这个观察下界使用；更早 cutoff 返回历史不可用，不把观察时间当成选择时间。
没有符合 cutoff 的历史时返回不含 target tuple 的稳定不可用文档；选中的历史若指向草稿或缺失 release，
或者指纹、选择时间和发布时间不一致，则以 `SQLSTATE 55000` 拒绝解析。

发布函数和 6AM resolver 共用 `canonical-region-tree-publication:v1` 事务 advisory lock。resolver 是
私有 `VOLATILE SECURITY DEFINER` 函数，reader role 只获得所需的 selection history 和 release 读取权限。
runtime、PUBLIC 和区域维护角色都不能执行它；runtime 和 PUBLIC 也不能直接读取 selection history。区域发布者
只保留 0038 发布流程所需的既有 `SELECT`／`INSERT`。未来区域报告先消费 6AM 的显式树版本和指纹，
再传给 6AL；0055 不聚合接触、不注册报告、不开放 HTTP 或 Flutter。

`0056_management_current_city_report.sql` 提供 DB-only 的固定区域候选
`contact_sessions_by_current_city_two_periods@1`。专用 canonicalizer 只接受该 ID 和 version；旧渠道
canonicalizer、16 格 validator、快照、HTTP 和导出继续拒绝它。executor 只接受可信项目、IANA 报告时区和
截止点，先消费 6AM 的 target context，再把显式树版本和指纹传给 6AL。它不接受客户端树版本、城市列表、
坐标、polygon 或筛选。

候选使用 current active contact 的 current revision，并把可报告的最小区域归入目标树中唯一城市祖先。
完整网格固定为两个完整 ISO 周 × 目标树全部城市，按 `C` 排序。每格先执行 `k=10`、至少三位贡献者和
单人不超过一半；一个期间只有一个 primary-suppressed 格时，再按稳定城市顺序互补隐藏一个可显示格。
suppressed 值始终为 `NULL`。输出包含固定定义、期间、截止点、source change watermark 和 6AM 选择证据，
不含城市名称、边界、坐标、来源、contact、revision、贡献者或 PII。

无登录、无成员的 `tongxingzhe_management_region_report_reader` 只获得所需列读取和私有函数执行权。
runtime、PUBLIC 和区域维护身份不能执行 executor。0056 不提供 original 视图、生产快照、runtime bridge、
HTTP、Flutter、缓存或导出；watermark 也不把 current projection 变成历史 `as-of`。

`0057_management_current_city_report_snapshot_lineage.sql` 只增加 DB-only 的 6AO 固定发布合同。它复用通用的
不可变受保护快照存储 `app_private.management_report_snapshots`，但为 current 城市报告保存独立的区域 release
attempt／provenance；区域 provenance 不能冒充渠道 v2 provenance。私有发布在取得必要锁后重新验证
`release_management_reports`，由数据库派生可信项目报告时区 revision、`data_cutoff_utc` 和 6AM target context，
再调用 6AN executor。调用方不能提交 JSON、capability、时区、截止点、城市列表或 target tuple。

0057 的 validator／pair comparison 固定 report、metric、dimension、view、granularity、query fingerprint、privacy、
source scope、期间、source watermark、target context 和完整 cells。completed 以外的 unavailable、额外字段、错误
identity、错误 target tuple、缺失／重复／乱序网格或期间错误都失败关闭；`displayed` 必须达到 6AN 的 `k=10`，
`suppressed` 必须是 JSON `null`。

首个通过 6AN 合同的文档建立唯一 baseline；后续发布只能推进 cutoff，并保持定义、期间、完整网格、target tuple
和可信时区 revision 一致，且链接前一 snapshot。相同 request 和固定上下文精确幂等，不新增 snapshot 或 attempt。
一张不含报告值的 request claim 表使 current-city UUID 与渠道发布 UUID 互斥；trusted v2 仍与它委托写入的 v1
记录共享同一渠道 claim。

same／earlier cutoff、无共享期间、共享期间的城市值或隐私状态变化，以及 target tuple、时区 revision、定义、期间
或网格上下文漂移，均返回稳定 blocked reason。失败 attempt 只能保存不含 protected document、cells、来源、贡献者、
隐藏前值和 PII 的最小 lineage 证据。snapshot 与 attempt 均追加不可变，不允许 UPDATE 或 DELETE。既有 channel v2、
snapshot read、directory 和 export 仍只接受固定渠道定义，不接受区域文档。

0057 的 release writer 之外，runtime、PUBLIC 和区域维护身份不能执行发布、读取区域 provenance 或直接写区域
attempt／snapshot 表。0057 本身不实现 HTTP、UI、Flutter、Drift、缓存、目录、读取、导出、生产调度、retention 或
warehouse。通过 0057 的数据库检查只证明 synthetic DB-only 合同，不证明生产区域报告已经发布。0058 单独增加
current 城市快照读取，不改变 0057 的发布和 provenance 边界。

`0058_authorized_management_current_city_report_snapshot_read.sql` 增加 DB-only 的 6AP 读取合同。调用方必须提供
用户、项目和 snapshot UUID。函数先重新解析 `view_anonymous_analytics`，再只接受有
`current_city_management_report_snapshot_release` claim 的 0057 `approved`／`approved_baseline` attempt。
`reason_codes` 必须是空数组。attempt 与 snapshot 的 report、query、lineage、reporting time zone、cutoff、previous
snapshot 和 target tuple 必须对齐，函数还会再次调用 0057 current-city document validator。

成功读取在同一 transaction 写入不可变、value-free 的访问审计。unknown、cross-project、legacy channel 或不可信
provenance 只返回失败状态，不返回 protected report。撤权与读取共享授权锁；runtime、PUBLIC 和区域维护身份不能
读取审计表或执行函数。0058 不增加 HTTP、Flutter、Drift、缓存、目录或导出。

在专用测试库中验证 6AP：

```bash
export DATABASE_URL='postgresql://postgres:postgres@127.0.0.1:5432/tongxingzhe_test'
./tool/postgres_migrate.sh
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/checks/verify_authorized_management_current_city_report_snapshot_read.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/fixtures/0058_authorized_management_current_city_report_snapshot_read.sql
./tool/verify_authorized_management_current_city_report_snapshot_read_concurrency.sh
```

完整 Docker runner 会自动发现 0058 的 migration、check、fixture 和并发脚本，并在 checksum、dump／restore 和恢复库
中重跑。通过只证明 synthetic DB-only 合同成立，不证明生产区域证据或 HTTP／客户端已经完成。

`0059_runtime_authorized_management_current_city_report_snapshot_read.sql` 增加 Backend runtime 的窄读取桥。调用方
提供 external identity 的 exact issuer／subject、project UUID 和 snapshot UUID。bridge 只映射现有 active identity，
随后调用 0058 current-city 私有函数。它不 trim 数据库中的 identity 值，也不调用渠道 read。runtime 本身不能直接读取
用户、identity、snapshot 或审计表。

0059 使用 `SECURITY DEFINER` 和 `search_path = pg_catalog`。runtime 只有 bridge `EXECUTE`，没有 `app_private` schema
usage、关键私有表或函数权限。bridge owner 必须与 0058 私有函数 owner 相同，且不能是 runtime、区域维护或 release
writer。Backend adapter 只执行一次固定 SQL，并严格检查 root keys、project／snapshot 绑定、固定报告定义、period、
target context、两个期间的 city grid、cell keys 和顺序。它拒绝 contact、source、contributor、城市名称、坐标、
geometry 和其他额外字段。

真实 adapter integration 不依赖会回滚的 psql fixture。它在自己的 transaction 中建立 fixture 数据，读取 active identity，
验证未知 identity 失败关闭，最后回滚。完整 Docker runner 会显式运行该 integration，并在 checksum、并发和 dump／restore
恢复库中重跑 0059。

在专用测试库中验证 6AQ：

```bash
export DATABASE_URL='postgresql://postgres:postgres@127.0.0.1:5432/tongxingzhe_test'
./tool/postgres_migrate.sh
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/checks/verify_runtime_authorized_management_current_city_report_snapshot_read.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/fixtures/0059_runtime_authorized_management_current_city_report_snapshot_read.sql
cd backend/server
npm run build
DATABASE_URL="$DATABASE_URL" \
CURRENT_CITY_RUNTIME_FIXTURE=../../backend/database/fixtures/0059_runtime_authorized_management_current_city_report_snapshot_read.sql \
node dist/test/management-current-city-report-snapshots.integration.js
```

fixture、integration 和并发脚本不能互相替代。fixture 证明 exact identity、0058 claim、project／snapshot 对齐、runtime
ACL 和 value-free audit。integration 证明真实 Node adapter 的单次 bridge 调用和严格 JSON 对账。通过只证明 DB-only
runtime bridge 合同，不证明 HTTP、Flutter、目录、导出或真实平台运行时证据。

`0060_authorized_management_current_city_report_snapshot_directory.sql` 增加 current-city 快照目录的独立 DB 合同。它
不复用 0035 渠道目录。private 函数重新解析 `view_anonymous_analytics`，只返回通过 0057 current-city release family
claim 的 `approved`／`approved_baseline` 快照，且 attempt 的 project、report、version、query fingerprint、release lineage、
可信报告时区、cutoff、previous snapshot 和 target tree tuple 与 snapshot 对齐。固定报告为
`contact_sessions_by_current_city_two_periods@1`，`reason_codes` 必须为空；legacy channel、blocked／unavailable、跨项目、
claim 不匹配和 tuple 漂移的记录不会进入目录。

目录最多返回 20 项，按 `data_cutoff_utc`、`released_at_utc`、`snapshot_id` 降序排列。每项只含 snapshot UUID、报告 ID／版本、
报告时区、数据截止和发布时间。每次成功读取，包括空目录，都会在同一事务追加不可变、value-free 的目录审计。审计保存
授权 lineage、项目、访问时刻、结果和返回数量，不保存 snapshot ID、报告元数据、格值、来源、贡献者、城市名称、坐标或 PII。

runtime bridge 的签名是
`app_data.list_authorized_management_current_city_report_snapshots_v1(text,text,uuid)`。它使用
`SECURITY DEFINER`、`search_path = pg_catalog` 和 exact issuer／subject 的 active identity 映射，只调用 0060 private
函数。runtime 只有 bridge `EXECUTE`，没有 `app_private` schema usage、目录／snapshot／attempt／claim 表、用户表或
identity 表权限；区域发布、区域映射、接触来源、区域归属和 current-city release writer 角色也没有 bridge 或目录审计权限。
bridge owner 与 private function owner 相同，且不能属于这些 runtime 或写入角色。

`0061_management_interest_distribution_report.sql` 固定一个独立的 DB-only 管理报告候选
`contact_sessions_by_interest_level_two_periods@1`。metric identity 是 `interest_distribution@1`，维度是
`interest_level`，产品视图分类是 `management`（不是 DB 输出字段），粒度是 `iso_week_monday_v1`，query fingerprint 是
`management-report:contact_sessions_by_interest_level_two_periods:v1`，privacy policy 是
`management_interest_distribution_privacy_v1`，source scope 是
`backend_accepted_active_contacts_current_revision`。它只统计 Backend 已接受的有效接触场次，并以可信 `app_user_id` 作为
贡献者。

private policy／executor 使用项目报告 IANA 时区和可信 `data_cutoff_utc`，解析两个相邻、已经结束的完整 ISO 周。输出固定为
`previous/current × 0..4` 的十个格，只有 count-only 的 `displayed` 或 `suppressed` 状态，没有 total cell、中位数、比例或
其他派生值。每个期间的每个兴趣等级都检查 `N >= 10`、至少三位贡献者和 `2 × M <= N`；同一期任一等级不安全时，五格
整体 suppressed，count 全部为 `NULL`，另一期间独立判断。这个规则不依赖既有 channel 或 current-city 报告的隐藏状态，防止
跨报告相减恢复隐藏等级。

0061 的结构 check、fixture 和 Dart 对账必须覆盖恰好 `10`、三位贡献者、`50%` 上限，以及 `9`、两位贡献者、`6/10` 主导者；
还要覆盖半开周边界、可信截止点、项目隔离、草稿／尝试／作废排除、畸形输入、无 PII 输出和“同期渠道与城市总数可显示但兴趣
某档不安全”的跨报告反例。private policy／executor 不授予 `PUBLIC`、runtime 或普通 app role 执行权，也不提供 HTTP、快照、
发布、目录、Flutter、缓存、离线、同步、导出或 warehouse 入口。

### 如何验证 6AV PostgreSQL 合同

第一次使用 Docker 时，启动 Docker Desktop，从仓库根目录运行：

```bash
./tool/run_postgres_tests_in_docker.sh
```

runner 会自动发现 0061 migration、check、fixture、checksum 和 dump／restore。它使用隔离的 PostgreSQL 容器和 synthetic 数据，
最后删除临时容器。成功只说明当前 DB-only 合同在自动检查中成立。

如果本机已有专用测试库，可以单独运行：

```bash
export DATABASE_URL='postgresql://postgres:postgres@127.0.0.1:5432/tongxingzhe_test'
./tool/postgres_migrate.sh
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/checks/verify_management_interest_distribution_report.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/fixtures/0061_management_interest_distribution_report.sql
```

确认 `DATABASE_URL` 指向本机专用测试库。没有 `psql` 时使用 Docker runner。Dart 纯政策测试仍需单独运行，数据库 fixture 通过不替代
Dart 对账。Docker、PostgreSQL fixture 和 Dart 测试都不能证明 Backend HTTP、Flutter UI、真实身份提供方、六平台真人运行或
形式化不可重识别保证。

### 6AW：管理兴趣报告快照与独立发布 lineage

`0062_management_interest_report_snapshot_lineage.sql` 在 6AV 的十格 count-only 保护合同之上增加 DB-only 的不可变
兴趣报告快照与 release lineage。它复用 `app_private.management_report_snapshots` 的通用 snapshot storage，但使用独立的
兴趣 request claim family、release attempt 和 provenance；不能把兴趣十格文档当作 channel 16 格或 current-city 区域文档。

兴趣 validator／pair comparison 固定 6AV 的 report、metric、dimension、统计单位、两个相邻完整 ISO 周、period boundary、
query fingerprint、privacy policy、source scope 和 `previous/current × interest_level 0..4` 十格顺序。只接受符合 6AV 完整受保护文档合同的
文档；私有 release 在固定事务内调用 6AV executor 生成候选；`displayed` 只能保存安全整数 count，`suppressed` 必须是 JSON `null`。它不增加中位数、比例、total cell
或其他派生值。unavailable、额外字段、错误固定 identity／metadata、缺失／重复／乱序网格和贡献者、接触、地点或其他 PII
都失败关闭。

私有 release 只提交 request、可信内部 user、project 和固定 report identity。数据库在锁内重新验证
`release_management_reports`，在同一 release transaction 中派生可信项目报告时区 revision 和 `data_cutoff_utc`，再执行
6AV executor；调用方不能提交报告 JSON、时区、cutoff、期间、兴趣等级、筛选或 SQL。首个合法发布建立唯一 baseline；后续
发布只能推进 cutoff，保持固定定义、period definition／boundary、十格顺序、query fingerprint、privacy policy、source scope 和时区 revision 一致，
并链接前一 snapshot。相同 request 与固定上下文精确幂等，不新增 snapshot 或 attempt。

same／earlier cutoff、没有共享期间、共享期间内的兴趣格值或隐私状态变化，以及定义、period definition／boundary、网格、query fingerprint、privacy
policy、source scope 或时区 revision 漂移，返回稳定 blocked reason。blocked attempt 只保存最小 value-free lineage 和
reason，不保存候选文档、cells、来源、贡献者、隐藏前值或 PII。snapshot、attempt 和 request claim 追加不可变，不允许
UPDATE 或 DELETE。兴趣 request UUID 与 channel、current-city request UUID 互斥，兴趣 provenance 不能冒充其他发布 family。

release writer 之外，`tongxingzhe_runtime`、`PUBLIC`、普通 app role 和区域维护角色不能执行兴趣发布、读取兴趣 provenance
或直接写兴趣 snapshot／attempt 表。共享 snapshot 表用 report-family RLS 限制两个专用 release writer：current-city writer
只能访问自己的 report 与 lineage，兴趣 writer 也只能访问兴趣 report 与 lineage。表 owner 保留已有内部维护与受控读取路径。
check 应同时固定 owner、`SECURITY DEFINER`、`search_path`、函数执行权、表／列 ACL、RLS policy 和
旧 channel、current-city、6AV 合同隔离。

第一次使用 Docker 时，从仓库根目录运行：

```bash
./tool/run_postgres_tests_in_docker.sh
```

runner 会按完整 migration 顺序自动发现 0062 migration、check、fixture、并发脚本、checksum 和 dump／restore，并在恢复库重跑。
也可以在确认不是 production 的专用测试库中按顺序运行：

```bash
export DATABASE_URL='postgresql://postgres:postgres@127.0.0.1:5432/tongxingzhe_test'
./tool/postgres_migrate.sh
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/checks/verify_management_interest_report_snapshot_lineage.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/fixtures/0062_management_interest_report_snapshot_lineage.sql
./tool/verify_management_interest_report_snapshot_lineage_concurrency.sh
```

Docker、check、fixture 和并发脚本不能互相替代。通过只证明 DB-only synthetic snapshot、lineage、并发和 ACL，不证明 HTTP、
Flutter、runtime bridge、读取、目录、导出、生产发布、真实账号、六平台真人运行或形式化不可重识别保证。

### 6AX：授权读取单份管理兴趣快照

`0063_authorized_management_interest_report_snapshot_read.sql` 在 6AW 的 interest snapshot lineage 之上增加 private
DB-only 读取合同。读取函数只接收内部用户、显式 project 和 snapshot UUID。它在同一事务中重新解析
`view_anonymous_analytics`，再检查 0062 的 interest request claim、`approved`／`approved_baseline` attempt、空
`reason_codes`，以及 attempt 与 snapshot 的 project、report、version、query fingerprint、release lineage、报告时区、
`data_cutoff_utc`、`source_change_sequence`（source watermark）、previous pointer 和 released snapshot 对齐。返回前再次运行 6AV interest document
validator，不能让调用方提交报告 JSON、capability、时区或截止点。

`completed` 才返回原始的 `previous/current × interest_level 0..4` 十格 protected report；`suppressed` 继续是 JSON
`null`。未知或跨项目 snapshot 统一返回 `not_found`。同项目但属于 channel、current-city、legacy、blocked、缺失或漂移
provenance 的 snapshot 返回 `untrusted_provenance`。这两种结果都不带报告正文。读取函数不重算、不拼接其他报告，也不把
`view=management` 加入 6AV/6AW 没有定义的 DB 输出字段。

每次已授权尝试在同一事务追加兴趣专用的不可变、value-free audit。审计不保存 `protected_report`、cells、
`value_count`、贡献者、contact、来源或 PII。未授权、撤权、过期、release-only 和无项目成员调用失败关闭且不写 audit。
读取和撤权共享授权锁，因此 read-first 与 revoke-first 都有确定的数据库结果。runtime、`PUBLIC`、普通 app role、interest
reader、current-city writer 和区域角色不能执行读取函数或读取 audit／provenance。6AX 不增加 runtime bridge、HTTP、目录、
Flutter、Drift、缓存、离线、同步、导出、warehouse、retention 或生产调度。

在 Docker 中运行完整验证：

```bash
./tool/run_postgres_tests_in_docker.sh
```

runner 按 migration 文件名自动发现 0063 migration、结构／权限 check、synthetic fixture 和
`verify_authorized_management_interest_report_snapshot_read_concurrency.sh`。它还运行 checksum、dump／restore，并在
没有源 cluster roles 的恢复库重跑 migration、check 和 fixture。恢复阶段不重跑会提交 synthetic 行的并发脚本，避免把相同
并发写入再次导入恢复库。成功必须同时证明合法读取、三类失败状态、授权撤权并发、value-free audit、不可改删、最小 ACL 和
旧 channel、current-city、6AV、6AW 回归。

如果只调试已有专用 PostgreSQL 测试库，先确认它不是 production，再按顺序运行：

并发脚本会提交固定 `6d*` synthetic 行。每次运行请使用新建的空测试库；重复运行前应重建该测试库，否则固定主键会按预期冲突。

```bash
export DATABASE_URL='postgresql://postgres:postgres@127.0.0.1:5432/tongxingzhe_test'
./tool/postgres_migrate.sh
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/checks/verify_authorized_management_interest_report_snapshot_read.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/fixtures/0063_authorized_management_interest_report_snapshot_read.sql
./tool/verify_authorized_management_interest_report_snapshot_read_concurrency.sh
```

check、fixture 和并发脚本不能互相替代。通过只证明当前 PostgreSQL 的 private authorization、兴趣 provenance、失败关闭、
value-free audit、并发和 ACL。它不证明 runtime、HTTP、Flutter、导出、生产发布、真实账号、六平台运行或形式化不可重识别。

### 6AY：验证管理兴趣快照 runtime bridge

0064 把 0063 private read 接到 Backend runtime。bridge 接收 exact external `issuer + subject`、显式 project UUID 和 snapshot UUID，
只映射现有且 active 的 identity，再调用 0063 private function。它不 trim、bootstrap、读取 session context 或调用 channel、current-city、
directory、export 和其他 report reader。

bridge 使用 `SECURITY DEFINER` 和固定 `search_path = pg_catalog`。runtime 只拥有 bridge `EXECUTE`，没有 `app_private` schema usage、0063
private function、用户、identity、snapshot、provenance 或 audit 表权限。bridge owner 必须与 0063 private function owner 相同。Backend adapter
接收已有 `VerifiedIdentity`，只执行一次固定参数化 SQL，并严格解析 root keys、结果状态、reason code、project／snapshot 绑定和 6AX 十格
protected report。它拒绝额外字段、PII、隐藏前值和其他 report family；只把 `42501` 映射为 typed `forbidden`。

新手可以把 Docker runner 理解成一次性测试环境。它启动隔离的 PostgreSQL 和 Node 容器，使用 synthetic 数据完成测试，然后删除容器。
它不连接 production，也不会修改 production 数据。从仓库根目录运行：

```bash
./tool/run_postgres_tests_in_docker.sh
```

runner 自动发现 0064 migration、check 和 fixture，并显式运行第八条 Backend integration。它还运行 0063 read/revoke 并发、checksum 和
dump／restore。恢复库只重跑 migration、check 和 fixture，不重跑会提交 synthetic 行的并发脚本。

如果只调试专用测试库，先确认 `DATABASE_URL` 不是 production，再运行：

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

fixture 证明 identity、project／snapshot、0063 状态和 runtime ACL；adapter integration 证明真实 Node adapter 的一次 bridge 调用和严格 JSON
对账。通过只证明 DB-only runtime bridge 合同，不证明 HTTP、Flutter、目录、导出、真实身份提供方或六平台运行时。

### Slice 6BA：验证管理兴趣快照 metadata-only 目录

6BA 为 6AW interest snapshot 增加独立的 directory function、runtime bridge 和 value-free directory audit。它不复用 0035 channel directory 或
0060 current-city directory。数据库重新确认 `view_anonymous_analytics`，只列出 interest release family 中 approved／approved_baseline、空
reason 且 metadata 完全对齐的快照。目录最多返回 20 项，按 `data_cutoff_utc DESC`、`released_at_utc DESC`、`snapshot_id DESC` 排序。
第一项只是固定排序结果，不表示 current、latest、最新有效或未被取代。

固定目录函数和 HTTP collection route 为：

```text
app_private.list_authorized_management_interest_report_snapshots_v1(uuid, uuid)
app_data.list_authorized_management_interest_report_snapshots_v1(text, text, uuid)
GET /v1/projects/:projectId/management-interest-report-snapshots
```

private function 在一次事务中检查完整项目授权链，并过滤跨项目、channel、current-city、legacy、blocked、claim 不匹配和
lineage／metadata drift。数据库响应根对象只含 `access_contract_id`、`access_event_id`、`project_id` 和 `snapshots`。HTTP 成功正文不转发
内部 `access_contract_id`。每项只含 snapshot ID、固定 report ID／version、报告时区、data cutoff 和发布时间。响应和 audit 不含 protected
report、cells、suppressed 前值、来源、贡献者或 PII。

runtime bridge 使用 exact `issuer + subject`、`SECURITY DEFINER` 和固定 `search_path = pg_catalog`。runtime 只有 bridge `EXECUTE`，不能使用
`app_private` schema、读取目录或快照私有表，也不能执行 private function。目录 audit 追加且不可变，只保存最小授权 lineage、project、访问
时间、结果和返回数量。

#### Docker 完整验证

没有使用过 Docker 时，可以把它理解成一次性测试环境。Docker Desktop 启动隔离的 PostgreSQL 和 Node 容器，runner 使用 synthetic 数据运行
测试，完成后删除容器。它不连接 production。

```bash
cd "$(git rev-parse --show-toplevel)"
./tool/run_postgres_tests_in_docker.sh
```

runner 自动发现 0065 migration、directory check 和 fixture，并运行 interest directory Backend integration、独立 concurrency script、checksum
和 dump／restore。恢复库重跑 migration、check 和 fixture，不重跑会提交 synthetic 行的并发脚本。6BA integration 必须使用自己的 interest
directory fixture，不得读取 `CURRENT_CITY_RUNTIME_FIXTURE` 或 current-city directory fixture。

#### 专用测试库验证

先确认 `DATABASE_URL` 不是 production。并发脚本会提交 synthetic 行，所以每次使用新的空库：

```bash
export DATABASE_URL='postgresql://postgres:postgres@127.0.0.1:5432/tongxingzhe_test'
./tool/postgres_migrate.sh
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/checks/verify_authorized_management_interest_report_snapshot_directory.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/fixtures/0065_authorized_management_interest_report_snapshot_directory.sql
./tool/verify_authorized_management_interest_report_snapshot_directory_concurrency.sh
```

fixture 和 check 必须覆盖 exact identity、撤权、跨项目、approved interest provenance、legacy／blocked 排除、空目录、20 项上限、
固定排序、strict metadata、value-free audit、UPDATE／DELETE 拒绝和 runtime 最小 ACL。通过只证明 DB-only synthetic 合同，不证明 HTTP、
Flutter、导出、缓存、离线、生产身份或真人平台运行时。

### 6BD：原始区域城市固定报告

6BD 定义私有 PostgreSQL 报告 `contact_sessions_by_original_region_two_periods@1`。它固定 `metric=contact_sessions@1`、
`view_mode=original`、`dimension=original_region`、城市粒度、项目报告时区和两个完整 ISO 周。每份报告只能绑定一个精确的
`source_tree_version + source_content_fingerprint`；每条记录必须使用保存的 original 来源，并沿同一来源树找到唯一城市父级。

它不读取 6AM current target context，不做 current selection、跨版本 mapping、坐标重新解析或名称／父链猜测。release、指纹、节点、城市父链或其他证据缺失时，
记录不是可报告数据；候选中出现多个来源树 tuple 或没有可用来源树时，报告返回 unavailable／失败关闭，不跨树聚合。`data_cutoff_utc` 只限定本次纳入的
已接受事实，不是任意历史 `as-of`，也不选择 current 或 latest release。

输出是单一来源树的全部城市完整网格。每个期间和城市执行 `k=10`、至少三位贡献者、贡献者不超过一半和互补隐藏；只返回安全整数或
`suppressed = null`，不返回城市名称、边界、坐标、来源、contact、revision、贡献者或 PII。它只覆盖 DB-only private function、migration、check、fixture 和
并发合同，不提供 snapshot、authorized read、runtime、HTTP、Flutter、Drift、缓存、离线、同步、导出、retention、warehouse 或真机证据。

首次使用 Docker 时，先启动 Docker Desktop。runner 会启动隔离的 PostgreSQL 和 Node 容器，使用 synthetic 数据，结束后清理容器；它不会连接 production。
从仓库根目录运行：

```bash
cd "$(git rev-parse --show-toplevel)"
./tool/run_postgres_tests_in_docker.sh
```

runner 会自动发现 0066 migration、check、fixture 和并发脚本，并在 checksum 与 dump／restore 阶段重跑 migration、check 和 fixture；恢复库不会重跑会提交
synthetic 行的并发脚本。预期成功消息是 `PostgreSQL Docker 测试全部通过。`。这只证明 synthetic PostgreSQL 合同成立。

只调试专用测试库时，确认 `DATABASE_URL` 不是 production，并使用新的空库，因为并发脚本会提交 synthetic 行：

```bash
export DATABASE_URL='postgresql://postgres:postgres@127.0.0.1:5432/tongxingzhe_test'
./tool/postgres_migrate.sh
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/checks/verify_management_original_region_report.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/fixtures/0066_management_original_region_report.sql
./tool/verify_management_original_region_report_concurrency.sh
```

check、fixture 和并发脚本分别验证原始来源证据、单一来源树、唯一城市父级、`not_reportable`、混合树失败关闭、完整网格、阈值、互补隐藏、无敏感输出和 ACL。
这些数据库证据不代表真实区域树内容、任意 `as-of`、Backend、HTTP、Flutter、生产身份、导出或六平台真人运行时。

### 6BG：原始区域报告 snapshot/release lineage

6BG 在 6BD 的 original-region 候选之上建立独立的私有 snapshot／release lineage。它复用不可变的
`app_private.management_report_snapshots`，但使用独立的 `management_original_region_report_release_attempts`、
`tongxingzhe_management_original_region_snapshot_release_writer`、RLS row scope 和 request-claim family。它不复用 channel、
current-city 或 interest provenance，也不把一次 executor 返回值自动当作已发布快照。

首次成功的 `completed` 候选建立 baseline。后续发布必须保持相同 report identity、query／privacy／source scope、期间、可信时区 revision
和精确 `source_tree_version + source_content_fingerprint`，只能推进 cutoff、保持 source change sequence 不回退，并链接当前 lineage head。
same／earlier cutoff、来源树改变或不可用、无共享期间、共享 protected 值／隐私状态变化，以及已发布 lineage 与候选的固定上下文漂移都失败关闭，不生成 snapshot。
executor 内部定义不一致会抛出实现错误，不会伪装成业务 blocked attempt。
授权仍有效时，同 request 精确重试不能新增 attempt 或 snapshot；身份漂移、跨 project 和跨 report family request claim 复用必须失败关闭。

blocked attempt 只保存固定 reason 和最小 value-free lineage metadata，不保存 candidate report、cells、隐藏前值、source、contact、contributor、区域名称、坐标或 PII。
snapshot、attempt 和 request claim 追加不可变；`PUBLIC`、runtime、普通 reader、其他 report-family writer 和区域维护角色不能直接读取或写入原始区域范围。

从仓库根目录运行完整套件：

```bash
./tool/run_postgres_tests_in_docker.sh
```

runner 会自动发现 0068 migration、structural check、fixture 和并发脚本。restore 阶段先运行 `tool/postgres_prepare_restore_roles.sh`，再恢复 dump，
随后重跑 migration、check 和 fixture；不会重跑会提交 synthetic 行的并发脚本。专用测试库的调试顺序是：

```bash
export DATABASE_URL='postgresql://postgres:postgres@127.0.0.1:5432/tongxingzhe_test'
./tool/postgres_migrate.sh
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/checks/verify_management_original_region_report_snapshot_lineage.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/fixtures/0068_management_original_region_report_snapshot_lineage.sql
./tool/verify_management_original_region_report_snapshot_lineage_concurrency.sh
```

fixture 使用 `6bg*`，并发脚本使用独立的 `6bgc*` committed namespace；断言按 workspace、project 和 lineage 过滤。完整通过只证明 synthetic PostgreSQL
中的 snapshot／release、授权、claim、幂等、并发、不可变性、value-free blocked attempt、checksum、restore role 和 ACL 合同。
它不证明 authorized read、runtime、HTTP、Flutter、导出、删除、生产备份或六平台真人运行时。

### 6BH：授权读取单份原始区域管理报告快照

`0069_authorized_management_original_region_report_snapshot_read.sql` 在 6BG lineage 之上增加 private DB-only 读取合同。读取函数只接受
可信内部用户、显式 project 和 snapshot UUID，并在同一事务重新解析 `view_anonymous_analytics`。调用方不能提交报告 JSON、cells、
source tree tuple、时区、cutoff、capability、筛选或 SQL。

可信读取必须同时满足：0068 request claim 属于 original-region family；release attempt 是 `approved`／`approved_baseline` 且 reason 为空；
attempt 与 snapshot 的 project、report／version、query fingerprint、lineage、时区 revision、cutoff、previous／compared pointer、source
watermark 和 `source_tree_version + source_content_fingerprint` 全部对齐。函数在返回前再次运行 6BD validator，不重算或改写城市网格。

`completed` 返回既有 protected report。unknown／cross-project 返回 `not_found`；同项目 channel、current-city、interest、legacy、blocked、
缺失或漂移 provenance 返回 `untrusted_provenance`。后两种结果都不返回正文。每次已授权尝试追加原始区域专用、不可变、value-free audit；
audit 不保存 `protected_report`、cells、隐藏前值、来源记录、contact、contributor、区域名称、坐标或 PII。撤权、过期、release-only、无成员和
inactive project 请求失败关闭且不写 audit。`untrusted_provenance` 审计还会把未经验证的 source tree tuple 和 watermark 固定为 `NULL`。

private function 与 audit 归共享 snapshot 的可信 owner。`PUBLIC`、runtime、普通 app role、0066 original report reader、0068 release writer 和
其他 report-family 角色不能执行读取或直接访问审计。6BH 不增加 runtime bridge、HTTP、目录、Flutter、Drift、导出、缓存、离线、同步、删除、
retention、warehouse 或生产身份。

完整验证：

```bash
./tool/run_postgres_tests_in_docker.sh
```

runner 自动发现 0069 migration、structural check、rollback fixture 和 read／revoke 并发脚本，并执行 checksum 与 dump／restore。恢复库只重跑
migration、check 和 fixture，不重跑会提交 synthetic 行的并发脚本。调试已有专用测试库时按顺序运行：

```bash
export DATABASE_URL='postgresql://postgres:postgres@127.0.0.1:5432/tongxingzhe_test'
./tool/postgres_migrate.sh
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/checks/verify_authorized_management_original_region_report_snapshot_read.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/fixtures/0069_authorized_management_original_region_report_snapshot_read.sql
./tool/verify_authorized_management_original_region_report_snapshot_read_concurrency.sh
```

fixture 使用 `6bh*`；并发脚本的文本键使用 `6bhc*`，UUID 使用独立且符合十六进制格式的 `6fc*` committed namespace。完整通过只证明 synthetic PostgreSQL 的授权、provenance、validator、
value-free audit、撤权锁、checksum、restore 和 ACL 合同，不证明 runtime、HTTP、Flutter、目录、导出、生产身份或真人平台运行时。

### 6BI：验证原始区域快照 runtime bridge

6BI 在 6BH 的 0069 private read 之上增加 0070 `app_data` bridge。bridge 接收 Backend 已验证的 exact external `issuer + subject`、显式 project UUID
和 snapshot UUID。它只映射现有且 active 的 identity，再调用 0069 private function。它不 trim、bootstrap、读取 `SessionContext`，也不接收内部用户 ID、
capability、时区、截止点、source tuple、筛选或 SQL。

0070 使用 `SECURITY DEFINER` 和固定 `search_path = pg_catalog`。runtime 只拥有 bridge `EXECUTE`，没有 `app_private` schema usage，也不能读取
用户、identity、snapshot、release attempt、request claim 或 audit 表。bridge owner 与 0069 private reader owner 相同。`PUBLIC`、普通 app role、
0066 original-region report reader、0068 release writer 和其他 report-family 角色均不能调用 bridge 或 private reader。

Backend adapter 只执行一次固定参数化 SQL。它的 strict parser 只接受 0069 的固定 envelope：`completed` 必须包含固定的 17 个 original-region report
keys、同项目和 snapshot 绑定、selected source tree tuple、两个完整期间、连续 `cell_order`、安全整数和 `suppressed = null`。它拒绝额外字段、其他
report family、城市名称、坐标、来源记录、贡献者、contact 和 PII。`not_found` 与 `untrusted_provenance` 不返回 protected report。adapter 只将
SQLSTATE `42501` 映射为 typed `forbidden`，其他 SQLSTATE 保持为内部错误。

6BI 不新增 private read 的并发脚本。0069 已覆盖 read／revoke 锁线性化，0070 只验证 bridge 的 exact identity、最小 ACL、一次 SQL、strict parser
和对 0069 结果的无损对账。它不增加 HTTP、Bearer／JWT、目录、latest、导出、Flutter、Drift、缓存、离线、同步、删除、retention 或生产身份。

从仓库根目录运行完整套件：

```bash
./tool/run_postgres_tests_in_docker.sh
```

runner 自动发现 0070 migration、structural check 和 rollback fixture，并显式运行原始区域 runtime integration。它继续运行 0069 read／revoke 并发、
checksum 和 dump／restore。恢复库只重跑 migration、check 和 fixture，不重跑会提交 synthetic 行的并发脚本。

如果只调试专用测试库，先确认 `DATABASE_URL` 不是 production，再按以下顺序运行：

```bash
export DATABASE_URL='postgresql://postgres:postgres@127.0.0.1:5432/tongxingzhe_test'
./tool/postgres_migrate.sh
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/checks/verify_runtime_authorized_management_original_region_report_snapshot_read.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/fixtures/0070_runtime_authorized_management_original_region_report_snapshot_read.sql
```

再运行 Backend 合同测试：

```bash
cd backend/server
npm ci --ignore-scripts
npm run check
npm test
```

这些命令只证明 synthetic PostgreSQL、Backend adapter 和 ACL 合同。它们不证明 HTTP、Flutter、导出、生产 identity provider、真实账号或六平台真人运行时。

### 6BK：验证原始区域快照 metadata-only 目录

6BK 为 6BG original-region snapshot 增加独立 private directory、runtime bridge 和 value-free audit。目录重新验证 active identity、项目授权和
`view_anonymous_analytics`，只接受 original-region release family 中 provenance 完整的 approved 快照。它不复用 generic、channel、current-city 或
interest directory。结果最多 20 项，按 cutoff、release time 和 snapshot ID 固定降序；第一项不表示 current 或 latest。

目录项只保存 snapshot ID、固定 report ID／version、报告时区、cutoff 和 release time。audit 只保存授权 lineage、project、访问时间和返回数量，
不保存 snapshot ID、报告 metadata、source tuple、protected report、cells、来源、贡献者、区域名称、坐标或 PII。runtime 只能执行 0071 bridge，
不能使用 `app_private` 或读取 private 表。

从仓库根目录运行完整套件：

```bash
./tool/run_postgres_tests_in_docker.sh
```

runner 自动发现 0071 migration、check 和 rollback fixture，并运行 original-region directory integration、独立 concurrency、checksum 和 dump／restore。
恢复库重跑 migration、check 和 fixture，不重跑会提交 synthetic 行的并发脚本。fixture 与并发脚本使用不同命名空间，避免已提交行与 rollback 数据冲突。

只调试专用测试库时，先确认 `DATABASE_URL` 不是 production，再按顺序运行：

```bash
export DATABASE_URL='postgresql://postgres:postgres@127.0.0.1:5432/tongxingzhe_test'
./tool/postgres_migrate.sh
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/checks/verify_authorized_management_original_region_report_snapshot_directory.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/fixtures/0071_authorized_management_original_region_report_snapshot_directory.sql
./tool/verify_authorized_management_original_region_report_snapshot_directory_concurrency.sh
```

这些 synthetic 测试证明 provenance 过滤、撤权锁、20 项上限、稳定排序、value-free audit、strict parser 和最小 ACL。它们不证明 Flutter、导出、缓存、
离线、production identity provider、真实账号或六平台真人运行时。

### 6BN：验证原始区域快照 replacement lineage

0072 只在 private PostgreSQL 登记两份已通过 6BG 的 original-region approved snapshot 之间的直接 replacement。它不生成或改写 snapshot。
两份快照必须保持同一 project、报告定义、隐私与来源范围、报告时区 revision、期间、release lineage 和 source-tree tuple；新快照的 cutoff 与
发布时间必须更晚，source watermark 不得回退。

replacement 在管理报告共享的 value-free request UUID ledger 中使用独立 family claim，并与 release 共用 request lock。同一 UUID 无论先用于 release
还是 replacement，另一个合同都会失败关闭。lifecycle owner 只能通过专用 provenance bridge 核对 6BG attempt，不能直接读取 attempt ledger。
生命周期结果只含 snapshot ID、`active`／`superseded` 和直接 replacement ID。

从仓库根目录运行完整测试：

```bash
./tool/run_postgres_tests_in_docker.sh
```

runner 自动发现 0072 migration、structural check、rollback fixture 和并发脚本，并继续验证 checksum 与 dump／restore。若只调试专用测试库，先确认
`DATABASE_URL` 不是 production，再依次运行：

```bash
./tool/postgres_migrate.sh
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/checks/verify_management_original_region_report_snapshot_replacements.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/fixtures/0072_management_original_region_report_snapshot_replacements.sql
./tool/verify_management_original_region_report_snapshot_replacements_concurrency.sh
```

这些测试只证明 synthetic DB-only replacement、授权锁、claim、provenance、不可变性和 ACL。它们不证明 snapshot 生成、runtime、HTTP、Flutter、目录、
导出、删除、retention、production identity 或六平台真人运行时。

### 6CB：验证 current-city 快照 replacement lineage

0080 只在 private PostgreSQL 登记两份已通过 0057 的 current-city approved snapshot 之间的直接 replacement。它不生成或改写 snapshot。两份快照必须保持同一 project、报告定义、隐私与来源范围、报告时区 revision、期间、release lineage 和完整 target context；新快照的 cutoff 与发布时间必须更晚，source watermark 不得回退。

replacement 在管理报告共享的 value-free request UUID ledger 中使用独立 current-city family claim，并与 release 共用 request lock。既有 lifecycle writer 只能通过专用 provenance seam 核对 0057 attempt，不能直接读取 attempt ledger。生命周期结果只含 snapshot ID、`active`／`superseded` 和直接 replacement ID。

从仓库根目录运行完整测试：

```bash
./tool/run_postgres_tests_in_docker.sh
```

runner 自动发现 0080 migration、structural check、rollback fixture 和并发脚本，并继续验证 checksum 与 dump／restore。只调试专用测试库时，先确认 `DATABASE_URL` 不是 production，再运行：

```bash
./tool/postgres_migrate.sh
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/checks/verify_management_current_city_report_snapshot_replacements.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/fixtures/0080_management_current_city_report_snapshot_replacements.sql
./tool/verify_management_current_city_report_snapshot_replacements_concurrency.sh
```

这些测试只证明 synthetic DB-only current-city replacement、授权锁、claim、provenance、不可变性和 ACL。它们不证明 snapshot 生成、跨版本更正、runtime、HTTP、Flutter、目录、导出、删除、retention、production identity 或六平台真人运行时。

### 6CD：验证 interest 快照 replacement lineage

0082 只在 private PostgreSQL 登记两份已通过 0062 的 interest approved snapshot 之间的直接 replacement。它不生成或改写 snapshot。两份快照必须保持同一 project、报告定义、隐私与来源范围、报告时区 revision、期间和 release lineage；新快照的 cutoff 与发布时间必须更晚，source watermark 不得回退。

replacement 在共享的 value-free request UUID ledger 中使用独立 interest family claim，并与 release 共用 request lock。关闭的 lifecycle writer 只能通过 interest 专用 provenance seam 核对 0062 attempt。生命周期只返回 snapshot ID、`active`／`superseded` 和直接 replacement ID。

从仓库根目录运行完整测试：

```bash
./tool/run_postgres_tests_in_docker.sh
```

runner 自动发现 0082 migration、structural check、rollback fixture 和并发脚本，并继续验证 checksum 与 dump／restore。只调试专用测试库时，先确认 `DATABASE_URL` 不是 production，再运行：

```bash
./tool/postgres_migrate.sh
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/checks/verify_management_interest_report_snapshot_replacements.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/fixtures/0082_management_interest_report_snapshot_replacements.sql
./tool/verify_management_interest_report_snapshot_replacements_concurrency.sh
```

这些测试只证明 synthetic DB-only interest replacement、授权锁、claim、provenance、不可变性和 ACL。它们不证明 snapshot 生成、runtime、HTTP、Flutter、目录、导出、删除、retention、production identity 或真人平台运行时。

### 6CC：验证项目范围的去身份化地点异常读取

0081 增加 private、DB-only 的异常目录与详情合同。候选只包含 active contact 当前 accepted revision 的
`pending_resolution + pending_coordinates` 与 `unknown + legacy_incomplete` provenance；revision kind 必须是 `submitted` 或 `corrected`。
resolved、not-applicable、draft、attempt、voided、旧 revision 和跨项目记录都被排除。

调用者必须具有独立 `view_deidentified_anomalies` capability。目录最多返回 20 个 opaque ID 和最小 metadata，不返回坐标；详情只对显式 ID 返回
pending 异常的 latitude、longitude 与可空 accuracy，legacy 异常的 coordinates 为 `null`。unknown、cross-project 和 stale ID 都返回同一
`not_found`。`tongxingzhe_management_deidentified_anomaly_reader` 是关闭的 NOLOGIN／NOINHERIT／NOBYPASSRLS role，只获得必要列和 private
resolver 的最小权限。mapping 和 access audit 追加不可变；audit 不保存 anomaly ID、坐标、发生时间、provenance、contact、revision、source 或 PII。

从仓库根目录运行完整套件：

```bash
./tool/run_postgres_tests_in_docker.sh
```

runner 自动发现 0081 migration、structural check、rollback fixture 和 authorization concurrency script，并继续执行 migration checksum 与独立
dump／restore。若只调试专用测试库，先确认 `DATABASE_URL` 绝不是 production，再运行：

```bash
./tool/postgres_migrate.sh
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/checks/verify_authorized_management_deidentified_anomaly_read.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/fixtures/0081_authorized_management_deidentified_location_anomaly_read.sql
./tool/verify_authorized_management_deidentified_anomaly_read_concurrency.sh
```

check、fixture 和 concurrency 证明的内容不同，不能互相替代。并发脚本会提交 synthetic 行，只能在新建测试库运行。Docker 通过只证明
synthetic PostgreSQL 中的资格、授权锁、最小输出、不可变审计、ACL、checksum 和 restore；不证明 correction、runtime、Backend、HTTP、Flutter、
地图、搜索、分页、导出、组织清除、production identity、真实 PII 清除或六平台真人运行时。

### 如何验证 6AS PostgreSQL 合同

第一次使用 Docker 时，先启动 Docker Desktop。Docker 是一次性测试环境：runner 创建隔离的 PostgreSQL 容器，运行
migration、结构 check、synthetic fixture 和并发脚本，然后删除容器。它不连接 production，也不会修改 production 数据。
从仓库根目录运行：

```bash
./tool/run_postgres_tests_in_docker.sh
```

完整 runner 会按仓库约定执行 0060 migration、check、fixture、并发脚本、migration checksum 和 dump／restore。恢复库会
再次检查函数存在性、`SECURITY DEFINER`、固定 search path、owner 对齐、最小 ACL、审计触发器、current-city provenance
过滤、20 项上限和稳定排序。

如果只调试已经运行的专用测试库，先确认 `DATABASE_URL` 不是 production，再按顺序运行：

```bash
export DATABASE_URL='postgresql://postgres:postgres@127.0.0.1:5432/tongxingzhe_test'
./tool/postgres_migrate.sh
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/checks/verify_authorized_management_current_city_report_snapshot_directory.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/fixtures/0060_authorized_management_current_city_report_snapshot_directory.sql
./tool/verify_authorized_management_current_city_report_snapshot_directory_concurrency.sh
```

fixture 覆盖 approved／approved_baseline、legacy channel、blocked／unavailable、claim 与 tuple 漂移、未知／停用 exact
identity、跨项目、撤权、空目录、20 项上限、稳定排序、value-free audit 和 UPDATE／DELETE 拒绝。并发脚本分别验证目录
读取先取得授权锁和撤权先取得授权锁。通过这些检查只证明 synthetic PostgreSQL 合同成立，不证明 Backend HTTP、Flutter、
生产 identity provider 或六平台运行时证据。

只在已有专用测试库调试 6AO 时，先确认 `DATABASE_URL` 不是 production，再按顺序运行：

```bash
export DATABASE_URL='postgresql://postgres:postgres@127.0.0.1:5432/tongxingzhe_test'
./tool/postgres_migrate.sh
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/checks/verify_management_current_city_report_snapshot_lineage.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/fixtures/0057_management_current_city_report_snapshot_lineage.sql
./tool/verify_management_current_city_report_snapshot_lineage_concurrency.sh
```

check、fixture 和并发脚本分别验证 6AN 文档字段、发布能力与可信时区、target tuple 漂移、基线／滚动发布、前一
snapshot 链接、精确幂等、same／earlier cutoff、无共享期间、value-free blocked attempt、不可改删、区域 provenance
独立性和角色读写边界。它们不能证明 HTTP、Flutter、UI、读取、导出、retention、warehouse 或生产调度。

0054 的手工验证需要专用测试库：

```bash
export DATABASE_URL='postgresql://postgres:postgres@127.0.0.1:5432/tongxingzhe_test'
./tool/postgres_migrate.sh
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/checks/verify_management_region_attribution.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/fixtures/0054_management_region_attribution.sql
```

完整 Docker 套件会从空库运行同一 migration、check 和 fixture，在 checksum 复跑及 dump／restore 后再次
执行。synthetic fixture 必须覆盖 original 精确来源、current 坐标唯一／零命中／同链嵌套／跨链歧义／同深度
歧义、region-only 同版本／显式 mapping／缺失 mapping、错误指纹、草稿或未知树，以及 pending、N/A 和
不完整来源的 `not_reportable`。这些检查不证明真实区域对应关系或生产报告已经验收。

Backend Store 对 0039 触发器的地点错误只做固定 `SQLSTATE 23514` 与错误文字的窄映射：已知 source 形状失败返回 `rejected / invalid_location_source`，已知 location 形状失败返回 `rejected / invalid_location`，HTTP 层将其作为 `422` permanent failure。未知 `23514` 或其他数据库错误仍向上抛出，HTTP 层返回 `503 sync_unavailable`。不得用一条宽泛的 SQLSTATE 映射掩盖新的约束或权限问题。

`contact_location_source_v1.csv` 是 Flutter、Backend 和 PostgreSQL 共用的四种当前状态及错误输入。`0039_contact_location_provenance.sql` fixture 另行验证历史回填、revision／冲突／作废、地点与来源原子合并、warehouse 清理和 runtime 权限。Node 24 integration 通过真实 Backend Store 与 PostgreSQL bridge 重放共享状态，并断言 permanent／retryable 分类、匿名管理报告以及错误和分析边界。SQL fixture 是数据库证据；它不能单独证明 Backend HTTP 或 Flutter 已经完成四层对账。

普通 fixture 在一个会话中验证定义、权限、revision、幂等和不可变约束。`0038_frozen_canonical_region_tree_releases.sql` 还验证草稿编辑、成功发布、发布后节点和边界写入失败、内容指纹复算、current 切换和旧版本保留。全部 `verify_*_concurrency.sh` 脚本必须另行运行，因为它们会启动独立 `psql` 会话，验证问卷发布、指标兼容、个人与机构活动关系、对象匿名化、管理授权写入与撤权、管理上下文选择、快照目录访问、项目报告时区、管理报告 lineage 和区域树 current 发布的并发不变量。Docker wrapper 会按文件名排序并自动复制、执行这些脚本。检查脚本只使用 synthetic 数据，并要求显式 `DATABASE_URL`。

普通 fixture 会回滚，独立并发脚本会提交 synthetic 数据；并发数据还会进入 dump，并在恢复库中与全部 fixture 再次相遇。因此两类测试必须使用不同的 synthetic UUID 前缀，且 fixture 的数量断言应限定到自己的用户或项目。若测试只在 dump/restore 后失败，先检查 UUID 命名空间与全表计数，不要把持久并发行当成产品缺陷。
