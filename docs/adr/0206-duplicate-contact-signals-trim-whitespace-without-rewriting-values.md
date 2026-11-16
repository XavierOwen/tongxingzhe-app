# ADR-0206：疑似重复联系方式只在比较时去除首尾空白

- 状态：已接受
- 日期：2026-11-16
- 范围：私有数据库修正；Issue [#657](https://github.com/XavierOwen/tongxingzhe-app/issues/657)
- Requirement：`PII-010`、`TEST-190`、`MANUAL-179`
- 关联：[ADR-0041](./0041-imported-target-data-never-creates-contact-facts.md)、[ADR-0043](./0043-promotion-target-merges-are-reversible.md)

既有疑似重复合同要求先去除电话和 email 的首尾空白。原 SQL 使用默认 `btrim`，只能去除普通空格；带 tab、换行或不换行空格的相同联系方式会漏报。真实 0156 基线运行正式 fixture 时，普通空格对照通过，Unicode 空白样例返回空提示而失败。

0157 增加纯 SQL helper `app_private.personal_target_duplicate_contact_signal_v1(text)`，仅在比较时去除首尾 Unicode `White_Space` 与 BOM（U+FEFF），空结果转为 null。CSV 同文件和已有对象提示、双对象预览及 receipt validator 使用同一规则。电话保留大小写、标点和内部空白；email 继续以原 `lower` 规则比较。名称不参与匹配，也不增加模糊匹配或自动合并。

存储的姓名、电话和 email 保持原值。普通创建 writer、CSV canonicalizer 和行指纹均不修改，避免改变既有资料或已完成导入的精确重放。待确认 preview 若因新的重复比较得到不同提示，按原合同返回 `stale_preview`，由调用方重新预览。

升级只允许三个既有函数的比较表达式变化，并新增上述 helper；原函数 OID、owner、ACL、其余 catalog 和全部业务状态保留。真实升级验证保留旧已完成 CSV receipt，checksum 重放后仍返回原结果。正式 runner 继续检查 fresh、既有 0111／0113 合同和独立恢复；这些结果分别留证，不从局部 fixture 通过推定完整 CI 已通过。

本决定只适用于私有 PostgreSQL，不部署生产，不增加 runtime grant、Backend、HTTP 或 UI 入口。
