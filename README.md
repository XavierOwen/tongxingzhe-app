# 同行者 / Outreach Companion

同行者是一个六平台 Flutter App，帮助个人和团队记录不限渠道的“推广接触”，进行自我问责、后续跟进与隐私保护的汇总分析。它不限定宗教场景：福音外展、课程推广、销售推广等都使用同一套中性的领域语言。

本仓库同时是一套正式上线代码和 Flutter／SQL 学习材料；不另维护与生产脱节的教学 App。

## 当前状态

项目已完成 [Slice 0：安全地基与可测试接缝](https://github.com/XavierOwen/tongxingzhe-app/issues/2) 和 [Slice 1：匿名接触闭环](https://github.com/XavierOwen/tongxingzhe-app/issues/3)，正在实施 [Slice 2：离线事实更正、重试与合并](https://github.com/XavierOwen/tongxingzhe-app/issues/4)。Backend 可验证 Supabase JWT，并原子映射内部用户、个人空间、多个个人项目和各项目当前问卷版本。Flutter `AppSession` 只接受这份可信上下文。正式 App 已接入邮箱密码登录、四个主导航、可选跨设备私有草稿、冲突副本、七类匿名接触、已提交接触的追加式更正与作废、独立的未获回应接触尝试、IANA 发生时区、面对面坐标、版本化严格区域树、“今日”与最近七日个人统计，以及 SQLite 到自有 Backend／PostgreSQL 的持久双向同步。坐标自动解析到区域节点、问卷题目、正式注册与恢复界面仍未完成。旧原型只作为显式 legacy Demo 保留。

已经建立的地基包括：

- 正式 composition root，以及可控制的 Clock、ID、Database、Identity、错误结果和 Platform Capability 接缝；
- 正式入口与 MD5、默认演示账号、自动 seed 和旧登录 UI 的 import 边界；
- Drift v5 基线、v6／v7／v8／v9／v10 中间版本、当前 v11 schema 快照和 v5／v6／v8／v9／v10→v11 升级测试；
- `ContactJournal` 本地深模块，以及可读的 SQLite 个人汇总 SQL；
- Supabase `IdentitySession` Adapter、安全 session／PKCE 存储和 test-only fake；
- PostgreSQL 有序 SQL migration、checksum、最小权限 runtime role、synthetic fixture 和恢复检查；
- 自有 Backend 的 JWKS 验证、`(issuer, subject) → app_user_id` 映射和上下文端点；
- 六平台 build、格式、静态分析、测试、文档链接和生成文件 CI；
- 与代码一同演进的中文开发说明书。

Supabase 仍是有条件首选。SDK 接线完成不等于六平台认证通过；真实 OTP、安全存储和重启恢复状态见 [六平台认证 Spike](docs/spikes/supabase-auth-six-platform.md)。

## 权威文档

- [产品规格](docs/PRODUCT_SPEC.md)：需求、架构、切片与 Definition of Done；
- [统一领域语言](CONTEXT.md)：术语及其精确定义；
- [架构决策索引](docs/adr/README.md)：每项决策的状态、取代关系、关联 Slice 和主题入口；
- [正式开发说明书](docs/manual/README.md)：面向初学者解释 Flutter、SQL、设计和数学背景的唯一入口；
- [Legacy v5 盘点](docs/migrations/legacy-v5-inventory.md)：旧 schema、数据分类和停止规则；
- [PostgreSQL migration 说明](backend/database/README.md)：空库重建、权限与 fixture。
- [Backend 运行说明](backend/server/README.md)：身份验证、配置、测试和上下文端点。

`docs/PROJECT_DESIGN.md` 和 `docs/BEGINNER_LEARNING_GUIDE.md` 是 legacy Demo 历史资料，不作为现代功能实现依据。

## 安全运行

安装依赖并启动正式入口：

```bash
flutter pub get
flutter run
```

没有 Supabase 配置时，正式 App 会显示认证尚未接入的安全状态；它不会创建演示账号或记录。配置真实 test project 时只传 publishable key：

```bash
flutter run \
  --dart-define=SUPABASE_URL='https://YOUR_TEST_PROJECT.supabase.co' \
  --dart-define=SUPABASE_PUBLISHABLE_KEY='sb_publishable_REPLACE_ME' \
  --dart-define=BACKEND_BASE_URL='https://YOUR_BACKEND.example.com'
```

Flutter 中禁止出现 Supabase secret/service-role key、PostgreSQL 密码或 warehouse 凭据。

macOS 真实运行需要 Apple Development 签名。复制本地签名示例并填写自己的 Team ID；目标文件已被 Git 忽略：

```bash
cp -n macos/Runner/Configs/LocalSigning.xcconfig.example \
  macos/Runner/Configs/LocalSigning.xcconfig
```

CI 的 macOS job 只做无签名编译，不能代替 Keychain 运行时探针；完整状态见六平台认证 Spike。

需要回归旧原型时，必须显式选择 Demo 入口：

```bash
flutter run -t lib/main_demo.dart
```

这个入口才会装配 MD5 兼容 Adapter、旧登录页、默认演示账号和 synthetic records。它不是 production 入口。

## 本地检查

```bash
dart format --output=none --set-exit-if-changed \
  lib test integration_test test_driver tool
dart analyze
flutter test --no-pub
dart run tool/check_production_boundary.dart
dart run tool/check_markdown_links.dart
```

若中文路径使 `flutter analyze` 的 analysis server 输出异常，可使用 `dart analyze`；这不是跳过静态分析。

Drift 当前 v11 快照和 v5／v6／v8／v9／v10→v11 升级检查：

```bash
flutter test test/data/local_database_migration_test.dart
```

PostgreSQL 空库重建需要一个明确的测试数据库，详见 [数据库说明](backend/database/README.md)。

## 数据边界

- Drift／SQLite 是设备离线数据库；
- PostgreSQL 是自有 HTTPS Backend 的共享事务数据库；
- Flutter 不直连 PostgreSQL，也不通过 Supabase Data API 读写业务表；
- Snowflake 类 warehouse 将来只接收经过批准的去身份化分析事实，不保存 Auth schema、推广对象 PII、精细位置或私人备注；
- 仓库只允许代码、schema 与明确标记 synthetic 的 fixture，不允许真实用户数据库、导出、截图或密钥。

## 开发流程

需求与实现由 GitHub Issues 管理。每个垂直切片同时更新：

1. 领域词汇／ADR／Spec（若语义变化）；
2. 正式 Flutter 与 SQL 代码；
3. 负向和失败测试；
4. `docs/manual/` 对应章节；
5. 六平台与 migration 证据。

这样，需求更新不会只改 UI 文案，而会沿着领域合同、数据库、测试和说明书一起演进。

## License

本项目使用 MIT License，详见 [LICENSE](LICENSE)。
