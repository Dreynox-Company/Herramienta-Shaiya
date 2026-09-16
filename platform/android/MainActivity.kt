package com.dreynox.herramienta_shaiya

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.DocumentsContract
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors

/** Acceso SAF de solo lectura. Nunca solicita MANAGE_EXTERNAL_STORAGE. */
class MainActivity : FlutterActivity() {
    private val workers = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private var pendingPicker: MethodChannel.Result? = null
    private val indexed = ConcurrentHashMap<String, Set<String>>()
    private val extensions = setOf("3dc", "3do", "ani", "mlt", "alt", "itm", "mon", "dds", "png", "jpg", "jpeg", "tga", "bmp", "wav", "mp3", "ogg", "wld", "smod", "dg", "eft")
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "dreynox.shaiya/data").setMethodCallHandler { call, result ->
            when (call.method) {
                "chooseTree" -> {
                    if (pendingPicker != null) { result.error("busy", "Ya hay un selector abierto.", null) }
                    else {
                        pendingPicker = result
                        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE)
                        intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION or Intent.FLAG_GRANT_PREFIX_URI_PERMISSION)
                        try { startActivityForResult(intent, 7201) }
                        catch (e: Exception) { pendingPicker = null; result.error("picker", e.message, null) }
                    }
                }
                "index" -> {
                    val tree = call.argument<String>("tree")
                    if (tree == null) { result.error("input", "Falta la carpeta autorizada.", null) }
                    else async(result) {
                        val uri = Uri.parse(tree)
                        require(uri.scheme == "content" && DocumentsContract.isTreeUri(uri)) { "No es una carpeta SAF." }
                        val entries = LinkedHashMap<String, String>()
                        val queue = java.util.ArrayDeque<Pair<String, String>>()
                        val visited = HashSet<String>()
                        queue.add(Pair(DocumentsContract.getTreeDocumentId(uri), ""))
                        while (queue.isNotEmpty()) {
                            val (parent, prefix) = queue.removeFirst()
                            if (!visited.add(parent)) continue
                            require(visited.size < 25000) { "Demasiadas subcarpetas." }
                            val children = DocumentsContract.buildChildDocumentsUriUsingTree(uri, parent)
                            contentResolver.query(children, arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID, DocumentsContract.Document.COLUMN_DISPLAY_NAME, DocumentsContract.Document.COLUMN_MIME_TYPE), null, null, null)?.use { cursor ->
                                while (cursor.moveToNext()) {
                                    val id = cursor.getString(0) ?: continue
                                    val name = cursor.getString(1) ?: continue
                                    require(name != "." && name != ".." && !name.contains('/') && !name.contains('\\')) { "Nombre de recurso inválido." }
                                    val path = if (prefix.isEmpty()) name else "$prefix/$name"
                                    if (cursor.getString(2) == DocumentsContract.Document.MIME_TYPE_DIR) queue.add(Pair(id, path))
                                    else if (name.substringAfterLast('.', "").lowercase() in extensions) {
                                        require(entries.size < 200000) { "Se superó el límite de recursos." }
                                        entries[path] = DocumentsContract.buildDocumentUriUsingTree(uri, id).toString()
                                    }
                                }
                            } ?: error("El proveedor no permitió listar $prefix.")
                        }
                        indexed.clear()
                        indexed[tree] = entries.values.toHashSet()
                        entries
                    }
                }
                "read" -> {
                    val tree = call.argument<String>("tree") ?: ""
                    val target = call.argument<String>("uri") ?: ""
                    val maximum = (call.argument<Number>("limit")?.toInt() ?: 67108864).coerceIn(1, 67108864)
                    async(result) {
                        require(indexed[tree]?.contains(target) == true) { "El recurso no pertenece a la biblioteca indexada." }
                        val output = ByteArrayOutputStream()
                        contentResolver.openInputStream(Uri.parse(target))?.use { input ->
                            val buffer = ByteArray(65536)
                            var count = input.read(buffer)
                            while (count >= 0) {
                                require(output.size() + count <= maximum) { "El archivo supera el límite de memoria." }
                                output.write(buffer, 0, count)
                                count = input.read(buffer)
                            }
                        } ?: error("El proveedor no permitió leer el archivo.")
                        output.toByteArray()
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
    private fun async(result: MethodChannel.Result, work: () -> Any) {
        workers.execute {
            try { val value = work(); main.post { result.success(value) } }
            catch (e: Exception) { main.post { result.error("data", e.message ?: "Error de lectura.", null) } }
        }
    }
    @Deprecated("Activity result bridge for the platform folder picker")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != 7201) return
        val callback = pendingPicker ?: return
        pendingPicker = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) { callback.success(null); return }
        try {
            contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
            callback.success(uri.toString())
        } catch (e: Exception) { callback.error("permission", "No se pudo conservar el permiso de lectura: ${e.message}", null) }
    }
    override fun onDestroy() { pendingPicker?.success(null); pendingPicker = null; workers.shutdown(); super.onDestroy() }
}
