# 同行者 / Outreach Companion

同行者是一个 Flutter 开发的双语实地推广记录 App 原型。它面向不同城市的团队，帮助成员快速记录接触时间、地点、基础问卷、多条联系方式、关系/兴趣度，并给管理员提供定位校正与统计视图。

## 项目文档

现代化产品的完整需求、架构边界、交付顺序和验收合同见 [docs/PRODUCT_SPEC.md](docs/PRODUCT_SPEC.md)；统一领域词汇见 [CONTEXT.md](CONTEXT.md)，单项决策见 [docs/adr/](docs/adr/)。

[docs/PROJECT_DESIGN.md](docs/PROJECT_DESIGN.md) 保留为当前 legacy demo 的历史设计资料，可能与已确认的新模型冲突，不再作为新功能实现依据。

如果你是刚开始学 Flutter / Dart / Git，可以先读 [docs/BEGINNER_LEARNING_GUIDE.md](docs/BEGINNER_LEARNING_GUIDE.md)。它按“先看哪个文件、顺便补什么基础知识”的方式带你拆这个项目。

## 当前功能

- 中文 / English 界面切换
- 跟随系统 / 浅色 / 深色主题切换
- 快速记录：时间自动生成，定位自动请求，也可补充具体所在地
- 基础问卷：姓名、英文姓名、平均心率、性别、身份、年龄段、态度、备注
- 多联系方式：微信、电话、邮箱、WhatsApp、其他，可一条条添加
- 演示登录/注册/忘记密码/修改密码：本地模拟云端用户表
- 权限过滤：普通用户只看自己采集的数据，城市管理员看本城市，组织管理员看全部
- 平均心率：当前为权限与无设备状态模拟，真实移动端可接 HealthKit / Google Fit
- 本机持久化：记录和设置保存在设备本地
- 管理员模式：筛出没有定位、定位精度较差、未核准的记录并校正地点
- 统计图表：今日数量、总数、正向态度数、待校正数，按小时、身份、态度统计
- 匿名统计导出：不导出姓名、联系方式、备注等个人信息

## 本地运行

```bash
flutter pub get
flutter run
```

运行测试：

```bash
flutter test
flutter analyze
```

如果项目路径包含中文而 `flutter analyze` 崩溃，可以先运行 `dart analyze`，或者把项目临时复制到 ASCII 路径再运行 `flutter analyze`。

## App 数据模型

当前原型已经使用本地 SQLite。Flutter 侧采用 Drift 打开数据库，核心本地表包括：

- `db_users`: 本地假云端用户表
- `db_conversation_records`: 交谈记录主表
- `db_record_contacts`: 多条联系方式子表
- `db_app_settings`: 语言、主题、当前用户等设置
- `db_security_events`: 登录失败、锁定、重置密码等安全事件

记录主表的核心字段包括：

- `id`: 本机生成的记录 ID
- `createdAt`: 记录时间
- `cityName`, `teamName`, `recorderName`: 城市、团队、记录人
- `personName`, `englishName`: 对方姓名，可选
- `averageHeartRate`: 当时平均心率，可选
- `latitude`, `longitude`, `locationAccuracyMeters`, `locationError`: 自动定位结果
- `manualPlaceName`: 具体所在地
- `gender`, `identity`, `ageRange`: 问卷字段
- `relationshipLevel`: 关系/跟进阶段，范围为 `1..4`
- `contacts[]`: 多条联系方式，每条包含 `channel` 和 `value`
- `attitudeLevel`: 五级态度，范围为 `-2..2`
- `notes`: 其他备注
- `isLocationVerified`, `correctedLatitude`, `correctedLongitude`, `correctedPlaceName`, `correctedAt`: 管理员校正字段

生产版本建议把当前本地 SQLite 升级为加密 SQLite，例如 Drift + SQLCipher，并保留离线 outbox。网络恢复后先同步 outbox，再刷新最近记录缓存。

当前 demo 的数据实际存在 SQLite：

