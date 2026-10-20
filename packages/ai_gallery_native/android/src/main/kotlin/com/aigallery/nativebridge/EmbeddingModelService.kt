package com.aigallery.nativebridge

import android.content.Context
import android.os.Build
import android.util.Log
import com.google.ai.edge.litertlm.Backend
import com.google.ai.edge.litertlm.EmbeddingEngine
import com.google.ai.edge.litertlm.EmbeddingEngineConfig
import com.google.ai.edge.litertlm.EmbeddingOptions
import com.google.ai.edge.litertlm.InputData
import java.io.File
import kotlin.math.sqrt

/** Called only on the plugin's serial worker; GPU context and index never cross threads. */
class EmbeddingModelService(private val context: Context) {
    companion object {
        private const val TAG = "AIGalleryModel"
        private val EMULATOR_HARDWARE = setOf("goldfish", "ranchu")
    }

    private val index = EmbeddingIndexService(context)
    private var engine: EmbeddingEngine? = null
    private val options = EmbeddingOptions(normalize = true, outputSize = EmbeddingIndexService.DIMENSIONS, visionTokensPerImage = 70)

    private var loadedPath: String? = null
    fun modelDirectory(): File = File(context.noBackupFilesDir, "models").apply { mkdirs() }

    fun initialize(path: String, version: String) {
        if (engine != null && loadedPath == path && index.modelVersion == version) return
        val file = File(path).canonicalFile
        check(file.parentFile == modelDirectory().canonicalFile && file.isFile && version.isNotBlank()) { "下载模型不存在或路径不正确。" }
        engine?.close(); engine = null
        // Emulator Vulkan can initialize successfully but stall on inference.
        // CPU works for both modalities; physical devices retain GPU acceleration.
        val emulator = Build.HARDWARE in EMULATOR_HARDWARE
        val backend = if (emulator) Backend.CPU() else Backend.GPU()
        val runtimeCache = File(context.cacheDir, if (emulator) "LiteRTLM-cpu" else "LiteRTLM").apply { mkdirs() }
        Log.i(TAG, "Initializing embeddings with ${if (emulator) "CPU (emulator)" else "GPU"}")
        val loaded = EmbeddingEngine(EmbeddingEngineConfig(modelPath = file.absolutePath, backend = backend,
            visionBackend = backend, cacheDir = runtimeCache.absolutePath, visionTokensPerImage = 70))
        loaded.initialize()
        engine = loaded
        loadedPath = path
        index.modelVersion = version
    }
    fun hasAny(ids: List<String>) = ids.any { index.has(it) }
    fun analyze(ids: List<String>, photos: PhotoLibraryService, progress: (Int, Int) -> Unit): Map<String, Int> {
        val runtime = checkNotNull(engine) { "模型未初始化。" }
        val accessible = photos.photos().map { it.id }.toSet()
        val pending = ids.distinct().filter { it in accessible && !index.has(it) }
        var succeeded = 0
        progress(0, pending.size)
        pending.forEachIndexed { position, id ->
            val vector = try {
                normalize(runtime.computeEmbedding(listOf(InputData.Image(photos.jpeg(id, 1024))), options).embedding)
            } catch (failure: Exception) {
                // Preserve the underlying inference error for Android diagnostics.
                Log.w(TAG, "Unable to analyze photo $id", failure)
                null
            }
            // Save errors are surfaced; failed photo reads/inference remain pending for retry.
            if (vector != null) { index.upsert(id, vector); succeeded++ }
            progress(position + 1, pending.size)
        }
        return mapOf("processed" to pending.size, "succeeded" to succeeded, "failed" to pending.size - succeeded)
    }
    fun search(query: String, photos: PhotoLibraryService, limit: Int): List<Map<String, Any>> {
        val runtime = checkNotNull(engine) { "模型未初始化。" }
        val vector = normalize(runtime.computeEmbedding(listOf(InputData.Text("task: search query | text: ${query.trim()}")), options).embedding)
        return index.rank(vector, photos.photos(), limit)
    }
    private fun normalize(vector: FloatArray): FloatArray {
        require(vector.size >= EmbeddingIndexService.DIMENSIONS) { "无效向量维度。" }
        val values = vector.copyOf(EmbeddingIndexService.DIMENSIONS)
        require(values.all { it.isFinite() }) { "无效向量。" }
        val norm = sqrt(values.sumOf { it.toDouble() * it.toDouble() })
        require(norm.isFinite() && norm > 0) { "空向量。" }
        return FloatArray(values.size) { (values[it] / norm).toFloat() }
    }
    fun close() { engine?.close(); engine = null; index.close() }
}
