package com.ezcar24.business.data.images

import android.content.Context
import dagger.hilt.android.qualifiers.ApplicationContext
import java.io.File
import java.util.UUID
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

@Singleton
class ImageStore @Inject constructor(
    @ApplicationContext private val context: Context
) {
    private val directory: File by lazy {
        File(context.filesDir, "VehicleImages").apply { mkdirs() }
    }

    fun imageFile(id: UUID): File = File(directory, "${id}.jpg")

    suspend fun saveImage(id: UUID, data: ByteArray) = withContext(Dispatchers.IO) {
        val file = imageFile(id)
        file.parentFile?.mkdirs()
        file.writeBytes(data)
    }

    suspend fun loadImage(id: UUID): ByteArray? = withContext(Dispatchers.IO) {
        val file = imageFile(id)
        if (file.exists()) file.readBytes() else null
    }

    fun hasImage(id: UUID): Boolean = imageFile(id).exists()

    suspend fun deleteImage(id: UUID) = withContext(Dispatchers.IO) {
        imageFile(id).delete()
    }

    suspend fun clearAll() = withContext(Dispatchers.IO) {
        if (directory.exists()) {
            directory.deleteRecursively()
        }
    }
}
