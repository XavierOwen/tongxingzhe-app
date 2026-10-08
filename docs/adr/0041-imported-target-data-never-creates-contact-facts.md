# 导入推广对象资料不生成接触事实

## 决定

系统可以通过 CSV 批量导入推广对象，并为未来外部 CRM API 保留独立边界。导入只建立推广对象和导入者的初始分配，不生成接触记录、单次兴趣、对象反应、关系阶段、后续联系同意或其他关系事实。

CSV v1 只向当前可信账号拥有的个人空间开放。数据库根据 active app user 的个人空间 owner 事实派生 `import_target_pii`，Backend 检查该 capability，确认 writer 再根据可信 exact identity 重验 owner 事实。客户端上下文字符串和 preview receipt 都不授权。未来组织空间必须另行定义 capability grant 和跨成员分配，不从个人空间 owner 规则推导。

文件只接受有界 UTF-8 四列合同，并按 RFC 4180 解码。预览先校验每行，并用同空间去除首尾空白后完全相同的电话，或去除首尾空白后不区分大小写的 email 提示疑似重复。名称不参与匹配，也不检查其他空间。提示不会自动合并、覆盖或更新；使用者只能排除该行或明确建立独立对象。提示是事务时点的 best-effort 结果，不是唯一性约束。

预览返回 opaque receipt，绑定规范化完整行集、行序和当时提示。receipt 从数据库 UTC 预览时间起连续 15 分钟有效，期限为半开区间。确认必须引用该 receipt；无提示行只接受 `skip`／`create`，提示行只接受 `skip`／`create_separate`。确认重新运行授权、行校验和重复检查。receipt 过期或任何行、行序、提示漂移都失败关闭。首次确认在单一事务中建立全部已选对象、初始分配和审计；任一失败使整批回滚。一个 import request UUID 固定 receipt、规范化行序和完整选择；精确重放返回首次确认结果，载荷漂移发生冲突。

预览和确认都追加 value-free 审计。审计只记录操作者、目标空间、request／preview ID、阶段、结果、计数、`source_kind = csv` 和数据库时间。原文件名、CSV 内容、字段值和错误行不进入审计、日志或错误。

## 后果

CSV parser、数据库 writer、Backend 路由和 Flutter 预览顺序实现。组织空间、CRM、模糊匹配、自动合并、更新既有对象和部分成功都不在 v1 中。
