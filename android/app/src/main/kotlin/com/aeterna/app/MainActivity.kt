package com.aeterna.app

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.util.Log
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterFragmentActivity() {
    private val CHANNEL = "com.aeterna.app/share"
    private val TAG = "AETERNA_SHARE"
    private var sharedImagePath: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        Log.d(TAG, "onNewIntent action=${intent.action} type=${intent.type}")
        handleIntent(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "getSharedImage") {
                Log.d(TAG, "getSharedImage -> ${sharedImagePath ?: "null"}")
                result.success(sharedImagePath)
                sharedImagePath = null
            } else {
                result.notImplemented()
            }
        }
    }

    private fun handleIntent(intent: Intent?) {
        if (intent == null) return
        val action = intent.action
        val type = intent.type

        Log.d(TAG, "handleIntent action=$action type=$type")

        val handler: (Uri) -> Unit = { uri ->
            Log.d(TAG, "uri=$uri")
            val ext = extensionForMimeType(type) ?: "jpg"
            sharedImagePath = copyUriToTempFile(uri, ext)
            Log.d(TAG, "copied_path=${sharedImagePath ?: "FALHOU"}")
        }

        if (Intent.ACTION_SEND == action && type != null) {
            val uri = intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
            if (uri != null) {
                val uriCount = if (intent.clipData != null) intent.clipData!!.itemCount else 0
                Log.d(TAG, "uri_count=${if (uriCount > 0) uriCount else 1}")

                if (uriCount > 0) {
                    for (i in 0 until uriCount) {
                        val itemUri = intent.clipData!!.getItemAt(i).uri
                        itemUri?.let { handler(it) }
                    }
                } else {
                    handler(uri)
                }
            }
        } else if (Intent.ACTION_SEND_MULTIPLE == action && type != null) {
            @Suppress("UNCHECKED_CAST")
            val uris = intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)
            Log.d(TAG, "uri_count=${uris?.size ?: 0}")
            uris?.forEach { handler(it) }
        }
    }

    private fun extensionForMimeType(mimeType: String?): String? {
        if (mimeType == null) return null
        return when {
            mimeType.startsWith("video/") -> "mp4"
            mimeType.startsWith("image/png") -> "png"
            mimeType.startsWith("image/gif") -> "gif"
            mimeType.startsWith("image/webp") -> "webp"
            mimeType.startsWith("image/") -> "jpg"
            else -> null
        }
    }

    private fun copyUriToTempFile(uri: Uri, extension: String): String? {
        try {
            val inputStream = contentResolver.openInputStream(uri) ?: run {
                Log.e(TAG, "openInputStream falhou para uri=$uri")
                return null
            }
            val tempFile = File(cacheDir, "shared_android_${System.currentTimeMillis()}.$extension")
            Log.d(TAG, "size=${inputStream.available()}")
            val outputStream = FileOutputStream(tempFile)
            inputStream.use { input ->
                outputStream.use { output ->
                    input.copyTo(output)
                }
            }
            return tempFile.absolutePath
        } catch (e: Exception) {
            Log.e(TAG, "error=${e.message}")
            e.printStackTrace()
            return null
        }
    }
}
