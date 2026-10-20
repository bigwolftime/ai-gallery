# 模型独立下载与托管

## 当前可用配置

当前模型同时使用 LiteRT Community 的 Hugging Face 和已验证的七牛 CDN 地址：

https://huggingface.co/litert-community/embeddinggemma-2-740m-litert-lm/resolve/main/embeddinggemma-2-740m.litertlm

https://img.zonheng.net/embeddinggemma-2-740m.litertlm

当前内置 Hugging Face 清单的模型哈希保持不变，由 Dart 为这个已知哈希补充七牛镜像，允许通过 OTA 启用而无需修改安装包资源。未来其他模型可在清单中显式提供 `mirrors` 数组；旧清单仍兼容。

下载前并行获取各源前 256 KiB，以含 DNS/TLS/重定向的实际耗时排序，每个探测总超时 5 秒。达到采样上限立即关闭连接，避免忽略 Range 的服务器传完模型；仍可能有少量网络预读。单源跳过测速，已验证的本地模型和完整下载的待校验文件也不测速。最快源失败后自动尝试备用源，正确的前缀继续断点续传；校验失败会删除无效内容，恢复下载混入坏前缀时允许在当前源从零重试一次。磁盘错误不通过重复下载重试。

元数据在 `assets/models/model-manifest.json`。现在只把清单打进安装包，不打包约 485 MB 的模型。首次使用显示下载确认；下载失败/暂停后保留按 SHA-256 命名的 `.partial` 文件。校验通过后原子重命名为 `.litertlm`，后续启动可离线复用。

当前为前台下载：iOS/Android 在 App 挂起或退出时可能中断，下次打开点击继续即可续传。没有接入 OS 后台下载任务。

## 需要提供的服务能力

1. HTTPS 文件托管。可使用对象存储 + CDN（OSS、COS、S3 等），提供稳定的公开下载链接，无需业务数据库。
2. 支持 HTTP `Range: bytes=N-`，正常返回 `206` 和准确的 `Content-Range`。若服务忽略 Range 返回 `200`，客户端会重新从头写入，不会追加重复数据。
3. 模型 JSON 清单，提供地址、字节长度、SHA-256、模型版本、维度和视觉 token 配置。
4. 版本化文件路径，例如 `/models/embeddinggemma2/v1/model.litertlm`。每个路径对应不可变内容；上传完整文件之后才发布清单。
5. 下载流量和可用性。每台首次使用设备约下载 485 MB；100 台首次使用约 48.5 GB。建议根据用户所在区域选择节点。

这是原生 App 下载，CDN 不需要浏览器 CORS 设置。不需要上传用户照片。无需把 CDN 管理密钥放入 App。

## 清单格式

```json
{
  "schemaVersion": 1,
  "name": "embeddinggemma-2-740m",
  "modelVersion": "embeddinggemma-2-256-v1",
  "url": "https://your-cdn.example/models/embeddinggemma2/v1/model.litertlm",
  "mirrors": ["https://your-backup.example/models/embeddinggemma2/v1/model.litertlm"],
  "sha256": "e7a8a2204b91e0f96e92960e84a09a89212e1633dcb7575a9bf3378b4df77f4c",
  "size": 484622336,
  "dimensions": 256,
  "visionTokens": 70
}
```

以上校验值对应当前官方通用 LiteRT-LM 模型。上传相同文件时值保持不变。换文件必须重新计算哈希和大小。

## 发布清单

修改内置 JSON 的 `url` / `mirrors` 需要新基础包，因为它们是资源文件；当前已知模型的七牛兼容配置在 Dart 中。希望以后无需重装 App 就发布新模型时，可以托管远端 JSON 并在构建时配置固定清单地址：

```sh
flutter build ios --no-codesign --dart-define=MODEL_MANIFEST_URL=https://your-cdn.example/models/manifest.json
JAVA_HOME=/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home flutter build apk --release --target-platform android-arm64,android-x64 --dart-define=MODEL_MANIFEST_URL=https://your-cdn.example/models/manifest.json
```

远端不可用时回退到已缓存的清单或内置清单。只支持当前运行时可加载的 `.litertlm` 模型、256 维和 70 vision tokens；运行时变化仍需发布 IPA/APK。

新内容使用新的哈希路径，旧已验证文件保留。索引身份由模型内容哈希和推理配置确定；当前相同模型特别兼容旧 `embeddinggemma-2-256-v1` 索引。更换内容后旧向量不会用于新模型检索，用户需要重新分析。

## 存储与升级

- iOS：`Application Support/AIGallery/models`，排除 iCloud 备份。
- Android：`noBackupFilesDir/models`。
- 模型不在 cache 中，系统清缓存不会移除模型；卸载 App 会删除模型和索引。
- 完整大小与 SHA-256 校验是首次激活条件；已验证文件通过校验标记和大小检查复用。
- 模型 JSON 已缓存，已下载模型的普通离线启动无需访问网络。
- 模型下载与已接入的 Shorebird 代码 OTA 独立；新增下载源不会改变相同模型的索引身份。

## 七牛 CDN 配置核对（2026-10-20）

`img.zonheng.net` 已绑定 `pictures` 源站，状态成功，使用场景为下载分发，覆盖全球，CNAME 已配置。HTTPS、强制 HTTPS、HTTP/2 和 Range 回源均已开启；现有全局缓存规则为 1 个月，适合当前不可变模型文件。模型 URL 实测返回 206，大小 484,622,336 字节，ETag `lkYR9Qt-bPE_n3JDKqJhTxmq2Rm6` 与本地相同；两个源的 256 KiB 采样内容均匹配同一模型前缀。

本次仅查看线上配置。后续建议：

- 保持 Range 回源和现有 HTTPS 设置；模型更新使用新文件名/版本路径，不覆盖旧文件名。
- 缓存参数保留现状，同一域名还有图片，不能为模型全局忽略所有参数，否则会影响图片处理。
- 在 CDN 的“告警配置”配置流量告警；在域名“安全防护 → 用量封顶”按试用预算设置上限。每个首次完整下载约 0.485 GB，预算还需包含图片、测速和重试。封顶影响整个域名，且周期性统计存在延迟。
- 当前时间戳防盗链、Referer 防盗链和回源鉴权未启用。原生 App 不宜依赖 Referer 防盗链；开启时间戳鉴权前先接服务端生成短期签名 URL，不能在 App 内保存签名密钥，也不能把一次性签名 URL 写死。

下载器测试覆盖并行选源、超时和暂停、跨源续传、坏内容回退、坏前缀从零恢复、忽略 Range 时提前断开连接、HTTPS 镜像校验和原模型索引兼容。共享下载流程适用于 iOS/Android。
