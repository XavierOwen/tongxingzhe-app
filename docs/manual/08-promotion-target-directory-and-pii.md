# 第 8 章：推广对象目录如何限制个人资料的建立与读取

推广对象是为了持续跟进而建立的资料，不是每次接触的必填主体。使用者可以继续离线记录匿名接触；只有确有跟进需要、并且对方愿意留下资料时，才建立个人或机构对象。本章说明第一段对象路径：在线建立对象、由建立者取得初始跟进分配，并且只读取当前分配给自己的对象。

## 匿名接触为何仍是默认入口

接触记录描述一次已经发生的推广事实。推广对象描述一个可能跨多次接触持续跟进的主体。两者有不同的保存目的和隐私风险，所以当前实现不要求先建对象再记接触，也不把姓名、电话或邮箱写入接触、问卷文本、同步 command 或分析 warehouse。

对象页会明确说明保存目的。建立按钮只有在使用者填写名称并确认跟进需要和资料意愿后才可用。这个确认是操作意图证据，不替代当地法律要求，也不扩大后端授权。

## 一次建立请求经过哪些边界

```mermaid
flowchart LR
  A["Flutter 明示目的与资料意愿"] --> B["HTTPS + access token"]
  B --> C["Backend 重取可信当前上下文"]
  C --> D["检查 create_target 与查看能力"]
  D --> E["PostgreSQL 再验个人空间所有权"]
  E --> F["同一事务建立对象、初始分配和审计"]
  F --> G["只返回当前分配对象"]
```

[`PromotionTargetDirectoryPage`](../../lib/features/targets/promotion_target_directory_page.dart) 不提交用户、空间或项目 ID。它只提交对象类型、名称、可选电话、可选邮箱和幂等 request ID。Backend 从 access token 取得内部 `app_user_id` 和当前上下文；客户端不能通过修改 JSON 选择另一个空间。

PostgreSQL 生成对象 UUID。客户端无需先猜测或保留对象 ID。相同使用者和 request ID 的网络重试返回原对象；同一 request ID 改写资料会冲突，不会产生第二个对象。

## PII 保存在哪里

当前 PII 只在 `promotion_targets` 保存一份。`promotion_target_creation_requests` 只保存操作者、request ID 和对象 ID；`promotion_target_access_events` 只保存对象、操作者、动作和时间。两张审计表没有名称、电话或邮箱列，并由触发器阻止修改和删除。

建立事务同时写入：

- workspace 级对象资料；
- 建立者的活动跟进分配；
- 不重复 PII 的幂等请求记录；
- 一条 `created` 访问审计。

任一步失败，整个事务回滚。目录读取只联结 `ended_at IS NULL` 的分配，并为实际返回的每个对象追加 `viewed` 审计。已经结束分配的对象不会返回。

## 为什么当前不做离线对象缓存

这一切片没有在 Drift、应用偏好、日志或同步 Outbox 保存对象资料。对象页没有网络时失败关闭，同时提示匿名接触仍可离线使用。这样先证明授权和审计路径，再在后续切片加入经过加密、受七十二小时期限约束的最小离线资料。

[`HttpPromotionTargetGateway`](../../lib/targets/http_promotion_target_gateway.dart) 只接受 HTTPS Backend；localhost 仅用于本机测试。它在每次请求前取得 access token，遇到 `401` 最多强制刷新一次。正式 Flutter 不知道 PostgreSQL login 或表权限。

## 两层授权为何都需要

Backend 每次列表或建立操作都重新检查 capability：

- `create_target` 允许建立对象；
- `view_assigned_target_pii` 允许读取当前分配对象的资料。

界面隐藏按钮只改善操作体验，不是授权。即使攻击者直接调用 HTTP，Backend 仍会拒绝缺少 capability 的上下文。即使 Backend 传入错误上下文，[`0016_promotion_target_directory.sql`](../../backend/database/migrations/0016_promotion_target_directory.sql) 也会重新检查活动用户、个人空间所有权和活动项目。

当前只有个人空间。组织成员、角色和跨成员分配要等组织切片建立成员关系后再授权，不能从个人空间所有者规则推导。

## 如何验证这个边界

Flutter 测试证明建立按钮需要明示确认、空目录不阻断匿名接触，并固定 bearer header 与不含客户端 `target_id` 的请求合同。Backend 测试证明 capability 会在存储前重验，额外 `workspace_id` 会被拒绝，PostgreSQL Adapter 只传可信上下文和受控资料。

PostgreSQL 检查与 synthetic fixture 证明：

- runtime role 只能执行受控函数，不能直接读写对象、分配或审计表；
- 建立者在同一事务取得初始分配；
- 精确重放返回同一对象，改写重放发生冲突；
- 伪造空间和未分配身份不能读取 PII；
- 结束分配后对象退出目录；
- 建立和查看审计只追加，且不重复 PII。

CI 从空库执行全部 migration 两次，再运行检查和 fixture。随后执行 `pg_dump`／`pg_restore`，并在恢复库中重跑同一组验证。

## 当前边界

当前实现只完成在线对象目录、个人或机构资料建立、初始分配、当前分配读取、幂等与访问审计。接触关联、当次反应、关系阶段、跟进备注、历史关系、加密限时离线资料和匿名化仍属于后续切片。
