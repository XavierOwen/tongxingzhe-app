# 同行者

同行者服务于推广活动的记录、协作与分析。产品保持场景中立，可用于课程、产品、服务、公益或信仰内容的推广，不把任何一种场景或接触渠道当作唯一用途。

## Language

**推广**:
个人或团队接触潜在对象，并介绍产品、课程、服务、公益或信仰内容的通用活动。
_Avoid_: 福音外展（作为总称）、销售（作为总称）

**接触**:
推广者通过任意渠道与推广对象发生的直接互动；没有直接互动的广告投放、资料准备或通勤不属于接触。
_Avoid_: 线下接触（作为总称）、曝光、准备工作

**接触尝试**:
针对明确个人或小组发出、但尚未获得任何回应或实际互动的直接联络行动；它不是接触，不产生触达人数、单次兴趣或关系阶段变化。
_Avoid_: 未接通的接触、广告曝光、群发宣传、接触记录

**渠道类别**:
每条接触记录或接触尝试必须且只能选择的全平台稳定渠道分类：面对面、语音通话、视频通话、即时文字互动、异步消息、混合渠道或其他直接渠道。
_Avoid_: 项目自定义总类、同一记录重复计入多个渠道、平台品牌

**渠道明细**:
项目在稳定渠道类别下配置的可选具体方式或平台，例如 WhatsApp、Zoom、电话外呼或校园摊位；它用于项目内分析，不改变全平台渠道类别的语义。
_Avoid_: 渠道类别、跨项目默认可比维度、自由改写总类

**推广对象**:
推广活动中需要后续跟进、类型明确为个人或机构的主体；在对方愿意留下可识别信息时按需建立，归一个个人空间或组织所有，并可在该空间内关联多个项目的接触。
_Avoid_: 客户、被推广者

**推广对象类型**:
推广对象是自然人的“个人”或是学校、商店、公司等外部实体的“机构”；机构推广对象不等于 App 内用来协作的组织。
_Avoid_: 组织成员类型、触达人数、自动创建协作组织

**个人—机构关系**:
同一空间内个人推广对象与机构推广对象之间、可以多对多并保留历史的明确联系；它可记录关系类型、角色说明与有效时间，但不授予对象访问权或 App 组织成员资格。
_Avoid_: 所属机构字段、协作组织成员、对象所有权、自动授权

**机构关系性质**:
每条个人—机构关系必须选择的一种稳定分类：任职／代表、所有／治理、学习／参与、成员／归属、合作／服务或其他；具体职务或身份由可选角色说明表达。
_Avoid_: 关系阶段、项目决策角色、自由文本总类、一条关系多种性质

**推广对象资料**:
集中保存于推广对象上的姓名、联系方式等可识别信息；接触记录只引用推广对象，不复制这些资料。
_Avoid_: 接触字段、统计事实

**后续联系同意**:
推广对象在一次接触中明确表示愿意就当前项目继续被联系的结构化事实；它不能由数据库中已有电话、邮箱或其他可识别资料自动推断。
现有记录中没有主动选择的默认状态只表示未回答，不能证明“未知”是使用者明确作出的判断。
_Avoid_: 已有联系方式、默认同意、永久同意、未回答即未知

**后续联系同意占比**:
项目明确启用后才存在的分析指标：分子是明确记录后续联系同意的有效接触对象关联，分母是适用且已明确回答是或否的有效接触对象关联；未回答、拒绝回答与不适用须分开报告。同一接触关联多个对象时，各对象分别形成统计单位，不能把场次层面的问卷答案当成对象同意。项目未启用时，该指标处于独立的 `not_enabled` 状态，不表示 0% 或覆盖为空。
_Avoid_: 联系方式率、接触率、资料完整率

**后续联系同意占比开关**:
个人项目所有者明确允许或停止读取后续联系同意占比的可审计当前配置；每次变更追加版本并使用预期版本和幂等请求 ID。它不是接触对象的同意，也不按配置时间裁切统计期间。
_Avoid_: 对象同意、客户端本地偏好、组织权限、历史生效区间

**推广对象资料导出**:
把多名推广对象的可识别资料带出 App 的受控行为；普通查看权不包含该能力，导出范围不能超过操作者原本可查看的对象。
_Avoid_: 匿名统计导出、复制单项联系方式、默认管理员权限

**固定匿名管理报告文件导出**:
把一份已经发布且具有可信 v2 来源的固定匿名管理报告快照，以版本化 canonical JSON v1 从受控服务端生成并准备交付的行为；它同时要求 `view_anonymous_analytics` 与 `export_management_reports`，只携带已经抑制的匿名结果，不表示客户端已经落盘或分享。
_Avoid_: 推广对象资料导出、动态重算、CSV 文件、客户端保存证明

**管理报告导出 artifact**:
Flutter 对固定导出响应的头、事件 ID、目录摘要、报告合同和 canonical UTF-8 原始字节全部验证后，保留在内存中的 typed 结果；它是后续平台交付的输入，不表示浏览器已下载、文件已保存或系统已分享。
_Avoid_: 本地报告缓存、重新序列化、文件保存结果、分享结果

**Web 管理报告下载请求**:
用户在已验证的管理报告导出 artifact 准备完成后，以新的明确操作把原始字节、固定 MIME 和文件名交给浏览器的行为；客户端最多知道浏览器已接收请求，不知道文件是否已保存、打开或保留。
_Avoid_: 下载成功、原生文件保存、系统分享、服务端导出审计结果

**推广对象资料导入**:
从 CSV 或外部系统把已有对象资料受控地加入指定空间的行为；它只建立推广对象，不能据此生成接触记录、单次兴趣或关系进展。
_Avoid_: 接触导入、批量制造接触事实

**疑似重复对象**:
同一空间内因联系方式等信号而可能代表同一主体的两个推广对象；它只是需要人工判断的提示，不能自动改变或合并资料。
_Avoid_: 已确认同一人、跨空间匹配

**推广对象合并**:
有权查看两个疑似重复对象的人确认其属于同一主体后，把它们归为一个可用对象的受审计关系；原对象及双方来源、项目关系和接触关联继续保留，以便撤销。
_Avoid_: 自动去重、跨空间合并、覆盖来源、物理删除原对象

**推广对象拆分**:
撤销一次错误推广对象合并的受审计行为；合并前的数据按原来源恢复，合并后新增且归属不明确的数据必须人工分配。
_Avoid_: 删除合并结果、丢弃合并后数据

**跟进者**:
被明确分配处理某个推广对象的当前组织成员；创建者只是在创建时自动成为首位跟进者，取消分配或退出组织后即失去资料访问权。
_Avoid_: 项目管理员、全体项目成员

**离线跟进资料**:
当前跟进者为无网络场景临时保存在自己设备上的已分配推广对象资料；它不包含整个组织的对象目录，并在跟进分配或访问资格结束时失效。
_Avoid_: 组织通讯录、永久本地副本、匿名接触事实

**离线授权期限**:
敏感离线跟进资料自最近一次成功联网校验访问资格起可使用的七十二小时时段；期限届满后必须重新联网确认，匿名接触记录的离线填写不受此期限限制。
_Avoid_: 登录有效期、永久离线访问

**推广对象匿名化**:
移除推广对象可识别资料、使既有接触继续作为匿名行动事实保留的处理。
_Avoid_: 删除接触历史、隐藏姓名

**推广对象资料保留期**:
可识别资料只在项目关系活跃且仍有明确跟进目的时保留；对方明确退出时立即匿名化，连续十二个月没有接触则必须复核，未明确续期即匿名化。组织可以采用更短期限，但不得无限期静默保留。
_Avoid_: 永久保存、接触记录保留期

**项目关系**:
一个推广对象与某个推广项目之间独立的长期关系与跟进状态；同一对象在其他项目中的状态不能由此推断。
_Avoid_: 推广对象全局状态、单次兴趣

**单次兴趣**:
对一次接触场次整体当下可观察反应的必填全平台五级核心事实，底层固定存为 `0–4`：`0` 明确拒绝，`1` 互动但无继续意愿，`2` 中性或无法判断，`3` 明确愿意继续，`4` 主动提出或落实下一步。项目可以配置符合各级固定含义的显示名称，但不能改变含义或方向。
_Avoid_: 对象当次反应、项目自定义量表、关系阶段

**对象当次反应**:
对一个已识别推广对象在某次接触中当下反应的可选五级事实；它依附于接触对象关联、使用与单次兴趣相同的 `0–4` 固定语义，但不代表整个场次。机构只有在参与者明确代表该机构表态时才能拥有此反应。
_Avoid_: 对象关系阶段、从场次兴趣推断的个人反应、必填逐人评分

**对象当次反应分布**:
个人分析中，按有效接触当前 revision 的每条已填写对象关联分别统计 `0–4`；同一接触可以贡献多个关联事实。`NULL` 是未填写，不进入五档分母，也不等于等级 `2`，但必须以未填写覆盖数单独呈现。
_Avoid_: 按接触场次计数、按对象去重、把未填写归为中性、关系阶段分布

**对象当次反应中位等级**:
把对象当次反应分布中的已填关联按 `0–4` 排序后取中间等级。偶数关联使用两个中间观察值中较低的真实等级；没有已填关联时没有中位等级。`NULL` 只表示未填覆盖，不进入中位分母。
_Avoid_: 对象反应平均数、把偶数中间等级取平均、把未填写归为等级 `2`、关系阶段

**对象当次反应等级比例**:
`target_response_level_ratios@1` 个人指标中，每个 `0–4` 等级的已填对象关联数除以同一期间全部已填对象关联数。五个分子必须穷尽共同分母；`NULL` 不进入分子或分母，只作为未填写覆盖单独报告。权威值是整数分子、分母和按 half-up 规则计算的百分比基点；空分母保留 `0 / 0`，不显示 `0%`。
_Avoid_: 按接触场次计数、把未填写归为等级 `2`、浮点权威值、空样本 `0%`

**兴趣算术指数**:
把单次兴趣 `0–4` 暂时假设为等距后计算的算术平均值；它只是带数学警示的高级分析指标，不能取代各等级分布、比例和中位等级。
_Avoid_: 平均兴趣度、整体兴趣结论

**兴趣中位等级**:
把有效接触的单次兴趣按 `0–4` 排序后取得的中间等级；偶数场次使用两个中间观察值中较低的真实等级，空期间没有中位等级。它只使用顺序，不假设等级间距相等。
_Avoid_: 兴趣平均数、偶数样本中间等级的算术平均、空期间的 `0` 级

**兴趣等级比例**:
个人分析中某一兴趣等级的有效接触场次数除以同一期间全部有效接触场次。权威值是整数分子和分母；百分比使用整数基点，空分母没有百分比。核心兴趣只能是非空 `0–4`，因此缺失状态为零，但这不表示草稿、尝试和作废记录已被逐条盘点。
_Avoid_: 浮点权威值、空样本 `0%`、生命周期排除盘点、兴趣算术指数

**兴趣 3–4 与 0 占比**:
从同一期间的有效接触场次派生的两个独立子集比例：`3–4` 的分子是明确愿意继续或主动提出／落实下一步的场次，`0` 的分子是明确拒绝的场次。两者共享全部有效接触场次分母，但不会穷尽兴趣 `1–2`，因此不要求两个分子相加等于分母。
_Avoid_: 三档兴趣分布、两个分子必须穷尽分母、兴趣算术指数

**关系阶段**:
推广对象在某个推广项目中的长期关系进展，使用全平台五级 `0–4` 量表：`0` 初次建立，`1` 可以联络，`2` 持续互动，`3` 明确推进，`4` 达成项目定义的目标关系；它可以随真实关系上升或下降。项目只能配置符合原含义的显示名称。
_Avoid_: 单次兴趣、项目自定义流程、`0/2/4/6/8` 存储

