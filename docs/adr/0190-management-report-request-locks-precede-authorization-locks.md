# ADR-0190：管理报告写入先锁 request，再锁授权层级

- 状态：已接受
- 日期：2026-10-07
- Slice：7DI
- Issue：[#514](https://github.com/XavierOwen/tongxingzhe-app/issues/514)
- 关联：ADR-0104、ADR-0162、ADR-0188
- 替代范围：仅替代 [ADR-0104](0104-trusted-report-release-binds-authorization-and-time-zone-revision.md) 与 [ADR-0162](0162-management-follow-up-consent-ratio-snapshots-use-independent-release-lineage.md) 的授权锁先于 request 锁的次序；两者的授权、隐私、固定回执和不可变 provenance 合同继续有效。

## 已确认的问题

0031、0057、0062、0067、0068、0072、0073、0075、0080、0082、0083 的十一条当前 writer 定义，都在 request lock 前解析一次授权，在 request lock 后再次解析。第一次赋值尚未被使用，就被第二次赋值覆盖。

这些 writer 直接调用 strict resolver，或调用只转发到它的 report-family wrapper。strict resolver 的当前定义来自 0081，依次取得 organization-membership、project-membership 和 capability advisory locks。0103 新增的恢复读取 resolver 另外先取得 governance 和 workspace `KEY SHARE` 锁；它没有替换这些 writer 的 strict resolver。

#509 的终结事务需要先取得完整受影响 request 锁集合，再取得 governance、workspace 和授权层级锁。现有 writer 的 hierarchy → request 与该 request → governance／workspace → hierarchy 形成具体反序；即使只处理既有 receipt 的 exact replay，一个先持有 request 的事务也可能与它死锁。

## 决定

0107 精确替换这十一条既有函数定义，只移除 request lock 前未使用的第一次授权赋值。函数身份、参数、owner、ACL、执行安全属性、request UUID namespace 和其余逻辑保持原合同。

writer 在完成原有输入校验后先取得各自既有 request lock，再取得授权层级锁。每次 receipt 读取或业务写入仍必须先通过授权；原有等待 project、时区或 lineage 等锁后的重新授权全部保留。exact replay 仍重新确认当前授权，不能因旧 receipt 存在而绕过撤权。配置、release 和 replacement 的固定回执、不可变审计来源与隐私保护不变。

本决定只移除已确认的锁反序，是 #509 的前置条件。它不执行 physical purge，也不改变 runtime、HTTP、Backend 或 Flutter 合同。

## 验证

catalog check 对十一条精确 signatures 检查 owner、ACL、安全属性、request namespace 和次序：第一把 request lock 前没有 resolver 调用，锁后及后续等待后的两次调用都存在，receipt／write 位于授权之后。migration 另核对替换前后的 OID、owner、ACL 和安全属性。

rollback fixture 以真实 active owner 和 project membership、缺少 release capability 的前置调用全部十一条 writer，固定返回 `42501`，没有新增 claim、receipt、snapshot、配置或访问 audit。既有 release、replacement 和 opt-in fixtures 继续验证成功行为。

独立会话测试先建立真实 channel-v2 receipt。A 持有该 request；B 尝试 exact replay 并等待 A；A 再依次取得 governance、workspace 和 hierarchy 授权锁，撤销 capability 并提交。B 只能返回 `42501`，receipt、snapshot、claim 和访问 audit 的完整行内容不变。旧定义使 B 在等待 request 时持有 hierarchy，A 随后等待 hierarchy，测试因死锁失败。

标准 Docker runner 覆盖 0106 → 0107 的旧 live 数据升级、checksum replay、业务和 lifecycle 数据不变，以及全部检查、fixtures、并发和 dump／restore。上述 synthetic 证据只证明 PostgreSQL 合同。
