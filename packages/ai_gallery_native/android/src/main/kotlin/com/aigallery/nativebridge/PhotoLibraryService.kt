package com.aigallery.nativebridge

import android.content.ContentUris
import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.ImageDecoder
import android.graphics.Matrix
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import androidx.exifinterface.media.ExifInterface
import java.io.ByteArrayOutputStream
import java.time.Instant
import kotlin.math.max
import kotlin.math.roundToInt

/** MediaStore identifiers stay stable across app updates; no absolute storage paths. */
data class GalleryPhoto(val id: String, val uri: Uri, val createdAt: String, val width: Int, val height: Int) {
    fun map(): Map<String, Any> = mapOf("id" to id, "uri" to uri.toString(), "createdAt" to createdAt, "width" to width, "height" to height)
}

class PhotoLibraryService(private val context: Context) {
    fun photos(): List<GalleryPhoto> {
        val columns = arrayOf(MediaStore.Images.Media._ID, MediaStore.Images.Media.DATE_ADDED,
            MediaStore.Images.Media.DATE_TAKEN, MediaStore.Images.Media.WIDTH, MediaStore.Images.Media.HEIGHT)
        val result = mutableListOf<GalleryPhoto>()
        context.contentResolver.query(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, columns, null, null,
            "${MediaStore.Images.Media.DATE_ADDED} DESC")?.use { cursor ->
            while (cursor.moveToNext()) {
                val id = cursor.getLong(0)
                val taken = cursor.getLong(2).takeIf { it > 0 } ?: cursor.getLong(1) * 1000
                result += GalleryPhoto("media:$id", ContentUris.withAppendedId(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, id),
                    Instant.ofEpochMilli(taken).toString(), cursor.getInt(3), cursor.getInt(4))
            }
        }
        return result
    }

    fun uri(id: String): Uri {
        require(id.startsWith("media:")) { "Invalid photo identifier" }
        val value = id.substringAfter("media:").toLong()
        return ContentUris.withAppendedId(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, value)
    }

    /** Decode at bounded size and apply EXIF orientation before inference or display. */
    fun jpeg(id: String, maxSize: Int): ByteArray {
        val uri = uri(id)
        val bitmap = if (Build.VERSION.SDK_INT >= 28) {
            ImageDecoder.decodeBitmap(ImageDecoder.createSource(context.contentResolver, uri)) { decoder, info, _ ->
                val ratio = (maxSize.toFloat() / max(info.size.width, info.size.height)).coerceAtMost(1f)
                decoder.setTargetSize(max(1, (info.size.width * ratio).roundToInt()), max(1, (info.size.height * ratio).roundToInt()))
                decoder.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
            }
        } else {
            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            context.contentResolver.openInputStream(uri).use { BitmapFactory.decodeStream(it, null, bounds) }
            var sample = 1
            while (max(bounds.outWidth, bounds.outHeight) / sample > maxSize * 2) sample *= 2
            val options = BitmapFactory.Options().apply { inSampleSize = sample }
            val decoded = context.contentResolver.openInputStream(uri).use { BitmapFactory.decodeStream(it, null, options) }
                ?: error("Unable to read image")
            val exif = context.contentResolver.openInputStream(uri).use { ExifInterface(requireNotNull(it)) }
            val matrix = Matrix().apply {
                if (exif.isFlipped) postScale(-1f, 1f)
                postRotate(exif.rotationDegrees.toFloat())
            }
            val oriented = Bitmap.createBitmap(decoded, 0, 0, decoded.width, decoded.height, matrix, true)
            if (oriented !== decoded) decoded.recycle()
            val ratio = (maxSize.toFloat() / max(oriented.width, oriented.height)).coerceAtMost(1f)
            val resized = Bitmap.createScaledBitmap(oriented, max(1, (oriented.width * ratio).roundToInt()), max(1, (oriented.height * ratio).roundToInt()), true)
            if (resized !== oriented) oriented.recycle()
            resized
        }
        return try {
            ByteArrayOutputStream().use { output ->
                check(bitmap.compress(Bitmap.CompressFormat.JPEG, 88, output))
                output.toByteArray()
            }
        } finally { bitmap.recycle() }
    }
}
