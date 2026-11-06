package dev.eulernotes.euler_notes

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.DocumentsContract
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.io.FileNotFoundException
import java.io.FileOutputStream
import java.io.OutputStream
import java.io.SyncFailedException
import java.security.MessageDigest
import java.util.concurrent.Executors

/**
 * Canal `dev.eulernotes/backup` (Misión 017): guardar una copia de seguridad
 * donde elija el usuario con el selector del sistema (Storage Access
 * Framework), sin pedir permisos de almacenamiento.
 *
 * - `createDocument(name, mimeType)` → URI elegida o `null` si se cancela.
 * - `copyToDocument(path, uri)` → copia el archivo, lo vuelca al disco y lo
 *   relee para devolver `{bytes, sha256}`.
 * - `deleteDocument(uri)` → borra un documento a medias.
 *
 * No registra nada en los logs.
 */
class MainActivity : FlutterActivity() {
    private val io = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private var pendingCreate: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler(::onBackupCall)
    }

    private fun onBackupCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "createDocument" -> createDocument(call, result)
            "copyToDocument" -> copyToDocument(call, result)
            "deleteDocument" -> deleteDocument(call, result)
            else -> result.notImplemented()
        }
    }

    private fun createDocument(call: MethodCall, result: MethodChannel.Result) {
        if (pendingCreate != null) {
            result.error("busy", "Ya hay un selector abierto", null)
            return
        }
        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = call.argument<String>("mimeType") ?: "application/octet-stream"
            putExtra(Intent.EXTRA_TITLE, call.argument<String>("name"))
        }
        pendingCreate = result
        try {
            @Suppress("DEPRECATION")
            startActivityForResult(intent, CREATE_DOCUMENT)
        } catch (e: Exception) {
            pendingCreate = null
            result.error("no_picker", "No hay selector de archivos", null)
        }
    }

    @Deprecated("API de FlutterActivity")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != CREATE_DOCUMENT) return
        val result = pendingCreate ?: return
        pendingCreate = null
        val uri = data?.data
        result.success(if (resultCode == Activity.RESULT_OK && uri != null) uri.toString() else null)
    }

    private fun copyToDocument(call: MethodCall, result: MethodChannel.Result) {
        val path = call.argument<String>("path")
        val uri = call.argument<String>("uri")?.let(Uri::parse)
        if (path == null || uri == null) {
            result.error("bad_args", "Faltan argumentos", null)
            return
        }
        io.execute {
            try {
                // "wt": escribir desde cero (truncar). Algunos proveedores no
                // aceptan "wt": entonces "w" (el documento recién creado está
                // vacío; si no, la relectura de abajo detecta la diferencia).
                val output = openForWrite(uri)
                output.use { stream ->
                    FileInputStream(File(path)).use { input -> input.copyTo(stream, BUFFER) }
                    stream.flush()
                    // Volcado al disco cuando es un archivo local. Los
                    // proveedores en la nube dan una tubería sin fsync: no es
                    // un error (la relectura comprueba el resultado).
                    if (stream is FileOutputStream) {
                        try {
                            stream.fd.sync()
                        } catch (e: SyncFailedException) {
                        }
                    }
                }
                // Releer lo que quedó guardado de verdad.
                val digest = MessageDigest.getInstance("SHA-256")
                var bytes = 0L
                val input = contentResolver.openInputStream(uri)
                    ?: throw IllegalStateException("no se puede releer")
                input.use { stream ->
                    val buffer = ByteArray(BUFFER)
                    while (true) {
                        val read = stream.read(buffer)
                        if (read < 0) break
                        digest.update(buffer, 0, read)
                        bytes += read
                    }
                }
                val sha = digest.digest().joinToString("") { "%02x".format(it) }
                main.post { result.success(mapOf("bytes" to bytes, "sha256" to sha)) }
            } catch (e: Exception) {
                main.post { result.error("copy_failed", "No se pudo escribir el documento", null) }
            }
        }
    }

    private fun openForWrite(uri: Uri): OutputStream {
        for (mode in arrayOf("wt", "w")) {
            try {
                contentResolver.openOutputStream(uri, mode)?.let { return it }
            } catch (e: FileNotFoundException) {
            } catch (e: IllegalArgumentException) {
            } catch (e: UnsupportedOperationException) {
            }
        }
        throw IllegalStateException("el proveedor no permite escribir")
    }

    private fun deleteDocument(call: MethodCall, result: MethodChannel.Result) {
        val uri = call.argument<String>("uri")?.let(Uri::parse)
        if (uri == null) {
            result.success(false)
            return
        }
        io.execute {
            val deleted = try {
                DocumentsContract.deleteDocument(contentResolver, uri)
            } catch (e: Exception) {
                false
            }
            main.post { result.success(deleted) }
        }
    }

    override fun onDestroy() {
        io.shutdown()
        super.onDestroy()
    }

    private companion object {
        const val CHANNEL = "dev.eulernotes/backup"
        const val CREATE_DOCUMENT = 4017
        const val BUFFER = 64 * 1024
    }
}
