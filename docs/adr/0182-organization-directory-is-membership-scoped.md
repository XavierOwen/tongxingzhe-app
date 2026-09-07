# ADR-0182：我的组织目录按当前组织成员关系读取

- 状态：已接受
- 日期：2026-09-06
- Slice：7U
- Issue：[#332](https://github.com/XavierOwen/tongxingzhe-app/issues/332)
- 依赖：[ADR-0175](./0175-organization-creation-is-atomic-with-first-active-owner.md)、[ADR-0176](./0176-organization-creation-http-contract.md)、0084、0087
- Requirement：`AUTHZ-001`、`AUTHZ-003`、`AUTHZ-004`、`ORG-018`、`TEST-071`、`MANUAL-061`

## 背景

组织创建只建立 workspace、organization membership 和首位 owner，不创建 project。
当前项目上下文和管理分析目录都需要项目证据，不能表示尚无项目的组织。
让新组织自动进入任一项目列表，会把组织成员关系错误地当成项目授权。

## 决定

新增独立的“我的组织目录”，只读当前 active 账号具有有效成员关系的未删除 organization workspace，包含尚无项目的组织。
不要求 owner、project membership 或 capability，不显示个人 workspace、其他账号的组织和恢复期组织。
有效账号的空列表返回成功，不把“没有组织”变成身份错误。

0089 的 `app_data.list_organizations_for_identity_v1(text,text)` 使用 exact trusted issuer／subject，不 normalize、bootstrap 或复用创建资格查询。
原值长度限制和 ASCII-space 空值检查在查询前执行；无效输入为 22023，无法解析 active app user 为统一 42501。
函数用一个 `clock_timestamp()` 和同一查询快照检验用户、成员半开区间与组织状态，只返回 workspace UUID 和原名称。
按名称 `COLLATE "C"`、UUID 排序。同名组织保持独立，不新增名称唯一性要求。
函数继承既有可信 owner，SECURITY DEFINER、固定 search_path，显式撤销 PUBLIC 函数权限，runtime 只获 EXECUTE；不增加底表权限、角色、表、写入或 audit。

读取不是锁定资格。响应后成员关系仍可变化，后续受保护操作必须重新授权。
本目录不是组织恢复入口；恢复期数据可保留但不因此出现在当前有效成员目录中。

HTTP 使用 `GET /v1/organizations`，明确取代 ADR-0176 在只有创建操作时的 GET 404；POST 保持原合同。
canonical raw path 先于认证匹配，非法路径不经 URL normalization 落入其他操作。
有效 GET 先验证 Bearer 与 generic identity，再拒绝 query（包括裸 `?`）或声明 body，再检查 store 并等待一次参数化 reader。
复用现有无 GET body 检查，不读 body、不执行 7A Auth user lookup，也不获取当前项目上下文。

200 root 固定为 `organization_directory_contract_id: "organization-directory:v1"` 与 `organizations` 数组。
每项只有 `organization_workspace_id`、`organization_name`。strict parser 拒绝错误字段、类型、非 canonical UUID、ASCII-space 空名称和重复 UUID。
名称保持数据库原文，不能用创建 validator 拒绝历史上已合法保存的组织名。
所有响应 JSON UTF-8、no-store；固定错误为 400 invalid request、401 unauthenticated、403 forbidden、503 unavailable，具体 wire code 见 Product Spec 7U。
身份、SQL、异常和目录内容不进入响应错误或日志。

## 取舍与边界

不复用项目或管理分析目录，因为那会排除 projectless 组织或混淆权限。
不增加 owner flag、成员数、能力或恢复状态，这些都需要独立授权与合同。
v1 完整读取账号自己的组织，不设任意截断。若实测单账号目录大小影响延迟，再定义带稳定排序的 cursor 合同；当前不预造分页、搜索或缓存。

结构 check、回滚 fixture、Backend unit／真实本地 HTTP／composition／runtime integration 与 Docker restore 验证实现。
它们证明 synthetic 数据库与 transport 边界，不证明生产认证、部署服务、真实组织或真人平台。
本切片不实现 Flutter、UI、组织项目、上下文切换、账号目录、成员治理或生命周期 API。
