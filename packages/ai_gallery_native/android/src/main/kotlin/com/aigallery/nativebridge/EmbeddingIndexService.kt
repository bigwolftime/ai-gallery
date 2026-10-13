package com.aigallery.nativebridge

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import java.nio.ByteBuffer
import java.nio.ByteOrder

/** Persist each successful embedding so restarts and incremental runs can resume. */
class EmbeddingIndexService(context: Context) : SQLiteOpenHelper(context, "photo-embeddings.db", null, 1) {
    companion object {
        const val VERSION = "embeddinggemma-2-256-v1"
        const val DIMENSIONS = 256
    }
    var modelVersion: String = VERSION
    override fun onCreate(db: SQLiteDatabase) {
        db.execSQL("CREATE TABLE embeddings (asset_id TEXT PRIMARY KEY NOT NULL, model_version TEXT NOT NULL, vector BLOB NOT NULL)")
    }
    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) = Unit
    fun has(id: String): Boolean = readableDatabase.query("embeddings", arrayOf("asset_id"),
        "asset_id = ? AND model_version = ?", arrayOf(id, modelVersion), null, null, null).use { it.moveToFirst() }
    fun upsert(id: String, vector: FloatArray) {
        val buffer = ByteBuffer.allocate(vector.size * 4).order(ByteOrder.LITTLE_ENDIAN)
        vector.forEach { buffer.putFloat(it) }
        val values = ContentValues().apply {
            put("asset_id", id); put("model_version", modelVersion); put("vector", buffer.array())
        }
        check(writableDatabase.insertWithOnConflict("embeddings", null, values, SQLiteDatabase.CONFLICT_REPLACE) != -1L) { "Unable to save index" }
    }
    fun rank(query: FloatArray, photos: List<GalleryPhoto>, limit: Int): List<Map<String, Any>> {
        val byId = photos.associateBy { it.id }
        val ranked = mutableListOf<Pair<GalleryPhoto, Double>>()
        readableDatabase.query("embeddings", arrayOf("asset_id", "vector"), "model_version = ?", arrayOf(modelVersion), null, null, null).use { cursor ->
            while (cursor.moveToNext()) {
                val photo = byId[cursor.getString(0)] ?: continue
                val bytes = cursor.getBlob(1)
                if (bytes.size != query.size * 4) continue
                val buffer = ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN)
                var dot = 0.0
                for (value in query) dot += value * buffer.float
                if (dot.isFinite()) ranked += photo to dot
            }
        }
        val sorted = ranked.sortedByDescending { it.second }
        return (if (limit > 0) sorted.take(limit) else sorted).map { mapOf("photo" to it.first.map(), "score" to it.second) }
    }
}