**当前关系阶段分布**:
个人分析中，在同一当前项目下，按查看者仍在跟进的有效“推广对象 × 项目”关系分别统计 `0–4`；只包含生命周期为 active 的当前关系，paused、ended、匿名化对象和已结束分配不进入五档。它回答当前状态，不回答过去某个期间的状态。
_Avoid_: 接触期间关系阶段、按接触次数计数、暂停关系混入当前跟进、历史阶段回填

**阶段变更**:
项目关系从一个关系阶段转到另一个阶段的可审计事件；它保留原阶段、新阶段、时间、操作者和原因，不以覆盖当前数值代替历史。
_Avoid_: 阶段覆盖、只升不降

**阶段变更事件**:
关系 revision 中 `old_stage` 非空、不同于 `new_stage` 且 `changed_fields` 包含 `stage` 的一次真实阶段改变；个人指标把它按 `changed_at`、可信操作者和可信项目范围计数。初始 `project_entry`、只改 lifecycle／备注和同阶段 revision 都不是阶段变更事件。
_Avoid_: 当前阶段快照、所有关系 revision、重复提交的同一事件

**阶段变更方向**:
阶段变更事件按数值比较固定分为 `upward`（`new_stage > old_stage`）和 `downward`（`new_stage < old_stage`）；两个标签的顺序和含义不能随项目显示名称改变。
_Avoid_: 项目自定义方向、只统计上升、把下降当作错误

**发生过阶段变更的项目关系**:
某个 UTC 半开期间内至少有一条合格阶段变更事件的去重“推广对象 × 推广项目”关系；同一关系的多次事件仍只形成一个关系统计单位。
_Avoid_: 事件条数、当前分配、当前阶段快照

**项目关系状态**:
项目关系是否仍在跟进的生命周期状态；停止跟进、退出或匿名化等状态与 `0–4` 关系阶段分开表达。
_Avoid_: 负数阶段、关系阶段

**跟进备注**:
记录推广对象在某个项目中后续事项的共享自由文本；它只对当前跟进者可见并保留修改历史，不进入匿名分析。
_Avoid_: 个人反思、公共备注

**接触记录**:
对一个实际互动场次的独立记录，用于呈现推广者已经采取的行动；它默认匿名且不复制推广对象资料，即使涉及多人或没有可识别的推广对象，一个场次仍只形成一条接触记录。
_Avoid_: 推广对象、客户档案

**快速记录**:
以核心事实优先、默认匿名和按需展开的方式创建完整接触草稿的高频入口；它不是字段更少、校验更弱或统计地位不同的接触类型。
_Avoid_: 简化接触、临时记录、绕过问卷

**接触对象关联**:
一条接触记录与同一空间内、在所属推广项目中建立项目关系的零个、一个或多个已识别推广对象之间的受审计关联；它不增加接触记录数，未识别参与者只计入触达人数。
_Avoid_: 一接触一对象、未知对象占位档案、跨空间关联

**接触草稿**:
尚未正式提交、创建时固定归属一个推广项目与问卷版本的接触内容；记录者可以修改、明确升级或放弃，草稿不计入接触事实和分析。
_Avoid_: 接触记录、未绑定问卷的表单、已同步记录

**草稿升级**:
记录者把旧问卷版本的接触草稿明确转换到当前问卷版本的行为；只有语义兼容的答案可自动复制，确认完成前保留原草稿。
_Avoid_: 静默迁移、覆盖旧答案、自动填写新必填题

**草稿同步模式**:
记录者为一份接触草稿选择的保存边界：默认只向本人的已登录设备跨设备同步，也可明确限定为仅当前设备；它不改变正式提交后的数据同步。
_Avoid_: 组织共享草稿、管理员可见草稿、停止正式数据同步

**草稿冲突副本**:
同一接触草稿在不同设备上产生不能安全自动合并的分叉时，为防止最后写入覆盖而保留的另一份私有内容；它不会自动成为接触记录或接触修订。
_Avoid_: 最后写入胜出、自动覆盖、正式接触事实

**接触修订**:
对已提交接触记录的追加更正；它保留修改前后、时间、操作者和原因，默认视图显示最新有效值但不覆盖原始历史。
_Avoid_: 直接覆盖、最近十条修改

**接触修订冲突**:
两台设备从同一基础 revision 修改同一事实组时形成的待处理分叉；系统保留服务器与本机快照，由本人选择其中一方或提交手动合并结果。不同事实组的并发更正可以自动合并，不属于冲突。
_Avoid_: 最后写入胜出、静默覆盖、所有过期更正都冲突

**延迟录入**:
接触发生后才在较晚时间首次提交的记录；它同时保留实际发生时间与首次录入时间，按发生时间进入对应目标周期，并明确标示补录状态。
_Avoid_: 录入时间接触、当前周接触

**作废接触**:
被确认不存在、重复或误录而停止生效的已提交接触；它保留最小审计证据，但从正常统计中排除。
_Avoid_: 物理删除、推广对象匿名化

**个人反思**:
记录者对一次接触的私有自由文本，只服务于本人的自我问责；组织成员和管理员不可见，也不进入匿名分析。
_Avoid_: 跟进备注、公共备注

**个人生理信号**:
推广者自愿启用、仅供本人自我观察的健康数据，例如接触时的平均心率；它默认关闭，不属于组织或项目数据。
_Avoid_: 接触结果、推广对象健康数据

**匿名接触**:
没有关联可识别推广对象的接触记录；它是快速记录的默认形态，而不是资料缺失或未完成状态。
_Avoid_: 无效记录、未完成记录

**触达人数**:
一个互动场次中实际直接参与互动的自然人数量；它与接触记录数、个人对象关联数和机构对象关联数分别统计。
_Avoid_: 接触次数、对象关联数、机构数、记录数

**接触地点**:
每次接触对地点的明确说明；地点适用时记录具体线下地点和最小区域，不适用时明确记为 `N/A`，而不是留空。
_Avoid_: 未填写、缺少定位

**接触地点来源**:
说明一个已解析接触地点如何得到的最小证据；坐标解析来源绑定原始坐标、区域解析版本和已发布区域树内容指纹，人工选择或旧记录可以明确保持仅区域来源。
_Avoid_: 当前区域、服务器记录时间、推测的设备采集时间、区域名称

**区域体系**:
全 App 共用的严格层级树；每个区域节点只有一个规范父级，面对面接触最终至少归入城市，并可继续细分为片区、街道、学校、商店或其他地点节点。
_Avoid_: 项目私有区域、平铺地点标签

**最小区域**:
一次面对面接触所能确定的最具体区域节点；接触记录只关联该节点，州、城市和片区等上级区域由父级链推导。
_Avoid_: 完整区域路径、多个重复层级字段

**区域属性**:
对区域节点性质的描述，例如校园或超市；它不充当父级、不形成额外汇总路径，也不改变区域在严格层级树中的位置。
_Avoid_: 区域父级、区域层级

**区域维护者**:
负责审核并维护全 App 规范区域树的平台角色；该职责独立于任何组织，也不因此获得接触记录访问权。
_Avoid_: 项目管理员、全数据管理员

**区域建议**:
组织或项目成员提交的新增区域或边界修正提案；审核通过前不改变规范区域树。
_Avoid_: 区域修改、项目私有区域

**区域别名**:
组织为规范区域节点设置的本地显示名称；它不改变节点身份、边界或父级关系。
_Avoid_: 新区域、规范名称

**区域解析版本**:
一次区域匹配所依据的规范区域树版本；重新解析旧坐标时保留原版本结果，以便解释历史变化。
_Avoid_: 当前区域、覆盖历史

**规范区域跨版本映射证据**:
平台区域维护流程对两个已发布区域树中的一个来源节点和一个目标节点作出的显式一对一对应事实；它绑定两个冻结内容指纹、固定证据合同和证据摘要，只允许精确幂等追加。它不改写原地点来源，也不按名称、父链或几何相似自动推断；拆分、合并、缺失或冲突必须保持不可映射。
_Avoid_: 区域名称匹配、自动边界迁移、current 选择历史、覆盖原解析版本、生产区域报告

**当前区域视图**:
按照调用方明确指定的已发布规范区域树重新解释历史来源的分析视图，用于跨时期比较现行区域；
它不读取 current 选择开关，也不由区域名称、父链或重叠边界猜测归属。
_Avoid_: 原始记录、历史复现、隐式当前版本

**原始区域视图**:
按照接触来源保存的区域解析版本和内容指纹呈现数据的分析视图，用于审计和复现历史报告；来源
release、指纹、节点或城市父链不完整时不能伪造归属。
_Avoid_: 当前区域、重新归类

**区域归属证据解析**:
把一条地点来源按 `original` 或明确指定的 `current` 目标区域树转换为可供报告使用的最小区域 tuple；
坐标只接受唯一最深且同属一条父链的命中，`region-only` 跨版本只接受显式一对一映射，其他缺失或歧义
返回失败关闭或 `not_reportable`。
_Avoid_: current 开关选择、名称匹配、父链猜测、重叠边界裁决、区域报告发布

**历史派生报告截止上下文（history-derived cutoff context）**:
由可信 `data_cutoff_utc` 和追加式区域树选择历史派生的最小区域目标证据；它固定目标树版本、内容指纹、
选择序号、选择来源、证据时间和区域树发布时间，供后续报告把 `current` 视图显式传给 6AL。
它由私有、无 runtime 执行权的 resolver 提供，不是完整报告、快照 lineage 或任意历史查询。
_Avoid_: `is_current`、最新 release、客户端时钟、区域名称猜测

**current 城市接触场次报告候选**:
只在私有数据库边界组合可信截止点、current 目标树、单条地点归属、两个完整 ISO 周和城市完整网格的
固定 `contact_sessions@1` 文档；每条可报告归属只进入唯一城市祖先，格值在返回前完成阈值和互补隐藏。
它保存 source change watermark，但读取的是 current contact projection，不是历史 `as-of`，也尚未接入生产发布链。
_Avoid_: original 区域视图、最小区域下钻、任意区域筛选、生产区域报告、历史重放

**原始区域接触场次报告候选**:
只在私有数据库边界组合已保存的原始区域来源、单一 `source_tree_version + source_content_fingerprint`、两个完整 ISO 周和城市完整网格，形成固定的
`contact_sessions_by_original_region_two_periods@1` 文档。它只使用每条接触来源的 `original` 证据，不读取 current 选择、目标上下文、跨版本 mapping、坐标重新解析或名称／父链猜测；来源树 tuple 混杂、来源缺失或证据不完整时失败关闭，不跨树聚合。
`data_cutoff_utc` 只限定本次报告纳入的已接受事实，不提供任意历史 `as-of` 重建，也不把 cutoff 解释为树版本选择。每个期间先执行 `k=10`、至少三位贡献者和不超过一半的贡献者保护，再按稳定城市顺序执行互补隐藏；返回只含已保护的安全整数或 `suppressed = null`。
这是 DB-only 报告候选，不是 snapshot、授权读取、runtime、HTTP、Flutter、缓存、离线、导出或生产平台证据。
_Avoid_: 混合来源树、current 区域归类、as-of 查询、跨树相减、隐藏值、城市名称猜测、生产报告

