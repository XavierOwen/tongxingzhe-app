# ADR-0210：个人合并接触 metadata 使用精确私有键

- 状态：已接受
- 日期：2026-11-16
- 范围：私有数据库修正；Issue [#665](https://github.com/XavierOwen/tongxingzhe-app/issues/665)
- Requirement：`PII-009`、`PII-013`、`TEST-194`、`MANUAL-183`
- 关联：[ADR-0193](./0193-historical-pending-facts-and-current-source-candidates.md)、[ADR-0203](./0203-mixed-resolution-confirmation-uses-one-final-manifest.md)、[ADR-0204](./0204-mixed-project-entry-prelocks-before-one-confirmation.md)、[ADR-0209](./0209-personal-merge-child-command-keys-are-bounded.md)

0160 已缩短长 contact ID 的内部子命令键。
真实 0160 基线中，2670 字节低压缩 TEXT contact ID 使用独立短 command ID，普通 submit、revise 和 0127 stage 均成功，0128 确认仍在 private application 的复合唯一索引报 `54000`，索引行 2720 字节超过该测试库的 2704 字节上限。
四张私有接触收据表将 raw ID 与多个 UUID 组成索引键，仍有独立的宽度限制。

0161 新增私有 contact identity map（`app_private.personal_merge_contact_keys_v1`），原 `contact_id TEXT` 是主键，`contact_identity_key bigint` 由数据库 identity 分配且唯一，二者另有精确 pair UNIQUE。
四张 application／history／current／choices 收据表各增加非空 `contact_identity_key`，并以 `(contact_identity_key, contact_id)` 外键引用 map。
application 的 actor／request／contact UNIQUE、history 的 original-once UNIQUE，以及 current 和 choices 的主键只将宽 contact 列换为 bigint。
choices→current 外键也使用 bigint；双方的 map 外键保证它仍对应同一原 ID。
窄的 history `(contact_id, to_revision_number)` UNIQUE 和八个 ordinary raw FK 全部保留。
该映射不使用摘要作为身份，没有 hash 碰撞假设。

四表的 BEFORE INSERT trigger 仅在 `NEW.contact_identity_key IS NULL` 时取得或创建映射并赋值。
显式提供的错误 key 留给 exact pair FK 拒绝，不被覆盖。
map 的 BEFORE UPDATE 复用原不可变 guard，DELETE 允许随 contacts 级联清理；四表到 map 的 FK 保持 NO ACTION，不能级联删除历史收据。
map、identity sequence 和新 helper 不向 PUBLIC 或 runtime 开放。

迁移在独占 DDL 锁下回填新增列，只临时停用并恢复四表各自指定的 immutable guard。
旧字段、旧收据和原 contact ID 保留。
真实升级 fixture 逐字段检查这些值及所有旧函数的完整 catalog。
原 coordinator、proof 和 v3 writer 的函数体不变；普通表的列与约束不变。

MANUAL-183／TEST-194 要求四入口验证长 ID、短对照、同 contact 复用 key、显式错误 key 拒绝、精确重放及晚期 end 故障整批回滚。
真实 0160 升级先保留 pending 和已完成回执，再检查旧字段、完整旧函数 catalog 与零写重放。
strict purge inventory 增加五个 FK 并更新 choices→current 定义，总数为 401；contacts 删除须级联清理 map。
fresh、升级、checksum、既有 fixtures 和独立恢复由正式 runner 分别验证。
此决定只覆盖私有 PostgreSQL，不开放生产、runtime、Backend、HTTP 或 UI 入口，也不扩大普通 writer 接受 contact ID 的范围。
