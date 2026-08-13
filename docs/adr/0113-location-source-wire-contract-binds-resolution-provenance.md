# 位置来源 wire 合同绑定解析来源

状态：**已接受（2026-08-12）**。

关联：Issue #94、Slice 6T；ADR-0011、ADR-0110 至 ADR-0112；`REGION-001`、
`REGION-002`、`REGION-005`、`REGION-007` 至 `REGION-009`、`ARCH-004`、
`ARCH-006` 至 `ARCH-008`、`ARCH-010`、`PRIVACY-007`、`PRIVACY-010`、
`PRIVACY-011`、`TEST-003`、`TEST-005`。

## 决定

同步协议把 `location` 和可选的 `location_source` 当作同一个事实组。只有
`resolved` 地点可以带 `captured_coordinates` 来源。该来源保存原始纬度、经度、
可选精度、固定解析器合同 `canonical-region-resolution:v1`，以及解析时已发布区域树
的 64 位小写 SHA-256 内容指纹。

以下组合有不同含义，不能互相猜测：

- `resolved` 没有来源表示旧数据或人工选择的 `region-only` 地点；
- `pending_resolution` 的坐标保存在地点本身，不带来源；
- `not_applicable` 不带坐标、区域或来源；
- `null` 草稿地点不带来源；
- 作废命令不接收地点或来源，只复制服务器已经接受的 revision。

Backend 对地点和来源使用同一个 exact-key codec。未知字段、未知枚举、非有限或
越界坐标、负精度、错误指纹、未知合同版本和不相容组合全部失败关闭。提交、更正、
冲突解决和草稿共用该 codec；冲突读取也要重新验证服务器返回的两份快照，不能用
类型断言绕过边界。

区域解析响应只从窄范围的 `SECURITY DEFINER` 函数取得已发布 release 指纹。
`tongxingzhe_runtime` 可以执行该函数，但不能直接读取区域 release 表。Flutter 只在
父链、内容指纹和解析器合同都合法时，把输入坐标绑定到 resolved 地点；否则继续保留
原始 `pending_resolution`。

来源不包含设备采集时间。ADR-0112 的服务器记录时间不是设备采集时间，客户端和
Backend 都不得用它补造该字段。

## 后果与边界

旧 protocol v1 payload 缺少 `location_source` 时继续有效；已解析地点不会因此被
重解释为坐标解析结果。错误响应、日志和测试失败信息不得回显精确坐标。

本决定固定跨边界合同和可信解析响应，但不声称 Drift、Outbox、冲突本地存储或
PostgreSQL 接触来源表已经完成端到端接线。这些持久化和对账工作分别由 Slice 6U、
Slice 6V 完成。地图、历史重新解析、跨版本映射和区域报表也不在本决定内。

## 验证入口

```bash
flutter test test/regions/contact_region_resolver_test.dart
(cd backend/server && npm test)
./tool/run_postgres_tests_in_docker.sh
```

测试只使用 synthetic 身份、坐标和区域。通过表示当前 codec、可信指纹读取和失败关闭
路径符合合同；它不证明真实客户端已把来源持久化到服务器，也不构成真机或生产验收。
