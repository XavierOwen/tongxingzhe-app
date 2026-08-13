# 设备位置来源是原子类型化事实

状态：**已接受（2026-08-12）**。

关联：Issue #95、Slice 6U；ADR-0022、ADR-0098、ADR-0100、ADR-0112、
ADR-0113；`REGION-001`、`REGION-002`、`REGION-005`、`REGION-007` 至
`REGION-009`、`ARCH-001`、`ARCH-004`、`ARCH-006` 至 `ARCH-008`、
`ARCH-010`、`PRIVACY-007`、`PRIVACY-010`、`PRIVACY-011`、`MIGRATION-001`
至 `MIGRATION-005`、`TEST-003`、`TEST-005`。

## 决定

Drift v18 在草稿、当前接触投影和每条接触 revision 上保存六个可空的类型化来源
字段：来源类型、纬度、经度、可选精度、解析器合同版本和区域树内容指纹。来源不
保存为不透明 JSON。SQLite `CHECK` 和 Dart 边界共同拒绝部分来源、越界数值、未知
合同和不合法指纹。

只有 `resolved` 地点可带 `captured_coordinates` 来源。`resolved` 没有来源仍表示
兼容的 `region-only` 地点；`pending_resolution` 的坐标保存在地点本身；
`not_applicable` 和空草稿地点没有来源。从 v17 升级时，旧行的六个字段全部保持
空值。迁移不从当前区域 assignment、旧坐标或当前发布树猜测历史来源。

ContactJournal、Outbox、pull apply 和冲突快照把地点和来源作为一个事实组。保存、
更正或冲突解决会同时替换或清空两者；作废 revision 复制上一条已接受 revision 的
完整事实组。跨设备比较中，地点或来源任一变化都表示该事实组发生变化。自动合并
只能采用一侧完整事实组；不能把一侧地点和另一侧来源拼接。

同步 command 使用 ADR-0113 的 snake_case `location_source`。change feed 和冲突
快照使用 Backend 已有的 camelCase `locationSource`。两种表示只在受控 adapter
边界转换，不能把数据库列名直接当 wire 合同。

## 后果与边界

类型化列会增加 Drift 生成代码，但让 SQLite 在 Dart 之外也能保护核心不变量。
来源坐标仍是设备内私有事实。界面可显示“待解析”或明确的地点名称，但 pending、
N/A 和冲突比较不得直接回显纬度、经度或精度。

本决定证明设备内保存、重启、重试和冲突处理不静默丢失来源。它不证明 Flutter、
Backend、PostgreSQL 来源表和 warehouse 清理已经完成四层对账；该证据由 Slice 6V
收口。历史重新解析、地图、区域报表和真机验收不在本 Slice 内。

## 验证入口

```bash
flutter test --no-pub test/data/local_database_migration_test.dart
flutter test --no-pub test/features/contact_journal
flutter test --no-pub test/sync
flutter test --no-pub test/features/contact_entry test/features/contact_revision
dart analyze
```

迁移测试必须包含 v17 至 v18 旧行保留和新行 round-trip。Journal 与同步测试必须
覆盖草稿重启、提交、更正、作废、pull、重试、来源单边变化和双方冲突。界面测试
使用 synthetic 坐标，并断言这些精确数值没有进入可见文本。
