# 私有管理区域归属解析只接受显式目标树和可验证来源

状态：**已接受（2026-08-14）**。

关联：Issue #153、Slice 6AL；ADR-0110 至 ADR-0115、ADR-0132；
`REGION-007` 至 `REGION-011`、`ANALYTICS-012`、`PRIVACY-010`、`TEST-007`、`TEST-015`。

## 决定

未来固定区域报告使用一个私有、只读的 typed resolver，把一条不可变地点来源转换为最小的区域归属证据。
调用方必须明确传入 `original` 或 `current` 视图。`original` 的两个 target 参数必须为 `NULL`；
`current` 还必须传入已发布目标区域树的 `tree_version` 和精确 `content_fingerprint`。resolver 不读取
current 选择开关，也不替调用方决定报告截止点使用哪一个目标树。

`original` 只有在来源 release 已发布、来源指纹精确匹配、来源节点真实存在且父链包含城市时才返回原始
区域 tuple。来源证据不完整或不一致时，resolver 失败关闭。

`current` 对 `resolved_from_coordinates` 使用来源保存的原始坐标和明确目标树的边界。它只接受唯一最深
候选；其他命中必须位于同一父链。零命中返回 `unmapped`，跨父链或同深度多候选返回 `ambiguous`，不使用
稳定排序隐藏几何歧义。`resolved_region_only` 在来源和目标树相同时保留已验证来源，跨版本时只调用
ADR-0132 的显式一对一映射，不组合映射链。

`pending_resolution`、`not_applicable` 和 `legacy_incomplete` 返回不含区域 tuple 的稳定
`not_reportable` 状态。成功结果只包含固定 contract、视图、状态、原因和区域 ID、树版本、内容指纹。
结果不得包含来源 ID、contact、revision、贡献者、地点名称、坐标或 PII。错误视图、缺少 current 目标、
草稿目标、目标指纹漂移、未知目标节点或没有城市父链的目标均失败关闭。

resolver 由无登录、无成员的最小权限 reader role 拥有。该角色只读取地点来源、已发布区域树、节点和
边界，并且只能通过 6AK resolver 解析显式映射，不能直接读取映射表。`tongxingzhe_runtime`、`PUBLIC`、
区域发布者、mapping writer 和 provenance writer 都不能执行本 resolver 或直接读取新增能力。

## 后果与边界

这项决定为 future 区域报告提供统一的来源归属接缝，并把坐标唯一性、跨树映射和不可报告状态固定在
数据库边界。它不选择 current tree，不提供历史 `as-of`，也不把 resolver 结果当作完整报表。

本 Slice 不注册生产区域报告，不实现接触统计资格、完整区域网格、父子或重叠查询、互补隐藏、授权、
快照 lineage、HTTP、Flutter、缓存、导出、pending 的自动补全、逆地理编码、一对多／多对一映射或链式映射。
组织成员治理和区域维护者对外部证据的审核仍由后续工作单元负责。

## 验证

使用 synthetic 数据运行完整 PostgreSQL Docker 套件：

```bash
./tool/run_postgres_tests_in_docker.sh
```

0054 的结构与权限 check、fixture、migration checksum 和 dump／restore 必须同时通过。fixture 至少覆盖
original 精确来源、current 坐标唯一／零命中／同链嵌套／跨链歧义／同深度歧义、region-only 同版本与
显式 mapping、错误指纹、草稿或未知树、`not_reportable` 和敏感字段不出现在输出。

通过只证明当前 synthetic 形状和权限边界成立，不证明真实区域边界、维护者证据或生产区域报告已经验收。
