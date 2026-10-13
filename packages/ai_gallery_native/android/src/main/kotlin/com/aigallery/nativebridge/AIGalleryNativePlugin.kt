package com.aigallery.nativebridge

import android.Manifest
import android.app.Activity
import android.content.ClipData
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import java.util.concurrent.Executors

/** Permissions and presentation run on main; all model operations use one native worker. */
class AIGalleryNativePlugin : FlutterPlugin, MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler, ActivityAware, PluginRegistry.RequestPermissionsResultListener {
    companion object { private const val PERMISSION_REQUEST = 4211 }
    private lateinit var binding: FlutterPlugin.FlutterPluginBinding
    private lateinit var channel: MethodChannel
    private lateinit var progress: EventChannel
    private lateinit var photos: PhotoLibraryService
    private lateinit var model: EmbeddingModelService
    private val main = Handler(Looper.getMainLooper())
    private val modelWorker = Executors.newSingleThreadExecutor()
    private val imageWorker = Executors.newFixedThreadPool(2)
    private var activityBinding: ActivityPluginBinding? = null
    private var activity: Activity? = null
    private var events: EventChannel.EventSink? = null
    private var permissionResult: MethodChannel.Result? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        this.binding = binding
        photos = PhotoLibraryService(binding.applicationContext)
        model = EmbeddingModelService(binding.applicationContext)
        channel = MethodChannel(binding.binaryMessenger, "ai_gallery/native")
        progress = EventChannel(binding.binaryMessenger, "ai_gallery/progress")
        channel.setMethodCallHandler(this); progress.setStreamHandler(this)
    }
    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null); progress.setStreamHandler(null)
        modelWorker.execute { model.close() }; modelWorker.shutdown(); imageWorker.shutdown()
    }
    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activityBinding = binding; activity = binding.activity; binding.addRequestPermissionsResultListener(this)
    }
    override fun onDetachedFromActivityForConfigChanges() { detachActivity() }
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) { onAttachedToActivity(binding) }
    override fun onDetachedFromActivity() { detachActivity() }
    private fun detachActivity() {
        activityBinding?.removeRequestPermissionsResultListener(this); activityBinding = null; activity = null
    }

    private fun authorized(): Boolean {
        val context = binding.applicationContext
        val permission = if (Build.VERSION.SDK_INT >= 33) Manifest.permission.READ_MEDIA_IMAGES else Manifest.permission.READ_EXTERNAL_STORAGE
        return context.checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED ||
            (Build.VERSION.SDK_INT >= 34 && context.checkSelfPermission(Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED) == PackageManager.PERMISSION_GRANTED)
    }
    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray): Boolean {
        if (requestCode != PERMISSION_REQUEST) return false
        val result = permissionResult ?: return true
        permissionResult = null
        if (authorized()) worker(result) { photos.photos().map { it.map() } }
        else result.error("PHOTO_PERMISSION", "请允许 AI Gallery 访问照片。", null)
        return true
    }
    private fun worker(result: MethodChannel.Result, image: Boolean = false, action: () -> Any?) {
        (if (image) imageWorker else modelWorker).execute {
            try { val value = action(); main.post { result.success(value) } }
            catch (failure: Throwable) { main.post { result.error("NATIVE_ERROR", failure.message ?: failure.javaClass.simpleName, null) } }
        }
    }
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getModelDirectory" -> worker(result) { model.modelDirectory().absolutePath }
            "initializeModel" -> worker(result) {
                model.initialize(requireNotNull(call.argument<String>("modelPath")), requireNotNull(call.argument<String>("indexVersion")))
                null
            }
            "loadPhotos" -> {
                if (authorized()) worker(result) { photos.photos().map { it.map() } }
                else {
                    val host = activity
                    if (host == null) { result.error("NO_ACTIVITY", "页面未准备好。", null); return }
                    if (permissionResult != null) { result.error("BUSY", "权限请求正在进行。", null); return }
                    permissionResult = result
                    val permissions = if (Build.VERSION.SDK_INT >= 34) arrayOf(Manifest.permission.READ_MEDIA_IMAGES, Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED)
                        else if (Build.VERSION.SDK_INT >= 33) arrayOf(Manifest.permission.READ_MEDIA_IMAGES)
                        else arrayOf(Manifest.permission.READ_EXTERNAL_STORAGE)
                    host.requestPermissions(permissions, PERMISSION_REQUEST)
                }
            }
            "loadThumbnail", "loadImage" -> worker(result, image = true) { photos.jpeg(requireNotNull(call.argument<String>("id")), if (call.method == "loadImage") 2400 else 360) }
            "shouldOfferAnalysis" -> result.success(!binding.applicationContext.getSharedPreferences("AIGallery", 0).getBoolean("didAskAnalysis", false))
            "dismissAnalysisPrompt" -> {
                binding.applicationContext.getSharedPreferences("AIGallery", 0).edit().putBoolean("didAskAnalysis", true).apply()
                result.success(null)
            }
            "openSettings" -> {
                activity?.startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:${binding.applicationContext.packageName}")))
                result.success(null)
            }
            "hasIndexedPhotos" -> worker(result) { model.hasAny(call.argument<List<String>>("photoIds") ?: emptyList()) }
            "analyzePhotos" -> worker(result) {
                model.analyze(call.argument<List<String>>("photoIds") ?: emptyList(), photos) { completed, total ->
                    main.post { events?.success(mapOf("completed" to completed, "total" to total)) }
                }
            }
            "search" -> worker(result) { model.search(call.argument<String>("query") ?: "", photos, call.argument<Int>("limit") ?: 0) }
            "sharePhotos" -> {
                val host = activity ?: run { result.error("NO_ACTIVITY", "页面未准备好。", null); return }
                val ids = call.argument<List<String>>("photoIds") ?: emptyList()
                modelWorker.execute {
                    try {
                        val allowed = photos.photos().associateBy { it.id }
                        val uris = ArrayList(ids.mapNotNull { allowed[it]?.uri })
                        check(uris.isNotEmpty()) { "图片已删除或无法访问。" }
                        main.post {
                            try {
                                val intent = Intent(if (uris.size == 1) Intent.ACTION_SEND else Intent.ACTION_SEND_MULTIPLE).apply {
                                    type = "image/*"
                                    if (uris.size == 1) putExtra(Intent.EXTRA_STREAM, uris.first()) else putParcelableArrayListExtra(Intent.EXTRA_STREAM, uris)
                                    clipData = ClipData.newUri(host.contentResolver, "AI Gallery", uris.first()).also { clip -> uris.drop(1).forEach { clip.addItem(ClipData.Item(it)) } }
                                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                }
                                host.startActivity(Intent.createChooser(intent, "分享图片"))
                                result.success(null)
                            } catch (failure: Exception) {
                                result.error("SHARE_ERROR", failure.message, null)
                            }
                        }
                    } catch (failure: Exception) {
                        main.post { result.error("SHARE_ERROR", failure.message, null) }
                    }
                }
            }
            else -> result.notImplemented()
        }
    }
    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) { this.events = events }
    override fun onCancel(arguments: Any?) { events = null }
}
