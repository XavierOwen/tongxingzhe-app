# 持久 Outbox 使用领取、租约与确认协议

状态：**已接受（2026-08-03）**。

关联：Slice 1 和 2；`ARCH-001`、`ARCH-007`、`TEST-001`、`TEST-003`。

## Context

ADR-0022 已决定先在本地事务中写入业务事实和 Outbox，再通过 HTTPS 同步。仅有“队列加重试”不足以处理 App 崩溃、Web 多标签、同一对象上的命令顺序、超时后结果未知和不可重试拒绝。若这些状态由页面或临时内存控制，重启后会重复发送、永久卡住，或让 UI 错报同步成功。

## Decision

`ContactJournal` 对外提供提交、修订和作废等完整行为，并在一个 Drift transaction 中原子写入业务事实与 Outbox。页面不直接操作 Outbox。内部 `SyncEngine` 负责下列持久状态机；唯一远端接缝是窄的同步 Transport，生产使用 HTTP Adapter，合同测试使用内存 Adapter。

每条 command 至少保存：唯一 `command_id`、协议版本、类型、类型化 payload、`aggregate_id`、`base_revision`、`created_at`、`status`、`attempt_count`、`next_attempt_at`、`lease_owner`、`lease_expires_at`、`last_failure_code` 和 `completed_at`。payload 可以包含完成业务命令所需的最少资料，不进入健康日志或分析事件。

状态只有：

- `pending`：等待第一次发送或下一次重试；
- `leased`：已由一个 drainer 原子领取，租约到期后可再次领取；
- `needs_resolution`：冲突，等待明确处理；
- `permanent_failure`：业务拒绝或禁止，不自动重试；
- `completed`：服务端已接受，或确认相同 command 早已处理。

领取必须在 SQLite transaction 中完成。过期租约可重新领取，以恢复 App、进程或浏览器标签崩溃。同一 `aggregate_id` 同时最多租出一条 command，并按创建顺序发送；其他 aggregate 不被一个冲突或失败阻塞。Web 也以持久租约保证同一时刻只有一个 drainer；内存锁或 tab 协调只能作为减少竞争的优化，不能作为正确性边界。

服务端结果按稳定合同转换：`accepted`／`duplicate` 进入 `completed`；`conflict` 进入 `needs_resolution`；`rejected`／`forbidden` 进入 `permanent_failure`；传输超时、`429` 和 `5xx` 回到 `pending`。可重试失败使用有上限的指数退避和 jitter，并遵守可信的 `Retry-After`。服务端 push 结果与本地 command 状态、错误码必须在本地 transaction 中确认。pull 事实与 pull cursor 必须在另一个本地 transaction 中确认。push ACK cursor 不得直接推进 pull cursor；原因和失败场景见 ADR-0100。`needs_resolution` 不自动清理。

同步健康只暴露 `pending_count`、`retrying_count`、`needs_resolution_count`、`oldest_pending_age`、`last_success_at` 和稳定 failure code，不暴露 payload、PII 或自由文本。Slice 1 必须提供最小健康状态和过期租约恢复；Slice 2 再加入冲突处理、部分批次失败和完整错误分类。

## Options considered

- 仅用内存队列：实现简单，但进程退出后丢失领取状态，不能满足离线优先。
- 每次扫描并发送所有未完成行：缺少互斥、顺序和崩溃恢复，Web 多标签会放大重复请求。
- 现在加入高低优先级：没有真实积压证据，先增加饥饿和排序规则会扩大状态空间。优先级延后到有可测的业务需要时决定。

## Consequences

SQLite schema、索引、时钟和失败分类更明确，测试必须覆盖原子领取、租约过期、ACK transaction、重启、退避和双 drainer。协议仍以服务端幂等为最终安全边界，因为客户端可能在服务端已提交但 ACK 丢失后重发。页面获得稳定而有限的同步状态，不需要知道 HTTP 或队列表结构。
