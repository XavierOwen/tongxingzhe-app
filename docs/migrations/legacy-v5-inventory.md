# Legacy Drift v5 盘点与保全记录

状态：v5 基线和 v6 中间版本已保存；Slice 1B 已加入当前 v7 升级测试

记录日期：2026-07-31

适用需求：`MIGRATION-001` 到 `MIGRATION-005`

## 1. 结论与证据边界

当前没有需要迁移或保全的真实用户数据。

这个结论由两类证据共同支持：

1. 产品所有者已经确认：App 尚未给任何真实用户使用，任何设备上都不存在不可丢失的真实 v5 数据；
2. 当前 Git checkout 没有被版本控制的 `.db`、`.sqlite`、`.sqlite3`、`.csv` 或 `.xlsx` 数据文件。仓库的 `.gitignore` 也明确排除这些可能含个人资料的文件。

第二点只能证明“仓库里没有数据文件”，不能证明所有外部设备的状态；因此第一点仍是本次盘点的必要前提。若以后发现未知设备数据库，本页结论立即失效，必须按第 5 节暂停自动迁移。

## 2. 被保存的 schema 证据

Drift v5 的机器可读快照位于：

```text
drift_schemas/drift_schema_v5.json
```

快照包含五张 legacy 表：

| 表 | 旧用途 | 数据敏感性 |
| --- | --- | --- |
| `db_users` | 本地模拟账号、角色与锁定状态 | 含邮箱、电话、MD5；若来自未知设备则按敏感数据处理 |
| `db_conversation_records` | 旧版“交谈记录” | 可能含姓名、位置、备注 |
| `db_record_contacts` | 旧版联系方式 | PII |
| `db_app_settings` | 语言、主题、当前用户等设置 | 可能间接标识用户 |
| `db_security_events` | 本地模拟认证事件 | 可能含账号标识与失败细节 |

记录时快照的 SHA-256 是：

```text
bf98732ab6801a3667f127289a333a24a31688f79cae36ea53cf4cc565767901
```

v5 是不可改写的历史基线。当前 `LocalDatabase` 已是 v7，不能再用当前 Dart 定义重新导出 v5 或 v6。以下命令生成全部已保存版本的测试辅助代码：

```bash
dart run drift_dev schema generate \
  drift_schemas \
  test/generated_migrations
```

`test/data/local_database_migration_test.dart` 会用 Drift 的 `SchemaVerifier` 从这份 v5 快照建立旧库，再运行当前 migration。这样保存的是结构与升级行为，不把真实资料提交进 Git。

## 3. 数据分类规则

发现 legacy 数据时，先分类，不能直接“导入再说”。

| 分类 | 判定证据 | 允许动作 |
| --- | --- | --- |
| 空库 | 五张表均为 0 行 | 可从现代 schema 重新初始化 |
| 明确 Demo seed | 账号仅为 `admin1`–`admin3`、`user1`–`user2`，记录符合仓库内 deterministic synthetic generator | 可删除后重新生成；不得当成业务事实 |
| 未知／真实数据 | 不完全符合上述两类，或来源、使用者、同意状态不清楚 | 立即停止自动初始化和导入，单独评估 |

旧字段不能推导现代领域事实。例如：

- `role_level` 不能直接变成现代 membership capability；
- `team_name` 和 `city_names_json` 不能证明现代组织／项目成员关系；
- 姓名、联系方式和备注不能自动变成推广对象；
- `relationship_level`、`interest_level` 和旧区域默认值不能静默套用新口径。

## 4. 为什么仓库不保存 SQLite 二进制备份

现在没有真实数据库可备份。额外提交一个含 Demo 账号、MD5 和旧 PII 字段的 SQLite 文件只会制造误用风险，而不会增加 schema 证据。

本次保留：

- 可审阅的 v5 JSON schema；
- 自动生成的 Drift migration 测试辅助代码；
- 明确标记 synthetic 的测试数据；
- 本盘点记录和可重复命令。

若将来需要保存真实旧版本 fixture，应先做最小化、去标识化和人工复核，并放入受控测试资产；不得直接复制用户数据库。

### 4.1 当前 v7 的用途

当前 schema 快照位于 `drift_schemas/drift_schema_v7.json`。v6 保留五张 legacy 表，并新增现代接触、revision、类型化答案和持久 Outbox 表。v7 再新增私有草稿及草稿答案表。两个版本都不从 legacy 宽表猜测现代接触事实。

当前 v7 可以用下列命令重新导出：

```bash
dart run drift_dev schema dump \
  lib/data/local_database.dart \
  drift_schemas/drift_schema_v7.json
```

迁移测试保存三条证据。当前 v7 可从快照独立重建。v6 的 synthetic 接触升级后仍存在，草稿表为空。v5 的 synthetic 设置升级后仍存在，全部现代表为空。测试也核对索引与 v7 快照。

## 5. 意外发现未知 v5 数据时

1. 不启动 Demo seed，不执行现代 schema 初始化，不删除原文件；
2. 对原文件做只读副本并记录来源设备、App 版本、文件哈希和取得时间；
3. 在隔离环境只读统计表名、列名和行数，不查看不必要的 PII；
4. 新建 GitHub migration 评估 Issue，记录合法基础、保留范围和字段映射；
5. 只有经过人工确认的映射才可进入一次性 migration；无法证明语义的字段保留为隔离原始证据或放弃导入，不猜测。

这条停止规则是数据安全边界，不是普通 warning。
