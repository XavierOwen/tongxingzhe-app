# ADR-0207：CSV 字段归一化版本绑定预览回执

- 状态：已接受
- 日期：2026-11-16
- 范围：私有数据库修正；Issue [#659](https://github.com/XavierOwen/tongxingzhe-app/issues/659)
- Requirement：`PII-010`、`TEST-191`、`MANUAL-180`
- 关联：[ADR-0041](./0041-imported-target-data-never-creates-contact-facts.md)、[ADR-0206](./0206-duplicate-contact-signals-trim-whitespace-without-rewriting-values.md)

CSV 字段合同要求去除首尾空白，空电话和 email 转为 null。真实 0157 基线中，合法名称配上仅含 tab 的电话和仅含不换行空格的 email，普通 preview／confirm 仍成功建立一个对象，并保留两个非空字段。0157 只修正疑似重复比较，没有修正导入字段值。

0158 为 private preview 增加 `normalization_version smallint`，只接受 1 或 2；既有行默认版本 1，新签发预览显式使用版本 2。版本 2 在原长度校验前，去除姓名、电话和 email 首尾的 Unicode `White_Space` 与 BOM（U+FEFF）。空姓名拒绝，空电话和 email 转为 null，内部字符保持原样。普通创建 writer 与已保存对象不改写。

确认和精确重放只按 preview 保存的版本选择 canonicalizer。版本 1 的实现及原行指纹算法保留，不尝试其他版本匹配指纹。已完成的版本 1 请求仍按原规则精确重放；原规则下属于漂移的 tab 变化仍返回 23505。版本 2 已完成请求接受归一化后相同的 Unicode 首尾空白表示，返回首次回执。

未完成的版本 1 preview 仍先绑定原规范化行集。若其字段按版本 2 处理会改变，首次确认返回 `stale_preview`，不建立对象，调用方重新预览后再确认。归一化结果不变的旧 preview 可沿用原确认流程。新版本不借旧回执写入不符合当前字段合同的值，也不改写已完成的历史结果。

正式 runner 验证真实 0157 基线、0158 fresh、升级、checksum 与独立恢复，逐值核对原对象、旧完成回执和函数 catalog 的预期变化。局部回归与完整 Docker、固定提交 CI 分别留证。本决定只适用于私有 PostgreSQL，不增加生产、runtime grant、Backend、HTTP 或 UI 入口。