**渠道管理报告快照取代登记**:
6BE 在 private PostgreSQL 中登记两份已经具有 6J trusted-v2 provenance 的渠道管理报告快照之间的直接 replacement 关系。两份快照必须属于同一项目、report ID、version、query fingerprint、
reporting time zone 和 release lineage；新快照的 `data_cutoff_utc` 与发布时间必须晚于旧快照。登记只引用已存在的快照，不生成 snapshot、release attempt 或报告正文。
登记原因只允许 `late_accepted_data`、`contact_revision` 和 `contact_void`。分析定义修正和跨版本取代留给后续独立合同。
每份旧快照最多有一个直接替代者，每份新快照最多替代一份旧快照；关系可以形成严格向前的链，但不能自链接、分叉或循环，只有当前链头可以继续被取代。
登记在取得会等待的锁后重新确认 `release_management_reports` 和 trusted-v2 provenance。相同 request UUID 与 canonical payload 精确幂等，载荷漂移、跨项目、current-city、interest、legacy、blocked 或未知来源失败关闭。
生命周期查询对可信渠道快照只返回快照 ID、`active`／`superseded` 状态和直接 replacement snapshot ID；未知或不可信来源返回 value-free `not_found`。
它不返回报告正文、cells、隐藏前值、来源、贡献者、地点、授权关系或 PII。
关系和最小审计证据追加不可变，不允许 UPDATE 或 DELETE。
_Avoid_: 生成新快照、静默改写旧快照、自动选择 latest、跨 report family 复用 lineage、把取代登记当作删除、tombstone 或 retention 策略

**current 城市报告受保护快照**:
由 6AN 固定定义、两个完整 ISO 周、完整城市网格、目标树 tuple、可信报告时区 revision、数据截止时间和
source change watermark 组成的不可变私有报告文档；它只能在 `release_management_reports` 能力和可信时区上下文重新确认后建立，
不能由调用方提交 JSON、时区、截止点或目标树 tuple。它可以复用通用不可变快照存储，但不是既有渠道 v2
快照，也不是历史 `as-of`、读取、目录或导出能力。6AO validator 和 pair comparison 固定 report、metric、
dimension、view、granularity、query fingerprint、privacy、source scope、期间、watermark、target context 和
完整 cells；unavailable、额外字段、错误 identity、错误 target tuple、期间或网格均失败关闭。
_Avoid_: 渠道 16 格、客户端快照、任意历史重放、生产 HTTP、UI、调度

**区域报告发布 lineage**:
围绕一份 current 城市报告受保护快照保存的、区域专属发布尝试和来源证据序列；它绑定 `release_management_reports`、可信项目
报告时区 revision、固定数据截止时间、目标树 tuple、6AN 定义和隐私网格。首个成功文档建立基线，后续
尝试必须保持共享期间的城市值和隐私状态不变，并把成功发布链接到前一 snapshot。相同 request 和固定上下文
必须精确幂等，不新增 snapshot 或 attempt。current-city 与渠道发布不能复用 request UUID；trusted v2 与其
委托的 v1 记录仍属于同一渠道发布。same／earlier cutoff、无共享期间、共享值或隐私状态变化，以及
target tuple、时区 revision、定义、期间或网格上下文漂移，都返回稳定 blocked reason。blocked attempt 只保留
原因、固定 identity 和最小 lineage，不保存 protected document、cells、来源、贡献者、隐藏前值或 PII。
snapshot 与 attempt 均为追加不可变记录，不允许 UPDATE 或 DELETE；runtime、`PUBLIC` 和区域维护身份不能执行、
读取区域 provenance 或直接写表。它不等于渠道 v2 provenance，也不授予读取、目录或导出权。
_Avoid_: 复用渠道 lineage、绕过 release capability、值带入失败记录、HTTP/UI 发布、warehouse、retention

**迁移基线观察下界**:
0038 迁移为既有 current release 写入的基线观察只有 `recorded_at_utc`；它的 `selected_at_utc` 为 `NULL`，
不能解释成真实选择时间。只有不早于该观察时间的报告截止点，才能把基线作为已观察证据；更早截止点必须返回
历史不可用，不能伪造目标树 tuple。
_Avoid_: 把观察时间当选择时间、把迁移时刻回填成历史 current

**区域树发布共享事务锁**:
区域树发布和历史派生截止 resolver 共用同一事务 advisory lock；resolver 虽然只读，仍需在锁内线性化，
不能看到未提交的选择历史或与发布提交顺序相矛盾的上下文。
_Avoid_: 绕过发布锁、读取未提交选择、用 current 投影替代历史

**待解析区域**:
面对面接触已经保存经纬度、但尚未完成区域匹配的暂时状态；它必须最终解析到至少城市，既不是有效的最终归属，也不同于非线下接触的 `N/A`。
_Avoid_: `N/A`、无法识别区域

**核心事实**:
所有推广场景共同拥有、不会随问卷变化而改变含义的接触信息，例如时间、渠道、接触地点、触达人数和单次兴趣。
_Avoid_: 自定义问题、场景选项

**场景问卷**:
为某个推广项目配置的一组补充问题；它扩展接触记录，但不改变核心事实的含义。
_Avoid_: 核心字段、写死表单

**问卷题型**:
决定场景问题的答案结构、验证规则与可用统计方法的受控分类；选项是否有顺序属于题型语义，不能仅从显示顺序推断。
_Avoid_: 界面控件、全部按文本保存、任意 JSON

**问卷显示规则**:
根据同一问卷版本中较早问题的答案，判定后续问题当次是否适用的版本化声明规则；它不是权限控制，也不能执行任意代码。
_Avoid_: 隐藏即授权、跳题脚本、循环依赖

**问卷回答状态**:
表明一道场景问题是已回答、未知或无法判断、拒绝回答、不适用还是未回答的明确状态；它与真实答案值分开，规则跳过是系统判定不适用的原因。
_Avoid_: 空字符串、哨兵值、把“否”当作未回答

**问卷草稿**:
尚未发布、可以继续编辑与预览的场景问卷定义；它不接收接触回答，也不改变当前统计解释。
_Avoid_: 接触草稿、当前问卷版本、未完成回答

**当前问卷版本**:
某个推广项目当前唯一用于新建接触草稿的已发布问卷版本；它的“当前”地位不覆盖历史版本及其回答。
_Avoid_: 可编辑问卷、最新文字、覆盖历史

**问卷版本**:
场景问卷一次发布后形成的固定解释版本；历史接触记录始终引用填写当时的版本。
_Avoid_: 当前问卷、可变历史

**问卷指标**:
场景问卷中用于跨版本分析的稳定概念；它拥有不随显示文字改变的标识和版本化定义，只接收被明确确认为语义兼容的问题版本。
_Avoid_: 问题文字、同名问题

**语义兼容**:
两个问题版本在含义、选项、时间范围和回答方式上足以支持合并统计的明确关系；它不能根据文字相似或选项同名自动推断。
_Avoid_: 自动匹配、相似问题、默认兼容

**指标目录**:
集中列明每个正式分析指标的稳定标识、名称、统计单位、分子与分母、时间口径、隐私规则和版本的权威注册表。
_Avoid_: 页面内公式、未版本化统计、SQL 文件名

**指标版本**:
一个正式指标不可变的某次解释定义；定义含义改变时创建新版本，报告快照始终引用生成时使用的版本。
_Avoid_: 当前公式、静默覆盖、App 版本

**平台核心指标**:
由全平台统一定义并随正式代码审查、测试和发布的指标，例如接触场次、触达人数、单次兴趣和关系阶段；项目不能改变其核心含义。
_Avoid_: 项目自定义核心口径、问卷指标

**项目配置指标**:
项目基于已发布场景问卷，使用受验证的统计操作组合而成的版本化指标；它可配置分子、分母和缺失处理，但不允许通过 App 执行任意 SQL。
_Avoid_: 平台核心指标、自由 SQL、未发布公式

**组织**:
共同管理成员、权限和推广项目的协作边界；一个组织可以同时拥有多个推广项目。
_Avoid_: 推广项目、团队

**个人空间**:
系统为每个用户账号提供的私有协作边界；它让用户无需组织邀请即可创建个人推广项目，且其中数据默认只对本人可见。
_Avoid_: 正式组织、个人账号

**外部身份**:
认证商已经验证、由签发者与主体共同确定的登录身份；它只证明当前请求来自该身份，不能直接充当 App 内部用户标识、成员关系或权限。
_Avoid_: 用户权限、内部用户标识、单独使用主体标识

**内部用户标识**:
同行者为用户账号生成的稳定、不透明标识；一个外部身份经可信映射后指向它，业务归属、成员关系与审计都引用它而不引用认证商主体。
_Avoid_: Supabase 用户 ID、外部主体、邮箱、全局角色

**可信当前用户**:
Backend 从已验证外部身份取得、并在数据库重新授权的当前 `app_user_id`；个人阶段变更指标只接受 revision 的 `changed_by_app_user_id` 等于这个标识，客户端不能提交或替换操作者。
_Avoid_: 请求体中的用户 ID、历史分配者、认证商主体

**用户账号**:
代表一个自然人的登录身份；它独立于任何组织或角色，同一账号可以加入多个组织和推广项目。
_Avoid_: 组织成员、管理员账号

**账号删除**:
用户终止登录身份与个人空间的处理；三十天恢复期后清除身份资料、个人数据和全部成员关系，而组织拥有的历史事实继续以不可反查身份的“已删除成员”保留。唯一组织所有者必须先转让所有权或删除组织。
_Avoid_: 退出登录、退出组织、组织删除

**成员关系**:
用户账号与组织或推广项目之间各自独立的归属关系；组织成员关系不自动产生任何项目成员关系，角色和权限分别属于对应关系。
_Avoid_: 用户账号、全局角色、全组织项目通行权

**组织加入**:
用户通过有效邀请或获批准的加入申请成为组织成员；组织默认私有，不能仅凭搜索结果直接自助加入。
_Avoid_: 公开自助加入、注册即入组

**定向邀请**:
组织发给指定邮箱或用户账号的一次性入组凭证，有效期为七天；只有预定接收者接受后才建立成员关系。
_Avoid_: 通用邀请码、永久链接

**加入链接**:
可以转发的组织入口，只用于发起加入申请；持有链接本身不授予成员关系或组织数据访问权。
_Avoid_: 自动入组链接、定向邀请

**项目成员**:
被明确分配到某个推广项目的用户；新项目成员默认拥有推广者能力，项目管理员等更高能力必须另外明确授予。
_Avoid_: 全体组织成员、默认项目管理员

**推广者**:
在推广项目中实际发生接触并记录自己行动的成员；可以查看自己的完整记录与自我分析。
_Avoid_: 普通用户、低权限用户

**项目管理员**:
负责配置推广项目与场景问卷、查看匿名分析并处理去身份化异常的成员；该角色本身不授予个人明细访问权。
_Avoid_: 城市管理员、数据所有者

**组织所有者**:
负责组织成员与推广项目治理的成员；所有权不意味着可以查看成员或推广对象的个人明细。
_Avoid_: 超级管理员、全数据管理员

**组织所有权转让**:
现有组织所有者把所有者职责明确交给另一位有效组织成员的行为；组织任何时候都必须至少有一位有效所有者。
_Avoid_: 自动继承、无人组织

**组织删除**:
对整个组织协作空间及其拥有数据的终止处理；申请后有三十天可恢复只读期，期满后清除组织拥有的业务数据，只保留不含业务内容的最小删除审计。个人空间原始记录不受影响，历史贡献副本随组织清除。
_Avoid_: 作废接触、删除用户账号

**成员能力**:
成员关系中被明确授予的一项操作权限；角色只是常用成员能力的组合，不能通过数字高低推导权限。
_Avoid_: 权限等级、`roleLevel`

**管理分析查看能力**:
项目成员被明确授予的 `view_anonymous_analytics` 能力；它只允许在完整成员授权链内读取已经执行隐私保护的管理分析，不允许发布报告、查看个人明细或取得组织治理权。
_Avoid_: 项目管理员角色、管理报告发布能力、个人资料查看权

