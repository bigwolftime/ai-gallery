# OTA 增量更新（Shorebird）

## 两类更新

- 模型：继续使用 Hugging Face，独立下载、续传、SHA-256 校验。无需随 Dart 补丁重新下载。
- Flutter/Dart 代码：通过 Shorebird 发布与基础包版本绑定的增量补丁。

Swift/Kotlin、LiteRT-LM 框架、权限、Flutter 资源文件的变化需要新的基础包。模型清单是资源文件；更改它不能作为 Dart 补丁强行发布。远端模型清单方案见 `model-delivery.md`。

## 客户端行为

- 启动后异步检查，不等待更新服务器再显示照片/下载模型。
- 右上角“检查更新”可查看状态、当前补丁号、下载可用补丁。
- 下载完成后，下次完整启动才应用；不会强制退出 App。
- 新补丁不删除模型或照片索引。
- 普通 `flutter build` 包明确显示不支持在线更新，避免误报安装成功。
- `shorebird.yaml` 的 `auto_update: false` 由客户端控制下载流程。

## 当前基础版本

- App：AI Gallery
- Bundle ID / Android application ID：`com.aigallery.app`
- 基础包：`0.4.0+4`
- Shorebird Flutter：`3.47.7`（专用引擎，系统 Homebrew Flutter 保留）
- Shorebird App ID：`8bbe2ac9-0d49-49c0-98c4-8400cbaa7a71`
- 初始测试通道：`beta`，通过 `OTA_TRACK=beta` 编译。

必须先覆盖安装 Shorebird 生成的基础包。此前普通 Flutter 包无法接收补丁。保持签名身份和 Bundle ID 不变可保留本地数据。

## 初始化和构建

```sh
shorebird login
python3 scripts/ota.py init
python3 scripts/ota.py doctor

# 默认只构建/校验，不上传。
python3 scripts/ota.py release --platform ios --track beta
python3 scripts/ota.py release --platform android --track beta

# 上传首个 OTA 基础包。
python3 scripts/ota.py release --platform ios --track beta --publish
python3 scripts/ota.py release --platform android --track beta --publish

# iOS 未签名 archive 打包为可交给 SideStore 的 IPA。
# --ota 明确选取 archive，并检查版本、配置与更新引擎。
python3 scripts/package_ios.py --ota
```

`shorebird init` 生成真实 app ID；它可提交进版本库，不是密钥。登录凭证保留在 CLI 的用户目录，不放进项目或安装包。

## 发布补丁

修改 Dart 后保持 `pubspec.yaml` 的基础版本 `0.4.0+4` 不变。补丁号由 Shorebird 管理。

```sh
# 先校验，保留 native/asset diff 检查。
python3 scripts/ota.py patch --platform ios --track beta --release-version 0.4.0+4
python3 scripts/ota.py patch --platform android --track beta --release-version 0.4.0+4

# 校验通过后上传 beta 补丁。
python3 scripts/ota.py patch --platform ios --track beta --release-version 0.4.0+4 --publish
python3 scripts/ota.py patch --platform android --track beta --release-version 0.4.0+4 --publish
```

脚本不使用 `--allow-native-diffs` 或 `--allow-asset-diffs`。遇到这些差异应发新基础包；补丁自动使用原基础包的引擎。

beta 包只检查 beta 通道。生产包需使用 `--track stable` 构建与发布，避免混用。

发布基础包后，立即保留 IPA/APK，再执行 patch。patch 会覆盖 `build` 下的产物；不要把补丁构建产物当作基础包分发。此次基础安装包单独保存在 `dist/AI-Gallery-OTA-0.4.0-unsigned.ipa` 和 `dist/AI-Gallery-OTA-0.4.0.apk`，版本和校验值见 `dist/ota-baseline.json`。旧的 `AI-Gallery-Flutter` 安装包是普通 Flutter 包，不能用于验证 OTA。

## 验证与回滚

安装 OTA 基础包 → 打开检查更新 → 下载 beta 补丁 → 完全关闭并重新打开 → 当前补丁号增加，并确认旧图片索引仍可搜索。

覆盖安装时沿用此前的自签账号和应用标识，不先卸载。OTA 不替代 SideStore 的定期续签，补丁也不改变 iOS 签名有效期。

撤回补丁在 Shorebird 控制台操作。客户端检查更新会处理服务端的撤回状态；不要把 hot reload 当作补丁激活或回滚验证。

## 当前验证范围

客户端回归覆盖普通包不可用、检查超时、避免重复请求、下载成功、撤回、失败重试和完整重启提示。Shorebird Flutter 3.47.7 下静态检查通过，全部 27 项测试通过。

2026-10-13 已向用户账号发布 `0.4.0+4`，release ID 为 `894405`，iOS/Android 均为 active。安装产物已检查版本、可执行文件、Shorebird 更新符号与模型权重缺席。

当前 beta 测试补丁把“当前已是最新版本”调整为“当前应用已是最新版本”。它只修改 Dart 文案，保留基础版本号。手机收到补丁并完整重启后，可通过补丁号和这一文案确认生效。物理设备上的实际下载、激活和本地索引复用仍需安装测试。

实际发布成功：Android 补丁 1（arm64/x86_64，各约 12 KB），iOS 补丁 2（arm64，约 0.7 MB）。补丁号在同一 release 下递增，两个平台的当前补丁号不同是正常的。客户端检查和下载使用 beta 通道。