- Web 运行时：Drift 的 Web SQLite 后端，浏览器会用 OPFS 或 IndexedDB 保存 `tongxingzhe_local`
- macOS / iOS / Android / Windows / Linux 运行时：应用文档目录里的 `tongxingzhe_local.sqlite`
- Web 所需资源：`web/sqlite3.wasm` 和 `web/drift_worker.js`

因此现在的“假云端用户表”和“假记录表”已经是本地 SQL 表。下一步如果要模拟云同步，可以再加 `pending_mutations` 表，把同步目标换成 Snowflake 后端 API。

## 演示账号

本地 demo 会自动生成用户和假记录，不需要手工一条条录入。密码与用户名相同：

- `admin1` / `admin1`: 组织管理员，可看所有城市
- `admin2` / `admin2`: Chicago 城市管理员
- `admin3` / `admin3`: New York 城市管理员
- `user1` / `user1`: Chicago 普通用户
- `user2` / `user2`: New York 普通用户

当前按你的要求，演示登录流程会把输入密码转换为 MD5 后与本地“假云端”用户表对比。连续失败 4 次会把账户锁定 30 天。这个锁定状态会写回本地用户表，字段包括 `failedLoginCount`, `lockedUntil`, `lastFailedLoginAt`。真实云端也应该保留一张 `security_events` 或审计表，记录登录失败、锁定、重置密码等异常。

MD5 只适合这个 demo 阶段。上线时仍建议改成外部认证服务，或至少换成 Argon2id / bcrypt / PBKDF2。

## 数据库设计建议

你的管理员表和普通用户表建议合并成一张 `app_users`。理由是：一万级用户量很小，不需要为了性能拆表；管理员和普通用户的共同字段很多；用 `role_level` 或 `role_code` 区分权限更容易维护。超过一年不访问的用户可以通过 `last_seen_at` 和定时任务做禁用或删除。

密码在当前 demo 中按你的要求用 MD5 对比。正式版本不要明文保存，也不要继续用 MD5。推荐使用外部认证服务，例如 Auth0、AWS Cognito、Firebase Auth、Supabase Auth，App 后端只保存外部身份 ID。若必须自建密码登录，保存 Argon2id、bcrypt 或 PBKDF2 这种带盐的慢哈希，并记录 `password_hash`, `password_algo`, `password_updated_at`。Snowflake 账号本身也正在强化 MFA/强认证，所以不要让移动 App 直接保存 Snowflake 用户密码。

建议的核心表：

- `organizations`: 一个总项目或机构
- `cities`: 城市工作区，例如 `Chicago, IL`
- `teams`: 城市内小组
- `app_users`: 所有管理员和普通用户
- `city_memberships`: 用户和城市/团队的关系
- `conversation_records`: 实际采集到的交谈记录
- `record_contacts`: 联系方式子表
- `record_revisions`: 管理员校正和审计历史
- `security_events`: 登录失败、账户锁定、密码重置等安全事件
- `sync_outbox`: 客户端或后端同步队列

## Snowflake 草案

Snowflake 很适合作为分析与长期存储层。它支持 `VARIANT` 存 JSON/半结构化数据，支持 `GEOGRAPHY` 做地理分析，也有 Hybrid Tables 可服务轻量事务型应用，但 Hybrid Tables 有云区域与功能限制，真正上线前要看你的 Snowflake account 是否支持。

一个可落地的 Snowflake 草案：