**管理报告导出能力**:
项目成员被明确授予的 `export_management_reports` 能力；它只允许在完整成员授权链内生成并准备交付固定匿名管理报告文件，且必须与 `view_anonymous_analytics` 同时有效，不自动取得发布、个人明细或推广对象资料权限。
_Avoid_: `export_target_pii`、管理报告发布能力、项目管理员角色

**管理报告发布能力**:
项目成员被明确授予的 `release_management_reports` 能力；它允许未来的可信服务端流程尝试发布正式管理报告，但不自动允许查看报告内容、个人明细或管理成员。
_Avoid_: 管理分析查看能力、项目管理员角色、报告读取权

**推广项目**:
组织内一项具体的推广工作；它拥有自己的场景问卷版本和分析口径，每条接触记录只归属于一个推广项目。
_Avoid_: 组织、问卷

**当前项目上下文**:
用户当前明确选中的“个人空间或组织 + 推广项目”操作边界；它在界面中持续可见，决定默认记录、推广对象、个人计划、分析与项目设置的范围。
_Avoid_: 当前组织、全局团队、隐式上次项目

**记录归属**:
接触记录创建时确定的空间与推广项目归属；它不会因用户后来加入组织或切换项目而自动改变。
_Avoid_: 当前空间、自动迁移

**历史贡献**:
用户主动把个人空间中的历史接触以去身份化副本贡献给组织项目的行为；个人原记录保持不变，并保留贡献审计。
_Avoid_: 自动同步、搬移原记录

**自我问责**:
使用者如实回顾自己的实际推广行动，从而发现行动与个人承诺之间的差距；它只服务于自我提醒，不是组织对个人的考核。
_Avoid_: 绩效考核、排名

**个人行动计划**:
用户针对某个推广项目私下设定的行动安排；提醒时间可以自由设置，每周接触场次目标可以选择启用或不启用，组织不能强制设定或查看完成情况。
_Avoid_: 团队指标、管理员任务、公开目标

**每周接触场次目标**:
用户为自己在某个推广项目中可选设置的一周接触记录数量目标；只有有效的已提交接触记录计数，触达人数、兴趣度、关系阶段和结果不能代替接触场次。
_Avoid_: 触达人数目标、转化目标、团队配额

**统计时区**:
个人行动计划用于划分每周目标周期的固定时区，默认取创建计划时的所在地；旅行不会自动改变，用户修改后只影响下一个周期，不重算历史周报。
_Avoid_: 当前设备时区、接触地点时区、当地时间提醒

**项目报告时区**:
推广项目用于统一划分管理分析日、周和月边界的固定 IANA 时区；它不跟随查看者设备，且每份已生成报告保留当时采用的时区。
_Avoid_: 查看者时区、设备当前时区、个人计划统计时区

**接触当地时间**:
接触发生时推广者所在地的本地钟点及 IANA 时区；即使线上接触的接触地点为 `N/A`，它仍作为按小时行为分析的默认时间口径。
_Avoid_: 推广对象时区、项目报告时间、录入时间

**周期起始日**:
个人行动计划中每个七天目标周期从星期几开始的用户选择；默认跟随系统地区习惯，任意星期均可选择，修改只影响下一个周期。
_Avoid_: 全平台固定星期一、修改历史周报

**计划差距**:
用户的可选每周接触场次目标与当周有效接触场次之间的私有事实差额；它用于提示下一步行动，不要求解释、不产生惩罚，也不向组织披露。
_Avoid_: 绩效差距、失败记录、连续打卡中断

**隐私通知**:
设备锁屏或系统通知区默认显示的通用提醒，不包含项目或推广对象信息；用户可以主动允许显示项目名称与个人进度，但推广对象资料始终禁止出现。
_Avoid_: 详细锁屏通知、推广对象提醒

**提醒设备**:
用户明确启用系统通知的一台登录设备；个人行动计划在所有设备间同步，但新设备不会自动成为提醒设备。
_Avoid_: 所有登录设备、计划所属设备

**当地时间提醒**:
按提醒设备当前所在地的本地钟点触发的个人提醒；用户跨时区后仍在所设定的当地时间收到提醒，同时保留每次实际触发的时区。
_Avoid_: 固定 UTC 提醒、原时区提醒

**动态分析**:
始终按当前有效数据与当前分析定义重新计算的查询视图；补录、修订或作废会改变它的历史期间结果。
_Avoid_: 正式报告、不变快照

**UTC 半开期间**:
由 UTC `from` 和 `until` 定义的 `[from, until)` 时间范围；包含等于 `from` 的 `changed_at`，不包含等于 `until` 的 `changed_at`，相邻期间不会重复计数。
_Avoid_: 本地设备时区、闭区间、按录入时间切段

**数据截止时间**:
一份分析或报告确定已纳入服务器接受数据的最新时间边界；它说明结果包含到哪里，不等于页面最后打开或刷新的时间。
_Avoid_: 页面刷新时间、当前时间、未同步数据截止时间

**当前快照时刻**:
动态状态查询在同一一致性读取中判断“当前”的 UTC 时刻；它不接受使用者选择，也不表示系统能够重建该时刻以前的历史状态。
_Avoid_: 历史查询截止时间、数据截止时间、接触发生时间

**报告快照**:
在明确数据截止时间和计算定义下生成的可复现正式报告；后续数据变化不静默覆盖它。
_Avoid_: 实时看板、随数据漂移的导出

**受保护快照读取**:
具有管理分析查看能力的项目成员，在数据库重新确认完整授权链后读取一份属于该项目、且具有可信 v2 发布来源的不可变受保护报告快照；每次已授权尝试与不含格值的访问审计在同一事务中提交。
_Avoid_: 动态重算、跨项目探测、发布即查看、客户端授权 token

**管理报告快照读取端点**:
自有 HTTPS Backend 中按显式项目和快照 ID 读取一份受保护快照的窄入口；Backend 只传递已验证的外部身份，数据库映射既有内部用户并重新授权，提交访问审计后才交付报告。
_Avoid_: 个人 session capability、app_private 通用代理、任意报告查询

**管理报告导出审计**:
对固定匿名管理报告文件导出的服务端授权、生成和准备交付结果所留下的不可变最小事件；它证明服务端已完成授权并准备交付，不证明客户端已经落盘、分享或读取文件。
_Avoid_: 普通快照读取审计、客户端保存证明、报告内容日志

**管理报告快照目录**:
按显式项目返回至多 20 份可信 v2 报告快照元数据的只读目录；数据库在每次请求中重新确认管理分析查看能力，并在同一事务中保存不含快照 ID、报告元数据或格值的目录访问审计。目录按数据截止时间、发布时间和快照 ID 降序排列，但不宣称第一项是当前、最新有效或未被取代的报告。
_Avoid_: 最新报告、当前报告、历史查询、分页目录、授权 token

**管理分析导航上下文**:
已认证成员当前明确选择的一个可查看管理分析的组织项目；选择保存当次组织成员、项目成员和查看能力 grant 的完整证据，任一证据失效或以新关系重新加入后都必须重新选择。它只帮助导航，不能代替报告读取时的再次授权。
_Avoid_: 个人 session context、授权 token、只保存项目 ID、自动复活旧选择

**可信报告发布**:
在同一数据库事务中确认发布能力、固定数据库数据截止点、解析项目报告时区 revision、检查既有报告 lineage，并只在全部条件通过后建立报告快照的私有操作；调用方不能提交时区、截止时间或可复用授权 token。
_Avoid_: 客户端指定时区、先生成后授权、跨时区重置基线

**管理兴趣报告受保护快照**:
由 6AV 固定定义、两个相邻完整 ISO 周、`previous/current × interest_level 0..4` 十格 count-only 网格、隐私状态、
可信报告时区 revision 和数据截止时间组成的不可变私有报告文档。它可以复用通用 snapshot storage，但必须经过
兴趣专用 validator，并且不是渠道 16 格或 current-city 区域快照；中位数、比例、总计格和其他派生值不在此定义中。
_Avoid_: 客户端组装十格、跨报告拼接、把 `suppressed` 当零、渠道快照、区域快照

**兴趣报告发布 lineage**:
围绕一份管理兴趣受保护快照保存的兴趣专属 release attempt、request claim 和 provenance 序列。首个合法文档建立唯一
baseline；后续成功发布只能推进 cutoff，保持定义、period definition／boundary、网格顺序和时区 revision 一致，并链接前一 snapshot。相同
request 和固定上下文必须精确幂等，不新增 snapshot 或 attempt。same／earlier cutoff、无共享期间、共享期间内的兴趣格值或隐私
状态变化以及定义、期间、网格、query fingerprint、privacy policy、source scope 或时区 revision 漂移，返回稳定
blocked reason；blocked attempt 只保留最小 value-free lineage evidence，不保存候选文档、cells、来源、贡献者、隐藏
前值或 PII。它与 channel／current-city request UUID 和 provenance 互斥，不授予读取、目录、导出或 HTTP 权限。
_Avoid_: 复用渠道 claim、跨报告 provenance、失败记录带值、发布即读取、生产 HTTP、warehouse、retention

**管理兴趣快照读取**:
拥有 `view_anonymous_analytics` 的项目成员按显式 project 和 snapshot ID 读取一份 6AW 兴趣快照的 private DB-only 操作。
数据库重新确认完整成员授权链，只接受 interest release attempt、request claim 和 provenance 全部匹配的 approved 快照，
并在返回前再次验证 6AV 十格文档。未知或跨项目 snapshot 返回 `not_found`；同项目但属于 channel、current-city、legacy、
blocked 或其他不可信来源的 snapshot 返回 `untrusted_provenance`，两者都不返回报告正文。每次已授权尝试追加不含格值的不可变
访问审计；撤权与读取使用同一授权锁。该操作不提供 runtime、HTTP、目录、Flutter、导出或客户端授权 token。
_Avoid_: 发布即查看、跨项目探测、复用渠道 read、把管理项目选择当作再次授权、客户端重算十格

**管理兴趣快照 runtime bridge**:
6AY 通过 0064 `app_data` bridge 将 6AX private read 接到 Backend runtime。bridge 接收 Backend 已验证的 exact `issuer + subject`、显式
project UUID 和 snapshot UUID，只映射现有且 active 的 identity，再调用 0063 private function。它不 trim、bootstrap、读取 `SessionContext` 或
接受内部用户、capability、时区、截止点、期间、筛选和 SQL。runtime 只有 bridge `EXECUTE`，没有 `app_private` 使用权或 private 表读取权。
Backend adapter 只执行一次固定 SQL，并严格解析 0063 envelope、6AX 十格和 `suppressed = null`。6AY 不增加 HTTP、目录、导出、Flutter、
Drift、缓存、离线、同步或真人平台证据。
_Avoid_: runtime 直接读 private schema、发布即读取、宽泛 SQL、客户端重算、用 HTTP 测试冒充 DB-only bridge 证据

**管理兴趣快照 HTTP 读取**:
6AZ 通过固定的 `GET /v1/projects/:projectId/management-interest-report-snapshots/:snapshotId` 调用 6AY store。handler 先验证 Bearer token，
再检查两个 UUID、query、GET body 和 store；认证失败先返回 `401`。认证通过后只把 verified identity、显式 project 和 snapshot 传给 6AY，
不使用 `SessionContext`、通用 reader、current-city reader 或客户端查询。成功返回 6AX protected report、snapshot ID 和 value-free access event ID；`not_found`、
`untrusted_provenance`、`forbidden` 和内部错误分别映射为稳定的 `404`、`409`、`403` 和 `503`。所有响应使用 JSON 和 `Cache-Control: no-store`。
6AZ 不修改数据库，不增加 DB fixture、migration 或并发协议；既有 6AY PostgreSQL suite 仍由 CI 运行，HTTP 证据由 Backend unit、route 和
composition 测试提供。它不增加目录、Flutter、导出、缓存、离线、同步或真人平台证据。
_Avoid_: HTTP 层重新授权、SessionContext 授权、暴露数据库错误、缓存受保护报告、把 6AY DB integration 当作 HTTP 测试

