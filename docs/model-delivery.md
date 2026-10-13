# 模型独立下载与托管

## 当前可用配置

默认地址为 LiteRT Community 的 Hugging Face 文件：

https://huggingface.co/litert-community/embeddinggemma-2-740m-litert-lm/resolve/main/embeddinggemma-2-740m.litertlm

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
  "sha256": "e7a8a2204b91e0f96e92960e84a09a89212e1633dcb7575a9bf3378b4df77f4c",
  "size": 484622336,
  "dimensions": 256,
  "visionTokens": 70
}
```

以上校验值对应当前官方通用 LiteRT-LM 模型。上传相同文件时值保持不变。换文件必须重新计算哈希和大小。

## 发布清单

最简单方式是修改内置 JSON 的 `url` 后打包。希望以后无需重装 App 就发布新模型时，可以托管远端 JSON 并在构建时配置固定清单地址：

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
- 本功能不包含 Flutter 代码 OTA；Shorebird 仍未接入。