```sql
create table organizations (
  organization_id varchar primary key,
  name varchar not null,
  created_at timestamp_ntz not null
);

create table cities (
  city_id varchar primary key,
  organization_id varchar not null,
  city_label varchar not null,
  timezone varchar not null,
  created_at timestamp_ntz not null
);

create table app_users (
  user_id varchar primary key,
  organization_id varchar not null,
  display_name varchar not null,
  email varchar,
  phone varchar,
  role_level number(3, 0) not null,
  auth_provider varchar,
  auth_subject varchar,
  password_hash varchar,
  password_algo varchar,
  failed_login_count number(3, 0) default 0,
  locked_until timestamp_ntz,
  status varchar not null,
  last_seen_at timestamp_ntz,
  created_at timestamp_ntz not null,
  updated_at timestamp_ntz not null
);

create table security_events (
  event_id varchar primary key,
  user_id varchar,
  event_type varchar not null,
  event_detail variant,
  created_at timestamp_ntz not null
);

create table city_memberships (
  membership_id varchar primary key,
  user_id varchar not null,
  city_id varchar not null,
  team_id varchar,
  role_level number(3, 0) not null,
  created_at timestamp_ntz not null
);

create table conversation_records (
  record_id varchar primary key,
  collector_user_id varchar not null,
  city_id varchar not null,
  city_label varchar not null,
  collected_at timestamp_ntz not null,
  latitude float,
  longitude float,
  geog geography,
  location_accuracy_m float,
  exact_place varchar,
  average_heart_rate float,
  gender_code varchar,
  person_name varchar,
  english_name varchar,
  identity_code varchar,
  relationship_level number(1, 0),
  attitude_score number(2, 0),
  notes varchar,
  contacts_json variant,
  is_location_verified boolean default false,
  corrected_latitude float,
  corrected_longitude float,
  corrected_geog geography,
  corrected_place varchar,
  created_at timestamp_ntz not null,
  updated_at timestamp_ntz not null
);

create table record_contacts (
  contact_id varchar primary key,
  record_id varchar not null,
  contact_type varchar not null,
  contact_value varchar not null,
  created_at timestamp_ntz not null
);

create table record_revisions (
  revision_id varchar primary key,
  record_id varchar not null,
  editor_user_id varchar not null,
  revision_type varchar not null,
  before_json variant,
  after_json variant,
  created_at timestamp_ntz not null
);
```

经纬度建议保留两列 `latitude` / `longitude`，同时生成 `GEOGRAPHY` 列，原因是两列 float 方便 App 调试和普通 SQL 入门，`GEOGRAPHY` 则方便以后做距离、范围、热力图等空间分析。Snowflake WKT 点的顺序是 `POINT(longitude latitude)`，不要写反。

联系方式我建议同时做两层：

- `record_contacts`: 规范化子表，方便统计“多少人留下微信/电话”等
- `contacts_json`: 原始 JSON 快照，方便回放客户端提交内容和排查同步问题

敏感字段如姓名、联系方式、备注，应在应用后端加密或脱敏后再进入 Snowflake。Snowflake 也有行访问策略和动态数据脱敏能力，但这不是替代应用层加密的理由。

## 本地缓存设计

本地 App 只需要保留：

- `recent_records`: 最近 10 条完整记录，用于快速查看和修改
- `pending_mutations`: 尚未成功同步的新增/修改/删除操作
- `settings`: 当前城市、团队、语言、主题、登录态摘要

本地推荐加密 SQLite，而不是 CSV。CSV 不适合多联系方式、离线修改、冲突处理和加密。同步成功后，服务端返回记录版本号；如果最近 10 条里某条被修改，本地先更新缓存，再把 mutation 放进 outbox。

## 开源与数据安全

这个 App 可以开源，关键是让代码仓库只包含代码、测试和假数据，不包含真实收集数据。

已做的保护：

- `.gitignore` 排除 `.env`、密钥和 secrets 目录
- 演示数据由 App 本机生成，都是合成内容
- 匿名统计导出不包含联系方式、姓名、备注、记录人
- `CONTRIBUTING.md` 明确提醒不要提交真实个人数据

后续上线前还应做：

- 数据库备份和导出文件默认加密
- 真实数据绝不提交到 GitHub issue、PR、fixture 或截图
- 对联系方式字段做端到端或字段级加密
- 给团队成员设置最小权限
- 为删除、导出、管理员校正保留审计日志

## 参考

- Snowflake Hybrid Tables: https://docs.snowflake.com/en/user-guide/tables-hybrid
- Snowflake semi-structured data types: https://docs.snowflake.com/en/sql-reference/data-types-semistructured
- Snowflake `TO_GEOGRAPHY`: https://docs.snowflake.com/en/sql-reference/functions/to_geography
- Snowflake MFA / strong authentication rollout: https://docs.snowflake.com/en/user-guide/security-mfa-rollout
- Snowflake authentication policies: https://docs.snowflake.com/en/user-guide/authentication-policies

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE).
