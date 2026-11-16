# ADR-0208：项目关系待分配新请求拒绝全 Unicode 空白文本

- 状态：已接受
- 日期：2026-11-16
- 范围：私有数据库修正；Issue [#661](https://github.com/XavierOwen/tongxingzhe-app/issues/661)
- Requirement：`PII-014`、`PII-015`、`TEST-192`、`MANUAL-181`
- 关联：[ADR-0197](./0197-unknown-project-relationship-facts-stay-pending-until-assigned.md)

ADR-0197 已要求非空备注和原因详情不能全为空白。真实 0158 基线通过正常 private stage，接受并原样保存了仅含 U+202F 的备注、仅含 U+00A0 的 `other` 详情；两个字段单独使用这些值也能成功。原 POSIX 空白检查会拒绝 tab，但没有覆盖这两个 Unicode 空白字符。

0159 只在 `stage_unassigned_personal_merge_project_relationship_v1` 的既有精确重放返回之后、首次 pending UUID 创建之前增加一次检测。新请求的非 null 备注或原因详情若全部属于 Unicode `White_Space` 与 BOM（U+FEFF），返回原 `22023 invalid unassigned project relationship request`，不建立 pending。含有实际内容的原文按原长度限制和原值保存，不裁剪、不转为 null，也不引入归一化版本。

检测放在精确重放之后，保留此前已接受请求的结果。旧全空白 payload 在满足原重放条件时仍返回原 receipt，并按原协议推进 generation fence epoch；业务事实和回执保持原值，成功重放并非零写。任一 typed 值漂移仍由原逐值比较返回原 conflict；新请求拒绝和载荷漂移错误均使本次状态变化完整回滚。既有 POSIX 输入检查与表 CHECK 保留，不重写旧载荷，也不放宽原先会拒绝的输入。

迁移只改变上述函数的一处 body，OID、owner、ACL、锁序、普通 writer 和其余函数保持。正式 runner 检查真实 0158 回归、升级、checksum、fresh、既有 fixtures 与独立恢复，核对旧原文、receipt、全部业务状态及函数 catalog。局部检查与完整 Docker、固定提交 CI 分别留证；本决定不新增生产、runtime grant、Backend、HTTP 或 UI 入口。
