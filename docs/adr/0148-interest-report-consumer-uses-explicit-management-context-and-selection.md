# ADR-0148：兴趣报告 consumer 使用显式管理上下文和快照选择

- 状态：已接受
- 日期：2026-08-21
- 切片：Slice 6BC
- Issue：#191
- 需求：`ANALYTICS-038`、`PRIVACY-030`、`TEST-032`、`MANUAL-022`

## 背景

6BB 已提供独立的 Flutter interest gateway，但不选择管理项目、report family 或快照。既有管理报告浏览器已有
channel 和 current-city 视图。增加 interest 后，多个布尔开关会产生无效组合，而个人工作区 project 也不能冒充已重新授权的
管理分析上下文。目录顺序只是服务端固定排序，第一项没有 current 或 latest 语义。

## 决策

管理报告浏览器使用一个互斥 report-family 状态表示 channel、current-city 和 interest，channel 仍为默认。只在用户明确
选择 interest 时挂载独立 panel，并且只使用当前 `ManagementAnalysisContext.projectId`。没有管理上下文时不请求，不回退到
个人 `TrustedSessionContext`。

interest ViewModel 只允许打开当前目录中用户明确选择的 summary。它不自动打开第一项，不推断 current、latest 或
as-of。目录、详情、项目切换、返回目录、重试和 dispose 均递增 generation；迟到响应只能在 generation 与当前项目仍匹配时更新状态。

panel 使用 interest 专属 typed model 显示固定元数据和十格。`displayed` 显示服务端计数；`suppressed` 显示“已隐藏 / Hidden”，
不显示为零。UI 不计算总计、比例、平均等级、中位数或趋势。它支持中英文、小屏、200% 字号、键盘、焦点恢复、heading
和错误 live region。composition root 独立构造、传递并关闭 interest gateway。

## 后果

管理 project 来源、report family 和快照选择都是显式的，目录首项不会被客户端升格为“最新事实”。channel、current-city 和
interest 保持独立 DTO、gateway 和 panel，避免一个泛型抽象隐藏三种报告的不同合同。代价是保留三套窄小 UI 路径，但这使
不同的隐私语义和迟到响应边界可以独立测试。

6BC 不修改 Backend 或数据库，不增加 Drift、缓存、离线、同步、导出或真机运行时证据。

## 验证

ViewModel 测试覆盖空目录、明确 summary、分阶段重试、项目切换、返目录、异常和 dispose。Widget 测试覆盖十格、隐藏语义、
320×568、200% 字号、键盘、焦点恢复和语义。Browser 和 app 测试覆盖三个互斥 family、管理 project 来源、gateway 独立、注入与关闭。

运行：

```bash
dart analyze
flutter test --no-pub
dart run tool/check_production_boundary.dart
dart run tool/check_markdown_links.dart
```

这些 synthetic Flutter 测试不代表 Backend／DB 授权、生产身份或六平台真机证据。
