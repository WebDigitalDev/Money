package com.webdigital.money

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterFragmentActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.webdigital.money/app_update",
        ).setMethodCallHandler { call, result ->
            if (call.method != "installApk") {
                result.notImplemented()
                return@setMethodCallHandler
            }

            val path = call.argument<String>("path")
            if (path.isNullOrBlank()) {
                result.error("invalid_path", "O arquivo da atualização não foi informado.", null)
                return@setMethodCallHandler
            }

            try {
                if (
                    Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                    !packageManager.canRequestPackageInstalls()
                ) {
                    startActivity(
                        Intent(
                            Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                            Uri.parse("package:$packageName"),
                        ),
                    )
                    result.success("permission_requested")
                    return@setMethodCallHandler
                }

                val apk = File(path)
                if (!apk.isFile) {
                    result.error("missing_apk", "O APK baixado não foi encontrado.", null)
                    return@setMethodCallHandler
                }
                val contentUri = FileProvider.getUriForFile(
                    this,
                    "$packageName.fileprovider",
                    apk,
                )
                val installer = Intent(Intent.ACTION_VIEW).apply {
                    setDataAndType(contentUri, "application/vnd.android.package-archive")
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                if (installer.resolveActivity(packageManager) == null) {
                    result.error("installer_missing", "O instalador do Android não está disponível.", null)
                    return@setMethodCallHandler
                }
                startActivity(installer)
                result.success("installer_opened")
            } catch (error: Exception) {
                result.error("installer_failed", error.message ?: "Falha ao abrir o instalador.", null)
            }
        }
    }
}
