# PostgreSQL schema 与 migration

这里是共享事务数据库 schema 的唯一权威来源。Supabase Dashboard 可以用于观察，不得手工创建或修改正式业务表。

## 目录

- `migrations/`：只追加、按文件名排序的正式 SQL；已经执行的文件不得改写；
- `runner/`：迁移历史、锁与 checksum 检查；
- `checks/`：环境和权限不变量；
- `fixtures/`：只含 synthetic 数据的可回滚验证资料。

## Docker 中运行完整数据库测试

没有安装 PostgreSQL 或 `psql` 时，先启动 Docker，再从仓库根目录运行：

```bash
./tool/run_postgres_tests_in_docker.sh
```

脚本建立隔离的 PostgreSQL 16 容器，运行 migration、check、fixture、并发和 dump／restore，最后自动删除容器。第一次使用 Docker、需要保留失败容器或理解输出时，阅读[本机、Docker 与 CI 测试指南](../../docs/manual/09-local-docker-and-ci-testing.md)。

## 使用已有 PostgreSQL 测试库

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
./tool/verify_questionnaire_publish_concurrency.sh
./tool/verify_questionnaire_metric_concurrency.sh
./tool/verify_person_institution_relationship_concurrency.sh
./tool/verify_promotion_target_retention_concurrency.sh
./tool/verify_management_report_authorization_concurrency.sh
./tool/verify_management_report_release_concurrency.sh
./tool/verify_project_reporting_time_zone_concurrency.sh
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

`0018_promotion_target_relationship_audit.sql` 把项目关系扩展为当前投影和追加 revision 历史。阶段仍固定为 `0–4`，生命周期独立保存；阶段、生命周期和共享跟进备注的每次修改都保留操作者、时间、原因和 mutation ID。旧 revision 通过 base snapshot 做字段级三方比较：不同字段自动合并，同字段把拟提交内容写入受保护冲突表，等待当前跟进者明确解决。阶段下降要求结构化原因。项目别名只覆盖显示名，双倍刻度只在响应中派生。runtime role 不能直接读取备注、冲突或历史表。

`0019_person_institution_relationships.sql` 保存 workspace 内明确建立的个人与机构关系。六类性质固定；同一对对象可同时有不同性质，但同一种活动关系只允许一条。建立和结束都追加 revision 并使用 mutation ID。列表和写入都要求调用者仍同时获分配两端对象；关系本身不增加分配、成员资格、接触关联或 warehouse 事实。

`0020_promotion_target_retention.sql` 保存一至十二个月的 workspace 保留策略和不含 PII 的续期／匿名化审计。期限基准取对象建立、最近有效接触和最近明确续期中的最新时间。到期目录读取先匿名化；明确撤回立即匿名化。一个 transaction 会清除对象 PII 和历史敏感文本、结束活动分配与关系，同时保留接触和去标识统计。

`0021_personal_action_plans.sql` 保存每位用户、每个项目的一份私人计划和追加式版本。首次设置采用当前自然周；后续目标、IANA 统计时区或周期起始日修改从下一周期生效。进度只计算当前有效、已提交且实际发生在周期内的接触。runtime role 只能用可信当前上下文读取或修改本人计划，不能直接读表，也没有管理员列表函数。

`0022_personal_action_reminders.sql` 独立保存每位用户、每个项目的可选每日当地提醒钟点。版本只追加，提醒可在没有周目标时单独使用。服务端不会保存或开启设备通知权限；每台设备的 opt-in 只留在本机。runtime role 同样只能通过可信当前上下文读写本人提醒。

`0023_management_contact_session_privacy.sql` 建立固定双期间渠道网格的私有隐私政策。函数执行 `k=10`、至少三位推广者、单人不超过一半和总计互补隐藏；隐藏结果不返回精确值。runtime role 没有 `app_private` 使用权或函数执行权；`0031` 只在私有事务中组合授权和发布，尚未开放生产管理端点。

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

`0035_management_report_snapshot_directory.sql` 提供按显式项目列出可信 v2 管理报告快照的只读目录。数据库在同一事务中重新检查完整 `view_anonymous_analytics` 授权链，只返回至多 20 项固定元数据，并按数据截至时间、发布时间和快照 ID 降序排列。每次成功访问都追加一条不可变目录审计；审计保存精确授权证据和返回数量，但不保存快照 ID、报告元数据或格值。runtime 只能执行一个窄 bridge。目录不判断“当前”或“最新有效”，也不提供筛选、分页或任意历史查询。

普通 fixture 在一个会话中验证定义、权限、revision、幂等和不可变约束。全部 `verify_*_concurrency.sh` 脚本必须另行运行，因为它们会启动独立 `psql` 会话，验证问卷发布、指标兼容、个人与机构活动关系、对象匿名化、管理授权写入与撤权、管理上下文选择、快照目录访问、项目报告时区和管理报告 lineage 的并发不变量。Docker wrapper 会按文件名排序并自动复制、执行这些脚本。检查脚本只使用 synthetic 数据，并要求显式 `DATABASE_URL`。

普通 fixture 会回滚，独立并发脚本会提交 synthetic 数据；并发数据还会进入 dump，并在恢复库中与全部 fixture 再次相遇。因此两类测试必须使用不同的 synthetic UUID 前缀，且 fixture 的数量断言应限定到自己的用户或项目。若测试只在 dump/restore 后失败，先检查 UUID 命名空间与全表计数，不要把持久并发行当成产品缺陷。