已直接请求客户端补丁检查接口，三个平台/架构组合都返回对应 beta 补丁且能完整下载。Android 还核对了服务端返回的目标 AOT 哈希与本次构建结果；此哈希用于重建后的代码文件，不能拿增量 diff 本身的哈希比较。发布回执和下载验证记录保存在 `dist/ota-deployment.json`。交付基础包的哈希在补丁构建后保持不变。

本机代理曾导致基础包存储上传很慢。重试 release 时将 `storage.googleapis.com` 加入 `NO_PROXY` 和 `no_proxy`，Shorebird API 仍走原代理后上传成功。后续 patch 下载基础包时直连较慢，改回代理后完成。此调整仅用于命令环境，不修改系统代理；按网络分别选择，其他网络无需照搬。

## 键盘与动效更新（2026-10-13）

最新 beta 补丁：iOS 4、Android 3，仍绑定基础版本 `0.4.0+4`。安装过该基础包的用户无需重新安装 IPA/APK，在更新入口检查并下载后，完全关闭并重开 App 即可。

- 输入框放进随键盘缩放的页面内容区，只避让一次键盘高度。
- 输入时显示“收起键盘”；点击外部、拖动照片列表、搜索提交或进入其他操作也会释放输入焦点，收起时保留未提交的文字。
- 新出现的照片淡入并轻微上移，勾选状态和底部操作区使用短过渡；系统减少动态效果开启时取消这些动效。
- 复用基础包已有的图标，未修改资源文件或 Swift/Kotlin，原生与资源差异校验通过。

静态检查和全部 31 项测试通过。新增测试覆盖 390×844 和 320×568 屏幕的键盘避让、避免重复抬高、收起后文字保留、iOS 外部点击/拖动收起以及减少动态效果。另用临时截图测试检查了键盘弹出/收起时的页面位置；这是模拟键盘高度的布局验证，不能代替真机输入法和流畅度测试。

正式 iOS 补丁报告 85.5% Dart 代码共享，Shorebird 提示部分补丁代码可能影响运行速度。补丁已发布到 beta，真机帧率尚未测量；照片分析仍由原生运行时执行。发布和下载回执见 `dist/ota-keyboard-update.json`，基础安装包保持原始版本供 OTA 测试。

## 设置、主题与更新弹窗（2026-10-13）

照片页增加“设置”，原来的更新入口移入设置页。主题默认跟随系统，也可选择深色或浅色，立即应用并保存，重新打开 App 后恢复。照片占位、输入框、辅助文字、详情页、卡片和更新弹窗都使用统一深浅主题；照片上的分数徽标保持白字黑底。

偏好文件为模型目录的同级 `settings.json`，iOS 对应 `Application Support/AIGallery/settings.json`。Dart 复用基础包已有的持久目录接口，无需增加原生插件。写入排队并原子替换；配置缺失/损坏时默认跟随系统，保存失败时在设置页提示重试。

检查更新后，仅有可下载更新或已下载待重启时弹出更新窗口；已是最新、失败或普通 Flutter 包不支持更新时，在设置页显示结果。更新弹窗在手机两侧各留 20 像素，最大宽度 440，操作按钮铺满内容区，内容可滚动以适配小屏和大字体。

静态检查、39 项回归测试和深浅主题截图检查通过。新测试覆盖磁盘保存/恢复、损坏配置、保存失败重试、快速切换顺序、启动读取竞争、系统主题变化、跨页面主题同步、无更新时不弹窗、320×568 屏幕及 1.4 倍字体下的更新下载流程。原生与资源差异保护保持开启，模型和索引不重新准备。

发布脚本现使用项目互斥锁，避免多个 Shorebird 命令同时替换/恢复同一份依赖配置。不要在 OTA 命令运行时另外执行 `flutter pub get` 或直接调用另一个 Shorebird 构建；通过同一脚本发起的命令会自动排队。

已发布到 beta：iOS 补丁 5（约 1.6 MB）、Android 补丁 6（arm64/x86_64，各约 0.95 MB）。iOS 代码共享率为 65.3%，工具仍提示可能影响补丁运行速度，真机流畅度未测量。发布与下载回执保存在 `dist/ota-settings-update.json`。使用当前版本的更新入口下载并完全重启后，后续更新入口即为“设置 → 检查更新”。

## 首页入口与照片分析位置（2026-10-13）

首页移除“选择”入口和分析图标，长按照片进入多选，点击其他照片继续选择，“完成”退出并清空选中状态。照片分析移至设置页第一项，显示运行进度，并在模型未准备或其他操作正在运行时禁用。

设置页复用首页持有的 `GalleryController`，继续调用原有的增量分析流程。返回首页不会创建新的分析任务或索引，也不取消已开始的任务；完成反馈继续由已有控制器监听呈现。

静态检查及 40 项测试通过。既有分享和减少动态效果测试改为使用长按；新增设置页集成测试验证第一项分析使用同一索引、跳过已分析的 20 张照片，并在增加 1 张照片后只追加处理 1 张。小屏设置页通过滚动访问更新入口。

已发布 beta：iOS 补丁 7、Android 补丁 8。原生和资源差异校验通过，基础安装包未重打；发布与下载回执见 `dist/ota-entry-update.json`。iOS 代码共享率仍为约 65.3%，工具性能提示保持存在，真机流畅度未测量。
