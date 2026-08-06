# 同行者 App 开发说明书

这是正式开发说明书的唯一入口，也是未来 App 内“开发说明书”页面所渲染内容的源头。Markdown 是唯一内容来源；以后生成的 HTML 不是另一套需要人工维护的文档。

本说明书面向第一次参与 App 开发的读者。它不会从 Dart 或 SQL 的语言底层讲起，但会解释：代码为什么这样分、Flutter 如何调用业务逻辑、SQLite／PostgreSQL 如何保存事实、统计公式如何定义，以及需求变化时应该改哪里。

## 阅读路线

1. [第 1 章：先让正式代码安全、可替换、可验证](01-safety-foundations.md)
2. [第 2 章：用测试和证据安全地修改代码](02-testing-and-change-workflow.md)
3. [第 3 章：接触、尝试和追加修订如何在 SQLite 中保存](03-contact-journal-and-local-sql.md)
4. [第 4 章：登录身份如何成为可信的当前项目上下文](04-identity-and-current-context.md)
5. [第 5 章：接触提交、修订与尝试入口如何连接 Flutter 与 SQL](05-formal-contact-loop.md)
6. [第 6 章：持久同步与 Backend SQL 如何保护追加历史](06-persistent-sync-and-backend-sql.md)
7. [第 7 章：版本化问卷如何设计、发布、离线执行并由服务端复验](07-versioned-questionnaire-execution.md)
8. [第 8 章：推广对象目录、资料保留、匿名化和限时离线资料](08-promotion-target-directory-and-pii.md)
9. [第 9 章：在本机、Docker 与 CI 中运行测试](09-local-docker-and-ci-testing.md)

当前认证验证状态见 [Supabase Auth 六平台 Spike](../spikes/supabase-auth-six-platform.md)。它会明确区分 package 声明、build 通过和真实设备流程通过。

数据库、离线、同步、界面和认证的整体证据见 [六平台能力证据矩阵](../spikes/six-platform-capability-matrix.md)。

后续章节会依次加入：个人计划、管理统计与隐私、六平台能力、发布与恢复演练。

## 文档与代码如何保持一致

- 每个实现 Issue 同时修改正式代码、测试和对应章节；
- 代码块未来由 `ManualCatalog` 提供复制内容，App 页面显示复制成功／失败反馈；
- 关键代码通过稳定的类、函数、字段或 snippet marker 追溯，不使用容易失效的固定行号；
- 生成代码只解释生成方式与用途，不逐行手写注释；
- 复杂业务规则、SQL、事务、migration、同步、统计和隐私边界重点解释“为什么”和“不变量”。

## 其他权威入口

- 产品合同：[产品规格](../PRODUCT_SPEC.md)
- 统一领域语言：[领域上下文](../../CONTEXT.md)
- 单项架构决策：[ADR 索引](../adr/README.md)
- 离线对象资料安全边界：[威胁模型](../security/offline-pii-threat-model.md)
- 对象资料保留与匿名化边界：[威胁模型](../security/promotion-target-anonymization-threat-model.md)
- legacy v5 证据：[v5 盘点](../migrations/legacy-v5-inventory.md)

`docs/PROJECT_DESIGN.md` 是旧 Demo 的历史资料，不是现代实现依据。
