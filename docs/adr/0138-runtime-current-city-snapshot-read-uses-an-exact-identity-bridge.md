# ADR-0138：Backend runtime 使用 exact identity bridge 读取 current 城市快照

- 状态：已接受
- 日期：2026-08-20
- 切片：Slice 6AQ
- Issue：#167
- 需求：`ANALYTICS-026`、`PRIVACY-018`、`TEST-020`

## 背景

Slice 6AP 已在 PostgreSQL 私有边界完成 current 城市快照的授权读取。Backend runtime 仍不能直接读取
`app_private`，也不能把 0032 的渠道读取函数当作区域快照读取入口。runtime 需要一个只接受可信 external identity、
project UUID 和 snapshot UUID 的窄桥。

身份映射必须保持在数据库边界内。若 bridge 对数据库中的 issuer 或 subject 做 trim，带空格的数据库 identity
可能被干净 token 错误映射。若 runtime 获得 identity 表、用户表、快照或审计表权限，窄桥就失去意义。

## 决策

0059 增加 `app_data.read_authorized_management_current_city_report_snapshot_v1(text, text, uuid, uuid)`。
它只用 exact `issuer = trusted_issuer` 和 `subject = trusted_subject` 查找现有 active external identity，再调用
0058 的 current-city 私有函数。参数中的 project 与 snapshot UUID 保持显式，bridge 原样返回 6AP 固定合同；
completed 报告内的 project 必须匹配请求。

bridge 使用 `SECURITY DEFINER` 和 `SET search_path = pg_catalog`。它的 owner 与 0058 私有函数 owner 相同，且不属于
runtime、区域维护或 release writer。runtime 只有 bridge `EXECUTE`，没有 `app_private` schema usage，没有关键私有表或
函数权限，也没有 `app_users` 或 `external_identities` 的 `SELECT`。函数体不调用 generic reader、bootstrap 或
session context。

Backend adapter 只执行一次固定 bridge 查询。它严格核对返回 JSON 的 root keys、请求 project／snapshot、固定报告定义、
period、target context、两个期间的 city grid、cell keys 和顺序，并接受 `suppressed = null` 或安全的 displayed integer。
它拒绝 contact、source、contributor、城市名称、坐标、geometry 和其他额外字段。adapter 只把 SQLSTATE `42501`
映射为稳定的 `forbidden`；其他数据库错误仍是内部异常。本 Slice 没有 HTTP／wire 入口，完整错误映射留给后续 HTTP 切片。

## 后果

runtime 获得一个可审计的 current 城市读取入口，但不能自行选择用户、绕过 0058 provenance 或访问私有表。6AP 的授权、
时区／截止点／前一 snapshot 对齐、current-city validator 和 value-free audit 仍由私有函数完成。解析器的严格 allowlist
使 protected JSON 合同变化时失败关闭。

真实 PostgreSQL integration 在事务内自建数据并回滚。Docker runner 同时运行 migration、check、fixture、adapter
integration、并发检查、checksum 和 dump／restore。该决定不增加 HTTP handler、Flutter、目录、导出或生产平台证据。

## 验证

从仓库根目录运行：

```bash
./tool/run_postgres_tests_in_docker.sh
```

该套件包含 0059 的结构检查、synthetic fixture 和真实 Node adapter integration。专用测试库的最小顺序见
`docs/manual/11-management-metrics-and-privacy.md` 的 Slice 6AQ 小节。
