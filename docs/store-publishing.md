# Android 商店发布

计划调整（2026-10-20）：目前只有开发者本人测试，用户改为评估更易开始分发的渠道。F-Droid/Play 的代码准备保留，尚未提交收录或上架申请。

当前工作版本：0.4.5+9。线上自签基础包仍是 0.4.4+8；本次不替换其七牛清单、安装包或 Shorebird release。

## 已确定的发行方式

| 渠道 | Android 应用标识 | 更新方式 | 签名 |
| --- | --- | --- | --- |
| 自签测试 | com.aigallery.app | Shorebird + 七牛 APK | 原测试签名 |
| GitHub / Uptodown / OpenAPK Beta | net.zonheng.aigallery | Shorebird + 独立七牛 APK 清单 | 正式发行密钥 |
| F-Droid | net.zonheng.aigallery | F-Droid 客户端 | 默认由 F-Droid 构建、签名 |
| Google Play | net.zonheng.aigallery | Google Play | 正式上传密钥 + Play App Signing |

项目代码、原生桥接和原创商店美术采用用户确认的 Apache-2.0。模型、转换版模型均标注 Apache-2.0，LiteRT-LM 0.18.0 Maven POM 同样声明 Apache-2.0；第三方组件保留其各自许可与版权。

正式 Android ID 已由域名持有人确认。正式版与测试版数据空间独立，不能直接读取测试版下载的模型、索引和设置。不要为了迁移而卸载仍需保留数据的测试版。F-Droid 与 Play 的签名通常不同，相同应用 ID 不能默认相互覆盖；跨渠道签名迁移应在发布前另行规划，不能使用测试 debug key 提交 Play。

## 构建

公开 Beta 使用 Shorebird 构建，保留应用内更新，版本清单为 `https://img.zonheng.net/apps/ai-gallery/public/releases.json`。该清单的 `appId` 为 `net.zonheng.aigallery`，与旧测试版根目录清单隔离；不要覆盖旧测试版及 iOS 的清单。

```sh
# 不上传的正式签名候选构建。
python3 scripts/ota.py release --platform android --track beta --distribution-channel public

# 验证候选后，创建可接收后续补丁的基础版本。
python3 scripts/ota.py release --platform android --track beta --distribution-channel public --publish
```

公开 APK 发布前运行 `scripts/test_android_store.py --channel public --require-signed` 和 `scripts/test_android_runtime.py`。独立发行与商店构建必须保留各自的渠道配置，不能把公开 Beta 上传成禁止站外更新的商店构建。

正式签名证书 SHA-256 为 `68d79f85fc5e5e63efc4eb3e3678ed1a9d8d2422040866460fd4df493a600fa8`。私有的 `android/ai-gallery-release.jks` 与 `android/key.properties` 需一起安全备份；丢失会影响后续覆盖升级。公开源码不包含私钥。

以下 F-Droid / Play 构建复用普通 Flutter 3.41.9（commit `00b0c91f06209d9e4a41f71b7a512d6eb3b9c694`），不使用 Shorebird 引擎。JDK 17+（本机 21），Android SDK 36，NDK 27.0.12077973。

```sh
# F-Droid 自行签名，构建产物应为未签名 APK。
python3 scripts/build_android_store.py --channel fdroid --unsigned

# Play 审阅产物；未签名 AAB 不能直接上传 Play Console。
python3 scripts/build_android_store.py --channel play --unsigned

# 完成正式上传密钥配置后，构建已签名 Play AAB。
# 将 android/key.properties.example 复制为私有的 android/key.properties。
python3 scripts/build_android_store.py --channel play
```

脚本将 Gradle 渠道与 Dart 渠道同时设置，使用互斥锁避免与 OTA 构建并发替换依赖配置。商店构建强制应用标识为 `net.zonheng.aigallery`，移除 `REQUEST_INSTALL_PACKAGES` 和更新 FileProvider，禁止自动访问七牛整包清单及 Shorebird。设置页只引导去对应商店。

