# 冻结已发布的规范区域树和边界版本

状态：**已接受（2026-08-12）**。

关联：Slice 6R；ADR-0011、ADR-0012、ADR-0110；`REGION-005` 至 `REGION-009`、`ARCH-004`、`ARCH-006`、`ARCH-010`、`PRIVACY-010`、`TEST-003`、`TEST-005`。

## 决定

规范区域树采用 `draft` 和 `published` 两个生命周期。现有 release 在迁移时解释为 `published`，不改写节点、边界、接触的 `region_id` 或解析版本。旧 schema 没有保存 current 的实际选择时间；迁移只追加一条 `migration_baseline` 观察记录，实际选择时间保持空值，不能把旧发布时间解释成选择时间。新 `tree_version` 先作为草稿编辑，只有私有发布函数
`app_private.publish_canonical_region_tree_v1(text, boolean)` 可以把它发布。

发布函数在一个事务中验证并冻结整个版本：

- 每个节点只有一个父级，父链无环；
- 每个边界节点都有城市父链；
- 至少有一条属于该版本、包含至少三个点且面积大于零的可解析边界；
- 节点、父级、规范名称、`kind`、`attributes` 和边界按 `C` 排序、固定浮点输出与规范 JSON 编码计算内容指纹；
- 发布时间、生命周期和内容指纹与版本一同写入；
- 若请求成为 `current`，函数在同一事务中切换当前投影，并追加一条选择记录。

指纹覆盖发布版本的可读内容，而不是数据库行顺序。相同内容重算得到相同指纹，任一节点或边界内容变化都会得到不同指纹。发布完成后，节点和边界不能再 `INSERT`、`UPDATE` 或 `DELETE`；release 的版本、发布时间和指纹也不能改写。

`current` 是解析器使用的单值投影，不是历史事实。切换 current 可以把旧版本从投影中移除，但不能修改旧版本的节点、边界或发布时间。迁移后的每次真实切换都向追加式选择历史写入顺序、前一个版本、选定版本、选择时间、记录时间、来源和内容指纹，因此可以复核“何时从哪个版本切换到哪一个版本”。唯一 current 约束以及草稿编辑与发布共用的事务锁，保证内容验证、指纹计算和冻结之间没有编辑穿过，也保证并发发布不会留下两个 current 或半个发布版本。重复发布同一版本返回稳定的 `55000` 冲突，不重新生成另一份历史。

区域解析器继续只读取已经提交的 current、published 版本。`tongxingzhe_runtime` 只保留解析函数的 `EXECUTE` 权限，不能直接读取或写入区域表、选择历史，也不能执行私有发布函数。发布函数由无登录、无成员的 `tongxingzhe_region_publisher` 专用角色执行；trigger 只信任这个不可由普通维护会话设置的数据库身份，不把 session 配置当权限。区域维护流程使用单独的部署或维护身份，并在发布前运行 check、fixture 和并发验证。

## 后果

区域树内容现在有明确的草稿边界、发布时点和可复核指纹。后续的 `original`／`current` 地点视图可以把已发布 tree version 当作稳定基准，历史重放也不会读到被静默改写的边界。current 选择历史记录的是投影变化，不把旧版本复制成另一份内容。

这项决定没有补齐接触地点的追加式 provenance。当前已解析地点仍可能只有 `region_id + tree_version`，而 `contact_region_assignments` 仍是当前投影。6S 必须另行保存地点来源、坐标或可验证的跨版本映射。生产区域报告仍需自己的完整网格、互补隐藏、授权、快照 lineage 和重识别 fixture；本 ADR 不授权生产报告或任意区域查询。

## 验证入口

从仓库根目录运行完整 PostgreSQL Docker 套件：

```bash
./tool/run_postgres_tests_in_docker.sh
```

该脚本会从空库运行 migration 两次以检查历史 checksum，然后按文件名运行 `verify_frozen_canonical_region_tree_releases.sql`、`0038_frozen_canonical_region_tree_releases.sql` 和全部并发脚本。它还会执行 `verify_canonical_region_tree_release_concurrency.sh`，导出 `app_data`、`app_private` 与 migration 历史，在没有源 cluster roles 的第二个 PostgreSQL 容器中先运行 `postgres_prepare_restore_roles.sh`，再恢复 archive 并重跑检查与 fixture。脚本结束后会删除临时容器。失败时可设置 `KEEP_POSTGRES_TEST_CONTAINER=1` 保留容器，并按第 9 章说明查看日志。