**管理兴趣快照目录**:
6BA 按显式 project 返回至多 20 份 6AW interest snapshot 的 metadata-only 只读目录。数据库每次请求重新确认
`view_anonymous_analytics` 和完整项目成员授权链，并只接受 interest release family 中 `approved`／`approved_baseline`、空 reason、
project／report／version／query fingerprint／lineage／报告时区／data cutoff／previous snapshot／source watermark 全部对齐的快照。
目录使用独立的 interest provenance、runtime bridge 和 value-free directory audit，不复用 channel 或 current-city directory。结果按
`data_cutoff_utc`、`released_at_utc` 和 `snapshot_id` 降序排列，最多 20 项；第一项不表示 current、latest、最新有效或未被取代。
响应只含快照 ID、固定报告 ID／版本、报告时区、截止时间和发布时间，不含 protected report、cells、suppressed 前值、来源、贡献者或 PII。
它为 6AZ 提供可选择的显式 snapshot ID，但不替代 6AX 的再次授权、读取审计或详情读取。
_Avoid_: 复用 0035／0060 provenance、最新报告推断、跨项目探测、分页搜索、报告正文、Flutter、导出、缓存、离线、同步、真机证据

**管理兴趣快照 Flutter typed gateway**:
6BB 为 6BA 的有界目录和 6AZ 的显式详情提供独立的 `InterestReportGateway`。目录使用固定 collection path，HTTP 根对象只有
`access_event_id`、`project_id` 和 `snapshots` 三项；数据库 bridge 的内部 envelope 虽有四项（另含
`access_contract_id`），该内部字段不得进入 HTTP 或 Dart。详情使用固定 snapshot path，根对象只有 `access_event_id`、
`snapshot_id` 和 `report` 三项。目录最多 20 项，保持服务端的 `data_cutoff_utc`、`released_at_utc`、`snapshot_id` 降序；第一项
不具有 current、latest 或未被取代语义，详情必须使用用户明确选择的 project／snapshot。
gateway 从 `IdentitySession` 取得 Bearer token，最多对一次 `401` 刷新并重试一次；目录和十格 interest report 都由 strict
parser 检查固定根键、字段、类型、顺序、项目／快照绑定、`suppressed = null` 及无 PII，解析失败即失败关闭。类型只在本次调用
期间保存在内存，不写 Drift、缓存、离线存储、同步队列或导出，也不承担 UI、ViewModel、Widget、导航、管理项目上下文或真机验收。
_Avoid_: 暴露 `access_contract_id`、自动选择首项、客户端重算或隐藏、复用 channel／current-city gateway、重复刷新、持久化受保护报告、
把 synthetic HTTP／Dart 测试当作 Backend 授权或平台运行时证据

**管理兴趣报告 Flutter consumer**:
6BC 把 6BB 的独立 interest gateway 接入管理报告浏览器。浏览器保留渠道、当前城市和兴趣三个互斥视图，
默认仍是渠道；只有用户明确选择兴趣视图后，才用当前已重新授权的 `ManagementAnalysisContext.projectId`
读取目录。它不使用个人 `TrustedSessionContext`，也不自动打开目录首项或推断 current／latest。
独立 panel 和 ViewModel 只接受当前目录中用户明确选择的 interest summary，显示两个期间的固定十格。
`displayed` 显示服务端已保护的计数，`suppressed` 只显示“已隐藏 / Hidden”，不显示为零。切换项目、视图、
返回目录、重试或 dispose 会使旧 generation 失效，迟到响应不能恢复旧项目或旧快照。结果只留在内存，支持中英文、
小屏、200% 字号、键盘、焦点恢复、heading 和 live region。
_Avoid_: 个人项目回退、多个布尔开关表示 report family、自动打开首项、客户端总计／比例／趋势、隐藏值当零、旧响应写回、
复用 current-city DTO／Widget、Drift、缓存、离线、导出或真机证据

**管理原始区域固定报告**:
6BD 定义私有的 `contact_sessions_by_original_region_two_periods@1` DB-only 保护报告。它固定 `metric=contact_sessions@1`、
`view_mode=original`、`dimension=original_region`、城市粒度、项目报告时区和两个完整 ISO 周；所有可报告接触必须来自同一个精确的
`source_tree_version + source_content_fingerprint`。报告使用保存的 original 来源把每条记录归入该来源树中的唯一城市，不读取 current
选择或 6AM target context，也不重新解析坐标、使用跨版本 mapping 或猜测名称／父链。它输出来源树全部城市的稳定完整网格，并在返回前完成 `k=10`、
三位贡献者、半数上限和互补隐藏。`data_cutoff_utc` 只是本次纳入事实的边界，不支持任意历史 `as-of`。来源树混杂、没有可用来源树或证据不完整时不生成跨树结果。
它只属于 PostgreSQL 私有合同；6BD 不增加 snapshot、release、runtime、HTTP、Flutter、Drift、缓存、离线、同步、导出、父级／重叠处理、retention、warehouse 或真机验收。
_Avoid_: current 归类、跨树聚合、as-of 重建、自动选择 latest、隐藏值、城市名称／边界／坐标、客户端报告

**管理原始区域快照发布 lineage**:
6BG 围绕 6BD 已保护的 original-region 报告保存一条原始区域专属的追加式 snapshot／release provenance，复用不可变的通用
`management_report_snapshots` 存储，但使用独立的 release attempt、writer role、RLS 范围和 request-claim family；它不复用 channel、
current-city 或 interest lineage，也不把 6BD executor 的即时结果自动解释为已发布快照。

发布在请求、项目和 lineage 锁后重新确认 `release_management_reports`、组织／项目成员关系、可信报告时区 revision 和 6BD candidate。
首个 `completed` candidate 建立 baseline；后续 snapshot 必须保持相同 report identity、期间定义、query／privacy／source scope、时区 revision
和精确 `source_tree_version + source_content_fingerprint`，只能推进 cutoff、保持 source change sequence 不回退并链接当前 lineage head。
来源树变化或不可用、已发布 lineage 与候选的固定上下文漂移、same／earlier cutoff、无共享期间或共享 protected 值／隐私状态变化时失败关闭，不生成 snapshot。
executor 内部定义不一致属于实现错误，必须抛出，不能伪装成业务 blocked attempt。

blocked attempt 只保存固定 reason 和最小 value-free lineage metadata，不保存候选报告、cells、隐藏前值、来源、contact、contributor、区域名称、坐标或 PII。
这是 PostgreSQL 私有 DB-only 合同，不是 authorized read、runtime、HTTP、目录、导出、删除、retention、任意历史 `as-of` 或真实平台证据。
_Avoid_: 复用其他 report family provenance、静默改写旧 snapshot、把 baseline 当 latest、把 blocked attempt 当报告、用 Docker synthetic 证据代替生产或真人运行时证据

**管理原始区域快照授权读取**:
6BH 按可信内部用户、显式项目和 snapshot UUID 私有读取一份 6BG 原始区域快照。数据库在每次调用中重新确认
`view_anonymous_analytics`，只接受 0068 original-region request claim、`approved`／`approved_baseline` attempt 和与 snapshot 完全对齐的
project、report identity、lineage、时区 revision、cutoff、previous pointer、source watermark 与 source tree tuple。返回前再次运行 6BD
original-region document validator，不重算、不重新归类、不改写，也不自动选择 latest。

只有 `completed` 返回既有 protected report。未知或跨项目 snapshot 返回 `not_found`；同项目但属于 channel、current-city、interest、legacy、
blocked、缺失或漂移 provenance 的 snapshot 返回 `untrusted_provenance`。两种失败都没有正文。每次已授权尝试追加原始区域专用、不可变、
value-free 的访问审计；撤权与读取使用同一授权锁。该操作不提供 runtime、HTTP、目录、Flutter、导出、缓存、离线或生产身份。
_Avoid_: 发布即查看、跨项目探测、复用其他 report family reader、客户端提交 source tuple、自动 latest、客户端重算城市网格

**管理原始区域快照 runtime bridge**:
6BI 通过 0070 `app_data` bridge 把 6BH private read 接到 Backend runtime。bridge 接收 Backend 已验证的 exact external `issuer + subject`、显式
project UUID 和 snapshot UUID，只映射现有且 active 的 identity，再调用 0069 private function。它不 trim、bootstrap、读取 `SessionContext`，也不
接受内部用户 ID、capability、时区、截止点、期间、source tuple、筛选或 SQL。runtime 只有 bridge `EXECUTE`，没有 `app_private` schema usage 或
private 表读取权。

Backend adapter 只执行一次固定参数化 SQL，并严格解析 0069 envelope。`completed` 必须包含固定 17 个 original-region report keys、同项目 ID、
selected source tree tuple、两个完整期间、连续 `cell_order`、安全整数和 `suppressed = null`；`not_found` 与 `untrusted_provenance` 不含正文。
parser 拒绝额外字段、其他 report family、城市名称、坐标、来源记录、贡献者和 PII，只把 SQLSTATE `42501` 映射为 typed `forbidden`。6BI 不增加
HTTP、目录、导出、Flutter、Drift、缓存、离线、同步或真人平台证据。
_Avoid_: runtime 直读 private schema、复用其他 report family bridge、宽泛 SQL、客户端重算、把 synthetic integration 当作生产身份或平台运行时证据

**管理原始区域快照 HTTP 读取**:
6BJ 通过固定的 `GET /v1/projects/:projectId/management-original-region-report-snapshots/:snapshotId` 调用 6BI
`ManagementOriginalRegionReportSnapshotStore`。handler 先解析并验证 Bearer identity，再验证两个 UUID、query、GET body 的
`Content-Length`／`Transfer-Encoding` 声明以及专用 store；认证失败先返回 `401`，不会用 malformed path、query、body 或缺失 store 探测资源状态。
认证通过后只把 verified identity、显式 project 和 snapshot 传给 6BI，并等待 store Promise 完成后写响应。

成功响应只含 `access_event_id`、`snapshot_id` 和 `report`。`400`、`403`、`404`、`409`、`503` 分别使用固定 request、forbidden、not_found、
untrusted 和 unavailable code；`404`／`409` 只能附带 value-free `access_event_id`。成功和错误响应都使用 JSON 与 `Cache-Control: no-store`。

响应不暴露数据库消息、SQL、栈、external subject、授权关系、报告格、来源、贡献者、区域名称、坐标或 PII。HTTP 层不使用 `SessionContext`，不调用
generic、current-city 或 interest store，也不访问 `app_private` 或复制 6BI／6BH 的授权、provenance、validator、撤权锁和 audit。
6BJ 不增加 migration、database check、fixture、PostgreSQL integration、并发、目录、latest、分页、搜索、筛选、导出、缓存、离线、Flutter、Drift、
UI、报告生成／发布／更正、删除、retention、warehouse、production JWT 或真人平台证据；Backend route、handler 和 production composition 测试是
本切片的 synthetic HTTP 证据。
_Avoid_: 认证前验证路径、复用其他 report family store、自动选择 latest、缓存 protected report、把 DB-only Docker 结果当作 HTTP 或生产身份证据

**管理原始区域快照目录**:
6BK 按显式 project 返回最多 20 份 6BG original-region snapshot 的 metadata-only 目录。数据库每次请求重新确认 active identity、完整项目成员授权链和
`view_anonymous_analytics`，并只接受 original-region release family 中 `approved`／`approved_baseline`、空 reason、project／report／version／query
fingerprint／lineage／报告时区 revision／cutoff／previous pointer／source watermark／source tree tuple 全部对齐的快照。

