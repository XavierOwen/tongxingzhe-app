# ADR-0189：组织删除申请入口只向当前所有者显示

- 状态：已接受
- 日期：2026-10-07
- Issue：[#505](https://github.com/XavierOwen/tongxingzhe-app/issues/505)、[#512](https://github.com/XavierOwen/tongxingzhe-app/issues/512)
- Requirement：`ORG-049`、`TEST-139`
- 关联：[ADR-0182](./0182-organization-directory-is-membership-scoped.md)、[ADR-0188](./0188-organization-deletion-and-recovery-execution-contract.md)

删除申请入口只向读取时仍是 current active owner 的账号显示。普通组织目录仍只返回 workspace UUID 与名称；独立资格读取只返回未删除组织的 workspace UUID，不增加普通目录的 owner 标志。这样普通成员不会在服务端拒绝删除申请前先清除本地离线资料。

资格读取以 exact verified issuer／subject、active 账号、同一数据库快照和一个 observation clock 检验组织成员与 owner 的半开有效区间。workspace 必须未删除，lifecycle current 必须不存在或为 `restored`；没有项目的组织也可返回。active 账号没有合格组织时返回空列表，身份无法映射时统一 forbidden。读取不写 audit、不取请求锁、不建立身份；runtime 只有窄 reader 的 EXECUTE。UUID 完整返回并排序，不预设截断或分页。

HTTP 为 `GET /v1/organizations/deletion-eligibility`，不接受 query 或 body。成功只返回 `organization_deletion_eligibility_contract_id: "organization-deletion-eligibility:v1"` 与 `organization_workspace_ids`。Flutter 把它与当前普通目录按 UUID 取交集，只为交集中的组织显示删除入口；读取失败时隐藏入口并允许重新读取。资格只控制显示，POST 仍在锁后重验 current owner、组织状态与 request UUID。撤权后过期的入口不能使删除成功；提交前本地离线资料清理和结果不确定时固定请求重试沿用既有删除申请合同。
