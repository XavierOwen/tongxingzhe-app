# 同行者 App 开发说明书

这是正式开发说明书的唯一入口，也是未来 App 内“开发说明书”页面所渲染内容的源头。Markdown 是唯一内容来源；以后生成的 HTML 不是另一套需要人工维护的文档。

本说明书面向第一次参与 App 开发的读者。它不会从 Dart 或 SQL 的语言底层讲起，但会解释：代码为什么这样分、Flutter 如何调用业务逻辑、SQLite／PostgreSQL 如何保存事实、统计公式如何定义，以及需求变化时应该改哪里。

## 阅读路线

1. [第 1 章：先让正式代码安全、可替换、可验证](01-safety-foundations.md)

当前认证验证状态见 [Supabase Auth 六平台 Spike](../spikes/supabase-auth-six-platform.md)。它会明确区分 package 声明、build 通过和真实设备流程通过。

后续切片会依次加入：领域与数据模型、接触记录、离线同步、认证与权限、推广对象、问卷、个人计划、统计与隐私、六平台能力、发布与恢复演练。

## 文档与代码如何保持一致

- 每个实现 Issue 同时修改正式代码、测试和对应章节；
- 代码块未来由 `ManualCatalog` 提供复制内容，App 页面显示复制成功／失败反馈；
- 关键代码通过稳定的类、函数、字段或 snippet marker 追溯，不使用容易失效的固定行号；
- 生成代码只解释生成方式与用途，不逐行手写注释；
- 复杂业务规则、SQL、事务、migration、同步、统计和隐私边界重点解释“为什么”和“不变量”。

## 其他权威入口

- 产品合同：[产品规格](../PRODUCT_SPEC.md)
- 统一领域语言：[领域上下文](../../CONTEXT.md)
- 单项架构决策：[ADR 目录](../adr/)
- legacy v5 证据：[v5 盘点](../migrations/legacy-v5-inventory.md)

`docs/PROJECT_DESIGN.md` 是旧 Demo 的历史资料，不是现代实现依据。