目录使用独立的 original-region provenance、runtime bridge 和 value-free directory audit，不复用 generic、channel、current-city 或 interest directory。
结果按 `data_cutoff_utc`、`released_at_utc` 和 `snapshot_id` 降序排列，最多 20 项；第一项不表示 current、latest、最新有效或未被取代。响应只含
snapshot ID、固定报告 ID／版本、报告时区、截止时间和发布时间，不含 protected report、cells、隐藏前值、source tuple、来源、贡献者、区域名称、坐标或 PII。

固定 HTTP collection route 先认证再检查 project UUID、query、GET body 和专用 store。它为 6BJ 提供可选择的显式 snapshot ID，但不替代 6BH 的
再次授权、读取审计或详情读取。6BK 不增加 Flutter、导出、缓存、离线、Drift、分页、搜索、自动 latest、发布、更正、删除、retention 或真人平台证据。
_Avoid_: 复用其他目录 provenance、自动选择首项、跨项目探测、返回报告正文、用 synthetic Docker 或 HTTP 测试冒充生产或真人证据

**管理原始区域快照 Flutter typed gateway**:
6BL 使用独立的 `OriginalRegionReportGateway` 消费 6BK metadata-only 目录和 6BJ 显式详情。目录 HTTP 根对象只有
`access_event_id`、`project_id` 和 `snapshots` 三项；数据库内部的 `access_contract_id` 不进入 HTTP 或 Dart。详情根对象只有
`access_event_id`、`snapshot_id` 和 `report` 三项。目录最多 20 项，保持服务端的 cutoff、release time 和 snapshot ID 降序；第一项
不具有 current、latest 或未被取代语义，详情只读取调用方明确选择的同项目 summary。

gateway 从 `IdentitySession` 取得 Bearer token，一次 `401` 最多刷新并重试一次。strict parser 核对固定 original report identity、
project／snapshot 绑定、两个相邻期间、单一 source tree tuple、previous／current 完整城市网格、连续 `cell_order`、安全整数和
`suppressed = null`。额外字段、错误顺序、其他 report family、来源记录、贡献者、contact、区域名称、坐标或 PII 失败关闭。结果只在内存中
存在；6BL 不交付 UI、ViewModel、composition、Drift、缓存、离线、同步、导出或真人平台验收。
_Avoid_: 暴露 `access_contract_id`、自动读取首项、客户端重算或重新归类、复用其他 report family gateway、重复刷新、持久化受保护报告

**管理原始区域报告 Flutter consumer**:
6BM 把 6BL 的独立 original-region gateway 接入管理报告浏览器。浏览器保留渠道、当前城市、兴趣和原始区域四个互斥视图，默认仍是渠道；只有用户
明确选择原始区域视图后，才用当前已重新授权的 `ManagementAnalysisContext.projectId` 读取目录。它不使用个人项目，不自动打开首项，也不推断
current、latest 或 replacement。

独立 panel 和 ViewModel 只接受当前目录中用户明确选择的 original-region summary。详情显示固定元数据、两个期间、source-tree context、城市 ID 和
服务端已保护的完整城市格；不显示城市名称、坐标、边界、来源记录、贡献者、contact 或 PII。`displayed` 显示安全整数，`suppressed` 只显示
“已隐藏 / Hidden”。客户端不排序、聚合、重算、重新归类或推导总计、比例、差值、趋势和隐私状态。

切换项目、report family、返回目录、重试或 dispose 会使旧 generation 失效。状态只留在内存，并支持中英文、小屏、200% 字号、键盘、焦点恢复、
heading 和 live region。6BM 不增加 Backend、PostgreSQL、Drift、缓存、离线、同步、导出、搜索、分页、筛选或真人平台证据。
_Avoid_: 个人项目回退、多个布尔开关表示 report family、自动打开首项、客户端重算或归类、隐藏值当零、旧响应写回、复用其他 report family DTO、持久化受保护报告

**原始区域快照更正版取代**:
6BN 只登记两份已经通过 6BG 的 original-region approved snapshot 之间的直接 replacement。两份快照必须属于同一 project、report／version、query fingerprint、privacy、source scope、报告时区 revision、期间、release lineage 和精确的
`source_tree_version + source_content_fingerprint`。新快照的 `data_cutoff_utc` 与发布时间必须晚于旧快照。该关系在管理报告共享的 value-free request UUID ledger 中使用独立 replacement family claim，并使用 original-region 专用 provenance 和最小权限；它不复用渠道 replacement ledger。release 与 replacement 共享 request lock，因此同一 UUID 在两个合同中的先后顺序都失败关闭。

登记原因只允许 `late_accepted_data`、`contact_revision` 和 `contact_void`。旧快照与新快照保持不变；关系和最小 audit 追加且不可变，不允许 UPDATE 或 DELETE。每份旧快照最多有一个直接 replacement，每份新快照最多有一个 predecessor；自链接、循环、分叉和 stale head 失败关闭。请求与 lineage 锁取得后必须再次确认 `release_management_reports`。相同 request UUID 与 canonical payload 精确幂等，载荷漂移失败关闭。

生命周期查询只返回 snapshot ID、`active`／`superseded` 和直接 replacement ID，不返回报告格、来源、贡献者、地点或 PII。这是 DB-only、value-free 合同，不生成 snapshot，不增加 runtime、HTTP、Flutter、目录、导出、缓存、离线或分享，也不执行删除、tombstone、retention、备份清除、parent／overlap 查询、warehouse 或真人平台验收。
_Avoid_: 复用 0067 渠道关系、按目录排序猜测 latest、静默改写快照、跨 report family 取代、分析定义或跨版本更正、把 Docker synthetic 通过写成生产证据

**组织项目后续联系同意占比 opt-in 配置**:
6BO 为组织项目保存 `follow_up_consent_ratio@1` 的当前 opt-in。配置使用独立的 `app_private` 表和 private configure/read 合同，不复用个人 0048 配置。
调用方只提供可信内部 `app_user_id`，数据库重新确认活动账号、组织／项目 membership、项目状态和 `release_management_reports` capability。`view_anonymous_analytics`
只允许读取受保护管理分析，不允许修改配置。版本追加不可变，记录 request UUID、授权 provenance 和数据库时间；未配置与停用返回 `not_enabled`，启用返回 `enabled`。
配置时间不裁切统计期间。项目 status 变更触发器与 configure 共享 project lock，归档与写入因此线性化；锁后必须重新授权，0030 resolver 不替代归档锁。结果不含比例、报告格、contact、推广对象、贡献者、地点或 PII。
这是 DB-only 配置合同，不是比例候选、报告、runtime、HTTP、Flutter、统计或披露安全证据。
_Avoid_: 复用个人 opt-in 表、用查看 capability 写配置、用配置时间截断数据、读取 contact-target link、把配置通过 UI 隐藏当成授权

**组织项目后续联系同意占比候选**:
6BP 在组织项目明确启用后，按固定的 `contact_target_follow_up_consent_ratio_two_periods@1`
生成一份 private release-candidate。它只使用两个相邻且已经结束的完整 ISO 周、项目报告时区和数据库截止时间，
统计单位是当前有效 contact revision 的 contact-target link；同一 contact 的多个 link 分别计数，贡献者是 contact 的可信 `app_user_id`。
`yes` 是分子，`yes + no` 是分母；`unknown` 作为 unanswered，`refused` 与 `not_applicable` 作为独立 coverage cell。
候选在 `release_management_reports` capability、membership、项目状态和 6BO opt-in 重新确认后运行。
`yes` 与 `no` 必须分别满足 `N >= 10`、至少三位贡献者和贡献者不超过总数一半，二者都通过才返回比例数值；
coverage cell 也独立执行同一保护。未启用返回 `not_enabled`，已启用但不满足披露条件返回 `suppressed`，两者都不表示零。
这是 private PostgreSQL DB-only 候选，不是 snapshot、发布报告、授权读取、runtime、HTTP、客户端结果或生产证据。
_Avoid_: 把候选当成正式报告、把 suppressed 当成零、用总数相减恢复隐藏值、把 Docker synthetic 通过写成生产或真人平台证据

**组织项目后续联系同意占比快照发布**:
6BQ 把 6BP 的 completed protected candidate 固定为不可变 snapshot。它使用独立的 release writer、request claim family、attempt、RLS policy 和
`management-follow-up-consent-ratio-report:<report_id>` lineage，不复用渠道、current-city、interest 或 original-region provenance。发布事务在锁内重新确认
`release_management_reports`、组织／项目 membership、项目状态、报告时区 revision 和 6BO 当前 opt-in，并从 `change_feed` 取得 source watermark。调用方不能提交候选 JSON、统计值、cutoff、时区、watermark 或授权 provenance。
首份 completed candidate 建立 `approved_baseline`；后续发布只允许 cutoff 前进并链接当前 predecessor。相同 request 精确幂等。`not_enabled` 不生成 snapshot；同期或更早 cutoff、无共享期间、共享 ratio／coverage 显示值或 privacy status 变化，以及固定定义、时区或 watermark 漂移，都只写 value-free blocked attempt。snapshot、attempt 和 claim 追加不可变。
这是 private PostgreSQL DB-only 发布合同，不是授权读取、runtime、HTTP、客户端、目录、导出、replacement、删除、retention 或生产证据。
_Avoid_: 把 candidate 当 snapshot、跨 report family 借用 provenance、保存 blocked candidate 值、把 suppressed 当零、由调用方提交 watermark、把 Docker synthetic 通过写成生产证据

**组织项目后续联系同意占比快照授权读取**:
6BR 只按可信内部用户、显式 project 和 snapshot UUID 私有读取一份 6BQ snapshot。
数据库在授权锁内重新确认 active user、组织／项目 membership、active project 和 `view_anonymous_analytics`。
它还复核 0075 consent-ratio claim／attempt／snapshot 的固定 report identity、时区 revision、cutoff、previous pointer 和 source watermark。
返回前再次执行 6BQ validator；不重算、不恢复隐藏值、不修改 snapshot，也不选择 latest。
合法 provenance 返回既有 protected report；unknown／cross-project 返回 value-free `not_found`；同项目 foreign／legacy／blocked／missing／drift provenance 返回 value-free `untrusted_provenance`。每次已授权调用追加不可变、value-free audit；未授权、撤权、过期、release-only、无有效成员或 inactive project 失败关闭且不写 audit。
这是 private PostgreSQL DB-only 读取合同，不是 runtime identity bridge、HTTP、Backend、客户端、目录、导出、replacement、删除、retention 或生产证据。
_Avoid_: 用发布能力代替查看能力、跨 report family 借用 provenance、把 `not_found` 与未授权混为一谈、返回 untrusted 正文、把 private function 直接开放给 runtime

**组织项目后续联系同意占比快照 runtime bridge**:
6BS 用 Backend 已验证的 exact external `issuer + subject`、显式 project 和 snapshot UUID 调用 6BR private reader。
bridge 只映射既有 active identity，不 trim、不 bootstrap，也不接受内部用户、capability、时区、截止点、筛选或 SQL。
runtime 只有 bridge `EXECUTE`，不能使用 `app_private` 或读取 identity、用户、snapshot、provenance 和 audit 表。
Backend adapter 只执行一次固定 SQL，并严格解析 6BR envelope、同意占比报告、两个期间、ratio、coverage 和 `suppressed = null`。
授权、0075 provenance、6BQ validator、撤权锁和 value-free audit 仍由 6BR 负责。
这是 synthetic PostgreSQL 与 Backend adapter 合同。6BS 当时不包含 HTTP；HTTP 详情读取由后续 6BT 单独定义，不能把两层证据合并。
_Avoid_: trim identity、runtime 直接进入 private schema、复用其他报告 parser、在 adapter 重算比例、把 Docker integration 当生产身份或 HTTP 证据

