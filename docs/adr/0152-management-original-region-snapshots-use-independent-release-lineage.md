# ADR-0152：原始区域管理报告使用独立 snapshot release lineage

- 状态：已接受
- 日期：2026-08-22
- Slice：6BG
- Issue：#199
- 需求：`ANALYTICS-042`、`PRIVACY-034`、`TEST-036`、`MANUAL-026`
- 相关决定：ADR-0149、ADR-0150、ADR-0151

## 背景

6BD 已在私有 PostgreSQL 中固定 `contact_sessions_by_original_region_two_periods@1`。它使用接触保存的 original
来源证据和单一 `source_tree_version + source_content_fingerprint`，生成完整的城市保护网格；它不读取 current selection，
也不把 `data_cutoff_utc` 当作任意历史 `as-of`。

6BD 的 executor 是即时、只读的候选生成合同，还没有保存 snapshot、baseline、前一 snapshot、发布授权或 request claim。若把它
直接接入已有 channel、current-city 或 interest lineage，来源树语义和 family provenance 会混在一起；若把一次 executor 返回值
直接当作已发布报告，则无法证明哪个授权、时区 revision 和 source tree tuple 被固定。

## 决定

6BG 为 6BD 增加独立的私有 DB-only snapshot／release lineage。它复用不可变的
`app_private.management_report_snapshots` storage，但使用专用的原始区域 release attempt、writer role、RLS policy、
provenance 和 request-claim family。原始区域 lineage 不能冒充 channel、current-city 或 interest lineage，其他 report-family
writer 也不能写入或读取原始区域范围。

发布函数只接受 request UUID、可信内部用户、项目和固定 report identity。数据库在请求、项目和 lineage 锁后重新确认
`release_management_reports`、组织／项目成员关系、项目报告时区 revision，并在同一发布事务中调用 6BD executor。调用方不能
提交报告 JSON、cells、时区、截止点、source tree tuple、capability、target tree 或 SQL。

首个 `completed` candidate 建立唯一 `approved_baseline`。后续成功 snapshot 必须属于同一项目、report／version、query fingerprint、
privacy、source scope、期间定义、报告时区 revision 和精确 source tree tuple；新 cutoff 必须前进，source change sequence 不能回退，
并且 snapshot 必须链接当前 lineage head。共享期间的 protected displayed 值或 privacy 状态改变、没有共享期间、source tree tuple
改变、来源不可用，或已发布 lineage 与候选的固定上下文漂移，均返回稳定 blocked reason，不生成 snapshot。executor
内部定义不一致属于实现错误，必须抛出，不能伪装成业务上的 blocked attempt。

授权仍有效时，同一 request UUID 和完全相同的固定输入精确幂等，不新增 attempt 或 snapshot。身份漂移、跨项目和跨 report family
request claim 复用失败关闭。snapshot、attempt 和 request claim 追加不可变，不允许 UPDATE 或 DELETE。blocked attempt
只保留固定 reason 和最小 value-free lineage metadata，不保存候选报告、cells、隐藏前值、来源、contact、contributor、区域名称、
坐标或 PII。撤权与发布的授权复核必须在所有可能等待的锁后进行。

## 后果与边界

独立 lineage 使原始区域报告可以记录自身的 source tree 证据和发布顺序，同时保留 6BD 的历史来源边界。共享 snapshot storage
避免重复实现不可变基础设施，但要求 shared snapshot validator、request-claim family 和 writer RLS 明确扩展到 original-region，
并在恢复 cluster 中准备新的无登录 role。并发 fixture 的 committed namespace 必须与 rollback fixture 分离；restore 只重跑全部
check 和 numbered fixture，不重新执行 migration，也不重跑会提交 synthetic 行的并发脚本。

本决定只交付 DB-only 的 snapshot、release、授权、lineage、幂等、并发和失败关闭合同。它不交付 authorized read、runtime bridge、
HTTP、Flutter、目录／latest、导出、缓存、离线、同步、parent／overlap 下钻、任意历史 `as-of`、replacement、删除、tombstone、
retention、warehouse、调度、生产身份或六平台真人运行时证据。6BF 的删除与保留边界以及 Slice 7 的组织生命周期继续独立存在。

## 验证

0068 migration、structural check、rollback fixture 和独立并发脚本应覆盖：

- original document validator、专用 writer role、RLS row scope、固定 owner、`SECURITY DEFINER`、search path 和最小 ACL；
- 首个 baseline、后续 cutoff、previous／compared pointer、source tree tuple 不变和 source watermark 不回退；
- same／earlier cutoff、无共享期间、共享 displayed／privacy 变化、source tree 改变或不可用、时区／query／privacy／source context 漂移；
- 授权有效时的同 request 精确幂等、身份漂移、跨项目／跨 report family claim、source unavailable 和 direct mutation；
- blocked result 不含 protected report、cells、隐藏前值、来源、contact、contributor、区域名称、坐标或 PII；
- 相同 request、竞争 successor 以及 revoke-first／release-first 的锁线性化；
- 源库的 migration、check、fixture、并发和 checksum，以及 dump／restore、restore role 准备和恢复库的全部 check／numbered fixture 重跑。

这些 synthetic PostgreSQL 结果只能证明已执行的数据库合同和 ACL；不能证明授权读取、runtime、HTTP、Flutter、导出、组织删除、
物理清除、生产备份或真实平台运行时已经完成。
