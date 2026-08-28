# ADR-0174：跨版本报告快照更正必须引用当前有效的直接定义兼容决定

- 状态：已接受
- 日期：2026-08-28
- Slice：6CF Spec
- Issue：[#267](https://github.com/XavierOwen/tongxingzhe-app/issues/267)
- 关联：ADR-0065、ADR-0150、ADR-0151、ADR-0170、ADR-0172、ADR-0173
- Requirement：`ANALYTICS-013`、`ANALYTICS-067`、`PRIVACY-058`、`TEST-061`、`MANUAL-051`

## 背景

现有 replacement 合同只连接同一 report version 的 approved snapshot，原因限于补录、接触修订和接触作废。分析定义或报告版本变化不能借用这些原因，也不能仅凭目录顺序、版本号或传递关系推断兼容。

问卷指标已有明确、可审计、可撤销的语义兼容决定，但管理报告尚未固定跨版本更正所需的两条授权链、兼容决定内容和撤销后的生命周期投影。直接实现通用关系表会替尚未选择的 report family 猜测 provenance 和 validator。

## 决定

6CF 只固定后续 report-family 实现必须遵守的共同政策。跨版本更正只能连接同一 project、report family 和 stable metric 的两份既有 approved snapshot；两端的 report version、metric version 或 definition fingerprint 至少一项不同，全部相同时继续使用该 family 的同版本合同。6CF 不生成、修改或重新发布 snapshot，也不改变任一版本内部的 replacement 图。

旧、新端必须引用一项当前有效、不可变且方向明确的直接兼容决定。该决定保存 project、report family、stable metric、旧／新 definition ID、report／metric version 和 definition fingerprint。比较结论覆盖单位、分子／分母、维度、排除项、期间边界、报告时区、privacy policy、source scope、旧／新 query fingerprint、validator 和问卷语义。

登记时，决定中的 project、family、metric、方向和两端 definition tuple 必须分别与两份 snapshot 的不可变 trusted provenance 精确相等。两端期间、时区、privacy 和 source scope 也必须相同。
缺失决定、未知 report version／fingerprint、protected shape 或 validator 漂移、已撤销、反向或不匹配的决定均以 value-free reason 失败关闭。每份旧 snapshot 最多一个 direct successor，每份新 snapshot 最多一个 predecessor。
自链接、传递推断、环、分叉或 stale head 同样失败关闭。跨版本关系本身不授权趋势合并，也不把目录首项解释为 current 或 latest。

定义兼容决定由当前具备 `manage_analysis_definitions` 的成员确认或撤销；若组织已启用第二人批准，沿用该流程，平台不新增强制双人审批。登记跨版本更正另由当前具备 `release_management_reports` 的成员执行，登记者不因引用有效决定而自动获得定义管理权。

未来实现的确认、撤销和登记统一按 request claim、project／family／metric definition pair、cross-version lineage（仅登记）和既有 authorization／revoke 的顺序取得锁。cross-version lineage lock 与各 report family 的 release／同版本 replacement lineage lock 分离。不同 request UUID 的普通操作不互相串行，只有同一 UUID 的共享 claim 互斥。

确认／撤销路径随后重核 active identity、组织／项目 membership、active project、grant validity 和定义管理权限。登记路径随后重核同类状态、发布权限、direct compatibility 和两端 trusted provenance。相同 UUID 和 canonical payload 精确幂等，payload drift 失败关闭。登记者或原决定者后来失去 capability 不会自动改写历史；只有显式撤销兼容决定才撤销其当前效力。

跨版本登记只允许原因 `analysis_definition_change`。现有 `late_accepted_data`、`contact_revision` 和 `contact_void` 仍只用于同版本数据更正，不能伪装定义变更。

兼容撤销与登记按锁顺序线性化。撤销先取得锁时，后续登记失败关闭；登记先提交时，关系保留为不可变历史证据，但撤销后不再进入当前跨版本投影。跨版本投影只返回 edge ID、`active`／`compatibility_revoked` 和两端 snapshot ID；各版本内的 `active`／`superseded` 仍是 version-scoped，不表示全局最新。撤销不会删除、回开或重写 snapshot。既有 reader、目录、导出和缓存不自动跟随跨版本 successor。

兼容决定、撤销事件、request claim、cross-version edge、结果和最小 audit 必须追加不可变且 PII-free；撤销另写事件，不修改原决定。允许字段只限 event／request ID、project、family、metric、两端 definition ID／version／fingerprint、固定 reason／decision／status 和数据库时间。还可保存服从账号删除去关联规则的 opaque internal actor reference，以及枚举化 comparison／impact 摘要。

这些记录不得保存 email、姓名、外部身份、自由文本理由或原始问题／定义／选项文字。它们也不得保存报告正文、cell、ratio、answer、contact、source value、隐藏前值、坐标或贡献者身份。客户端不能提交 capability、provenance、兼容结论或报告正文替代可信注册表和数据库核对。

## 后果与边界

组织删除恢复期内禁止新兼容决定、撤销和跨版本登记。恢复期届满后的清除继续遵守 ADR-0151：删除该组织的快照、正文、provenance、兼容决定／撤销历史、replacement edge 和含业务内容审计，只保留既有最小组织删除审计；删除后这些记录不可读取，失败时组织保持不可访问。6CF 不新增 tombstone、独立 retention 或清除入口。

0015 的问卷题目兼容事件只是决策模式先例，不自动成为管理报告定义或 snapshot provenance 的权威。本切片只交付 Spec、ADR 和学习文档。它不选择首个 report family，不增加 migration、SQL、fixture、concurrency、runtime、Backend、HTTP、Flutter、目录、读取、导出或 Apple 平台证据。
后续单一 report-family 实现必须另建 review-sized Issue，并以 migration、structural check、rollback fixture、concurrency 及 reader／directory／export 回归证明 provenance、validator、锁顺序、撤销竞争、最小 ACL、checksum 和 dump／restore。

## 验证

当前验证只检查 Markdown 链接、文档一致性和 diff。它不能证明数据库关系、并发线性化、权限、删除、生产身份、部署环境或真人平台运行时。
