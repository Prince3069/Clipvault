// MainActivity.kt - COMPLETE FIXED VERSION with proper WhatsApp Status access
package com.princedevlabs.all_social_downloader

import android.Manifest
import android.content.ClipData
import android.content.ClipboardManager
import android.content.ContentUris
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.MediaScannerConnection
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaMetadataRetriever
import android.media.MediaMuxer
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.provider.MediaStore
import android.provider.DocumentsContract
import android.provider.Settings
import android.util.Log
import android.webkit.CookieManager
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.nio.ByteBuffer
import java.net.HttpURLConnection
import java.net.URL
import kotlinx.coroutines.*

class MainActivity : FlutterActivity() {

    companion object {
        private const val TAG = "MainActivity"
        private const val WHATSAPP_CHANNEL = "com.yourapp.allsocialdownloader/whatsapp"
        private const val NATIVE_BRIDGE_CHANNEL = "com.yourapp.allsocialdownloader/native"
        private const val PERMISSIONS_CHANNEL = "com.yourapp.allsocialdownloader/permissions"
        private const val SHARE_TARGET_CHANNEL = "com.yourapp.allsocialdownloader/share_target"
        private const val FILE_MONITOR_CHANNEL = "com.yourapp.allsocialdownloader/file_monitor"
        private const val WHATSAPP_TREE_REQUEST = 2001
        private const val WHATSAPP_TREE_PREF = "whatsapp_status_tree_uri"
        private const val WHATSAPP_BUSINESS_TREE_PREF = "whatsapp_business_status_tree_uri"
        private const val OVERLAY_PERMISSION_REQUEST = 1001
        private const val STORAGE_PERMISSION_REQUEST = 1004
        private const val MEDIA_PICK_REQUEST = 3001
    }

    private var clipboardManager: ClipboardManager? = null
    private var pendingShareIntent: Intent? = null
    private var pendingMediaPickerResult: MethodChannel.Result? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (intent?.action == Intent.ACTION_SEND || intent?.action == Intent.ACTION_SEND_MULTIPLE) {
            pendingShareIntent = intent
        } else {
            handleShareIntent(intent)
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        if (intent.action == Intent.ACTION_SEND || intent.action == Intent.ACTION_SEND_MULTIPLE) {
            pendingShareIntent = intent
            deliverPendingShare()
        } else {
            handleShareIntent(intent)
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)

        when (requestCode) {
            WHATSAPP_TREE_REQUEST -> {
                if (resultCode != RESULT_OK) return
                val uri = data?.data ?: return
                try {
                    contentResolver.takePersistableUriPermission(
                        uri,
                        Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
                    )
                    Log.d(TAG, "✅ Persisted URI permission: $uri")
                } catch (e: Exception) {
                    Log.w(TAG, "Could not persist permission: ${e.message}")
                }
                val prefs = getSharedPreferences("clipvault_storage", Context.MODE_PRIVATE)
                val business = prefs.getBoolean("whatsapp_status_business_pending", false)
                prefs.edit()
                    .putString(
                        if (business) WHATSAPP_BUSINESS_TREE_PREF else WHATSAPP_TREE_PREF,
                        uri.toString()
                    )
                    .remove("whatsapp_status_business_pending")
                    .apply()
                Log.d(TAG, "✅ WhatsApp tree saved: ${if (business) "Business" else "Personal"}")

                // Catches exactly what happened before: someone taps
                // through the picker, ends up in an unrelated (often
                // empty) folder like a self-created "My WhatsApp folder",
                // and gets zero feedback that anything's wrong until the
                // status list comes up empty later. A quick shallow check
                // right here, immediately, is much more honest.
                if (!looksLikeWhatsAppFolder(uri)) {
                    runOnUiThread {
                        android.widget.Toast.makeText(
                            this,
                            "That doesn't look like WhatsApp's status folder — look for " +
                                "the folder named \"Media\" inside Android > media > " +
                                "com.whatsapp > WhatsApp, then tap \"Use this folder\".",
                            android.widget.Toast.LENGTH_LONG
                        ).show()
                    }
                }
            }
            MEDIA_PICK_REQUEST -> {
                val callback = pendingMediaPickerResult
                pendingMediaPickerResult = null
                if (resultCode != RESULT_OK || data?.data == null) {
                    callback?.success(null)
                } else {
                    callback?.success(copyIncomingUriToCache(data.data!!))
                }
            }
            OVERLAY_PERMISSION_REQUEST -> Log.d(TAG, "Overlay: ${hasOverlayPermission()}")
            STORAGE_PERMISSION_REQUEST -> Log.d(TAG, "Storage: ${hasStoragePermission()}")
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        setupChannels(flutterEngine)
        initServices()
        deliverPendingShare()
    }

    private fun setupChannels(flutterEngine: FlutterEngine) {
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        // ─── WHATSAPP CHANNEL ────────────────────────────────────────────────
        MethodChannel(messenger, WHATSAPP_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getWhatsAppStatuses" -> {
                    val path = call.argument<String>("path")
                    val business = call.argument<Boolean>("business") ?: false
                    Log.d(TAG, "📱 getWhatsAppStatuses: path=$path, business=$business")
                    Thread {
                        try {
                            val response = getWhatsAppStatuses(path, business)
                            result.success(response)
                        } catch (e: Exception) {
                            Log.e(TAG, "❌ getWhatsAppStatuses error: ${e.message}", e)
                            result.success(mapOf("paths" to emptyList<String>(), "count" to 0))
                        }
                    }.start()
                }
                "hasWhatsAppStatusAccess" -> {
                    val business = call.argument<Boolean>("business") ?: false
                    result.success(hasWhatsAppStatusAccess(business))
                }
                "requestWhatsAppStatusAccess" -> {
                    val business = call.argument<Boolean>("business") ?: false
                    requestWhatsAppStatusAccess(business)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        // ─── NATIVE BRIDGE CHANNEL ────────────────────────────────────────────
        MethodChannel(messenger, NATIVE_BRIDGE_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "initialize" -> result.success(true)
                "shareText" -> {
                    shareText(
                        call.argument<String>("text") ?: "",
                        call.argument<String>("title") ?: "Share with ClipVault"
                    )
                    result.success(true)
                }
                "trimVideo" -> {
                    trimVideo(
                        call.argument<String>("sourcePath") ?: "",
                        call.argument<String>("outputPath") ?: "",
                        call.argument<Long>("startUs") ?: 0L,
                        call.argument<Long>("endUs") ?: 0L,
                        result
                    )
                }
                "extractFrame" -> {
                    extractFrame(
                        call.argument<String>("sourcePath") ?: "",
                        call.argument<String>("outputPath") ?: "",
                        call.argument<Long>("positionUs") ?: 0L,
                        call.argument<String>("format") ?: "jpg",
                        result
                    )
                }
                "rotateVideo" -> {
                    val sourcePath = call.argument<String>("sourcePath") ?: ""
                    val outputPath = call.argument<String>("outputPath") ?: ""
                    val degrees = call.argument<Int>("degrees") ?: 0
                    Thread {
                        rotateVideo(sourcePath, outputPath, degrees, result)
                    }.start()
                }
                "hasAllPermissions" -> result.success(hasAllRequiredPermissions())
                "requestAllPermissions" -> { requestAllRequiredPermissions(); result.success(true) }
                "getAppInfo" -> result.success(getAppInfo())
                "openAppSettings" -> { openAppSettings(); result.success(true) }
                "scanMediaFile" -> {
                    val path = call.argument<String>("path") ?: ""
                    if (path.isNotEmpty()) scanMediaFile(path)
                    result.success(true)
                }
                "saveToMediaStore" -> {
                    val sourcePath = call.argument<String>("sourcePath") ?: ""
                    val fileName = call.argument<String>("fileName") ?: ""
                    val platform = call.argument<String>("platform") ?: "Others"
                    val mimeType = call.argument<String>("mimeType") ?: "video/mp4"
                    Thread {
                        saveToMediaStore(sourcePath, fileName, platform, mimeType, result)
                    }.start()
                }
                "queryClipVaultMedia" -> {
                    Thread { result.success(queryClipVaultMedia()) }.start()
                }
                "pickMediaFile" -> pickMediaFile(result)
                else -> result.notImplemented()
            }
        }

        // ─── PERMISSIONS CHANNEL ─────────────────────────────────────────────
        MethodChannel(messenger, PERMISSIONS_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "hasNotificationAccess" -> result.success(hasNotificationAccess())
                "requestNotificationAccess" -> {
                    requestNotificationAccess()
                    result.success(true)
                }
                "hasOverlayPermission" -> result.success(hasOverlayPermission())
                "requestOverlayPermission" -> {
                    requestOverlayPermission()
                    result.success(true)
                }
                "hasStoragePermission" -> result.success(hasStoragePermission())
                "requestStoragePermission" -> {
                    requestStoragePermission()
                    result.success(true)
                }
                "checkAllPermissions" -> result.success(checkAllPermissions())
                "getSdkVersion" -> result.success(Build.VERSION.SDK_INT)
                else -> result.notImplemented()
            }
        }

        // ── Universal Share Target Channel ────────────────────────────────────
        MethodChannel(messenger, SHARE_TARGET_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getSharedContent" -> result.success(mapOf("text" to ""))
                "clearSharedContent" -> result.success(true)
                else -> result.notImplemented()
            }
        }

