# Pull cursor 只在整批变化本地落盘后推进

状态：**已接受（2026-08-05）**。

关联：Slice 1 和 2；ADR-0022、ADR-0098；`ARCH-001`、`ARCH-007`、`TEST-003`。

Backend 接受 push command 后返回的 cursor 只证明该 command 已进入 change feed，不证明客户端已取得之前的所有变化。如果另一设备的变化先进入 feed，本设备随后用 push ACK cursor 覆盖 pull cursor，就会永久跳过较早变化。因此 push ACK 只原子更新 command 结果和成功时间。只有 pull batch 的全部事实已幂等应用到 SQLite，客户端才在同一 transaction 中推进 pull cursor。任何一条变化无效时，整批事实和 cursor 一起回滚。

这个决定会让客户端在 push 后再拉到自己的接触。本地幂等应用会跳过同一接触和 revision，这个小额重复换取不丢失他人或其他设备变化的正确性。
