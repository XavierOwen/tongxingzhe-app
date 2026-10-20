# ADR-0198：项目关系处置预检只列来源与当前候选

- 状态：已接受
- 日期：2026-10-20
- Slice：7EZ／private DB-only
- Issue：[#600](https://github.com/XavierOwen/tongxingzhe-app/issues/600)
- Requirement：`PII-009`、`PII-018`、`TEST-170`、`MANUAL-159`
- 关联：[ADR-0193](./0193-historical-pending-facts-and-current-source-candidates.md)、[ADR-0197](./0197-unknown-project-relationship-facts-stay-pending-until-assigned.md)

## 决定

0136 pending 是独立项目关系事件，不是已经应用的普通 revision。只读处置预检接收使用者拟议的完整来源映射，把每项 pending 指向两个原对象之一，并按原项目与拟议来源列出全部候选。它不保存分配、不选赢家、不写事实，不把单候选自动当作明确决定。

`app_private.plan_personal_merge_project_relationship_resolutions_v1` 接收可信内部 user／workspace／project／generation、expected known fingerprint、expected pending fingerprint 和完整 assignments 数组。每项精确包含两个 string 键 `pending_fact_id`／`source_target_id`；只接受标准分段 UUID，大小写及数组顺序归一，不接受重复项、遗漏、其他代次或两原对象之外的 source。两个 expected fingerprint 都必须与同一调用快照中的当前目录一致。

复用 0136 reader 和 known-source 验证，以 STABLE calling-command snapshot 同时读取资格、pending 与已有关系。拟议映射只覆盖本类 pending；其他已知事实继续留在 known-source plan，不把它们改称未知或重复搬移。

## 候选与指纹

每个受拟议分配影响的 `(source target, original project)` 槽只含项目／来源 ID、按 staged time 和 UUID 排序的 pending ID，以及可空的已有当前关系指针。有当前关系时，只返回真实 current revision 的 number 和 generation binding；关系创建时的 binding 与各次 revision 的 binding 分别形成，可以不同。

合并前创建的关系可以保持 NULL binding，而合并期间的普通修订绑定当前代次。两列均不回填；分别校验非 NULL binding 对应原对象、空间和类型的合法 generation member，允许旧代次。缺少真实 current revision 或 binding 来源矛盾才拒绝。

`candidate_count` 为 pending 数加已有当前关系的零或一，`requires_choice` 只描述是否有多候选冲突；即使它为 false，未来写入仍须明确选择。同值 pending 不合并，多个事件不自动取最新，不读取或比较阶段、生命周期、备注或原因来替用户决定。

结果固定七键：contract、known-source plan、pending fingerprint、canonical assignments、source slots、conflict count 和 resolution fingerprint。

canonical assignments 包含 pending／source／派生 project，按 pending UUID 排序；slots 按 project／source UUID 排序。resolution fingerprint 是前六项 metadata JSON 的 SHA-256，不含业务值或业务哈希。

输入形状／UUID／重复项返回 invalid，known／pending 指纹、完整集或 source 漂移 conflict；已有关系缺少真实 current revision 或 binding 矛盾 unavailable。原 reader 的 forbidden 继续透传。空 pending 和空映射可返回空目录，不能据此说明其他 pending 类型已处理。

## 只读与边界

只新增一个 STABLE SECURITY DEFINER 函数，固定 `search_path=pg_catalog`，owner 与 0136 reader 相同，PUBLIC／runtime 无执行权。没有新表、FK、request、audit、context、fence、行锁或隔离级别写门禁。READ ONLY transaction 必须实际成功，全部旧事实和 metadata 逐值不变；预检不保留后续确认资格。

普通关系 writer 不为同值请求追加 revision，也不创建不存在的关系。此预检不规避这些约束，不制造 conflict、contact 或 project_entry 来消费 pending。历史事件保留、关系创建来源、当前候选确认、payload 消费及 mixed split 的执行合同另行固定。

不增加 runtime、Backend／HTTP／UI、scheduler、生产部署或产品 active merge。synthetic fresh、真实升级、checksum 和独立恢复只证明此私有 metadata 预检，不能称完整拆分或真实 PII 验收完成。
