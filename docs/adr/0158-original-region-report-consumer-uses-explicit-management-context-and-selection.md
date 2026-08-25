# ADR-0158：原始区域报告 consumer 使用显式管理上下文和快照选择

- 状态：已接受
- 日期：2026-08-25
- Slice：6BM
- Issue：[#211](https://github.com/XavierOwen/tongxingzhe-app/issues/211)
- 依赖：[#209](https://github.com/XavierOwen/tongxingzhe-app/issues/209)
- Requirement：`ANALYTICS-048`、`PRIVACY-040`、`TEST-042`、`MANUAL-032`

## 决定

6BM 把独立的 `OriginalRegionReportGateway` 接入 `ManagementReportBrowser`。浏览器继续默认显示渠道报告。只有用户明确选择原始区域视图后，
consumer 才使用当前 `ManagementAnalysisContext.projectId` 读取目录。它不使用个人项目，不自动打开第一项，也不推断 current、latest 或 replacement。

独立 panel 和 ViewModel 只接受当前目录中用户明确选择的 `OriginalRegionReportSnapshotSummary`。状态只保存在内存。项目切换、report family 切换、
返回目录、重试和 dispose 使旧 generation 失效，迟到响应不能恢复旧项目或旧快照。

详情只显示 6BL typed report 中的固定元数据、两个期间、source-tree context、城市 ID 和服务端已保护的城市格。`displayed` 显示安全整数；
`suppressed` 只显示“已隐藏 / Hidden”，不显示为零。客户端不排序、聚合、重新归类或计算总计、比例、差值、趋势和隐私状态。

## 边界与验证

6BM 使用 ViewModel、Widget、browser 和 composition 测试验证显式选择、management project 来源、状态隔离、中英文、320×568、200% 字号、键盘、
焦点恢复、heading、live region，以及 gateway 的构造、传递和关闭。

本决定不修改 6BL parser、Backend、PostgreSQL、授权、provenance 或审计，也不增加 Drift、缓存、离线、同步、导出、下载、分享、搜索、分页、
筛选、地图、城市名称、父级／重叠区域或真人平台证据。Flutter 模拟测试不能替代生产身份、数据库授权或真实辅助技术验收。
