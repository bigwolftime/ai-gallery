# 整包版本更新

App 启动后及“设置 → 检查更新”先检查远端整包版本，再检查 Shorebird 补丁。新基础包优先于旧基础包的补丁；网络失败会明确提示整包版本未确认，不把“暂无补丁”显示成“应用已是最新”。照片、模型初始化不等待版本检查。

## 两个平台的行为

- Android 直接分发版：显示版本、大小、说明，下载 APK，可暂停/续传。完成 SHA-256 校验后，原生端再次检查包名、实际版本、递增 buildNumber 和签名。首次安装需在系统页面允许此来源，返回后点“继续安装”，由用户在系统安装界面确认。
- iOS 自签版：显示新版本和说明，打开 IPA 下载地址，下载后交给 SideStore 等工具重新签名并覆盖安装。App 无法替用户静默安装，也不续期签名。
- 商店版：预留 `play` / `store` / `appstore` / `testflight` 渠道记录，打开相应 HTTPS 商店页面。当前 Android 包为直接分发版；以后提交 Google Play 前，需单独构建商店变体并移除 `REQUEST_INSTALL_PACKAGES` 权限。

保持实际应用标识和签名身份一致、覆盖安装且不先卸载，才可保留模型、索引和设置。更新 APK 缓存在独立目录，下载新包时清理旧安装缓存，不接触模型或索引。系统也可能回收缓存，届时重新下载即可。

## 版本清单

默认地址为 `https://img.zonheng.net/apps/ai-gallery/releases.json`，可通过 `--dart-define=APP_RELEASE_MANIFEST_URL=...` 更改。必须为 HTTPS。客户端限制响应大小 64 KiB、总等待 12 秒；请求携带唯一 `check` 参数和 `no-cache`，避免图片域名的长期缓存隐藏新版本。CDN 必须保留此查询参数，推荐单独把该路径 TTL 设为 0 或很短。

```json
{
  "schemaVersion": 1,
  "appId": "com.aigallery.app",
  "releases": [
    {
      "platform": "android",
      "channel": "direct",
      "kind": "apk",
      "version": "0.4.4",
      "buildNumber": 8,
      "url": "https://example.com/apps/ai-gallery/0.4.4-8/android/app.apk",
      "sha256": "<64位小写SHA-256>",
      "size": 123,
      "notes": "更新说明"
    }
  ]
}
```

按原生安装包的数字 `buildNumber` 判断新旧，严格匹配平台和渠道；不能只修改清单版本号指向旧 APK。APK 必填 SHA-256 与字节数。iOS 自签使用 `platform: ios`、`channel: sideload`、`kind: ipa`；商店渠道使用 `kind: store`。自动识别安装来源，也可在构建时通过 `APP_DISTRIBUTION_CHANNEL` 指定渠道。

## 构建与发布顺序

1. 修改 `pubspec.yaml`，递增 buildNumber；运行测试与静态检查。
2. 使用 `scripts/ota.py release --platform android|ios --track beta --publish` 发布新的 Shorebird 基础版本。可以传入 `--app-release-manifest-url` 和 `--distribution-channel`。Swift/Kotlin 改动不能通过补丁替代。
3. 保存原始发布 APK；iOS 用 `python3 scripts/package_ios.py --ota` 生成未签名 IPA。不要拿后续补丁构建的 APK 替换基础包。
4. 生成清单和上传计划：

```sh
python3 scripts/prepare_app_release.py \
  --apk dist/AI-Gallery-OTA-0.4.4.apk \
  --ipa dist/AI-Gallery-OTA-0.4.4-unsigned.ipa
```

脚本读取 APK/IPA 内的真实版本，计算 SHA-256 和字节数，输出 `dist/app-updates/releases.json` 与 `upload-plan.json`。只更新一个平台时，先取回现网清单并传入 `--merge-from <现网清单>`，保留另一平台和渠道。默认七牛对象路径为 `apps/ai-gallery/<版本>-<build>/<平台>/<文件名>`；版本文件不可覆盖复用。

5. 按计划先上传 APK/IPA，确认 HTTPS 地址可下载且长度/校验值匹配，再发布 `releases.json`。发布清单会让已安装且具备此功能的旧版发现新包。

Shorebird 保存构建产物供开发者取用，但不代替客户端整包分发渠道。七牛承载清单、APK/IPA，Shorebird 承载补丁，两者各自发布。

首次接入需要手动覆盖安装包含原生接口的 0.4.4+8 基础包；此前版本没有 APK 安装能力。后续整包与补丁均可从 App 检查入口发现。
