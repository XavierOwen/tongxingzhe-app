# ADR-0195：历史贡献只复制已确认的个人核心事实

- 状态：已接受
- 日期：2026-10-20
- Slice：7EW／private DB-only
- Issue：[#595](https://github.com/XavierOwen/tongxingzhe-app/issues/595)
- Requirement：`CTX-006` 至 `CTX-012`、`TEST-167`、`MANUAL-156`
- 关联：[ADR-0009](./0009-records-do-not-move-between-workspaces-implicitly.md)、[ADR-0037](./0037-delete-accounts-without-erasing-organization-owned-history.md)、[ADR-0192](./0192-organization-purge-finalizer-atomic-scope-and-completion.md)

## 决定

个人记录不会因加入组织或切换项目而移动。首片历史贡献接收可信内部用户、本人个人接触 ID 和明确的组织项目 ID，经预览与确认生成独立核心副本；原记录、全部修订、对象关系与个人分析均不改变。它不向现有 contacts、revision、change feed、outbox 或管理报告塞入合成记录，也不伪造匿名作者或 contributor 数量。

核心副本只保存发生时间、发生时区、有限渠道类别、触达人数和兴趣度，另有随机副本 ID、目标项目与确认时间。时区必须命中数据库时区目录，不能把任意自由文本当作时区复制。来源的当前位置、坐标、对象或同意关系、渠道详情、问卷答案、原因、笔记、反思和其他自由文本均不复制。预览只返回同一五项核心事实及固定 metadata；确认只返回 contract、副本 ID、目标项目与确认时间。

没有作者字段不等于公开匿名。时间与核心事实仍可能关联到个人，本片只在封闭 private schema 保存未聚合事实，不提供阅读、导出或统计入口。现有管理报告、隐私阈值和 contributor 口径不变；接入统计前须另行决定贡献者口径、重复计算和披露保护。

## 预览与确认

预览由数据库签发随机 UUID，绑定 actor、source contact、当前 revision 和目标项目，只保存这些引用与签发／过期时间，不保存业务值。有效期为最后等待锁后数据库墙钟起连续 15 分钟。来源必须属于本人未删除个人空间，当前 revision 为有效 submitted／corrected，且当前 projection 与该 revision 的五项 typed 核心值完全一致；个人来源项目可以已经归档。

首次确认使用独立 request UUID 与显式 preview UUID。数据库重新验证本人和目标资格、半开预览窗口及 source revision；来源在预览后修订或作废时 conflict，不能暗中确认新的内容。首次确认把副本与不可变 receipt 原子写入；任一步失败全部回滚。同一 source contact 对同一目标项目只允许一份副本，不因来源修订重新计入。多个预览可以并存，但不能绕过这一唯一约束。

精确确认重放要求相同 actor、request、preview、目标资格及一致的副本来源，返回原确认结果。它不再要求预览未到期或个人记录仍为原版本，因此后续个人修订／作废不会改变已经确认的组织副本。换 actor、selector、重复贡献、过期的首次确认和已清除的 request UUID 均 conflict。没有来源读取权返回 forbidden；projection／revision 核心值或已完成 receipt 漂移返回 unavailable，不猜测或修复。

## 锁与权限

入口只接受 READ COMMITTED，在授权、锁和读取前拒绝其他模式。确认先取 `personal-history-contribution-confirmation:<request UUID>`；随后两条入口共用本人 user row、目标组织 governance、organization membership、project membership、既有 project status fence 和来源 contact advisory lock。最后一个等待锁之后取一次墙钟，并重新检查 active user、未删除且不处于删除周期的组织、active target project 和当前两级 membership。贡献不要求管理角色，组织成员也不会自动获得项目成员资格。

本人 user row 使用 `FOR NO KEY UPDATE`：它阻止状态变化和删除，同时兼容旧 contact writer 作者外键的 `KEY SHARE`，避免 user→contact 与 contact→作者外键检查的反向等待。project status 复用既有 `management-follow-up-consent-opt-in:<project UUID>` 锁，不反向锁 project row。来源读与普通 contact writer 共用 `contact:<contact ID>`；同 source／target 的并行确认由该锁串行化。撤权、项目归档、来源修订、账号 pending 与组织删除先提交时，新调用必须重新拒绝；确认先提交则保留已经成立的副本。成功重放也不能绕过当前目标授权或组织删除冻结。

四个新函数均为 `VOLATILE SECURITY DEFINER`，固定 `search_path=pg_catalog`，owner 与既有 membership validator 相同。PUBLIC／runtime 无表权限与函数执行权；不增加 external identity bridge。三个 private 表分别保存 metadata-only preview、五字段核心副本与确认 receipt。receipt 与 preview 可供可信终结处理把 actor／source 非空引用解除为 null，但不能重绑；副本不允许 UPDATE。

## 清除与边界

组织终结清除把三表纳入该组织目标项目范围，先删除 confirmation，再删除 preview 与 copy；个人来源和其他组织的副本不动。复用既有 exact-row transaction DELETE proof，并在删除前独立验证三表来源、目标与个人 ownership。原 finalizer 的 86 项相对顺序保留，collector 尾部增加 rank 14 的独立 confirmation family，成功后只留 value-free UUID tombstone；失败时全部回滚，不能把新副本留在已清除组织之外。

0134 只增加三表、四个函数，并最小扩展两个既有 purge 函数与一个 tombstone CHECK。真实 0133 升级须保留全部旧表内容、原 OID、owner、ACL、约束及未扩展函数定义；两个扩展函数只能出现固定新增块，不能借此改写旧清除逻辑。

本片不交付 Backend、HTTP、UI、runtime、scheduler、生产部署、自动历史扫描、批量选择、组织内普通 contact writer 或统计接入。个人账号期满清除和贡献撤回／更正另行交付；没有这些流程前，不声称完整历史贡献产品或真实身份不可反查。Docker synthetic 的 fresh、升级、并发、checksum 和独立恢复证据仅覆盖私有 PostgreSQL 合同。
