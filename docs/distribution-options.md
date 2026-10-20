# 早期 Android 分发渠道（2026-10-20）

用户目前仅本人测试，因此暂缓 F-Droid 主仓库与 Google Play 首次正式发布，转向低门槛渠道。已采用 Apache-2.0 与正式 Android ID net.zonheng.aigallery，发布 0.4.5 Beta 1，并提交 Uptodown、OpenAPK，等待编辑审核。F-Droid / Play 尚未提交。发布回执见 [Beta 发布记录](releases/0.4.5-beta.1-publishing.md)。

| 渠道 | 定位 | 当前适配情况 |
| --- | --- | --- |
| Uptodown | 应用商店，有公开目录与编辑审核 | 官方发布流程支持 Beta/Alpha/Pre-Alpha。公开审核条件未列 Google 式固定测试人数或三个月开发期；仍检查功能、权限/安全、版权和素材质量。可上传 APK 或使用直链，当前包大小远低于其 4 GB 文件上传阈值。 |
| GitHub Releases + 七牛 | 公开发布与下载，不是应用商店 | 无固定测试人数或项目年龄条件，适合先发正式签名 Beta。GitHub 提供版本与反馈入口，国内下载可继续使用七牛。GitHub 官方说明单个 Release 文件小于 2 GiB，未设发布总大小或带宽上限。 |
| OpenAPK | 开源 Android 应用目录 | 官方提交表要求代码仓库，并明确要求仓库 Releases 中已有 APK。公开说明未列固定测试人数或开发时长，不保证自动收录。Apache-2.0 与公开仓库方向匹配。 |
| 蒲公英 | 内测和链接/二维码分发 | 官方目前宣称分发功能永久免费；开发者须实名认证并遵守审核规则，实际账号下载等限制以平台提示为准。安装者不需要注册/实名。缺少应用商店自然曝光。 |
| 自建 F-Droid 仓库 | 自行托管的 F-Droid 兼容源 | 不适用官方主仓库的项目成熟期收录条件。需要维护 APK、签名索引和密钥；用户需手动添加源，不会自动出现在官方主仓库目录。 |

建议：先用 GitHub Releases + 七牛发布 Beta、收集真实反馈；希望进入应用商店时优先评估 Uptodown，同时可申请 OpenAPK 展示。

IzzyOnDroid 不作为本项目优先备选：其政策通常为每个应用保留约 30 MB（允许个别例外），当前 APK 约 85–91 MB；现行 AI policy 还明确拒绝 vibe-coded 应用，并限制生成式 AI 代码进入项目。不能将它当作对本项目更宽松的替代，或隐瞒代码来源申请收录。

参考：

- https://docs.github.com/en/repositories/releasing-projects-on-github/about-releases
- https://obtainium.imranr.dev/
- https://support.uptodown.com/hc/en-us/articles/360052792972-Uptodown-s-app-publication-criteria
- https://support.uptodown.com/hc/en-us/articles/360053260491-How-to-publish-an-app-on-Uptodown
- https://www.openapk.net/developers/
- https://www.openapk.net/submitapp/
- https://www.pgyer.com/app/distribution
- https://www.pgyer.com/doc/view/Certified
- https://f-droid.org/en/docs/Inclusion_Policy/
- https://izzyondroid.org/docs/general/AppInclusionPolicy/
