# ADR-0203：混合确认共用最终清单并只终结一次

- 状态：已接受
- 日期：2026-10-21
- Slice：7FE／private DB-only
- Issue：[#611](https://github.com/XavierOwen/tongxingzhe-app/issues/611)
- Requirement：`PII-022`、`TEST-175`、`MANUAL-164`
- 关联：[ADR-0193](./0193-historical-pending-facts-and-current-source-candidates.md)、[ADR-0199](./0199-existing-project-relationship-resolution-keeps-history-and-explicit-current.md)、[ADR-0201](./0201-missing-project-relationships-require-explicit-entry.md)、[ADR-0202](./0202-mixed-resolution-preflight-keeps-both-plans-in-one-snapshot.md)

## 决定

0142 为同一代次的接触和项目关系 pending 增加私有混合确认。两类来源映射都须完整且非空，每个槽都须明确选择当前候选。它在任何事实写入前重新验证 0141 组合计划，再依次应用接触和项目关系事实，采用一个共同最终 manifest，最后调用一次原 end。证明和 end 可以重新计算同一清单核对，不能把一类的中间清单当成最终回执。

两个旧确认器都会终结代次，锁序也不同，不能直接串联。将各自的事实应用段精确抽为两个私有 helper，立即供原单类入口与混合入口复用。原单类入口的其余校验、重放和终结顺序保留，函数 OID、owner、ACL 与 config 不变；不复制普通 writer。

## 已有关系与完整预锁

首版要求所有受影响项目关系都已存在。集合包括项目 pending 的原项目／拟议来源槽，以及每项接触历史 snapshot 和进入前 current snapshot 的全部 pair、nonpair links。缺任一关系就整批拒绝，不初始化项目进入，也不补造接触、同意或续期。接触 writer 对已有关系只执行冲突时不插入，因此先应用接触不会改变项目关系的原 current base。

先锁操作者／请求及本人活动账号行，再依 C 顺序预锁全部子命令与接触。账号行采用 FOR NO KEY UPDATE。随后取得全局代次 fence，按创建时间／UUID 锁全部相关对象及其活动分配，最后按项目／来源 UUID 锁完整关系集。所有等待后重新核对完整集合、两份原生计划、授权、两端 due 与明确选择。新 pending 或 current 漂移时拒绝重取，不在 fence 后补取反向 contact／child 锁。只接受 READ COMMITTED，其他模式在请求读取、授权和锁前拒绝。

## 共同证明与原子终结

历史应用和当前选择沿用原两类合同。同值 pending 保留为独立事件；接触的原事实、answers、地点 provenance 和 nonpair links 保留，项目原历史、原时间与 parent binding 不改。原普通 writer 的资格与校验继续适用，不能丢弃失效关联来通过确认。

两类应用完成后才插入各自的原 request，保存相同 context、known／post 指纹及确认时间，分别保留原生 resolution 指纹。新增共同 receipt 仅保存 actor、request、generation 与原混合 resolution 指纹，使用 generation FK 和两条 deferred family-request FK。插入时核对实际数量和全部预期 metadata，ledger 不复制或散列业务值。

项目事实证明从原 proof 抽出共享核心，旧 proof 仍先拒绝未处理的接触 pending，再委托它。新的混合证明核对共同回执、两类请求的相同上下文／最终指纹，并调用原接触证明与项目事实核心。

仅在 project end guard 原有的精确请求、上下文、代次、最终指纹、operation、outcome 和时间谓词内增加混合证明分支。原 contact proof／end guard 和两类 payload guard 不变，不用 session flag 或跳过 guard。

共同证明通过后调用一次原 end，再凭精确 end receipt 消费两类 payload，末尾复核数量与完整证明。任一错误、抑制、缺证据或数量不符，全部应用、当前值、回执、end 和消费共同回滚。旧单类 live 确认仍不能完成 mixed；代次结束后的旧单类精确回执重放不等于执行混合写入。

## 重放与边界

新混合入口重放时从不可变 metadata 还原两类完整映射和选择，核对原 context 与四项指纹，再走原 end 的当前授权。不读取已结束代次的 active plan，也不要求后来普通编辑会失效的 live proof 仍为真；不重复历史、初始化或恢复已匿名化文本。

所有新对象仅归原可信 owner，PUBLIC／runtime 封闭。0140 的单类显式进入合同、普通 writer、来源历史与匿名化规则不改。不接生产、Backend／HTTP／UI 或 scheduler；缺关系的混合确认、其他未知事实类型和完整拆分另行交付。synthetic fresh、真实版本升级、并发、checksum 与独立恢复不证明生产身份、真实 PII、设备或部署验收。
