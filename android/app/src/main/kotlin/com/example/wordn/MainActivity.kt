package com.example.wordn

import android.app.DownloadManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.database.Cursor
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val METHOD_CHANNEL = "com.example.wordn/download_manager"
    private val EVENT_CHANNEL = "com.example.wordn/download_progress"
    private val NOTIFICATION_CHANNEL_ID = "wordn_install_channel"
    private val NOTIFICATION_ID = 2002
    private val TAG = "WordNDownloadManager"

    private var currentDownloadId: Long = -1L
    private var progressEventSink: EventChannel.EventSink? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private var progressRunnable: Runnable? = null
    private var isActivityResumed = false

    private val downloadReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action == DownloadManager.ACTION_DOWNLOAD_COMPLETE) {
                val id = intent.getLongExtra(DownloadManager.EXTRA_DOWNLOAD_ID, -1L)
                if (id != -1L && id == currentDownloadId) {
                    Log.d(TAG, "Download complete broadcast received for id=$id, isResumed=$isActivityResumed")
                    handleDownloadComplete(id)
                }
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        createNotificationChannel()

        // Register download broadcast receiver
        val filter = IntentFilter(DownloadManager.ACTION_DOWNLOAD_COMPLETE)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(downloadReceiver, filter, Context.RECEIVER_EXPORTED)
        } else {
            registerReceiver(downloadReceiver, filter)
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startDownload" -> {
                    val url = call.argument<String>("url")
                    val fileName = call.argument<String>("fileName") ?: "WordN_Latest.apk"
                    if (url.isNullOrBlank()) {
                        result.error("INVALID_URL", "Download URL cannot be null or empty", null)
                        return@setMethodCallHandler
                    }
                    try {
                        val downloadId = enqueueDownload(url, fileName)
                        currentDownloadId = downloadId
                        startProgressPolling()
                        result.success(downloadId)
                    } catch (e: Exception) {
                        Log.e(TAG, "Failed to start download", e)
                        result.error("DOWNLOAD_ERROR", e.message, null)
                    }
                }
                "cancelDownload" -> {
                    val id = (call.argument<Number>("downloadId"))?.toLong() ?: currentDownloadId
                    val success = cancelDownload(id)
                    stopProgressPolling()
                    result.success(success)
                }
                "installApk" -> {
                    val id = (call.argument<Number>("downloadId"))?.toLong() ?: currentDownloadId
                    val success = checkAndInstallApk(id)
                    result.success(success)
                }
                "getDownloadProgress" -> {
                    val id = (call.argument<Number>("downloadId"))?.toLong() ?: currentDownloadId
                    val progressMap = queryProgress(id)
                    result.success(progressMap)
                }
                else -> result.notImplemented()
            }
        }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    progressEventSink = events
                    if (currentDownloadId != -1L) {
                        startProgressPolling()
                    }
                }

                override fun onCancel(arguments: Any?) {
                    progressEventSink = null
                    stopProgressPolling()
                }
            }
        )
    }

    override fun onResume() {
        super.onResume()
        isActivityResumed = true
        if (currentDownloadId != -1L) {
            val progressData = queryProgress(currentDownloadId)
            val status = progressData["status"] as? String
            if (status == "successful") {
                checkAndInstallApk(currentDownloadId)
            } else if (status == "downloading" || status == "pending" || status == "paused") {
                startProgressPolling()
            }
        }
    }

    override fun onPause() {
        isActivityResumed = false
        stopProgressPolling()
        super.onPause()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                NOTIFICATION_CHANNEL_ID,
                "WordN 安装提示",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "下载完成时提示安装"
                enableVibration(true)
            }
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.createNotificationChannel(channel)
        }
    }

    private fun enqueueDownload(url: String, fileName: String): Long {
        val downloadManager = getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager

        // Remove old file if exists
        val dir = getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS)
        if (dir != null) {
            val oldFile = File(dir, fileName)
            if (oldFile.exists()) {
                oldFile.delete()
            }
        }

        val request = DownloadManager.Request(Uri.parse(url)).apply {
            setTitle("WordN 考研词汇助手")
            setDescription("正在后台下载新版本安装包...")
            setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED)
            setDestinationInExternalFilesDir(this@MainActivity, Environment.DIRECTORY_DOWNLOADS, fileName)
            setAllowedOverMetered(true)
            setAllowedOverRoaming(true)
        }

        return downloadManager.enqueue(request)
    }

    private fun queryProgress(downloadId: Long): Map<String, Any> {
        if (downloadId == -1L) {
            return mapOf("status" to "idle", "progress" to 0)
        }

        val downloadManager = getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
        val query = DownloadManager.Query().setFilterById(downloadId)
        val cursor: Cursor? = downloadManager.query(query)

        if (cursor != null && cursor.moveToFirst()) {
            val bytesDownloadedIdx = cursor.getColumnIndex(DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR)
            val bytesTotalIdx = cursor.getColumnIndex(DownloadManager.COLUMN_TOTAL_SIZE_BYTES)
            val statusIdx = cursor.getColumnIndex(DownloadManager.COLUMN_STATUS)
            val reasonIdx = cursor.getColumnIndex(DownloadManager.COLUMN_REASON)

            val bytesDownloaded = if (bytesDownloadedIdx != -1) cursor.getLong(bytesDownloadedIdx) else 0L
            val bytesTotal = if (bytesTotalIdx != -1) cursor.getLong(bytesTotalIdx) else 0L
            val status = if (statusIdx != -1) cursor.getInt(statusIdx) else 0
            val reason = if (reasonIdx != -1) cursor.getInt(reasonIdx) else 0

            cursor.close()

            val progress = if (bytesTotal > 0) ((bytesDownloaded * 100) / bytesTotal).toInt() else 0

            val statusStr = when (status) {
                DownloadManager.STATUS_RUNNING -> "downloading"
                DownloadManager.STATUS_SUCCESSFUL -> "successful"
                DownloadManager.STATUS_FAILED -> "failed"
                DownloadManager.STATUS_PAUSED -> "paused"
                DownloadManager.STATUS_PENDING -> "pending"
                else -> "unknown"
            }

            return mapOf(
                "status" to statusStr,
                "progress" to progress,
                "bytesDownloaded" to bytesDownloaded,
                "bytesTotal" to bytesTotal,
                "reason" to reason
            )
        }
        cursor?.close()
        return mapOf("status" to "unknown", "progress" to 0)
    }

    private fun startProgressPolling() {
        stopProgressPolling()
        progressRunnable = object : Runnable {
            override fun run() {
                if (currentDownloadId == -1L) return
                val progressData = queryProgress(currentDownloadId)
                progressEventSink?.success(progressData)

                val status = progressData["status"] as? String
                if (status == "downloading" || status == "pending" || status == "paused") {
                    mainHandler.postDelayed(this, 500)
                } else if (status == "successful") {
                    handleDownloadComplete(currentDownloadId)
                }
            }
        }
        mainHandler.post(progressRunnable!!)
    }

    private fun stopProgressPolling() {
        progressRunnable?.let { mainHandler.removeCallbacks(it) }
        progressRunnable = null
    }

    private fun cancelDownload(downloadId: Long): Boolean {
        if (downloadId == -1L) return false
        val downloadManager = getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
        val count = downloadManager.remove(downloadId)
        if (downloadId == currentDownloadId) {
            currentDownloadId = -1L
        }
        return count > 0
    }

    private fun handleDownloadComplete(downloadId: Long) {
        val apkFile = getDownloadedApkFile(downloadId) ?: return
        if (isActivityResumed) {
            // App is in foreground, directly launch install intent
            installApkFile(apkFile)
        } else {
            // App is in background: Show High-Priority notification with full screen intent
            showInstallNotification(apkFile)
        }
    }

    private fun getDownloadedApkFile(downloadId: Long): File? {
        if (downloadId == -1L) return null
        val downloadManager = getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
        val query = DownloadManager.Query().setFilterById(downloadId)
        val cursor = downloadManager.query(query)

        if (cursor != null && cursor.moveToFirst()) {
            val statusIdx = cursor.getColumnIndex(DownloadManager.COLUMN_STATUS)
            val status = if (statusIdx != -1) cursor.getInt(statusIdx) else 0

            if (status == DownloadManager.STATUS_SUCCESSFUL) {
                val localUriIdx = cursor.getColumnIndex(DownloadManager.COLUMN_LOCAL_URI)
                val localUriStr = if (localUriIdx != -1) cursor.getString(localUriIdx) else null
                cursor.close()

                if (localUriStr != null) {
                    val file = File(Uri.parse(localUriStr).path ?: "")
                    if (file.exists()) {
                        return file
                    }
                }
            } else {
                cursor.close()
            }
        } else {
            cursor?.close()
        }
        return null
    }

    private fun checkAndInstallApk(downloadId: Long): Boolean {
        val apkFile = getDownloadedApkFile(downloadId) ?: return false
        return installApkFile(apkFile)
    }

    private fun installApkFile(file: File): Boolean {
        return try {
            val contentUri = FileProvider.getUriForFile(
                this,
                "${applicationContext.packageName}.fileprovider",
                file
            )

            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(contentUri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
            Log.d(TAG, "Started APK installation intent for: ${file.absolutePath}")
            true
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start install intent", e)
            false
        }
    }

    private fun showInstallNotification(file: File) {
        try {
            val contentUri = FileProvider.getUriForFile(
                this,
                "${applicationContext.packageName}.fileprovider",
                file
            )

            val installIntent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(contentUri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }

            val flag = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            } else {
                PendingIntent.FLAG_UPDATE_CURRENT
            }

            val pendingIntent = PendingIntent.getActivity(this, 0, installIntent, flag)

            val notification = NotificationCompat.Builder(this, NOTIFICATION_CHANNEL_ID)
                .setSmallIcon(R.mipmap.ic_launcher)
                .setContentTitle("WordN 新版本下载完成")
                .setContentText("安装包已下载完毕，点击立即开始安装")
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setDefaults(NotificationCompat.DEFAULT_ALL)
                .setAutoCancel(true)
                .setContentIntent(pendingIntent)
                .setFullScreenIntent(pendingIntent, false)
                .build()

            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.notify(NOTIFICATION_ID, notification)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to show install notification", e)
        }
    }

    override fun onDestroy() {
        try {
            unregisterReceiver(downloadReceiver)
        } catch (e: Exception) {
            Log.w(TAG, "Error unregistering receiver", e)
        }
        stopProgressPolling()
        super.onDestroy()
    }
}