**组织项目后续联系同意占比快照 HTTP 读取**:
6BT 为已知的后续联系同意占比 snapshot 提供固定的只读 HTTP 详情入口：
`GET /v1/projects/:projectId/management-follow-up-consent-ratio-report-snapshots/:snapshotId`。
在固定 path 命中后，handler 必须先验证 Bearer identity，再检查 project／snapshot UUID、query、GET body 和 6BS 专用 store；认证失败时，
即使这些输入无效，也先返回 `401 unauthenticated`。认证通过后只传递 verified `issuer + subject`、显式 project UUID 和 snapshot UUID，
不调用 `SessionContext`、generic 或其他 report-family reader，也不接受客户端筛选、时区、截止点、SQL 或内部用户 ID。

GET 不接受 query 参数或 body；非零 `Content-Length`、`Transfer-Encoding` 等声明的 body 也失败关闭。成功 wire 只含
`access_event_id`、`snapshot_id` 和 `report`。`400`、`403`、`404`、`409` 和 `503` 使用固定、脱敏的错误 code；其中 `404`／`409` 最多携带
6BS 返回的 value-free `access_event_id`，不携带报告格、授权关系、external subject、数据库消息或 PII。所有成功和错误响应都是 JSON，
并设置 `Cache-Control: no-store`。

6BT 只增加 Backend handler、固定 route、专用 production composition 和 synthetic HTTP 测试，不增加 PostgreSQL migration、reader、目录、
latest／current 选择、分页、筛选、Flutter、Drift、导出、缓存、离线、同步、replacement、删除、retention、warehouse 或六平台真人证据。
这些测试只证明 Backend HTTP transport contract，不证明 production identity provider、部署端点、真实账号或客户端消费。
_Avoid_: 认证后才验证请求形状、复用 6BS 以外的 store、自动选择 snapshot、把报告正文放入错误、缓存 protected report、把 synthetic HTTP 测试写成生产证据

**组织项目后续联系同意占比快照目录**:
6BU 是 SQL-only 目录合同。private 函数的 canonical 名称是
`app_private.list_authorized_management_follow_up_consent_snapshots_v1(uuid, uuid)`；名称保持在 PostgreSQL
标识符限制内，避免长名称被截断。每次调用都重新确认 active user、组织／项目 membership、active project 和
`view_anonymous_analytics`，并沿既有 authorization／revoke lock order。它只接受 0075
consent-ratio family 的 `approved_baseline`／`approved` exact provenance，跨 project、跨 report family、legacy、blocked、缺失或漂移的 provenance 失败关闭。

结果 envelope 只含 `access_contract_id`、`access_event_id`、`project_id` 和 `snapshots` 四项。
`snapshots` 最多返回 20 项，每项只含 `snapshot_id`、`report_id`、`report_version`、`reporting_time_zone`、
`data_cutoff_utc` 和 `released_at_utc`。数据库固定按 `data_cutoff_utc DESC`、`released_at_utc DESC`、
`snapshot_id DESC` 排序；第一项只是该排序的第一项，不表示 current、latest 或未被取代，也不提供 latest、current、分页或筛选语义。
授权项目没有合格快照时返回空数组，并追加数量为 0 的成功 audit。

目录 audit 使用专用追加式、不可变、value-free 合同，只记录授权和访问 metadata，不记录 snapshot ID、report、period、ratio、coverage、source、contributor、target、contact 或 PII。
授权撤回、过期、无成员、inactive project、未知 ID、跨项目和权限不足都失败关闭；失败授权不写成功 audit。
6BU 不修改前序 6BS／6BT 已定义的 `app_data` identity bridge、runtime、Backend adapter 和 HTTP route，也不增加 Flutter、导出、缓存、离线、同步或生产平台验收。
本地 Docker、结构检查、可回滚 fixture、授权／撤权并发、checksum 和 dump／restore 只提供 synthetic PostgreSQL 证据，不能替代前序 transport 证据、生产或真人平台证据。
_Avoid_: 用超长函数名造成 identifier 截断、把目录第一项当 latest、复用其他 report family provenance、把审计写入 snapshot ID、让 runtime 直接执行 private function、把 synthetic 通过写成运行时证据

**组织项目后续联系同意占比快照目录 runtime bridge**:
6BV 在 6BU 的 private directory 之上增加 0079 `app_data` exact-identity bridge。Backend 先验证 external identity，再把原始 `issuer + subject`、显式 project UUID 交给 bridge；bridge 只映射已有且 active 的 identity，不 trim、不 bootstrap、不创建 identity，也不接受内部用户、capability、筛选或 SQL。

0079 只调用 0078 的 `app_private.list_authorized_management_follow_up_consent_snapshots_v1(uuid, uuid)`。`tongxingzhe_runtime` 只有 bridge `EXECUTE`，不能使用 `app_private` schema 或直接读取 identity、snapshot、attempt、claim、directory 或 audit 表。bridge 使用 `SECURITY DEFINER`、`VOLATILE` 和固定 `search_path = pg_catalog`，owner 与 0078 private function 对齐。

Backend 使用独立的 consent-ratio directory store，只执行一条固定参数化 SQL。strict parser 只接受 0078 的四项 root envelope 和六项 metadata item，检查 exact keys、project 绑定、UUID、UTC 时间、最多 20 项、无重复和固定排序；额外字段、错误 contract、非 consent-ratio report、无效 UUID 或时间均失败关闭。只有 SQLSTATE `42501` 映射为 typed `forbidden`，其他数据库或解析错误保持 unavailable。

6BV 不增加 HTTP route、认证顺序、wire error mapping、Flutter、Drift、UI、缓存、离线、导出、分页、筛选、current／latest 选择或生产身份／真人平台验收。0078 继续负责目录授权、provenance、撤权锁和 value-free audit；6BV 的 synthetic PostgreSQL 与 Backend integration 证据只证明 bridge、adapter、parser 和 ACL 合同。
_Avoid_: 让 runtime 直接调用 0078 private function、trim external identity、复用 6BS snapshot reader、在 Backend 重算或筛选目录、把 DB／Backend synthetic 通过写成 HTTP 或生产身份证据

**组织项目后续联系同意占比快照目录 HTTP 集合读取**:
6BW 在 6BV 的 runtime bridge 之上增加固定的只读集合入口：
`GET /v1/projects/:projectId/management-follow-up-consent-ratio-report-snapshots`。它使用独立的 consent-ratio snapshot directory store，
只把 Backend 已验证的 identity 和显式 project UUID 传给 6BV store；不调用 detail reader、generic directory、`SessionContext` 或 `app_private`。

固定 path 命中后，handler 先验证 Bearer identity，再检查 project UUID、query、GET body 和 dedicated store。GET 不接受 query 或 body；非零
`Content-Length`、`Transfer-Encoding` 等 body 声明也失败关闭。认证失败始终返回 `401 unauthenticated`，不会用 malformed request 或缺失 store 探测资源状态。
认证通过后，malformed request 返回 `400 invalid_management_follow_up_consent_ratio_snapshot_directory_request`；store 的 typed forbidden 返回
`403 management_follow_up_consent_ratio_snapshot_directory_forbidden`；其他 verifier、store、数据库、parser 或未知错误返回
`503 management_follow_up_consent_ratio_snapshot_directory_unavailable`。

成功 `200` 的 HTTP root 只含 `access_event_id`、`project_id` 和 `snapshots`。每项只含 6BV 已定义的六个 metadata 字段：`snapshot_id`、`report_id`、
`report_version`、`reporting_time_zone`、`data_cutoff_utc` 和 `released_at_utc`。空目录也返回 `200` 和空数组。被过滤或不存在的快照不会从集合读取暴露为
`404` 或 `409` 详情错误；其他 method 或未匹配 path 仍可由通用 server 返回 `404`。第一项只是服务端固定排序的第一项，
不表示 current、latest 或未被取代。

所有响应使用 JSON 和 `Cache-Control: no-store`。6BW 只增加 Backend handler、固定 route、production composition 和 synthetic HTTP 测试，不修改数据库、
runtime bridge、Flutter、Drift、缓存、离线、导出、分页、筛选或部署。HTTP 测试只证明 transport contract、认证顺序、请求拒绝、专用 store、状态映射、
Promise gate、wire 和 no-store，不证明 production identity、部署端点或 Android、iOS、macOS、Windows、Linux、Web 真人平台证据。
_Avoid_: 认证前验证请求、自动选择第一项、把集合读取当成 latest 查询、返回 404／409 详情错误、复用其他 report family store、缓存 metadata 或 protected report、
把 synthetic HTTP 测试写成生产或真人平台证据

**组织项目后续联系同意占比 Flutter typed gateway**:
6BX 为 6BW collection 和 6BT detail 增加独立的 Flutter typed gateway。它把 DB-only 四字段 directory envelope 与 HTTP／Dart 三字段 root 分开，
只读取显式 project 和用户明确选择的 snapshot，不自动选择第一项，也不推断 current、latest 或 replacement。

目录请求固定使用 6BW collection path，详情请求固定使用 6BT detail path；两个请求都只发送 GET、显式 project UUID 和已选 snapshot UUID，不发送 query 或 body。
gateway 从 `IdentitySession` 取得 Bearer token，第一次收到 `401` 时强制刷新并只重试一次。成功响应必须是 JSON 并带 `Cache-Control: no-store`；identity、HTTP、
timeout、network、非成功状态、strict parser 和 closed 错误映射为稳定 typed failure。

目录 parser 只接受三项 root、六项 metadata、最多 20 项、空数组、无重复和服务端固定降序。详情 parser 只接受三项 root，严格解析
`contact_target_follow_up_consent_ratio_two_periods@1` 的两个完整期间、ratio、coverage 顺序、`suppressed = null` 和安全整数，并核对
project／snapshot／summary 绑定。额外字段、PII 形状、错误 key、错误顺序、错误算术、不安全整数或隐藏值恢复失败关闭。

解析结果只保存在内存，并通过不可修改集合暴露；`close` 释放 gateway 持有的 HTTP client。6BX 只增加 Dart 类型、HTTP adapter 和 synthetic Flutter 测试，不修改
Backend、PostgreSQL、runtime、UI、ViewModel、composition、Drift、缓存、离线、同步、导出、分页或筛选。测试只证明 transport、parser 和内存边界，不证明
6BW／6BT 的 Backend authorization、数据库 provenance、部署端点、production identity 或 Android、iOS、macOS、Windows、Linux、Web 真人平台运行时。
_Avoid_: 复用其他 report family gateway、把 DB envelope 的 `access_contract_id` 带入 Dart、自动选择首项、在客户端重算或补回隐藏值、把 synthetic Flutter 测试写成生产证据

**组织项目后续联系同意占比 typed gateway composition 与生命周期**:
6BY 在现有 `AppDependencies` composition root 增加可选的
`followUpConsentRatioReportGatewayBuilder`。生产配置使用既有 HTTP gateway factory；没有配置时建立
`DeferredFollowUpConsentRatioReportGateway`，它返回 `notConfigured` 且不访问网络。builder 只接收启动流程已经打开的同一个
`IdentitySession`，`AppStartupReady` 暴露同一个 gateway 实例；个人同意占比和其他管理报告 gateway 仍保持独立。

如果 gateway 已建立而后续启动阶段失败，启动清理必须关闭它一次。`TongxingzheApp` 移除时也关闭 ready gateway 一次，重复关闭保持安全。
本切片不把 gateway 传入 `_ReadyApp`、`ProductionHomeShell`、ViewModel、widget、导航或 UI；后续 UI 切片再决定消费边界。

