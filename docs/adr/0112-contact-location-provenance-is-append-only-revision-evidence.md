# 接触地点来源是追加式 revision 证据

状态：**已接受（2026-08-12）**。

关联：Issue #92、Slice 6S；ADR-0011、ADR-0012、ADR-0020、ADR-0021、ADR-0110、ADR-0111；`CONTACT-010`、`REGION-001`、`REGION-002`、`REGION-005`、`REGION-007` 至 `REGION-009`、`ARCH-004`、`ARCH-006` 至 `ARCH-008`、`ARCH-010`、`AUTHZ-004`、`AUTHZ-006`、`PRIVACY-007`、`PRIVACY-010`、`PRIVACY-011`、`MIGRATION-001` 至 `MIGRATION-005`、`TEST-003`、`TEST-005`。

## 决定

接触地点的来源证据保存在 PostgreSQL 的独立追加表中。一个已接受的
`contact_id + revision_number` 最多对应一条来源记录；可信追加操作在接触
revision 同一 transaction 中写入它。来源记录一旦提交不能 `UPDATE` 或
`DELETE`，也不能因为当前区域投影变化而重写。

来源记录至少要能区分以下事实：

- `resolved`：保存最小区域、`tree_version` 和 6R 的发布内容指纹。区域必须
  属于已发布版本并且沿父链存在城市；有原始坐标时保存坐标和精度，没有时
  明确标记为 `region-only`；
- `pending_resolution`：保存合法纬度、经度和可选精度，不保存区域或区域树；
- `not_applicable`：表示纯非线下接触，明确不保存坐标、区域或区域树；
- 历史数据无法完整解释时：保存 `incomplete`／`unknown` 状态，不猜测坐标、
  城市、区域映射或采集时间。

来源记录的服务器记录时间不是设备采集时间。若 6R 的区域 release 不存在、
未发布或内容指纹不匹配，追加操作失败关闭。`current` 仍只是解析器使用的
当前投影；来源记录不产生跨版本映射，也不把旧区域 ID 猜成新树中的相似
城市。

三路修订把 `location` 和 `locationSource` 视为同一事实组。自动合并替换地点时
必须同时替换或移除来源；冲突读取把两者一起返回给有权解决者。这样旧坐标不会
与新区域误配，待解析地点也不会残留上一版 resolved 来源。

6S 的可信追加合同是私有、窄范围的 PostgreSQL 合同，供后续生产写入 bridge
接入。`tongxingzhe_runtime` 没有来源表、sequence 或维护函数的直接权限；
区域发布者和管理分析 capability 也不会因此获得接触来源或精确坐标读取权。
本决定不声称 Flutter／Drift、同步 envelope、Backend HTTP 或生产写入 bridge
已经接入。

## 历史回填

新增 migration 只从每个不可变 revision 自己的 `snapshot.location` 和可选
`snapshot.locationSource` 回填：

- `pending_resolution` 复制该 revision 自己的坐标；
- `resolved` 复制该 revision 的区域和树版本，并从 6R release 绑定内容指纹；
  没有坐标的旧记录保持 `region-only`；
- `not_applicable` 保持明确的不适用状态；
- 缺失或不合法的旧数据保持 `incomplete`／`unknown`。

回填不能使用 `contact_region_assignments` 当前投影伪造旧 revision，不能改写
contact、revision 或 assignment，也不能把区域发布时间或 current 选择时间当作
采集时间。迁移必须可从空库重建、检查 checksum，并在没有源 cluster roles 的
独立 PostgreSQL 集群中 dump／restore 后保留来源身份、指纹和不可变约束。

## 后果与边界

这项决定让 `original` 有一份按 revision 保存的可复核证据，并为未来按坐标
或明确映射生成 `current` 提供必要材料。它不交付 current 地点视图、跨版本
映射、批量重新解析或生产区域报告。`contact_region_assignments` 继续作为
兼容性的 current projection；它不是历史来源。

精确坐标属于敏感接触事实。来源表留在 `app_data`，不得进入管理报表、日志、
错误响应或 warehouse。`warehouse_outbox` 的写入边界会移除 location 与 source，
包括修订和作废复制的完整 snapshot。作废接触仍保留来源历史；普通路径不物理删除。账号、
空间删除和保留期遵循既有政策，不在本 ADR 新增一套清理语义。

6S 只覆盖已提交 contact revisions。当前 `contact_attempts` 没有地点字段，
尝试地点另行处理，不在本决定中偷偷扩展。

## 验证入口

从仓库根目录运行完整 PostgreSQL Docker 套件：

```bash
./tool/run_postgres_tests_in_docker.sh
```

该套件应包含 0039 的 schema check、可回滚 fixture、独立并发脚本、migration
checksum 复跑以及独立集群 dump／restore。测试只使用 synthetic 数据；通过只证明
当前列出的 shape、权限、回填和并发不变量成立，不证明 Flutter／Backend 生产
写入已经接入，也不构成区域报表不可重识别保证。
