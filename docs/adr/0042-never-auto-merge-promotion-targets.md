# 推广对象只在同一空间内人工合并

## 决定

系统可以在同一空间内提示疑似重复推广对象，但绝不自动合并。不同空间之间不检测、不提示也不合并。

个人空间 v1 只比较当前账号可见、仍获分配、未到期、active 且 `target_type` 相同的对象。候选信号只接受去除首尾空白后完全相同的非空电话，或去除首尾空白后不区分大小写的非空 email。名称不参与匹配，候选提示也不证明两个对象属于同一主体。

预览和确认同时要求 `view_assigned_target_pii` 与独立的 `manage_assigned_target_merges`。Backend 与 PostgreSQL 每次重验 exact identity、active personal workspace owner、两项 capability 和两端 active assignment。客户端 capability、对象 ID 或预览 receipt 都不授权。

预览返回不含 PII 的 opaque receipt，并显示两个成员的保留截止、较早的合并截止和到期后两端匿名化后果。服务端把 receipt 绑定到两个对象、当时字段、状态、assignment、保留截止、候选信号和数据库时间。receipt 只在数据库预览时间起连续 15 分钟的半开区间内有效。确认时任何绑定事实漂移或任一成员已经到期都失败关闭。

一次 active merge 只包含两个尚未参加其他 active merge 的同类型对象。使用者指定保留对象，并为 `display_name`、`phone` 和 `email` 分别选择其中一个原对象的现有值或原有 `null`。相同值也保留明确来源。合并不接受自由编辑、链式合并、嵌套合并或三方合并。

## 后果

合并只建立受审计关系和合并视图。两个原对象及双方字段来源、assignment、项目关系、接触关联和个人与机构关系继续保留。组织空间、模糊匹配和超过两个对象的合并需要新的决定。