6BY 只处理已有 typed gateway 的装配和资源所有权，不改变 parser、HTTP、Backend、PostgreSQL、runtime、Drift、缓存、离线、同步、导出或
生产身份合同。Flutter fake identity、fake gateway 和 widget lifecycle 测试只证明 composition、同一身份传递、deferred fallback 和关闭边界，
不证明网络解析、Backend 授权、数据库行为、UI 消费或真人平台运行时。
_Avoid_: 打开第二个 IdentitySession、把 token 传给 builder、让 deferred fallback 发网络请求、把 gateway 交给 UI、启动失败时泄漏资源、重复关闭已有 gateway、
把 composition 测试写成 HTTP 或生产证据

**组织项目后续联系同意占比 Flutter 独立面板**:
6BZ 在 6BY 已装配的 `FollowUpConsentRatioReportGateway` 上增加独立
`FollowUpConsentRatioReportPanel` 和对应 ViewModel。面板接收 `AppStrings`、该 gateway 和可空的已授权
`projectId`；`projectId` 为空时保持 inactive。非空项目只请求一次当前项目的目录，先显示 loading，不自动选择第一项或请求详情。

用户从当前目录明确选择一个 snapshot 后，面板只用该条 summary 请求详情。详情显示固定 report metadata、previous 和 current 两个完整期间、服务端提供的
ratio 与 unanswered／refused／not_applicable coverage。面板保持 gateway 的顺序和每个 cell 的 privacy status；显示值原样呈现，basis points 只做文字格式化，
不在客户端计算 ratio、总数、趋势、互补值、排序、latest 或 current。`suppressed` ratio 或 coverage 只显示本地化的 hidden 状态，不显示零、任何隐藏前值或推断值；
每个 coverage cell 独立判断隐私状态。

面板状态包括 inactive、loading directory、directory、loading detail 和可恢复 failure。项目切换、返回目录、重试和 dispose 都使旧 generation 失效，迟到响应不能
改写当前状态。目录、详情、返回和重试必须保留键盘路径、heading、label、live region 和焦点返回，并在 `320×568` 与 `200%` 字号下可读。failure 只显示本地化
消息和 retry，不显示响应正文、数据库消息、授权详情、内部 ID 或 PII。

6BZ 只交付这个独立 panel、ViewModel、localized strings 和 focused Flutter tests；不把第五个 report-family choice 加入
`ManagementReportBrowser`，也不修改 `_ReadyApp`、`ProductionHomeShell`、`AppDependencies`、导航或 gateway passing route。它不改变 typed gateway、HTTP、Backend、
PostgreSQL、runtime、identity、authorization、Drift、缓存、离线、同步、导出、搜索、分页、latest／current 选择或报告生成合同。
测试使用 fake typed gateway，证明状态转换、严格 typed rendering、privacy suppression、focus／semantics、迟到响应隔离和响应式布局；不证明 gateway parser、HTTP、
Backend 授权、数据库、部署服务、生产身份或 Android、iOS、macOS、Windows、Linux、Web 真人平台运行时。该切片沿用现有 panel／ViewModel 模式，不需要新增 ADR。
_Avoid_: 复用个人 follow-up consent opt-in 或 ratio panel、自动打开首项、在客户端重算或补回隐藏值、用 UI 门控冒充授权、把 fake Flutter 测试写成生产证据

**组织项目后续联系同意占比管理报告浏览器**:
6CA 在 `ManagementReportBrowser` 中增加第五个、互斥的后续联系同意占比 report family。渠道 family 仍默认选中；默认状态和其他
family 不请求该 gateway。只有用户明确选择第五个 family 后，浏览器才创建并显示 6BZ panel，并把当前已重新授权的
`ManagementAnalysisContext.projectId` 传给它。浏览器不回退到个人项目、旧项目或 gateway 内置项目，也不自动打开目录首项或详情。

`FollowUpConsentRatioReportGateway` 由 6BY 的 composition root 创建和关闭。它沿
`AppStartupReady → _ReadyApp → ProductionHomeShell → ManagementReportBrowser` 原样传递；浏览器和 panel 只借用同一实例，不拥有、替换或关闭它。
第五个 family 使用本地化的中英文标签，并与渠道、current-city、interest、original-region 保持单一互斥选择。

项目或 family 切换会使当前 panel 的 generation 失效。旧项目的目录或详情响应不能写回新项目，也不能在离开第五个 family 后重新显示 panel。
既有 report family 的请求和显示行为保持不变。该切片只增加浏览器选择、panel 接线和对应测试，不改变 6BY 的 identity、gateway ownership 或 close 逻辑，
也不改变 6BZ panel、typed gateway、HTTP、Backend、PostgreSQL、runtime、Drift、缓存、离线、同步、导出或导航合同。
测试使用 fake gateway 证明默认不请求、明确选择、当前项目传递、键盘路径、切换隔离、同一实例传递和小屏布局；它们不证明 Backend 授权、部署服务、生产身份或
Android、iOS、macOS、Windows、Linux、Web 真人平台运行时。该切片沿用现有 browser 和 composition 模式，不需要新增 ADR。
_Avoid_: 默认读取第五个 family、个人项目回退、多个布尔开关、自动选择首项、关闭借用的 gateway、旧响应写回、用 UI 选择代替服务端授权、把 fake 测试写成生产证据

**current-city 快照更正版取代**:
6CB 只登记两份已经通过 0057 的 current-city approved snapshot 之间的直接 replacement。两份快照必须同 project、report／version、query／privacy／source scope、报告时区 revision、期间、release lineage 和完整 target context；新快照 cutoff／发布时间更晚且 source watermark 不回退。旧、新 snapshot 保持不变。

关系使用管理报告共享的 value-free request UUID ledger 和独立 current-city replacement family，并复用关闭的 lifecycle writer。lifecycle writer 只能通过 current-city 专用 provenance seam 核对 0057 approved attempt，不能直接读取 attempt ledger。release 与 replacement 共享 request lock；同一 UUID 双向互斥。原因只允许 `late_accepted_data`、`contact_revision` 和 `contact_void`。

关系和最小 audit 追加不可变。每份旧快照最多一个直接 replacement，每份新快照最多一个 predecessor；自链接、循环、分叉、stale head、跨项目／family、context 漂移、倒序和撤权失败关闭。生命周期只返回 snapshot ID、`active`／`superseded` 和直接 replacement ID，不返回报告格、区域来源、贡献者、接触、坐标或 PII。6CB 不生成 snapshot，不改变目录／读取／HTTP／导出／Flutter，也不处理跨版本更正、删除或 retention。
_Avoid_: 复用渠道或 original-region replacement 表、按目录排序猜测 latest、静默改写 snapshot、直接读取 0057 attempt、返回 target context 或报告值、把 Docker synthetic 通过写成生产证据

**interest 快照更正版取代**:
6CD 只登记两份已经通过 0062 的 interest approved snapshot 之间的直接 replacement。两份快照必须同 project、report／version、query／privacy／source scope、报告时区 revision、期间和 release lineage；新快照 cutoff／发布时间更晚且 source watermark 不回退。旧、新 snapshot 保持不变。

关系使用管理报告共享的 value-free request UUID ledger 和独立 interest replacement family。关闭的 lifecycle writer 只能通过 interest 专用 provenance seam 核对 0062 approved attempt，不能直接读取 attempt ledger。release 与 replacement 共享 request lock；同一 UUID 双向互斥。原因只允许 `late_accepted_data`、`contact_revision` 和 `contact_void`。

关系和最小 audit 追加不可变。每份旧快照最多一个直接 replacement，每份新快照最多一个 predecessor；自链接、循环、分叉、stale head、跨项目／family、倒序和撤权失败关闭。生命周期只返回 snapshot ID、`active`／`superseded` 和直接 replacement ID，不返回 interest cells、计数、贡献者、接触或 PII。6CD 不生成 snapshot，不改变目录／读取／runtime／HTTP／Flutter／导出，也不处理跨版本更正、删除或 retention。
_Avoid_: 复用渠道、current-city 或 original-region replacement 表、按目录排序猜测 latest、静默改写 snapshot、直接读取 0062 attempt、返回报告值、把 Docker synthetic 通过写成生产证据

**项目去身份化地点异常只读合同**:
6CC 只把 active contact 当前 accepted revision 中的 `pending_resolution + pending_coordinates` 和 `unknown + legacy_incomplete` 暴露为项目范围的去身份化异常。revision 必须为 `submitted` 或 `corrected`；resolved、not-applicable、draft、attempt、voided、旧 revision 和跨项目事实不进入候选。

读取需要独立 `view_deidentified_anomalies` capability，并在每次目录或详情调用中重新确认 active user、组织／项目 membership 和 active project。组织 owner、项目管理员、`view_anonymous_analytics`、区域维护或其他 capability 不能推导该权限。追加式 private mapping 为 provenance 分配随机 opaque ID；目录最多 20 项且不返回坐标，详情只对显式 ID 返回 pending 的最小坐标，legacy 返回 null。unknown、cross-project 与 stale ID 都返回相同 `not_found`。

不可变 audit 只保存 access event、授权 lineage、project、operation、result、数量和数据库时间，不保存 anomaly ID、坐标、发生时间、contact、revision、source 或 PII。6CC 是 DB-only read contract；它不修改 provenance，不提供 correction mutation、runtime、Backend、HTTP、Flutter、地图、geocode、搜索、分页、导出、组织清除或真人平台证据。
_Avoid_: 从 owner／admin／分析查看能力推导访问权、在目录返回坐标、暴露 contact／revision／source identity、把 stale 与 cross-project 区分给 caller、客户端补造异常、直接修改 provenance、把 synthetic Docker 写成生产隐私证据

**管理报告清除**:
组织删除恢复期届满后，移除该组织全部管理报告和含业务内容依赖的组织级处理；失败时组织保持不可访问。账号删除、授权撤回、更正版取代和报告年龄都不是管理报告清除。
_Avoid_: 授权撤回、报告到期、tombstone、superseded

**更正版报告**:
补录、修订、作废或分析定义修正后重新生成并明确取代某份报告快照的新快照；原报告保留但标记已被取代。
_Avoid_: 静默改写、删除旧报告

**管理分析**:
管理者在权限范围内查看匿名事实汇总与异常信号，以了解整体推广情况；它不评价个人，也不产生公开排行榜。
_Avoid_: 个人绩效、员工排行榜

**匿名统计阈值**:
管理分析中的一个筛选结果或统计分组只有包含至少十个该指标的真实统计单位时才显示精确值；接触型指标按有效接触记录，关系型指标按不同项目关系。阶段变更事件的个人值可以按事件计数，但未来管理 `k=10` 必须按不同“推广对象 × 推广项目”关系计数，不能用同一关系的重复事件凑足阈值。不足时统一表达为“样本不足”。个人查看自己的数据不受此限制。
_Avoid_: 全部按接触条数、重复事件凑阈值、界面隐藏、个人分析阈值

**贡献者保护**:
管理分析单元除了满足匿名统计阈值，还必须包含至少三位不同推广者，且任意一人贡献的统计单位不得超过该单元的一半；否则不展示精确匿名汇总。
_Avoid_: 单人汇总、少数人支配、记录足够即匿名

**互补隐藏**:
当一个统计分组因匿名统计阈值被隐藏时，同时隐藏其他必要分组或总数的保护方式，使人不能通过相减恢复小分组的精确值。
_Avoid_: 只隐藏小格子、可相减的总数、界面模糊

**去身份化异常记录**:
管理者为处理数据质量问题而查看的最小化单条记录；它可以包含纠错所需的时间、区域、定位状态和坐标，但不暴露推广者或推广对象的身份、联系方式和备注。
_Avoid_: 个人明细、完整接触记录