`android/key.properties`、`.jks`、`.keystore` 已加入忽略列表。不要将真实密钥、密码提交 Git；正式密钥应离线备份。F-Droid 源码构建不需要开发者私钥。

最终产物在 `dist/stores/`。`scripts/test_android_store.py` 检查最终 APK/AAB 的正式 ID、版本、渠道、安装权限、provider、普通 Flutter 引擎、模型不内置和 16 KB ELF 对齐；APK 还检查 ZIP 对齐。AAB 需官方 bundletool jar，可通过 `--bundletool` 指定。本机复用已有 bundletool 工具，不把它打进 App。

## F-Droid 主仓库

不能只提交本地 APK；需公开、可构建的源码版本及维护者审核。当前 GitHub 仓库公开，但尚需把本次改动发布为固定 tag。申请草稿见 `fdroid/request-for-packaging.md`，商店文案、美术和示例截图放在 `fastlane/metadata/android/`。

2026-10-20 查阅的官方收录政策要求项目通常已有至少 3 个月活跃开发，存在“已有实际用户”等例外。项目目前较新，需补充真实试用和反馈证据，或继续开发积累维护记录；不能保证立即收录。自建 F-Droid 仓库可让用户手动添加，但不会自动进入官方主仓库目录。

Android 原生依赖来自 Google Maven / Maven Central，当前政策允许可信 Maven 来源的自由软件预编译依赖，不应笼统认定所有 AAR 都必须重新编译。维护者仍需审查完整依赖链。仓库中的 iOS Framework 不参与 Android 构建；配方扫描时可删除 `packages/ai_gallery_native/ios/Frameworks/`，而不是修改项目实际 iOS 工作文件。

模型由用户主动下载，固定 SHA-256；下载的是模型数据，运行库随 App 打包。商店版没有应用内补丁或 APK 下载。F-Droid 官方政策也允许满足明确自愿同意条件的额外可执行文件下载，本项目选择统一由商店负责更新。

## Google Play

普通 Google 账号还需要注册 Play Console 开发者账号。官方费用为 US$25 一次性注册费，并要求身份验证。新个人开发者账号还需 Android 设备验证；先准备一台可运行 Play Console 的合格 Android 真机，不能只依赖当前模拟器。

2023-11-13 后创建的个人开发者账号：至少 12 名测试者连续加入封闭测试 14 天，然后申请生产发布权限。内部测试不替代这项要求，测试者还需实际使用并提供反馈。

自 2026-08-31 起，Google Play 新应用和更新要求 targetSdk 36 或更高。本项目目标为 36。16 KB ELF/ZIP 对齐通过不等同于已在 16 KB 真机验证运行。

上架前还需完成：正式上传密钥、AAB、开发者联系邮箱、公开隐私政策 URL、数据安全表、内容分级、目标受众、照片权限用途声明及真机测试。App 的全图库访问服务于核心本地搜索与增量索引，需在照片权限声明中如实解释；不请求视频或“所有文件访问”权限。

数据安全声明不要只根据“本地 AI”就全部勾选不收集：照片、查询和向量不上传；模型下载时的 IP/请求日志需结合下载服务商的实际处理确认。商店版没有 Shorebird 安装标识及更新运行状态上报。政策正文与 App 内本地隐私页面保持一致，见 `docs/privacy-policy.md`。

## 参考依据（2026-10-20）

- https://f-droid.org/en/docs/Inclusion_Policy/
- https://f-droid.org/en/docs/Anti-Features/
- https://huggingface.co/google/embeddinggemma-2
- https://huggingface.co/litert-community/embeddinggemma-2-740m-litert-lm
- https://support.google.com/googleplay/android-developer/answer/6112435
- https://support.google.com/googleplay/android-developer/answer/14151465
- https://support.google.com/googleplay/android-developer/answer/16559646
- https://support.google.com/googleplay/android-developer/answer/11926878
