# 健康（iOS 原生项目源码）

这是一个 SwiftUI + HealthKit 原生 iPhone 项目，面向 iPhone 14 Pro。当前交付的是源码和云端构建配置，**不是已经编译、签名或实机验证的 IPA**。

## 功能与数据边界

- 请求 Apple HealthKit 读取权限。
- 读取 Apple 健康中的最新心率、最新血氧。
- 汇总当天步数、步行/跑步距离、活动能量。
- 汇总睡眠样本时长；当前版本不提供独立睡眠评分或完整睡眠阶段分析。
- iOS 26 使用原生 Liquid Glass 卡片；旧版 iOS 使用半透明材质兼容样式。
- 数据仅在设备本地读取和显示，不上传第三方服务器。

本 App 不直接通过蓝牙连接 Redmi Watch 6。数据链路是 Redmi Watch 6 → Mi Fitness → Apple 健康 → 本 App。只有 Mi Fitness 实际写入 Apple 健康的数据才可能被读取；不能保证每种指标都可同步。请先在 iPhone「健康」App 中确认数据来源和类别。

## 必须先修改的项目标识

项目当前使用占位 Bundle ID：`com.example.healthapp`。发布前必须在以下位置统一改成你自己唯一的 Bundle ID：

1. `RedmiHealthSync/RedmiHealthSync.xcodeproj/project.pbxproj` 中的 `PRODUCT_BUNDLE_IDENTIFIER`（Debug 和 Release 两处）。
2. `RedmiHealthSync/codemagic.yaml` 中两个 workflow 的 `bundle_identifier`。
3. Apple Developer Portal 的 Identifiers/App ID 与 App Store Connect App 记录。

App 显示名称已设为「健康」。不要把 Bundle ID 留成 `com.example.healthapp`。

## 无 Mac 的建议安装路线：Codemagic → TestFlight

对只有 iPhone、没有电脑的用户，优先使用 TestFlight：云端构建并上传到 TestFlight 后，在 iPhone 安装 TestFlight，再从 TestFlight 安装 App。这样不需要把 Ad Hoc IPA 通过电脑侧载工具装入手机。TestFlight 仍需要 Apple 账号、App Store Connect App 记录、有效签名和苹果处理构建。

### A. Apple Developer / App Store Connect 准备

1. 在 Apple Developer → Certificates, Identifiers & Profiles → Identifiers 创建显式 App ID，Bundle ID 与项目保持一致。
2. 在 App ID 的 Capabilities 中启用 HealthKit，并保存。
3. 在 App Store Connect → Apps 新建 iOS App 记录，Bundle ID 选择同一个 App ID。
4. 在 App Store Connect → Users and Access → Integrations → App Store Connect API 创建 API Key。建议使用满足上传需要的权限角色（通常 App Manager 或 Admin）。
5. 下载 `.p8` 私钥；它只应上传到 Codemagic 的安全集成页面，**不要发给聊天、邮件或任何人**。记录 Key ID 和 Issuer ID。

### B. GitHub 准备（可用 iPhone Safari）

1. 在 GitHub 创建一个 Private repository。
2. 在 iPhone「文件」App 解压本 ZIP。
3. 把解压后的 `RedmiHealthSync` 文件夹中的项目内容上传到仓库根目录，确保仓库根目录直接包含 `RedmiHealthSync.xcodeproj` 所在的 `RedmiHealthSync/` 文件夹和 `codemagic.yaml`。
4. 不要把 `.p8`、证书私钥、密码或个人配置文件上传到 GitHub。

### C. Codemagic 云端构建

1. 打开 https://codemagic.io/ 并用 GitHub 授权登录，添加刚创建的仓库。
2. 在 Codemagic Team integrations 中添加名为 `App Store Connect` 的集成，使用前面创建的 API Key（Key ID、Issuer ID 和 `.p8` 内容）。
3. 在项目设置中启用/识别仓库中的 `codemagic.yaml`。
4. 选择 workflow：`health-ios-testflight`，确认 Bundle ID 与 App Store Connect 记录完全一致。
5. 启动构建，查看 Xcode 编译、签名、上传日志。只有全部成功才会得到 IPA，并将构建提交到 TestFlight。
6. 在 iPhone 安装 TestFlight，从邀请或内部测试页面安装构建。首次测试时，在 App 内触发 HealthKit 授权，并在 iPhone「健康」App 的数据访问权限中检查授权。

### D. 另一个 workflow

`health-ios-development` 用于已注册设备的开发签名 IPA。它要求设备 UDID 已加入 Apple Developer 设备列表，并且相应 provisioning profile 包含该设备。对没有电脑的情况，优先采用 TestFlight workflow。

## HealthKit 说明

- `NSHealthShareUsageDescription` 已在 `Info.plist` 配置。
- `com.apple.developer.healthkit` 已在 entitlements 文件声明。
- Apple Developer Portal 的 App ID 必须实际启用 HealthKit，签名 profile 也必须包含对应 entitlement；仅在源码写入 entitlement 不代表授权成功。
- HealthKit 读取授权有隐私保护：App 无法可靠区分用户拒绝读取与数据库没有数据。界面显示「—」不代表一定没有授权。
- HealthKit 查询成功不等于数据来自 Redmi Watch 6；如需确认来源，必须在 Apple 健康中查看具体样本来源，并在实机上验证。

## 当前版本限制

- 当前没有在本环境执行 Xcode/iOS SDK 编译，未生成签名 IPA，也未在 iPhone 实机测试。
- 当前睡眠时长查询以当天为窗口，跨午夜睡眠统计可能不完整。
- 当前不计算睡眠评分，不伪造深睡、浅睡或 REM 数据。
- 本 App 不是医疗器械，不能用于诊断、治疗或紧急监测。

## 官方入口

- Apple Developer: https://developer.apple.com/programs/
- App Store Connect: https://appstoreconnect.apple.com/
- Codemagic: https://codemagic.io/
- TestFlight: https://developer.apple.com/testflight/
- HealthKit: https://developer.apple.com/documentation/healthkit
