# ADR-0171：去身份化地点异常使用项目范围的不透明只读合同

- 状态：已接受
- 日期：2026-08-26
- Slice：6CC
- Issue：[#243](https://github.com/XavierOwen/tongxingzhe-app/issues/243)
- 依赖：ADR-0010、ADR-0112、ADR-0133
- Requirement：`AUTHZ-008`、`ANALYTICS-064`、`PRIVACY-007`、`PRIVACY-011`、`PRIVACY-055`、`TEST-058`、`MANUAL-048`

## 背景

0039 已为每份接受的 contact revision 保存追加式地点 provenance。`pending_resolution + pending_coordinates` 表示已有坐标但没有可信区域；`unknown + legacy_incomplete` 表示旧证据不足。0054 把这两类来源视为不可进入区域报告，但数据质量维护者仍需要知道哪些当前记录需要后续纠正。

管理报告查看能力不能因此变成单条接触读取能力。组织 owner、项目管理员或 `view_anonymous_analytics` 持有者也不能自动取得异常详情。异常入口必须隐藏记录者、对象、contact、revision 和 source identity，并把坐标限制在明确选择的详情中。

## 决定

6CC 增加独立 `view_deidentified_anomalies` capability。每次目录或详情读取都按组织 membership、项目 membership、active project 和该 capability 的既有锁顺序重新授权。授权不能从角色、owner 身份或其他 capability 推导。

异常只来自 active contact 的当前 accepted revision，并且 provenance 必须精确匹配以下一个 tuple：

- `pending_resolution + pending_coordinates`；
- `unknown + legacy_incomplete`。

resolved、not-applicable、旧 revision、voided contact、contact attempt、draft 和其他项目都不进入目录。合同不按名称、坐标、区域树或客户端标记补造异常。

私有映射为合格 provenance 分配随机 `anomaly_id`。映射不保存 contact 或 project ID，且不能更新或删除。项目、current revision 和 lifecycle 每次读取时重新派生；因此旧 revision 的 opaque ID 保留历史映射，但详情稳定返回 `not_found`。

目录固定最多 20 项，按发生时间和 opaque ID 排序。它返回 reason、open status、发生时间、location kind、evidence kind 和坐标可用状态，不返回坐标。
详情只对显式 anomaly ID 返回相同 metadata。pending anomaly 返回必要的 latitude、longitude 和可空 accuracy。legacy anomaly 的 coordinates 固定为 null。
unknown、cross-project 和 stale opaque ID 使用同一个 value-free `not_found` 结果。

目录和详情共用一张不可变 audit。audit 保存 access event、授权 lineage、项目、operation、结果、授权时间和目录数量，不保存 anomaly ID、坐标、发生时间、location evidence、contact、revision、source 或 PII。未授权请求在 resolver 阶段失败，不写成功 audit。

私有函数和表由新的 closed reader role 拥有。该 role 无登录、无继承、无 bypass RLS，只读取 contacts、revisions 和 provenance 的必要列。`PUBLIC`、runtime、普通 app role、报告 reader／writer 和 provenance writer 都不能执行读取合同或直接访问 mapping、audit 与坐标。

## 后果与边界

这个决定交付 PostgreSQL DB-only 只读合同，不交付 correction mutation。后续修正必须使用独立 capability 和 append-only contact revision，并处理 stale revision conflict；不能由 6CC 直接更新 provenance 或 current contact。

6CC 不增加 runtime bridge、Backend、HTTP、Flutter、地图、geocode、搜索、分页、导出、缓存、离线、组织清除或真人平台证据。Docker synthetic fixture 只证明资格、最小输出、授权锁、审计、ACL 和恢复，不证明生产中实际存在这些异常，也不证明真实坐标或个人数据已安全清除。

## 验证

完整 runner 自动发现 0081 migration、structural check、rollback fixture 和 authorization concurrency script，并执行 checksum 与独立 dump／restore：

```bash
./tool/run_postgres_tests_in_docker.sh
```

只调试 6CC 时，先让 `DATABASE_URL` 指向专用测试库，再运行：

```bash
./tool/postgres_migrate.sh
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/checks/verify_authorized_management_deidentified_anomaly_read.sql
psql "$DATABASE_URL" --no-psqlrc --set=ON_ERROR_STOP=1 \
  --file backend/database/fixtures/0081_authorized_management_deidentified_location_anomaly_read.sql
./tool/verify_authorized_management_deidentified_anomaly_read_concurrency.sh
```

恢复库只重跑 check 和 rollback fixture，不重跑会提交 synthetic 行的并发脚本。
