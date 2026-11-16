# ADR-0209：个人合并接触确认的子命令键保持有界

- 状态：已接受
- 日期：2026-11-16
- 范围：私有数据库修正；Issue [#663](https://github.com/XavierOwen/tongxingzhe-app/issues/663)
- Requirement：`PII-009`、`PII-013`、`TEST-193`、`MANUAL-182`
- 关联：[ADR-0193](./0193-historical-pending-facts-and-current-source-candidates.md)、[ADR-0203](./0203-mixed-resolution-confirmation-uses-one-final-manifest.md)、[ADR-0204](./0204-mixed-project-entry-prelocks-before-one-confirmation.md)

真实 0159 基线中，2600 字节低压缩 TEXT contact ID 使用独立短 command ID，普通 submit、revise 和 0127 stage 均成功。0128 确认将完整 contact ID 拼进子命令后，audit 唯一索引报 `54000`，索引行 2720 字节超过该测试库的 2704 字节上限；0130 的 current 子命令在 `processed_commands` 主键处失败。两条路径各重复两次，短 ID 对照成功。

0160 新增私有纯函数 `personal_merge_contact_child_key_v1(text)`。contact ID 的 UTF-8 字节数不超过 2048 时，保留原 `字节数:contact ID` 后缀；超过时，后缀为 `sha256-v2:` 加原始 UTF-8 字节的 SHA-256 十六进制摘要。外层 confirm／resolve 前缀、request UUID 和 current 标记保留。contact ID、snapshot、来源、事件时间和业务值不改，不给原 contact ID 增加长度上限。

0128、0130、0142 mixed v1 和 0143 mixed v2 的协调器在 generation fence 前预锁新子命令及长 ID 的旧 v1 别名，并检查两者是否已被占用。实际应用只写新派生键。0142 的共享应用承接 0130 和两条 mixed 路径，必须与协调器同步修改。迁移只改变六个旧函数 body，保留其 OID、owner、ACL 和其余实现，不修改普通 v3 writer。

0130 proof 精确接受保存的完整旧 v1 键或新 helper 派生键。旧可压缩长 ID 的已完成回执继续返回原结果，且不重写历史、命令或回执。未完成 pending 在首次确认时使用新键；旧别名预占仍返回原 conflict。0128 proof 继续通过保存的 child ID 核对真实 writer、feed、audit 和实际 revision。

正式 fixture 覆盖四条确认入口、2600 字节 ID、短 ID、2048／2049 UTF-8 字节边界、新旧键预占、typed 漂移和晚期 end 异常的整批回滚。真实 0159 升级 fixture 须保留旧业务状态与完整函数 catalog，重放旧长 v1 完成回执，再确认原 pending。fresh、升级、checksum、既有 fixtures 与独立恢复由正式 runner 分别验证；局部通过不代替完整 Docker、固定提交 CI 或 main 验收。无新表、grant 或依赖，不新增生产、Backend、HTTP 或 UI 入口。

更长 ID 在私有 metadata 复合索引中的宽度限制由 [ADR-0210](./0210-personal-merge-contact-metadata-uses-exact-private-keys.md) 单独处理，0160 的子命令与旧回执合同继续有效。
