package com.aigallery.nativebridge

import android.app.Activity
import android.content.Context
import android.content.ClipData
import android.content.Intent
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import java.io.File

/** Version reads and APK validation never share the model's long-running worker. */
class AppUpdateService(private val context: Context) {
    companion object {
        private const val DIRECTORY = "app-updates"
        private const val APK_MIME_TYPE = "application/vnd.android.package-archive"
        private const val PLAY_INSTALLER = "com.android.vending"
    }
    fun directory(): File = File(context.cacheDir, DIRECTORY).apply { mkdirs() }

    fun info(): Map<String, Any> {
        val current = context.packageManager.getPackageInfo(context.packageName, 0)
        val installer = runCatching {
            if (Build.VERSION.SDK_INT >= 30) context.packageManager.getInstallSourceInfo(context.packageName).installingPackageName
            else @Suppress("DEPRECATION") context.packageManager.getInstallerPackageName(context.packageName)
        }.getOrNull()
        return mapOf("platform" to "android", "channel" to if (installer == PLAY_INSTALLER) "play" else "direct",
            "version" to (current.versionName ?: ""), "buildNumber" to buildNumber(current))
    }

    private fun buildNumber(info: PackageInfo): Long = if (Build.VERSION.SDK_INT >= 28) info.longVersionCode
        else @Suppress("DEPRECATION") info.versionCode.toLong()

    @Suppress("DEPRECATION")
    fun validate(path: String, version: String, expectedBuild: Long): File {
        val file = File(path).canonicalFile
        check(file.parentFile == directory().canonicalFile && file.isFile && file.extension == "apk") { "安装包路径不正确，请重新下载。" }
        val flags = if (Build.VERSION.SDK_INT >= 28) PackageManager.GET_SIGNING_CERTIFICATES else PackageManager.GET_SIGNATURES
        val installed = context.packageManager.getPackageInfo(context.packageName, flags)
        val candidate = context.packageManager.getPackageArchiveInfo(file.path, flags)
            ?: error("无法读取安装包，请重新下载。")
        check(candidate.packageName == context.packageName) { "安装包不属于 AI Gallery。" }
        check(buildNumber(candidate) == expectedBuild && candidate.versionName == version && expectedBuild > buildNumber(installed)) { "安装包版本不匹配或不是更新版本。" }
        val signatureMatches = if (Build.VERSION.SDK_INT >= 28) {
            val old = checkNotNull(installed.signingInfo) { "无法读取当前应用签名。" }
            val next = checkNotNull(candidate.signingInfo) { "无法读取安装包签名。" }
            val currentSigners = old.apkContentsSigners.map { it.toCharsString() }.toSet()
            val nextSigners = next.apkContentsSigners.map { it.toCharsString() }.toSet()
            if (old.hasMultipleSigners() || next.hasMultipleSigners()) currentSigners == nextSigners
            else {
                // Accept a legitimate forward signing-key rotation, never an
                // unrelated certificate or a downgrade to an earlier key.
                val lineage = (next.signingCertificateHistory ?: next.apkContentsSigners).map { it.toCharsString() }.toSet()
                currentSigners.isNotEmpty() && lineage.containsAll(currentSigners)
            }
        } else {
            val currentSigners = installed.signatures?.map { it.toCharsString() }?.toSet().orEmpty()
            currentSigners.isNotEmpty() && currentSigners == candidate.signatures?.map { it.toCharsString() }?.toSet()
        }
        check(signatureMatches) { "安装包签名与当前应用不一致，无法保留数据覆盖安装。" }
        return file
    }

    fun openInstaller(host: Activity, file: File): String {
        if (!context.packageManager.canRequestPackageInstalls()) {
            host.startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:${context.packageName}")))
            return "permissionRequired"
        }
        val uri = FileProvider.getUriForFile(context, "${context.packageName}.ai_gallery.updates", file, "AI-Gallery-update.apk")
        host.startActivity(Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, APK_MIME_TYPE)
            clipData = ClipData.newRawUri("AI Gallery update", uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        })
        return "opened"
    }

    fun openUrl(host: Activity, value: String) {
        val url = Uri.parse(value)
        require(url.scheme == "https" && !url.host.isNullOrBlank()) { "更新地址必须使用 HTTPS。" }
        host.startActivity(Intent(Intent.ACTION_VIEW, url))
    }
}