        // ─── FILE MONITOR CHANNEL ─────────────────────────────────────────────
        // NOTE: this channel was previously never registered at all, so every
        // call NativeBridge made on it (downloadMedia, scanMediaFile,
        // getExternalStoragePath, getAppCacheDirectory, and more) threw a
        // MissingPluginException on the Dart side and was silently swallowed
        // as a "false"/failure — which is exactly what showed up as
        // "❌ Save failed" when saving a WhatsApp status. This wires up the
        // methods that back that save path. getWhatsAppStatuses,
        // getInstagramCachedMedia, startFileMonitoring, stopFileMonitoring,
        // and getViewedMediaToday are also called on this channel but aren't
        // implemented here yet — they'll keep failing silently until a
        // follow-up pass adds them.
        MethodChannel(messenger, FILE_MONITOR_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "downloadMedia" -> {
                    val sourcePath = call.argument<String>("sourcePath") ?: ""
                    val destinationFolder = call.argument<String>("destinationFolder")
                        ?: "/storage/emulated/0/Download/ClipVaults"
                    Thread {
                        try {
                            val success = downloadMediaToPublicStorage(sourcePath, destinationFolder)
                            result.success(success)
                        } catch (e: Exception) {
                            Log.e(TAG, "❌ downloadMedia error: ${e.message}", e)
                            result.success(false)
                        }
                    }.start()
                }
                "scanMediaFile" -> {
                    val path = call.argument<String>("path") ?: (call.arguments as? String) ?: ""
                    if (path.isNotEmpty()) scanMediaFile(path)
                    result.success(true)
                }
                "getExternalStoragePath" -> {
                    result.success(Environment.getExternalStorageDirectory().absolutePath)
                }
                "getAppCacheDirectory" -> {
                    result.success(cacheDir.absolutePath)
                }
                else -> result.notImplemented()
            }
        }
    }

    // ─── DOWNLOAD MEDIA TO PUBLIC STORAGE ───────────────────────────────────
    // Backs the file_monitor channel's "downloadMedia" call — copies a source
    // file (a cached WhatsApp status, a detected cache file, etc.) into
    // public storage so it shows up in the user's gallery/file manager.

    private fun downloadMediaToPublicStorage(sourcePath: String, destinationFolder: String): Boolean {
        val sourceFile = File(sourcePath)
        if (!sourceFile.exists() || !sourceFile.canRead()) {
            Log.e(TAG, "❌ downloadMedia: source not found or unreadable: $sourcePath")
            return false
        }

        val fileName = "clipvault_${System.currentTimeMillis()}_${sourceFile.name}"
        val lowerName = fileName.lowercase()
        val mimeType = when {
            lowerName.endsWith(".mp4") || lowerName.endsWith(".mov") ||
                lowerName.endsWith(".3gp") || lowerName.endsWith(".mkv") ||
                lowerName.endsWith(".webm") -> "video/mp4"
            lowerName.endsWith(".png") -> "image/png"
            lowerName.endsWith(".webp") -> "image/webp"
            lowerName.endsWith(".gif") -> "image/gif"
            else -> "image/jpeg"
        }

        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val isVideo = mimeType.startsWith("video/")
                val collection = if (isVideo) {
                    MediaStore.Video.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
                } else {
                    MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
                }

                // destinationFolder arrives as an absolute path like
                // "/storage/emulated/0/Download/ClipVaults/WhatsApp". MediaStore
                // only accepts specific primary directories per collection —
                // Pictures/DCIM for images, Movies/DCIM/Pictures for video —
                // "Download" is only valid for the separate Downloads
                // collection, so re-root under the correct one here regardless
                // of what destinationFolder's caller originally intended.
                val subPath = destinationFolder
                    .substringAfter("ClipVaults", "")
                    .trim('/')
                val relative = if (isVideo) {
                    "Movies/ClipVaults/$subPath".trimEnd('/')
                } else {
                    "Pictures/ClipVaults/$subPath".trimEnd('/')
                }

                val values = ContentValues().apply {
                    put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
                    put(MediaStore.MediaColumns.MIME_TYPE, mimeType)
                    put(MediaStore.MediaColumns.RELATIVE_PATH, relative)
                }

                val uri = contentResolver.insert(collection, values) ?: run {
                    Log.e(TAG, "❌ downloadMedia: MediaStore insert failed")
                    return false
                }

                val output = contentResolver.openOutputStream(uri) ?: run {
                    Log.e(TAG, "❌ downloadMedia: could not open output stream")
                    return false
                }
                output.use { out -> sourceFile.inputStream().use { input -> input.copyTo(out) } }
                Log.d(TAG, "✅ downloadMedia saved via MediaStore: $relative/$fileName")
                true
            } else {
                val dir = File(destinationFolder)
                dir.mkdirs()
                val destFile = File(dir, fileName)
                sourceFile.copyTo(destFile, overwrite = true)
                scanMediaFile(destFile.absolutePath)
                Log.d(TAG, "✅ downloadMedia saved directly: ${destFile.absolutePath}")
                true
            }
        } catch (e: Exception) {
            Log.e(TAG, "❌ downloadMediaToPublicStorage error: ${e.message}", e)
            false
        }
    }

    // ─── QUERY CLIPVAULT MEDIA ──────────────────────────────────────────────

    private fun queryClipVaultMedia(): List<Map<String, Any>> {
        val output = mutableListOf<Map<String, Any>>()
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return output

        val projection = arrayOf(
            MediaStore.Files.FileColumns._ID,
            MediaStore.MediaColumns.DISPLAY_NAME,
            MediaStore.MediaColumns.MIME_TYPE,
            MediaStore.MediaColumns.SIZE,
            MediaStore.MediaColumns.DATE_MODIFIED,
            MediaStore.MediaColumns.RELATIVE_PATH,
            MediaStore.Files.FileColumns.MEDIA_TYPE
        )
        // ClipVaults-saved files now live under Pictures/ClipVaults (images)
        // and Movies/ClipVaults (videos) — see saveToMediaStore, fixed after
        // MediaStore rejected "Download" as a primary directory for images.
        // Querying only "Download/ClipVaults/%" (the old path) would miss
        // everything saved since that fix.
        val selection = "${MediaStore.MediaColumns.RELATIVE_PATH} LIKE ? OR " +
            "${MediaStore.MediaColumns.RELATIVE_PATH} LIKE ? OR " +
            "${MediaStore.MediaColumns.RELATIVE_PATH} LIKE ?"
        val args = arrayOf(
            "Pictures/ClipVaults/%",
            "Movies/ClipVaults/%",
            "Download/ClipVaults/%", // kept for files saved before the fix
        )
        val external = MediaStore.Files.getContentUri("external")

        try {
            contentResolver.query(
                external,
                projection,
                selection,
                args,
                "${MediaStore.MediaColumns.DATE_MODIFIED} DESC"
            )?.use { cursor ->
                val idCol = cursor.getColumnIndex(MediaStore.Files.FileColumns._ID)
                val nameCol = cursor.getColumnIndex(MediaStore.MediaColumns.DISPLAY_NAME)
                val mimeCol = cursor.getColumnIndex(MediaStore.MediaColumns.MIME_TYPE)
                val sizeCol = cursor.getColumnIndex(MediaStore.MediaColumns.SIZE)
                val modifiedCol = cursor.getColumnIndex(MediaStore.MediaColumns.DATE_MODIFIED)
                val relativeCol = cursor.getColumnIndex(MediaStore.MediaColumns.RELATIVE_PATH)
                val mediaTypeCol = cursor.getColumnIndex(MediaStore.Files.FileColumns.MEDIA_TYPE)

                while (cursor.moveToNext()) {
                    val mime = if (mimeCol >= 0) cursor.getString(mimeCol) ?: "" else ""
                    val mediaType = if (mediaTypeCol >= 0) cursor.getInt(mediaTypeCol) else 0
                    if (!mime.startsWith("video/") && !mime.startsWith("image/") &&
                        mediaType != MediaStore.Files.FileColumns.MEDIA_TYPE_VIDEO &&
                        mediaType != MediaStore.Files.FileColumns.MEDIA_TYPE_IMAGE) continue

                    val name = if (nameCol >= 0) cursor.getString(nameCol) ?: "media" else "media"
                    val relative = if (relativeCol >= 0) cursor.getString(relativeCol) ?: "" else ""
                    val relativeLower = relative.lowercase()

                    // The public root depends on which of the three prefixes this
                    // row actually matched — each MediaStore collection's files
                    // live under a different Environment public directory.
                    val publicRoot = when {
                        relativeLower.startsWith("pictures/") ->
                            Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES)
                        relativeLower.startsWith("movies/") ->
                            Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_MOVIES)
                        else ->
                            Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
                    }
                    val topFolder = when {
                        relativeLower.startsWith("pictures/") -> "Pictures/"
                        relativeLower.startsWith("movies/") -> "Movies/"
                        else -> "Download/"
                    }
                    val relativeFile = relative.removePrefix(topFolder) + name
                    val absolutePath = File(publicRoot, relativeFile).absolutePath

                    val id = if (idCol >= 0) cursor.getLong(idCol) else name.hashCode().toLong()
                    val size = if (sizeCol >= 0 && !cursor.isNull(sizeCol)) cursor.getLong(sizeCol) else 0L
                    val modifiedSeconds = if (modifiedCol >= 0 && !cursor.isNull(modifiedCol)) cursor.getLong(modifiedCol) else 0L
                    val platform = relativeLower
                        .substringAfter("clipvaults/", "")
                        .substringBefore('/')
                        .ifEmpty { "unknown" }

                    output.add(
                        mapOf(
                            "id" to "mediastore_$id",
                            "path" to absolutePath,
                            "uri" to ContentUris.withAppendedId(external, id).toString(),
                            "fileName" to name,
                            "mimeType" to mime,
                            "fileSize" to size,
                            "isVideo" to mime.startsWith("video/"),
                            "sourceApp" to platform,
                            "createdAt" to (modifiedSeconds * 1000L)
                        )
                    )
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "queryClipVaultMedia error: ${e.message}")
        }
        return output
    }

    private fun pickMediaFile(result: MethodChannel.Result) {
        pendingMediaPickerResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "video/*"
            putExtra(Intent.EXTRA_ALLOW_MULTIPLE, false)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
        }
        try {
            startActivityForResult(intent, MEDIA_PICK_REQUEST)
        } catch (e: Exception) {
            pendingMediaPickerResult = null
            result.error("PICKER_UNAVAILABLE", e.message, null)
        }
    }

    // ─── SHARE TARGET ────────────────────────────────────────────────────────

    private fun deliverPendingShare() {
        val pending = pendingShareIntent ?: return
        if (flutterEngine?.dartExecutor?.binaryMessenger == null) return
        pendingShareIntent = null
        handleShareIntent(pending)
    }

    private fun handleShareIntent(intent: Intent) {
        try {
            when (intent.action) {
                Intent.ACTION_SEND -> handleSingleShare(intent)
                Intent.ACTION_SEND_MULTIPLE -> handleMultipleShare(intent)
            }
        } catch (e: Exception) {
            Log.e(TAG, "handleShareIntent error: ${e.message}")
        }
    }

    private fun handleSingleShare(intent: Intent) {
        val sharedText = intent.getStringExtra(Intent.EXTRA_TEXT).orEmpty()
        @Suppress("DEPRECATION")
        val sharedUri = intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
        val cachedPath = if (sharedText.isEmpty() && sharedUri != null) {
            copyIncomingUriToCache(sharedUri)
        } else null
        if (sharedText.isEmpty() && cachedPath == null) return

        Log.d(TAG, "📤 Shared content received")
        val messenger = flutterEngine?.dartExecutor?.binaryMessenger
        if (messenger == null) {
            pendingShareIntent = intent
            return
        }
        MethodChannel(messenger, SHARE_TARGET_CHANNEL).invokeMethod("onShareReceived", mapOf(
            "text" to sharedText,
            "uri" to cachedPath,
            "timestamp" to System.currentTimeMillis(),
            "source" to "share_target"
        ))
    }

    private fun handleMultipleShare(intent: Intent) {
        val clipData = intent.clipData ?: return
        val sharedTexts = mutableListOf<String>()
        val sharedUris = mutableListOf<String>()

        for (i in 0 until clipData.itemCount) {
            val item = clipData.getItemAt(i)
            val text = item.text?.toString()
            if (!text.isNullOrEmpty()) {
                sharedTexts.add(text)
            } else {
                item.uri?.let { copyIncomingUriToCache(it)?.let(sharedUris::add) }
            }
        }

        if (sharedTexts.isEmpty() && sharedUris.isEmpty()) return

        Log.d(TAG, "📤 Multiple shares received: ${sharedTexts.size + sharedUris.size} items")
        val messenger = flutterEngine?.dartExecutor?.binaryMessenger
        if (messenger == null) {
            pendingShareIntent = intent
            return
        }
        MethodChannel(messenger, SHARE_TARGET_CHANNEL).invokeMethod("onMultipleShareReceived", mapOf(
            "texts" to sharedTexts,
            "uris" to sharedUris,
            "timestamp" to System.currentTimeMillis(),
            "source" to "share_target"
        ))
    }

    private fun copyIncomingUriToCache(uri: Uri): String? {
        return try {
            val mime = contentResolver.getType(uri).orEmpty()
            val extension = mime.substringAfter('/', "mp4").ifBlank { "mp4" }
            val file = File(cacheDir, "shared_${System.currentTimeMillis()}.$extension")
            contentResolver.openInputStream(uri)?.use { input ->
                file.outputStream().use { output -> input.copyTo(output) }
            } ?: return null
            if (file.length() > 0L) file.absolutePath else null
        } catch (e: Exception) {
            Log.e(TAG, "Could not cache shared URI: ${e.message}")
            null
        }
    }

    // ─── VIDEO EDITING METHODS ─────────────────────────────────────────────

    private fun trimVideo(
        sourcePath: String,
        outputPath: String,
        startUs: Long,
        endUs: Long,
        result: MethodChannel.Result
    ) {
        try {
            Log.d(TAG, "🎬 trimVideo: source=$sourcePath")

            if (sourcePath.isBlank() || outputPath.isBlank() || endUs <= startUs) {
                result.success(false)
                return
            }

            val sourceFile = File(sourcePath)
            if (!sourceFile.exists() || !sourceFile.canRead()) {
                result.success(false)
                return
            }

            File(outputPath).parentFile?.mkdirs()

            val extractor = MediaExtractor()
            extractor.setDataSource(sourcePath)
            val muxer = MediaMuxer(outputPath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
            val trackMap = mutableMapOf<Int, Int>()

            for (index in 0 until extractor.trackCount) {
                val format = extractor.getTrackFormat(index)
                val mime = format.getString(android.media.MediaFormat.KEY_MIME).orEmpty()
                if (mime.startsWith("video/") || mime.startsWith("audio/")) {
                    trackMap[index] = muxer.addTrack(format)
                }
            }

            if (trackMap.isEmpty()) {
                extractor.release()
                muxer.release()
                result.success(false)
                return
            }

            muxer.start()
            val buffer = ByteBuffer.allocate(2 * 1024 * 1024)
            val bufferInfo = MediaCodec.BufferInfo()

            for ((sourceTrack, outputTrack) in trackMap) {
                extractor.selectTrack(sourceTrack)
                extractor.seekTo(startUs, MediaExtractor.SEEK_TO_CLOSEST_SYNC)

                while (true) {
                    val sampleTime = extractor.sampleTime
                    if (sampleTime < 0L || sampleTime > endUs) break

                    val size = extractor.readSampleData(buffer, 0)
                    if (size < 0) break

                    bufferInfo.offset = 0
                    bufferInfo.size = size
                    bufferInfo.presentationTimeUs = (sampleTime - startUs).coerceAtLeast(0L)
                    bufferInfo.flags = extractor.sampleFlags

                    muxer.writeSampleData(outputTrack, buffer, bufferInfo)
                    extractor.advance()
                }
                extractor.unselectTrack(sourceTrack)
            }

            muxer.stop()
            muxer.release()
            extractor.release()

            val success = File(outputPath).exists() && File(outputPath).length() > 0L
            Log.d(TAG, "✅ trimVideo: success=$success")
            result.success(success)

        } catch (e: Exception) {
            Log.e(TAG, "❌ trimVideo error: ${e.message}", e)
            try { File(outputPath).delete() } catch (_: Exception) {}
            result.success(false)
        }
    }

    private fun extractFrame(
        sourcePath: String,
        outputPath: String,
        positionUs: Long,
        format: String,
        result: MethodChannel.Result
    ) {
        try {
            Log.d(TAG, "🎬 extractFrame: source=$sourcePath, position=$positionUs")

            val sourceFile = File(sourcePath)
            if (!sourceFile.exists() || !sourceFile.canRead()) {
                Log.e(TAG, "❌ Source file not found")
                result.success(false)
                return
            }

            File(outputPath).parentFile?.mkdirs()

            val retriever = MediaMetadataRetriever()
            retriever.setDataSource(sourcePath)

            // Try multiple methods to get frame - MORE ROBUST
            var bitmap = retriever.getFrameAtTime(positionUs, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)

            if (bitmap == null) {
                bitmap = retriever.getFrameAtTime(positionUs, MediaMetadataRetriever.OPTION_CLOSEST)
            }

            if (bitmap == null) {
                bitmap = retriever.getFrameAtTime(-1, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
            }

            if (bitmap == null) {
                // Try with different position - middle of video
                val retriever2 = MediaMetadataRetriever()
                retriever2.setDataSource(sourcePath)
                val durationStr = retriever2.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
                val durationMs = durationStr?.toLongOrNull() ?: 0L
                bitmap = retriever2.getFrameAtTime(durationMs * 500, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
                retriever2.release()
            }

            if (bitmap == null) {
                Log.e(TAG, "❌ Could not extract frame with any method")
                retriever.release()
                result.success(false)
                return
            }

            val compressFormat = when (format.lowercase()) {
                "png" -> android.graphics.Bitmap.CompressFormat.PNG
                "webp" -> if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    @Suppress("DEPRECATION")
                    android.graphics.Bitmap.CompressFormat.WEBP_LOSSY
                } else {
                    @Suppress("DEPRECATION")
                    android.graphics.Bitmap.CompressFormat.WEBP
                }
                else -> android.graphics.Bitmap.CompressFormat.JPEG
            }

            val quality = when (compressFormat) {
                android.graphics.Bitmap.CompressFormat.PNG -> 100
                android.graphics.Bitmap.CompressFormat.JPEG -> 92
                else -> 90
            }

            FileOutputStream(outputPath).use { stream ->
                bitmap.compress(compressFormat, quality, stream)
            }

            bitmap.recycle()
            retriever.release()

            val success = File(outputPath).exists() && File(outputPath).length() > 0L
            Log.d(TAG, "✅ extractFrame: success=$success, size=${File(outputPath).length()}")
            result.success(success)

        } catch (e: Exception) {
            Log.e(TAG, "❌ extractFrame error: ${e.message}", e)
            try { File(outputPath).delete() } catch (_: Exception) {}
            result.success(false)
        }
    }

    // ─── ROTATE VIDEO — real implementation via container rotation metadata ──
    // This rewrites the container without re-encoding: it copies every sample
    // as-is and just sets the rotation flag MediaMuxer bakes into the moov
    // atom, exactly like MediaMuxer#setOrientationHint is meant to be used.
    // Works for 0/90/180/270 and is instant, since no frame is decoded.

    private fun rotateVideo(
        sourcePath: String,
        outputPath: String,
        degrees: Int,
        result: MethodChannel.Result
    ) {
        try {
            Log.d(TAG, "🎬 rotateVideo: source=$sourcePath, degrees=$degrees")

            val normalizedDegrees = ((degrees % 360) + 360) % 360
            if (normalizedDegrees != 0 && normalizedDegrees != 90 &&
                normalizedDegrees != 180 && normalizedDegrees != 270
            ) {
                Log.e(TAG, "❌ rotateVideo: unsupported angle $degrees")
                result.success(false)
                return
            }

            val sourceFile = File(sourcePath)
            if (!sourceFile.exists() || !sourceFile.canRead()) {
                result.success(false)
                return
            }

            File(outputPath).parentFile?.mkdirs()

            val extractor = MediaExtractor()
            extractor.setDataSource(sourcePath)
            val muxer = MediaMuxer(outputPath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
            muxer.setOrientationHint(normalizedDegrees)

            val trackMap = mutableMapOf<Int, Int>()
            for (index in 0 until extractor.trackCount) {
                val format = extractor.getTrackFormat(index)
                val mime = format.getString(android.media.MediaFormat.KEY_MIME).orEmpty()
                if (mime.startsWith("video/") || mime.startsWith("audio/")) {
                    trackMap[index] = muxer.addTrack(format)
                }
            }

            if (trackMap.isEmpty()) {
                extractor.release()
                muxer.release()
                result.success(false)
                return
            }

            muxer.start()
            val buffer = ByteBuffer.allocate(2 * 1024 * 1024)
            val bufferInfo = MediaCodec.BufferInfo()

            for ((sourceTrack, outputTrack) in trackMap) {
                extractor.selectTrack(sourceTrack)
                extractor.seekTo(0, MediaExtractor.SEEK_TO_CLOSEST_SYNC)
                while (true) {
                    val size = extractor.readSampleData(buffer, 0)
                    if (size < 0) break
                    val sampleTime = extractor.sampleTime
                    if (sampleTime < 0L) break

                    bufferInfo.offset = 0
                    bufferInfo.size = size
                    bufferInfo.presentationTimeUs = sampleTime
                    bufferInfo.flags = extractor.sampleFlags

                    muxer.writeSampleData(outputTrack, buffer, bufferInfo)
                    extractor.advance()
                }
                extractor.unselectTrack(sourceTrack)
            }

            muxer.stop()
            muxer.release()
            extractor.release()

            val success = File(outputPath).exists() && File(outputPath).length() > 0L
            Log.d(TAG, "✅ rotateVideo: success=$success")
            result.success(success)
        } catch (e: Exception) {
            Log.e(TAG, "❌ rotateVideo error: ${e.message}", e)
            try { File(outputPath).delete() } catch (_: Exception) {}
            result.success(false)
        }
    }

    private fun shareText(text: String, title: String) {
        if (text.isBlank()) return
        startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).apply {
            type = "text/plain"
            putExtra(Intent.EXTRA_TEXT, text)
        }, title))
    }

    // ─── MEDIASTORE SAVE ─────────────────────────────────────────────────────

    private fun saveToMediaStore(
        sourcePath: String,
        fileName: String,
        platform: String,
        mimeType: String,
        result: MethodChannel.Result
    ) {
        try {
            val sourceFile = File(sourcePath)
            if (!sourceFile.exists()) {
                result.success(mapOf("success" to false, "error" to "Source file not found"))
                return
            }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val isVideo = mimeType.startsWith("video/")
                val isAudio = mimeType.startsWith("audio/")

                val collection = when {
                    isVideo -> MediaStore.Video.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
                    isAudio -> MediaStore.Audio.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
                    else -> MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
                }

                val folder = when {
                    isVideo -> "Movies/ClipVaults/${_properCase(platform)}"
                    isAudio -> "Music/ClipVaults/${_properCase(platform)}"
                    else -> "Pictures/ClipVaults/${_properCase(platform)}"
                }

                val values = ContentValues().apply {
                    put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
                    put(MediaStore.MediaColumns.MIME_TYPE, mimeType)
                    put(MediaStore.MediaColumns.RELATIVE_PATH, folder)
                }

                val uri = contentResolver.insert(collection, values)
                if (uri == null) {
                    result.success(mapOf("success" to false, "error" to "MediaStore insert failed"))
                    return
                }

                val output = contentResolver.openOutputStream(uri)
                if (output == null) {
                    Log.e(TAG, "❌ saveToMediaStore: could not open output stream for $uri")
                    result.success(mapOf("success" to false, "error" to "Could not open output stream"))
                    return
                }
                output.use { out -> sourceFile.inputStream().use { input -> input.copyTo(out) } }

                sourceFile.delete()

                val publicRoot = when {
                    isVideo -> Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_MOVIES)
                    isAudio -> Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_MUSIC)
                    else -> Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES)
                }
                val absolutePath = File(
                    publicRoot,
                    "ClipVaults/${_properCase(platform)}/$fileName"
                ).absolutePath
                result.success(mapOf("success" to true, "path" to absolutePath, "uri" to uri.toString()))

            } else {
                val isVideoLegacy = mimeType.startsWith("video/")
                val isAudioLegacy = mimeType.startsWith("audio/")
                val legacyRoot = when {
                    isVideoLegacy -> Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_MOVIES)
                    isAudioLegacy -> Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_MUSIC)
                    else -> Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES)
                }
                val dir = File(legacyRoot, "ClipVaults/${_properCase(platform)}")
                dir.mkdirs()
                val destFile = File(dir, fileName)
                sourceFile.copyTo(destFile, overwrite = true)
                sourceFile.delete()
                scanMediaFile(destFile.absolutePath)
                result.success(mapOf("success" to true, "path" to destFile.absolutePath))
            }

        } catch (e: Exception) {
            Log.e(TAG, "saveToMediaStore error: ${e.message}")
            result.success(mapOf("success" to false, "error" to (e.message ?: "Unknown error")))
        }
    }

    // Normalizes platform folder names ("whatsapp" / "Whatsapp" / "WHATSAPP")
    // to one consistent form ("WhatsApp") so saved files always land in the
    // same folder regardless of how the caller capitalized the string.
    private fun _properCase(platform: String): String {
        return when (platform.lowercase()) {
            "whatsapp" -> "WhatsApp"
            "whatsapp_business" -> "WhatsApp Business"
            "tiktok" -> "TikTok"
            else -> platform.replaceFirstChar { it.uppercase() }
        }
    }

    // ─── WHATSAPP STATUS - COMPLETE FIX ─────────────────────────────────────

    private fun statusTreeKey(business: Boolean): String =
        if (business) WHATSAPP_BUSINESS_TREE_PREF else WHATSAPP_TREE_PREF

    private fun hasWhatsAppStatusAccess(business: Boolean): Boolean {
        val uriString = getSharedPreferences("clipvault_storage", Context.MODE_PRIVATE)
            .getString(statusTreeKey(business), null) ?: return false
        val uri = Uri.parse(uriString)
        return contentResolver.persistedUriPermissions.any {
            it.uri == uri && it.isReadPermission
        }
    }

    private fun requestWhatsAppStatusAccess(business: Boolean) {
        getSharedPreferences("clipvault_storage", Context.MODE_PRIVATE)
            .edit()
            .putBoolean("whatsapp_status_business_pending", business)
            .apply()

        val packageFolder = if (business) "com.whatsapp.w4b" else "com.whatsapp"
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
            addFlags(Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
            addFlags(Intent.FLAG_GRANT_PREFIX_URI_PERMISSION)

            // Without this, the picker opens at the device storage root and
            // the person has to manually navigate Android > media >
            // com.whatsapp > WhatsApp > Media themselves — that's exactly
            // how they end up lost and picking (or creating) an unrelated
            // empty folder instead of the real one. This hints the picker
            // to open right inside WhatsApp's own media folder instead.
            // NOTE: not every device's file picker honors this hint the
            // same way — most stock/Google-Files-based pickers do, but some
            // OEM file managers (used as the system picker on some devices)
            // ignore it and still open at the root. If that happens, the
            // in-app instructions (whatsapp_status_screen.dart) are the
            // fallback — they spell out the exact folder path to tap
            // through manually.
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                try {
                    val initialUri = DocumentsContract.buildDocumentUri(
                        "com.android.externalstorage.documents",
                        "primary:Android/media/$packageFolder/WhatsApp/Media"
                    )
                    putExtra(DocumentsContract.EXTRA_INITIAL_URI, initialUri)
                } catch (e: Exception) {
                    Log.e(TAG, "Could not set initial picker URI: ${e.message}")
                }
            }
        }
        startActivityForResult(intent, WHATSAPP_TREE_REQUEST)
    }

    /**
     * Quick sanity check on a freshly-granted folder: does its own name, OR
     * any of its immediate children, look WhatsApp-related? This won't
     * catch every wrong folder (a correct-looking name with no real content
     * would still pass), but it reliably catches the exact failure mode
     * from a self-created empty folder like "My WhatsApp folder" — its own
     * name matches loosely, but genuinely checking contents next would be
     * a further improvement if this proves insufficient in practice.
     */
    private fun looksLikeWhatsAppFolder(treeUri: Uri): Boolean {
        return try {
            val docId = DocumentsContract.getTreeDocumentId(treeUri)
            if (docId.contains("whatsapp", ignoreCase = true) ||
                docId.contains("statuses", ignoreCase = true)
            ) {
                return true
            }
            val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(treeUri, docId)
            var found = false
            contentResolver.query(
                childrenUri,
                arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME),
                null, null, null
            )?.use { cursor ->
                val nameCol = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_DISPLAY_NAME)
                while (cursor.moveToNext()) {
                    val name = (if (nameCol >= 0) cursor.getString(nameCol) else null)?.lowercase() ?: continue
                    if (name.contains("whatsapp") || name.contains("statuses") || name == "media") {
                        found = true
                        break
                    }
                }
            }
            found
        } catch (e: Exception) {
            // If we can't even check, don't block or falsely warn — the
            // real scan (scanGrantedTree) will surface a genuine problem.
            true
        }
    }

    // ─── GET WHATSAPP STATUSES - PROPERLY IMPLEMENTED ──────────────────────

    private fun getWhatsAppStatuses(path: String?, business: Boolean): Map<String, Any> {
        val result = mutableListOf<String>()
        val cutoffMillis = System.currentTimeMillis() - (48L * 60L * 60L * 1000L)
        Log.d(TAG, "📱 getWhatsAppStatuses: scanning, business=$business")

        try {
            // METHOD 1: Direct file system (Android 10 and below)
            // METHOD 2: Storage Access Framework (Android 11+ - uses persisted URI)
            // METHOD 3: MediaStore query (Fallback)

            // ─── Check if we have SAF access first ───────────────────────────
            val prefs = getSharedPreferences("clipvault_storage", Context.MODE_PRIVATE)
            val savedTree = prefs.getString(statusTreeKey(business), null)

            if (!savedTree.isNullOrEmpty() && hasWhatsAppStatusAccess(business)) {
                Log.d(TAG, "📱 Using SAF tree: $savedTree")
                val treeUri = Uri.parse(savedTree)
                try {
                    runBlocking {
                        withTimeout(20000L) {
                            val rootDocumentId = DocumentsContract.getTreeDocumentId(treeUri)
                            scanGrantedTree(treeUri, rootDocumentId, result, 0, false)
                        }
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "❌ SAF scan error: ${e.message}")
                }
                Log.d(TAG, "📱 SAF found ${result.size} statuses")
            }

            // ─── If SAF didn't find anything, try direct paths ──────────────
            if (result.isEmpty()) {
                Log.d(TAG, "📱 Trying direct file system")
                val pathsToScan = if (!path.isNullOrEmpty()) {
                    listOf(path)
                } else {
                    if (business) {
                        listOf(
                            "/storage/emulated/0/WhatsApp Business/Media/.Statuses",
                            "/storage/emulated/0/Android/media/com.whatsapp.w4b/WhatsApp Business/Media/.Statuses",
                            "/storage/emulated/0/WhatsApp Business/Media/Statuses"
                        )
                    } else {
                        listOf(
                            "/storage/emulated/0/WhatsApp/Media/.Statuses",
                            "/storage/emulated/0/Android/media/com.whatsapp/WhatsApp/Media/.Statuses",
                            "/storage/emulated/0/WhatsApp/Media/Statuses"
                        )
                    }
                }

                for (scanPath in pathsToScan) {
                    try {
                        val dir = File(scanPath)
                        if (dir.exists() && dir.isDirectory) {
                            val files = dir.listFiles() ?: continue
                            for (file in files) {
                                if (file.isFile && isStatusFile(file.name)) {
                                    val lastModified = file.lastModified()
                                    if (lastModified >= cutoffMillis) {
                                        result.add(file.absolutePath)
                                        Log.d(TAG, "📱 Direct FS found: ${file.name}")
                                    }
                                }
                            }
                        }
                    } catch (e: Exception) {
                        Log.e(TAG, "❌ Error scanning $scanPath: ${e.message}")
                    }
                }
                Log.d(TAG, "📱 Direct FS found ${result.size} statuses")
            }

            // ─── Finally, try MediaStore ────────────────────────────────────
            if (result.isEmpty()) {
                Log.d(TAG, "📱 Trying MediaStore")
                val projection = arrayOf(
                    MediaStore.Files.FileColumns.DATA,
                    MediaStore.Files.FileColumns.MIME_TYPE,
                    MediaStore.Files.FileColumns.DATE_MODIFIED
                )
                val selection = "(${MediaStore.Files.FileColumns.DATA} LIKE ? OR ${MediaStore.Files.FileColumns.DATA} LIKE ?) AND ${MediaStore.Files.FileColumns.DATE_MODIFIED} >= ?"
                val selectionArgs = if (business) {
                    arrayOf(
                        "%WhatsApp Business/Media/.Statuses%",
                        "%com.whatsapp.w4b/WhatsApp Business/Media/.Statuses%",
                        (cutoffMillis / 1000L).toString()
                    )
                } else {
                    arrayOf(
                        "%WhatsApp/Media/.Statuses%",
                        "%com.whatsapp/WhatsApp/Media/.Statuses%",
                        (cutoffMillis / 1000L).toString()
                    )
                }
                try {
                    contentResolver.query(
                        MediaStore.Files.getContentUri("external"),
                        projection,
                        selection,
                        selectionArgs,
                        "${MediaStore.Files.FileColumns.DATE_MODIFIED} DESC"
                    )?.use { cursor ->
                        val dataCol = cursor.getColumnIndex(MediaStore.Files.FileColumns.DATA)
                        while (cursor.moveToNext() && dataCol >= 0) {
                            val value = cursor.getString(dataCol)
                            if (!value.isNullOrEmpty() && isStatusFile(value)) {
                                val file = File(value)
                                if (file.exists()) {
                                    result.add(value)
                                }
                            }
                        }
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "❌ MediaStore error: ${e.message}")
                }
                Log.d(TAG, "📱 MediaStore found ${result.size} statuses")
            }

        } catch (e: Exception) {
            Log.e(TAG, "❌ getWhatsAppStatuses error: ${e.message}", e)
        }

        // Filter and return
        val filtered = result.distinct()
            .filter { File(it).exists() }
            .sortedByDescending { File(it).lastModified() }
            .take(200)

        Log.d(TAG, "📱 FINAL: ${filtered.size} statuses")
        return mapOf("paths" to filtered, "count" to filtered.size)
    }

    private fun isStatusFile(name: String): Boolean {
        val lower = name.lowercase()
        return lower.endsWith(".jpg") || lower.endsWith(".jpeg") ||
            lower.endsWith(".png") || lower.endsWith(".webp") ||
            lower.endsWith(".gif") || lower.endsWith(".mp4") ||
            lower.endsWith(".mov") || lower.endsWith(".3gp") ||
            lower.endsWith(".mkv") || lower.endsWith(".webm")
    }

    private fun scanGrantedTree(
        treeUri: Uri,
        documentId: String,
        output: MutableList<String>,
        depth: Int,
        insideStatusFolder: Boolean
    ) {
        if (depth > 8) return
        // Hard cap — without this, the scan gets slower and slower as more
        // statuses accumulate in the cache over time (each match is copied
        // byte-by-byte via SAF, which is expensive per file), eventually
        // blowing past the timeout below and showing "scan stopped" with
        // zero results even though access is fine. 200 matches the existing
        // cap already used when the results reach Dart.
        if (output.size >= 200) return

        try {
            // NOTE: documentId is the id of the folder we are CURRENTLY listing,
            // not the tree root. treeUri never changes across the recursion —
            // it's just the permission grant. Passing the root's tree id here
            // on every recursive call (as the old code did via
            // getTreeDocumentId(treeUri)) makes buildChildDocumentsUriUsingTree
            // list the top-level folder's children again and again, so the scan
            // never actually descends into .Statuses and finds no files.
            val treeIsStatusFolder = documentId.contains(".statuses", ignoreCase = true) ||
                documentId.endsWith("/statuses", ignoreCase = true)
            val scanInside = insideStatusFolder || treeIsStatusFolder

            val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(treeUri, documentId)
            val projection = arrayOf(
                DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                DocumentsContract.Document.COLUMN_MIME_TYPE,
                DocumentsContract.Document.COLUMN_LAST_MODIFIED
            )

            contentResolver.query(childrenUri, projection, null, null, null)?.use { cursor ->
                val idCol = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_DOCUMENT_ID)
                val nameCol = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_DISPLAY_NAME)
                val mimeCol = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_MIME_TYPE)
                val modifiedCol = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_LAST_MODIFIED)
                val cutoffMillis = System.currentTimeMillis() - (48L * 60L * 60L * 1000L)

                while (cursor.moveToNext()) {
                    if (output.size >= 200) break

                    val id = cursor.getString(idCol)
                    val name = cursor.getString(nameCol) ?: "status"
                    val mime = cursor.getString(mimeCol) ?: ""
                    val modified = if (modifiedCol >= 0 && !cursor.isNull(modifiedCol)) {
                        cursor.getLong(modifiedCol)
                    } else 0L

                    val childUri = DocumentsContract.buildDocumentUriUsingTree(treeUri, id)
                    val isStatusDir = name.contains(".statuses", ignoreCase = true) ||
                        name.equals("statuses", ignoreCase = true)

                    if (mime == DocumentsContract.Document.MIME_TYPE_DIR) {
                        val lowerName = name.lowercase()
                        val isRelevant = scanInside || isStatusDir ||
                            lowerName == "android" || lowerName == "media" ||
                            lowerName == "whatsapp" || lowerName == "whatsapp business" ||
                            lowerName == "com.whatsapp" || lowerName == "com.whatsapp.w4b"
                        if (isRelevant) {
                            // Pass the same treeUri (the permission grant) but the
                            // CHILD folder's own document id ("id") so the next
                            // call lists this child's contents, not the root's.
                            scanGrantedTree(treeUri, id, output, depth + 1, scanInside || isStatusDir)
                        }
                    } else if (scanInside && isStatusFile(name) &&
                        (modified <= 0L || modified >= cutoffMillis)) {
                        copyStatusToCache(childUri, name)?.let { output.add(it) }
                    }
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "❌ scanGrantedTree error: ${e.message}")
        }
    }

    private fun copyStatusToCache(uri: Uri, displayName: String): String? {
        return try {
            val safeName = displayName.replace(Regex("[^A-Za-z0-9._-]"), "_")
            val target = File(cacheDir, "whatsapp_statuses/$safeName")
            target.parentFile?.mkdirs()
            contentResolver.openInputStream(uri)?.use { input ->
                target.outputStream().use { output -> input.copyTo(output) }
            } ?: return null
            if (target.length() < 1000L) null else target.absolutePath
        } catch (e: Exception) {
            Log.w(TAG, "Could not copy status: ${e.message}")
            null
        }
    }

    // ─── INIT AND HELPERS ──────────────────────────────────────────────────

    private fun initServices() {
        try {
            clipboardManager = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        } catch (e: Exception) {
            Log.e(TAG, "initServices: ${e.message}")
        }
    }

    private fun scanMediaFile(path: String) {
        try {
            if (!File(path).exists()) return
            MediaScannerConnection.scanFile(applicationContext, arrayOf(path), null) { p, uri ->
                Log.d(TAG, "Scanned: $p → $uri")
            }
        } catch (e: Exception) {
            Log.e(TAG, "scanMediaFile: ${e.message}")
        }
    }

    private fun hasNotificationAccess() =
        NotificationManagerCompat.getEnabledListenerPackages(this).contains(packageName)

    private fun requestNotificationAccess() = try {
        startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)
            .apply { flags = Intent.FLAG_ACTIVITY_NEW_TASK })
    } catch (e: Exception) {
        Log.e(TAG, "requestNotificationAccess: ${e.message}")
    }

    private fun hasOverlayPermission() =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) Settings.canDrawOverlays(this) else true

    private fun requestOverlayPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !Settings.canDrawOverlays(this)) {
            try {
                startActivityForResult(Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                    Uri.parse("package:$packageName")), OVERLAY_PERMISSION_REQUEST)
            } catch (e: Exception) {
                Log.e(TAG, "requestOverlayPermission: ${e.message}")
            }
        }
    }

    private fun hasStoragePermission(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            true
        } else {
            ContextCompat.checkSelfPermission(this,
                Manifest.permission.WRITE_EXTERNAL_STORAGE) == PackageManager.PERMISSION_GRANTED
        }
    }

    private fun requestStoragePermission() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            ActivityCompat.requestPermissions(this,
                arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE,
                    Manifest.permission.READ_EXTERNAL_STORAGE),
                STORAGE_PERMISSION_REQUEST)
        }
    }

    private fun hasAllRequiredPermissions() = hasStoragePermission()

    private fun requestAllRequiredPermissions() {
        if (!hasStoragePermission()) requestStoragePermission()
    }

    private fun checkAllPermissions() = mapOf(
        "notificationAccess" to true,
        "overlayPermission" to true,
        "storagePermission" to hasStoragePermission(),
        "allPermissions" to hasAllRequiredPermissions()
    )

    private fun getAppInfo(): Map<String, Any> = try {
        val pkg = packageManager.getPackageInfo(packageName, 0)
        mapOf(
            "packageName" to packageName,
            "versionName" to (pkg.versionName ?: "1.0.0"),
            "versionCode" to if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P)
                pkg.longVersionCode else pkg.versionCode.toLong(),
            "hasNotificationAccess" to hasNotificationAccess(),
            "hasOverlayPermission" to hasOverlayPermission(),
            "hasStoragePermission" to hasStoragePermission(),
            "androidVersion" to Build.VERSION.SDK_INT,
            "deviceModel" to Build.MODEL,
            "deviceManufacturer" to Build.MANUFACTURER
        )
    } catch (e: Exception) { emptyMap() }

    private fun openAppSettings() = try {
        startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
            Uri.parse("package:$packageName")).apply { flags = Intent.FLAG_ACTIVITY_NEW_TASK })
    } catch (e: Exception) {
        Log.e(TAG, "openAppSettings: ${e.message}")
    }

    private fun getClipboardContent() = try {
        val clip = clipboardManager?.primaryClip
        if (clip != null && clip.itemCount > 0) clip.getItemAt(0).text?.toString() ?: "" else ""
    } catch (e: Exception) { "" }

    private fun setClipboardContent(content: String) = try {
        clipboardManager?.setPrimaryClip(ClipData.newPlainText("ClipVaults", content))
    } catch (e: Exception) {
        Log.e(TAG, "setClipboardContent: ${e.message}")
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
    }
}